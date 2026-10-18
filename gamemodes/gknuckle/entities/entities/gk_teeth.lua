AddCSLuaFile()

-- TEETH: White Knuckle's unkillable Habitation hunter (DEN_Teeth). Like in
-- WK it haunts one place, the service shaft at the top of Habitation: when a
-- climber gets into it, it digs up under them and climbs after whoever's
-- nearest in the shaft, faster the longer it hunts. It can't be killed: enough hurt (or one flare) and it
-- burrows away, to come back later. Light drives it off: stand in a lit
-- flashlight's beam or by a burning flare and it shies back. A swipe knocks
-- you off the wall; a downed climber it catches, it eats.
--
-- WK's numbers: climbs 3 m/s, charges 5 m/s, aggression +0.01/s (x3 when it's
-- more than 15 m off), capped at x1.35; stun after 3 hurt (a hammer counts an
-- eighth); a flare sends it away at once. Rooms here stream in and out, so
-- instead of WK's navmesh it burrows through anything in its way and digs
-- back up beside its prey.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "TEETH"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.AutomaticFrameAdvance = true

local MODEL = "models/wk_npcs/teeth.mdl"
local M = 39.37
local SPEED, CHARGE = 3 * M, 5 * M
local REACH = 118 -- WK stopDistance: 3 m
local S = { EMERGE = 1, HUNT = 2, SWIPE = 3, AFRAID = 4, GONE = 5, EAT = 6 }

-- Room collision in runs is entities (gk_level_chunk), not brushes: trace
-- against those and the world, nothing that moves.
local function levelOnly(e) return e:IsWorld() or e:GetClass() == "gk_level_chunk" or e:GetClass() == "gk_level_piece" end

