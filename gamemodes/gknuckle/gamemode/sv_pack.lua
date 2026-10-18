-- playable-pack, server side: asks the Illicit API whether a player may have the
-- content (White Knuckle ownership via their gk.style link) and for a short-lived
-- signed Bunny URL for playable-pack.gma, hands that to the client, and keeps the
-- per-player ready flag that gates runs, arenas and training pads.
-- Set in server.cfg (never anywhere a client can read):
--   gk_pack_api      "https://illicit.up.railway.app"   Illicit API origin (empty = gating off)
--   gk_pack_key      "<GKNUCKLE_API_SECRET>"            service key, signs every request
--   gk_pack_sha256   "<sha256 of this release's pack>"  lets cached packs count as ready if the API is down
--   gk_pack_link_url "https://gk.style/link"
-- The server's own copy of the pack (it needs .phy collision and the level JSON) is
-- mounted from data/gknuckle/packs/ at load; put the release's playable-pack.gma there.
include("sh_pack.lua")
AddCSLuaFile("sh_pack.lua")
AddCSLuaFile("cl_pack.lua")

util.AddNetworkString("gk_pack_hello")    -- C->S { have sha256 or "" }
util.AddNetworkString("gk_pack_refresh")  -- C->S {}  (URL about to expire / got a 403)
util.AddNetworkString("gk_pack_ready")    -- C->S { sha256 mounted }
util.AddNetworkString("gk_pack_offer")    -- S->C status, message, link, and the pack details when ok

local cvApi = CreateConVar("gk_pack_api", "", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "Illicit API origin for playable-pack delivery (empty = off)")
local cvKey = CreateConVar("gk_pack_key", "", { FCVAR_PROTECTED, FCVAR_DONTRECORD }, "gKnuckle service key for the Illicit API")
local cvSha = CreateConVar("gk_pack_sha256", "", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "sha256 of the current playable-pack release")
local cvLink = CreateConVar("gk_pack_link_url", "https://gk.style/link", { FCVAR_ARCHIVE }, "Where players link Steam and verify White Knuckle")

local function enabled() return cvApi:GetString() ~= "" end
timer.Create("GK_PackGate", 2, 0, function() SetGlobal2Bool("gk_pack_gate", enabled()) end)

