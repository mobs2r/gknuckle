-- Automated smoke test. Only runs when data/gknuckle/selftest.txt exists:
-- drives the local player through climbing, lifting, throwing, kicking and the
-- stun burst, logs results to console (use -condebug), takes screenshots, quits.

if not file.Exists("gknuckle/selftest.txt", "DATA") then return end

local function log(...) print("[GKTEST]", ...) end

if CLIENT then
    local held, untilT = 0, 0
    net.Receive("gk_selftest", function()
        local kind = net.ReadString()
        if kind == "input" then
            held = net.ReadUInt(32)
            untilT = CurTime() + net.ReadFloat()
        elseif kind == "shot" then
            -- Screenshots only in the explicit "shots" focus mode (the user asked for a few pictures).
            if GetGlobal2Bool("gk_selftest_shots", false) then RunConsoleCommand("jpeg_quality", "95") RunConsoleCommand("jpeg") end
        elseif kind == "inv" then
            GAMEMODE:ScoreboardShow()
        elseif kind == "invclose" then
            GAMEMODE:ScoreboardHide()
        end
    end)
    timer.Create("GK_SelfTestFPS", 2, 0, function()
        print("[GKTEST]", "client fps", math.Round(1 / math.max(RealFrameTime(), 0.0001)))
    end)
    hook.Add("CreateMove", "GK_SelfTest", function(cmd)
        if CurTime() < untilT then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), held))
            if bit.band(held, IN_FORWARD) ~= 0 then cmd:SetForwardMove(200) end
        end
    end)
    return
end

util.AddNetworkString("gk_selftest")

local function press(ply, buttons, dur)
    net.Start("gk_selftest") net.WriteString("input") net.WriteUInt(buttons, 32) net.WriteFloat(dur) net.Send(ply)
end
local function shot(ply) net.Start("gk_selftest") net.WriteString("shot") net.Send(ply) end

local function face(ply, pos)
    ply:SetEyeAngles((pos - ply:EyePos()):Angle())
end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end

local function state(ply)
    return ("pos.z=%.0f vel=%.0f handL=%d handR=%d anchorL=%s stamina=%.0f chip=%s ragdoll=%s"):format(
        ply:GetPos().z, ply:GetVelocity():Length(), ply:GetNW2Int("gk_hand_l"), ply:GetNW2Int("gk_hand_r"),
        tostring(ply:GetNW2Bool("gk_anchor_l")), GK.Stamina(ply), tostring(GK.IsChipOnline(ply)), tostring(GK.IsRagdolled(ply)))
end

local P, tower, startZ

step(0, function()
    P = player.GetHumans()[1]
    log("gamemode", engine.ActiveGamemode(), "map", game.GetMap(), "player", IsValid(P) and P:Nick())
    local counts = {}
    for _, e in ipairs(ents.GetAll()) do
        if e.GK_Starter then counts[e:GetClass()] = (counts[e:GetClass()] or 0) + 1 end
    end
    log("starter ents", util.TableToJSON(counts))
    local wep = {}
    for _, w in ipairs(P:GetWeapons()) do wep[#wep + 1] = w:GetClass() end
    log("weapons", table.concat(wep, ","), "active", IsValid(P:GetActiveWeapon()) and P:GetActiveWeapon():GetClass())
    for _, e in ipairs(ents.GetAll()) do
        if e.GK_Starter and e:GetClass() == "prop_physics" and IsValid(e:GetPhysicsObject()) and not e:GetPhysicsObject():IsMotionEnabled() then
            if not tower or e:GetPos().z < tower:GetPos().z then tower = e end
        end
    end
    log("tower base", tostring(tower and tower:GetPos()))
    shot(P)
end)

-- Climb test: stand at the tower, hold LMB on it, then pull up with W.
step(2, function()
    if not IsValid(tower) then log("CLIMB SKIP: no tower") return end
    local back = (P:GetPos() - tower:GetPos()) back.z = 0 back:Normalize()
    P:SetPos(tower:GetPos() + back * 60 - Vector(0, 0, tower:OBBMaxs().z * 0))
    P:SelectWeapon("gk_mind")
    face(P, tower:GetPos() + Vector(0, 0, 50))
    startZ = P:GetPos().z
    log("climb start", state(P))
    press(P, IN_ATTACK, 3)
end)
step(1, function() log("climb gripping", state(P)) press(P, bit.bor(IN_ATTACK, IN_FORWARD), 3) end)
step(0.5, function() log("climb pull 0.5s", state(P)) end)
step(0.5, function() log("climb pull 1.0s", state(P)) shot(P) end)
step(1, function() log("climb pull 2.0s", state(P)) end)
step(1.2, function() log("climb end", state(P), "rose", ("%.0f"):format(P:GetPos().z - startZ)) end)

-- Lift + throw test with a chair.
local chair
step(1, function()
    P:SetPos(P:GetPos() + Vector(0, 0, 0))
    chair = ents.Create("prop_physics")
    chair:SetModel("models/props_c17/chair02a.mdl")
    chair:SetPos(P:EyePos() + P:GetAimVector() * 70 + Vector(0, 0, -20))
    chair:Spawn()
    face(P, chair:WorldSpaceCenter())
    log("chair mass", chair:GetPhysicsObject():GetMass())
    press(P, IN_ATTACK, 2.5)
end)
step(1.2, function() log("lift", state(P), "chairZ", ("%.0f"):format(chair:GetPos().z)) shot(P) end)
step(0.3, function()
    GK.Kick(P) -- kick key while holding = throw
    timer.Simple(0.12, function() log("throw chair vel", ("%.0f"):format(chair:GetVelocity():Length()), state(P)) end)
end)
step(0.6, function() log("after throw (should not re-grab)", state(P)) end)

-- Kick a bot.
local bot
step(1, function() RunConsoleCommand("bot") end)
step(2, function()
    bot = player.GetBots()[1]
    if not IsValid(bot) then log("KICK SKIP: no bot") return end
    P:SetNW2Entity("gk_impaled", NULL)
    P.GK_NextKick = 0
    local sp = ents.FindByClass("info_player_start")[1]:GetPos()
    P:SetPos(sp)
    P:SetEyeAngles(Angle(0, 0, 0))
    bot:SetPos(sp + Vector(55, 0, 0))
    timer.Simple(0.5, function()
        -- Put the bot where we're actually aiming (server aim lags SetEyeAngles).
        local aim = P:GetAimVector() aim.z = 0 aim:Normalize()
        bot:SetPos(P:GetPos() + aim * 50)
        local start = P:GetShootPos() - Vector(0, 0, 30)
        local tr = util.TraceHull({ start = start, endpos = start + P:GetAimVector() * GK.Config.KickRange,
            mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10), filter = P, mask = MASK_SHOT_HULL })
        log("kick trace hits", tostring(tr.Entity), "onground", tostring(P:OnGround()), "wep", P:GetActiveWeapon():GetClass(),
            "legs", tostring(GK.HasLegs(P)))
        GK.Kick(P)
        timer.Simple(0.2, function() log("kick bot right after", state(bot)) end)
    end)
end)
step(1, function() if IsValid(bot) then log("kick bot", state(bot)) shot(P) end end)

-- Stun burst on ourselves.
step(4, function()
    GK.ChipBurst(P:GetPos(), 200, 4, P)
    log("stun", state(P))
end)
step(0.5, function() shot(P) end)