local function snd(name, n) return "gknuckle/creatures/teeth/" .. name .. (n and math.random(n) or "") .. ".wav" end

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "TState")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel(util.IsValidModel(MODEL) and MODEL or "models/Zombie/Poison.mdl")
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-18, -18, 0), Vector(18, 18, 110))
        self:SetCollisionGroup(COLLISION_GROUP_NPC)
        self:SetMoveType(MOVETYPE_FLY)
        self:SetHealth(1000)
        self.Aggression = 1
        self.Stun = 0
        self:Emerge(self:GetPos())
    end

    function ENT:Anim(name, restart)
        local seq = self:LookupSequence(name)
        if seq < 0 then return 0 end
        if restart or self:GetSequence() ~= seq then self:ResetSequence(seq) self:SetCycle(0) end
        return self:SequenceDuration(seq)
    end

    function ENT:SetT(s, untilT)
        self:SetTState(s)
        self.Until = untilT or 0
    end

    -- Up out of the floor at `pos`.
    function ENT:Emerge(pos)
        self:SetPos(pos)
        self:SetNoDraw(false)
        self:SetNotSolid(false)
        self:SetLocalVelocity(vector_origin)
        local len = self:Anim("emerge", true)
        self:EmitSound(snd("emerge1"), 85)
        self:EmitSound(snd("spawn"), 90)
        util.ScreenShake(pos, 4, 10, 1.2, 600)
        self:SetT(S.EMERGE, CurTime() + math.min(len, 2.6))
    end

    -- Down into the floor; back up near its prey after `wait` seconds.
    function ENT:Burrow(wait)
        self:Anim("dig", true)
        self:EmitSound(snd("burrow1"), 80)
        self:SetLocalVelocity(vector_origin)
        self:SetT(S.GONE, CurTime() + (wait or 10))
        self.Hidden = CurTime() + 1.4
        self.Stun, self.LitSince = 0, nil
    end

    function ENT:Arena() return self.GK_Arena and GK.Rounds and GK.Rounds.arenas[self.GK_Arena] end

    -- Its prey: the nearest living climber in its run (not resting at a break).
    function ENT:FindPrey()
        local best, bestD
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and (not self.GK_Arena or GK.ArenaOf(p) == self.GK_Arena) and not (GK.AtBreak and GK.AtBreak(p))
                and (not self.GK_Room or GK.TeethInRoom(self.GK_Room, p)) then -- it never leaves its shaft
                local d = p:GetPos():DistToSqr(self:GetPos())
                if not bestD or d < bestD then best, bestD = p, d end
            end
        end
        return best
    end

    -- A spot to dig up at: on whatever floor is a few metres below `p`.
    local function digSpot(p)
        for _, down in ipairs({ 260, 160, 80 }) do
            local s = p + VectorRand() * 60 * Vector(1, 1, 0) + Vector(0, 0, 8)
            local tr = util.TraceHull({ start = s, endpos = s - Vector(0, 0, down + 200), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 40), mask = MASK_PLAYERSOLID, filter = levelOnly })
            if tr.Hit and not tr.StartSolid and s.z - tr.HitPos.z >= down * 0.5 then return tr.HitPos end
        end
        return p - Vector(0, 0, 120)
    end

    -- Light it can't stand: a lit flashlight pointed at it, or a burning flare.
    function ENT:InLight()
        local c = self:WorldSpaceCenter()
        for _, f in ipairs(ents.FindByClass("gk_flare")) do
            if f:GetPos():DistToSqr(c) < 300 * 300 then return true end
        end
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and p:GetNW2Bool("gk_flashlight", false) then
                local to = c - p:GetShootPos()
                if to:LengthSqr() < 500 * 500 and p:GetAimVector():Dot(to:GetNormalized()) > 0.85 then return true end
            end
        end
        return false
    end

    function ENT:Think()
        local ct = CurTime()
        local st = self:GetTState()
        local prey = self:FindPrey()
        -- Its run ended or moved on: gone.
        if self.GK_Arena and not self:Arena() then self:Remove() return end

        if st == S.GONE then
            if self.Hidden and ct > self.Hidden then
                self.Hidden = nil
                self:SetNoDraw(true) self:SetNotSolid(true)
            end
            if ct > self.Until and IsValid(prey) then self:Emerge(digSpot(prey:GetPos())) end
            self:NextThink(ct + 0.2) return true
        end
        if st == S.EMERGE or st == S.EAT then
            if ct > self.Until then self:SetT(S.HUNT) end
            self:NextThink(ct) return true
        end

        -- Light: it shies back, and too long in it sends it away.
        if self:InLight() then
            self.LitSince = self.LitSince or ct
            if st ~= S.AFRAID then
                self:EmitSound(snd("fearburn1"), 80)
                self:SetT(S.AFRAID)
            end
            self:Anim(self.Climbing and "climbscared" or "scared")
            local away = IsValid(prey) and (self:GetPos() - prey:GetPos()):GetNormalized() or -self:GetForward()
            self:SetLocalVelocity(away * 60)
            if ct - self.LitSince > 3 then self.LitSince = nil self:Burrow(12) end
            self:NextThink(ct) return true
        elseif st == S.AFRAID then
            self:SetT(S.HUNT)
        end
        self.LitSince = nil

        if not IsValid(prey) then
            -- Nobody left in its shaft: it sinks back into the walls to wait.
            if self.GK_Room then self:Burrow(4) self:NextThink(ct) return true end
            self:SetLocalVelocity(vector_origin)
            self:Anim(self.Climbing and "climbidle" or "idle")
            self:NextThink(ct + 0.1) return true
        end

        local to = prey:WorldSpaceCenter() - self:WorldSpaceCenter()
        local dist = to:Length()
        -- WK's aggression: it gets faster the longer it hunts, faster still when far off.
        self.Aggression = math.min(1.35, self.Aggression + 0.01 * FrameTime() * (dist > 15 * M and 3 or 1))
        local yaw = Angle(0, to:Angle().y, 0)
        self:SetAngles(LerpAngle(math.min(1, FrameTime() * 6), self:GetAngles(), yaw))

        if st == S.SWIPE then
            self:SetLocalVelocity(vector_origin)
            if self.HitAt and ct > self.HitAt then
                self.HitAt = nil
                if dist < REACH + 30 then
                    local d = DamageInfo()
                    d:SetDamage(25) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
                    d:SetDamagePosition(prey:WorldSpaceCenter()) d:SetDamageForce(to:GetNormalized() * 8000)
                    prey:TakeDamageInfo(d)
                    if GK.DropHang then GK.DropHang(prey, 0.6, 2) end
                    prey:SetVelocity(to:GetNormalized() * 300 + Vector(0, 0, 120))
                    prey:ViewPunch(Angle(-10, math.Rand(-12, 12), math.Rand(-8, 8)))
                end
            end
            if ct > self.Until then self:SetT(S.HUNT) end
            self:NextThink(ct) return true
        end

        -- A downed climber in reach: caught, and eaten.
        if dist < REACH and GK.IsDowned and GK.IsDowned(prey) then
            self:Anim("grab", true)
            self:EmitSound(snd("caughtya"), 90)
            self:SetT(S.EAT, ct + 2)
            timer.Simple(0.9, function()
                if not IsValid(self) or not IsValid(prey) or not prey:Alive() then return end
                self:EmitSound(snd("eat"), 85)
                prey.GK_Goring = true
                local d = DamageInfo() d:SetDamage(prey:Health() + 1000) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
                prey:TakeDamageInfo(d)
                prey.GK_Goring = false
                if prey:Alive() then prey:Kill() end
            end)
            self:NextThink(ct) return true
        end

        -- In reach: swipe.
        if dist < REACH and ct > (self.NextSwipe or 0) then
            self.NextSwipe = ct + 1.4
            local len = self:Anim(self.Climbing and "climbswipe" or "swipe", true)
            self.HitAt = ct + 0.35
            self:SetT(S.SWIPE, ct + math.min(len, 1.1))
            self:EmitSound(snd("bark", 2), 85)
            self:NextThink(ct) return true
        end

        -- Something solid in the way: through the wall, the WK way, by digging.
        local tr = util.TraceHull({ start = self:WorldSpaceCenter(), endpos = self:WorldSpaceCenter() + to:GetNormalized() * 60,
            mins = Vector(-12, -12, -12), maxs = Vector(12, 12, 12), mask = MASK_PLAYERSOLID, filter = levelOnly })
        if tr.Hit and dist > REACH then
            self.Stuck = (self.Stuck or 0) + FrameTime()
            if self.Stuck > 1.2 then self.Stuck = 0 self:Burrow(2.5) self:NextThink(ct) return true end
        else
            self.Stuck = 0
        end

        -- Climb toward it: mostly up or down is climbing, across is running.
        local dir = to:GetNormalized()
        self.Climbing = math.abs(dir.z) > 0.5
        local speed = (dist < 300 and CHARGE or SPEED) * (self.Climbing and self.Aggression or 1)
        self:SetLocalVelocity(dir * speed)
        self:Anim(self.Climbing and "climb" or "run")
        if ct > (self.NextStep or 0) then
            self.NextStep = ct + (self.Climbing and 0.35 or 0.25)
            self:EmitSound(self.Climbing and snd("climb", 4) or snd("step", 3), 75)
        end
        if ct > (self.NextBark or 0) then
            self.NextBark = ct + math.Rand(6, 12)
            self:EmitSound(snd("search", 2), 85)
        end
        self:NextThink(ct)
        return true
    end

    -- Unkillable: hurt adds up to a stun (WK: 3, a hammer counts an eighth),
    -- and a flare drives it off at once. Either way it burrows and comes back.
    function ENT:OnTakeDamage(d)
        if self:GetTState() == S.GONE or self:GetTState() == S.EMERGE then return 0 end
        self:EmitSound(snd("hurt", 2), 85)
        local inf = d:GetInflictor()
        local amt = d:GetDamage() / 10
        if IsValid(inf) and inf:IsPlayer() and d:IsDamageType(DMG_CLUB) then amt = amt / 8 end
        self.Stun = (self.Stun or 0) + amt
        if (IsValid(inf) and inf:GetClass() == "gk_flare") or d:IsDamageType(DMG_BURN) or self.Stun >= 3 then
            self:Burrow(15)
        end
        return 0
    end
