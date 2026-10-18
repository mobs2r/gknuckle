-- Hand emotes. The Xenium virus handles everything, hands included, so emotes are
-- the hologram hands making a gesture: hold C for the emote wheel (it
-- replaces Sandbox's context menu), point at one and let go. While an emote
-- plays the hands glow green and the Husk's mouth shows its expression
-- (GK.Expression). Q no longer opens the spawn menu: it's the pocket key.
--
-- Only White Knuckle's own hand frames, unedited (the hand-edited middle
-- finger / Vulcan frames and the finger-guns and 6 7 emotes were dropped).
--
-- Each emote's hands(t, side) says, for a moment t seconds in, where that
-- hand is: frame (a holo hand frame, a left hand; the right is mirrored),
-- x, y (screen fractions of the hand's centre), rot (degrees), size (x hand size),
-- or nil to leave that hand where it is.
AddCSLuaFile()

GK.Emotes = {}
GK.EmoteOrder = {}
local function emote(id, def)
    def.id = id
    GK.Emotes[id] = def
    GK.EmoteOrder[#GK.EmoteOrder + 1] = id
end

local sin, abs = math.sin, math.abs

-- Flips the left hand's x across the middle of the screen for the right hand.
local function mx(side, x) return side == "r" and 1 - x or x end

emote("shy", {
    name = "Shy", icon = "hnd_b3d4", time = 3.5, expression = "shy",
    -- Index fingers pointing in, tapping together.
    hands = function(t, side)
        local tap = (abs(sin(t * 4)) ^ 3) * 0.035
        return { frame = "hnd_b3d4", x = mx(side, 0.405 + tap), y = 0.72, rot = side == "r" and -12 or 12, size = 0.85 }
    end,
})

emote("wave", {
    name = "Wave", icon = "hnd_b1a2", time = 2.5, expression = "grin",
    hands = function(t, side)
        if side ~= "r" then return end
        return { frame = "hnd_b1a2", x = 0.66, y = 0.6, rot = sin(t * 9) * 22, size = 1 }
    end,
})

emote("thumbsup", {
    name = "Thumbs up", icon = "hnd_b3b1", time = 2, expression = "grin",
    hands = function(t, side)
        if side ~= "r" then return end
        local pop = math.min(1, t * 6)
        return { frame = "hnd_b3b1", x = 0.62, y = 0.75 - 0.1 * pop, rot = 0, size = 1 }
    end,
})

emote("rock", {
    name = "Rock on", icon = "hnd_b2c1", time = 3, expression = "taunt",
    hands = function(t, side)
        local bob = abs(sin(t * 7 + (side == "r" and 0.6 or 0))) * 0.05
        return { frame = "hnd_b2c1", x = mx(side, 0.3), y = 0.7 - bob, rot = 0, size = 0.95 }
    end,
})

emote("clap", {
    name = "Clap", icon = "hnd_b1a2", time = 3, expression = "laugh",
    hands = function(t, side)
        local c = abs(sin(t * 6))
        return { frame = "hnd_b1a2", x = mx(side, 0.43 - c * 0.12), y = 0.7, rot = side == "r" and -80 or 80, size = 0.9 }
    end,
})

emote("fist", {
    name = "Shake fist", icon = "hnd_b3d1", time = 2.5, expression = "rage",
    hands = function(t, side)
        if side ~= "r" then return end
        return { frame = "hnd_b3d1", x = 0.62, y = 0.62 + sin(t * 14) * 0.03, rot = -20, size = 1 }
    end,
})

function GK.EmoteOf(ply)
    if ply:GetNW2Float("gk_emote_until", 0) <= CurTime() then return nil end
    local e = GK.Emotes[ply:GetNW2String("gk_emote_id", "")]
    if not e then return nil end
    return e, e.time - (ply:GetNW2Float("gk_emote_until", 0) - CurTime())
end

if SERVER then
    util.AddNetworkString("gk_emote")
    net.Receive("gk_emote", function(_, ply)
        local e = GK.Emotes[net.ReadString()]
        if not e or not ply:Alive() or GK.IsDowned(ply) or GK.IsRagdolled(ply) or GK.IsImpaled(ply) or not GK.IsChipOnline(ply) then return end
        if (ply.GK_NextEmote or 0) > CurTime() then return end
        ply.GK_NextEmote = CurTime() + 0.5
        ply:SetNW2String("gk_emote_id", e.id)
        ply:SetNW2Float("gk_emote_until", CurTime() + e.time)
        ply:SetNW2Int("gk_emote_act", 0)
    end)
end

if CLIENT then
    -- Q: the pocket key, never the spawn menu (gk_spawnmenu 1 lets admins have it back).
    local cvSpawn = CreateClientConVar("gk_spawnmenu", "0", true, false, "Admins: let Q open the spawn menu")
    function GM:SpawnMenuOpen()
        local ply = LocalPlayer()
        return cvSpawn:GetBool() and IsValid(ply) and ply:IsAdmin()
    end

    -- C: the emote wheel instead of the context menu.
    local open, openedAt, pick = false, 0, nil
    function GM:ContextMenuOpen() return false end
    hook.Add("OnContextMenuOpen", "GK_EmoteWheel", function()
        open, openedAt, pick = true, RealTime(), nil
        gui.EnableScreenClicker(true)
        input.SetCursorPos(ScrW() / 2, ScrH() / 2)
        return true
    end)
    hook.Add("OnContextMenuClose", "GK_EmoteWheel", function()
        if not open then return end
        open = false
        gui.EnableScreenClicker(false)
        if pick then
            net.Start("gk_emote") net.WriteString(pick) net.SendToServer()
        end
    end)

    local mats = {}
    local function holo(frame)
        if not mats[frame] then
            local png = Material("gknuckle/hands/holo/" .. frame .. ".png", "noclamp")
            mats[frame] = CreateMaterial("gk_emote_" .. frame, "UnlitGeneric", {
                ["$basetexture"] = png:GetTexture("$basetexture"):GetName(),
                ["$additive"] = 1, ["$vertexcolor"] = 1, ["$vertexalpha"] = 1,
            })
        end
        return mats[frame]
    end
    GK.HoloFrame = holo

    -- The wheel: a ring of hand icons, no text; the one you point at lights up.
    hook.Add("HUDPaint", "GK_EmoteWheel", function()
        if not open then return end
        local w, h = ScrW(), ScrH()
        local cx, cy = w / 2, h / 2
        local n = #GK.EmoteOrder
        local R = h * 0.26
        local mxp, myp = input.GetCursorPos()
        local dx, dy = mxp - cx, myp - cy
        pick = nil
        local hover
        if dx * dx + dy * dy > (R * 0.3) ^ 2 then
            local a = (math.deg(math.atan2(dy, dx)) + 90) % 360
            hover = math.floor((a + 180 / n) / (360 / n)) % n + 1
            pick = GK.EmoteOrder[hover]
        end
        local grow = math.min(1, (RealTime() - openedAt) * 8)
        surface.SetDrawColor(0, 0, 0, 120 * grow)
        surface.DrawRect(0, 0, w, h)
        local green = GK.Colors.Emote or Color(80, 255, 120)
        for i, id in ipairs(GK.EmoteOrder) do
            local a = math.rad((i - 1) * 360 / n - 90)
            local x, y = cx + math.cos(a) * R * grow, cy + math.sin(a) * R * grow
            local size = h * (i == hover and 0.15 or 0.11)
            local col = i == hover and green or Color(200, 220, 255)
            surface.SetMaterial(holo(GK.Emotes[id].icon))
            surface.SetDrawColor(col.r, col.g, col.b, (i == hover and 255 or 150) * grow)
            surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
        end
    end)
end
