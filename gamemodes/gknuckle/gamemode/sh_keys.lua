-- Kick and drop live on their own keys so they work with any item out
-- (R stays reload). Rebind with gk_kick_key / gk_drop_key, e.g. `gk_kick_key 33`
-- (KEY_ enum numbers), or from the console: lua_run_cl print(KEY_F).
--   F  kick   (or, with a prop lifted in a mind-hand, throw it)
--   G  drop the item in your hand (right first) to free that hand
--   Q / E  pocket the left / right hand's item, or take it back out
--   R  reload a held item (takes both hands)

local C = GK.Config

if CLIENT then
    CreateClientConVar("gk_kick_key", tostring(KEY_F), true, true, "Key code for kicking")
    CreateClientConVar("gk_drop_key", tostring(KEY_G), true, true, "Key code for dropping your held item")
end

-- No arms, no flashlight: F is the kick.
function GM:PlayerSwitchFlashlight(ply, on)
    return not on
end

if SERVER then

-- Kick: anyone caught by it is knocked down into a ragdoll and stunned.
-- It's your own leg, so it works even with the link offline.
function GK.Kick(ply)
    if (ply.GK_NextKick or 0) > CurTime() then return end
    -- On a rebar you went onto forwards: kick yourself off it (sh_impale.lua).
    if GK.IsImpaled(ply) then
        ply.GK_NextKick = CurTime() + 0.4
        GK.ImpaleKick(ply)
        return
    end

    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.ThrowHeld and GK.IsChipOnline(ply) and wep:ThrowHeld(ply) then
        ply.GK_NextKick = CurTime() + 0.4
        return
    end
    if not GK.HasLegs(ply) or GK.OneLegged(ply) or GK.IsDowned(ply) or GK.IsRagdolled(ply) or GK.IsImpaled(ply) then return end
    -- Half a jump's stamina (sh_melee.lua); too tired, no kick.
    if GK.Melee and GK.Melee.Spend and not GK.Melee.Spend(ply, GK.Melee.SwingCost()) then return end
    ply.GK_NextKick = CurTime() + C.KickCooldown

    -- Kick-boost: crouched in the air and looking down, a kick off the floor
    -- below launches you back the way you kicked, like a small rocket jump
    -- (weaker than a boom bug's blast). Your fall is cancelled first.
    local aim = ply:GetAimVector()
    if not ply:OnGround() and ply:Crouching() and aim.z < -0.3 then
        local feet = ply:GetPos() + Vector(0, 0, 10)
        local below = util.TraceHull({
            start = feet, endpos = feet + aim * (C.KickBoostReach or 90),
            mins = Vector(-8, -8, -4), maxs = Vector(8, 8, 4), filter = ply, mask = MASK_PLAYERSOLID,
        })
        local solid = below.Hit and (below.HitWorld or (IsValid(below.Entity) and (not IsValid(below.Entity:GetPhysicsObject())
            or not below.Entity:GetPhysicsObject():IsMotionEnabled())))
        if solid then
            local push = (-aim + Vector(0, 0, 0.5)):GetNormalized() * (C.KickBoost or 380)
            local vel = ply:GetVelocity()
            ply:SetVelocity(Vector(0, 0, math.max(0, -vel.z)) + push)
            ply:SetNW2Float("gk_kick_at", CurTime())
            ply:ViewPunch(Angle(-6, 0, math.Rand(-3, 3)))
            ply:EmitSound("physics/concrete/concrete_impact_hard" .. math.random(1, 3) .. ".wav", 75, 90)
            ply:EmitSound("weapons/slam/throw.wav", 65, 70)
            local fx = EffectData() fx:SetOrigin(below.HitPos) fx:SetNormal(below.HitNormal) fx:SetScale(1)
            util.Effect("ThumperDust", fx, true, true)
            return
        end
    end

    local start = ply:GetShootPos() - Vector(0, 0, 30)
    local tr = util.TraceHull({
        start = start,
        endpos = start + ply:GetAimVector() * C.KickRange,
        mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10),
        filter = ply,
        mask = MASK_SHOT_HULL,
    })
    ply:ViewPunch(Angle(4, 0, 0))
    ply:SetNW2Float("gk_kick_at", CurTime()) -- the right leg swings (sh_melee.lua)
    ply:EmitSound("weapons/slam/throw.wav", 65, 80)
    if not tr.Hit then return end

    local ent = tr.Entity
    local dir = ply:GetAimVector()
    dir.z = math.max(dir.z, 0.2)
    if IsValid(ent) and ent:IsPlayer() then
        -- A kick hurts; only a kick to the head knocks them down (sh_melee.lua),
        -- and a block soaks some or all of it.
        GK.Melee.Hit(ply, ent, GK.Melee.KICK_DAMAGE, tr.HitPos, dir, true)
    elseif IsValid(ent) then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) and phys:IsMotionEnabled() then
            phys:ApplyForceOffset(dir * C.KickForce * phys:GetMass() * 0.5, tr.HitPos)
            ent.GK_Thrower = ply
        end
        ent:EmitSound("physics/wood/wood_box_impact_hard" .. math.random(1, 3) .. ".wav")
        -- A kick is a blow: pods pop, crates break, turrets topple, pests die.
        local d = DamageInfo()
        d:SetDamage(15) d:SetDamageType(DMG_CLUB) d:SetAttacker(ply) d:SetInflictor(ply)
        d:SetDamageForce(dir * C.KickForce * 10) d:SetDamagePosition(tr.HitPos)
        ent:TakeDamageInfo(d)
    else
        -- Kick off a wall to push yourself back.
        ply:SetVelocity(-ply:GetAimVector() * 250)
        ply:EmitSound("physics/concrete/concrete_impact_soft" .. math.random(1, 3) .. ".wav")
    end