end

if CLIENT then
    function ENT:Draw() self:DrawModel() end
end

-- Spawning, the WK way: TEETH lives in one room only, the service shaft at the
-- top of Habitation (M3_Habitation_Shaft_To_Pier in the campaign, its Endless
-- version at the end of an Endless shaft). When a run's plan has that room and
-- a climber gets into it, TEETH digs up under them and chases them up the
-- shaft. It never leaves the room: with nobody in it, it burrows and waits.
if SERVER then
    local cvTeeth = CreateConVar("gk_teeth", "1", FCVAR_ARCHIVE, "TEETH hunts the Habitation service shaft")
    GK.TeethRooms = { m3_habitation_shaft_to_pier = true, m3_habitation_endless_shaft_end = true }

    -- Is p inside room `r`'s bounds (with a little slack)?
    local function inRoom(r, p)
        local b = r.bounds
        if not b then return false end
        local pos = p:GetPos()
        return pos.x >= b.mins.x - 64 and pos.x <= b.maxs.x + 64 and pos.y >= b.mins.y - 64 and pos.y <= b.maxs.y + 64
            and pos.z >= b.mins.z - 64 and pos.z <= b.maxs.z + 64
    end
    GK.TeethInRoom = inRoom

    hook.Add("GK_ArenaRoomSpawned", "GK_Teeth", function(info, n)
        local step = info.plan and info.plan[n]
        if step and GK.TeethRooms[string.lower(step.piece or "")] then
            info.teethRoom = n
        end
    end)

    timer.Create("GK_TeethSpawn", 0.5, 0, function()
        if not cvTeeth:GetBool() or not GK.Rounds then return end
        for index, a in pairs(GK.Rounds.arenas) do
            local info = a.info
            local n = info and info.teethRoom
            local room = n and info.rooms and info.rooms[n]
            if room and not a.inBreak and not IsValid(a.teeth) and a.teethStage ~= a.stage then
                for _, p in ipairs(a.players) do
                    if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and inRoom(room, p) then
                        local t = ents.Create("gk_teeth")
                        t.GK_Arena, t.GK_Room = index, room
                        local s = p:GetPos() + Vector(0, 0, 8)
                        local tr = util.TraceHull({ start = s, endpos = s - Vector(0, 0, 400), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 40),
                            mask = MASK_PLAYERSOLID, filter = function(e) return e:IsWorld() or e:GetClass() == "gk_level_chunk" or e:GetClass() == "gk_level_piece" end })
                        t:SetPos(tr.Hit and not tr.StartSolid and tr.HitPos or p:GetPos() - Vector(0, 0, 150))
                        t:Spawn()
                        a.teeth, a.teethStage = t, a.stage
                        room.ents[#room.ents + 1] = t -- goes with its room
                        info.ents[#info.ents + 1] = t
                        break
                    end
                end
            end
        end
    end)
    -- A break or a new region: it stays behind.
    hook.Add("GK_ArenaBreak", "GK_Teeth", function(a) if IsValid(a.teeth) then a.teeth:Remove() end end)
    hook.Add("GK_ArenaEnd", "GK_Teeth", function(a) if IsValid(a.teeth) then a.teeth:Remove() end end)
end
