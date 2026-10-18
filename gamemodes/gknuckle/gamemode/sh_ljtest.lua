-- Long-jump number test (gk_style). Only runs when data/gknuckle/ljtest.txt
-- exists: finds each lane's gap, stands on the take-off block looking across,
-- then on the landing block looking back, and saves data/gknuckle/lj_*.jpg.
-- Logs "[GKLJ]", ends with "[GKTEST] DONE" and quits.
if not file.Exists("gknuckle/ljtest.txt", "DATA") then return end
local function log(...) print("[GKLJ]", ...) end

if CLIENT then
    net.Receive("gk_ljtest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_LJShot", function()
            hook.Remove("PostRender", "GK_LJShot")
            file.Write("gknuckle/lj_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 90, x = 0, y = 0, w = ScrW(), h = ScrH() }))
        end)
    end)
    return
end
util.AddNetworkString("gk_ljtest")
local function shot(P, name) net.Start("gk_ljtest") net.WriteString(name) net.Send(P) end

hook.Add("PlayerInitialSpawn", "GK_LJTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_LJTest")
    timer.Simple(12, function()
        local P = ply
        P:GodEnable()
        local labels = ents.FindByClass("gk_ljlabel")
        log("labels", #labels)
        for _, l in ipairs(labels) do
            l:FindFaces()
            local f = l.GK_Faces
            log(l:GetText(), "faces", #f, f[1] and ("gap %.1f depth %.0f/%.0f"):format(f[1].pos:Distance(f[2].pos), f[1].depth, f[2].depth) or "none")
        end
        local l = labels[1]
        local f = IsValid(l) and l.GK_Faces
        if not f or #f < 2 then log("no faces to look at") print("[GKTEST] DONE") return end
        -- On the take-off block, a step back from its edge, looking at the far face.
        P:SetPos(f[1].pos - f[1].n * 60 + Vector(0, 0, 2))
        P:SetEyeAngles((f[2].pos - Vector(0, 0, 30) - P:EyePos()):Angle())
        timer.Simple(1.5, function() shot(P, "1_across") end)
        timer.Simple(3, function()
            P:SetPos(f[2].pos - f[2].n * 60 + Vector(0, 0, 2))
            P:SetEyeAngles((f[1].pos - Vector(0, 0, 30) - P:EyePos()):Angle())
        end)
        timer.Simple(4.5, function() shot(P, "2_back") end)
        timer.Simple(5, function()
            -- From the side, so both faces show.
            local mid = (f[1].pos + f[2].pos) / 2
            local side = f[1].n:Angle():Right()
            P:SetPos(mid + side * 260 + Vector(0, 0, 10))
            P:SetEyeAngles((mid - Vector(0, 0, 30) - P:EyePos()):Angle())
        end)
        timer.Simple(6.5, function() shot(P, "3_side") end)
        timer.Simple(8, function() print("[GKTEST] DONE") end)
        timer.Simple(9, function() game.ConsoleCommand("quit\n") end)
    end)
end)
