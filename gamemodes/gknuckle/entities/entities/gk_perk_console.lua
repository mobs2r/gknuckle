AddCSLuaFile()

-- The perk console in each break room: a White Knuckle desktop computer.
-- Click it with a mind-hand (or E) to see three perk cards (sh_perks.lua).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Perk Console"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

if SERVER then
    function ENT:Initialize()
        self:SetModel(util.IsValidModel("models/gknuckle/items/computer.mdl") and "models/gknuckle/items/computer.mdl" or "models/props_lab/monitor01a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:SetUseType(SIMPLE_USE)
    end

    function ENT:Press(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return true end
        self:EmitSound("gknuckle/ui/computer_chime_new.wav", 65)
        GK.OfferPerks(ply, self)
        return true
    end

    function ENT:Use(ply) self:Press(ply) end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")
    function ENT:Draw()
        self:DrawModel()
        -- A soft screen glow so it reads as the thing to use.
        render.SetMaterial(glow)
        local p = self:GetPos() + self:GetUp() * 14 + self:GetForward() * 8
        render.DrawSprite(p, 26, 20, Color(120, 255, 160, 60 + math.sin(CurTime() * 3) * 20))
    end
end
