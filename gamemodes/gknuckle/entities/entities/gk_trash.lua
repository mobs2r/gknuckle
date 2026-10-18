AddCSLuaFile()

-- One piece of junk falling down a garbage chute (gk_trashchute). Tossed
-- with MOVETYPE_FLYGRAVITY, no physics object; hits a climber once on the way.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Falling Trash"
ENT.Spawnable = false

if SERVER then
    function ENT:Initialize()
        if self:GetModel() == "" or not util.IsValidModel(self:GetModel()) then self:SetModel("models/props_junk/garbage_metalcan001a.mdl") end
        -- A small box that lands on floors but never blocks anyone (debris group).
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-4, -4, -4), Vector(4, 4, 4))
        self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
        self:SetMoveType(MOVETYPE_FLYGRAVITY)
        self:SetLocalVelocity(VectorRand() * 30 - Vector(0, 0, 100))
        self:SetLocalAngularVelocity(AngleRand() * 2)
        self.GK_Born = CurTime()
        SafeRemoveEntityDelayed(self, self.GK_Linger or 6)
        self:NextThink(CurTime())
    end

    function ENT:Think()
        local ct = CurTime()
        local pos = self:GetPos()
        if not self.GK_Hit and not self.GK_Harmless then
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() and p:WorldSpaceCenter():Distance(pos) < 34 then
                    self.GK_Hit = true
                    local d = DamageInfo()
                    d:SetDamage(8) d:SetDamageType(DMG_CLUB) d:SetAttacker(self) d:SetInflictor(self)
                    d:SetDamagePosition(pos)
                    p:TakeDamageInfo(d)
                    GK.DropHang(p, 0.2, 1)
                    p:ViewPunch(Angle(8, math.Rand(-4, 4), 0))
                    p:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 70)
                    break
                end
            end
        end
        -- Landed (or stuck): gone shortly.
        if ct - self.GK_Born > 0.5 and self:GetVelocity():LengthSqr() < 100 then
            if not self.GK_Linger then SafeRemoveEntityDelayed(self, 1) end
            return
        end
        self:NextThink(ct + 0.05)
        return true
    end
end
