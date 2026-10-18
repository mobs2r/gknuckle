-- Test for the Vent Thing (reach, grab, drag, look-away scare) and items being
-- knocked out of your hands. Only runs when data/gknuckle/venttest.txt exists.
-- Logs "[GKVENT]" lines; no screenshots.
if not file.Exists("gknuckle/venttest.txt", "DATA") then return end
local function log(...) print("[GKVENT]", ...) end
if CLIENT then return end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, vt, start, startYaw

local function face(dir) P:SetEyeAngles(dir:Angle()) end

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    start = P:GetPos()
    startYaw = P:EyeAngles().y
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    vt = ents.Create("gk_ventthing")
    vt:SetPos(P:GetPos() + fwd * 500 + Vector(0, 0, 4))
    vt:Spawn()
    -- Look away from it so it can reach us.
    face(-fwd)
    log("spawned", tostring(IsValid(vt)), "model", vt:GetModel())
end)
step(2, function() log("after 2 s: state", vt:GetState(), "hand to us", math.floor(vt:GetHand():Distance(P:WorldSpaceCenter()))) end)
step(4, function()
    log("after 6 s: state", vt:GetState(), "grabbed", tostring(P:GetNW2Entity("gk_ventgrab") == vt), "hand to us", math.floor(vt:GetHand():Distance(P:WorldSpaceCenter())),
        "us to vent", math.floor(P:GetPos():Distance(vt:GetPos())))
end)
step(1.5, function()
    log("dragged: us to vent", math.floor(P:GetPos():Distance(vt:GetPos())), "alive", tostring(P:Alive()))
    -- Hit it: it lets go and pulls back.
    vt:TakeDamage(5, P, P)
end)
step(0.3, function() log("after a hit: state", vt:GetState(), "grabbed", tostring(IsValid(P:GetNW2Entity("gk_ventgrab")))) end)
-- The scare: move away, wait for it to reach out again, then look right at the hand.
step(6, function()
    if not P:Alive() then P:Spawn() end
    -- Back the way we came (open ground), 1000 u out, facing away.
    local fwd = (start - vt:GetPos()) fwd.z = 0 fwd:Normalize()
    P:SetPos(vt:GetPos() + fwd * 1000 + Vector(0, 0, 8))
    face(fwd)
end)
step(4, function()
    log("reaching again: state", vt:GetState(), "hand from body", math.floor(vt:GetHand():Distance(vt:Root())), "hand to us", math.floor(vt:GetHand():Distance(P:WorldSpaceCenter())))
    face(vt:GetHand() - P:EyePos())
end)
step(0.5, function() log("looked at it: state", vt:GetState(), "(2 = pulling back)") end)
-- Knocked out of your hands.
step(1, function()
    local inv = GK.Inv.Get(P)
    GK.Inv.Give(P, "brick")
    inv.slots.hand_r = inv.slots.hand_r or table.remove(inv.bag)
    GK.Inv.Sync(P)
    local before = GK.Inv.HandItem(P, "r") ~= nil
    local n0 = #ents.FindByClass("gk_item")
    local knocked = GK.Inv.KnockFromHands(P, P:GetPos() + Vector(100, 0, 0))
    log("hand item before", tostring(before), "knocked", tostring(knocked), "hand item after", tostring(GK.Inv.HandItem(P, "r") ~= nil), "items dropped", #ents.FindByClass("gk_item") - n0)
end)
-- The hopper: it spots us, crouches, leaps and bites.
local hop
step(1, function()
    if IsValid(vt) then vt:Remove() end
    if not P:Alive() then P:Spawn() end
    -- Back to where we started (open ground), the way we first faced.
    P:SetPos(start) P:SetEyeAngles(Angle(0, startYaw, 0)) P:SetLocalVelocity(vector_origin)
    P:SetHealth(100)
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward() fwd.z = 0 fwd:Normalize()
    hop = ents.Create("gk_hopper")
    hop:SetPos(P:GetPos() + fwd * 250 + Vector(0, 0, 4))
    hop:Spawn()
    log("hopper spawned", tostring(IsValid(hop)), "model", hop:GetModel())
end)
step(1, function()
    local p = hop:GetPos()
    local g = util.TraceLine({ start = p + Vector(0, 0, 8), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID, filter = hop })
    log("hopper after 1 s: state", hop:GetState(), "(1 ready, 2 leaping)", "z above floor", math.floor(p.z - g.HitPos.z), "movetype", hop:GetMoveType(), "vel", tostring(hop:GetVelocity()), "next", hop.GK_Next and math.floor(hop.GK_Next - CurTime()), "target", tostring(hop.Target and hop:Target()))
end)
step(3, function() log("hopper after 4 s: player health", P:Health(), "hopper state", hop:GetState(), "dist", math.floor(hop:GetPos():Distance(P:GetPos()))) end)
step(0.2, function()
    hop:TakeDamage(20, P, P)
    log("hopper hit for 20: state", hop:GetState(), "(3 dead)")
end)
-- A bloodbug and a gas bag: they fly without physics objects now.
local bug, bag, bp0, gp0
-- A clear spot dist out from us at height h (first of eight directions with open air and a clear line).
local function clearSpot(dist, h)
    local eye = P:EyePos()
    for k = 0, 7 do
        local d = Angle(0, k * 45, 0):Forward()
        local p = P:GetPos() + d * dist + Vector(0, 0, h)
        if util.PointContents(p) == CONTENTS_EMPTY and not util.TraceLine({ start = eye, endpos = p, mask = MASK_SOLID }).Hit then return p end
    end
end
step(0.5, function()
    P:SetPos(start) P:SetLocalVelocity(vector_origin) P:SetHealth(100)
    P:SetEyeAngles(Angle(0, startYaw, 0))
    local fwd, right = Angle(0, startYaw, 0):Forward(), Angle(0, startYaw, 0):Right()
    local pb, pg = P:GetPos() + fwd * 400 + Vector(0, 0, 120), P:GetPos() + fwd * 380 + right * 140 + Vector(0, 0, 140)
    log("spots solid", bit.band(util.PointContents(pb), CONTENTS_SOLID) ~= 0, bit.band(util.PointContents(pg), CONTENTS_SOLID) ~= 0)
    bug = ents.Create("gk_bloodbug") bug:SetPos(pb or P:GetPos() + Vector(0, 0, 300)) bug:Spawn()
    bag = ents.Create("gk_gasbag") bag:SetPos(pg or P:GetPos() + Vector(0, 0, 400)) bag:Spawn()
    bp0, gp0 = bug:GetPos(), bag:GetPos()
end)
step(3, function()
    log("bloodbug moved", math.floor(bug:GetPos():Distance(bp0)), "state", bug:GetState(), "to us", math.floor(bug:GetPos():Distance(P:WorldSpaceCenter())))
    log("gas bag moved", math.floor(bag:GetPos():Distance(gp0)))
end)
step(6, function() log("bloodbug after 9 s: state", bug:GetState(), "to us", math.floor(bug:GetPos():Distance(P:WorldSpaceCenter())), "player health", P:Health()) end)
step(1, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_VentTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_VentTest")
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
