-- Race flow test (gk_style): per-squad breaks, spectating, WK region order.
-- Only runs when data/gknuckle/racetest.txt exists. Four players (you and
-- three bots), everyone for themselves. Logs "[GKRACE]", saves
-- data/gknuckle/race_*.jpg, ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/racetest.txt", "DATA") then return end
local function log(...) print("[GKRACE]", ...) end

if CLIENT then
    net.Receive("gk_racetest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_RaceShot", function()
            hook.Remove("PostRender", "GK_RaceShot")
            file.Write("gknuckle/race_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
            local me = LocalPlayer()
            log("client shot", name, "alive", tostring(me:Alive()), "observer", me:GetObserverMode(), "target", tostring(me:GetObserverTarget()))
        end)
    end)
    return
end
util.AddNetworkString("gk_racetest")
local function shot(P, name) net.Start("gk_racetest") net.WriteString(name) net.Send(P) end

local steps, P, B, A = {}, nil, {}, nil
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local function where(p)
    if not IsValid(p) then return "gone" end
    local pk = GK.Arena.Pocket(1)
    local inPocket = pk and p:GetPos():Distance(pk.center) < pk.half * 2
    return ("%s alive=%s pocket=%s arena=%d obs=%d tgt=%s"):format(p:Nick(), tostring(p:Alive()), tostring(inPocket), GK.ArenaOf(p),
        p:GetObserverMode(), IsValid(p:GetObserverTarget()) and p:GetObserverTarget():Nick() or "-")
end
local function toTop(p)
    local info = A.info
    p:SetPos(Vector(info.spawn.x, info.spawn.y, info.top + 8))
    p:SetLocalVelocity(vector_origin)
end

step(0, function()
    RunConsoleCommand("gk_break_time", "6")
    RunConsoleCommand("gk_run_regions", "2")
    RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
    RunConsoleCommand("gk_tube_rise", "0")
    for i = 1, 3 do player.CreateNextBot("racer" .. i) end
end)
step(0.5, function() GK.LiftRide({ P }, function() log("lift arrived") end) end)
step(3, function() shot(P, "0_lift_view") end)
step(4, function()
    B = player.GetBots()
    P:GodDisable()
    A = GK.StartArena(1, { P, B[1], B[2], B[3] }, true)
    log("started: region", A and A.info.region, "teams", A and A.teamCount, "stage", A and A.stage)
end)
step(1.6, function() shot(P, "0_title_card") end)
step(1.4, function() toTop(B[1]) end)
step(1, function()
    log("racer1 reached the top:", where(B[1]), "| stage", A.stage, "inBreak", tostring(A.inBreak))
    P:Kill()
end)
step(4.5, function()
    log("you died with three racers left:", where(P), "(expect dead, watching a racer)")
    shot(P, "1_watching")
end)
step(1, function()
    toTop(B[2])
end)
step(1, function()
    log("racer2 reached the top:", where(B[2]), "| inBreak", tostring(A.inBreak), "(expect false: racer3 still climbing)")
    B[3]:Kill()
end)
step(1, function() log("racer3 died: inBreak", tostring(A.inBreak), "(expect true)") end)
step(3, function()
    log("riding the lift out:", "racer1 in lift", tostring(GK.InLift(B[1])), "racer2 in lift", tostring(GK.InLift(B[2])), "stage", A.stage, "(expect true, true, 1)")
    shot(P, "1b_lift")
end)
step(5, function()
    log("next region: stage", A.stage, "region", A.info.region, "(expect 2, Region_Pipeworks_Campaign)")
    log(" ", where(P)) log(" ", where(B[1])) log(" ", where(B[2])) log(" ", where(B[3]))
    shot(P, "2_watching_stage2")
end)
step(1, function() toTop(B[1]) end)
step(6, function()
    log("racer1 topped the last region: arena running", tostring(GK.Rounds.arenas[1] ~= nil), "(expect false)")
    log(" ", where(P)) log(" ", where(B[1])) log(" ", where(B[2])) log(" ", where(B[3]))
end)
step(0.5, function() print("[GKTEST] DONE") end)
step(1, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_RaceTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_RaceTest")
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
