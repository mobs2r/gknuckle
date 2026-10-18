-- CrabCoin shop. Normally you buy at a vending machine (gk_vendor), which
-- drops the item into its tray; `gk_buy <item>` puts it straight in your bag.
-- Items are only handed out after the omerta debit succeeds. With the economy
-- unconfigured, everything is free so courses can be tested locally.

GK.Shop = {}

function GK.Shop.Slot(name)
    for _, slot in ipairs(GK.ShopSlots) do
        if slot.name == name then return slot end
    end
end

-- Spawns the bought thing in the world as a physics object.
function GK.Shop.SpawnItem(slot, pos, ang)
    local ent
    if slot.entity then
        ent = ents.Create(slot.entity)
    else
        local def = GK.ItemDef(slot.item)
        ent = ents.Create(def.worldClass or "gk_item")
        ent.GKItemClass = slot.item
        ent.GKItemData = slot.data and table.Copy(slot.data) or (def.newData and def.newData()) or {}
        if ent.SetItemClass then ent:SetItemClass(slot.item) end
    end
    if not IsValid(ent) then return end
    ent:SetPos(pos)
    ent:SetAngles(ang or angle_zero)
    ent:Spawn()
    ent:Activate()
    return ent
end

-- Vending machines take roaches, like White Knuckle: the price is in roaches,
-- paid from what you've caught (sh_roaches.lua; xenium lumps are broken into
-- change). gk_vend_free 1 makes vending free outside a run (off by default:
-- the hub has its free racks instead). (Replaces the old gk_hub_free, whose
-- archived value of 1 would otherwise keep machines free on existing setups.)
local cvHubFree = CreateConVar("gk_vend_free", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Vending machines are free outside a run")

-- Charge the player, then call done(ok).
function GK.Shop.Charge(ply, slot, done)
    if cvHubFree:GetBool() and GK.ArenaOf(ply) == 0 then done(true) return end
    -- Iron Knuckle has no bank: you pay with the roaches you carry.
    if GK.RunMode and GK.RunMode(ply) == "iron" then done(GK.Roaches.Spend(ply, slot.price)) return end
    done(GK.Roaches.SpendBank(ply, slot.price)) -- only roaches fed into a machine pay
end
concommand.Add("gk_buy", function(ply, _, args)
    if not IsValid(ply) or not ply:Alive() then return end
    local slot = GK.Shop.Slot(string.lower(args[1] or ""))
    if not slot or (ply.GK_NextBuy or 0) > CurTime() then return end
    ply.GK_NextBuy = CurTime() + 1
    GK.Shop.Charge(ply, slot, function(ok)
        if not ok or not ply:Alive() then return end
        if slot.entity then
            GK.Shop.SpawnItem(slot, ply:GetPos() + Vector(0, 0, 20))
        else
            GK.Inv.Give(ply, slot.item, slot.data and table.Copy(slot.data))
        end
    end)
end)
