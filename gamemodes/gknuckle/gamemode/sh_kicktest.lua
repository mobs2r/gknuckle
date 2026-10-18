-- Kick, kick-boost and boom jar test (gm_construct, needs a bot slot).
-- Only runs when data/gknuckle/kicktest.txt exists. Logs "[GKKICK]", saves
-- data/gknuckle/kick_*.jpg, ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/kicktest.txt", "DATA") then return end
local function log(...) print("[GKKICK]", ...) end

if CLIENT then
    local duck = false
    net.Receive("gk_kicktest", function()
        local what = net.ReadString()
        if what == "duck" then duck = net.ReadBool() return end
        hook.Add("PostRender", "GK_KickShot", function()
            hook.Remove("PostRender", "GK_KickShot")
            file.Write("gknuckle/kick_" .. what .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
        end)
    end)
    hook.Add("CreateMove", "GK_KickTestDuck", function(cmd) if duck then cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK)) end end)
    return
end
util.AddNetworkString("gk_kicktest")
local function send(P, what, b) net.Start("gk_kicktest") net.WriteString(what) if b ~= nil then net.WriteBool(b) end net.Send(P) end

local steps, P, B = {}, nil, nil
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local fwd, base

step(0, function()
    player.CreateNextBot("kicker")
    fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    base = P:GetPos()
    P:GodEnable()
end)
step(2, function()
    B = player.GetBots()[1]
    -- The bot faces us side-on, a little way off: we watch it kick.
    B:SetPos(base + fwd * 120)
    B:SetEyeAngles(Angle(0, fwd:Angle().y + 90, 0))
    P:SetEyeAngles((B:WorldSpaceCenter() - P:EyePos()):Angle())
end)
for i, at in ipairs({ 0.08, 0.16, 0.26 }) do
    step(1, function()
        B.GK_NextKick = 0
        B:SetNW2Float("gk_stamina", 100) GK.SetStamina(B, 100)
        GK.Kick(B)
        timer.Simple(at, function() send(P, "pose" .. i) end)
    end)
end
-- Kick-boost: crouched in the air, looking down at the floor.
step(1.5, function() send(P, "duck", true) end)
step(0.5, function()
    P.GK_NextKick = 0
    GK.SetStamina(P, 100)
    P:SetPos(base + Vector(0, 0, 40))
    P:SetLocalVelocity(Vector(0, 0, -150))
    P:SetEyeAngles(Angle(80, fwd:Angle().y, 0))
end)
step(0.05, function()
    log("before: on ground", tostring(P:OnGround()), "crouching", tostring(P:Crouching()), "vel z", math.floor(P:GetVelocity().z))
    local z0 = P:GetPos().z
    GK.Kick(P)
    P.GK_BoostZ0 = z0
end)
step(0.1, function() log("just after the kick-boost: vel z", math.floor(P:GetVelocity().z), "(expect well above 0)") end)
step(0.5, function() log("rose", math.floor(P:GetPos().z - P.GK_BoostZ0), "units in 0.6 s") send(P, "duck", false) end)
-- Boom jar: thrown at the floor beside the bot.
step(1.5, function()
    B:SetPos(base + fwd * 140) B:SetHealth(100)
    P:SetPos(base) P:SetEyeAngles((B:GetPos() + fwd * -30 - P:GetShootPos()):Angle())
    local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
    GK.Inv.Give(P, "boomjar")
    for _, it in ipairs(table.Copy(inv.bag)) do if it.class == "boomjar" then GK.Inv.Move(P, it.id, "hand_r") end end
    GK.Inv.Sync(P)
end)
step(0.3, function()
    GK.Inv.Use(P, "r")
    log("jar thrown:", #ents.FindByClass("gk_boomjar_thrown"), "in the air; hand now", tostring(GK.Inv.HandItem(P, "r")))
end)
step(1.5, function()
    log("after impact: jars left", #ents.FindByClass("gk_boomjar_thrown"), "(expect 0)", "bot health", B:Health(), "(expect below 100)", "alive", tostring(B:Alive()))
end)
step(0.5, function() print("[GKTEST] DONE") end)
step(1, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_KickTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_KickTest")
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
