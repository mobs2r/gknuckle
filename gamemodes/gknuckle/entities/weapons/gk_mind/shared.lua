AddCSLuaFile()

-- the Xenium virus's telekinetic "hands": the gKnuckle SWEP folded into the gamemode.
-- Hold LMB/RMB to grip with the left/right mind-hand; let go to release.
--   wall/ledge   -> climb (jump while gripping to launch)
--   heavy prop   -> drag it like White Knuckle's chair/crates (only frozen props hold your weight)
--   light prop   -> lift it like an HL pickup; let go drops it gently, kick (R) throws it
--   player       -> LMB drags them, RMB shoves them
-- Drawn as hologram sprites by cl_hands.lua.

SWEP.Base = "weapon_base"
SWEP.PrintName = "Mind"
SWEP.Author = "mobs2r"
SWEP.Instructions = "Hold LMB/RMB: grip with each mind-hand. Jump while gripping to launch. R: kick / throw."
SWEP.Spawnable = false
SWEP.Slot = 0
SWEP.SlotPos = 0

SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = false
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.GKMindHands = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local C = GK.Config

HAND_IDLE, HAND_GRIP, HAND_HOLD = 0, 1, 2

-- Which mouse button drives which hand. A hand holding an item uses it instead.
local BUTTONS = { l = IN_ATTACK, r = IN_ATTACK2 }

-- Two-handed actions (reloading) make you let go and stop you gripping.
function SWEP:IsBusy()
    local ply = self:GetOwner()
    return IsValid(ply) and ply:GetNW2Float("gk_busy_until", 0) > CurTime()
end

function SWEP:Initialize()
    self:SetHoldType("normal")
    self.NextStaminaTick = 0
    self.Grips = {}
end

function SWEP:Deploy() return true end
function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end

function SWEP:Holster()
    if SERVER then self:ReleaseAll() end
    return true
end

function SWEP:OnRemove()
    if SERVER then self:ReleaseAll() end
end

if SERVER then

local function setStamina(ply, v)
    GK.SetStamina(ply, v)
end

-- anchor = this hand is holding the player's weight (sh_movement springs them to it);
-- top = the hold is a ledge's top surface, so pulling up (W) mantles over it.
-- lip/into: where the ledge's top is and the way over it (sh_movement's mantle).
function SWEP:SetHand(side, state, pos, anchor, top, lip, into)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    ply:SetNW2Int("gk_hand_" .. side, state)
    ply:SetNW2Vector("gk_grip_" .. side, pos or vector_origin)
    ply:SetNW2Bool("gk_anchor_" .. side, anchor or false)
    ply:SetNW2Bool("gk_top_" .. side, top or false)
    ply:SetNW2Vector("gk_lip_" .. side, lip or pos or vector_origin)
    ply:SetNW2Vector("gk_into_" .. side, into or vector_origin)
end

function SWEP:LiftMass(ply)
    return GK.HasSurge(ply) and C.SurgeLiftMass or C.LiftMass
end

function SWEP:Holding()
    for side, g in pairs(self.Grips or {}) do
        if g.kind == "hold" then return side, g end
    end
end

-- Grip targets ---------------------------------------------------------------

function SWEP:Trace(ply)
    local range = GK.GripRange(ply)
    local tr = ply:GetEyeTrace()
    if tr.Hit and tr.HitPos:Distance(ply:GetShootPos()) <= range then return tr end
    -- A near miss still counts (thin bars, rebar stubs, a ledge lip just off the
    -- crosshair): WK's grab is a sphere cast, not a line. A small hull instead.
    -- WK widens its grab sphere with your speed (0.15 to 0.3): fast grabs forgive more.
    local src = ply:GetShootPos()
    local r = 5 + 5 * math.Clamp(ply:GetVelocity():Length() / 400, 0, 1)
    local hull = util.TraceHull({ start = src, endpos = src + ply:GetAimVector() * range,
        mins = Vector(-r, -r, -r), maxs = Vector(r, r, r), mask = MASK_SHOT, filter = ply })
    if hull.Hit and not hull.StartSolid then return hull end
    return nil
