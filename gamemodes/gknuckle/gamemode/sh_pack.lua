-- playable-pack: shared bits. gKnuckle's White Knuckle content (models, materials,
-- sounds, level data) is one GMA, playable-pack.gma, served from Bunny.net to
-- licensed players; see sv_pack.lua (license + signed URL) and cl_pack.lua (download,
-- verify, mount). Until a player's pack is mounted the hub stays playable but runs,
-- arenas and training pads are locked for them.
AddCSLuaFile()
include("sh_sha256.lua")

GK = GK or {}
GK.Pack = GK.Pack or {}

-- M2/N2: the releases this build of gKnuckle will download, mount or report, each pinned
-- to its size, chunk size and the sha256 of its chunk list (the 64-hex chunk hashes
-- concatenated in order, lowercase). Every chunk is checked against that list, so a
-- server can't pass off other bytes under a known release's name. For a new release
-- copy bytes/chunkSize from its manifest and set
--   chunks = sha256(''.join(manifest.files[0].chunkSha256))
GK.Pack.RELEASES = {
    ["48e09ef6f5fbfca14d3550c8aa5b0c787d9d412196944ffa35122d28277437c7"] = {
        name = "gKnuckle/ver0.5.0", bytes = 856620377, chunk_size = 8388608,
        chunks = "487d3ad52c6ba19bcbeb407d1d39c41480537d4f05815c93044e06fee11853bd",
    },
}

GK.Pack.DIR = "gknuckle/packs"                -- under data/
GK.Pack.INDEX = GK.Pack.DIR .. "/index.json"
GK.Pack.MAX_CHUNKS = 512                       -- 512 x 8 MiB = 4 GiB, far above the real 103

function GK.Pack.IsSha(s)
    return isstring(s) and #s == 64 and string.match(s, "^[0-9a-f]+$") ~= nil
end
function GK.Pack.Allowed(sha) return GK.Pack.IsSha(sha) and GK.Pack.RELEASES[sha] ~= nil end
function GK.Pack.ReleaseName(sha) local r = GK.Pack.Allowed(sha) and GK.Pack.RELEASES[sha] return r and r.name or "?" end
function GK.Pack.ChunkListHash(chunks) return GK.SHA256Hex(table.concat(chunks)) end
-- N2: true only if an offer (or a cached index) is exactly a pinned release.
function GK.Pack.MatchesRelease(sha, bytes, chunkSize, chunks)
    if not GK.Pack.Allowed(sha) then return false end
    local r = GK.Pack.RELEASES[sha]
    if bytes ~= r.bytes or chunkSize ~= r.chunk_size then return false end
    if chunks ~= nil and (not istable(chunks) or GK.Pack.ChunkListHash(chunks) ~= r.chunks) then return false end
    return true
end

-- Paths are only ever built from a validated sha (nil otherwise).
function GK.Pack.FileFor(sha256)
    if not GK.Pack.IsSha(sha256) then return nil end
    return GK.Pack.DIR .. "/playable-pack-" .. string.sub(sha256, 1, 16) .. ".gma"
end
-- True only for files this code could have written (used before any file.Delete).
function GK.Pack.IsPackFile(path)
    return isstring(path) and string.match(path, "^gknuckle/packs/playable%-pack%-[0-9a-f]+%.gma$") ~= nil and #path == #"gknuckle/packs/playable-pack-" + 16 + 4
end

-- The release the server expects, replicated so the client can read it before its Lua
-- runs (M2: early mount only when this matches the cached pack). Not a secret.
GK.Pack.cvSha = CreateConVar("gk_pack_sha256", "", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "sha256 of the current playable-pack release")

-- Is this player cleared for levels? Bots always are; with no pack API configured
-- (gk_pack_api empty) gating is off and the Workshop content is used as before.
function GK.PackReady(ply)
    if not IsValid(ply) then return false end
    if ply:IsBot() then return true end
    if GetGlobal2Bool("gk_pack_gate", false) == false then return true end
    return ply:GetNW2Bool("gk_pack_ready", false)
end

-- Message shown to players who can't get the pack.
function GK.Pack.LinkMessage(url)
    return ("gKnuckle's levels use White Knuckle content, available to White Knuckle owners. "
        .. "Link your Steam account at %s (set Steam > Privacy > Game details to Public while you verify), "
        .. "then type gk_pack_retry in console. The hub stays playable meanwhile."):format(url or "https://gk.style/link")
end
