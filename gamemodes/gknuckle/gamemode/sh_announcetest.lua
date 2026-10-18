-- Announcer test (gk_style). Only runs when data/gknuckle/announcetest.txt
-- exists: in a solo Silos run, the PA should play a Silos line to the climber.
-- Logs "[GKANN]", ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/announcetest.txt", "DATA") then return end
local function log(...) print("[GKANN]", ...) end

if CLIENT then
    hook.Add("InitPostEntity", "GK_AnnTest", function()
        net.Receive("gk_announce", function()
            local path = net.ReadString()
            log("PA played", path, "exists", tostring(file.Exists("sound/" .. path, "GAME")), "length", ("%.1f"):format(SoundDuration(path)))
            surface.PlaySound(path)
        end)
    end)
    return
end

hook.Add("PlayerInitialSpawn", "GK_AnnTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_AnnTest")
    timer.Simple(12, function()
        RunConsoleCommand("gk_tube_rise", "0")
        RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
        local a = GK.StartArena(1, { ply }, true)
        log("run", a.info.region)
        a.nextAnnounce = CurTime() + 2
        timer.Simple(9, function()
            a.nextAnnounce = CurTime()
        end)
        timer.Simple(16, function() print("[GKTEST] DONE") end)
        timer.Simple(17, function() game.ConsoleCommand("quit\n") end)
    end)
end)
