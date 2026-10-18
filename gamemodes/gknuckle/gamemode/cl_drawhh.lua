-- gk_drawhh 1 (cheat): draws every handhold box of the run rooms around you, so the
-- converted holds can be checked against the geometry in game. Colours: red pitons,
-- cyan ledges (the "edge" holds), yellow ladders, white everything else. Reads the
-- layouts through GK.LevelLayout, so it shows exactly what the mind-hands can grab.
local cv = CreateClientConVar("gk_drawhh", "0", false, false, "Draw the run rooms' handhold boxes (needs sv_cheats 1)", 0, 1)
local RANGE = 1400

local function kindColor(name)
    name = string.lower(name or "")
    if name:find("piton", 1, true) or name:find("red", 1, true) then return Color(255, 60, 40, 255) end
    if name == "edge" then return Color(60, 220, 255, 255) end
    if name:find("ladder", 1, true) then return Color(255, 220, 60, 255) end
    return Color(230, 230, 230, 255)
end

hook.Add("PostDrawTranslucentRenderables", "GK_DrawHandholds", function(depth, sky)
    if depth or sky or not cv:GetBool() then return end
    if not GetConVar("sv_cheats"):GetBool() then return end
    local eye = EyePos()
    local r2 = RANGE * RANGE
    local drawn = 0
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        local p = piece:GetPos()
        local lay = GK.LevelLayout(piece:GetPiece())
        for _, h in ipairs(lay.handholds or {}) do
            if h.mins and h.maxs then
                local lo, hi = GK.LevelToModel(h.mins), GK.LevelToModel(h.maxs)
                local mins = Vector(math.min(lo.x, hi.x), math.min(lo.y, hi.y), math.min(lo.z, hi.z))
                local maxs = Vector(math.max(lo.x, hi.x), math.max(lo.y, hi.y), math.max(lo.z, hi.z))
                local c = p + (mins + maxs) * 0.5
                if c:DistToSqr(eye) < r2 then
                    render.DrawWireframeBox(p, angle_zero, mins, maxs, kindColor(h.name), true)
                    drawn = drawn + 1
                    if drawn > 6000 then return end
                end
            end
        end
    end
end)

hook.Add("HUDPaint", "GK_DrawHandholdsHint", function()
    if not cv:GetBool() then return end
    local txt = GetConVar("sv_cheats"):GetBool() and "gk_drawhh: red pitons, cyan ledges, yellow ladders" or "gk_drawhh needs sv_cheats 1"
    draw.SimpleText(txt, "DermaDefault", ScrW() / 2, 12, Color(255, 255, 255, 200), TEXT_ALIGN_CENTER)
end)