end

-- A ledge: a walkable top surface just above and behind where we hit. Returns
-- the lip (a point on that top, just in from the edge) and the way into the
-- wall, or nil. Looks up to an arm's reach above the hand (WK lets you mantle
-- from a hold below the lip), a few depths in so thin walls and rails count,
-- against everything solid: WK rooms' collision is entities (gk_level_chunk),
-- which brush-only traces and PointContents never saw.
local LEDGE_UP = { 4, 10, 18, 28, 40, 52, 64 }
local LEDGE_IN = { 3, 8, 16 }
local TINY = Vector(-2, -2, -2)
function SWEP:LedgeLip(tr)
    local owner = self:GetOwner()
    if tr.HitNormal.z > 0.7 then
        -- The top surface itself: only near its edge (the lip you are reaching
        -- over, toward you), not anywhere out on a floor.
        local f = Angle(0, owner:EyeAngles().y, 0):Forward()
        for _, k in ipairs({ 6, 14, 24 }) do
            local p = tr.HitPos - f * k + Vector(0, 0, 4)
            local down = util.TraceLine({ start = p, endpos = p - Vector(0, 0, 34), mask = MASK_SOLID, filter = owner })
            if not down.Hit then return tr.HitPos, f end
        end
        return nil
    end
    if tr.HitNormal.z < -0.3 then return nil end -- an overhang's underside
    local flat = Vector(tr.HitNormal.x, tr.HitNormal.y, 0)
    if flat:LengthSqr() < 0.01 then return nil end
    flat:Normalize()
    local into = -flat
    for _, h in ipairs(LEDGE_UP) do
        for _, d in ipairs(LEDGE_IN) do
            local probe = tr.HitPos + into * d + Vector(0, 0, h)
            local free = util.TraceHull({ start = probe, endpos = probe, mins = TINY, maxs = -TINY, mask = MASK_SOLID, filter = owner })
            if not free.StartSolid then
                local down = util.TraceLine({ start = probe, endpos = probe - Vector(0, 0, h + 8), mask = MASK_SOLID, filter = owner })
                if down.Hit and not down.StartSolid and down.HitNormal.z > 0.7 then
                    -- Room to get over it: a body-wide gap above the lip.
                    local over = down.HitPos + into * 12 + Vector(0, 0, 2)
                    local room = util.TraceHull({ start = over, endpos = over, mins = Vector(-8, -8, 0), maxs = Vector(8, 8, 30), mask = MASK_PLAYERSOLID, filter = owner })
                    if not room.StartSolid then return down.HitPos, into end
                end
            end
        end
    end
    return nil
end
function SWEP:IsLedge(tr) return self:LedgeLip(tr) ~= nil end

