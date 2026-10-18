AddCSLuaFile()

-- The run-mode switch beside each vacuum pad's force-start button: press it
-- (E, or click it with an empty mind-hand) to step that pad's next run
-- through Campaign, Iron Knuckle and Hard (sv_arena.lua). A lamp shows the
-- choice by colour (white, steel blue, red) and a small plate names it.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Run Mode"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"

local MODES = { "campaign", "iron", "hard" }
local NAMES = { campaign = "CAMPAIGN", iron = "IRON KNUCKLE", hard = "HARD" }
local COLS = { campaign = Color(235, 230, 220), iron = Color(120, 170, 255), hard = Color(255, 50, 40) }

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Pad")
    self:NetworkVar("String", 0, "Mode")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/maxofs2d/button_02.mdl")
        self:SetModelScale(2)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if self:GetMode() == "" then self:SetMode(GK.DefaultRunMode and GK.DefaultRunMode() or "campaign") end
    end

    function ENT:Press(ply)
        if (self.GK_Next or 0) > CurTime() then return true end
        self.GK_Next = CurTime() + 0.4
        local i = 1
        for k, m in ipairs(MODES) do if m == self:GetMode() then i = k end end
        self:SetMode(MODES[i % #MODES + 1])
        self:EmitSound("buttons/button" .. (self:GetMode() == "hard" and "8" or "9") .. ".wav", 70)
        if GK.SetPadMode then GK.SetPadMode(self:GetPad(), self:GetMode()) end
        return true
    end
    function ENT:Use(ply) if IsValid(ply) and ply:IsPlayer() then self:Press(ply) end end
end

if CLIENT then
    surface.CreateFont("GK_ModePlate", { font = "Impact", size = 48, weight = 800 })
    function ENT:Draw()
        local mode = self:GetMode() ~= "" and self:GetMode() or "campaign"
        local c = COLS[mode] or COLS.campaign
        render.SetColorModulation(c.r / 255, c.g / 255, c.b / 255)
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
        local l = DynamicLight(self:EntIndex())
        if l then
            l.pos = self:GetPos() + Vector(0, 0, 14)
            l.r, l.g, l.b = c.r, c.g, c.b
            l.brightness = 1.5
            l.size = 110
            l.dietime = CurTime() + 0.1
        end
        -- The plate above it, facing whoever's looking.
        if EyePos():DistToSqr(self:GetPos()) > 600 * 600 then return end
        local ang = (EyePos() - self:GetPos()):Angle()
        ang = Angle(0, ang.y + 90, 90)
        cam.Start3D2D(self:GetPos() + Vector(0, 0, 30), ang, 0.12)
            draw.SimpleText(NAMES[mode] or mode, "GK_ModePlate", 0, 0, c, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end
end
