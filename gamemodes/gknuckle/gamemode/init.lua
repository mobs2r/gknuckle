AddCSLuaFile("cl_init.lua")
AddCSLuaFile("sh_titlecard.lua")
AddCSLuaFile("sh_lift.lua")
AddCSLuaFile("sh_announcer.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("sh_ladders.lua")
AddCSLuaFile("sh_movement.lua")
AddCSLuaFile("sh_states.lua")
AddCSLuaFile("sh_keys.lua")
AddCSLuaFile("sh_buffs.lua")
AddCSLuaFile("sh_items.lua")
AddCSLuaFile("sh_items_more.lua")
AddCSLuaFile("sh_roaches.lua")
AddCSLuaFile("sh_impale.lua")
AddCSLuaFile("sh_squads.lua")
AddCSLuaFile("cl_inventory.lua")
AddCSLuaFile("cl_post.lua")
AddCSLuaFile("cl_status.lua")
AddCSLuaFile("cl_pausemenu.lua")
AddCSLuaFile("sh_selftest.lua")
AddCSLuaFile("sh_impaletest.lua")
AddCSLuaFile("sh_arenatest.lua")
AddCSLuaFile("sh_laddertest.lua")
AddCSLuaFile("sh_roachtest.lua")
AddCSLuaFile("sh_heldtest.lua")
AddCSLuaFile("sh_looktest.lua")
AddCSLuaFile("sh_ledgetest.lua")
AddCSLuaFile("sh_catchtest.lua")
AddCSLuaFile("sh_creaturetest.lua")
AddCSLuaFile("sh_venttest.lua")
AddCSLuaFile("sh_bagtest.lua")
AddCSLuaFile("sh_climbtest.lua")
AddCSLuaFile("sh_birthtest.lua")
AddCSLuaFile("sh_meleetest.lua")
AddCSLuaFile("sh_vactest.lua")
AddCSLuaFile("sh_fplegtest.lua")
AddCSLuaFile("sh_emotetest.lua")
AddCSLuaFile("sh_pitontest.lua")
AddCSLuaFile("sh_goretest.lua")
AddCSLuaFile("sh_vendtest.lua")
AddCSLuaFile("sh_ljtest.lua")
AddCSLuaFile("sh_racetest.lua")
AddCSLuaFile("sh_masstest.lua")
AddCSLuaFile("sh_griptest.lua")
AddCSLuaFile("sh_hazardtest.lua")
AddCSLuaFile("sh_econtest.lua")
AddCSLuaFile("sh_kicktest.lua")
AddCSLuaFile("sh_teethtest.lua")
AddCSLuaFile("sh_announcetest.lua")
AddCSLuaFile("sh_statustest.lua")
AddCSLuaFile("sh_backuptest.lua")
AddCSLuaFile("sh_mothtest.lua")
AddCSLuaFile("sh_rulestest.lua")
AddCSLuaFile("sh_modetest.lua")
AddCSLuaFile("sh_padmodetest.lua")
AddCSLuaFile("sh_sprinttest.lua")
AddCSLuaFile("sh_invtest.lua")
AddCSLuaFile("sh_beasttest.lua")
AddCSLuaFile("sh_ghosttest.lua")
AddCSLuaFile("sh_facetest.lua")
AddCSLuaFile("sh_nightmaretest.lua")
AddCSLuaFile("sh_pausetest.lua")
AddCSLuaFile("cl_hands.lua")
AddCSLuaFile("cl_hud.lua")
AddCSLuaFile("cl_regionsky.lua")
AddCSLuaFile("cl_drawhh.lua")
AddCSLuaFile("cl_roomlights.lua")
AddCSLuaFile("cl_mirror.lua")

include("sv_apiauth.lua") -- signed id:secret API calls (pure-Lua HMAC-SHA256)
include("sv_pack.lua") -- playable-pack: mounts the server copy before the rest loads
include("shared.lua")
include("sv_economy.lua")
include("sv_sandbox_guard.lua")
include("sv_explode.lua")
include("sv_inventory.lua")
include("sv_ragdoll.lua")
include("sv_dismember.lua")
include("sv_downed.lua")
include("sv_brainchip.lua")
include("sv_round.lua")
include("sv_shop.lua")
include("sv_arena.lua")
include("sv_hub.lua")
include("sv_creatures.lua")
include("sv_threats.lua")
include("sv_hazards.lua")
include("sv_backpack.lua")
include("sv_mapsetup.lua")
include("sv_levels.lua")
include("sv_wk_arena.lua")
include("sv_hostname.lua")
include("sv_birthing.lua")
include("sv_bans.lua")       -- Omerta global-ban check at connect + reporting ULX/SAM bans
include("sv_chatbridge.lua") -- COMMUNiTY: in-game chat <-> the Omerta #gknuckle room (bot API)

-- Players joining a dedicated server download the addon (models, textures,
-- sounds, the gk_style map) from its Workshop item.
resource.AddWorkshop("3479529954") -- the original gKnuckle item (3815586706 was a mistaken duplicate)

-- Required Workshop items: the White Knuckle Prop Pack and NPCs Pack.
resource.AddWorkshop("3817814674")
resource.AddWorkshop("3818830408")
-- White Knuckle's UI fonts and the hand sprites now ship in playable-pack.gma
-- (cl_pack.lua), so they're no longer sent with resource.AddFile.

local C = GK.Config

function GM:PlayerInitialSpawn(ply)
    GK.SetStamina(ply, C.StaminaMax)
    GK.Economy.Refresh(ply)
end

-- Built on Sandbox, so the spawn menu, physgun and toolgun all work (and
-- toolgun addons like Junk Jet find weapons/gmod_tool).
local cvTools = CreateConVar("gk_sandbox_tools", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Give physgun + toolgun on spawn")

-- CS:GO movement: its accel/friction and its 800 gravity (White Knuckle's
-- lift lives in the grip launch instead, JumpBoostForce).
local MOVEMENT = {
    sv_accelerate = 5.5, sv_airaccelerate = 12, sv_friction = 5.2,
    sv_stopspeed = 80, sv_gravity = 800,
}
local function applyMovement()
    for cv, v in pairs(MOVEMENT) do RunConsoleCommand(cv, tostring(v)) end
    -- KZ: air strafing builds speed like a KZ/bhop server (gk_kz, sh_movement.lua).
    RunConsoleCommand("sv_airaccelerate", GK.KZ:GetBool() and "100" or "12")
end
hook.Add("Initialize", "GK_Movement", applyMovement)
cvars.AddChangeCallback("gk_kz", function() applyMovement() end, "GK_Movement")

function GM:PlayerSpawn(ply, transition)
    self.BaseClass.PlayerSpawn(self, ply, transition)

    ply:SetWalkSpeed(C.WalkSpeed)
    ply:SetRunSpeed(C.RunSpeed)
    ply:SetSlowWalkSpeed(C.SprintSpeed) -- Alt is our sprint (sh_movement.lua), not a slower walk
    ply:SetCrouchedWalkSpeed(C.CrouchSpeed / C.WalkSpeed)
    ply:SetJumpPower(C.JumpPower)
    GK.SetStamina(ply, C.StaminaMax)
    ply:SetNW2Float("gk_chip_offline_until", 0)
    ply:SetNW2Float("gk_busy_until", 0)
    GK.RestoreLegs(ply)
end

function GM:PlayerLoadout(ply)
    ply:StripWeapons()
    ply:Give(GK.Weapons.Mind)
    if cvTools:GetBool() and GK.SandboxGuard.Allowed(ply) then
        ply:Give("weapon_physgun")
        ply:Give("gmod_tool")
    end
    ply:SelectWeapon(GK.Weapons.Mind)
    return true
end

-- No arms means no c_arms: keep the base hands entity from ever appearing.
function GM:PlayerSetHandsModel(ply, ent)
    ent:SetNoDraw(true)
end

-- Minds battle it out: players always hurt players, whatever Sandbox's
-- sbox_playershurtplayers says (it's off by default on some servers).
function GM:PlayerShouldTakeDamage(ply, attacker)
    return not cvars.Bool("sbox_godmode", false)
end

function GM:GetFallDamage(ply, speed)
    return 0
end

function GM:PlayerDeathThink(ply)
    if ply.NextSpawnTime and ply.NextSpawnTime > CurTime() then return end
    if ply:KeyPressed(IN_ATTACK) or ply:KeyPressed(IN_JUMP) or ply:IsBot() then
        ply:Spawn()
    end
end
