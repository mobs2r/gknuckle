GM.Name = "gKnuckle"
GM.Author = "mobs2r"
GM.Email = ""
GM.Website = "omerta.chat"
GM.TeamBased = false

DeriveGamemode("sandbox")

GK = GK or {}
include("sh_admin.lua") -- CAMI privileges (ULX/SAM/ServerGuard/sAdmin or plain usergroups)
include("sh_ulx_gk.lua") -- ulx gkgive/gktake/gkarena/gkpack, only when ULX is installed

-- Merged into the existing table on a Lua refresh, so files that cached
-- `local C = GK.Config` see new keys too (no "nil config value" errors).
local config = {
    -- Movement matches CS:GO (knife-out speed, shift walks, its accel/friction
    -- and gravity set in init.lua; take-off cap, jump slowdown and duck spam
    -- in sh_movement.lua). White Knuckle's lift comes from the grip launch.
    WalkSpeed = 250,
    RunSpeed = 130,           -- shift = walk, like CS:GO
    SprintSpeed = 330,        -- Alt = sprint (WK has one); costs stamina, widens the view
    SprintDrain = 6,          -- stamina/s while sprinting
    CrouchSpeed = 85,
    JumpPower = 301.993,      -- CS:GO's sv_jump_impulse: ~57u jump at 800 gravity

    GripRange = 180,
    JumpBoostForce = 580,     -- grip launch; 500 at the old 600 gravity, scaled to keep WK's lift

    StaminaMax = 100,
    StaminaDrainPerTick = 0.4,
    StaminaRegenPerTick = 2,
    StaminaDrainJump = 5,        -- grip-jump off a wall, per hand on the wall (WK: 0.5 of 10)
    StaminaJumpCost = 8,         -- every jump off the ground (autohop included)
    StaminaRegenDelay = 1,       -- rest this long after a jump / letting go before it comes back
    GripDrainOneHand = 10,       -- stamina/s hanging by one hand (WK: ~10 s from full)
    GripDrainTwoHands = 5,       -- stamina/s hanging by both (WK: ~20 s)
    GripHangRegen = 7.5,         -- stamina/s back while hanging with your feet on the ground
    GripOutLockout = 1,          -- slipped off from no grip: hands can't grab again for this long
    GripOutRefill = 10,          -- ...then they get this much back (WK: grip-out isn't "must land")
    GripGroundRegen = 9,         -- grip/s back for a free hand with your feet on the ground (WK ~9)
    GripAirRegen = 0.75,         -- grip/s back for a free hand in the air, after GripAirDelay (WK)
    GripAirDelay = 0.17,
    GripReleaseLock = 0.25,      -- a hand that lets go can't grab again for this long (WK)
    StaminaTickRate = 0.1,

    PlayerPushForce = 5000,

    -- Props: light ones lift like an HL pickup, heavier ones drag like the
    -- White Knuckle chair/crates, very heavy ones also hold your weight.
    LiftMass = 35,
    ThrowSpeed = 700,          -- kick while holding: HL-style throw
    DragImpulse = 400,         -- max push per tick on a dragged prop
    HoldDistance = 55,

    -- Gravity surge pickup: grav-gun strength for a while
    SurgeTime = 30,
    SurgeLiftMass = 250,
    SurgeThrowSpeed = 2200,
    SurgeDragMultiplier = 6,

    -- Legs
    LegHealth = 40,           -- damage to legs before they come off
    LeglessWalkSpeed = 60,

    -- Xenium link (stuns knock it offline)
    StunRadius = 420,
    StunDuration = 6,

    -- Bricks
    BrickRagdollSpeed = 450,  -- impact speed that knocks a player down
    RagdollTime = 3,

    -- Downed / revive
    BleedOutTime = 30,
    ReviveTime = 3,
    ReviveRange = 90,
    ReviveHealth = 25,
    DownedCrawlSpeed = 40,
    GoreDamage = 60,          -- a single hit this big while downed (or a blast kill) gores

    -- Kick
    KickRange = 70,
    KickCooldown = 1,
    KickForce = 450,
    KickBoost = 380,          -- kick-boost launch speed (a boom bug's blast is 520)
    KickBoostReach = 90,      -- how far below your feet the floor can be

    -- Rebar impalement (sh_impale.lua)
    SpikeImpaleSpeed = 250,        -- landing speed that impales a stunned, empty-handed climber
    RagdollImpaleSpeed = 220,      -- same for a ragdolled body coming down on a point
    ImpaleWeightFactor = 0.06,     -- each unit of carried weight lowers that speed by ~6%
    ImpaleLookCone = 45,           -- look is held within +/-45 deg (a 90 deg cone) of the bar
    ImpaleDamage = 15,
    SpikeEscapeTime = 2.5,         -- forwards: hold jump this long to drag yourself off
    ImpalePullTime = 3,            -- backwards: both empty hands pulling
    ImpaleOneHandFactor = 3,       -- one hand takes this many times longer
    ImpalePullWeightFactor = 0.12, -- each unit of carried weight slows the pull by 12% (double for one hand)
    SpikeBleedTime = 6,

    -- Thrown rebar: White Knuckle's Projectile_Rebar speed (50 m/s), flying dead straight
    RebarThrowSpeed = 1970,
    RebarGravity = 0,
    RebarDamage = 25,
}
GK.Config = GK.Config or {}
table.Merge(GK.Config, config)

-- 0 = grip any wall, 1 = ledges only (rebar handholds and props always work).
GK.ClimbCarry = CreateConVar("gk_climb_carry", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "WK climb-jump chaining: a fresh grab keeps your momentum for a moment", 0, 1)
-- 1 is White Knuckle's rule (the default): hands take handholds and ledges
-- only, never a bare wall (Slug Grub goop still grabs anything).
GK.ClimbMode = CreateConVar("gk_climb_mode_wk", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
    "0 = grip any wall, 1 = handholds and ledges only (White Knuckle)", 0, 1)

GK.Weapons = {
    Mind = "gk_mind",
}

function GK.IsChipOnline(ply)
    return IsValid(ply) and ply:GetNW2Float("gk_chip_offline_until", 0) <= CurTime()
end

function GK.HasLegs(ply)
    return IsValid(ply) and not ply:GetNW2Bool("gk_legless", false)
end

-- One leg gone (sv_dismember.lua): no kicking, and no walking about on the
-- ground (hop instead); in the air you still steer, so bunnyhops still go.
function GK.OneLegged(ply)
    return IsValid(ply) and GK.HasLegs(ply) and (ply:GetNW2Bool("gk_leg_l_gone", false) or ply:GetNW2Bool("gk_leg_r_gone", false))
end

function GK.IsRagdolled(ply)
    return IsValid(ply) and IsValid(ply:GetNW2Entity("gk_ragdoll"))
end

function GK.HasSurge(ply)
    return IsValid(ply) and ply:GetNW2Float("gk_surge_until", 0) > CurTime()
end

function GK.Stamina(ply)
    return ply:GetNW2Float("gk_stamina", GK.Config.StaminaMax)
end

-- Grip: each hand has its own meter, like WK's two gloves (one red hand, one
-- white). GK.Stamina is the two averaged (kept in gk_stamina) for whatever
-- just wants "grip left": jump costs, melee, the HUD, food refills both.
function GK.HandGrip(ply, side) return ply:GetNW2Float("gk_gm_" .. side, GK.Stamina(ply)) end
function GK.SetHandGrip(ply, side, v)
    ply:SetNW2Float("gk_gm_" .. side, math.Clamp(v, 0, GK.Config.StaminaMax))
    ply:SetNW2Float("gk_stamina", (GK.HandGrip(ply, "l") + GK.HandGrip(ply, "r")) / 2)
end
function GK.SetStamina(ply, v) GK.SetHandGrip(ply, "l", v) GK.SetHandGrip(ply, "r", v) end
function GK.AddStamina(ply, d)
    for _, side in ipairs({ "l", "r" }) do GK.SetHandGrip(ply, side, GK.HandGrip(ply, side) + d) end
end

-- Reach: WK's is 2 m (about 80 u). Runs use that; the hub keeps the longer
-- mind-reach its training towers were built around.
GK.RunReach = CreateConVar("gk_reach_run", "90", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Grip reach inside a run (units; WK 2 m is about 80)")
function GK.GripRange(ply)
    local base = (GK.ArenaOf and GK.ArenaOf(ply) ~= 0) and GK.RunReach:GetFloat() or GK.Config.GripRange
    return base * (GK.BuffMult and GK.BuffMult(ply, "reach") or 1)
end

include("sh_buffs.lua")
include("sh_ladders.lua")
include("sh_movement.lua")
include("sh_states.lua")
include("sh_emotes.lua")
include("sh_perks.lua")
include("sh_handholds.lua")
include("sh_stagger.lua")
include("sh_melee.lua")
include("sh_catch.lua")
include("sh_impale_prone.lua")
include("sh_crystalgore.lua")
include("sh_keys.lua")
include("sh_items.lua")
include("sh_items_more.lua")
include("sh_legs.lua") -- after the item system: it registers the leg items
include("sh_roaches.lua")
include("sh_impale.lua")
include("sh_squads.lua")
include("sh_hub.lua")
include("sh_score.lua")
include("sh_titlecard.lua")
include("sh_lift.lua")
include("sh_announcer.lua")
include("sh_selftest.lua")
include("sh_impaletest.lua")
include("sh_arenatest.lua")
include("sh_laddertest.lua")
include("sh_roachtest.lua")
include("sh_heldtest.lua")
include("sh_creaturetest.lua")
include("sh_venttest.lua")
include("sh_bagtest.lua")
include("sh_climbtest.lua")
include("sh_birthtest.lua")
include("sh_meleetest.lua")
include("sh_vactest.lua")
include("sh_looktest.lua")
include("sh_ledgetest.lua")
include("sh_catchtest.lua")
include("sh_fplegtest.lua")
include("sh_emotetest.lua")
include("sh_pitontest.lua")
include("sh_goretest.lua")
include("sh_vendtest.lua")
include("sh_ljtest.lua")
include("sh_racetest.lua")
include("sh_masstest.lua")
include("sh_griptest.lua")
include("sh_hazardtest.lua")
include("sh_econtest.lua")
include("sh_kicktest.lua")
include("sh_teethtest.lua")
include("sh_announcetest.lua")
include("sh_statustest.lua")
include("sh_backuptest.lua")
include("sh_mothtest.lua")
include("sh_rulestest.lua")
include("sh_modetest.lua")
include("sh_padmodetest.lua")
include("sh_sprinttest.lua")
include("sh_invtest.lua")
include("sh_beasttest.lua")
include("sh_ghosttest.lua")
include("sh_facetest.lua")
include("sh_nightmaretest.lua")
include("sh_pausetest.lua")
include("sh_husk.lua")

-- The hub layout written with the map (data_static/gknuckle/hub.json), on both realms.
function GK.HubLayout()
    if GK._hubLayout == nil then GK._hubLayout = util.JSONToTable(file.Read("data_static/gknuckle/hub.json", "GAME") or "") or false end
    return GK._hubLayout or nil
end

-- Layout json (SMD space) -> model space: studiomdl yaws compiled rooms 90 degrees,
-- so (x, y) -> (-y, x). Shared so client code (handholds, hazards) can use it too.
function GK.LevelToModel(p) return Vector(-p[2], p[1], p[3]) end

-- One parsed copy of a room's layout json per realm (six files used to parse the same
-- 0.2-1.2 MB file on every spawn, 16 s round starts). Callers must not modify the
-- table. "edges" (flat x0,y0,z0,x1,y1,z1 per ledge segment, from make_edge_holds.py)
-- are expanded into handhold boxes here so every reader sees the same handholds.
local layoutCache = {}
function GK.LevelLayout(piece)
    local lay = layoutCache[piece]
    if lay then return lay end
    lay = util.JSONToTable(file.Read("data_static/gknuckle/levels/" .. piece .. ".json", "GAME") or "") or {}
    local e = lay.edges
    if e and #e >= 6 then
        local hh = lay.handholds or {}
        local n = #hh
        for i = 1, #e - 5, 6 do
            local x0, y0, z0, x1, y1, z1 = e[i], e[i + 1], e[i + 2], e[i + 3], e[i + 4], e[i + 5]
            n = n + 1
            hh[n] = { name = "edge", mins = { math.min(x0, x1) - 5, math.min(y0, y1) - 5, math.min(z0, z1) - 6 }, maxs = { math.max(x0, x1) + 5, math.max(y0, y1) + 5, math.max(z0, z1) + 3 } }
        end
        lay.handholds = hh
        lay.edges = nil
    end
    layoutCache[piece] = lay
    return lay
end
