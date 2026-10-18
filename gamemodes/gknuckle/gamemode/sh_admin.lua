-- Admin permissions through CAMI, so ULX/ULib, SAM, ServerGuard, sAdmin (or plain
-- usergroups with no admin mod) all decide who may use gKnuckle's admin powers.
-- With no admin mod, CAMI's fallback uses each privilege's MinAccess below.
if SERVER then AddCSLuaFile() AddCSLuaFile("sh_cami.lua") end
include("sh_cami.lua")

GK = GK or {}
GK.Privileges = {
    { Name = "gknuckle.sandbox",        MinAccess = "admin",      Description = "Sandbox spawning, tools, physgun and noclip (gk_sandbox_admin_only 1)" },
    { Name = "gknuckle.spawnmenu",      MinAccess = "admin",      Description = "Open the Sandbox spawn menu with gk_spawnmenu 1" },
    { Name = "gknuckle.spawn_creature", MinAccess = "admin",      Description = "gk_spawn_creature: spawn gKnuckle creatures" },
    { Name = "gknuckle.runs",           MinAccess = "admin",      Description = "gk_run, gk_level, gk_arena_start/clear/gas, gk_vacuum_fire, gk_setup_area" },
    { Name = "gknuckle.face",           MinAccess = "admin",      Description = "gk_face_summon, gk_face_setstate" },
    { Name = "gknuckle.hazards_debug",  MinAccess = "admin",      Description = "gk_hazards_here" },
    { Name = "gknuckle.pack_status",    MinAccess = "admin",      Description = "gk_pack_status" },
    { Name = "gknuckle.economy_admin",  MinAccess = "superadmin", Description = "Give or take CrabCoin (ulx gkgive / gktake)" },
    { Name = "gknuckle.community_admin",MinAccess = "superadmin", Description = "gk_community_status" },
    { Name = "gknuckle.bans_admin",     MinAccess = "superadmin", Description = "gk_bans_status, gk_bans_flush" },
}
local MIN = {}
for _, p in ipairs(GK.Privileges) do
    MIN[p.Name] = p.MinAccess
    CAMI.RegisterPrivilege(p)
end

-- Synchronous answer for a privilege. The console always has access. Admin mods that
-- answer CAMI synchronously (ULX, SAM, plain fallback) are used directly; one that only
-- answers asynchronously gets an async query, and until it replies the cached answer
-- (default: deny) is used, so a slow admin mod never grants by accident.
function GK.HasAccess(ply, priv)
    if not IsValid(ply) then return SERVER end
    if not ply:IsPlayer() then return false end
    ply.GK_Access = ply.GK_Access or {}
    local ok, has = pcall(CAMI.PlayerHasAccess, ply, priv, nil, nil, { Fallback = MIN[priv] or "superadmin" })
    if ok and has ~= nil then
        ply.GK_Access[priv] = has and true or false
        return has and true or false
    end
    ply.GK_AccessAsking = ply.GK_AccessAsking or {}
    if not ply.GK_AccessAsking[priv] then
        ply.GK_AccessAsking[priv] = true
        CAMI.PlayerHasAccess(ply, priv, function(answer)
            if not IsValid(ply) then return end
            ply.GK_Access = ply.GK_Access or {}
            ply.GK_Access[priv] = answer and true or false
            ply.GK_AccessAsking[priv] = nil
        end, nil, { Fallback = MIN[priv] or "superadmin" })
    end
    return ply.GK_Access[priv] == true
end

-- Group changes (ULX "ulx adduser", SAM rank changes) invalidate the cache.
hook.Add("CAMI.PlayerUsergroupChanged", "GK_AccessReset", function(ply) if IsValid(ply) then ply.GK_Access = nil end end)

-- For a concommand: true if allowed, otherwise tells the caller and returns false.
function GK.RequireAccess(ply, priv)
    if GK.HasAccess(ply, priv) then return true end
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[gKnuckle] you need " .. priv .. " for that") end
    return false
end
