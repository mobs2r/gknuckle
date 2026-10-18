AddCSLuaFile()

-- Bloodbug: White Knuckle's flying charger (a port of DEN_Bloodbug). It
-- drifts about, now and then lands on a wall to rest, and when it spots a
-- climber it hovers a metre off them, winds up for 3 s (that buzz is your
-- warning), then charges. A hit hurts a little and, worse, knocks you off
-- the wall (GK.DropHang). 10 s before it charges again.
-- Dies to a rebar or a brick in one, a hammer in three; any big blast too.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Bloodbug"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.AutomaticFrameAdvance = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "State")    -- 0 wander, 1 rest, 2 hunt, 3 windup, 4 charge, 5 dead
end

local WANDER, REST, HUNT, WINDUP, CHARGE, DEAD = 0, 1, 2, 3, 4, 5

if SERVER then
    local M = 39.4            -- Source units per WK metre
    local SIGHT = 12 * M      -- spots climbers this far off (with line of sight)
    local CHARGE_RANGE = 5 * M
    local LOSE = 5            -- forgets a target unseen this long
    local WINDUP_T, CHARGE_T, COOLDOWN = 3, 1, 10
    local CRUISE, CHARGE_SPEED = 3 * M, 15 * M
    local HOME_RANGE = 15 * M
    local HEALTH = 45         -- hammer 20 -> three hits

    local function snd(self, name, lvl) self:EmitSound("gknuckle/creatures/" .. name .. ".wav", lvl or 75, math.random(95, 105)) end

    function ENT:Initialize()
        self:SetModel(util.IsValidModel("models/gknuckle/items/bloodbug.mdl") and "models/gknuckle/items/bloodbug.mdl" or "models/props_junk/watermelon01.mdl")
        -- No physics object: it flies with MOVETYPE_FLY and a bounding box.
        -- (Physics-simulated fliers were the shared factor in the vphysics
        -- access-violation crashes in runs.)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-8, -8, -8), Vector(8, 8, 8))
        self:SetMoveType(MOVETYPE_FLY)
        self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
        self:SetHealth(HEALTH)
        self.GK_Home = self:GetPos()
        self.GK_Goal = self:GetPos()
        self.GK_Hover = 0
        self.GK_RestIn = CurTime() + math.Rand(5, 15)
        self.GK_Cool = 0
        self.GK_Noise = math.Rand(0, 100)
        self:SetState(WANDER)
        self:NextThink(CurTime())
    end

    function ENT:OnRemove() if self.GK_Fly then self.GK_Fly:Stop() end end

    local function trace(a, b, self)
        return util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID, filter = self })
    end

    -- A wander spot: a random direction 1-10 m off, pulled home when it strays,
    -- and stopping short of walls.
    function ENT:WanderSpot()
        local pos = self:GetPos()
        local v = VectorRand():GetNormalized() * math.Rand(1, 10) * M
        if (pos + v):Distance(self.GK_Home) > HOME_RANGE then v = LerpVector(0.3, v, self.GK_Home - pos) end
        local tr = trace(pos, pos + v, self)
        if tr.Hit then
            local p = tr.HitPos + tr.HitNormal * 2 * M
            if trace(pos, p, self).Hit then p = pos + v:GetNormalized() * (tr.Fraction * v:Length() * 0.2) end
            return p
        end
        return pos + v
    end

    function ENT:CanSee(ply)
        local tr = util.TraceLine({ start = self:GetPos(), endpos = ply:EyePos() - Vector(0, 0, 10), mask = MASK_SHOT, filter = { self, ply } })
        return not tr.Hit
    end

    function ENT:FindTarget()
        if self.GK_Ambient and CurTime() > (self.GK_AggroUntil or 0) then return nil end
        local best, bd = nil, SIGHT
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() then
                local d = p:GetPos():Distance(self:GetPos())
                if d < bd and self:CanSee(p) then best, bd = p, d end
            end
        end
        return best
    end

    function ENT:Think()
        local ct = CurTime()
        if self:GetState() == DEAD then return end
        local pos = self:GetPos()
        local state = self:GetState()
        local tgt = self.GK_Target

        -- Targets: find one, keep it while seen, forget it 5 s after losing it.
        if IsValid(tgt) and tgt:Alive() then
            if self:CanSee(tgt) then self.GK_LastSeen = ct self.GK_LastPos = tgt:GetPos()
            elseif ct - (self.GK_LastSeen or 0) > LOSE then self.GK_Target, tgt = nil, nil end
        else
            self.GK_Target, tgt = nil, nil
        end
        if not tgt and ct > (self.GK_NextScan or 0) then
            self.GK_NextScan = ct + 0.3
            tgt = self:FindTarget()
            if tgt then
                self.GK_Target, self.GK_LastSeen = tgt, ct
                if state == WANDER or state == REST then state = HUNT snd(self, "bloodbug_warning", 70) end
            end
        end
        if not tgt and (state == HUNT or state == WINDUP or state == CHARGE) then state = WANDER end

        -- Where it wants to be.
        local hover = tgt and (tgt:GetPos() + Vector(0, 0, 36) + (pos - tgt:GetPos() - Vector(0, 0, 36)):GetNormalized() * M)
        if state == WANDER then
            if pos:Distance(self.GK_Goal) < M then
                if self.GK_Hover <= 0 then self.GK_Goal = self:WanderSpot() self.GK_Hover = math.Rand(1, 2)
                else self.GK_Hover = self.GK_Hover - 0.05 end
            end
            if ct > self.GK_RestIn then
                -- Off to rest on a wall within 10 m.
                local tr = trace(pos, pos + VectorRand():GetNormalized() * 10 * M, self)
                if tr.HitWorld then state = REST self.GK_Goal = tr.HitPos + tr.HitNormal * 6 self.GK_RestN = tr.HitNormal self.GK_RestUntil = nil end
                self.GK_RestIn = ct + math.Rand(10, 30)
            end
        elseif state == REST then
            if not self.GK_RestUntil and pos:Distance(self.GK_Goal) < 10 then
                self.GK_RestUntil = ct + math.Rand(10, 30)
                self:SetMoveType(MOVETYPE_NONE) self:SetLocalVelocity(vector_origin)
                self:SetAngles((-self.GK_RestN):Angle())
                if self.GK_Fly then self.GK_Fly:ChangeVolume(0, 0.5) end
            end
            if self.GK_RestUntil and ct > self.GK_RestUntil then
                state = WANDER self:SetMoveType(MOVETYPE_FLY)
                if self.GK_Fly then self.GK_Fly:ChangeVolume(0.5, 0.5) end
                self.GK_RestIn = ct + math.Rand(2, 10)
                self.GK_Goal = self:WanderSpot()
            end
        elseif state == HUNT then
            self.GK_Goal = hover or self.GK_LastPos or pos
            if tgt and pos:Distance(tgt:GetPos()) < CHARGE_RANGE and ct > self.GK_Cool and ct - (self.GK_LastSeen or 0) < 0.5 then
                state = WINDUP self.GK_ChargeAt = ct + WINDUP_T
                snd(self, "bloodbug_warning2", 80)
            end
        elseif state == WINDUP then
            self.GK_Goal = hover or pos
            if ct > self.GK_ChargeAt then
                state = CHARGE self.GK_ChargeEnd = ct + CHARGE_T self.GK_Hit = false
                snd(self, math.random(2) == 1 and "bloodbug_charge" or "bloodbug_charge2", 85)
            end
        elseif state == CHARGE then
            if ct > self.GK_ChargeEnd or (ct > self.GK_ChargeEnd - CHARGE_T * 0.5 and self:GetVelocity():Length() < 5) then
                state = HUNT self.GK_Cool = ct + COOLDOWN
            end
        end
        if state ~= self:GetState() then
            if self:GetState() == REST and state ~= REST then self:SetMoveType(MOVETYPE_FLY) end
            self:SetState(state)
        end

        -- Flight: steer toward the goal with a little wobble; charging, straight at them.
        if state ~= REST or not self.GK_RestUntil then
            local want
            if state == CHARGE and tgt then
                want = (tgt:WorldSpaceCenter() - pos):GetNormalized() * CHARGE_SPEED
            else
                local err = self.GK_Goal - pos
                want = err * 1.5
                if want:Length() > CRUISE then want = want:GetNormalized() * CRUISE end
                local t = ct + self.GK_Noise
                want = want + Vector(math.sin(t * 1.3), math.cos(t * 1.1), math.sin(t * 0.9)) * 0.25 * M
                -- Hover assist: keep off the floor.
                if trace(pos, pos - Vector(0, 0, 40), self).Hit then want.z = want.z + 60 end
            end
            self:SetLocalVelocity(LerpVector(state == CHARGE and 0.5 or 0.15, self:GetVelocity(), want))
            local look = state == CHARGE and want or (tgt and (tgt:EyePos() - pos)) or self:GetVelocity()
            if look:LengthSqr() > 1 then
                local a = look:Angle()
                -- Bank into turns.
                local turn = math.AngleDifference(a.y, self:GetAngles().y)
                a.r = math.Clamp(-turn, -45, 45)
                self:SetAngles(LerpAngle(0.2, self:GetAngles(), a))
            end
        end

        -- The charge connecting.
        if state == CHARGE and tgt and not self.GK_Hit and tgt:WorldSpaceCenter():Distance(pos) < 40 then
            self.GK_Hit = true
            local d = DamageInfo()
            d:SetDamage(10) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
            d:SetDamagePosition(pos)
            tgt:TakeDamageInfo(d)
            GK.DropHang(tgt, 0.1, 1)
            if GK.Inv.KnockFromHands then GK.Inv.KnockFromHands(tgt, pos) end
            local flat = tgt:GetPos() - pos flat.z = 0
            tgt:SetVelocity((flat:GetNormalized() + Vector(0, 0, 0.5)):GetNormalized() * 220)
            tgt:ViewPunch(Angle(-6, math.Rand(-6, 6), 0))
            self:SetState(HUNT) self.GK_Cool = ct + COOLDOWN
            self:SetLocalVelocity(-self:GetVelocity() * 0.3)
        end

        self:NextThink(ct + 0.05)
        return true
    end

    function ENT:Touch(e)
        if self:GetState() == CHARGE and e:IsWorld() then
            self:SetState(HUNT) self.GK_Cool = CurTime() + COOLDOWN
        end
    end

    function ENT:OnTakeDamage(d)
        if self:GetState() == DEAD then return end
        local inf = d:GetInflictor()
        local cls = IsValid(inf) and inf:GetClass() or ""
        local amount = d:GetDamage()
        -- A rebar or a brick drops it outright.
        if cls == "gk_rebar_thrown" or cls == "gk_brick" or d:IsExplosionDamage() then amount = HEALTH end
        self:SetHealth(self:Health() - amount)
        snd(self, "bloodbug_warning", 70)
        if self:GetMoveType() == MOVETYPE_FLY then self:SetLocalVelocity(self:GetVelocity() + d:GetDamageForce() * 0.02) end
        if self:Health() <= 0 then self:Die() end
    end

    function ENT:Die()
        self:SetState(DEAD)
        snd(self, "bloodbug_die", 80)
        if self.GK_Fly then self.GK_Fly:Stop() end
        -- Drops to the floor and lies there.
        self:SetMoveType(MOVETYPE_FLYGRAVITY)
        self:SetLocalVelocity(self:GetVelocity() * 0.3)
        self:SetColor(Color(120, 90, 90))
        local fx = EffectData() fx:SetOrigin(self:GetPos()) fx:SetColor(BLOOD_COLOR_RED)
        util.Effect("BloodImpact", fx, true, true)
        SafeRemoveEntityDelayed(self, 20)
    end
