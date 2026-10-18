AddCSLuaFile()

-- The light pouring out of the respawn vacuum in the hub's garden (where gored
-- Husks drop back in). It's blinding: look straight up into it and the whole
-- screen whites out and the Xenium link's electrical jitter kicks in, easing
-- off once you look away.
-- Place it at the light's source, with its forward pointing the way the
-- light shines (straight down for the vacuum: angles "90 0 0").
-- Keyvalues: radius (size of the opening, default 64), cone (degrees off
-- dead centre that still blinds, default 18).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "God Ray"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "Radius")
    self:NetworkVar("Float", 1, "Cone")
end

function ENT:KeyValue(k, v)
    if k == "radius" then self.GK_Radius = tonumber(v) end
    if k == "cone" then self.GK_Cone = tonumber(v) end
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
        self:SetNoDraw(false)
        self:DrawShadow(false)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetRadius(self.GK_Radius or 64)
        self:SetCone(self.GK_Cone or 18)
    end
    function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")
    local beam = Material("sprites/glow04_noz")

    function ENT:Initialize()
        self.PixVis = util.GetPixelVisibleHandle()
        self:SetRenderBounds(Vector(-400, -400, -400), Vector(400, 400, 400))
    end

    function ENT:Draw() end

    -- The opening itself: a hot white core and a soft shaft of light.
    function ENT:DrawTranslucent()
        local pos, dir, r = self:GetPos(), self:GetForward(), self.GetRadius and self:GetRadius() or 64
        self.Visible = util.PixelVisible(pos, r * 0.5, self.PixVis)
        self.VisibleAt = RealTime()
        render.SetMaterial(beam)
        for i = 0, 5 do
            local a = pos + dir * (i * 60)
            render.DrawSprite(a, r * (2.2 + i * 0.5), r * (2.2 + i * 0.5), Color(255, 250, 235, 60 - i * 8))
        end
        render.SetMaterial(glow)
        render.DrawSprite(pos, r * 6, r * 6, Color(255, 252, 240, 255))
    end

    -- How hard the brightest ray is blinding you right now, 0..1.
    local blind = 0
    function GK.GodRayBlind() return blind end

    hook.Add("Think", "GK_GodRayBlind", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local want = 0
        local eye, aim = ply:EyePos(), ply:GetAimVector()
        for _, ray in ipairs(ents.FindByClass("gk_godray")) do
            -- Seen once with its network vars missing on the client: set them up
            -- rather than erroring every frame.
            if not ray.GetCone and ray.SetupDataTables and ray.InstallDataTable then
                ray:InstallDataTable()
                ray:SetupDataTables()
            end
            local to = ray:GetPos() - eye
            local dist = to:Length()
            if dist > 1 and ray.GetCone then
                to:Div(dist)
                -- Looking at the opening, from inside the light (against its direction).
                local centre = aim:Dot(to)
                local inBeam = -to:Dot(ray:GetForward())
                local cone = math.cos(math.rad(ray.GetCone and ray:GetCone() or 18))
                if centre > cone and inBeam > 0.3 and (ray.Visible or 0) > 0.1 and RealTime() - (ray.VisibleAt or 0) < 0.2 then
                    local w = math.Clamp((centre - cone) / (1 - cone), 0, 1)
                    -- Only up close: full glare within 400 u, none past 1400.
                    local near = math.Clamp((1400 - dist) / 1000, 0, 1)
                    want = math.max(want, (0.35 + 0.65 * w) * (ray.Visible or 1) * near)
                end
            end
        end
        -- Whites out fast, clears more slowly.
        local rate = want > blind and 2.5 or 0.8
        blind = math.Approach(blind, want, FrameTime() * rate)
    end)

    -- Electrical jitter: the link's static and a twitching view.
    hook.Add("RenderScreenspaceEffects", "GK_GodRayWhite", function()
        if blind <= 0.01 then return end
        DrawBloom(0.3, 4 * blind, 9, 9, 2, 1, 1, 1, 1)
        DrawColorModify({
            ["$pp_colour_addr"] = 0.5 * blind, ["$pp_colour_addg"] = 0.5 * blind, ["$pp_colour_addb"] = 0.48 * blind,
            ["$pp_colour_brightness"] = 0.2 * blind, ["$pp_colour_contrast"] = 1 + blind,
            ["$pp_colour_colour"] = 1 - 0.8 * blind,
            ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        })
    end)

    hook.Add("HUDPaint", "GK_GodRayStatic", function()
        if blind <= 0.01 then return end
        local w, h = ScrW(), ScrH()
        surface.SetDrawColor(255, 255, 250, math.Clamp(blind * 1.15, 0, 1) * 255)
        surface.DrawRect(0, 0, w, h)
        for _ = 1, math.floor(200 * blind) do
            local v = math.random(0, 120)
            surface.SetDrawColor(v, v, v + 20, math.random(30, 140) * blind)
            surface.DrawRect(math.random(0, w), math.random(0, h), math.random(4, 120), math.random(1, 3))
        end
    end)

    hook.Add("CalcView", "GK_GodRayJitter", function(ply, origin, angles, fov)
        if blind <= 0.05 then return end
        local j = blind * 1.5
        angles.p = angles.p + math.Rand(-j, j)
        angles.y = angles.y + math.Rand(-j, j)
        angles.r = angles.r + math.Rand(-j, j) * 2
    end)
end
