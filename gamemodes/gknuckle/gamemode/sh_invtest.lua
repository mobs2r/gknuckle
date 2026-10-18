-- Inventory rules test (gm_construct). Only runs when data/gknuckle/invtest.txt
-- exists: the bag counts items, rebar won't pocket, X swaps hands, new perks.
if not file.Exists("gknuckle/invtest.txt", "DATA") then return end
if CLIENT then return end
local function log(...) print("[GKINV]", ...) end
hook.Add("PlayerInitialSpawn", "GK_InvTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_InvTest")
    timer.Simple(10, function()
        local ok, e = pcall(function()
            local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
            for _ = 1, 13 do GK.Inv.Give(P, "foodbar") end
            log("13 things: encumber", P:GetNW2Float("gk_encumber"), "(expect 1)")
            for _ = 1, 4 do GK.Inv.Give(P, "foodbar") end
            log("17 things: encumber", ("%.2f"):format(P:GetNW2Float("gk_encumber")), "(expect 0.6)")
            inv.slots = {} inv.bag = {}
            GK.Inv.Give(P, "rebar") GK.Inv.Give(P, "brick")
            for _, it in ipairs(table.Copy(inv.bag)) do
                if it.class == "rebar" then GK.Inv.Move(P, it.id, "hand_l") else GK.Inv.Move(P, it.id, "hand_r") end
            end
            GK.Inv.Pocket(P, "l")
            log("pocket a rebar: hand", tostring(inv.slots.hand_l and inv.slots.hand_l.class), "pocket", tostring(inv.slots.pocket_l and inv.slots.pocket_l.class), "(expect rebar, nil)")
            GK.Inv.SwapHands(P)
            log("swap hands: left", tostring(inv.slots.hand_l and inv.slots.hand_l.class), "right", tostring(inv.slots.hand_r and inv.slots.hand_r.class), "(expect brick, rebar)")
            log("perks: velocity speed x", GK.Perks.velocity and GK.Perks.velocity.mult.speed, "rabbit jump x", GK.Perks.rabbit and GK.Perks.rabbit.mult.jump)
        end)
        if not ok then log("ERROR", e) end
        print("[GKTEST] DONE")
        timer.Simple(1, function() game.ConsoleCommand("quit\n") end)
    end)
end)
