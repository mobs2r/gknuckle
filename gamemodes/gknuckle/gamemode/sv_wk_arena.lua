-- Arena shafts for gk_style: three sealed sky boxes where fresh White Knuckle
-- runs are generated at round time. Geometry/plumbing only; who goes, squads,
-- caps and round rules live in sv_arena.lua (gameplay) via the GK_VacuumPull hook.
--
--   GK.Arena.Free()                     -> index of an idle arena, or nil
--   GK.Arena.Start(index, region, seed) -> info { index, region, seed, pieces, spawn, bounds = {mins, maxs}, top, bottom, ents, gas }
--                                         region nil = random region from WK's tables
--   GK.Arena.Clear(index)               -> removes the run and its gas
--   GK.Arena.SetGasHeight(index, z)     -> the gas plane (gk_gas) moves to world z; it damages anyone
--                                         below it inside the arena at gk_gas_damage per second
--   GK.Arena.Get(index) / GK.Arena.Of(ply) / GK.Arena.Pocket(index)
--   hooks GK_ArenaBuilt(info), GK_ArenaCleared(index), GK_ArenaRoomSpawned(info, n), GK_ArenaRoomRemoved(info, n)
--
-- Rooms stream like WK's WorldLoader: the whole run is planned up front (so
-- bounds, top and the gas footprint are known), but only the start room plus
-- gk_arena_ahead rooms exist at first. More appear when the leading player
-- reaches the last one; rooms far below the lowest living player and under the
-- gas are removed.

GK.Arena = GK.Arena or {}
local Arena = GK.Arena
Arena.runs = Arena.runs or {}

