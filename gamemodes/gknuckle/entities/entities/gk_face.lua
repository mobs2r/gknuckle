AddCSLuaFile()

-- The Face: White Knuckle's Abyss worm (DEN_Face). A huge head on a body of
-- 200 fleshy segments, swimming through walls after the climber. It can't be
-- killed, only driven back. Ported from DEN_Face and its AIC_Face_* states,
-- with the numbers from WK's Denizen_Face prefab:
--   steering  seek toward a target point: velocity += (dir * 6.5 m/s * vm - velocity)
--             * seekMult each second, velocity capped at 8, and it moves velocity * vm,
--             where vm = aggression * 0.48 (x2 when it's more than 50 m off)
--   aggression starts 0.73 (+-0.025) and grows 0.0006/s (x3 past 100 m, again x2
--             in hard mode, which also starts it x1.6); in a long run it's at least
--             (run time - 600 s) / 1800 and metres climbed / 4000
--   stalk     hangs 30 m off you, sideways to where you're heading, barking every
--             10-30 s; after 10 s, once you're quick enough (metres per second x
--             aggression over 5) or 45 s (+-10) / 0.8 pass: hunt (3 in 4) or block
--   block     sits 30 m ahead of where you're going, seek x1.3; hunts after 10 s
--             once you're quick, or 45 s
--   hunt      straight at you, seek x1.6 rising by 4 over the 15 s it spends within
--             25 m; roars inside 15 m, chomps inside 3 m; then back to stalk
--   bite      its head within 1 m of you (2.3 m once aggression passes 6) kills you
--   body      every third segment checked each frame: inside 1.5 m x the segment's
--             size, 1 WK damage (10 here) and a shove, at most every 0.15 s
--   hurt      hits of 4+ WK damage (40 here) count (half once aggression passes
--             1.8; rebar half, flares x3); 20 drives it back to stalking. Every hit
--             adds a quarter of itself to the hunt clock.
-- Body: segments every 0.58 m along the path the head swam (WK keeps a position
-- every 0.29 m and puts a segment on every second one), sized by WK's
-- bodyScaleCurve (0.85 at the neck, 2.2 a fifth of the way down, tapering to
-- nothing), each one of WK's four Denizen_Face_Body models.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "The Face"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_OPAQUE

local M = 39.37
local MODEL = "models/wk_npcs/face.mdl"
local BODY = { "models/wk_npcs/face_body_01.mdl", "models/wk_npcs/face_body_02.mdl", "models/wk_npcs/face_body_03.mdl", "models/wk_npcs/face_body_04.mdl" }
local SEGMENTS, SPACING = 200, 0.29 * M -- a history point every 0.29 m, a segment on every 2nd
local MAXSPEED, MAXFORCE, BASEVEL = 6.5, 8, 0.48
local ST = { STALK = 1, HUNT = 2, BLOCK = 3 }
GK.FaceStates = ST

local function snd(name) return "gknuckle/creatures/face/" .. name .. ".wav" end

-- WK's bodyScaleCurve, sampled from its keys (time, value).
local CURVE = { { 0, 0.849 }, { 0.2255, 2.197 }, { 0.986, 0.53 }, { 1, 0.005 } }
function GK.FaceBodyScale(t)
    for i = 1, #CURVE - 1 do
        local a, b = CURVE[i], CURVE[i + 1]
        if t <= b[1] then
            local k = math.Clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
            k = k * k * (3 - 2 * k) -- eased like Unity's curve tangents
            return a[2] + (b[2] - a[2]) * k
        end
    end
    return CURVE[#CURVE][2]
end

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "FState")
    self:NetworkVar("Float", 0, "Aggro")
    self:NetworkVar("Float", 1, "Hurt")
end

-- Points along the swim path, newest first (shared: both realms keep their own).
function ENT:RecordPath()
    local p = self:GetPos()
    self.Path = self.Path or { p }
    if p:DistToSqr(self.Path[1]) > SPACING * SPACING then
        table.insert(self.Path, 1, p)
        if #self.Path > SEGMENTS * 2 + 1 then self.Path[#self.Path] = nil end
    end
