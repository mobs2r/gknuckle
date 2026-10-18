-- Automated rounds test. Only runs when data/gknuckle/arenatest.txt exists.
-- Fills the server with bots and drives squads, the vacuum pull rules,
-- force start, team damage, the gas and round end. If the level code's
-- GK.Arena isn't there yet (no gk_style), a stand-in builds nothing and uses
-- a spot on the current map. Logs "[GKARENA]" lines.

if not file.Exists("gknuckle/arenatest.txt", "DATA") then return end
-- Optional convars for a bisect: data/gknuckle/testcvars.txt, "name=value" tokens.
if SERVER then
    for k, v in string.gmatch(file.Read("gknuckle/testcvars.txt", "DATA") or "", "([%w_]+)=(%S+)") do
        timer.Simple(1, function() RunConsoleCommand(k, v) print("[GKARENA]", "test cvar", k, v) end)
    end
end
if CLIENT then
    -- Held buttons for the ladder check.
    local held, untilT = 0, 0
    net.Receive("gk_arenatest_press", function() held = net.ReadUInt(32) untilT = CurTime() + net.ReadFloat() end)
    hook.Add("CreateMove", "GK_ArenaTestInput", function(cmd)
        if CurTime() < untilT then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), held))
            if bit.band(held, IN_FORWARD) ~= 0 then cmd:SetForwardMove(250) end
        end
    end)
    return
end
util.AddNetworkString("gk_arenatest_press")

