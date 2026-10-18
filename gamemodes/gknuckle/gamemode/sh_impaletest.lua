-- Automated impalement test. Only runs when data/gknuckle/impaletest.txt
-- exists: spikes forwards/backwards, weight, look clamp, escapes, and thrown
-- rebar on a bot (body pin, legs, head). Logs "[GKIMPALE]" lines (-condebug),
-- takes screenshots, then quits.

if not file.Exists("gknuckle/impaletest.txt", "DATA") then return end

local function log(...) print("[GKIMPALE]", ...) end

if CLIENT then
    local held, untilT = 0, 0
    net.Receive("gk_impaletest", function()
        local kind = net.ReadString()
        if kind == "input" then
            held = net.ReadUInt(32)
            untilT = CurTime() + net.ReadFloat()
        elseif kind == "shot" then
            do end
        elseif kind == "turn" then
            -- Try to look way past the cone, like a player flicking the mouse.
            local a = LocalPlayer():EyeAngles()
            a.y = a.y + net.ReadFloat()
            LocalPlayer():SetEyeAngles(a)
            timer.Simple(0.3, function()
                print("[GKIMPALE]", "client eye after turn", tostring(LocalPlayer():EyeAngles()),
                    "centre", tostring(LocalPlayer():GetNW2Angle("gk_impale_look")))
            end)
        end
    end)
    hook.Add("CreateMove", "GK_ImpaleTestInput", function(cmd)
        if CurTime() < untilT then cmd:SetButtons(bit.bor(cmd:GetButtons(), held)) end
    end)
    return
end

util.AddNetworkString("gk_impaletest")

local function send(ply, kind, fn)
    net.Start("gk_impaletest") net.WriteString(kind) if fn then fn() end net.Send(ply)
end
local function press(ply, buttons, dur) send(ply, "input", function() net.WriteUInt(buttons, 32) net.WriteFloat(dur) end) end
local function shot(ply) send(ply, "shot") end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end

local P, bot, spike, ground, home, botSpot, hits = nil, nil, nil, nil, nil, nil, {}

local function st(ply)
    return ("impaled=%s back=%s prog=%.2f hp=%d legs=%s alive=%s pos=%s weight=%d need=%.0f"):format(
        tostring(GK.IsImpaled(ply)), tostring(GK.ImpaledBack(ply)), ply:GetNW2Float("gk_impale_progress", 0),
        ply:Health(), tostring(GK.HasLegs(ply)), tostring(ply:Alive()), tostring(ply:GetPos()),
        GK.CarriedWeight(ply), GK.ImpaleSpeed(ply))
end

local function clearInv(ply)
    local inv = GK.Inv.Get(ply)
    inv.bag, inv.slots = {}, {}
    GK.Inv.Sync(ply)
end

local function reset(ply)
    GK.Unimpale(ply)
    ply.GK_ImpaleImmune = 0
    ply.GK_BleedUntil = 0
    ply:SetHealth(100)
    ply:SetLocalVelocity(vector_origin)
    ply:SetNW2Float("gk_chip_offline_until", 0)
end

-- Drop P onto the spike at `speed`, with the bar `side` of them ("front"/"back").
-- Stunned unless awake = true (only the helpless go onto spikes).
local function dropOnSpike(side, speed, awake)
    reset(P)
    if not awake then P:SetNW2Float("gk_chip_offline_until", CurTime() + 30) end
    local face = Angle(0, 0, 0):Forward()
    P:SetEyeAngles(Angle(0, 0, 0))
    local off = side == "front" and -face * 6 or face * 6
    P:SetPos(spike:GetPos() + Vector(-200, 0, 0)) -- leave the trigger first so it sees a fresh touch
    timer.Simple(0.3, function()
        P:SetPos(spike:GetPos() + off + Vector(0, 0, 70))
        timer.Simple(0, function() P:SetLocalVelocity(Vector(0, 0, -speed)) end)
    end)
end

