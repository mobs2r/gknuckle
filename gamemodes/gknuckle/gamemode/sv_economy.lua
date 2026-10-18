-- omerta.chat economy (CrabCoin) bridge.
-- Talks to the omerta backend's key-authenticated /api/private/* routes (crabcoin-api,
-- branch omerta; the same ones support/integrations/generic_http/lua/illicit_api.lua wraps).
-- Set these in server.cfg (never in a client-visible place):
--   gk_economy_api "https://illicit.up.railway.app"
--   gk_economy_key "<id>:<secret>"   per-server key, scope gk:wallet (API_SPEC.md §1): only
--                                    the id is sent and the secret HMAC-signs each request.
--                  "<API_SECRET>"    legacy: the global secret sent as X-Api-Key. It can mint
--                                    unlimited coins, so it's accepted with a warning only
--                                    until the API has per-server keys.
-- With no key set, the economy is disabled and the gamemode runs without it.

GK.Economy = GK.Economy or {}

local cvApi = CreateConVar("gk_economy_api", "https://illicit.up.railway.app", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "omerta API origin")
local cvKey = CreateConVar("gk_economy_key", "", { FCVAR_PROTECTED, FCVAR_DONTRECORD }, "Per-server key id:secret (legacy: the global API_SECRET)")

local function enabled()
    return cvKey:GetString() ~= ""
end

local warnedLegacy = false
-- onDone(ok, data, code). Shared with sv_backpack.lua, which passes its own origin.
-- H2: the origin must be on GK.ApiAuth.ORIGINS (pinned in code), and only 2xx is ok;
-- a redirect is a failure so the key is never re-sent somewhere else.
local function request(method, path, body, onDone, originOverride)
    if not enabled() then return end
    local label = originOverride and "gk_backpack_api" or "gk_economy_api"
    local function done(code, data)
        if code >= 300 then
            print(("[gKnuckle] economy %s %s failed (%d): %s"):format(method, string.match(path, "^[^?]*"), code, tostring(data.error)))
        elseif code == 0 then
            print("[gKnuckle] economy request failed: " .. tostring(data.error))
        end
        if onDone then onDone(code >= 200 and code < 300, data, code) end
    end
    local origin = originOverride or cvApi:GetString()
    if GK.ApiAuth.ParseKey(cvKey:GetString()) then
        return GK.ApiAuth.Request(origin, cvKey:GetString(), method, path, body, done, label)
    end
    local o = GK.ApiAuth.Origin(origin)
    if not o then
        print(("[gKnuckle] %s %q is not on the allowlist (sv_apiauth.lua); request skipped"):format(label, origin))
        return done(0, { error = "origin not allowed" })
    end
    if not warnedLegacy then
        warnedLegacy = true
        print("[gKnuckle] gk_economy_key is a legacy global secret (can mint coins). Switch to a per-server id:secret key when the API has them.")
    end
    HTTP({
        url = o .. path,
        method = method,
        headers = { ["X-Api-Key"] = cvKey:GetString() },
        type = body and "application/json" or nil,
        body = body and util.TableToJSON(body) or nil,
        timeout = 15,
        success = function(code, resp)
            if code >= 300 and code < 400 then return done(0, { error = "redirect " .. code }) end
            done(code, util.JSONToTable(resp or "") or {})
        end,
        failed = function(err) done(0, { error = tostring(err) }) end,
    })
end
GK.Economy.Request = request
GK.Economy.Enabled = enabled

-- The API maps a SteamID64 to its Omerta account through auth_identities, so a
-- Discord-first account with Steam linked shares one wallet with the game.
-- /balance also carries b1_count, bugz and roaches, so there's no separate B1 call.
function GK.Economy.Refresh(ply)
    if not IsValid(ply) or ply:IsBot() then return end
    if (ply.GK_NextEcoRefresh or 0) > CurTime() then return end -- L8: at most every 5 s per player
    ply.GK_NextEcoRefresh = CurTime() + 5
    request("GET", "/api/private/balance/" .. ply:SteamID64(), nil, function(ok, data)
        if not ok or not IsValid(ply) then return end
        ply:SetNW2Int("gk_crabcoin", tonumber(data.balance) or 0)
        ply:SetNW2Int("gk_b1", tonumber(data.b1_count) or 0) -- B1 rides along on /balance
    end)
end

local MAX_AWARD = 1000
-- M4: only finite whole amounts in 1..MAX_AWARD (NaN fails every comparison, so test it explicitly).
local function validAmount(n, max)
    n = tonumber(n)
    return n and n == n and n ~= math.huge and n >= 1 and n <= (max or MAX_AWARD) and math.floor(n) == n and n or nil
end
GK.Economy.ValidAmount = validAmount

-- eventId (optional) makes a retry or double call idempotent on the API (event_id).
function GK.Economy.Add(ply, amount, reason, eventId)
    amount = validAmount(amount)
    if not IsValid(ply) or ply:IsBot() or not amount then return end
    request("POST", "/api/private/add", { steam_id = ply:SteamID64(), amount = amount, reason = reason,
        event_id = eventId or GK.ApiAuth.EventId("add", ply) }, function(ok, data)
        if ok and IsValid(ply) then
            ply:SetNW2Int("gk_crabcoin", tonumber(data.new_balance) or ply:GetNW2Int("gk_crabcoin"))
            ply:ChatPrint(("+%d CrabCoin (%s)"):format(amount, reason))
        end
    end)
end

-- onDone(ok) lets shops only hand out the item once the debit has cleared.
function GK.Economy.Deduct(ply, amount, reason, onDone)
    if not validAmount(amount, 1000000) then if onDone then onDone(false) end return end
    if ply:IsBot() then if onDone then onDone(true) end return end
    if not enabled() then if onDone then onDone(true) end return end
    request("POST", "/api/private/deduct", { steam_id = ply:SteamID64(), amount = amount, reason = reason,
        event_id = GK.ApiAuth.EventId("deduct", ply) }, function(ok, data)
        if ok and IsValid(ply) then ply:SetNW2Int("gk_crabcoin", tonumber(data.new_balance) or 0) end
        if onDone then onDone(ok) end
    end)
end

-- Removed: POST /api/private/ensure and GET /api/private/b1 never existed on the API.
-- The account is mapped server-side (auth_identities) and b1_count comes from /balance.

-- What the vending machines' currency lines show (gk_vendor.lua): nothing
-- without a key (a local game), coins and B1 with one.
timer.Create("GK_EconomyFlags", 5, 0, function()
    local key = cvKey:GetString() ~= ""
    SetGlobal2Bool("gk_eco_coins", key)
    SetGlobal2Bool("gk_eco_b1", key)
end)
