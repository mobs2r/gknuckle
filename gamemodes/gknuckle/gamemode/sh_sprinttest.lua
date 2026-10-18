-- Sprint test (gm_construct). Only runs when data/gknuckle/sprinttest.txt
-- exists: walk, then sprint (Alt + W); logs speed, stamina and view FOV.
if not file.Exists("gknuckle/sprinttest.txt", "DATA") then return end
local function log(...) print("[GKSPRINT]", ...) end
if CLIENT then
    local held, fov = 0, 0
    net.Receive("gk_sprinttest", function() held = net.ReadUInt(32) end)
    hook.Add("CreateMove", "GK_SprintTest", function(cmd)
        if held ~= 0 then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) cmd:SetForwardMove(400) end
    end)
    hook.Add("PostRender", "GK_SprintTestFov", function() fov = render.GetViewSetup and render.GetViewSetup().fov or 0 end)
    timer.Create("GK_SprintTestFov", 0.5, 0, function() log("client view fov", math.floor(fov)) end)
    return
end
util.AddNetworkString("gk_sprinttest")
hook.Add("PlayerInitialSpawn", "GK_SprintTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_SprintTest")
    local function hold(b) net.Start("gk_sprinttest") net.WriteUInt(b, 32) net.Send(P) end
    local t = 10
    local function at(dt, fn) t = t + dt timer.Simple(t, function() local ok, e = pcall(fn) if not ok then log("ERROR", e) end end) end
    at(0, function() P:SetPos(Vector(-2600, -1800, -140)) P:SetEyeAngles(Angle(0, 0, 0)) GK.SetStamina(P, 100) hold(IN_FORWARD) end)
    at(1.5, function() log("walking: speed", math.floor(P:GetVelocity():Length2D()), "stamina", math.floor(GK.Stamina(P))) hold(bit.bor(IN_FORWARD, IN_WALK)) end)
    at(1.5, function() log("sprinting: speed", math.floor(P:GetVelocity():Length2D()), "(expect ~330)", "stamina", math.floor(GK.Stamina(P)), "(expect down ~8)") hold(0) end)
    at(1, function() print("[GKTEST] DONE") end)
    at(1, function() game.ConsoleCommand("quit\n") end)
end)