hook.Add("GK_RebarExplode", "GK_ImpaleTest", function(pos, how) log("explosion", how, tostring(pos), "P", IsValid(P) and tostring(P:GetPos())) end)
hook.Add("GK_RebarHit", "GK_ImpaleTest", function(ply, res, _, tr)
    hits[#hits + 1] = res
    log("rebar hit", ply:Nick(), res, "hitgroup", tr.HitGroup, "hitpos", tostring(tr.HitPos), "ply pos", tostring(ply:GetPos()), "hp", ply:Health())
end)

step(0, function()
    P = player.GetHumans()[1]
    -- The row of try-out items at spawn would get in the way of these tests.
    local row = 0
    for _, e in ipairs(ents.FindByClass("gk_item")) do if e.GK_Starter then row = row + 1 e:Remove() end end
    log("starter item row", row)
    log("map", game.GetMap(), "model", tostring(util.IsValidModel("models/gknuckle/items/rebar.mdl")), "pvp", GetConVarString("sbox_playershouldtakedamage"), "god", GetConVarString("sbox_godmode"))
    local tr = util.TraceLine({ start = P:GetPos() + Vector(0, 0, 10), endpos = P:GetPos() - Vector(0, 0, 200), filter = P })
    ground = tr.HitPos
    home = P:GetPos()
    spike = ents.Create("gk_spike")
    spike:SetPos(ground) -- where P spawned, so it's open space
    P:SetPos(ground + Vector(-200, 0, 0))
    spike:Spawn()
    log("spike at", tostring(spike:GetPos()), "fwd", tostring(spike:GetForward()))
    clearInv(P)
    RunConsoleCommand("bot")
end)

-- 0. Awake (chip online): a hard landing doesn't impale; you catch yourself.
step(2, function() dropOnSpike("front", 400, true) end)
step(1, function() log("T0 awake hard landing", st(P)) end)

-- 1. Stunned. Slow landing, empty-handed: should NOT impale. Same landing loaded up: should.
step(0.5, function() dropOnSpike("front", 180) end)
step(1, function() log("T1 slow empty", st(P)) end)
step(0.5, function()
    for _ = 1, 8 do GK.Inv.Give(P, "brick") end
    GK.Inv.Give(P, "revolver")
    log("T1 loaded need", ("%.0f"):format(GK.ImpaleSpeed(P)))
    dropOnSpike("front", 180)
end)
step(1, function() log("T1 slow loaded", st(P)) end)

-- 2. Forwards: look clamp, then F kicks off.
step(0.5, function() clearInv(P) dropOnSpike("front", 400) end)
step(1, function()
    log("T2 forward", st(P), "look", tostring(P:GetNW2Angle("gk_impale_look")))
    shot(P)
    send(P, "turn", function() net.WriteFloat(150) end)
end)
step(1, function()
    local c = P:GetNW2Angle("gk_impale_look")
    log("T2 server eye after turn", tostring(P:EyeAngles()), "yaw off centre",
        ("%.0f"):format(math.AngleDifference(P:EyeAngles().y, c.y)))
    press(P, IN_JUMP, 1)
end)
step(1.1, function() log("T2 after 1s jump hold", st(P)) P:SetEyeAngles(Angle(70, 0, 0)) end)
step(0.5, function() shot(P) end)
step(0.2, function() GK.Kick(P) log("T2 after kick", st(P)) end)

-- 3. Backwards with a gun in one hand and a heavy bag.
step(1.5, function()
    clearInv(P)
    for _ = 1, 6 do GK.Inv.Give(P, "brick") end
    GK.Inv.Give(P, "revolver")
    for _, it in ipairs(GK.Inv.Get(P).bag) do if it.class == "revolver" then GK.Inv.Move(P, it.id, "hand_r") break end end
    dropOnSpike("back", 400)
end)
step(1, function()
    P:SetNW2Float("gk_chip_offline_until", 0) -- chip back up, so the hands can pull
    log("T3 back", st(P)) shot(P) press(P, IN_JUMP, 1)
end)
step(1.1, function() log("T3 jump does nothing", st(P)) GK.Kick(P) log("T3 kick does nothing", st(P)) press(P, bit.bor(IN_ATTACK, IN_ATTACK2), 2) end)
step(2.1, function() log("T3 one empty hand 2s (gun in right)", st(P)) GK.Inv.DropHand(P) press(P, bit.bor(IN_ATTACK, IN_ATTACK2), 2) end)
step(0.3, function() shot(P) end)
step(1.8, function() log("T3 two hands 2s, heavy bag", st(P)) clearInv(P) press(P, bit.bor(IN_ATTACK, IN_ATTACK2), 4) end)
step(2, function() log("T3 two hands 2s, empty", st(P)) end)
step(2.1, function() log("T3 end", st(P), "bleeding", tostring((P.GK_BleedUntil or 0) > CurTime())) end)

-- 5. Ragdolled (kicked / bricked) and coming down on the spike point.
step(0.5, function()
    reset(P)
    P:SetPos(spike:GetPos() + Vector(-200, 0, 0))
end)
step(0.5, function()
    P:SetPos(spike:GetPos() + Vector(0, 0, 90))
    P:SetEyeAngles(Angle(0, 0, 0))
    GK.Ragdoll(P, Vector(0, 0, -450))
end)
step(1.2, function() log("T5 ragdoll onto spike", st(P), "ragdolled", tostring(GK.IsRagdolled(P))) shot(P) end)
step(0.3, function() reset(P) if GK.IsRagdolled(P) then GK.Unragdoll(P) end end)

-- 4. Thrown rebar at a bot standing in front of a wall.
local wallPos, aimAt
step(1, function()
    if IsValid(spike) then spike:Remove() end
    reset(P)
    bot = player.GetBots()[1]
    if not IsValid(bot) then log("T4 SKIP no bot") return end
    -- Find a wall: walk directions from the start until one is 200-600u away.
    local start = home + Vector(0, 0, 40)
    for yaw = 0, 345, 15 do
        local dir = Angle(0, yaw, 0):Forward()
        local tr = util.TraceLine({ start = start, endpos = start + dir * 700, mask = MASK_SOLID_BRUSHONLY })
        if tr.Hit and tr.Fraction * 700 > 250 and math.abs(tr.HitNormal.z) < 0.2 then
            wallPos = tr.HitPos
            botSpot = tr.HitPos - dir * 40 - Vector(0, 0, 40)
            bot:SetPos(botSpot)
            bot:SetEyeAngles(Angle(0, yaw + 180, 0))
            P:SetPos(tr.HitPos - dir * 260 - Vector(0, 0, 40))
            break
        end
    end
    log("T4 wall", tostring(wallPos), "bot", tostring(bot:GetPos()))
    clearInv(P)
    GK.Inv.Give(P, "rebar")
    for _, it in ipairs(GK.Inv.Get(P).bag) do if it.class == "rebar" then it.data.count = 6 GK.Inv.Move(P, it.id, "hand_r") break end end
end)
local function aim(pos) P:SetEyeAngles((pos - P:GetShootPos()):Angle()) end
-- Bots drift; put it back on its mark and hold it there before each throw.
local function placeBot()
    if not IsValid(bot) or not botSpot then return end
    bot:Freeze(false)
    bot:SetPos(botSpot)
    bot:SetLocalVelocity(vector_origin)
    bot:Freeze(true)
end
step(0.5, function() if IsValid(bot) then placeBot() aim(botSpot + Vector(0, 0, 42)) end end)
step(0.5, function() log("throw from", st(P), tostring(P:GetShootPos()), "aim", tostring(P:GetAimVector()), "bot", IsValid(bot) and tostring(bot:GetPos())) GK.Inv.Use(P, "r") end)
step(0.5, function()
    if not IsValid(bot) then return end
    log("T4 body", st(bot), "pins", #ents.FindByClass("gk_rebar_hold"))
    shot(P)
end)
step(0.5, function() if IsValid(bot) then reset(bot) log("T4 bot freed", st(bot)) end end)
step(0.5, function() if IsValid(bot) then placeBot() aim(botSpot + Vector(0, 0, 12)) end end)
step(0.5, function() log("throw from", st(P), tostring(P:GetShootPos()), "aim", tostring(P:GetAimVector()), "bot", IsValid(bot) and tostring(bot:GetPos())) GK.Inv.Use(P, "r") end)
step(0.5, function() if IsValid(bot) then log("T4 legs", st(bot)) end end)
step(0.5, function() if IsValid(bot) then reset(bot) placeBot() aim(botSpot + Vector(0, 0, 66)) end end)
step(0.5, function() log("throw from", st(P), tostring(P:GetShootPos()), "aim", tostring(P:GetAimVector()), "bot", IsValid(bot) and tostring(bot:GetPos())) GK.Inv.Use(P, "r") end)
step(0.5, function() if IsValid(bot) then log("T4 head", st(bot), "gored", tostring(GK.IsGored(bot))) end shot(P) end)
-- Into the wall: sticks as a handhold.
step(1, function()
    if IsValid(bot) then bot:SetPos(home) end -- out of the way
    if wallPos then aim(wallPos + Vector(0, 0, 30)) end
end)
step(0.5, function()
    local before = #ents.FindByClass("gk_rebar_hold")
    GK.Inv.Use(P, "r")
    timer.Simple(0.4, function() log("T4 wall stick handholds", before, "->", #ents.FindByClass("gk_rebar_hold")) end)
end)
step(1, function() shot(P) log("hits", table.concat(hits, ",")) end)
-- Close look at the newest stuck rebar (texture / orientation check).
step(0.5, function()
    local bars = ents.FindByClass("gk_rebar_hold")
    local bar = bars[#bars]
    if IsValid(bar) then
        local mid = bar:GetPos() + bar:GetForward() * 18
        P:SetPos(mid + bar:GetRight() * 45 - Vector(0, 0, 50))
        aim(mid)
        log("closeup bar fwd", tostring(bar:GetForward()))
    end
end)
step(1, function() shot(P) end)

-- 6. Revolver: centred, kicks, legs then head.
step(0.5, function()
    if IsValid(bot) then bot:Freeze(false) bot:Spawn() end
    clearInv(P)
    GK.Inv.Give(P, "revolver")
    for _, it in ipairs(GK.Inv.Get(P).bag) do if it.class == "revolver" then GK.Inv.Move(P, it.id, "hand_r") break end end
    if wallPos then P:SetPos(botSpot - (wallPos - botSpot):GetNormalized() * 200) end
end)
step(0.5, function() if IsValid(bot) then placeBot() aim(botSpot + Vector(0, 0, 14)) end end)
step(0.5, function()
    local before = P:EyeAngles().p
    GK.Inv.Use(P, "r")
    timer.Simple(0.1, function() log("T6 recoil pitch", ("%.1f -> %.1f"):format(before, P:EyeAngles().p), "clip", GK.Inv.HandItem(P, "r").data.clip) end)
    shot(P)
end)
step(0.6, function() if IsValid(bot) then log("T6 legs shot", st(bot)) placeBot() aim(botSpot + Vector(0, 0, 66)) end end)
step(0.8, function() GK.Inv.Use(P, "r") end)
step(0.5, function() if IsValid(bot) then log("T6 head shot", st(bot), "gored", tostring(GK.IsGored(bot))) end end)
step(0.1, function()
    local it = GK.Inv.HandItem(P, "r")
    log("T6 ammo", it.data.clip, "/", it.data.ammo)
end)

-- 7. Vending machine: press the rebar button, it drops a real rebar into the tray.
local vendor
step(0.5, function()
    vendor = ents.FindByClass("gk_vendor")[1]
    if not IsValid(vendor) then log("T7 SKIP no vendor") return end
    clearInv(P)
    log("T7 vendor", vendor:GetModel(), tostring(vendor:GetPos()), "stock", vendor:StockSlot(1).name, vendor:StockSlot(2).name, vendor:StockSlot(3).name)
    local front = vendor:GetForward() -- the model faces +X
    P:SetPos(vendor:GetPos() + front * 110)
    aim(vendor:LocalToWorld(Vector(32.6, -0.4, 67))) -- WK slot 2
end)
step(0.8, function() shot(P) end)
-- All four sides of the machine, for comparing with White Knuckle's.
for i, yaw in ipairs({ 90, 180, 270, 0 }) do
    step(0.6, function()
        if not IsValid(vendor) then return end
        local dir = Angle(0, vendor:GetAngles().y + yaw, 0):Forward()
        P:SetPos(vendor:GetPos() + dir * 130)
        aim(vendor:GetPos() + Vector(0, 0, 60))
        log("T7 side shot", yaw)
    end)
    step(0.6, function() shot(P) end)
end
step(0.3, function()
    if not IsValid(vendor) then return end
    P:SetPos(vendor:GetPos() + vendor:GetForward() * 110)
    aim(vendor:LocalToWorld(Vector(32.6, -0.4, 67)))
end)
step(0.8, function()
    if not IsValid(vendor) then return end
    local before = #ents.FindByClass("gk_item")
    local tr = P:GetEyeTrace()
    log("T7 eye trace", tostring(tr.Entity), "local", tostring(vendor:WorldToLocal(tr.HitPos)))
    vendor:Use(P)
    timer.Simple(1.6, function()
        local items = {}
        for _, e in ipairs(ents.FindInSphere(vendor:GetPos(), 120)) do
            if e:GetClass() == "gk_item" then items[#items + 1] = e.GKItemClass .. "@" .. ("%.0f"):format(e:GetPos():Distance(vendor:GetPos())) end
        end
        log("T7 dispensed", table.concat(items, ","), "items before", before)
    end)
end)
step(2, function() shot(P) end)

-- 8. The new items.
local function hand(class, side, data)
    side = side or "r"
    local inv = GK.Inv.Get(P)
    inv.slots["hand_" .. side] = nil
    GK.Inv.Give(P, class, data)
    for _, it in ipairs(inv.bag) do if it.class == class then GK.Inv.Move(P, it.id, "hand_" .. side) break end end
    return GK.Inv.HandItem(P, side)
end
local wallSpot
step(0.5, function()
    clearInv(P) reset(P)
    if IsValid(bot) then bot:Freeze(false) bot:Spawn() bot:SetPos(home + Vector(0, 0, 10)) bot:Freeze(true) end -- out of the way
    -- Stand 60u from the wall used in T4, facing it.
    if wallPos and botSpot then
        local into = (wallPos - botSpot) into.z = 0 into:Normalize()
        wallSpot = wallPos - into * 60 - Vector(0, 0, 40)
        P:SetPos(wallSpot)
        aim(wallPos + Vector(0, 0, 20))
    end
    hand("grenade", "r") hand("injector", "l")
end)
step(0.8, function() shot(P) log("T8 held grenade R + injector L", "palm", tostring(GK.HandPalm ~= nil)) end)
step(0.2, function() GK.Inv.Use(P, "l") end)
step(0.8, function() log("T8 injector", "injected", tostring(GK.HasBuff(P, "injected")), "jump", P:GetJumpPower()) end)
step(0.2, function() hand("grub", "l") GK.Inv.Use(P, "l") end)
step(0.6, function()
    log("T8 grub", "gooped", tostring(GK.HasBuff(P, "gooped")))
    GK.SetStamina(P, 0)
    P:SelectWeapon("gk_mind")
    if wallPos then aim(wallPos + Vector(0, 0, 40)) end
    press(P, IN_ATTACK, 2)
end)
step(1.5, function() log("T8 gooped grip at 0 stamina", "handL", P:GetNW2Int("gk_hand_l"), "anchor", tostring(P:GetNW2Bool("gk_anchor_l")), "stamina", GK.Stamina(P)) end)
step(0.8, function()
    P:SetNW2Float("gk_buff_gooped", 0)
    P:SetPos(wallSpot or P:GetPos())
    hand("piton", "r")
    if wallPos then aim(wallPos + Vector(0, 0, 10)) end
end)
step(0.5, function()
    local before = #ents.FindByClass("gk_piton_hold")
    GK.Inv.Use(P, "r")
    log("T8 piton without hammer", before, "->", #ents.FindByClass("gk_piton_hold"))
    hand("hammer", "l")
    GK.Inv.Use(P, "r")
    log("T8 piton with hammer", before, "->", #ents.FindByClass("gk_piton_hold"))
end)
step(0.5, function()
    hand("rebarrope", "r")
    if wallPos then aim(wallPos + Vector(0, 0, 120)) end
end)
step(0.5, function() GK.Inv.Use(P, "r") end)
step(0.6, function()
    local rope = ents.FindByClass("gk_rope")[1]
    log("T8 rope", tostring(rope), rope and tostring(rope:GetBottom()))
    if IsValid(rope) then aim((rope:GetPos() + rope:GetBottom()) / 2) end
end)
step(0.5, function()
    local g = GK.RopeGrip(P, 200)
    log("T8 rope grip point", tostring(g))
    shot(P)
end)
step(0.3, function()
    hand("rebarexplo", "r")
    if wallPos and wallSpot then
        local back = wallSpot - wallPos back.z = 0 back:Normalize()
        P:SetPos(wallSpot + back * 320) -- well clear of the blast
        aim(wallPos + Vector(0, 0, 60))
    end
end)
step(0.5, function() GK.Inv.Use(P, "r") end)
step(2, function() log("T8 explosive", "handholds now", #ents.FindByClass("gk_rebar_hold"), "P", st(P)) reset(P) end)
step(0.3, function()
    hand("battery", "r") GK.Inv.Use(P, "r")
end)
step(0.6, function()
    GK.ChipBurst(P:GetPos(), 200, 4, P)
    log("T8 battery shielded", tostring(GK.HasBuff(P, "shielded")), "chip online after stun", tostring(GK.IsChipOnline(P)))
    P:SetHealth(40)
    hand("bandage", "r") GK.Inv.Use(P, "r")
end)
step(2, function() log("T8 bandage hp", P:Health()) end)
step(0.5, function() hand("flaregun", "r") end)
step(0.5, function() GK.Inv.Use(P, "r") end)
step(0.3, function() log("T8 flares", #ents.FindByClass("gk_flare")) shot(P) end)
step(0.5, function()
    if IsValid(bot) then bot:Freeze(false) placeBot() bot:Freeze(false) local flat = wallPos - botSpot flat.z = 0 P:SetPos(botSpot - flat:GetNormalized() * 55) aim(botSpot + Vector(0, 0, 40)) end
    hand("crowbar", "r")
end)
step(0.5, function() if IsValid(bot) then aim(bot:WorldSpaceCenter()) end end)
step(0.5, function() log("T8 before swing P", st(P), "onfire", tostring(P:IsOnFire()), "ragdoll", tostring(GK.IsRagdolled(P)), "dist to bot", IsValid(bot) and ("%.0f"):format(P:GetPos():Distance(bot:GetPos())), "aim", tostring(P:GetAimVector())) GK.Inv.Use(P, "r") end)
step(0.3, function() if IsValid(bot) then log("T8 crowbar", st(bot), "ragdolled", tostring(GK.IsRagdolled(bot))) end end)
step(0.3, function() hand("blinkeye", "r") P:SetEyeAngles(Angle(0, P:EyeAngles().y + 180, 0)) end)
step(0.5, function()
    local before = P:GetPos()
    log("T8 before blink", st(P), "item", tostring(GK.Inv.HandItem(P, "r") and GK.Inv.HandItem(P, "r").class))
    GK.Inv.Use(P, "r")
    log("T8 blink moved", ("%.0f"):format(P:GetPos():Distance(before)))
end)
step(0.5, function()
    -- The row of test items laid out at spawn.
    local items = ents.FindByClass("gk_item")
    log("T8 items in world", #items)
    local s = ents.FindByClass("info_player_start")[1]
    if s then P:SetPos(s:GetPos()) end
end)
step(2, function() shot(P) log("DONE") end)
step(2, function() game.ConsoleCommand("quit\n") end)

hook.Add("PlayerInitialSpawn", "GK_ImpaleTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_ImpaleTest")
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
