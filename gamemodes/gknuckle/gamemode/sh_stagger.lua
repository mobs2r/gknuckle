-- Staggers, by severity.
--
--   Light (a kick to the head, a heavy blow): a short ragdoll and you're up
--   again: GK.Ragdoll(ply, vel, LIGHT_TIME) in sv_ragdoll.lua.
--
--   Full (the red overdraw bar shattering): you collapse into a ragdoll and
--   stay down until your grip/stamina has fully refilled, or a teammate grabs
--   you and pulls you up. You are NOT downed: your hands go red, but you can
--   still open the inventory and use what you hold (a gun, rebar) to defend
--   yourself. Your view is the ragdoll's head: you can look 45 degrees either
--   way of where it faces, and that's where you use things. Getting up gives a
--   few seconds where you can't be fully staggered again (no stun-locking).
AddCSLuaFile()

GK.Stagger = GK.Stagger or {}
local S = GK.Stagger
S.LIGHT_TIME = 1.5
local CONE = 45         -- degrees either way of the head's facing
local IMMUNE = 4        -- seconds after getting up
local REGEN = 12        -- stamina per second while lying there

function GK.IsStaggered(ply) return IsValid(ply) and ply:GetNW2Bool("gk_staggered", false) end
function S.Ragdoll(ply) return ply:GetNW2Entity("gk_stagger_rag") end

-- The ragdoll's head: position and facing.
function S.Head(rag)
    if not IsValid(rag) then return nil end -- the body can go away mid-frame (recovered, removed)
    local bone = rag:LookupBone("ValveBiped.Bip01_Head1")
    if bone then
        local m = rag:GetBoneMatrix(bone)
        if m then
            -- ValveBiped heads face along the bone's -Y... use the
            -- direction from neck to head and the pelvis' facing to get "out".
            local pos = m:GetTranslation()
            local ang = m:GetAngles()
            local fwd = ang:Right() * -1
            return pos + fwd * 4, fwd
        end
    end
    return rag:WorldSpaceCenter(), rag:GetForward()
end

-- Keep a view angle within CONE of the head's facing.
function S.Clamp(ang, fwd)
    local want = ang:Forward()
    local dot = math.Clamp(want:Dot(fwd), -1, 1)
    if math.deg(math.acos(dot)) <= CONE then return ang end
    -- Slerp-ish: rotate fwd toward want by CONE degrees.
    local axis = fwd:Cross(want)
    if axis:LengthSqr() < 1e-6 then return fwd:Angle() end
    axis:Normalize()
    local a = fwd:Angle()
    a:RotateAroundAxis(axis, CONE)
    return a
end

