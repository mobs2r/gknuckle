-- Rounds: the hub's vacuum pulls players into a fresh White Knuckle run (an
-- arena) for PvPvE. The map side (gk_style, the vacuum, building runs and the
-- gas plane) is the level code's: GK.Arena.Start / Clear / Free / SetGasHeight
-- and hook GK_VacuumPull. This file decides who goes and runs the round.
--
--   Up to 12 players per arena; at most 3 arenas at once (a 36-player lobby).
--   6+ in the vacuum: squads (sh_squads.lua) stay together, loners are made
--     into squads of up to 3; every squad is a team (2 teams at 6, 4 at 12).
--   Under 6: nobody goes, unless someone pressed the force-start button
--     (gk_force_start): then it's every player for themselves (solo, 1v1, up
--     to 1v1v1v1v1).
--   Anyone past the 12th in the vacuum is vaporized and respawns in the hub.
--   The gas rises from the bottom of the run and hurts anyone under it.
--   A team wins by getting someone to the top, or by being the last alive.

local cvMin = CreateConVar("gk_arena_min", "6", FCVAR_ARCHIVE, "Players needed to start squads without force start")
local cvMax = CreateConVar("gk_arena_max", "12", FCVAR_ARCHIVE, "Players per arena")
-- The Mass (the rising gas), with WK's numbers: it starts once someone has
-- climbed 16 m (or after gk_mass_grace seconds if nobody does), rises at
-- 1 m/s, gains 0.001 m/s every second and tops out at 2 m/s, before the
-- rubber band below. (New names: the old gk_gas_speed/gk_gas_grace values
-- are archived in players' configs at the old, much slower tuning.)
local cvGrace = CreateConVar("gk_mass_grace", "60", FCVAR_ARCHIVE, "Seconds before the Mass starts rising if nobody has climbed 16 m")
local cvMassStart = CreateConVar("gk_mass_start", "16", FCVAR_ARCHIVE, "Metres someone has to climb before the Mass starts rising")
local cvGasSpeed = CreateConVar("gk_mass_speed", "39.4", FCVAR_ARCHIVE, "Mass rise speed when it starts (units/s; WK 1 m/s)")
local cvGasAccel = CreateConVar("gk_mass_accel", "0.0394", FCVAR_ARCHIVE, "Mass speed gained per second (units/s; WK 0.001 m/s)")
local cvGasMax = CreateConVar("gk_mass_max", "78.7", FCVAR_ARCHIVE, "Mass top speed before the rubber band (units/s; WK 2 m/s)")
local cvRegions = CreateConVar("gk_run_regions", "3", FCVAR_ARCHIVE, "Regions per run; between them the survivors rest in a break room")
local cvBreak = CreateConVar("gk_break_time", "30", FCVAR_ARCHIVE, "Seconds in the break room between regions")
local cvRise = CreateConVar("gk_tube_rise", "1", FCVAR_ARCHIVE, "Ride up the staging tube before arriving in a run")
local cvReward = CreateConVar("gk_arena_reward", "25", FCVAR_ARCHIVE, "CrabCoin for each player on the winning team")
local cvMinSecs = CreateConVar("gk_arena_reward_min_secs", "90", FCVAR_ARCHIVE, "Runs shorter than this pay no CrabCoin")

GK.Rounds = GK.Rounds or { arenas = {}, forceUntil = 0 }
local R = GK.Rounds

local function inArena(ply) return GK.ArenaOf(ply) ~= 0 end

-- Vaporize: disintegrate them on the spot; they respawn in the hub.
function GK.Vaporize(ply)
    local fx = EffectData()
    fx:SetOrigin(ply:WorldSpaceCenter())
    fx:SetEntity(ply)
    util.Effect("cball_explode", fx, true, true)
    ply:EmitSound("weapons/physcannon/energy_disintegrate4.wav", 90)
    local d = DamageInfo()
    d:SetDamage(ply:Health() + 1000)
    d:SetDamageType(DMG_DISSOLVE)
    d:SetAttacker(game.GetWorld())
    d:SetInflictor(game.GetWorld())
    ply.GK_Goring = true -- straight to dead, not downed
    ply:TakeDamageInfo(d)
    ply.GK_Goring = false
    if ply:Alive() then ply:Kill() end
end

-- Splits players into teams. squads: keep squads together, loners fill squads
-- of up to 3. Otherwise everyone alone.
local function makeTeams(players, squads)
    local teams = {}
    if not squads then
        for _, p in ipairs(players) do teams[#teams + 1] = { p } end
        return teams
    end
    local bySquad, loners = {}, {}
    for _, p in ipairs(players) do
        local s = GK.SquadOf(p)
        if s ~= 0 then
            bySquad[s] = bySquad[s] or {}
            table.insert(bySquad[s], p)
        else
            loners[#loners + 1] = p
        end
    end
    for _, members in SortedPairs(bySquad) do teams[#teams + 1] = members end
    -- Loners top up short squads first, then form new ones.
    for _, p in ipairs(loners) do
        local placed = false
        for _, t in ipairs(teams) do
            if #t < GK.SquadSize and GK.SquadOf(t[1]) == 0 then t[#t + 1] = p placed = true break end
        end
        if not placed then teams[#teams + 1] = { p } end
    end
    -- A lone squad isn't a fight: split the biggest team until there are two.
    while #teams == 1 and #teams[1] > 1 do
        local t = teams[1]
        teams[2] = { table.remove(t) }
    end
    return teams
end

-- Picks who goes: squads first (whole), then loners, up to the cap.
local function pickParticipants(players, cap)
    local chosen, extra, seen = {}, {}, {}
    local squadsFirst = {}
    for _, p in ipairs(players) do if GK.SquadOf(p) ~= 0 then squadsFirst[#squadsFirst + 1] = p end end
    for _, p in ipairs(players) do if GK.SquadOf(p) == 0 then squadsFirst[#squadsFirst + 1] = p end end
    for _, p in ipairs(squadsFirst) do
        if not seen[p] then
            local group = GK.SquadOf(p) ~= 0 and GK.SquadMembers(GK.SquadOf(p)) or { p }
            local here = {}
            for _, m in ipairs(group) do if table.HasValue(players, m) then here[#here + 1] = m end end
            for _, m in ipairs(here) do seen[m] = true end
            if #chosen + #here <= cap then
                for _, m in ipairs(here) do chosen[#chosen + 1] = m end
            else
                for _, m in ipairs(here) do extra[#extra + 1] = m end
            end
        end
    end
    return chosen, extra
end

-- Run modes, WK's: "campaign" (the normal run), "iron" (Iron Knuckle: no
-- perks, no bank, no backups; machines take the roaches you carry) and "hard"
-- (the Mass rises twice as fast and creatures hit twice as hard).
local cvMode = CreateConVar("gk_run_mode", "campaign", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Run mode for new runs: campaign, iron or hard")
GK.RunModes = { campaign = true, iron = true, hard = true }
-- Each vacuum pad can pick its own mode with its mode button (gk_mode_button);
-- otherwise gk_run_mode is the server's default.
R.padMode = R.padMode or {}
function GK.DefaultRunMode()
    local m = string.lower(cvMode:GetString())
    return GK.RunModes[m] and m or "campaign"
end
function GK.SetPadMode(pad, mode) if GK.RunModes[mode] then R.padMode[pad or 0] = mode end end

function GK.RunMode(ply)
    local a = R.arenas[GK.ArenaOf(ply)]
    return a and a.mode or "campaign"
end

-- The pause menu's LEAVE RUN (WK's End Run): you die where you are, and the
-- run carries on for anyone else in it.
util.AddNetworkString("gk_ascended") -- WK's 50 m chime (was SendLua)

concommand.Add("gk_leaverun", function(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    local a = R.arenas[GK.ArenaOf(ply)]
    if not a then return end
    a.forfeit = a.forfeit or {}
    a.forfeit[ply] = true -- M4: leaving hands nobody a "last team standing" payout
    ply:Kill()
end)
-- M4: a console "kill" (attacker = self) mid-run counts as a forfeit too.
hook.Add("PlayerDeath", "GK_ArenaForfeit", function(ply, _, attacker)
    if attacker ~= ply then return end
    local a = R.arenas[GK.ArenaOf(ply)]
    if a then a.forfeit = a.forfeit or {} a.forfeit[ply] = true end
end)

-- WK's campaign goes Silos -> Pipeworks -> Habitation, a break room between
-- each pair; any stages past those draw a random region.
GK.RegionOrder = { "Region_Silos_Campaign", "Region_Pipeworks_Campaign", "Region_Habitation_Campaign" }
local cvOrder = CreateConVar("gk_region_order", "1", FCVAR_ARCHIVE, "Runs go Silos, Pipeworks, Habitation like WK's campaign (0 = random regions)")
function GK.StageRegion(stage)
    if not cvOrder:GetBool() then return nil end
    return GK.RegionOrder[stage] -- nil past the list: GK.Arena.Start draws one
end

function GK.StartArena(index, players, forced)
    local cleared = {}
    for _, p in ipairs(players) do if GK.PackReady(p) then cleared[#cleared + 1] = p else GK.Pack.Nag(p) end end
    players = cleared
    if #players == 0 then return end
    local squads = not forced
    local teams = makeTeams(players, squads)
    local info = GK.Arena.Start(index, GK.StageRegion(1), os.time() + index)
    if not info then return end
    local mode = R.padMode[index] or R.padMode[0] or GK.DefaultRunMode()
    local a = { index = index, teams = {}, players = {}, info = info, started = CurTime(), startedAt = os.time(), gas = nil, forced = forced, teamCount = #teams, stage = 1, mode = mode }
    SetGlobal2String("gk_arena_mode_" .. index, mode)
    R.arenas[index] = a
    for t, members in ipairs(teams) do
        for i, p in ipairs(members) do
            a.players[#a.players + 1] = p
            a.teams[p] = t
            p:SetNW2Int("gk_arena", index)
            p:SetNW2Int("gk_team", t)
            -- Spread each team out a little around the spawn.
            local off = Angle(0, t * 70 + i * 20, 0):Forward() * (20 + i * 12)
            local dest = (info.spawn or info.top) + off
            local function arrive()
                if not IsValid(p) then return end
                p.GK_RiseTo = nil
                p:SetNW2Float("gk_rise_to", 0)
                p:SetPos(dest)
                p:SetLocalVelocity(vector_origin)
                p:SetHealth(p:GetMaxHealth())
                GK.SetStamina(p, GK.Config.StaminaMax)
                p:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 255), 0.8, 0.2)
                p:EmitSound("ambient/machines/teleport4.wav", 70)
            end
            -- The hub's staging tube: up into the dark first, then you're there.
            -- Each pad has its own tube (gk_vacuum_top_N); the old single one as a fallback.
            local top = ents.FindByName("gk_vacuum_top_" .. index)[1] or ents.FindByName("gk_vacuum_top")[1]
            if IsValid(top) and p:GetPos().z < top:GetPos().z and GetConVar("gk_tube_rise"):GetBool() then
                -- The ride is the camera's only (sh_movement.lua holds you still,
                -- the view climbs into the dark): moving bodies up through the
                -- tube crashed vphysics in full matches.
                p.GK_RiseTo, p.GK_Arrive, p.GK_RiseGiveUp = top:GetPos().z, arrive, CurTime() + 1.4
                p:SetNW2Float("gk_rise_to", CurTime())
                p:EmitSound("ambient/machines/wall_move4.wav", 75, 70)
            else
                arrive()
            end
        end
    end
    a.gas = info.bounds and info.bounds.mins and info.bounds.mins.z or (info.spawn and info.spawn.z - 200) or 0
    hook.Run("GK_ArenaStart", a)
    return a
end

-- Rising up the tube (above): lifted until the top marker, then placed.
hook.Add("Tick", "GK_TubeRise", function()
    for _, p in ipairs(player.GetAll()) do
        if p.GK_RiseTo then
            if not p:Alive() then p.GK_RiseTo = nil
            elseif CurTime() > p.GK_RiseGiveUp then p.GK_Arrive()
            end
        end
    end
end)

-- M4: is this win worth CrabCoin? Not for short runs, and a "last team standing"
-- win only counts against at least one other real player who didn't forfeit.
local function payable(a, winTeam, how)
    if CurTime() - (a.started or CurTime()) < cvMinSecs:GetFloat() then return false end
    if how ~= "last" then return true end
    local rivals = 0
    for _, p in ipairs(a.players) do
        if IsValid(p) and not p:IsBot() and a.teams[p] ~= winTeam and not (a.forfeit and a.forfeit[p]) then rivals = rivals + 1 end
    end
    return rivals >= 1
end

-- how: "top" (reached the top of the last region), "last" (last team standing) or nil.
function GK.EndArena(index, winTeam, how)
    local a = R.arenas[index]
    if not a then return end
    R.arenas[index] = nil
    local winners = {}
    local pay = winTeam ~= nil and payable(a, winTeam, how)
    for _, p in ipairs(a.players) do
        if IsValid(p) and a.teams[p] == winTeam then
            winners[#winners + 1] = p
            if pay then
                -- One payout per player per run, even if this is ever called twice.
                GK.Economy.Add(p, cvReward:GetInt(), "gknuckle_arena_win",
                    GK.ApiAuth.EventId("arena_win", p, index .. ":" .. (a.startedAt or 0)))
            end
            p:EmitSound("ambient/levels/citadel/portal_beam_shoot" .. math.random(1, 6) .. ".wav", 70)
        end
    end
    hook.Run("GK_ArenaEnd", a, winners)
    -- Everyone left in the run goes back to the hub a moment later.
    timer.Simple(4, function()
        for _, p in ipairs(a.players) do
            if IsValid(p) and GK.ArenaOf(p) == index then
                p:SetNW2Int("gk_arena", 0)
                p:SetNW2Int("gk_team", 0)
                if p.GK_Watching then GK.StopWatching(p) end
                if p:Alive() then p:Spawn() end
            end
        end
        GK.Arena.Clear(index)
    end)
end

-- The vacuum fires: decide who goes where.
hook.Add("GK_VacuumPull", "GK_Rounds", function(inZone, freeIndex)
    local players = {}
    for _, p in ipairs(inZone) do
        if IsValid(p) and p:Alive() and not inArena(p) then
            if GK.PackReady(p) then
                players[#players + 1] = p
            else
                GK.Pack.Nag(p) -- still downloading playable-pack, or not licensed: stays in the hub
            end
        end
    end
    if #players == 0 then return true end
    -- Forced by the hub's one button, or by this pad's own (gk_force_start_N).
    R.forceFor = R.forceFor or {}
    local forced = R.forceUntil > CurTime() or (freeIndex and (R.forceFor[freeIndex] or 0) > CurTime())
    if #players < cvMin:GetInt() and not forced then return true end -- wait for more
    if not freeIndex then return true end -- every arena busy: wait

    local chosen, extra = pickParticipants(players, cvMax:GetInt())
    for _, p in ipairs(extra) do GK.Vaporize(p) end
    R.forceUntil = 0
    R.forceFor[freeIndex] = 0
    GK.StartArena(freeIndex, chosen, #players < cvMin:GetInt())
    return true
end)

-- Force start: pressing the button lets the next vacuum go with under 6.
function GK.ForceStart(ply, index)
    R.forceFor = R.forceFor or {}
    if index then R.forceFor[index] = CurTime() + 60 else R.forceUntil = CurTime() + 60 end
    sound.Play("buttons/button3.wav", IsValid(ply) and ply:GetPos() or vector_origin, 75, 100)
end

-- Players can't hurt their own team inside an arena (or squadmates in the hub).
hook.Add("PlayerShouldTakeDamage", "GK_TeamDamage", function(ply, attacker)
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply and GK.SameSide(ply, attacker) then return false end
end)

-- Running rounds: rise the gas, check the top, check who's left.
-- Breaks are per squad, as in WK's interludes: a squad that gets someone to
-- the top of a region is taken to the arena's sealed break room (a pocket off
-- in the void, with a vendor) and rests there while the others are still
-- climbing with the gas under them. Once every squad still alive has made it
-- (or the gas has caught the rest), the next region is built in the same
-- shaft and everyone at the break drops into its start together.
local function atBreak(a, p) return a.atBreak ~= nil and a.atBreak[a.teams[p]] == true end
function GK.AtBreak(p)
    local a = R.arenas[GK.ArenaOf(p)]
    return a ~= nil and atBreak(a, p)
end

local function toPocket(a, p, i, n)
    local pocket = GK.Arena.Pocket and GK.Arena.Pocket(a.index)
    if pocket then
        local off = Angle(0, i * (360 / math.max(n, 1)), 0):Forward() * math.min(pocket.half * 0.6, 40 + n * 6)
        p:SetPos(pocket.center + off + Vector(0, 0, 8))
        p:SetLocalVelocity(vector_origin)
    end
    p:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 255), 0.6, 0.1)
    p:EmitSound("ambient/machines/teleport4.wav", 70)
end

-- Squad `t` made it to the top of this region: to the break room with them.
function GK.TeamToBreak(index, t)
    local a = R.arenas[index]
    if not a or a.inBreak then return end
    a.atBreak = a.atBreak or {}
    if a.atBreak[t] then return end
    a.atBreak[t] = true
    a.firstAtBreak = a.firstAtBreak or CurTime()
    local members = {}
    for _, p in ipairs(a.players) do
        if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and a.teams[p] == t then members[#members + 1] = p end
    end
    -- Squads already resting keep their spots; this one takes the next ones round.
    local resting = 0
    for _, p in ipairs(a.players) do if IsValid(p) and p:Alive() and atBreak(a, p) then resting = resting + 1 end end
    for i, p in ipairs(members) do toPocket(a, p, resting - #members + i, resting) end
    -- Squadmates who died with a Biological Backup come back here (sh_perks.lua).
    for _, p in ipairs(a.players) do
        if IsValid(p) and not p:Alive() and a.teams[p] == t and GK.ArenaOf(p) == index and GK.HasBackup and GK.HasBackup(p) then
            GK.RestoreBackup(a, p)
        end
    end
    hook.Run("GK_TeamBreak", a, t, members)
    GK.CheckStageDone(index)
end

-- A Biological Backup brings you back in the break room (used up).
function GK.RestoreBackup(a, p)
    p.GK_BackupSpawn = true
    p:Spawn()
    p.GK_BackupSpawn = nil
    p:SetNW2Bool("gk_backup", false)
    toPocket(a, p, 0, 1)
    p:EmitSound("gknuckle/ui/comp_upgradeInjection.wav", 70)
end

-- Every squad still alive is resting: on to the next region.
function GK.CheckStageDone(index)
    local a = R.arenas[index]
    if not a or a.inBreak or not a.atBreak then return end
    for _, p in ipairs(a.players) do
        if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and not atBreak(a, p) then return end
    end
    GK.ArenaBreak(index)
end

function GK.ArenaBreak(index)
    local a = R.arenas[index]
    if not a or a.inBreak then return end
    a.inBreak = true
    local pocket = GK.Arena.Pocket and GK.Arena.Pocket(index)
    -- Anyone still in the shaft (an admin test calling this directly) goes too.
    local stray = {}
    for _, p in ipairs(a.players) do
        if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and not atBreak(a, p) then stray[#stray + 1] = p end
    end
    for i, p in ipairs(stray) do toPocket(a, p, i, #stray) end
    hook.Run("GK_ArenaBreak", a, a.stage)
    -- Build the next region now, in the same shaft (this clears the last one).
    local info = GK.Arena.Start(index, GK.StageRegion(a.stage + 1), (a.info.seed or os.time()) + a.stage * 7919)
    -- The break lasts gk_break_time from the first squad in, but the last squad
    -- in still gets a little while at the vendor.
    local wait = 0.5
    if pocket then
        local since = CurTime() - (a.firstAtBreak or CurTime())
        wait = math.max(cvBreak:GetFloat() - since, math.min(8, cvBreak:GetFloat()))
        -- The ride out (sh_lift.lua) is part of the break, not added to it.
        wait = math.max(1, wait - (GK.LiftTime or 0))
    end
    local function nextRegion()
        if R.arenas[index] ~= a then return end
        if info then a.info = info end
        a.stage = a.stage + 1
        for _, p in ipairs(a.players) do if IsValid(p) and p.GK_Ascended then p.GK_Ascended[a] = 0 end end
        a.started = CurTime()
        a.gas = a.info.bounds and a.info.bounds.mins and a.info.bounds.mins.z or ((a.info.spawn or vector_origin).z - 200)
        local n = 0
        for _, p in ipairs(a.players) do
            if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index then
                n = n + 1
                local off = Angle(0, n * 40, 0):Forward() * (20 + n * 8)
                p:SetPos((a.info.spawn or a.info.top) + off)
                p:SetLocalVelocity(vector_origin)
                p:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 255), 0.8, 0.2)
                p:EmitSound("ambient/machines/teleport4.wav", 70)
            end
        end
        a.atBreak, a.firstAtBreak, a.massAt = nil, nil, nil
        a.inBreak = false
        hook.Run("GK_ArenaStage", a, a.stage)
    end
    timer.Simple(wait, function()
        if R.arenas[index] ~= a then return end
        local riders = {}
        for _, p in ipairs(a.players) do
            if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index then riders[#riders + 1] = p end
        end
        if pocket and GK.LiftRide then GK.LiftRide(riders, nextRegion) else nextRegion() end
    end)
end

-- Out of the run: watch it. A player who dies in an arena follows their own
-- squad first, then anyone still in the run (attack / attack2 to switch,
-- jump to leave for the hub). They stay out until the run ends: getting back
-- in is the Biological Backup's job, not a free respawn.
local function watchable(a, me)
    local mates, others = {}, {}
    for _, p in ipairs(a.players) do
        if IsValid(p) and p ~= me and p:Alive() and GK.ArenaOf(p) == a.index then
            if a.teams[p] == a.teams[me] then mates[#mates + 1] = p else others[#others + 1] = p end
        end
    end
    for _, p in ipairs(others) do mates[#mates + 1] = p end
    return mates
end

function GK.StopWatching(p)
    p.GK_Watching = nil
    p:SetNW2Bool("gk_watching", false)
    if p:GetObserverMode() ~= OBS_MODE_NONE and not IsValid(p:GetNW2Entity("gk_ragdoll")) then p:UnSpectate() end
end

local function watchNext(p, step)
    local a = R.arenas[GK.ArenaOf(p)]
    if not a then return false end
    local list = watchable(a, p)
    if #list == 0 then return false end
    local cur = p:GetObserverTarget()
    local i = 0
    for k, q in ipairs(list) do if q == cur then i = k end end
    -- Stay on your squad when the current target dropped out; otherwise step.
    local nextOne = list[((i - 1 + (step or 1)) % #list) + 1]
    if i == 0 then nextOne = list[1] end
    p:Spectate(OBS_MODE_CHASE)
    p:SpectateEntity(nextOne)
    p:SetNW2Bool("gk_watching", true)
    return true
end

hook.Add("PlayerDeath", "GK_ArenaWatch", function(ply)
    local a = R.arenas[GK.ArenaOf(ply)]
    if not a then return end
    ply.GK_Watching = a
    -- The death screen first (sh_score.lua), then the squad's view.
    timer.Simple(3.5, function()
        if IsValid(ply) and not ply:Alive() and ply.GK_Watching == a then watchNext(ply, 0) end
    end)
end)

timer.Create("GK_ArenaWatch", 0.5, 0, function()
    for _, p in ipairs(player.GetAll()) do
        local a = p.GK_Watching
        if a and not p:Alive() then
            if R.arenas[a.index] ~= a or GK.ArenaOf(p) ~= a.index then
                -- The run is over: back to the hub.
                GK.StopWatching(p)
                p:SetNW2Int("gk_arena", 0) p:SetNW2Int("gk_team", 0)
                p:Spawn()
            elseif p:GetNW2Bool("gk_watching", false) then
                local t = p:GetObserverTarget()
                if not IsValid(t) or not t:Alive() or GK.ArenaOf(t) ~= a.index then watchNext(p, 0) end
            end
        end
    end
end)

-- While watching: no respawn on click; attack/attack2 switch, jump leaves.
hook.Add("PlayerDeathThink", "GK_ArenaWatch", function(ply)
    local a = ply.GK_Watching
    if not a then return end
    if R.arenas[a.index] ~= a then return end
    if ply:KeyPressed(IN_JUMP) and not ply:IsBot() then
        GK.StopWatching(ply)
        ply:SetNW2Int("gk_arena", 0) ply:SetNW2Int("gk_team", 0)
        ply:Spawn()
        return false
    end
    if ply:GetNW2Bool("gk_watching", false) then
        if ply:KeyPressed(IN_ATTACK) then watchNext(ply, 1) end
        if ply:KeyPressed(IN_ATTACK2) then watchNext(ply, -1) end
    end
    return false
end)

hook.Add("PlayerSpawn", "GK_ArenaWatch", function(ply)
    if ply.GK_Watching then GK.StopWatching(ply) end
end)

timer.Create("GK_Rounds", 0.25, 0, function()
    for index, a in pairs(R.arenas) do
        local info = a.info
        -- Start the Mass: someone not resting is 16 m up, or the grace ran out.
        if not a.massAt and not a.inBreak and info.spawn then
            local start = CurTime() - a.started >= cvGrace:GetFloat()
            for _, p in ipairs(a.players) do
                if not start and IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and not atBreak(a, p)
                    and p:GetPos().z - info.spawn.z >= cvMassStart:GetFloat() * 39.37 then start = true end
            end
            if start then a.massAt = CurTime() end
        end
        local t = a.massAt and CurTime() - a.massAt or 0
        if a.inBreak then t = 0 end -- the gas waits too
        if a.massAt and not a.inBreak then
            -- WK's Mass rubber-bands: speed x max(1, 0.07 per metre it's behind),
            -- up to x4. Measured to the lowest player still alive, so it presses
            -- whoever is last rather than the leader.
            local lowest
            for _, p in ipairs(a.players) do
                if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and not atBreak(a, p) then
                    local z = p:GetPos().z
                    if not lowest or z < lowest then lowest = z end
                end
            end
            local behind = lowest and math.max(0, (lowest - a.gas) / 39.4) or 0
            local band = math.Clamp(behind * 0.07, 1, 4)
            local speed = math.min(cvGasSpeed:GetFloat() + t * cvGasAccel:GetFloat(), cvGasMax:GetFloat())
            if a.mode == "hard" then speed = speed * 2 end -- Hard: the Mass x2
            a.gas = a.gas + speed * band * 0.25
            GK.Arena.SetGasHeight(index, a.gas)
            -- WK: 1 m under the surface is death, not a slow burn.
            for _, p in ipairs(a.players) do
                if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index and not atBreak(a, p) and p:GetPos().z < a.gas - 39.4 then
                    local d = DamageInfo()
                    d:SetDamage(p:Health() + 1000) d:SetDamageType(DMG_DISSOLVE)
                    d:SetAttacker(game.GetWorld()) d:SetInflictor(game.GetWorld())
                    p.GK_Goring = true -- straight to dead (WK), not downed first
                    p:TakeDamageInfo(d)
                    p.GK_Goring = false
                    if p:Alive() then p:Kill() end
                end
            end
        end

        local alive, teamsAlive = 0, {}
        for _, p in ipairs(a.players) do
            if IsValid(p) and p:Alive() and GK.ArenaOf(p) == index then
                alive = alive + 1
                -- WK's "ASCENDED N METERS" every 50 m, as a chime (no HUD text here).
                local resting = a.inBreak or atBreak(a, p)
                if not resting and info.spawn then
                    local m = math.floor((p:GetPos().z - info.spawn.z) / (50 * 39.4))
                    p.GK_Ascended = p.GK_Ascended or {}
                    if m > (p.GK_Ascended[a] or 0) then
                        p.GK_Ascended[a] = m
                        net.Start("gk_ascended") net.Send(p)
                    end
                end
                teamsAlive[a.teams[p]] = true
                if not resting and info.top and p:GetPos().z >= info.top - 64 then
                    if (a.stage or 1) < cvRegions:GetInt() then
                        GK.TeamToBreak(index, a.teams[p]) -- this squad made it through: rest
                    else
                        GK.EndArena(index, a.teams[p], "top") -- top of the last region: that team wins
                        return
                    end
                end
            end
        end
        -- A trailing squad caught by the gas can be the last thing a stage waited on.
        if R.arenas[index] == a and a.atBreak and (a.teamCount == 1 or table.Count(teamsAlive) > 1) then GK.CheckStageDone(index) end
        if R.arenas[index] ~= a then
            -- moved on above
        elseif alive == 0 then
            GK.EndArena(index, nil)
        elseif table.Count(teamsAlive) == 1 and a.teamCount > 1 then
            GK.EndArena(index, next(teamsAlive), "last") -- last team standing (a solo run goes on to the top)
        end
    end
end)

-- Dying in a run: you're out of it, back to the hub.
hook.Add("PlayerSpawn", "GK_ArenaRespawn", function(ply)
    if ply.GK_BackupSpawn then return end -- back in from a Biological Backup: still in the run
    ply:SetNW2Bool("gk_backup", false)
    if GK.ArenaOf(ply) ~= 0 then
        ply:SetNW2Int("gk_arena", 0)
        ply:SetNW2Int("gk_team", 0)
    end
end)

-- Force-start buttons: one beside every vacuum, if the map didn't place one.
hook.Add("InitPostEntity", "GK_ForceButtons", function()
    timer.Simple(2, function()
        if #ents.FindByClass("gk_force_start") == 0 then
            for _, v in ipairs(ents.FindByClass("gk_vacuum")) do
                local b = ents.Create("gk_force_start")
                b:SetPos(v:GetPos() + Vector(220, 0, 0))
                b:Spawn()
                b:DropToFloor()
            end
        end
        -- A run-mode switch beside every force-start button, for that button's pad.
        for _, b in ipairs(ents.FindByClass("gk_force_start")) do
            local m = ents.Create("gk_mode_button")
            if IsValid(m) then
                m:SetPad(tonumber(string.match(b:GetName() or "", "_(%d+)$")) or 0)
                m:SetPos(b:GetPos() + b:GetRight() * 48 + Vector(0, 0, 4))
                m:SetAngles(b:GetAngles())
                m:Spawn()
                m:DropToFloor()
            end
        end
    end)
end)

-- Stepping into the vacuum circle ---------------------------------------------
-- Whatever you're carrying is vaporized as you step in (runs start empty-
-- handed), and anything dropped on the pad goes too. The circle holds one
-- arena's worth (12): whoever steps in past that is vaporized on the spot.

function GK.VaporizeItems(ply)
    local inv = GK.Inv.Get(ply)
    -- Everything carried burns, xenium lumps and roaches in hand included
    -- (roaches already in your bag count are kept; bank them to be safe).
    local lost = #inv.bag > 0 or next(inv.slots) ~= nil
    if not lost then return end
    inv.bag, inv.slots = {}, {}
    GK.Inv.Sync(ply)
    local fx = EffectData()
    fx:SetOrigin(ply:WorldSpaceCenter())
    util.Effect("cball_bounce", fx, true, true)
    ply:EmitSound("weapons/physcannon/energy_sing_flyby" .. math.random(1, 2) .. ".wav", 70, 140)
end

local ITEM_CLASSES = { gk_item = true, gk_brick = true, gk_surge = true }
local inCircle = {} -- vacuum -> players inside, in the order they stepped in
function GK.VacuumCircle(vac) return inCircle[vac] or {} end

-- One update of who's in the circle, given everyone standing in it now.
function GK.VacuumCircleUpdate(vac, inZone)
        local now = {}
        for _, p in ipairs(inZone) do
            if GK.ArenaOf(p) == 0 then now[p] = true end
        end
        local list = {}
        for _, p in ipairs(inCircle[vac] or {}) do
            if IsValid(p) and now[p] then list[#list + 1] = p now[p] = nil end
        end
        -- Newcomers, in a stable order.
        local fresh = {}
        for p in pairs(now) do fresh[#fresh + 1] = p end
        table.sort(fresh, function(a, b) return a:EntIndex() < b:EntIndex() end)
        for _, p in ipairs(fresh) do
            GK.VaporizeItems(p)
            if #list >= cvMax:GetInt() then
                GK.Vaporize(p) -- one too many: the last one in goes
            else
                list[#list + 1] = p
            end
        end
        inCircle[vac] = list
end

timer.Create("GK_VacuumCircle", 0.2, 0, function()
    for _, vac in ipairs(ents.FindByClass("gk_vacuum")) do
        if vac.PlayersInZone then
            GK.VacuumCircleUpdate(vac, vac:PlayersInZone())
            -- Queue state for the hub's ring screen (GK.VacuumQueueText, sh_squads.lua).
            local n = #(inCircle[vac] or {})
            vac:SetNW2Int("gk_queue", n)
            vac:SetNW2Int("gk_queue_max", cvMax:GetInt())
            vac:SetNW2Bool("gk_queue_ready", n > 0 and (n >= cvMin:GetInt() or R.forceUntil > CurTime()))
            if n >= cvMax:GetInt() then
                local c = vac:GetPos()
                for _, p in ipairs(inCircle[vac]) do
                    local d = p:GetPos() - c d.z = 0
                    if IsValid(p) and p:Alive() and d:Length() > vac:GetRadius() * 0.85 and (p.GK_NextZap or 0) < CurTime() then
                        p.GK_NextZap = CurTime() + 0.6
                        p:SetVelocity(-d:GetNormalized() * 420 + Vector(0, 0, 160))
                        local fx = EffectData() fx:SetOrigin(p:WorldSpaceCenter()) fx:SetMagnitude(2) fx:SetScale(1)
                        util.Effect("TeslaHitboxes", fx, true, true)
                        util.Effect("Sparks", fx, true, true)
                        p:EmitSound("ambient/energy/zap" .. math.random(1, 9) .. ".wav", 75)
                        p:ViewPunch(Angle(-6, math.Rand(-6, 6), 0))
                    end
                end
            end

            -- Items lying on the pad.
            local r2 = vac:GetRadius() ^ 2
            for _, e in ipairs(ents.FindInSphere(vac:GetPos(), vac:GetRadius())) do
                if ITEM_CLASSES[e:GetClass()] and not e.GK_FromRack and e:GetPos():DistToSqr(vac:GetPos()) <= r2 then
                    local fx = EffectData()
                    fx:SetOrigin(e:WorldSpaceCenter())
                    util.Effect("cball_bounce", fx, true, true)
                    e:Remove()
                end
            end
        end
    end
end)

-- Hard mode: creatures hit twice as hard.
local CREATURES = { gk_bloodbug = true, gk_drone = true, gk_turret = true, gk_hopper = true, gk_gasbag = true,
    gk_barnacle = true, gk_ventthing = true, gk_teeth = true, gk_roach = true }
hook.Add("EntityTakeDamage", "GK_HardMode", function(ent, d)
    if not ent:IsPlayer() then return end
    local att, inf = d:GetAttacker(), d:GetInflictor()
    local from = (IsValid(att) and CREATURES[att:GetClass()]) or (IsValid(inf) and CREATURES[inf:GetClass()])
    if from and GK.RunMode(ent) == "hard" then d:ScaleDamage(2) end
end)
