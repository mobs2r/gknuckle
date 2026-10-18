-- Hand colour = the player's condition, readable by everyone at a glance.
-- Action colours override the idle health colour.
--
-- Idle (health):  100 white, 99-70 -> green, 69-50 -> yellow, 49-20 -> orange,
--                 19-1 -> dark red, 0 downed = neon pink, gored = grey/black
-- Action:         orange gripping/climbing, green emote, light red stunned/hurt,
--                 pink down/crawling/impaled, blue in menus

GK.Colors = {
    White = Color(255, 255, 255),
    Green = Color(70, 235, 90),
    Yellow = Color(255, 230, 40),
    Orange = Color(255, 140, 30),
    DarkRed = Color(120, 0, 0),
    NeonPink = Color(255, 20, 230),
    Gored = Color(45, 45, 48),

    Grip = Color(255, 140, 30),
    Emote = Color(70, 235, 90),
    Hurt = Color(255, 120, 120),
    Crawl = Color(255, 130, 200),
    Menu = Color(70, 150, 255),
}

local function lerpColor(t, a, b)
    t = math.Clamp(t, 0, 1)
    return Color(Lerp(t, a.r, b.r), Lerp(t, a.g, b.g), Lerp(t, a.b, b.b))
end

function GK.IsDowned(ply) return ply:GetNW2Bool("gk_downed", false) end
function GK.IsGored(ply) return ply:GetNW2Bool("gk_gored", false) end
function GK.IsImpaled(ply) return IsValid(ply:GetNW2Entity("gk_impaled")) end
function GK.InMenu(ply) return ply:GetNW2Bool("gk_in_menu", false) end
function GK.IsEmoting(ply) return ply:GetNW2Float("gk_emote_until", 0) > CurTime() end
function GK.IsHurt(ply) return ply:GetNW2Float("gk_hurt_until", 0) > CurTime() end

function GK.IsCrawling(ply)
    return not GK.HasLegs(ply) and ply:OnGround() and ply:GetVelocity():Length2DSqr() > 100
end

function GK.HealthColor(ply)
    local C = GK.Colors
    local hp = ply:Health()
    if hp >= 100 then return C.White end
    if hp >= 70 then return lerpColor((99 - hp) / 29, C.White, C.Green) end
    if hp >= 50 then return lerpColor((69 - hp) / 19, C.Green, C.Yellow) end
    if hp >= 20 then return lerpColor((49 - hp) / 29, C.Yellow, C.Orange) end
    return lerpColor((19 - hp) / 18, C.Orange, C.DarkRed)
end

-- side is "l" or "r"; handState comes from the mind weapon (1 grip, 2 holding).
function GK.HandColor(ply, side)
    local C = GK.Colors
    if GK.IsGored(ply) or (not ply:Alive() and not GK.IsDowned(ply)) then return C.Gored end
    if GK.IsDowned(ply) then return C.NeonPink end
    if GK.IsImpaled(ply) or GK.IsCrawling(ply) then return C.Crawl end
    if GK.InMenu(ply) then return C.Menu end
    if not GK.IsChipOnline(ply) or GK.IsHurt(ply) or GK.IsRagdolled(ply) or (GK.IsStaggered and GK.IsStaggered(ply)) then return C.Hurt end
    if GK.HasBuff(ply, "gooped") then return GK.BuffInfo.gooped.color end -- slimed with a crushed grub
    if side and ply:GetNW2Int("gk_hand_" .. side, 0) > 0 then
        -- A gripping hand reddens as grip runs out, in six steps like WK's.
        local frac = math.Clamp(GK.HandGrip(ply, side) / GK.Config.StaminaMax, 0, 1)
        local t = 1 - math.ceil(frac * 6) / 6
        if t <= 0 then return C.Grip end
        local r = GK.Colors.GripOut or Color(220, 30, 30)
        return Color(Lerp(t, C.Grip.r, r.r), Lerp(t, C.Grip.g, r.g), Lerp(t, C.Grip.b, r.b), C.Grip.a)
    end
    if GK.IsEmoting(ply) then return C.Emote end
    return GK.HealthColor(ply)
end

-- Emotes use the base gamemode's `act` taunts.
function GM:PlayerShouldTaunt(ply, act)
    return not GK.IsDowned(ply) and not GK.IsRagdolled(ply)
end

function GM:PlayerStartTaunt(ply, act, length)
    if SERVER then
        ply:SetNW2Float("gk_emote_until", CurTime() + length)
        ply:SetNW2Int("gk_emote_act", act or 0)
    end
end

