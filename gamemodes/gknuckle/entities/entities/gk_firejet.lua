AddCSLuaFile()

-- A fire jet (WK's UT_Fire, e.g. Hazard_Fire_Jet_Tall_Timer): roars on for a
-- few seconds, then cuts out; anyone in the flames burns and is knocked off
-- whatever they're holding. Its box comes from the room's hazard data
-- (sv_hazards.lua); the flames fill it.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Fire Jet"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "Half")  -- half extents, in its own (yawed) frame
    self:NetworkVar("Bool", 0, "On")
end

local ON, OFF = 3, 3

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:DrawShadow(false)
        self.GK_Phase = CurTime() + math.Rand(0, OFF)
        self:SetOn(false)
        self:NextThink(CurTime())
    end
    function ENT:UpdateTransmitState() return TRANSMIT_PVS end

    function ENT:Inside(p)
        local l = self:WorldToLocal(p)
        local h = self:GetHalf()
        return math.abs(l.x) <= h.x and math.abs(l.y) <= h.y and math.abs(l.z) <= h.z
    end

    function ENT:Think()
        local ct = CurTime()
        if ct > self.GK_Phase then
            local on = not self:GetOn()
            self:SetOn(on)
            self.GK_Phase = ct + (on and ON or OFF)
            if on then self:EmitSound("ambient/fire/ignite.wav", 80) end
        end
        if self:GetOn() then
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() and self:Inside(p:WorldSpaceCenter()) and (p.GK_FireNext or 0) < ct then
                    p.GK_FireNext = ct + 0.25
                    local d = DamageInfo()
                    d:SetDamage(5) d:SetDamageType(DMG_BURN)
                    d:SetAttacker(game.GetWorld()) d:SetInflictor(self)
                    p:TakeDamageInfo(d)
                    p:Ignite(1)
                    GK.DropHang(p, 0.3, 1)
                end
            end
        end
        self:NextThink(ct + 0.1)
        return true
    end
end

if CLIENT then
    function ENT:Initialize()
        self.Emitter = ParticleEmitter(self:GetPos())
        self:SetRenderBounds(Vector(-300, -300, -300), Vector(300, 300, 300))
    end
    function ENT:OnRemove() if self.Emitter then self.Emitter:Finish() end end
    function ENT:Draw() end
    function ENT:DrawTranslucent()
        if not self:GetOn() or not self.Emitter then return end
        if (self.GK_NextPuff or 0) > CurTime() then return end
        self.GK_NextPuff = CurTime() + 0.03
        local h = self:GetHalf()
        -- Flames pour along the box's longest axis.
        for _ = 1, 3 do
            local l = Vector(math.Rand(-h.x, h.x), math.Rand(-h.y, h.y), math.Rand(-h.z, h.z))
            local p = self.Emitter:Add("particles/flamelet" .. math.random(1, 5), self:LocalToWorld(l))
            if p then
                p:SetVelocity(VectorRand() * 20 + Vector(0, 0, 60))
                p:SetDieTime(math.Rand(0.3, 0.6))
                p:SetStartAlpha(220) p:SetEndAlpha(0)
                p:SetStartSize(math.Rand(10, 18)) p:SetEndSize(2)
                p:SetRoll(math.Rand(0, 360)) p:SetRollDelta(math.Rand(-2, 2))
            end
        end
        local dl = DynamicLight(self:EntIndex())
        if dl then
            dl.pos = self:GetPos() dl.r, dl.g, dl.b = 255, 130, 40
            dl.brightness = 3 dl.size = 260 dl.decay = 800 dl.dietime = CurTime() + 0.1
        end
    end
end
