AddCSLuaFile()

-- Rising gas for an arena: a flat hazard plane inside the arena's footprint.
-- Anyone below it (inside the footprint) takes gk_gas_damage per second.
-- Gameplay drives the height with GK.Arena.SetGasHeight; this entity only
-- draws it and deals the damage so nothing gets doubled.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Arena Gas"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Arena")
    self:NetworkVar("Float", 0, "GasHeight")
    self:NetworkVar("Vector", 0, "GasMins")
    self:NetworkVar("Vector", 1, "GasMaxs")
end

if SERVER then
    function ENT:Initialize()
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:DrawShadow(false)
        self:SetNoDraw(false)
        self.NextTick = 0
    end

    function ENT:Think()
        local ct = CurTime()
        if ct < self.NextTick then self:NextThink(ct + 0.1) return true end
        self.NextTick = ct + 0.5
        local dmg = GetConVar("gk_gas_damage"):GetFloat() * 0.5
        local h, mins, maxs = self:GetGasHeight(), self:GetGasMins(), self:GetGasMaxs()
        if dmg > 0 then
            for _, ply in ipairs(player.GetAll()) do
                local p = ply:GetPos()
                if ply:Alive() and p.z < h and p.x > mins.x and p.x < maxs.x and p.y > mins.y and p.y < maxs.y then
                    local d = DamageInfo()
                    d:SetDamage(dmg)
                    d:SetDamageType(DMG_NERVEGAS)
                    d:SetAttacker(self)
                    d:SetInflictor(self)
                    ply:TakeDamageInfo(d)
                    if (ply.GK_NextGasCough or 0) < ct then
                        ply.GK_NextGasCough = ct + 2
                        ply:EmitSound("ambient/gas/steam2.wav", 60, 70, 0.4)
                    end
                end
            end
        end
        self:NextThink(ct + 0.5)
        return true
    end
end

if CLIENT then
    local mat = Material("effects/water_warp01")
    local fog = Material("sprites/light_glow02_add")

    function ENT:Initialize()
        self:SetRenderBounds(Vector(-16384, -16384, -16384), Vector(16384, 16384, 16384))
    end

    function ENT:Draw()
        local h, mins, maxs = self:GetGasHeight(), self:GetGasMins(), self:GetGasMaxs()
        if maxs.x <= mins.x then return end
        local t = CurTime()
        render.SetMaterial(mat)
        local c = Color(170, 230, 90, 190)
        -- Two layers for a bit of depth, drawn from both sides.
        for _, dz in ipairs({ 0, -24 }) do
            local z = h + dz + math.sin(t * 1.3 + dz) * 3
            render.DrawQuad(Vector(mins.x, mins.y, z), Vector(maxs.x, mins.y, z), Vector(maxs.x, maxs.y, z), Vector(mins.x, maxs.y, z), c)
            render.DrawQuad(Vector(mins.x, maxs.y, z), Vector(maxs.x, maxs.y, z), Vector(maxs.x, mins.y, z), Vector(mins.x, mins.y, z), c)
        end
        -- Glow when you're under it.
        local eye = EyePos()
        if eye.z < h and eye.x > mins.x and eye.x < maxs.x and eye.y > mins.y and eye.y < maxs.y then
            render.SetMaterial(fog)
            render.DrawSprite(eye + EyeAngles():Forward() * 40, 200, 200, Color(150, 220, 80, 40))
        end
    end
end
