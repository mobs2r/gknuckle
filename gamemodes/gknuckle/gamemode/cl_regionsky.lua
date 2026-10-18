-- Per-region look inside the arena shafts, client-side: White Knuckle's regions
-- are each a dark void with their own fog colour and density (Region_*.asset
-- fxData: fog, fogMultiplier, worldTint), so while the local player is in an
-- arena running region X the map's sky is skipped (black void) and the fog and
-- colour grade follow that region. The hub and the practice towers keep the
-- map's own sky and no fog.
--
-- Server side: sv_wk_arena.lua publishes the region per arena as the global
-- string gk_arena_region_<index>; the player's arena is NW2Int gk_arena.

-- WK fog is per metre; Source fog is start/end in units (39.37 u/m). WK's
-- multiplier 0.06 reads as "fully fogged after ~1/0.06 m".
local M = 39.37
local LOOK = {
    silos      = { fog = Color(8, 8, 8), mult = 0.05, tint = { 1.00, 1.00, 1.00 } },
    pipeworks  = { fog = Color(14, 14, 6), mult = 0.034, tint = { 1.00, 1.00, 0.92 } },
    habitation = { fog = Color(6, 6, 7), mult = 0.06, tint = { 0.96, 0.98, 1.00 } },
    nest       = { fog = Color(7, 5, 5), mult = 0.06, tint = { 1.00, 0.95, 0.93 } },
    chimney    = { fog = Color(6, 13, 20), mult = 0.02, tint = { 0.92, 0.98, 1.00 } },
    ladder     = { fog = Color(5, 5, 5), mult = 0.06, tint = { 1.00, 1.00, 1.00 } },
    abyss      = { fog = Color(3, 3, 5), mult = 0.03, tint = { 0.95, 0.95, 1.00 } },
    -- Region_Dusk (single-room Abyss stage): WK's outdoor dusk is a near-black wine-brown
    -- haze (about 28,19,21 measured from the walkthrough), thin enough to see the cliffs.
    dusk       = { fog = Color(28, 19, 21), mult = 0.015, tint = { 1.00, 0.94, 0.92 } },
}
local DEFAULT = { fog = Color(5, 5, 5), mult = 0.05, tint = { 1, 1, 1 } }

local function regionLook()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end
    local idx = ply:GetNW2Int("gk_arena", 0)
    if idx == 0 then
        -- Not in a round (admin test, spectating): fall back to the shaft footprints.
        local hub = GK.HubLayout and GK.HubLayout()
        local p = ply:GetPos()
        for _, a in ipairs(hub and hub.arenas or {}) do
            if math.abs(p.x - a.center[1]) <= a.half and math.abs(p.y - a.center[2]) <= a.half then idx = a.index break end
        end
    end
    if idx == 0 then return nil end
    local region = GetGlobal2String("gk_arena_region_" .. idx, "")
    if region == "" then return nil end
    local key = string.lower(string.match(region, "^Region_(%a+)") or "")
    return LOOK[key] or DEFAULT, key
end

-- Smooth the fog in and out over a second so the vacuum teleport doesn't pop.
local blend, cur = 0, nil
local nextDbg = 0
local DEBUG = file.Exists("gknuckle/selftest.txt", "DATA") or file.Exists("gknuckle/regionsky_debug.txt", "DATA") -- once, not every frame
hook.Add("Think", "GK_RegionSkyBlend", function()
    local look, key = regionLook()
    if look then cur = look end
    blend = math.Approach(blend, look and 1 or 0, FrameTime() * 1.5)
    if DEBUG then
        if CurTime() > nextDbg then
            nextDbg = CurTime() + 2
            local ply = LocalPlayer()
            local hub = GK.HubLayout and GK.HubLayout()
            print("[GKSKY]", "arenaNW", IsValid(ply) and ply:GetNW2Int("gk_arena", 0) or -1, "hub", tostring(hub and #hub.arenas), "pos", tostring(IsValid(ply) and ply:GetPos()), "region1", GetGlobal2String("gk_arena_region_1", ""), "key", tostring(key), "blend", blend)
        end
    end
end)

-- No map sky inside a run: the shaft is a void. Returning true from
-- PreDrawSkyBox did not hide the 2D sky here, so after it is drawn a huge
-- inward-facing box in the region's fog colour is painted over it (depth write
-- off, so the world still draws in front).
local function paintVoid()
    if blend <= 0 or not cur then return end
    local a = math.floor(255 * math.min(blend * 1.5, 1))
    local eye = EyePos()
    render.SetColorMaterial()
    render.OverrideDepthEnable(true, false)
    render.CullMode(MATERIAL_CULLMODE_CW)
    render.DrawBox(eye, angle_zero, Vector(-12000, -12000, -12000), Vector(12000, 12000, 12000), Color(cur.fog.r, cur.fog.g, cur.fog.b, a))
    render.CullMode(MATERIAL_CULLMODE_CCW)
    render.OverrideDepthEnable(false, false)
end
hook.Add("PostDraw2DSkyBox", "GK_RegionVoid", paintVoid)
hook.Add("PostDrawSkyBox", "GK_RegionVoid2", paintVoid)

local function applyFog()
    if blend <= 0 or not cur then return end
    local far = M / cur.mult            -- units at which WK's fog saturates
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(far * 0.08)
    render.FogEnd(far)
    render.FogMaxDensity(0.97 * blend)
    render.FogColor(cur.fog.r, cur.fog.g, cur.fog.b)
    return true
end
hook.Add("SetupWorldFog", "GK_RegionFog", applyFog)
hook.Add("SetupSkyboxFog", "GK_RegionSkyFog", function(scale)
    if blend <= 0 or not cur then return end
    local far = M / cur.mult * scale
    render.FogMode(MATERIAL_FOG_LINEAR)
    render.FogStart(0)
    render.FogEnd(far)
    render.FogMaxDensity(0.97 * blend)
    render.FogColor(cur.fog.r, cur.fog.g, cur.fog.b)
    return true
end)

-- WK's worldTint as a colour grade, blended in with the fog.
local grade = { ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0, ["$pp_colour_brightness"] = 0,
    ["$pp_colour_contrast"] = 1, ["$pp_colour_colour"] = 1, ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0 }
hook.Add("RenderScreenspaceEffects", "GK_RegionGrade", function()
    if blend <= 0 or not cur then return end
    local t = cur.tint
    grade["$pp_colour_mulr"] = (t[1] - 1) * blend
    grade["$pp_colour_mulg"] = (t[2] - 1) * blend
    grade["$pp_colour_mulb"] = (t[3] - 1) * blend
    grade["$pp_colour_contrast"] = 1 + 0.08 * blend
    grade["$pp_colour_colour"] = 1 - 0.1 * blend
    DrawColorModify(grade)
end)
