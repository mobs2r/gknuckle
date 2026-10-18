# gKnuckle

gKnuckle is a **Garry's Mod gamemode inspired by White Knuckle**. It's a climbing and grip-based movement game where you race up vertical courses, fight in arenas and use the CrabCoin economy. It's built and run by **mobs2r / Illicit**.

- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3479529954
- Website: https://gk.style
- Server: `play.gk.style:26147`

## Assets are not included

This repo is **code only**. Everything converted from White Knuckle (models, materials and textures, sounds, fonts, UI icons, the `gk_style` map (`maps/gk_style.bsp`) and the level data in `data_static/gknuckle/`, i.e. `levels/*.json`, `regions.json`, `hub.json`, `dusk.json`, `ghosts.json`, `held.json`) is **not** here. It's distributed only through the [Workshop addon](https://steamcommunity.com/sharedfiles/filedetails/?id=3479529954).

To run it, subscribe to the Workshop addon, or mount its content alongside this code. If you're running a dedicated server, add the Workshop ID to your server's Workshop collection so clients download the content.

The creature entities (`wkn_*`) come from the **White Knuckle NPCs Pack** (https://steamcommunity.com/sharedfiles/filedetails/?id=3818830408) and aren't duplicated here.

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

(data_static/, resource/, maps/, models/, materials/, sound/ come from the Workshop addon)
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
