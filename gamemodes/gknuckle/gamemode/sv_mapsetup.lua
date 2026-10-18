-- Sandbox maps (gm_construct, gm_flatgrass) get a gKnuckle starter area at
-- spawn: a vending machine against the nearest wall, and a playground of
-- props to drag/lift/throw, a frozen crate tower to climb, bricks, spikes and a
-- gravity surge, laid out down the most open direction from spawn.
-- Re-placed after every map cleanup. Turn off with gk_sandbox_setup 0.

local cvSetup = CreateConVar("gk_sandbox_setup", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Place the gKnuckle starter area on sandbox maps")

local SANDBOX_MAPS = { gm_construct = true, gm_flatgrass = true }

local DIRS = {}
for i = 0, 15 do
    local a = math.rad(i * 22.5)
    DIRS[#DIRS + 1] = Vector(math.cos(a), math.sin(a), 0)
end

local function floorAt(pos)
    local tr = util.TraceLine({ start = pos + Vector(0, 0, 64), endpos = pos - Vector(0, 0, 512), mask = MASK_SOLID_BRUSHONLY })
    return tr.Hit and tr.HitPos or pos
end

local function spawnProp(class, model, pos, ang, frozen)
    local ent = ents.Create(class)
    if not IsValid(ent) then return end
    if model then ent:SetModel(model) end
    ent:SetPos(pos)
    ent:SetAngles(ang or angle_zero)
    ent:Spawn()
    ent:Activate()
    ent.GK_Starter = true
    if frozen then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end
    return ent
end

-- Puts a model flush on the floor at pos (uses its bounds).
local function onFloor(model, pos)
    util.PrecacheModel(model)
    local mins = ents.Create("prop_physics")
    mins:SetModel(model)
    local lo = mins:OBBMins()
    mins:Remove()
    return floorAt(pos) - Vector(0, 0, lo.z)
end

function GK.SetupStarterArea()
    if not cvSetup:GetBool() or not SANDBOX_MAPS[game.GetMap()] then return end
    for _, ent in ipairs(ents.GetAll()) do
        if ent.GK_Starter then ent:Remove() end
    end

    local spawn = ents.FindByClass("info_player_start")[1]
    if not IsValid(spawn) then return end
    local origin = floorAt(spawn:GetPos()) + Vector(0, 0, 40)

    -- Measure every direction: nearest wall gets the vending machine, the most
    -- open direction gets the playground.
    local nearest, open
    for _, dir in ipairs(DIRS) do
        local tr = util.TraceLine({ start = origin, endpos = origin + dir * 2000, mask = MASK_SOLID_BRUSHONLY })
        local dist = tr.Fraction * 2000
        if tr.Hit and math.abs(tr.HitNormal.z) < 0.2 and dist > 96 and (not nearest or dist < nearest.dist) then
            nearest = { dist = dist, pos = tr.HitPos, normal = tr.HitNormal }
        end
        if not open or dist > open.dist then open = { dist = dist, dir = dir } end
    end

    -- White Knuckle vending machine: back against the nearest wall, or (open maps
    -- like gm_flatgrass) standing on its own a little way out, facing spawn.
    local vend = scripted_ents.GetStored("gk_vendor").t
    local wallPos, normal
    if nearest and nearest.dist < 900 then
        wallPos, normal = nearest.pos + nearest.normal * (vend.GKDepth + 2), nearest.normal
    elseif open then
        local side = open.dir:Angle():Right()
        wallPos, normal = origin + side * 220, -side
    end
    if wallPos then
        local pos = onFloor(vend.GKModel, wallPos)
        local vendor = spawnProp("gk_vendor", nil, pos, Angle(0, normal:Angle().y + vend.GKYawOffset, 0))
        if IsValid(vendor) then vendor.GK_WallNormal = normal GK.RadioOn(vendor) end
    end

    if not open then return end
    local fwd = open.dir
    local right = fwd:Angle():Right()
    local base = origin + fwd * math.min(260, open.dist * 0.3)
    local yaw = Angle(0, fwd:Angle().y, 0)

    -- Light: lift and throw.
    for i = -1, 1 do
        spawnProp("prop_physics", "models/props_c17/chair02a.mdl", onFloor("models/props_c17/chair02a.mdl", base + right * (i * 50)), yaw)
    end
    for i = 0, 3 do
        spawnProp("gk_brick", nil, floorAt(base + fwd * 60 + right * (-60 + i * 40)) + Vector(0, 0, 8))
    end
    spawnProp("prop_physics", "models/props_junk/watermelon01.mdl", floorAt(base + fwd * 60 + right * 110) + Vector(0, 0, 10))

    -- Heavy: drag (crates), and hang-able (big crate).
    local crate = "models/props_junk/wood_crate001a.mdl"
    local big = "models/props_junk/wood_crate002a.mdl"
    spawnProp("prop_physics", crate, onFloor(crate, base + fwd * 150 - right * 90), yaw)
    spawnProp("prop_physics", big, onFloor(big, base + fwd * 150 + right * 90), yaw)

    -- Climbing tower: frozen crates stacked with offsets so there are ledges.
    local towerBase = base + fwd * 300
    local z = onFloor(crate, towerBase).z
    for i = 0, 4 do
        local off = right * ((i % 2 == 0) and -16 or 16) + fwd * (i * 6)
        spawnProp("prop_physics", crate, Vector(towerBase.x, towerBase.y, z) + off + Vector(0, 0, i * 40), yaw, true)
    end

    -- Hazards and power-up.
    for i = -1, 1 do
        spawnProp("gk_spike", nil, floorAt(base + fwd * 430 + right * (i * 28)))
    end
    spawnProp("gk_surge", nil, floorAt(base + fwd * 300 + right * 120))

    -- A row of one of every item, to try out (click with an empty hand).
    local classes = {}
    for class in SortedPairs(GK.Items) do classes[#classes + 1] = class end
    for i, class in ipairs(classes) do
        local it = ents.Create("gk_item")
        it.GKItemClass = class
        it:SetPos(floorAt(base - fwd * 70 + right * ((i - (#classes + 1) / 2) * 26)) + Vector(0, 0, 10))
        it:Spawn()
        it.GK_Starter = true
    end
end

-- Portal's radio (gk_radio), sat on top of a vending machine, playing.
function GK.RadioOn(vendor)
    local r = ents.Create("gk_radio")
    if not IsValid(r) then return end
    r:SetAngles(vendor:LocalToWorldAngles(Angle(0, -15, 0)))
    r:Spawn()
    -- Standing on the machine's roof (its top is 118 u up), toward the front.
    r:SetPos(vendor:LocalToWorld(Vector(8, 6, 118.5 - r:OBBMins().z)))
    local phys = r:GetPhysicsObject()
    if IsValid(phys) then phys:Sleep() end
    return r
end

hook.Add("InitPostEntity", "GK_StarterArea", function() timer.Simple(1, GK.SetupStarterArea) end)
hook.Add("PostCleanupMap", "GK_StarterArea", function() timer.Simple(0, GK.SetupStarterArea) end)
concommand.Add("gk_setup_area", function(ply)
    if not GK.RequireAccess(ply, "gknuckle.runs") then return end
    GK.SetupStarterArea()
end)
