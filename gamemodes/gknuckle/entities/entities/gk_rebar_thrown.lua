AddCSLuaFile()

-- A thrown rebar, flying like White Knuckle's Projectile_Rebar: fast, nearly
-- flat, traced every tick so hits land on the exact body part.
--   wall / frozen prop -> sticks in at the angle it hit, as a climbable handhold
--   player head        -> takes it off;  legs -> take them off
--   player body        -> runs them through and pins them (sh_impale.lua)
--   loose prop         -> knocks it and drops as a pick-up-able rebar
-- GK_Kind (set before Spawn) picks White Knuckle's variants:
--   "rope"      Rebar Rope: sticks the same, and a climbable rope (gk_rope) hangs from it
--   "explosive" Rebar-Explosive: blows up on impact, whatever it hits (WK), and the
--               blast throws everyone near it, the thrower too: a rebar rocket jump
-- Like WK, a bar that hits a wall at a glancing angle (more than 30 degrees
-- off head-on) skips off it at 0.8x speed instead of sticking.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Thrown Rebar"
ENT.Spawnable = false

local LENGTH = 49.7 * 0.75 -- same bar as gk_rebar_hold

-- Model per kind; the rope/explosive meshes are centred on their origin, so
-- they're drawn shifted forward half a length to line up with the plain bar.
GK.RebarKinds = {
    rebar     = { item = "rebar",      model = "models/gknuckle/items/rebar.mdl" },
    rope      = { item = "rebarrope",  model = "models/gknuckle/items/rebarrope.mdl", centred = true },
    explosive = { item = "rebarexplo", model = "models/gknuckle/items/rebarexplo.mdl", centred = true },
}

-- Shared draw for thrown and stuck rebar (gk_rebar_hold uses it too).
function GK.DrawRebar(ent)
    local kind = GK.RebarKinds[ent:GetNW2String("gk_kind", "rebar")] or GK.RebarKinds.rebar
    if kind.centred then
        ent:SetRenderOrigin(ent:GetPos() + ent:GetForward() * ent:GetModelScale() * 49.7 / 2)
        ent:SetupBones()
        ent:DrawModel()
        ent:SetRenderOrigin(nil)
    else
        ent:DrawModel()
    end
end

local glow = CLIENT and Material("sprites/light_glow02_add")
function ENT:Draw()
    GK.DrawRebar(self)
    -- The explosive rod glows red in flight: you can see what's coming.
    if self:GetNW2String("gk_kind", "") == "explosive" then
        local p = 0.7 + math.sin(CurTime() * 30) * 0.3
        render.SetMaterial(glow)
        render.DrawSprite(self:GetPos(), 40 * p, 40 * p, Color(255, 50, 30, 230))
    end
end

