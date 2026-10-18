AddCSLuaFile()

-- A piton knocked into a wall: frozen, so the mind treats it as a handhold
-- (like WK's Item_Piton_Handhold). It sticks out along its forward.
-- Like WK it has to be hammered home: just set, it takes your weight for half
-- a second before popping out; each hammer hit drives it deeper (3.5 s, 6.5 s)
-- and the third makes it permanent. The auto piton drills itself in fully.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Piton"
ENT.Spawnable = false
ENT.GKHandhold = true

local HOLD_TIMES = { 0.5, 3.5, 6.5 } -- by hits so far; past the end it holds forever
local DEPTH = 1.5                     -- units it sinks per hit

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Hits")
end

-- How long it takes a hand's weight before it pops, or nil if it's in for good.
function ENT:HoldTime()
    return HOLD_TIMES[self:GetHits() + 1]
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/gknuckle/items/piton.mdl")
        -- A box with no physics object: it sits half inside the wall, and frozen
        -- physics objects buried in fresh room collision are the vphysics
        -- run-crash pattern (see gk_turret.lua).
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-6, -6, -6), Vector(6, 6, 6))
        self:SetMoveType(MOVETYPE_NONE)
        self:EmitSound("gknuckle/items/piton_hit.wav", 75)
        -- Seat it: the model's longest axis out of the wall, 3 u buried.
        if self.GK_WallPos then
            local mins, maxs = self:GetModelBounds()
            local ext = maxs - mins
            local n = self.GK_WallNormal
            local ang = n:Angle()
            if ext.z >= ext.x and ext.z >= ext.y then
                ang:RotateAroundAxis(ang:Right(), -90) -- the model's +Z out of the wall
            elseif ext.y > ext.x then
                ang:RotateAroundAxis(ang:Up(), -90)    -- its +Y out of the wall
            end
            self:SetAngles(ang)
            local long = math.max(ext.x, ext.y, ext.z)
            -- Where the model's centre goes so its back end is 3 u in the wall.
            local centre = self.GK_WallPos + n * (long * 0.5 - 3)
            self:SetPos(centre - LocalToWorld((mins + maxs) * 0.5, angle_zero, vector_origin, ang))
        end
        -- WK pitons stay put; a long cap only so a busy hub can't fill up with them.
        SafeRemoveEntityDelayed(self, 900)
    end

    function ENT:Hammer(full)
        if self.GK_Popped or not self:HoldTime() then return false end
        local n = full and #HOLD_TIMES or 1
        n = math.min(n, #HOLD_TIMES - self:GetHits())
        self:SetHits(self:GetHits() + n)
        self:SetPos(self:GetPos() - self:GetForward() * DEPTH * n)
        self:EmitSound("gknuckle/items/piton_hit.wav", 75, 100 + self:GetHits() * 8)
        return true
    end

    -- Worked loose: it falls out of the wall.
    function ENT:PopOut()
        if self.GK_Popped then return end
        self.GK_Popped = true
        self.GKHandhold = nil
        self:EmitSound("physics/metal/metal_solid_impact_soft1.wav", 70, 150)
        -- Drops out of the wall and falls (no physics object, just a toss).
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_FLYGRAVITY)
        self:SetLocalVelocity(self:GetForward() * 60)
        SafeRemoveEntityDelayed(self, 4)
    end
end
