-- Sandbox guard. gKnuckle derives from Sandbox, and hiding the spawn menu on the
-- client (sh_emotes.lua) doesn't stop the server-side Sandbox commands: any
-- client can still run gm_spawn / gm_spawnsent / gm_giveswep / gmod_tool /
-- noclip from the console. That lets players noclip or physgun to a gk_finish
-- (CrabCoin rewards), spawn Spawnable entities like gk_roach or gk_item_* (roach
-- bank / backpack currency), or spam props to lag the server.
-- With gk_sandbox_admin_only 1 (the default), only admins get Sandbox spawning,
-- tools, the physgun/toolgun loadout and noclip (noclip also works with sv_cheats 1).
-- Set it to 0 to go back to stock Sandbox rules.
local cvGuard = CreateConVar("gk_sandbox_admin_only", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Only admins may use Sandbox spawning, tools, physgun and noclip")

GK.SandboxGuard = GK.SandboxGuard or {}

-- true = this player is allowed Sandbox powers.
function GK.SandboxGuard.Allowed(ply)
    if not cvGuard:GetBool() then return true end
    return not IsValid(ply) or GK.HasAccess(ply, "gknuckle.sandbox")
end

local function deny(ply)
    if not GK.SandboxGuard.Allowed(ply) then return false end
end

for _, h in ipairs({ "PlayerSpawnProp", "PlayerSpawnRagdoll", "PlayerSpawnEffect", "PlayerSpawnVehicle",
    "PlayerSpawnNPC", "PlayerSpawnSENT", "PlayerSpawnSWEP", "PlayerGiveSWEP", "PlayerSpawnObject",
    "CanTool", "CanProperty", "CanDrive" }) do
    hook.Add(h, "GK_SandboxGuard", deny)
end

-- L1 defence in depth: no physgun grabs, and no picking up the physgun/toolgun, for
-- players without gknuckle.sandbox (another addon's hook returning true can't hand them out).
hook.Add("PhysgunPickup", "GK_SandboxGuard", function(ply) if not GK.SandboxGuard.Allowed(ply) then return false end end)
hook.Add("PlayerCanPickupWeapon", "GK_SandboxGuard", function(ply, wep)
    local c = IsValid(wep) and wep:GetClass()
    if (c == "weapon_physgun" or c == "gmod_tool") and not GK.SandboxGuard.Allowed(ply) then return false end
end)

hook.Add("PlayerNoClip", "GK_SandboxGuard", function(ply, desired)
    if not desired then return end -- always allow turning noclip off
    if GetConVar("sv_cheats"):GetBool() then return end
    if not GK.SandboxGuard.Allowed(ply) then return false end
end)
