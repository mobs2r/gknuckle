-- Per-hand grip test (gm_construct). Only runs when data/gknuckle/griptest.txt
-- exists: hangs off a frozen wall by the left hand, then both, and checks each
-- hand's meter, the 0.25 s release lock, run reach and KZ in runs.
-- Logs "[GKGRIP]", ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/griptest.txt", "DATA") then return end
local function log(...) print("[GKGRIP]", ...) end

if CLIENT then
    local held = 0
    net.Receive("gk_griptest", function() held = net.ReadUInt(32) end)
    hook.Add("CreateMove", "GK_GripTest", function(cmd)
        if held ~= 0 then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) end
    end)
    return
end
util.AddNetworkString("gk_griptest")

local steps, P, wall = {}, nil, nil
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local function hold(b) net.Start("gk_griptest") net.WriteUInt(b, 32) net.Send(P) end
local function meters() return ("L %.1f  R %.1f  avg %.1f"):format(GK.HandGrip(P, "l"), GK.HandGrip(P, "r"), GK.Stamina(P)) end
local fwd, base
local function hangAt()
    P:SetPos(base + Vector(0, 0, 120)) P:SetLocalVelocity(vector_origin)
    P:SetEyeAngles(Angle(-20, fwd:Angle().y, 0))
end

step(0, function()
    RunConsoleCommand("gk_climb_mode_wk", "0") -- a bare wall
    P:SelectWeapon("gk_mind")
    fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    base = P:GetPos()
    for k = 0, 2 do
        local p = ents.Create("prop_physics")
        p:SetModel("models/hunter/plates/plate8x8.mdl")
        p:SetPos(base + fwd * 60 + Vector(0, 0, 190 + k * 379))
        p:SetAngles(fwd:Angle() + Angle(90, 0, 0))
        p:Spawn()
        p:GetPhysicsObject():EnableMotion(false)
    end
    GK.SetStamina(P, 100)
end)
-- Left hand alone, off the ground, for 3 s.
step(1, function() hangAt() hold(IN_ATTACK) end)
step(0.5, function() log("left hand on:", P:GetNW2Int("gk_hand_l", 0), P:GetNW2Int("gk_hand_r", 0), meters()) end)
step(3, function()
    log("after 3 s one-handed (expect L down ~30, R full):", meters(), "on ground", tostring(P:OnGround()))
    hold(0)
end)
-- Released: the left hand can't take a hold again for 0.25 s.
step(0.1, function() hold(IN_ATTACK) end)
step(0.08, function() log("re-grab 0.1 s after letting go:", P:GetNW2Int("gk_hand_l", 0), "(expect 0: locked)") end)
step(0.4, function() log("0.5 s after letting go:", P:GetNW2Int("gk_hand_l", 0), "(expect 1: grabbed again)") hold(0) end)
-- Both hands for 3 s.
step(0.5, function() GK.SetStamina(P, 100) hangAt() hold(bit.bor(IN_ATTACK, IN_ATTACK2)) end)
step(3.5, function() log("after ~3 s two-handed (expect both down ~15):", meters()) hold(0) end)
-- Reach: hub vs a run.
step(0.5, function()
    log("reach in the hub", GK.GripRange(P), "| gk_kz", GK.KZ:GetInt(), "uses KZ here", tostring(GK.UsesKZ(P)))
    P:SetNW2Int("gk_arena", 1)
    log("reach in a run", GK.GripRange(P), "uses KZ in a run", tostring(GK.UsesKZ(P)), "(expect 90, false)")
    P:SetNW2Int("gk_arena", 0)
    RunConsoleCommand("gk_climb_mode_wk", "1")
end)
step(0.5, function() print("[GKTEST] DONE") end)
step(1, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_GripTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_GripTest")
    P = ply
    local t = 10
    for _, s in ipairs(steps) do
        t = t + s[1]
        timer.Simple(t, function()
            local ok, err = pcall(s[2])
            if not ok then log("STEP ERROR", err) end
        end)
    end
end)
