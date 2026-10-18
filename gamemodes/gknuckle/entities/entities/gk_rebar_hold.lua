AddCSLuaFile()

-- A White Knuckle rebar stuck in a wall: frozen, so the mind treats it as
-- climbable. The model's base is at its origin and it runs along +X, so it
-- sticks out of the wall along its forward.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Rebar Handhold"
ENT.Spawnable = false
ENT.GKHandhold = true

ENT.GKModel = "models/gknuckle/items/rebar.mdl"
ENT.GKScale = 0.75
ENT.GKLength = 49.7 * 0.75

if SERVER then
    function ENT:Initialize()
        -- Rope / explosive variants (gk_rebar_thrown) use their own WK model.
        self.GK_Kind = self.GK_Kind or "rebar"
        self:SetNW2String("gk_kind", self.GK_Kind)
        self:SetModel(GK.RebarKinds and GK.RebarKinds[self.GK_Kind] and GK.RebarKinds[self.GK_Kind].model or self.GKModel)
        self:SetModelScale(self.GKScale)
        -- (Kept as a thin frozen physics box: a world-aligned box around a bar
        -- at an angle swallowed later throws aimed past it. Bars come from
        -- players during play, not from the room hooks.)
        self:PhysicsInitBox(Vector(0, -3, -3), Vector(self.GKLength, 3, 3)) -- 6 u thick: easy to grab from any side
        self:SetSolid(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        -- A bar someone's pinned to is removed once they're off it (sh_impale.lua).
        if not self.GK_PinsPlayer then SafeRemoveEntityDelayed(self, 60) end
    end
end

if CLIENT then
    function ENT:Draw() if GK.DrawRebar then GK.DrawRebar(self) else self:DrawModel() end end
end
