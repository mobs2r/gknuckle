-- Fists, punches, blocks and the kick's rules.
--
--   Q / E with nothing in that hand or its pocket raises that hand as a fist
--   (pocketed items always come out first, as in White Knuckle). Q/E again
--   lowers it; picking anything up lowers it too.
--   A fist's mouse button punches, CS:GO Danger Zone style: tap for a quick
--   jab (a kick's damage), or hold to wind up and let go for the heavy punch
--   (double a kick's damage at full wind-up, and a longer lunge). The fist
--   stays closed through it.
--   Neither punches nor kicks knock you down... except a kick to the head:
--   that's a light stagger (a short ragdoll, sh_stagger.lua).
--   Hold R with a fist up to block: a fist covers its own side, an open hand
--   doesn't; both fists up covers both (and stops the head kick). A blow that
--   lands on a block does no damage at all, but holding it costs a jump's
--   stamina; too tired to pay, the guard breaks and the blow lands in full.
--   Punches and kicks cost half a jump's stamina each; too tired, no swing.
--   Kicks are always the right leg (animated on the model below).
AddCSLuaFile()

GK.Melee = GK.Melee or {}
local M = GK.Melee
M.KICK_DAMAGE = 5
M.PUNCH_DAMAGE = M.KICK_DAMAGE * 2
M.PUNCH_RANGE = 64
M.PUNCH_COOLDOWN = 0.45 -- after a heavy punch
M.JAB_DAMAGE = M.KICK_DAMAGE
M.JAB_COOLDOWN = 0.28
M.TAP_TIME = 0.2     -- let go sooner than this: a jab
M.CHARGE_TIME = 0.8  -- held this long: full wind-up

-- How wound up a punch is (0-1), from when the button went down (0 = not winding).
function M.Charge(ply, side)
    local t0 = ply:GetNW2Float("gk_punch_charge_" .. side, 0)
    if t0 == 0 then return 0, false end
    local held = CurTime() - t0
    return math.Clamp((held - M.TAP_TIME) / (M.CHARGE_TIME - M.TAP_TIME), 0, 1), true
end

function GK.HasFist(ply, side) return ply:GetNW2Bool("gk_fist_" .. side, false) end

-- Stamina: a jump's cost (sh_movement.lua) is the unit.
function M.JumpCost() return GK.Config.StaminaJumpCost or 8 end
function M.SwingCost() return M.JumpCost() * 0.5 end
-- Pays amount from ply's stamina; false (and nothing paid) if there isn't enough.
function M.Spend(ply, amount)
    local s = GK.Stamina(ply)
    if s < amount then return false end
    GK.AddStamina(ply, -amount)
    return true
end
function GK.IsBlocking(ply) return ply:GetNW2Bool("gk_blocking", false) end

-- How much of a blow from `from` gets through a block (1 = all of it).
function M.BlockMult(victim, from)
    if not GK.IsBlocking(victim) then return 1, false end
    local l, r = GK.HasFist(victim, "l"), GK.HasFist(victim, "r")
    if l and r then return 0.2, true end
    local rightSide = (from - victim:GetPos()):Dot(victim:GetRight()) > 0
    if (rightSide and r) or (not rightSide and l) then return 0.4, false end
    return 1, false
end

-- The head: near the head bone, or a head hitgroup.
function M.IsHeadHit(victim, pos)
    local b = victim:LookupBone("ValveBiped.Bip01_Head1")
    local head = b and victim:GetBonePosition(b) or victim:EyePos()
    return pos:Distance(head) < 16
end

if SERVER then
    function M.ToggleFist(ply, side)
        local inv = GK.Inv.Get(ply)
        if inv.slots["hand_" .. side] or inv.slots["pocket_" .. side] then return false end
        local on = not GK.HasFist(ply, side)
        ply:SetNW2Bool("gk_fist_" .. side, on)
        if on then
            -- Fists up means fighting on the ground: let go of anything you're climbing on.
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) and wep.Grips then
                for s, g in pairs(wep.Grips) do if g.kind == "world" or s == side then wep:Release(s, true) end end
            end
        end
        ply:EmitSound(on and "physics/flesh/flesh_impact_hard1.wav" or "physics/flesh/flesh_impact_bullet2.wav", 50, on and 140 or 160)
        return true
    end

    -- An item in that hand lowers the fist.
    hook.Add("Think", "GK_FistItems", function()
        for _, ply in ipairs(player.GetAll()) do
            for _, side in ipairs({ "l", "r" }) do
                if GK.HasFist(ply, side) and GK.Inv.HandItem(ply, side) then ply:SetNW2Bool("gk_fist_" .. side, false) end
                if not GK.HasFist(ply, side) and ply:GetNW2Float("gk_punch_charge_" .. side, 0) ~= 0 then ply:SetNW2Float("gk_punch_charge_" .. side, 0) end
            end
            local block = (GK.HasFist(ply, "l") or GK.HasFist(ply, "r")) and ply:KeyDown(IN_RELOAD)
            if block ~= GK.IsBlocking(ply) then ply:SetNW2Bool("gk_blocking", block) end
        end
    end)

    -- One blow against a player: damage through any block, and what happens.
    function M.Hit(attacker, victim, dmg, pos, dir, isKick)
        local mult, strongGuard = M.BlockMult(victim, attacker:GetPos())
        if mult < 1 then
            -- On the guard: nothing gets through, if they can pay for holding it.
            if M.Spend(victim, M.JumpCost()) then
                mult = 0
            else
                mult, strongGuard = 1, false -- too tired: the guard breaks
            end
        end
        if mult > 0 then
            local d = DamageInfo()
            d:SetDamage(dmg * mult) d:SetDamageType(DMG_CLUB) d:SetAttacker(attacker) d:SetInflictor(attacker)
            d:SetDamagePosition(pos) d:SetDamageForce(dir * 2000)
            victim:TakeDamageInfo(d)
        end
        victim:ViewPunch(Angle(math.Rand(-6, 6) * math.max(mult, 0.3), math.Rand(-6, 6) * math.max(mult, 0.3), 0))
        if mult < 1 then
            victim:EmitSound("physics/flesh/flesh_impact_hard" .. math.random(1, 6) .. ".wav", 70, 90)
        else
            victim:EmitSound("physics/body/body_medium_impact_hard" .. math.random(1, 6) .. ".wav", 70)
        end
        -- A kick to the head (not stopped by a two-fist guard): a light stagger.
        if isKick and mult > 0 and M.IsHeadHit(victim, pos) then -- blocked: no stagger
            GK.Ragdoll(victim, dir * GK.Config.KickForce, GK.Stagger and GK.Stagger.LIGHT_TIME or 1.5)
            return "head"
        end
        victim:SetVelocity(Vector(dir.x, dir.y, 0):GetNormalized() * 120 * mult)
        return "body"
    end

    -- The fist's button, every tick: down winds up, let go throws it.
    function M.PunchInput(ply, side, down)
        local winding = ply:GetNW2Float("gk_punch_charge_" .. side, 0) ~= 0
        if down and not winding then
            if (ply["GK_NextPunch_" .. side] or 0) > CurTime() then return end
            ply:SetNW2Float("gk_punch_charge_" .. side, CurTime())
        elseif not down and winding then
            local c = M.Charge(ply, side)
            local tap = CurTime() - ply:GetNW2Float("gk_punch_charge_" .. side, 0) < M.TAP_TIME
            ply:SetNW2Float("gk_punch_charge_" .. side, 0)
            M.Punch(ply, side, tap and 0 or c)
        end
    end

    -- charge: 0 = a quick jab, 1 = a full wind-up (nil: full).
    function M.Punch(ply, side, charge)
        charge = charge or 1
        if not GK.HasFist(ply, side) or GK.IsRagdolled(ply) or GK.IsDowned(ply) then return end
        local key = "GK_NextPunch_" .. side
        if (ply[key] or 0) > CurTime() then return end
        if not M.Spend(ply, M.SwingCost()) then return end -- too tired to swing
        ply[key] = CurTime() + Lerp(charge, M.JAB_COOLDOWN, M.PUNCH_COOLDOWN)
        ply.GK_LastPunchCharge = charge
        -- A lunge into it, longer the more it was wound up.
        local aim = ply:GetAimVector()
        local flat = Vector(aim.x, aim.y, 0):GetNormalized()
        if ply:OnGround() then ply:SetVelocity(flat * Lerp(charge, 70, 220)) end
        local dmg = Lerp(charge, M.JAB_DAMAGE, M.PUNCH_DAMAGE)
        ply:SetNW2Float("gk_punch_" .. side, CurTime())
        local src = ply:GetShootPos()
        local tr = util.TraceHull({ start = src, endpos = src + aim * M.PUNCH_RANGE, mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8),
            mask = MASK_SHOT_HULL, filter = ply })
        ply:EmitSound("weapons/slam/throw.wav", 60, Lerp(charge, 150, 115))
        if not tr.Hit then return end
        local ent = tr.Entity
        if IsValid(ent) and ent:IsPlayer() then
            M.Hit(ply, ent, dmg, tr.HitPos, aim, false)
        elseif IsValid(ent) then
            local d = DamageInfo()
            d:SetDamage(dmg * 3) d:SetDamageType(DMG_CLUB) d:SetAttacker(ply) d:SetInflictor(ply)
            d:SetDamagePosition(tr.HitPos) d:SetDamageForce(aim * 3000)
            ent:TakeDamageInfo(d)
            ent:EmitSound("physics/flesh/flesh_impact_hard" .. math.random(1, 6) .. ".wav", 65)
        else
            ply:EmitSound("physics/concrete/concrete_impact_hard" .. math.random(1, 3) .. ".wav", 60, 120)
        end
    end
