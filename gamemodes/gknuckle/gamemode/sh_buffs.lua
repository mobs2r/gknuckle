-- Timed buffs from consumables, after White Knuckle's buff ids:
--   gooped    Slug Grub crushed in your hands: grab anything (any surface, even
--             in ledges-only mode, even with no stamina) and grips never tire.
--   injected  Injector (the needle): addSpeed 1.3, addJump 0.35, addFOV 15.
--   pilled    Pill bottle: grip strength (climbing drains half the stamina)
--             and stamina comes back half again as fast.
--   fed       Bean bar / beans / meat: a little speed.
--   shielded  HL suit battery: the Xenium link can't be knocked offline.
-- Each is a NW2 float "gk_buff_<id>" holding when it runs out.

local C = GK.Config

GK.BuffInfo = {
    gooped   = { color = Color(150, 255, 60) },
    injected = { speed = 2.3, jump = 1.35, fov = 15, color = Color(255, 60, 60) },
    pilled   = { drain = 0.5, regen = 1.5, color = Color(240, 240, 120) },
    fed      = { speed = 1.25 },
    shielded = { color = Color(90, 170, 255) },
}

function GK.HasBuff(ply, id)
    return IsValid(ply) and ply:GetNW2Float("gk_buff_" .. id, 0) > CurTime()
end

function GK.BuffLeft(ply, id)
    return math.max(0, ply:GetNW2Float("gk_buff_" .. id, 0) - CurTime())
end

-- A buff field over every active buff (speed, jump, drain, regen). Like WK,
-- each buff fades out evenly over its whole time, and buffs on the same field
-- add together rather than multiply.
function GK.BuffMult(ply, field)
    local m = 1
    for id, info in pairs(GK.BuffInfo) do
        if info[field] and GK.HasBuff(ply, id) then
            local total = math.max(1, ply:GetNW2Float("gk_bufflen_" .. id, 10))
            local k = math.Clamp(GK.BuffLeft(ply, id) / total, 0, 1)
            m = m + (info[field] - 1) * k
        end
    end
    m = math.max(0.05, m)
    if GK.PerkMult then m = m * GK.PerkMult(ply, field) end -- run perks (sh_perks.lua)
    return m
end

if SERVER then
    function GK.AddBuff(ply, id, seconds)
        seconds = seconds * GK.BuffMult(ply, "bufftime") -- Metabolic Stasis
        local untilT = math.max(ply:GetNW2Float("gk_buff_" .. id, 0), CurTime()) + seconds
        ply:SetNW2Float("gk_buff_" .. id, untilT)
        ply:SetNW2Float("gk_bufflen_" .. id, untilT - CurTime()) -- fades evenly from here
    end

    hook.Add("PlayerSpawn", "GK_ClearBuffs", function(ply)
        for id in pairs(GK.BuffInfo) do ply:SetNW2Float("gk_buff_" .. id, 0) end
    end)

    -- Jump power follows the buffs (legless stays at zero).
    hook.Add("PlayerTick", "GK_BuffJump", function(ply)
        if not GK.HasLegs(ply) then return end
        local want = C.JumpPower * GK.BuffMult(ply, "jump")
        -- WK: a bag heavy enough to halve your speed cuts your jump too.
        local enc = ply:GetNW2Float("gk_encumber", 1)
        if enc < 0.5 then want = want * math.max(0.5, enc * 2) end
        if math.abs(ply:GetJumpPower() - want) > 1 then ply:SetJumpPower(want) end
    end)
end

if CLIENT then
    -- The view: the needle widens it, real speed kicks it out a little, and
    -- hanging off a wall tilts it toward the hand you're hanging from (WK
    -- rolls the camera hard while climbing, 20-45 degrees).
    local roll, kick = 0, 0
    hook.Add("CalcView", "GK_View", function(ply, origin, angles, fov)
        if ply:ShouldDrawLocalPlayer() then return end
        local dt = FrameTime()
        local l, r = ply:GetNW2Int("gk_hand_l", 0) == 1, ply:GetNW2Int("gk_hand_r", 0) == 1
        local want = 0
        -- WK rolls hard on the wall: about 20 degrees toward a lone hand, up
        -- to 45 with a sideways swing on top.
        if l ~= r then want = l and -20 or 20 end
        if l or r then
            -- Swinging sideways on the wall leans you into it.
            want = math.Clamp(want + ply:GetVelocity():Dot(angles:Right()) * 0.08, -45, 45)
        end
        roll = Lerp(math.min(1, dt * 6), roll, want)
        local speed = ply:GetVelocity():Length2D()
        kick = Lerp(math.min(1, dt * 4), kick, math.Clamp((speed - 260) / 40, 0, 8))
        -- WK's sprint widens the view by 15.
        local sprintFov = ply:GetNW2Bool("gk_sprint", false) and 15 or 0
        ply.GK_SprintFov = Lerp(math.min(1, dt * 5), ply.GK_SprintFov or 0, sprintFov)
        local add = kick + ply.GK_SprintFov
        if GK.HasBuff(ply, "injected") then
            add = add + GK.BuffInfo.injected.fov * math.min(1, GK.BuffLeft(ply, "injected") / 10)
        end
        if math.abs(roll) < 0.05 and add < 0.05 then return end
        local a = Angle(angles.p, angles.y, angles.r + roll)
        return { origin = origin, angles = a, fov = fov + add }
    end)

    -- Goop on the screen edges while your hands are slimed; a red pulse on the needle.
    hook.Add("HUDPaintBackground", "GK_BuffScreen", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local w, h = ScrW(), ScrH()
        if GK.HasBuff(ply, "gooped") then
            local a = 40 + math.sin(CurTime() * 3) * 15
            surface.SetDrawColor(110, 200, 40, a)
            surface.DrawRect(0, 0, w, h * 0.04)
            surface.DrawRect(0, h * 0.96, w, h * 0.04)
            surface.DrawRect(0, 0, w * 0.03, h)
            surface.DrawRect(w * 0.97, 0, w * 0.03, h)
        end
        if GK.HasBuff(ply, "injected") then
            surface.SetDrawColor(255, 30, 30, 18 + math.abs(math.sin(CurTime() * 6)) * 22)
            surface.DrawRect(0, 0, w, h)
        end
    end)
end
