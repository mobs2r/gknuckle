AddCSLuaFile()

-- WK's Habitation apparitions (DEN_Apparition on the Pier rooms): dim, see-through
-- human silhouettes with glowing eyes, standing where WK put them and drifting a
-- metre or so either way, very slowly. They never come for you. Sprites are WK's
-- own DEN_Apparitions_01 sheet (White x the Ghost material's brown tint + the
-- Emissive eyes), baked to materials/gknuckle/creatures/ghost_1..4.
--   size     45x161 px at 50 px per metre: 0.9 x 3.2 m, times the placed scale
--   wander   WK wanderAmount 3 m (perlin offset -0.5..0.5, so +-1.5 m), speed 0.1
--   facing   WK's billboard (verticalMult 0.2): turns to face you, barely tilts
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Apparition"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Sprite")
    self:NetworkVar("Float", 0, "Size")
    self:NetworkVar("Float", 1, "Wander")
    self:NetworkVar("Float", 2, "Speed")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate.mdl")
        self:SetNoDraw(false)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:DrawShadow(false)
        if self:GetSprite() == 0 then self:SetSprite(math.random(1, 4)) end
        if self:GetSize() == 0 then self:SetSize(1) end
    end
    function ENT:UpdateTransmitState() return TRANSMIT_PVS end
end

if CLIENT then
    local mats = {}
    for i = 1, 4 do mats[i] = Material("gknuckle/creatures/ghost_" .. i) end
    local M = 39.37

    -- Smooth noise standing in for Unity's PerlinNoise: a few slow sines.
    local function noise(a, b)
        return (math.sin(a * 1.7 + b * 0.3) + math.sin(a * 0.63 - b * 1.1 + 1.3) + math.sin(a * 2.9 + b * 2.1 + 4.1) * 0.5) / 5
    end

    function ENT:Initialize()
        self:SetRenderBounds(Vector(-120, -120, -80), Vector(120, 120, 160))
    end

    function ENT:Draw() end

    function ENT:DrawTranslucent()
        local mat = mats[self:GetSprite()] or mats[1]
        local base = self:GetPos()
        local t = CurTime() * self:GetSpeed()
        local seed = base.x * 0.013 + base.y * 0.007
        local w = self:GetWander()
        local pos = base + Vector(noise(seed - t, seed * 0.5 - t) * w, noise(seed + t, seed * 1.5 + t) * w, 0)
        local eye = EyePos()
        local to = eye - pos
        local flat = Vector(to.x, to.y, 0):GetNormalized()
        local n = (flat + Vector(0, 0, to:GetNormalized().z * 0.2)):GetNormalized()
        local s = self:GetSize()
        -- The baked texture is 64x256 around a 0.9 x 3.2 m figure, so the quad is
        -- 64/45 x 256/161 of the figure: 1.28 x 5.09 m at scale 1.
        render.SetMaterial(mat)
        render.DrawQuadEasy(pos, n, 1.28 * M * s, 5.09 * M * s, color_white, 180)
    end
end
