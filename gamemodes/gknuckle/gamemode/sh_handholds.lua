-- White Knuckle's handholds in the rooms: the red pitons, rebar stubs, bars,
-- polyps and the rest WK lets you grab. Each room's layout json lists their
-- boxes (handholds[], in json space), but the room's collision is simplified
-- and often misses the small ones, so the mind-hands test the boxes directly
-- (GK.HandholdHit, used by gk_mind's TryGrip). Ladder boxes are left to
-- gk_ladder (sv_levels.lua).
-- Client: WK's red pitons glow red, like in the game.
AddCSLuaFile()

GK.Handholds = GK.Handholds or {}
local byPiece = {}

-- Layout json -> model space (same as sv_levels.lua's GK.LevelToModel, which
-- is server-only; this runs on the client too).
local function toModel(p) return Vector(-p[2], p[1], p[3]) end

-- A piece's handhold boxes in model space: { mins, maxs, piton = bool }.
local CELL = 256
local function boxesOf(piece)
    if byPiece[piece] then return byPiece[piece] end
    local lay = GK.LevelLayout(piece) -- cached, shared: read only (expands the compact "edges" ledges)
    local out = {}
    for _, h in ipairs(lay.handholds or {}) do
        local name = string.lower(h.name or "")
        if h.mins and h.maxs and not name:find("ladder", 1, true) then
            local lo, hi = toModel(h.mins), toModel(h.maxs)
            out[#out + 1] = {
                mins = Vector(math.min(lo.x, hi.x), math.min(lo.y, hi.y), math.min(lo.z, hi.z)),
                maxs = Vector(math.max(lo.x, hi.x), math.max(lo.y, hi.y), math.max(lo.z, hi.z)),
                piton = name:find("piton", 1, true) ~= nil or name:find("red", 1, true) ~= nil,
                kind = h.kind, -- "icy" (slips off), "breakable" (one use), "rope", or nil
                -- WK's cryoshot platforms (Handhold_Cryoshot_*): jump off one and it
                -- shatters in an explosive boost (HandholdModule_JumpBoost).
                boost = name:find("cryoshot", 1, true) ~= nil,
            }
        end
    end
    -- Rooms now carry thousands of ledge boxes: bucket them into a coarse grid
    -- (by box centre; CELL is far bigger than any box) so a grip only tests the
    -- boxes near its short ray, and keep the pitons apart for the glow.
    local grid, pitons = {}, {}
    for _, b in ipairs(out) do
        local c = (b.mins + b.maxs) * 0.5
        local key = math.floor(c.x / CELL) .. ":" .. math.floor(c.y / CELL) .. ":" .. math.floor(c.z / CELL)
        grid[key] = grid[key] or {}
        table.insert(grid[key], b)
        if b.piton then pitons[#pitons + 1] = b end
    end
    out.grid, out.pitons = grid, pitons
    byPiece[piece] = out
    return out
end
GK.Handholds.BoxesOf = boxesOf

-- Ray/box slab test: distance along the ray, or nil.
local function rayBox(o, d, mins, maxs, maxDist)
    local tmin, tmax = 0, maxDist
    for _, ax in ipairs({ "x", "y", "z" }) do
        local od, dd = o[ax], d[ax]
        if math.abs(dd) < 1e-6 then
            if od < mins[ax] or od > maxs[ax] then return nil end
        else
            local t1, t2 = (mins[ax] - od) / dd, (maxs[ax] - od) / dd
            if t1 > t2 then t1, t2 = t2, t1 end
            tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
            if tmin > tmax then return nil end
        end
    end
    return tmin
end

-- Icy, breakable and heated holds as special holds for the mind-hands (GK.HoldTick in
-- sv_hazards.lua): one per box per placed room piece, so a broken hold stays
-- broken in that room only. WK: ice slips you off after about 3 s; a
-- breakable hold crumbles under you.
local specials = setmetatable({}, { __mode = "k" }) -- piece entity -> { [box] = hold }
local SLIP, CRUMBLE = 3, 1.5
function GK.HandholdSpecial(piece, box)
    if not box or not (box.kind == "icy" or box.kind == "breakable" or box.kind == "heat") or not IsValid(piece) then return nil end
    specials[piece] = specials[piece] or {}
    local h = specials[piece][box]
    if not h then
        local c = piece:GetPos() + (box.mins + box.maxs) * 0.5
        -- Heated surfaces (WK Surface_Heated) burn the hands that hold them: a
        -- damage hold (GK.HoldTick: 5 a second from the first moment).
        h = box.kind == "heat" and { kind = "damage", maxHold = 0, damage = 5 }
            or { kind = box.kind, maxHold = box.kind == "icy" and SLIP or CRUMBLE, damage = 0 }
        h.shape = { sphere = true, centre = c, r = (box.maxs - box.mins):Length() * 0.5 + 6 }
        specials[piece][box] = h
    end
    return h
end
local function broken(piece, box)
    local t = specials[piece]
    return t and t[box] and t[box].broken
end

-- The nearest WK handhold the ray hits within maxDist: hit position, distance,
-- and which box on which piece (for icy/breakable holds).
local PAD = Vector(3, 3, 3) -- a little forgiving, they're small
function GK.HandholdHit(origin, dir, maxDist)
    local best, bestT, bestBox, bestPiece
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        local p = piece:GetPos()
        -- Only pieces near enough to matter (their bounds from the layout).
        local b = GK.LevelBoundsWorld and GK.LevelBoundsWorld(piece)
        if not b or (origin.x > b.mins.x - maxDist and origin.x < b.maxs.x + maxDist
            and origin.y > b.mins.y - maxDist and origin.y < b.maxs.y + maxDist
            and origin.z > b.mins.z - maxDist and origin.z < b.maxs.z + maxDist) then
            local o = origin - p
            local grid = boxesOf(piece:GetPiece()).grid
            -- The cells the ray's span touches, one cell of slack for box size.
            local e = o + dir * maxDist
            local x0, x1 = math.floor(math.min(o.x, e.x) / CELL) - 1, math.floor(math.max(o.x, e.x) / CELL) + 1
            local y0, y1 = math.floor(math.min(o.y, e.y) / CELL) - 1, math.floor(math.max(o.y, e.y) / CELL) + 1
            local z0, z1 = math.floor(math.min(o.z, e.z) / CELL) - 1, math.floor(math.max(o.z, e.z) / CELL) + 1
            for gx = x0, x1 do for gy = y0, y1 do for gz = z0, z1 do
                local cell = grid[gx .. ":" .. gy .. ":" .. gz]
                if cell then
                    for _, box in ipairs(cell) do
                        local t = rayBox(o, dir, box.mins - PAD, box.maxs + PAD, maxDist)
                        -- WK ice walls (Surface_Ice) cannot be held at all.
                        if t and (not bestT or t < bestT) and box.kind ~= "ice" and not broken(piece, box) then
                            best, bestT, bestBox, bestPiece = origin + dir * t, t, box, piece
                        end
                    end
                end
            end end end
        end
    end
    return best, bestT, bestBox, bestPiece
end

-- The kind of WK hold box (if any) right at a point on a surface, e.g. "ice"
-- for a frozen wall the mind-hands may not grip even in grip-anywhere mode.
local SLACK = Vector(4, 4, 4)
function GK.HandholdKindAt(pos)
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        local o = pos - piece:GetPos()
        local grid = boxesOf(piece:GetPiece()).grid
        local gx, gy, gz = math.floor(o.x / CELL), math.floor(o.y / CELL), math.floor(o.z / CELL)
        for x = gx - 1, gx + 1 do for y = gy - 1, gy + 1 do for z = gz - 1, gz + 1 do
            for _, box in ipairs(grid[x .. ":" .. y .. ":" .. z] or {}) do
                if box.kind and o:WithinAABox(box.mins - SLACK, box.maxs + SLACK) then return box.kind end
            end
        end end end
    end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")
    local RANGE = 1600
    -- Red pitons glow, as in WK. Draws the nearest ones only.
    hook.Add("PostDrawTranslucentRenderables", "GK_PitonGlow", function(depth, sky)
        if depth or sky then return end
        local eye = EyePos()
        local t = CurTime()
        render.SetMaterial(glow)
        local drawn = 0
        for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
            local p = piece:GetPos()
            for i, box in ipairs(boxesOf(piece:GetPiece()).pitons) do
                do
                    local c = p + (box.mins + box.maxs) * 0.5
                    if c:DistToSqr(eye) < RANGE * RANGE then
                        local pulse = 0.8 + math.sin(t * 2 + i) * 0.2
                        render.DrawSprite(c, 26 * pulse, 26 * pulse, Color(255, 30, 20, 200))
                        render.DrawSprite(c, 9, 9, Color(255, 140, 120, 255))
                        drawn = drawn + 1
                        if drawn > 120 then return end
                    end
                end
            end
        end
    end)
end