-- Vendor menu opens?
step(2, function()
    local v = ents.FindByClass("gk_vendor")[1]
    log("vendor", tostring(IsValid(v) and v:GetPos()), tostring(IsValid(v) and v:GetAngles()))
    if IsValid(v) then
        local n = v.GK_WallNormal or v:GetForward()
        log("vendor wall normal", tostring(n), "forward", tostring(v:GetForward()), "right", tostring(v:GetRight()))
        P:SetPos(v:GetPos() + n * 170 + Vector(0, 0, 10))
        face(P, v:WorldSpaceCenter())
    end
end)
step(1, function() shot(P) end)
step(1, function()
    local v = ents.FindByClass("gk_vendor")[1]
    if IsValid(v) then v:Use(P, P) end
end)
-- Overview of the starter playground.
step(1, function()
    if IsValid(tower) then
        P:SetPos(tower:GetPos() + (P:GetPos() - tower:GetPos()):GetNormalized() * 0 + Vector(300, 300, 0))
        face(P, tower:GetPos() + Vector(0, 0, 60))
    end
end)
step(1, function() shot(P) end)
step(1, function() shot(P) end)

-- Movement: CS:GO convars + walk speed check.
step(1, function()
    log("movement", "accel", GetConVar("sv_accelerate"):GetFloat(), "air", GetConVar("sv_airaccelerate"):GetFloat(),
        "friction", GetConVar("sv_friction"):GetFloat(), "grav", GetConVar("sv_gravity"):GetFloat(),
        "walk", P:GetWalkSpeed(), "run", P:GetRunSpeed(), "jump", P:GetJumpPower())
    local sp = ents.FindByClass("info_player_start")[1]:GetPos()
    P:SetPos(sp)
    P:SetEyeAngles(Angle(0, 0, 0))
    press(P, IN_FORWARD, 2)
end)
step(1.5, function() log("run speed after 1.5s", ("%.0f"):format(P:GetVelocity():Length2D())) end)

