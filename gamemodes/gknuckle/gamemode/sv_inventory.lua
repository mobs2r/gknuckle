-- Server-side White Knuckle inventory: a bag (free-placed items, weight
-- limited), two hands and two pockets. The client UI only asks for moves;
-- every move is validated here.

util.AddNetworkString("gk_inv")
util.AddNetworkString("gk_inv_move")

GK.Inv = GK.Inv or {}
local Inv = GK.Inv

local BAG_WEIGHT = 13 -- WK: items carried free before you slow down
local SLOTS = { hand_l = true, hand_r = true, pocket_l = true, pocket_r = true }

function Inv.Get(ply)
    if not ply.GK_Inv then
        ply.GK_Inv = { bag = {}, slots = {}, nextId = 1 }
    end
    return ply.GK_Inv
end

function Inv.HandItem(ply, side)
    return Inv.Get(ply).slots["hand_" .. side]
end

-- How much the bag carries before it slows you (Back Strengtheners raises it).
function Inv.Capacity(ply) return math.floor(BAG_WEIGHT * GK.BuffMult(ply, "capacity")) end

-- WK counts things, not weight: every item in the bag is one, except a
-- xenium lump, which is gKnuckle's own heavy load.
function Inv.Weight(ply)
    local w = 0
    for _, item in ipairs(Inv.Get(ply).bag) do
        w = w + (item.class == "xenium" and (GK.ItemDef(item.class).weight or 6) or 1)
    end
    return w
end

function Inv.Sync(ply)
    local inv = Inv.Get(ply)
    net.Start("gk_inv")
    net.WriteTable({ bag = inv.bag, slots = inv.slots, maxWeight = Inv.Capacity(ply) })
    net.Send(ply)
    -- WK encumbrance (sh_movement.lua slows you by it).
    local over = Inv.Weight(ply) - Inv.Capacity(ply)
    ply:SetNW2Float("gk_encumber", math.Clamp(1 - over / 10, 0.1, 1))
    -- Xenium lumps carried (they slow you down; sh_movement.lua predicts it).
    local lumps = 0
    for _, it in ipairs(inv.bag) do if it.class == "xenium" then lumps = lumps + 1 end end
    for _, it in pairs(inv.slots) do if it.class == "xenium" then lumps = lumps + 1 end end
    ply:SetNW2Int("gk_xenium", lumps)
    -- Live roaches in hands and pockets (part of your balance).
    local held = 0
    for _, it in pairs(inv.slots) do
        local def = GK.ItemDef(it.class)
        if def and def.roachWorth then held = held + def.roachWorth end
    end
    ply:SetNW2Int("gk_roach_held", held)
    -- A flashlight in a pocket still shines (WK), from your chest.
    local pocketLight = false
    for slot, it in pairs(inv.slots) do if it.class == "flashlight" and slot:find("^pocket") then pocketLight = true end end
    ply:SetNW2Bool("gk_flash_pocket", pocketLight)
    -- Everyone else just needs to know what's in each hand to draw it.
    for _, side in ipairs({ "l", "r" }) do
        local item = inv.slots["hand_" .. side]
        ply:SetNW2String("gk_hitem_" .. side, item and item.class or "")
    end
end

local function newItem(ply, class, data)
    local inv = Inv.Get(ply)
    local def = GK.ItemDef(class)
    local item = {
        id = inv.nextId, class = class,
        data = data or (def.newData and def.newData() or {}),
        x = math.Rand(0.15, 0.85), y = math.Rand(0.2, 0.8),
    }
    inv.nextId = inv.nextId + 1
    return item
end

-- Where is item `id`? Returns the item, and either ("bag", index) or (slotName).
local function find(inv, id)
    for i, item in ipairs(inv.bag) do
        if item.id == id then return item, "bag", i end
    end
    for slot, item in pairs(inv.slots) do
        if item.id == id then return item, slot end
    end
end

local function take(inv, where, index)
    if where == "bag" then return table.remove(inv.bag, index) end
    local item = inv.slots[where]
    inv.slots[where] = nil
    return item
end

