AddCSLuaFile()

-- Roaches: White Knuckle's currency, alive. A port of WK's DEN_Roach: they
-- crawl over any surface (floors, walls, ceilings), wander and flock, and
-- run from anyone who comes close. Grab one with an empty mind-hand (or E) to
-- pocket its worth (sh_roaches.lua keeps the count). Get right on top of one
-- (walk over it, land on it) and it's crushed; any damage kills it too.
--   gold      worth 1   (WK Denizen_Roach_Gold)
--   platinum  worth 5   (WK Denizen_Roach_Platinum)
--   boom      red boom bug (WK Denizen_Roach_Explosive): grab it and it hisses,
--             then blows up in your hands; crush or shoot it and it blows
--             right there (runners use the blast as a boost). Worth nothing.
--   xenium    gKnuckle's own: glowing orange, slow, worth the most, but it's
--             a lump you carry in your bag, and it's extremely heavy.
-- Set GK_Kind before Spawn (default gold).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Roach"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Kind")
end

local function kind(self) return GK.RoachKinds[self:GetKind()] or GK.RoachKinds.gold end

if SERVER then
    -- WK's numbers (metres) in Source units (~39.4 u/m).
    local SIGHT = 59         -- notices players / other roaches (1.5 m)
    local CRUSH = 18         -- a feared body this close crushes it (0.45 m)
    local GRACE = 2          -- ...but not in the first 2 s after it's set down (dropTime)
    local SLEEP = 1180       -- no player within this: the AI sleeps (30 m)
    local STRAY = 394        -- airborne this far from where it started: gone (10 m)
    local GRAVITY = 354      -- 9 m/s²
    local TURN = 5           -- velocity lerps toward its target at this rate
    local OFFSET = 0.5       -- rides this far off the surface
    local DT = 0.05

    local HISS = { "gknuckle/roach/cockroach_hiss1.wav", "gknuckle/roach/cockroach_hiss2.wav", "gknuckle/roach/cockroach_hiss3.wav" }
    local OOF = { "gknuckle/roach/cockroach_oof1.wav", "gknuckle/roach/cockroach_oof2.wav" }

    -- What a roach can stand on: the world and anything that doesn't move.
    local function surface(ent)
        if ent:IsWorld() then return true end
        if ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "gk_roach" then return false end
        local phys = ent:GetPhysicsObject()
        return not IsValid(phys) or not phys:IsMotionEnabled()
    end
    -- A trace that starts inside something (a thin plate, wrapping an edge)
    -- doesn't count as finding a surface.
    local function trace(a, b)
        local tr = util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID, filter = surface })
        if tr.StartSolid or tr.HitNormal:LengthSqr() < 0.25 then tr.Hit = false end
        return tr
    end

    -- NaN guards. A zero-length vector normalized somewhere (an explosion
    -- centred on a roach, a degenerate surface normal) used to poison the
    -- roach's state and spam "Ignoring unreasonable angles/position".
    local function finite(v)
        return v and v.x == v.x and v.y == v.y and v.z == v.z
            and math.abs(v.x) < 1e7 and math.abs(v.y) < 1e7 and math.abs(v.z) < 1e7
    end
    local function finiteAng(a)
        return a and a.p == a.p and a.y == a.y and a.r == a.r
    end
    function ENT:SafePos(p) if finite(p) then self:SetPos(p) self.GK_LastGood = p end end
    function ENT:SafeAng(a) if finiteAng(a) then self:SetAngles(a) end end
    -- Any poisoned state: forget it and drop from the last good spot.
    function ENT:Sanitize()
        if finite(self.GK_Vel) and finite(self.GK_Target) and finite(self.GK_Fall)
            and (self.GK_N == nil or (finite(self.GK_N) and self.GK_N:LengthSqr() > 0.25)) and finite(self:GetPos()) then
            return
        end
        self.GK_Vel, self.GK_Target, self.GK_Fall = Vector(), Vector(), Vector()
        self.GK_N = nil
        local back = self.GK_LastGood or self.GK_Start
        if not finite(self:GetPos()) and finite(back) then self:SetPos(back) end
        self.GK_Start = finite(back) and back or self.GK_Start
    end

    -- Carry a velocity across from one surface to the next. Climbing a wall
    -- (into = into the wall, sign 1): what pointed into it now points up the
    -- old normal. Over an edge (into = the new face's normal, sign -1): what
    -- pointed out past the edge now points down, against the old normal.
    local function carry(v, nOld, into, sign)
        local d = v:Dot(into)
        return v - into * d + nOld * d * sign
    end

    function ENT:Initialize()
        self:SetKind(self.GK_Kind or "gold")
        local k = kind(self)
        self:SetModel(util.IsValidModel(k.model) and k.model or "models/props_junk/garbage_metalcan001a.mdl")
        self:SetModelScale(k.scale or 1)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-4, -4, -2), Vector(4, 4, 4))
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetUseType(SIMPLE_USE)
        self.GK_Vel, self.GK_Target, self.GK_Fall = Vector(), Vector(), Vector()
        self.GK_Wander = 0
        self.GK_Hiss = CurTime() + math.Rand(0, 5)
        self:Settle()
        self:NextThink(CurTime())
    end

    -- Find the surface under it (on spawn, or after being dropped/thrown).
    function ENT:Settle()
        self.GK_Grace = CurTime() + GRACE
        self.GK_Start = self:GetPos()
        local pos = self:GetPos()
        local tr = trace(pos + Vector(0, 0, 8), pos - Vector(0, 0, 24))
        if not tr.Hit then
            -- Nothing under it, but a ceiling just above: it clings on up there.
            local up = trace(pos - Vector(0, 0, 4), pos + Vector(0, 0, 24))
            if up.Hit then tr = up end
        end
        if tr.Hit then
            self.GK_N = tr.HitNormal
            self:SafePos(tr.HitPos + tr.HitNormal * OFFSET)
        else
            self.GK_N = nil -- falling
        end
    end

    -- Knocked about (explosions, the vacuum): it comes off whatever it's on.
    function ENT:AddForce(v)
        if not finite(v) then return end
        self.GK_Fall = self.GK_Fall + v
        self.GK_N = nil
        self.GK_Start = self:GetPos()
    end

    -- A surface frame: two tangents to wander along.
    local function frame(n)
        local right = n:Cross(math.abs(n.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0)):GetNormalized()
        return right, n:Cross(right)
    end

    -- Every 0-3 s: 30% of the time stop, otherwise pick a direction along the
    -- surface, drawn toward any roaches nearby.
    function ENT:Wander(flock)
        if math.random() > 0.7 then
            self.GK_Target = Vector()
        else
            local a, b = frame(self.GK_N)
            local f = flock - self.GK_N * flock:Dot(self.GK_N)
            self.GK_Target = (a * math.Rand(-1, 1) + b * math.Rand(-1, 1) + f) * kind(self).speed
        end
        self.GK_Wander = CurTime() + math.Rand(0, 3)
    end

    function ENT:Think()
        if self.GK_Dead or self.GK_Taken then return end
        self:Sanitize()
        local ct = CurTime()
        local pos = self:GetPos()

        -- Asleep unless someone's within 30 m.
        local near = false
        for _, ply in ipairs(player.GetAll()) do
            if ply:Alive() and ply:GetPos():DistToSqr(pos) < SLEEP * SLEEP then near = true break end
        end
        if not near then self:NextThink(ct + 0.5) return true end

        local k = kind(self)
        if ct > self.GK_Hiss then
            self.GK_Hiss = ct + math.Rand(0, 20)
            self:EmitSound(HISS[math.random(#HISS)], 55, math.random(95, 110), 0.5)
        end

        -- Who's about: players it fears (and can be crushed by), roaches to flock with.
        local flock, fleeing = Vector(), false
        for _, e in ipairs(ents.FindInSphere(pos, SIGHT)) do
            if e:IsPlayer() and e:Alive() and not GK.HasPerk(e, "pheromone") then -- Pheromone Glands: roaches love you
                local mins, maxs = e:WorldSpaceAABB()
                local closest = Vector(math.Clamp(pos.x, mins.x, maxs.x), math.Clamp(pos.y, mins.y, maxs.y), math.Clamp(pos.z, mins.z, maxs.z))
                if closest:DistToSqr(pos) < CRUSH * CRUSH and ct > self.GK_Grace then
                    self:Kill("crush", e)
                    return
                end
                local away = pos - e:WorldSpaceCenter()
                if self.GK_N then away = away - self.GK_N * away:Dot(self.GK_N) end
                if away:LengthSqr() > 0.01 then
                    self.GK_Target = away:GetNormalized() * k.run
                    fleeing = true
                end
            elseif e ~= self and e:GetClass() == "gk_roach" then
                flock = flock + (e:GetPos() - pos) * (0.15 / 39.4)
            end
        end
        if flock:LengthSqr() > 1 then flock:Normalize() end
        if not fleeing and ct > self.GK_Wander and self.GK_N then self:Wander(flock) end

        if self.GK_N then self:Crawl(pos) else self:Fall(pos) end
        if not IsValid(self) then return end
        self:NextThink(ct + DT)
        return true
    end

    -- Off any surface: fall, and cling to whatever it hits.
    function ENT:Fall(pos)
        self.GK_Fall = self.GK_Fall - Vector(0, 0, GRAVITY * DT)
        local step = (self.GK_Vel + self.GK_Fall) * DT
        local tr = trace(pos, pos + step + step:GetNormalized() * 4)
        if tr.Hit then
            self.GK_N = tr.HitNormal
            self.GK_Vel, self.GK_Target, self.GK_Fall = Vector(), Vector(), Vector()
            self:SafePos(tr.HitPos + tr.HitNormal * OFFSET)
            return
        end
        if pos:Distance(self.GK_Start) > STRAY then self:Remove() return end
        self:SafePos(pos + step)
        if step:LengthSqr() > 0.01 then self:SafeAng(step:Angle()) end
    end

    -- Glued to a surface: move along it, climb what it runs into, wrap over
    -- edges, and turn back where there's nothing to wrap onto.
    function ENT:Crawl(pos)
        local n = self.GK_N
        self.GK_Target = self.GK_Target - n * self.GK_Target:Dot(n)
        self.GK_Vel = LerpVector(math.min(1, DT * TURN), self.GK_Vel, self.GK_Target)
        self.GK_Vel = self.GK_Vel - n * self.GK_Vel:Dot(n)
        local v = self.GK_Vel
        local step = v * DT
        local len = step:Length()

        if len > 0.01 then
            local dir = step / len
            local lift = pos + n * 3
            local ahead = trace(lift, lift + dir * (len + 4))
            if ahead.Hit and ahead.HitNormal:Dot(n) < 0.7 then
                -- Something in the way: climb onto it.
                local nn = ahead.HitNormal
                self.GK_Vel = carry(v, n, -nn, 1)
                self.GK_Target = carry(self.GK_Target, n, -nn, 1)
                self.GK_N = nn
                self:SafePos(ahead.HitPos + nn * OFFSET)
            else
                local nextPos = pos + step
                local down = trace(nextPos + n * 3, nextPos - n * 6)
                if down.Hit then
                    self.GK_N = down.HitNormal
                    self:SafePos(down.HitPos + down.HitNormal * OFFSET)
                else
                    -- Over an edge: wrap round onto the face below it...
                    local under = nextPos - n * 3
                    local wrap = trace(under, under - dir * 10)
                    if wrap.Hit then
                        local nn = wrap.HitNormal
                        self.GK_Vel = carry(v, n, nn, -1)
                        self.GK_Target = carry(self.GK_Target, n, nn, -1)
                        self.GK_N = nn
                        self:SafePos(wrap.HitPos + nn * OFFSET)
                    else
                        -- ...or, if there isn't one, turn back (WK: reverse, wander again soon).
                        self.GK_Vel = -v
                        self.GK_Target = -self.GK_Target
                        self.GK_Wander = math.min(self.GK_Wander, CurTime() + 0.5)
                    end
                end
            end
        else
            -- Standing still: check the surface is still there (a prop moved, a door opened).
            local under = trace(pos + n * 3, pos - n * 6)
            if not under.Hit then self.GK_N = nil self.GK_Start = pos return end
        end

        local up = self.GK_N
        local fwd = self.GK_Vel:LengthSqr() > 1 and self.GK_Vel:GetNormalized() or self:GetForward()
        fwd = fwd - up * fwd:Dot(up)
        if fwd:LengthSqr() < 0.01 then fwd = frame(up) end
        self:SafeAng(fwd:GetNormalized():AngleEx(up))
    end

    -- The boom bug's blast: hurts, and throws everything near it.
    function ENT:Explode(pos, attacker)
        GK.Explode(pos, { radius = 160, damage = 35, force = 520, lift = 0.6, attacker = attacker, inflictor = self }) -- sv_explode.lua
    end

    -- Crushed, shot, blown up: dead. (WK: any damage at all kills a roach,
    -- after a short random delay; an explosion delays it a bit more.)
    function ENT:Kill(how, by)
        if self.GK_Dead then return end
        self.GK_Dead = true
        local k = kind(self)
        local delay = ((k.deathTime or 0) + (how == "explosion" and 0.5 or 0)) * math.random()
        timer.Simple(delay, function()
            if not IsValid(self) then return end
            local pos, up = self:GetPos(), self.GK_N or vector_up
            if k.boom then
                self:Explode(pos, by)
            else
                self:EmitSound(OOF[math.random(#OOF)], 65, math.random(95, 110))
                self:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(4) .. ".wav", 60, 150)
                util.Decal("YellowBlood", pos + up * 4, pos - up * 8, self)
                local fx = EffectData() fx:SetOrigin(pos) fx:SetColor(BLOOD_COLOR_YELLOW) fx:SetScale(0.3)
                util.Effect("BloodImpact", fx, true, true)
            end
            hook.Run("GK_RoachKilled", self, how, by)
            self:Remove()
        end)
    end

    function ENT:OnTakeDamage(d)
        if d:GetDamage() <= 0 then return end
        self:Kill(d:IsExplosionDamage() and "explosion" or "damage", d:GetAttacker())
    end

    -- Grabbed (mind-hand click via gk_mind's Press hook, or E).
    function ENT:Press(ply)
        if self.GK_Taken or self.GK_Dead then return true end
        self.GK_Taken = true
        local k = kind(self)
        if k.boom then
            -- The boom bug: it hisses in your grip, then goes off.
            self:EmitSound(HISS[math.random(#HISS)], 75, 80)
            self:EmitSound("npc/roller/mine/rmine_blip3.wav", 75, 140)
            timer.Simple(0.9, function()
                if not IsValid(self) then return end
                self:Explode(IsValid(ply) and ply:GetShootPos() + ply:GetAimVector() * 20 or self:GetPos(), ply)
                self:Remove()
            end)
            return true
        end
        if (self.GK_NoGrabUntil or 0) > CurTime() then self.GK_Taken = false return true end
        if k.smush then
            -- A brown roach is worth nothing and can't be held: it squashes in your grip.
            self.GK_Taken = false
            self:Kill("crush", ply)
            return true
        end
        local side = ply.GK_PressSide
        ply.GK_PressSide = nil
        -- Caught in the hand that grabbed it (E: any free hand). No free hand,
        -- or at the 999 cap: it stays.
        if GK.Roaches.Collect(ply, self:GetKind(), side) == false then self.GK_Taken = false return true end
        self:EmitSound("gknuckle/roach/pickup_cockroach" .. math.random(3) .. ".wav", 65)
        self:Remove()
        return true
    end

    function ENT:Use(ply) if IsValid(ply) and ply:IsPlayer() then self:Press(ply) end end
end

if CLIENT then
    local glow = Material("sprites/light_glow02_add")
    -- WK's roach shell shimmers (its shader's _Shimmer: a bright band passing
    -- over the shell about once a second). Here: the shell drawn again,
    -- additive, as a quick gleam that comes round every second or so.
    local shimmer = CreateMaterial("gk_roach_shimmer", "UnlitGeneric", {
        ["$basetexture"] = "color/white", ["$additive"] = "1", ["$model"] = "1", ["$vertexcolor"] = "1",
    })
    function ENT:Draw()
        if (self.GK_HideUntil or 0) > CurTime() then return end -- just caught (sh_catch.lua)
        local k = kind(self)
        if k.tint then render.SetColorModulation(k.tint.r / 255, k.tint.g / 255, k.tint.b / 255) end
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
        if k.boom or EyePos():DistToSqr(self:GetPos()) > 1500 * 1500 then return end
        local t = (CurTime() * 0.9 + self:EntIndex() * 0.37) % 1
        local g = math.max(0, 1 - math.abs(t - 0.5) / 0.12) -- a 0.25 s gleam each cycle
        if g <= 0 then return end
        local c = k.tint or Color(255, 230, 160)
        render.MaterialOverride(shimmer)
        render.SetColorModulation(c.r / 255, c.g / 255, c.b / 255)
        render.SetBlend(g * 0.55)
        self:DrawModel()
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
        render.MaterialOverride()
    end
    -- WK's glimmer on the gold and platinum shells: a star glint that runs
    -- along the back with the gleam, and a faint twinkle in between.
    local GLINT = { gold = Color(255, 225, 140), platinum = Color(225, 240, 255) }
    function ENT:DrawTranslucent()
        if (self.GK_HideUntil or 0) > CurTime() then return end
        local k = kind(self)
        local gc = GLINT[self:GetKind()]
        if gc and EyePos():DistToSqr(self:GetPos()) < 1200 * 1200 then
            local t = (CurTime() * 0.9 + self:EntIndex() * 0.37) % 1
            local g = math.max(0, 1 - math.abs(t - 0.5) / 0.12)
            render.SetMaterial(glow)
            if g > 0 then
                local along = (t - 0.38) / 0.24 * 2 - 1 -- -1..1 across the gleam
                local p = self:GetPos() + self:GetForward() * along * 3 * (k.scale or 1) + self:GetUp() * 2.2
                render.DrawSprite(p, 9 * g, 9 * g, Color(gc.r, gc.g, gc.b, 255 * g))
                render.DrawSprite(p, 3, 3, Color(255, 255, 255, 255 * g))
            end
            local tw = math.max(0, math.sin(CurTime() * 7.3 + self:EntIndex() * 2.1) - 0.85) / 0.15
            if tw > 0 then render.DrawSprite(self:GetPos() - self:GetForward() * 1.5 + self:GetUp() * 2, 5 * tw, 5 * tw, Color(gc.r, gc.g, gc.b, 200 * tw)) end
        end
        if not k.glow then return end
        local pulse = 0.85 + math.sin(CurTime() * 3 + self:EntIndex()) * 0.15
        render.SetMaterial(glow)
        if k.glowSoft then
            -- A soft bloom around the shell and a dim light on the floor under it.
            local s = 22 * (k.scale or 1) * pulse
            render.DrawSprite(self:GetPos() + self:GetUp() * 2, s, s, Color(k.glow.r, k.glow.g, k.glow.b, 55))
            render.DrawSprite(self:GetPos() + self:GetUp() * 2, s * 0.45, s * 0.45, Color(k.glow.r, k.glow.g, k.glow.b, 70))
            local l = DynamicLight(self:EntIndex())
            if l then
                l.pos = self:GetPos() + self:GetUp() * 6
                l.r, l.g, l.b = k.glow.r, k.glow.g, k.glow.b
                l.brightness = 0.4 * pulse
                l.size = 60 * (k.scale or 1)
                l.dietime = CurTime() + 0.1
            end
            return
        end
        render.DrawSprite(self:GetPos() + self:GetUp() * 3, 26 * pulse, 26 * pulse, k.glow)
        local l = DynamicLight(self:EntIndex())
        if l then
            l.pos = self:GetPos() + self:GetUp() * 8
            l.r, l.g, l.b = k.glow.r, k.glow.g, k.glow.b
            l.brightness = 1.5 * pulse
            l.size = 110
            l.dietime = CurTime() + 0.1
        end
    end
end
