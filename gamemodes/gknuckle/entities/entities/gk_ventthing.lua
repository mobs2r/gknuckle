AddCSLuaFile()

-- The Vent Thing: White Knuckle's Habitation lurker (a port of DEN_VentThing).
-- A body hides in a vent; when a climber comes within 50 m it sends a long
-- hand after them, snaking along its arm. LOOK AT THE HAND and it flinches
-- back (from 8 m off its body, within 15 m of you). If it reaches you it
-- grabs and drags you to the vent: hang on to a hold to resist (it costs your
-- grip, and the hand tires out after 5 s of that and lets go); dragged right
-- into the vent, you die. Any hit makes it let go and pull back; a blast kills it.
-- Placed from rooms' Denizen_VentThing_Body creatures (sv_creatures.lua).
-- No physics objects anywhere (see the vphysics run crash notes in gk_turret).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Vent Thing"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

local IDLE, REACH, RETREAT, GRAB, DEAD = 0, 1, 2, 3, 4

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "State")
    self:NetworkVar("Vector", 0, "Hand")    -- the hand's world position
    self:NetworkVar("Entity", 0, "Victim")
    self:NetworkVar("Float", 0, "HandTire") -- 0 fresh .. 1 exhausted (it reddens)
end

-- Where the arm comes out of the body.
function ENT:Root() return self:GetPos() + Vector(0, 0, 8) end

