# gKnuckle ↔ Illicit/Omerta API spec

Status: **draft, nothing built or deployed.** This revision follows:
- Cod City's pattern and cod.city draft PR #27
- Vlad's API/DB review against crabcoin-api `omerta`
- the security review (H1–M7, L-items)

The gamemode side is on `mobs2r/gknuckle` branch `next`; every call it makes is listed in `CALLS.md`. Routes marked **(exists)** are on crabcoin-api `omerta` today. Everything else is **(planned)**.

> **Pending decision:** whether licensed White Knuckle content may be served from Bunny at all is a legal/business call for mobs2r / Illicit and DreadXP / Dark Machine Games. Until then, keep `gk_pack_api` empty on servers. That turns gating off and keeps the current Workshop behaviour. The licence gate is a convenience gate, not DRM (§3.1, M1).

## 1. Service authentication (game server → API)

**Per-server keys (H1, Vlad HIGH).**
- Each game server gets its own key from `gknuckle.server_keys`, in the form `id:secret`.
- The secret is stored hashed or encrypted.
- Scopes:
  - `gk:wallet`: balance, add, deduct, gknuckle wallet, access-role
  - `gk:pack`: delivery and manifest
  - `gk:bans`: check and report
- Daily caps apply per key and per steam_id on money routes.
- The gamemode **never sends the secret**. It sends only the id and signs with the secret (`sv_apiauth.lua`).

| Header | Value |
|---|---|
| `X-GKnuckle-Key` | key **id** |
| `X-GKnuckle-Timestamp` | unix seconds (game server applies the offset learned from `server_time`) |
| `X-GKnuckle-Nonce` | 32 hex chars, unique per request |
| `X-GKnuckle-Signature` | `base64url_nopad(HMAC-SHA256(secret, canonical))` |
| `Idempotency-Key` | optional, 8–128 `[A-Za-z0-9_-]` |

The canonical string includes the key id (H1). PATH has no query string, and the body is the exact bytes sent (`""` for GET):
```
METHOD \n PATH \n KEY_ID \n TIMESTAMP \n NONCE \n hex(sha256(body))
```

**API checks, in order.** Every failure is **401** with a `reason`:
1. Key id is known and active (`bad_key`), and the route is inside the key's scope (`scope`).
2. Timestamp is within ±60 s (`stale`). The response includes `server_time`; the game server corrects its clock and retries once.
3. Signature compared with `crypto.timingSafeEqual` on the decoded 32 bytes, after a length check (`bad_signature`).
4. **Nonce cache keyed on (key id, nonce) for 120 s** (M3: covers the whole ±60 s window), or until `ts + 60`, whichever is later (`replay`).

**401 is for auth only.** Licence, ban or business "no" answers are 200 with a reason, or 403 on licence routes.

**Signing implementation.** The game server's HMAC runs on a pure-Lua SHA-256, never on `util.SHA256` (H3). At load it self-tests against the RFC 4231 #2 vector plus a NUL, `6` and `\` vector, and refuses to sign if that fails. `tests/apiauth_test.lua` reproduces a Python `hmac` signature offline.

**Origins (H2).** Keys only go to origins pinned in code: `GK.ApiAuth.ORIGINS` in `sv_apiauth.lua`.
- There is one list per purpose (N8):
  - `api` (signed calls): `https://illicit.up.railway.app`, `https://api.gk.style`
  - `chat` (Omerta bot token): `https://illicit.up.railway.app`, `https://omerta.chat`, `https://www.omerta.chat`
- The gk.style web host is on neither list.
- Convars can't add origins.
- 3xx is a failure, and only 2xx is success.

**Legacy key.** `gk_economy_key` may still be the global `API_SECRET`, but it is only sent (as `X-Api-Key`, to a pinned `api` origin) when the server also sets `gk_economy_legacy_key 1`. The default is 0, with a red console warning either way. **The live server needs a per-server key or that convar, or its economy stops.** Remove the path once per-server keys ship.

## 2. Licence model (`licenses/<linkId>` pattern)

**Tables.** `gknuckle.licenses` holds `link_id`, `account_id` (Omerta, via `auth_identities`), `steam_id64`, `status` (active/revoked/pending), `source`, `verified_at`, `checked_at`, `revoked_at` and `reason`. Other tables: `gknuckle.delivery_log` and `gknuckle.idempotency`. There is **no** gknuckle bans table (§7).

