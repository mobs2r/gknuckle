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

The economy bridge (`sv_economy.lua`, `sv_backpack.lua`) reads its secret from a server convar. Never commit it:

```
gk_economy_api "https://illicit.up.railway.app"
gk_economy_key "<API_SECRET>"     // set in server.cfg only
```
