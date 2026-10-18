local C = GK.Config

-- No text on screen at all. Your hands' colour is your health and state
-- (sh_states.lua); the only HUD is a few thin bars that appear when needed:
--   stamina (while not full), getting off a rebar, reviving / being revived,
--   Xenium link reboot countdown, gravity surge time left.

local function bar(frac, y, col, w)
    w = w or 220
    local x = ScrW() / 2 - w / 2
    surface.SetDrawColor(0, 0, 0, 120)
    surface.DrawRect(x - 2, y - 2, w + 4, 10)
    surface.SetDrawColor(col.r, col.g, col.b, 210)
    surface.DrawRect(x, y, w * math.Clamp(frac, 0, 1), 6)
end

hook.Add("HUDPaint", "GK_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local h = ScrH()

    local stamina = GK.Stamina(ply) / C.StaminaMax
    local over = ply:GetNW2Float("gk_overdraw", 0)
    local shatter = CurTime() - ply:GetNW2Float("gk_shatter_at", -10)
    if shatter < 0.6 then
        -- The bar just shattered: shards flying off.
        local w, cx = 220, ScrW() / 2
        local seed = ply:GetNW2Float("gk_shatter_at", 0)
        local function rnd(i, k) return (math.sin(i * 12.9898 + k * 78.233 + seed) * 43758.5453) % 1 end
        for i = 1, 14 do
            local dx, dy = rnd(i, 1) * 2 - 1, rnd(i, 2) * 1.6 - 1.2
            local x = cx - w / 2 + (i - 0.5) * w / 14 + dx * shatter * 260
            local y = h - 46 + dy * shatter * 200 + shatter * shatter * 400
            surface.SetDrawColor(220, 40, 40, 255 * (1 - shatter / 0.6))
            surface.DrawRect(x, y, w / 14 - 2, 6)
        end
    elseif stamina < 1 or over > 0 then
        -- Overdrawing: the bar shakes harder as the red strain fills it.
        local shake = over > 0 and over * 6 or 0
        local y = h - 46 + math.Rand(-shake, shake)
        local w = 220
        local x = ScrW() / 2 - w / 2 + math.Rand(-shake, shake)
        surface.SetDrawColor(0, 0, 0, 120)
        surface.DrawRect(x - 2, y - 2, w + 4, 10)
        surface.SetDrawColor(255, 255, 255, 210)
        surface.DrawRect(x, y, w * math.Clamp(stamina, 0, 1), 6)
        if over > 0 then
            surface.SetDrawColor(220, 40, 40, 230)
            surface.DrawRect(x, y, w * math.Clamp(over, 0, 1), 6)
        end
    end

    if not GK.IsChipOnline(ply) then
        bar((ply:GetNW2Float("gk_chip_offline_until") - CurTime()) / C.StunDuration, h - 60, GK.Colors.Hurt)
    end
    if GK.IsImpaled(ply) then
        bar(ply:GetNW2Float("gk_impale_progress", 0), h - 74, GK.Colors.Crawl)
    end
    if GK.IsDowned(ply) then
        local rev = ply:GetNW2Float("gk_revive_progress", 0)
        if rev > 0 then
            bar(rev, h - 74, GK.Colors.Green)
        else
            bar((ply:GetNW2Float("gk_bleedout_at") - CurTime()) / C.BleedOutTime, h - 74, GK.Colors.NeonPink)
        end
    end
    if GK.HasSurge(ply) then
        bar((ply:GetNW2Float("gk_surge_until") - CurTime()) / C.SurgeTime, h - 88, GK.Colors.Orange, 120)
    end

    -- Reviving someone: a short bar under the crosshair.
    local tr = ply:GetEyeTrace()
    if IsValid(tr.Entity) and tr.Entity:IsPlayer() and GK.IsDowned(tr.Entity) and tr.HitPos:Distance(ply:GetShootPos()) < C.ReviveRange then
        bar(tr.Entity:GetNW2Float("gk_revive_progress", 0), h / 2 + 24, GK.Colors.Green, 60)
    end
end)