-- Puts a world item entity for `item` in front of the player.
function Inv.DropToWorld(ply, item, vel)
    local def = GK.ItemDef(item.class)
    -- A roach let go of is a live roach again, and it runs.
    if def and def.roachKind and GK.SpawnRoach then
        local r = GK.SpawnRoach(def.roachKind, ply:GetPos() + ply:GetAimVector() * 24 + Vector(0, 0, 4))
        if IsValid(r) then r.GK_NoGrabUntil = CurTime() + 0.5 end
        return r
    end
    local ent = ents.Create(def.worldClass or "gk_item")
    if not IsValid(ent) then return end
    ent:SetPos(ply:GetShootPos() + ply:GetAimVector() * 30)
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent.GKItemClass = item.class
    ent.GKItemData = item.data
    if ent.SetItemClass then ent:SetItemClass(item.class) end
    ent:Spawn()
    ent:Activate()
    local phys = ent:GetPhysicsObject()
    -- WK: dropped things carry your speed plus 2 m/s along your view, and
    -- can't be grabbed again for 0.15 s (no instant re-grab spam).
    if IsValid(phys) then phys:SetVelocity(vel or (ply:GetAimVector() * 79 + ply:GetVelocity())) end
    ent.GK_NoPickupUntil = CurTime() + 0.15
    return ent
end

-- New item for this player: into the bag, or at their feet if it's too heavy.
function Inv.Give(ply, class, data)
    if not GK.ItemDef(class) then return end
    local inv = Inv.Get(ply)
    local item = newItem(ply, class, data)
    local def = GK.ItemDef(class)
    -- Stackables merge into an existing stack first.
    if def.stack then
        local all = {}
        for _, it in ipairs(inv.bag) do all[#all + 1] = it end
        for _, it in pairs(inv.slots) do all[#all + 1] = it end
        for _, other in ipairs(all) do
            if other.class == class and other.data.count < def.stack then
                local add = math.min(def.stack - other.data.count, item.data.count)
                other.data.count = other.data.count + add
                item.data.count = item.data.count - add
                if item.data.count <= 0 then Inv.Sync(ply) return end
            end
        end
    end
    -- WK's bag never refuses: carrying more only slows you down.
    table.insert(inv.bag, item)
    Inv.Sync(ply)
end

-- Validated move from the UI (or keys). target: "bag", a slot name, or "world".
function Inv.Move(ply, id, target, x, y)
    local inv = Inv.Get(ply)
    local item, where, index = find(inv, id)
    if not item then return end

    if target == "bag" then
        take(inv, where, index)
        local def = GK.ItemDef(item.class)
        if def and def.roachWorth then
            -- Into the bag: it joins your roach count (shown there as roach icons).
            ply:SetNW2Int("gk_roaches", math.Clamp(GK.Roaches.Count(ply) + def.roachWorth, 0, GK.RoachCap))
            Inv.Sync(ply)
            return
        end
        item.x, item.y = math.Clamp(x or 0.5, 0.05, 0.95), math.Clamp(y or 0.5, 0.05, 0.95)
        table.insert(inv.bag, item)
    elseif target == "world" then
        take(inv, where, index)
        Inv.DropToWorld(ply, item)
    elseif SLOTS[target] then
        if where == target then return end
        take(inv, where, index)
        local occupant = inv.slots[target]
        inv.slots[target] = item
        if occupant then -- swap back to where the dragged item came from
            if where == "bag" then
                occupant.x, occupant.y = item.x, item.y
                table.insert(inv.bag, occupant)
            else
                inv.slots[where] = occupant
            end
        end
        if target:sub(1, 4) == "hand" then
            local wep = ply:GetActiveWeapon()
            if IsValid(wep) and wep.Release then wep:Release(target:sub(-1), true) end
        end
    end
    Inv.Sync(ply)
end

-- Q / E: pocket the item in that hand, take it back out, or swap the two.
function Inv.Pocket(ply, side)
    local inv = Inv.Get(ply)
    local hand, pocket = "hand_" .. side, "pocket_" .. side
    -- WK: rebar is too long for a pocket.
    local h = inv.slots[hand]
    if h and string.find(h.class, "^rebar") then ply:EmitSound("GK.VendDeny") return end
    inv.slots[hand], inv.slots[pocket] = inv.slots[pocket], inv.slots[hand]
    local wep = ply:GetActiveWeapon()
    if inv.slots[hand] and IsValid(wep) and wep.Release then wep:Release(side, true) end
    ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 3) .. ".wav", 55, 140)
    Inv.Sync(ply)
end

function Inv.HasPocketable(ply, side)
    local inv = Inv.Get(ply)
    return inv.slots["hand_" .. side] ~= nil or inv.slots["pocket_" .. side] ~= nil
end

-- Mouse button on a hand holding an item.
function Inv.Use(ply, side)
    if ply:GetNW2Float("gk_busy_until", 0) > CurTime() then return end
    local inv = Inv.Get(ply)
    local item = inv.slots["hand_" .. side]
    if not item then return end
    local def = GK.ItemDef(item.class)
    if def.Use and def.Use(ply, side, item) then
        inv.slots["hand_" .. side] = nil
        Inv.Sync(ply)
    end
