-- Creatures in runs, placed where White Knuckle places them. Each room's
-- layout json carries WK's own creature placements (creatures[]), its roach
-- spawners (spawners[], table SPT_Roaches) and its flying-creature spawn
-- points (locators[] "creature-fly-spawn"), from the build thread's
-- tools/extract_hazards.js. As each room streams in, this spawns its share;
-- they go when the room goes. The start room stays safe.
--   Denizen_Barnacle_*, DEN_Myzont, Denizen_Screecher -> gk_barnacle (all DEN_Barnacle in WK)
--   Denizen_Turret_*    -> gk_turret
--   Denizen_Gasbag      -> gk_gasbag
--   Denizen_Bloodbug*   -> gk_bloodbug (plus some fly-spawn points, Silos/Pipeworks)
--   Denizen_SlugGrub*   -> a Slug Grub item lying there
--   Denizen_Roach_*     -> gk_roach
-- WK creatures not ported yet (Phage, the Mother, Vent Thing, striders...) are skipped.
-- gk_creatures 0 turns creatures off (rooms still get roaches).

local cvOn = CreateConVar("gk_creatures", "1", FCVAR_ARCHIVE, "Spawn WK creatures in runs")
-- Per-type switches (crash bisect): 0 skips that kind in runs.
local cvType = {
    gk_barnacle = CreateConVar("gk_spawn_barnacles", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_turret   = CreateConVar("gk_spawn_turrets", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_gasbag   = CreateConVar("gk_spawn_gasbags", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_bloodbug = CreateConVar("gk_spawn_bloodbugs", "1", FCVAR_NONE, "Test switch, not saved"),
    grub        = CreateConVar("gk_spawn_grubs", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_crate    = CreateConVar("gk_spawn_crates", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_ventthing = CreateConVar("gk_spawn_ventthings", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_hopper   = CreateConVar("gk_spawn_hoppers", "1", FCVAR_NONE, "Test switch, not saved"),
    gk_drone    = CreateConVar("gk_spawn_drones", "1", FCVAR_NONE, "Test switch, not saved"),
    wkn_strider = CreateConVar("gk_spawn_striders", "1", FCVAR_NONE, "Test switch, not saved"),
    wkn_giantroach = CreateConVar("gk_spawn_giantroaches", "1", FCVAR_NONE, "Test switch, not saved"),
}
local function allowed(kind) return not cvType[kind] or cvType[kind]:GetBool() end
-- Bloodbugs are WK's main "knock you off the wall" creature: common, not rare.
CreateConVar("gk_giantroach_chance", "0.35", FCVAR_ARCHIVE, "Chance a Nest room gets a giant roach on its floor")
local cvFly = CreateConVar("gk_bloodbug_chance", "0.3", FCVAR_NONE, "Chance a creature-fly-spawn point gets a bloodbug")

local ROACH_KIND = {
    Denizen_Roach = "brown", Denizen_Roach_Gold = "gold", Denizen_Roach_Platinum = "platinum",
    Denizen_Roach_Explosive = "boom",
}

local function classFor(id)
    -- WK's Myzont and Screecher run on the barnacle's own code (DEN_Barnacle).
    if id:find("^Denizen_Barnacle") or id:find("Myzont") or id:find("^Denizen_Screecher") then return "gk_barnacle" end
    if id:find("^Denizen_Turret") then return "gk_turret" end
    if id:find("^Denizen_Gasbag") then return "gk_gasbag" end
    if id:find("^Denizen_Bloodbug") then return "gk_bloodbug" end
    if id:find("^Denizen_VentThing") then return "gk_ventthing" end
    -- From the NPC pack's ports (lua/entities/wkn_*.lua): Pipeworks' gentle giants.
    if id:find("^Denizen_WasteStrider") then return "wkn_strider" end
end

-- What WK's spawner ids become (anything else isn't ported yet and is skipped).
local SPAWNER_CLASS = {
    Denizen_Bloodbug = "gk_bloodbug", Denizen_Bloodbug_Christmas = "gk_bloodbug",
    Denizen_Gasbag = "gk_gasbag", Denizen_Hopper = "gk_hopper",
    Denizen_Drone = "gk_drone", -- WK's sturge drones, in runs too, not just the training rooms
    HAZ_FallingTrash = "gk_trashchute",
}

local function weighted(t)
    local total = 0
    for _, w in pairs(t) do total = total + w end
    local r = math.Rand(0, total)
    for k, w in SortedPairs(t) do r = r - w if r <= 0 then return k end end
end

local function layoutOf(piece)
    return GK.LevelLayout(piece) -- cached and shared: read only
end

-- Drop a point onto whatever's below it (WK positions are a little above floors).
local function ground(p)
    local tr = util.TraceLine({ start = p + Vector(0, 0, 16), endpos = p - Vector(0, 0, 200), mask = MASK_SOLID })
    return tr.Hit and tr.HitPos or p
end

local function add(info, room, e)
    room.ents[#room.ents + 1] = e
    info.ents[#info.ents + 1] = e
end

local function spawnEnt(info, room, class, pos, yaw, n)
    if not scripted_ents.GetStored(class) or not allowed(class) then return end
    local e = ents.Create(class)
    if not IsValid(e) then return end
    e:SetPos(pos)
    e:SetAngles(Angle(0, yaw, 0))
    e:Spawn()
    add(info, room, e)
    if GetConVar("developer"):GetInt() > 0 then print(("[gKnuckle] creature %s spawned in room %s"):format(class, tostring(n or "?"))) end
    return e
end

hook.Add("GK_ArenaRoomSpawned", "GK_RoomCreatures", function(info, n)
    local room = info.rooms and info.rooms[n]
    local step = info.plan and info.plan[n]
    if not room or not step then return end
    timer.Simple(0.2, function()
        if not info.rooms[n] then return end
        local lay = layoutOf(step.piece)
        local origin = step.pos
        local function at(p) return origin + GK.LevelToModel(p) end
        local roaches = 0

        -- Roach spawners: min..max roaches scattered within range, by WK's weights.
        for _, s in ipairs(lay.spawners or {}) do
            if s.table == "SPT_Roaches" and math.random() <= (s.chance or 1) then
                for _ = 1, math.random(s.min or 1, math.max(s.min or 1, s.max or 1)) do
                    local id = weighted(s.spawns or { Denizen_Roach = 1 })
                    local off = VectorRand() * (s.range or 60) off.z = 0
                    local p = ground(at(s.pos) + off)
                    add(info, room, GK.SpawnRoach(ROACH_KIND[id] or "gold", p + Vector(0, 0, 2)))
                    roaches = roaches + 1
                end
            end
        end

        if cvOn:GetBool() and n > 1 then
            for _, c in ipairs(lay.creatures or {}) do
                local id = c.id or ""
                local pos, yaw = at(c.pos), (c.yaw or 0) + 90
                local class = classFor(id)
                if class == "gk_turret" then
                    spawnEnt(info, room, class, ground(pos) + Vector(0, 0, 2), yaw, n)
                elseif class then
                    spawnEnt(info, room, class, pos, yaw, n)
                elseif id:find("^Denizen_SlugGrub") and allowed("grub") then
                    local e = ents.Create("gk_item")
                    e.GKItemClass = "grub"
                    e.GK_Asleep = true -- no physics settling into new room collision
                    e:SetPos(pos + Vector(0, 0, 4)) e:Spawn()
                    add(info, room, e)
                elseif ROACH_KIND[id] then
                    add(info, room, GK.SpawnRoach(ROACH_KIND[id], ground(pos) + Vector(0, 0, 2)))
                    roaches = roaches + 1
                end
            end
            -- WK supply crates (breakable, an item or two inside) at some object spawn points.
            for _, l in ipairs(lay.locators or {}) do
                if l.id == "object-spawn" and allowed("gk_crate") and math.random() < 0.2 then
                    local e = ents.Create("gk_crate")
                    e.GK_Supply = true
                    e.GK_Frozen = true
                    e:SetPos(ground(at(l.pos)) + Vector(0, 0, 1)) e:SetAngles(Angle(0, (l.yaw or 0) + 90, 0))
                    e:Spawn()
                    add(info, room, e)
                end
            end
            -- Giant roaches: WK's room data never places one, so the Nest gets them,
            -- the region that's all roaches: some rooms have one on their floor.
            if (info.region or ""):find("Nest") and lay.floor and math.random() < GetConVar("gk_giantroach_chance"):GetFloat() then
                spawnEnt(info, room, "wkn_giantroach", ground(at(lay.floor)) + Vector(0, 0, 4), math.Rand(0, 360), n)
            end
            -- Bloodbugs come out of the flying-creature spawn points.
            local region = info.region or ""
            if region:find("Silos") or region:find("Pipeworks") or region:find("Habitation") then
                for _, l in ipairs(lay.locators or {}) do
                    if l.id == "creature-fly-spawn" and math.random() < cvFly:GetFloat() then
                        spawnEnt(info, room, "gk_bloodbug", at(l.pos), (l.yaw or 0) + 90, n)
                    end
                end
            end

            -- WK's creature spawners (Bloodbug_Spawner, Gasbag_Spawner,
            -- Hopper_Spawner): a chance roll, then min..max of them within range
            -- of the point, either when the room loads (onStart) or the first
            -- time a climber comes within "vicinity" of it.
            for si, sp in ipairs(lay.spawners or {}) do
                if sp.table ~= "SPT_Roaches" and math.random() <= (sp.chance or 1) then
                    local id = weighted(sp.spawns or {})
                    local class = id and SPAWNER_CLASS[id]
                    if class and allowed(class) then
                        local centre = at(sp.pos)
                        local function release()
                            for _ = 1, math.random(sp.min or 1, math.max(sp.min or 1, sp.max or 1)) do
                                local off = VectorRand() * (sp.range or 60) off.z = 0
                                local p = centre + off
                                if class == "gk_hopper" then p = ground(p) + Vector(0, 0, 2) end
                                spawnEnt(info, room, class, p, math.Rand(0, 360), n)
                            end
                        end
                        if sp.onStart then
                            release()
                        else
                            local reach = (sp.vicinity and sp.vicinity > 0) and sp.vicinity or ((sp.range or 60) + 300)
                            local name = ("GK_Spawner_%s_%d_%d"):format(tostring(info), n, si)
                            timer.Create(name, 0.5, 0, function()
                                if not info.rooms or info.rooms[n] ~= room then timer.Remove(name) return end
                                for _, p in ipairs(player.GetAll()) do
                                    if p:Alive() and p:GetPos():DistToSqr(centre) < reach * reach then
                                        timer.Remove(name)
                                        release()
                                        return
                                    end
                                end
                            end)
                        end
                    end
                end
            end
        end

        -- Rooms WK gave no roaches still get a couple.
        if roaches == 0 and room.bounds then
            local b = room.bounds
            for _ = 1, 40 do
                if roaches >= 2 then break end
                local p = Vector(math.Rand(b.mins.x, b.maxs.x), math.Rand(b.mins.y, b.maxs.y), math.Rand(b.mins.z, b.maxs.z))
                local tr = util.TraceLine({ start = p, endpos = p - Vector(0, 0, 400), mask = MASK_PLAYERSOLID })
                if util.PointContents(p) == CONTENTS_EMPTY and tr.Hit and not tr.StartSolid and tr.HitNormal.z > 0.7 then
                    add(info, room, GK.SpawnRoach(GK.RandomRoachKind(), tr.HitPos + Vector(0, 0, 2)))
                    roaches = roaches + 1
                end
            end
        end
    end)
end)

-- Admin: gk_spawn_creature <class> puts one where you're looking.
concommand.Add("gk_spawn_creature", function(ply, _, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local tr = ply:GetEyeTrace()
    local e = ents.Create(args[1] or "gk_bloodbug")
    if not IsValid(e) then return end
    e:SetPos(tr.HitPos + tr.HitNormal * 40)
    e:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    e:Spawn()
end)

-- The hub's training rooms (WK's Foundations pieces) keep their drone
-- spawners: when someone climbs near one, its drones come out to practise on;
-- once they're all down, it re-arms after a while.
local TRAIN_REARM = 45
local function armTrainingDrones()
    for _, piece in ipairs(ents.FindByClass("gk_level_piece")) do
        local name = piece.GetPiece and piece:GetPiece() or ""
        local lay = layoutOf(name)
        for si, sp in ipairs(lay.spawners or {}) do
            if (sp.spawns or {}).Denizen_Drone then
                local centre = piece:GetPos() + GK.LevelToModel(sp.pos)
                local reach = (sp.vicinity and sp.vicinity > 0) and sp.vicinity or 600
                local tname = ("GK_TrainDrone_%d_%d"):format(piece:EntIndex(), si)
                local out = {}
                timer.Create(tname, 1, 0, function()
                    if not IsValid(piece) then timer.Remove(tname) return end
                    for i = #out, 1, -1 do if not IsValid(out[i]) or out[i]:GetState() == 5 then table.remove(out, i) end end
                    if #out > 0 or CurTime() < (out.rearm or 0) then return end
                    for _, p in ipairs(player.GetAll()) do
                        if p:Alive() and GK.ArenaOf(p) == 0 and p:GetPos():DistToSqr(centre) < reach * reach then
                            for _ = 1, math.random(sp.min or 1, math.max(sp.min or 1, sp.max or 1)) do
                                local d = ents.Create("gk_drone")
                                local off = VectorRand() * (sp.range or 80) off.z = math.abs(off.z) * 0.3
                                d:SetPos(centre + off)
                                d:Spawn()
                                out[#out + 1] = d
                            end
                            out.rearm = CurTime() + TRAIN_REARM
                            return
                        end
                    end
                end)
            end
        end
    end
end
hook.Add("InitPostEntity", "GK_TrainingDrones", function() timer.Simple(5, armTrainingDrones) end)
