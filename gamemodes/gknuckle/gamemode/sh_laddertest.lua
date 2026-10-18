-- Automated ladder test. Only runs when data/gknuckle/laddertest.txt exists:
-- puts a gk_ladder on a wall near spawn and walks the player into it, climbs,
-- hangs, climbs down, jumps off. Logs "[GKLADDER]" lines.

if not file.Exists("gknuckle/laddertest.txt", "DATA") then return end

local function log(...) print("[GKLADDER]", ...) end

if CLIENT then
    local held, untilT, pitch = 0, 0, nil
    net.Receive("gk_laddertest", function()
        held = net.ReadUInt(32)
        untilT = CurTime() + net.ReadFloat()
    end)
    hook.Add("CreateMove", "GK_LadderTestInput", function(cmd)
        if CurTime() < untilT then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), held))
            if bit.band(held, IN_FORWARD) ~= 0 then cmd:SetForwardMove(250) end
            if bit.band(held, IN_BACK) ~= 0 then cmd:SetForwardMove(-250) end
            if bit.band(held, IN_MOVERIGHT) ~= 0 then cmd:SetSideMove(250) end
            if bit.band(held, IN_MOVELEFT) ~= 0 then cmd:SetSideMove(-250) end
        end
    end)
    return
end

util.AddNetworkString("gk_laddertest")
local function press(ply, buttons, dur)
    net.Start("gk_laddertest") net.WriteUInt(buttons, 32) net.WriteFloat(dur) net.Send(ply)
end
local function shot(ply) end -- no screenshots

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, ladder, base, normal

local function z() return ("%.0f"):format(P:GetPos().z - base.z) end

step(0, function()
    P = player.GetHumans()[1]
    for _, e in ipairs(ents.FindByClass("gk_item")) do if e.GK_Starter then e:Remove() end end
    -- A wall 150-500u away from spawn, with clear floor in front.
    local start = P:GetPos() + Vector(0, 0, 40)
    for yaw = 0, 345, 15 do
        local dir = Angle(0, yaw, 0):Forward()
        local tr = util.TraceLine({ start = start, endpos = start + dir * 600, mask = MASK_SOLID_BRUSHONLY })
        if tr.Hit and tr.Fraction * 600 > 150 and math.abs(tr.HitNormal.z) < 0.1 then
            local floor = util.TraceLine({ start = tr.HitPos + tr.HitNormal * 20, endpos = tr.HitPos + tr.HitNormal * 20 - Vector(0, 0, 300), mask = MASK_SOLID_BRUSHONLY })
            base = Vector(tr.HitPos.x, tr.HitPos.y, floor.HitPos.z)
            normal = tr.HitNormal
            break
        end
    end
    if not base then log("no wall") return end
    ladder = ents.Create("gk_ladder")
    ladder:SetPos(base + normal * 1)
    ladder:SetAngles(normal:Angle())
    ladder:Spawn()
    ladder:SetBox(40, 320)
    log("ladder at", tostring(base), "normal", tostring(normal))
    -- Stand 80u out, facing the ladder.
    P:SetPos(base + normal * 80)
    P:SetEyeAngles((-normal):Angle())
end)

step(1, function() log("start z", z(), "onground", tostring(P:OnGround())) press(P, IN_FORWARD, 0.8) end)
step(0.6, function() log("walked in 0.6s: z", z(), "onladder", tostring(GK.OnLadder(P))) end)
step(0.4, function() log("released at z", z()) shot(P) end)
step(1, function() log("hanging 1s later z", z(), "onladder", tostring(GK.OnLadder(P))) P:SetEyeAngles(Angle(80, (-normal):Angle().y, 0)) end)
step(0.3, function() press(P, IN_FORWARD, 0.6) end)
step(0.7, function() log("W looking down 0.6s z", z()) press(P, IN_BACK, 0.4) end)
step(0.5, function() log("S 0.4s z", z(), "onladder", tostring(GK.OnLadder(P))) P:SetEyeAngles(Angle(0, (-normal):Angle().y, 0)) end)
step(0.2, function() press(P, IN_JUMP, 0.2) end)
step(0.8, function() log("jumped off z", z(), "onladder", tostring(GK.OnLadder(P)), "dist from wall", ("%.0f"):format((P:GetPos() - base):Dot(normal))) end)
-- Walk away from the bottom with S: should just walk off.
step(1.5, function()
    P:SetPos(base + normal * 20)
    P:SetEyeAngles((-normal):Angle())
    press(P, IN_BACK, 1)
end)
step(1.1, function() log("S at bottom: z", z(), "dist", ("%.0f"):format((P:GetPos() - base):Dot(normal)), "onladder", tostring(GK.OnLadder(P))) end)
-- All the way up: should get helped over the top.
step(0.3, function()
    ladder:SetBox(40, 120)
    P:SetPos(base + normal * 30)
    P:SetEyeAngles((-normal):Angle())
    press(P, IN_FORWARD, 3)
end)
step(3.2, function() log("climb to top of 120u ladder: z", z(), "dist", ("%.0f"):format((P:GetPos() - base):Dot(normal))) shot(P) end)
-- Climb speed by input, CS:GO style: W alone, W+D turned 45 degrees (the
-- vector), W looking up 45 degrees. Each from the middle of a tall ladder, 0.8 s.
local tests = {
    { "W facing it", IN_FORWARD, 0, 0 },
    { "W+D turned 45 (vector)", bit.bor(IN_FORWARD, IN_MOVERIGHT), 45, 0 },
    { "W looking up 45", IN_FORWARD, 0, -45 },
}
for _, t in ipairs(tests) do
    step(0.6, function()
        ladder:SetBox(40, 600)
        P:SetPos(base + normal * 30 + Vector(0, 0, 120)) P:SetLocalVelocity(vector_origin)
        local a = (-normal):Angle()
        P:SetEyeAngles(Angle(t[4], a.y + t[3], 0))
        P.GK_Z0 = P:GetPos().z
        press(P, t[2], 0.8)
    end)
    step(0.4, function() log("  mid:", t[1], "vel", tostring(P:GetVelocity()), "fwdmove held", tostring(P:KeyDown(IN_FORWARD)), "z", math.floor(P:GetPos().z - P.GK_Z0), "movetype", P:GetMoveType()) end)
    step(0.45, function() log("climb speed,", t[1], ":", math.floor((P:GetPos().z - P.GK_Z0) / 0.8), "u/s", "on ladder", tostring(GK.OnLadder(P))) end)
end
step(1, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_LadderTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_LadderTest")
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
