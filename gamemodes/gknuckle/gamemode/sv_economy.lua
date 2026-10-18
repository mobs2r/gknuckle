-- omerta.chat economy (CrabCoin) bridge.
-- Talks to the omerta backend's key-authenticated /api/private/* routes, the same
-- ones support/integrations/generic_http/lua/illicit_api.lua wraps.
-- Set these in server.cfg (never in a client-visible place):
--   gk_economy_api "https://illicit.up.railway.app"
--   gk_economy_key "<API_SECRET>"
-- With no key set, the economy is disabled and the gamemode runs without it.

GK.Economy = GK.Economy or {}

local cvApi = CreateConVar("gk_economy_api", "https://illicit.up.railway.app", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "omerta API origin")
local cvKey = CreateConVar("gk_economy_key", "", { FCVAR_PROTECTED, FCVAR_DONTRECORD }, "omerta API_SECRET for /api/private routes")

local function enabled()
    return cvKey:GetString() ~= ""
end

local function request(method, path, body, onDone)
    if not enabled() then return end
    HTTP({
        url = cvApi:GetString() .. path,
        method = method,
        headers = { ["X-Api-Key"] = cvKey:GetString() },
        type = body and "application/json" or nil,
        body = body and util.TableToJSON(body) or nil,
        success = function(code, resp)
            local data = util.JSONToTable(resp or "") or {}
            if code >= 400 then
                print(("[gKnuckle] economy %s %s failed (%d): %s"):format(method, path, code, tostring(data.error)))
            end
            if onDone then onDone(code < 400, data) end
        end,
        failed = function(err)
            print("[gKnuckle] economy request failed: " .. tostring(err))
            if onDone then onDone(false, {}) end
        end,
    })
end

-- Note: /api/private looks up players.steam_id directly, so a player whose main
-- omerta account is Discord-based with Steam linked gets a separate Steam row.
function GK.Economy.Refresh(ply)
    if ply:IsBot() then return end
    request("GET", "/api/private/balance/" .. ply:SteamID64(), nil, function(ok, data)
        if ok and IsValid(ply) then ply:SetNW2Int("gk_crabcoin", tonumber(data.balance) or 0) end
    end)
end

function GK.Economy.Add(ply, amount, reason)
    if ply:IsBot() or amount <= 0 then return end
    request("POST", "/api/private/add", { steam_id = ply:SteamID64(), amount = amount, reason = reason }, function(ok, data)
        if ok and IsValid(ply) then
            ply:SetNW2Int("gk_crabcoin", tonumber(data.new_balance) or ply:GetNW2Int("gk_crabcoin"))
            ply:ChatPrint(("+%d CrabCoin (%s)"):format(amount, reason))
        end
    end)
end

-- onDone(ok) lets shops only hand out the item once the debit has cleared.
function GK.Economy.Deduct(ply, amount, reason, onDone)
    if ply:IsBot() then if onDone then onDone(true) end return end
    if not enabled() then if onDone then onDone(true) end return end
    request("POST", "/api/private/deduct", { steam_id = ply:SteamID64(), amount = amount, reason = reason }, function(ok, data)
        if ok and IsValid(ply) then ply:SetNW2Int("gk_crabcoin", tonumber(data.new_balance) or 0) end
        if onDone then onDone(ok) end
    end)
end

-- Omerta accounts and B1 (planned; OFF until the omerta backend has these
-- routes: gk_omerta_accounts 1 turns them on). Routes we expect, same
-- X-Api-Key auth as the ones above:
--   POST /api/private/ensure  { steam_id, name }
--        -> { created = bool, balance = n }   find the omerta account tied to
--           this Steam ID, or create one they can later sign in to with Steam
--   GET  /api/private/b1/<steam_id>
--        -> { b1 = n }                        B1 count from their Steam
--           inventory, as omerta.chat parses it
-- Results land in NW2 ints gk_crabcoin and gk_b1 (the vending machine's bar).
local cvAccounts = CreateConVar("gk_omerta_accounts", "0", FCVAR_ARCHIVE, "Create/recognise omerta accounts on join and read B1 (needs the backend routes)")

function GK.Economy.Ensure(ply)
    if ply:IsBot() or not cvAccounts:GetBool() then return end
    request("POST", "/api/private/ensure", { steam_id = ply:SteamID64(), name = ply:Nick() }, function(ok, data)
        if not ok or not IsValid(ply) then return end
        ply:SetNW2Int("gk_crabcoin", tonumber(data.balance) or ply:GetNW2Int("gk_crabcoin"))
        if data.created then ply:ChatPrint("An Omerta account was made for you: sign in with Steam on omerta.chat to use it.") end
        GK.Economy.RefreshB1(ply)
    end)
end

function GK.Economy.RefreshB1(ply)
    if ply:IsBot() or not cvAccounts:GetBool() then return end
    request("GET", "/api/private/b1/" .. ply:SteamID64(), nil, function(ok, data)
        if ok and IsValid(ply) then ply:SetNW2Int("gk_b1", tonumber(data.b1) or 0) end
    end)
end

hook.Add("PlayerInitialSpawn", "GK_OmertaAccount", function(ply)
    timer.Simple(2, function() if IsValid(ply) then GK.Economy.Ensure(ply) end end)
end)

-- What the vending machines' currency lines show (gk_vendor.lua): nothing
-- without a key (a local game), coins with one, B1 too with accounts on.
timer.Create("GK_EconomyFlags", 5, 0, function()
    local key = cvKey:GetString() ~= ""
    SetGlobal2Bool("gk_eco_coins", key)
    SetGlobal2Bool("gk_eco_b1", key and cvAccounts:GetBool())
end)