end

-- Where segment i (1-based) is, and how big.
function ENT:Segment(i)
    local p = self.Path and self.Path[i * 2]
    if not p then return end
    return p, GK.FaceBodyScale((i - 1) / SEGMENTS)
end

if SERVER then
    local cvSpeed = CreateConVar("gk_face_speed", "1", FCVAR_ARCHIVE, "The Face's speed multiplier (WK's face-setspeed)")

    function ENT:Initialize()
        self:SetModel(util.IsValidModel(MODEL) and MODEL or "models/Gibs/HGIBS.mdl")
        self:SetMoveType(MOVETYPE_NOCLIP)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-40, -40, -40), Vector(40, 40, 40))
        self:SetCollisionGroup(COLLISION_GROUP_DEBRIS) -- shootable, but swims through you and the walls
        self:SetNotSolid(false)
        self:DrawShadow(false)
        self.Vel = Vector(0, 0, 0)            -- WK metres per second
        self.Aggression = 0.73 + (math.random() - 0.5) * 0.05
        self.Born = CurTime()
        self.CurDamage = 0
        self.DamageAt = 0
        self.ChompAt = 0
        self.CheckOffset = 0
        self.Path = { self:GetPos() }
        if self.Hard then self.Aggression = self.Aggression * 1.6 end
        self:PickTarget()
        self.EnterStart = IsValid(self.Target) and self.Target:GetPos() or self:GetPos()
        self:SetState(ST.STALK)
        local seq = self:LookupSequence("far")
        if seq >= 0 then self:ResetSequence(seq) end
    end

    function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end -- heard and seen from far off

    -- WK hunts the one player; here, the nearest climber still in it.
    function ENT:PickTarget()
        local best, bd = nil, math.huge
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP and not p:IsFlagSet(FL_NOTARGET)
                and (not self.Players or self.Players[p]) then
                local d = p:GetPos():DistToSqr(self:GetPos())
                if d < bd then best, bd = p, d end
            end
        end
        if best ~= self.Target then
            self.Target = best
            if IsValid(best) then self.EnterStart = best:GetPos() end
        end
        return best
    end

    function ENT:SetState(s)
        local old = self:GetFState()
        if old == ST.HUNT and s ~= ST.HUNT then self:EmitSound(snd("hunt_end" .. math.random(2)), 110) end
        self:SetFState(s)
        self.StateTime = 0
        self.StateStart = IsValid(self.Target) and self.Target:GetPos() or self:GetPos()
        self.StalkPoint = self.StateStart
        if s == ST.STALK then
            self.StalkTarget = 45 + math.Rand(-10, 10)
            self.BarkAt = CurTime() + 20 * (math.random() + 0.5)
            self:EmitSound(snd("bark1"), 105)
        elseif s == ST.HUNT then
            self.HuntTime = 0
            self.Roared = false
            self:EmitSound(snd("hunt_start" .. math.random(2)), 115)
            util.ScreenShake(self:GetPos(), 6, 8, 1, 3000)
        elseif s == ST.BLOCK then
            self:EmitSound(snd("block"), 110)
        end
    end

    function ENT:Think()
        local now = CurTime()
        local dt = math.Clamp(now - (self.LastThink or now), 0, 0.1)
        self.LastThink = now
        local T = self:PickTarget()
        if not IsValid(T) then self:NextThink(now + 0.5) return true end
        local me = self:GetPos()
        local tp = T:WorldSpaceCenter()
        local headDist = me:Distance(tp) / M
        self.StateTime = self.StateTime + dt
        local seekMult, target = 1, tp
        local s = self:GetFState()
        local toMe = (me - tp):GetNormalized()
        local heading = self.EnterStart - T:GetPos() -- WK's targetEnterStart - target
        if s == ST.STALK then
            seekMult = 1
            local score = T:GetPos():Distance(self.StateStart) / M / math.max(self.StateTime, 0.01) * self.Aggression
            local side = heading:LengthSqr() > 1 and (toMe - heading:GetNormalized() * toMe:Dot(heading:GetNormalized())) or toMe
            if side:LengthSqr() < 0.001 then side = toMe end
            target = tp + side:GetNormalized() * 30 * M
            if now > self.BarkAt then
                self.BarkAt = now + 20 * (math.random() + 0.5)
                self:EmitSound(snd("bark" .. math.random(2)), 105)
            end
            if self.StateTime > 10 and (self.StateTime > self.StalkTarget / 0.8 or score * 0.8 > 5) then
                self:SetState(math.random() > 0.25 and ST.HUNT or ST.BLOCK)
            end
        elseif s == ST.BLOCK then
            seekMult = 1.3
            local score = T:GetPos():Distance(self.EnterStart) / M / math.max(self.StateTime, 0.01)
            local dir = (toMe - heading:GetNormalized()):GetNormalized()
            target = tp + dir * 30 * M
            if self.StateTime > 10 and (self.StateTime > 45 or score > 5) then self:SetState(ST.HUNT) end
        elseif s == ST.HUNT then
            if headDist < 25 then self.HuntTime = self.HuntTime + dt end
            seekMult = 1.6 + self.HuntTime / 15 * 4
            if not self.Roared and headDist < 15 then
                self.Roared = true
                self:EmitSound(snd("meld"), 120)
                util.ScreenShake(me, 8, 10, 1.2, 2000)
            elseif self.Roared and headDist > 35 then
                self.Roared = false
            end
            if headDist < 3 and now > self.ChompAt then
                self.ChompAt = now + 8
                self:EmitSound(snd("chomp"), 100)
            end
            if self.HuntTime > 15 then self:SetState(ST.STALK) end
        end

        -- Aggression (WK DEN_Face.Update; endless runs floor it by time and height).
        local rate = 0.0006 * (headDist > 100 and 3 or 1) * (self.Hard and 2 or 1)
        self.Aggression = self.Aggression + dt * rate
        local run = now - self.Born
        local climbed = math.max(0, (T:GetPos().z - (self.FloorZ or T:GetPos().z)) / M)
        self.Aggression = math.max(self.Aggression, (run - 600) / 1800, climbed / 4000)
        self:SetAggro(self.Aggression)

        local vm = self.Aggression * BASEVEL * cvSpeed:GetFloat()
        if headDist > 50 then vm = vm * 2 end
        -- Steering (DenizenMovement_SteeringVehicle): seek, cap, move.
        local want = (target - me):GetNormalized() * MAXSPEED * vm
        self.Vel = self.Vel + (want - self.Vel) * seekMult * dt
        if self.Vel:Length() > MAXFORCE then self.Vel = self.Vel:GetNormalized() * MAXFORCE end
        self:SetPos(me + self.Vel * dt * vm * M)
        if self.Vel:LengthSqr() > 0.0001 then
            self:SetAngles(LerpAngle(math.min(1, dt * 6), self:GetAngles(), self.Vel:Angle()))
        end
        self:RecordPath()

        -- Head: anim by distance, and the bite.
        local facing = math.deg(math.acos(math.Clamp(self:GetForward():Dot((tp - me):GetNormalized()), -1, 1))) < 30
        local anim = (facing and headDist < 15) and "bite" or headDist < 8 and "veryclose" or headDist < 20 and "close" or "far"
        local seq = self:LookupSequence(anim)
        if seq >= 0 and self:GetSequence() ~= seq then self:ResetSequence(seq) end


        if now > self.DamageAt then
            local biteR = (self.Aggression > 6 and 2.3 or 1) * M
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP and p:WorldSpaceCenter():Distance(self:GetPos()) < biteR + 16 then
                    self:EmitSound(snd("chomp"), 110)
                    -- WK's Kill("face"): no going down, no revive.
                    local d = DamageInfo()
                    d:SetDamage(p:Health() + p:Armor() + 1000) d:SetDamageType(DMG_CRUSH)
                    d:SetAttacker(self) d:SetInflictor(self)
                    if GK.Gore then GK.Gore(p, d) end
                    if p:Alive() then p:Kill() end
                    self.DamageAt = now + 5
                end
            end
            -- The body: every third segment this frame.
            for i = 1, SEGMENTS do
                if (i + self.CheckOffset) % 3 == 0 then
                    local sp, sc = self:Segment(i)
                    if not sp then break end
                    local r = 1.5 * sc * M
                    for _, p in ipairs(player.GetAll()) do
                        if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP then
                            local pc = p:WorldSpaceCenter()
                            if pc:DistToSqr(sp) < r * r then
                                local d = DamageInfo()
                                d:SetDamage(10) d:SetDamageType(DMG_CRUSH)
                                d:SetAttacker(self) d:SetInflictor(self)
                                p:TakeDamageInfo(d)
                                p:SetVelocity((pc - sp):GetNormalized() * 3 * M)
                                if GK.DropHang then pcall(GK.DropHang, p, 0.1, 1) end
                                self.DamageAt = now + 0.15
                            end
                        end
                    end
                    if self.DamageAt > now then break end
                end
            end
            self.CheckOffset = (self.CheckOffset + 1) % (SEGMENTS + 1)
        end

        self:NextThink(now)
        return true
    end

    function ENT:OnTakeDamage(dmg)
        local wk = dmg:GetDamage() / 10
        if self.StateTime and self:GetFState() == ST.HUNT then self.HuntTime = self.HuntTime + wk * 0.25 end
        if wk < 4 then return 0 end
        if self.Aggression > 1.8 then wk = wk * 0.5 end
        local inf = dmg:GetInflictor()
        local cls = IsValid(inf) and inf:GetClass() or ""
        if cls:find("rebar") then wk = wk * 0.5
        elseif cls:find("flare") or dmg:IsDamageType(DMG_BURN) then wk = wk * 3 end
        self.CurDamage = self.CurDamage + wk
        self:SetHurt(self.CurDamage / 20)
        util.ScreenShake(self:GetPos(), 3, 10, 0.3, 1500)
        -- Knocked aside a little, like WK's HitShift.
        local away = IsValid(dmg:GetAttacker()) and (self:GetPos() - dmg:GetAttacker():GetPos()):GetNormalized() or VectorRand()
        self.Vel = (self.Vel + (away - self.Vel:GetNormalized() * away:Dot(self.Vel:GetNormalized())) * self.Vel:Length()):GetNormalized() * self.Vel:Length()
        if self.CurDamage >= 20 then
            self.CurDamage = 0
            self:SetHurt(0)
            self:EmitSound(snd("hurt"), 120)
            util.ScreenShake(self:GetPos(), 8, 10, 1, 2500)
            self:SetState(ST.STALK)
        end
        return 0
    end

    -- Spawn it `below` units under a point (WK's Face comes up from beneath you).
    function GK.SpawnFace(pos, opts)
        opts = opts or {}
        local e = ents.Create("gk_face")
        if not IsValid(e) then return end
        e.Hard = opts.hard
        e.Players = opts.players
        e.FloorZ = pos.z
        e:SetPos(pos - Vector(0, 0, opts.below or 60 * M))
        e:Spawn()
        return e
    end

    concommand.Add("gk_face_summon", function(ply)
        if not GetConVar("sv_cheats"):GetBool() and not GK.RequireAccess(ply, "gknuckle.face") then return end
        local at = IsValid(ply) and ply:GetPos() or Vector(0, 0, 0)
        GK.SpawnFace(at, { below = 40 * M })
    end, nil, "Summon the Face 40 m below you (admin or sv_cheats)")
    concommand.Add("gk_face_setstate", function(ply, _, args)
        if not GetConVar("sv_cheats"):GetBool() and not GK.RequireAccess(ply, "gknuckle.face") then return end
        local s = ST[string.upper(args[1] or "stalk")]
        for _, f in ipairs(ents.FindByClass("gk_face")) do if s then f:SetState(s) end end
    end, nil, "WK's face-setstate: stalk, hunt or block")
end

if CLIENT then
    local bodyEnts = {}
    local function bodyModel(i)
        local e = bodyEnts[i]
        if not IsValid(e) then
            e = ClientsideModel(BODY[i], RENDERGROUP_OPAQUE)
            if not IsValid(e) then return end
            e:SetNoDraw(true)
            bodyEnts[i] = e
        end
        return e
    end

    function ENT:Initialize()
        self.Path = { self:GetPos() }
        self:SetRenderBounds(Vector(-6000, -6000, -6000), Vector(6000, 6000, 6000))
        self.Loops = {}
        for _, n in ipairs({ "breathe", "violins" }) do
            local s = CreateSound(self, snd(n))
            if s then s:SetSoundLevel(n == "violins" and 90 or 85) s:PlayEx(n == "violins" and 0 or 0.8, 100) self.Loops[n] = s end
        end
    end

    function ENT:OnRemove()
        for _, s in pairs(self.Loops or {}) do s:Stop() end
    end

    function ENT:Think()
        self:RecordPath()
        -- The violins swell as it closes in (WK's screen effect distance, 12 m).
        local me = LocalPlayer()
        if IsValid(me) and self.Loops and self.Loops.violins then
            local near = self:NearestBody(me:EyePos())
            local k = math.Clamp(1 - near / (12 * M), 0, 1)
            self.Loops.violins:ChangeVolume(0.15 + 0.85 * k, 0.5)
            GK.FaceNear = math.max(GK.FaceNear or 0, k)
        end
        self:SetNextClientThink(CurTime())
        return true
    end

    function ENT:NearestBody(p)
        local best = p:Distance(self:GetPos())
        for i = 1, SEGMENTS, 4 do
            local sp, sc = self:Segment(i)
            if not sp then break end
            best = math.min(best, p:Distance(sp) - sc * 1.5 * M)
        end
        return math.max(0, best)
    end

    function ENT:Draw()
        self:DrawModel()
        local hurt = self:GetHurt()
        for i = 1, SEGMENTS do
            local sp, sc = self:Segment(i)
            if not sp then break end
            local nxt = self.Path[i * 2 - 1] or self:GetPos()
            local fwd = nxt - sp
            local ang = fwd:LengthSqr() > 0.01 and fwd:Angle() or self:GetAngles()
            -- WK twists each segment by a fixed amount (segmentRotationOffset 33.3).
            ang:RotateAroundAxis(ang:Forward(), (i * 33.31235 * 57.3) % 360)
            ang:RotateAroundAxis(ang:Right(), math.sin(i * 33.31235) * 40)
            local e = bodyModel((i * 7919) % 4 + 1)
            if IsValid(e) then
                local m = Matrix() m:Scale(Vector(sc, sc, sc))
                e:EnableMatrix("RenderMultiply", m)
                e:SetRenderOrigin(sp)
                e:SetRenderAngles(ang)
                e:SetupBones()
                if hurt > 0 then render.SetColorModulation(1, 1 - hurt * 0.4, 1 - hurt * 0.4) end
                e:DrawModel()
                if hurt > 0 then render.SetColorModulation(1, 1, 1) end
            end
        end
    end

    -- WK's corruption overlay: dark, red, warped as the body closes in.
    hook.Add("RenderScreenspaceEffects", "GK_FaceNear", function()
        local k = GK.FaceNear or 0
        GK.FaceNear = 0
        if k <= 0 then return end
        -- screenEffectCurve: 0 at 0, 0.43 at 0.9 (so it never quite blacks out).
        local a = math.min(0.48, k * 0.48)
        DrawColorModify({
            ["$pp_colour_addr"] = 0.06 * a, ["$pp_colour_addg"] = 0, ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = -0.25 * a, ["$pp_colour_contrast"] = 1 + 0.6 * a,
            ["$pp_colour_colour"] = 1 - 1.2 * a,
            ["$pp_colour_mulr"] = 0, ["$pp_colour_mulg"] = 0, ["$pp_colour_mulb"] = 0,
        })
        DrawMotionBlur(0.2, 0.6 * a, 0.01)
        if a > 0.24 then DrawSharpen(1 + a * 3, 1.2) end
    end)
end
