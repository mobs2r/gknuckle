-- Habitation apparition test (gk_style). Only runs when data/gknuckle/ghosttest.txt
-- exists: builds a Habitation run, counts apparitions, looks at one. Saves
-- data/gknuckle/ghost_*.jpg, ends with "[GKTEST] DONE".
if not file.Exists("gknuckle/ghosttest.txt", "DATA") then return end
local function log(...) print("[GKGHOST]", ...) end
if CLIENT then
    net.Receive("gk_ghosttest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_GhostShot", function()
            hook.Remove("PostRender", "GK_GhostShot")
            file.Write("gknuckle/ghost_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
            log("client: apparitions", #ents.FindByClass("gk_ghost"))
        end)
    end)
    return
end
util.AddNetworkString("gk_ghosttest")
hook.Add("PlayerInitialSpawn", "GK_GhostTest", function(P)
    if P:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_GhostTest")
    timer.Simple(12, function()
        RunConsoleCommand("gk_tube_rise", "0")
        RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
        GK.StageRegion = function() return "Region_Habitation_Campaign" end
        -- How often a campaign Habitation run reaches WK's Haunted Pier (pier_01..03).
        for _, budget in ipairs({ 9000, false }) do
            local hits, order = 0, nil
            for seed = 1, 30 do
                local pieces = GK.GenerateRun("Region_Habitation_Campaign", seed, budget or nil) or {}
                for _, pc in ipairs(pieces) do if pc:find("^m3_habitation_pier_0") then hits = hits + 1 order = order or table.concat(pieces, " ") break end end
            end
            log("width budget", tostring(budget), "runs with a Haunted Pier room:", hits, "of 30", order or "")
        end
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
            local s = ents.FindByClass("gk_ghost")
            local pieces = {}
            for _, st in ipairs(info.plan) do if st.piece:find("pier") then pieces[#pieces + 1] = st.piece end end
            log("Habitation run", info.region, "rooms", #info.plan, "pier rooms", table.concat(pieces, ","), "apparitions", #s)
            if not s[1] then
                -- None placed this seed: stand one up in front of us to look at.
                s[1] = GK.SpawnGhost(P:GetPos() + P:GetForward() * 200 + Vector(0, 0, 64), { scale = 1, wander = 118, speed = 0.1 })
                log("spawned a test apparition")
            end
            local g = s[1]
            P:SetPos(g:GetPos() + Vector(220, 40, -64))
            P:SetEyeAngles((g:GetPos() - (g:GetPos() + Vector(220, 40, 0))):Angle())
        end)
        timer.Simple(#info.plan * 0.5 + 4, function() net.Start("gk_ghosttest") net.WriteString("swarm") net.Send(P) end)
        timer.Simple(#info.plan * 0.5 + 6, function() print("[GKTEST] DONE") end)
        timer.Simple(#info.plan * 0.5 + 7, function() game.ConsoleCommand("quit\n") end)
    end)
end)
