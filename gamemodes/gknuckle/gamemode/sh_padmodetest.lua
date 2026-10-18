-- Hub mode buttons test (gk_style). Only runs when data/gknuckle/padmodetest.txt
-- exists: each pad gets a mode switch; pressing it sets that pad's next run.
if not file.Exists("gknuckle/padmodetest.txt", "DATA") then return end
local function log(...) print("[GKPAD]", ...) end
if CLIENT then
    net.Receive("gk_padtest", function() RunConsoleCommand("jpeg") end)
    return
end
util.AddNetworkString("gk_padtest")
hook.Add("PlayerInitialSpawn", "GK_PadTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_PadTest")
    timer.Simple(12, function()
        local btns = ents.FindByClass("gk_mode_button")
        log("mode buttons", #btns, "force buttons", #ents.FindByClass("gk_force_start"))
        local b = btns[1]
        if not IsValid(b) then print("[GKTEST] DONE") return end
        log("button pad", b:GetPad(), "starts at", b:GetMode())
        b.GK_Next = 0 b:Press(P)
        b.GK_Next = 0 b:Press(P)
        log("pressed twice:", b:GetMode(), "(expect hard)")
        RunConsoleCommand("gk_tube_rise", "0")
        local pad = b:GetPad() ~= 0 and b:GetPad() or 1
        local a = GK.StartArena(pad, { P }, true)
        log("pad", pad, "run mode", a and a.mode, "(expect hard)")
        GK.EndArena(pad, nil)
        timer.Simple(5, function()
            P:SetPos(b:GetPos() + b:GetForward() * 110 + Vector(0, 0, 10))
            P:SetEyeAngles((b:GetPos() + Vector(0, 0, 20) - P:EyePos()):Angle())
        end)
        timer.Simple(6.5, function() net.Start("gk_padtest") net.Send(P) end)
        timer.Simple(8, function() print("[GKTEST] DONE") end)
        timer.Simple(9, function() game.ConsoleCommand("quit\n") end)
    end)
end)
