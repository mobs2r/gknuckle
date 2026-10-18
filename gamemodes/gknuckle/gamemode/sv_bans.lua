-- Ban check layer for bans.gk.style (BANS_PLAN.md, API_SPEC.md §7).
-- Bans live in Omerta (core.is_globally_banned through the account mapping); there is no
-- separate gKnuckle bans table. This file asks the Illicit API at connect time and reports
-- bans made in game (ULX/ULib, SAM) so the bans.gk.style page and Omerta moderators see them.
--   POST /api/integrations/gknuckle/bans/check   { steam_id, owner_steam_id? } -> { banned, reason, until }
--   POST /api/integrations/gknuckle/bans/report  { event_id, action, steam_id, minutes, reason, admin_steam_id, source }
-- Signed like every other call (sv_apiauth.lua) with a gk:bans-scoped key.
-- server.cfg:
--   gk_bans_api       "https://illicit.up.railway.app"   (empty = off; must be on GK.ApiAuth.ORIGINS)
--   gk_bans_key       "<id>:<secret>"                     (empty = use gk_pack_key)
--   gk_bans_failmode  "open"                              ("closed" refuses joins it can't check)
-- Local ULX/SAM bans keep working on their own; this only adds the Omerta ones.

GK.Bans = GK.Bans or {}
local B = GK.Bans

local cvApi   = CreateConVar("gk_bans_api", "", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "Illicit API origin for Omerta ban checks (empty = off)")
local cvKey   = CreateConVar("gk_bans_key", "", { FCVAR_PROTECTED, FCVAR_DONTRECORD }, "id:secret with gk:bans scope (empty = gk_pack_key)")
local cvFail  = CreateConVar("gk_bans_failmode", "open", { FCVAR_ARCHIVE }, "open: let players in when the ban API can't answer; closed: refuse them")
local cvClean = CreateConVar("gk_bans_cache", "120", { FCVAR_ARCHIVE }, "Seconds a not-banned answer is reused", 10, 3600)
local cvSvName = CreateConVar("gk_bans_server", "", { FCVAR_ARCHIVE }, "Name reported with in-game bans (default: hostname)")

local function key()
    local k = cvKey:GetString()
    if k == "" then local pk = GetConVar("gk_pack_key") k = pk and pk:GetString() or "" end
    return k
end
local function enabled() return cvApi:GetString() ~= "" and key() ~= "" end
local function isSid(s) return isstring(s) and string.match(s, "^7656119%d%d%d%d%d%d%d%d%d%d$") ~= nil end

-- Keyed on "sid|owner" (N1): an answer for the bare account never satisfies a lookup that
-- also carries a family-share owner, and the owner is checked as its own account too.
local cache = {}   -- "sid|owner" -> { banned, reason, untilTs, expires }
local asking = {}  -- sid -> true while a check is in flight
local waiters = {} -- sid -> { fn, ... }

local function banMessage(e)
    local when = (e.untilTs and e.untilTs > 0) and (" until " .. os.date("!%Y-%m-%d %H:%M UTC", e.untilTs)) or ""
    return ("You are banned from Omerta%s.\nReason: %s\nAppeal at https://bans.gk.style"):format(when, e.reason ~= "" and e.reason or "not given")
end
B.Message = banMessage

-- cb(entry or nil): nil = couldn't find out.
function B.Lookup(sid, owner, cb)
    if not (isSid(owner) and owner ~= sid) then owner = nil end
    local ck = sid .. "|" .. (owner or "")
    local c = cache[ck]
    if c and c.expires > CurTime() then return cb and cb(c) end
    if cb then waiters[ck] = waiters[ck] or {} table.insert(waiters[ck], cb) end
    if asking[ck] then return end
    asking[ck] = true
    local body = { steam_id = sid }
    if owner then body.owner_steam_id = owner end -- family-shared alts
    GK.ApiAuth.Request(cvApi:GetString(), key(), "POST", "/api/integrations/gknuckle/bans/check", body, function(code, data)
        asking[ck] = nil
        local entry
        if code == 200 and isbool(data.banned) then
            local untilTs = tonumber(data["until"]) or 0
            entry = { banned = data.banned, reason = string.sub(tostring(data.reason or ""), 1, 160), untilTs = untilTs,
                expires = CurTime() + (data.banned and 300 or cvClean:GetFloat()) }
            if entry.banned and untilTs > 0 and untilTs < os.time() then entry.banned = false end
            cache[ck] = entry
        elseif code == 401 then
            print("[gKnuckle] ban API rejected the key (401): check gk_bans_key")
        end
        local list = waiters[ck] or {}
        waiters[ck] = nil
        for _, fn in ipairs(list) do fn(entry) end
    end, "gk_bans_api")
end

local function kickIfBanned(ply, entry)
    if IsValid(ply) and entry and entry.banned then
        print(("[gKnuckle] %s (%s) is banned on Omerta; kicking"):format(ply:Nick(), ply:SteamID64()))
        ply:Kick(banMessage(entry))
    end
end

-- Connect time. Never returns true (that would skip the server password).
hook.Add("CheckPassword", "GK_Bans", function(sid64)
    if not enabled() or not isSid(sid64) then return end
    local c = cache[sid64 .. "|"]
    if c and c.expires > CurTime() then
        if c.banned then return false, banMessage(c) end
        return
    end
    B.Lookup(sid64, nil, function(entry)
        if entry and entry.banned then kickIfBanned(player.GetBySteamID64(sid64), entry) end
    end)
    if cvFail:GetString() == "closed" then
        return false, "Checking your Omerta account... please reconnect in a few seconds."
    end
end)

-- Again once Steam has verified the account (also covers a hook elsewhere answering
-- CheckPassword with true first) and for family-shared accounts' owners.
hook.Add("PlayerAuthed", "GK_Bans", function(ply)
    if not enabled() or not IsValid(ply) or ply:IsBot() then return end
    local sid, owner = ply:SteamID64(), ply.OwnerSteamID64 and ply:OwnerSteamID64() or nil
    if not (isSid(owner) and owner ~= sid) then owner = nil end
    local function handle(entry)
        if entry then return kickIfBanned(ply, entry) end
        if cvFail:GetString() == "closed" and IsValid(ply) then ply:Kick("Couldn't check your Omerta account. Please reconnect.") end
    end
    B.Lookup(sid, owner, handle)
    -- N1: a family-shared licence's owner is checked as an account of its own as well,
    -- so the alt of a banned owner is kicked even if the API ignores owner_steam_id.
    if owner then B.Lookup(owner, nil, handle) end
end)

-- Reporting in-game bans ---------------------------------------------------------
local OUTBOX = "gknuckle/bans_outbox.json"
local outbox = util.JSONToTable(file.Read(OUTBOX, "DATA") or "") or {}
local function saveOutbox() file.CreateDir("gknuckle") file.Write(OUTBOX, util.TableToJSON(outbox)) end
local sending = false

local function pump()
    if sending or #outbox == 0 or not enabled() then return end
    local item = outbox[1]
    sending = true
    GK.ApiAuth.Request(cvApi:GetString(), key(), "POST", "/api/integrations/gknuckle/bans/report", item, function(code)
        sending = false
        item.tries = (item.tries or 0) + 1
        if (code >= 200 and code < 300) or (code >= 400 and code < 500 and code ~= 401 and code ~= 429) or item.tries >= 8 then
            table.remove(outbox, 1) -- done, refused for good, or given up on
        end
        saveOutbox()
    end, "gk_bans_api")
end
timer.Create("GK_BansOutbox", 15, 0, pump)

function B.Report(action, steamid, minutes, reason, admin, source)
    local sid = isSid(steamid) and steamid or util.SteamIDTo64(tostring(steamid or ""))
    if not isSid(sid) then return end
    local adminSid = (isentity(admin) and IsValid(admin)) and admin:SteamID64()
        or (isstring(admin) and (isSid(admin) and admin or util.SteamIDTo64(string.match(admin, "STEAM_%d:%d:%d+") or ""))) or nil
    local server = cvSvName:GetString() ~= "" and cvSvName:GetString() or GetHostName()
    table.insert(outbox, {
        event_id = GK.ApiAuth.EventId("ban_" .. action, sid),
        action = action, steam_id = sid,
        minutes = math.max(0, math.floor(tonumber(minutes) or 0)),
        reason = string.sub(tostring(reason or ""), 1, 160),
        admin_steam_id = isSid(adminSid) and adminSid or nil,
        source = source, server = string.sub(server, 1, 64),
    })
    if #outbox > 200 then table.remove(outbox, 1) end
    saveOutbox()
    for k in pairs(cache) do -- forget every answer involving this account, as player or owner
        local s, o = string.match(k, "^(%d*)|(%d*)$")
        if s == sid or o == sid then cache[k] = nil end
    end
    pump()
end

-- ULX / ULib: ban_data is ULib.bans[steamid] (unban = unix time or 0 for permanent).
hook.Add("ULibPlayerBanned", "GK_BansReport", function(steamid, data)
    data = istable(data) and data or {}
    local unban = tonumber(data.unban) or 0
    local minutes = unban > 0 and math.ceil((unban - os.time()) / 60) or 0
    B.Report("ban", steamid, minutes, data.reason, data.admin, "ulx")
end)
hook.Add("ULibPlayerUnBanned", "GK_BansReport", function(steamid, admin)
    B.Report("unban", steamid, 0, "", admin, "ulx")
end)
-- SAM (best effort: argument order per SAM's hooks; checked by type before use).
hook.Add("SAM.BannedPlayer", "GK_BansReport", function(ply, unbanDate, reason, adminSid)
    if not IsValid(ply) then return end
    local u = tonumber(unbanDate) or 0
    B.Report("ban", ply:SteamID64(), u > 0 and math.ceil((u - os.time()) / 60) or 0, reason, adminSid, "sam")
end)
hook.Add("SAM.BannedSteamID", "GK_BansReport", function(steamid, unbanDate, reason, adminSid)
    local u = tonumber(unbanDate) or 0
    B.Report("ban", steamid, u > 0 and math.ceil((u - os.time()) / 60) or 0, reason, adminSid, "sam")
end)
hook.Add("SAM.UnbannedSteamID", "GK_BansReport", function(steamid, adminSid)
    B.Report("unban", steamid, 0, "", adminSid, "sam")
end)

-- Find one player by SteamID64, SteamID or a unique part of their name.
function B.FindTarget(q)
    q = string.lower(string.Trim(tostring(q or "")))
    if q == "" then return nil end
    local hit
    for _, p in ipairs(player.GetHumans()) do
        if p:SteamID64() == q or string.lower(p:SteamID()) == q then return p end
        if string.find(string.lower(p:Nick()), q, 1, true) then
            if hit then return nil end -- ambiguous
            hit = p
        end
    end
    return hit
end

-- Moderators (Omerta role or gknuckle.moderate): kick with a reason. Can't kick the owner.
concommand.Add("gk_mod_kick", function(ply, _, args)
    if not GK.RequireAccess(ply, "gknuckle.moderate") then return end
    local target = B.FindTarget(args[1])
    if not IsValid(target) then if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, "[gKnuckle] no single player matches") end return end
    if GK.IsOwnerSteamID and GK.IsOwnerSteamID(target:SteamID64()) then return end
    local reason = string.sub(table.concat(args, " ", 2), 1, 120)
    print(("[gKnuckle] %s kicked %s (%s): %s"):format(IsValid(ply) and ply:Nick() or "console", target:Nick(), target:SteamID64(), reason))
    target:Kick(reason ~= "" and reason or "Kicked by a moderator")
end)

concommand.Add("gk_bans_status", function(ply)
    if not GK.RequireAccess(ply, "gknuckle.bans_view") then return end
    local n = 0 for _ in pairs(cache) do n = n + 1 end
    local msg = ("[gKnuckle] bans %s, failmode %s, cached %d, outbox %d"):format(enabled() and "on" or "off", cvFail:GetString(), n, #outbox)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)
concommand.Add("gk_bans_flush", function(ply)
    if not GK.RequireAccess(ply, "gknuckle.bans_admin") then return end
    cache = {}
end)
