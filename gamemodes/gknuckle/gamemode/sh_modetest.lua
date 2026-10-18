-- Run modes test (gk_style). Only runs when data/gknuckle/modetest.txt
-- exists: Hard doubles the Mass and creature hits; Iron Knuckle has no perks,
-- no bank and pays from carried roaches. Logs "[GKMODE]".
if not file.Exists("gknuckle/modetest.txt", "DATA") then return end
if CLIENT then return end
local function log(...) print("[GKMODE]", ...) end
hook.Add("PlayerInitialSpawn", "GK_ModeTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_ModeTest")
    local t, A = 12, nil
    local function at(dt, fn) t = t + dt timer.Simple(t, function() local ok, e = pcall(fn) if not ok then log("ERROR", e) end end) end
    at(0, function()
        RunConsoleCommand("gk_tube_rise", "0") RunConsoleCommand("gk_mass_grace", "0")
        RunConsoleCommand("gk_run_mode", "hard")
    end)
    at(0.5, function()
        A = GK.StartArena(1, { P }, true)
        P:GodDisable() P:SetMoveType(MOVETYPE_NOCLIP)
        P:SetPos(A.info.spawn + Vector(0, 0, 200))
        log("mode", A.mode, "region", A.info.region)
    end)
    local g0
    at(1.5, function() g0 = A.gas end)
    at(3, function() log("hard: gas rose", math.floor(A.gas - g0), "u in 3 s (campaign base would be ~118 x band)") end)
    at(0.2, function()
        local bug = ents.Create("gk_bloodbug") bug:SetPos(P:GetPos() + Vector(100, 0, 0)) bug:Spawn()
        P:SetHealth(100)
        local d = DamageInfo() d:SetDamage(10) d:SetDamageType(DMG_SLASH) d:SetAttacker(bug) d:SetInflictor(bug)
        P:TakeDamageInfo(d)
        log("hard: a creature's 10 damage took", 100 - P:Health(), "(expect 20)")
        bug:Remove()
        GK.EndArena(1, nil)
    end)
    at(6, function()
        RunConsoleCommand("gk_run_mode", "iron")
    end)
    at(0.5, function()
        A = GK.StartArena(1, { P }, true)
        log("mode", A.mode)
        local c = ents.Create("gk_perk_console") c:SetPos(P:GetPos() + Vector(40, 0, 0)) c:Spawn()
        GK.OfferPerks(P, c)
        local o = P.GK_PerkOffer
        log("iron: perk pick", tostring(GK.PickPerk(P, o.cards[1] or "x")), "backup pick", tostring(GK.PickPerk(P, "backup")), "(expect false, false)")
        P:SetNW2Int("gk_bank", 0) P:SetNW2Int("gk_roaches", 10)
        local slot = GK.ShopSlots[1]
        local paid
        GK.Shop.Charge(P, slot, function(ok) paid = ok end)
        log("iron: bought", slot.name, "for", slot.price, "with carried roaches:", tostring(paid), "carried now", GK.Roaches.Count(P))
    end)
    at(1, function() RunConsoleCommand("gk_run_mode", "campaign") RunConsoleCommand("gk_mass_grace", "60") print("[GKTEST] DONE") end)
    at(1, function() game.ConsoleCommand("quit\n") end)
end)