function SWEP:TryGrip(ply, side)
    local tr = self:Trace(ply)
    -- A staggered body (sh_stagger.lua): a teammate's grab pulls them up.
    local body = tr and tr.Entity
    if SERVER and IsValid(body) and body.GK_StaggerOwner then
        local owner = body.GK_StaggerOwner
        -- Only your own side can (your squad in the hub, your team in a run):
        -- whoever knocked you down can't undo it just by grabbing you.
        local mate = IsValid(owner) and GK.SameSide and GK.SameSide(ply, owner)
        if IsValid(owner) and owner ~= ply and mate then GK.Stagger.Recover(owner, ply) end
        self.GripLock = self.GripLock or {} self.GripLock[side] = true
        return nil
    end
    -- Staggered yourself: you can use items, not climb.
    if GK.IsStaggered and GK.IsStaggered(ply) then return nil end
    -- A fist up (either hand) means you're fighting on the ground: no climbing.
    local fists = GK.HasFist and (GK.HasFist(ply, "l") or GK.HasFist(ply, "r"))
    -- A hanging rope (rope rebar) closer than whatever the eye trace hit.
    local rope = not fists and GK.RopeGrip and GK.RopeGrip(ply, tr and tr.HitPos:Distance(ply:GetShootPos()) or GK.GripRange(ply))
    if rope then return { kind = "world", hitpos = rope, top = false } end
    -- A WK handhold (red piton, rebar stub, bar...) in reach, nearer than the wall it's on.
    if GK.HandholdHit and not fists then
        local range = GK.GripRange(ply)
        local hh, d, box, piece = GK.HandholdHit(ply:GetShootPos(), ply:GetAimVector(), range)
        if hh and (not tr or d <= tr.HitPos:Distance(ply:GetShootPos()) + 8) then
            local special = SERVER and GK.HandholdSpecial and GK.HandholdSpecial(piece, box) or nil
            return { kind = "world", hitpos = hh, top = false, special = special, boost = box and box.boost and special or nil }
        end
    end
    if not tr then
        -- Nothing under the crosshair: the hold this hand just left, if it's fresh and still in reach.
        local m = self.GK_Memory and self.GK_Memory[side]
        if m and CurTime() - m.t <= 0.3 and not fists and m.g.hitpos:Distance(ply:GetShootPos()) <= GK.GripRange(ply)
            and (not m.g.entity or IsValid(m.g.entity)) then
            self.GK_Memory[side] = nil
            return table.Copy(m.g)
        end
        return nil
    end
    local ent = tr.Entity

    -- A WK room's collision (gk_level_chunk) is part of the level: grip it like the world.
    local cls = IsValid(ent) and ent:GetClass() or ""
    if fists and (ent:IsWorld() or cls == "gk_level_chunk" or cls == "gk_level_piece" or ent.GKHandhold) then return nil end
    if ent:IsWorld() or cls == "gk_level_chunk" or cls == "gk_level_piece" then
        -- Ledges-only mode doesn't stop goo-slimed hands (Slug Grub): they grab anything.
        if GK.ClimbMode:GetInt() == 1 and not GK.HasBuff(ply, "gooped") then
            -- A WK room's own surfaces only through its handholds (found above,
            -- WK's "edge" ledge holds among them); our map brushes at a real ledge.
            if cls == "gk_level_chunk" or cls == "gk_level_piece" then return nil end
            if not self:IsLedge(tr) then return nil end
        end
        -- The training towers' outer shell is out of bounds, not a wall to climb.
        if string.lower(tr.HitTexture or "") == "gknuckle/brush/wk_tower_wall" then return nil end
        -- WK ice walls (Surface_Ice) can't be held, except with goo-slimed hands.
        if GK.HandholdKindAt and not GK.HasBuff(ply, "gooped") and GK.HandholdKindAt(tr.HitPos) == "ice" then return nil end
        local lip, into = self:LedgeLip(tr)
        return { kind = "world", hitpos = tr.HitPos, top = lip ~= nil, lip = lip, into = into }
    end
    if not IsValid(ent) then return nil end

    -- Items: clicking one with an empty hand puts it in that hand.
    if ent.GKItemClass and GK.Inv.PickupToHand(ply, ent, side) then
        self.GripLock = self.GripLock or {}
        self.GripLock[side] = true -- don't fire it until the button comes up again
        return nil
    end

    -- Buttons (the vending machine's): a click presses them instead of gripping.
    ply.GK_PressSide = side -- e.g. a roach is caught in this hand
    if ent.Press and ent:Press(ply, tr.HitPos) then
        self.GripLock = self.GripLock or {}
        self.GripLock[side] = true
        return nil
    end

    if ent:IsPlayer() then
        if side == "l" then
            ent.GK_GrippedBy = ply
            return { kind = "player", entity = ent }
        end
        self:Shove(ply, ent)
        return nil
    end

    -- Handhold entities (pitons, rebar stubs) have no physics object: grip them like the wall.
    if ent.GKHandhold then
        return { kind = "world", entity = ent, hitpos = tr.HitPos, top = tr.HitNormal.z > 0.7 }
    end

    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return nil end
    if not phys:IsMotionEnabled() then
        local lip, into = self:LedgeLip(tr) -- frozen props climb like walls, ledges and all
        if not lip and GK.ClimbMode:GetInt() == 1 and not GK.HasBuff(ply, "gooped") then return nil end -- WK: ledges only
        return { kind = "world", entity = ent, hitpos = tr.HitPos, top = lip ~= nil, lip = lip, into = into }
    end

    ent:SetPhysicsAttacker(ply)
    if phys:GetMass() <= self:LiftMass(ply) and not self:Holding() then
        local g = { kind = "hold", entity = ent, mass = phys:GetMass(), gravity = phys:IsGravityEnabled() }
        phys:EnableGravity(false)
        phys:SetMass(math.min(10, g.mass))
        ent:EmitSound("weapons/physcannon/physcannon_pickup.wav", 65, GK.HasSurge(ply) and 100 or 130, 0.5)
        return g
    end

    return {
        kind = "drag", entity = ent,
        localpos = ent:WorldToLocal(tr.HitPos),
        dist = math.max(tr.HitPos:Distance(ply:GetShootPos()), 40),
    }
end

-- WK's grab memory: for 0.3 s after letting go (TryGrip), a hand can take the same
-- hold again even if the crosshair has moved off it.

function SWEP:Release(side, gentle)
    local g = self.Grips[side]
    self.Grips[side] = nil
    self:SetHand(side, HAND_IDLE)
    if not g then return end
    if g.kind == "world" then
        -- WK: a hand that lets go of a hold can't grab again for a moment, so
        -- swapping hands is how you climb, not tapping one button.
        self.HandLock = self.HandLock or {}
        self.HandLock[side] = math.max(self.HandLock[side] or 0, CurTime() + (GK.Config.GripReleaseLock or 0.25))
        self.ReleasedAt = self.ReleasedAt or {}
        self.ReleasedAt[side] = CurTime()
    end
    if g.kind == "world" and g.hitpos then
        self.GK_Memory = self.GK_Memory or {}
        self.GK_Memory[side] = { t = CurTime(), g = { kind = "world", entity = g.entity, hitpos = g.hitpos, top = g.top, lip = g.lip, into = g.into, special = g.special } }
    end

    if g.kind == "player" and IsValid(g.entity) then
        g.entity.GK_GrippedBy = nil
    elseif g.kind == "hold" and IsValid(g.entity) then
        local phys = g.entity:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableGravity(g.gravity ~= false)
            phys:SetMass(g.mass)
            if gentle then phys:SetVelocity(phys:GetVelocity() * 0.3) end
        end
    end
    return g
end

-- WK's DropHang: a creature hit (bloodbug charge, turret round, gas bag
-- blast, barnacle tongue) knocks you off whatever you're hanging on. Hanging
-- hands let go and lose some grip, and can't grab again for `lockout` seconds.
-- Held props and items stay put.
function GK.DropHang(ply, lockout, gripLoss)
    if not IsValid(ply) then return end
    local mind = ply:GetWeapon("gk_mind")
    if not IsValid(mind) or not mind.Grips then return end
    local hung = false
    for side, g in pairs(mind.Grips) do
        if g.kind == "world" then mind:Release(side) hung = true end
    end
    if hung then
        GK.AddStamina(ply, -(gripLoss or 1) * 10 * GK.BuffMult(ply, "griploss"))
    end
    mind.GripOutUntil = math.max(mind.GripOutUntil or 0, CurTime() + (lockout or 0.1))
