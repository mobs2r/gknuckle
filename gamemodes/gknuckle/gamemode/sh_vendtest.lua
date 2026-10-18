-- Vending machine look test. Only runs when data/gknuckle/vendtest.txt exists:
-- stands in front of a gk_vendor, banks a few roaches, feeds one in by hand
-- and saves screenshots to data/gknuckle/vend_*.jpg. Logs "[GKVEND]", ends
-- with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/vendtest.txt", "DATA") then return end
local function log(...) print("[GKVEND]", ...) end

if CLIENT then
    net.Receive("gk_vendtest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_VendShot", function()
            hook.Remove("PostRender", "GK_VendShot")
            local data = render.Capture({ format = "jpeg", quality = 92, x = 0, y = 0, w = ScrW(), h = ScrH() })
            file.Write("gknuckle/vend_" .. name .. ".jpg", data)
            local v = ents.FindByClass("gk_vendor")[1]
            local r = ents.FindByClass("gk_radio")[1]
            if IsValid(r) then log("client radio", r:GetModel(), "on", tostring(r:GetOn()), "song", tostring(r.GK_SongPath), "playing", tostring(r.GK_Song and r.GK_Song:IsPlaying())) end
            log("shot", name, "dial shows", v and v.GK_DialV and ("%.2f"):format(v.GK_DialV) or "-", "banked", GK.Roaches.Banked(LocalPlayer()))
        end)
    end)
    return
end
util.AddNetworkString("gk_vendtest")

local function shot(P, name) net.Start("gk_vendtest") net.WriteString(name) net.Send(P) end
local function lookFrom(P, v, back, up, at)
    P:SetPos(v:GetPos() + v:GetForward() * back + Vector(0, 0, up or 0))
    P:SetEyeAngles((v:LocalToWorld(at) - P:EyePos()):Angle())
end

hook.Add("PlayerInitialSpawn", "GK_VendTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_VendTest")
    timer.Simple(10, function()
        local P = ply
        local v = ents.FindByClass("gk_vendor")[1]
        if not IsValid(v) then log("no vendor") print("[GKTEST] DONE") return end
        log("vendor", v:GetModel(), "at", tostring(v:GetPos()))
        P:GodEnable()
        for _, e in ipairs(ents.FindByClass("gk_item")) do
            local mn, mx = e:GetCollisionBounds()
            local ph = e:GetPhysicsObject()
            local pmn, pmx
            if IsValid(ph) then pmn, pmx = ph:GetAABB() end
            if (mx - mn):Length() > 80 or (pmn and (pmx - pmn):Length() > 80) then
                log("BIG item", e.GKItemClass, e:GetModel(), "coll", tostring(mn), tostring(mx), "phys", tostring(pmn), tostring(pmx), "solid", e:GetSolid(), "movetype", e:GetMoveType())
            end
        end
        P:SetNW2Int("gk_bank", 7)
        lookFrom(P, v, 110, 0, Vector(28, 0, 70))
        timer.Simple(1.5, function() shot(P, "1_front") end)
        timer.Simple(3, function() lookFrom(P, v, 72, 0, Vector(30, 0, 74)) end)
        timer.Simple(4.5, function() shot(P, "2_close") end)
        timer.Simple(5, function()
            P:SetPos(v:GetPos() + v:GetForward() * 70 + v:GetRight() * 35)
            P:SetEyeAngles((v:LocalToWorld(Vector(30, 0, 68)) - P:EyePos()):Angle())
        end)
        timer.Simple(5.8, function() shot(P, "2b_angle") end)
        -- A gold roach in the left hand, clicked at the hole under the gold roach.
        timer.Simple(6, function()
            local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
            GK.Inv.Give(P, "roach")
            for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "roach" then GK.Inv.Move(P, it.id, "hand_l") end end
            GK.Inv.Sync(P)
            lookFrom(P, v, 72, 0, Vector(31, 15.8, 80.7))
            P:SetEyeAngles((v:LocalToWorld(Vector(31, 15.8, 80.7)) - P:GetShootPos()):Angle())
        end)
        timer.Simple(7, function()
            local b0 = GK.Roaches.Banked(P)
            local held = GK.Inv.Get(P).slots.hand_l
            local tr = util.TraceLine({ start = P:GetShootPos(), endpos = P:GetShootPos() + P:GetAimVector() * 120, filter = P })
            log("hand_l", held and held.class, "trace", tostring(tr.Entity), "local hit", IsValid(tr.Entity) and tostring(tr.Entity:WorldToLocal(tr.HitPos)) or "-",
                "busy", P:GetNW2Float("gk_busy_until", 0) - CurTime())
            if IsValid(tr.Entity) then log("hit ent", tr.Entity.GKItemClass, tr.Entity:GetModel(), "at", tostring(tr.Entity:GetPos()), "hitpos", tostring(tr.HitPos), "shootpos", tostring(P:GetShootPos()), "vendor", tostring(v:GetPos())) end
            GK.Inv.Use(P, "l")
            log("fed roach: banked", b0, "->", GK.Roaches.Banked(P), "(expect +1)")
        end)
        timer.Simple(7.15, function() shot(P, "3_feeding") end)
        timer.Simple(9, function() shot(P, "4_rolled") end)
        -- Buy the middle item: the window lights up and the item drops in the tray.
        timer.Simple(10, function()
            local slot = v:StockSlot(2)
            local hit = v:LocalToWorld(v.Layout.slots[2])
            log("buying", slot and slot.name, "price", slot and slot.price, "banked", GK.Roaches.Banked(P))
            P:SetNW2Int("gk_bank", 99)
            v:Press(P, hit)
        end)
        timer.Simple(10.4, function() shot(P, "5_bought") end)
        timer.Simple(12, function()
            local n = 0
            for _, e in ipairs(ents.FindInSphere(v:LocalToWorld(v.Layout.spawn), 60)) do if e:GetClass() == "gk_item" then n = n + 1 end end
            log("items near tray", n)
            lookFrom(P, v, 220, 0, Vector(28, 0, 80))
        end)
        timer.Simple(13.5, function() shot(P, "6_far") end)
        timer.Simple(13.7, function()
            local r = ents.FindByClass("gk_radio")[1]
            if not IsValid(r) then return end
            P:SetPos(v:GetPos() + v:GetForward() * 120 + Vector(0, 0, 90)) P:SetMoveType(MOVETYPE_NOCLIP) P:SetFOV(30, 0)
            P:SetEyeAngles((r:WorldSpaceCenter() - P:EyePos()):Angle())
        end)
        timer.Simple(14.3, function() shot(P, "6b_radio") end)
        timer.Simple(14.6, function()
            local r = ents.FindByClass("gk_radio")[1]
            if IsValid(r) then log("radio size", tostring(r:OBBMaxs() - r:OBBMins()), "local pos on vendor", tostring(v:WorldToLocal(r:GetPos())), "asleep", tostring(IsValid(r:GetPhysicsObject()) and r:GetPhysicsObject():IsAsleep())) end
            log("radios", #ents.FindByClass("gk_radio"), IsValid(r) and r:GetModel() or "-", IsValid(r) and ("on top of vendor: %.0f u above its base"):format(r:GetPos().z - v:GetPos().z) or "")
            if IsValid(r) then r:Press(P) log("pressed: on", tostring(r:GetOn())) end
        end)
        timer.Simple(15.2, function() shot(P, "7_radio_off") end)
        timer.Simple(16, function() print("[GKTEST] DONE") end)
        timer.Simple(17, function() game.ConsoleCommand("quit\n") end)
    end)
end)