-- Menus: clients report when they have a cursor/menu open so others see blue hands.
if SERVER then
    util.AddNetworkString("gk_menu")
    net.Receive("gk_menu", function(_, ply)
        ply:SetNW2Bool("gk_in_menu", net.ReadBool())
    end)
else
    local last = false
    timer.Create("GK_MenuState", 0.25, 0, function()
        local open = vgui.CursorVisible() or gui.IsGameUIVisible() or gui.IsConsoleVisible()
        if open ~= last then
            last = open
            net.Start("gk_menu")
            net.WriteBool(open)
            net.SendToServer()
        end
    end)
end

-- For the player model (visor headband + hologram hands), client or server:
--   GK.PlayerVisuals(ply) -> {
--     visor = Color   health colour (white 100 .. green .. yellow .. orange .. dark red,
--                     neon pink downed, grey gored)
--     handL = Color, handR = Color   action colour per hand (orange gripping,
--                     green emote, light red stunned/hurt, pink impaled/crawling,
--                     blue in menus, slime green with the grub; else the health colour)
--     gripL = 0/1/2, gripR = 0/1/2   0 idle, 1 gripping a surface, 2 holding something
--     chipOnline = bool, downed = bool, gored = bool, impaled = bool,
--     expression = string  the hologram mouth (GK.Expression): "neutral", "grin",
--                     "laugh", "wink", "rage", "taunt", "shy", "determined",
--                     "worried", "strain", "panicked", "pain", "scream", "stunned", "dead"
--     emote = string or nil   the hand emote playing (GK.Emotes id: "middle",
--                     "sixseven", "shy", "vulcan", "wave", "thumbsup", ...) }
function GK.PlayerVisuals(ply)
    local visor = GK.HealthColor(ply)
    if GK.IsGored(ply) or (not ply:Alive() and not GK.IsDowned(ply)) then visor = GK.Colors.Gored
    elseif GK.IsDowned(ply) then visor = GK.Colors.NeonPink end
    return {
        visor = visor,
        handL = GK.HandColor(ply, "l"), handR = GK.HandColor(ply, "r"),
        gripL = ply:GetNW2Int("gk_hand_l", 0), gripR = ply:GetNW2Int("gk_hand_r", 0),
        chipOnline = GK.IsChipOnline(ply), downed = GK.IsDowned(ply), gored = GK.IsGored(ply),
        impaled = GK.IsImpaled(ply),
        expression = GK.Expression(ply),
        emote = GK.EmoteOf and GK.EmoteOf(ply) and ply:GetNW2String("gk_emote_id", "") or nil,
    }
end

-- The hologram mouth's expression, most urgent first.
local GRIN_ACTS = { [ACT_GMOD_TAUNT_LAUGH] = true, [ACT_GMOD_TAUNT_CHEER] = true, [ACT_GMOD_GESTURE_AGREE] = true }
function GK.Expression(ply)
    if GK.IsGored(ply) or (not ply:Alive() and not GK.IsDowned(ply)) then return "dead" end
    if GK.IsImpaled(ply) or ply:GetNW2Bool("gk_grabbed", false) then return "scream" end
    if ply:GetVelocity().z < -650 and not ply:OnGround() then return "scream" end -- a long fall
    if not GK.IsChipOnline(ply) or GK.IsRagdolled(ply) then return "stunned" end
    if GK.IsDowned(ply) or GK.IsHurt(ply) then return "pain" end
    if GK.IsEmoting(ply) then
        local e = GK.EmoteOf and GK.EmoteOf(ply)
        if e then return e.expression end
        return GRIN_ACTS[ply:GetNW2Int("gk_emote_act", 0)] and "grin" or "taunt"
    end
    if ply:GetNW2Float("gk_kill_until", 0) > CurTime() then return "grin" end
    -- The gas coming up close under you in a run.
    local a = GK.ArenaOf and GK.ArenaOf(ply) or 0
    if a ~= 0 then
        local gas = GetGlobal2Float("gk_arena" .. a .. "_gas", -math.huge)
        if ply:GetPos().z - gas < 220 then return "panicked" end
    end
    local hanging = ply:GetNW2Int("gk_hand_l", 0) == 1 or ply:GetNW2Int("gk_hand_r", 0) == 1
    if hanging then
        local g = GK.Stamina(ply) / GK.Config.StaminaMax
        if g < 0.3 then return "strain" end
        if g < 0.6 then return "worried" end
        if ply:GetVelocity().z > 120 then return "determined" end -- pulling up
    end
    return "neutral"
end

if SERVER then
    -- A kill gets a grin for a few seconds.
    hook.Add("PlayerDeath", "GK_KillGrin", function(victim, inflictor, attacker)
        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            attacker:SetNW2Float("gk_kill_until", CurTime() + 3)
        end
    end)
end
