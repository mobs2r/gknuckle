AddCSLuaFile()

-- A ladder volume, like Source's ladder clip (func_ladder): an invisible box
-- in front of a White Knuckle ladder. Walk into it and you're on the ladder
-- (sh_ladders.lua). The level code places one on every red ladder.
--
-- Set before Spawn (or with SetBox afterwards): position = bottom centre of
-- the ladder's face, angles = facing OUT from the ladder (toward the climber),
-- GKWidth / GKHeight in units.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Ladder"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"

ENT.GKWidth = 32
ENT.GKHeight = 256
ENT.GKDepth = 24 -- how far out from the ladder face the volume reaches

-- Map-set size: "width" / "height" keyvalues.
function ENT:KeyValue(k, v)
    if k == "width" then self.GKWidth = tonumber(v) or self.GKWidth end
    if k == "height" then self.GKHeight = tonumber(v) or self.GKHeight end
end

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "Width")
    self:NetworkVar("Float", 1, "Height")
end

-- Is world point p inside this ladder's volume (grown by pad)?
function ENT:Contains(p, pad)
    pad = pad or 0
    local l = self:WorldToLocal(p)
    local w, h = self:GetWidth() / 2 + pad, self:GetHeight()
    return l.x >= -pad and l.x <= self.GKDepth + pad and math.abs(l.y) <= w and l.z >= -pad and l.z <= h + pad
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate.mdl")
        self:SetNoDraw(true)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetWidth(self.GKWidth)
        self:SetHeight(self.GKHeight)
        self:DrawShadow(false)
    end

    function ENT:SetBox(width, height)
        self:SetWidth(width)
        self:SetHeight(height)
    end

    -- Always send it: clients predict ladder movement too.
    function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end
end

if CLIENT then
    -- Outline it when developer mode is on, to check placement.
    function ENT:Draw() end
    hook.Add("PostDrawTranslucentRenderables", "GK_LadderDebug", function(depth, sky)
        if depth or sky or GetConVarNumber("developer") < 1 then return end
        for _, l in ipairs(ents.FindByClass("gk_ladder")) do
            local w, h = l:GetWidth() / 2, l:GetHeight()
            render.DrawWireframeBox(l:GetPos(), l:GetAngles(), Vector(0, -w, 0), Vector(l.GKDepth, w, h), Color(255, 120, 40), true)
        end
    end)
end
