local CEILBASE, R0 -- shared between the steps below (were accidental globals)
-- Creature test: bloodbug, turret, gas bag, a roach under a ceiling, and the
-- god ray stare. Only runs when data/gknuckle/creaturetest.txt exists.
-- Logs "[GKCRIT]" lines and takes screenshots.
if not file.Exists("gknuckle/creaturetest.txt", "DATA") then return end
local function log(...) print("[GKCRIT]", ...) end

if CLIENT then
    net.Receive("gk_creaturetest", function()
        local what = net.ReadString()
        if what == "shot" then do end
        elseif what == "blind" then print("[GKCRIT]", "client god ray blind", ("%.2f"):format(GK.GodRayBlind and GK.GodRayBlind() or -1)) end
    end)
    local held, untilT = 0, 0
    net.Receive("gk_creaturetest_press", function() held = net.ReadUInt(32) untilT = CurTime() + net.ReadFloat() end)
    hook.Add("CreateMove", "GK_CritTestInput", function(cmd)
        if CurTime() < untilT then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) end
    end)
    return
end
util.AddNetworkString("gk_creaturetest")
util.AddNetworkString("gk_creaturetest_press")
local function send(ply, s) net.Start("gk_creaturetest") net.WriteString(s) net.Send(ply) end
local function press(ply, b, d) net.Start("gk_creaturetest_press") net.WriteUInt(b, 32) net.WriteFloat(d) net.Send(ply) end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, W, bug, tur, bag, rc, ceil
local function plate(mdl, pos, ang)
    local p = ents.Create("prop_physics")
    p:SetModel(mdl) p:SetPos(pos) p:SetAngles(ang) p:Spawn()
    p:GetPhysicsObject():EnableMotion(false)
    return p
end
local function gripping() return P:GetNW2Int("gk_hand_l", 0) end

-- Hang on a wall high up, so the creatures can knock us off it.
local function hang()
    local fwd = W.fwd
    P:SetPos(W.hit - fwd * 40 - Vector(0, 0, 50))
    P:SetEyeAngles(fwd:Angle())
    GK.SetStamina(P, 100)
    local mind = P:GetWeapon("gk_mind")
    local g = mind:TryGrip(P, "l")
    if g then g.since = CurTime() g.hold = g.kind == "world" and GK.HoldAt(g.hitpos) or nil mind.Grips.l = g end
    press(P, IN_ATTACK, 8)
end

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    for _, e in ipairs(ents.FindByClass("gk_roach")) do e:Remove() end
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    local base = P:GetPos() + Vector(0, 0, 400)
    local wall = plate("models/hunter/plates/plate4x4.mdl", base + fwd * 60, fwd:Angle() + Angle(90, 0, 0))
    W = { hit = wall:GetPos() - fwd * 2, fwd = fwd }
    hang()
end)
step(0.5, function() log("hanging", gripping()) end)

-- 0. Special holds: an icy one slips after its hold time, a breakable one crumbles.
local slips = 0
step(0.1, function()
    local orig = GK.HoldTick
    GK.HoldTick = function(...) local r = orig(...) if r then slips = slips + 1 end return r end
    GK.Hazards.Holds[99] = { { { kind = "icy", shape = { sphere = true, centre = W.hit, r = 60 }, maxHold = 1, damage = 0 } } }
    hang()
    local g = P:GetWeapon("gk_mind").Grips.l
    log("grabbed hold kind", g and g.hold and g.hold.kind or "none")
end)
step(1.5, function() log("icy hold slips after 1.5s", slips) end)
step(0.1, function()
    slips = 0
    GK.Hazards.Holds[99] = { { { kind = "breakable", shape = { sphere = true, centre = W.hit, r = 60 }, maxHold = 1, damage = 0 } } }
    hang()
end)
step(1.5, function() log("breakable hold broke", slips, "broken", tostring(GK.Hazards.Holds[99][1][1].broken)) GK.Hazards.Holds[99] = nil hang() end)

-- 1. Bloodbug: spawns 3 m behind, should wind up 3 s, charge, knock us off.
step(0.1, function()
    bug = ents.Create("gk_bloodbug")
    bug:SetPos(P:EyePos() - W.fwd * 120 + Vector(0, 0, 20))
    bug:Spawn()
end)
step(1.5, function() log("bloodbug state", bug:GetState(), "(2 hunt, 3 windup)") P:SetEyeAngles((bug:GetPos() - P:EyePos()):Angle()) send(P, "shot") end)
step(4.5, function()
    log("after charge: gripping", gripping(), "hp", P:Health(), "bug state", IsValid(bug) and bug:GetState())
end)
step(0.5, function()
    local hits = 0
    for i = 1, 3 do if IsValid(bug) then bug:TakeDamage(20, P, P) hits = i end end
    log("bloodbug after 3 hammer-size hits: alive", tostring(IsValid(bug) and bug:GetState() ~= 5))
end)

