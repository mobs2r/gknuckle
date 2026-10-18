local C = GK.Config

-- KZ movement (default): CS:GO's movement with bunnyhopping unleashed, the
-- way KZ / bhop servers run it: no take-off speed cap, no jump/land
-- slowdown, and sv_airaccelerate 100 (init.lua), so strafing in the air
-- builds real speed. gk_kz 0 is matchmaking CS:GO (capped, slowing hops).
GK.KZ = CreateConVar("gk_kz", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }, "KZ bhop movement (1) or matchmaking CS:GO (0)")
-- Races run CS:GO's capped take-off whatever gk_kz says, so nobody bhops past
-- a region's climb; the hub keeps KZ for the KZ course and messing about.
GK.KZRuns = CreateConVar("gk_kz_runs", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Allow KZ bhop movement inside runs too")
function GK.UsesKZ(ply)
    return GK.KZ:GetBool() and (GK.KZRuns:GetBool() or not GK.ArenaOf or GK.ArenaOf(ply) == 0)
end

function GM:Move(ply, mv)
    if GK.IsRagdolled(ply) then
        mv:SetMaxSpeed(0)
        mv:SetMaxClientSpeed(0)
        return
    end

    -- Pinned on a rebar: sh_impale.lua slides gk_impale_pos along it as you get off.
    local spike = ply:GetNW2Entity("gk_impaled")
    if IsValid(spike) then
        mv:SetVelocity(vector_origin)
        mv:SetOrigin(ply:GetNW2Vector("gk_impale_pos", mv:GetOrigin()))
        return
    end

    if drive.Move(ply, mv) then return true end

    -- Being sucked up the staging tube (sv_arena.lua): held still while the
    -- view rides up into the dark (cl: GK_TubeRideView), then you arrive.
    if ply:GetNW2Float("gk_rise_to", 0) ~= 0 or (GK.InLift and GK.InLift(ply)) then
        mv:SetVelocity(vector_origin)
        return true
    end

    -- Caught by a barnacle's tongue: reeled up toward its mouth (WK's TonguePull),
    -- with only a little say over it.
    local tongue = ply:GetNW2Entity("gk_tongue")
    if IsValid(tongue) and tongue.Mouth then
        local target = tongue:Mouth() - Vector(0, 0, 62)
        local to = target - mv:GetOrigin()
        local vel = to:Length() > 6 and to:GetNormalized() * 70 or vector_origin
        local fwd = Angle(0, mv:GetMoveAngles().y, 0)
        vel = vel + (fwd:Forward() * mv:GetForwardSpeed() + fwd:Right() * mv:GetSideSpeed()):GetNormalized() * 15 * math.min(1, math.abs(mv:GetForwardSpeed()) + math.abs(mv:GetSideSpeed()))
        if ply:OnGround() then
            ply:SetGroundEntity(NULL)
            mv:SetOrigin(mv:GetOrigin() + Vector(0, 0, 2))
        end
        mv:SetVelocity(vel)
        return
    end

    -- Grabbed by a Vent Thing's hand: dragged toward its vent, unless you're
    -- hanging on to something (then it's a tug of war over your grip).
    local vt = ply:GetNW2Entity("gk_ventgrab")
    if IsValid(vt) and vt.Root and not (ply:GetNW2Bool("gk_anchor_l", false) or ply:GetNW2Bool("gk_anchor_r", false)) then
        local to = vt:Root() - mv:GetOrigin() - Vector(0, 0, 36)
        local vel = to:Length() > 4 and to:GetNormalized() * 110 or vector_origin
        if ply:OnGround() then
            ply:SetGroundEntity(NULL)
            mv:SetOrigin(mv:GetOrigin() + Vector(0, 0, 2))
        end
        mv:SetVelocity(vel)
        return
    end

    -- Climbing: each weight-bearing grip is a handhold the body is sprung toward.
    -- Hanging rests the eyes just below the hold; W pulls up to it, and on a
    -- ledge top W mantles you up and over. Runs in Move so it's predicted (smooth).
    local n, target = 0, Vector()
    local pull = mv:KeyDown(IN_FORWARD) and 1 or (mv:KeyDown(IN_BACK) and -1 or 0)
    local fwd = Angle(0, mv:GetMoveAngles().y, 0):Forward()
    -- Jumping off a wall is predicted here, on both sides: the server lets go of
    -- the holds in the mind's Think right after, and until that reaches the
    -- client the holds it still sees (grabbed before the jump) don't pull you back.
    local ct = CurTime()
    local jumped = ply.GK_GripJumpAt or 0
    local stale = ct >= jumped and ply:GetNW2Float("gk_grab_at", 0) <= jumped
    local hands = 0
    if not stale then
        for _, side in ipairs({ "l", "r" }) do
            if ply:GetNW2Bool("gk_anchor_" .. side, false) then hands = hands + 1 end
        end
    end
    if hands > 0 and mv:KeyPressed(IN_JUMP) and GK.Stamina(ply) > C.StaminaDrainJump * hands then
        ply.GK_GripJumpAt = ct
        local dir = mv:GetMoveAngles():Forward()
        dir.z = math.max(0.3, dir.z)
        if ply:OnGround() then
            ply:SetGroundEntity(NULL)
            mv:SetOrigin(mv:GetOrigin() + Vector(0, 0, 2))
        end
        mv:SetVelocity(mv:GetVelocity() + dir * C.JumpBoostForce)
        return
    end
    for _, side in ipairs({ "l", "r" }) do
        if hands > 0 and ply:GetNW2Bool("gk_anchor_" .. side, false) then
            local a = ply:GetNW2Vector("gk_grip_" .. side)
            local t
            if pull > 0 and ply:GetNW2Bool("gk_top_" .. side, false) then
                -- Up over the lip itself (it can be an arm's reach above the
                -- hand) and in over the top, the way the wall faces, not the view.
                local lip = ply:GetNW2Vector("gk_lip_" .. side, a)
                local into = ply:GetNW2Vector("gk_into_" .. side, vector_origin)
                if into:IsZero() then into = fwd end
                -- Eyes a body-height over the lip, so the feet clear it.
                t = Vector(a.x, a.y, math.max(a.z, lip.z)) + Vector(0, 0, ply:GetViewOffset().z + 10) + into * 28
            elseif pull > 0 then
                t = a + Vector(0, 0, 10)
            elseif pull < 0 then
                t = a - Vector(0, 0, 50)
            else
                t = a - Vector(0, 0, 22)
            end
            target:Add(t)
            n = n + 1
        end
    end
    -- WK: crouch while hanging to lock in place (no pull, no sag, no sway).
    if n > 0 and mv:KeyDown(IN_DUCK) then
        mv:SetVelocity(vector_origin)
        return
    end
    if n > 0 then
        target:Div(n)
        local eye = mv:GetOrigin() + (ply:Crouching() and ply:GetViewOffsetDucked() or ply:GetViewOffset())
        local climb = GK.BuffMult(ply, "climb") -- perks: Latissimus, System Reorganization
        local to = target - eye
        -- WK's hang has a dead zone: no pull right at the hold (no jitter).
        local dist = to:Length()
        local vel = dist > 4 and to * ((dist - 4) / dist) * 9 * climb or Vector()
        -- A little sideways shimmy with A/D.
        local strafe = (mv:KeyDown(IN_MOVERIGHT) and 1 or 0) - (mv:KeyDown(IN_MOVELEFT) and 1 or 0)
        vel:Add(Angle(0, mv:GetMoveAngles().y, 0):Right() * strafe * 60)
        if vel:Length() > 450 * climb then vel = vel:GetNormalized() * 450 * climb end
        -- WK's climb-jump chaining: right after a new grab (holdTime ~ 0) the hang
        -- barely damps your speed, so jump -> grab -> jump keeps its momentum and
        -- carries you up past the hold; over ~0.35 s the hang takes over fully.
        local held = CurTime() - ply:GetNW2Float("gk_grab_at", 0)
        if held < 0.35 and GK.ClimbCarry:GetBool() then
            local cur = mv:GetVelocity()
            local k = math.Clamp(held / 0.35, 0, 1)
            k = k * k
            -- Upward speed is kept (never cut by the grab), the rest blends in.
            local blended = LerpVector(math.max(k, 0.15), cur, vel)
            if cur.z > vel.z then blended.z = Lerp(k, cur.z, vel.z) end
            vel = blended
        end
        -- Ground movement zeroes upward velocity, so lift off before pulling up.
        if vel.z > 10 and ply:OnGround() then
            ply:SetGroundEntity(NULL)
            mv:SetOrigin(mv:GetOrigin() + Vector(0, 0, 2))
        end
        mv:SetVelocity(vel)
        return
    end

    -- Source-style ladders (red WK ladders): walk into one and climb (sh_ladders.lua).
    if GK.LadderMove(ply, mv) then return true end

    GK.DuckSpam(ply, mv)
    -- WK's coyote time: a jump pressed up to 0.12 s after walking off a ledge
    -- still counts (once, and it costs the jump's stamina like any other).
    if ply:OnGround() then
        ply.GK_GroundAt, ply.GK_CoyoteUsed = CurTime(), false
    elseif mv:KeyPressed(IN_JUMP) and not ply.GK_CoyoteUsed and CurTime() - (ply.GK_GroundAt or 0) <= 0.12
        and mv:GetVelocity().z <= 0 and GK.HasLegs(ply) and GK.Stamina(ply) >= (C.StaminaJumpCost or 8) then
        ply.GK_CoyoteUsed = true
        local v = mv:GetVelocity()
        mv:SetVelocity(Vector(v.x, v.y, ply:GetJumpPower()))
        if SERVER then GK.AddStamina(ply, -(C.StaminaJumpCost or 8)) end
    end
    local speedMultiplier = GK.UsesKZ(ply) and 1 or (1 - GK.JumpSlow(ply))

    local speed = ply:KeyDown(IN_SPEED) and C.RunSpeed or C.WalkSpeed
    -- WK's sprint, on Alt: faster on your feet while you have stamina for it.
    local sprinting = mv:KeyDown(IN_WALK) and not mv:KeyDown(IN_SPEED) and not ply:Crouching()
        and GK.Stamina(ply) > 1 and (mv:GetForwardSpeed() > 0)
    if sprinting then speed = C.SprintSpeed or 330 end
    ply.GK_Sprinting = sprinting
    if not GK.HasLegs(ply) then
        -- Dragging yourself along; jump power is zeroed in sv_dismember, and the
        -- mind can still climb and grip-jump at full strength.
        speed = C.LeglessWalkSpeed
    end
    if GK.IsDowned(ply) then speed = C.DownedCrawlSpeed end
    speed = speed * GK.BuffMult(ply, "speed") -- the needle, food (sh_buffs.lua)
    speed = speed * GK.XeniumSlow ^ ply:GetNW2Int("gk_xenium", 0) -- heavy xenium roaches in the bag
    speed = speed * ply:GetNW2Float("gk_encumber", 1) -- WK: more than 13 things in the bag slows you
    if ply:GetNW2Float("gk_stagger_until", 0) > CurTime() then speed = speed * 0.55 end -- grip shattered: staggering
    if GK.OneLegged(ply) and ply:OnGround() then
        -- One leg: you can't walk, only hop (air control is untouched).
        mv:SetForwardSpeed(0) mv:SetSideSpeed(0)
    end

    mv:SetMaxSpeed(speed * speedMultiplier)
    mv:SetMaxClientSpeed(speed * speedMultiplier)
    ply.GK_MaxSpeed = speed
end

if CLIENT then
    hook.Add("CalcView", "GK_TubeRideView", function(ply, origin, angles, fov)
        local t0 = ply:GetNW2Float("gk_rise_to", 0)
        if t0 == 0 then return end
        local t = math.max(0, CurTime() - t0)
        return { origin = origin + Vector(0, 0, 1200 * t * t), angles = Angle(math.min(-60, angles.p), angles.y, angles.r + t * 40), fov = fov + t * 25 }
    end)
    hook.Add("HUDPaintBackground", "GK_TubeRideFade", function()
        local t0 = LocalPlayer():GetNW2Float("gk_rise_to", 0)
        if t0 == 0 then return end
        surface.SetDrawColor(0, 0, 0, math.Clamp((CurTime() - t0) / 1.4, 0, 1) * 255)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    end)
end

-- The body is narrower than a stock player (24 u, not 32): the Husk has no
-- arms, and a wide box snagged on lips and holds while climbing. Set on both
-- realms (prediction), once per player and again on each spawn.
local HULL_MIN, HULL_MAX = Vector(-12, -12, 0), Vector(12, 12, 72)
local DUCK_MAX = Vector(12, 12, 36)
function GK.ApplyHull(ply)
    ply:SetHull(HULL_MIN, HULL_MAX)
    ply:SetHullDuck(HULL_MIN, DUCK_MAX)
    ply.GK_Hull = true
end
hook.Add("PlayerSpawn", "GK_NarrowHull", function(ply) GK.ApplyHull(ply) end)
hook.Add("SetupMove", "GK_NarrowHull", function(ply) if not ply.GK_Hull then GK.ApplyHull(ply) end end)

-- CS:GO's jump stamina: every jump adds 8% and every landing 5% to a
-- slowdown that wears off at 60/80 a second while you're on the ground, so
-- chaining hops (autohop included) makes you slower, not faster.
local SLOW_JUMP, SLOW_LAND, SLOW_RECOVER, SLOW_MAX = 0.08, 0.05, 0.75, 0.35
function GK.JumpSlow(ply, add)
    local ct = CurTime()
    local v, t = ply.GK_Slow or 0, ply.GK_SlowT or ct
    if ct > t and ply:OnGround() then v = math.max(0, v - (ct - t) * SLOW_RECOVER) end
    if add and ct > (ply.GK_SlowEvt or 0) then -- once per tick, even when re-predicted
        ply.GK_SlowEvt = ct
        v = math.min(SLOW_MAX, v + add)
    end
    if ct >= t then ply.GK_Slow, ply.GK_SlowT = v, ct end
    return v
end

-- CS:GO's duck spam rule: ducking itself gets slower the more you spam it
-- (each press uses up duck speed, which comes back over a second or two);
-- walking speed is untouched.
local DUCK_MAX, DUCK_COST, DUCK_RECOVER, DUCK_TIME = 8, 2, 3, 0.2
function GK.DuckSpam(ply, mv)
    local ct = CurTime()
    local v, t = ply.GK_DuckRes or DUCK_MAX, ply.GK_DuckT or ct
    if ct > t then v = math.min(DUCK_MAX, v + (ct - t) * DUCK_RECOVER) end
    if mv:KeyPressed(IN_DUCK) and ct > (ply.GK_DuckEvt or 0) then
        ply.GK_DuckEvt = ct
        v = math.max(0, v - DUCK_COST)
    end
    if ct >= t then ply.GK_DuckRes, ply.GK_DuckT = v, ct end
    local time = DUCK_TIME * DUCK_MAX / math.max(v, 1.6)
    if math.abs(ply:GetDuckSpeed() - time) > 0.01 then
        ply:SetDuckSpeed(time)
        ply:SetUnDuckSpeed(time)
    end
end

-- Landing: CS:GO's landing slowdown and a little view punch for the impact.
hook.Add("OnPlayerHitGround", "GK_CSLanding", function(ply, inWater, onFloater, speed)
    if not GK.UsesKZ(ply) then GK.JumpSlow(ply, SLOW_LAND) end
    -- WK's three landing kicks: a dip, a thump, and a hard jolt with a tilt.
    if SERVER and speed > 200 then
        if speed < 400 then ply:ViewPunch(Angle(1.5, 0, 0))
        elseif speed < 650 then ply:ViewPunch(Angle(4, 0, math.Rand(-1.5, 1.5)))
        else ply:ViewPunch(Angle(8, math.Rand(-2, 2), math.Rand(-5, 5))) end
    end
end)

-- Autohop: hold jump and you jump again the moment you land (the engine only
-- jumps on a fresh press, so forget the held button while on the ground).
-- Every jump off the ground costs stamina; without enough you can't jump.
function GM:SetupMove(ply, mv, cmd)
    if not mv:KeyDown(IN_JUMP) then return end
    if ply:GetMoveType() ~= MOVETYPE_WALK or GK.IsImpaled(ply) then return end
    if GK.OnLadder and GK.OnLadder(ply) then return end
    -- Hanging on a hold: Jump is the grip-jump (GM:Move), with its own cost.
    if ply:GetNW2Bool("gk_anchor_l", false) or ply:GetNW2Bool("gk_anchor_r", false) then return end
    local cost = GK.Config.StaminaJumpCost or 8
    -- Too tired: no jump at all, including on the tick you land.
    if GK.Stamina(ply) < cost then
        mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))
        return
    end
    if not ply:OnGround() then return end
    mv:SetOldButtons(bit.band(mv:GetOldButtons(), bit.bnot(IN_JUMP)))
    -- CS:GO take-off: no carrying more than 1.1x run speed into a jump (this,
    -- not an air cap, is what stops bhop snowballing; air strafing still
    -- gains speed mid-air), then the jump slowdown on top.
    if not GK.UsesKZ(ply) then
        local vel = mv:GetVelocity()
        local flat = Vector(vel.x, vel.y, 0)
        local cap = (ply.GK_MaxSpeed or C.WalkSpeed) * 1.1
        if flat:Length() > cap then flat = flat:GetNormalized() * cap end
        flat = flat * (1 - GK.JumpSlow(ply, SLOW_JUMP))
        mv:SetVelocity(Vector(flat.x, flat.y, vel.z))
    end
    -- Pay for it once per take-off (the server owns stamina).
    if SERVER and (ply.GK_JumpPaid or 0) < CurTime() - 0.2 and GK.HasLegs(ply) then
        ply.GK_JumpPaid = CurTime()
        GK.AddStamina(ply, -cost)
        ply.GK_StaminaRestAt = CurTime() + (GK.Config.StaminaRegenDelay or 1)
    end
end

-- Sprinting costs stamina while you're actually running on the ground.
if SERVER then
    hook.Add("PlayerTick", "GK_SprintDrain", function(ply)
        local running = ply.GK_Sprinting and ply:OnGround() and ply:GetVelocity():Length2D() > (C.WalkSpeed or 250) + 10
        if running ~= ply:GetNW2Bool("gk_sprint", false) then ply:SetNW2Bool("gk_sprint", running) end -- the view widens (sh_buffs.lua)
        if running then
            GK.AddStamina(ply, -(C.SprintDrain or 6) * FrameTime())
            ply.GK_StaminaRestAt = CurTime() + (C.StaminaRegenDelay or 1)
        end
    end)
end
