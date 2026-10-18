-- Birthing room check on gk_style's real entities: tube drops, the flush
-- (drain, swirl, clean-up, refill) and the match-end trigger.
-- Only runs when data/gknuckle/birthtest.txt exists. Logs "[GKBIRTH]"; no screenshots.
if not file.Exists("gknuckle/birthtest.txt", "DATA") then return end
local function log(...) print("[GKBIRTH]", ...) end
if CLIENT then return end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, bed, water, drop, it, wz0
local function named(n) return ents.FindByName(n)[1] end

step(0, function()
    P = player.GetHumans()[1]
    bed, water, drop = named("gk_pool_bed"), named("gk_pool_water"), named("gk_drop_spawn")
    local hub = util.JSONToTable(file.Read("data_static/gknuckle/hub.json", "GAME") or "") or {}
    log("entities: bed", tostring(IsValid(bed)), "water", tostring(IsValid(water)), water and water:GetClass() or "", "drop", tostring(IsValid(drop)),
        "bedZ", tostring(hub.garden and hub.garden.bedZ), "bed z", IsValid(bed) and math.floor(bed:GetPos().z) or "")
    log("match-end hook", tostring(hook.GetTable().GK_ArenaEnd and hook.GetTable().GK_ArenaEnd.GK_BirthingFlush ~= nil), "timers", tostring(timer.Exists("GK_TubeDrop")), tostring(timer.Exists("GK_FlushCycle")))
end)
step(0.5, function()
    for _ = 1, 8 do GK.Birthing.Drop() end
    log("dropped: junk", #ents.FindByClass("gk_trash"))
end)
step(5, function()
    local onBed, n = 0, 0
    for _, e in ipairs(ents.FindByClass("gk_trash")) do
        n = n + 1
        if IsValid(bed) and e:GetPos():Distance(bed:GetPos()) < 400 and e:GetPos().z < bed:GetPos().z + 60 then onBed = onBed + 1 end
    end
    log("after 5 s: junk", n, "lying on the bed", onBed)
    for _, e in ipairs(ents.FindByClass("gk_trash")) do log("junk above bed", math.floor(e:GetPos().z - bed:GetPos().z)) end
    -- An item on the bed, and us standing in the pool off-centre.
    it = ents.Create("gk_item") it.GKItemClass = "piton" it:SetPos(bed:GetPos() + Vector(60, 0, 10)) it:Spawn()
    P:SetPos(bed:GetPos() + Vector(180, 0, 16)) P:SetLocalVelocity(vector_origin) P:SetHealth(100)
    wz0 = water:GetPos().z
    GK.Birthing.Flush()
end)
step(0.5, function() log("0.5 s: player speed", math.floor(P:GetVelocity():Length2D()), "player above bed", math.floor(P:GetPos().z - bed:GetPos().z), "water level", P:WaterLevel()) end)
step(0.5, function() log("1 s into the flush: water moved", math.floor(water:GetPos().z - wz0), "player speed", math.floor(P:GetVelocity():Length2D())) end)
step(1.5, function()
    log("2.5 s: player speed", math.floor(P:GetVelocity():Length2D()))
    local left = 0
    for _, e in ipairs(ents.FindByClass("gk_trash")) do if e:GetPos():Distance(bed:GetPos()) < 400 then left = left + 1 end end
    log("2.5 s: water moved", math.floor(water:GetPos().z - wz0), "item on bed gone", tostring(not IsValid(it)), "junk left in pool", left, "player alive", tostring(P:Alive()))
end)
step(6, function() log("after: water back", math.floor(water:GetPos().z - wz0), "flushing", tostring(GK.Birthing.Flushing), "player hp", P:Health()) end)
-- Training drones: stand by a Foundations drone spawner and they come out.
step(0.5, function()
    local spot
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        local lay = GK.LevelLayout(piece:GetPiece())
        for _, sp in ipairs(lay.spawners or {}) do
            if (sp.spawns or {}).Denizen_Drone and not spot then spot = piece:GetPos() + GK.LevelToModel(sp.pos) log("drone spawner in", piece:GetPiece()) end
        end
    end
    if not spot then log("no drone spawners in the hub") return end
    local tr = util.TraceLine({ start = spot + Vector(0, 0, 40), endpos = spot - Vector(0, 0, 600), mask = MASK_PLAYERSOLID })
    P:SetPos(tr.HitPos + Vector(0, 0, 4)) P:SetLocalVelocity(vector_origin) P:SetHealth(100)
end)
step(3, function()
    local d = ents.FindByClass("gk_drone")
    log("drones out", #d, "model", d[1] and d[1]:GetModel() or "")
    if d[1] then d[1]:TakeDamage(200, P, P) log("shot one: state", d[1]:GetState(), "(5 down)") end
end)
step(5, function() local d = ents.FindByClass("gk_drone") log("after 5 s: drones", #d, "first state", d[1] and d[1]:GetState() or "", "player hp", P:Health()) end)
-- Roach NaN guard: poison a few roaches and blow one up on its own spot.
local rs = {}
step(0.5, function()
    P:SetPos(bed:GetPos() + Vector(300, 0, 60)) P:SetLocalVelocity(vector_origin)
    for k = 1, 4 do rs[k] = GK.SpawnRoach("gold", P:GetPos() + Vector(40 * k, 0, 4)) end
    local nan = 0 / 0
    rs[1].GK_Vel = Vector(nan, nan, nan)
    rs[2].GK_N = Vector(0, 0, 0)
    rs[3]:AddForce(Vector(nan, 0, 0))
    print("[GKBIRTH] zero normalized", tostring(Vector(0, 0, 0):GetNormalized()))
    rs[4]:AddForce((rs[4]:GetPos() - rs[4]:GetPos()):GetNormalized() * 300)
end)
step(2, function()
    local ok = 0
    for k = 1, 4 do
        local r = rs[k]
        if IsValid(r) then
            local p = r:GetPos()
            if p.x == p.x and p.y == p.y and p.z == p.z then ok = ok + 1 end
        end
    end
    log("roaches with a sane position after poisoning", ok, "of", #rs)
end)
-- Pods the way players meet them: walk up against one, and kick another.
local pods
step(0.5, function()
    pods = ents.FindByClass("gk_husk_pod")
    log("pods in the map", #pods)
    local a = pods[1]
    if not IsValid(a) then return end
    -- Stand just outside its box, touching distance, as walking into it leaves you.
    local side = Vector(a.GK_Maxs.x + 13, 0, 0)
    P:SetPos(a:GetPos() + side + Vector(0, 0, 2)) P:SetLocalVelocity(vector_origin)
end)
step(0.5, function() log("pod touched from outside: broken", tostring(pods[1] and pods[1]:GetBroken())) end)
-- Bunker bloodbugs: ambient ones topped up to gk_bunker_bugs, never hunting;
-- a broken pod sometimes lets an angry one out.
step(0.2, function()
    for _ = 1, 6 do GK.Birthing.BugTick() end
    local amb, angry = 0, 0
    for _, b in ipairs(ents.FindByClass("gk_bloodbug")) do
        if b.GK_Bunker then if b.GK_AggroUntil then angry = angry + 1 else amb = amb + 1 end end
    end
    local tgt = 0
    for _, b in ipairs(ents.FindByClass("gk_bloodbug")) do if b.GK_Bunker and not b.GK_AggroUntil and b:FindTarget() then tgt = tgt + 1 end end
    local vents, near = ents.FindByName("gk_bug_vent_*"), 0
    for _, b in ipairs(ents.FindByClass("gk_bloodbug")) do
        if b.GK_Bunker and not b.GK_AggroUntil then for _, v in ipairs(vents) do if b:GetPos():Distance(v:GetPos()) < 40 then near = near + 1 break end end end
    end
    log("map vents", #vents, "spots", #ents.FindByName("gk_bug_spot"), "ambient bugs that came out of a vent", near)
    log("bunker bugs: ambient", amb, "(expect 4)", "angry", angry, "ambient ones targeting someone", tgt, "(expect 0)")
    local made = 0
    for _ = 1, 40 do local n0 = #ents.FindByClass("gk_bloodbug") GK.Birthing.PodBug(P:GetPos() + Vector(0, 0, 60)) if #ents.FindByClass("gk_bloodbug") > n0 then made = made + 1 end end
    log("pod bugs from 40 broken pods", made, "(expect up to the cap of 7 in the room, about 25%)")
    local angryBug
    for _, b in ipairs(ents.FindByClass("gk_bloodbug")) do if b.GK_AggroUntil then angryBug = b break end end
    log("an angry pod bug targets", tostring(angryBug and angryBug:FindTarget()))
end)
step(0.2, function()
    local b = pods[2]
    if not IsValid(b) then return end
    P:SetPos(b:GetPos() + Vector(b.GK_Maxs.x + 50, 0, 2)) P:SetLocalVelocity(vector_origin)
    P:SetEyeAngles((b:WorldSpaceCenter() - P:GetShootPos() + Vector(0, 0, 30)):Angle())
    P.GK_NextKick = 0
    GK.Kick(P)
    log("pod kicked: broken", tostring(b:GetBroken()), "kick from", math.floor(P:GetPos():Distance(b:GetPos())))
end)
step(0.5, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_BirthTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_BirthTest")
    timer.Simple(12, function()
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
