AddCSLuaFile()

-- White Knuckle's radio (Prop_Radio, red light on) playing Portal's Aperture
-- Science radio song, for players who have Portal mounted in Garry's Mod;
-- without Portal it plays HL2's radio music instead, so it's never silent.
-- Press it (E, or click it with an empty mind-hand) to switch it on or off.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Radio"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local MODEL = "models/gknuckle/props/radio.mdl"
local PORTAL_SONG = "ambient/music/looping_radio_mix.wav"
local HL2_SONG = "music/radio1.mp3"

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "On")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(MODEL) -- each client picks its own song (below)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:SetMass(8) phys:Wake() end
        self:Switch(true)
    end

    function ENT:Switch(on)
        self:SetOn(on)
        self:SetSubMaterial(0, on and "models/gknuckle/props/radio/radio_lit" or "") -- its red light
    end

    function ENT:Toggle()
        self:Switch(not self:GetOn())
        self:EmitSound("buttons/lightswitch2.wav", 60, self:GetOn() and 110 or 90)
    end

    function ENT:Use(ply) if IsValid(ply) and ply:IsPlayer() then self:Toggle() end end

    -- The mind-hand's click (gk_mind TryGrip) presses it instead of gripping.
    function ENT:Press(ply) self:Toggle() return true end
end

if CLIENT then
    local function song()
        if file.Exists("sound/" .. PORTAL_SONG, "GAME") then return PORTAL_SONG end
        return HL2_SONG
    end

    -- Each client plays its own loop, so it's the Portal song for anyone who
    -- has Portal mounted. Restarted when it ends (the mp3 doesn't loop by itself).
    function ENT:Think()
        local on = self:GetOn() and not self:IsDormant()
        if on and EyePos():DistToSqr(self:GetPos()) < 1500 * 1500 then
            if not self.GK_Song then
                self.GK_SongPath = song()
                self.GK_Song = CreateSound(self, self.GK_SongPath)
                self.GK_Song:SetSoundLevel(70)
            end
            if not self.GK_Song:IsPlaying() then
                self.GK_Song:PlayEx(0.55, 100)
            end
        elseif self.GK_Song and self.GK_Song:IsPlaying() then
            self.GK_Song:Stop()
        end
        self:SetNextClientThink(CurTime() + 0.5)
        return true
    end

    function ENT:OnRemove()
        if self.GK_Song then self.GK_Song:Stop() end
    end

    -- Where the red light is on the model: the texels WK's emissive map lights
    -- (around 22.5, 8.5 on its 128 px texture), found on the mesh by UV.
    local lightPos
    local function findLight(mdl)
        local best, bestD = nil, math.huge
        for _, mesh in ipairs(util.GetModelMeshes(mdl) or {}) do
            for _, v in ipairs(mesh.triangles or {}) do
                if v.u and v.v then
                    for _, tv in ipairs({ v.v, 1 - v.v }) do
                        local d = (v.u - 22.5 / 128) ^ 2 + (tv - 8.5 / 128) ^ 2
                        if d < bestD then bestD, best = d, v.pos end
                    end
                end
            end
        end
        return best or Vector(0, 0, 0)
    end

    local glow = Material("sprites/light_glow02_add")
    ENT.RenderGroup = RENDERGROUP_BOTH
    function ENT:Draw() self:DrawModel() end
    function ENT:DrawTranslucent()
        if not self:GetOn() then return end
        lightPos = lightPos or findLight(self:GetModel())
        local p = self:LocalToWorld(lightPos)
        local pulse = 0.85 + 0.15 * math.sin(CurTime() * 3)
        render.SetMaterial(glow)
        render.DrawSprite(p, 5 * pulse, 5 * pulse, Color(255, 40, 30, 220))
        render.DrawSprite(p, 1.6, 1.6, Color(255, 120, 100, 255))
    end

end
