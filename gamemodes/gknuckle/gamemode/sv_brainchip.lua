local C = GK.Config

-- Knock a player's Xenium link offline (V Corp's suppression tech): their mind-hands let go and vanish, and
-- their screen fills with static until it reboots (see cl_hud.lua).
function GK.StunChip(ply, duration, attacker)
    if not IsValid(ply) or not ply:Alive() then return end
    -- A suit battery (sh_buffs.lua) keeps the link shielded.
    if GK.HasBuff(ply, "shielded") then
        ply:EmitSound("items/suitchargeno1.wav", 70, 120)
        return
    end
    local untilTime = CurTime() + (duration or C.StunDuration)
    ply:SetNW2Float("gk_chip_offline_until", math.max(ply:GetNW2Float("gk_chip_offline_until", 0), untilTime))

    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.ReleaseAll then wep:ReleaseAll() end

    ply:EmitSound("ambient/energy/zap" .. math.random(1, 9) .. ".wav", 75, 90)
    ply:ScreenFade(SCREENFADE.IN, Color(120, 200, 255, 160), 0.6, 0)
end

-- Gravity surge: grav-gun lift/throw/drag strength for a while (gk_surge pickup, shop).
function GK.GiveSurge(ply)
    ply:SetNW2Float("gk_surge_until", CurTime() + C.SurgeTime)
    ply:EmitSound("weapons/physcannon/physcannon_charge.wav", 75, 110)
    ply:ScreenFade(SCREENFADE.IN, Color(255, 140, 30, 80), 0.5, 0)
    timer.Create("GK_SurgeEnd_" .. ply:EntIndex(), C.SurgeTime, 1, function()
        if IsValid(ply) then ply:EmitSound("weapons/physcannon/physcannon_drop.wav") end
    end)
end

hook.Add("PlayerSpawn", "GK_SurgeReset", function(ply)
    ply:SetNW2Float("gk_surge_until", 0)
end)

-- Emits the energy burst used by the stun grenade.
function GK.ChipBurst(pos, radius, duration, attacker)
    local fx = EffectData()
    fx:SetOrigin(pos)
    fx:SetMagnitude(8)
    fx:SetScale(2)
    fx:SetRadius(radius)
    util.Effect("cball_explode", fx, true, true)
    util.Effect("TeslaHitboxes", fx, true, true)
    sound.Play("weapons/physcannon/energy_disintegrate4.wav", pos, 90, 100)

    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and ply:WorldSpaceCenter():DistToSqr(pos) <= radius * radius then
            local tr = util.TraceLine({ start = pos, endpos = ply:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY })
            if not tr.Hit then GK.StunChip(ply, duration, attacker) end
        end
    end
    hook.Run("GK_ChipBurst", pos, radius, duration, attacker)
end
