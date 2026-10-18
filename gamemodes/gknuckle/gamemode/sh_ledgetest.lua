-- Ledge detection and mantling, by numbers (gm_construct). Only runs when
-- data/gknuckle/ledgetest.txt exists. Logs "[GKLEDGE]"; no screenshots.
if not file.Exists("gknuckle/ledgetest.txt", "DATA") then return end
local function log(...) print("[GKLEDGE]", ...) end

if CLIENT then
    local on = false
    net.Receive("gk_ledgetest", function() on = net.ReadBool() end)
    hook.Add("CreateMove", "GK_LedgeTest", function(cmd)
        if not on then return end
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK, IN_FORWARD))
        cmd:SetForwardMove(200)
    end)
    return
end
util.AddNetworkString("gk_ledgetest")

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, fwd, face, top, cube
local function hold(b) net.Start("gk_ledgetest") net.WriteBool(b) net.Send(P) end
local function aimAt(pos) P:SetEyeAngles((pos - P:GetShootPos()):Angle()) end

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    fwd = Angle(0, math.Round(P:EyeAngles().y / 90) * 90, 0):Forward()
    -- A 95 u frozen block a step in front of us: a ledge at its top.
    cube = ents.Create("prop_physics")
    cube:SetModel("models/hunter/blocks/cube2x2x2.mdl")
    cube:SetPos(P:GetPos() + fwd * 110 + Vector(0, 0, 47.5))
    cube:SetAngles(fwd:Angle())
    cube:Spawn()
    cube:GetPhysicsObject():EnableMotion(false)
    local mins, maxs = cube:WorldSpaceAABB()
    top = maxs.z
    face = cube:GetPos() - fwd * 47.4
    log("block top above our feet", math.floor(top - P:GetPos().z))
    for _, e in ipairs(ents.FindInSphere(cube:GetPos(), 400)) do if e:GetClass() == "gk_item" then e:Remove() end end -- loose items in the way
end)
-- How far below the lip a grab still finds it (expect yes to 64, no beyond).
for _, below in ipairs({ 6, 20, 40, 60, 80 }) do
    step(0.3, function()
        P:SetPos(cube:GetPos() - fwd * 100 - Vector(0, 0, 47.5)) P:SetLocalVelocity(vector_origin)
        aimAt(Vector(face.x, face.y, top - below))
        local mind = P:GetWeapon("gk_mind")
        local tr = mind:Trace(P)
        local lip = tr and mind:LedgeLip(tr)
        log("grab", below, "u below the lip: ledge", tostring(lip ~= nil), "lip z vs top", lip and math.floor(lip.z - top) or "-")
    end)
end
-- Its top surface directly: a ledge.
step(0.3, function()
    aimAt(Vector(face.x, face.y, top) + fwd * 10)
    local mind = P:GetWeapon("gk_mind")
    local tr = mind:Trace(P)
    log("grab the top surface: ledge", tostring(tr and mind:LedgeLip(tr) ~= nil))
end)
-- Mantling: hang 40 u under the lip and hold W, once facing it and once looking
-- 60 degrees off to the side. Expect to end up standing on the block.
for _, off in ipairs({ 0, 60 }) do
    step(0.5, function()
        P:SetPos(cube:GetPos() - fwd * 64 - Vector(0, 0, 47.5)) P:SetLocalVelocity(vector_origin)
        GK.SetStamina(P, 100)
        local a = (Vector(face.x, face.y, top - 40) - P:GetShootPos()):Angle()
        P:SetEyeAngles(a)
        P.GK_LedgeYaw = a.y + off
        hold(true)
    end)
    for _ = 1, 6 do
        step(0.25, function()
            -- After the grab, turn the view (the grip stays where it is).
            local e = P:EyeAngles() P:SetEyeAngles(Angle(-10, P.GK_LedgeYaw, 0))
            GK.SetStamina(P, 100)
            log("  hands", P:GetNW2Int("gk_hand_l", 0), P:GetNW2Int("gk_hand_r", 0), "top", tostring(P:GetNW2Bool("gk_top_l", false)), tostring(P:GetNW2Bool("gk_top_r", false)), "feet vs top", math.floor(P:GetPos().z - top))
        end)
    end
    step(0.5, function()
        hold(false)
        local on = P:GetPos().z >= top - 4
        local d = P:GetPos() - cube:GetPos() d.z = 0
        log("mantle looking", off, "deg off: on top", tostring(on), "feet vs top", math.floor(P:GetPos().z - top), "inside block footprint", tostring(math.abs(d:Dot(fwd)) < 48 and math.abs(d:Dot(fwd:Angle():Right())) < 48))
    end)
