-- White Knuckle levels in Garry's Mod. Each converted level piece (see
-- tools/port_level.ps1) is a gk_level_piece entity plus its layout: the items
-- it had lying around. Best on a big open map like gm_flatgrass.
-- Admins: `gk_level` lists pieces, `gk_level <piece>` builds one under you.

GK.Levels = GK.Levels or { spawned = {} }

-- WK item names -> gKnuckle items (unknown ones are skipped for now).
-- White Knuckle item kinds (json "items[].kind", from the Item_* object names) -> gKnuckle
-- item classes (sh_items.lua). Kinds with no class here (notes, floppies, trinkets,
-- power cells, cocoa) are lore pickups WK has and we do not, and are left out.
CreateConVar("gk_item_settle", "1", { FCVAR_ARCHIVE }, "Rest loose room pickups on the floor below when a room spawns")
local ITEM_MAP = {
    rebar = "rebar", rubble = "brick", brick = "brick", grenade = "grenade",
    piton = "piton", autopiton = "autopiton", autodrillpiton = "autopiton",
    rope = "rebarrope", rebarrope = "rebarrope", ropebag = "rebarrope",
    beans = "beans", food = "foodbar", milk = "milk", pillbottle = "pills", injector = "injector",
    flashlight = "flashlight", flaregun = "flaregun", handgun = "revolver",
    ["10mm"] = "bullet", ["9mm"] = "bullet", blinkeye = "blinkeye",
    -- note, mesh, trinket, floppy, powercell, candycauldron, cocoa, pipewrench, cryogun:
    -- lore pickups WK has and we do not; left out.
}

-- studiomdl turns the SMD's +X into +Y (a 90° yaw), so compiled rooms sit
-- rotated relative to their layout json (written in SMD space). Every json
-- position goes through this to land in model space: (x, y) -> (-y, x).
local toModel = GK.LevelToModel   -- defined in shared.lua