-- Inventory: revolver from bag into the right hand, left hand climbs, RMB
-- fires, R reload is two-handed, E pockets, G drops, clicking picks it up.
local function invDump()
    local inv = GK.Inv.Get(P)
    local bag = {}
    for _, it in ipairs(inv.bag) do bag[#bag + 1] = it.class end
    local slots = {}
    for k, it in pairs(inv.slots) do slots[#slots + 1] = k .. "=" .. it.class end
    return "bag[" .. table.concat(bag, ",") .. "] slots[" .. table.concat(slots, ",") .. "]"
end
local function rev() return GK.Inv.HandItem(P, "r") end
step(1, function()
    GK.Inv.Give(P, "revolver")
    log("inv after give", invDump())
    net.Start("gk_selftest") net.WriteString("inv") net.Send(P)
end)
step(1, function() shot(P) end)
step(0.5, function()
    net.Start("gk_selftest") net.WriteString("invclose") net.Send(P)
    for _, it in ipairs(GK.Inv.Get(P).bag) do
        if it.class == "revolver" then GK.Inv.Move(P, it.id, "hand_r") end
    end
    log("revolver in right hand", tostring(rev() ~= nil), invDump())
    if IsValid(tower) then
        local back = (P:GetPos() - tower:GetPos()) back.z = 0 back:Normalize()
        P:SetPos(tower:GetPos() + back * 60)
        face(P, tower:GetPos() + Vector(0, 0, 50))
    end
end)
step(0.6, function() press(P, IN_ATTACK, 3) end)
step(0.8, function() log("left hand grips while right holds gun", state(P)) GK.Inv.Use(P, "r") end)
step(0.4, function() log("fired, clip", rev() and rev().data.clip, state(P)) shot(P) end)
step(0.3, function() GK.Inv.Reload(P) end)
step(0.5, function() log("reloading (should not grip)", state(P), "busy", tostring(P:GetNW2Float("gk_busy_until") > CurTime())) shot(P) end)
step(2.6, function() log("reload done clip", rev() and rev().data.clip, "ammo", rev() and rev().data.ammo) end)
step(0.3, function() GK.Inv.Pocket(P, "r") log("pocketed", invDump()) end)
step(0.3, function() GK.Inv.Pocket(P, "r") log("unpocketed", invDump()) end)
step(0.3, function() GK.Inv.DropHand(P) log("dropped", invDump(), "world items", #ents.FindByClass("gk_item")) end)
step(1, function()
    local it = ents.FindByClass("gk_item")[1]
    if IsValid(it) then
        local ok = GK.Inv.PickupToHand(P, it, "r")
        log("picked back up", tostring(ok), invDump())
    end
    GK.Kick(P)
    log("kick ok, next kick at", P.GK_NextKick)
end)
-- WK brick: real model, thrown at the bot, should shatter and ragdoll it.
step(4, function()
    GK.Inv.DropHand(P)
    local inv = GK.Inv.Get(P)
    inv.slots.hand_r = nil
    GK.Inv.Give(P, "brick")
    for _, it in ipairs(inv.bag) do if it.class == "brick" then GK.Inv.Move(P, it.id, "hand_r") break end end
    log("brick model valid", tostring(util.IsValidModel("models/gknuckle/wk/brick.mdl")), invDump())
    if IsValid(bot) then
        local aim = P:GetAimVector() aim.z = 0 aim:Normalize()
        bot:SetPos(P:GetPos() + aim * 150)
        bot:SetNW2Entity("gk_ragdoll", NULL)
    end
end)
step(0.5, function()
    if IsValid(bot) then P:SetEyeAngles((bot:WorldSpaceCenter() - P:EyePos()):Angle()) end
end)
step(0.5, function()
    GK.Inv.Use(P, "r")
    log("brick thrown, bricks in flight", #ents.FindByClass("gk_brick"))
end)
step(0.4, function() if IsValid(bot) then log("bot after brick", state(bot)) end shot(P) end)
step(1, function() log("DONE") end)
step(2, function() game.ConsoleCommand("quit\n") end)

-- On gm_flatgrass: test a random White Knuckle run (roguelite mode).
if game.GetMap() == "gm_flatgrass" then
    steps = {}
    local spawnPos
    step(0, function()
        P = player.GetHumans()[1]
        P:SetPos(Vector(0, 0, -12700))
        local pieces, err = GK.GenerateRun("Region_Silos_Campaign", 4242)
        log("run pieces", pieces and table.concat(pieces, " > ") or err)
        local origin = Vector(0, 0, -12780)
        spawnPos = GK.SpawnRun(pieces or {}, origin)
        local n, chunks = 0, 0
        for _, e in ipairs(GK.Levels.spawned) do
            if e:GetClass() == "gk_level_piece" then n = n + 1 end
        end
        log("spawned level pieces", n, "spawn at", tostring(spawnPos))
        -- Check each room's entrance sits on the previous exit (stacking sanity).
        local prevExit
        for i, e in ipairs(GK.Levels.spawned) do
            if e:GetClass() == "gk_level_piece" then
                local lay = util.JSONToTable(file.Read("data_static/gknuckle/levels/" .. e:GetPiece() .. ".json", "GAME") or "") or {}
                local ent = lay.entrances and lay.entrances[1] and (e:GetPos() + GK.LevelToModel(lay.entrances[1].pos))
                local ex = lay.exits and lay.exits[1] and (e:GetPos() + GK.LevelToModel(lay.exits[1].pos))
                if prevExit and ent then log("join", e:GetPiece(), "gap", ("%.1f"):format(prevExit:Distance(ent))) end
                prevExit = ex
            end
        end
    end)
    step(1, function()
        P:SetPos(GK.FindSafeSpot(P, spawnPos) or spawnPos)
    end)
    step(2, function() log("standing", state(P), "onground", tostring(P:OnGround())) shot(P) end)
    for i, yaw in ipairs({ 90, 180, 270 }) do
        step(1, function() P:SetEyeAngles(Angle(-10, yaw, 0)) end)
        step(0.7, function() shot(P) end)
    end
    step(1, function() P:SetPos(Vector(0, 0, -12780) + Vector(600, 600, 1400)) P:SetEyeAngles(Angle(35, -135, 0)) end)
    step(1.5, function() log("after drop", state(P)) shot(P) end)
    step(1, function() log("DONE") end)
end

-- Focus mode (data/gknuckle/selftest_focus.txt: "<region> <seed> [nohooks]"): on gk_style,
-- build just that run in arena 1, climb through it room by room (forcing the
-- streaming), and log every 2 s so a hard exit can be placed. "nohooks" removes
-- every GK_ArenaRoomSpawned / GK_ArenaBuilt hook first, to tell the room models
-- from what gameplay spawns into them.
local focusText = SERVER and file.Read("gknuckle/selftest_focus.txt", "DATA") or nil
-- One-shot: the focus file goes as soon as it is read, so a stale one can never arm a later game.
if SERVER and focusText then file.Delete("gknuckle/selftest_focus.txt") end
GK_SELFTEST_CVAR_DEFAULTS = { gk_creatures = "1", gk_spawn_barnacles = "1", gk_spawn_turrets = "1", gk_spawn_gasbags = "1", gk_spawn_bloodbugs = "1", gk_spawn_grubs = "1", gk_spawn_crates = "1", gk_bloodbug_chance = "0.12" }
if SERVER and game.GetMap() == "gk_style" and not focusText then
    for k, v in pairs(GK_SELFTEST_CVAR_DEFAULTS) do if ConVarExists(k) and GetConVar(k):GetString() ~= v then RunConsoleCommand(k, v) print("[GKTEST] cvar reset to default", k, v) end end
end
-- "shots" mode (selftest_focus.txt: "shots 1"): teleport through a list of hub views and
-- take a jpeg at each (garrysmod/screenshots/gk_style*.jpg), nothing else.
local shotsMode = focusText and string.match(string.Trim(focusText), "^shots") ~= nil
if game.GetMap() == "gk_style" and shotsMode then
    steps = {}
    SetGlobal2Bool("gk_selftest_shots", true)
    -- Views: the 0.4 layout when hub.hall.shape is "octagon", else the 0.3 hub.
    -- (chosen inside the first step: GK.HubLayout is defined after this file is included)
    local V4 = {
            { Vector(-2150, -600, 0), 180, 0 },        -- the mirror in the hide-and-seek yard, from 250 u in front
            { Vector(834, 1004, 784), 342, 50 },       -- upper deck: a ladder hatch from above
            { Vector(-200, 1300, 784), 270, 14 },      -- upper deck: the bridge and the collar round the hypervisor
            { Vector(0, -1000, 0), 90, -10 },          -- floor: the hypervisor joined to the catwalks
            { Vector(0, 2400, 0), 90, -45 },           -- birthing bunker: the drop tube in its ceiling hole
            { Vector(-1000, -760, 464), 45, 10 },      -- lower deck: the ring past a ladder
            { Vector(0, -300, 0), 90, -70 },           -- inside the hypervisor: the three tubes overhead
            { Vector(0, 0, 0), 270, 0 },               -- inside the hypervisor: the V and the south pads
            { Vector(1100, -400, 784), 160, 20 },      -- upper deck: catwalk rails and brackets
            { Vector(-3000, 0, 0), 0, 0 },             -- hide-and-seek yard towards the atrium doorway
        }
    local V3 = {
            { Vector(-720, -1010, 464), 56, 12 }, { Vector(0, 1000, 0), 270, -6 }, { Vector(0, 420, 0), 270, -12 }, { Vector(-1000, -560, 0), 15, -14 },
            { Vector(-360, -600, 0), 180, -2 }, { Vector(-1960, -600, 0), 180, -2 }, { Vector(1960, -600, 0), 0, -2 }, { Vector(0, 1640, 0), 90, -4 },
            { Vector(0, 2300, 0), 90, 6 }, { Vector(1100, 300, 464), 180, 4 },
        }
    local V = {}
    for i = 1, math.max(#V3, #V4) do V[i] = V4[i] or V3[i] end
    step(4, function()
        P = player.GetHumans()[1]
        local hub = GK.HubLayout and GK.HubLayout() or {}
        local oct = hub.hall and hub.hall.shape == "octagon"
        for i = 1, #V do V[i] = oct and V4[i] or V3[i] end
        log("shots", #V, oct and "octagon" or "round")
    end)
    for _, view in ipairs(V) do
        step(1.2, function() if not view then return end P:SetPos(Vector(view[1].x, view[1].y, -14984 + view[1].z)) P:SetEyeAngles(Angle(view[3], view[2], 0)) end)
        step(1.5, function() if view then shot(P) end end)
    end
    step(3, function() log("DONE") end)
end
-- "spawncheck N" mode: every region, seeds 1..N: build the run, hull-trace down from the
-- raw marker and from the settled spawn, log both drops, clear. Finds first rooms whose
-- marker hangs in the air (the 0.3.10 tube-ride fall).
local sweepN = focusText and tonumber(string.match(string.Trim(focusText), "^spawncheck%s+(%d+)"))
if game.GetMap() == "gk_style" and sweepN then
    steps = {}
    if SERVER then
        local function dropOf(p)
            local tr = util.TraceHull({ start = p, endpos = p - Vector(0, 0, 8192), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = function(e) return e:IsWorld() or e:GetClass() == "gk_level_chunk" or e:GetClass() == "gk_level_piece" end })
            if tr.StartSolid then return "SOLID" end
            if not tr.Hit then return "NONE" end
            return ("%.0f"):format(p.z - tr.HitPos.z)
        end
        -- (GK.Arena is not loaded yet when steps are built: list every run region here, as sv_wk_arena.lua RunRegions)
        local regions = { "Region_Silos_Campaign", "Region_Silos_Endless", "Region_Pipeworks_Campaign", "Region_Pipeworks_Endless", "Region_Habitation_Campaign", "Region_Habitation_Endless", "Region_Nest_Campaign", "Region_Nest_Endless", "Region_Chimney_Endless", "Region_Ladder_Endless" }
        step(3, function() P = player.GetHumans()[1] end)
        for _, region in ipairs(regions) do
            for seed = 1, sweepN do
                step(0.35, function()
                    local tg = SysTime()
                    local free = GK.GenerateRun(region, seed) or {}
                    local tg1 = SysTime()
                    local fit = GK.GenerateRun(region, seed, 9472) or {}
                    local genms = ("%d/%d"):format(math.Round((tg1 - tg) * 1000), math.Round((SysTime() - tg1) * 1000))
                    local t0 = SysTime()
                    local ai = (seed - 1) % GK.Arena.Count() + 1
                    local info, err = GK.Arena.Start(ai, region, seed)
                    local ms = math.Round((SysTime() - t0) * 1000)
                    if info then
                        local b = info.bounds
                        local out = math.max(math.abs(b.mins.x), math.abs(b.maxs.x), math.abs(b.mins.y), math.abs(b.maxs.y), math.abs(b.mins.z), math.abs(b.maxs.z))
                        -- air between consecutive rooms of the planned run (bounds, world z)
                        local worst, wpair = -math.huge, ""
                        for k = 1, #info.plan - 1 do
                            local A, B = GK.LevelLayout(info.plan[k].piece), GK.LevelLayout(info.plan[k + 1].piece)
                            if A.bounds and B.bounds then
                                local g = (info.plan[k + 1].pos.z + B.bounds.mins[3]) - (info.plan[k].pos.z + A.bounds.maxs[3])
                                if g > worst then worst, wpair = g, info.plan[k].piece .. ">" .. info.plan[k + 1].piece end
                            end
                        end
                        log(worst > 300 and "sweep AIRGAP" or "sweep gap", region, seed, ("%.0f"):format(worst), wpair)
                        -- loose pickups resting on something (wall-mounted rope, rebar, pitons excluded)
                        local wall = { rebar = true, rebarrope = true, piton = true, autopiton = true, grub = true }   -- grubs are gameplay creatures that cling
                        local loose, hover = 0, 0
                        for _, e in ipairs(ents.FindByClass("gk_item*")) do
                            if e.GKItemClass and not wall[e.GKItemClass] then
                                loose = loose + 1
                                local tr = util.TraceLine({ start = e:GetPos() + Vector(0, 0, 2), endpos = e:GetPos() - Vector(0, 0, 40), mask = MASK_SOLID, filter = function(x) return x:IsWorld() or x:GetClass() == "gk_level_chunk" end })
                                if not tr.Hit then
                                    hover = hover + 1
                                    if hover <= 3 then
                                        local t2 = util.TraceLine({ start = e:GetPos() + Vector(0, 0, 2), endpos = e:GetPos() - Vector(0, 0, 2000), mask = MASK_SOLID, filter = function(x) return x:IsWorld() or x:GetClass() == "gk_level_chunk" end })
                                        local t3 = util.TraceLine({ start = e:GetPos() + Vector(0, 0, 2), endpos = e:GetPos() - Vector(0, 0, 2000), mask = MASK_SOLID })
                                        log("hover", e.GKItemClass, tostring(e:GetPos()), "chunk-trace", tostring(t2.Hit), ("%.0f"):format(t2.Fraction * 2000), "any-trace", tostring(t3.Hit), IsValid(t3.Entity) and t3.Entity:GetClass() or "world", ("%.0f"):format(t3.Fraction * 2000), "asleep", tostring(e.GK_Asleep))
                                    end
                                end
                            end
                        end
                        log("sweep items", region, seed, "loose", loose, "hovering", hover)
                        log(out > 15900 and "sweep OUTSIDE" or "sweep bounds", region, seed, "arena", ai, ("x %.0f..%.0f y %.0f..%.0f z %.0f..%.0f"):format(b.mins.x, b.maxs.x, b.mins.y, b.maxs.y, b.mins.z, b.maxs.z))
                    end
                    if not info then log("sweep FAIL", region, seed, tostring(err)) return end
                    local raw, now = dropOf(info.spawnRaw or info.spawn), dropOf(info.spawn)   -- (arena ai)
                    local bad = (now ~= "SOLID" and tonumber(now) and tonumber(now) > 80) or now == "NONE" or now == "SOLID"
                    local who = ""
                    if bad then
                        local p0 = info.spawnRaw or info.spawn
                        local tr = util.TraceHull({ start = p0, endpos = p0, mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID })
                        local e = tr.Entity
                        who = IsValid(e) and (e:GetClass() .. ":" .. tostring(e.GetPiece and e:GetPiece() or e:GetModel())) or (tr.HitWorld and "world" or "none")
                        local names = {}
                        for i = 1, math.min(3, #info.plan) do names[#names + 1] = info.plan[i].piece .. "@" .. tostring(info.plan[i].pos) end
                        who = who .. " | raw " .. tostring(p0) .. " | " .. table.concat(names, " > ")
                    end
                    log(bad and "sweep BAD" or "sweep", region, seed, info.plan[1].piece, "raw drop", raw, "settled drop", now, "via", tostring(info.spawnHow), "ms", ms, "rooms", #info.plan, "gen free/fit ms", genms, "rooms free/fit", #free .. "/" .. #fit, who)
                    GK.Arena.Clear(ai)
                end)
            end
        end
        step(1, function() log("DONE") end)
    end
end
-- "climb <region> <seed0> <seed1> [arena]": for each seed, build the run with every hook
-- on (creatures, movers, hazards) and carry the player up room by room so the stream
-- builds ahead, logging each step; reproduces crashes that need streaming with gameplay on.
local climbRegion, climbS0, climbS1, climbArena = nil, nil, nil, nil
if focusText then climbRegion, climbS0, climbS1, climbArena = string.match(string.Trim(focusText), "^climb%s+(%S+)%s+(%d+)%s+(%d+)%s*(%d*)") end
if game.GetMap() == "gk_style" and climbRegion then
    steps = {}
    if SERVER then
        local ai = tonumber(climbArena) or 1
        step(3, function()
            P = player.GetHumans()[1]
            for k, v in pairs(GK_SELFTEST_CVAR_DEFAULTS) do RunConsoleCommand(k, v) end
            for k, v in string.gmatch(focusText, "([%w_]+)=(%S+)") do RunConsoleCommand(k, v) log("climb cvar", k, v) end
            if string.find(focusText, "nohooks", 1, true) then
                for _, ev in ipairs({ "GK_ArenaRoomSpawned", "GK_ArenaBuilt", "GK_ArenaStart" }) do
                    for name in pairs(hook.GetTable()[ev] or {}) do log("climb: removing hook", ev, tostring(name)) hook.Remove(ev, name) end
                end
            end
        end)
        for seed = tonumber(climbS0), tonumber(climbS1) do
            local info
            step(0.5, function()
                info = GK.Arena.Start(ai, climbRegion, seed)
                log("climb start", climbRegion, seed, "arena", ai, info and #info.plan or -1, info and info.plan[1].piece or "")
                if info then P:SetPos(info.spawn) end
            end)
            for n = 1, 16 do
                step(1.0, function()
                    if not info then return end
                    local room = info.rooms[math.min(info.built, n)]
                    if room then P:SetPos(Vector((room.bounds.mins.x + room.bounds.maxs.x) / 2, (room.bounds.mins.y + room.bounds.maxs.y) / 2, room.bounds.maxs.z - 100)) end
                    log("climb tick", seed, n, "built", info.built, "of", #info.plan, "piece", info.plan[math.min(info.built, #info.plan)].piece, "movers", #ents.FindByClass("gk_mover"), "chunks", #ents.FindByClass("gk_level_chunk"), "phys", #ents.FindByClass("prop_physics"), "edicts", ents.GetEdictCount(), "pool", (GK.ChunkPoolStats and GK.ChunkPoolStats() or -1))
                end)
            end
            step(0.5, function() GK.Arena.Clear(ai) log("climb cleared", seed) end)
        end
        step(1, function() log("DONE") end)
    end
end
-- "cycle <region> <seed> <n> [arena]": build and clear the same run n times, 5 s apart, to
-- see whether memory comes back after a clear (the proc monitor log has the process size).
local cycRegion, cycSeed, cycN, cycArena
if focusText then cycRegion, cycSeed, cycN, cycArena = string.match(string.Trim(focusText), "^cycle%s+(%S+)%s+(%d+)%s+(%d+)%s*(%d*)") end
if game.GetMap() == "gk_style" and cycRegion then
    steps = {}
    if SERVER then
        local ai = tonumber(cycArena) or 1
        step(3, function()
            P = player.GetHumans()[1]
            for _, ev in ipairs({ "GK_ArenaRoomSpawned", "GK_ArenaBuilt", "GK_ArenaStart" }) do for name in pairs(hook.GetTable()[ev] or {}) do hook.Remove(ev, name) end end
            P:SetPos(Vector(0, -900, -14984))
            for k, v in string.gmatch(focusText, "([%w_]+)=(%S+)") do RunConsoleCommand(k, v) log("cycle cvar", k, v) end
        end)
        for i = 1, tonumber(cycN) do
            step(2.5, function()
                local info = GK.Arena.Start(ai, cycRegion, tonumber(cycSeed))
                log("cycle build", i, os.date("%H:%M:%S"), "chunks", #ents.FindByClass("gk_level_chunk"), "luaKB", math.floor(collectgarbage("count")), info and info.built or -1)
            end)
            step(2.5, function() GK.Arena.Clear(ai) collectgarbage() log("cycle clear", i, os.date("%H:%M:%S"), "luaKB", math.floor(collectgarbage("count")), "pool", GK.ChunkPoolStats and GK.ChunkPoolStats() or -1, "edicts", ents.GetEdictCount()) end)
        end
        step(3, function()
            log("cycle end", os.date("%H:%M:%S"), "chunks", #ents.FindByClass("gk_level_chunk"))
            -- "reload": change level to the same map, to see whether that frees the leaked collides
            if string.find(focusText, "reload", 1, true) then log("cycle reload", os.date("%H:%M:%S")) game.ConsoleCommand("changelevel " .. game.GetMap() .. string.char(10)) else log("DONE") end
        end)
    end
end
-- "chunkcycle <piece> <n> [mode]": spawn just the collision chunks of one piece and remove
-- them, n times, to see whether the collides alone leak. mode "piece" spawns the whole
-- gk_level_piece instead (chunks + its model), "chunks" (default) only the chunk entities.
local ccPiece, ccN, ccMode
if focusText then ccPiece, ccN, ccMode = string.match(string.Trim(focusText), "^chunkcycle%s+(%S+)%s+(%d+)%s*(%S*)") end
if game.GetMap() == "gk_style" and ccPiece then
    steps = {}
    if SERVER then
        local made = {}
        local origin = Vector(9000, -6000, -12000)
        step(3, function() P = player.GetHumans()[1] P:SetPos(Vector(0, -900, -14984)) log("chunkcycle", ccPiece, ccN, ccMode) end)
        for i = 1, tonumber(ccN) do
            step(2, function()
                made = {}
                if ccMode == "piece" then
                    made[1] = GK.SpawnLevel(ccPiece, origin) or ents.FindByClass("gk_level_piece")[#ents.FindByClass("gk_level_piece")]
                else
                    for key in pairs(GK.LevelChunks(ccPiece) or {}) do
                        local c = ents.Create("gk_level_chunk") c:SetPiece(ccPiece) c:SetCell(key) c:SetPos(origin) c:Spawn() made[#made + 1] = c
                    end
                end
                log("chunkcycle build", i, os.date("%H:%M:%S"), "chunks", #ents.FindByClass("gk_level_chunk"), "edicts", #ents.GetAll())
            end)
            step(2, function()
                for _, e in ipairs(made) do if IsValid(e) then if e.Retire then e:Retire() else e:Remove() end end end
                if ccMode == "piece" then for _, e in ipairs(GK.Levels.spawned) do if IsValid(e) then e:Remove() end end GK.Levels.spawned = {} end
                log("chunkcycle clear", i, os.date("%H:%M:%S"))
            end)
        end
        step(3, function() log("chunkcycle end", os.date("%H:%M:%S"), "chunks", #ents.FindByClass("gk_level_chunk"), "edicts", #ents.GetAll()) log("DONE") end)
    end
end
-- "dumpcell <piece> <cell>": write one chunk cell triangles to data/gknuckle/cell_dump.txt.
local dcPiece, dcCell
if focusText then dcPiece, dcCell = string.match(string.Trim(focusText), "^dumpcell%s+(%S+)%s+(%d+)") end
if game.GetMap() == "gk_style" and dcPiece then
    steps = {}
    if SERVER then
        step(2, function()
            local cells = GK.LevelChunks(dcPiece)
            local v = cells and cells[tonumber(dcCell)]
            local out = {}
            for i = 1, #(v or {}), 3 do
                local a, b, c = v[i].pos, v[i + 1].pos, v[i + 2].pos
                out[#out + 1] = ("%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f"):format(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z)
            end
            file.Write("gknuckle/cell_dump.txt", table.concat(out, string.char(10)))
            log("dumpcell", dcPiece, dcCell, #out) log("DONE")
        end)
    end
end
-- "gapshots": load each room the reach audit flags, stand at the gap's lower point
-- looking at the upper one with the handhold overlay on, and take two shots.
local gapMode = focusText and string.match(string.Trim(focusText), "^gapshots") ~= nil
if game.GetMap() == "gk_style" and gapMode then
    steps = {}
    if SERVER then
        SetGlobal2Bool("gk_selftest_shots", true)
        local GAPS = {
            { "m5_nest_trough_05", { 0, 0, 1889.8 }, { 0, 0, 2819.6 } },
            { "m5_nest_trough_endless_start_01", { -707.9, 1822.3, 3170.2 }, { -436.35, 210.1, 3174.1 } },
            { "mx_chimney_icebox_01", { 767.2, -839.1, -13.6 }, { 357.8, -348.2, 376.45 } },
            { "mx_chimney_icebox_03", { 767.2, -839.1, 0 }, { 705.8, -377.95, 301.4 } },
            { "mx_chimney_shelf_01", { -1393.05, 323.3, 1222.1 }, { -2102.6, 556.85, 1328.6 } },
            { "campaign_interlude_pipeworks_to_habitation_01", { -1959.35, 576.7, 2697.3 }, { -1622, 675.9, 2955 } },
        }
        step(3, function()
            P = player.GetHumans()[1]
            P:ConCommand("gk_drawhh 1")   -- the overlay needs sv_cheats 1, set on the launch line
            for _, ev in ipairs({ "GK_ArenaRoomSpawned", "GK_ArenaBuilt", "GK_ArenaStart" }) do for name in pairs(hook.GetTable()[ev] or {}) do hook.Remove(ev, name) end end
        end)
        for i, g in ipairs(GAPS) do
            local origin
            step(1, function()
                GK.ClearLevel()
                local lay = GK.LevelLayout(g[1])
                origin = Vector(0, 11000, -15000 - ((lay.bounds and lay.bounds.mins[3]) or 0))
                GK.SpawnLevel(g[1], origin)
                log("gap", i, g[1])
            end)
            step(2, function()
                local a = origin + GK.LevelToModel(g[2]) + Vector(0, 0, 4)
                local b = origin + GK.LevelToModel(g[3])
                P:SetMoveType(MOVETYPE_NOCLIP)
                P:SetPos(a)
                P:SetEyeAngles((b - (a + Vector(0, 0, 64))):Angle())
            end)
            step(1.2, function() shot(P) end)
            step(0.5, function()
                local a = origin + GK.LevelToModel(g[2])
                local b = origin + GK.LevelToModel(g[3])
                local mid = (a + b) / 2
                local side = (b - a):Cross(Vector(0, 0, 1)):GetNormalized()
                if side:LengthSqr() < 0.5 then side = Vector(1, 0, 0) end
                local cam = mid + side * 420 + Vector(0, 0, 60)
                P:SetPos(cam - Vector(0, 0, 64))
                P:SetEyeAngles((mid - cam):Angle())
            end)
            step(1.2, function() shot(P) end)
        end
        step(1, function() GK.ClearLevel() P:SetMoveType(MOVETYPE_WALK) log("DONE") end)
    end
end
-- "stages <n> [arena] [cvar=v ...]": the break-room path, n times in one arena slot: climb
-- the current region, step into the break pocket, start the next region in the same slot
-- (Arena.Start clears the old one in the same tick), wait, drop into the new spawn, repeat.
-- Regions cycle through GK.Arena.RunRegions with gameplay hooks on.
local stN, stArena
if focusText then stN, stArena = string.match(string.Trim(focusText), "^stages%s+(%d+)%s*(%d*)") end
if game.GetMap() == "gk_style" and stN then
    steps = {}
    if SERVER then
        local ai = tonumber(stArena) or 1
        local regions   -- GK.Arena exists only once the gamemode has loaded: read it in the first step
        local info
        step(3, function()
            P = player.GetHumans()[1]
            regions = GK.Arena.RunRegions
            for k, v in pairs(GK_SELFTEST_CVAR_DEFAULTS) do RunConsoleCommand(k, v) end
            for k, v in string.gmatch(focusText, "([%w_]+)=(%S+)") do RunConsoleCommand(k, v) log("stages cvar", k, v) end
            info = GK.Arena.Start(ai, regions[1], 101)
            if info then P:SetPos(info.spawn) end
            log("stage", 1, regions[1], info and #info.plan or -1)
        end)
        for s = 1, tonumber(stN) do
            for n = 1, 6 do
                step(0.8, function()
                    if not info then return end
                    local room = info.rooms[math.min(info.built, n)]
                    if room then P:SetPos(Vector((room.bounds.mins.x + room.bounds.maxs.x) / 2, (room.bounds.mins.y + room.bounds.maxs.y) / 2, room.bounds.maxs.z - 100)) end
                end)
            end
            step(0.5, function()
                local hub = GK.HubLayout and GK.HubLayout() or {}
                local pk = hub.pockets and hub.pockets[ai]
                if pk then P:SetPos(Vector(pk.center[1], pk.center[2], pk.center[3] + 8)) end
                local region = regions[(s % #regions) + 1]
                log("stage", s + 1, region, "edicts", ents.GetEdictCount(), "pool", (GK.ChunkPoolStats and GK.ChunkPoolStats() or -1))
                local gap = tonumber(string.match(focusText, "gap=(%S+)") or "0") or 0
                if gap > 0 then GK.Arena.Clear(ai) local t0 = SysTime() while SysTime() - t0 < 0 do end end
                if gap > 0 then
                    timer.Simple(gap, function() info = GK.Arena.Start(ai, region, 100 + s * 7919) log("stage built (after gap)", s + 1, info and info.built or -1) end)
                    return
                end
                info = GK.Arena.Start(ai, region, 100 + s * 7919)
                log("stage built", s + 1, info and info.built or -1, "of", info and #info.plan or -1)
            end)
            step(4, function() if info then P:SetPos(info.spawn) end end)
        end
        step(1, function() GK.Arena.Clear(ai) log("DONE") end)
    end
end
-- "look <piece> sx sy sz tx ty tz [sx2 sy2 sz2]": spawn one room alone, stand at s (SMD space)
-- looking at t, take a shot; optional second camera position looking at the same point.
local lkPiece, lkRest
if focusText then lkPiece, lkRest = string.match(string.Trim(focusText), "^look%s+(%S+)%s+(.+)$") end
if game.GetMap() == "gk_style" and lkPiece then
    steps = {}
    if SERVER then
        SetGlobal2Bool("gk_selftest_shots", true)
        local n = {}
        for v in string.gmatch(lkRest, "%S+") do n[#n + 1] = tonumber(v) end
        local origin
        step(3, function()
            P = player.GetHumans()[1]
            for _, ev in ipairs({ "GK_ArenaRoomSpawned", "GK_ArenaBuilt", "GK_ArenaStart" }) do for name in pairs(hook.GetTable()[ev] or {}) do hook.Remove(ev, name) end end
            local lay = GK.LevelLayout(lkPiece)
            origin = Vector(0, 11000, -15000 - ((lay.bounds and lay.bounds.mins[3]) or 0))
            GK.SpawnLevel(lkPiece, origin)
            P:SetMoveType(MOVETYPE_NOCLIP)
            log("look", lkPiece)
        end)
        local cams = { { n[1], n[2], n[3] } }
        if n[7] then cams[2] = { n[7], n[8], n[9] } end
        for _, c in ipairs(cams) do
            step(1.5, function()
                local s = origin + GK.LevelToModel(c)
                local t = origin + GK.LevelToModel({ n[4], n[5], n[6] })
                P:SetPos(s - Vector(0, 0, 64))
                P:SetEyeAngles((t - s):Angle())
            end)
            step(1.5, function() shot(P) end)
        end
        step(1, function() GK.ClearLevel() P:SetMoveType(MOVETYPE_WALK) log("DONE") end)
    end
end
-- "dusk <seed0> <seed1>": single-room dusk stages (Region_Dusk). For each seed: build it in
-- arena 1, log the room, spawn (and how it settled), top and bounds against the shaft,
-- then take a shot at the start looking up and one from the top looking down.
-- "drawcheck <region> <n> <pattern>": generate n runs of a region (seeds 1..n, shaft width)
-- and log how many draw a piece matching pattern, plus the pieces of the first that does.
local dcRegion, dcN, dcPat
if focusText then dcRegion, dcN, dcPat = string.match(string.Trim(focusText), "^drawcheck%s+(%S+)%s+(%d+)%s+(%S+)") end
if game.GetMap() == "gk_style" and dcRegion and SERVER then
    steps = {}
    step(3, function()
        local a = GK.Arena.Layout()[1]
        local hits, example = 0
        for seed = 1, tonumber(dcN) do
            local pieces = GK.GenerateRun(dcRegion, seed, 2 * a.half - 128) or {}
            if seed <= 3 then log("drawcheck run", seed, table.concat(pieces, " > ")) end
            local found = false
            for _, p in ipairs(pieces) do if string.find(p, dcPat) then found = true end end
            if found then hits = hits + 1 example = example or (seed .. ": " .. table.concat(pieces, " > ")) end
        end
        log("drawcheck", dcRegion, dcPat, "runs with it", hits, "of", dcN, "example", example or "-")
    end)
    step(1, function() log("DONE") end)
end
local duskS0, duskS1
if focusText then duskS0, duskS1 = string.match(string.Trim(focusText), "^dusk%s+(%d+)%s+(%d+)") end
if game.GetMap() == "gk_style" and duskS0 then
    steps = {}
    if SERVER then
        local info
        step(3, function()
            P = player.GetHumans()[1]
            for k, v in string.gmatch(focusText, "([%w_]+)=(%S+)") do RunConsoleCommand(k, v) log("dusk cvar", k, v) end
        end)
        for seed = tonumber(duskS0), tonumber(duskS1) do
            step(1, function()
                info = GK.Arena.Start(1, "Region_Dusk", seed)
                if not info then log("dusk", seed, "FAILED") return end
                local a = GK.Arena.Layout()[1]
                local b = info.bounds
                local inside = b.mins.z >= a.bottom - 1 and b.maxs.z <= a.top + 1 and math.abs((b.mins.x + b.maxs.x) / 2 - a.center.x) + (b.maxs.x - b.mins.x) / 2 <= a.half and math.abs((b.mins.y + b.maxs.y) / 2 - a.center.y) + (b.maxs.y - b.mins.y) / 2 <= a.half
                log("dusk", seed, info.plan[1].piece, "spawn", tostring(info.spawn), "via", info.spawnHow, "top", math.floor(info.top), "climb", math.floor(info.top - info.spawn.z), "inside shaft", tostring(inside))
                P:SetPos(info.spawn) P:SetEyeAngles(Angle(-35, 90, 0))
            end)
            step(2.5, function()
                if not info then return end
                log("dusk", seed, "after 2.5 s at the start: z", math.floor(P:GetPos().z), "stood", tostring(math.abs(P:GetPos().z - info.spawn.z) < 64 and P:IsOnGround()))
                shot(P)
            end)
            step(0.5, function()
                if not info then return end
                local d = GK.Arena.DuskRooms()[info.plan[1].piece]
                P:SetPos(info.plan[1].pos + GK.LevelToModel(d.top) + Vector(0, 0, 8)) P:SetEyeAngles(Angle(35, 270, 0))
            end)
            step(2.5, function() if info then shot(P) end end)
            -- "fall" token: drop from just off the top down through the whole room (players
            -- who let go fall like this); logs where they end up.
            if string.find(focusText, "fall", 1, true) then
                step(0.2, function() if info then P:SetPos(info.plan[1].pos + GK.LevelToModel(GK.Arena.DuskRooms()[info.plan[1].piece].top) + Vector(180, 180, 64)) P:SetVelocity(-P:GetVelocity()) end end)
                step(5, function() if info then log("dusk", seed, "fell to z", math.floor(P:GetPos().z)) end end)
            end
        end
        step(1, function() GK.Arena.Clear(1) log("DONE") end)
    end
end
if game.GetMap() == "gk_style" and focusText and not duskS0 and not dcRegion and not shotsMode and not sweepN and not climbRegion and not cycRegion and not ccPiece and not dcPiece and not gapMode and not stN and not lkPiece then
    steps = {}
    local region, seed, mode = string.match(string.Trim(focusText), "^(%S+)%s+(%d+)%s*(%S*)")
    -- Extra "name=value" tokens are convars to set before the run (bisecting what gameplay spawns).
    local cvars = {}
    for k, v in string.gmatch(focusText, "([%w_]+)=(%S+)") do cvars[k] = v end
    if mode and string.find(mode, "=", 1, true) then mode = "" end
    local info
    step(0, function()
        P = player.GetHumans()[1]
        if mode == "nohooks" then
            for _, ev in ipairs({ "GK_ArenaRoomSpawned", "GK_ArenaBuilt", "GK_ArenaStart" }) do
                for name in pairs(hook.GetTable()[ev] or {}) do log("focus: removing hook", ev, tostring(name)) hook.Remove(ev, name) end
            end
        end
        -- The creature convars are archived, so a bisect run would otherwise leave them
        -- off for every later run (it did on 2026-10-09): start from the defaults.
        for k, v in pairs(GK_SELFTEST_CVAR_DEFAULTS) do if cvars[k] == nil then RunConsoleCommand(k, v) end end
        for k, v in pairs(cvars) do RunConsoleCommand(k, v) log("focus: cvar", k, v) end
        log("focus", region, seed, mode)
        local err
        info, err = GK.Arena.Start(1, region, tonumber(seed))
        log("focus start", info and ("rooms=%d built=%d"):format(#info.plan, info.built) or tostring(err))
        if info then P:SetPos(GK.FindSafeSpot(P, info.spawn) or info.spawn) end
    end)
    for n = 1, 14 do
        step(2, function()
            if not info then return end
            local room = info.rooms[math.min(info.built, n)]
            if room then P:SetPos(Vector((room.bounds.mins.x + room.bounds.maxs.x) / 2, (room.bounds.mins.y + room.bounds.maxs.y) / 2, room.bounds.maxs.z - 100)) end
            log("focus tick", n, "built", info.built, "of", #info.plan, "movers", #ents.FindByClass("gk_mover"), "chunks", #ents.FindByClass("gk_level_chunk"), "items", #ents.FindByClass("gk_item"), "edicts", ents.GetEdictCount())
        end)
    end
    step(1, function() GK.Arena.Clear(1) log("DONE") end)
end

-- On gk_style: hub entities and views, every pad, then every run region in
-- every arena (bounds inside the shaft, spawn on solid ground, clean clear).
if game.GetMap() == "gk_style" and not focusText then
    steps = {}
    local LIMIT = 16000
    -- data/gknuckle/selftest_nohooks.txt: validate the map alone, with whatever
    -- gameplay spawns into rooms (movers, creatures, hazards) switched off.
    if SERVER and file.Exists("gknuckle/selftest_nohooks.txt", "DATA") then
        step(0, function()
            for _, ev in ipairs({ "GK_ArenaRoomSpawned", "GK_ArenaBuilt", "GK_ArenaStart" }) do
                for name in pairs(hook.GetTable()[ev] or {}) do log("nohooks: removed", ev, tostring(name)) hook.Remove(ev, name) end
            end
        end)
    end
    local function stuck(ply)
        local tr = util.TraceHull({ start = ply:GetPos(), endpos = ply:GetPos(), mins = ply:OBBMins(), maxs = ply:OBBMaxs(), filter = ply, mask = MASK_PLAYERSOLID })
        return tr.StartSolid or tr.Hit
    end
    local function ground(ply)
        local tr = util.TraceHull({ start = ply:GetPos(), endpos = ply:GetPos() - Vector(0, 0, 72), mins = ply:OBBMins(), maxs = ply:OBBMaxs(), filter = ply, mask = MASK_PLAYERSOLID })
        return tr.Hit and not tr.StartSolid, tr.Hit and (ply:GetPos().z - tr.HitPos.z) or -1
    end
    step(0, function()
        P = player.GetHumans()[1]
        log("hub", "pieces", #ents.FindByClass("gk_level_piece"), "pads", #ents.FindByClass("gk_pad"), "vendors", #ents.FindByClass("gk_vendor"),
            "vacuum", #ents.FindByClass("gk_vacuum"), "arenas", GK.Arena.Count(), "spawns", #ents.FindByClass("info_player_start"), "ladders", #ents.FindByClass("gk_ladder"), "buttons", #ents.FindByClass("gk_force_start"), "spawned at", tostring(P:GetPos()), "onground", tostring(P:OnGround()))
        -- Every spawn point must be free of world geometry.
        local bad = 0
        for _, s in ipairs(ents.FindByClass("info_player_start")) do
            local tr = util.TraceHull({ start = s:GetPos(), endpos = s:GetPos(), mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 72), mask = MASK_PLAYERSOLID, filter = player.GetAll() })
            if tr.StartSolid then bad = bad + 1 log("BAD SPAWN", tostring(s:GetPos())) end
        end
        log("spawns in solid", bad)
        shot(P)
    end)
    -- Views of the v4 hub: central bay, garden, pool, drop, side bays, catwalk, screens.
    local V = { { Vector(0, -850, 0), 90, -4 }, { Vector(-900, 0, 0), 0, -2 }, { Vector(0, 1250, 256), 90, -6 }, { Vector(0, 1450, 256), 90, -22 },
        { Vector(0, 1900, 256), 0, -89 }, { Vector(-1500, 0, 0), 180, -2 }, { Vector(1500, 0, 0), 0, -2 }, { Vector(-2800, -200, 0), 180, 0 },
        { Vector(-1200, -760, 464), 0, -8 }, { Vector(600, 700, 0), 90, 6 }, { Vector(0, 2650, 256), 90, -4 }, { Vector(0, -700, 0), 90, 2 }, { Vector(-640, -120, 0), 20, -12 }, { Vector(0, 0, 0), 270, -6 }, { Vector(-960, 640, 0), 90, -4 }, { Vector(0, -620, 0), 90, 8 }, { Vector(-1000, -500, 0), 0, 4 }, { Vector(-3300, -120, 0), 180, 2 }, { Vector(0, 1500, 256), 90, 0 }, { Vector(-300, 2650, 256), 60, 4 },
        { Vector(0, 450, 0), 90, -2 }, { Vector(0, 796, 0), 90, -35 }, { Vector(0, 1010, 300), 90, 4 }, { Vector(0, 1560, 256), 270, 2 }, { Vector(-400, 1330, 256), 300, 4 } }
    for _, view in ipairs(V) do
        step(0.6, function() P:SetPos(Vector(view[1].x, view[1].y, -14984 + view[1].z)) P:SetEyeAngles(Angle(view[3] or -8, view[2], 0)) end)
        step(0.9, function() shot(P) end)
    end
    -- Every pad: land on its target, stand there, and look around. Pads exist
    -- only at run time, so this step schedules its own sub-steps.
    local PAD_SLOT = 1.2
    local padCount = 0
    step(0.5, function()
        local pads = ents.FindByClass("gk_pad")
        padCount = #pads
        for i, pad in ipairs(pads) do
            timer.Simple((i - 1) * PAD_SLOT, function()
                local tgt = pad.GKTarget
                P:SetPos(GK.FindSafeSpot(P, tgt) or tgt)
                P:SetEyeAngles(Angle(10, 45, 0))
            end)
            timer.Simple((i - 1) * PAD_SLOT + 0.7, function()
                local g, h = ground(P)
                log("pad", i, pad:GetLabel(), "target", tostring(pad.GKTarget), "at", tostring(P:GetPos()), "ground", tostring(g), ("drop=%.0f"):format(h), "stuck", tostring(stuck(P)))
                if pad:GetLabel() == "PRACTICE" then shot(P) end
            end)
        end
    end)
    step(16, function() log("pads tested", padCount) end)
    -- Every run region in every arena.
    -- sv_wk_arena.lua is included after this file, so the list is copied here.
    local regions = (GK.Arena and GK.Arena.RunRegions) or {
        "Region_Silos_Campaign", "Region_Silos_Endless", "Region_Pipeworks_Campaign", "Region_Pipeworks_Endless",
        "Region_Habitation_Campaign", "Region_Habitation_Endless", "Region_Nest_Campaign", "Region_Nest_Endless",
        "Region_Chimney_Endless", "Region_Ladder_Endless",
    }
    for i, region in ipairs(regions) do
        local idx = (i - 1) % 3 + 1
        local info
        step(0.5, function()
            local err
            local t0 = SysTime()
            info, err = GK.Arena.Start(idx, region, 1000 + i)
            if not info then log("ARENA FAIL", idx, region, err) return end
            local a = GK.Arena.Layout()[idx]
            local b = info.bounds
            local inside = b.mins.x >= a.center.x - a.half - 64 and b.maxs.x <= a.center.x + a.half + 64 and b.mins.y >= a.center.y - a.half - 64 and b.maxs.y <= a.center.y + a.half + 64
            log("run", idx, region, ("rooms=%d built=%d build=%.2fs bottom=%.0f top=%.0f x=%.0f..%.0f y=%.0f..%.0f inside=%s topOK=%s"):format(
                #info.pieces, info.built, SysTime() - t0, info.bottom, info.top, b.mins.x, b.maxs.x, b.mins.y, b.maxs.y, tostring(inside), tostring(info.top < LIMIT - 600)))
            if not inside then log("OUT OF SHAFT", region, ("half=%d need x %.0f y %.0f"):format(a.half, math.max(a.center.x - b.mins.x, b.maxs.x - a.center.x), math.max(a.center.y - b.mins.y, b.maxs.y - a.center.y))) end
            P:SetPos(GK.FindSafeSpot(P, info.spawn) or info.spawn)
            P:SetEyeAngles(Angle(-20, 90, 0))
        end)
        step(2.2, function()
            if not info then return end
            local g, h = ground(P)
            log("run spawn", region, "at", tostring(P:GetPos()), "ground", tostring(g), ("drop=%.0f"):format(h), "stuck", tostring(stuck(P)), "arenaOf", GK.Arena.Of(P))
            shot(P)
            P:SetEyeAngles(Angle(-60, 90, 0))   -- up the shaft: region fog/void instead of the map sky
            timer.Simple(1.4, function() shot(P) end)
            -- Streaming: jump to the top of the last built room; more should build.
            local last = info.rooms[info.built]
            if last then P:SetPos(Vector((last.bounds.mins.x + last.bounds.maxs.x) / 2, (last.bounds.mins.y + last.bounds.maxs.y) / 2, last.bounds.maxs.z - 100)) end
        end)
        step(1.2, function()
            if not info then return end
            log("stream", region, "built", info.built, "of", #info.plan, "pieces now", #ents.FindByClass("gk_level_piece"), "chunks", #ents.FindByClass("gk_level_chunk"), "edicts", ents.GetEdictCount())
            -- Ladder volumes placed on the run's WK ladders, and movers/hazards gameplay spawned in it.
            local lad, mov = 0, 0
            for _, e in ipairs(ents.FindByClass("gk_ladder")) do if GK.Arena.Of(e) == idx then lad = lad + 1 end end
            for _, e in ipairs(ents.FindByClass("gk_mover")) do if GK.Arena.Of(e) == idx then mov = mov + 1 end end
            log("run ents", region, "ladders", lad, "movers", mov, "roaches", #ents.FindByClass("gk_roach"), "creatures", #ents.FindByClass("gk_creature") + #ents.FindByClass("gk_barnacle") + #ents.FindByClass("gk_turret") + #ents.FindByClass("gk_bloodbug") + #ents.FindByClass("gk_gasbag"))
            GK.Arena.Clear(idx)
        end)
        step(0.2, function() log("after clear", region, "pieces", #ents.FindByClass("gk_level_piece"), "gas", #ents.FindByClass("gk_gas"), "free", tostring(GK.Arena.Free())) end)
    end
    step(0.5, function() P:SetPos(Vector(0, -1000, -14984)) end)
    step(0.5, function() log("DONE") end)
end

-- On a compiled gk_wk_ map: check spawn, collision pieces, items, finish.
if string.StartsWith(game.GetMap(), "gk_wk_") then
    steps = {}
    step(0, function()
        P = player.GetHumans()[1]
        local pieces = ents.FindByClass("gk_level_piece")
        local physOk = 0
        for _, e in ipairs(pieces) do if IsValid(e:GetPhysicsObject()) then physOk = physOk + 1 end end
        log("map", game.GetMap(), "pieces", #pieces, "with physics", physOk, "items", #ents.FindByClass("gk_item"),
            "bricks", #ents.FindByClass("gk_brick"), "finish", #ents.FindByClass("gk_finish"),
            "static props", "(engine)")
        log("spawned at", tostring(P:GetPos()), "onground", tostring(P:OnGround()))
        shot(P)
    end)
    step(2, function() log("after 2s", tostring(P:GetPos()), "onground", tostring(P:OnGround())) end)
    for i, yaw in ipairs({ 0, 90, 180, 270 }) do
        step(0.8, function() P:SetEyeAngles(Angle(0, yaw, 0)) end)
        step(0.7, function() shot(P) end)
    end
    for _, e in ipairs({ 2, 4 }) do
        step(1, function()
            local pc = ents.FindByClass("gk_level_piece")[e]
            if IsValid(pc) then P:SetPos(pc:GetPos() + Vector(0, 0, 300)) P:SetEyeAngles(Angle(20, 45, 0)) end
        end)
        step(1.5, function() log("piece", e, tostring(P:GetPos()), "onground", tostring(P:OnGround())) shot(P) end)
    end
    step(1, function() log("DONE") end)
end

hook.Add("PlayerInitialSpawn", "GK_SelfTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_SelfTest")
    -- One-shot: the trigger file goes once the test is under way (the client has
    -- loaded its half by now), so a normal launch afterwards never re-runs it.
    file.Delete("gknuckle/selftest.txt")
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
