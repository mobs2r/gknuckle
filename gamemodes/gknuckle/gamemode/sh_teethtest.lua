-- TEETH test (gk_style). Only runs when data/gknuckle/teethtest.txt exists:
-- a solo Habitation run; TEETH should dig up once the Mass is rising, hunt
-- and swipe, shy from a flare and burrow away, and shrug off damage.
-- Logs "[GKTEETH]", saves data/gknuckle/teeth_*.jpg, ends with "[GKTEST] DONE".
if not file.Exists("gknuckle/teethtest.txt", "DATA") then return end
local function log(...) print("[GKTEETH]", ...) end

if CLIENT then
    net.Receive("gk_teethtest", function()
        local name = net.ReadString()
        hook.Add("PostRender", "GK_TeethShot", function()
            hook.Remove("PostRender", "GK_TeethShot")
            file.Write("gknuckle/teeth_" .. name .. ".jpg", render.Capture({ format = "jpeg", quality = 85, x = 0, y = 0, w = ScrW(), h = ScrH() }))
        end)
    end)
    return
end
util.AddNetworkString("gk_teethtest")
local function shot(P, name) net.Start("gk_teethtest") net.WriteString(name) net.Send(P) end

local steps, P, A, T = {}, nil, nil, nil
hook.Add("EntityRemoved", "GK_TeethTestGone", function(e)
    if e:GetClass() ~= "gk_teeth" then return end
    log("TEETH removed: arena running", tostring(GK.Rounds.arenas[1] ~= nil), "you alive", tostring(IsValid(P) and P:Alive()), "your arena", IsValid(P) and GK.ArenaOf(P))
    print(debug.traceback())
end)
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local STATE = { "emerge", "hunt", "swipe", "afraid", "gone", "eat" }
local function st() return IsValid(T) and STATE[T:GetTState()] or "none" end