function GK.ListLevelPieces()
    local out = {}
    for _, f in ipairs(file.Find("data_static/gknuckle/levels/*.json", "GAME")) do
        out[#out + 1] = string.StripExtension(f)
    end
    return out
end

function GK.ClearLevel()
    for _, ent in ipairs(GK.Levels.spawned) do
        if IsValid(ent) then ent:Remove() end
    end
    GK.Levels.spawned = {}
end

function GK.SpawnLevel(piece, origin)
    piece = string.lower(piece)
    local level = ents.Create("gk_level_piece")
    if not IsValid(level) then return end
    level:SetPiece(piece)
    level:SetPos(origin)
    level:Spawn()
    table.insert(GK.Levels.spawned, level)

    local layout = GK.LevelLayout(piece)
    -- Big rooms are several model parts; the piece entity draws the first.
    for i, part in ipairs(layout.parts or {}) do
        if i > 1 then
            local extra = ents.Create("prop_dynamic")
            extra:SetModel("models/gknuckle/levels/" .. part .. ".mdl")
            extra:SetPos(origin)
            extra:Spawn()
            table.insert(GK.Levels.spawned, extra)
        end
    end
    -- Ladders: WK marks them as tall handhold boxes named *ladder*; a gk_ladder
    -- volume on each face makes them walk-in climbable (sh_ladders.lua).
    for _, h in ipairs(layout.handholds or {}) do
        if h.mins and string.find(string.lower(h.name or ""), "ladder", 1, true) then
            local lo, hi = toModel(h.mins), toModel(h.maxs)
            local mins = Vector(math.min(lo.x, hi.x), math.min(lo.y, hi.y), math.min(lo.z, hi.z))
            local maxs = Vector(math.max(lo.x, hi.x), math.max(lo.y, hi.y), math.max(lo.z, hi.z))
            local size = maxs - mins
            if size.z >= 96 then
                local thinX = size.x <= size.y          -- the thin axis is the ladder's depth
                local width = thinX and size.y or size.x
                local centre = origin + (mins + maxs) / 2
                for _, sign in ipairs({ -1, 1 }) do
                    local lad = ents.Create("gk_ladder")
                    if not IsValid(lad) then break end
                    local face = thinX and Vector(sign, 0, 0) or Vector(0, sign, 0)
                    local half = thinX and size.x / 2 or size.y / 2
                    lad:SetPos(Vector(centre.x + face.x * half, centre.y + face.y * half, origin.z + mins.z))
                    lad:SetAngles(face:Angle())
                    lad:SetKeyValue("width", tostring(math.max(32, width)))
                    lad:SetKeyValue("height", tostring(size.z))
                    lad:Spawn()
                    table.insert(GK.Levels.spawned, lad)
                end
            end
        end
    end
    local WALL_ITEMS = { rope = true, rebar = true, rebarrope = true, piton = true, autopiton = true, autodrillpiton = true }
    for _, it in ipairs(layout.items or {}) do
        local class = ITEM_MAP[it.kind]
        if class then
            local ent = ents.Create(GK.ItemDef(class).worldClass or "gk_item")
            ent.GKItemClass = class
            -- Asleep on brand-new chunk collision: items sit where WK put them and
            -- only wake when touched (a room of items settling at once onto a
            -- fresh virtual mesh is the remaining vphysics-fatal candidate).
            ent.GK_Asleep = true
            local pos = origin + toModel(it.pos) + Vector(0, 0, 4)
            -- Loose pickups rest on whatever is under them: White Knuckle drops them with
            -- physics, but here they spawn asleep, so 70-odd hung in the air. Wall-mounted
            -- kinds (rope anchors, rebar, pitons) stay where the room put them.
            if not WALL_ITEMS[it.kind] and GetConVar("gk_item_settle"):GetBool() then
                local tr = util.TraceLine({ start = pos + Vector(0, 0, 8), endpos = pos - Vector(0, 0, 512), mask = MASK_SOLID,
                    filter = function(e) return e:IsWorld() or e:GetClass() == "gk_level_chunk" end })
                if tr.Hit and not tr.StartSolid then pos = tr.HitPos + Vector(0, 0, 4) end
            end
            ent:SetPos(pos)
            ent:SetAngles(Angle(0, (it.yaw or 0) + 90, 0))
            ent:Spawn()
            table.insert(GK.Levels.spawned, ent)
        end
    end
    return level, layout
end

-- Roguelite runs: a random climb built from White Knuckle's own generation
-- tables (data_static/gknuckle/regions.json, from tools/extract_regions.js):
-- the region's start room, then for each subregion group one subregion is
-- picked and 2-5 (its min/max) rooms drawn from it, each placed so its
-- entrance locator meets the previous room's exit locator. Rooms are reused as
-- rarely as possible, like the game. `gk_run <region>` (admin) builds one
-- under you; GK.GenerateRun returns the piece list for map tools.

local function loadRegions()
    if GK.Levels.regions then return GK.Levels.regions end
    local data = util.JSONToTable(file.Read("data_static/gknuckle/levels/../regions.json", "GAME")
        or file.Read("data_static/gknuckle/regions.json", "GAME") or "") or {}
    GK.Levels.regions = data
    return data
end

local function layoutOf(piece)
    return GK.LevelLayout(piece)
end

-- A Source map is ~31k units tall: rooms taller than one map (backdrop set
-- pieces) are skipped, and a run stops when the next room wouldn't fit.
local MAX_ROOM_HEIGHT, HEIGHT_BUDGET = 24000, 30000
local function heightOf(piece)
    local b = layoutOf(piece).bounds
    return b and (b.maxs[3] - b.mins[3]) or 2000
end
-- Rooms the climb proof (tools/climb_proof.js) shows cannot be climbed from entrance to exit
-- under gk_climb_mode 0 without items: never drawn into runs.
GK.RoomBlocklist = {
    m5_nest_trough_05 = true,        -- a 930 u climb up an open shaft with nothing in reach
    mx_chimney_looproom_01 = true,   -- the exit sits 1,000 u above any floor or wall in reach
}
local function usable(level)
    if GK.RoomBlocklist[level.piece] then return false end
    if not level.converted or not file.Exists("data_static/gknuckle/levels/" .. level.piece .. ".json", "GAME") then return false end
    local lay = layoutOf(level.piece)
    -- No bounds means the prefab had no geometry (effects-only "rooms"): skip.
    return lay.bounds ~= nil and heightOf(level.piece) <= MAX_ROOM_HEIGHT
end

-- Picks `count` rooms from `pool`, preferring ones not used yet this run.
-- Width: rooms drift sideways as they stack, and a run wider than its shaft puts
-- rooms in the sky walls. `used.__pieces` is the run so far; a candidate that would
-- make the planned run wider than used.__width (set by the caller) is passed over,
-- and if every candidate would, the draw stops.
local function fitsWidth(used, piece)
    if not used.__width then return true end
    local trial = {}
    for _, p in ipairs(used.__pieces or {}) do trial[#trial + 1] = p end
    trial[#trial + 1] = piece
    local _, mins, maxs = GK.PlanRun(trial, vector_origin)
    return (maxs.x - mins.x) <= used.__width and (maxs.y - mins.y) <= used.__width
end
local function draw(pool, count, used)
    local out = {}
    used.__pieces = used.__pieces or {}
    for _ = 1, count do
        local fresh = {}
        for _, lv in ipairs(pool) do if usable(lv) and not used[lv.piece] then fresh[#fresh + 1] = lv end end
        local from = #fresh > 0 and fresh or pool
        local candidates = {}
        for _, lv in ipairs(from) do if usable(lv) then candidates[#candidates + 1] = lv end end
        if #candidates == 0 then break end
        local pick
        while #candidates > 0 do
            local i = math.random(#candidates)
            if fitsWidth(used, candidates[i].piece) then pick = candidates[i] break end
            table.remove(candidates, i)
        end
        if not pick then break end
        if (used.__height or 0) + heightOf(pick.piece) + (used.__reserve or 0) > HEIGHT_BUDGET then break end
        used.__height = (used.__height or 0) + heightOf(pick.piece)
        used[pick.piece] = true
        used.__pieces[#used.__pieces + 1] = pick.piece
        out[#out + 1] = pick.piece
    end
    return out
end

-- Rooms a run must not stop short of when its region has them: TEETH's
-- service shaft at the top of Habitation (gk_teeth.lua), and WK's Haunted
-- Pier, where the apparitions are (sv_threats.lua). Earlier groups draw fewer
-- rooms if that's what it takes to leave height for them. For a subregion,
-- the height of its tallest usable room is kept, so whichever room the draw
-- picks there fits.
GK.MustReachRooms = { m3_habitation_shaft_to_pier = true }
GK.MustReachSubregions = { Subregion_Habitation_HauntedPier = true }
local function mustReachHeight(data, groups, from)
    local h = 0
    for gi = from, #groups do
        local tallest = 0
        for _, key in ipairs(groups[gi].subregions or {}) do
            local sub = data.subregions[key]
            for _, g in ipairs(sub and sub.groups or {}) do
                for _, lv in ipairs(g.levels or {}) do
                    if (GK.MustReachRooms[lv.piece] or GK.MustReachSubregions[key]) and usable(lv) then
                        tallest = math.max(tallest, heightOf(lv.piece))
                    end
                end
            end
        end
        h = h + tallest
    end
    return h
end

function GK.GenerateRun(regionKey, seed, widthBudget)
    local data = loadRegions()
    local region = data.regions and data.regions[regionKey]
    if not region then return nil, "unknown region " .. tostring(regionKey) end
    if seed then math.randomseed(seed) end
    local used, pieces = { __width = widthBudget }, {}
    used.__reserve = mustReachHeight(data, region.subregionGroups or {}, 1)
    for _, p in ipairs(draw(region.startLevels or {}, 1, used)) do pieces[#pieces + 1] = p end
    local groups = region.subregionGroups or {}
    for gi, group in ipairs(groups) do
        used.__reserve = mustReachHeight(data, groups, gi + 1)
        local options = {}
        for _, key in ipairs(group.subregions) do
            local sub = data.subregions[key]
            if sub then options[#options + 1] = sub end
        end
        if #options > 0 then
            local sub = options[math.random(#options)]
            local pool = {}
            for _, g in ipairs(sub.groups or {}) do for _, lv in ipairs(g.levels) do pool[#pool + 1] = lv end end
            for _, p in ipairs(draw(sub.startLevels or {}, 1, used)) do pieces[#pieces + 1] = p end
            local count = math.random(math.max(1, sub.minLevels or 1), math.max(sub.minLevels or 1, sub.maxLevels or 1))
            for _, p in ipairs(draw(pool, count, used)) do pieces[#pieces + 1] = p end
            for _, p in ipairs(draw(sub.endLevels or {}, 1, used)) do pieces[#pieces + 1] = p end
        end
    end
    used.__reserve = nil
    return pieces
end

-- A room's entrance or exit marker (SMD space, {x, y, z}), clamped into the room's own
-- bounds when it lies well outside them. Some White Knuckle rooms (Nest troughs, Chimney
-- shelves and transitions) carry their markers in the original scene's frame, thousands
-- of units off their geometry; stacking on those left 300 to 42,000 u of empty air between
-- rooms. Clamped, a run always continues from the top of the room it left.
local LOC_SLACK = 64
function GK.RoomLocator(lay, which)
    local list = which == "exit" and lay.exits or lay.entrances
    local l = list and list[1]
    if not l then return nil end
    local p, b = l.pos, lay.bounds
    if not b then return { p[1], p[2], p[3] } end
    -- 35 rooms (the Habitation service shaft, Nest hotzones, garbage chutes,
    -- Chimney spires...) came out of extraction with entrance and exit on the
    -- same spot, usually the origin. Stacked on that, every following room sat
    -- at the same height inside this one. A climb goes up: enter at the floor,
    -- leave at the top.
    local en, ex = lay.entrances and lay.entrances[1], lay.exits and lay.exits[1]
    if en and ex and en.pos[1] == ex.pos[1] and en.pos[2] == ex.pos[2] and en.pos[3] == ex.pos[3] then
        return { p[1], p[2], which == "exit" and b.maxs[3] or b.mins[3] }
    end
    local out = {}
    for k = 1, 3 do
        local lo, hi, v = b.mins[k], b.maxs[k], p[k]
        if v < lo - LOC_SLACK or v > hi + LOC_SLACK then v = math.Clamp(v, lo, hi) end
        out[k] = v
    end
    -- an exit pushed down into the room from far above sits on its top; an entrance on its floor
    if p[3] > b.maxs[3] + LOC_SLACK then out[3] = which == "exit" and b.maxs[3] or b.mins[3] end
    if p[3] < b.mins[3] - LOC_SLACK then out[3] = b.mins[3] end
    return out
end

-- Builds a list of pieces end to end from `origin`, entrance on exit.
-- Where each piece of a run lands (entrance on the previous exit) and the
-- run's overall world bounds, without spawning anything.
function GK.PlanRun(pieces, origin)
    local prevExit
    local plan = {}
    local mins, maxs = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, piece in ipairs(pieces) do
        local lay = layoutOf(piece)
        local entrance = GK.RoomLocator(lay, "entrance")
        local exit = GK.RoomLocator(lay, "exit")
        entrance = entrance and { pos = entrance }
        exit = exit and { pos = exit }
        local pos
        if prevExit and entrance then
            pos = prevExit - toModel(entrance.pos)
        else
            local lo = lay.bounds and lay.bounds.mins or { 0, 0, 0 }
            pos = (prevExit or origin) - Vector(0, 0, lo[3])
        end
        plan[#plan + 1] = { piece = piece, pos = pos }
        if lay.bounds then
            local lo, hi = lay.bounds.mins, lay.bounds.maxs
            -- Layout bounds are in SMD space; rotate into model space.
            local wlo, whi = pos + Vector(-hi[2], lo[1], lo[3]), pos + Vector(-lo[2], hi[1], hi[3])
            mins.x, mins.y, mins.z = math.min(mins.x, wlo.x), math.min(mins.y, wlo.y), math.min(mins.z, wlo.z)
            maxs.x, maxs.y, maxs.z = math.max(maxs.x, whi.x), math.max(maxs.y, whi.y), math.max(maxs.z, whi.z)
        end
        prevExit = exit and (pos + toModel(exit.pos)) or nil
    end
    if mins.x == math.huge then mins, maxs = origin, origin end
    return plan, mins, maxs
end

function GK.SpawnRun(pieces, origin)
    local plan = GK.PlanRun(pieces, origin)
    for _, p in ipairs(plan) do GK.SpawnLevel(p.piece, p.pos) end
    -- Where to put players: the first room's spawn marker, else above its entrance.
    local first = layoutOf(pieces[1] or "")
    local lo = first.bounds and first.bounds.mins or { 0, 0, 0 }
    local firstPos = origin - Vector(0, 0, lo[3])
    if first.spawn then return firstPos + toModel(first.spawn) + Vector(0, 0, 16) end
    local e = first.entrances and first.entrances[1]
    if e then return firstPos + toModel(e.pos) + Vector(0, 0, 48) end
    return origin + Vector(0, 0, 40)
end

concommand.Add("gk_run", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local data = loadRegions()
    if not args[1] then
        local names = {}
        for k in SortedPairs(data.regions or {}) do names[#names + 1] = k end
        local msg = "Regions: " .. table.concat(names, ", ")
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
        return
    end
    local pieces, err = GK.GenerateRun(args[1], tonumber(args[2]))
    if not pieces then if IsValid(ply) then ply:ChatPrint(err) end return end
    GK.ClearLevel()
    local base = IsValid(ply) and ply:GetPos() or vector_origin
    local tr = util.TraceLine({ start = base + Vector(0, 0, 32), endpos = base - Vector(0, 0, 4096), mask = MASK_SOLID_BRUSHONLY })
    local origin = (tr.Hit and tr.HitPos or base) + Vector(0, 0, 60)
    local spawnPos = GK.SpawnRun(pieces, origin)
    local msg = ("[gKnuckle] run: %s"):format(table.concat(pieces, " > "))
    if IsValid(ply) then ply:ChatPrint(msg) end
    print(msg)
    if IsValid(ply) then
        timer.Simple(0.2, function()
            if not IsValid(ply) then return end
            ply:SetPos(GK.FindSafeSpot(ply, spawnPos) or spawnPos)
        end)
    end
end)

-- Compiled gk_wk_ maps: the spawn point is a guess from the level's triangles,
-- so make sure players land on a real floor near it rather than inside a wall.
function GK.FindSafeSpot(ply, near)
    local mins, maxs = ply:OBBMins(), ply:OBBMaxs()
    local function fits(pos)
        local tr = util.TraceHull({ start = pos + Vector(0, 0, 600), endpos = pos - Vector(0, 0, 1500),
            mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
        if tr.StartSolid or not tr.Hit or tr.HitNormal.z < 0.7 then return nil end
        local stand = util.TraceHull({ start = tr.HitPos + Vector(0, 0, 2), endpos = tr.HitPos + Vector(0, 0, 2),
            mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
        if stand.StartSolid then return nil end
        return tr.HitPos + Vector(0, 0, 2)
    end
    local spot = fits(near)
    if spot then return spot end
    for r = 96, 1536, 96 do
        for a = 0, 330, 30 do
            local rad = math.rad(a)
            spot = fits(near + Vector(math.cos(rad) * r, math.sin(rad) * r, 0))
            if spot then return spot end
        end
    end
end

hook.Add("PlayerSpawn", "GK_WKSafeSpawn", function(ply)
    if not string.StartWith(game.GetMap(), "gk_wk_") then return end
    timer.Simple(0.1, function()
        if not IsValid(ply) or not ply:Alive() or ply.GK_SpawnFixed == CurTime() then return end
        local spot = GK.FindSafeSpot(ply, ply:GetPos())
        if spot then ply:SetPos(spot) end
    end)
end)

concommand.Add("gk_level", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end
    if not args[1] then
        local msg = "Level pieces: " .. table.concat(GK.ListLevelPieces(), ", ")
        if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
        return
    end
    GK.ClearLevel()
    local base = IsValid(ply) and ply:GetPos() or vector_origin
    local tr = util.TraceLine({ start = base + Vector(0, 0, 32), endpos = base - Vector(0, 0, 4096), mask = MASK_SOLID_BRUSHONLY })
    local origin = (tr.Hit and tr.HitPos or base) + Vector(0, 0, 60)
    local level = GK.SpawnLevel(args[1], origin)
    if IsValid(level) and IsValid(ply) then
        ply:SetPos(origin + Vector(0, 0, 40))
    end
end)