end

function SWEP:ReleaseAll()
    self.Grips = self.Grips or {}
    self:Release("l", true)
    self:Release("r", true)
end

-- The kick key (sh_keys.lua) while holding something throws it like an HL throw (or a grav-gun punt).
function SWEP:ThrowHeld(ply)
    local side = self:Holding()
    if not side then return false end
    local g = self:Release(side)
    local phys = IsValid(g.entity) and g.entity:GetPhysicsObject()
    if IsValid(phys) then
        local surge = GK.HasSurge(ply)
        phys:SetVelocity(ply:GetAimVector() * (surge and C.SurgeThrowSpeed or C.ThrowSpeed) + ply:GetVelocity())
        phys:AddAngleVelocity(VectorRand() * 200)
        g.entity.GK_Thrower = ply
        g.entity:EmitSound(surge and "weapons/physcannon/superphys_launch" .. math.random(1, 4) .. ".wav"
            or "weapons/slam/throw.wav", 75, surge and 100 or 110)
    end
    ply:ViewPunch(Angle(-3, 0, 0))
    -- Don't instantly re-grab what we just threw: that hand waits for the button to come up.
    self.GripLock = self.GripLock or {}
    self.GripLock[side] = true
    return true
end

function SWEP:Shove(ply, ent)
    local dir = (ent:WorldSpaceCenter() - ply:GetShootPos()):GetNormalized()
    dir.z = math.Clamp(dir.z, -0.1, 0.3)
    ent:SetVelocity(dir * C.PlayerPushForce)
    local theirs = ent:GetActiveWeapon()
    if IsValid(theirs) and theirs.Grips then
        for side, g in pairs(theirs.Grips) do
            if g.kind == "player" and g.entity == ply then theirs:Release(side) end
        end
    end
    ent:EmitSound("weapons/physcannon/superphys_small_zap" .. math.random(1, 4) .. ".wav", 70)