end

-- R: reload whichever held item can (right hand first). Needs both hands.
function Inv.Reload(ply)
    if ply:GetNW2Float("gk_busy_until", 0) > CurTime() then return end
    for _, side in ipairs({ "r", "l" }) do
        local item = Inv.HandItem(ply, side)
        local def = item and GK.ItemDef(item.class)
        if def and def.Reload then
            def.Reload(ply, side, item)
            return
        end
    end
end

-- Clicking a world item with an empty hand picks it up into that hand.
function Inv.PickupToHand(ply, ent, side)
    local class = ent.GKItemClass
    if not class or not GK.ItemDef(class) then return false end
    if (ent.GK_NoPickupUntil or 0) > CurTime() then return false end
    local inv = Inv.Get(ply)
    if inv.slots["hand_" .. side] then return false end
    local item = newItem(ply, class, ent.GKItemData)
    inv.slots["hand_" .. side] = item
    ent:Remove()
    ply:EmitSound(GK.ItemDef(class).pickupSound or "items/ammo_pickup.wav", 60, 120)
    Inv.Sync(ply)
    return true
end

-- G: drop what's in a hand (right first).
-- Knocked out of your hands (WK: a bloodbug charge or a turret round): both
-- held items fly off, away from where the hit came from.
function Inv.KnockFromHands(ply, from)
    local inv = Inv.Get(ply)
    local away = from and (ply:WorldSpaceCenter() - from):GetNormalized() or ply:GetAimVector()
    local any = false
    for _, side in ipairs({ "l", "r" }) do
        local item = inv.slots["hand_" .. side]
        if item then
            inv.slots["hand_" .. side] = nil
            Inv.DropToWorld(ply, item, (away + VectorRand() * 0.4 + Vector(0, 0, 0.6)):GetNormalized() * 220)
            any = true
        end
    end
    if any then ply:SetNW2Float("gk_busy_until", 0) Inv.Sync(ply) end
    return any
end

-- Drops what one hand holds (side "l"/"r"), or the first full hand if no side.
function Inv.DropHand(ply, only)
    local inv = Inv.Get(ply)
    for _, side in ipairs(only and { only } or { "r", "l" }) do
        local item = inv.slots["hand_" .. side]
        if item then
            inv.slots["hand_" .. side] = nil
            Inv.DropToWorld(ply, item)
            ply:SetNW2Float("gk_busy_until", 0)
            Inv.Sync(ply)
            return
        end
    end
end

net.Receive("gk_inv_move", function(_, ply)
    if not IsValid(ply) or not ply:Alive() then return end
    -- Each move answers with a full inventory sync: cap how often a client can ask.
    local now = CurTime()
    if (ply.GK_InvMoveWindow or 0) < now then ply.GK_InvMoveWindow, ply.GK_InvMoves = now + 1, 0 end
    ply.GK_InvMoves = (ply.GK_InvMoves or 0) + 1
    if ply.GK_InvMoves > 30 then return end
    local id = net.ReadUInt(16)
    local target = net.ReadString()
    local x, y = net.ReadFloat(), net.ReadFloat()
    if target ~= "bag" and target ~= "world" and not SLOTS[target] then return end
    -- NaN / inf would slip through math.Clamp and end up in the synced bag layout.
    if x ~= x or x == math.huge or x == -math.huge then x = 0.5 end
    if y ~= y or y == math.huge or y == -math.huge then y = 0.5 end
    Inv.Move(ply, id, target, x, y)
end)

-- Death: whatever was in your hands and pockets falls; the bag is lost.
hook.Add("DoPlayerDeath", "GK_InventoryDeath", function(ply)
    local inv = Inv.Get(ply)
    for slot, item in pairs(inv.slots) do
        Inv.DropToWorld(ply, item, VectorRand() * 80 + Vector(0, 0, 80))
    end
    ply.GK_Inv = nil
end)

hook.Add("PlayerSpawn", "GK_InventoryStart", function(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        local inv = Inv.Get(ply)
        if not inv.started then
            inv.started = true
            Inv.Give(ply, "rebar")
        end
        Inv.Sync(ply)
    end)
end)

-- X swaps what's in your two hands (WK has a swap).
function Inv.SwapHands(ply)
    local inv = Inv.Get(ply)
    inv.slots.hand_l, inv.slots.hand_r = inv.slots.hand_r, inv.slots.hand_l
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.Release then wep:Release("l", true) wep:Release("r", true) end
    ply:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 3) .. ".wav", 55, 120)
    Inv.Sync(ply)
end
