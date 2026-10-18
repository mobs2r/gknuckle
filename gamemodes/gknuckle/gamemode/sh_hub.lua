-- GK.Hub: the numbers the hub's wall screens show (the map draws the screens).
--
--   GK.Hub.TopKD(n)     -> { { name, kills, deaths, kd }, ... }  best K/D first
--   GK.Hub.TopMoney(n)  -> { { name, roaches }, ... }            most roaches first
--       Both cover everyone who has played on this server (saved to
--       data/gknuckle/leaderboard.json), not just who's online.
--   GK.Hub.Arenas()     -> { [1..GK.Hub.ArenaCount] = { active, alive, total, started, gasHeight, stage, inBreak } }
--       active false: nothing running there, show "PLAY NOW!".
--   GK.VacuumQueue(vac) / GK.VacuumQueueText(vac)  (sh_squads.lua): the ring's
--       "5/12 SUBJECTS_iNiTiATED | STARTiNG iN... m:s:ms" / "WAiTiNG...".
--   gk_godray entity: the garden's blinding light (stare-blind and jitter).
-- Shared: call these on the client from a screen's draw code.
AddCSLuaFile()

GK.Hub = GK.Hub or {}
GK.Hub.ArenaCount = 3

local function decode(key)
    local ok, t = pcall(util.JSONToTable, GetGlobal2String(key, "[]"))
    return ok and t or {}
end

function GK.Hub.TopKD(n)
    local t = decode("gk_top_kd")
    while n and #t > n do table.remove(t) end
    return t
end

function GK.Hub.TopMoney(n)
    local t = decode("gk_top_money")
    while n and #t > n do table.remove(t) end
    return t
end

function GK.Hub.Arenas()
    local out = {}
    for i = 1, GK.Hub.ArenaCount do
        local p = "gk_arena" .. i .. "_"
        out[i] = {
            active = GetGlobal2Bool(p .. "active", false),
            alive = GetGlobal2Int(p .. "alive", 0),
            total = GetGlobal2Int(p .. "total", 0),
            started = GetGlobal2Float(p .. "started", 0),
            gasHeight = GetGlobal2Float(p .. "gas", 0),
            stage = GetGlobal2Int(p .. "stage", 0),        -- region 1..gk_run_regions
            inBreak = GetGlobal2Bool(p .. "break", false), -- resting in the break room
        }
    end
    return out
end

if SERVER then
    local FILE = "gknuckle/leaderboard.json"
    local board -- steamid -> { name, kills, deaths, roaches }

    local function load()
        if board then return board end
        board = util.JSONToTable(file.Read(FILE, "DATA") or "") or {}
        return board
    end
    local function save()
        file.CreateDir("gknuckle")
        file.Write(FILE, util.TableToJSON(board))
    end
    local function entry(ply)
        load()
        local id = ply:SteamID64() or ply:SteamID()
        if ply:IsBot() then id = "bot_" .. ply:Nick() end
        board[id] = board[id] or { kills = 0, deaths = 0, roaches = 0 }
        board[id].name = ply:Nick()
        return board[id]
    end

    hook.Add("PlayerDeath", "GK_HubBoard", function(victim, inflictor, attacker)
        entry(victim).deaths = entry(victim).deaths + 1
        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
            entry(attacker).kills = entry(attacker).kills + 1
        end
    end)

    local function publish()
        load()
        for _, ply in ipairs(player.GetAll()) do
            local e = entry(ply)
            e.roaches = math.max(e.roaches or 0, GK.Roaches and GK.Roaches.Balance(ply) or 0) -- their best balance
        end
        local kd, money = {}, {}
        for _, e in pairs(board) do
            kd[#kd + 1] = { name = e.name, kills = e.kills, deaths = e.deaths, kd = e.kills / math.max(1, e.deaths) }
            money[#money + 1] = { name = e.name, roaches = e.roaches or 0 }
        end
        table.sort(kd, function(a, b) if a.kd ~= b.kd then return a.kd > b.kd end return a.kills > b.kills end)
        table.sort(money, function(a, b) return a.roaches > b.roaches end)
        for i = #kd, 11, -1 do kd[i] = nil end
        for i = #money, 11, -1 do money[i] = nil end
        SetGlobal2String("gk_top_kd", util.TableToJSON(kd))
        SetGlobal2String("gk_top_money", util.TableToJSON(money))

        -- Arenas.
        local arenas = GK.Rounds and GK.Rounds.arenas or {}
        for i = 1, GK.Hub.ArenaCount do
            local a, p = arenas[i], "gk_arena" .. i .. "_"
            local alive = 0
            if a then
                for _, pl in ipairs(a.players) do
                    if IsValid(pl) and pl:Alive() and GK.ArenaOf(pl) == i then alive = alive + 1 end
                end
            end
            SetGlobal2Bool(p .. "active", a ~= nil)
            SetGlobal2Int(p .. "alive", alive)
            SetGlobal2Int(p .. "total", a and #a.players or 0)
            SetGlobal2Float(p .. "started", a and a.started or 0)
            SetGlobal2Float(p .. "gas", a and a.gas or 0)
            SetGlobal2Int(p .. "stage", a and a.stage or 0)
            SetGlobal2Bool(p .. "break", a and a.inBreak or false)
        end
    end
    GK.Hub.Publish = publish
    timer.Create("GK_HubPublish", 2, 0, publish)
    timer.Create("GK_HubSave", 60, 0, function() if board then save() end end)
    hook.Add("ShutDown", "GK_HubSave", function() if board then save() end end)
end
