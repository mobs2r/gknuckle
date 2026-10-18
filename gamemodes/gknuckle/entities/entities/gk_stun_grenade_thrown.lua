AddCSLuaFile()

-- Thrown stun grenade: on fuse, an energy burst knocks nearby Xenium links offline.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Stun Grenade"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/items/combine_rifle_ammo01.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:SetMass(5) phys:Wake() end
        self.Detonate = CurTime() + 2
        util.SpriteTrail(self, 0, Color(120, 200, 255), true, 6, 0, 0.4, 0.1, "trails/laser.vmt")
    end

    function ENT:Think()
        if CurTime() >= self.Detonate then
            GK.ChipBurst(self:GetPos(), GK.Config.StunRadius, GK.Config.StunDuration, self:GetOwner())
            self:Remove()
            return
        end
        self:NextThink(CurTime() + 0.05)
        return true
    end

    function ENT:PhysicsCollide(data)
        if data.Speed > 80 then self:EmitSound("physics/metal/metal_grenade_impact_hard" .. math.random(1, 3) .. ".wav") end
    end
end