end

if CLIENT then
    ENT.RenderGroup = RENDERGROUP_BOTH
    local wing = Material("gknuckle/creatures/bug_wing.png", "noclamp smooth")

    -- The buzz: louder hunting, a whine winding up, silent resting on a wall.
    function ENT:Think()
        local st = self:GetState()
        if st == 5 then
            if self.GK_Buzz then self.GK_Buzz:Stop() self.GK_Buzz = nil end
            return
        end
        if not self.GK_Buzz then
            self.GK_Buzz = CreateSound(self, "gknuckle/creatures/bloodbug_fly.wav")
            self.GK_Buzz:PlayEx(0, 100)
        end
        local resting = st == 1 and self:GetVelocity():LengthSqr() < 4
        local vol = resting and 0 or ((st == 3 or st == 4) and 0.9 or (st == 2 and 0.7 or 0.5))
        local pitch = st == 3 and 130 or (st == 4 and 115 or 100)
        self.GK_Buzz:ChangeVolume(vol, 0.3)
        self.GK_Buzz:ChangePitch(pitch, 0.3)
        self:SetNextClientThink(CurTime() + 0.2)
        return true
    end
    function ENT:OnRemove() if self.GK_Buzz then self.GK_Buzz:Stop() end end

    -- Wings: a blur of two pairs beating fast on its back (folded still at rest).
    function ENT:DrawTranslucent()
        local st = self:GetState()
        if st == 5 or self.GKNoWings then return end
        local resting = st == 1 and self:GetVelocity():LengthSqr() < 4
        local pos, ang = self:GetPos(), self:GetAngles()
        local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
        local beat = resting and 0 or math.sin(CurTime() * (st == 4 and 90 or 60) + self:EntIndex())
        render.SetMaterial(wing)
        for _, sgn in ipairs({ -1, 1 }) do
            -- Each side hinges at the back and sweeps between flat and raised.
            local a = resting and 10 or (25 + beat * 40)
            local out = right * sgn
            local n = (up * math.cos(math.rad(a)) - out * math.sin(math.rad(a))):GetNormalized()
            local wingDir = (out * math.cos(math.rad(a)) + up * math.sin(math.rad(a))):GetNormalized()
            local c = pos + up * 4 - fwd * 2 + wingDir * 7
            local alpha = resting and 230 or 150
            render.DrawQuadEasy(c, n, 14, 11, Color(255, 255, 255, alpha), sgn > 0 and 0 or 180)
            render.DrawQuadEasy(c, -n, 14, 11, Color(255, 255, 255, alpha), sgn > 0 and 0 or 180)
        end
    end

    function ENT:Draw()
        -- Wind-up: it shudders and glows red before it charges.
        local st = self:GetState()
        if st == 3 then
            local j = VectorRand() * 0.8
            self:SetRenderOrigin(self:GetNetworkOrigin() + j)
            render.SetColorModulation(1, 0.55, 0.55)
        else
            self:SetRenderOrigin()
        end
        self:DrawModel()
        render.SetColorModulation(1, 1, 1)
    end
end
