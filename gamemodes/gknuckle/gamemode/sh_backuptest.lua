-- Biological Backup test (gk_style, needs a bot slot). Only runs when
-- data/gknuckle/backuptest.txt exists: buy a backup at a console, die, and
-- come back when your squadmate reaches the break. Logs "[GKBACK]".
if not file.Exists("gknuckle/backuptest.txt", "DATA") then return end
if CLIENT then return end
local function log(...) print("[GKBACK]", ...) end

hook.Add("PlayerInitialSpawn", "GK_BackTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_BackTest")
    local t, B, A = 10, nil, nil
    local function at(dt, fn) t = t + dt timer.Simple(t, function() local ok, e = pcall(fn) if not ok then log("ERROR", e) end end) end
    at(0, function()
        RunConsoleCommand("gk_tube_rise", "0") RunConsoleCommand("gk_break_time", "6")
        RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
        player.CreateNextBot("mate")
    end)
    at(2, function()
        B = player.GetBots()[1]
        GK.LeaveSquad(P) GK.LeaveSquad(B) GK.JoinSquads(P, B)
        A = GK.StartArena(1, { P, B }, false)
        -- One squad of two for the test.
        A.teams[B] = A.teams[P] A.teamCount = 1 B:SetNW2Int("gk_team", A.teams[P])
        log("run", A.info.region, "teams", A.teamCount, "same team", tostring(A.teams[P] == A.teams[B]))
    end)
    at(1, function()
        local c = ents.Create("gk_perk_console") c:SetPos(P:GetPos() + Vector(40, 0, 0)) c:Spawn()
        P:SetNW2Int("gk_bank", 30)
        GK.OfferPerks(P, c)
        log("bought a backup:", tostring(GK.PickPerk(P, "backup")), "has it", tostring(GK.HasBackup(P)), "bank", GK.Roaches.Banked(P), "(expect true, true, 5)")
        log("a second one:", tostring(GK.PickPerk(P, "backup")), "(expect false)")
    end)
    at(1, function() P:Kill() end)
    at(4, function() log("you died:", "alive", tostring(P:Alive()), "arena", GK.ArenaOf(P), "backup", tostring(GK.HasBackup(P))) end)
    at(0.5, function()
        B:SetPos(Vector(A.info.spawn.x, A.info.spawn.y, A.info.top + 8))
    end)
    at(1.5, function()
        local pk = GK.Arena.Pocket(1)
        log("mate reached the break: you alive", tostring(P:Alive()), "in the break room", tostring(pk and P:GetPos():Distance(pk.center) < pk.half * 2),
            "arena", GK.ArenaOf(P), "backup used up", tostring(not GK.HasBackup(P)), "(expect true, true, 1, true)")
    end)
    at(1, function() print("[GKTEST] DONE") end)
    at(1, function() game.ConsoleCommand("quit\n") end)
end)