CreateConVar("gk_gas_damage", "6", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Damage per second to players below an arena's gas plane")
local cvAhead = CreateConVar("gk_arena_ahead", "3", FCVAR_ARCHIVE, "Rooms kept built ahead of the leading player (WK: 3 beyond the current)")
local cvBehind = CreateConVar("gk_arena_behind", "2", FCVAR_ARCHIVE, "Rooms kept below the lowest living player before old ones are removed")

-- Arena shafts: from data_static/gknuckle/hub.json (written with the map), with
-- gk_arena_N info_targets in the map as a fallback for the centre points.
function Arena.Layout()
    if Arena.layout then return Arena.layout end
    local hub = util.JSONToTable(file.Read("data_static/gknuckle/hub.json", "GAME") or "") or {}
    local list = {}
    for _, a in ipairs(hub.arenas or {}) do
        list[a.index] = { index = a.index, center = Vector(a.center[1], a.center[2], 0), half = a.half, bottom = a.bottom, top = a.top }
    end
    if #list == 0 then
        for _, ent in ipairs(ents.FindByName("gk_arena_*")) do
            local i = tonumber(string.match(ent:GetName(), "(%d+)$"))
            if i then list[i] = { index = i, center = Vector(ent:GetPos().x, ent:GetPos().y, 0), half = 4800, bottom = ent:GetPos().z, top = ent:GetPos().z + 30000 } end
        end
    end
    Arena.layout = list
    Arena.hub = hub
    return list
end

function Arena.Count() return #Arena.Layout() end
function Arena.Get(index) return Arena.runs[index] end

function Arena.Free()
    for i = 1, Arena.Count() do
        if not Arena.runs[i] then return i end
    end
end

-- Which arena a player is standing in (by footprint), 0 if none.
function Arena.Of(ply)
    local p = ply:GetPos()
    for i, a in pairs(Arena.Layout()) do
        if math.abs(p.x - a.center.x) <= a.half and math.abs(p.y - a.center.y) <= a.half then return i end
    end
    return 0
end
GK.ArenaOf = GK.ArenaOf or function(ply) return Arena.Of(ply) end

-- Pocket chambers (break rooms off in the void above the hub), from hub.json.
function Arena.Pocket(index)
    Arena.Layout()
    local p = Arena.hub and Arena.hub.pockets and Arena.hub.pockets[index]
    if not p then return nil end
    return { index = index, center = Vector(p.center[1], p.center[2], p.center[3]), half = p.half, height = p.height }
end

-- Regions that make a full run (not segments, breakrooms or dev tables). WK's Abyss
-- regions are left out: their areas are 20,000-35,000 units tall with backdrop, so a
-- stacked run never fits a shaft. Region_Dusk (ours, regions.json) is the Abyss as a
-- single-room stage instead: one whole room that fits, climbed from its start to its
-- top as listed in data_static/gknuckle/dusk.json (tools/make_dusk_stage.js).
Arena.RunRegions = {
    "Region_Silos_Campaign", "Region_Silos_Endless",
    "Region_Pipeworks_Campaign", "Region_Pipeworks_Endless",
    "Region_Habitation_Campaign", "Region_Habitation_Endless",
    "Region_Nest_Campaign", "Region_Nest_Endless",
    "Region_Chimney_Endless", "Region_Ladder_Endless",
    "Region_Dusk",
}

-- Single-room dusk stages: piece -> { start, top } in layout (SMD) space.
function Arena.DuskRooms()
    if not Arena.dusk then
        local d = util.JSONToTable(file.Read("data_static/gknuckle/dusk.json", "GAME") or "") or {}
        Arena.dusk = d.rooms or {}
    end
    return Arena.dusk
end
function Arena.RandomRegion()
    local data = util.JSONToTable(file.Read("data_static/gknuckle/regions.json", "GAME") or "") or {}
    local keys = {}
    for _, k in ipairs(Arena.RunRegions) do
        if data.regions and data.regions[k] then keys[#keys + 1] = k end
    end
    return keys[math.random(#keys)]
end

local function layoutOf(piece)
    return GK.LevelLayout(piece)
end

-- World-space bounds of a layout placed at pos (layout json is in SMD space).
local function boundsAt(lay, pos)
    if not lay.bounds then return nil end
    local lo, hi = lay.bounds.mins, lay.bounds.maxs
    return { mins = pos + Vector(-hi[2], lo[1], lo[3]), maxs = pos + Vector(-lo[2], hi[1], hi[3]) }
end

-- World-space bounds of a placed level piece from its layout json.
function GK.LevelBoundsWorld(ent)
    return boundsAt(layoutOf(ent:GetPiece()), ent:GetPos())
end

-- Spawn room n of a run (everything SpawnLevel adds belongs to that room).
local function spawnRoom(info, n)
    local step = info.plan[n]
    if not step or info.rooms[n] ~= nil then return end
    local before = #GK.Levels.spawned
    GK.SpawnLevel(step.piece, step.pos)
    local list = {}
    for i = before + 1, #GK.Levels.spawned do
        list[#list + 1] = GK.Levels.spawned[i]
        info.ents[#info.ents + 1] = GK.Levels.spawned[i]
    end
    info.rooms[n] = { ents = list, bounds = boundsAt(layoutOf(step.piece), step.pos) or { mins = step.pos, maxs = step.pos } }
    info.built = math.max(info.built, n)
    hook.Run("GK_ArenaRoomSpawned", info, n)
end

local function removeRoom(info, n)
    local room = info.rooms[n]
    if not room then return end
    for _, e in ipairs(room.ents) do
        if IsValid(e) then e:Remove() end
    end
    info.rooms[n] = false  -- gone for good
    hook.Run("GK_ArenaRoomRemoved", info, n)
end

-- Players alive inside this arena's footprint.
local function playersIn(index)
    local out = {}
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and Arena.Of(ply) == index then out[#out + 1] = ply end
    end
    return out
end

-- Planned bounds of room n (built or not).
local function roomBounds(info, n)
    local room = info.rooms[n]
    if room then return room.bounds end
    return boundsAt(layoutOf(info.plan[n].piece), info.plan[n].pos)
end

-- Streaming: build ahead of the leader, drop rooms well below everyone.
function Arena.Stream(index)
    local info = Arena.runs[index]
    if not info then return end
    local plys = playersIn(index)
    if #plys == 0 then return end
    local highest, lowest = -math.huge, math.huge
    for _, p in ipairs(plys) do
        highest = math.max(highest, p:GetPos().z)
        lowest = math.min(lowest, p:GetPos().z)
    end
    -- The leader's room: the first room whose top is above them.
    local lead = #info.plan
    for n = 1, #info.plan do
        local b = roomBounds(info, n)
        if b and highest < b.maxs.z - 64 then lead = n break end
    end
    for n = 1, math.min(#info.plan, lead + cvAhead:GetInt()) do
        if info.rooms[n] == nil then spawnRoom(info, n) end
    end
    -- Rooms below the gas and more than gk_arena_behind rooms under the lowest
    -- living player go away.
    local lowRoom = #info.plan
    for n = 1, #info.plan do
        local b = roomBounds(info, n)
        if b and lowest < b.maxs.z then lowRoom = n break end
    end
    local gasZ = IsValid(info.gas) and info.gas:GetGasHeight() or -math.huge
    for n = 1, lowRoom - cvBehind:GetInt() - 1 do
        local room = info.rooms[n]
        if room and room.bounds.maxs.z < gasZ then removeRoom(info, n) end
    end
end

-- Where players actually land. The first room's Unity spawn marker can hang in the
-- air (the game stood a start platform there that the prefab does not carry), so once
-- the room is built the spawn is settled onto solid floor with a player-hull trace:
-- marker, then the entrance, then the room's floor point, nearest floor first.
local HULL_MINS, HULL_MAXS = Vector(-16, -16, 0), Vector(16, 16, 72)
-- Only the room collision and the world count: an item lying on the marker is not a wall.
local function solidOnly(ent) return ent:IsWorld() or ent:GetClass() == "gk_level_chunk" or ent:GetClass() == "gk_level_piece" end
local function settle(pos, reach)
    local function drop(from)
        local tr = util.TraceHull({ start = from, endpos = from - Vector(0, 0, reach), mins = HULL_MINS, maxs = HULL_MAXS, mask = MASK_PLAYERSOLID, filter = solidOnly })
        if tr.StartSolid or not tr.Hit then return nil end
        return tr.HitPos + Vector(0, 0, 2)
    end
    return drop(pos + Vector(0, 0, 64)) or drop(pos)
end
function Arena.SettleSpawn(info)
    local step = info.plan[1]
    local lay = layoutOf(step.piece)
    local cands = {}
    -- Dusk start: a platform over open air, so look round it (up to 256 u) for a spot where
    -- the whole player hull stands on floor, never falling back to the room's origin markers.
    if info.duskStart then
        local function firm(p)
            for _, c in ipairs({ Vector(-14, -14, 0), Vector(14, -14, 0), Vector(-14, 14, 0), Vector(14, 14, 0) }) do
                local tr = util.TraceLine({ start = p + c + Vector(0, 0, 4), endpos = p + c - Vector(0, 0, 12), mask = MASK_PLAYERSOLID, filter = solidOnly })
                if not tr.Hit then return false end
            end
            return true
        end
        for r = 0, 256, 32 do
            for a = 0, (r == 0 and 0 or 330), 30 do
                local o = info.duskStart + Vector(math.cos(math.rad(a)) * r, math.sin(math.rad(a)) * r, 0)
                local p = settle(o, 160)
                if p and p.z > info.duskStart.z - 112 and firm(p) then return p, "dusk", r end
            end
        end
    end
    if lay.spawn then cands[#cands + 1] = { "marker", step.pos + GK.LevelToModel(lay.spawn) + Vector(0, 0, 16) } end
    local entL = GK.RoomLocator(lay, "entrance")
    if entL then cands[#cands + 1] = { "entrance", step.pos + GK.LevelToModel(entL) + Vector(0, 0, 48) } end
    if lay.floor then cands[#cands + 1] = { "floor", step.pos + GK.LevelToModel(lay.floor) + Vector(0, 0, 16) } end
    for _, reach in ipairs({ 160, 1024, 8192 }) do
        for _, c in ipairs(cands) do
            local p = settle(c[2], reach)
            if p then return p, c[1], reach end
        end
    end
    return info.spawn, "unsettled", 0
end

function Arena.Start(index, region, seed)
    local a = Arena.Layout()[index]
    if not a then return nil, "no arena " .. tostring(index) end
    if Arena.runs[index] then Arena.Clear(index) end
    region = region or Arena.RandomRegion()

    -- Plan the whole run first, centred on the shaft (runs drift sideways as
    -- rooms stack), so bounds and the top are known before anything exists. A run
    -- wider than the shaft would put rooms inside the sky walls (Pipeworks endless,
    -- seed 6, put the start room in the wall): draw again with the next seed.
    local pieces, err, origin, plan, mins, maxs
    local trySeed = seed
    for attempt = 1, 6 do
        pieces, err = GK.GenerateRun(region, trySeed, 2 * a.half - 128)   -- drawn to fit the shaft; the redraw below is the safety net
        if not pieces or #pieces == 0 then return nil, err or ("no rooms for " .. tostring(region)) end
        origin = Vector(a.center.x, a.center.y, a.bottom + 64)
        local _, pmins, pmaxs = GK.PlanRun(pieces, origin)
        origin = origin + Vector(a.center.x - (pmins.x + pmaxs.x) / 2, a.center.y - (pmins.y + pmaxs.y) / 2, 0)
        plan, mins, maxs = GK.PlanRun(pieces, origin)
        -- Rooms can stack lower than the first room's floor (exits inside a room, next room
        -- hanging below): lift the whole run so its lowest geometry stays on the shaft floor,
        -- inside the arena's sky box (Nest Endless dipped 700 u below it).
        if mins.z < a.bottom + 64 - 1 then
            origin = origin + Vector(0, 0, (a.bottom + 64) - mins.z)
            plan, mins, maxs = GK.PlanRun(pieces, origin)
        end
        local fits = (maxs.x - mins.x) <= 2 * a.half - 128 and (maxs.y - mins.y) <= 2 * a.half - 128
        if fits then break end
        print(("[gKnuckle] arena %d: %s seed %s run is %.0f x %.0f, wider than the shaft; redrawing"):format(index, region, tostring(trySeed), maxs.x - mins.x, maxs.y - mins.y))
        trySeed = (trySeed or math.random(1, 1e6)) + 1
    end
    seed = trySeed

    -- Top of the run: the last room's exit locator.
    local top = maxs.z
    local last = plan[#plan]
    local lastLay = layoutOf(last.piece)
    local exL = GK.RoomLocator(lastLay, "exit")
    if exL then top = (last.pos + GK.LevelToModel(exL)).z end

    -- Where players start: the first room's spawn marker, else above its entrance.
    local first = layoutOf(plan[1].piece)
    local spawn
    if first.spawn then spawn = plan[1].pos + GK.LevelToModel(first.spawn) + Vector(0, 0, 16)
    elseif GK.RoomLocator(first, "entrance") then spawn = plan[1].pos + GK.LevelToModel(GK.RoomLocator(first, "entrance")) + Vector(0, 0, 48)
    else spawn = origin + Vector(0, 0, 40) end

    -- A dusk stage is one Abyss room whose markers sit at its origin: start at the bottom
    -- of its climb and finish above its highest holds instead.
    local dusk = #plan == 1 and Arena.DuskRooms()[plan[1].piece]
    local duskStart
    if dusk then
        duskStart = plan[1].pos + GK.LevelToModel(dusk.start) + Vector(0, 0, 16)
        spawn = duskStart
        top = (plan[1].pos + GK.LevelToModel(dusk.top)).z
    end

    local info = { index = index, region = region, seed = seed, pieces = pieces, plan = plan, spawn = spawn,
        bounds = { mins = mins, maxs = maxs }, top = top, bottom = mins.z, ents = {}, rooms = {}, built = 0, started = CurTime(),
        duskStart = duskStart }
    Arena.runs[index] = info
    SetGlobal2String("gk_arena_region_" .. index, region)   -- cl_regionsky.lua reads this

    -- Gas plane, parked below the run until gameplay raises it.
    local gas = ents.Create("gk_gas")
    gas:SetPos(Vector(a.center.x, a.center.y, mins.z - 200))
    gas:SetArena(index)
    gas:SetGasMins(Vector(mins.x - 256, mins.y - 256, 0))
    gas:SetGasMaxs(Vector(maxs.x + 256, maxs.y + 256, 0))
    gas:SetGasHeight(mins.z - 200)
    gas:Spawn()
    info.gas = gas
    info.ents[#info.ents + 1] = gas
    GK.Levels.spawned[#GK.Levels.spawned + 1] = gas

    -- The start room and the first few ahead; the rest stream in.
    for n = 1, math.min(#plan, 1 + cvAhead:GetInt()) do spawnRoom(info, n) end
    -- The rooms' collision exists now (chunks build inside Initialize): put the spawn on the floor.
    local raw = info.spawn
    local settled, how, reach = Arena.SettleSpawn(info)
    info.spawnRaw, info.spawnHow = raw, how
    info.spawn = settled
    if how ~= "marker" or reach > 160 then print(("[gKnuckle] arena %d: spawn settled via %s (reach %d), moved %.0f u"):format(index, how, reach, raw:Distance(settled))) end
    timer.Create("GK_ArenaStream" .. index, 0.5, 0, function() Arena.Stream(index) end)

    print(("[gKnuckle] arena %d: %s seed %s, %d rooms planned, %d built"):format(index, region, tostring(seed), #plan, info.built))
    hook.Run("GK_ArenaBuilt", info)
    return info
end

function Arena.Clear(index)
    local info = Arena.runs[index]
    if not info then return end
    timer.Remove("GK_ArenaStream" .. index)
    for _, e in ipairs(info.ents) do
        if IsValid(e) then e:Remove() end
    end
    local keep = {}
    for _, e in ipairs(GK.Levels.spawned) do if IsValid(e) then keep[#keep + 1] = e end end
    GK.Levels.spawned = keep
    Arena.runs[index] = nil
    SetGlobal2String("gk_arena_region_" .. index, "")
    hook.Run("GK_ArenaCleared", index)
end

function Arena.SetGasHeight(index, z)
    local info = Arena.runs[index]
    if info and IsValid(info.gas) then info.gas:SetGasHeight(z) end
end

-- Admin helpers for testing.
concommand.Add("gk_arena_start", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local index = tonumber(args[1]) or Arena.Free() or 1
    local info, err = Arena.Start(index, args[2], tonumber(args[3]))
    local msg = info and ("[gKnuckle] arena %d: %s (%d rooms, top z %d)"):format(index, info.region, #info.pieces, info.top) or ("[gKnuckle] " .. tostring(err))
    if IsValid(ply) then ply:ChatPrint(msg) end
    print(msg)
    if info and IsValid(ply) then
        timer.Simple(0.2, function() if IsValid(ply) then ply:SetPos(GK.FindSafeSpot(ply, info.spawn) or info.spawn) end end)
    end
end)
concommand.Add("gk_arena_clear", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    Arena.Clear(tonumber(args[1]) or 1)
end)
concommand.Add("gk_arena_gas", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    Arena.SetGasHeight(tonumber(args[1]) or 1, tonumber(args[2]) or 0)
end)