end

-- E only pockets when you're not looking at something you can use.
local function lookingAtUsable(ply)
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or tr.HitPos:Distance(ply:GetShootPos()) > 100 then return false end
    return ent.Layout ~= nil or ent:GetClass() == "gk_vendor" or (ent:IsPlayer() and GK.IsDowned(ent)) -- vending machines (gk_vendor, gk_vendor_big)
end

hook.Add("PlayerButtonDown", "GK_Keys", function(ply, button)
    if button == ply:GetInfoNum("gk_kick_key", KEY_F) then
        GK.Kick(ply)
    elseif button == KEY_X then
        GK.Inv.SwapHands(ply)
    elseif button == KEY_1 then
        GK.Inv.DropHand(ply, "l") -- WK: 1 drops the left hand's item, 2 the right's
    elseif button == KEY_2 then
        GK.Inv.DropHand(ply, "r")
    elseif button == ply:GetInfoNum("gk_drop_key", KEY_G) then
        GK.Inv.DropHand(ply)
    elseif button == KEY_Q then
        -- The pocket first (WK); with nothing to swap, the hand becomes a fist (sh_melee.lua).
        if GK.Inv.HasPocketable(ply, "l") then GK.Inv.Pocket(ply, "l") else GK.Melee.ToggleFist(ply, "l") end
    elseif button == KEY_E then
        if lookingAtUsable(ply) then return end
        if GK.Inv.HasPocketable(ply, "r") then GK.Inv.Pocket(ply, "r") else GK.Melee.ToggleFist(ply, "r") end
    end
end)

-- R reloads a held item (two-handed).
hook.Add("KeyPress", "GK_Reload", function(ply, key)
    if key == IN_RELOAD then GK.Inv.Reload(ply) end
end)

end

if CLIENT then
    -- 1 and 2 drop items (above), not weapon-slot switches.
    hook.Add("PlayerBindPress", "GK_DropSlots", function(_, bind, pressed)
        if bind == "slot1" or bind == "slot2" then return true end
    end)
end
