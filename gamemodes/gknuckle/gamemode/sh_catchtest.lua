-- Click-catching a roach and the explosive rod's flight, by numbers (gm_construct).
-- Only runs when data/gknuckle/catchtest.txt exists. Logs "[GKCATCH]"; no screenshots.
if not file.Exists("gknuckle/catchtest.txt", "DATA") then return end
local function log(...) print("[GKCATCH]", ...) end

if CLIENT then
    local clickFrames, button = 0, 0
    net.Receive("gk_catchtest", function()
        local what = net.ReadString()
        if what == "click" then
            -- A real click through the input system (+attack, then -attack).
            local cmdName = net.ReadString() == "l" and "attack" or "attack2"
            log("client: grab cue showing before the click", tostring(GK.GrabCue and GK.GrabCue(LocalPlayer(), LocalPlayer():GetEyeTrace())))
            RunConsoleCommand("+" .. cmdName)
            timer.Simple(0.15, function() RunConsoleCommand("-" .. cmdName) end)
        elseif what == "rod" then
            hook.Add("PostDrawTranslucentRenderables", "GK_CatchTestRod", function(depth, sky)
                if depth or sky then return end
                hook.Remove("PostDrawTranslucentRenderables", "GK_CatchTestRod")
                local n, ok = 0, 0
                for _, e in ipairs(ents.FindByClass("gk_rebar_thrown")) do
                    n = n + 1
                    if pcall(e.Draw, e) then ok = ok + 1 end
                end
                log("client: rods in flight", n, "drawn with the glow, no errors", ok)
            end)
        end
    end)
    hook.Add("CreateMove", "GK_CatchTestClick", function(cmd)
        if clickFrames > 0 then
            clickFrames = clickFrames - 1
            -- Down for two frames, up on the last: one fresh click.
            if clickFrames > 0 then cmd:SetButtons(bit.bor(cmd:GetButtons(), button)) end
        end
    end)
    return
end
util.AddNetworkString("gk_catchtest")

local function send(P, what, arg) net.Start("gk_catchtest") net.WriteString(what) net.WriteString(arg or "") net.Send(P) end
local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, roach

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {} GK.Inv.Sync(P)
    for _, e in ipairs(ents.FindInSphere(P:GetPos(), 400)) do if e.GKItemClass then e:Remove() end end -- nothing else to grab
    -- A gold roach on the floor just in front of us, and look at it.
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    roach = GK.SpawnRoach("gold", P:GetPos() + fwd * 70 + Vector(0, 0, 2))
    log("roach spawned", tostring(IsValid(roach)))
end)
step(0.6, function()
    if IsValid(roach) then roach.GK_Target = nil P:SetEyeAngles((roach:WorldSpaceCenter() - P:GetShootPos()):Angle()) end
end)
step(0.1, function()
    if IsValid(roach) then P:SetEyeAngles((roach:WorldSpaceCenter() - P:GetShootPos()):Angle()) end
    log("aiming: roach", math.floor(IsValid(roach) and roach:GetPos():Distance(P:GetShootPos()) or -1), "u away, in the cone", tostring(IsValid(roach) and (roach:WorldSpaceCenter() - P:GetShootPos()):GetNormalized():Dot(P:GetAimVector()) > 0.82))
    send(P, "click", "l")
end)
step(0.8, function()
    local h = GK.Inv.HandItem(P, "l")
    log("clicked at it with the left hand: holding", tostring(h and h.class), "(expect roach)", "roach left on the floor", tostring(IsValid(roach) and not roach.GK_Dead and roach:GetNoDraw() == false))
end)
-- An explosive rod thrown straight up: it whistles and glows on the way.
step(0.5, function()
    local inv = GK.Inv.Get(P) inv.slots = {} GK.Inv.Sync(P)
    P:SetEyeAngles(Angle(-89, P:EyeAngles().y, 0))
    local bar = GK.ThrowRebar(P, "explosive")
    P.GK_TestRod = bar
end)
step(0.25, function()
    local bar = P.GK_TestRod
    log("rod in flight", tostring(IsValid(bar)), "whistle playing", tostring(IsValid(bar) and bar.GK_Whistle ~= nil and bar.GK_Whistle:IsPlaying()))
    send(P, "rod")
end)
step(1.5, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_CatchTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_CatchTest")
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