**Rules:**
- **Ownership:** White Knuckle (Steam app **3195790**) is in the account's Steam library. The API calls `IPlayerService/GetOwnedGames` with the Railway env var **`STEAM_API_KEY`** (not `STEAM_WEB_API_KEY`).
- **Private profile:** an empty answer from a private profile gives `pending` with reason `profile_private`.
- **Re-check:** every 7 days, on delivery and asynchronously.
- **Fail-open cap (L7):** a failed re-check keeps `active` for at most **30 days** since `verified_at`, then switches to `pending` (`profile_private`).
- **Linking:** happens only on gk.style, in the Steam OpenID session.

## 3. Endpoints

**Access by caller (H4):**
- **Game-server keys** (`gk:pack`) may call **only** `POST /api/integrations/gknuckle/delivery` and `POST …/manifest`.
- `licenses/*` is **session-only on gk.style**, bound to the session's own steam_id, with no `link_id` or `steam_id` parameter. It is never reachable with a game-server key.
- `status` never returns `link_id` to anyone but its owner.
- The API logs and alerts on per-key `steam_id` fan-out (many distinct players per key per hour).

### 3.1 `POST /api/integrations/gknuckle/delivery` (planned; `sv_pack.lua`)

Request:
```json
{ "steam_id": "7656119…", "client_ip": "203.0.113.7", "have_sha256": "48e0…" }
```
The game server only sends this after `ply:IsFullyAuthenticated()` (L5). `client_ip` is omitted for loopback and singleplayer.

**200, licensed:**
```json
{ "licensed": true, "release": "gKnuckle/ver0.5.0", "server_time": 1792291306, "link_url": "https://gk.style/link",
  "files": [{ "route": "playable-pack",
    "url": "https://<pullzone>.b-cdn.net/gKnuckle/ver0.5.0/data/<random24hex>.gma?token=…&expires=…",
    "expires": 1792291366, "bytes": 856620377,
    "sha256": "48e09ef6f5fbfca14d3550c8aa5b0c787d9d412196944ffa35122d28277437c7",
    "chunk_size": 8388608, "chunk_sha256": ["…103 hex…"] }] }
```

**Game-server checks.** These match the client's own checks (M2):
- `route` is `playable-pack`.
- `url` uses `https://`.
- `sha256` is 64 hex **and on `GK.Pack.RELEASES` in the shipped gamemode**.
- `bytes`, `chunk_size` and `sha256(concat(chunk_sha256))` equal the values pinned for that release in `GK.Pack.RELEASES` (N2). A new release needs a gamemode update with its pins.
- `chunk_size` is 1–32 MiB.
- There are exactly `ceil(bytes/chunk_size)` chunk hashes, at most 512, each 64 hex.
- At least 5 s of validity remain.

**200, not licensed:** `{ "licensed": false, "reason": "not_linked" | "not_owned" | "profile_private" | "revoked" | "banned", "link_url": … }`.
- `banned` means Omerta's `core.is_globally_banned` for the mapped account (Vlad). The player gets no link prompt, only a ban notice.
- The game server **clears** that player's ready flag on any not-licensed answer (M1).

**403:** treated as not licensed.

**5xx or timeout:** "content server unreachable". Only in this state does the game server accept a client's report of the cached release `gk_pack_sha256` as ready (M1). New downloads wait.

### 3.2 `POST /api/integrations/gknuckle/manifest` (planned)
Body `{}`. Returns the current release's manifest (release, bytes, sha256, chunk_size, chunk_sha256, createdAt). There's no URL in it.

### 3.3 gk.style session routes (planned; not callable by game servers)
- `GET /api/gknuckle/license`: the signed-in user's own licence (`status`, `reason`, `verified_at`).
- `POST /api/gknuckle/license/verify`: re-run GetOwnedGames for the session's own account. Takes `Idempotency-Key`, limited to 1 per 30 s.
- `POST /api/gknuckle/license/unlink`: the session's own account only.

### 3.4 `GET /api/private/access-role/:steamid64` (Vlad's endpoint, planned; `sh_admin.lua`)
- **Scope:** `gk:wallet`, signed per §1.
- **Response:** `200 { "role": "owner" | "admin" | "moderator" | null }`.
- **Mapping:** Omerta staff roles, through the account mapping. For example, mobs2r (Omerta uid 1, Steam 76561199041513241) is `owner`.
- **Game-server caching:** 5 min, or 60 s after a failure.
- **Failure:** fails closed. The player gets nothing beyond the `gk_owner_steamids` convar and CAMI.
- **What each role grants in game:**
  - owner: every `gknuckle.*` privilege
  - admin: every admin-level privilege
  - moderator: `gknuckle.moderate` (gk_mod_kick, gk_community_mute), `gknuckle.community_admin` and `gknuckle.bans_view`

