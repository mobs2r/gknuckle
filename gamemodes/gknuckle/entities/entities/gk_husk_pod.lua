AddCSLuaFile()

-- A husk pod in the hub's birthing room: an unhatched husk. Break it (hit,
-- shoot, throw something at it) and it bursts in orange glowing blood that
-- dims to black and fades away, like crystal gore (sh_crystalgore.lua).
-- It grows back a while later.
-- Map keyvalues (or set before Spawn): model (default a WK shroompod),
-- height (units, default 72: about a husk), regrow (seconds, default 90).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Husk Pod"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local DEFAULT_MODEL = "models/gknuckle/wk/prop_shroompod_regular_01.mdl"
local BLOOD = Color(255, 140, 40) -- the husks' orange
local HEALTH = 5 -- one kick, a thrown anything

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Broken")
end

if SERVER then
    function ENT:KeyValue(k, v)
        if k == "model" then self.GK_Model = v
        elseif k == "height" then self.GK_Height = tonumber(v)
        elseif k == "regrow" then self.GK_Regrow = tonumber(v) end
    end

    function ENT:Initialize()
        local mdl = self.GK_Model or DEFAULT_MODEL
        self:SetModel(util.IsValidModel(mdl) and mdl or "models/props_junk/watermelon01.mdl")
        -- Sized to a husk's height, then a plain frozen box for collision: no
        -- loose physics (see the vphysics run crash notes in gk_turret.lua).
        local mins, maxs = self:OBBMins(), self:OBBMaxs()
        local s = (self.GK_Height or 72) / math.max(maxs.z - mins.z, 1)
        self:SetModelScale(s)
        self.GK_Mins, self.GK_Maxs = mins * s, maxs * s
        self:Grow()
    end

    function ENT:Grow()
        self:SetBroken(false)
        self:SetNoDraw(false)
        self:SetCollisionBounds(self.GK_Mins, self.GK_Maxs)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX) -- a box, no physics object
        self:SetHealth(HEALTH)
        self:NextThink(CurTime() + 0.5)
    end

    function ENT:OnTakeDamage(d)
        if self:GetBroken() then return end
        self:SetHealth(self:Health() - d:GetDamage())
        self:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 70, math.random(80, 95))
        if self:Health() <= 0 then
            local dir = d:GetDamageForce():GetNormalized()
            -- Next tick: damage can arrive inside a physics callback.
            timer.Simple(0, function() if IsValid(self) then self:Burst(dir) end end)
        end
    end

    function ENT:Burst(dir)
        if self:GetBroken() then return end
        self:SetBroken(true)
        local c = self:WorldSpaceCenter()
        GK.CrystalBurstColor(c, 40, dir, BLOOD)
        GK.CrystalBurstColor(c + Vector(0, 0, (self.GK_Maxs.z - self.GK_Mins.z) * 0.25), 30, vector_up, BLOOD)
        self:EmitSound("physics/flesh/flesh_bloody_break.wav", 80, 90)
        self:EmitSound("npc/antlion_grub/squashed.wav", 75, 85)
        self:SetNoDraw(true)
        self:SetSolid(SOLID_NONE)
        -- What was incubating spills out: roaches (now and then a platinum one)
        -- and sometimes a glowing xenium gem, the virus's crop.
        local base = self:GetPos() + Vector(0, 0, 4)
        for i = 1, math.random(3, 6) do
            local a = Angle(0, i * 60 + math.Rand(-20, 20), 0):Forward() * math.Rand(10, 30)
            GK.SpawnRoach(math.random() < 0.2 and "platinum" or "gold", base + a)
        end
        if math.random() < 0.35 then GK.SpawnRoach("xenium", base) end
        -- Now and then something nastier was incubating: a bloodbug bursts
        -- out angry, goes for whoever's nearest for a while, then settles.
        if GK.Birthing and GK.Birthing.PodBug then GK.Birthing.PodBug(self:WorldSpaceCenter() + Vector(0, 0, 24)) end
        self:RegrowLater(self.GK_Regrow or 90)
    end

    -- Grabbing it with a mind-hand pops it (gk_mind's Press).
    function ENT:Press(ply)
        if self:GetBroken() then return false end
        self:Burst(ply:GetAimVector())
        return true
    end

    -- Walking into it pops it too: nobody gets stuck inside a pod.
    function ENT:Think()
        if not self:GetBroken() then
            local lo, hi = self:GetPos() + self.GK_Mins - Vector(20, 20, 4), self:GetPos() + self.GK_Maxs + Vector(20, 20, 0) -- a player touching it stands its hull width (12 u) off it
            for _, e in ipairs(ents.FindInBox(lo, hi)) do
                if e:IsPlayer() and e:Alive() then self:Burst(e:GetVelocity():GetNormalized()) break end
            end
        end
        self:NextThink(CurTime() + 0.2)
        return true
    end

    -- Grows back once nobody is standing where it would be.
    function ENT:RegrowLater(t)
        timer.Simple(t, function()
            if not IsValid(self) then return end
            for _, e in ipairs(ents.FindInBox(self:GetPos() + self.GK_Mins, self:GetPos() + self.GK_Maxs)) do
                if e:IsPlayer() then self:RegrowLater(5) return end
            end
            self:Grow()
        end)
    end
end

if CLIENT then
    function ENT:Draw()
        if self:GetBroken() then return end
        self:DrawModel()
    end
end
