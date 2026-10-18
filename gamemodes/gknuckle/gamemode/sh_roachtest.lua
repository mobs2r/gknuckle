-- Automated test for autohop, finite grip and roaches. Only runs when
-- data/gknuckle/roachtest.txt exists. Logs "[GKROACH]" lines.

if not file.Exists("gknuckle/roachtest.txt", "DATA") then return end

local function log(...) print("[GKROACH]", ...) end

if CLIENT then
    local held, untilT = 0, 0
    net.Receive("gk_roachtest", function() held = net.ReadUInt(32) untilT = CurTime() + net.ReadFloat() end)
    hook.Add("CreateMove", "GK_RoachTestInput", function(cmd)
        if CurTime() < untilT then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) end
    end)
    return
end

util.AddNetworkString("gk_roachtest")
local function press(ply, b, d) net.Start("gk_roachtest") net.WriteUInt(b, 32) net.WriteFloat(d) net.Send(ply) end
local function shot(ply) ply:SendLua("RunConsoleCommand('jpeg')") end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, jumps, lastGround = nil, 0, true
local W -- a wall found for the grip test, reused by the piton test

hook.Add("Think", "GK_RoachTestJumps", function()
    if not IsValid(P) then return end
    local g = P:OnGround()
    if lastGround and not g and P:GetVelocity().z > 100 then jumps = jumps + 1 end
    lastGround = g
end)

local function sta() return ("%.0f"):format(GK.Stamina(P)) end

step(0, function()
    P = player.GetHumans()[1]
    for _, e in ipairs(ents.FindByClass("gk_item")) do if e.GK_Starter then e:Remove() end end
    GK.SetStamina(P, 100)
end)

-- 1. Autohop: hold jump for 3s.
step(1, function()
    jumps = 0 log("autohop start stamina", sta(), "jump power", P:GetJumpPower(), "gravity", GetConVar("sv_gravity"):GetFloat())
    press(P, IN_JUMP, 3)
    for i = 1, 6 do
        timer.Simple(i * 0.4, function()
            log(("  hop t=%.1f ground %s vz %.0f speed %.0f crouch %s duck %.2f slow %.2f movetype %d"):format(i * 0.4, tostring(P:OnGround()),
                P:GetVelocity().z, P:GetVelocity():Length2D(), tostring(P:Crouching()), P:GetDuckSpeed(), GK.JumpSlow(P), P:GetMoveType()))
        end)
    end
end)
step(3.2, function() log("autohop 3s: jumps", jumps, "stamina", sta()) end)
-- 2. No stamina, no jump.
step(1, function() GK.SetStamina(P, 3) end)
step(0.5, function() jumps = 0 log("before low-stamina hop: ground", tostring(P:OnGround()), "vz", ("%.0f"):format(P:GetVelocity().z)) press(P, IN_JUMP, 1.5) end)
step(1.6, function() log("at 3 stamina: jumps", jumps) GK.SetStamina(P, 100) end)

-- 3. Grip a wall with one hand, in the air, for 3 s.
step(0.5, function()
    -- A frozen plate as a wall (frozen props climb like walls), well off the ground.
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    local wall = ents.Create("prop_physics")
    wall:SetModel("models/hunter/plates/plate4x4.mdl")
    wall:SetPos(P:GetPos() + fwd * 90 + Vector(0, 0, 200))
    wall:SetAngles(fwd:Angle() + Angle(90, 0, 0))
    wall:Spawn()
    wall:GetPhysicsObject():EnableMotion(false)
    W = { hit = wall:GetPos() - fwd * 2, n = -fwd }
    -- High enough that the feet hang clear (feet on the ground refill grip).
    P:SetPos(W.hit + W.n * 50 + Vector(0, 0, 40 - 64))
    P:SetEyeAngles(fwd:Angle())
    P:SelectWeapon("gk_mind")
    GK.SetStamina(P, 100)
    press(P, IN_ATTACK, 3)
end)
step(0.5, function() end)
step(1, function() log("grip 1s: stamina", sta(), "handL", P:GetNW2Int("gk_hand_l"), "ground", tostring(P:OnGround())) end)
step(2.2, function() log("grip 3s: stamina", sta(), "handL", P:GetNW2Int("gk_hand_l")) end)
-- Hold on until it runs out.
step(0.1, function() press(P, IN_ATTACK, 12) end)
step(5, function() log("grip 8s: stamina", sta(), "hand colour", tostring(GK.HandColor(P, "l"))) end)
step(5, function() log("grip held 10 more s: stamina", sta(), "still gripping", P:GetNW2Int("gk_hand_l")) end)
step(2.5, function() log("after let go 1s: stamina", sta()) end)

