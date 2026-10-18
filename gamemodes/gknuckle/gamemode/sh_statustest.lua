-- Status screen effects test (gm_construct). Only runs when
-- data/gknuckle/statustest.txt exists: a heavy hit, a blink, pills, a shield;
-- saves data/gknuckle/status_*.jpg. Ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/statustest.txt", "DATA") then return end
local function log(...) print("[GKSTAT]", ...) end

if CLIENT then
    net.Receive("gk_statustest", function()
        local name = net.ReadString()
        if name == "openlogs" then local c, n = GK.OpenLogs() log("logs panel", tostring(IsValid(c)), "logs", n, "found", #file.Find("data_static/gknuckle/logs/*.txt", "GAME")) return end
        hook.Add("PostRender", "GK_StatShot", function()
            hook.Remove("PostRender", "GK_StatShot")
            file.Write("gknuckle/status_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
            log("shot", name)
        end)
    end)
    return
end
util.AddNetworkString("gk_statustest")
local function shot(P, name) net.Start("gk_statustest") net.WriteString(name) net.Send(P) end

hook.Add("PlayerInitialSpawn", "GK_StatTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_StatTest")
    local t = 10
    local function at(dt, fn) t = t + dt timer.Simple(t, function() local ok, e = pcall(fn) if not ok then log("ERROR", e) end end) end
    at(0, function() shot(P, "0_normal") end)
    at(1, function()
        local d = DamageInfo() d:SetDamage(30) d:SetDamageType(DMG_SLASH) d:SetAttacker(game.GetWorld()) d:SetInflictor(game.GetWorld())
        P:TakeDamageInfo(d)
        log("hit for 30: wound mark set", tostring(P:GetNW2Float("gk_wound_at", 0) > 0))
    end)
    at(0.4, function() shot(P, "1_wounded") end)
    at(4.5, function() P:SetHealth(100) P:SetNW2Float("gk_blink_at", CurTime()) end)
    at(0.15, function() shot(P, "2_blink") end)
    at(1.5, function() GK.AddBuff(P, "pilled", 30) end)
    at(1, function() shot(P, "3_pilled") end)
    at(1, function() GK.AddBuff(P, "shielded", 30) end)
    at(1, function() shot(P, "4_shielded") end)
    at(1, function() net.Start("gk_statustest") net.WriteString("openlogs") net.Send(P) end)
    at(1, function() P:SendLua("RunConsoleCommand(\"jpeg\")") end)
    at(1, function() print("[GKTEST] DONE") end)
    at(1, function() game.ConsoleCommand("quit\n") end)
end)