if SERVER then
    local M = 39.4
    local ACTIVATE = 50 * M
    local SPEED, RETREAT_SPEED = 3.5 * M, 7 * M
    local GRAB_RANGE = 1 * M
    local SCARE_RANGE, SCARE_MIN_BODY = 15 * M, 8 * M
    local KILL_RANGE = 2 * M
    local HAND_STAMINA = 5

    local function snd(self, name, lvl, at)
        if at then sound.Play("gknuckle/creatures/ventthing_" .. name .. ".wav", at, lvl or 75, math.random(95, 105))
        else self:EmitSound("gknuckle/creatures/ventthing_" .. name .. ".wav", lvl or 75, math.random(95, 105)) end
    end

    function ENT:Initialize()
        local mdl = "models/gknuckle/items/ventthing_body.mdl"
        self:SetModel(util.IsValidModel(mdl) and mdl or "models/props_junk/watermelon01.mdl")
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-20, -20, -10), Vector(20, 20, 30))
        self:SetMoveType(MOVETYPE_NONE)
        self:SetState(IDLE)
        self:SetHand(self:Root())
        self.GK_Stamina = HAND_STAMINA
        self.GK_RetreatUntil = 0
        self.GK_Idle = CreateSound(self, "gknuckle/creatures/ventthing_idleloop.wav")
        self.GK_Idle:PlayEx(0.4, 100)
        self:NextThink(CurTime())
    end

    function ENT:OnRemove()
        if self.GK_Idle then self.GK_Idle:Stop() end
        self:Drop(false)
    end

    local function visible(a, b, filter)
        return not util.TraceLine({ start = a, endpos = b, mask = MASK_SOLID_BRUSHONLY, filter = filter }).Hit
    end

    -- Nearest living climber in range that the body or hand can see.
    function ENT:FindTarget()
        local best, bd = nil, ACTIVATE
        local root, hand = self:Root(), self:GetHand()
        for _, p in ipairs(player.GetAll()) do
            if p:Alive() then
                local c = p:WorldSpaceCenter()
                local d = c:Distance(root)
                if d < bd and (visible(root, c, self) or visible(hand, c, self)) then best, bd = p, d end
            end
        end
        return best
    end

    -- Is ply looking at the hand (within 45 degrees, nothing in between)?
    local function looksAt(ply, pos)
        local to = pos - ply:EyePos()
        if to:GetNormalized():Dot(ply:GetAimVector()) < math.cos(math.rad(45)) then return false end
        return visible(ply:EyePos(), pos)
    end

    function ENT:Retreat(t)
        self:Drop(true)
        self.GK_RetreatUntil = math.max(self.GK_RetreatUntil, CurTime() + t)
        if self:GetState() ~= DEAD then self:SetState(RETREAT) end
    end

    function ENT:Drop(hurt)
        local v = self:GetVictim()
        if IsValid(v) then
            v:SetNW2Entity("gk_ventgrab", NULL)
            if hurt and v:Alive() then
                local d = DamageInfo() d:SetDamage(10) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
                v:TakeDamageInfo(d)
            end
            snd(self, "dropplayer", 80, self:GetHand())
        end
        self:SetVictim(NULL)
    end

    -- Moves the hand toward a point; it slides along walls, and a hand that
    -- can't make progress for 2 s gives up and pulls back.
    function ENT:MoveHand(goal, speed, dt)
        local hand = self:GetHand()
        local to = goal - hand
        local dist = to:Length()
        if dist < 1 then return true end
        local step = to:GetNormalized() * math.min(dist, speed * dt)
        -- A little snake-like wobble while it travels.
        local t = CurTime() * 2
        step = step + Vector(math.sin(t * 1.3), math.cos(t * 1.1), math.sin(t * 0.7)) * 6 * dt
        local tr = util.TraceHull({ start = hand, endpos = hand + step, mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), mask = MASK_SOLID_BRUSHONLY, filter = self })
        local np = tr.HitPos
        if tr.Hit and not tr.StartSolid then
            local slide = step - tr.HitNormal * step:Dot(tr.HitNormal)
            local tr2 = util.TraceHull({ start = np, endpos = np + slide, mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), mask = MASK_SOLID_BRUSHONLY, filter = self })
            np = tr2.HitPos
        elseif tr.StartSolid then
            np = hand + step -- inside the vent wall: pass through
        end
        if np:DistToSqr(hand) < (speed * dt * 0.1) ^ 2 then
            self.GK_Stuck = (self.GK_Stuck or 0) + dt
        else
            self.GK_Stuck = 0
        end
        self:SetHand(np)
        return false
    end

    function ENT:Think()
        local ct = CurTime()
        local st = self:GetState()
        if st == DEAD then return end
        local dt = 0.05
        local root, hand = self:Root(), self:GetHand()

        if st == GRAB then
            local v = self:GetVictim()
            if not IsValid(v) or not v:Alive() or v:GetNW2Entity("gk_ventgrab") ~= self then
                self:Retreat(5)
                return self:Next(ct)
            end
            self:SetHand(v:WorldSpaceCenter())
            -- Hanging on resists it: costs your grip and tires the hand.
            local hanging = v:GetNW2Bool("gk_anchor_l", false) or v:GetNW2Bool("gk_anchor_r", false)
            if hanging then
                GK.AddStamina(v, -10 * dt)
                self.GK_Stamina = self.GK_Stamina - dt
                util.ScreenShake(v:GetPos(), 1.5, 8, 0.1, 64)
                if self.GK_Stamina <= 0 then self:Retreat(5) return self:Next(ct) end
            end
            self:SetHandTire(1 - self.GK_Stamina / HAND_STAMINA)
            if v:WorldSpaceCenter():Distance(root) < KILL_RANGE then
                self:Drop(false)
                snd(self, "bite1", 90)
                local d = DamageInfo() d:SetDamage(v:Health() + 1000) d:SetDamageType(DMG_SLASH) d:SetAttacker(self) d:SetInflictor(self)
                v:TakeDamageInfo(d)
                self:Retreat(5)
            end
            return self:Next(ct)
        end

        -- The hand gets its strength back while it's not holding anyone.
        self.GK_Stamina = math.min(HAND_STAMINA, self.GK_Stamina + dt)
        self:SetHandTire(1 - self.GK_Stamina / HAND_STAMINA)

        if ct < self.GK_RetreatUntil or st == RETREAT then
            if self:MoveHand(root, RETREAT_SPEED, dt) or ct >= self.GK_RetreatUntil then
                if ct >= self.GK_RetreatUntil then self:SetState(IDLE) end
            end
            return self:Next(ct)
        end

        local tgt = self:FindTarget()
        if not IsValid(tgt) then
            if st == REACH then snd(self, "targetlost", 70) end
            self:SetState(IDLE)
            self:MoveHand(root, RETREAT_SPEED, dt)
            return self:Next(ct)
        end
        if st == IDLE then
            self:SetState(REACH)
            snd(self, "reach", 80, hand)
        end

        local c = tgt:WorldSpaceCenter()
        -- Seen: it flinches back.
        if c:Distance(hand) < SCARE_RANGE and hand:Distance(root) > SCARE_MIN_BODY and looksAt(tgt, hand) then
            snd(self, "retract" .. math.random(3, 4), 80, hand)
            util.ScreenShake(hand, 2, 10, 0.4, 600)
            self:Retreat(2.5)
            return self:Next(ct)
        end

        self:MoveHand(c, SPEED, dt)
        if (self.GK_Stuck or 0) > 2 then self.GK_Stuck = 0 self:Retreat(1) return self:Next(ct) end

        if self:GetHand():Distance(c) < GRAB_RANGE and not IsValid(tgt:GetNW2Entity("gk_ventgrab")) then
            self:SetState(GRAB)
            self:SetVictim(tgt)
            tgt:SetNW2Entity("gk_ventgrab", self)
            snd(self, "grabplayer", 85)
            snd(self, "anger1", 80)
        end
        return self:Next(ct)
    end

    function ENT:Next(ct) self:NextThink(ct + 0.05) return true end

    function ENT:OnTakeDamage(d)
        if self:GetState() == DEAD then return end
        snd(self, "anger1", 80)
        if d:IsExplosionDamage() then
            self:Drop(false)
            self:SetState(DEAD)
            self:SetColor(Color(90, 70, 70))
            if self.GK_Idle then self.GK_Idle:Stop() end
            return
        end
        self:Retreat(5)
    end
