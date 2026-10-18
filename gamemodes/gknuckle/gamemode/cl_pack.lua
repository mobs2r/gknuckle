-- playable-pack, client side. Included first by cl_init.lua so a pack cached from an
-- earlier session is mounted before any other gKnuckle Lua creates Material()s
-- (game.MountGMA does not repair error materials that were already loaded).
-- First time: the server hands over a short-lived signed Bunny URL; the whole pack
-- is fetched in 8 MiB Range chunks, each checked with util.SHA256 against the
-- manifest, appended to data/gknuckle/packs/, resumable across crashes and sessions.
-- Then game.MountGMA, re-init hooks (GK_PackMounted), and gk_pack_ready to the server.
include("sh_pack.lua")

local P = GK.Pack
P.state = P.state or "idle"     -- idle | waiting | downloading | paused | mounted | unlicensed | unavailable | error
P.msg = P.msg or ""

-- Record surface.CreateFont calls so fonts can be rebuilt after the pack mounts
-- (the MonocleFixed / Smart 9 .ttf files live in the pack).
P.fonts = P.fonts or {}
if not P.fontHooked then
    P.fontHooked = true
    local create = surface.CreateFont
    surface.CreateFont = function(name, data)
        P.fonts[name] = data
        return create(name, data)
    end
    P.rawCreateFont = create
end

local function readIndex() return util.JSONToTable(file.Read(P.INDEX, "DATA") or "") or {} end
local function writeIndex(t)
    file.CreateDir(P.DIR)
    file.Write(P.INDEX, util.TableToJSON(t))
end

