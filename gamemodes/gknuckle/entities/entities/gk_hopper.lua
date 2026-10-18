AddCSLuaFile()

-- Hopper: White Knuckle's leaping pest (Denizen_Hopper, its mesh is "Lengen").
-- It hops about on floors and ledges; when it spots a climber within 5 m it
-- crouches with a warning chirp, then leaps at them. A hit stings and knocks
-- you off your hold. Fragile: any decent hit kills it (WK: 3 health, the
-- hammer does 1 and pops it into the air).
-- Spawned by rooms' Hopper_Spawner (sv_creatures.lua). No physics object:
-- it flies ballistically with MOVETYPE_FLYGRAVITY (see gk_turret's crash notes).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Hopper"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local IDLE, READY, LEAP, DEAD = 0, 1, 2, 3

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "State")
end

if SERVER then
    local M = 39.4
    local SIGHT = 5 * M -- WK: hoppers spot you at 5 m
    local READY_T = 0.8         -- crouch before the leap (the warning)
    local LEAP_SPEED = 520
    local HOP_SPEED = 160
    local COOLDOWN = 2.5
    local DAMAGE = 8

    local function snd(self, name, lvl) self:EmitSound("gknuckle/creatures/hopper_" .. name .. ".wav", lvl or 70, math.random(92, 108)) end

    function ENT:Initialize()
        local mdl = "models/gknuckle/items/hopper.mdl"
        self:SetModel(util.IsValidModel(mdl) and mdl or "models/props_junk/watermelon01.mdl")
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-10, -10, 0), Vector(10, 10, 16))
        self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
        self:SetMoveType(MOVETYPE_FLYGRAVITY)
        self:SetHealth(15)
        self:SetState(IDLE)
        self.GK_Next = CurTime() + math.Rand(1, 3)
        self:NextThink(CurTime())
    end

    local function onGround(self)
        local p = self:GetPos()
        return util.TraceHull({ start = p + Vector(0, 0, 2), endpos = p - Vector(0, 0, 3), mins = Vector(-8, -8, 0), maxs = Vector(8, 8, 4), mask = MASK_SOLID, filter = self }).Hit
    end

    function ENT:Target()
        local best, bd = nil, SIGHT
        local eye = self:GetPos() + Vector(0, 0, 10)
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and not GK.HasPerk(p, "pheromone") then -- WK: Pheromone Glands calms them too
                local d = p:WorldSpaceCenter():Distance(eye)
                if d < bd and not util.TraceLine({ start = eye, endpos = p:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY }).Hit then best, bd = p, d end
            end
        end
        return best
    end

    function ENT:Think()
        local ct = CurTime()
        local st = self:GetState()
        if st == DEAD then return end
        local grounded = onGround(self)

        if st == LEAP then
            -- In the air at someone: a hit on contact, then back to hopping on landing.
            local v = self.GK_Victim
            if IsValid(v) and v:Alive() and not self.GK_Hit and v:WorldSpaceCenter():Distance(self:WorldSpaceCenter()) < 36 then
                self.GK_Hit = true
                local d = DamageInfo()
                d:SetDamage(DAMAGE) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
                d:SetDamagePosition(self:GetPos())
                v:TakeDamageInfo(d)
                GK.DropHang(v, 0.2, 1)
                v:ViewPunch(Angle(-5, math.Rand(-5, 5), 0))
                snd(self, "attack", 75)
                self:SetLocalVelocity(-self:GetVelocity() * 0.3)
            end
            if grounded and ct > self.GK_LeapAt + 0.2 then
                self:SetState(IDLE)
                self.GK_Next = ct + COOLDOWN
            end
            self:NextThink(ct + 0.03)
            return true
        end

        local tgt = self:Target()
        if st == READY then
            if not IsValid(tgt) then self:SetState(IDLE)
            elseif ct >= self.GK_ReadyUntil then
                -- The leap: at their chest, arcing a little.
                local to = tgt:WorldSpaceCenter() + tgt:GetVelocity() * 0.2 - self:GetPos()
                local flat = Vector(to.x, to.y, 0)
                local t = math.max(flat:Length() / LEAP_SPEED, 0.15)
                local vz = to.z / t + 0.5 * 600 * t
                self:SetLocalVelocity(flat:GetNormalized() * math.min(LEAP_SPEED, flat:Length() / t) + Vector(0, 0, math.Clamp(vz, 120, 700)))
                self:SetGroundEntity(NULL) self:RemoveFlags(FL_ONGROUND) self:SetPos(self:GetPos() + Vector(0, 0, 2))
                self.GK_Victim, self.GK_Hit, self.GK_LeapAt = tgt, false, ct
                self:SetState(LEAP)
                snd(self, "attack", 72)
            end
        elseif grounded and ct >= self.GK_Next then
            if IsValid(tgt) then
                -- Face them and crouch: the leap is coming.
                local a = (tgt:GetPos() - self:GetPos()):Angle()
                self:SetAngles(Angle(0, a.y, 0))
                self:SetLocalVelocity(vector_origin)
                self:SetState(READY)
                self.GK_ReadyUntil = ct + READY_T
                snd(self, "ready", 72)
            else
                -- A little hop somewhere.
                local yaw = self:GetAngles().y + math.Rand(-90, 90)
                self:SetAngles(Angle(0, yaw, 0))
                self:SetLocalVelocity(Angle(0, yaw, 0):Forward() * HOP_SPEED * math.Rand(0.5, 1) + Vector(0, 0, 180))
                self:SetGroundEntity(NULL) self:RemoveFlags(FL_ONGROUND) self:SetPos(self:GetPos() + Vector(0, 0, 2))
                self.GK_Next = ct + math.Rand(1.5, 4)
                if math.random() < 0.3 then snd(self, "bark" .. math.random(3), 65) end
            end
        end
        self:NextThink(ct + 0.05)
        return true
    end

    function ENT:OnTakeDamage(d)
        if self:GetState() == DEAD then return end
        self:SetHealth(self:Health() - d:GetDamage())
        if self:Health() > 0 then
            -- WK: a hammer knocks it up into the air.
            self:SetGroundEntity(NULL) self:RemoveFlags(FL_ONGROUND) self:SetPos(self:GetPos() + Vector(0, 0, 2))
            self:SetLocalVelocity(self:GetVelocity() + Vector(0, 0, 200))
            return
        end
        self:SetState(DEAD)
        snd(self, "die" .. math.random(2), 75)
        local fx = EffectData() fx:SetOrigin(self:WorldSpaceCenter()) fx:SetColor(BLOOD_COLOR_RED)
        util.Effect("BloodImpact", fx, true, true)
        self:SetColor(Color(110, 80, 80))
        self:SetSolid(SOLID_NONE)
        SafeRemoveEntityDelayed(self, 15)
    end
end

if CLIENT then
    function ENT:Draw()
        -- Crouched before a leap: squashed down, shivering.
        if self:GetState() == 1 then
            local m = Matrix() m:Scale(Vector(1.15, 1.15, 0.7))
            self:EnableMatrix("RenderMultiply", m)
            self:SetRenderOrigin(self:GetNetworkOrigin() + VectorRand() * 0.4)
        else
            self:DisableMatrix("RenderMultiply")
            self:SetRenderOrigin()
        end
        self:DrawModel()
    end
end
