-- Roaches (gk_roach): the currency you catch. Gold and platinum go straight
-- into your roach count; xenium is a heavy glowing lump that sits in your bag
-- (and slows you down) until you spend it; the red boom bug just blows up.
-- Values are White Knuckle's (gold 1, platinum 5); xenium is gKnuckle's own.
--
-- For vending machines and anything else that takes roaches:
--   GK.Roaches.Balance(ply)      total worth carried (count + xenium lumps)
--   GK.Roaches.Spend(ply, n)     takes n if they have it (breaking into a
--                                xenium lump if needed), returns true/false
--   GK.Roaches.Add(ply, n)
-- Your roaches are dropped where you die, for anyone to grab.

-- speed/run in u/s, from WK's prefabs (0.3 m/s wander, 2 m/s flee; the
-- explosive wanders at 1.3 m/s and dies 0-0.2 s after it's hit).
GK.RoachKinds = {
    brown    = { worth = 0,  speed = 12, run = 79, model = "models/gknuckle/items/roach_brown.mdl", weight = 12, smush = true },
    gold     = { worth = 1,  speed = 12, run = 79, model = "models/gknuckle/items/roach_gold.mdl", weight = 6 },
    platinum = { worth = 5,  speed = 12, run = 79, model = "models/gknuckle/items/roach_platinum.mdl", weight = 2 },
    boom     = { worth = 0,  speed = 51, run = 79, model = "models/gknuckle/items/roach_boom.mdl", boom = true, weight = 1.5,
                 deathTime = 0.2, glow = Color(255, 50, 40), glowSoft = true }, -- a soft red bloom
    -- The platinum roach's shell recoloured orange, with the same soft bloom in orange.
    xenium   = { worth = 25, speed = 8,  run = 40, model = "models/gknuckle/items/roach_platinum.mdl", scale = 1.6, lump = true,
                 tint = Color(255, 150, 60), glow = Color(255, 140, 40), glowSoft = true, weight = 0.4 },
}
GK.XeniumWorth = GK.RoachKinds.xenium.worth
GK.XeniumSlow = 0.82 -- run speed multiplier per lump you carry

