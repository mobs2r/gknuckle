-- Backpack: a player's banked roaches and bag carried between sessions,
-- stored on the omerta.chat (Illicit) backend next to their CrabCoin.
-- OFF unless both are set in server.cfg:
--   gk_backpack_api "https://illicit.up.railway.app"   (the omerta API origin)
--   gk_economy_key  "<API_SECRET>"                    (shared with sv_economy.lua)
-- Proposed routes (they don't exist on omerta yet; the backend has to add them):
--   GET  /api/private/backpack/<steamid64>  -> { roaches = n, xenium = n, bag = { "<item class>", ... } }
--   POST /api/private/backpack              <- { steam_id, roaches, xenium, bag }
-- Loaded when a player joins the hub; saved when they leave and when a run ends.

GK.Backpack = GK.Backpack or {}

local cvApi = CreateConVar("gk_backpack_api", "", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "omerta API origin for backpacks (empty = off)")

local function enabled()
    local key = GetConVar("gk_economy_key")
    return cvApi:GetString() ~= "" and key and key:GetString() ~= ""
end

local function request(method, path, body, onDone)
    if not enabled() then return end
    HTTP({
        url = cvApi:GetString() .. path,
        method = method,
        headers = { ["X-Api-Key"] = GetConVar("gk_economy_key"):GetString() },
        type = body and "application/json" or nil,
        body = body and util.TableToJSON(body) or nil,
        success = function(code, resp)
            if onDone then onDone(code < 400, util.JSONToTable(resp or "") or {}) end
        end,
        failed = function(err)
            print("[gKnuckle] backpack request failed: " .. tostring(err))
            if onDone then onDone(false, {}) end
        end,
    })
end

-- What we'd save: roaches, xenium lumps and the bag's item classes.
function GK.Backpack.Snapshot(ply)
    local inv = GK.Inv.Get(ply)
    local bag = {}
    for _, it in ipairs(inv.bag or {}) do if it.class ~= "xenium" then bag[#bag + 1] = it.class end end
    return { steam_id = ply:SteamID64(), roaches = GK.Roaches.Count(ply) + GK.Roaches.Banked(ply), xenium = GK.Roaches.Lumps(ply), bag = bag }
end

function GK.Backpack.Load(ply)
    if ply:IsBot() then return end
    request("GET", "/api/private/backpack/" .. ply:SteamID64(), nil, function(ok, data)
        if not ok or not IsValid(ply) then return end
        ply:SetNW2Int("gk_bank", tonumber(data.roaches) or 0) -- saved roaches come back banked
        for _ = 1, math.min(tonumber(data.xenium) or 0, 20) do GK.Inv.Give(ply, "xenium") end
        for _, class in ipairs(istable(data.bag) and data.bag or {}) do
            if GK.ItemDef(class) then GK.Inv.Give(ply, class) end
        end
        ply.GK_BackpackLoaded = true
    end)
end

function GK.Backpack.Save(ply)
    if ply:IsBot() or not ply.GK_BackpackLoaded then return end -- never overwrite one we didn't load
    request("POST", "/api/private/backpack", GK.Backpack.Snapshot(ply))
end

hook.Add("PlayerInitialSpawn", "GK_Backpack", function(ply) timer.Simple(2, function() if IsValid(ply) then GK.Backpack.Load(ply) end end) end)
hook.Add("PlayerDisconnected", "GK_Backpack", function(ply) GK.Backpack.Save(ply) end)
hook.Add("GK_ArenaEnd", "GK_Backpack", function(a)
    for _, p in ipairs(a.players or {}) do if IsValid(p) then GK.Backpack.Save(p) end end
end)
