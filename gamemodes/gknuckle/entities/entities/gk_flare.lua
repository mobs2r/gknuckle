AddCSLuaFile()

-- A flaregun flare: a bright burning projectile that bounces about and sets
-- any player it touches on fire. Burns out after a while.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Flare"
ENT.Spawnable = false

ENT.GKBurnTime = 12

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_junk/flare.mdl")
        self:PhysicsInitSphere(2, "metal")
        self:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() phys:SetMass(1) phys:EnableDrag(false) end
        self.GK_Born = CurTime()
        self:EmitSound("gknuckle/items/flaregun_projectile.wav", 75)
        SafeRemoveEntityDelayed(self, self.GKBurnTime)
    end

    function ENT:PhysicsCollide(data)
        local hit = data.HitEntity
        if IsValid(hit) and hit:IsPlayer() and hit ~= self:GetOwner() then
            -- Next tick: damage can kill, and death makes ragdolls and gibs
            -- (new physics objects), which must not happen inside a physics callback.
            local by = IsValid(self:GetOwner()) and self:GetOwner() or self
            timer.Simple(0, function()
                if not IsValid(hit) then return end
                hit:Ignite(5)
                hit:TakeDamage(12, IsValid(by) and by or game.GetWorld(), IsValid(self) and self or game.GetWorld())
            end)
        elseif data.Speed > 200 then
            self:EmitSound("gknuckle/items/flaregun_projectile_ricochet.wav", 70)
        end
    end

    function ENT:Think()
        -- Anyone standing on a lit flare catches too.
        for _, ply in ipairs(ents.FindInSphere(self:GetPos(), 20)) do
            local age = CurTime() - self.GK_Born
            if ply:IsPlayer() and ply:Alive() and not ply:IsOnFire() and (age > 1.5 or (ply ~= self:GetOwner() and age > 0.1)) then
                ply:Ignite(3)
            end
        end
        self:NextThink(CurTime() + 0.2)
        return true
    end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")
    function ENT:Draw()
        self:DrawModel()
        local flicker = 0.8 + math.random() * 0.2
        render.SetMaterial(glow)
        render.DrawSprite(self:GetPos(), 40 * flicker, 40 * flicker, Color(255, 60, 40))
        local l = DynamicLight(self:EntIndex())
        if l then
            l.pos = self:GetPos()
            l.r, l.g, l.b = 255, 70, 40
            l.brightness = 3 * flicker
            l.size = 300
            l.decay = 1000
            l.dietime = CurTime() + 0.1
        end
    end
end