step(0, function()
    RunConsoleCommand("gk_tube_rise", "0")
    RunConsoleCommand("gk_mass_speed", "0") RunConsoleCommand("gk_mass_accel", "0") -- the gas starts but stays put
    GK.StageRegion = function() return GetConVar("gk_test_region") and GetConVar("gk_test_region"):GetString() ~= "" and GetConVar("gk_test_region"):GetString() or "Region_Habitation_Campaign" end
    -- Campaign Habitation runs must reach the service shaft, every seed.
    local hits = 0
    for seed = 1, 12 do
        local pieces = GK.GenerateRun("Region_Habitation_Campaign", seed, 9000) or {}
        local has = false
        for _, pc in ipairs(pieces) do if pc == "m3_habitation_shaft_to_pier" then has = true end end
        if has then hits = hits + 1 end
    end
    log("campaign Habitation runs reaching the service shaft:", hits, "of 12 seeds (expect 12)")
    -- Every run region: rooms climb (no room starts below the one before) and fit the shaft.
    local lay = GK.Arena.Layout()[1]
    for _, region in ipairs(GK.Arena.RunRegions) do
        local worst, tallest, flat = 0, 0, 0
        for seed = 1, 8 do
            local pieces = GK.GenerateRun(region, seed, 2 * lay.half - 128)
            if pieces and #pieces > 0 then
                local plan, mins, maxs = GK.PlanRun(pieces, Vector(0, 0, 0))
                tallest = math.max(tallest, maxs.z - mins.z)
                for k = 2, #plan do
                    local dz = plan[k].pos.z - plan[k - 1].pos.z
                    if dz < -1 then worst = math.min(worst, dz) end
                    if math.abs(dz) < 1 then flat = flat + 1 end
                end
            end
        end
        log(("  %-32s tallest run %6.0f (shaft %6.0f)  rooms on the same level as the last %d  biggest drop %.0f"):format(region, tallest, lay.top - lay.bottom, flat, worst))
    end
    A = GK.StartArena(1, { P }, true)
    local names = {}
    for _, st in ipairs(A.info.plan) do names[#names + 1] = st.piece end
    log("run", A.info.region, "rooms:", table.concat(names, " "))
    for k, stp in ipairs(A.info.plan) do
        local lay = GK.LevelLayout(stp.piece)
        local b = lay.bounds
        log("  plan", k, stp.piece, "z", math.floor(stp.pos.z), "height", b and math.floor(b.maxs[3] - b.mins[3]) or "-",
            "entrance", tostring(lay.entrances and lay.entrances[1] and lay.entrances[1].pos[3]), "exit", tostring(lay.exits and lay.exits[1] and lay.exits[1].pos[3]))
    end
    log("  spawn z", math.floor(A.info.spawn.z), "top z", math.floor(A.info.top))
end)
step(1, function()
    -- Climb up through the run (streaming rooms in) until the service shaft exists.
    P:SetMoveType(MOVETYPE_NOCLIP)
    local info = A.info
    for k = 1, #info.plan do
        timer.Simple(k * 0.4, function()
            if info.teethRoom then return end
            local z = info.spawn.z + (info.top - info.spawn.z) * k / #info.plan
            P:SetPos(Vector(info.spawn.x, info.spawn.y, z))
            GK.Arena.Stream(1)
        end)
    end
end)
step(8, function()
    local info = A.info
    local built = {}
    for k = 1, #info.plan do built[#built + 1] = tostring(info.rooms[k] and true or info.rooms[k]) end
    log("rooms built:", table.concat(built, " "), "you z", math.floor(P:GetPos().z), "top", math.floor(info.top), "alive", tostring(P:Alive()), "arena", GK.ArenaOf(P))
    log("service shaft in this run:", tostring(info.teethRoom), "of", #info.plan, "rooms; TEETH before entering it:", tostring(IsValid(A.teeth)), "(expect false)")
    local room = info.teethRoom and info.rooms[info.teethRoom]
    if not room then return end
    local b = room.bounds
    P:SetPos(Vector((b.mins.x + b.maxs.x) / 2, (b.mins.y + b.maxs.y) / 2, b.mins.z + 300))
end)
step(2, function()
    T = A.teeth
    log("TEETH in the shaft:", tostring(IsValid(T)), "model", IsValid(T) and T:GetModel() or "-", "state", st(),
        "below you by", IsValid(T) and math.floor(P:GetPos().z - T:GetPos().z) or "-")
    if not IsValid(T) then return end
    P:SetEyeAngles((T:WorldSpaceCenter() - P:EyePos()):Angle())
    P:SetHealth(100)
end)
step(0.6, function() shot(P, "1_emerging") end)
step(3.5, function()
    log("after 4 s: state", st(), "distance", IsValid(T) and math.floor(T:GetPos():Distance(P:GetPos())) or "-", "your health", P:Health(), "(expect hurt by a swipe)")
    shot(P, "2_hunting")
end)
step(1, function()
    -- A burning flare at its feet: it shies back, and after 3 s it burrows.
    if not IsValid(T) then return end
    P:SetHealth(100)
    local f = ents.Create("gk_flare")
    if IsValid(f) then
        f:SetPos(T:GetPos() + Vector(0, 0, 20)) f:Spawn() P.GK_TestFlare = f
        if IsValid(f:GetPhysicsObject()) then f:GetPhysicsObject():EnableMotion(false) end -- held there burning
    end
end)
step(0.6, function() log("by a flare: state", st(), "(expect afraid)") end)
step(3.5, function() log("3.5 s in the light: state", st(), "(expect gone, burrowed)") if IsValid(P.GK_TestFlare) then P.GK_TestFlare:Remove() end end)
step(14, function()
    log("back again: state", st(), "(expect emerge or hunt)")
end)
step(3, function()
    if not IsValid(T) then return end
    -- Leave the shaft: it sinks back into the walls.
    local room = A.info.rooms[A.info.teethRoom]
    P.GK_InShaftPos = P:GetPos()
    P:SetPos(Vector(P:GetPos().x, P:GetPos().y, room.bounds.maxs.z + 600))
end)
step(2.5, function() log("you left the shaft: state", st(), "(expect gone)") P:SetPos(P.GK_InShaftPos) end)
step(6, function() log("back in the shaft: state", st(), "(expect emerge, hunt or swipe)") end)
step(1, function()
    if not IsValid(T) then return end
    local d = DamageInfo() d:SetDamage(500) d:SetDamageType(DMG_BULLET) d:SetAttacker(P) d:SetInflictor(P)
    T:TakeDamageInfo(d)
    log("shot for 500: still there", tostring(IsValid(T)), "state", st(), "(expect gone: it can't die, it burrows)")
end)
step(0.2, function() RunConsoleCommand("gk_mass_speed", "39.4") RunConsoleCommand("gk_mass_accel", "0.0394") end)
step(0.5, function() print("[GKTEST] DONE") end)
step(1, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_TeethTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_TeethTest")
    P = ply
    local t = 12
    for _, s in ipairs(steps) do
        t = t + s[1]
        timer.Simple(t, function()
            local ok, err = pcall(s[2])
            if not ok then log("STEP ERROR", err) end
        end)
    end
end)