end

-- (The drag itself is in GM:Move, predicted: gk_ventgrab in sh_movement.lua.)

if CLIENT then
    local limbModel, handModel
    local function models()
        if not IsValid(limbModel) then
            limbModel = ClientsideModel("models/gknuckle/items/ventthing_limb.mdl", RENDERGROUP_OPAQUE)
            if IsValid(limbModel) then limbModel:SetNoDraw(true) end
        end
        if not IsValid(handModel) then
            handModel = ClientsideModel("models/gknuckle/items/ventthing_hand.mdl", RENDERGROUP_OPAQUE)
            if IsValid(handModel) then handModel:SetNoDraw(true) end
        end
    end

    function ENT:Initialize()
        self:SetRenderBounds(Vector(-2000, -2000, -2000), Vector(2000, 2000, 2000))
        models() -- made here, never while drawing
        self.GK_Trail = {}
    end

    local LIMB_LEN = 40 -- one limb segment along its +X

    function ENT:Draw()
        self:DrawModel()
        if not IsValid(limbModel) or not IsValid(handModel) then return end
        local root, hand = self:Root(), self:GetHand()
        if hand:DistToSqr(root) < 16 then return end
        -- The arm: limb segments from the vent to the hand, sagging a little.
        local len = root:Distance(hand)
        local n = math.max(1, math.ceil(len / LIMB_LEN))
        local sag = math.min(len * 0.12, 60)
        local prev = root
        local tire = self:GetHandTire()
        render.SetColorModulation(1, 1 - tire * 0.6, 1 - tire * 0.6)
        for i = 1, n do
            local f = i / n
            local p = LerpVector(f, root, hand) - Vector(0, 0, math.sin(f * math.pi) * sag)
            local d = p - prev
            local m = Matrix()
            m:Scale(Vector(d:Length() / LIMB_LEN, 1, 1))
            limbModel:EnableMatrix("RenderMultiply", m)
            limbModel:SetRenderOrigin(prev)
            limbModel:SetRenderAngles(d:Angle())
            limbModel:SetupBones()
            limbModel:DrawModel()
            prev = p
        end
        -- The hand, reaching onward.
        local dir = (hand - root):GetNormalized()
        local a = dir:Angle()
        a:RotateAroundAxis(dir, math.sin(CurTime() * 3) * 15)
        handModel:SetRenderOrigin(hand - dir * 6)
        handModel:SetRenderAngles(a)
        handModel:SetupBones()
        handModel:DrawModel()
        render.SetColorModulation(1, 1, 1)
    end

    -- Grabbed: the screen darkens and bloodies at the edges (WK's vignette).
    hook.Add("HUDPaintBackground", "GK_VentGrab", function()
        local me = LocalPlayer()
        if not IsValid(me) or not IsValid(me:GetNW2Entity("gk_ventgrab")) then return end
        local w, h = ScrW(), ScrH()
        local a = 60 + math.sin(CurTime() * 8) * 20
        surface.SetDrawColor(90, 0, 0, a)
        surface.DrawRect(0, 0, w, h * 0.08) surface.DrawRect(0, h * 0.92, w, h * 0.08)
        surface.DrawRect(0, 0, w * 0.06, h) surface.DrawRect(w * 0.94, 0, w * 0.06, h)
    end)
end

if SERVER then
    -- A fresh life is never still in a hand's grip.
    hook.Add("PlayerSpawn", "GK_VentThingRelease", function(ply) ply:SetNW2Entity("gk_ventgrab", NULL) end)
end