if SERVER then
    function S.Full(ply)
        if not IsValid(ply) or not ply:Alive() or GK.IsStaggered(ply) or GK.IsRagdolled(ply) or GK.IsDowned(ply) then return end
        if ply:GetNW2Float("gk_stagger_immune", 0) > CurTime() then return end
        GK.SetStamina(ply, 0) -- the bar is broken: it fills back up from empty
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep.Grips then for side in pairs(wep.Grips) do wep:Release(side) end end

        local rag = ents.Create("prop_ragdoll")
        rag:SetModel(ply:GetModel())
        rag:SetPos(ply:GetPos())
        rag:SetAngles(Angle(0, ply:EyeAngles().y, 0))
        rag:SetSkin(ply:GetSkin())
        rag:Spawn()
        rag:Activate()
        if GK.ScaleArmBones then GK.ScaleArmBones(rag) end
        local vel = ply:GetVelocity()
        for i = 0, rag:GetPhysicsObjectCount() - 1 do
            local phys = rag:GetPhysicsObjectNum(i)
            if IsValid(phys) then
                local pos, ang = ply:GetBonePosition(rag:TranslatePhysBoneToBone(i))
                if pos then phys:SetPos(pos) phys:SetAngles(ang) end
                phys:SetVelocity(vel)
            end
        end
        rag.GK_StaggerOwner = ply
        rag:SetNW2Entity("gk_stagger_owner", ply)

        ply:SetNW2Entity("gk_stagger_rag", rag)
        ply:SetNW2Bool("gk_staggered", true)
        ply:SetNoDraw(true)
        ply:SetNotSolid(true)
        ply:SetMoveType(MOVETYPE_NONE)
        ply:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 70)
    end

    -- Back on your feet where your body lies.
    function S.Recover(ply, helper)
        if not GK.IsStaggered(ply) then return end
        local rag = S.Ragdoll(ply)
        ply:SetNW2Bool("gk_staggered", false)
        ply:SetNW2Entity("gk_stagger_rag", NULL)
        ply:SetNoDraw(false)
        ply:SetNotSolid(false)
        ply:SetMoveType(MOVETYPE_WALK)
        ply:SetNW2Float("gk_stagger_immune", CurTime() + IMMUNE)
        if IsValid(rag) then
            local tr = util.TraceHull({ start = rag:GetPos() + Vector(0, 0, 40), endpos = rag:GetPos() + Vector(0, 0, 4),
                mins = Vector(-12, -12, 0), maxs = Vector(12, 12, 72), mask = MASK_PLAYERSOLID, filter = { ply, rag } })
            ply:SetPos(tr.HitPos)
            ply:SetEyeAngles(Angle(0, ply:EyeAngles().y, 0))
            rag:Remove()
        end
        if IsValid(helper) then ply:EmitSound("physics/body/body_medium_impact_soft" .. math.random(1, 7) .. ".wav", 65) end
    end

    -- Lying there: follow the head, get grip back, get up once it's full.
    hook.Add("Tick", "GK_Stagger", function()
        local dt = engine.TickInterval()
        for _, ply in ipairs(player.GetAll()) do
            if GK.IsStaggered(ply) then
                local rag = S.Ragdoll(ply)
                if not IsValid(rag) or not ply:Alive() then
                    S.Recover(ply)
                else
                    local head = S.Head(rag)
                    ply:SetPos(head - ply:GetViewOffset())
                    GK.AddStamina(ply, REGEN * dt)
                    local st = GK.Stamina(ply)
                    if st >= GK.Config.StaminaMax then S.Recover(ply) end
                end
            end
        end
    end)

    -- Hits on the lying body land on its owner.
    hook.Add("EntityTakeDamage", "GK_StaggerBody", function(ent, d)
        local owner = ent.GK_StaggerOwner
        if IsValid(owner) and GK.IsStaggered(owner) and owner ~= d:GetAttacker() then
            owner:TakeDamageInfo(d)
            return true
        end
    end)

    hook.Add("DoPlayerDeath", "GK_StaggerDeath", function(ply)
        local rag = S.Ragdoll(ply)
        if IsValid(rag) then rag:Remove() end
        ply:SetNW2Bool("gk_staggered", false)
        ply:SetNW2Entity("gk_stagger_rag", NULL)
        ply:SetNoDraw(false)
        ply:SetNotSolid(false)
    end)
    hook.Add("PlayerSpawn", "GK_StaggerReset", function(ply)
        ply:SetNW2Bool("gk_staggered", false)
        ply:SetNW2Entity("gk_stagger_rag", NULL)
    end)
end

-- Not moving while you lie there (predicted on both realms).
hook.Add("SetupMove", "GK_StaggerMove", function(ply, mv, cmd)
    if not GK.IsStaggered(ply) then return end
    mv:SetForwardSpeed(0) mv:SetSideSpeed(0) mv:SetUpSpeed(0)
    mv:SetVelocity(vector_origin)
    mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(bit.bor(IN_JUMP, IN_DUCK))))
end)

if CLIENT then
    -- The view from the ragdoll's head, within the cone.
    hook.Add("CreateMove", "GK_StaggerAim", function(cmd)
        local ply = LocalPlayer()
        if not GK.IsStaggered(ply) then return end
        local rag = S.Ragdoll(ply)
        if not IsValid(rag) then return end
        local _, fwd = S.Head(rag)
        cmd:SetViewAngles(S.Clamp(cmd:GetViewAngles(), fwd))
    end)
    hook.Add("CalcView", "GK_StaggerView", function(ply, origin, angles, fov)
        if not GK.IsStaggered(ply) then return end
        local rag = S.Ragdoll(ply)
        if not IsValid(rag) then return end
        local pos = S.Head(rag)
        -- Our own head isn't drawn (we're looking out of it).
        if rag.GK_HeadHidden ~= true then
            local b = rag:LookupBone("ValveBiped.Bip01_Head1")
            if b then rag:ManipulateBoneScale(b, vector_origin) end
            rag.GK_HeadHidden = true
        end
        return { origin = pos, angles = angles, fov = fov, drawviewer = false }
    end)
    -- Don't draw our own body's head in our face.
    hook.Add("PrePlayerDraw", "GK_StaggerHide", function(ply) if GK.IsStaggered(ply) then return true end end)
end
