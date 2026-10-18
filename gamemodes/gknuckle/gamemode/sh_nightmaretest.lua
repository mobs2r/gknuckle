-- Ladder nightmare test (gk_style). Only runs when data/gknuckle/nightmaretest.txt
-- exists: builds a ladder run, checks the nightmare came with it and hangs
-- over the climber, looks up at it, walks into the 1500 m room's settings,
-- falls, gets caught. Saves data/gknuckle/nightmare_*.jpg, logs "[GKNIGHT]",
-- ends with "[GKTEST] DONE".
if not file.Exists("gknuckle/nightmaretest.txt", "DATA") then return end
local function log(...) print("[GKNIGHT]", ...) end
if CLIENT then
    net.Receive("gk_nightmaretest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_NightShot", function()
            hook.Remove("PostRender", "GK_NightShot")
            file.Write("gknuckle/nightmare_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
            log("client: shot", name, "nightmares", #ents.FindByClass("gk_laddernightmare"))
        end)
    end)
    return
end
util.AddNetworkString("gk_nightmaretest")
local function shot(P, name) net.Start("gk_nightmaretest") net.WriteString(name) net.Send(P) end
local M = 39.37

hook.Add("PlayerInitialSpawn", "GK_NightTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_NightTest")
    local e, info
    hook.Add("PlayerDeath", "GK_NightTestDeath", function(v, inf, att)
        log("death:", tostring(v), "by", IsValid(att) and att:GetClass() or tostring(att), "(expect gk_laddernightmare)")
    end)
    timer.Simple(12, function()
        RunConsoleCommand("gk_tube_rise", "0")
        RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
        GK.StageRegion = function() return "Region_Ladder_Endless" end
        local a = GK.StartArena(1, { P }, true)
        info = a.info
        local has = {}
        for _, pc in ipairs(info.pieces or {}) do if GK.NightmareRooms[pc] then has[#has + 1] = pc end end
        log("ladder run", info.region, "rooms", #info.plan, "trigger rooms", table.concat(has, " "))
        P:GodEnable()
    end)
    timer.Simple(16, function()
        e = ents.FindByClass("gk_laddernightmare")[1]
        log("nightmare with the run:", IsValid(e), "(expect true)")
        if not IsValid(e) then print("[GKTEST] DONE") return end
        log("height over the climber:", ("%.1f m"):format((e:GetPos().z - P:GetPos().z) / M), "(expect about 30, or 37.5 while hiding)")
        P:SetEyeAngles(((e:GetPos()) - P:EyePos()):Angle())
    end)
    timer.Simple(17, function() if IsValid(e) then P:SetEyeAngles((e:GetPos() - P:EyePos()):Angle()) shot(P, "above") end end)
    timer.Simple(18, function()
        if not IsValid(e) then return end
        -- The 1500 m room's trigger, then a fall.
        e:Configure(GK.NightmareRooms.m3_habitation_ladderwarp_1500m_01)
        e.HideTime, e.Peeking = 0, true
        P:SetMoveType(MOVETYPE_WALK)
        P:SetPos(P:GetPos() + Vector(0, 0, 40 * M)) -- 40 m up in the air
        P:SetVelocity(Vector(0, 0, -200))
        log("1500 m settings: offset", e.Offset, "attack", tostring(e.CanAttack))
    end)
    timer.Simple(21.5, function()
        if not IsValid(e) then return end
        log("after a long fall: attacking", tostring(IsValid(e.Attacking)), "(expect true)", "fell", ("%.1f m"):format(e:FallOf(P)))
        P:GodDisable()
        P:SetMoveType(MOVETYPE_NONE) -- hold still so it reaches us
        log("it's", ("%.1f m"):format(e:GetPos():Distance(P:WorldSpaceCenter()) / M), "away")
    end)
    timer.Simple(23, function() if IsValid(e) then log("it's", ("%.1f m"):format(e:GetPos():Distance(P:WorldSpaceCenter()) / M), "away, attacking", tostring(e.Attacking)) end end)
    timer.Simple(25, function()
        log("caught: alive", tostring(P:Alive()), "(expect false)")
        print("[GKTEST] DONE")
    end)
    timer.Simple(26, function() game.ConsoleCommand("quit\n") end)
end)
