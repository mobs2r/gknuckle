-- Pause menu test (gm_construct). Only runs when data/gknuckle/pausetest.txt
-- exists: ESC's hook opens gKnuckle's menu instead of Garry's Mod's, the
-- settings panel opens, ESC again closes it, LEAVE RUN asks first. Screenshots
-- (engine jpeg, since VGUI isn't in render.Capture) land in garrysmod/screenshots.
-- Logs "[GKPAUSE]", ends with "[GKTEST] DONE".
if not file.Exists("gknuckle/pausetest.txt", "DATA") then return end
local function log(...) print("[GKPAUSE]", ...) end
if SERVER then
    hook.Add("PlayerInitialSpawn", "GK_PauseTest", function(P)
        timer.Simple(30, function() game.ConsoleCommand("quit\n") end)
    end)
    return
end

local function find(panel, label)
    for _, c in ipairs(panel:GetChildren()) do
        local l = c.Label
        if l and (isfunction(l) and l() or l) == label then return c end
    end
end

hook.Add("InitPostEntity", "GK_PauseTest", function()
    timer.Simple(8, function()
        local shown = hook.Run("OnPauseMenuShow")
        local m = GK.PauseMenu
        log("ESC: Garry's Mod menu shown", tostring(shown), "(expect false)", "ours open", tostring(IsValid(m)), "(expect true)")
        RunConsoleCommand("jpeg")
    end)
    timer.Simple(10, function()
        local m = GK.PauseMenu
        if not IsValid(m) then return end
        find(m.Col, "SETTINGS"):DoClick()
        log("settings panel open", tostring(IsValid(m.Side)), "(expect true)")
        timer.Simple(0.5, function() RunConsoleCommand("jpeg") end)
    end)
    timer.Simple(12, function()
        local m = GK.PauseMenu
        if not IsValid(m) then return end
        local leave = find(m.Col, "LEAVE RUN")
        leave:DoClick()
        log("LEAVE RUN once: asks", tostring(leave.Label()), "menu still open", tostring(IsValid(m)), "(expect the warning, true)")
        timer.Simple(0.3, function() RunConsoleCommand("jpeg") end)
    end)
    timer.Simple(14, function()
        hook.Run("OnPauseMenuShow")
        log("ESC again: ours open", tostring(IsValid(GK.PauseMenu)), "(expect false)")
        RunConsoleCommand("gk_pausemenu", "0")
    end)
    timer.Simple(15, function()
        local shown = hook.Run("OnPauseMenuShow")
        log("with gk_pausemenu 0: Garry's Mod menu shown", tostring(shown), "(expect true)")
        RunConsoleCommand("gk_pausemenu", "1")
        print("[GKTEST] DONE")
    end)
end)
