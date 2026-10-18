-- Source-style ladders on White Knuckle's red ladders: an old-school ladder
-- clip (gk_ladder volumes) mixed with the mind-hands. Walk into a ladder and
-- you're on it, no grabbing needed:
--   Climbing works exactly like CS:GO's (Source's LadderMove): whatever part
--   of your move input points into the ladder becomes climbing, so W, S, A, D
--   all climb depending on which way you face; W+A/D at an angle and A+D
--   together "vector" you up faster; Jump pushes you off (with your strafe),
--   and strafing past the side of the ladder takes you off it.
--   Off the ground inside the volume you hang there; nothing drains stamina.
--   At the top you're helped over onto the ledge.
--   Gripping with a mind-hand still wins over the ladder (sh_movement.lua),
--   so you can grab off a ladder onto the wall beside it.
-- Runs in GM:Move so it's predicted.

local CLIMB_SPEED = 190   -- CS:GO's ladder speed is 156-195
local STICK = 30
local SNEAK = 0.5        -- walk key: half speed, and silent, like CS:GO

function GK.LadderAt(pos)
    local centre = pos + Vector(0, 0, 36)
    for _, l in ipairs(ents.FindByClass("gk_ladder")) do
        if l.Contains and l:Contains(centre, 16) then return l end
    end
end

-- Returns true if the player is on a ladder this tick (moved and velocity set);
-- GM:Move then returns true so the engine's walking doesn't also run.
function GK.LadderMove(ply, mv)
    if (ply.GK_LadderOff or 0) > CurTime() then return false end
    local l = GK.LadderAt(mv:GetOrigin())
    if not l then return false end

    local out = l:GetForward()            -- away from the ladder, toward the climber
    local up = l:GetUp()
    local right = l:GetRight()
    local fs, ss = mv:GetForwardSpeed(), mv:GetSideSpeed()
    local maxIn = math.max(math.abs(fs), math.abs(ss), 1)

    -- What you're asking for, exactly like Source/CS:GO's LadderMove: your
    -- full 3D move input (view pitch included), in units of climb speed.
    local ang = mv:GetMoveAngles()
    local wish = ang:Forward() * (fs ~= 0 and (fs > 0 and 1 or -1) or 0) + ang:Right() * (ss ~= 0 and (ss > 0 and 1 or -1) or 0)
    -- The part pushing into the ladder turns into climbing up, and the part
    -- pulling away into climbing down; the rest moves you up/down and across
    -- it. So you climb facing any way (backwards, sideways, looking up or
    -- down), and W with A or D at an angle (the vector) climbs faster than W alone.
    local into = -wish:Dot(out)
    local across = wish:Dot(right)
    local vert = wish:Dot(up)
    local climb = vert + into
    -- A and D held together: the classic ladder vector, straight up at full tilt.
    local ad = mv:KeyDown(IN_MOVELEFT) and mv:KeyDown(IN_MOVERIGHT)
    if ad then climb = math.max(climb, 1) * math.sqrt(2) end

    -- On the ground, only moving into the ladder gets you on it; anything else
    -- is ordinary walking (so you can step away from the bottom).
    if ply:OnGround() and into < 0.3 and not ad then return false end

    if mv:KeyPressed(IN_JUMP) then
        -- Off the ladder, CS:GO style: a soft push back plus whatever way you're strafing.
        ply.GK_LadderOff = CurTime() + 0.35
        mv:SetVelocity(out * 180 + right * across * 200 + Vector(0, 0, 140))
        return true
    end

    local mult = 1
    if mv:KeyDown(IN_SPEED) then mult = SNEAK end
    ply.GK_LadderSneak = mv:KeyDown(IN_SPEED)
    -- Only the strafe vector (W with A or D, turned into the ladder) climbs
    -- faster, as in CS:GO; looking up or down alone climbs at plain speed.
    local cap = (ss ~= 0 or ad) and math.sqrt(2) or 1
    climb = math.Clamp(climb, -cap, cap)
    -- Pushing into the ladder, a strafe turns into climb (the vector) rather
    -- than sliding you off its side; with no push it shuffles you across.
    local slide = across * (1 - math.Clamp(math.abs(into), 0, 1))
    local vel = up * climb * CLIMB_SPEED * mult + right * slide * CLIMB_SPEED * 0.7 * mult - out * STICK
    -- Near the top going up: help over the lip onto whatever's above.
    local l2 = l:WorldToLocal(mv:GetOrigin() + Vector(0, 0, 36))
    if climb > 0.2 and l2.z > l:GetHeight() - 24 then
        vel = vel - out * 140 + Vector(0, 0, 60)
    end
    -- Move ourselves (GM:Move returns true, so no gravity or air control fights
    -- the ladder), sliding along whatever we bump, like the engine does.
    local dt = FrameTime()
    local pos = mv:GetOrigin()
    local mins, maxs = ply:OBBMins(), ply:OBBMaxs()
    local move = vel * dt
    for _ = 1, 3 do
        if move:LengthSqr() < 1e-4 then break end
        local tr = util.TraceHull({ start = pos, endpos = pos + move, mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID })
        pos = tr.HitPos
        if not tr.Hit then break end
        move = move * (1 - tr.Fraction)
        move = move - tr.HitNormal * move:Dot(tr.HitNormal)
        vel = vel - tr.HitNormal * math.min(0, vel:Dot(tr.HitNormal))
    end
    mv:SetOrigin(pos)
    mv:SetVelocity(vel)
    ply:SetGroundEntity(NULL)
    ply.GK_OnLadder = CurTime()
    return true
end

function GK.OnLadder(ply) return (ply.GK_OnLadder or 0) > CurTime() - 0.1 end

-- Ladder footsteps: the rungs ring as you climb.
if SERVER then
    hook.Add("PlayerTick", "GK_LadderSteps", function(ply)
        if not GK.OnLadder(ply) or ply.GK_LadderSneak or ply:GetVelocity():Length() < 40 then return end
        if (ply.GK_NextRung or 0) > CurTime() then return end
        ply.GK_NextRung = CurTime() + 0.35
        ply:EmitSound("player/footsteps/ladder" .. math.random(1, 4) .. ".wav", 65)
    end)
end
