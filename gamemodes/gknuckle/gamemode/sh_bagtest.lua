-- Gas bag check: it drifts, homes in on a climber within 6 m, and bursts
-- within 3 m. Only runs when data/gknuckle/bagtest.txt exists (on gk_style,
-- whose hub hall is open). Logs "[GKBAG]" lines; no screenshots.
if not file.Exists("gknuckle/bagtest.txt", "DATA") then return end
local function log(...) print("[GKBAG]", ...) end
if CLIENT then
    local held, untilT = 0, 0
    net.Receive("gk_bagtest_press", function() held = net.ReadUInt(32) untilT = CurTime() + net.ReadFloat() end)
    hook.Add("CreateMove", "GK_BagTestInput", function(cmd)
        if CurTime() < untilT then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), held))
            if bit.band(held, IN_FORWARD) ~= 0 then cmd:SetForwardMove(200) end
        end
    end)
    return
end
util.AddNetworkString("gk_bagtest_press")

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, bag, p0

step(0, function()
    P = player.GetHumans()[1]
    -- Above us in open air: straight up as far as is clear, then down a bit.
    local up = util.TraceLine({ start = P:EyePos(), endpos = P:EyePos() + Vector(0, 0, 600), mask = MASK_SOLID, filter = P })
    local pos = P:EyePos() + Vector(0, 0, math.min(170, (up.HitPos.z - P:EyePos().z) * 0.6)) + Angle(0, P:EyeAngles().y, 0):Forward() * 40
    bag = ents.Create("gk_gasbag")
    bag:SetPos(pos)
    bag:Spawn()
    p0 = bag:GetPos()
    log("spawned", math.floor(pos.z - P:GetPos().z), "u above us; in solid", tostring(bit.band(util.PointContents(pos), CONTENTS_SOLID) ~= 0))
end)
step(3, function() log("after 3 s: moved", math.floor(bag:GetPos():Distance(p0)), "to us", math.floor(bag:WorldSpaceCenter():Distance(P:WorldSpaceCenter())), "target", tostring(bag.GK_Target)) end)
step(5, function()
    log("after 8 s: valid", tostring(IsValid(bag)), "to us", IsValid(bag) and math.floor(bag:WorldSpaceCenter():Distance(P:WorldSpaceCenter())) or "burst", "player health", P:Health())
end)
-- A placed piton (now a box with no physics object) is still a handhold.
step(1, function()
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    local tr = util.TraceLine({ start = P:EyePos(), endpos = P:EyePos() + fwd * 3000, mask = MASK_SOLID_BRUSHONLY })
    P:SetPos(tr.HitPos - fwd * 60 - Vector(0, 0, 64))
    local pt = ents.Create("gk_piton_hold")
    pt:SetPos(tr.HitPos + tr.HitNormal * 4) pt:SetAngles(tr.HitNormal:Angle())
    pt:Spawn()
    P:SetEyeAngles((pt:GetPos() - P:EyePos()):Angle())
    local mind = P:GetWeapon("gk_mind")
    local look = P:GetEyeTrace()
    local g = IsValid(mind) and mind:TryGrip(P, "l")
    log("piton: eye trace hits it", tostring(look.Entity == pt), "grip", g and g.kind or "none", "on it", tostring(g and g.entity == pt), "hold time", tostring(pt:HoldTime()))
    pt:PopOut()
    log("popped: solid", pt:GetSolid(), "movetype", pt:GetMoveType())
end)
-- Icy and breakable WK holds through the mind-hands hold logic.
step(0.5, function()
    local piece = ents.FindByClass("gk_level_piece")[1]
    local icy = { kind = "icy", mins = Vector(0, 0, 0), maxs = Vector(8, 8, 8) }
    local brk = { kind = "breakable", mins = Vector(0, 0, 0), maxs = Vector(8, 8, 8) }
    local hi, hb = GK.HandholdSpecial(piece, icy), GK.HandholdSpecial(piece, brk)
    log("specials", hi and hi.kind, hi and hi.maxHold, hb and hb.kind, hb and hb.maxHold, "plain", tostring(GK.HandholdSpecial(piece, { mins = vector_origin, maxs = Vector(1, 1, 1) })))
    log("icy at 2 s lets go", tostring(GK.HoldTick(P, hi, 2) == true), "at 3.5 s", tostring(GK.HoldTick(P, hi, 3.5) == true))
    log("breakable at 1 s", tostring(GK.HoldTick(P, hb, 1) == true), "at 2 s", tostring(GK.HoldTick(P, hb, 2) == true), "broken", tostring(hb.broken))
end)
-- Falling trash down a chute above us.
step(0.5, function()
    P:SetHealth(100)
    local up = util.TraceLine({ start = P:EyePos(), endpos = P:EyePos() + Vector(0, 0, 900), mask = MASK_SOLID, filter = P })
    local ch = ents.Create("gk_trashchute")
    ch:SetPos(up.HitPos - Vector(0, 0, 20))
    ch:Spawn()
    log("chute", math.floor(up.HitPos.z - P:GetPos().z), "u above")
end)
step(12, function() log("after 12 s under the chute: health", P:Health(), "junk now", #ents.FindByClass("gk_trash")) end)
-- A run-room item (GK_Asleep): no physics, rests on the floor, still picked up by a hand.
step(0.5, function()
    local it = ents.Create("gk_item")
    it.GKItemClass = "beans" it.GK_Asleep = true
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    it:SetPos(P:GetPos() + fwd * 50 + Vector(0, 0, 20))
    it:Spawn()
    log("room item: physics", tostring(IsValid(it:GetPhysicsObject())), "height above our feet", math.floor(it:GetPos().z - P:GetPos().z), "model", it:GetModel())
    local ok = GK.Inv.PickupToHand(P, it, "l")
    log("picked up", tostring(ok), "hand", tostring(GK.Inv.HandItem(P, "l") and GK.Inv.HandItem(P, "l").class))
end)
-- Every hub ladder: walk into it and climb.
local ladders, lad
step(0.5, function() ladders = ents.FindByClass("gk_ladder") log("hub ladders", #ladders) end)
step(0.5, function()
    lad = ladders[1]
    if not IsValid(lad) then return end
    P:SetLocalVelocity(vector_origin)
    -- Stand on the open side of the ladder (its forward isn't the same way on every map ladder).
    local up = Vector(0, 0, 40)
    local out = lad:GetForward()
    local blk = util.TraceLine({ start = lad:GetPos() + up, endpos = lad:GetPos() + up + out * 60, mask = MASK_PLAYERSOLID })
    log("ladder front blocked", tostring(blk.Hit), blk.Hit and tostring(blk.Entity) or "", blk.Hit and math.floor(blk.Fraction * 60) or "")
    P:SetPos(lad:GetPos() + out * 60 + Vector(0, 0, 4))
    P:SetEyeAngles((-out):Angle())
    net.Start("gk_bagtest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.4) net.Send(P)
end)
step(1.6, function() if IsValid(lad) then log("ladder 1", tostring(lad:GetPos()), "rose", math.floor(P:GetPos().z - lad:GetPos().z), "on ladder", tostring(GK.OnLadder(P)), "dist", math.floor(P:GetPos():Distance(lad:GetPos()))) end end)
step(0.5, function()
    lad = ladders[2]
    if not IsValid(lad) then return end
    P:SetLocalVelocity(vector_origin)
    -- Stand on the open side of the ladder (its forward isn't the same way on every map ladder).
    local up = Vector(0, 0, 40)
    local out = lad:GetForward()
    local blk = util.TraceLine({ start = lad:GetPos() + up, endpos = lad:GetPos() + up + out * 60, mask = MASK_PLAYERSOLID })
    log("ladder front blocked", tostring(blk.Hit), blk.Hit and tostring(blk.Entity) or "", blk.Hit and math.floor(blk.Fraction * 60) or "")
    P:SetPos(lad:GetPos() + out * 60 + Vector(0, 0, 4))
    P:SetEyeAngles((-out):Angle())
    net.Start("gk_bagtest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.4) net.Send(P)
end)
step(1.6, function() if IsValid(lad) then log("ladder 2", tostring(lad:GetPos()), "rose", math.floor(P:GetPos().z - lad:GetPos().z), "on ladder", tostring(GK.OnLadder(P)), "dist", math.floor(P:GetPos():Distance(lad:GetPos()))) end end)
step(0.5, function()
    lad = ladders[3]
    if not IsValid(lad) then return end
    P:SetLocalVelocity(vector_origin)
    -- Stand on the open side of the ladder (its forward isn't the same way on every map ladder).
    local up = Vector(0, 0, 40)
    local out = lad:GetForward()
    local blk = util.TraceLine({ start = lad:GetPos() + up, endpos = lad:GetPos() + up + out * 60, mask = MASK_PLAYERSOLID })
    log("ladder front blocked", tostring(blk.Hit), blk.Hit and tostring(blk.Entity) or "", blk.Hit and math.floor(blk.Fraction * 60) or "")
    P:SetPos(lad:GetPos() + out * 60 + Vector(0, 0, 4))
    P:SetEyeAngles((-out):Angle())
    net.Start("gk_bagtest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.4) net.Send(P)
end)
step(1.6, function() if IsValid(lad) then log("ladder 3", tostring(lad:GetPos()), "rose", math.floor(P:GetPos().z - lad:GetPos().z), "on ladder", tostring(GK.OnLadder(P)), "dist", math.floor(P:GetPos():Distance(lad:GetPos()))) end end)
step(0.5, function()
    lad = ladders[4]
    if not IsValid(lad) then return end
    P:SetLocalVelocity(vector_origin)
    -- Stand on the open side of the ladder (its forward isn't the same way on every map ladder).
    local up = Vector(0, 0, 40)
    local out = lad:GetForward()
    local blk = util.TraceLine({ start = lad:GetPos() + up, endpos = lad:GetPos() + up + out * 60, mask = MASK_PLAYERSOLID })
    log("ladder front blocked", tostring(blk.Hit), blk.Hit and tostring(blk.Entity) or "", blk.Hit and math.floor(blk.Fraction * 60) or "")
    P:SetPos(lad:GetPos() + out * 60 + Vector(0, 0, 4))
    P:SetEyeAngles((-out):Angle())
    net.Start("gk_bagtest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.4) net.Send(P)
end)
step(1.6, function() if IsValid(lad) then log("ladder 4", tostring(lad:GetPos()), "rose", math.floor(P:GetPos().z - lad:GetPos().z), "on ladder", tostring(GK.OnLadder(P)), "dist", math.floor(P:GetPos():Distance(lad:GetPos()))) end end)
step(0.5, function()
    lad = ladders[5]
    if not IsValid(lad) then return end
    P:SetLocalVelocity(vector_origin)
    local up = Vector(0, 0, 40)
    local out = lad:GetForward()
    local blk = util.TraceLine({ start = lad:GetPos() + up, endpos = lad:GetPos() + up + out * 60, mask = MASK_PLAYERSOLID })
    log("ladder front blocked", tostring(blk.Hit), blk.Hit and tostring(blk.Entity) or "", blk.Hit and math.floor(blk.Fraction * 60) or "")
    P:SetPos(lad:GetPos() + out * 60 + Vector(0, 0, 4))
    P:SetEyeAngles((-out):Angle())
    net.Start("gk_bagtest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.4) net.Send(P)
end)
step(1.6, function() if IsValid(lad) then log("ladder 5", tostring(lad:GetPos()), "rose", math.floor(P:GetPos().z - lad:GetPos().z), "on ladder", tostring(GK.OnLadder(P)), "dist", math.floor(P:GetPos():Distance(lad:GetPos()))) end end)
step(0.5, function()
    lad = ladders[6]
    if not IsValid(lad) then return end
    P:SetLocalVelocity(vector_origin)
    local up = Vector(0, 0, 40)
    local out = lad:GetForward()
    local blk = util.TraceLine({ start = lad:GetPos() + up, endpos = lad:GetPos() + up + out * 60, mask = MASK_PLAYERSOLID })
    log("ladder front blocked", tostring(blk.Hit), blk.Hit and tostring(blk.Entity) or "", blk.Hit and math.floor(blk.Fraction * 60) or "")
    P:SetPos(lad:GetPos() + out * 60 + Vector(0, 0, 4))
    P:SetEyeAngles((-out):Angle())
    net.Start("gk_bagtest_press") net.WriteUInt(IN_FORWARD, 32) net.WriteFloat(1.4) net.Send(P)
end)
step(1.6, function() if IsValid(lad) then log("ladder 6", tostring(lad:GetPos()), "rose", math.floor(P:GetPos().z - lad:GetPos().z), "on ladder", tostring(GK.OnLadder(P)), "dist", math.floor(P:GetPos():Distance(lad:GetPos()))) end end)
-- A WK cryoshot platform: jump off it and it shatters, blasting you up.
local boostHold
step(0.5, function()
    local piece = ents.FindByClass("gk_level_piece")[1]
    local box = { kind = "icy", boost = true, mins = Vector(0, 0, 0), maxs = Vector(8, 8, 8) }
    boostHold = GK.HandholdSpecial(piece, box)
    P:SetPos(P:GetPos() + Vector(0, 0, 4)) P:SetLocalVelocity(vector_origin)
    GK.SetStamina(P, 100)
    net.Start("gk_bagtest_press") net.WriteUInt(IN_ATTACK, 32) net.WriteFloat(1.5) net.Send(P)
end)
step(0.5, function()
    local mind = P:GetWeapon("gk_mind")
    mind.Grips = mind.Grips or {}
    P:SetPos(P:GetPos() + Vector(0, 0, 200)) P:SetLocalVelocity(vector_origin)
    mind.Grips.l = { kind = "world", hitpos = P:EyePos() + P:GetAimVector() * 30, top = false, special = boostHold, boost = boostHold, since = CurTime() }
    P:SetEyeAngles(Angle(-20, P:EyeAngles().y, 0))
    net.Start("gk_bagtest_press") net.WriteUInt(bit.bor(IN_ATTACK, IN_JUMP), 32) net.WriteFloat(0.3) net.Send(P)
end)
local z0, zmax
step(0, function()
    z0 = P:GetPos().z zmax = z0 log("cryoshot: on ground at jump", tostring(P:OnGround()))
    local seen = 0
    hook.Add("Tick", "GK_BagBoostWatch", function()
        if boostHold.broken then
            seen = seen + 1
            if seen <= 4 then log("tick after shatter", seen, "vel z", math.floor(P:GetVelocity().z), "z", math.floor(P:GetPos().z - z0)) else hook.Remove("Tick", "GK_BagBoostWatch") end
        end
    end)
end)
for _ = 1, 12 do step(0.1, function() zmax = math.max(zmax, P:GetPos().z) end) end
step(0, function() log("cryoshot jump: rose", math.floor(zmax - z0), "shattered", tostring(boostHold.broken == true)) end)
-- Roaches the WK way: caught in a hand, pocketed, put in the bag, let go.
step(0.5, function()
    local inv = GK.Inv.Get(P)
    inv.slots.hand_l, inv.slots.hand_r, inv.slots.pocket_l, inv.slots.pocket_r = nil, nil, nil, nil
    GK.Inv.Sync(P)
    P:SetNW2Int("gk_roaches", 0) P:SetNW2Int("gk_bank", 0)
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    local r = GK.SpawnRoach("gold", P:GetPos() + fwd * 40 + Vector(0, 0, 4))
    local rp = GK.SpawnRoach("platinum", P:GetPos() + fwd * 50 + Vector(0, 0, 4))
    P.GK_PressSide = "l" r:Press(P)
    P.GK_PressSide = "r" rp:Press(P)
    log("caught: left", tostring(GK.Inv.HandItem(P, "l") and GK.Inv.HandItem(P, "l").class), "right", tostring(GK.Inv.HandItem(P, "r") and GK.Inv.HandItem(P, "r").class), "roach ents left", tostring(IsValid(r)), tostring(IsValid(rp)), "balance", GK.Roaches.Balance(P))
    GK.Inv.Pocket(P, "l")
    log("pocketed left: pocket", tostring(inv.slots.pocket_l and inv.slots.pocket_l.class), "hand", tostring(inv.slots.hand_l), "balance", GK.Roaches.Balance(P))
    GK.Inv.Move(P, inv.slots.pocket_l.id, "bag", 0.5, 0.5)
    log("into the bag: count", GK.Roaches.Count(P), "held", GK.Roaches.Held(P), "balance", GK.Roaches.Balance(P))
    local n0 = #ents.FindByClass("gk_roach")
    GK.Inv.Move(P, inv.slots.hand_r.id, "world")
    log("let go of the platinum: live roaches +", #ents.FindByClass("gk_roach") - n0, "held", GK.Roaches.Held(P), "balance", GK.Roaches.Balance(P))
end)
-- A husk pod: walking into it pops it, and it spills roaches.
step(0.5, function()
    local pod = ents.FindByClass("gk_husk_pod")[1]
    if not IsValid(pod) then log("no pods") return end
    local n0 = #ents.FindByClass("gk_roach")
    P:SetPos(pod:GetPos() + Vector(60, 0, 4)) P:SetLocalVelocity(vector_origin)
    timer.Simple(0.1, function() P:SetPos(pod:GetPos() + Vector(0, 0, 4)) end)
    timer.Simple(0.6, function() log("pod after walking in: broken", tostring(pod:GetBroken()), "roaches +", #ents.FindByClass("gk_roach") - n0, "solid", pod:GetSolid()) end)
end)
-- The tube and the flush, with stand-in map points.
step(1, function()
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    local c = ents.Create("info_target") c:SetName("gk_pool_bed") c:SetPos(P:GetPos() + Vector(0, 0, 4)) c:Spawn()
    local t = ents.Create("info_target") t:SetName("gk_drop_spawn") t:SetPos(P:GetPos() + fwd * 120 + Vector(0, 0, 200)) t:Spawn()
    for _ = 1, 6 do GK.Birthing.Drop() end
    log("tube drops: junk", #ents.FindByClass("gk_trash"), "items", #ents.FindByClass("gk_item"))
end)
step(3, function()
    local low = 0
    for _, e in ipairs(ents.FindByClass("gk_trash")) do if e:GetPos().z < P:GetPos().z + 40 then low = low + 1 end end
    log("junk landed near the floor", low, "of", #ents.FindByClass("gk_trash"))
    for _, e in ipairs(ents.FindByClass("gk_trash")) do log("junk z above us", math.floor(e:GetPos().z - P:GetPos().z), "vel", math.floor(e:GetVelocity().z), "movetype", e:GetMoveType(), "model", e:GetModel()) end
    P:SetPos(P:GetPos() + Vector(150, 0, 0)) -- off-centre, so the swirl has a direction
    -- Pretend the tub base is right here: everything on this floor is "in the drained tub".
    local v0 = P:GetVelocity()
    GK.Birthing.Flush()
    timer.Simple(1, function() log("during flush: player speed", math.floor(P:GetVelocity():Length2D()), "flushing", tostring(GK.Birthing.Flushing)) end)
end)
step(7, function() log("after flush: junk", #ents.FindByClass("gk_trash"), "flushing", tostring(GK.Birthing.Flushing), "player alive", tostring(P:Alive())) end)
step(1, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_BagTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_BagTest")
    timer.Simple(12, function()
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