## 4. Bunny signed URLs (Vlad MEDIUM, M6)

**Storage:** `gKnuckle/<release>/data/<random24hex>.gma`. The manifest lives outside the pull zone or in a separate folder. **Nothing else goes in a release's `data/` folder.**

**Token:**
```
token = base64url_nopad(SHA256_raw(BUNNY_TOKEN_AUTH_KEY + token_path + expires [+ client_ip]))
```
- `token_path` is the **exact `.gma` path** (`/gKnuckle/<release>/data/<file>.gma`), so it is bound under `/gKnuckle/<release>/` and scoped to that single file (M6). Range requests work with a file-scoped token.
- **TTL:** `BUNNY_TOKEN_TTL` defaults to **60 s with a hard max of 60** (values above 60 are clamped). The client asks for a fresh URL before every chunk once less than 8 s remain, or on 401/403. It's rate-limited to one refresh per 8 s per player.
- **IP binding:** with `BUNNY_TOKEN_IP=1`, IP binding is used when `client_ip` is a known IPv4.
- **Re-sharing:** accepted, and the business side should be told. Any licensed player can re-share the downloaded GMA.

## 5. Environment (API)

| Var | Meaning |
|---|---|
| `GK_ASSET_CDN_ORIGIN` | `https://<pullzone>.b-cdn.net` |
| `GK_ASSET_RELEASE` | `gKnuckle/ver0.5.0` |
| `BUNNY_TOKEN_AUTH_KEY` | pull zone token key |
| `BUNNY_TOKEN_TTL` | default 60, max 60 |
| `BUNNY_TOKEN_IP` | `0`/`1` |
| `STEAM_API_KEY` | GetOwnedGames (already on Railway) |
| `GK_LINK_URL` | `https://gk.style/link` |

Server keys live in `gknuckle.server_keys`, not in env.

## 6. COMMUNiTY chat (Omerta bot API; crabcoin-api PR #180)

**Setup:**
- Each game server is an Omerta bot (`players.is_bot`) created on the bot desk.
- It's installed in the `#gknuckle` room with **read** and **send** permissions, not mention.
- The token `omb_…` goes in the protected convar `gk_community_bot_token`. There's no separate chat key.
- This waits on #180's security fixes (Vlad).

