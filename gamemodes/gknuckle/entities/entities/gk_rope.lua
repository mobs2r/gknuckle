AddCSLuaFile()

-- The rope from White Knuckle's rope rebar: hangs straight down from where the
-- rebar stuck. Mind-hands grip it anywhere along its length (GK.RopeGrip,
-- used by gk_mind), so you climb it hand over hand like a wall.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Rope"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

ENT.GKMaxLength = 360

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "Bottom")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate.mdl")
        self:SetNoDraw(false)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        local tr = util.TraceLine({ start = self:GetPos(), endpos = self:GetPos() - Vector(0, 0, self.GKMaxLength), mask = MASK_SOLID_BRUSHONLY })
        self:SetBottom(tr.HitPos + Vector(0, 0, 4))
        SafeRemoveEntityDelayed(self, 120)
    end

    -- Where along a rope the player is reaching (within maxDist), or nil.
    function GK.RopeGrip(ply, maxDist)
        local eye, aim = ply:GetShootPos(), ply:GetAimVector()
        local best, bestDist
        -- Ropes, plus anything else rope-like (a barnacle's tongue: ENT:RopeSegment).
        local segs = {}
        for _, rope in ipairs(ents.FindByClass("gk_rope")) do segs[#segs + 1] = { rope:GetPos(), rope:GetBottom() } end
        for _, e in ipairs(ents.FindByClass("gk_barnacle")) do
            local a, b = e:RopeSegment()
            if a then segs[#segs + 1] = { a, b } end
        end
        for _, seg in ipairs(segs) do
            local a, b = seg[1], seg[2]
            -- Closest points between the aim ray and the rope segment.
            local d = b - a
            local w = eye - a
            local A, B, Cc = aim:Dot(aim), aim:Dot(d), d:Dot(d)
            local D, E = aim:Dot(w), d:Dot(w)
            local den = A * Cc - B * B
            if den > 1e-6 then
                local s = math.Clamp((B * E - Cc * D) / den, 0, math.min(maxDist, GK.Config.GripRange))
                local t = math.Clamp((A * E - B * D) / den, 0, 1)
                local onRay, onRope = eye + aim * s, a + d * t
                if onRay:Distance(onRope) < 12 and (not bestDist or s < bestDist) then
                    best, bestDist = onRope, s
                end
            end
        end
        return best
    end
end

if CLIENT then
    local mat = Material("cable/rope")
    function ENT:Draw()
        local a, b = self:GetPos(), self:GetBottom()
        render.SetMaterial(mat)
        render.DrawBeam(a, b, 2.5, 0, a:Distance(b) / 16, Color(200, 170, 120))
    end
    function ENT:Think()
        -- Keep the render bounds covering the whole rope.
        local lo, hi = self:GetPos() * 1, self:GetBottom() * 1
        OrderVectors(lo, hi)
        self:SetRenderBoundsWS(lo - Vector(4, 4, 4), hi + Vector(4, 4, 4))
    end
end