local cursorHand = Material("gknuckle/vending/cursor_hand.png", "noclamp")
local cursorRoach = Material("gknuckle/vending/cursor_roach.png", "noclamp")
-- An item or a roach a click would pick up: in reach, under the crosshair
-- (roaches with the same forgiving cone the catch uses), and a free hand.
local function grabCue(ply, tr)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "gk_mind" then return false end
    local free = false
    for _, side in ipairs({ "l", "r" }) do
        if ply:GetNW2String("gk_hitem_" .. side, "") == "" and not (GK.HasFist and GK.HasFist(ply, side)) then free = true end
    end
    if not free then return false end
    local src, aim = ply:GetShootPos(), ply:GetAimVector()
    local reach = GK.GripRange(ply)
    local e = tr.Entity
    if IsValid(e) and e:GetClass() == "gk_item" and e.GetItemClass and e:GetItemClass() ~= "" and tr.HitPos:Distance(src) <= reach then return true end
    for _, r in ipairs(ents.FindInSphere(src, reach)) do
        if r:GetClass() == "gk_roach" and (r.GK_HideUntil or 0) < CurTime() and (r:WorldSpaceCenter() - src):GetNormalized():Dot(aim) > 0.95 then return true end
    end
    return false
end
GK.GrabCue = grabCue
hook.Add("HUDPaint", "GK_VendCursor", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local tr = ply:GetEyeTrace()
    local v = tr.Entity
    local mat
    if IsValid(v) and v.Layout and v.SlotAt and tr.HitPos:DistToSqr(ply:GetShootPos()) <= 160 * 160 then
        local lp = v:WorldToLocal(tr.HitPos)
        if v.AtRoachSlot and v:AtRoachSlot(lp) then mat = cursorRoach
        elseif v:SlotAt(lp) then mat = cursorHand end
    elseif grabCue(ply, tr) then
        mat = cursorHand -- something a free hand would pick up
    end
    if not mat then return end
    local s = math.floor(ScrH() / 30)
    surface.SetDrawColor(255, 255, 255, 235)
    surface.SetMaterial(mat)
    surface.DrawTexturedRect(ScrW() / 2 + 2, ScrH() / 2 - s / 4, s, s)
end)

-- Strip the rest of the default HUD text: names over heads, kill feed, hints,
-- ammo/health readouts, weapon selection.
function GM:HUDDrawTargetID() end
function GM:DrawDeathNotice() end
function GM:AddHint() end
function GM:SuppressHint() end
function GM:AddNotify() end -- Sandbox's hint/notice popups (its hints are queued before we load)

local HIDDEN = {
    CHudHealth = true, CHudBattery = true, CHudSuitPower = true, CHudAmmo = true,
    CHudSecondaryAmmo = true, CHudWeaponSelection = true, CHudHintDisplay = true,
    CHudDamageIndicator = true, CHudPoisonDamageIndicator = true, CHudSquadStatus = true,
    CHudZoom = true, CHudGeiger = true, CHudHistoryResource = true,
}
function GM:HUDShouldDraw(name)
    if HIDDEN[name] then return false end
    return self.BaseClass.HUDShouldDraw(self, name)
end

-- Xenium link offline: desaturate and scatter static over the screen.
hook.Add("RenderScreenspaceEffects", "GK_ChipStatic", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or GK.IsChipOnline(ply) then return end
    DrawColorModify({
        ["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0.03,
        ["$pp_colour_brightness"] = -0.05, ["$pp_colour_contrast"] = 1.2,
        ["$pp_colour_colour"] = 0.1,
        ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
    })
    DrawMotionBlur(0.3, 0.8, 0.01)
end)

hook.Add("HUDPaintBackground", "GK_ChipNoise", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or GK.IsChipOnline(ply) then return end
    local w, h = ScrW(), ScrH()
    for _ = 1, 160 do
        local v = math.random(80, 255)
        surface.SetDrawColor(v, v, v, math.random(20, 90))
        surface.DrawRect(math.random(0, w), math.random(0, h), math.random(2, 60), 2)
    end
end)
