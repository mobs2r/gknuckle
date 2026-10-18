-- Nest moth swarm test (gk_style). Only runs when data/gknuckle/mothtest.txt
-- exists: builds a Nest run, counts swarms, looks at one. Saves
-- data/gknuckle/moth_*.jpg, ends with "[GKTEST] DONE".
if not file.Exists("gknuckle/mothtest.txt", "DATA") then return end
local function log(...) print("[GKMOTH]", ...) end
if CLIENT then
    net.Receive("gk_mothtest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_MothShot", function()
            hook.Remove("PostRender", "GK_MothShot")
            file.Write("gknuckle/moth_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
            local s = ents.FindByClass("gk_mothswarm")[1]
            local drawn = 0
            for _, m in ipairs(s and s.Moths or {}) do if IsValid(m.ent) then drawn = drawn + 1 end end
            log("client: swarms", #ents.FindByClass("gk_mothswarm"), "moths drawn in the first", drawn)
        end)
    end)
    return
end
util.AddNetworkString("gk_mothtest")
hook.Add("PlayerInitialSpawn", "GK_MothTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_MothTest")
    timer.Simple(12, function()
        RunConsoleCommand("gk_tube_rise", "0")
        RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
        GK.StageRegion = function() return "Region_Nest_Campaign" end
        local a = GK.StartArena(1, { P }, true)
        local info = a.info
        P:SetMoveType(MOVETYPE_NOCLIP)
        for k = 1, #info.plan do
            timer.Simple(k * 0.5, function()
                P:SetPos(Vector(info.spawn.x, info.spawn.y, info.spawn.z + (info.top - info.spawn.z) * 0.9 * k / #info.plan))
                GK.Arena.Stream(1)
            end)
        end
        timer.Simple(#info.plan * 0.5 + 2, function()
            local s = ents.FindByClass("gk_mothswarm")
            log("Nest run", info.region, "rooms", #info.plan, "swarms", #s)
            if s[1] then
                P:SetPos(s[1]:GetPos() + Vector(260, 0, -40))
                P:SetEyeAngles((s[1]:GetPos() - P:EyePos()):Angle())
            end
        end)
        timer.Simple(#info.plan * 0.5 + 4, function() net.Start("gk_mothtest") net.WriteString("swarm") net.Send(P) end)
        timer.Simple(#info.plan * 0.5 + 6, function() print("[GKTEST] DONE") end)
        timer.Simple(#info.plan * 0.5 + 7, function() game.ConsoleCommand("quit\n") end)
    end)
end)
