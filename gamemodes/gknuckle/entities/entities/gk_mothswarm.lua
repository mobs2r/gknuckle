AddCSLuaFile()

-- A swarm of White Knuckle's moths (Denizen_Moth), glowing amber, wheeling
-- round a spot in the Nest the way the walkthrough's flesh towers have them.
-- Harmless scenery: the moths are drawn on each client (no physics, nothing
-- to network but the swarm's spot), drift toward a lit flashlight near them,
-- and flutter off when someone walks right through.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Moth Swarm"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.RenderGroup = RENDERGROUP_BOTH

local MODEL = "models/wk_npcs/moth.mdl"
local COUNT, RADIUS = 12, 140

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_junk/PopCan01a.mdl")
        self:SetNoDraw(false)
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:DrawShadow(false)
    end
    function ENT:UpdateTransmitState() return TRANSMIT_PVS end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")
    function ENT:Initialize()
        self:SetRenderBounds(Vector(-1, -1, -1) * (RADIUS + 80), Vector(1, 1, 1) * (RADIUS + 80))
        self.Moths = {}
        for i = 1, COUNT do
            self.Moths[i] = {
                phase = math.Rand(0, math.pi * 2), speed = math.Rand(0.5, 1.1), r = math.Rand(0.35, 1) * RADIUS,
                h = math.Rand(-0.5, 0.6) * RADIUS, tilt = math.Rand(-0.6, 0.6), scatter = 0, pos = self:GetPos(),
            }
        end
    end

    function ENT:OnRemove()
        for _, m in ipairs(self.Moths or {}) do if IsValid(m.ent) then m.ent:Remove() end end
    end

    function ENT:Think()
        local ct, dt = CurTime(), FrameTime()
        local centre = self:GetPos()
        local near = EyePos():DistToSqr(centre) < 1800 * 1800
        -- A lit flashlight close by draws them; someone right in the swarm scatters it.
        local lure
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and p:GetPos():DistToSqr(centre) < (RADIUS * 1.3) ^ 2 then self.Scatter = ct + 2.5 end
            if p:GetNW2Bool("gk_flashlight", false) and p:EyePos():DistToSqr(centre) < 600 * 600 then lure = p:EyePos() + p:GetAimVector() * 90 end
        end
        local scatter = (self.Scatter or 0) > ct and 1 or 0
        for i, m in ipairs(self.Moths) do
            m.phase = m.phase + dt * m.speed * (1 + scatter * 2.5)
            local r = m.r * (1 + scatter * 1.2)
            local goal = centre + Vector(math.cos(m.phase) * r, math.sin(m.phase * 1.3) * r, m.h + math.sin(m.phase * 2.7 + i) * 30 + m.tilt * math.cos(m.phase) * 40)
            if lure and i % 2 == 0 then goal = LerpVector(0.6, goal, lure + VectorRand() * 30) end
            local last = m.pos
            m.pos = LerpVector(math.min(1, dt * 3), m.pos, goal)
            m.vel = (m.pos - last) / math.max(dt, 0.001)
            if near and not IsValid(m.ent) then
                m.ent = ClientsideModel(MODEL, RENDERGROUP_OPAQUE)
                if IsValid(m.ent) then
                    m.ent:SetNoDraw(true)
                    m.ent:SetModelScale(math.Rand(0.35, 0.55))
                    local seq = m.ent:LookupSequence("fly")
                    if seq >= 0 then m.ent:ResetSequence(seq) m.ent:SetCycle(math.Rand(0, 1)) end
                    m.ent:SetPlaybackRate(math.Rand(0.9, 1.3))
                end
            elseif not near and IsValid(m.ent) then
                m.ent:Remove() m.ent = nil
            end
        end
        if near and ct > (self.NextFlap or 0) then
            self.NextFlap = ct + math.Rand(0.4, 1.2)
            local m = self.Moths[math.random(#self.Moths)]
            sound.Play("wk_npcs/moth/flap.wav", m.pos, 60, math.random(90, 115), 0.5)
        end
        self:SetNextClientThink(ct)
        return true
    end

    function ENT:Draw()
        -- Lit from within, amber, the way the walkthrough's swarms glow in the dark.
        render.SuppressEngineLighting(true)
        render.ResetModelLighting(0.9, 0.55, 0.25)
        render.SetColorModulation(1.3, 0.85, 0.5)
        for _, m in ipairs(self.Moths or {}) do
            local e = m.ent
            if IsValid(e) then
                local v = m.vel or vector_origin
                local ang = v:LengthSqr() > 1 and v:Angle() or Angle(0, m.phase * 57, 0)
                ang.p = math.Clamp(ang.p, -30, 30)
                e:SetPos(m.pos) e:SetAngles(ang)
                e:FrameAdvance(FrameTime())
                e:SetupBones()
                e:DrawModel()
            end
        end
        render.SetColorModulation(1, 1, 1)
        render.SuppressEngineLighting(false)
    end

    -- The amber glow each moth carries.
    function ENT:DrawTranslucent()
        render.SetMaterial(glow)
        for i, m in ipairs(self.Moths or {}) do
            if IsValid(m.ent) then
                local k = 0.7 + 0.3 * math.sin(CurTime() * 5 + i)
                render.DrawSprite(m.pos, 28 * k, 28 * k, Color(255, 150, 50, 180))
            end
        end
    end
end

-- In runs: the Nest's flying-creature spots get moth swarms instead of nothing.
if SERVER then
    local cvMoths = CreateConVar("gk_nest_moths", "0.5", FCVAR_ARCHIVE, "Chance a Nest flying-creature spot gets a moth swarm")
    hook.Add("GK_ArenaRoomSpawned", "GK_MothSwarms", function(info, n)
        local region = info.region or ""
        if not region:find("Nest") then return end
        local room, step = info.rooms and info.rooms[n], info.plan and info.plan[n]
        if not room or not step then return end
        for _, l in ipairs(GK.LevelLayout(step.piece).locators or {}) do
            if l.id == "creature-fly-spawn" and math.random() < cvMoths:GetFloat() then
                local e = ents.Create("gk_mothswarm")
                e:SetPos(step.pos + GK.LevelToModel(l.pos))
                e:Spawn()
                room.ents[#room.ents + 1] = e
                info.ents[#info.ents + 1] = e
            end
        end
    end)
end
