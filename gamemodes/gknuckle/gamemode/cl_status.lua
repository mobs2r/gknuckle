-- Status screen effects, like WK's: the world itself changes, no icons.
--   wounded  a heavy hit (25+ in one go: a TEETH swipe, a rebar, a blast)
--            drains the colour out and leaves scratches across your eyes for
--            a few seconds, as after WK's flesh bursts.
--   blink    the blink eye's jump: a flash of the inverted, outline-only
--            vision WK shows (its 31:12 "vision" frames).
--   pilled   a warm, slightly over-bright glow while the pills work.
--   shielded a cold blue rim at the edges of your sight.
-- (Gooped and injected are drawn in sh_buffs.lua; the chip being knocked
-- offline is the static in cl_hud.lua.)

local WOUND, BLINK = 4, 0.6

local function fade(t0, dur)
    local t = CurTime() - t0
    if t0 == 0 or t < 0 or t > dur then return 0 end
    return 1 - t / dur
end

hook.Add("RenderScreenspaceEffects", "GK_StatusEffects", function()
    local me = LocalPlayer()
    if not IsValid(me) or not me:Alive() then return end
    local wound = fade(me:GetNW2Float("gk_wound_at", 0), WOUND)
    local blink = fade(me:GetNW2Float("gk_blink_at", 0), BLINK)
    local pilled = GK.HasBuff(me, "pilled") and math.min(1, GK.BuffLeft(me, "pilled") / 10) or 0
    if wound > 0 then
        DrawColorModify({
            ["$pp_colour_addr"] = 0.02 * wound, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = -0.03 * wound, ["$pp_colour_contrast"] = 1 + 0.15 * wound,
            ["$pp_colour_colour"] = 1 - 0.8 * wound,
            ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        })
    end
    if pilled > 0 then
        DrawColorModify({
            ["$pp_colour_addr"] = 0.03 * pilled, ["$pp_colour_addg"] = 0.025 * pilled, ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = 0.02 * pilled, ["$pp_colour_contrast"] = 1,
            ["$pp_colour_colour"] = 1 + 0.25 * pilled,
            ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        })
        DrawBloom(0.7, 1.2 * pilled, 8, 8, 1, 1, 1, 0.9, 0.6)
    end
    if blink > 0 then
        -- Outlines only, light on dark: the world as a negative sketch.
        DrawSobel(0.12)
        DrawColorModify({
            ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = 0, ["$pp_colour_contrast"] = 1 + blink,
            ["$pp_colour_colour"] = 1 - blink,
            ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        })
    end
end)

-- Scratches: fixed for each wound (seeded by when it happened), fading out.
hook.Add("HUDPaintBackground", "GK_StatusOverlay", function()
    local me = LocalPlayer()
    if not IsValid(me) or not me:Alive() then return end
    local w, h = ScrW(), ScrH()
    local t0 = me:GetNW2Float("gk_wound_at", 0)
    local wound = fade(t0, WOUND)
    if wound > 0 then
        local seed = t0 * 1000
        local function rnd(i, k) return (math.sin(i * 12.9898 + k * 78.233 + seed) * 43758.5453) % 1 end
        for i = 1, 26 do
            local x, y = rnd(i, 1) * w, rnd(i, 2) * h
            local len, ang = 40 + rnd(i, 3) * 260, rnd(i, 4) * math.pi
            local dx, dy = math.cos(ang) * len, math.sin(ang) * len
            local v = 170 + rnd(i, 5) * 80
            surface.SetDrawColor(v, v * 0.92, v * 0.85, 110 * wound * (0.5 + rnd(i, 6) * 0.5))
            surface.DrawLine(x, y, x + dx, y + dy)
            surface.DrawLine(x + 1, y, x + dx + 1, y + dy)
        end
        -- Dark at the edges, the way a hard knock narrows your sight.
        surface.SetDrawColor(20, 0, 0, 90 * wound)
        surface.DrawRect(0, 0, w, h * 0.06) surface.DrawRect(0, h * 0.94, w, h * 0.06)
        surface.DrawRect(0, 0, w * 0.04, h) surface.DrawRect(w * 0.96, 0, w * 0.04, h)
    end
    if GK.HasBuff(me, "shielded") then
        local k = math.min(1, GK.BuffLeft(me, "shielded") / 10) * (0.7 + 0.3 * math.sin(CurTime() * 2))
        surface.SetDrawColor(90, 170, 255, 40 * k)
        surface.DrawRect(0, 0, w, h * 0.025) surface.DrawRect(0, h * 0.975, w, h * 0.025)
        surface.DrawRect(0, 0, w * 0.015, h) surface.DrawRect(w * 0.985, 0, w * 0.015, h)
    end
end)

-- WK's speed streaks: moving really fast (a launch, a long fall, a boost),
-- thin lines rush past the edges of your sight.
local streaks = {}
hook.Add("HUDPaintBackground", "GK_SpeedStreaks", function()
    local me = LocalPlayer()
    if not IsValid(me) or not me:Alive() then return end
    local v = me:GetVelocity():Length()
    local k = math.Clamp((v - 550) / 450, 0, 1)
    if k <= 0 then streaks = {} return end
    local w, h = ScrW(), ScrH()
    local cx, cy = w / 2, h / 2
    while #streaks < 40 * k do
        local a = math.Rand(0, math.pi * 2)
        streaks[#streaks + 1] = { a = a, r = math.Rand(0.35, 0.6), born = CurTime() }
    end
    for i = #streaks, 1, -1 do
        local s = streaks[i]
        local t = (CurTime() - s.born) * 3.5
        if t > 1 then table.remove(streaks, i) else
            local r0, r1 = (s.r + t * 0.4) * h, (s.r + t * 0.4 + 0.12) * h
            local c, sn = math.cos(s.a), math.sin(s.a)
            surface.SetDrawColor(255, 255, 255, 90 * k * (1 - t))
            surface.DrawLine(cx + c * r0, cy + sn * r0, cx + c * r1, cy + sn * r1)
        end
    end
end)
