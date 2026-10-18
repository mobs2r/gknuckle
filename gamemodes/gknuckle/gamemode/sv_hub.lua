-- Hub (gk_style) free items. The map marks spots with info_targets:
--   gk_free_<item>   a shelf spot: that item, free, back a few seconds after
--                    someone takes it (e.g. gk_free_hammer, gk_free_piton)
--   gk_floor_piton   a piton lying loose on the floor; comes back after a while
-- Vending machines in the hub are free too (sv_shop.lua, gk_hub_free).
-- Items you carry are vaporized as you step into the vacuum (sv_arena.lua).

local ALIAS = { rope = "rebarrope", stungrenade = "stun", stun_grenade = "stun" } -- map spot names -> item classes

-- The physics yard's loose props: White Knuckle's own, back at their spot a
-- while after they're carried off (or wrecked).
local YARD = {
    "models/gknuckle/items/prop_chair.mdl", "models/gknuckle/items/prop_crate.mdl",
    "models/gknuckle/items/prop_barrel.mdl", "models/gknuckle/items/prop_officechair.mdl",
}
local function yardProp(t, mdl)
    if not IsValid(t) then return end
    -- Crates break, like WK's; the rest are plain physics props.
    local crate = mdl:find("crate", 1, true) ~= nil
    local p = ents.Create(crate and "gk_crate" or "prop_physics")
    if crate then p.GK_Model = mdl else p:SetModel(mdl) end
    p:SetPos(t:GetPos() + Vector(0, 0, 4)) p:SetAngles(t:GetAngles()) p:Spawn()
    p.GK_FromHubSpot = true
    local home = t:GetPos()
    timer.Create("GK_Yard" .. p:EntIndex(), 10, 0, function()
        if not IsValid(p) then return end
        if p:GetPos():DistToSqr(home) > 900 * 900 then p:Remove() end
    end)
    p:CallOnRemove("GK_YardBack", function() timer.Simple(20, function() yardProp(t, mdl) end) end)
end

