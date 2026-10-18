AddCSLuaFile()

-- The ladder nightmare: White Knuckle's DEN_LadderNightmare, the huge slowly
-- spinning thing that hangs over the endless ladder climb (Region_Ladder_Endless,
-- WK's "Ladder" mode). It keeps a set height above the climber and mostly out
-- of sight; every so often it drifts lower and peeks down for 2-6 s, then
-- pulls back for 5-20 s (sighing as it goes if you saw it). The ladder rooms
-- switch it on step by step, as WK's UT_LadderNightmare_Controller triggers do:
--   500 m    it starts breathing around you (every 5-45 s, within 6 m)
--   1000 m   it comes down to 22 m above you
--   1500 m   19 m, and now it can attack: fall 25 m and it comes for you at
--            20 m/s, spinning three times as fast; within 3 m you're dead
--   the loop room puts it back to 35 m and quiet
-- Numbers are WK's: playerOffset 30, spinSpeed 25 deg/s, moves toward its spot
-- at 2x the gap per second, holds 80% of the way over your column.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Ladder Nightmare"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"

local M = 39.37
local MODEL = "models/wk_npcs/laddernightmare.mdl"
local function snd(name) return "gknuckle/creatures/laddernightmare/" .. name .. ".wav" end

if SERVER then
    function ENT:Initialize()
        self:SetModel(util.IsValidModel(MODEL) and MODEL or "models/props_combine/combine_citadel001.mdl")
        self:SetMoveType(MOVETYPE_NOCLIP)
        self:SetSolid(SOLID_NONE)
        self:DrawShadow(false)
        self.Offset = self.Offset or 30
        self.CanAttack, self.Breathing = false, false
        self.BreathTimer, self.BreathTime = 20, 10
        self.Peeking, self.PeekTime, self.HideTime = false, 0, 0
        self.Start = self:GetPos()
        self.FallRef = {}
    end

    function ENT:UpdateTransmitState() return TRANSMIT_ALWAYS end

    -- WK's UT_LadderNightmare_Controller calls.
    function ENT:Configure(t)
        if t.offset then self.Offset = t.offset end
        if t.attack ~= nil then self.CanAttack = t.attack end
        if t.breathing ~= nil then self.Breathing = t.breathing end
    end

    -- How far a player has fallen since they last stood or held on (WK's
    -- GetCurrentFallDistance), in metres.
    function ENT:FallOf(p)
        local mind = p:GetWeapon("gk_mind")
        local held = false
        if IsValid(mind) and mind.Grips then
            for _, g in pairs(mind.Grips) do if g.kind == "world" then held = true end end
        end
        local z = p:GetPos().z
        if p:OnGround() or held or p:GetMoveType() ~= MOVETYPE_WALK then self.FallRef[p] = z return 0 end
        self.FallRef[p] = math.max(self.FallRef[p] or z, z)
        return (self.FallRef[p] - z) / M
    end

    -- The climber it hangs over: the highest one still in it.
    function ENT:PickTarget()
        local best
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() and p:GetMoveType() ~= MOVETYPE_NOCLIP and (not self.Players or self.Players[p])
                and (not best or p:GetPos().z > best:GetPos().z) then best = p end
        end
        return best
    end

    function ENT:Think()
        local now = CurTime()
        local dt = math.Clamp(now - (self.Last or now), 0, 0.1)
        self.Last = now
        local T = self.Attacking and IsValid(self.Attacking) and self.Attacking:Alive() and self.Attacking or self:PickTarget()
        if not IsValid(T) then self:NextThink(now + 0.5) return true end

        -- Breathing: somewhere close around you.
        if self.Breathing then
            self.BreathTime = self.BreathTime - dt
            if self.BreathTime <= 0 then
                self.BreathTime = math.Rand(0, self.BreathTimer) * 2 + 5
                sound.Play(snd("breath" .. math.random(4)), T:GetPos() + VectorRand():GetNormalized() * 6 * M, 75, 100)
            end
        end

        if self.Attacking then
            local tp = T:WorldSpaceCenter()
            local to = tp - self:GetPos()
            self:SetPos(self:GetPos() + to:GetNormalized() * math.min(to:Length(), 20 * M * dt))
            self:SetAngles(self:GetAngles() + Angle(0, dt * 25 * 3, 0))
            util.ScreenShake(tp, 4, 20, 0.2, 400)
            if self:GetPos():Distance(tp) < 3 * M then
                local d = DamageInfo()
                d:SetDamage(T:Health() + 1000) d:SetDamageType(DMG_CRUSH)
                d:SetAttacker(self) d:SetInflictor(self)
                if GK.Gore then GK.Gore(T, d) end
                if T:Alive() then T:Kill() end
                self.Attacking = nil
            end
            self:NextThink(now)
            return true
        end

        -- Peek and hide.
        local off = self.Offset
        if not self.Peeking then
            if self.HideTime > 0 then
                self.HideTime = self.HideTime - dt
                off = off * 1.25
            else
                self.Peeking, self.PeekTime = true, math.random(2, 5)
            end
        elseif self.PeekTime > 0 then
            self.PeekTime = self.PeekTime - dt
        else
            self.Peeking, self.HideTime = false, math.random(5, 19)
            -- WK: it sighs as it pulls back, if you were looking at it.
            local eye = T:EyePos()
            local tr = util.TraceLine({ start = eye, endpos = self:GetPos(), mask = MASK_SOLID_BRUSHONLY })
            if T:GetAimVector():Dot((self:GetPos() - eye):GetNormalized()) > 0.5 and (tr.Fraction > 0.97 or not tr.Hit) then
                sound.Play(snd("hide" .. math.random(2)), self:GetPos(), 110, 100)
            end
        end
        local want = T:GetPos() + Vector(0, 0, off * M)
        want.x = Lerp(0.2, want.x, self.Start.x)
        want.y = Lerp(0.2, want.y, self.Start.y)
        self:SetPos(LerpVector(math.min(1, dt * 2), self:GetPos(), want))
        self:SetAngles(self:GetAngles() + Angle(0, dt * 25, 0))
        if self.CanAttack and self:FallOf(T) > 25 then
            self.Attacking = T
            self:EmitSound(snd("attack"), 140)
        end
        self:NextThink(now)
        return true
    end
end

if CLIENT then
    function ENT:Initialize()
        self:SetRenderBounds(Vector(-400, -400, -200), Vector(400, 400, 400))
    end
end
