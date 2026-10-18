AddCSLuaFile()

-- A White Knuckle room's moving part (door, spinner, grinder roller,
-- piston...), built from the room's hazards[] mover entries (sv_hazards.lua)
-- with the build thread's models/gknuckle/wk/movers meshes.
--   spin   turns continuously about its axis (WK UT_Spin). Spun on the
--          client only and not solid: a solid pusher flung loose items at
--          millions of u/s and is a suspect in run crashes.
--   door   placed open and solid (WK doors open on events we don't have yet,
--          and a closed one could wall off a run)
-- Set before Spawn: GK_Model, GK_Kind, GK_Axis (world unit vector), GK_Rate (deg/s).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "WK Mover"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("Vector", 0, "SpinAxis") -- in our own frame
    self:NetworkVar("Float", 0, "SpinRate")  -- degrees per second
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self.GK_Model and util.IsValidModel(self.GK_Model) and self.GK_Model or "models/hunter/blocks/cube025x025x025.mdl")
        self:SetMoveType(MOVETYPE_NONE)
        if self.GK_Kind == "spin" and self.GK_Axis and (self.GK_Rate or 0) ~= 0 then
            self:SetSolid(SOLID_NONE)
            self:SetSpinAxis(self:WorldToLocal(self:GetPos() + self.GK_Axis))
            self:SetSpinRate(self.GK_Rate)
        else
            self:PhysicsInit(SOLID_VPHYSICS)
            local phys = self:GetPhysicsObject()
            -- Some converted mover meshes carry a broken collision model hundreds of
            -- thousands of units across (l_door_habitation_room_01_1: 326,256 u). Every
            -- loose object in the map then overlaps it, vphysics' 16-bit contact list
            -- overflows and the game faults at vphysics.dll+0x8a88c (the 0.4.x crash after
            -- the break room). Such a mover gets a box the size of its visible model.
            if IsValid(phys) then
                local lo, hi = phys:GetAABB()
                local mlo, mhi = self:GetModelBounds()
                local span = lo and math.max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z) or 0
                local mspan = mlo and math.max(mhi.x - mlo.x, mhi.y - mlo.y, mhi.z - mlo.z) or 0
                -- No WK mover is anywhere near 8,192 u; the model's own bounds can be just as
                -- broken, so the size alone decides.
                if span > 8192 then
                    print(("[gKnuckle] mover %s: collision %d u across against a %d u model; using a box"):format(self:GetModel(), span, mspan))
                    self:PhysicsDestroy()
                    if mlo and mspan > 0 and mspan <= 4096 then
                        self:PhysicsInitBox(mlo, mhi)
                    else
                        self:SetSolid(SOLID_NONE)
                    end
                    self:SetMoveType(MOVETYPE_NONE)
                    phys = self:GetPhysicsObject()
                end
            end
            if IsValid(phys) then phys:EnableMotion(false) end
        end
    end
end

if CLIENT then
    function ENT:Draw()
        local rate = self:GetSpinRate()
        if rate ~= 0 then
            local a = self:GetAngles()
            local axis = self:LocalToWorld(self:GetSpinAxis()) - self:GetPos()
            a:RotateAroundAxis(axis:GetNormalized(), (CurTime() * rate) % 360)
            self:SetRenderAngles(a)
        end
        self:DrawModel()
    end
end
