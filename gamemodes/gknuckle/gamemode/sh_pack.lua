-- playable-pack: shared bits. gKnuckle's White Knuckle content (models, materials,
-- sounds, level data) is one GMA, playable-pack.gma, served from Bunny.net to
-- licensed players; see sv_pack.lua (license + signed URL) and cl_pack.lua (download,
-- verify, mount). Until a player's pack is mounted the hub stays playable but runs,
-- arenas and training pads are locked for them.
AddCSLuaFile()

GK = GK or {}
GK.Pack = GK.Pack or {}

GK.Pack.DIR = "gknuckle/packs"                -- under data/
GK.Pack.INDEX = GK.Pack.DIR .. "/index.json"
GK.Pack.MAX_CHUNKS = 512                       -- 512 x 8 MiB = 4 GiB, far above the real 103

function GK.Pack.FileFor(sha256)
    return GK.Pack.DIR .. "/playable-pack-" .. string.sub(sha256, 1, 16) .. ".gma"
end

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
