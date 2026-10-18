-- Giant roach and strider test (gk_style). Only runs when
-- data/gknuckle/beasttest.txt exists. Logs "[GKBEAST]", saves beast_*.jpg.
if not file.Exists("gknuckle/beasttest.txt", "DATA") then return end
local function log(...) print("[GKBEAST]", ...) end
if CLIENT then
    net.Receive("gk_beasttest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_BeastShot", function()
            hook.Remove("PostRender", "GK_BeastShot")
            file.Write("gknuckle/beast_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
        end)
    end)
    return
end
util.AddNetworkString("gk_beasttest")
local function shot(P, n) net.Start("gk_beasttest") net.WriteString(n) net.Send(P) end
local P
local function climb(a, frac, done)
    local info = a.info
    for k = 1, #info.plan do
        timer.Simple(k * 0.5, function()
            P:SetPos(Vector(info.spawn.x, info.spawn.y, info.spawn.z + (info.top - info.spawn.z) * frac * k / #info.plan))
            GK.Arena.Stream(1)
        end)
    end
    timer.Simple(#info.plan * 0.5 + 2, done)
end
local function look(cls, name, after)
    local e = ents.FindByClass(cls)[1]
    if IsValid(e) then
        P:SetPos(e:GetPos() + Vector(220, 0, 60))
        P:SetEyeAngles((e:WorldSpaceCenter() - P:EyePos()):Angle())
        timer.Simple(1.5, function() shot(P, name) end)
    end
    timer.Simple(3, after)
end
hook.Add("PlayerInitialSpawn", "GK_BeastTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_BeastTest")
    P = ply
    timer.Simple(12, function()
        RunConsoleCommand("gk_tube_rise", "0") RunConsoleCommand("gk_mass_grace", "1000") RunConsoleCommand("gk_mass_start", "100000")
        P:GodEnable()
        -- A Pipeworks run with the Waste Heap in it.
        local seed
        for s = 1, 40 do
            for _, pc in ipairs(GK.GenerateRun("Region_Pipeworks_Campaign", s, 9000) or {}) do
                if pc:find("pipeworks_waste") then seed = s break end
            end
            if seed then break end
        end
        GK.StageRegion = function() return "Region_Pipeworks_Campaign" end
        local a = GK.StartArena(1, { P }, true)
        P:SetMoveType(MOVETYPE_NOCLIP)
        log("pipeworks seed with a waste room", tostring(seed), "this run's rooms", #a.info.plan)
        climb(a, 0.95, function()
            log("Pipeworks: striders", #ents.FindByClass("wkn_strider"))
            look("wkn_strider", "strider", function()
                GK.EndArena(1, nil)
                timer.Simple(6, function()
                    GK.StageRegion = function() return "Region_Nest_Campaign" end
                    local b = GK.StartArena(1, { P }, true)
                    P:SetMoveType(MOVETYPE_NOCLIP)
                    climb(b, 0.95, function()
                        log("Nest: giant roaches", #ents.FindByClass("wkn_giantroach"))
                        look("wkn_giantroach", "giantroach", function()
                            print("[GKTEST] DONE")
                            timer.Simple(1, function() game.ConsoleCommand("quit\n") end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
