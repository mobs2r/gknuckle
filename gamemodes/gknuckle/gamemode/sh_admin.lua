-- Admin permissions through CAMI, so ULX/ULib, SAM, ServerGuard, sAdmin (or plain
-- usergroups with no admin mod) all decide who may use gKnuckle's admin powers.
-- With no admin mod, CAMI's fallback uses each privilege's MinAccess below.
-- Above all of that sits the owner tier and Omerta's access roles (checked first):
--   gk_owner_steamids  comma-separated SteamID64s with every gKnuckle privilege
--                      (default: mobs2r, 76561199041513241)
--   GET /api/private/access-role/<steamid64> (Omerta, planned) -> { role = "owner"|"admin"|"moderator"|null }
--     owner: everything; admin: every MinAccess "admin" privilege; moderator: ROLE_MOD below.
--     Signed (sv_apiauth.lua) on the pinned economy origin, cached 5 min. Any failure
--     grants nothing extra (fail closed to the convar + CAMI). Roles only ever add access.
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
    { Name = "gknuckle.bans_admin",     MinAccess = "superadmin", Description = "gk_bans_flush" },
    { Name = "gknuckle.bans_view",      MinAccess = "admin",      Description = "gk_bans_status" },
    { Name = "gknuckle.moderate",       MinAccess = "admin",      Description = "gk_mod_kick, gk_community_mute / unmute (COMMUNiTY relay)" },
}
-- What an Omerta "moderator" gets: kick, relay mutes, COMMUNiTY status and ban status.
local ROLE_MOD = { ["gknuckle.moderate"] = true, ["gknuckle.community_admin"] = true, ["gknuckle.bans_view"] = true }
local MIN = {}
for _, p in ipairs(GK.Privileges) do
    MIN[p.Name] = p.MinAccess
    CAMI.RegisterPrivilege(p)
end

-- Synchronous answer for a privilege. The console always has access. Admin mods that
-- answer CAMI synchronously (ULX, SAM, plain fallback) are used directly; one that only
-- answers asynchronously gets an async query, and until it replies the cached answer
-- (default: deny) is used, so a slow admin mod never grants by accident.
local function roleGrants(role, priv)
    if role == "owner" then return true end
    if role == "admin" then return MIN[priv] == "admin" or MIN[priv] == "user" or ROLE_MOD[priv] == true end
    if role == "moderator" then return ROLE_MOD[priv] == true end
    return false
end

if SERVER then
    local cvOwners = CreateConVar("gk_owner_steamids", "76561199041513241", { FCVAR_ARCHIVE, FCVAR_PROTECTED },
        "SteamID64s (comma-separated) with full gKnuckle owner access")
    local cvRoles = CreateConVar("gk_access_roles", "1", { FCVAR_ARCHIVE }, "Ask Omerta /api/private/access-role for owner/admin/moderator roles")
    local owners, ownersRaw = {}, nil
    function GK.IsOwnerSteamID(sid)
        local raw = cvOwners:GetString()
        if raw ~= ownersRaw then
            ownersRaw, owners = raw, {}
            for s in string.gmatch(raw, "[^,%s]+") do if string.match(s, "^7656119%d+$") and #s == 17 then owners[s] = true end end
        end
        return owners[sid] == true
    end

    local roleCache = {} -- sid -> { role, expires }
    local ROLES = { owner = true, admin = true, moderator = true }
    function GK.AccessRole(ply)
        local sid = ply:SteamID64()
        if not sid or ply:IsBot() then return nil end
        -- The owner tier needs a Steam-verified SteamID (no -insecure / pending-auth spoofing).
        if GK.IsOwnerSteamID(sid) and (ply:IsFullyAuthenticated() or game.SinglePlayer() or ply:IsListenServerHost()) then return "owner" end
        local c = roleCache[sid]
        local fresh = c and c.expires > CurTime()
        if not fresh and cvRoles:GetBool() and not (c and c.asking) and GK.ApiAuth and ply:IsFullyAuthenticated() then
            local key, api = GetConVar("gk_economy_key"), GetConVar("gk_economy_api")
            if key and api and GK.ApiAuth.ParseKey(key:GetString()) then -- signed calls only, never the legacy secret
                roleCache[sid] = { role = c and c.role, expires = c and c.expires or 0, asking = true }
                GK.ApiAuth.Request(api:GetString(), key:GetString(), "GET", "/api/private/access-role/" .. sid, nil, function(code, data)
                    local role = (code == 200 and ROLES[data.role]) and data.role or nil -- fail closed
                    roleCache[sid] = { role = role, expires = CurTime() + (code == 200 and 300 or 60) }
                    if IsValid(ply) then
                        ply.GK_Access = nil
                        ply:SetNW2String("gk_role", GK.IsOwnerSteamID(sid) and "owner" or (role or ""))
                    end
                end, "access-role")
            end
        end
        return c and c.expires > CurTime() and c.role or nil
    end
    hook.Add("PlayerAuthed", "GK_AccessRole", function(ply)
        if not IsValid(ply) then return end
        ply:SetNW2String("gk_role", (GK.IsOwnerSteamID(ply:SteamID64() or "") and ply:IsFullyAuthenticated()) and "owner" or "")
        GK.AccessRole(ply)
    end)
    concommand.Add("gk_whois_role", function(ply, _, args)
        if not GK.RequireAccess(ply, "gknuckle.moderate") then return end
        for _, p in ipairs(player.GetHumans()) do
            local line = ("%s %s role=%s"):format(p:SteamID64(), p:Nick(), tostring(GK.AccessRole(p) or "-"))
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
    end)
end

function GK.HasAccess(ply, priv)
    if not IsValid(ply) then return SERVER end
    if not ply:IsPlayer() then return false end
    -- Owner tier and Omerta roles first. Server: the convar and the cached lookup.
    -- Client: the server-set NW2 role (UI only; every power is enforced server-side).
    local role
    if SERVER then role = GK.AccessRole(ply) else role = ply:GetNW2String("gk_role", "") end
    if roleGrants(role, priv) then return true end
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