-- 2. Turret on the floor below, facing us: shoots, knocks us off; tipped, it dies.
step(1, function()
    P:SetHealth(100)
    hang()
    local floor = util.TraceLine({ start = P:GetPos(), endpos = P:GetPos() - Vector(0, 0, 2000), mask = MASK_SOLID_BRUSHONLY }).HitPos
    tur = ents.Create("gk_turret")
    tur:SetPos(floor - W.fwd * 300 + Vector(0, 0, 4))
    tur:SetAngles(Angle(0, W.fwd:Angle().y, 0))
    tur:Spawn()
    timer.Simple(0.5, function() log("turret spawned: dead", tostring(tur:GetDead()), "up dot", ("%.2f"):format(tur:GetUp():Dot(vector_up)), "dist", ("%.0f"):format(tur:GetPos():Distance(P:GetPos()))) end)
end)
step(3, function()
    log("turret locked", tostring(tur:GetLocked()), "gripping", gripping(), "hp", P:Health())
    P:SetEyeAngles((tur:GetPos() - P:EyePos()):Angle()) send(P, "shot")
end)
step(0.5, function()
    local phys = tur:GetPhysicsObject()
    phys:ApplyForceOffset(W.fwd * 40 * 900, tur:GetPos() + Vector(0, 0, 40))
end)
step(2, function() log("turret after shove: dead", tostring(tur:GetDead()), "up dot", ("%.2f"):format(tur:GetUp():Dot(vector_up))) end)

-- 3. Gas bag right under us: bursts and launches us straight up.
step(1, function()
    P:SetHealth(100)
    P:GetWeapon("gk_mind"):ReleaseAll()
    press(P, 0, 0.1)
    local pos = P:GetPos() + Vector(0, 0, 200)
    P:SetPos(pos)
    bag = ents.Create("gk_gasbag")
    bag:SetPos(pos - Vector(0, 0, 70))
    bag:Spawn()
end)
local peak = -math.huge
step(0.05, function()
    hook.Add("Think", "GK_CritPeak", function() if IsValid(P) then peak = math.max(peak, P:GetVelocity().z) end end)
end)
step(1, function()
    hook.Remove("Think", "GK_CritPeak")
    log("gas bag burst", tostring(not IsValid(bag)), "peak vz", ("%.0f"):format(peak), "hp", P:Health())
end)

-- 4. A roach under a ceiling plate: it should crawl along the underside.
step(1.5, function()
    local base = P:GetPos() + Vector(0, 0, 300)
    ceil = plate("models/hunter/plates/plate4x4.mdl", base, Angle(0, 0, 0))
    CEILBASE = base
end)
step(0.2, function()
    local base = CEILBASE
    -- Spawned just under the ceiling: it should cling to it (gk_roach Settle).
    local mins = ceil:WorldSpaceAABB()
    log("ceiling plate bottom", ("%.1f"):format(mins.z - base.z))
    rc = GK.SpawnRoach("gold", Vector(base.x, base.y, mins.z - 6))
    log("ceiling roach on spawn: normal", rc.GK_N and ("%.2f"):format(rc.GK_N.z) or "falling")
    rc.GK_Target = Vector(40, 0, 0) rc.GK_Wander = CurTime() + 3
    R0 = rc:GetPos()
end)
step(3, function()
    local n = rc.GK_N
    log("ceiling roach after 3s: normal", n and ("%.2f %.2f %.2f"):format(n.x, n.y, n.z) or "falling", "moved", ("%.0f"):format(rc:GetPos():Distance(R0)), "dz", ("%.1f"):format(rc:GetPos().z - R0.z))
end)

-- 4b. Barnacle on the ceiling plate, right above us: its tongue reaches, grabs, reels, bites.
local barn, hp0
step(0.5, function()
    P:SetHealth(100) hp0 = 100
    local spotB = ceil:GetPos() - Vector(0, 0, 4)
    barn = ents.Create("gk_barnacle")
    barn:SetPos(spotB) barn:Spawn()
    barn.GK_Wait = 0
    -- Stand right under it, on a little floor plate.
    plate("models/hunter/plates/plate2x2.mdl", spotB - Vector(0, 0, 160), Angle(0, 0, 0))
    P:SetMoveType(MOVETYPE_WALK)
    P:SetPos(spotB - Vector(0, 0, 156))
    P:SetLocalVelocity(vector_origin)
end)
step(1, function() log("barnacle state", barn:GetState(), "(1 reach, 2 grab)", "tip drop", ("%.0f"):format(barn:Mouth().z - barn:GetTip().z)) end)
step(4, function()
    log("barnacle after 5s: state", barn:GetState(), "victim is P", tostring(barn:GetVictim() == P), "P rose", ("%.0f"):format(P:GetPos().z - (ceil:GetPos().z - 160)), "hp", P:Health())
    P:SetEyeAngles((barn:GetPos() - P:EyePos()):Angle()) send(P, "shot")
end)
step(0.5, function() barn:TakeDamage(5, P, P) end)
step(0.5, function() log("barnacle hurt: state", barn:GetState(), "(3 retract) victim", tostring(barn:GetVictim())) end)

-- 5. God ray above, looking straight up into it: the screen should white out.
step(0.5, function()
    P:SetPos(P:GetPos() + W.fwd * -900) P:SetLocalVelocity(vector_origin)
    local ray = ents.Create("gk_godray")
    ray:SetPos(P:EyePos() + Vector(0, 0, 400))
    ray:SetAngles(Angle(90, 0, 0))
    ray:Spawn()
    P:SetEyeAngles(Angle(-89, 0, 0))
    P:SetMoveType(MOVETYPE_NOCLIP)
end)
step(1.5, function() send(P, "blind") send(P, "shot") end)
step(0.5, function() P:SetEyeAngles(Angle(0, 0, 0)) end)
step(2.5, function() send(P, "blind") log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_CritTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_CritTest")
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
