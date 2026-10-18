AddCSLuaFile()

-- The vacuum in the middle of the hub plaza. On a timer it gathers everyone
-- standing within `radius`, pulls them up with a whoosh and fires
--   hook.Run("GK_VacuumPull", players, freeArenaIndex)
-- If gameplay returns true it has handled who goes where (squads, caps,
-- vaporizing extras). Otherwise the default: build a run in the free arena
-- and drop everyone in, vaporizing anyone past the 12th.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Vacuum"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

function ENT:SetupDataTables()
    self:NetworkVar("Float", 0, "NextPull")
    self:NetworkVar("Float", 1, "Radius")
    self:NetworkVar("Bool", 0, "Pulling")
    self:NetworkVar("Int", 0, "Count")      -- players on the pad right now
    self:NetworkVar("Int", 1, "FreeArenas")
    self:NetworkVar("Int", 2, "Arena")
    self:NetworkVar("Bool", 1, "Hyper")
end

function ENT:KeyValue(k, val)
    if k == "radius" then self.GKRadius = tonumber(val) end
    if k == "interval" then self.GKInterval = tonumber(val) end
    if k == "arena" then self.GK_Arena = tonumber(val) end         -- hub-4: one vacuum per pad, each tied to its trial chamber
    if k == "hyper" then self.GK_Hyper = tobool(val) end           -- only this pad draws the hypervisor band
end

