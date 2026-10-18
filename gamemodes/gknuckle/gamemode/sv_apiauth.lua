-- Signed service calls to the Illicit/Omerta API (server only). API_SPEC.md §1.
-- Server keys are "id:secret" (gknuckle.server_keys on the API; scopes gk:wallet, gk:pack,
-- gk:bans, gk:chat). Only the id goes over the wire; the secret signs and never leaves:
--   X-GKnuckle-Key        <id>
--   X-GKnuckle-Timestamp  unix seconds, corrected by the API's clock (accepted +-60 s)
--   X-GKnuckle-Nonce      32 hex chars, unique per request (API caches nonces 120 s)
--   X-GKnuckle-Signature  base64url_nopad(HMAC-SHA256(secret, canonical))
-- canonical = METHOD \n PATH \n KEY_ID \n TIMESTAMP \n NONCE \n hex(sha256(body))
-- PATH has no query string; body is the exact bytes sent ("" for GET).
-- HMAC runs on the pure-Lua SHA-256 (sh_sha256.lua), never util.SHA256 (finding H3), and
-- a known-vector self-test at load turns signing off if it ever fails.
include("sh_sha256.lua")

GK.ApiAuth = GK.ApiAuth or {}
local A = GK.ApiAuth

-- H2: keys and signatures only ever go to these origins, whatever a convar says.
-- Add a custom domain here in code (and only here) when the API moves.
-- N8: one list per purpose, so a key or token can only reach the host that serves it.
--   api:  signed id:secret calls (wallet, backpack, access-role, pack delivery, bans)
--   chat: the Omerta bot API (COMMUNiTY bridge's Bot token)
-- The gk.style web host is on neither list.
A.PURPOSES = {
    api = {
        ["https://illicit.up.railway.app"] = true,
        ["https://api.gk.style"] = true,
    },
    chat = {
        ["https://illicit.up.railway.app"] = true,
        ["https://omerta.chat"] = true,
        ["https://www.omerta.chat"] = true,
    },
}
A.ORIGINS = {} -- union, for display only
for _, list in pairs(A.PURPOSES) do for o in pairs(list) do A.ORIGINS[o] = true end end
function A.Origin(value, purpose)
    local o = string.lower(string.gsub(string.Trim(tostring(value or "")), "/+$", ""))
    local list = A.PURPOSES[purpose or "api"]
    if list and list[o] then return o end
    return nil
end

local function xorWith(s, n)
    return (string.gsub(s, ".", function(c) return string.char(bit.bxor(string.byte(c), n)) end))
end
local function hmac(key, msg)
    if #key > 64 then key = GK.SHA256(key) end
    key = key .. string.rep("\0", 64 - #key)
    return GK.SHA256(xorWith(key, 0x5c) .. GK.SHA256(xorWith(key, 0x36) .. msg))
end
local function b64url(bin)
    local s = util.Base64Encode(bin, true)
    s = string.gsub(s, "%+", "-")
    s = string.gsub(s, "/", "_")
    s = string.gsub(s, "=+$", "")
    return s
end
A.B64Url = b64url

-- RFC 4231 test case 2 plus a key with '6' / '\' bytes and a NUL-heavy message (the H3 traps).
local function selfTest()
    if not GK.SHA256OK then return false end
    local ok1 = GK.ToHex(hmac("Jefe", "what do ya want for nothing?")) ==
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
    local ok2 = GK.ToHex(hmac("6\\6\\key\0with-nul", "\0\0body\0\54\92")) ==
        "51fc542c74dbb2e5a3555fe62f4e7bbeee8734aa5bef98becfdb75987533fd47"
    return ok1 and ok2
end
A.SelfTestVectors = selfTest
A.Disabled = not selfTest()
if A.Disabled then
    print("[gKnuckle] HMAC self-test FAILED: signed API calls are disabled (pack, economy id:secret, bans, chat)")
end

-- "id:secret" -> id, secret. Ids [A-Za-z0-9_-]{3,64}; secrets at least 16 chars.
function A.ParseKey(value)
    local id, secret = string.match(string.Trim(tostring(value or "")), "^([%w_%-]+):(.+)$")
    if not id or #id < 3 or #id > 64 or #secret < 16 then return nil end
    return id, secret
end

local counter = 0
function A.Nonce()
    counter = counter + 1
    return string.sub(GK.SHA256Hex(table.concat({ SysTime(), os.time(), counter, math.random(), tostring({}) }, "|")), 1, 32)
end

-- Unique, retry-safe ids for money/save events ([A-Za-z0-9:._-]{8,160}, the API's event_id rule).
function A.EventId(kind, ply, stable)
    local who = (isentity(ply) and IsValid(ply)) and ply:SteamID64() or tostring(ply or "server")
    return string.format("gk:%s:%s:%s", kind, who, stable or (os.time() .. ":" .. string.sub(A.Nonce(), 1, 12)))
end

A.ClockOffset = A.ClockOffset or 0 -- API time minus os.time(), learned from server_time / 401 stale

function A.Headers(key, method, path, body)
    local id, secret = A.ParseKey(key)
    if not id or A.Disabled then return nil end
    local ts, nonce = tostring(os.time() + A.ClockOffset), A.Nonce()
    path = string.match(path, "^[^?]*")
    local canonical = table.concat({ string.upper(method), path, id, ts, nonce, GK.SHA256Hex(body or "") }, "\n")
    return {
        ["X-GKnuckle-Key"] = id,
        ["X-GKnuckle-Timestamp"] = ts,
        ["X-GKnuckle-Nonce"] = nonce,
        ["X-GKnuckle-Signature"] = b64url(hmac(secret, canonical)),
        ["Accept"] = "application/json",
    }
end

-- One helper for every signed call. onDone(code, data): 0 = transport failure or refused
-- locally. Only 2xx counts as success; a 3xx (redirect) is a failure (H2).
function A.Request(origin, key, method, path, body, onDone, label, retried)
    label = label or "api"
    local o = A.Origin(origin)
    if not o then
        print(("[gKnuckle] %s: origin %q is not on the allowlist (sv_apiauth.lua); request skipped"):format(label, tostring(origin)))
        return onDone and onDone(0, { error = "origin not allowed" })
    end
    local raw = body and util.TableToJSON(body) or ""
    local headers = A.Headers(key, method, path, raw)
    if not headers then
        print(("[gKnuckle] %s: %s; request skipped"):format(label, A.Disabled and "signing disabled (self-test failed)" or "key must be id:secret"))
        return onDone and onDone(0, { error = "cannot sign" })
    end
    HTTP({
        url = o .. path, method = method, headers = headers, timeout = 15,
        type = body and "application/json" or nil, body = body and raw or nil,
        success = function(code, resp)
            local data = util.JSONToTable(resp or "") or {}
            local st = tonumber(data.server_time)
            if st and math.abs(st - os.time()) < 86400 then A.ClockOffset = st - os.time() end
            -- M3: a clock-skew 401 retries once with the corrected offset.
            if code == 401 and data.reason == "stale" and not retried then
                return A.Request(origin, key, method, path, body, onDone, label, true)
            end
            if code >= 300 and code < 400 then
                print(("[gKnuckle] %s: unexpected redirect (%d); treated as failure"):format(label, code))
                return onDone and onDone(0, { error = "redirect" })
            end
            if onDone then onDone(code, data) end
        end,
        failed = function(err) if onDone then onDone(0, { error = tostring(err) }) end end,
    })
end