local function setupHub()
    for _, e in ipairs(ents.FindByClass("gk_item_rack")) do
        if e.GK_FromHubSpot then e:Remove() end
    end
    local yard = 0
    for _, t in ipairs(ents.FindByClass("info_target")) do
        local name = t:GetName() or ""
        if name == "gk_prop_spot" then
            yard = yard + 1
            yardProp(t, YARD[(yard - 1) % #YARD + 1])
        elseif name == "gk_gambling_spot" then
            local m = ents.Create("gk_slots")
            m:SetPos(t:GetPos()) m:SetAngles(Angle(0, t:GetAngles().y, 0)) m:Spawn()
            m:DropToFloor()
        elseif name:match("^gk_pocket_vendor_%d+$") then
            -- A vending machine in each break room (paid in roaches like any run vendor).
            local v = ents.Create("gk_vendor")
            v:SetPos(t:GetPos()) v:SetAngles(Angle(0, t:GetAngles().y, 0)) v:Spawn()
            GK.RadioOn(v)
            -- And the perk console beside it (WK's interlude upgrade terminal).
            local yaw = Angle(0, t:GetAngles().y, 0)
            local c = ents.Create("gk_perk_console")
            c:SetPos(t:GetPos() + yaw:Right() * 80 + Vector(0, 0, 8)) c:SetAngles(yaw) c:Spawn()
            c:DropToFloor()
        end
        local item, respawn = name:match("^gk_free_(%w+)$"), 4
        item = item and (ALIAS[item] or item)
        if not item and name == "gk_floor_piton" then item, respawn = "piton", 20 end
        if name == "gk_easter_gravgun" then
            -- Behind the back pillar: the grav-gun strength pickup, coming back now and then.
            local function place()
                if not IsValid(t) then return end
                local s = ents.Create("gk_surge")
                if not IsValid(s) then return end
                s:SetPos(t:GetPos()) s:SetAngles(t:GetAngles()) s:Spawn()
                s.GK_FromHubSpot = true
                s:CallOnRemove("GK_EasterBack", function() timer.Simple(45, place) end)
            end
            place()
        end
        if item and GK.ItemDef(item) then
            local rack = ents.Create("gk_item_rack")
            rack:SetKeyValue("item", item)
            rack:SetKeyValue("respawn", tostring(respawn))
            rack:SetKeyValue("plinth", "0")
            rack:SetPos(t:GetPos())
            rack:SetAngles(t:GetAngles())
            rack:Spawn()
            rack.GK_FromHubSpot = true
        end
    end
end

hook.Add("InitPostEntity", "GK_HubSetup", function() timer.Simple(1, setupHub) end)
hook.Add("PostCleanupMap", "GK_HubSetup", function() timer.Simple(0, setupHub) end)

-- Gored for good, or knocked out of a run: you drop back into the hub through
-- the garden's respawn vacuum (gk_gored_spawn info_targets round the pool).
local function gardenSpots()
    local out = {}
    for _, t in ipairs(ents.FindByClass("info_target")) do
        if t:GetName() == "gk_gored_spawn" then out[#out + 1] = t end
    end
    return out
end

hook.Add("PlayerDeath", "GK_GardenRespawn", function(ply)
    ply.GK_ToGarden = GK.IsGored(ply) or GK.ArenaOf(ply) ~= 0
end)

hook.Add("PlayerSelectSpawn", "GK_GardenRespawn", function(ply)
    if not ply.GK_ToGarden then return end
    ply.GK_ToGarden = nil
    local spots = gardenSpots()
    if #spots == 0 then return end
    -- A free one if there is, else any.
    for _, i in RandomPairs(spots) do
        local blocked = false
        for _, e in ipairs(ents.FindInSphere(i:GetPos(), 40)) do if e:IsPlayer() and e:Alive() then blocked = true break end end
        if not blocked then return i end
    end
    return spots[math.random(#spots)]
end)

-- The garden's roaches: bankable gold and silver (platinum) ones kept topped
-- up on a rotation around the pool, plus every roach a run leaves behind
-- (dropped by the dead, never caught before the gas took the room) washing
-- up here when that region is cleared. Feed them into a vending machine's
-- roach hole to bank them.
GK.Garden = GK.Garden or {}
local GARDEN_KEEP, GARDEN_MAX = 16, 48

local function gardenCentre()
    local spots = gardenSpots()
    if #spots == 0 then return nil end
    local c = Vector()
    for _, s in ipairs(spots) do c:Add(s:GetPos()) end
    return c / #spots, spots
end

local function gardenRoaches()
    local c = gardenCentre()
    if not c then return {} end
    local out = {}
    for _, r in ipairs(ents.FindInSphere(c, 900)) do if r:GetClass() == "gk_roach" then out[#out + 1] = r end end
    return out
end

-- One roach somewhere in the garden, on the ground near a spawn spot.
function GK.Garden.Spawn(kind)
    local c, spots = gardenCentre()
    if not c or #gardenRoaches() >= GARDEN_MAX then return end
    local base = spots[math.random(#spots)]:GetPos()
    local s = base + Vector(math.Rand(-160, 160), math.Rand(-160, 160), 40)
    local tr = util.TraceLine({ start = s, endpos = s - Vector(0, 0, 300), mask = MASK_PLAYERSOLID })
    -- Same floor as the spawn spot (the garden is raised: never off its edge).
    if tr.Hit and not tr.StartSolid and math.abs(tr.HitPos.z - base.z) < 48 then return GK.SpawnRoach(kind or "gold", tr.HitPos + Vector(0, 0, 2)) end
end

-- The rotation: every 20 s, a couple more until there are GARDEN_KEEP.
timer.Create("GK_GardenRoaches", 20, 0, function()
    local have = #gardenRoaches()
    for _ = 1, math.min(2, GARDEN_KEEP - have) do
        GK.Garden.Spawn(math.random() < 0.8 and "gold" or "platinum")
    end
end)

-- Roaches left in a run's region come back to the garden when it's cleared.
function GK.Garden.Harvest(bounds)
    if not bounds or not bounds.mins then return 0 end
    local n = 0
    for _, r in ipairs(ents.FindInBox(bounds.mins - Vector(256, 256, 256), bounds.maxs + Vector(256, 256, 256))) do
        if r:GetClass() == "gk_roach" and not r.GK_Taken and not r.GK_Dead then
            local kind = r:GetKind()
            if kind == "gold" or kind == "platinum" then
                n = n + 1
                timer.Simple(0.1 * n, function() GK.Garden.Spawn(kind) end)
            end
        end
    end
    return n
end
hook.Add("GK_ArenaEnd", "GK_GardenHarvest", function(a)
    -- The run is cleared 4 s after it ends (sv_arena.lua): collect just before.
    local bounds = a.info and a.info.bounds
    timer.Simple(3.8, function() GK.Garden.Harvest(bounds) end)
end)
hook.Add("GK_ArenaBreak", "GK_GardenHarvest", function(a)
    -- The next region replaces this one: what's left of it goes to the garden.
    GK.Garden.Harvest(a.info and a.info.bounds)
end)