if SERVER then
    local C = GK.Config

    function ENT:Initialize()
        self.GK_Kind = self.GK_Kind or "rebar"
        self:SetNW2String("gk_kind", self.GK_Kind)
        self:SetModel(GK.RebarKinds[self.GK_Kind].model)
        self:SetModelScale(0.75)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self.GK_Thrower = self:GetOwner()
        self.GK_Vel = self.GK_Vel or self:GetForward() * C.RebarThrowSpeed
        self.GK_Born = CurTime()
        self:EmitSound("gknuckle/rebar/throw.wav", 70, math.random(95, 105), 0.7)
        -- The explosive rod's tell: it screams in flight (it gibs on a direct hit).
        if self.GK_Kind == "explosive" then
            self.GK_Whistle = CreateSound(self, "weapons/rpg/rocket1.wav")
            self.GK_Whistle:PlayEx(0.8, 140)
        end
        self:NextThink(CurTime())
    end
    function ENT:OnRemove() if self.GK_Whistle then self.GK_Whistle:Stop() end end

    -- Drops as an ordinary rebar item you can pick back up.
    function ENT:DropItem(pos, vel)
        local it = ents.Create("gk_item")
        it.GKItemClass = GK.RebarKinds[self.GK_Kind].item
        it.GKItemData = { count = 1 }
        it:SetPos(pos)
        it:SetAngles(self:GetAngles())
        it:Spawn()
        local phys = it:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(vel or vector_origin) end
        self:Remove()
    end

    -- Rebar-Explosive going off.
    function ENT:Explode(pos)
        local attacker = IsValid(self.GK_Thrower) and self.GK_Thrower or game.GetWorld()
        -- Throws everyone near it (this is what makes the rocket jump).
        GK.Explode(pos, { radius = 200, damage = 110, force = 620, lift = 0.3, attacker = attacker, inflictor = IsValid(self) and self or attacker })
        hook.Run("GK_RebarExplode", pos, "hit")
        sound.Play("gknuckle/items/rebar_detonate" .. table.Random({ "", "2", "3" }) .. ".wav", pos, 95, math.random(95, 105))
    end

    function ENT:Stick(tr, dir)
        local bar = ents.Create("gk_rebar_hold")
        bar.GK_Kind = self.GK_Kind
        bar:SetPos(tr.HitPos + dir * 6) -- base sunk into the surface, the rest sticks out back toward the thrower
        bar:SetAngles((-dir):Angle())
        bar:Spawn()
        if self.GK_Kind == "rope" then
            -- The rope hangs from just short of the bar's free end.
            local rope = ents.Create("gk_rope")
            rope:SetPos(bar:GetPos() + bar:GetForward() * bar.GKLength * 0.85)
            rope:Spawn()
            bar:DeleteOnRemove(rope)
        elseif self.GK_Kind == "explosive" then
            local thrower = self.GK_Thrower
            bar:EmitSound("weapons/c4/c4_beep1.wav", 75, 120)
            timer.Simple(1.2, function()
                if not IsValid(bar) then return end
                local pos = bar:GetPos() + bar:GetForward() * 10
                bar:Remove()
                local fx = EffectData() fx:SetOrigin(pos)
                util.Effect("Explosion", fx, true, true)
                util.BlastDamage(game.GetWorld(), IsValid(thrower) and thrower or game.GetWorld(), pos, 200, 110)
                hook.Run("GK_RebarExplode", pos, "stuck")
                sound.Play("gknuckle/items/rebar_detonate" .. table.Random({ "", "2", "3" }) .. ".wav", pos, 95, math.random(95, 105))
            end)
            self:Remove()
            return
        end
        bar:EmitSound("gknuckle/rebar/impact.wav", 80, math.random(95, 105))
        local thrower = self.GK_Thrower
        if IsValid(thrower) then
            thrower.GK_Rebars = thrower.GK_Rebars or {}
            table.insert(thrower.GK_Rebars, bar)
            while #thrower.GK_Rebars > 3 do
                local old = table.remove(thrower.GK_Rebars, 1)
                if IsValid(old) then old:Remove() end
            end
        end
        self:Remove()
    end

    function ENT:Think()
        if self.GK_Done then return end
        local dt = FrameTime()
        local vel = self.GK_Vel
        vel.z = vel.z - C.RebarGravity * dt
        local dir = vel:GetNormalized()
        local tip = self:GetPos() + dir * LENGTH
        local young = CurTime() - self.GK_Born < 0.25
        local thrower = self.GK_Thrower
        local tr = util.TraceLine({
            start = tip, endpos = tip + vel * dt, mask = MASK_SHOT,
            filter = function(e) return e ~= self and not (young and e == thrower) end,
        })

        if tr.Hit then
            self.GK_Done = true -- one hit only, even if handling it errors
            local hit = tr.Entity
            if self.GK_Kind == "explosive" then
                -- A direct hit: nothing left of them but chunks (sh_impale_prone.lua).
                if IsValid(hit) and hit:IsPlayer() and hit:Alive() and GK.Gib then GK.Gib(hit, thrower, tr.HitPos) end
                self:Explode(tr.HitPos - dir * 4)
                self:Remove()
                return true
            end
            if IsValid(hit) and hit:IsPlayer() then
                if hit:Alive() and not GK.IsImpaled(hit) then
                    local res = GK.RebarHit(hit, tr, dir, self, thrower)
                    self.GK_Result = res
                    hook.Run("GK_RebarHit", hit, res, thrower, tr)
                    if res == "head" or res == "legs" then
                        self:DropItem(tr.HitPos, dir * 120)
                    else
                        self:Remove() -- it's the bar they're pinned on now
                    end
                else
                    hit:TakeDamage(C.RebarDamage, IsValid(thrower) and thrower or self, self)
                    self:DropItem(tr.HitPos, -dir * 60)
                end
                return true
            end
            local phys = IsValid(hit) and hit:GetPhysicsObject()
            if IsValid(phys) and phys:IsMotionEnabled() then
                phys:ApplyForceOffset(vel * 4, tr.HitPos)
                hit:EmitSound("gknuckle/rebar/ricochet.wav", 75)
                self:DropItem(tr.HitPos - dir * 4, -dir * 80)
                return true
            end
            if tr.HitSky then self:Remove() return true end
            -- A glancing hit skips off (twice at most) rather than sticking.
            if dir:Dot(-tr.HitNormal) < math.cos(math.rad(60)) and (self.GK_Skips or 0) < 2 then
                self.GK_Skips = (self.GK_Skips or 0) + 1
                self.GK_Done = false
                self.GK_Vel = (vel - 2 * vel:Dot(tr.HitNormal) * tr.HitNormal) * 0.8
                self:SetPos(tr.HitPos + tr.HitNormal * 2 - self.GK_Vel:GetNormalized() * LENGTH)
                sound.Play("gknuckle/rebar/ricochet.wav", tr.HitPos, 75, math.random(95, 110))
                local fx = EffectData() fx:SetOrigin(tr.HitPos) fx:SetNormal(tr.HitNormal)
                util.Effect("MetalSpark", fx, true, true)
                self:NextThink(CurTime())
                return true
            end
            self:Stick(tr, dir)
            return true
        end

        self:SetPos(self:GetPos() + vel * dt)
        self:SetAngles(dir:Angle())
        if CurTime() - self.GK_Born > 10 then self:DropItem(self:GetPos()) end -- WK lifetime
        self:NextThink(CurTime())
        return true
    end

    -- A rebar rocket jump shouldn't kill you: your own blast hurts a third as much.
    hook.Add("EntityTakeDamage", "GK_RebarSelfBlast", function(ent, d)
        local inf = d:GetInflictor()
        if ent:IsPlayer() and d:IsExplosionDamage() and d:GetAttacker() == ent and IsValid(inf) and inf:GetClass() == "gk_rebar_thrown" then
            d:ScaleDamage(0.3)
        end
    end)
end
