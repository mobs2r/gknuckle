-- Roach looks and the vending machine's dial, by numbers (on gk_style). Only
-- runs when data/gknuckle/looktest.txt exists. Logs "[GKLOOK]"; no screenshots.
if not file.Exists("gknuckle/looktest.txt", "DATA") then return end
local function log(...) print("[GKLOOK]", ...) end

if CLIENT then
    net.Receive("gk_looktest", function()
        local what = net.ReadString()
        if what == "assets" then
            -- Anything drawn with a missing model or material (purple/black checks).
            local bad = 0
            for _, e in ipairs(ents.GetAll()) do
                local m = e:GetModel()
                if m and m ~= "" and not e:GetNoDraw() and string.EndsWith(m, ".mdl") then
                    local why
                    if not util.IsValidModel(m) then why = "model missing" else
                        for _, mat in ipairs(e:GetMaterials() or {}) do
                            if Material(mat):IsError() then why = "material " .. mat break end
                        end
                    end
                    if why then bad = bad + 1 if bad <= 15 then log("BROKEN", e:GetClass(), m, why, "at", tostring(e:GetPos())) end end
                end
            end
            log("broken-looking entities", bad)
            local coin = Material("gknuckle/vending/coin.png", "smooth noclamp")
            log("coin icon error", tostring(coin:IsError()), "size", coin:Width(), coin:Height())
            log("xenium model", GK.RoachKinds.xenium.model, "held layout tint", tostring(GK.HeldLayout("xenium") and GK.HeldLayout("xenium").layers[3].tint and table.concat(GK.HeldLayout("xenium").layers[3].tint, ",")),
                "bag icon", tostring(GK.ItemSprite and GK.ItemSprite("xenium") and GK.ItemSprite("xenium").mat:GetName()))
        elseif what == "draw" then
            -- Draw every roach's glow/glimmer and one vendor directly, catching errors.
            hook.Add("PostDrawTranslucentRenderables", "GK_LookTestDraw", function(depth, sky)
                if depth or sky then return end
                hook.Remove("PostDrawTranslucentRenderables", "GK_LookTestDraw")
                local n, errs = 0, {}
                for _, r in ipairs(ents.FindByClass("gk_roach")) do
                    local ok, err = pcall(r.DrawTranslucent, r)
                    n = n + 1
                    if not ok then errs[#errs + 1] = err end
                end
                log("roach glow/glimmer draws", n, "errors", #errs, errs[1] or "")
                local kinds = {}
                for _, r in ipairs(ents.FindByClass("gk_roach")) do kinds[r:GetKind()] = (kinds[r:GetKind()] or 0) + 1 end
                local parts = {} for k, c in pairs(kinds) do parts[#parts + 1] = k .. "=" .. c end
                log("roaches near", table.concat(parts, " "))
            end)
        elseif what == "dial" then
            local v = ents.FindByClass("gk_vendor")[1]
            local me = LocalPlayer()
            log("vendor", tostring(v), "banked", GK.Roaches.Banked(me), "dial shows", v and v.GK_DialV and math.floor(v.GK_DialV * 10) / 10 or "not drawn yet",
                "eco lines", tostring(GetGlobal2Bool("gk_eco_coins", false)), tostring(GetGlobal2Bool("gk_eco_b1", false)))
        end
    end)
    return
end
util.AddNetworkString("gk_looktest")

local function send(P, what) net.Start("gk_looktest") net.WriteString(what) net.Send(P) end
hook.Add("PlayerInitialSpawn", "GK_LookTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_LookTest")
    timer.Simple(10, function()
        local P = ply
        send(P, "assets")
        -- One of each roach in front of us.
        local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
        for i, k in ipairs({ "gold", "platinum", "xenium", "boom" }) do
            GK.SpawnRoach(k, P:GetPos() + fwd * 80 + P:GetRight() * (i - 2.5) * 30 + Vector(0, 0, 4))
        end
        timer.Simple(1.5, function() send(P, "draw") end)
        -- Stand at a vendor and bank roaches: the dial should roll up to the count.
        timer.Simple(3, function()
            local v = ents.FindByClass("gk_vendor")[1]
            if not IsValid(v) then log("no vendor") return end
            P:SetPos(v:GetPos() + v:GetForward() * 70)
            P:SetEyeAngles((v:WorldSpaceCenter() - P:EyePos()):Angle())
            P:SetNW2Int("gk_bank", 0)
            timer.Simple(1, function() send(P, "dial") end)
            timer.Simple(1.5, function()
                P:SetNW2Int("gk_roaches", 0)
                GK.Roaches.Add(P, 137)
                GK.Roaches.Bank(P)
                log("banked now", GK.Roaches.Banked(P))
            end)
            timer.Simple(2.2, function() send(P, "dial") end) -- mid-roll
            timer.Simple(6, function() send(P, "dial") end)   -- settled
            -- WK roach slot: a roach held in a hand, clicked at the hole, is banked.
            timer.Simple(7, function()
                local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
                GK.Inv.Give(P, "roach")
                for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "roach" then GK.Inv.Move(P, it.id, "hand_l") end end
                GK.Inv.Sync(P)
                local hole = v:LocalToWorld(v.Layout.inserter)
                P:SetEyeAngles((hole - P:GetShootPos()):Angle())
                local b0 = GK.Roaches.Banked(P)
                GK.Inv.Use(P, "l")
                log("roach in hand clicked at the hole: banked +", GK.Roaches.Banked(P) - b0, "(expect 1)", "hand now", tostring(GK.Inv.HandItem(P, "l") and GK.Inv.HandItem(P, "l").class))
                -- The top edge of the third product window, right under the hole: a purchase, not the slot.
                local c = v.Layout.slots[3]
                local top = v:LocalToWorld(c + Vector(0, 0, v.Layout.slotSize / 2 - 1))
                log("third window top to hole distance", ("%.1f"):format(v:WorldToLocal(top):Distance(v.Layout.inserter)), "slot radius", v.SlotRadius)
            end)
            timer.Simple(8, function() log("DONE") end)
        end)
    end)
end)