**Messages in (exists in #180):** `POST /api/bots/v1/channels/:channel/messages`, `Authorization: Bot omb_…` → `201 { id }`.
- Body: `{ "body": "<text>", "relayed_for": { "steam_id": "7656119…", "name": "<nick>" }, "kind"?: "join"|"leave"|"death" }`. Player text is never prefixed with a name (N4).
- **Requested of Omerta:**
  - accept `relayed_for` and render it as "<name> via <bot name>", visibly different from a real account
  - reserve staff display names
  - render bot bodies as escaped plain text
- Until Omerta does this, relayed lines show under the bot's name without the player's name.
- Omerta runs `insertChatMessage`, which applies bans, blocked terms and no external links.

**Messages out (polled):** game servers can't receive Omerta's signed webhooks (no inbound HTTPS), so they poll every ~2 s.
- **Exists in #180:** `GET /api/bots/v1/channels/:channel/messages?before&limit` (≤50, newest first) → `{ messages: [{ id, authorId, body, createdAt }] }`.
- **Requested additions** (the gamemode already sends and uses them when present):
  - `after=<id>`: messages with `id > after`, oldest first (so polls don't re-read 50 rows)
  - `author: { name, isBot }` on each message (so names show in game; otherwise "web")
  - a read rate limit that tolerates 1 request per 2 s per bot

**Limits:**
- Omerta's bot send caps are `CHAT_BOT_SENDS_PER_MINUTE` 20 and `CHAT_BOT_SENDS_PER_DAY` 400.
- The gamemode keeps itself to 18/min and 380/day for the bot.
- Per SteamID (not per connection): 1.5 s apart, 8/min, and at most 25% of the daily budget (N12).
- It tells players when a line stays in-game.
- Relay mutes (`gk_community_mute`) persist in `data/gknuckle/community_mutes.json`.

**Text rules (both directions):**
- Control characters, newlines, bidi overrides and isolates, zero-width marks and U+FEFF are stripped (N11).
- Anything link-like is kept in-game: `://`, `//`, `www.`, `hxxp`, markdown links, and `name.tld` for common TLDs.
- Every `@` is defused.
- In game, web authors are shown as `web:<name>` and other servers as `server:<name>`.
- Lines are capped at 280 chars and names at 32.
- `@word` is defused with a ZWSP, and links aren't sent.
- Only chat that was really said (the `player_say` event, after gags and filters) is relayed.
- The relay ignores its own lines (by returned id, by text for 60 s, and by `gk_community_bot_id`).

## 7. Bans (Omerta global ban; no gknuckle bans table)

### `POST /api/integrations/gknuckle/bans/check` (planned; scope `gk:bans`)
- **Request:** `{ "steam_id": "…", "owner_steam_id": "…" }` (the owner of a family-shared licence, if different).
- **Response:** `200 { "banned": bool, "reason": "…", "until": unix|null, "scope": "omerta_global" }`.
- **Backing:** `core.is_globally_banned(account)` via `auth_identities`, for either id.
- **Caching:** the game server caches not-banned answers for 120 s and banned ones for 300 s.
- **When the API can't answer:** `gk_bans_failmode` decides, `open` (default) or `closed`.

### `POST /api/integrations/gknuckle/bans/report` (planned; scope `gk:bans`)
- **Request:** `{ "event_id", "action": "ban"|"unban", "steam_id", "minutes" (0 = permanent), "reason", "admin_steam_id", "source": "ulx"|"sam", "server" }` → `200 { accepted: true }`.
- **Moderation, not auto-ban:** a reported in-game ban goes into Omerta's moderation queue and on bans.gk.style. It does **not** become a global ban automatically. A moderator promotes it.
- **Duplicates:** an `event_id` is applied at most once.

## 8. Wallet and backpack routes the gamemode uses

| Route | Status | Gamemode use |
|---|---|---|
| `GET /api/private/balance/:steamid64` | exists | `balance`, `b1_count` (no separate B1 call) |
| `POST /api/private/add` `{steam_id, amount, reason, event_id}` | exists; `event_id` **requested** (Vlad) | rewards; amount is a finite integer 1–1000 |
| `POST /api/private/deduct` `{…, event_id}` | exists; `event_id` requested | shop |
| `GET /api/private/gknuckle/:steamId` | exists; **`version` requested** (not returned today) | `bugz` → roach bank, `version` |
| `POST /api/private/gknuckle/save` `{steam_id, event_id, bugz, source, version}` | exists; **`version` requested** | backpack save |
| `GET /api/private/access-role/:steamid64` | planned (§3.4) | owner/admin/moderator |

**Requested API changes:**
- **`GET /api/private/gknuckle/:steamId` must return `version`** (the stored backpack version, an integer; `0` when none) alongside `bugz`. Prod doesn't return it today and `/save` ignores the `version` it is sent, so the gamemode's version handling (e5788f2, N6: continue from `max(stored, local)+1`, reload on 409) has nothing to work with until both this field and the 409 check below exist.
- `/add` must be idempotent on `event_id`: a repeated `event_id` returns the original result and pays nothing more. Until it is, the gamemode treats a timeout, 5xx or unclear answer as "maybe paid" and doesn't give the daily allowance back (R4); only a 4xx (other than 408) or a request that was never sent is refunded.
- Make `event_id` required on `/add` and `/deduct`, with daily caps per key and per steam_id. Answer a capped `/add` with **429 `{ reason: "daily_cap" }`**. The gamemode also keeps its own per-SteamID cap (`gk_economy_daily_cap`, default 300/day, persisted; admin grants are exempt).
- For `/gknuckle/save`: store `version` per account and answer **409 `{ version }`** to a save whose `version` isn't higher than the stored one, so a late save can't overwrite a newer one (M7). `GET /gknuckle/:steamId` must return `version`. The game server continues from `max(stored, local)+1` and reloads on 409 (N6).
- Store xenium and bag items (they're local-only until then).
- Removed from the gamemode: `/api/private/ensure` and `/api/private/b1/:id` (they never existed).

## 9. Reason codes

| Reason | HTTP | Meaning |
|---|---|---|
| `bad_key`, `scope`, `stale`, `bad_signature`, `replay` | 401 | auth only |
| `bad_request` | 400 | |
| `not_linked`, `not_owned`, `profile_private`, `revoked`, `banned` | 200 (`licensed:false`) / 403 | licence |
| `rate_limited` | 429 | |
| `release_unavailable` | 503 | |

## 10. Logging

- **Logged:** key id, route, steam_id64, result and reason.
- **Never logged:** signatures, secrets, bot tokens, signed URLs or headers. `client_ip` isn't stored beyond the request.
