-- Batch 5 test (gm_construct): vendor sold-out, the hammer breaking a supply
-- crate, one perk per console. Only runs when data/gknuckle/econtest.txt
-- exists. Logs "[GKECON]", ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/econtest.txt", "DATA") then return end
if CLIENT then return end
local function log(...) print("[GKECON]", ...) end

local steps, P = {}, nil
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local v, crate, console

step(0, function()
    v = ents.FindByClass("gk_vendor")[1]
    P:GodEnable()
    P:SetNW2Int("gk_bank", 50)
    local slot = v:StockSlot(1)
    v:Press(P, v:LocalToWorld(v.Layout.slots[1]))
    log("bought slot 1 (", slot and slot.name, "price", slot and slot.price, "): bank", P:GetNW2Int("gk_bank"), "sold", tostring(v:IsSold(1)))
end)
step(1.5, function()
    local b = GK.Roaches.Banked(P)
    v:Press(P, v:LocalToWorld(v.Layout.slots[1]))
    log("pressed the sold-out slot again: bank", b, "->", GK.Roaches.Banked(P), "(expect unchanged)")
end)
step(1.5, function()
    -- A supply crate, and a hammer in the right hand.
    crate = ents.Create("gk_crate")
    crate.GK_Supply = true crate.GK_Frozen = true
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    crate:SetPos(P:GetPos() + fwd * 50 + Vector(0, 0, 1))
    crate:Spawn()
    local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
    GK.Inv.Give(P, "hammer")
    for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "hammer" then GK.Inv.Move(P, it.id, "hand_r") end end
    GK.Inv.Sync(P)
    P:SetEyeAngles((crate:WorldSpaceCenter() - P:GetShootPos()):Angle())
    log("crate health", crate:Health())
end)
step(0.5, function() GK.Inv.Use(P, "r") end)
step(0.8, function()
    if IsValid(crate) then GK.Inv.Use(P, "r") end
end)
step(0.8, function() log("hammered the crate: still there", tostring(IsValid(crate)), "(expect false: broken open)") end)
step(0.5, function()
    console = ents.Create("gk_perk_console")
    console:SetPos(P:GetPos() + Vector(60, 0, 0)) console:Spawn()
    GK.OfferPerks(P, console)
    local o = P.GK_PerkOffer
    local cards = o and table.concat(o.cards, ",")
    log("console offers", cards)
    P:SetNW2Int("gk_bank", 30)
    log("reroll for 15:", tostring(GK.PickPerk(P, "reroll")), "now offers", table.concat(o.cards, ","), "bank", GK.Roaches.Banked(P), "(expect true, new cards, 15)")
    local first = o and o.cards[1]
    log("take one:", tostring(GK.PickPerk(P, first)), "(expect true)")
    GK.OfferPerks(P, console)
    log("come back to it: cards left", #(P.GK_PerkOffer.cards), "(expect 0, spent)", "take another:", tostring(GK.PickPerk(P, o.cards[1] or "x")), "(expect false)")
    local c2 = ents.Create("gk_perk_console") c2:SetPos(P:GetPos() + Vector(-60, 0, 0)) c2:Spawn()
    GK.OfferPerks(P, c2)
    log("a second console offers", #(P.GK_PerkOffer.cards), "cards (expect 3)")
end)
step(0.5, function() print("[GKTEST] DONE") end)
step(1, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_EconTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_EconTest")
    P = ply
    local t = 10
    for _, s in ipairs(steps) do
        t = t + s[1]
        timer.Simple(t, function()
            local ok, err = pcall(s[2])
            if not ok then log("STEP ERROR", err) end
        end)
    end
end)
