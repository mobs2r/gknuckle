-- Habitation's scripted presences, placed where White Knuckle places them.
--   Apparitions  DEN_Apparition in the Habitation Pier rooms (and the comms
--                array), from data_static/gknuckle/ghosts.json (gKnuckle's own
--                tools/extract_ghosts.js reads them from WK's prefabs). Each one
--                shows with WK's UT_SpawnChance (0.775) and goes when the room goes.
--   The Face     DEN_Face, with Abyss runs (below).
--   The ladder nightmare, with ladder runs (below).
-- gk_ghosts 0 / gk_face 0 / gk_laddernightmare 0 turn them off.

local cvGhosts = CreateConVar("gk_ghosts", "1", FCVAR_ARCHIVE, "Show WK's Habitation apparitions in runs")

local ghosts
local function ghostData()
    if ghosts == nil then
        ghosts = util.JSONToTable(file.Read("data_static/gknuckle/ghosts.json", "GAME") or "") or {}
    end
    return ghosts
end

function GK.SpawnGhost(pos, g)
    local e = ents.Create("gk_ghost")
    if not IsValid(e) then return end
    e:SetPos(pos)
    e:SetSprite(math.random(1, 4))
    e:SetSize(g and g.scale or 1)
    e:SetWander((g and g.wander or 118) / 2) -- WK's perlin offset is -0.5..0.5 of wanderAmount
    e:SetSpeed(g and g.speed or 0.1)
    e:Spawn()
    return e
end

hook.Add("GK_ArenaRoomSpawned", "GK_RoomGhosts", function(info, n)
    if not cvGhosts:GetBool() then return end
    local room = info.rooms and info.rooms[n]
    local step = info.plan and info.plan[n]
    if not room or not step then return end
    local list = ghostData()[step.piece]
    if not list then return end
    timer.Simple(0.3, function()
        if not info.rooms or info.rooms[n] ~= room then return end
        for _, g in ipairs(list) do
            if math.random() <= (g.chance or 1) then
                local e = GK.SpawnGhost(step.pos + GK.LevelToModel(g.pos), g)
                if IsValid(e) then
                    room.ents[#room.ents + 1] = e
                    info.ents[#info.ents + 1] = e
                end
            end
        end
    end)
end)

-- The Face. WK puts it in the Abyss (M4_Abyss_Endless_Intro): it's waiting
-- below when the region starts and follows the climb from there. Here it comes
-- with any run whose region is an Abyss one (or Region_Dusk, the Abyss as a
-- single-room stage), 60 m under the start (WK's dive
-- distance), after whoever in that run is nearest. It goes with the run.
-- gk_face 0 keeps it out of runs (gk_face_summon still calls it up).
local cvFace = CreateConVar("gk_face", "1", FCVAR_ARCHIVE, "The Face hunts Abyss runs")

hook.Add("GK_ArenaRoomSpawned", "GK_RoomFace", function(info, n)
    if n ~= 1 or not cvFace:GetBool() then return end
    local region = tostring(info.region or "")
    if not (region:find("Abyss") or region:find("Dusk")) then return end -- WK's Abyss, and our single-room Dusk stage of it
    timer.Simple(1, function()
        if not info.rooms or not info.rooms[1] then return end
        local players = {}
        for _, p in ipairs(player.GetAll()) do
            if GK.ArenaOf and GK.ArenaOf(p) == info.index then players[p] = true end
        end
        local hard = false
        for p in pairs(players) do if GK.RunMode and GK.RunMode(p) == "hard" then hard = true end end
        local f = GK.SpawnFace(info.spawn or info.plan[1].pos, { players = next(players) and players or nil, hard = hard })
        if IsValid(f) then info.ents[#info.ents + 1] = f end
    end)
end)

-- The ladder nightmare (DEN_LadderNightmare, gk_laddernightmare.lua). WK only
-- has it in the endless ladder climb (Region_Ladder_Endless): it's placed in
-- the intro room, and triggers in the 500 m, 1000 m, 1500 m and loop rooms
-- (UT_LadderNightmare_Controller) wake it up step by step. Here it comes with a
-- ladder run, 30 m over its start, and the same rooms set it as a climber gets
-- into them. gk_laddernightmare 0 keeps it out.
local cvNightmare = CreateConVar("gk_laddernightmare", "1", FCVAR_ARCHIVE, "The ladder nightmare haunts ladder runs")
local M = 39.37
GK.NightmareRooms = {
    m3_habitation_ladderwarp_500m_01 = { breathing = true },
    m3_habitation_ladderwarp_1000m_01 = { offset = 22 },
    m3_habitation_ladderwarp_1500m_01 = { offset = 19, attack = true },
    m3_habitation_ladderwarp_loop = { offset = 35, breathing = false, attack = false },
}

local function inBounds(b, p)
    if not b then return false end
    local q = p:GetPos()
    return q.x >= b.mins.x and q.x <= b.maxs.x and q.y >= b.mins.y and q.y <= b.maxs.y and q.z >= b.mins.z and q.z <= b.maxs.z
end

hook.Add("GK_ArenaRoomSpawned", "GK_RoomNightmare", function(info, n)
    if n ~= 1 or not cvNightmare:GetBool() then return end
    if not tostring(info.region or ""):find("Ladder") then return end
    timer.Simple(1, function()
        if not info.rooms or not info.rooms[1] then return end
        local players = {}
        for _, p in ipairs(player.GetAll()) do
            if GK.ArenaOf and GK.ArenaOf(p) == info.index then players[p] = true end
        end
        local e = ents.Create("gk_laddernightmare")
        if not IsValid(e) then return end
        e.Players = next(players) and players or nil
        e:SetPos((info.spawn or info.plan[1].pos) + Vector(0, 0, 30 * M))
        e:Spawn()
        info.ents[#info.ents + 1] = e
        info.nightmare = e
        info.nightmareDone = {}
    end)
end)

-- Room triggers: the first climber into one of those rooms sets it.
timer.Create("GK_NightmareRooms", 0.5, 0, function()
    if not GK.Rounds then return end
    for index, a in pairs(GK.Rounds.arenas or {}) do
        local info = a.info
        local e = info and info.nightmare
        if IsValid(e) and info.rooms then
            for n, room in pairs(info.rooms) do
                local step = info.plan[n]
                local set = step and GK.NightmareRooms[step.piece]
                if set and not info.nightmareDone[n] then
                    for _, p in ipairs(a.players or {}) do
                        if IsValid(p) and p:Alive() and inBounds(room.bounds, p) then
                            info.nightmareDone[n] = true
                            e:Configure(set)
                            break
                        end
                    end
                end
            end
        end
    end
end)
