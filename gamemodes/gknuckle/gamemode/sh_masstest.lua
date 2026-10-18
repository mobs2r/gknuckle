-- The Mass (rising gas) test (gk_style). Only runs when data/gknuckle/masstest.txt
-- exists: a solo run; the gas should wait until you've climbed 16 m, rise at
-- WK's pace, and kill outright (not down you) once you're 1 m under it.
-- Logs "[GKMASS]", ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/masstest.txt", "DATA") then return end
if CLIENT then return end
local function log(...) print("[GKMASS]", ...) end

local steps, P, A = {}, nil, nil
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local function gas() return A and A.gas or 0 end
local g0

step(0, function()
    RunConsoleCommand("gk_tube_rise", "0")
    RunConsoleCommand("gk_mass_grace", "60")
    P:GodDisable()
    A = GK.StartArena(1, { P }, true)
    log("started", A.info.region, "spawn z", math.floor(A.info.spawn.z), "gas z", math.floor(gas()))
end)
step(1, function() g0 = gas() end)
step(4, function()
    log("standing at the start for 4 s: gas moved", math.floor(gas() - g0), "u (expect 0: waits for 16 m)", "massAt", tostring(A.massAt))
    -- Up 17 m.
    P:SetPos(A.info.spawn + Vector(0, 0, 17 * 39.37)) P:SetMoveType(MOVETYPE_NOCLIP)
end)
step(1, function() log("17 m up: Mass started", tostring(A.massAt ~= nil)) g0 = gas() end)
step(5, function()
    local behind = (P:GetPos().z - gas()) / 39.4
    log(("over 5 s the gas rose %.0f u = %.1f u/s (WK base 39.4 u/s, x up to 4 when far behind; %.0f m behind now)"):format(gas() - g0, (gas() - g0) / 5, behind))
    -- Drop just under the gas, 1.5 m deep.
    P:SetMoveType(MOVETYPE_WALK)
    P:SetPos(Vector(P:GetPos().x, P:GetPos().y, gas() - 1.5 * 39.4 - 36))
    P:SetLocalVelocity(vector_origin)
end)
step(0.1, function() log("placed: feet z", math.floor(P:GetPos().z), "gas z", math.floor(gas()), "arena", GK.ArenaOf(P), "running", tostring(GK.Rounds.arenas[1] ~= nil)) end)
step(0.5, function()
    log("feet z", math.floor(P:GetPos().z), "gas z", math.floor(gas()))
    log("1.5 m under the gas: alive", tostring(P:Alive()), "downed", tostring(GK.IsDowned and GK.IsDowned(P)), "(expect false, false)")
end)
step(0.5, function() print("[GKTEST] DONE") end)
step(1, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_MassTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_MassTest")
    P = ply
    local t = 12
    for _, s in ipairs(steps) do
        t = t + s[1]
        timer.Simple(t, function()
            local ok, err = pcall(s[2])
            if not ok then log("STEP ERROR", err) end
        end)
    end
end)
