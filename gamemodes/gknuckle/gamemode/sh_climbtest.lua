-- Climb-jump chaining test: hang on a tall wall holding both grip buttons and
-- tap jump every 0.45 s; compare height gained with gk_climb_carry 1 (WK's
-- momentum kept on a fresh grab) and 0 (the old hard snap to the hold).
-- Only runs when data/gknuckle/climbtest.txt exists. Logs "[GKCLIMB]"; no screenshots.
if not file.Exists("gknuckle/climbtest.txt", "DATA") then return end
local function log(...) print("[GKCLIMB]", ...) end

if CLIENT then
    local on, nextJump, jumpUntil, noJump = false, 0, 0, false
    net.Receive("gk_climbtest", function() on = net.ReadBool() noJump = net.ReadBool() end)
    hook.Add("CreateMove", "GK_ClimbTest", function(cmd)
        if not on then return end
        local b = bit.bor(cmd:GetButtons(), IN_ATTACK, IN_ATTACK2, IN_FORWARD)
        local t = CurTime()
        if t > nextJump then nextJump = t + 0.45 jumpUntil = t + 0.08 end
        if t < jumpUntil and not noJump then b = bit.bor(b, IN_JUMP) end
        cmd:SetButtons(b)
        cmd:SetForwardMove(200)
    end)
    return
end
util.AddNetworkString("gk_climbtest")

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, base, fwd, wallPos
local function setOn(b, noJump) net.Start("gk_climbtest") net.WriteBool(b) net.WriteBool(noJump or false) net.Send(P) end

local function trial(carry)
    step(0.5, function()
        RunConsoleCommand("gk_climb_carry", carry)
        P:SetPos(base) P:SetLocalVelocity(vector_origin)
        P:SetEyeAngles(Angle(-35, fwd:Angle().y, 0))
        GK.SetStamina(P, 100)
        P.GK_MaxZ = base.z
    end)
    step(0.5, function() setOn(true) end)
    for i = 1, 16 do
        step(0.5, function()
            P.GK_MaxZ = math.max(P.GK_MaxZ, P:GetPos().z)
            GK.SetStamina(P, 100) -- grip isn't what's being measured
            P:SetEyeAngles(Angle(-35, fwd:Angle().y, 0))
        end)
    end
    step(0.1, function()
        setOn(false)
        log("carry", carry, "climbed", math.floor(P.GK_MaxZ - base.z), "u in 8 s")
    end)
end

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    -- A bare wall: only grippable with WK's ledges-only rule off (restored at the end).
    RunConsoleCommand("gk_climb_mode_wk", "0")
    fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    -- A tall frozen wall (frozen props climb like walls).
    local wallBase = P:GetPos() + fwd * 60
    for k = 0, 5 do
        local p = ents.Create("prop_physics")
        p:SetModel("models/hunter/plates/plate8x8.mdl")
        p:SetPos(wallBase + Vector(0, 0, 190 + k * 379))
        p:SetAngles(fwd:Angle() + Angle(90, 0, 0))
        p:Spawn()
        p:GetPhysicsObject():EnableMotion(false)
    end
    base = P:GetPos()
end)
trial(1)
trial(0)
-- One jump off a hold, plain and then off a cryoshot platform (shatter boost).
local function oneJump(boost)
    local z0, zmax
    step(0.5, function()
        P:SetPos(base) P:SetLocalVelocity(vector_origin)
        P:SetEyeAngles(Angle(-10, fwd:Angle().y, 0)) GK.SetStamina(P, 100)
        setOn(true, true) -- grip, no jumping
    end)
    step(1.2, function()
        local mind = P:GetWeapon("gk_mind")
        local g = mind.Grips and (mind.Grips.l or mind.Grips.r)
        if boost and g then
            local piece = ents.FindByClass("gk_level_piece")[1] or game.GetWorld()
            g.boost = GK.HandholdSpecial(ents.FindByClass("gk_level_piece")[1], { kind = "icy", boost = true, mins = Vector(), maxs = Vector(8, 8, 8) }) or { shape = { centre = P:EyePos() } }
        end
        z0 = P:GetPos().z zmax = z0
        log(boost and "boost" or "plain", "gripping", tostring(g ~= nil))
        setOn(true, false) -- now jump
    end)
    for _ = 1, 12 do step(0.1, function() zmax = math.max(zmax, P:GetPos().z) end) end
    step(0, function() setOn(false) log(boost and "cryoshot jump" or "plain jump", "rose", math.floor(zmax - z0)) end)
end
oneJump(false)
oneJump(true)
step(0.5, function() RunConsoleCommand("gk_climb_carry", "1") RunConsoleCommand("gk_climb_mode_wk", "1") log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_ClimbTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_ClimbTest")
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