end

-- Per-tick grip behaviour ---------------------------------------------------

-- Returns true if this grip is holding the player's weight (drains stamina).
-- The actual hanging/pulling happens in GM:Move (sh_movement.lua) off the anchor NW vars.
function SWEP:UpdateGrip(ply, side, g, count)
    if g.kind == "world" then
        if g.entity then
            -- A handhold prop that got unfrozen (physgun etc.) stops being a handhold.
            local phys = IsValid(g.entity) and g.entity:GetPhysicsObject()
            if not IsValid(g.entity) or (IsValid(phys) and phys:IsMotionEnabled()) then
                self:Release(side)
                return false
            end
        end
        return true
    end

    if not IsValid(g.entity) then self:Release(side) return false end

    if g.kind == "player" then
        if not g.entity:Alive() then self:Release(side) return false end
        g.entity:SetVelocity((ply:GetShootPos() - g.entity:GetShootPos()):GetNormalized() * 150)
        self:SetHand(side, HAND_HOLD, g.entity:WorldSpaceCenter())
        return false
    end

    local phys = g.entity:GetPhysicsObject()
    if not IsValid(phys) then self:Release(side) return false end

    if g.kind == "hold" then
        phys:Wake()
        phys:ComputeShadowControl({
            secondstoarrive = 0.1,
            pos = ply:GetShootPos() + ply:GetAimVector() * (C.HoldDistance + g.entity:BoundingRadius()),
            angle = Angle(0, ply:EyeAngles().y, 0),
            maxangular = 5000, maxangulardamp = 10000,
            maxspeed = 1000, maxspeeddamp = 1000,
            dampfactor = 0.8, teleportdistance = 0,
            deltatime = FrameTime(),
        })
        self:SetHand(side, HAND_HOLD, g.entity:WorldSpaceCenter())
        return false
    end

    -- Drag: pull the grabbed point toward where the hand is reaching, limited
    -- strength, gravity untouched, so heavy things scrape along the floor.
    local point = g.entity:LocalToWorld(g.localpos)
    local target = ply:GetShootPos() + ply:GetAimVector() * g.dist
    local desired = (target - point) * 8
    local impulse = (desired - phys:GetVelocityAtPoint(point)) * phys:GetMass() * FrameTime() * 4
    local maxImpulse = C.DragImpulse * (GK.HasSurge(ply) and C.SurgeDragMultiplier or 1)
    if impulse:Length() > maxImpulse then impulse = impulse:GetNormalized() * maxImpulse end
    phys:Wake()
    phys:ApplyForceOffset(impulse, point)
    -- Loose props never hold your weight, however heavy; only frozen ones do.
    self:SetHand(side, HAND_GRIP, point, false)
    return false
