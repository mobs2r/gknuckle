# gKnuckle

gKnuckle is a **Garry's Mod gamemode inspired by White Knuckle**. It's a climbing and grip-based movement game where you race up vertical courses, fight in arenas and use the CrabCoin economy. It's built and run by **mobs2r / Illicit**.

- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3479529954
- Website: https://gk.style
- Server: `play.gk.style:26147`

## What ships where

This repo is **code only**. No White Knuckle content is committed here.

| Where | What |
|---|---|
| This repo | The gamemode's Lua code, `server.cfg.example` and the API spec (`docs/API_SPEC.md`). |
| [gKnuckle Workshop item](https://steamcommunity.com/sharedfiles/filedetails/?id=3479529954) | The gamemode code, plus the `gk_style` map (`maps/gk_style.bsp`) and the brush materials it needs. GMod loads a map before any gamemode code runs, so the map has to stay on the Workshop. |
| **playable-pack** (Bunny CDN) | Everything else converted from White Knuckle: models, materials, sounds, fonts, UI icons and the level data in `data_static/gknuckle/`. |
| [White Knuckle Prop Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=3817814674) and [NPCs Pack](https://steamcommunity.com/sharedfiles/filedetails/?id=3818830408) (Workshop) | Physics props and the `wkn_*` creature entities. These stay on the Workshop and aren't duplicated here. Servers should add both to their Workshop collection along with the gKnuckle item. |

### The playable-pack and the licence check

The playable-pack is only for players who own **White Knuckle** on Steam (app 3195790):

1. The player links their Steam account on [gk.style](https://gk.style/link). The Illicit API checks that White Knuckle is in their Steam library.
2. When they join a server that has `gk_pack_api` set, the game server asks the Illicit API for a delivery for that SteamID (a signed, per-server request). Globally banned players get a ban notice instead.
3. A licensed player gets a short-lived Bunny link, valid for 60 s and scoped to that one file. The client downloads the pack in 8 MiB chunks, resumes after a crash, and checks every chunk's SHA-256. The release's size, chunk size and chunk-list hash are pinned in `GK.Pack.RELEASES` (`sh_pack.lua`), so the client won't mount a pack that doesn't match the shipped gamemode. A new release needs a gamemode update.
4. The pack is mounted with `game.MountGMA` and cached in `data/gknuckle/packs/` for next time.

With `gk_pack_api` left empty, the check is off, and the server relies on whatever content the clients already have mounted. This is a convenience gate, not DRM: a licensed player could re-share the downloaded file.

## Layout

```
gamemodes/gknuckle/
  gknuckle.txt              gamemode descriptor (base sandbox, maps ^gk_, settings)
  gamemode/                 init.lua, cl_init.lua, shared.lua and the cl_/sh_/sv_ modules
                            (movement, grip, items, perks, economy, arena, levels, hub, HUD...)
                            sh_*test.lua files are in-game self-test / debug harnesses
  entities/entities/        gk_* entities (vendors, hazards, creatures, level pieces, ...)
  entities/weapons/gk_mind/ the player's "mind" SWEP (hands / grip)
addon.json                  gmad/gmpublisher descriptor

(maps/ and the map's brush materials come from the Workshop item; data_static/, resource/,
 models/, materials/ and sound/ come from the playable-pack)
```

## Configuration

All settings are server convars. Put them in `cfg/server.cfg` and never commit the keys. `server.cfg.example` lists every setting.

**Owner (full gKnuckle admin).** This is empty by default, so nobody gets owner access unless the server sets it. Illicit's own servers use:
```
gk_owner_steamids "76561199041513241"   // mobs2r; comma-separate more
```
The server prints the configured owners at startup.

**Omerta access roles.** Owner, admin and moderator roles also come from Omerta (`gk_access_roles 1`), but only with a per-server key.

**Economy / backpack (CrabCoin).** These need either:
- a per-server key in the form `gk_economy_key "<id>:<secret>"` (only the id is sent; requests are HMAC-signed), or
- **until the API ships per-server keys**, the legacy global secret **plus** `gk_economy_legacy_key 1`.

Without one of those, **the economy is off**, and the server console says so in red. The legacy secret can mint unlimited CrabCoin. Switch to a per-server key as soon as one exists.

**Bans.** `gk_bans_failmode` decides what happens when the ban API can't answer:
- `open` (the default): players are let in, so globally banned players can join during an API outage.
- `closed`: every first-time connect is refused until the ban cache warms up.

**Playable-pack delivery.** Set `gk_pack_api` to the Illicit API origin and `gk_pack_key "<id>:<secret>"` (scope `gk:pack`). Leave `gk_pack_api` empty until the delivery route is live on the API, or licensed players won't get any content.

**Admin mods (CAMI).** gKnuckle registers its privileges (`gknuckle.*`) through CAMI, so ULX, SAM, ServerGuard, sAdmin and other CAMI admin mods can grant them like any other permission. ULX also gets gKnuckle commands (`sh_ulx_gk.lua`). On top of that, players in `gk_owner_steamids` get every privilege, and Omerta staff roles (owner, admin, moderator) apply when `gk_access_roles 1` and a per-server key are set.

**Chat bridge (COMMUNiTY).** In-game chat and the gk.style web chat are linked through the Omerta bot API. Create a bot for the server, install it in the `#gknuckle` room with read and send permissions, then set `gk_community_api`, `gk_community_bot_token` and `gk_community_channel`. Player messages, joins, leaves and deaths are relayed out, and web messages show in game as `web:<name>`. Links and `@` mentions are stripped, messages are rate-limited per player, and admins can stop relaying a player with `gk_community_mute`.

**Bans (Omerta).** Set `gk_bans_api` and `gk_bans_key` (or reuse `gk_pack_key`). Every joining player is checked against Omerta's global ban list, including the owner of a family-shared copy. Bans made in game with ULX or SAM are reported to Omerta's moderation queue. They don't become global bans automatically; a moderator has to promote them. Banned players see the reason and can appeal at **https://bans.gk.style**.

Every key and token convar is protected, so it isn't sent to clients or recorded in demos. Never commit them, and never put them in a Workshop upload.
