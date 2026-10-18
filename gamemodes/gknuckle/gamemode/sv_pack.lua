-- playable-pack, server side: asks the Illicit API whether a player may have the
-- content (White Knuckle ownership via their gk.style link) and for a short-lived
-- signed Bunny URL for playable-pack.gma, hands that to the client, and keeps the
-- per-player ready flag that gates runs, arenas and training pads.
-- Set in server.cfg (never anywhere a client can read):
--   gk_pack_api      "https://illicit.up.railway.app"   Illicit API origin (empty = gating off)
--   gk_pack_key      "<id>:<secret>"                    per-server key (scope gk:pack); only the id
--                                                       is sent, the secret signs (sv_apiauth.lua)
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
local cvKey = CreateConVar("gk_pack_key", "", { FCVAR_PROTECTED, FCVAR_DONTRECORD }, "Per-server Illicit key, id:secret (the secret is never sent)")
local cvSha = GK.Pack.cvSha -- sh_pack.lua (replicated)
local cvLink = CreateConVar("gk_pack_link_url", "https://gk.style/link", { FCVAR_ARCHIVE }, "Where players link Steam and verify White Knuckle")

local function enabled() return cvApi:GetString() ~= "" end
timer.Create("GK_PackGate", 2, 0, function() SetGlobal2Bool("gk_pack_gate", enabled()) end)

-- Server copy --------------------------------------------------------------------
local function mountServerPack()
    if GK.Pack.ServerMounted then return end
    -- L6: only a file named for an allowlisted release (the configured one first), and
    -- only if its size matches that release's manifest when one sits next to it.
    local order = {}
    local want = string.lower(cvSha:GetString())
    if GK.Pack.Allowed(want) then order[1] = want end
    for sha in pairs(GK.Pack.RELEASES) do if sha ~= want then order[#order + 1] = sha end end
    for _, sha in ipairs(order) do
        local f = GK.Pack.FileFor(sha)
        if f and file.Exists(f, "DATA") then
            local man = util.JSONToTable(file.Read(GK.Pack.DIR .. "/playable-pack.manifest.json", "DATA") or "") or {}
            if man.sha256 == sha and tonumber(man.bytes) and file.Size(f, "DATA") ~= tonumber(man.bytes) then
                print(("[gKnuckle] %s is the wrong size for release %s; not mounted"):format(f, GK.Pack.RELEASES[sha]))
            else
                local ok, list = game.MountGMA("data/" .. f)
                if ok then
                    GK.Pack.ServerMounted, GK.Pack.ServerSha = f, sha
                    print(("[gKnuckle] mounted %s (%s, %d files)"):format(f, GK.Pack.RELEASES[sha], #list))
                    return
                end
                print("[gKnuckle] could not mount " .. f)
            end
        end
    end
end
mountServerPack()
hook.Add("Initialize", "GK_PackServerMount", mountServerPack)

-- Service auth: sv_apiauth.lua. gk_pack_key is "id:secret"; only the id is sent,
-- the secret HMAC-signs METHOD/PATH/TIMESTAMP/NONCE/body-hash (API_SPEC.md §1).
local function request(path, body, onDone)
    GK.ApiAuth.Request(cvApi:GetString(), cvKey:GetString(), "POST", path, body, function(code, data)
        if code == 0 then print("[gKnuckle] pack API request failed: " .. tostring(data.error)) end
        onDone(code > 0 and code < 400, code, data)
    end, "gk_pack_api")
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
        -- M1: the cached-pack fallback is only for "API unreachable", never after a no.
        ply.GK_PackApiDown = (code == 0 or code >= 500)
        if ok and data.licensed == true and istable(data.files) then
            local f = parseFile(data.files[1], data.server_time)
            if f and not GK.Pack.Allowed(f.sha256) then
                print(("[gKnuckle] API offered release %s that isn't in GK.Pack.RELEASES; update the gamemode"):format(string.sub(f.sha256, 1, 12)))
                f = nil
            end
            if f then
                ply.GK_PackOffer = f
                return sendOffer(ply, "ok", "", f)
            end
            return sendOffer(ply, "unavailable", "The content server sent an invalid answer. Retrying later.")
        end
        if ok and data.licensed == false and data.reason == "banned" then
            -- Omerta global ban (API_SPEC.md §4): no content, no link prompt.
            ply.GK_PackOffer = nil
            ply:SetNW2Bool("gk_pack_ready", false)
            return sendOffer(ply, "unlicensed", "Your Omerta account is banned, so gKnuckle content isn't available. The hub stays open.")
        end
        if ok or code == 403 then
            ply.GK_PackOffer = nil
            ply:SetNW2Bool("gk_pack_ready", false) -- M1: a no clears an earlier yes
            return sendOffer(ply, "unlicensed", GK.Pack.LinkMessage(data.link_url or cvLink:GetString()))
        end
        if code == 401 then print("[gKnuckle] pack API rejected gk_pack_key (401): check the id:secret pair") end
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
    if not GK.Pack.IsSha(have) then have = "" end
    ply.GK_PackHave = have
    -- L5: the SteamID has to be Steam-verified before it's used for a licence lookup.
    if not ply:IsFullyAuthenticated() and not game.SinglePlayer() then
        local tries = 0
        return timer.Create("GK_PackAuth" .. ply:EntIndex(), 3, 20, function()
            tries = tries + 1
            if not IsValid(ply) then return end
            if ply:IsFullyAuthenticated() then
                timer.Remove("GK_PackAuth" .. ply:EntIndex())
                deliver(ply, ply.GK_PackHave or "")
            elseif tries == 20 then
                sendOffer(ply, "unavailable", "Steam hasn't confirmed your account yet; rejoin to get gKnuckle content.")
            end
        end)
    end
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
    -- M1: the offered sha, or (only while the API is unreachable for this player) the
    -- configured release. This is a convenience gate, not DRM: the server can't see
    -- what a client really mounted. The real control is who gets a signed URL.
    local fallback = ply.GK_PackApiDown and GK.Pack.Allowed(sha) and sha == string.lower(cvSha:GetString())
    if (offered and sha == offered) or fallback then
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
