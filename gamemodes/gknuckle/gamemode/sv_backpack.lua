-- Backpack: a player's roach bank (BUGZ) carried between sessions, stored on the
-- Omerta (Illicit) backend next to their CrabCoin. Uses the routes that exist on
-- crabcoin-api (branch omerta), with sv_economy.lua's key and signing:
--   GET  /api/private/gknuckle/<steamid64> -> { bugz, bugz_cap, roaches, balance }
--   POST /api/private/gknuckle/save        <- { steam_id, event_id, bugz (0-999), source, version }
-- OFF unless both are set in server.cfg:
--   gk_backpack_api "https://illicit.up.railway.app"   (must be on GK.ApiAuth.PURPOSES.api)
--   gk_economy_key  "<id>:<secret>"                     (shared with sv_economy.lua)
-- TODO(backend): xenium lumps and the bag's items aren't stored by the API yet, so they
-- stay local to this session (not saved, not restored). Add them to /gknuckle/save
-- (with the same version/event_id rules) before syncing them.
-- Saves carry a per-player version and a unique event_id. The API ignores version
-- today; API_SPEC.md asks it to reject a save older than the stored one (409).

GK.Backpack = GK.Backpack or {}

local cvApi = CreateConVar("gk_backpack_api", "", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "omerta API origin for backpacks (empty = off)")

local function enabled()
    return cvApi:GetString() ~= "" and GK.Economy.Enabled and GK.Economy.Enabled()
end
local function request(method, path, body, onDone)
    GK.Economy.Request(method, path, body, onDone, cvApi:GetString())
end

-- M7: saves in flight, by SteamID64 (survives the player entity). A rejoin waits for
-- the pending save before loading, and a save made while one is in flight is coalesced
-- into one follow-up with the newest value.
local pending = {}   -- sid -> { inflight = bool, next = body or nil, since = CurTime() }
local versions = {}  -- sid -> last version sent this server session

local function bugzFor(ply, leavingMidRun)
    -- A mid-run disconnect counts as a death for the loose roaches (DoPlayerDeath drops
    -- them), so only the bank is saved; otherwise loose + bank, as before.
    local loose = leavingMidRun and 0 or GK.Roaches.Count(ply)
    return math.Clamp(math.floor(loose + GK.Roaches.Banked(ply)), 0, GK.RoachCap or 999)
end

local function send(sid)
    local p = pending[sid]
    if not p or p.inflight or not p.next then return end
    local body = p.next
    p.next, p.inflight, p.since = nil, true, CurTime()
    request("POST", "/api/private/gknuckle/save", body, function(ok, data, code)
        p.inflight = false
        if code == 409 then
            -- N6: another server (or a later save) holds a newer version: adopt it and reload
            -- this player's backpack from the API instead of overwriting it.
            versions[sid] = math.max(versions[sid] or 0, math.floor(tonumber(istable(data) and data.version) or 0))
            p.next = nil
            pending[sid] = nil
            local ply = player.GetBySteamID64(sid)
            if IsValid(ply) then ply.GK_BackpackLoaded = false GK.Backpack.Load(ply) end
            print(("[gKnuckle] backpack save for %s was stale (409); reloaded"):format(sid))
            return
        end
        if not ok then print(("[gKnuckle] backpack save for %s failed (%s)"):format(sid, tostring(code))) end
        if p.next then return send(sid) end
        pending[sid] = nil
    end)
end

function GK.Backpack.Save(ply, leaving)
    if not IsValid(ply) or ply:IsBot() or not ply.GK_BackpackLoaded or not enabled() then return end -- never overwrite one we didn't load
    local sid = ply:SteamID64()
    local midRun = leaving and GK.ArenaOf and GK.ArenaOf(ply) ~= 0
    versions[sid] = math.max((versions[sid] or 0) + 1, ply.GK_BackpackVersion or 0)
    pending[sid] = pending[sid] or { inflight = false, since = CurTime() }
    pending[sid].next = {
        steam_id = sid,
        event_id = GK.ApiAuth.EventId("save", sid, versions[sid] .. ":" .. os.time()),
        bugz = bugzFor(ply, midRun),
        source = "gknuckle-server",
        version = versions[sid],
    }
    send(sid)
end

function GK.Backpack.Load(ply, tries)
    if not IsValid(ply) or ply:IsBot() or not enabled() then return end
    local sid = ply:SteamID64()
    local p = pending[sid]
    if p and (CurTime() - p.since) < 20 and (tries or 0) < 40 then
        -- M7: our own save from their last visit hasn't landed yet; load after it does.
        return timer.Simple(0.5, function() GK.Backpack.Load(ply, (tries or 0) + 1) end)
    end
    request("GET", "/api/private/gknuckle/" .. sid, nil, function(ok, data)
        if not ok or not IsValid(ply) then return end
        ply:SetNW2Int("gk_bank", math.Clamp(math.floor(tonumber(data.bugz) or 0), 0, GK.RoachCap or 999)) -- saved roaches come back banked
        -- N6: continue from the API's stored version (survives restarts and other servers).
        local stored = math.floor(tonumber(data.version) or 0)
        versions[sid] = math.max(stored, versions[sid] or 0)
        ply.GK_BackpackVersion = versions[sid] + 1
        ply.GK_BackpackLoaded = true
    end)
end

hook.Add("PlayerInitialSpawn", "GK_Backpack", function(ply) timer.Simple(2, function() if IsValid(ply) then GK.Backpack.Load(ply) end end) end)
hook.Add("PlayerDisconnected", "GK_Backpack", function(ply) GK.Backpack.Save(ply, true) end)
hook.Add("GK_ArenaEnd", "GK_Backpack", function(a)
    for _, p in ipairs(a.players or {}) do if IsValid(p) then GK.Backpack.Save(p) end end
end)
hook.Add("ShutDown", "GK_Backpack", function()
    for _, p in ipairs(player.GetHumans()) do GK.Backpack.Save(p, true) end
end)
