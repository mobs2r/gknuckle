-- Emote test: opens the C wheel and screenshots it, then plays emotes and
-- screenshots each. Only runs when data/gknuckle/emotetest.txt exists.
if not file.Exists("gknuckle/emotetest.txt", "DATA") then return end
local function log(...) print("[GKEMOTE]", ...) end

if CLIENT then
    net.Receive("gk_emotetest", function()
        local what = net.ReadString()
        if what == "wheel" then
            hook.Run("OnContextMenuOpen")
            timer.Simple(0.4, function()
                input.SetCursorPos(ScrW() / 2 + 200, ScrH() / 2 - 60)
                timer.Simple(0.3, function()
                    do end
                    timer.Simple(0.3, function() hook.Run("OnContextMenuClose") end)
                end)
            end)
        elseif what == "spawnmenu" then
            print("[GKEMOTE]", "spawn menu allowed", tostring(hook.Run("SpawnMenuOpen")))
        else
            local e = GK.EmoteOf(LocalPlayer())
            print("[GKEMOTE]", "client emote", e and e.id, "expression", GK.Expression(LocalPlayer()))
            do end
        end
    end)
    return
end
util.AddNetworkString("gk_emotetest")
local function send(ply, s) net.Start("gk_emotetest") net.WriteString(s) net.Send(ply) end

hook.Add("PlayerInitialSpawn", "GK_EmoteTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_EmoteTest")
    timer.Simple(10, function()
        local P = ply
        P:SelectWeapon("gk_mind")
        P:SetEyeAngles(Angle(5, P:EyeAngles().y, 0))
        send(P, "spawnmenu")
        send(P, "wheel")
        local list = { "shy", "wave", "thumbsup", "rock", "clap", "fist" }
        for i, id in ipairs(list) do
            timer.Simple(2 + i * 1.5, function()
                P:SetNW2String("gk_emote_id", id)
                P:SetNW2Float("gk_emote_until", CurTime() + GK.Emotes[id].time)
                timer.Simple(0.6, function() send(P, "shot") log("server emote", id, "visuals", GK.PlayerVisuals(P).emote, GK.PlayerVisuals(P).expression) end)
            end)
        end
        timer.Simple(2 + #list * 1.5 + 2, function() log("DONE") end)
    end)
end)