-- 4. Roaches.
step(0.5, function()
    log("roaches alive near spawn", #ents.FindByClass("gk_roach"))
    P:SetNW2Int("gk_roaches", 0)
    local inv = GK.Inv.Get(P) inv.bag, inv.slots = {}, {} GK.Inv.Sync(P)
    for _, k in ipairs({ "gold", "platinum", "xenium" }) do
        local r = GK.SpawnRoach(k, P:GetPos() + P:GetForward() * 60)
        r:Press(P)
    end
    log("caught gold+platinum+xenium: count", GK.Roaches.Count(P), "lumps", GK.Roaches.Lumps(P), "balance", GK.Roaches.Balance(P))
    log("spend 10:", tostring(GK.Roaches.Spend(P, 10)), "count", GK.Roaches.Count(P), "lumps", GK.Roaches.Lumps(P))
    log("spend 100:", tostring(GK.Roaches.Spend(P, 100)), "count", GK.Roaches.Count(P))
end)
step(0.5, function()
    -- A wandering roach runs from you.
    local r = GK.SpawnRoach("gold", P:GetPos() + P:GetForward() * 80)
    timer.Simple(1.5, function() if IsValid(r) then log("roach fled", ("%.0f"):format(r:GetPos():Distance(P:GetPos()))) end end)
    local s = GK.SpawnRoach("xenium", P:GetPos() + P:GetForward() * 50 + P:GetRight() * 30)
    local b = GK.SpawnRoach("boom", P:GetPos() + P:GetForward() * 50 - P:GetRight() * 30)
    P:SetEyeAngles((s:GetPos() - P:EyePos()):Angle())
end)
step(0.6, function() shot(P) end)
step(1, function()
    local b = ents.FindByClass("gk_roach")
    for _, r in ipairs(b) do if r:GetKind() == "boom" then P:SetHealth(100) r:Press(P) break end end
end)
step(1.5, function() log("boom bug in hand: hp", P:Health()) end)
step(0.5, function()
    P:SetHealth(100)
    P:SetNW2Int("gk_roaches", 12)
    local before = #ents.FindByClass("gk_roach")
    P:Kill()
    timer.Simple(0.2, function() log("died with 12: dropped", #ents.FindByClass("gk_roach") - before, "count now", GK.Roaches.Count(P)) P:Spawn() end)
end)
-- Paying a vending machine in roaches; and the armless placeholder model.
step(1.5, function()
    local arm = P:LookupBone("ValveBiped.Bip01_L_UpperArm")
    log("player model", P:GetModel(), "arm bone", tostring(arm), "arm scale", arm and tostring(P:GetManipulateBoneScale(arm)))
    local slot = GK.ShopSlots[2]
    P:SetNW2Int("gk_roaches", 2)
    local paid
    GK.Shop.Charge(P, slot, function(ok) paid = ok end)
    log("buy", slot.name, "price", slot.price, "with 2 roaches:", tostring(paid), "left", GK.Roaches.Count(P))
    P:SetNW2Int("gk_roaches", 10)
    GK.Shop.Charge(P, slot, function(ok) paid = ok end)
    log("buy with 10 roaches:", tostring(paid), "left", GK.Roaches.Count(P))
    -- The bank: banked roaches survive death and are spent after carried ones.
    P:SetNW2Int("gk_bank", 0) P:SetNW2Int("gk_roaches", 8)
    local n = GK.Roaches.Bank(P)
    log("banked", n, "carried", GK.Roaches.Count(P), "bank", GK.Roaches.Banked(P))
    P:SetNW2Int("gk_roaches", 2)
    log("spend 5 with 2 carried + 8 banked:", tostring(GK.Roaches.Spend(P, 5)), "carried", GK.Roaches.Count(P), "bank", GK.Roaches.Banked(P))
end)
-- 5. Pitons (WK reference): set but unhammered it pops out after 0.5 s of
-- weight; hammered three times it holds for good. Rebar throw kicks you off.
local function faceWall()
    P:SetPos(W.hit + W.n * 40 + Vector(0, 0, -64))
    local eye = P:EyePos()
    local hit = util.TraceLine({ start = eye, endpos = eye - W.n * 200, filter = P })
    return hit.HitPos, hit.HitNormal
end
local piton
local function newPiton(hits)
    local pos, n = faceWall()
    piton = ents.Create("gk_piton_hold")
    piton:SetPos(pos + n) piton:SetAngles(n:Angle()) piton:Spawn()
    for i = 1, hits do piton:Hammer() end
    P:SetEyeAngles((piton:GetPos() + piton:GetForward() * 4 - P:EyePos()):Angle())
    GK.SetStamina(P, 100)
    -- Grab it straight away, before falling past it.
    local mind = P:GetWeapon("gk_mind")
    local g = mind:TryGrip(P, "l")
    log("piton grab hits", hits, g and g.kind, g and IsValid(g.entity) and g.entity:GetClass())
    if g then g.since = CurTime() mind.Grips.l = g end
    press(P, IN_ATTACK, 3)
end
step(2, function() P:SelectWeapon("gk_mind") end)
step(0.5, function() newPiton(0) end)
step(0.3, function() log("piton 0 hits gripped", P:GetNW2Int("gk_hand_l")) end)
step(1.2, function() log("piton 0 hits after 1.5s: popped", tostring(piton.GK_Popped == true)) end)
step(1, function() newPiton(3) end)
step(2.5, function() log("piton 3 hits after 2.5s: popped", tostring(piton.GK_Popped == true), "gripping", P:GetNW2Int("gk_hand_l"), "stamina", sta()) end)
step(0.5, function()
    GK.SetStamina(P, 100)
    newPiton(3)
end)
step(0.5, function()
    log("before rebar throw gripping", P:GetNW2Int("gk_hand_l"))
    GK.ThrowRebar(P, "rebar")
    local mind = P:GetWeapon("gk_mind")
    log("right after rebar throw: grip l", tostring(mind.Grips and mind.Grips.l ~= nil))
end)
step(0.2, function() log("after rebar throw gripping", P:GetNW2Int("gk_hand_l"), "hand colour", tostring(GK.HandColor(P, "l"))) end)
-- 6. Roach AI (WK DEN_Roach port): climbs walls, rides ceilings, flees at
-- 79 u/s, crushed when you're on top of it, dies to any damage.
local R = {}
local function nstr(r) return r.GK_N and ("%.2f %.2f %.2f"):format(r.GK_N.x, r.GK_N.y, r.GK_N.z) or "falling" end
step(1, function()
    for _, r in ipairs(ents.FindByClass("gk_roach")) do r:Remove() end
    P:SetPos(P:GetPos() + Vector(0, 0, 4))
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    -- A rig of frozen plates high in the air (props are surfaces too): a floor,
    -- a wall standing on it, and a ceiling over the far end.
    local function plate(mdl, pos, ang)
        local p = ents.Create("prop_physics")
        p:SetModel(mdl) p:SetPos(pos) p:SetAngles(ang) p:Spawn()
        p:GetPhysicsObject():EnableMotion(false)
        return p
    end
    local base = P:GetPos() + Vector(0, 0, 500)
    local floorP = plate("models/hunter/plates/plate4x4.mdl", base, Angle(0, fwd:Angle().y, 0))
    base = base + Vector(0, 0, 1.7)
    plate("models/hunter/plates/plate2x2.mdl", base + fwd * 60 + Vector(0, 0, 47), fwd:Angle() + Angle(90, 0, 0))
    local ceil = plate("models/hunter/plates/plate2x2.mdl", base - fwd * 60 + Vector(0, 0, 60), Angle(0, fwd:Angle().y, 0))
    log("roach rig floor", tostring(base))
    R.climber = GK.SpawnRoach("gold", base + fwd * 20 + Vector(0, 0, 2))
    R.climber.GK_Target = fwd * 79 R.climber.GK_Wander = CurTime() + 30
    R.ceiling = GK.SpawnRoach("gold", ceil:GetPos() - Vector(0, 0, 3))
    local under = util.TraceLine({ start = ceil:GetPos() - Vector(0, 0, 30), endpos = ceil:GetPos() + Vector(0, 0, 30), filter = function(e) return e == ceil end })
    R.ceiling:SetPos(under.HitPos - Vector(0, 0, 0.5))
    R.ceiling.GK_N = Vector(0, 0, -1) R.ceiling.GK_Start = R.ceiling:GetPos()
    R.ceilZ = ceil:GetPos().z
    R.ceilStart = R.ceiling:GetPos()
    R.base = base
    log("climber start normal", nstr(R.climber))
end)
step(2, function()
    log("climber after 2s normal", nstr(R.climber), "height", ("%.0f"):format(R.climber:GetPos().z - R.base.z))
    log("ceiling roach normal", nstr(R.ceiling), "below plate", ("%.1f"):format(R.ceilZ - R.ceiling:GetPos().z), "moved", ("%.0f"):format(R.ceiling:GetPos():Distance(R.ceilStart)))
end)
step(3, function()
    log("climber after 5s normal", nstr(R.climber), "height", ("%.0f"):format(R.climber:GetPos().z - R.base.z), "still on rig", tostring(R.climber:GetPos():Distance(R.base) < 200))
    log("ceiling roach after 5s normal", nstr(R.ceiling))
    -- Flee speed: a roach 40 u in front of the player.
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    R.runner = GK.SpawnRoach("gold", P:GetPos() + fwd * 40 + Vector(0, 0, 2))
    R.runStart = R.runner:GetPos()
end)
step(1, function()
    local d = R.runner:GetPos() - R.runStart
    log("fled in 1s", ("%.0f"):format(d:Length2D()), "u (WK ~79) dz", ("%.0f"):format(d.z), "normal", nstr(R.runner))
    -- Crushed: grace over, right under the player.
    R.runner.GK_Grace = 0
    R.runner:SetPos(P:GetPos() + Vector(0, 0, 1))
end)
step(0.3, function()
    log("crushed under player", tostring(not IsValid(R.runner)))
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    R.shot = GK.SpawnRoach("platinum", P:GetPos() + fwd * 120 + Vector(0, 0, 2))
    R.shot:TakeDamage(1, P, P)
    R.boom = GK.SpawnRoach("boom", P:GetPos() + Vector(0, 0, 1))
    R.boom.GK_Grace = 0
    P:SetHealth(100)
end)
step(0.6, function()
    log("one damage kills", tostring(not IsValid(R.shot)), "stepping on boom bug: hp", P:Health(), "vz", ("%.0f"):format(P:GetVelocity().z))
end)
step(0.5, function()
    GK.Hub.Publish()
    local kd = GK.Hub.TopKD(3)
    log("hub top kd", #kd, kd[1] and kd[1].name, kd[1] and kd[1].deaths, "money", GK.Hub.TopMoney(1)[1] and GK.Hub.TopMoney(1)[1].roaches, "arena1 active", tostring(GK.Hub.Arenas()[1].active))
    local vac = ents.FindByClass("gk_vacuum")[1]
    if vac then log("queue", GK.VacuumQueueText(vac)) else log("queue: no vacuum on this map") end
end)
step(1, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_RoachTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_RoachTest")
    timer.Simple(10, function()
        local t = 0
        for _, s in ipairs(steps) do
            t = t + s[1]
            timer.Simple(t, function()
                local ok, err = pcall(s[2])
                if not ok then log("STEP ERROR", err) end
            end)
        end
    end)
end)
