-- The server browser title, kept live, e.g.
--   gk.style | #1 | [12/36] | [2 Matches in progress...]
-- gk_hostname_format tokens: {players} {max} {matches} {match_word}
-- (empty format: leave hostname alone). Rewritten on joins, leaves and run
-- starts/ends, and every 5 s as a fallback. The server browser picks up a new
-- hostname on its next heartbeat, so it lags a few seconds behind.
if not SERVER then return end
local cvFormat = CreateConVar("gk_hostname_format", "gk.style | #1 | [{players}/{max}] | [{matches} {match_word} in progress...]",
    FCVAR_ARCHIVE, "Live server title; tokens {players} {max} {matches} {match_word}")

-- Running matches: the round system's live arenas (GK.Rounds.arenas), else
-- distinct nonzero gk_arena values among players.
local function matches()
    local n = 0
    if GK.Rounds and GK.Rounds.arenas then
        for _ in pairs(GK.Rounds.arenas) do n = n + 1 end
        return n
    end
    local seen = {}
    for _, p in ipairs(player.GetAll()) do
        local a = p:GetNW2Int("gk_arena", 0)
        if a ~= 0 and not seen[a] then seen[a] = true n = n + 1 end
    end
    return n
end

local last
function GK.UpdateHostname()
    local fmt = cvFormat:GetString()
    if fmt == "" then return end
    local m = matches()
    local title = fmt:gsub("{([%w_]+)}", {
        players = tostring(player.GetCount()), max = tostring(game.MaxPlayers()),
        matches = tostring(m), match_word = m == 1 and "Match" or "Matches",
    })
    if title == last then return end
    last = title
    RunConsoleCommand("hostname", title)
end

-- A tick later, so a leaving player is already gone from the count.
local function soon() timer.Simple(0, GK.UpdateHostname) end
hook.Add("PlayerInitialSpawn", "GK_Hostname", soon)
hook.Add("PlayerDisconnected", "GK_Hostname", soon)
hook.Add("GK_ArenaStart", "GK_Hostname", soon)
hook.Add("GK_ArenaEnd", "GK_Hostname", soon)
hook.Add("InitPostEntity", "GK_Hostname", soon)
cvars.AddChangeCallback("gk_hostname_format", function() last = nil soon() end, "GK_Hostname")
timer.Create("GK_Hostname", 5, 0, GK.UpdateHostname)
