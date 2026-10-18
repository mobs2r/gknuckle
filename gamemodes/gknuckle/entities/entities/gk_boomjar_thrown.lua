AddCSLuaFile()

-- A boom bug in a jar, thrown: it goes off the moment it hits anything, with
-- the boom bug's own blast (gk_roach's Explode: hurts and throws everything
-- near it). An impact grenade made of a very angry roach.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Boom Jar"
ENT.Spawnable = false

GK.BoomJarModel = "models/props_lab/jar01a.mdl"

if SERVER then
    function ENT:Initialize()
        self:SetModel(GK.BoomJarModel)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:SetMass(3) phys:Wake() end
        self.Armed = CurTime() + 0.08 -- not on the thrower's own hull as it leaves the hand
        util.SpriteTrail(self, 0, Color(255, 60, 40), true, 5, 0, 0.3, 0.1, "trails/laser.vmt")
    end

    function ENT:Blow(pos)
        if self.Blown then return end
        self.Blown = true
        local owner = self:GetOwner()
        sound.Play("physics/glass/glass_bottle_break" .. math.random(1, 2) .. ".wav", pos, 80)
        local fx = EffectData() fx:SetOrigin(pos)
        util.Effect("GlassImpact", fx, true, true)
        GK.Explode(pos, { radius = 160, damage = 35, force = 520, lift = 0.6, attacker = owner, inflictor = self }) -- the boom bug's own blast
        self:Remove()
    end

    function ENT:PhysicsCollide(data)
        if CurTime() < self.Armed or data.Speed < 40 then return end
        local pos = data.HitPos
        timer.Simple(0, function() if IsValid(self) then self:Blow(pos) end end) -- not mid-collision
    end

    -- Dropped gently or wedged somewhere: it still goes off before long.
    function ENT:Think()
        if CurTime() > (self.Armed or 0) + 6 then self:Blow(self:GetPos()) return end
        self:NextThink(CurTime() + 0.2)
        return true
    end
end

if CLIENT then
    -- The red bug inside, scrabbling at the glass.
    function GK.DrawJarBug(ent, scale)
        ent.GK_Bug = IsValid(ent.GK_Bug) and ent.GK_Bug or ClientsideModel("models/gknuckle/items/roach_boom.mdl", RENDERGROUP_OPAQUE)
        local bug = ent.GK_Bug
        if not IsValid(bug) then return end
        bug:SetNoDraw(true)
        bug:SetModelScale(scale or 0.55)
        local wob = Angle(math.sin(CurTime() * 17) * 20, CurTime() * 90 % 360, math.cos(CurTime() * 23) * 15)
        bug:SetPos(ent:LocalToWorld(ent:OBBCenter()))
        bug:SetAngles(ent:LocalToWorldAngles(wob))
        bug:SetupBones()
        bug:DrawModel()
    end
    function ENT:Draw()
        GK.DrawJarBug(self)
        self:DrawModel()
    end
    function ENT:OnRemove() if IsValid(self.GK_Bug) then self.GK_Bug:Remove() end end
end
