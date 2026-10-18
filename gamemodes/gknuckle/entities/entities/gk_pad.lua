AddCSLuaFile()

-- Hub teleport pad: step on it and you're moved to `target` (world position),
-- used to enter the hub's rooms and practice towers and to come back out.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Teleport Pad"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Label")
end

function ENT:KeyValue(k, val)
    if k == "target" then
        local x, y, z = string.match(val, "([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
        self.GKTarget = Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
    elseif k == "label" then
        self.GKLabel = val
    end
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_combine/combine_mine01.mdl")
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-64, -64, 0), Vector(64, 64, 80))
        self:SetTrigger(true)
        self:SetLabel(self.GKLabel or "ENTER")
    end

    function ENT:StartTouch(ply)
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or not self.GKTarget then return end
        if (ply.GK_NextPad or 0) > CurTime() then return end
        ply.GK_NextPad = CurTime() + 1.5
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep.ReleaseAll then wep:ReleaseAll() end
        ply:SetPos(GK.FindSafeSpot and GK.FindSafeSpot(ply, self.GKTarget) or self.GKTarget)
        ply:SetVelocity(-ply:GetVelocity())
        ply:EmitSound("gknuckle/items/translocator_use.wav", 65)
        ply:ScreenFade(SCREENFADE.IN, Color(120, 200, 255, 120), 0.4, 0)
    end
end

if CLIENT then
    surface.CreateFont("GK_PadLabel", { font = "MonocleFixed", size = 40, weight = 500, antialias = false })
    local ring = Material("effects/select_ring")
    function ENT:Initialize()
        self:SetRenderBounds(Vector(-80, -80, -8), Vector(80, 80, 160))
    end
    function ENT:Draw()
        local pos = self:GetPos()
        local t = CurTime()
        render.SetMaterial(ring)
        render.DrawQuadEasy(pos + Vector(0, 0, 2 + math.sin(t * 2) * 1), Vector(0, 0, 1), 150, 150, Color(120, 200, 255, 200), t * 20)
        -- Painted flat on the floor in the ring, not floating in the air.
        cam.Start3D2D(pos + Vector(0, 0, 1), Angle(0, self:GetAngles().y - 90, 0), 0.25)
            draw.SimpleText(self:GetLabel(), "GK_PadLabel", 0, 0, Color(120, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end
end
