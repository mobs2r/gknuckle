-- Screenshot test for held items in the hands. Only runs when
-- data/gknuckle/heldtest.txt exists. Puts pairs of items in the hands, takes a
-- screenshot of each, and logs "[GKHELD]" lines.
if not file.Exists("gknuckle/heldtest.txt", "DATA") then return end
local function log(...) print("[GKHELD]", ...) end

if CLIENT then
    net.Receive("gk_heldtest", function()
        local tag = net.ReadString()
        local l, r = GK.ClientInv and GK.ClientInv.slots["hand_l"], GK.ClientInv and GK.ClientInv.slots["hand_r"]
        print("[GKHELD]", "client", tag, "l", l and l.class, "layout", tostring(l and GK.HeldLayout(l.class) ~= nil),
            "r", r and r.class, "layout", tostring(r and GK.HeldLayout(r.class) ~= nil))
        -- Sprites rendered from a model: how much of the texture the model covers.
        hook.Add("HUDPaint", "GK_HeldTestRead", function()
        hook.Remove("HUDPaint", "GK_HeldTestRead")
        for _, c in ipairs({ "revolver", "crowbar", "rebar" }) do local sp = GK.ItemSprite(c) print("[GKHELD]", "bag icon", c, sp and tostring(sp.mat:GetName()) or "spawnicon") end
        for _, it in ipairs({ l, r }) do
            local lay = it and GK.HeldLayout(it.class)
            for _, layer in ipairs(lay and lay.layers or {}) do
                if layer.mat then
                    local tex = layer.mat:GetTexture("$basetexture")
                    render.PushRenderTarget(tex)
                    render.CapturePixels()
                    local solid, n, lit = 0, 0, 0
                    for y = 0, 255, 8 do for x = 0, 255, 8 do
                        n = n + 1
                        local cr, cg, cb, al = render.ReadPixel(x, y)
                        if (al or 0) > 40 then solid = solid + 1 end
                        if cr + cg + cb > 30 then lit = (lit or 0) + 1 end
                    end end
                    render.PopRenderTarget()
                    print("[GKHELD]", "rendered sprite", it.class, "coverage", math.floor(solid / n * 100) .. "%", "size", layer.w, "rgb coverage", math.floor(lit / n * 100) .. "%", "tex", tex:GetName(), tex:Width())
                end
            end
        end
        end)
        do end
    end)
    return
end
util.AddNetworkString("gk_heldtest")

local PAIRS = {
    { "flare", "flaregun" }, { "brick", "xenium" }, { "bullet", "revolver" },
    { "rebar", "hammer" }, { "grub", "pills" },
    { "crowbar", "battery" }, { "healthvial", "grenade" }, { "stun", "roach" }, { "flashlight", "crowbar" },
}

local function hand(P, class, side)
    local inv = GK.Inv.Get(P)
    inv.slots["hand_" .. side] = nil
    GK.Inv.Give(P, class)
    for _, it in ipairs(inv.bag) do if it.class == class then GK.Inv.Move(P, it.id, "hand_" .. side) break end end
end

hook.Add("PlayerInitialSpawn", "GK_HeldTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_HeldTest")
    timer.Simple(10, function()
        local P = ply
        P:SelectWeapon("gk_mind")
        P:SetEyeAngles(Angle(10, P:EyeAngles().y, 0))
        for i, pair in ipairs(PAIRS) do
            timer.Simple(i * 2, function()
                local inv = GK.Inv.Get(P) inv.bag, inv.slots = {}, {}
                hand(P, pair[1], "l") hand(P, pair[2], "r")
                GK.Inv.Sync(P)
                timer.Simple(1, function()
                    log("held", pair[1], P:GetNW2String("gk_hitem_l"), pair[2], P:GetNW2String("gk_hitem_r"))
                    net.Start("gk_heldtest") net.WriteString(pair[1] .. "+" .. pair[2]) net.Send(P)
                end)
            end)
        end
        -- WK reloads: fire the flare gun empty, then reload it from the flare in the other hand.
        local base = #PAIRS * 2 + 2
        timer.Simple(base, function()
            local inv = GK.Inv.Get(P) inv.bag, inv.slots = {}, {}
            hand(P, "flare", "l") hand(P, "flaregun", "r") GK.Inv.Sync(P)
            local gunItem = GK.Inv.HandItem(P, "r")
            GK.Inv.Use(P, "r")
            log("flare gun fired: clip", gunItem.data.clip)
            timer.Simple(0.6, function()
                GK.Inv.Use(P, "r") -- empty: loads from the flare in the left hand
                timer.Simple(1.5, function()
                    log("after reload: clip", gunItem.data.clip, "flare left in hand", tostring(GK.Inv.HandItem(P, "l") ~= nil))
                    net.Start("gk_heldtest") net.WriteString("flaregun loaded") net.Send(P)
                    -- Revolver: empty it, reload from a box.
                    local inv2 = GK.Inv.Get(P) inv2.bag, inv2.slots = {}, {}
                    hand(P, "bullet", "l") hand(P, "revolver", "r")
                    GK.Inv.HandItem(P, "l").data.count = 4 -- four rounds in the hand
                    GK.Inv.Sync(P)
                    local rev = GK.Inv.HandItem(P, "r")
                    rev.data.clip = 0
                    GK.Inv.Reload(P)
                    timer.Simple(2.8, function()
                        local box = GK.Inv.HandItem(P, "l")
                        log("revolver after reload with 4 rounds: clip", rev.data.clip, "rounds left in hand", box and box.data.count or 0)
                        rev.data.clip = 0
                        GK.Inv.Reload(P) -- no box now: nothing happens
                        timer.Simple(0.5, function() log("revolver with no ammo in hand: clip", rev.data.clip) log("DONE") end)
                    end)
                end)
            end)
        end)
    end)
end)
