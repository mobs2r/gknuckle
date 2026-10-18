-- The birthing room's plumbing (hub, gk_style):
--
-- The tube: what the gas can't eat comes down the birthing tube and drops
-- into the pool every so often: bones, hunks of flesh, pitons, rebar...
-- Point: info_target "gk_drop_spawn", inside the tube above its bottom lip.
--
-- The flush: every 10 minutes, and whenever a match ends, the pool spins and
-- drains for a few seconds, then fills back up. Players in the pool get
-- swirled about (no harm); loose items and junk that reach the tub base
-- while it's drained are gone. Map side (build thread):
--   info_target "gk_pool_bed"     centre of the pool, on its bed
--   func_water_analog "gk_pool_water": Open drains it to the bed, Close refills
--   hub.json garden.bedZ           the bed's top (items at or below +8 are taken)
--   optional logic_relay "gk_flush_start" / "gk_flush_end" for sounds/effects
-- Without those entities, the timer just does the swirl and the clean-up.

GK.Birthing = GK.Birthing or {}
local B = GK.Birthing

local FLUSH_EVERY = CreateConVar("gk_flush_interval", "600", FCVAR_ARCHIVE, "Seconds between birthing-pool flushes (also after every match)")
local DROP_MIN, DROP_MAX = 25, 55        -- seconds between things falling out of the tube
local FLUSH_TIME = 6         -- seconds of spin; the water (44 u at 28 u/s) is down after ~1.6 s
local POOL_RADIUS = 400      -- the swirl and the clean-up reach this far from the pool centre
local hub = util.JSONToTable(file.Read("data_static/gknuckle/hub.json", "GAME") or "") or {}
local BED_Z = hub.garden and hub.garden.bedZ

-- What falls down the tube. Bones and flesh are junk (gk_trash, gone after a
-- while); pitons and rebar are real items you can take.
local JUNK = {
    "models/gibs/hgibs_spine.mdl", "models/gibs/hgibs_scapula.mdl", "models/gibs/hgibs_rib.mdl",
    "models/gibs/antlion_gib_small_1.mdl", "models/gibs/antlion_gib_small_2.mdl", "models/gibs/antlion_gib_medium_1.mdl",
}
local ITEMS = { "piton", "piton", "rebar", "brick", "bullet" }

local function named(name)
    for _, e in ipairs(ents.FindByName(name)) do return e end
end

