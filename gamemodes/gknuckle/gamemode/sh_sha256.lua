-- sh_sha256.lua: pure-Lua SHA-256 (GMod's bit library), byte-exact for any input, NULs included.
-- Used for every HMAC (sv_apiauth.lua), so signing never depends on how util.SHA256 treats
-- binary strings, and as the fallback for pack chunk checks (cl_pack.lua) if util.SHA256
-- fails the binary self-test below. Checked against Python hashlib/hmac on 300 random
-- vectors (0-300 bytes, random keys) and the 1,000,000 x "a" vector.
if SERVER then AddCSLuaFile() end
GK = GK or {}
local band, bor, bxor, bnot, rshift, lshift, ror, tobit =
    bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift, bit.ror, bit.tobit
local byte, char, rep, format = string.byte, string.char, string.rep, string.format
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
for i = 1, 64 do K[i] = tobit(K[i]) end
local H0 = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
for i = 1, 8 do H0[i] = tobit(H0[i]) end

local function be32(n)
    return char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
end

local function sha256(msg)
    local len = #msg
    local bitsHi = math.floor(len / 536870912) -- len*8 / 2^32
    local bitsLo = (len % 536870912) * 8
    msg = msg .. "\128" .. rep("\0", (55 - len) % 64) .. be32(tobit(bitsHi)) .. be32(tobit(bitsLo))
    local h1, h2, h3, h4, h5, h6, h7, h8 = H0[1], H0[2], H0[3], H0[4], H0[5], H0[6], H0[7], H0[8]
    local w = {}
    for p = 1, #msg, 64 do
        for i = 0, 15 do
            local a, b, c, d = byte(msg, p + i * 4, p + i * 4 + 3)
            w[i] = bor(lshift(a, 24), lshift(b, 16), lshift(c, 8), d)
        end
        for i = 16, 63 do
            local x, y = w[i - 15], w[i - 2]
            local s0 = bxor(ror(x, 7), ror(x, 18), rshift(x, 3))
            local s1 = bxor(ror(y, 17), ror(y, 19), rshift(y, 10))
            w[i] = tobit(w[i - 16] + s0 + w[i - 7] + s1)
        end
        local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
        for i = 0, 63 do
            local S1 = bxor(ror(e, 6), ror(e, 11), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = tobit(h + S1 + ch + K[i + 1] + w[i])
            local S0 = bxor(ror(a, 2), ror(a, 13), ror(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            local t2 = tobit(S0 + maj)
            h, g, f, e, d, c, b, a = g, f, e, tobit(d + t1), c, b, a, tobit(t1 + t2)
        end
        h1, h2, h3, h4 = tobit(h1 + a), tobit(h2 + b), tobit(h3 + c), tobit(h4 + d)
        h5, h6, h7, h8 = tobit(h5 + e), tobit(h6 + f), tobit(h7 + g), tobit(h8 + h)
    end
    return be32(h1) .. be32(h2) .. be32(h3) .. be32(h4) .. be32(h5) .. be32(h6) .. be32(h7) .. be32(h8)
end
local function tohex(s) return (string.gsub(s, ".", function(c) return format("%02x", byte(c)) end)) end

GK.SHA256 = sha256                                   -- raw 32-byte digest
function GK.SHA256Hex(s) return tohex(sha256(s)) end -- 64 lowercase hex
GK.ToHex = tohex

-- Known answers: FIPS 180-2 "abc", and a NUL-containing string.
GK.SHA256OK = GK.SHA256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    and GK.SHA256Hex("a\0b") == "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138"
-- Does util.SHA256 hash binary strings byte-for-byte? (decides the chunk-check path)
GK.UtilSHA256BinarySafe = util and util.SHA256 and util.SHA256("a\0b") == GK.SHA256Hex("a\0b") or false
-- Hex SHA-256 of possibly binary data: util.SHA256 (C, fast) when it's binary-safe, else Lua.
function GK.SHA256HexFast(s)
    if GK.UtilSHA256BinarySafe then return util.SHA256(s) end
    return GK.SHA256Hex(s)
end
