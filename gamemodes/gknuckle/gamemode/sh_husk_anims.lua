-- Armless third-person animation for Husk models. Weapon holdtypes and arm gestures twist
-- the spine/shoulders as if holding things, so for Husks:
--  * every movement activity uses the "normal" (no-weapon) set: idle/walk/run/crouch/jump/swim
--  * attack / reload / grenade gestures and the typing ear-grab are dropped (taunts stay:
--    they are whole-body and Gameplay's GK.Expression reads them)
--  * gripping a surface adds a slight forward climbing lean (client-side, render only)
-- Hooks only return for Husks, so Gameplay's / Sandbox's animation code runs for everyone else.
AddCSLuaFile()
GK.Husk = GK.Husk or {}

local IDLE = ACT_HL2MP_IDLE
local NORMAL = {
    [ACT_MP_STAND_IDLE] = IDLE, [ACT_MP_WALK] = IDLE + 1, [ACT_MP_RUN] = IDLE + 2,
    [ACT_MP_CROUCH_IDLE] = IDLE + 3, [ACT_MP_CROUCHWALK] = IDLE + 4,
    [ACT_MP_ATTACK_STAND_PRIMARYFIRE] = IDLE, [ACT_MP_ATTACK_CROUCH_PRIMARYFIRE] = IDLE + 3,
    [ACT_MP_RELOAD_STAND] = IDLE, [ACT_MP_RELOAD_CROUCH] = IDLE + 3,
    [ACT_MP_JUMP] = ACT_HL2MP_JUMP_SLAM, [ACT_MP_SWIM] = IDLE + 9, [ACT_LAND] = ACT_LAND,
}
hook.Add("TranslateActivity", "GK_HuskAnims", function(ply, act)
    if GK.IsHusk and GK.IsHusk(ply) then return NORMAL[act] end
end)

local ARM_EVENTS = {
    [PLAYERANIMEVENT_ATTACK_PRIMARY] = true, [PLAYERANIMEVENT_ATTACK_SECONDARY] = true,
    [PLAYERANIMEVENT_ATTACK_GRENADE] = true, [PLAYERANIMEVENT_RELOAD] = true,
    [PLAYERANIMEVENT_RELOAD_LOOP] = true, [PLAYERANIMEVENT_RELOAD_END] = true,
}
hook.Add("DoAnimationEvent", "GK_HuskAnims", function(ply, event, data)
    if ARM_EVENTS[event] and GK.IsHusk and GK.IsHusk(ply) then
        ply:AnimResetGestureSlot(GESTURE_SLOT_ATTACK_AND_RELOAD)
        return ACT_INVALID
    end
end)

-- The typing ear-grab is a GM method, not a hook: wrap it once so Husks skip it.
local function wrapEar()
    local gm = GAMEMODE or GM
    if not gm or not gm.GrabEarAnimation or gm.GK_HuskEarWrapped then return end
    local orig = gm.GrabEarAnimation
    gm.GrabEarAnimation = function(self, ply, ...)
        if GK.IsHusk and GK.IsHusk(ply) then return end
        return orig(self, ply, ...)
    end
    gm.GK_HuskEarWrapped = true
end
hook.Add("Initialize", "GK_HuskAnims", wrapEar)
wrapEar()

if CLIENT then
    -- Climbing lean: Spine2's local Z is the body's side axis, so +yaw tips the chest forward.
    -- Eased in/out; only touches the render-side bone manipulation of Husk players.
    local LEAN = 14
    local leanNow = setmetatable({}, { __mode = "k" })
    hook.Add("PrePlayerDraw", "GK_HuskLean", function(ply)
        if not (GK.IsHusk and GK.IsHusk(ply)) then return end
        local bone = ply:LookupBone("ValveBiped.Bip01_Spine2")
        if not bone then return end
        local gripping = ply:GetNW2Int("gk_hand_l", 0) == 1 or ply:GetNW2Int("gk_hand_r", 0) == 1
        local want = (gripping and not ply:OnGround()) and LEAN or 0
        local cur = math.Approach(leanNow[ply] or 0, want, FrameTime() * 60)
        leanNow[ply] = cur
        ply:ManipulateBoneAngles(bone, Angle(0, cur, 0), false)
    end)
    GK.Husk.LeanOf = function(ply) return leanNow[ply] or 0 end
end
