AddCSLuaFile()

-- Gravity surge: touch it and your mind lifts and throws with gravity-gun
-- strength for GK.Config.SurgeTime seconds. Respawns after a while.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Gravity Surge"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local RESPAWN = 45

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "ReadyAt")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/items/combine_rifle_ammo01.mdl")
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-16, -16, 0), Vector(16, 16, 32))
        self:SetTrigger(true)
        self:SetReadyAt(0)
    end

    function ENT:StartTouch(ply)
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
        if self:GetReadyAt() > CurTime() then return end
        GK.GiveSurge(ply)
        self:SetReadyAt(CurTime() + RESPAWN)
    end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")

    function ENT:Draw()
        if self:GetReadyAt() > CurTime() then return end
        local t = CurTime()
        local pos = self:GetPos() + Vector(0, 0, 20 + math.sin(t * 3) * 4)
        self:SetRenderOrigin(pos)
        self:SetRenderAngles(Angle(0, t * 90, 0))
        self:DrawModel()
        self:SetRenderOrigin()
        self:SetRenderAngles()
        render.SetMaterial(glow)
        render.DrawSprite(pos, 48, 48, Color(255, 140, 30, 200))
    end
end
