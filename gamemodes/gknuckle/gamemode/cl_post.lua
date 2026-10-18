-- White Knuckle's look on the whole view, from its own post-processing
-- profile ("Main Post Processing": a wide bloom with a high threshold so only
-- lights and glowing things bloom, plus its sharpen pass) and the dark bunker
-- vignette: a wide soft bloom haze, a crisper image, slightly muted colour
-- and dark corners. gk_post 0 turns it off.
local cv = CreateClientConVar("gk_post", "1", true, false, "White Knuckle style screen effects")

local gradU = Material("gui/gradient_up")
local gradD = Material("gui/gradient_down")
local gradL = Material("vgui/gradient-l")
local gradR = Material("vgui/gradient-r")

hook.Add("RenderScreenspaceEffects", "GK_WKPost", function()
    if not cv:GetBool() then return end
    -- Bloom: WK's is intensity 11, threshold 2, diffusion 10: wide, only on bright things.
    DrawBloom(0.72, 1.4, 12, 12, 2, 1.1, 1, 1, 1)
    DrawSharpen(1.1, 0.8)
    DrawColorModify({
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.005,
        ["$pp_colour_brightness"] = -0.015, ["$pp_colour_contrast"] = 1.06,
        ["$pp_colour_colour"] = 0.88,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
    })
end)

-- The vignette: darkened edges, heavier at the bottom where the hands are.
hook.Add("HUDPaintBackground", "GK_WKVignette", function()
    if not cv:GetBool() then return end
    local w, h = ScrW(), ScrH()
    surface.SetDrawColor(0, 0, 0, 120)
    surface.SetMaterial(gradD) surface.DrawTexturedRect(0, 0, w, h * 0.22)
    surface.SetMaterial(gradU) surface.DrawTexturedRect(0, h * 0.72, w, h * 0.28)
    surface.SetDrawColor(0, 0, 0, 100)
    surface.SetMaterial(gradL) surface.DrawTexturedRect(0, 0, w * 0.18, h)
    surface.SetMaterial(gradR) surface.DrawTexturedRect(w * 0.82, 0, w * 0.18, h)
end)