end
-- Grab memory: let go, look away; within 0.3 s the hand takes the same hold again, later it does not.
for _, wait in ipairs({ 0.15, 0.6 }) do
    step(0.6, function()
        P:SetPos(cube:GetPos() - fwd * 64 - Vector(0, 0, 47.5)) P:SetLocalVelocity(vector_origin)
        P:SetEyeAngles((Vector(face.x, face.y, top - 40) - P:GetShootPos()):Angle())
        local mind = P:GetWeapon("gk_mind")
        mind.Grips = {}
        local g = mind:TryGrip(P, "l")
        if g then mind.Grips.l = g end
        mind:Release("l")
        P:SetEyeAngles(Angle(-80, P:EyeAngles().y + 120, 0)) -- at the sky, away from the block
        timer.Simple(wait, function()
            local again = mind:TryGrip(P, "l")
            log("grab memory: let go, looked away, tried again after", wait, "s: got the hold", tostring(again ~= nil and again.kind == "world"), wait < 0.3 and "(expect true)" or "(expect false)")
        end)
    end)
end
-- WK items: a piton goes in with one click (no hammer) and is used up; it
-- stands out of the wall; a rebar is one throw. Hands free of grips first.
step(0.6, function()
    local mind = P:GetWeapon("gk_mind") mind.Grips = {}
    P:SetPos(cube:GetPos() - fwd * 110 - Vector(0, 0, 47.5)) P:SetLocalVelocity(vector_origin)
    local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
    GK.Inv.Give(P, "piton") GK.Inv.Give(P, "piton") GK.Inv.Give(P, "rebar")
    log("given 2 pitons and a rebar: bag items", #inv.bag, "(expect 3, one each, no stacks)")
    for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "piton" then GK.Inv.Move(P, it.id, "hand_l") break end end
    GK.Inv.Sync(P)
    P:SetEyeAngles((Vector(face.x, face.y, top - 30) - P:GetShootPos()):Angle())
    local n0 = #ents.FindByClass("gk_piton_hold")
    GK.Inv.Use(P, "l")
    local p = ents.FindByClass("gk_piton_hold")[#ents.FindByClass("gk_piton_hold")]
    local out = IsValid(p) and (p:WorldSpaceCenter() - Vector(face.x, face.y, p:WorldSpaceCenter().z)):Dot(-fwd) or -1
    log("piton clicked at the wall: placed", #ents.FindByClass("gk_piton_hold") - n0, "(expect 1)", "hand now", tostring(GK.Inv.HandItem(P, "l")), "(expect nil)", "pitons left in bag", #inv.bag - 1)
    log("placed piton: centre stands out of the wall by", ("%.1f"):format(out), "u; model length", IsValid(p) and math.floor(math.max((p:OBBMaxs() - p:OBBMins()):Unpack())) or -1, "; drawn", tostring(IsValid(p) and not p:GetNoDraw()))
    P.GK_TestPiton = p
end)
step(5, function() log("piton still in the wall after 5 s", tostring(IsValid(P.GK_TestPiton))) end)
step(0.3, function()
    local inv = GK.Inv.Get(P)
    for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "rebar" then GK.Inv.Move(P, it.id, "hand_r") break end end
    GK.Inv.Sync(P)
    P:SetEyeAngles(Angle(-30, P:EyeAngles().y + 90, 0))
    GK.Inv.Use(P, "r")
    log("rebar thrown: hand now", tostring(GK.Inv.HandItem(P, "r")), "(expect nil, one and done)")
end)
step(1, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_LedgeTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_LedgeTest")
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
