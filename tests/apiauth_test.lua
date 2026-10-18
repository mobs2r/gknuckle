-- Offline check of the signing code (run from the repo root: luajit tests/apiauth_test.lua).
-- Stubs the few GMod functions sv_apiauth.lua needs, then checks SHA-256 / HMAC known
-- answers and one full request signature against a value computed with Python's hmac.
bit = require("bit")
GK = {}
local root = "gamemodes/gknuckle/gamemode/"
util = { Base64Encode = function(s)
    local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    return ((s:gsub(".", function(x)
        local r, n = "", x:byte()
        for i = 8, 1, -1 do r = r .. (n % 2 ^ i - n % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return b:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#s % 3 + 1])
end }
string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
string.StartsWith = function(s, p) return s:sub(1, #p) == p end
include = function(f) dofile(root .. f) end
AddCSLuaFile = function() end
SERVER = true
SysTime = os.clock
dofile(root .. "sv_apiauth.lua")
local A, fails = GK.ApiAuth, 0
local function check(name, ok) print((ok and "ok   " or "FAIL ") .. name) if not ok then fails = fails + 1 end end
check("sha256 self-test", GK.SHA256OK)
check("hmac self-test (RFC 4231 #2 + NUL/'6'/'\\' vector)", not A.Disabled)
check("1e6 x 'a'", GK.SHA256Hex(string.rep("a", 1000000)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
check("origin allowlist", A.Origin("https://illicit.up.railway.app/") == "https://illicit.up.railway.app" and A.Origin("https://evil.example") == nil)
check("key format", A.ParseKey("srv1:0123456789abcdef0123") == "srv1" and A.ParseKey("plainsecret") == nil)
local realTime = os.time
os.time = function() return 1700000000 end
A.Nonce = function() return "00112233445566778899aabbccddeeff" end
local h = A.Headers("srv1:0123456789abcdef0123", "POST", "/api/x?y=1", '{"a":1}')
os.time = realTime
check("signature", h["X-GKnuckle-Signature"] == "cqPAttS5jHfHkbRuHn5LgecU272Dc8Eb9D3JNBpecD0" and h["X-GKnuckle-Key"] == "srv1")
check("secret never in headers", not table.concat({ h["X-GKnuckle-Key"], h["X-GKnuckle-Signature"], h["X-GKnuckle-Nonce"] }):find("0123456789abcdef0123", 1, true))
os.exit(fails == 0 and 0 or 1)
