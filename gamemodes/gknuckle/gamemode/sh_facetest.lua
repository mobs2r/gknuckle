-- The Face test (gk_style). Only runs when data/gknuckle/facetest.txt exists:
-- builds an Abyss run, checks the Face came with it, makes it hunt, looks at
-- it, hurts it back to stalking, lets it bite. Saves data/gknuckle/face_*.jpg,
-- logs "[GKFACE]", ends with "[GKTEST] DONE".
local dusk = file.Exists("gknuckle/facedusk.txt", "DATA") -- the Dusk stage variant (staged build overlaid)
if not file.Exists("gknuckle/facetest.txt", "DATA") and not dusk then return end
local function log(...) print("[GKFACE]", ...) end
if CLIENT then
    net.Receive("gk_facetest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_FaceShot", function()
            hook.Remove("PostRender", "GK_FaceShot")
            file.Write("gknuckle/face_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
            local f = ents.FindByClass("gk_face")[1]
            log("client: shot", name, "face", IsValid(f), "path points", f and f.Path and #f.Path or 0)
        end)
    end)
    return
end
util.AddNetworkString("gk_facetest")
local function shot(P, name) net.Start("gk_facetest") net.WriteString(name) net.Send(P) end
local M = 39.37

hook.Add("PlayerInitialSpawn", "GK_FaceTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_FaceTest")
    local onStyle = game.GetMap() == "gk_style"
    local f
    if onStyle then
        -- Part 1 (gk_style): an Abyss run brings the Face.
        timer.Simple(12, function()
            RunConsoleCommand("gk_tube_rise", "0")
            RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
            local region = "Region_Abyss_Campaign"
            if dusk then
                -- The single-room Dusk stage (Region_Dusk, live since 0.5).
                region = "Region_Dusk"
            end
            GK.StageRegion = function() return region end
            local a = GK.StartArena(1, { P }, true)
            log("run", a.info.region, "rooms", #a.info.plan, table.concat(a.info.pieces or {}, " "))
            P:GodEnable()
        end)
        timer.Simple(16, function()
            f = ents.FindByClass("gk_face")[1]
            log("face with the run:", IsValid(f), "(expect true)", IsValid(f) and ("%.0f m under the run's start"):format((f.FloorZ - f:GetPos().z) / M) or "")
            if not (dusk and IsValid(f)) then print("[GKTEST] DONE") return end
            -- On the Dusk stage: let it hunt the climber standing at the start.
            P:SetMoveType(MOVETYPE_WALK)
            f.Aggression = 3
            f:SetState(GK.FaceStates.HUNT)
            f.D0 = f:GetPos():Distance(P:WorldSpaceCenter())
        end)
        timer.Simple(22, function()
            if dusk and IsValid(f) then
                log("Dusk: hunted from", ("%.1f m"):format(f.D0 / M), "to", ("%.1f m"):format(f:GetPos():Distance(P:WorldSpaceCenter()) / M), "in 6 s (expect closer)")
                P:SetEyeAngles((f:GetPos() - P:EyePos()):Angle())
                shot(P, "dusk")
            end
        end)
        timer.Simple(24, function() print("[GKTEST] DONE") end)
        timer.Simple(25, function() game.ConsoleCommand("quit\n") end)
        return
    end
    -- Part 2 (gm_construct): hunting, the look of it, driven back, the bite.
    timer.Simple(10, function()
        P:GodEnable()
        P:SetMoveType(MOVETYPE_WALK)
        P:SetPos(Vector(0, 0, 1500))
        P:Freeze(true)
        f = GK.SpawnFace(P:GetPos() + Vector(60 * M, 0, 60 * M), { below = 0 })
        f.Aggression = 3 -- quick, for the test
        f:SetState(GK.FaceStates.HUNT)
        f.D0 = f:GetPos():Distance(P:WorldSpaceCenter())
        log("hunting from", ("%.1f m"):format(f.D0 / M))
    end)
    timer.Simple(14, function()
        local d = f:GetPos():Distance(P:WorldSpaceCenter())
        log("after 4 s of hunting:", ("%.1f m"):format(d / M), "(expect closer than", ("%.1f m)"):format(f.D0 / M), "state", f:GetFState(), "path", #f.Path)
        -- Look at it from the side, out of reach.
        f.Aggression = 0.001
        f.Vel = Vector(0, 0, 0)
        P:Freeze(false)
        P:SetMoveType(MOVETYPE_NOCLIP)
        local mid = f.Path[math.min(#f.Path, 120)]
        local side = (f:GetPos() - mid):Cross(Vector(0, 0, 1)):GetNormalized() * 1400 + Vector(0, 0, 300)
        P:SetPos((f:GetPos() + mid) / 2 + side)
        P:SetEyeAngles(((f:GetPos() + mid) / 2 - P:EyePos()):Angle())
    end)
    timer.Simple(15.5, function() shot(P, "side") end)
    timer.Simple(16, function()
        P:SetPos(f:GetPos() + f:GetForward() * 260)
        P:SetEyeAngles((f:GetPos() - P:EyePos()):Angle())
    end)
    timer.Simple(17, function() shot(P, "head") end)
    timer.Simple(18, function()
        f.Aggression = 1
        f:SetState(GK.FaceStates.HUNT)
        for i = 1, 3 do
            local d = DamageInfo() d:SetDamage(80) d:SetAttacker(P) d:SetInflictor(P) d:SetDamageType(DMG_CLUB)
            f:TakeDamageInfo(d)
            log("hit", i, "for 8 WK: hurt", ("%.2f"):format(f:GetHurt()), "state", f:GetFState())
        end
        log("after 3 heavy hits: state", f:GetFState(), "(expect 1 = stalk, driven back)")
    end)
    timer.Simple(19, function()
        -- The bite: put it right on us, without god mode.
        P:GodDisable()
        P:Freeze(false)
        P:SetMoveType(MOVETYPE_WALK)
        local g = util.TraceLine({ start = Vector(0, 0, 1500), endpos = Vector(0, 0, -2000), mask = MASK_PLAYERSOLID_BRUSHONLY })
        P:SetPos(g.HitPos + Vector(0, 0, 2)) -- standing on the ground, so we stay put
        f.DamageAt = 0
        timer.Simple(0.3, function() f:SetPos(P:WorldSpaceCenter() + Vector(0, 0, 4)) log("bite set: dist", ("%.0f"):format(f:GetPos():Distance(P:WorldSpaceCenter())), "on ground", P:OnGround()) end)
    end)
    timer.Simple(19.5, function()
        log("bite check: dist", ("%.0f"):format(f:GetPos():Distance(P:WorldSpaceCenter())), "damageAt-now", ("%.2f"):format(f.DamageAt - CurTime()), "target", tostring(f.Target), "movetype", P:GetMoveType(), "lastthink", ("%.2f"):format(CurTime() - (f.LastThink or 0)))
    end)
    timer.Simple(20, function()
        log("bitten: alive", tostring(P:Alive()), "(expect false)")
        print("[GKTEST] DONE")
    end)
    timer.Simple(21, function() game.ConsoleCommand("quit\n") end)
end)