local cvInterval = CreateConVar("gk_vacuum_interval", "60", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Seconds between vacuum pulls (0 = manual via gk_vacuum_fire)")
local MAX_PER_ARENA = 12

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_combine/combine_mine01.mdl")
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_NONE)
        self:SetRadius(self.GKRadius or 520)
        self:SetArena(self.GK_Arena or 0)
        self:SetHyper(self.GK_Hyper == nil and true or self.GK_Hyper)
        self.Interval = self.GKInterval
        self:SetNextPull(CurTime() + (self.Interval or cvInterval:GetFloat()))
    end

    function ENT:PlayersInZone()
        local out = {}
        local r2 = self:GetRadius() ^ 2
        for _, ply in ipairs(player.GetAll()) do
            if ply:Alive() and ply:GetPos():DistToSqr(self:GetPos()) <= r2 and math.abs(ply:GetPos().z - self:GetPos().z) < 300 then
                out[#out + 1] = ply
            end
        end
        return out
    end

    function ENT:Think()
        local interval = self.Interval or cvInterval:GetFloat()
        if interval <= 0 then self:SetNextPull(0) self:NextThink(CurTime() + 1) return true end
        if CurTime() >= self:GetNextPull() and not self:GetPulling() then
            self:Fire_()
        end
        -- Readout for the lamps on the tube.
        self:SetCount(#self:PlayersInZone())
        local free = 0
        if self.GK_Arena then free = GK.Arena.Get(self.GK_Arena) and 0 or 1
        else for i = 1, GK.Arena.Count() do if not GK.Arena.Get(i) then free = free + 1 end end end
        self:SetFreeArenas(free)
        self:NextThink(CurTime() + 0.25)
        return true
    end

    -- The pull: 1.5 s of being dragged up, then the hook/default.
    function ENT:Fire_()
        local players = self:PlayersInZone()
        local interval = self.Interval or cvInterval:GetFloat()
        self:SetNextPull(CurTime() + math.max(interval, 10))
        if #players == 0 then return end
        self:SetPulling(true)
        self:EmitSound("ambient/machines/wall_move5.wav", 90, 60)
        for _, ply in ipairs(players) do
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) and wep.ReleaseAll then wep:ReleaseAll() end
            ply:SetVelocity(Vector(0, 0, 300))
            ply:ScreenFade(SCREENFADE.IN, Color(200, 230, 255, 180), 1.5, 0.3)
        end
        timer.Simple(1.5, function()
            if not IsValid(self) then return end
            self:SetPulling(false)
            local alive = {}
            for _, ply in ipairs(players) do if IsValid(ply) and ply:Alive() then alive[#alive + 1] = ply end end
            -- A pad tied to a chamber offers that chamber (only when it is free); the old single pad offers any.
            local free = self.GK_Arena and ((not GK.Arena.Get(self.GK_Arena)) and self.GK_Arena or nil) or GK.Arena.Free()
            if hook.Run("GK_VacuumPull", alive, free) == true then return end
            self:DefaultPull(alive, free)
        end)
    end

    function ENT:DefaultPull(players, free)
        if not free then
            for _, ply in ipairs(players) do ply:ChatPrint("[gKnuckle] All arenas are busy.") end
            return
        end
        local info, err = GK.Arena.Start(free)
        if not info then print("[gKnuckle] vacuum: " .. tostring(err)) return end
        for i, ply in ipairs(players) do
            if i > MAX_PER_ARENA then
                ply:EmitSound("ambient/energy/zap9.wav", 80)
                ply:Kill()
                ply:ChatPrint("[gKnuckle] Vaporized: the arena was full.")
            else
                ply:SetPos(GK.FindSafeSpot(ply, info.spawn + Vector(math.Rand(-60, 60), math.Rand(-60, 60), 0)) or info.spawn)
                ply:SetVelocity(-ply:GetVelocity())
                ply:EmitSound("ambient/machines/teleport1.wav", 65, 100)
            end
        end
    end

    concommand.Add("gk_vacuum_fire", function(ply)
        if IsValid(ply) and not ply:IsAdmin() then return end
        for _, v in ipairs(ents.FindByClass("gk_vacuum")) do v:Fire_() end
    end)
end

if CLIENT then
    surface.CreateFont("GK_Hyper", { font = "MonocleFixed", size = 44, weight = 500, antialias = false })
    local glow = Material("sprites/light_glow02_add")
    local beam = Material("effects/laser1")
    function ENT:Initialize()
        self:SetRenderBounds(Vector(-600, -600, -16), Vector(600, 600, 4000))
    end
    function ENT:Draw()
        local pos, t = self:GetPos(), CurTime()
        local r = self:GetRadius()
        local left = self:GetNextPull() - t
        local pulling = self:GetPulling()
        -- Ring of light on the pad edge, brighter as the pull nears.
        local urgency = pulling and 1 or math.Clamp(1 - left / 10, 0.15, 1)
        render.SetMaterial(glow)
        for i = 0, 15 do
            local a = i / 16 * math.pi * 2 + t * 0.4
            render.DrawSprite(pos + Vector(math.cos(a) * r, math.sin(a) * r, 24), 90, 90, Color(120, 200, 255, 120 * urgency))
        end
        -- Column up into the dark when pulling.
        if pulling then
            render.SetMaterial(beam)
            render.DrawBeam(pos, pos + Vector(0, 0, 3000), r * 1.6, 0, 1, Color(120, 200, 255, 60))
        end
        -- No HUD text: the queue is read off the tube. Twelve lamps around its
        -- lip light up one per player on the pad (the 13th would be vaporized);
        -- three lamps above show free arenas; the last 10 s the tube's rings
        -- light up from the bottom like a countdown.
        local lipZ, tubeR = 280, 190                       -- hub-4: the pad's own tube mouth
        local count, free = self:GetCount(), self:GetFreeArenas()
        -- The hypervisor: queue text running around the dark band at hip height.
        if not self:GetHyper() then return end             -- hypervisor band: one pad draws it
        local hub = GK.HubLayout and GK.HubLayout() or nil
        local hr = hub and hub.vacuum and hub.vacuum.hyper and hub.vacuum.hyper.r or 560
        local hz = hub and hub.vacuum and hub.vacuum.hyper and (hub.vacuum.hyper.z0 + hub.vacuum.hyper.z1) / 2 - pos.z or 212   -- band centre, relative to this pad
        local text
        if pulling then text = "iNiTiATiNG..."
        elseif GK.VacuumQueueText then text = GK.VacuumQueueText(self)   -- gameplay's queue rules
        elseif count == 0 then text = "WAiTiNG..."
        else
            local ms = math.max(left, 0)
            text = ("%d/12 SUBJECTS_iNiTiATED | STARTiNG iN... %d:%02d:%03d"):format(math.min(count, 12), math.floor(ms / 60), math.floor(ms % 60), math.floor((ms % 1) * 1000))
        end
        local run = "   " .. text .. "   //   "
        surface.SetFont("GK_Hyper")
        local tw = surface.GetTextSize(run)
        local HS = 0.7                      -- 2D px -> world units: 48 px text is ~34 u tall
        local scroll = (t * 60) % tw
        -- 24 flat panels approximate the band; each draws only the glyphs that
        -- fall in its own arc (drawing the whole string per panel cost ~100 fps).
        local N = 48
        local seg = hr * 2 * math.pi / N / HS
        local glyphs = self.GKGlyphs
        if not glyphs or glyphs.text ~= run then
            glyphs = { text = run, list = {} }
            local x = 0
            for _, ch in ipairs(string.Explode("", run)) do
                local cw = surface.GetTextSize(ch)
                glyphs.list[#glyphs.list + 1] = { ch, x, cw }
                x = x + cw
            end
            glyphs.width = x
            self.GKGlyphs = glyphs
        end
        tw = glyphs.width
        local col = Color(255, 170, 60, 230)
        -- Place every glyph repeat once around the band (band length C), then
        -- each panel draws only its own list. Inner face only when standing on the pad.
        local C = N * seg
        local panels = {}
        for _, g in ipairs(glyphs.list) do
            local ch, cx, cw = g[1], g[2], g[3]
            local u = (cx - scroll) % tw
            while u < C do
                local i = math.floor(u / seg)
                local list = panels[i]
                if not list then list = {} panels[i] = list end
                list[#list + 1] = { ch, u - i * seg, cw }
                u = u + tw
            end
        end
        local eye = EyePos()
        local dxy = (eye - pos):Length2D()
        -- Each glyph sits on its own tangent plane (no flat panels, so nothing jumps at
        -- a facet seam while the band scrolls), on the glass band's outer surface for
        -- the hall and on its inner surface for the pad. A glyph only draws when its
        -- face points at the eye, so the far side's inner face shows through the
        -- glass the right way round, never mirrored.
        -- Only the face you are on the same side of: the outer face from the hall, the
        -- inner face from inside the hypervisor. Nothing shows through the glass doubled.
        local inside = dxy < hr
        if dxy < 3000 then
            local GLASS_OUT, GLASS_IN = hr + 14 + 0.5, hr + 6 - 0.5
            for i = 0, N - 1 do
                local pl = panels[i]
                if pl then
                    for _, g in ipairs(pl) do
                        local u = i * seg + g[2] + g[3] / 2            -- band coordinate of the glyph centre
                        for face = inside and 2 or 1, inside and 2 or 1 do
                            -- face 1: outer surface, band anticlockwise; face 2: inner, clockwise.
                            local sgn = face == 1 and 1 or -1
                            local am = sgn * u / C * math.pi * 2
                            local radial = Vector(math.cos(am), math.sin(am), 0)
                            local nrm = radial * sgn
                            local p = pos + Vector(radial.x, radial.y, 0) * (face == 1 and GLASS_OUT or GLASS_IN) + Vector(0, 0, hz)
                            local facing = nrm:Dot((eye - p):GetNormalized())
                            if facing > 0.05 then
                                -- Fade with the viewing angle, so the far side read through
                                -- the glass is dimmer than the face you are looking at.
                                col.a = math.floor(90 + 140 * math.min(1, facing * 1.4))
                                local ang = nrm:Angle()
                                ang:RotateAroundAxis(ang:Up(), 90)
                                ang:RotateAroundAxis(ang:Forward(), 90)
                                cam.Start3D2D(p, ang, HS)
                                    draw.SimpleText(g[1], "GK_Hyper", 0, 0, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                                cam.End3D2D()
                            end
                        end
                    end
                end
            end
        end
        -- The lip lamps, free-arena lamps and countdown rings (glow sprites beside the tube,
        -- rising above the ceiling) are gone (mobs2r, 2026-10-11): the band text carries
        -- the count and the countdown, and nothing floats around the tubes.
    end
end
