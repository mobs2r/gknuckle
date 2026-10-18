AddCSLuaFile()

-- Spike: a White Knuckle rebar standing on end. It only gets you if you come
-- down on its point helpless: stunned (link offline, so no hands to catch
-- yourself) or ragdolled (sh_impale.lua watches ragdolls). How hard you land
-- and how much you carry decide it; see sh_impale.lua for getting off.
-- A non-solid volume: you fall onto it, not stand on it.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Spike"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"
ENT.GKSpike = true

ENT.GKHeight = 49.7
ENT.GKLength = 49.7

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/gknuckle/items/rebar.mdl")
        self:SetAngles(Angle(-90, self:GetAngles().y, 0)) -- the bar runs along +X: stand it up
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-8, -8, 0), Vector(8, 8, self.GKHeight + 6)) -- BBOX: world-aligned
        self:AddSolidFlags(FSOLID_NOT_SOLID)
        self:SetTrigger(true)
    end

    -- Only off the point: it has to be standing up.
    function ENT:PointsUp() return self:GetForward().z > 0.7 end

    -- Puts ply on the bar. yaw = which way they face; back = it went in their back.
    function ENT:ImpaleOn(ply, landing, back, yaw)
        -- Run through the middle (feet 40 below the tip); heavier climbers sink
        -- further down the bar. Forwards it comes out of your chest just ahead of
        -- you (look down and you see it); backwards it's just behind you.
        local sink = math.Clamp(GK.CarriedWeight(ply) * 1.5 + (landing - 200) * 0.02, 0, 20)
        local base = self:GetPos()
        local f2 = Angle(0, yaw, 0):Forward() * (back and 8 or -8)
        local pos = Vector(base.x + f2.x, base.y + f2.y, math.max(base.z, base.z + self.GKHeight - 40 - sink))
        return GK.Impale(ply, self, {
            pos = pos, axis = self:GetForward(), back = back,
            look = Angle(back and 0 or 30, yaw, 0),
        })
    end

    function ENT:StartTouch(ply)
        if not IsValid(ply) or not ply:IsPlayer() or (ply.GK_ImpaleImmune or 0) > CurTime() then return end
        if GK.IsChipOnline(ply) or not self:PointsUp() then return end
        local landing = -ply:GetVelocity():Dot(self:GetForward()) -- speed coming down onto the point
        if landing < GK.ImpaleSpeed(ply) then return end

        -- Front or back: is the bar ahead of you or behind you? Dead centre, go
        -- by which way you're drifting, then by whether you're looking up.
        local face = Angle(0, ply:EyeAngles().y, 0):Forward()
        local off = self:GetPos() - ply:GetPos()
        off.z = 0
        local drift = ply:GetVelocity()
        drift.z = 0
        local back
        if off:Length() > 4 then
            back = off:Dot(face) < 0
        elseif drift:Length() > 30 then
            back = drift:Dot(face) < 0
        else
            back = ply:EyeAngles().p < -15
        end
        self:ImpaleOn(ply, landing, back, ply:EyeAngles().y)
    end
end
