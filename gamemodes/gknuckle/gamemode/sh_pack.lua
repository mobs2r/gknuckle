-- playable-pack: shared bits. gKnuckle's White Knuckle content (models, materials,
-- sounds, level data) is one GMA, playable-pack.gma, served from Bunny.net to
-- licensed players; see sv_pack.lua (license + signed URL) and cl_pack.lua (download,
-- verify, mount). Until a player's pack is mounted the hub stays playable but runs,
-- arenas and training pads are locked for them.
AddCSLuaFile()
include("sh_sha256.lua")

GK = GK or {}
GK.Pack = GK.Pack or {}

-- M2: the releases this build of gKnuckle will download, mount or report. A server can't
-- push any other GMA onto clients. Add each new release's sha256 here (and ship it).
GK.Pack.RELEASES = {
    ["48e09ef6f5fbfca14d3550c8aa5b0c787d9d412196944ffa35122d28277437c7"] = "gKnuckle/ver0.5.0",
}

GK.Pack.DIR = "gknuckle/packs"                -- under data/
GK.Pack.INDEX = GK.Pack.DIR .. "/index.json"
GK.Pack.MAX_CHUNKS = 512                       -- 512 x 8 MiB = 4 GiB, far above the real 103

function GK.Pack.IsSha(s)
    return isstring(s) and #s == 64 and string.match(s, "^[0-9a-f]+$") ~= nil
end
function GK.Pack.Allowed(sha) return GK.Pack.IsSha(sha) and GK.Pack.RELEASES[sha] ~= nil end

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