function B.Drop()
    local at = named("gk_drop_spawn")
    if not IsValid(at) then return end
    local pos = at:GetPos() + VectorRand() * 8
    if math.random() < 0.65 then
        local j = ents.Create("gk_trash")
        if not IsValid(j) then return end
        j:SetModel(JUNK[math.random(#JUNK)])
        j:SetPos(pos)
        j.GK_Harmless = true -- falls into the pool, hurts nobody
        j.GK_Linger = 240    -- and lies there until the next flush (or this long)
        j:Spawn()
    else
        local class = ITEMS[math.random(#ITEMS)]
        if not GK.ItemDef(class) then return end
        local it = ents.Create("gk_item")
        if not IsValid(it) then return end
        it.GKItemClass = class
        it:SetPos(pos)
        it:Spawn()
        local phys = it:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(Vector(0, 0, -120) + VectorRand() * 30) end
        SafeRemoveEntityDelayed(it, 240) -- the next flush or this, whichever first
    end
    sound.Play("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", pos, 75, 80)
end

local function scheduleDrop()
    timer.Create("GK_TubeDrop", math.Rand(DROP_MIN, DROP_MAX), 1, function()
        B.Drop()
        scheduleDrop()
    end)
end

function B.Flush()
    if B.Flushing then return end
    local centre = named("gk_pool_bed")
    if not IsValid(centre) then return end
    B.Flushing = true
    local c = centre:GetPos()
    local water = named("gk_pool_water")
    if IsValid(water) then water:Fire("Open") end
    local relay = named("gk_flush_start")
    if IsValid(relay) then relay:Fire("Trigger") end
    sound.Play("ambient/water/water_flow_loop1.wav", c, 90, 70)
    local t0 = CurTime()
    timer.Create("GK_Flush", 0.05, 0, function()
        local t = CurTime() - t0
        -- The swirl: anyone in the pool is carried round the drain (no harm).
        for _, p in ipairs(player.GetAll()) do
            local d = p:GetPos() - c
            local flat = Vector(d.x, d.y, 0)
            if p:Alive() and flat:Length() < POOL_RADIUS and flat:Length() > 8 and d.z < 120 and d.z > -80 then
                local tangent = Vector(-flat.y, flat.x, 0):GetNormalized()
                local want = tangent * 220 - flat:GetNormalized() * 40
                local v = p:GetVelocity()
                p:SetVelocity(Vector(want.x - v.x, want.y - v.y, 0) * 0.3)
            end
        end
        -- Whatever loose junk reaches the tub base while it's drained is gone.
        -- Once the water is down (~1.6 s), loose things on the bed are gone. Never players.
        if t > 1.6 then
            local bed = (BED_Z or c.z) + 8
            for _, e in ipairs(ents.FindInSphere(c, POOL_RADIUS)) do
                if not e:IsPlayer() and (e.GKItemClass or e:GetClass() == "gk_trash") and e:GetPos().z <= bed + (e.GKItemClass and 0 or 56) then e:Remove() end -- junk floats at the old waterline
            end
        end
        if t > FLUSH_TIME then
            timer.Remove("GK_Flush")
            if IsValid(water) then water:Fire("Close") end
            local done = named("gk_flush_end")
            if IsValid(done) then done:Fire("Trigger") end
            B.Flushing = false
        end
    end)
    -- (No on-screen text: the map's gk_flush_start relay can drive the
    -- hypervisor screens and a V Corp tannoy line.)
end

local function scheduleFlush()
    timer.Create("GK_FlushCycle", math.max(60, FLUSH_EVERY:GetFloat()), 1, function()
        B.Flush()
        scheduleFlush()
    end)
end

hook.Add("InitPostEntity", "GK_Birthing", function()
    if game.GetMap() ~= "gk_style" then return end
    scheduleDrop()
    scheduleFlush()
end)
hook.Add("GK_ArenaEnd", "GK_BirthingFlush", function()
    timer.Simple(8, function() B.Flush() scheduleFlush() end)
end)

-- Bloodbugs in the bunker: a few always drifting about the pool (ambient:
-- they buzz, rest on the walls and die to a rebar like any other, but never
-- charge), and a chance one comes out of a pod you break, angry for a while.
local AMBIENT = CreateConVar("gk_bunker_bugs", "4", FCVAR_ARCHIVE, "Ambient bloodbugs kept in the birthing bunker (0 = none)")
local POD_BUG_CHANCE = 0.25 -- per broken pod
local POD_BUG_ANGRY = 20    -- seconds a pod-born bug hunts before it settles
local MAX_BUGS = 7          -- in the bunker at once, ambient and pod-born together
local BUNKER_R = 900        -- counts as "in the bunker" this close to the pool

local function poolCentre()
    local bed = ents.FindByName("gk_pool_bed")[1]
    if IsValid(bed) then return bed:GetPos() end
    local p = hub.garden and hub.garden.pool
    return p and Vector(p[1], p[2], p[3]) or nil
end
local function bunkerBugs(c)
    local n = 0
    for _, b in ipairs(ents.FindByClass("gk_bloodbug")) do
        if b.GK_Bunker and b:GetPos():Distance(c) < BUNKER_R * 1.5 then n = n + 1 end
    end
    return n
end
local function spawnBug(pos, angry)
    local b = ents.Create("gk_bloodbug")
    if not IsValid(b) then return end
    b:SetPos(pos)
    b:Spawn()
    b.GK_Bunker, b.GK_Ambient = true, true
    if angry then b.GK_AggroUntil = CurTime() + POD_BUG_ANGRY end
    return b
end
-- Where a bug comes in: out of one of the bunker's vents (info_target
-- gk_bug_vent_N, facing into the room) when the map has them, or over one of
-- its wander spots (gk_bug_spot, on the grass); else a free spot up off the
-- floor and under the ceiling (the 0.4 map has neither).
local function airSpot(c)
    local vents = ents.FindByName("gk_bug_vent_*")
    if #vents > 0 then
        local v = vents[math.random(#vents)]
        return v:GetPos() + v:GetForward() * 16
    end
    local spots = ents.FindByName("gk_bug_spot")
    if #spots > 0 then return spots[math.random(#spots)]:GetPos() + Vector(0, 0, math.Rand(90, 160)) end
    for _ = 1, 8 do
        local a = math.Rand(0, 360)
        local p = c + Angle(0, a, 0):Forward() * math.Rand(80, 380) + Vector(0, 0, 60)
        local up = util.TraceLine({ start = p, endpos = p + Vector(0, 0, 260), mask = MASK_SOLID })
        local z = math.min(p.z + math.Rand(60, 180), up.HitPos.z - 30)
        local spot = Vector(p.x, p.y, z)
        local fit = util.TraceHull({ start = spot, endpos = spot, mins = Vector(-10, -10, -10), maxs = Vector(10, 10, 10), mask = MASK_SOLID })
        if not fit.StartSolid and z > c.z + 40 then return spot end
    end
end

function B.PodBug(pos)
    local c = poolCentre()
    if not c or math.random() >= POD_BUG_CHANCE or bunkerBugs(c) >= MAX_BUGS then return end
    local b = spawnBug(pos, true)
    if IsValid(b) then b:EmitSound("gknuckle/creatures/bloodbug_warning.wav", 80, 110) end
end

function B.BugTick()
    if game.GetMap() ~= "gk_style" then return end
    local c = poolCentre()
    if not c then return end
    local want = math.min(AMBIENT:GetInt(), MAX_BUGS)
    local have = 0
    for _, b in ipairs(ents.FindByClass("gk_bloodbug")) do
        if b.GK_Bunker and not b.GK_AggroUntil and b:GetPos():Distance(c) < BUNKER_R * 1.5 then have = have + 1 end
    end
    if have < want and bunkerBugs(c) < MAX_BUGS then
        local spot = airSpot(c)
        if spot then spawnBug(spot, false) end
    end
end
timer.Create("GK_BunkerBugs", 20, 0, function() B.BugTick() end)
