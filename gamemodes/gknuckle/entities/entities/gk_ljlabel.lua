AddCSLuaFile()

-- Painted number on a long-jump lane: the gap in units. Placed on top of the
-- take-off deck (keyvalues: text, width = deck width in units); it's drawn on
-- the front faces of both blocks, facing into the gap, so you read it from
-- either end of the jump.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "LJ Label"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Text")
    self:NetworkVar("Float", 0, "Width")
end

function ENT:KeyValue(k, val)
    if k == "text" then self.GKText = val end
    if k == "width" then self.GKWidth = tonumber(val) end
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetText(self.GKText or "")
        self:SetWidth(self.GKWidth or 200)
    end
end

-- Where the deck under `p` ends going along `dir` (nil if not within `max`).
-- A deck top (level with the label, give or take) under p + dir * d. Starting
-- inside a wall doesn't count: that's the room's side, not a landing.
local function floorAt(p, dir, d)
    local s = p + dir * d + Vector(0, 0, 4)
    local tr = util.TraceLine({ start = s, endpos = s - Vector(0, 0, 12), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and not tr.StartSolid
end
local function edge(p, dir, from, max, wantFloor)
    for d = from, max, 4 do
        if floorAt(p, dir, d) == wantFloor then
            -- Narrow it down to a fraction of a unit, so the number sits right on the face.
            local lo, hi = math.max(from, d - 4), d
            for _ = 1, 5 do
                local mid = (lo + hi) / 2
                if floorAt(p, dir, mid) == wantFloor then hi = mid else lo = mid end
            end
            return hi
        end
    end
end

-- How far down the block's face goes from its top edge at `e` (the face looks along `n`).
local function faceDepth(e, n)
    local s = e + n * 2
    local tr = util.TraceLine({ start = s - Vector(0, 0, 1), endpos = s - Vector(0, 0, 400), mask = MASK_SOLID_BRUSHONLY })
    return math.Clamp(tr.Fraction * 400, 8, 400)
end

-- Find the gap along the lane: the take-off deck's edge, then the far
-- deck's near edge. Faces are cached once found.
function ENT:FindFaces()
    local p = self:GetPos()
    local fwd = self:GetForward()
    local best
    for _, dir in ipairs({ fwd, -fwd }) do
        local d0 = edge(p, dir, 0, 600, false)
        local d1 = d0 and edge(p, dir, d0 + 4, d0 + 600, true)
        -- The label reads along the jump: take its own direction when that finds a gap.
        if d1 then best = { dir = dir, d0 = d0, d1 = d1 - 2, gap = d1 - d0 } break end
    end
    local faces = {}
    if best then
        local a = p + best.dir * best.d0       -- take-off deck's top edge
        local b = p + best.dir * (best.d1 + 2) -- landing deck's top edge
        for _, q in ipairs({ a, b }) do
            local tr = util.TraceLine({ start = q - best.dir * 2 * (q == a and 1 or -1) + Vector(0, 0, 16), endpos = q - Vector(0, 0, 64), mask = MASK_SOLID_BRUSHONLY })
            if tr.Hit then q.z = tr.HitPos.z end
        end
        faces[1] = { pos = a, n = best.dir, depth = faceDepth(a, best.dir) }
        faces[2] = { pos = b, n = -best.dir, depth = faceDepth(b, -best.dir) }
    end
    self.GK_Faces = faces
    self.GK_FacesTry = CurTime()
end

if CLIENT then
    surface.CreateFont("GK_LJNum", { font = "MonocleFixed", size = 96, weight = 500, antialias = false })
    surface.CreateFont("GK_LJSmall", { font = "MonocleFixed", size = 28, weight = 500, antialias = false })

    function ENT:Initialize() self:SetRenderBounds(Vector(-900, -900, -400), Vector(900, 900, 64)) end
    function ENT:Draw()
        if EyePos():DistToSqr(self:GetPos()) > 2600 * 2600 then return end
        if not self.GK_Faces or (#self.GK_Faces == 0 and CurTime() - (self.GK_FacesTry or 0) > 5) then self:FindFaces() end
        local w = self:GetWidth()
        for _, f in ipairs(self.GK_Faces) do
            -- Facing the viewer who looks at it from across the gap: x along their right.
            if (EyePos() - f.pos):Dot(f.n) > 0 then
                local right = (-f.n):Angle():Right()
                local ang = right:AngleEx(f.n)
                -- As big as the face allows, centred a little under the top edge.
                local scale = math.min(w / 320, f.depth / 150)
                local c = f.pos + f.n * 0.6 - Vector(0, 0, math.min(f.depth, 150 * scale) / 2)
                cam.Start3D2D(c, ang, scale)
                    draw.SimpleText(self:GetText(), "GK_LJNum", 0, -12, Color(255, 190, 90, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    draw.SimpleText("UNITS", "GK_LJSmall", 0, 46, Color(255, 190, 90, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end
    end
end