GK.Roaches = GK.Roaches or {}
-- The vending machine's dial reads three digits: carried and banked roaches
-- each top out at 999 (a full count shows red on the vendor's bar).
GK.RoachCap = 999

function GK.Roaches.Count(ply) return ply:GetNW2Int("gk_roaches", 0) end
function GK.Roaches.Lumps(ply) return ply:GetNW2Int("gk_xenium", 0) end
-- Banked roaches (fed into a vending machine's bank slot in the hub): safe
-- from death drops, spent after the ones you carry.
function GK.Roaches.Banked(ply) return ply:GetNW2Int("gk_bank", 0) end
-- Live roaches held in your hands or pockets (WK: you catch them by hand).
function GK.Roaches.Held(ply) return ply:GetNW2Int("gk_roach_held", 0) end
function GK.Roaches.Balance(ply) return GK.Roaches.Count(ply) + GK.Roaches.Held(ply) + GK.Roaches.Lumps(ply) * GK.XeniumWorth + GK.Roaches.Banked(ply) end

-- A caught roach, wriggling in your hand (WK's Item_Hands_Roach_*): pocket it
-- (Q/E) or put it in your bag, where it joins your roach count; let go of it
-- (drop it, die) and it scurries off. Feed it into a vending machine's hole
-- to bank it.
GK.RegisterItem("roach", {
    name = "Roach", model = "models/gknuckle/items/roach_gold.mdl", weight = 0,
    roachKind = "gold", roachWorth = 1,
    pickupSound = "gknuckle/roach/pickup_cockroach1.wav",
})
GK.RegisterItem("roach_platinum", {
    name = "Platinum Roach", model = "models/gknuckle/items/roach_platinum.mdl", weight = 0,
    roachKind = "platinum", roachWorth = 5,
    pickupSound = "gknuckle/roach/pickup_cockroach2.wav",
})

-- Clicking with a roach in hand: if you're pointing at a vending machine's
-- roach hole (the one under the gold roach), it goes in and is banked.
local function feedHeld(ply, side, item)
    if CLIENT then return false end
    local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 120, filter = ply })
    local v = tr.Entity
    if not IsValid(v) or not v.FeedRoach or not v.AtRoachSlot then return false end
    if not v:AtRoachSlot(v:WorldToLocal(tr.HitPos)) then return false end
    local def = GK.ItemDef(item.class)
    return v:FeedRoach(ply, def and def.roachWorth or 1)
end
for _, class in ipairs({ "roach", "roach_platinum" }) do
    local def = GK.ItemDef(class)
    if def then def.Use = feedHeld end
end

-- A xenium lump is a bag item: heavy, does nothing in your hand.
GK.RegisterItem("xenium", {
    name = "Xenium Roach", model = "models/gknuckle/items/roach_platinum.mdl", weight = 6,
    roachKind = "xenium", -- let go of, it crawls off again (not roachWorth: it's not counted until spent)
    hold = { scale = 1.6 },
    pickupSound = "gknuckle/items/roach_lemon_eat.wav",
})

if SERVER then
    function GK.Roaches.Add(ply, n)
        ply:SetNW2Int("gk_roaches", math.Clamp(GK.Roaches.Count(ply) + n, 0, GK.RoachCap))
    end

    local function lumpItems(ply)
        local inv, out = GK.Inv.Get(ply), {}
        for i, it in ipairs(inv.bag) do if it.class == "xenium" then out[#out + 1] = { where = "bag", i = i } end end
        for slot, it in pairs(inv.slots) do if it.class == "xenium" then out[#out + 1] = { where = slot } end end
        return out
    end

    -- Pay from what's been fed into the machines (the bank) only.
    function GK.Roaches.SpendBank(ply, n)
        if GK.Roaches.Banked(ply) < n then return false end
        ply:SetNW2Int("gk_bank", GK.Roaches.Banked(ply) - n)
        return true
    end

    -- Feed every carried roach into the bank.
    function GK.Roaches.Bank(ply)
        GK.Roaches.Absorb(ply)
        local n = math.min(GK.Roaches.Count(ply), GK.RoachCap - GK.Roaches.Banked(ply))
        if n <= 0 then return 0 end
        ply:SetNW2Int("gk_roaches", GK.Roaches.Count(ply) - n)
        ply:SetNW2Int("gk_bank", GK.Roaches.Banked(ply) + n)
        hook.Run("GK_RoachesBanked", ply, n) -- the run score (sh_score.lua)
        return n
    end

    -- Roaches in hands and pockets go into the count (paying, banking).
    function GK.Roaches.Absorb(ply)
        local inv = GK.Inv.Get(ply)
        local n = 0
        for slot, it in pairs(inv.slots) do
            local def = GK.ItemDef(it.class)
            if def and def.roachWorth then n = n + def.roachWorth inv.slots[slot] = nil end
        end
        if n > 0 then
            ply:SetNW2Int("gk_roaches", math.Clamp(GK.Roaches.Count(ply) + n, 0, GK.RoachCap))
            GK.Inv.Sync(ply)
        end
        return n
    end

    function GK.Roaches.Spend(ply, n)
        if GK.Roaches.Balance(ply) < n then return false end
        GK.Roaches.Absorb(ply)
        -- Carried roaches and lumps first, the bank last.
        local carried = GK.Roaches.Count(ply) + GK.Roaches.Lumps(ply) * GK.XeniumWorth
        if carried < n then
            local fromBank = n - carried
            ply:SetNW2Int("gk_bank", GK.Roaches.Banked(ply) - fromBank)
            GK.Roaches.Add(ply, fromBank)
        end
        -- Break lumps into roaches until the count covers it.
        while GK.Roaches.Count(ply) < n do
            local inv = GK.Inv.Get(ply)
            local l = lumpItems(ply)[1]
            if not l then return false end
            if l.where == "bag" then table.remove(inv.bag, l.i) else inv.slots[l.where] = nil end
            GK.Roaches.Add(ply, GK.XeniumWorth)
            GK.Inv.Sync(ply)
        end
        GK.Roaches.Add(ply, -n)
        return true
    end

    function GK.Roaches.Collect(ply, kind, side)
        local k = GK.RoachKinds[kind]
        if not k then return end
        if k.lump then
            GK.Inv.Give(ply, "xenium") -- into the bag, or at your feet if it won't fit
        elseif k.worth > 0 and side ~= false then
            -- WK: you catch it in your hand. A free hand is needed (and room under the cap).
            if GK.Roaches.Count(ply) + GK.Roaches.Held(ply) >= GK.RoachCap then return false end
            local inv = GK.Inv.Get(ply)
            local hand
            for _, s in ipairs(side and { side } or { "r", "l" }) do
                if not inv.slots["hand_" .. s] then hand = "hand_" .. s break end
            end
            if not hand then return false end
            local class = kind == "platinum" and "roach_platinum" or "roach"
            inv.slots[hand] = { id = (inv.nextId or 1), class = class, data = {} }
            inv.nextId = (inv.nextId or 1) + 1
            GK.Inv.Sync(ply)
            return true
        else
            if k.worth > 0 and GK.Roaches.Count(ply) >= GK.RoachCap then return false end -- full: leave it
            GK.Roaches.Add(ply, k.worth)
        end
        return true
    end

    function GK.SpawnRoach(kind, pos)
        local r = ents.Create("gk_roach")
        r.GK_Kind = kind
        r:SetPos(pos)
        r:Spawn()
        return r
    end

    -- Random kind by weight.
    function GK.RandomRoachKind(exclude)
        local total = 0
        for name, k in pairs(GK.RoachKinds) do if not (exclude and exclude[name]) then total = total + k.weight end end
        local r = math.Rand(0, total)
        for name, k in SortedPairs(GK.RoachKinds) do
            if not (exclude and exclude[name]) then
                r = r - k.weight
                if r <= 0 then return name end
            end
        end
        return "gold"
    end

    -- Dying drops what you carried: platinum for every 5, gold for the rest.
    hook.Add("DoPlayerDeath", "GK_DropRoaches", function(ply)
        local n = GK.Roaches.Count(ply)
        ply:SetNW2Int("gk_roaches", 0)
        local plat, gold = math.floor(n / 5), n % 5
        local pos = ply:GetPos() + Vector(0, 0, 4)
        for i = 1, math.min(plat, 12) do GK.SpawnRoach("platinum", pos + VectorRand() * 12 * Vector(1, 1, 0)) end
        for i = 1, gold do GK.SpawnRoach("gold", pos + VectorRand() * 12 * Vector(1, 1, 0)) end
    end)

    -- Keeps a few roaches alive around marked spots (hub: info_target
    -- "gk_roach_spot"); on sandbox maps, around the starter area.
    local spots, nextFill = {}, 0
    local function findSpots()
        spots = {}
        for _, t in ipairs(ents.FindByClass("info_target")) do
            if t:GetName() == "gk_roach_spot" then spots[#spots + 1] = t:GetPos() end
        end
        if #spots == 0 and (game.GetMap() == "gm_construct" or game.GetMap() == "gm_flatgrass") then
            local s = ents.FindByClass("info_player_start")[1]
            if IsValid(s) then
                for i = 1, 4 do spots[#spots + 1] = s:GetPos() + Angle(0, i * 90, 0):Forward() * 220 end
            end
        end
    end
    hook.Add("InitPostEntity", "GK_RoachSpots", function() timer.Simple(2, findSpots) end)
    hook.Add("PostCleanupMap", "GK_RoachSpots", function() timer.Simple(1, findSpots) end)

    local PER_SPOT = 3
    timer.Create("GK_RoachFill", 4, 0, function()
        if #spots == 0 then return end
        local near = {}
        for _, r in ipairs(ents.FindByClass("gk_roach")) do
            if r.GK_Spot then near[r.GK_Spot] = (near[r.GK_Spot] or 0) + 1 end
        end
        for i, p in ipairs(spots) do
            if (near[i] or 0) < PER_SPOT then
                local tr = util.TraceLine({ start = p + VectorRand() * 60 * Vector(1, 1, 0) + Vector(0, 0, 32), endpos = p - Vector(0, 0, 200), mask = MASK_PLAYERSOLID })
                if tr.Hit then
                    local r = GK.SpawnRoach(GK.RandomRoachKind(), tr.HitPos)
                    r.GK_Spot = i
                end
            end
        end
    end)

    -- Runs: each room brings its own roaches as it streams in (WK's spawners, sv_creatures.lua).
end
