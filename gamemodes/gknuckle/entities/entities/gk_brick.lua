AddCSLuaFile()

-- White Knuckle's brick ("Rubble"): the real model, texture and sounds.
-- Lying around it's an item (click it with an empty hand). Thrown, it flies
-- fast and flat like WK's Projectile_Rubble (60 m/s, light gravity) and
-- shatters on the first thing it hits. Players it hits get ragdolled.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Brick"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

ENT.GKModel = "models/gknuckle/items/brick.mdl"   -- gameplay_tools/make_brick.ps1
ENT.GKThrowSpeed = 2360          -- WK shootSpeed 60 (m/s) in Source units
ENT.GKDamage = 10                -- WK does 3 on a 1-ish health scale; scaled for 100 hp

sound.Add({ name = "GK.BrickBounce", channel = CHAN_STATIC, volume = 0.8, level = 70, pitch = { 95, 110 },
    sound = { "gknuckle/brick/bounce1.wav", "gknuckle/brick/bounce2.wav", "gknuckle/brick/bounce3.wav", "gknuckle/brick/bounce4.wav" } })
sound.Add({ name = "GK.BrickBreak", channel = CHAN_STATIC, volume = 1, level = 80, pitch = { 95, 105 },
    sound = "gknuckle/brick/break.wav" })
sound.Add({ name = "GK.BrickPickup", channel = CHAN_ITEM, volume = 0.7, level = 60, pitch = 100,
    sound = "gknuckle/brick/pickup.wav" })

if SERVER then
    function ENT:Initialize()
        self.GKItemClass = "brick" -- click with an empty hand to pick it up
        self:SetModel(util.IsValidModel(self.GKModel) and self.GKModel or "models/props_debris/concrete_chunk05g.mdl")
        if self.GK_Asleep and not IsValid(self:GetOwner()) then
            -- Rubble placed by a run room (sv_levels sets GK_Asleep, like gk_item): no
            -- physics object, it lies where WK put it until someone picks it up. Awake
            -- bricks dropping onto a room's fresh collision, often from inside it, were
            -- the vphysics.dll+0x8a88c crash while Pipeworks rooms streamed in (0.4.4).
            self:SetSolid(SOLID_BBOX)
            self:SetCollisionBounds(self:OBBMins(), self:OBBMaxs())
            self:SetMoveType(MOVETYPE_NONE)
            self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            return
        end
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetMass(3)
            phys:Wake()
        end
        -- Thrown by the brick item (sh_items.lua): fly like a projectile.
        if IsValid(self:GetOwner()) then
            self.GK_Thrown = true
            self.GK_Thrower = self:GetOwner()
            if IsValid(phys) then phys:EnableDrag(false) end
            SafeRemoveEntityDelayed(self, 10) -- WK projectile lifetime
        end
    end

    function ENT:Shatter(pos, normal)
        if self.GK_Shattered then return end
        self.GK_Shattered = true
        self:EmitSound("GK.BrickBreak")
        local fx = EffectData()
        fx:SetOrigin(pos)
        fx:SetNormal(normal)
        fx:SetMagnitude(2)
        fx:SetScale(1)
        util.Effect("WheelDust", fx, true, true) -- brick dust
        for i = 1, 4 do
            local gib = ents.Create("prop_physics")
            gib:SetModel(self:GetModel()) -- shards of the brick itself (the HL2 debris models it used were missing: red ERRORs)
            gib:SetModelScale(math.Rand(0.25, 0.4))
            gib:SetPos(pos + VectorRand() * 3)
            gib:SetAngles(AngleRand())
            gib:Spawn()
            gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
            local gp = gib:GetPhysicsObject()
            if IsValid(gp) then gp:SetVelocity((normal + VectorRand() * 0.8) * 150) end
            SafeRemoveEntityDelayed(gib, 6)
        end
        SafeRemoveEntityDelayed(self, 0)
    end

    function ENT:PhysicsCollide(data)
        if not self.GK_Thrown then
            if data.Speed > 80 then self:EmitSound("GK.BrickBounce") end
            return
        end

        local hit = data.HitEntity
        if IsValid(hit) and hit:IsPlayer() and hit ~= self.GK_Thrower then
            local d = DamageInfo()
            d:SetDamage(self.GKDamage)
            d:SetAttacker(IsValid(self.GK_Thrower) and self.GK_Thrower or self)
            d:SetInflictor(self)
            d:SetDamageType(DMG_CLUB)
            local vel = data.OurOldVelocity * 0.25
            -- Next tick, not inside the physics callback (a kill makes ragdolls and gibs).
            timer.Simple(0, function()
                if not IsValid(hit) then return end
                if not IsValid(d:GetInflictor()) then d:SetInflictor(game.GetWorld()) end
                hit:TakeDamageInfo(d)
                if IsValid(hit) then GK.Ragdoll(hit, vel) end
            end)
        elseif IsValid(hit) then
            local phys = hit:GetPhysicsObject()
            local f, at = data.OurOldVelocity * 3 * 0.8, data.HitPos
            local by, dmg = self.GK_Thrower, self.GKDamage
            timer.Simple(0, function()
                if IsValid(phys) then phys:ApplyForceOffset(f, at) end
                -- Crates break and turrets tip from a thrown brick.
                if IsValid(hit) then hit:TakeDamage(dmg, IsValid(by) and by or game.GetWorld(), IsValid(self) and self or game.GetWorld()) end
            end)
        end
        -- Never make physics objects (the shards) inside a physics callback:
        -- that crashes vphysics. Next tick instead.
        local at, n = data.HitPos, data.HitNormal * -1
        self.GK_Thrown = false
        timer.Simple(0, function() if IsValid(self) then self:Shatter(at, n) end end)
    end
end
