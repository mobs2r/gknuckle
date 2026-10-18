-- COMMUNiTY chat bridge: in-game chat <-> the #gknuckle room on Omerta (shown on gk.style).
-- Each game server is its own Omerta bot (crabcoin-api PR #180 bot desk, "omb_" token),
-- installed in the room with read + send permissions. API_SPEC.md §6.
--   in:  POST {api}/api/bots/v1/channels/<channel>/messages   Authorization: Bot <token>
--        { body = "<player>: <text>" } -> 201 { id }
--   out: GET  {api}/api/bots/v1/channels/<channel>/messages?limit=50[&after=<id>]
--        -> { messages = [ { id, authorId, body, createdAt[, author = { name, isBot }] } ] }
--        polled every ~2 s: game servers can't take Omerta's signed webhooks.
--        (after= and author{} are proposed additions; without them the newest 50 are
--        read and filtered by id, and names fall back to "web".)
-- server.cfg:
--   gk_community_api        "https://illicit.up.railway.app"   (must be on GK.ApiAuth.ORIGINS)
--   gk_community_bot_token  "omb_..."                           (protected, never sent to clients)
--   gk_community_channel    "gknuckle"
-- Empty api or token = bridge off.

if GKCommunity and GKCommunity.loaded and not GKCommunity.gamemode then
    print("[COMMUNiTY] the portal's gk_community_sv.lua is already running; gamemode bridge not started")
    return
end
GKCommunity = { loaded = true, gamemode = true } -- makes the portal copy step aside if it loads later

util.AddNetworkString("gk_community")
AddCSLuaFile("cl_chatbridge.lua")

local cvApi     = CreateConVar("gk_community_api", "", { FCVAR_ARCHIVE, FCVAR_PROTECTED }, "Omerta API origin for the COMMUNiTY bot (empty = bridge off)")
local cvToken   = CreateConVar("gk_community_bot_token", "", { FCVAR_PROTECTED, FCVAR_DONTRECORD }, "This server's Omerta bot token (omb_...), never sent to clients")
local cvChannel = CreateConVar("gk_community_channel", "gknuckle", { FCVAR_ARCHIVE }, "Omerta room the bot relays")
local cvBotId   = CreateConVar("gk_community_bot_id", "", { FCVAR_ARCHIVE }, "This bot's authorId on Omerta (optional; skips its own lines)")
local cvPoll    = CreateConVar("gk_community_poll", "2", { FCVAR_ARCHIVE }, "Seconds between room polls", 1, 30)
local cvEvents  = CreateConVar("gk_community_events", "0", { FCVAR_ARCHIVE }, "Post join/leave lines (uses the bot's send budget)")
local cvDeaths  = CreateConVar("gk_community_deaths", "0", { FCVAR_ARCHIVE }, "Also post death lines (needs gk_community_events 1)")

local MAX_BODY, MAX_NAME = 280, 32       -- Omerta takes 2000; keep game lines chat-sized
local USER_GAP, USER_BURST = 1.5, 8      -- per player: 1.5 s apart, 8 a minute
local SEND_GAP, QUEUE_MAX = 3.0, 10      -- Omerta's bot cap is 20/min and 400/day per bot
local BOT_PER_MIN, BOT_PER_DAY = 18, 380 -- stay under it so a busy server degrades politely

local C = { cursor = 0, primed = false, number = nil, seen = {}, seenOrder = {}, queue = {},
    inflight = false, inflightAt = 0, nextPoll = 0, fails = 0, lastSend = 0, warned = {}, sent = {}, recent = {}, day = { d = os.date("%Y%m%d"), n = 0 } }
GKCommunity.state = C

local function origin() return GK.ApiAuth.Origin(cvApi:GetString()) end
local function channel()
    local c = string.lower(string.Trim(cvChannel:GetString()))
    return string.match(c, "^[%w_%-]+$") and c or nil
end
local function enabled()
    return cvToken:GetString() ~= "" and origin() ~= nil and channel() ~= nil
end
local function warn(kind, msg)
    if C.warned[kind] then return end
    C.warned[kind] = true
    MsgC(Color(255, 154, 31), "[COMMUNiTY] ", tostring(msg), "\n")
end

-- Control characters out (newlines too: one chat line per message), whitespace
-- squashed, valid UTF-8, cut on a character boundary.
local function clean(s, max)
    s = tostring(s or "")
    if utf8.force then s = utf8.force(s) end
    s = string.gsub(s, "[%z\1-\31\127]", " ")
    s = string.gsub(s, "\226\128[\168\169\170-\174]", " ") -- U+2028/2029 separators, bidi overrides
    s = string.Trim(string.gsub(s, "%s+", " "))
    if utf8.len(s) and utf8.len(s) > max then
        s = string.sub(s, 1, (utf8.offset(s, max + 1) or (#s + 1)) - 1)
    elseif #s > max * 4 then
        s = string.sub(s, 1, max)
    end
    return s
end
GKCommunity.Clean = clean

local function remember(id)
    id = tostring(id or "")
    if id == "" or C.seen[id] then return false end
    C.seen[id] = true
    C.seenOrder[#C.seenOrder + 1] = id
    if #C.seenOrder > 400 then C.seen[table.remove(C.seenOrder, 1)] = nil end
    return true
end
local function advance(id)
    local n = tonumber(id)
    if n and n > C.cursor then C.cursor = n end
end

local function request(method, path, body, onDone)
    HTTP({
        url = origin() .. path, method = method, timeout = 15,
        headers = { ["Authorization"] = "Bot " .. cvToken:GetString(), ["Accept"] = "application/json" },
        type = body and "application/json" or nil,
        body = body and util.TableToJSON(body) or nil,
        success = function(code, resp)
            if code >= 300 and code < 400 then return onDone(0, { error = "redirect " .. code }) end
            onDone(code, util.JSONToTable(resp or "") or {})
        end,
        failed = function(err) onDone(0, { error = tostring(err) }) end,
    })
end
local function roomPath() return "/api/bots/v1/channels/" .. channel() .. "/messages" end

-- Omerta -> game -----------------------------------------------------------------------
local function show(m)
    if not istable(m) then return end
    local id = m.id
    advance(id)
    if not remember(id) then return end
    if C.sent[tostring(id)] then return end -- a line this server posted
    local botId = string.Trim(cvBotId:GetString())
    if botId ~= "" and tostring(m.authorId or "") == botId then return end
    local body = clean(m.body, 300)
    if body == "" then return end
    -- Our own POST may not have answered yet when the poll sees the line: match by text.
    if (C.recent[body] or 0) > CurTime() then return end
    local author = istable(m.author) and m.author or {}
    local name = clean(author.name or m.authorName or m.username, MAX_NAME)
    local where = author.isBot and "server" or "web"
    if name == "" then name = where == "web" and "web" or "server" end
    net.Start("gk_community")
    net.WriteString(where)
    net.WriteString(name)
    net.WriteString(body)
    net.WriteString("")
    net.Broadcast()
end

local function poll()
    if C.inflight then
        if CurTime() - C.inflightAt < 30 then return end
        C.inflight = false -- a lost callback; try again
    end
    C.inflight, C.inflightAt = true, CurTime()
    local q = "?limit=50" .. (C.cursor > 0 and ("&after=" .. string.format("%d", C.cursor)) or "")
    request("GET", roomPath() .. q, nil, function(code, data)
        C.inflight = false
        if code ~= 200 then
            C.fails = C.fails + 1
            C.nextPoll = CurTime() + math.min(60, cvPoll:GetFloat() * 2 ^ math.min(C.fails, 5))
            if code == 401 or code == 403 then warn("auth", "Omerta refused the bot token or room permission (" .. code .. ")")
            else warn("poll", "poll failed: " .. (code > 0 and ("HTTP " .. code) or tostring(data.error))) end
            return
        end
        if C.fails > 0 then MsgC(Color(255, 154, 31), "[COMMUNiTY] Omerta reachable again\n") end
        C.fails, C.warned.poll, C.warned.auth = 0, nil, nil
        local list = {}
        for _, m in ipairs(istable(data.messages) and data.messages or {}) do
            if istable(m) and tonumber(m.id) and tonumber(m.id) > C.cursor then list[#list + 1] = m end
        end
        table.sort(list, function(a, b) return tonumber(a.id) < tonumber(b.id) end) -- the API answers newest first
        if not C.primed then
            -- First answer after a (re)load: skip the backlog instead of replaying old lines.
            C.primed = true
            for _, m in ipairs(list) do advance(m.id) remember(m.id) end
            return
        end
        for _, m in ipairs(list) do show(m) end
    end)
end

-- Game -> Omerta -----------------------------------------------------------------------
local function tell(ply, msg)
    if IsValid(ply) then ply:ChatPrint("[COMMUNiTY] " .. msg) end
end

local function userAllowed(ply)
    local now = CurTime()
    local hits = ply.GK_CommunityHits or {}
    local kept = {}
    for _, t in ipairs(hits) do if now - t < 60 then kept[#kept + 1] = t end end
    if (#kept > 0 and now - kept[#kept] < USER_GAP) or #kept >= USER_BURST then
        ply.GK_CommunityHits = kept
        return false
    end
    kept[#kept + 1] = now
    ply.GK_CommunityHits = kept
    return true
end

local function enqueue(item)
    if #C.queue >= QUEUE_MAX then table.remove(C.queue, 1) end
    C.queue[#C.queue + 1] = item
end

local function budgetOk()
    local now, today = CurTime(), os.date("%Y%m%d")
    if C.day.d ~= today then C.day = { d = today, n = 0 } end
    local kept = {}
    for _, ts in ipairs(C.minute or {}) do if now - ts < 60 then kept[#kept + 1] = ts end end
    C.minute = kept
    return #kept < BOT_PER_MIN and C.day.n < BOT_PER_DAY
end

local function flush()
    if C.sending or #C.queue == 0 or CurTime() - C.lastSend < SEND_GAP then return end
    if not budgetOk() then
        local item = table.remove(C.queue, 1)
        if item.ply then tell(item.ply, "the gk.style relay is busy; that line stayed in-game") end
        return
    end
    local item = table.remove(C.queue, 1)
    C.sending, C.lastSend = true, CurTime()
    C.minute[#C.minute + 1] = CurTime()
    C.day.n = C.day.n + 1
    C.recent[clean(item.body, 300)] = CurTime() + 60
    request("POST", roomPath(), { body = item.body }, function(code, data)
        C.sending = false
        if code == 200 or code == 201 then
            if data.id ~= nil then C.sent[tostring(data.id)] = true advance(data.id) remember(data.id) end
            return
        end
        if code >= 400 and code < 500 and item.ply then
            local why = clean(data.error, 120)
            tell(item.ply, "not sent to gk.style" .. (why ~= "" and (": " .. why) or ""))
        elseif code == 0 or code >= 500 then
            warn("send", "send failed: " .. (code > 0 and ("HTTP " .. code) or tostring(data.error)))
        end
    end)
end

-- player_say fires only for chat that was actually said, after every PlayerSay hook
-- (so admin-mod gags/mutes and chat filters apply before anything leaves the server).
gameevent.Listen("player_say")
hook.Add("player_say", "GK_CommunityRelay", function(d)
    if not enabled() or tonumber(d.teamonly) == 1 or d.teamonly == true then return end
    local ply = Player(tonumber(d.userid) or -1)
    if not IsValid(ply) or ply:IsBot() then return end
    local text = clean(d.text, MAX_BODY)
    local first = string.sub(text, 1, 1)
    if text == "" or first == "!" or first == "/" or first == "@" then return end
    if string.find(string.lower(text), "https?://") or string.find(string.lower(text), "www%.") then
        return tell(ply, "links stay in-game (gk.style chat doesn't take them)")
    end
    if not userAllowed(ply) then return tell(ply, "slow down: that line stayed in-game") end
    -- Mentions need a room permission the relay doesn't ask for; defuse them.
    text = string.gsub(text, "@(%a)", "@\226\128\139%1")
    enqueue({ ply = ply, body = clean(ply:Nick(), MAX_NAME) .. ": " .. text })
end)

-- Optional join/leave/death lines (they spend the same bot send budget) ------------
local function event(kind, ply)
    if not enabled() or not cvEvents:GetBool() or not IsValid(ply) or ply:IsBot() then return end
    local verb = kind == "join" and "joined" or kind == "leave" and "left" or "died"
    enqueue({ body = "* " .. clean(ply:Nick(), MAX_NAME) .. " " .. verb })
end
hook.Add("PlayerInitialSpawn", "GK_CommunityJoin", function(ply) timer.Simple(3, function() event("join", ply) end) end)
hook.Add("PlayerDisconnected", "GK_CommunityLeave", function(ply) event("leave", ply) end)
hook.Add("PlayerDeath", "GK_CommunityDeath", function(ply)
    if not cvDeaths:GetBool() or (ply.GK_CommunityNextDeath or 0) > CurTime() then return end
    ply.GK_CommunityNextDeath = CurTime() + 30 -- one notice per player per 30 s
    event("death", ply)
end)

timer.Create("GK_CommunityTick", 0.25, 0, function()
    if not enabled() then
        C.primed = false -- re-prime when it's switched on again
        if cvToken:GetString() ~= "" and cvApi:GetString() ~= "" and not origin() then warn("origin", "gk_community_api isn't on GK.ApiAuth.ORIGINS; bridge off") end
        return
    end
    flush()
    if CurTime() >= C.nextPoll then
        C.nextPoll = CurTime() + cvPoll:GetFloat()
        poll()
    end
end)

for _, n in ipairs({ "gk_community_api", "gk_community_channel", "gk_community_bot_token" }) do
    cvars.AddChangeCallback(n, function() C.primed, C.cursor, C.fails = false, 0, 0 end, "GK_Community")
end

concommand.Add("gk_community_status", function(ply)
    if not GK.RequireAccess(ply, "gknuckle.community_admin") then return end
    local msg = ("[COMMUNiTY] %s, api %s, room #%s, cursor %d, queue %d, sent today %d, fails %d"):format(
        enabled() and "on" or "off", tostring(origin() or "(unset/not allowed)"), tostring(channel()), C.cursor, #C.queue, C.day.n, C.fails)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)
