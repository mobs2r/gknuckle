-- Test for crystal gore, breakable crates and the stamina overdraw stagger.
-- Only runs when data/gknuckle/goretest.txt exists. Logs "[GKGORE]" lines.
if not file.Exists("gknuckle/goretest.txt", "DATA") then return end
local function log(...) print("[GKGORE]", ...) end

if CLIENT then
    net.Receive("gk_goretest", function()
        local what = net.ReadString()
        if what == "shot" then do end end
    end)
    local held, untilT = 0, 0
    net.Receive("gk_goretest_press", function() held = net.ReadUInt(32) untilT = CurTime() + net.ReadFloat() end)
    hook.Add("CreateMove", "GK_GoreTestInput", function(cmd)
        if CurTime() < untilT then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) end
    end)
    return
end
util.AddNetworkString("gk_goretest")
util.AddNetworkString("gk_goretest_press")
local function send(ply, s) net.Start("gk_goretest") net.WriteString(s) net.Send(ply) end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, bot, crate

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    if #player.GetBots() == 0 then RunConsoleCommand("bot") end
end)
-- 1. Crystal gore: a bot loses its legs in front of us.
step(2, function()
    bot = player.GetBots()[1]
    if not IsValid(bot) then log("no bot") return end
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    bot:SetPos(P:GetPos() + fwd * 110)
    bot:SetEyeAngles((-fwd):Angle())
    P:SetEyeAngles(Angle(15, P:EyeAngles().y, 0))
    GK.RemoveLegs(bot)
    log("bot legs", tostring(GK.HasLegs(bot)), "crystal colour", tostring(GK.CrystalColor(bot)))
end)
step(0.3, function() send(P, "shot") end)
step(1.5, function()
    if IsValid(bot) then
        local d = DamageInfo() d:SetDamage(500) d:SetAttacker(P) d:SetInflictor(P) d:SetDamageType(DMG_BULLET)
        d:SetDamagePosition(bot:WorldSpaceCenter())
        bot.GK_Goring = true
        bot:TakeDamageInfo(d)
        log("bot alive after a big hit", tostring(bot:Alive()))
    end
end)
step(0.4, function() send(P, "shot") end)
-- 2. A WK supply crate: hit it and it shatters, with loot.
step(1, function()
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    crate = ents.Create("gk_crate")
    crate.GK_Supply = true
    crate:SetPos(P:GetPos() + fwd * 90 + Vector(0, 0, 20))
    crate:Spawn()
    log("crate model", crate:GetModel())
end)
step(1, function()
    local items = #ents.FindByClass("gk_item")
    crate:TakeDamage(30, P, P)
    timer.Simple(0.3, function()
        log("crate broken", tostring(not IsValid(crate)), "loot dropped", #ents.FindByClass("gk_item") - items)
        send(P, "shot")
    end)
end)
-- 3. Overdraw: hang on a wall with no grip left; the bar fills, shatters, we stagger.
step(1.5, function()
    -- Well away from the crate bits and loot.
    for _, e in ipairs(ents.FindByClass("gk_item")) do e:Remove() end
    local fwd = Angle(0, P:EyeAngles().y + 180, 0):Forward()
    local wall = ents.Create("prop_physics")
    wall:SetModel("models/hunter/plates/plate4x4.mdl")
    wall:SetPos(P:GetPos() + fwd * 300 + Vector(0, 0, 400)) wall:SetAngles(fwd:Angle() + Angle(90, 0, 0)) wall:Spawn()
    wall:GetPhysicsObject():EnableMotion(false)
    P:SetPos(wall:GetPos() - fwd * 40 - Vector(0, 0, 64))
    P:SetEyeAngles(fwd:Angle())
    P:SetLocalVelocity(vector_origin)
    -- Hold the button first (a hand lets go the moment its button is up).
    net.Start("gk_goretest_press") net.WriteUInt(IN_ATTACK, 32) net.WriteFloat(5) net.Send(P)
    GK.SetStamina(P, 100)
end)
step(0.4, function()
    log("overdraw test: gripping before", P:GetNW2Int("gk_hand_l", 0))
    GK.SetStamina(P, 0)
end)
step(0.8, function() log("overdraw at 0.8 s", ("%.2f"):format(P:GetNW2Float("gk_overdraw", 0)), "gripping", P:GetNW2Int("gk_hand_l", 0)) send(P, "shot") end)
step(1.2, function()
    log("after 2 s: staggering", tostring(P:GetNW2Float("gk_stagger_until", 0) > CurTime()), "gripping", P:GetNW2Int("gk_hand_l", 0), "overdraw", ("%.2f"):format(P:GetNW2Float("gk_overdraw", 0)))
end)
step(1, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_GoreTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_GoreTest")
    timer.Simple(10, function()
        local t = 0
        for _, s in ipairs(steps) do
            t = t + s[1]
            timer.Simple(t, function()
                local ok, err = pcall(s[2])
                if not ok then log("STEP ERROR", err) end
            end)
        end
    end)
end)
