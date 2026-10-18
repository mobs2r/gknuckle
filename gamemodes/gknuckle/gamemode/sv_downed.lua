local C = GK.Config

-- Lethal damage puts you down (neon pink hands, 0 hp shown) instead of killing you.
-- A teammate revives you by holding E on you. Bleeding out, or getting hit hard
-- again, kills you; blasts, headshots and losing your legs while down gore you
-- (grey hands, not revivable).

local function setDowned(ply, downed)
    ply:SetNW2Bool("gk_downed", downed)
    ply:SetNW2Float("gk_bleedout_at", downed and CurTime() + C.BleedOutTime or 0)
    ply:SetNW2Float("gk_revive_progress", 0)
    ply:SetViewOffset(downed and Vector(0, 0, 20) or Vector(0, 0, 64))
    ply:SetViewOffsetDucked(downed and Vector(0, 0, 20) or Vector(0, 0, 28))
end

function GK.Down(ply)
    if GK.IsDowned(ply) then return end
    setDowned(ply, true)
    ply:SetHealth(1)
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.ReleaseAll then wep:ReleaseAll() end
    ply:EmitSound("vo/npc/male01/pain0" .. math.random(1, 9) .. ".wav")
end

function GK.Revive(ply, by)
    if not GK.IsDowned(ply) then return end
    setDowned(ply, false)
    ply:SetHealth(C.ReviveHealth)
    ply:EmitSound("items/medshot4.wav")
    if IsValid(by) then PrintMessage(HUD_PRINTTALK, ("[gKnuckle] %s revived %s"):format(by:Nick(), ply:Nick())) end
end

function GK.Gore(ply, dmginfo)
    ply:SetNW2Bool("gk_gored", true)
    GK.RemoveLegs(ply)
    setDowned(ply, false)
    if ply:Alive() then
        local d = DamageInfo()
        d:SetDamage(ply:Health() + 1000)
        d:SetDamageType(DMG_ALWAYSGIB)
        if dmginfo then
            if IsValid(dmginfo:GetAttacker()) then d:SetAttacker(dmginfo:GetAttacker()) end
            if IsValid(dmginfo:GetInflictor()) then d:SetInflictor(dmginfo:GetInflictor()) end
        end
        ply.GK_Goring = true
        ply:TakeDamageInfo(d)
        ply.GK_Goring = false
        if ply:Alive() then ply:Kill() end
    end
end

hook.Add("ScalePlayerDamage", "GK_HeadshotGore", function(ply, hitgroup, dmginfo)
    ply.GK_LastHitgroup = hitgroup
end)

hook.Add("EntityTakeDamage", "GK_Downed", function(ply, dmginfo)
    if not ply:IsPlayer() or not ply:Alive() or ply.GK_Goring then return end
    ply:SetNW2Float("gk_hurt_until", CurTime() + 0.4)

    local lethal = dmginfo:GetDamage() >= ply:Health()
    if GK.IsDowned(ply) then
        if dmginfo:GetDamage() >= C.GoreDamage or dmginfo:IsExplosionDamage() then
            GK.Gore(ply, dmginfo)
        end
        dmginfo:SetDamage(0)
        return true
    end
    if not lethal then return end

    local gore = dmginfo:IsExplosionDamage() and dmginfo:GetDamage() >= C.GoreDamage
        or ply.GK_LastHitgroup == HITGROUP_HEAD and dmginfo:IsBulletDamage()
        or not GK.HasLegs(ply) and dmginfo:GetDamage() >= C.GoreDamage
    if gore then
        GK.Gore(ply, dmginfo)
        return true
    end

    GK.Down(ply)
    dmginfo:SetDamage(0)
    return true
end)

-- Reviving: hold E on a downed player.
hook.Add("PlayerTick", "GK_ReviveAndBleed", function(ply)
    if GK.IsDowned(ply) and CurTime() > ply:GetNW2Float("gk_bleedout_at", math.huge) then
        setDowned(ply, false)
        ply:Kill()
        return
    end

    if not ply:Alive() or GK.IsDowned(ply) or not ply:KeyDown(IN_USE) then
        if ply.GK_Reviving then ply.GK_Reviving:SetNW2Float("gk_revive_progress", 0) ply.GK_Reviving = nil end
        return
    end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * C.ReviveRange,
        filter = ply,
        mask = MASK_SHOT,
    })
    local target = tr.Entity
    if not IsValid(target) or not target:IsPlayer() or not GK.IsDowned(target) then
        if ply.GK_Reviving then ply.GK_Reviving:SetNW2Float("gk_revive_progress", 0) ply.GK_Reviving = nil end
        return
    end

    ply.GK_Reviving = target
    local p = target:GetNW2Float("gk_revive_progress", 0) + FrameTime() / C.ReviveTime
    target:SetNW2Float("gk_revive_progress", p)
    if p >= 1 then
        GK.Revive(target, ply)
        ply.GK_Reviving = nil
    end
end)

hook.Add("PlayerSpawn", "GK_ResetDowned", function(ply)
    setDowned(ply, false)
    ply:SetNW2Bool("gk_gored", false)
    ply:SetNW2Float("gk_hurt_until", 0)
    ply.GK_LastHitgroup = nil
end)

hook.Add("PlayerDeath", "GK_DeathState", function(ply)
    setDowned(ply, false)
end)

-- A heavy hit (25+ in one go) leaves you seeing scratched and grey for a few
-- seconds (cl_status.lua).
hook.Add("PostEntityTakeDamage", "GK_WoundScreen", function(ent, d, took)
    if took and ent:IsPlayer() and ent:Alive() and d:GetDamage() >= 25 then ent:SetNW2Float("gk_wound_at", CurTime()) end
end)

-- WK's health regen: 0.15 a second of its 10 health (1.5 of our 100), after
-- a few seconds without being hurt, up to full. Not while downed.
local cvRegen = CreateConVar("gk_health_regen", "1.5", FCVAR_ARCHIVE, "Health back per second when not hurt for a while (WK 0.15 of 10)")
hook.Add("PostEntityTakeDamage", "GK_RegenPause", function(ent, d, took) if took and ent:IsPlayer() then ent.GK_HurtAt = CurTime() end end)
timer.Create("GK_HealthRegen", 0.5, 0, function()
    local per = cvRegen:GetFloat() * 0.5
    if per <= 0 then return end
    for _, p in ipairs(player.GetAll()) do
        if p:Alive() and not GK.IsDowned(p) and p:Health() < p:GetMaxHealth() and CurTime() - (p.GK_HurtAt or 0) > 4 then
            p.GK_RegenAcc = (p.GK_RegenAcc or 0) + per
            if p.GK_RegenAcc >= 1 then
                local n = math.floor(p.GK_RegenAcc)
                p.GK_RegenAcc = p.GK_RegenAcc - n
                p:SetHealth(math.min(p:GetMaxHealth(), p:Health() + n))
            end
        end
    end
end)
