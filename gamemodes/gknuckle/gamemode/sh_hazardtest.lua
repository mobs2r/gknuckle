-- Run hazards and creatures test (gk_style). Only runs when
-- data/gknuckle/hazardtest.txt exists: builds Silos, Pipeworks and Habitation
-- runs, climbs through each so every room streams in, counts drones,
-- bloodbugs and live fan/grinder zones, and stands in a fan zone.
-- Logs "[GKHAZ]", ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/hazardtest.txt", "DATA") then return end
if CLIENT then return end
local function log(...) print("[GKHAZ]", ...) end

local P
local REGIONS = { "Region_Silos_Campaign", "Region_Pipeworks_Campaign", "Region_Habitation_Campaign" }
local SEEDS = { 11, 22 }
local fanZone

local function count(cls) return #ents.FindByClass(cls) end
local function liveMoving(index)
    local n, kinds = 0, {}
    for _, list in pairs(GK.Hazards.zones[index] or {}) do
        for _, z in ipairs(list) do
            if z.damage and (z.type == "fan" or z.type == "grinder") then
                n = n + 1
                kinds[z.type] = (kinds[z.type] or 0) + 1
                fanZone = fanZone or z
            end
        end
    end
    return n, kinds
end

local jobs = {}
-- Silos' upper half is Ventilation (fans) or Chambers, at random: try seeds
-- until a run has fans, then stop.
for s = 1, 10 do jobs[#jobs + 1] = { "Region_Silos_Campaign", s } end

local function runJob(i)
    local job = jobs[i]
    if not job then
        -- Stand in a fan's blades for a second.
        if fanZone then
            P:SetNW2Int("gk_arena", 1)
            P:GodDisable() P:SetMoveType(MOVETYPE_WALK)
            P:SetPos(fanZone.shape.centre - Vector(0, 0, 36))
            local hp = P:Health()
            timer.Simple(1, function()
                log("one second in a fan's blades: health", hp, "->", P:Health(), "alive", tostring(P:Alive()), "(expect hurt or dead)")
                print("[GKTEST] DONE")
                timer.Simple(1, function() game.ConsoleCommand("quit\n") end)
            end)
        else
            log("no fan or grinder zone found in these runs")
            print("[GKTEST] DONE")
            timer.Simple(1, function() game.ConsoleCommand("quit\n") end)
        end
        return
    end
    local info = GK.Arena.Start(1, job[1], job[2])
    if not info then log(job[1], job[2], "failed to build") return runJob(i + 1) end
    P:SetNW2Int("gk_arena", 1)
    P:GodEnable()
    P:SetMoveType(MOVETYPE_NOCLIP)
    -- Climb: a jump up through each planned room so the stream builds them all.
    local steps = #info.plan
    for k = 1, steps do
        timer.Simple(k * 0.6, function()
            local z = info.spawn.z + (info.top - info.spawn.z) * k / steps
            P:SetPos(Vector(info.spawn.x, info.spawn.y, z))
            if GK.Arena.Stream then GK.Arena.Stream(1) end
        end)
    end
    timer.Simple(steps * 0.6 + 1.5, function()
        local n, kinds = liveMoving(1)
        local parts = {}
        for k, v in pairs(kinds) do parts[#parts + 1] = k .. "=" .. v end
        if n > 0 then jobs = { [i + 1] = nil } end -- found fans: stand in them next
        log(job[1], "seed", job[2], "rooms", steps, "| drones", count("gk_drone"), "bloodbugs", count("gk_bloodbug") - count("gk_drone"),
            "hoppers", count("gk_hopper"), "gasbags", count("gk_gasbag"), "| live fan/grinder zones", n, table.concat(parts, " "))
        runJob(i + 1)
    end)
end

hook.Add("PlayerInitialSpawn", "GK_HazTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_HazTest")
    P = ply
    timer.Simple(12, function()
        RunConsoleCommand("gk_tube_rise", "0")
        local ok, err = pcall(runJob, 1)
        if not ok then log("ERROR", err) print("[GKTEST] DONE") end
    end)
end)
