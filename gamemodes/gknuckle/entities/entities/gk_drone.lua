AddCSLuaFile()

-- The training drone (WK's Denizen_Drone in the Foundations training rooms):
-- a flying charger like the bloodbug (same wander / spot / wind-up / charge,
-- gk_bloodbug.lua), in a V Corp drone shell with a spinning rotor. Shot down,
-- it sparks and drops. Spawned in the hub's training rooms (sv_creatures.lua).
ENT.Type = "anim"
ENT.Base = "gk_bloodbug"
ENT.PrintName = "Training Drone"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.GKNoWings = true -- a rotor, not wings (gk_bloodbug draws wings)

local BODY = "models/gknuckle/items/drone.mdl"
local PROP = "models/gknuckle/items/drone_prop.mdl"

if SERVER then
    function ENT:Initialize()
        self.BaseClass.Initialize(self)
        if util.IsValidModel(BODY) then self:SetModel(BODY) end
    end

    function ENT:Die()
        self.BaseClass.Die(self)
        local fx = EffectData() fx:SetOrigin(self:WorldSpaceCenter()) fx:SetMagnitude(2) fx:SetScale(1)
        util.Effect("Sparks", fx, true, true)
        self:EmitSound("gknuckle/creatures/turret_shutdown.wav", 75)
        self:SetColor(Color(90, 90, 90))
    end
end

if CLIENT then
    function ENT:Initialize()
        self.GK_Prop = ClientsideModel(PROP, RENDERGROUP_OPAQUE)
        if IsValid(self.GK_Prop) then self.GK_Prop:SetNoDraw(true) end
    end
    function ENT:OnRemove() if IsValid(self.GK_Prop) then self.GK_Prop:Remove() end end

    function ENT:Draw()
        self.BaseClass.Draw(self)
        if not IsValid(self.GK_Prop) then return end
        -- The rotor on top, spinning (stopped once it's down).
        local a = self:GetAngles()
        if self:GetState() ~= 5 then a:RotateAroundAxis(self:GetUp(), (CurTime() * 1440) % 360) end
        self.GK_Prop:SetRenderOrigin(self:GetPos())
        self.GK_Prop:SetRenderAngles(a)
        self.GK_Prop:SetupBones()
        self.GK_Prop:DrawModel()
    end
end
