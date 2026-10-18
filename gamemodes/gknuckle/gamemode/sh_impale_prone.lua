-- Pinned to the floor (the impalement rework, per the user's sketch): a rebar
-- through your torso into the floor lays you flat, back or chest to the floor,
-- your body as low as a prone one. Chest down, you stare at the floor; back
-- down, you look out along the rod. Dragging yourself off slides you up the rod
-- (sh_impale.lua's progress); once off you bleed the glowing crystal blood a
-- while. Wall pins stay as they were (standing, back to the wall).
--
-- And the explosive rod: a direct hit gibs you outright. No corpse: bone and
-- flesh chunks, crystal blood, a burn mark on the floor.
AddCSLuaFile()

local C = GK.Config

function GK.ImpaleProne(ply) return GK.IsImpaled(ply) and ply:GetNW2Bool("gk_impale_prone", false) end

local PRONE_HULL_MIN, PRONE_HULL_MAX = Vector(-12, -12, 0), Vector(12, 12, 18)
local PRONE_VIEW = Vector(0, 0, 12)

-- The look cone's centre when pinned prone: the floor, or out along the rod.
function GK.ProneLook(ply)
    local yaw = ply:GetNW2Angle("gk_impale_look").y
    if GK.ImpaledBack(ply) then return Angle(70, yaw, 0) end   -- chest down: the floor
    local axis = ply:GetNW2Vector("gk_impale_axis", Vector(0, 0, 1))
    return (axis + Vector(0, 0, 0.2)):Angle()                -- back down: out along the rod
end

if SERVER then
    -- After a floor stake (GK.RebarHit): lie them down.
    function GK.MakeProne(ply)
        if not GK.IsImpaled(ply) then return end
        ply:SetNW2Bool("gk_impale_prone", true)
        ply:SetHull(PRONE_HULL_MIN, PRONE_HULL_MAX)
        ply:SetHullDuck(PRONE_HULL_MIN, PRONE_HULL_MAX)
        ply:SetViewOffset(PRONE_VIEW)
        ply:SetViewOffsetDucked(PRONE_VIEW)
        local look = GK.ProneLook(ply)
        ply:SetNW2Angle("gk_impale_look", look)
        ply:SetEyeAngles(look)
    end

    local function standUp(ply)
        if not ply:GetNW2Bool("gk_impale_prone", false) then return end
        ply:SetNW2Bool("gk_impale_prone", false)
        if GK.ApplyHull then GK.ApplyHull(ply) end
        ply:SetViewOffset(Vector(0, 0, 64))
        ply:SetViewOffsetDucked(Vector(0, 0, 28))
    end

    -- Off the bar (or dead): back up on your feet.
    hook.Add("Think", "GK_ImpaleProne", function()
        for _, ply in ipairs(player.GetAll()) do
            if ply:GetNW2Bool("gk_impale_prone", false) and not GK.IsImpaled(ply) then standUp(ply) end
        end
    end)
    hook.Add("PlayerSpawn", "GK_ImpaleProneReset", function(ply) ply:SetNW2Bool("gk_impale_prone", false) end)

    -- Bleeding after coming off: the glowing crystal blood, in your colour.
    hook.Add("PlayerTick", "GK_GlowBleed", function(ply)
        if (ply.GK_BleedUntil or 0) <= CurTime() or GK.IsImpaled(ply) then return end
        if (ply.GK_NextGlowBleed or 0) > CurTime() then return end
        ply.GK_NextGlowBleed = CurTime() + 0.6
        if GK.CrystalBurst then GK.CrystalBurst(ply, ply:GetPos() + Vector(0, 0, 30), 3, Vector(0, 0, -1)) end
    end)

    -- A direct hit from an explosive rod: nothing left but chunks.
    local CHUNKS = {
        "models/gibs/hgibs_spine.mdl", "models/gibs/hgibs_scapula.mdl", "models/gibs/hgibs_rib.mdl", "models/gibs/hgibs_rib.mdl",
        "models/gibs/antlion_gib_small_1.mdl", "models/gibs/antlion_gib_small_2.mdl", "models/gibs/antlion_gib_medium_1.mdl",
        "models/gibs/antlion_gib_medium_2.mdl",
    }
    function GK.Gib(ply, attacker, pos)
        if not ply:Alive() then return end
        local at = ply:WorldSpaceCenter()
        ply:SetNW2Bool("gk_gibbed", true)
        if GK.CrystalBurst then
            GK.CrystalBurst(ply, at, 40, vector_up)
            GK.CrystalBurst(ply, at, 30, VectorRand())
        end
        for _, mdl in ipairs(CHUNKS) do
            local g = ents.Create("gk_trash")
            g:SetModel(mdl)
            g:SetPos(at + VectorRand() * 10)
            g.GK_Harmless = true
            g.GK_Linger = 30
            g:Spawn()
            g:SetLocalVelocity(VectorRand() * 260 + Vector(0, 0, 220))
        end
        local floor = util.TraceLine({ start = at, endpos = at - Vector(0, 0, 200), mask = MASK_SOLID_BRUSHONLY })
        util.Decal("Scorch", at, at - Vector(0, 0, 200))
        if floor.Hit then util.Decal("Blood", floor.HitPos + Vector(0, 0, 4), floor.HitPos - Vector(0, 0, 8)) end
        local d = DamageInfo()
        d:SetDamage(ply:Health() + 1000) d:SetDamageType(DMG_BLAST)
        d:SetAttacker(IsValid(attacker) and attacker or game.GetWorld()) d:SetInflictor(game.GetWorld())
        d:SetDamagePosition(pos or at)
        ply:TakeDamageInfo(d)
        ply:EmitSound("physics/flesh/flesh_bloody_break.wav", 90, 80)
    end
    hook.Add("PlayerSpawn", "GK_GibReset", function(ply) ply:SetNW2Bool("gk_gibbed", false) end)
    hook.Add("PlayerDeath", "GK_GibNoCorpse", function(ply)
        if not ply:GetNW2Bool("gk_gibbed", false) then return end
        timer.Simple(0, function()
            if not IsValid(ply) then return end
            local rag = ply:GetRagdollEntity()
            if IsValid(rag) then rag:Remove() end
        end)
    end)
end

-- Prone movement and view (both realms): pinned flat, looking within the cone.
hook.Add("SetupMove", "GK_ImpaleProne", function(ply, mv)
    if not GK.ImpaleProne(ply) then return end
    mv:SetButtons(bit.bor(mv:GetButtons(), IN_DUCK))
end)

if CLIENT then
    -- Lying flat: the model is drawn on its back or front, along the floor.
    hook.Add("PrePlayerDraw", "GK_ImpaleProneDraw", function(ply)
        if not GK.ImpaleProne(ply) then return end
        local yaw = ply:GetNW2Angle("gk_impale_look").y
        ply:SetRenderAngles(Angle(GK.ImpaledBack(ply) and 90 or -90, yaw, 0))
        ply:SetRenderOrigin(ply:GetPos() + Vector(0, 0, 10) - Angle(0, yaw, 0):Forward() * (GK.ImpaledBack(ply) and 30 or -30))
    end)
    hook.Add("PostPlayerDraw", "GK_ImpaleProneDraw", function(ply)
        if ply.GK_ProneDrawn or GK.ImpaleProne(ply) then ply:SetRenderOrigin() ply.GK_ProneDrawn = GK.ImpaleProne(ply) end
    end)
    -- Gibbed: no corpse.
    hook.Add("CreateClientsideRagdoll", "GK_GibNoCorpse", function(ent, rag)
        if IsValid(ent) and ent:IsPlayer() and ent:GetNW2Bool("gk_gibbed", false) then
            rag:SetNoDraw(true)
        end
    end)
end
