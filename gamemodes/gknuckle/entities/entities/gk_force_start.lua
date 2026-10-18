AddCSLuaFile()

-- The hub's force-start button. With fewer than 6 players waiting in the
-- vacuum, pressing it (E, or an empty mind-hand click) lets the next pull go
-- anyway, as a free-for-all: solo, 1v1, up to 1v1v1v1v1 (sv_arena.lua).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Force Start"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "ArmedUntil")
    self:NetworkVar("Float", 1, "Held") -- 0..1 of the hold needed
end
local HOLD = 3 -- seconds of holding it down

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/maxofs2d/button_05.mdl")
        self:SetModelScale(2.5)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetUseType(CONTINUOUS_USE) -- held, not tapped
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    -- Held down (E held, or a mind-hand held on it): it counts up while
    -- someone keeps holding it, and resets when they let go (or get kicked
    -- off it: a kick to the head ragdolls them).
    function ENT:Press(ply)
        if not IsValid(ply) or not ply:Alive() or GK.IsRagdolled(ply) then return false end
        self.GK_HeldBy, self.GK_HeldAt = ply, CurTime()
        return false -- keep the hand free: Press comes again every tick while it's held
    end

    function ENT:Use(ply) self:Press(ply) end

    function ENT:Think()
        local ct = CurTime()
        local holding = IsValid(self.GK_HeldBy) and ct - (self.GK_HeldAt or 0) < 0.25 and not GK.IsRagdolled(self.GK_HeldBy)
        local h = self:GetHeld()
        if holding then
            h = math.min(1, h + 0.1 / HOLD)
            if h >= 1 and self:GetArmedUntil() < ct then
                -- gk_force_start_N starts pad N's run; an unnumbered one, any pad's.
                GK.ForceStart(self.GK_HeldBy, tonumber(string.match(self:GetName() or "", "_(%d+)$")))
                self:SetArmedUntil(ct + 60)
            end
        else
            h = 0
        end
        if h ~= self:GetHeld() then self:SetHeld(h) end
        self:NextThink(ct + 0.1)
        return true
    end
end

if CLIENT then
    -- Glows red while armed (the next vacuum will go).
    function ENT:Draw()
        local armed = self:GetArmedUntil() > CurTime()
        local h = self:GetHeld()
        if armed then render.SetColorModulation(1, 0.2, 0.2)
        elseif h > 0 then render.SetColorModulation(1, 1 - h * 0.8, 1 - h * 0.8) end -- reddening as it is held
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
        if armed or h > 0 then
            local l = DynamicLight(self:EntIndex())
            if l then
                l.pos = self:GetPos() + Vector(0, 0, 10)
                l.r, l.g, l.b = 255, 40, 40
                l.brightness = armed and (2 + math.sin(CurTime() * 8)) or h * 2 * (0.6 + math.sin(CurTime() * (6 + h * 14)) * 0.4)
                l.size = 160
                l.dietime = CurTime() + 0.1
            end
        end
    end
end
