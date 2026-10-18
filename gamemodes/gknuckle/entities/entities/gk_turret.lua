AddCSLuaFile()

-- White Knuckle's sentry turret (a port of DEN_Turret). It watches a 90 degree
-- cone out to 15 m, swings onto anyone it sees, beeps, and after half a
-- second on target fires a round a second. A hit stings and knocks you off
-- whatever you're hanging on. Knock it over (hit it hard: a hammer, a thrown
-- brick or rebar, a blast) and it topples, sprays
-- wildly for a second, harmlessly, and shuts down for good.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Turret"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local GUN_HEIGHT = 27.7 -- the gun's pivot above the base (WK: 0.702 m)

function ENT:SetupDataTables()
    self:NetworkVar("Angle", 0, "Aim")     -- world angles of the gun
    self:NetworkVar("Bool", 0, "Dead")
    self:NetworkVar("Bool", 1, "Locked")
end

if SERVER then
    local RANGE = 15 * 39.4
    local CONE = 45           -- each side of its rest facing
    local FIRE_CONE = 10
    local DELAY, RATE = 0.5, 1
    local SPREAD = 0.05
    local DAMAGE = 5

    local function snd(self, name, lvl) self:EmitSound("gknuckle/creatures/" .. name .. ".wav", lvl or 75) end

    function ENT:Initialize()
        self:SetModel(util.IsValidModel("models/gknuckle/items/turret_base.mdl") and "models/gknuckle/items/turret_base.mdl" or "models/combine_turrets/floor_turret.mdl")
        -- No physics object at all (vphysics run crash: physics objects that
        -- room hooks spawn are the common factor). A box that bullets and
        -- thrown things hit; a hard hit tips it over by animation instead.
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-12, -12, 0), Vector(12, 12, 40))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetAim(Angle(0, self:GetAngles().y, 0))
        self.GK_OnTarget = 0
        self.GK_NextShot = 0
        snd(self, "turret_activate", 70)
        self:NextThink(CurTime())
    end

    function ENT:Muzzle()
        return self:GetPos() + self:GetUp() * GUN_HEIGHT + self:GetAim():Forward() * 20 + self:GetAim():Up() * 9
    end

    function ENT:Visible(ply)
        local tr = util.TraceLine({ start = self:Muzzle(), endpos = ply:WorldSpaceCenter(), mask = MASK_SHOT, filter = { self, ply } })
        return not tr.Hit
    end

    function ENT:Think()
        local ct = CurTime()
        if self:GetDead() then
            -- Falling over (about 0.4 s), then lying on its side.
            if self.GK_FallAt then
                local k = math.Clamp((ct - self.GK_FallAt) / 0.4, 0, 1)
                self:SetAngles(LerpAngle(k * k, self.GK_FallFrom, self.GK_FallTo))
                if k >= 1 then self.GK_FallAt = nil end
            end
            -- Knocked over: a second of wild, harmless spray.
            if ct < (self.GK_SprayUntil or 0) then
                local a = self:GetAim()
                a.y = a.y + math.Rand(-25, 25) a.p = math.Clamp(a.p + math.Rand(-15, 15), -60, 60)
                self:SetAim(a)
                self:Shoot(false)
                self:NextThink(ct + 0.08)
                return true
            end
            if self.GK_FallAt then self:NextThink(ct + 0.03) return true end
            return
        end


        local origin = self:GetPos() + self:GetUp() * GUN_HEIGHT
        local tgt, bd
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() then
                local to = p:WorldSpaceCenter() - origin
                local d = to:Length()
                if d < RANGE and math.abs(math.AngleDifference(to:Angle().y, self:GetAngles().y)) < CONE and self:Visible(p) and (not bd or d < bd) then
                    tgt, bd = p, d
                end
            end
        end

        local aim = self:GetAim()
        if tgt then
            if tgt ~= self.GK_Target then
                self.GK_Target = tgt
                self.GK_OnTarget = 0
                self:SetLocked(true)
                snd(self, "turret_lockon", 75)
            end
            -- Lead them a little.
            local want = (tgt:WorldSpaceCenter() + tgt:GetVelocity() * 0.15 - origin):Angle()
            aim = LerpAngle(0.12, aim, want)
            self:SetAim(aim)
            local off = math.deg(math.acos(math.Clamp(aim:Forward():Dot(want:Forward()), -1, 1)))
            if off < FIRE_CONE then
                self.GK_OnTarget = self.GK_OnTarget + 0.05
                if self.GK_OnTarget > DELAY and ct > self.GK_NextShot then
                    self.GK_NextShot = ct + RATE
                    self:Shoot(true)
                end
            else
                self.GK_OnTarget = 0
            end
            if ct > (self.GK_Bark or 0) then
                self.GK_Bark = ct + math.Rand(3, 6)
                snd(self, "turret_bark" .. math.random(3), 70)
            end
        else
            if self.GK_Target then
                self.GK_Target = nil
                self:SetLocked(false)
                snd(self, "turret_locklost", 70)
            end
            -- Idle sweep about its rest facing.
            local sweep = Angle(0, self:GetAngles().y + math.sin(ct * 0.6) * 35, 0)
            self:SetAim(LerpAngle(0.05, aim, sweep))
        end
        self:NextThink(ct + 0.05)
        return true
    end

    -- One round. Harmless while it's going down.
    function ENT:Shoot(live)
        local src = self:Muzzle()
        local dir = (self:GetAim():Forward() + VectorRand() * SPREAD * (live and 1 or 4)):GetNormalized()
        self:FireBullets({
            Src = src, Dir = dir, Spread = vector_origin, Num = 1, Tracer = 1, TracerName = "AR2Tracer",
            Damage = live and DAMAGE or 0, Force = live and 2 or 0, Attacker = self, Distance = RANGE,
            Callback = function(_, tr)
                if live and IsValid(tr.Entity) and tr.Entity:IsPlayer() then
                    GK.DropHang(tr.Entity, 0.1, 1)
                    local victim = tr.Entity
                    timer.Simple(0, function() if IsValid(victim) and GK.Inv.KnockFromHands then GK.Inv.KnockFromHands(victim, src) end end)
                    tr.Entity:SetVelocity(dir * 40)
                end
            end,
        })
        self:EmitSound("NPC_FloorTurret.Shoot")
        local fx = EffectData() fx:SetOrigin(src) fx:SetAngles(self:GetAim()) fx:SetEntity(self) fx:SetScale(0.6)
        util.Effect("MuzzleEffect", fx, true, true)
    end

    function ENT:KnockOver()
        if self:GetDead() then return end
        self:SetDead(true)
        self:SetLocked(false)
        self.GK_SprayUntil = CurTime() + 1
        local a = self:GetAngles()
        self.GK_FallFrom = a
        self.GK_FallTo = Angle(a.p, a.y, a.r + (math.random(2) == 1 and 85 or -85))
        self.GK_FallAt = CurTime()
        snd(self, "turret_shutdown", 80)
        self:NextThink(CurTime())
    end

    function ENT:OnTakeDamage(d)
        if d:IsDamageType(DMG_CRUSH) then return end
        -- A heavy hit knocks it over (a blast, a thrown brick or rebar, a
        -- hammer swing); bullets only clang off.
        local inf = d:GetInflictor()
        local cls = IsValid(inf) and inf:GetClass() or ""
        if d:GetDamage() >= 30 or d:IsExplosionDamage() or d:IsDamageType(DMG_CLUB) or cls == "gk_brick" or cls == "gk_rebar_thrown" then
            timer.Simple(0, function() if IsValid(self) then self:KnockOver() end end)
        end
        self:EmitSound("physics/metal/metal_box_impact_bullet" .. math.random(3) .. ".wav", 70)
    end