local function log(...) print("[GKARENA]", ...) end
-- The run score (sh_score.lua): what each human gets shown.
hook.Add("GK_RunScored", "GK_ArenaTestScore", function(ply, r)
    if ply:IsBot() then return end
    local rows = {}
    for _, x in ipairs(r.rows) do rows[#rows + 1] = x.title .. "(" .. x.count .. ")" .. (x.mult and ("x" .. x.mult) or ("+" .. x.bonus)) end
    log("score shown: dist", math.floor(r.dist), "m speed", ("%.2f"):format(r.speed), "base", math.floor(r.base), "rows", table.concat(rows, " "), "FINAL", r.final)
end)
local function shot(ply) end -- no screenshots (the user asked us to stop)

local P, bots, home = nil, {}, nil
local gasLog = {}

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end

local function names(list)
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = p:Nick() end
    return table.concat(out, ",")
end
local function arenaSummary()
    local out = {}
    for _, p in ipairs(player.GetAll()) do
        out[#out + 1] = ("%s[a%d t%d s%d %s]"):format(p:Nick(), GK.ArenaOf(p), GK.TeamOf(p), GK.SquadOf(p), p:Alive() and "alive" or "dead")
    end
    return table.concat(out, " ")
end

step(0, function()
    P = player.GetHumans()[1]
    home = P:GetPos()
    RunConsoleCommand("gk_vacuum_interval", "0") -- this test pulls by hand
    local racks = {}
    for _, r in ipairs(ents.FindByClass("gk_item_rack")) do racks[#racks + 1] = r.GKItem end
    log("hub racks", table.concat(racks, ","), "ladders", #ents.FindByClass("gk_ladder"), "free items lying", #ents.FindByClass("gk_item"))
    log("map", game.GetMap(), "real GK.Arena", tostring(GK.Arena ~= nil and GK.Arena.Count ~= nil), "vacuums", #ents.FindByClass("gk_vacuum"), "force buttons", #ents.FindByClass("gk_force_start"))
    if not GK.Arena then
        log("GK.Arena missing: using stand-in")
        local busy = {}
        GK.Arena = {
            Free = function() for i = 1, 3 do if not busy[i] then return i end end end,
            Start = function(i)
                busy[i] = true
                local spawn = home + Vector(i * 400, 0, 10)
                return { spawn = spawn, bounds = { mins = spawn - Vector(300, 300, 60), maxs = spawn + Vector(300, 300, 500) }, top = spawn.z + 2000 }
            end,
            Clear = function(i) busy[i] = nil log("Clear arena", i) end,
            SetGasHeight = function(i, z) gasLog[i] = z end,
        }
    end
    for _ = 1, 12 do RunConsoleCommand("bot") end
end)

step(4, function()
    bots = player.GetBots()
    log("players", #player.GetAll(), "bots", #bots)
    -- Squads: P + 2 bots fit; a 4th doesn't.
    log("join P+b1", tostring(GK.JoinSquads(P, bots[1])))
    log("join P+b2", tostring(GK.JoinSquads(P, bots[2])))
    log("join P+b3 (4th)", tostring(GK.JoinSquads(P, bots[3])))
    log("squad of P", GK.SquadOf(P), "members", names(GK.SquadMembers(GK.SquadOf(P))))
    log("same side P/b1", tostring(GK.SameSide(P, bots[1])), "P/b3", tostring(GK.SameSide(P, bots[3])))
end)

-- 3 players in the vacuum, no force start: nobody goes.
step(1, function()
    hook.Run("GK_VacuumPull", { bots[4], bots[5], bots[6] }, GK.Arena.Free())
    log("pull 3 no force:", arenaSummary())
end)

-- Force start, then 3 go as a free-for-all.
step(1, function()
    GK.ForceStart(P)
    hook.Run("GK_VacuumPull", { bots[4], bots[5], bots[6] }, GK.Arena.Free())
    log("pull 3 forced:", arenaSummary())
end)
step(1, function()
    -- Teams can hurt each other in an FFA.
    local hp = bots[5]:Health()
    bots[5]:TakeDamage(10, bots[4], bots[4])
    log("FFA damage", hp, "->", bots[5]:Health())
    bots[5]:Kill()
    bots[6]:Kill()
end)
step(1, function() log("after 2 of 3 die:", arenaSummary()) end)
step(5, function() log("after round end:", arenaSummary()) end)

-- 13 in the vacuum: 12 go in squads, the 13th is vaporized.
step(1, function()
    for _, p in ipairs(player.GetAll()) do if not p:Alive() then p:Spawn() end end
end)
step(1, function()
    local all = {}
    for _, p in ipairs(player.GetAll()) do all[#all + 1] = p end
    log("pulling", #all)
    hook.Run("GK_VacuumPull", all, GK.Arena.Free())
    local inArena, dead, teams = 0, 0, {}
    for _, p in ipairs(player.GetAll()) do
        if GK.ArenaOf(p) ~= 0 then inArena = inArena + 1 teams[GK.TeamOf(p)] = (teams[GK.TeamOf(p)] or 0) + 1 end
        if not p:Alive() then dead = dead + 1 end
    end
    local sizes = {}
    for t, n in SortedPairs(teams) do sizes[#sizes + 1] = t .. "=" .. n end
    log("13 pulled: in arena", inArena, "vaporized/dead", dead, "teams", table.concat(sizes, " "))
    log("P team", GK.TeamOf(P), "b1 team", GK.TeamOf(bots[1]), "b2 team", GK.TeamOf(bots[2]))
    -- Team damage: squadmates can't hurt each other.
    local hp = bots[1]:Health()
    bots[1]:TakeDamage(10, P, P)
    log("teammate damage", hp, "->", bots[1]:Health())
end)
step(24, function()
    local s = {}
    for i, z in pairs(gasLog) do s[#s + 1] = ("arena %d gas z %.0f"):format(i, z) end
    local a = GK.Rounds.arenas[1]
    log("gas after grace:", table.concat(s, "; "), "my gas z", a and ("%.0f"):format(a.gas), "bounds z", a and a.info.bounds and ("%.0f..%.0f"):format(a.info.bounds.mins.z, a.info.bounds.maxs.z), "top", a and a.info.top, "P z", ("%.0f"):format(P:GetPos().z), "P hp", P:Health())
end)
-- Kill every team but P's: P's team wins.
step(1, function()
    for _, p in ipairs(player.GetAll()) do
        if GK.ArenaOf(p) ~= 0 and GK.TeamOf(p) ~= GK.TeamOf(P) then p:Kill() end
    end
end)
step(1, function() log("after others die:", arenaSummary()) end)
step(5, function() log("back in hub:", arenaSummary()) end)

-- The vacuum circle rules, driven directly (bots wander, so feed it who's
-- "in the circle" by hand): items vaporized on the way in; past 12, the
-- newest one in is vaporized.
local vac
step(1, function()
    vac = {} -- a stand-in key; the real circle code only uses it as a table key
    for _, p in ipairs(player.GetAll()) do if not p:Alive() then p:Spawn() end end
    GK.Inv.Give(P, "hammer") GK.Inv.Give(P, "piton")
end)
step(1, function()
    log("P items before", #GK.Inv.Get(P).bag)
    GK.VacuumCircleUpdate(vac, { P })
    log("P items after stepping in", #GK.Inv.Get(P).bag, "circle", #GK.VacuumCircle(vac))
    local inside = { P }
    local bots = player.GetBots()
    for i = 1, 12 do
        inside[#inside + 1] = bots[i]
        GK.VacuumCircleUpdate(vac, inside)
    end
    log("13 stepped in: circle", #GK.VacuumCircle(vac), "12th bot alive", tostring(bots[12]:Alive()), "11th bot alive", tostring(bots[11]:Alive()), "P alive", tostring(P:Alive()))
end)
-- A real hub ladder: walk into it.
local lad
step(0.5, function()
    lad = ents.FindByClass("gk_ladder")[1]
    if not IsValid(lad) then log("no ladder") return end
    P:Freeze(false)
    P:SetPos(lad:GetPos() + lad:GetForward() * 60 + Vector(0, 0, 4)) -- a ladder faces out, toward the climber
    P:SetEyeAngles((-lad:GetForward()):Angle())
    log("ladder", tostring(lad:GetPos()), "size", lad:GetWidth(), lad:GetHeight())
end)
step(0.6, function() if IsValid(lad) then net.Start("gk_arenatest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.2) net.Send(P) end end)
step(1.4, function() if IsValid(lad) then log("hub ladder climb: rose", ("%.0f"):format(P:GetPos().z - lad:GetPos().z), "onladder", tostring(GK.OnLadder(P))) end end)
-- Break rooms: top of region 1 of 2 sends survivors to the pocket, then into region 2.
local A2
step(1, function()
    RunConsoleCommand("gk_run_regions", "2") RunConsoleCommand("gk_break_time", "4")
    for _, p in ipairs(player.GetAll()) do if p:Alive() then p:SetNW2Int("gk_arena", 0) end end
    -- Under load: P and eleven bots, squads and all.
    local twelve = { P }
    for i = 1, 11 do if IsValid(bots[i]) then twelve[#twelve + 1] = bots[i] end end
    A2 = GK.StartArena(1, twelve, false)
    log("break test arena", tostring(A2 ~= nil), "pocket", tostring(GK.Arena.Pocket and GK.Arena.Pocket(1) and GK.Arena.Pocket(1).center))
end)
step(2, function()
    if not A2 then return end
    -- Skip the ride up the staging tube (sv_arena.lua): everyone arrives now.
    for _, p in ipairs(A2.players) do if IsValid(p) and p.GK_Arrive and p.GK_RiseTo then p.GK_Arrive() end end
    A2.region1 = A2.info.region
    P:SetPos(Vector(P:GetPos().x, P:GetPos().y, A2.info.top))
end)
step(1, function()
    if not A2 then return end
    local pk = GK.Arena.Pocket and GK.Arena.Pocket(1)
    local inPocket = 0
    for _, p in ipairs(A2.players) do if IsValid(p) and pk and p:GetPos():Distance(pk.center) < pk.half * 2 then inPocket = inPocket + 1 end end
    log("players in the break room", inPocket, "of", #A2.players)
    -- The perk console in the break room: two free cards, the third costs roaches.
    local con
    for _, c in ipairs(ents.FindByClass("gk_perk_console")) do if c:GetPos():Distance(P:GetPos()) < 1000 then con = c break end end
    if con then
        P:SetPos(con:GetPos() + con:GetForward() * 50)
        P:SetNW2Int("gk_roaches", 20)
        GK.OfferPerks(P, con)
        local cards = table.Copy(P.GK_PerkOffer.cards)
        local r = {}
        for _, id in ipairs(cards) do r[#r + 1] = id .. "=" .. tostring(GK.PickPerk(P, id)) end
        log("perk console picks", table.concat(r, " "), "perks", P:GetNW2String("gk_perks"), "roaches left", GK.Roaches.Count(P))
    else
        log("perk console: none near the pocket")
    end
    log("after top of region 1: inBreak", tostring(A2.inBreak), "stage", A2.stage, "P in pocket", tostring(pk and P:GetPos():Distance(pk.center) < pk.half * 2), "arena", GK.ArenaOf(P),
        "hub says break", tostring(GK.Hub.Publish() or GK.Hub.Arenas()[1].inBreak))
    shot(P)
end)
step(5, function()
    if not A2 then return end
    log("after break: inBreak", tostring(A2.inBreak), "stage", A2.stage, "region", A2.region1, "->", A2.info.region, "P dist to spawn", ("%.0f"):format(P:GetPos():Distance(A2.info.spawn or vector_origin)), "alive", tostring(P:Alive()))
    P:SetPos(Vector(P:GetPos().x, P:GetPos().y, A2.info.top))
end)
step(0, function()
    local c = {}
    for _, cls in ipairs({ "gk_barnacle", "gk_turret", "gk_gasbag", "gk_bloodbug", "gk_roach", "gk_mover", "gk_firejet" }) do c[#c + 1] = cls .. "=" .. #ents.FindByClass(cls) end
    log("creatures in the run", table.concat(c, " "), "hazard rooms", table.Count(GK.Hazards.Zones[1] or {}))
    -- WK handholds: aim at a red piton from 40 u off and see the hands find it.
    local tried, found = 0, 0
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        for _, box in ipairs(GK.Handholds.BoxesOf(piece:GetPiece())) do
            if box.piton and tried < 20 then
                tried = tried + 1
                local c = piece:GetPos() + (box.mins + box.maxs) * 0.5
                local from = c + Vector(40, 0, 0)
                local hit = GK.HandholdHit(from, (c - from):GetNormalized(), 180)
                if hit then found = found + 1 end
            end
        end
    end
    log("red pitons the hands can find", found, "of", tried)
end)
step(1, function() log("top of last region: arena still running", tostring(GK.Rounds.arenas[1] ~= nil), "P arena", GK.ArenaOf(P)) end)
step(1, function()
    local props = 0
    for _, e in ipairs(ents.FindByClass("prop_physics")) do if e.GK_FromHubSpot then props = props + 1 log("yard prop", e:GetModel(), "valid phys", tostring(IsValid(e:GetPhysicsObject()))) end end
    log("yard props", props, "pocket vendors", #ents.FindByClass("gk_vendor"), "easter surge", #ents.FindByClass("gk_surge"))
end)
step(1, function() log("DONE") end)
hook.Add("PlayerDeath", "GK_ArenaTestDeaths", function(ply) if vac then log("died", ply:Nick(), "in circle", tostring(IsValid(vac) and ply:GetPos():Distance(vac:GetPos()) < vac:GetRadius())) end end)
hook.Add("GK_ArenaEnd", "GK_ArenaTest", function(a, winners) log("ArenaEnd", a.index, "winners", names(winners)) end)
hook.Add("GK_ArenaStart", "GK_ArenaTest", function(a) log("ArenaStart", a.index, "players", #a.players, "teams", a.teamCount, "forced", tostring(a.forced)) end)

hook.Add("PlayerInitialSpawn", "GK_ArenaTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_ArenaTest")
    timer.Simple(10, function()
        local t = 0
        for _, s in ipairs(steps) do
            t = t + s[1]
            timer.Simple(t, function()
                local ok, err = pcall(s[2])
                if not ok then log("STEP ERROR", err) end
            end)
        end
    end)
end)