end

if CLIENT then
    -- The kick: the right leg swings up and out (any model with ValveBiped legs).
    local KICK_T = 0.45
    -- Poses ent's right leg for owner's kick (the player, or our first-person legs).
    function GK.KickPose(ent, owner)
        local t = CurTime() - owner:GetNW2Float("gk_kick_at", 0)
        local thigh, calf = ent:LookupBone("ValveBiped.Bip01_R_Thigh"), ent:LookupBone("ValveBiped.Bip01_R_Calf")
        if not thigh then return end
        if t >= 0 and t < KICK_T then
            -- A real kick in four beats: the knee chambers up, the leg snaps out
            -- straight (and reaches, the thigh pushed forward from the hip),
            -- holds a moment at full stretch, then pulls back.
            local f = t / KICK_T
            local function ease(x) x = math.Clamp(x, 0, 1) return x * x * (3 - 2 * x) end
            local lift, bend, reach
            if f < 0.25 then           -- chamber
                local e = ease(f / 0.25)
                lift, bend, reach = 70 * e, 95 * e, 0
            elseif f < 0.45 then       -- snap out
                local e = ease((f - 0.25) / 0.2)
                lift, bend, reach = 70 + 35 * e, 95 * (1 - e), 7 * e
            elseif f < 0.6 then        -- full stretch
                lift, bend, reach = 105, 0, 7
            else                       -- pull back down
                local e = ease((f - 0.6) / 0.4)
                lift, bend, reach = 105 * (1 - e), 30 * math.sin(e * math.pi), 7 * (1 - e)
            end
            ent:ManipulateBoneAngles(thigh, Angle(0, 0, -lift))
            ent:ManipulateBonePosition(thigh, Vector(reach, 0, 0))
            if calf then ent:ManipulateBoneAngles(calf, Angle(0, 0, bend)) end
            ent.GK_Kicking = true
        elseif ent.GK_Kicking then
            ent:ManipulateBoneAngles(thigh, angle_zero)
            ent:ManipulateBonePosition(thigh, vector_origin)
            if calf then ent:ManipulateBoneAngles(calf, angle_zero) end
            ent.GK_Kicking = nil
        end
    end
    hook.Add("PrePlayerDraw", "GK_KickAnim", function(ply) GK.KickPose(ply, ply) end)
end