end

if CLIENT then
    local laser = Material("sprites/laserbeam")
    function ENT:Initialize()
        self.Gun = ClientsideModel(util.IsValidModel("models/gknuckle/items/turret_gun.mdl") and "models/gknuckle/items/turret_gun.mdl" or "models/combine_turrets/floor_turret.mdl", RENDERGROUP_OPAQUE)
        if IsValid(self.Gun) then self.Gun:SetNoDraw(true) end
    end
    function ENT:OnRemove() if IsValid(self.Gun) then self.Gun:Remove() end end
    function ENT:Draw()
        self:DrawModel()
        if not IsValid(self.Gun) then return end
        local pivot = self:GetPos() + self:GetUp() * GUN_HEIGHT
        self.Gun:SetPos(pivot)
        self.Gun:SetAngles(self:GetAim())
        self.Gun:DrawModel()
        -- Its twin laser sights while it's live.
        if not self:GetDead() then
            local a = self:GetAim()
            local col = self:GetLocked() and Color(255, 40, 40, 200) or Color(255, 120, 60, 90)
            render.SetMaterial(laser)
            for _, side in ipairs({ -3.6, 3.6 }) do
                local s = pivot + a:Forward() * 8.6 + a:Right() * side + a:Up() * 2.9
                local tr = util.TraceLine({ start = s, endpos = s + a:Forward() * 600, mask = MASK_SHOT, filter = self })
                render.DrawBeam(s, tr.HitPos, 0.6, 0, 1, col)
            end
        end
    end
end
