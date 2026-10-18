AddCSLuaFile()

-- Course finish. Place as a point entity in Hammer (or spawn it) at the top of a course.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Course Finish"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_combine/combine_mine01.mdl")
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-48, -48, 0), Vector(48, 48, 96))
        self:SetTrigger(true)
        self:DrawShadow(false)
        -- Spawned by hand in a sandbox map: kick off a race (no map wipe).
        if not self:CreatedByMap() and not GK.Round.active then
            timer.Simple(0, function() if IsValid(self) then GK.Round.Start() end end)
        end
    end

    function ENT:OnRemove()
        timer.Simple(0, function()
            if GK.Round.active and #ents.FindByClass("gk_finish") == 0 then GK.Round.End("finish removed") end
        end)
    end

    function ENT:StartTouch(ent)
        if IsValid(ent) and ent:IsPlayer() and ent:Alive() then GK.Round.Finish(ent) end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
        local pos = self:GetPos() + Vector(0, 0, 60 + math.sin(CurTime() * 2) * 6)
        render.SetColorMaterial()
        render.DrawSphere(pos, 10, 16, 16, Color(255, 140, 30, 120))
    end
end