-- Server copy --------------------------------------------------------------------
local function mountServerPack()
    if GK.Pack.ServerMounted then return end
    local files = file.Find(GK.Pack.DIR .. "/playable-pack*.gma", "DATA", "datedesc")
    if not files or not files[1] then return end
    local ok, list = game.MountGMA("data/" .. GK.Pack.DIR .. "/" .. files[1])
    if ok then
        GK.Pack.ServerMounted = files[1]
        print(("[gKnuckle] mounted %s (%d files)"):format(files[1], #list))
    else
        print("[gKnuckle] could not mount " .. files[1])
    end
end
mountServerPack()
hook.Add("Initialize", "GK_PackServerMount", mountServerPack)

-- Service auth: X-GKnuckle-Key + HMAC-SHA256 (base64url) over
-- METHOD\nPATH\nTIMESTAMP\nhex(sha256(body)), the same canonical string as cod.city.
local function hex2bin(h) return (string.gsub(h, "..", function(c) return string.char(tonumber(c, 16)) end)) end
local function xorWith(s, n)
    return (string.gsub(s, ".", function(c) return string.char(bit.bxor(string.byte(c), n)) end))
end
local function hmacSha256(key, msg)
    if #key > 64 then key = hex2bin(util.SHA256(key)) end
    key = key .. string.rep("\0", 64 - #key)
    local inner = hex2bin(util.SHA256(xorWith(key, 0x36) .. msg))
    return hex2bin(util.SHA256(xorWith(key, 0x5c) .. inner))
end
local function b64url(bin)
    local s = util.Base64Encode(bin, true)
    s = string.gsub(s, "%+", "-")
    s = string.gsub(s, "/", "_")
    s = string.gsub(s, "=+$", "")
    return s
end
GK.Pack.HMAC = hmacSha256 -- exposed for a self-check against a known vector

local function request(path, body, onDone)
    local origin = cvApi:GetString()
    if not string.StartsWith(string.lower(origin), "https://") then
        print("[gKnuckle] gk_pack_api must start with https://; request skipped")
        return onDone(false, 0, {})
    end
    local raw = util.TableToJSON(body or {})
    local ts = tostring(os.time())
    local canonical = "POST\n" .. path .. "\n" .. ts .. "\n" .. util.SHA256(raw)
    HTTP({
        url = origin .. path,
        method = "POST",
        type = "application/json",
        body = raw,
        timeout = 15,
        headers = {
            ["X-GKnuckle-Key"] = cvKey:GetString(),
            ["X-GKnuckle-Timestamp"] = ts,
            ["X-GKnuckle-Signature"] = b64url(hmacSha256(cvKey:GetString(), canonical)),
            ["Accept"] = "application/json",
        },
        success = function(code, resp) onDone(code < 400, code, util.JSONToTable(resp or "") or {}) end,
        failed = function(err)
            print("[gKnuckle] pack API request failed: " .. tostring(err))
            onDone(false, 0, {})
        end,
    })
end

-- Offer to the client ---------------------------------------------------------------
local HEX64 = "^%x+$"
local function sendOffer(ply, status, message, f)
    if not IsValid(ply) then return end
    net.Start("gk_pack_offer")
    net.WriteString(status)
    net.WriteString(message or "")
    net.WriteString(cvLink:GetString())
    if status == "ok" then
        net.WriteString(f.url)
        net.WriteUInt(math.Clamp(math.floor(f.expiresIn), 0, 3600), 12)
        net.WriteString(f.sha256)
        net.WriteDouble(f.bytes)
        net.WriteUInt(f.chunkSize, 32)
        net.WriteUInt(#f.chunks, 10)
        for _, h in ipairs(f.chunks) do net.WriteString(h) end
    end
    net.Send(ply)
end

-- Validates one files[] entry from the API.
local function parseFile(e, serverTime)
    if not istable(e) or e.route ~= "playable-pack" then return nil end
    local url, sha = tostring(e.url or ""), string.lower(tostring(e.sha256 or ""))
    local bytes, cs = tonumber(e.bytes), tonumber(e.chunk_size)
    local chunks = istable(e.chunk_sha256) and e.chunk_sha256 or {}
    if not string.StartsWith(url, "https://") or #sha ~= 64 or not string.match(sha, HEX64) then return nil end
    if not bytes or bytes <= 0 or not cs or cs < 1048576 or cs > 33554432 then return nil end
    if #chunks ~= math.ceil(bytes / cs) or #chunks > GK.Pack.MAX_CHUNKS then return nil end
    for i, h in ipairs(chunks) do
        h = string.lower(tostring(h))
        if #h ~= 64 or not string.match(h, HEX64) then return nil end
        chunks[i] = h
    end
    local expiresIn = (tonumber(e.expires) or 0) - (tonumber(serverTime) or os.time())
    if expiresIn < 5 then return nil end
    return { url = url, sha256 = sha, bytes = bytes, chunkSize = cs, chunks = chunks, expiresIn = expiresIn }
end

local function deliver(ply, have)
    if not enabled() then return sendOffer(ply, "disabled") end
    local ip = string.match(ply:IPAddress() or "", "^(%d+%.%d+%.%d+%.%d+)")
    if ip == "127.0.0.1" or game.SinglePlayer() then ip = nil end
    request("/api/integrations/gknuckle/delivery", { steam_id = ply:SteamID64(), client_ip = ip, have_sha256 = have ~= "" and have or nil }, function(ok, code, data)
        if not IsValid(ply) then return end
        if ok and data.licensed == true and istable(data.files) then
            local f = parseFile(data.files[1], data.server_time)
            if f then
                ply.GK_PackOffer = f
                return sendOffer(ply, "ok", "", f)
            end
            return sendOffer(ply, "unavailable", "The content server sent an invalid answer. Retrying later.")
        end
        if ok or code == 403 then
            ply.GK_PackOffer = nil
            return sendOffer(ply, "unlicensed", GK.Pack.LinkMessage(data.link_url or cvLink:GetString()))
        end
        -- API down or erroring: a client whose cached pack matches this release can still play.
        sendOffer(ply, "unavailable", "The gKnuckle content server can't be reached right now. The hub stays playable; it will retry.")
    end)
end

local function throttled(ply, field, gap)
    if (ply[field] or 0) > CurTime() then return true end
    ply[field] = CurTime() + gap
    return false
end

net.Receive("gk_pack_hello", function(_, ply)
    if not IsValid(ply) or throttled(ply, "GK_PackHelloAt", 5) then return end
    local have = string.lower(string.sub(net.ReadString(), 1, 64))
    ply.GK_PackHave = have
    deliver(ply, have)
end)

net.Receive("gk_pack_refresh", function(_, ply)
    if not IsValid(ply) or throttled(ply, "GK_PackRefreshAt", 8) then return end
    deliver(ply, ply.GK_PackHave or "")
end)

net.Receive("gk_pack_ready", function(_, ply)
    if not IsValid(ply) or throttled(ply, "GK_PackReadyAt", 2) then return end
    local sha = string.lower(string.sub(net.ReadString(), 1, 64))
    local offered = ply.GK_PackOffer and ply.GK_PackOffer.sha256
    if (offered and sha == offered) or (cvSha:GetString() ~= "" and sha == string.lower(cvSha:GetString())) then
        ply:SetNW2Bool("gk_pack_ready", true)
        print(("[gKnuckle] %s has playable-pack %s"):format(ply:Nick(), string.sub(sha, 1, 12)))
    end
end)

concommand.Add("gk_pack_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local lines = { ("gate %s, server pack %s"):format(tostring(enabled()), tostring(GK.Pack.ServerMounted)) }
    for _, p in ipairs(player.GetHumans()) do
        lines[#lines + 1] = ("  %s ready=%s"):format(p:Nick(), tostring(p:GetNW2Bool("gk_pack_ready", false)))
    end
    for _, l in ipairs(lines) do if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, l) else print(l) end end
end)

-- Tell a not-ready player why a run/pad didn't take them (at most every 10 s).
function GK.Pack.Nag(ply)
    if not IsValid(ply) or throttled(ply, "GK_PackNagAt", 10) then return end
    ply:ChatPrint("[gKnuckle] Levels unlock once your gKnuckle content has downloaded. " .. cvLink:GetString())
end