end

function SWEP:Think()
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    self.Grips = self.Grips or {}
    local ct = CurTime()
    local stamina = GK.Stamina(ply)

    if not GK.IsChipOnline(ply) or GK.IsRagdolled(ply) or GK.IsDowned(ply) or GK.IsImpaled(ply) or self:IsBusy() then
        if next(self.Grips) then self:ReleaseAll() end
        return
    end

    -- Out of stamina: climbing grips slip, but held/dragged props stay.
    -- Goo-slimed hands never slip.
    local gooped = GK.HasBuff(ply, "gooped")
    if gooped and stamina <= 0 then stamina = 1 end
    -- Out of grip but still hanging on: you overdraw. A red strain meter
    -- fills over the stamina bar (it shakes, cl_hud.lua) for a moment, then
    -- it shatters: you lose your hold and stagger, and the hands are locked
    -- out for a bit before they get a little grip back to catch something.
    local hanging, dry = false, true
    for side, g in pairs(self.Grips) do
        if g.kind == "world" then
            hanging = true
            if gooped or GK.HandGrip(ply, side) > 0 then dry = false end
        end
    end
    local over = self.GK_Overdraw or 0
    if hanging and dry then
        over = over + FrameTime() / 1.5
        if over >= 1 then
            for side, g in pairs(self.Grips) do
                if g.kind == "world" then self:Release(side) end
            end
            self.GripOutUntil = ct + (GK.Config.GripOutLockout or 1) + 0.4
            over = 0
            ply:SetNW2Float("gk_stagger_until", ct + 1.2)
            ply:SetNW2Float("gk_shatter_at", ct)
            -- The ultimate penalty: down in a heap until grip refills or a teammate helps.
            if SERVER and GK.Stagger and GK.Stagger.Full then
                timer.Simple(0, function() if IsValid(ply) then GK.Stagger.Full(ply) end end)
            end
            ply:ViewPunch(Angle(math.Rand(6, 10), math.Rand(-6, 6), math.Rand(-8, 8)))
            ply:EmitSound("physics/glass/glass_impact_bullet" .. math.random(1, 4) .. ".wav", 60, 70)
            ply:EmitSound("vo/npc/male01/pain0" .. math.random(1, 9) .. ".wav", 60, 115)
        end
    else
        over = math.max(0, over - FrameTime() * 2)
    end
    self.GK_Overdraw = over
    if math.abs(over - ply:GetNW2Float("gk_overdraw", 0)) > 0.02 or (over == 0 and ply:GetNW2Float("gk_overdraw", 0) ~= 0) then
        ply:SetNW2Float("gk_overdraw", over)
    end
    if self.GripOutUntil and ct >= self.GripOutUntil then
        self.GripOutUntil = nil
        local refill = GK.Config.GripOutRefill or 10
        for _, s in ipairs({ "l", "r" }) do
            if GK.HandGrip(ply, s) < refill then GK.SetHandGrip(ply, s, refill) end
        end
        stamina = GK.Stamina(ply)
    end

    -- Grip-jump: works with or without legs.
    local climbing = 0
    for _, g in pairs(self.Grips) do if g.kind == "world" then climbing = climbing + 1 end end
    local jumpCost = C.StaminaDrainJump * climbing
    if ply:KeyPressed(IN_JUMP) and climbing > 0 and stamina > jumpCost then
        for side, g in pairs(self.Grips) do
            if g.kind == "world" then GK.SetHandGrip(ply, side, GK.HandGrip(ply, side) - C.StaminaDrainJump) end
        end
        -- The launch itself is in GM:Move (sh_movement.lua), so it's predicted.
        -- Off a WK cryoshot platform: it shatters and blasts you up (WK's
        -- explosive boost, mostly upward, a little along your look).
        for _, g in pairs(self.Grips) do
            if g.boost and not g.boost.broken and SERVER then
                g.boost.broken = true
                local at = g.boost.shape.centre
                ply:SetVelocity(LerpVector(0.3, Vector(0, 0, 1), ply:GetAimVector()):GetNormalized() * 520)
                local fx = EffectData() fx:SetOrigin(at) fx:SetScale(1) fx:SetMagnitude(1)
                util.Effect("Explosion", fx, true, true)
                util.Effect("GlassImpact", fx, true, true)
                sound.Play("physics/glass/glass_largesheet_break" .. math.random(1, 3) .. ".wav", at, 80)
                ply:ViewPunch(Angle(-6, 0, 0))
                break
            end
        end
        for side, g in pairs(self.Grips) do
            if g.kind == "world" then self:Release(side) end
        end
        -- WK: a hand that lets go can grab again after 0.25 s, held button or
        -- not, so holding both buttons and tapping jump chains up a wall.
        self.JumpLock = ct + 0.25
    end

    local anyDown = ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2)
    if self.JumpLock and (ct >= self.JumpLock or not anyDown) then self.JumpLock = false end

    -- Hold a button to grip; it keeps trying every tick until something's in reach.
    -- A hand holding an item (sh_items.lua) uses the item instead.
    self.GripLock = self.GripLock or {}
    for side, button in SortedPairs(BUTTONS) do
        local holdsItem = GK.Inv.HandItem(ply, side) ~= nil
        local usable = not holdsItem
        -- A raised fist punches instead of gripping (sh_melee.lua).
        if GK.HasFist and GK.HasFist(ply, side) then
            usable = false
            if SERVER then GK.Melee.PunchInput(ply, side, ply:KeyDown(button)) end
        end
        if holdsItem and ply:KeyPressed(button) and not self.GripLock[side] then GK.Inv.Use(ply, side) end
        if not ply:KeyDown(button) then self.GripLock[side] = nil end
        if usable and ply:KeyDown(button) then
            local handOk = (gooped or GK.HandGrip(ply, side) > 0) and (self.HandLock and self.HandLock[side] or 0) <= ct
            if not self.Grips[side] and handOk and not self.GripOutUntil and not self.JumpLock and not self.GripLock[side] then
                local g = self:TryGrip(ply, side)
                if g then
                    g.since = ct
                    -- A fresh grab (WK resets holdTime): the body keeps its momentum
                    -- for a moment before the hang takes over (sh_movement.lua).
                    if g.kind == "world" then ply:SetNW2Float("gk_grab_at", ct) end
                    if g.kind == "world" and GK.HoldAt then g.hold = g.special or GK.HoldAt(g.hitpos) end
                    self.Grips[side] = g
                    ply:EmitSound("physics/flesh/flesh_impact_bullet1.wav", 65, 140)
                    self:SetHand(side, g.kind == "hold" and HAND_HOLD or HAND_GRIP, g.hitpos, g.kind == "world", g.top, g.lip, g.into)
                end
            end
        elseif self.Grips[side] and (not usable or not ply:KeyDown(button)) then
            self:Release(side, true)
        end
    end

    local count = 0
    for _, g in pairs(self.Grips) do
        if g.kind == "world" or g.kind == "drag" then count = count + 1 end
    end
    local bearing = false
    for side, g in pairs(self.Grips) do
        if self:UpdateGrip(ply, side, g, math.max(count, 1)) then bearing = true end
    end

    -- WK's special holds: icy ones slip, breakable ones crumble, sharp ones cut (sv_hazards.lua).
    for side, g in pairs(self.Grips) do
        if g.hold and GK.HoldTick(ply, g.hold, ct - (g.since or ct)) then
            self:Release(side)
            if g.hold.kind ~= "icy" then self.GripOutUntil = math.max(self.GripOutUntil or 0, ct + 0.3) end
        end
    end

    -- A piton that isn't hammered home only takes your weight so long (gk_piton_hold).
    for side, g in pairs(self.Grips) do
        local p = g.entity
        if g.kind == "world" and IsValid(p) and p.HoldTime then
            local limit = p:HoldTime()
            if limit and ct - (g.since or ct) > limit then
                self:Release(side)
                p:PopOut()
            end
        end
    end

    -- Grip is per hand and finite (only the Slug Grub's goop makes it
    -- infinite), WK's numbers: a hand holding you alone drains in about 10 s,
    -- two hands share the load (about 20 s), feet on the ground let them
    -- recover. A free hand gets its grip back: fast standing on the ground,
    -- slowly in the air once it's been off a hold for a moment.
    if ct >= (self.NextStaminaTick or 0) then
        local cfg = GK.Config
        local dt = C.StaminaTickRate
        local hands = 0
        for _, g in pairs(self.Grips) do if g.kind == "world" then hands = hands + 1 end end
        local onGround = ply:OnGround()
        local rested = ct >= (ply.GK_StaminaRestAt or 0) and not (GK.IsStaggered and GK.IsStaggered(ply)) -- lying staggered refills at its own pace (sh_stagger.lua)
        self.ReleasedAt = self.ReleasedAt or {}
        for _, side in ipairs({ "l", "r" }) do
            local g = self.Grips[side]
            local m = GK.HandGrip(ply, side)
            local before = m
            if g and g.kind == "world" then
                if onGround then
                    m = m + (cfg.GripHangRegen or 7.5) * dt * GK.BuffMult(ply, "regen")
                elseif not gooped then
                    local perSec = hands >= 2 and (cfg.GripDrainTwoHands or 5) or (cfg.GripDrainOneHand or 10)
                    m = m - perSec * dt * GK.BuffMult(ply, "drain")
                end
            elseif onGround then
                if rested then m = m + (cfg.GripGroundRegen or 9) * dt * GK.BuffMult(ply, "regen") * GK.BuffMult(ply, "groundregen") end
            elseif ct - (self.ReleasedAt[side] or 0) > (cfg.GripAirDelay or 0.17) then
                m = m + (cfg.GripAirRegen or 0.75) * dt * GK.BuffMult(ply, "regen")
            end
            if m ~= before then GK.SetHandGrip(ply, side, m) end
        end
        self.NextStaminaTick = ct + dt
        -- A hand that runs dry while the other still has grip slips off on
        -- its own (WK: that hand's out for a second). The last hand holding
        -- you overdraws instead (above).
        if hands >= 2 and not gooped then
            for side, g in pairs(self.Grips) do
                local other = self.Grips[side == "l" and "r" or "l"]
                if g.kind == "world" and GK.HandGrip(ply, side) <= 0 and other and GK.HandGrip(ply, side == "l" and "r" or "l") > 0 then
                    self:Release(side)
                    self.HandLock = self.HandLock or {}
                    self.HandLock[side] = ct + (cfg.GripOutLockout or 1)
                    ply:EmitSound("physics/flesh/flesh_impact_hard" .. math.random(1, 3) .. ".wav", 55, 140)
                end
            end
        end
    end
    if bearing then ply.GK_StaminaRestAt = ct + (GK.Config.StaminaRegenDelay or 1) end
end

end -- SERVER

if CLIENT then
    -- The real hands are sprites; hide the (armless) viewmodel entirely.
    function SWEP:PreDrawViewModel() return true end
    function SWEP:DrawWorldModel() end
end
