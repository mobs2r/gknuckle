-- The lift out of a break room, like WK's interlude elevator rides: when the
-- break ends, everyone resting there rides up together for a few seconds:
-- the car starts with a jolt, lamps in the shaft slide past in the dark, it
-- rumbles and creaks, then stops at the next region and the doors let you out.
-- (The ride is the screen's; bodies stay put in the break room until they
-- arrive, the way the hub's staging tube works.)

local LIFT = 6

if SERVER then
    local cvLift = CreateConVar("gk_break_lift", "1", FCVAR_ARCHIVE, "Ride a lift out of the break room into the next region")
    GK.LiftTime = LIFT

    -- Rides `players` up for LIFT seconds, then calls arrive().
    function GK.LiftRide(players, arrive)
        if not cvLift:GetBool() or #players == 0 then arrive() return 0 end
        for _, p in ipairs(players) do
            if IsValid(p) then
                p:SetNW2Float("gk_lift_at", CurTime())
                p:SetLocalVelocity(vector_origin)
                p:EmitSound("plats/elevator_start1.wav", 70)
            end
        end
        timer.Simple(LIFT - 0.6, function()
            for _, p in ipairs(players) do if IsValid(p) then p:EmitSound("plats/elevator_stop1.wav", 70) end end
        end)
        timer.Simple(LIFT, function()
            for _, p in ipairs(players) do if IsValid(p) then p:SetNW2Float("gk_lift_at", 0) end end
            arrive()
        end)
        return LIFT
    end
end

function GK.InLift(ply)
    local t0 = ply:GetNW2Float("gk_lift_at", 0)
    return t0 ~= 0 and CurTime() - t0 < LIFT + 0.5
end

if CLIENT then
    local loop
    local gradU, gradD = Material("vgui/gradient-u"), Material("vgui/gradient-d")
    hook.Add("HUDPaintBackground", "GK_LiftRide", function()
        local me = LocalPlayer()
        if not IsValid(me) then return end
        local t0 = me:GetNW2Float("gk_lift_at", 0)
        if t0 == 0 then
            if loop then loop:Stop() loop = nil end
            return
        end
        local t = CurTime() - t0
        if t > LIFT + 0.5 then return end -- (the server clears it on arrival)
        if not loop then
            loop = CreateSound(me, "plats/elevator_move_loop1.wav")
            loop:PlayEx(0.6, 95)
        end
        local w, h = ScrW(), ScrH()
        -- Doors close (fade to the dark car), the ride, doors open at the end.
        local a = math.Clamp(t / 0.5, 0, 1) * math.Clamp((LIFT - t) / 0.5, 0, 1)
        surface.SetDrawColor(6, 5, 4, 245 * a)
        surface.DrawRect(0, 0, w, h)
        -- Shaft lamps sliding down past the gap in the car's doors: a soft
        -- glow and a thin bright tube each, faster mid-ride.
        local speed = math.sin(math.Clamp(t / LIFT, 0, 1) * math.pi) -- eases in and out
        local gap = h * 0.9
        local scroll = t * h * 0.7 * speed
        local slitL, slitW = w * 0.42, w * 0.16 -- the doors' gap
        for i = -1, 2 do
            local y = (i * gap + scroll) % (h + gap) - gap * 0.4
            local glow = 70 * a * speed
            surface.SetMaterial(gradU)
            surface.SetDrawColor(255, 170, 90, glow)
            surface.DrawTexturedRect(0, y, w, h * 0.18)
            surface.SetMaterial(gradD)
            surface.DrawTexturedRect(0, y - h * 0.18, w, h * 0.18)
            surface.SetDrawColor(255, 225, 170, 200 * a * speed)
            surface.DrawRect(slitL, y - 2, slitW, 4)
        end
        -- The car's door frame: dark panels either side of the gap.
        surface.SetDrawColor(10, 9, 8, 235 * a)
        surface.DrawRect(0, 0, slitL, h)
        surface.DrawRect(slitL + slitW, 0, w - slitL - slitW, h)
        if loop then loop:ChangePitch(85 + 25 * speed, 0) end
    end)
    -- A rumble through the floor while it climbs.
    hook.Add("CalcView", "GK_LiftShake", function(ply, origin, angles, fov)
        local t0 = ply:GetNW2Float("gk_lift_at", 0)
        if t0 == 0 then return end
        local t = CurTime() - t0
        local k = math.sin(math.Clamp(t / LIFT, 0, 1) * math.pi)
        local jolt = (t < 0.3 or (t > LIFT - 0.6 and t < LIFT - 0.3)) and 2 or 0
        return { origin = origin + VectorRand() * (0.4 * k + jolt), angles = angles + Angle(math.Rand(-1, 1) * 0.3 * k, 0, math.Rand(-1, 1) * 0.4 * k), fov = fov }
    end)
end