local function mount(idx, early)
    if P.mountedSha == idx.sha256 then return true end
    local ok, files = game.MountGMA("data/" .. idx.file)
    if not ok then
        P.state, P.msg = "error", "The gKnuckle content pack couldn't be mounted. It will be downloaded again."
        idx.complete, idx.done = false, 0
        file.Delete(idx.file)
        writeIndex(idx)
        return false
    end
    P.mountedSha, P.mountedEarly, P.state, P.msg = idx.sha256, early, "mounted", ""
    MsgN(("[gKnuckle] mounted playable-pack %s (%d files)%s"):format(string.sub(idx.sha256, 1, 12), #files, early and " at startup" or ""))
    if not early then
        -- Loaded late: rebuild what already read pack files.
        for name, data in pairs(P.fonts) do P.rawCreateFont(name, data) end
        for _, e in ipairs(ents.GetAll()) do
            local m = IsValid(e) and e.GetModel and e:GetModel()
            if m and string.StartsWith(m, "models/gknuckle/") then e:SetModel(m) end
        end
        hook.Run("GK_PackMounted", files)
        chat.AddText(Color(120, 200, 255), "[gKnuckle] ", color_white,
            "Content installed. Levels are unlocked. Rejoin once (gk_pack_rejoin) so every texture loads.")
    end
    return true
end

-- A pack cached from an earlier session: mount it right now, while this file loads.
do
    local idx = readIndex()
    if idx.complete and idx.file and idx.sha256 and file.Size(idx.file, "DATA") == idx.bytes then
        mount(idx, true)
    end
end

local function sendHello()
    net.Start("gk_pack_hello")
    net.WriteString(P.mountedSha or "")
    net.SendToServer()
end
local function sendReady(sha)
    net.Start("gk_pack_ready")
    net.WriteString(sha)
    net.SendToServer()
end
local function askRefresh()
    if P.refreshPending and P.refreshPending > RealTime() then return end
    P.refreshPending = RealTime() + 10
    net.Start("gk_pack_refresh")
    net.SendToServer()
end

-- Downloader ------------------------------------------------------------------------
local RETRY = { 2, 5, 15 }

local function finish(idx)
    idx.complete = true
    writeIndex(idx)
    P.progress = idx.bytes
    if P.mountedSha and P.mountedSha ~= idx.sha256 then
        -- An older pack is already mounted this session and can't be unmounted.
        P.state, P.msg = "update", "A gKnuckle content update has downloaded. Restart Garry's Mod to use it."
        chat.AddText(Color(120, 200, 255), "[gKnuckle] ", color_white, P.msg)
        return
    end
    if mount(idx, false) then sendReady(idx.sha256) end
end

local nextChunk
local function retryLater(idx, reason)
    P.tries = (P.tries or 0) + 1
    if P.tries > #RETRY then
        P.tries = 0
        P.state, P.msg = "paused", "Download paused (" .. reason .. "). Retrying in a minute; the hub stays playable."
        timer.Create("GK_PackResume", 60, 1, function() askRefresh() end)
        return
    end
    timer.Simple(RETRY[P.tries], function() nextChunk(idx) end)
end

nextChunk = function(idx)
    local o = P.offer
    if not o or o.sha256 ~= idx.sha256 then return end
    if idx.done >= #o.chunks then return finish(idx) end
    -- The signed URL lives a minute or two: get a new one shortly before it runs out.
    if RealTime() > o.expiresAt - 8 then
        P.state = "waiting"
        P.waitingIdx = idx
        return askRefresh()
    end
    local i = idx.done + 1
    local from = (i - 1) * o.chunkSize
    local to = math.min(from + o.chunkSize, o.bytes) - 1
    local have = file.Size(idx.file, "DATA") or 0
    if have ~= from then
        -- A chunk was half-written when the game closed: start that pack again.
        if have > from then file.Delete(idx.file) idx.done = 0 writeIndex(idx) return nextChunk(idx) end
        idx.done = math.floor(have / o.chunkSize)
        writeIndex(idx)
        return nextChunk(idx)
    end
    P.state = "downloading"
    HTTP({
        url = o.url,
        method = "GET",
        headers = { Range = ("bytes=%d-%d"):format(from, to) },
        timeout = 60,
        success = function(code, body)
            if not P.offer or P.offer.sha256 ~= idx.sha256 then return end
            if code == 401 or code == 403 then
                P.state, P.waitingIdx = "waiting", idx
                return askRefresh()
            end
            local want = to - from + 1
            if (code ~= 206 and not (code == 200 and from == 0 and want == o.bytes)) or not body or #body ~= want then
                return retryLater(idx, "bad response " .. tostring(code))
            end
            if util.SHA256(body) ~= o.chunks[i] then return retryLater(idx, "chunk " .. i .. " failed its sha256 check") end
            file.Append(idx.file, body)
            body = nil
            if file.Size(idx.file, "DATA") ~= to + 1 then return retryLater(idx, "couldn't write to data/") end
            idx.done = i
            P.progress = to + 1
            writeIndex(idx)
            P.tries = 0
            if i % 8 == 0 then collectgarbage("step", 4096) end
            timer.Simple(0, function() nextChunk(idx) end)
        end,
        failed = function(err) retryLater(idx, tostring(err)) end,
    })
end

local function startDownload(o)
    local idx = readIndex()
    if idx.sha256 ~= o.sha256 then
        -- New release: drop an unfinished older download (a finished, mounted one is
        -- removed on a later launch once it's no longer in use).
        if idx.file and not idx.complete then file.Delete(idx.file) end
        if idx.file and idx.complete then
            local old = readIndex().old or {}
            old[#old + 1] = idx.file
            idx = { old = old }
        else
            idx = { old = idx.old }
        end
        idx.sha256, idx.bytes, idx.chunkSize, idx.file, idx.done, idx.complete = o.sha256, o.bytes, o.chunkSize, P.FileFor(o.sha256), 0, false
        file.CreateDir(P.DIR)
        if file.Exists(idx.file, "DATA") then file.Delete(idx.file) end
        writeIndex(idx)
    end
    if idx.complete and file.Size(idx.file, "DATA") == idx.bytes then return finish(idx) end
    P.tries = 0
    P.progress = file.Size(idx.file, "DATA") or 0
    nextChunk(idx)
end

net.Receive("gk_pack_offer", function()
    local status, message, link = net.ReadString(), net.ReadString(), net.ReadString()
    P.link = link
    if status == "disabled" then P.state, P.msg = "idle", "" return end
    if status ~= "ok" then
        -- Unlicensed or the API is down. A cached pack for this release still counts.
        P.offer = nil
        if P.mountedSha then sendReady(P.mountedSha) end
        P.state = P.mountedSha and "mounted" or status
        P.msg = P.mountedSha and "" or message
        if status == "unlicensed" and not P.mountedSha then chat.AddText(Color(255, 170, 90), "[gKnuckle] ", color_white, message) end
        if status == "unavailable" then timer.Create("GK_PackHelloRetry", 120, 1, sendHello) end
        return
    end
    local o = { url = net.ReadString(), expiresAt = RealTime() + net.ReadUInt(12), sha256 = net.ReadString(),
        bytes = net.ReadDouble(), chunkSize = net.ReadUInt(32), chunks = {} }
    for i = 1, net.ReadUInt(10) do o.chunks[i] = net.ReadString() end
    local refreshing = P.offer and P.offer.sha256 == o.sha256
    P.offer = o
    P.refreshPending = nil
    if P.mountedSha == o.sha256 then sendReady(o.sha256) return end
    if refreshing and P.state == "downloading" then return end -- current chunk carries on with the old URL
    if refreshing and P.waitingIdx then local idx = P.waitingIdx P.waitingIdx = nil return nextChunk(idx) end
    startDownload(o)
end)

hook.Add("InitPostEntity", "GK_PackHello", function()
    -- Leftover packs from older releases (no longer mounted this session).
    local idx = readIndex()
    for _, f in ipairs(idx.old or {}) do if f ~= idx.file then file.Delete(f) end end
    if idx.old then idx.old = nil writeIndex(idx) end
    P.state = P.mountedSha and "mounted" or "waiting"
    timer.Simple(1, sendHello)
end)

concommand.Add("gk_pack_retry", function()
    P.state, P.msg = "waiting", ""
    sendHello()
end)
concommand.Add("gk_pack_rejoin", function() RunConsoleCommand("retry") end)

-- HUD: progress while downloading, the reason when it can't.
surface.CreateFont("GK_PackHUD", { font = "Tahoma", size = 18, weight = 600 })
hook.Add("HUDPaint", "GK_PackHUD", function()
    if GetGlobal2Bool("gk_pack_gate", false) == false then return end
    local text
    if P.state == "downloading" or P.state == "waiting" then
        local o = P.offer
        if o then
            local cur = P.progress or 0
            local done = cur / o.bytes
            text = ("Downloading gKnuckle content: %d%%  (%d / %d MB). Levels unlock when it's done; the hub is playable.")
                :format(math.floor(done * 100), math.floor(cur / 1e6), math.floor(o.bytes / 1e6))
        else
            text = "Checking gKnuckle content..."
        end
    elseif P.state == "unlicensed" or P.state == "unavailable" or P.state == "paused" or P.state == "error" or P.state == "update" then
        text = P.msg ~= "" and P.msg or GK.Pack.LinkMessage(P.link)
    end
    if not text then return end
    local w = ScrW()
    surface.SetFont("GK_PackHUD")
    local tw, th = surface.GetTextSize(text)
    draw.RoundedBox(4, w / 2 - tw / 2 - 10, 8, tw + 20, th + 10, Color(10, 12, 16, 210))
    draw.SimpleText(text, "GK_PackHUD", w / 2, 13, Color(220, 230, 240), TEXT_ALIGN_CENTER)
end)
