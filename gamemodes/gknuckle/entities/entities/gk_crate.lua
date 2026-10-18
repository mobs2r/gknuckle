AddCSLuaFile()

-- A breakable crate, like White Knuckle's supply crates (Prop_SupplyCrate_01
-- and its shattered bits). Hit it hard (hammer, crowbar, a thrown brick or
-- rebar, a blast, a heavy landing) and it bursts into its WK pieces. A supply
-- crate (GK_Supply set before Spawn) has an item or two inside.
-- GK_Model sets a different crate model (the hub yard's plain crate).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Crate"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

if SERVER then
    local LOOT = { "foodbar", "beans", "piton", "bandage", "pills", "flare", "brick", "rebar", "bullet" }

    function ENT:Initialize()
        local mdl = self.GK_Model or "models/gknuckle/items/supplycrate.mdl"
        self:SetModel(util.IsValidModel(mdl) and mdl or "models/props_junk/wood_crate001a.mdl")
        if self.GK_Frozen then
            -- Crates placed in run rooms (GK_Frozen) have no physics object,
            -- just a box (vphysics run crash: nothing the room hooks spawn is
            -- a physics object). Hits and blasts still break them.
            self:SetSolid(SOLID_BBOX)
            self:SetCollisionBounds(self:OBBMins(), self:OBBMaxs())
            self:SetMoveType(MOVETYPE_NONE)
        else
            self:PhysicsInit(SOLID_VPHYSICS)
            if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
            self:SetMoveType(MOVETYPE_VPHYSICS)
            self:SetSolid(SOLID_VPHYSICS)
            local phys = self:GetPhysicsObject()
            if IsValid(phys) then phys:Wake() end
        end
        self:SetHealth(self.GK_Health or 20)
    end

    function ENT:Break(force)
        if self.GK_Broken then return end
        self.GK_Broken = true
        local pos, ang = self:GetPos(), self:GetAngles()
        self:EmitSound("gknuckle/props/wood_break" .. math.random(1, 3) .. ".wav", 75)
        -- WK's shattered pieces (in the crate's own space, so they start where they were).
        for i = 1, 5 do
            local mdl = "models/gknuckle/items/crate_bit" .. i .. ".mdl"
            if util.IsValidModel(mdl) then
                local bit = ents.Create("prop_physics")
                bit:SetModel(mdl)
                bit:SetPos(pos) bit:SetAngles(ang)
                if self.GK_Model then bit:SetModelScale(0.8) end
                bit:Spawn()
                bit:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                local p = bit:GetPhysicsObject()
                if IsValid(p) then p:SetVelocity((force or vector_origin) * 0.3 + VectorRand() * 120 + Vector(0, 0, 80)) end
                SafeRemoveEntityDelayed(bit, 8)
            end
        end
        if self.GK_Supply then
            for _ = 1, math.random(1, 2) do
                local it = ents.Create("gk_item")
                it.GKItemClass = LOOT[math.random(#LOOT)]
                it:SetPos(pos + Vector(0, 0, 10) + VectorRand() * 6)
                it:Spawn()
            end
        end
        self:Remove()
    end

    function ENT:OnTakeDamage(d)
        self:SetHealth(self:Health() - d:GetDamage())
        self:EmitSound("physics/wood/wood_box_impact_hard" .. math.random(1, 3) .. ".wav", 70)
        if self:Health() <= 0 then
            local force = d:GetDamageForce() * 0.02
            timer.Simple(0, function() if IsValid(self) then self:Break(force) end end) -- damage can come from a physics callback
        end
    end

    function ENT:PhysicsCollide(data)
        -- A hard landing or a fast thing hitting it.
        if data.Speed > 450 then
            local v = data.OurOldVelocity
            timer.Simple(0, function() if IsValid(self) then self:Break(v) end end) -- not mid-collision
        end
    end
end
