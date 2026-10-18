-- WK small-rules test (gm_construct). Only runs when data/gknuckle/rulestest.txt
-- exists: crouch-lock on a wall, blink eye uses and reach, buff fade, health
-- regen, a pocketed flashlight. Logs "[GKRULES]", ends with "[GKTEST] DONE".
if not file.Exists("gknuckle/rulestest.txt", "DATA") then return end
local function log(...) print("[GKRULES]", ...) end

if CLIENT then
    local held = 0
    net.Receive("gk_rulestest", function() held = net.ReadUInt(32) end)
    hook.Add("CreateMove", "GK_RulesTest", function(cmd) if held ~= 0 then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) end end)
    return
end
util.AddNetworkString("gk_rulestest")

hook.Add("PlayerInitialSpawn", "GK_RulesTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_RulesTest")
    local function hold(b) net.Start("gk_rulestest") net.WriteUInt(b, 32) net.Send(P) end
    local t = 10
    local function at(dt, fn) t = t + dt timer.Simple(t, function() local ok, e = pcall(fn) if not ok then log("ERROR", e) end end) end
    local fwd, base, z0
    at(0, function()
        RunConsoleCommand("gk_climb_mode_wk", "0")
        P:SelectWeapon("gk_mind")
        fwd = Angle(0, P:EyeAngles().y, 0):Forward()
        base = P:GetPos()
        local p = ents.Create("prop_physics")
        p:SetModel("models/hunter/plates/plate8x8.mdl")
        p:SetPos(base + fwd * 60 + Vector(0, 0, 190)) p:SetAngles(fwd:Angle() + Angle(90, 0, 0)) p:Spawn()
        p:GetPhysicsObject():EnableMotion(false)
        GK.SetStamina(P, 100)
    end)
    -- Hang by both hands, then crouch: it should hold still.
    at(1, function() P:SetPos(base + Vector(0, 0, 120)) P:SetLocalVelocity(vector_origin) P:SetEyeAngles(Angle(-20, fwd:Angle().y, 0)) hold(bit.bor(IN_ATTACK, IN_ATTACK2)) end)
    at(1, function() hold(bit.bor(IN_ATTACK, IN_ATTACK2, IN_DUCK, IN_FORWARD)) end)
    at(0.4, function() z0 = P:GetPos().z end) -- after the crouch tucks the legs up
    at(1, function() log("crouched on the wall holding W for 1 s: moved", math.floor(math.abs(P:GetPos().z - z0)), "u (expect ~0)", "hands", P:GetNW2Int("gk_hand_l", 0), P:GetNW2Int("gk_hand_r", 0)) hold(0) end)
    -- Blink eye: three jumps of up to 10 m.
    at(1, function()
        RunConsoleCommand("gk_climb_mode_wk", "1")
        P:SetPos(base) P:SetEyeAngles(Angle(0, fwd:Angle().y + 180, 0))
        local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
        GK.Inv.Give(P, "blinkeye")
        for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "blinkeye" then GK.Inv.Move(P, it.id, "hand_r") end end
        GK.Inv.Sync(P)
    end)
    for k = 1, 3 do
        at(0.6, function()
            local p0 = P:GetPos()
            GK.Inv.Use(P, "r")
            local it = GK.Inv.HandItem(P, "r")
            log("blink", k, "jumped", math.floor(P:GetPos():Distance(p0)), "u (WK max 394)", "uses left", it and it.data and it.data.uses or "gone")
        end)
    end
    -- Buff fade: pills over 10 s, drain halves at the start, three quarters at half time.
    at(0.5, function() GK.AddBuff(P, "pilled", 10) log("pills: drain x", ("%.2f"):format(GK.BuffMult(P, "drain")), "(expect ~0.5)") end)
    at(5, function() log("pills half way: drain x", ("%.2f"):format(GK.BuffMult(P, "drain")), "(expect ~0.75, WK fades evenly)") end)
    -- Health regen.
    at(0.5, function() P:SetHealth(50) P.GK_HurtAt = CurTime() end)
    at(7, function() log("health 7 s after being hurt to 50:", P:Health(), "(expect ~54: 4 s wait, then 1.5/s)") end)
    -- Flashlight in a pocket.
    at(0.5, function()
        local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
        GK.Inv.Give(P, "flashlight")
        for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "flashlight" then GK.Inv.Move(P, it.id, "hand_l") end end
        GK.Inv.Sync(P)
        GK.Inv.Use(P, "l")
        GK.Inv.Pocket(P, "l")
        log("flashlight on and pocketed: still shining", tostring(P:GetNW2Bool("gk_flashlight", false) and P:GetNW2Bool("gk_flash_pocket", false)))
    end)
    at(1, function() print("[GKTEST] DONE") end)
    at(1, function() game.ConsoleCommand("quit\n") end)
end)
