AddCSLuaFile()

-- Barnacle: White Knuckle's ceiling grabber (a port of DEN_Barnacle and its
-- tongue). Its tongue creeps down and sideways, latches onto something, and
-- hangs there as a lure. Brush it and it grabs: you're knocked off your hold
-- (0.4 s before you can grab again) and reeled up toward its mouth; within
-- 2 m it bites every half second. Hurt it and it lets go. The tongue itself
-- is a handhold, like a rope, but you can't climb up past its grip.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Barnacle"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local SEARCH, REACH, GRAB, RETRACT, DEAD = 0, 1, 2, 3, 4

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "State")
    self:NetworkVar("Vector", 0, "Tip")
    self:NetworkVar("Entity", 0, "Victim")
end

-- The mouth the tongue hangs from.
function ENT:Mouth() return self:GetPos() - self:GetUp() * 10 end

-- Its tongue as a rope segment for the mind-hands (GK.RopeGrip), while it's out.
function ENT:RopeSegment()
    local st = self:GetState()
    if st ~= REACH and st ~= GRAB then return end
    local a, b = self:Mouth(), self:GetTip()
    if a:DistToSqr(b) < 400 then return end
    return a, b
end

if SERVER then
    local M = 39.4
    local SCAN = 5 * M           -- tongue reach
    local SPEED = 1.2 * M        -- tongue creep, u/s
    local RETRACT_SPEED = 4 * M
    local PULL = 70              -- u/s reeling a victim up
    local BITE_RANGE = 2 * M
    local BITE_DMG, BITE_RATE = 10, 0.5
    local WAIT = 5               -- after a retract, before reaching again

    local function snd(self, name, lvl) self:EmitSound("gknuckle/creatures/" .. name .. ".wav", lvl or 72, math.random(92, 108)) end

    function ENT:Initialize()
        self:SetModel(util.IsValidModel("models/gknuckle/items/barnacle.mdl") and "models/gknuckle/items/barnacle.mdl" or "models/barnacle.mdl")
        -- Hang from the ceiling above where it was placed.
        local up = util.TraceLine({ start = self:GetPos(), endpos = self:GetPos() + Vector(0, 0, 160), mask = MASK_SOLID_BRUSHONLY })
        if up.Hit and not up.StartSolid then self:SetPos(up.HitPos) end
        self:SetAngles(Angle(0, self:GetAngles().y, 0))
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-14, -14, -30), Vector(14, 14, 0))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetHealth(20)
        self:SetState(SEARCH)
        self:SetTip(self:Mouth())
        self.GK_Wait = CurTime() + math.Rand(0.5, 3)
        self:NextThink(CurTime())
    end

    -- Where to reach: down and a little off to the side, as far as it can,
    -- stopping at whatever it touches.
    function ENT:AimPoint()
        local dir = (Vector(0, 0, -1) + VectorRand() * 0.35):GetNormalized()
        local tr = util.TraceLine({ start = self:Mouth(), endpos = self:Mouth() + dir * SCAN, mask = MASK_SOLID, filter = self })
        return tr.HitPos, tr.Hit
    end

    -- Distance from a player's body to the tongue (mouth -> tip).
    local function touching(ply, a, b)
        local c = ply:WorldSpaceCenter()
        local ab = b - a
        local t = math.Clamp((c - a):Dot(ab) / math.max(ab:LengthSqr(), 1), 0, 1)
        local p = a + ab * t
        local mins, maxs = ply:WorldSpaceAABB()
        return p.x > mins.x - 4 and p.x < maxs.x + 4 and p.y > mins.y - 4 and p.y < maxs.y + 4 and p.z > mins.z - 4 and p.z < maxs.z + 4
    end

    function ENT:Think()
        local ct, st = CurTime(), self:GetState()
        if st == DEAD then return end
        local mouth = self:Mouth()
        local tip = self:GetTip()
        local dt = 0.05

        if st == SEARCH then
            if ct > self.GK_Wait then
                self.GK_Aim, self.GK_Latch = self:AimPoint()
                self.GK_ReachUntil = ct + math.Rand(10, 40)
                self:SetState(REACH)
                snd(self, "barnacle_reach" .. math.random(2), 65)
            end
        elseif st == REACH then
            -- Creep toward the aim point with a little wobble, then hang there.
            local to = self.GK_Aim - tip
            if to:Length() > 2 then
                local wob = Vector(math.sin(ct * 2.1), math.cos(ct * 1.7), 0) * 3
                self:SetTip(tip + to:GetNormalized() * math.min(to:Length(), SPEED * dt) + wob * dt)
            end
            -- Anyone brushing the tongue gets grabbed.
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() and not p.GK_TongueOf and touching(p, mouth, self:GetTip()) then
                    self:Grab(p)
                    break
                end
            end
            if ct > self.GK_ReachUntil and self:GetState() == REACH then self:Retract() end
        elseif st == GRAB then
            local v = self:GetVictim()
            if not IsValid(v) or not v:Alive() or v:GetPos():Distance(mouth) > SCAN * 2 then self:Retract() return self:Next(ct) end
            -- (The reeling itself is in GM:Move, predicted: gk_tongue below.)
            self:SetTip(v:WorldSpaceCenter() + Vector(0, 0, 20))
            if v:EyePos():Distance(mouth) < BITE_RANGE and ct > (self.GK_NextBite or 0) then
                self.GK_NextBite = ct + BITE_RATE
                local d = DamageInfo()
                d:SetDamage(BITE_DMG) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
                v:TakeDamageInfo(d)
                snd(self, "barnacle_burp1", 70)
                v:ViewPunch(Angle(math.Rand(-4, 4), math.Rand(-4, 4), 0))
            end
        elseif st == RETRACT then
            local to = mouth - tip
            if to:Length() < 4 then
                self:SetTip(mouth)
                self:SetState(SEARCH)
                self.GK_Wait = ct + WAIT
            else
                self:SetTip(tip + to:GetNormalized() * math.min(to:Length(), RETRACT_SPEED * dt))
            end
        end
        return self:Next(ct)
    end

    function ENT:Next(ct) self:NextThink(ct + 0.05) return true end

    function ENT:Grab(p)
        self:SetState(GRAB)
        self:SetVictim(p)
        p.GK_TongueOf = self
        p:SetNW2Bool("gk_grabbed", true)
        p:SetNW2Entity("gk_tongue", self)
        GK.DropHang(p, 0.4, 1)
        snd(self, "barnacle_grab" .. math.random(2), 80)
    end

    function ENT:Retract()
        local v = self:GetVictim()
        if IsValid(v) then v.GK_TongueOf = nil v:SetNW2Bool("gk_grabbed", false) v:SetNW2Entity("gk_tongue", NULL) end
        self:SetVictim(NULL)
        if self:GetState() ~= DEAD then
            self:SetState(RETRACT)
            snd(self, "barnacle_retract" .. math.random(2), 65)
        end
    end

    function ENT:OnTakeDamage(d)
        if self:GetState() == DEAD then return end
        self:SetHealth(self:Health() - d:GetDamage())
        snd(self, "barnacle_hurt" .. math.random(2), 75)
        if self:Health() <= 0 then
            self:Retract()
            self:SetState(DEAD)
            snd(self, "barnacle_death" .. math.random(2), 80)
            local fx = EffectData() fx:SetOrigin(self:Mouth()) fx:SetColor(BLOOD_COLOR_RED)
            util.Effect("BloodImpact", fx, true, true)
            self:SetColor(Color(110, 80, 80))
        else
            self:Retract() -- any hurt makes it let go
        end
    end

    function ENT:OnRemove() self:Retract() end
end

if CLIENT then
    local tongue = Material("gknuckle/creatures/barnacle_tongue.png", "noclamp")
    function ENT:Initialize()
        self:SetRenderBounds(Vector(-40, -40, -400), Vector(40, 40, 20))
    end
    function ENT:Draw()
        self:DrawModel()
        local st = self:GetState()
        if st == SEARCH or st == DEAD then return end
        local a, b = self:Mouth(), self:GetTip()
        local len = a:Distance(b)
        if len < 2 then return end
        render.SetMaterial(tongue)
        -- A slightly sagging tongue in a few segments.
        local prev, n = a, 6
        render.StartBeam(n + 1)
        for i = 0, n do
            local t = i / n
            local p = LerpVector(t, a, b) - Vector(0, 0, math.sin(t * math.pi) * len * 0.06)
            render.AddBeam(p, 2.5, t * len / 32, Color(255, 255, 255))
        end
        render.EndBeam()
    end
end
