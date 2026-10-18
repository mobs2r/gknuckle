-- White Knuckle's room lamps. The converter drops Unity lights, so runs were lit only by
-- the shaft floodlights; extract_hazards.js now writes each room's point lights into its
-- layout json ("lights": x,y,z, r,g,b, range, intensity per lamp, json space). This draws
-- the nearest few as dynamic lights, client side only, so a room reads the way WK lit it.
local cv = CreateClientConVar("gk_roomlights", "1", true, false, "Draw White Knuckle's room lamps as dynamic lights")
local cvMax = CreateClientConVar("gk_roomlights_max", "10", true, false, "How many room lamps to light at once")
local RANGE2 = 2200 * 2200
local cache = {}   -- piece -> { {pos, col, size, bright}, ... } in model space

local function lampsOf(piece)
    local list = cache[piece]
    if list then return list end
    list = {}
    local lay = GK.LevelLayout(piece)
    local L = lay.lights
    if L then
        for i = 1, #L - 7, 8 do
            list[#list + 1] = {
                pos = GK.LevelToModel({ L[i], L[i + 1], L[i + 2] }),
                col = Color(math.Clamp(L[i + 3] * 255, 0, 255), math.Clamp(L[i + 4] * 255, 0, 255), math.Clamp(L[i + 5] * 255, 0, 255)),
                size = math.Clamp(L[i + 6], 120, 900),
                bright = math.Clamp(L[i + 7], 0.5, 5),
            }
        end
    end
    -- Rooms that export no lamps (86 of the run rooms) were lit only by the shaft floodlights
    -- every 3000 u and read as black: give them a column of soft warm lamps up the middle.
    if #list == 0 and lay.bounds then
        local b = lay.bounds
        local cx, cy = (b.mins[1] + b.maxs[1]) / 2, (b.mins[2] + b.maxs[2]) / 2
        local w = math.max(b.maxs[1] - b.mins[1], b.maxs[2] - b.mins[2])
        for z = b.mins[3] + 200, b.maxs[3] - 100, 520 do
            list[#list + 1] = { pos = GK.LevelToModel({ cx, cy, z }), col = Color(255, 225, 190), size = math.Clamp(w * 0.6, 400, 900), bright = 1.2 }
        end
    end
    cache[piece] = list
    return list
end

hook.Add("Think", "GK_RoomLights", function()
    if not cv:GetBool() then return end
    local eye = EyePos()
    local near = {}
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        local p = piece:GetPos()
        for i, lamp in ipairs(lampsOf(piece:GetPiece())) do
            local wp = p + lamp.pos
            local d2 = wp:DistToSqr(eye)
            if d2 < RANGE2 then near[#near + 1] = { d2 = d2, pos = wp, lamp = lamp, key = piece:EntIndex() * 4096 + i } end
        end
    end
    table.sort(near, function(a, b) return a.d2 < b.d2 end)
    local n = math.min(#near, cvMax:GetInt())
    for k = 1, n do
        local e = near[k]
        local dl = DynamicLight(e.key)
        if dl then
            dl.pos = e.pos
            dl.r, dl.g, dl.b = e.lamp.col.r, e.lamp.col.g, e.lamp.col.b
            dl.brightness = e.lamp.bright
            dl.decay = e.lamp.size * 4
            dl.size = e.lamp.size
            dl.dietime = CurTime() + 0.2
        end
    end
end)
