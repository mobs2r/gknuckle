AddCSLuaFile()

-- Gas bag: White Knuckle's floating proximity mine (a port of DEN_Gasbag).
-- It drifts about holding its height, grunts, and when someone comes within
-- 6 m it drifts toward them; within 3 m it bursts. The blast hurts a little,
-- knocks you off the wall, and shoves you away from it, or, if you're above
-- it, straight up: the gas bag jump. Shoot or hit it and it bursts too.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Gas Bag"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

if SERVER then
    local M = 39.4
    local SIGHT, BURST = 6 * M, 3 * M
    local DRIFT = 30          -- u/s wander drift
    local HOME_SPEED = 45     -- u/s toward a target

    local function snd(self, name, lvl) self:EmitSound("gknuckle/creatures/" .. name .. ".wav", lvl or 72, math.random(90, 110)) end

    function ENT:Initialize()
        self:SetModel(util.IsValidModel("models/gknuckle/items/gasbag.mdl") and "models/gknuckle/items/gasbag.mdl" or "models/props_junk/watermelon01.mdl")
        local s = math.Rand(0.85, 1.25)
        self:SetModelScale(s)
        -- No physics object (see gk_bloodbug): drifts with MOVETYPE_FLY.
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-14, -14, -14) * s, Vector(14, 14, 14) * s)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
        self:SetHealth(15)
        self.GK_Height = self:GetPos().z
        self.GK_Dir = VectorRand():GetNormalized()
        self.GK_Noise = math.Rand(0, 100)
        self:NextThink(CurTime())
    end

    function ENT:Think()
        local ct = CurTime()
        if self.GK_Popped then return end
        local pos = self:GetPos()

        -- Who's near: within 3 m it bursts, within 6 m it homes in, past 9 m it forgets.
        local tgt = self.GK_Target
        if IsValid(tgt) and (not tgt:Alive() or tgt:GetPos():Distance(pos) > SIGHT * 1.5) then tgt = nil end
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() then
                local d = p:WorldSpaceCenter():Distance(pos)
                if d < BURST then self:Burst(p) return end
                if not tgt and d < SIGHT then tgt = p snd(self, "gasbag_alert" .. math.random(2), 75) end
            end
        end
        self.GK_Target = tgt

        -- Drift: a wandering heading, plus homing or holding its height.
        local t = ct * 0.4 + self.GK_Noise
        self.GK_Dir = (self.GK_Dir + Vector(math.sin(t * 1.7), math.cos(t * 1.3), math.sin(t * 0.7) * 0.3) * 0.15):GetNormalized()
        local want = self.GK_Dir * DRIFT
        if tgt then
            want = want + (tgt:WorldSpaceCenter() - pos):GetNormalized() * HOME_SPEED
        else
            want.z = want.z + (self.GK_Height - pos.z) * 0.5
        end
        self:SetLocalVelocity(LerpVector(0.1, self:GetVelocity(), want))
        self:SetAngles(LerpAngle(0.05, self:GetAngles(), Angle(0, self:GetAngles().y + 4, math.sin(t) * 6)))

        if ct > (self.GK_Grunt or 0) then
            self.GK_Grunt = ct + math.Rand(4, 12)
            snd(self, "gasbag_grunt" .. math.random(3), 65)
        end
        self:NextThink(ct + 0.1)
        return true
    end

    -- Bumping into something turns it away.
    function ENT:Touch(e)
        if e:IsWorld() then self.GK_Dir = -self.GK_Dir end
    end

    function ENT:Burst(by)
        if self.GK_Popped then return end
        self.GK_Popped = true
        local pos = self:WorldSpaceCenter()
        snd(self, "gasbag_death" .. math.random(2), 85)
        local fx = EffectData() fx:SetOrigin(pos) fx:SetScale(1) fx:SetMagnitude(1)
        util.Effect("Explosion", fx, true, true)
        for _, p in ipairs(player.GetAll()) do
            local c = p:WorldSpaceCenter()
            local d = c:Distance(pos)
            if p:Alive() and d < BURST * 1.3 then
                local dir = (c - pos):GetNormalized()
                -- Above it (within 70 degrees of straight up): launched straight up.
                if dir:Dot(vector_up) > math.cos(math.rad(70)) then
                    local v = p:GetVelocity()
                    p:SetVelocity(Vector(0, 0, 640 - math.max(v.z, -300)) - Vector(v.x, v.y, 0) * 0.5)
                else
                    p:SetVelocity(dir * 380 + Vector(0, 0, 120))
                end
                local dm = DamageInfo()
                dm:SetDamage(10) dm:SetDamageType(DMG_BLAST) dm:SetAttacker(IsValid(by) and by or self) dm:SetInflictor(self)
                dm:SetDamagePosition(pos)
                p:TakeDamageInfo(dm)
                GK.DropHang(p, 0.1, 1)
            end
        end
        -- Knocks roaches and props about too.
        for _, e in ipairs(ents.FindInSphere(pos, BURST)) do
            if e.AddForce and e:GetClass() == "gk_roach" then e:AddForce((e:GetPos() - pos):GetNormalized() * 300) end
        end
        self:SetNoDraw(true) self:SetSolid(SOLID_NONE) self:SetMoveType(MOVETYPE_NONE)
        SafeRemoveEntityDelayed(self, 0)
    end

    function ENT:OnTakeDamage(d)
        self:SetHealth(self:Health() - d:GetDamage())
        if self:Health() <= 0 or d:IsExplosionDamage() then self:Burst(d:GetAttacker()) end
    end
end
