-- Rebar impalement. It's not easy to end up on a bar: it takes a thrown rebar
-- (gk_rebar_thrown), or coming down point-first on a spike / a rebar sticking
-- out of a wall while you're helpless: stunned or ragdolled. How hard you land
-- and how much you're carrying decide whether it goes in: the heavier your
-- inventory, the gentler a landing it takes. Once on, you're pinned, and you
-- can only look around within a 90° cone of where you faced when it went in.
--
--   Forwards (it went in your front, you can see it): F kicks you off at once,
--   or hold Jump to drag yourself off.
--   Backwards (through your back): reach behind and pull. Both hands must be
--   empty (G drops, Q / E pockets); hold LMB + RMB. One hand is much slower,
--   and everything you carry slows the pull, one-handed doubly so.
--
-- Coming off opens the wound and you bleed for a while.
--
-- Player NW2 state:
--   gk_impaled          entity  the bar you're on (GK.IsImpaled)
--   gk_impale_pos       vector  where you're pinned
--   gk_impale_axis      vector  along the bar, toward its free end (you slide off this way)
--   gk_impale_look      angle   centre of the look cone
--   gk_impale_back      bool    went in through your back
--   gk_impale_progress  float   0..1 of the way off

local C = GK.Config

function GK.ImpaledBack(ply) return ply:GetNW2Bool("gk_impale_back", false) end

-- Keeps an angle inside the impaled look cone.
function GK.ClampImpaleLook(ply, ang)
    local c = ply:GetNW2Angle("gk_impale_look")
    local cone = C.ImpaleLookCone
    return Angle(
        math.Clamp(c.p + math.Clamp(math.AngleDifference(ang.p, c.p), -cone, cone), -89, 89),
        c.y + math.Clamp(math.AngleDifference(ang.y, c.y), -cone, cone),
        0)
end

local function outsideCone(ply, ang, slack)
    local c = ply:GetNW2Angle("gk_impale_look")
    local cone = C.ImpaleLookCone + (slack or 0)
    return math.abs(math.AngleDifference(ang.p, c.p)) > cone or math.abs(math.AngleDifference(ang.y, c.y)) > cone
end

if CLIENT then
    -- Clamp the view before the command goes out, so the camera itself stops at the edge.
    hook.Add("CreateMove", "GK_ImpaleLook", function(cmd)
        local ply = LocalPlayer()
        if not IsValid(ply) or not GK.IsImpaled(ply) then return end
        local ang = cmd:GetViewAngles()
        if outsideCone(ply, ang) then
            local clamped = GK.ClampImpaleLook(ply, ang)
            cmd:SetViewAngles(clamped)
            ply:SetEyeAngles(clamped)
        end
    end)
    return
end

-- Server ---------------------------------------------------------------------

-- Everything you're carrying: bag, hands and pockets.
function GK.CarriedWeight(ply)
    local inv = GK.Inv.Get(ply)
    local w = 0
    for _, item in ipairs(inv.bag) do w = w + (GK.ItemDef(item.class).weight or 1) end
    for _, item in pairs(inv.slots) do w = w + (GK.ItemDef(item.class).weight or 1) end
    return w
end

-- Landing speed (along the bar) it takes to go on, for this player right now.
function GK.ImpaleSpeed(ply)
    return C.SpikeImpaleSpeed / (1 + GK.CarriedWeight(ply) * C.ImpaleWeightFactor)
end

-- Hands gripping the bar behind your back (drawn as grip frames; the grip
-- point is behind you, so first-person they stay low at the screen edges).
local function setHands(ply, l, r)
    local behind = ply:GetPos() + Vector(0, 0, 40) - Angle(0, ply:EyeAngles().y, 0):Forward() * 12
    for side, state in pairs({ l = l, r = r }) do
        ply:SetNW2Int("gk_hand_" .. side, state)
        ply:SetNW2Vector("gk_grip_" .. side, behind)
        ply:SetNW2Bool("gk_anchor_" .. side, false)
    end
end

-- opts: pos (where to pin), axis (unit, toward the free end), back (bool),
-- look (Angle, cone centre), clear (optional spot to put them once off, for
-- solid bars they'd otherwise be stuck in), damage, attacker.
function GK.Impale(ply, bar, opts)
    if GK.IsImpaled(ply) or not ply:Alive() or GK.IsRagdolled(ply) or not IsValid(bar) then return false end
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep.ReleaseAll then wep:ReleaseAll() end
    ply:SetNW2Entity("gk_impaled", bar)
    ply:SetNW2Vector("gk_impale_pos", opts.pos)
    ply:SetNW2Vector("gk_impale_axis", opts.axis)
    ply:SetNW2Angle("gk_impale_look", opts.look)
    ply:SetNW2Bool("gk_impale_back", opts.back and true or false)
    ply:SetNW2Float("gk_impale_progress", 0)
    ply.GK_ImpaleClear = opts.clear
    ply:SetPos(opts.pos)
    ply:SetLocalVelocity(vector_origin)
    ply:SetEyeAngles(opts.look)

    local d = DamageInfo()
    d:SetDamage(opts.damage or C.ImpaleDamage)
    d:SetDamageType(DMG_SLASH)
    d:SetAttacker(IsValid(opts.attacker) and opts.attacker or bar)
    d:SetInflictor(bar)
    d:SetDamagePosition(opts.pos + Vector(0, 0, 40))
    ply:TakeDamageInfo(d)
    ply:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 80)
    ply:EmitSound("gknuckle/rebar/impact_heavy.wav", 75, 100, 0.6)
    util.Decal("Blood", opts.pos + Vector(0, 0, 40), opts.pos + Vector(0, 0, 40) - opts.axis * 64, ply)
    return true
end

-- Off the bar. kicked = shoved off it (forwards, F).
function GK.Unimpale(ply, kicked)
    if not GK.IsImpaled(ply) then return end
    local axis = ply:GetNW2Vector("gk_impale_axis", Vector(0, 0, 1))
    local look = ply:GetNW2Angle("gk_impale_look")
    ply:SetNW2Entity("gk_impaled", NULL)
    ply:SetNW2Float("gk_impale_progress", 0)
    setHands(ply, 0, 0)
    ply.GK_BleedUntil = CurTime() + C.SpikeBleedTime -- coming off opens the wound
    ply.GK_ImpaleImmune = CurTime() + 1.5

    -- Solid bars (stuck in walls): step clear of the end you slid off.
    local clear = ply.GK_ImpaleClear
    ply.GK_ImpaleClear = nil
    if clear then
        local tr = util.TraceHull({ start = clear, endpos = clear, mins = ply:OBBMins(), maxs = ply:OBBMaxs(), filter = ply, mask = MASK_PLAYERSOLID })
        if not tr.StartSolid then ply:SetPos(clear) end
    end

    if kicked then
        -- Push off the bar with your legs: back away from where you're facing.
        local away = -Angle(0, look.y, 0):Forward()
        ply:SetVelocity(away * 260 + Vector(0, 0, 160))
        ply:EmitSound("physics/flesh/flesh_bloody_break.wav", 75, 90)
    else
        ply:SetVelocity(axis * 150 + Vector(0, 0, 60))
        ply:EmitSound("physics/flesh/flesh_bloody_break.wav")
    end
    ply:EmitSound("gknuckle/rebar/pickup.wav", 70, 80)
end

-- Kick key while impaled (sh_keys.lua). Only works when you went on forwards.
function GK.ImpaleKick(ply)
    if not GK.IsImpaled(ply) then return false end
    if GK.ImpaledBack(ply) or not GK.HasLegs(ply) then
        ply:EmitSound("physics/flesh/flesh_impact_hard" .. math.random(1, 6) .. ".wav", 60)
        return true
    end
    GK.Unimpale(ply, true)
    return true
end

-- A hand can pull on the bar if it's empty, the link's up and its button is held.
local function pullingHands(ply)
    if not GK.IsChipOnline(ply) then return false, false end
    local l = not GK.Inv.HandItem(ply, "l") and ply:KeyDown(IN_ATTACK)
    local r = not GK.Inv.HandItem(ply, "r") and ply:KeyDown(IN_ATTACK2)
    return l, r
end

hook.Add("PlayerTick", "GK_Impale", function(ply)
    if (ply.GK_BleedUntil or 0) > CurTime() and (ply.GK_NextBleed or 0) <= CurTime() then
        ply.GK_NextBleed = CurTime() + 0.5
        ply:TakeDamage(1, ply, ply)
        util.Decal("Blood", ply:GetPos() + Vector(0, 0, 4), ply:GetPos() - Vector(0, 0, 24), ply)
    end

    if not GK.IsImpaled(ply) then return end
    if not ply:Alive() or GK.IsRagdolled(ply) then
        ply:SetNW2Entity("gk_impaled", NULL)
        setHands(ply, 0, 0)
        return
    end

    -- Bots and lagged clients: the client clamps its own view; this only catches strays.
    if outsideCone(ply, ply:EyeAngles(), 10) then ply:SetEyeAngles(GK.ClampImpaleLook(ply, ply:EyeAngles())) end

    local weight = GK.CarriedWeight(ply)
    local rate = 0
    if GK.ImpaledBack(ply) then
        local l, r = pullingHands(ply)
        setHands(ply, l and 1 or 0, r and 1 or 0)
        if l and r then
            rate = 1 / (C.ImpalePullTime * (1 + weight * C.ImpalePullWeightFactor))
        elseif l or r then
            rate = 1 / (C.ImpalePullTime * C.ImpaleOneHandFactor * (1 + weight * C.ImpalePullWeightFactor * 2))
        end
    elseif ply:KeyDown(IN_JUMP) then
        rate = 1 / (C.SpikeEscapeTime * (1 + weight * C.ImpaleWeightFactor))
    end
    if rate <= 0 then return end

    local p = ply:GetNW2Float("gk_impale_progress", 0) + FrameTime() * rate
    ply:SetNW2Float("gk_impale_progress", p)
    ply.GK_BleedUntil = CurTime() + C.SpikeBleedTime
    -- Slide along the bar as you work your way off it.
    local axis = ply:GetNW2Vector("gk_impale_axis", Vector(0, 0, 1))
    ply:SetNW2Vector("gk_impale_pos", ply:GetNW2Vector("gk_impale_pos") + axis * FrameTime() * rate * 20)
    if (ply.GK_NextPullSound or 0) < CurTime() then
        ply.GK_NextPullSound = CurTime() + 0.7
        ply:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 60, 120, 0.5)
    end
    if p >= 1 then GK.Unimpale(ply) end
end)

-- Ragdolled bodies (kicked, bricked, blasted) landing point-first on a spike
-- or on a rebar sticking out of a wall ------------------------------------------

function GK.RagdollImpaleSpeed(ply)
    return (GK.Config.RagdollImpaleSpeed or 220) / (1 + GK.CarriedWeight(ply) * C.ImpaleWeightFactor)
end

local function impaleBars()
    local bars = {}
    for _, bar in ipairs(ents.FindByClass("gk_spike")) do
        if bar:PointsUp() then bars[#bars + 1] = bar end
    end
    for _, bar in ipairs(ents.FindByClass("gk_rebar_hold")) do
        if not bar.GK_PinsPlayer then bars[#bars + 1] = bar end
    end
    return bars
end

local function tryRagdollImpale(ply, rag, bar)
    local axis = bar:GetForward()
    local len = bar.GKLength or 40
    local tip = bar:GetPos() + axis * len
    local need = GK.RagdollImpaleSpeed(ply)
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local rel = phys:GetPos() - tip
            local along = rel:Dot(axis)
            local landing = -phys:GetVelocity():Dot(axis)
            if along < 10 and along > -len * 0.8 and (rel - axis * along):Length() < 9 and landing >= need then
                -- Which way the body faces as it comes down onto the point.
                local att = rag:GetAttachment(rag:LookupAttachment("eyes") or 0)
                local face = att and att.Ang:Forward() or Vector(1, 0, 0)
                local back = face:Dot(axis) > 0
                local yaw = (math.abs(face.z) < 0.9 and face or (att and att.Ang:Up() or face)):Angle().y
                GK.Unragdoll(ply)
                if bar.ImpaleOn then
                    bar:ImpaleOn(ply, landing, back, yaw)
                else
                    -- A wall rebar: run onto it, centred on the bar clear of the wall.
                    local centre = bar:GetPos() + axis * math.Clamp(along + len, 17, len)
                    local flat = Vector(axis.x, axis.y, 0)
                    local out = flat:LengthSqr() > 0.01 and flat:GetNormalized() or axis
                    GK.Impale(ply, bar, {
                        pos = centre - Vector(0, 0, 40), axis = axis, back = back,
                        clear = tip + out * 18 - Vector(0, 0, 40),
                        look = Angle(0, yaw, 0), damage = C.ImpaleDamage * 1.5,
                    })
                end
                return true
            end
        end
    end
end

local nextRagCheck = 0
hook.Add("Think", "GK_RagdollImpale", function()
    if CurTime() < nextRagCheck then return end
    nextRagCheck = CurTime() + 0.05
    local bars
    for _, ply in ipairs(player.GetAll()) do
        local rag = ply:GetNW2Entity("gk_ragdoll")
        if IsValid(rag) and ply:Alive() and (ply.GK_ImpaleImmune or 0) < CurTime() then
            bars = bars or impaleBars()
            for _, bar in ipairs(bars) do
                if tryRagdollImpale(ply, rag, bar) then break end
            end
        end
    end
end)

hook.Add("PlayerSpawn", "GK_ImpaleReset", function(ply)
    ply:SetNW2Entity("gk_impaled", NULL)
    ply:SetNW2Float("gk_impale_progress", 0)
    ply.GK_BleedUntil = 0
    ply.GK_ImpaleClear = nil
end)

-- Rebar hits on players (thrown rebar, gk_rebar_thrown) ----------------------

-- Which part of the body the bar's line goes through. Everyone here is
-- armless (and maybe legless), but the hitboxes don't know that, so trust only
-- a head hitbox and otherwise go by the height at which the line crosses the
-- body's axis.
function GK.RebarBodyPart(ply, tr, dir)
    if tr.HitGroup == HITGROUP_HEAD then return "head" end
    local c = ply:GetPos()
    local flat = Vector(dir.x, dir.y, 0)
    local t = flat:LengthSqr() > 0.001 and (c - tr.HitPos):Dot(flat) / flat:LengthSqr() or 0
    local z = tr.HitPos.z + dir.z * t - c.z
    local eye = (ply:Crouching() and ply:GetViewOffsetDucked() or ply:GetViewOffset()).z
    if z >= eye - 10 then return "head" end
    if z < eye * 0.45 and GK.HasLegs(ply) then return "legs" end
    return "body"
end

-- Takes the head off (a skull gib flies along dir) and gores them: dead,
-- grey hands, headless corpse (cl_init.lua). dmginfo carries the attacker.
function GK.Decapitate(ply, dir, dmginfo)
    local head = ply:LookupBone("ValveBiped.Bip01_Head1")
    local hpos = head and ply:GetBonePosition(head) or ply:EyePos()
    local gib = ents.Create("prop_physics")
    gib:SetModel("models/gibs/hgibs.mdl")
    gib:SetPos(hpos)
    gib:Spawn()
    gib:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    local gp = gib:GetPhysicsObject()
    if IsValid(gp) then gp:SetVelocity(dir * 500 + Vector(0, 0, 120)) end
    SafeRemoveEntityDelayed(gib, 20)
    local fx = EffectData() fx:SetOrigin(hpos) fx:SetNormal(dir)
    util.Effect("BloodImpact", fx, true, true)
    ply:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav", 85)
    GK.Gore(ply, dmginfo)
end

-- Head: comes off (gored). Legs: come off. Anything else: run through and
-- pinned to whatever's behind them, or staked to the floor.
function GK.RebarHit(ply, tr, dir, rebar, attacker)
    local part = GK.RebarBodyPart(ply, tr, dir)
    local d = DamageInfo()
    d:SetDamage(C.RebarDamage)
    d:SetDamageType(DMG_SLASH)
    d:SetAttacker(IsValid(attacker) and attacker or rebar)
    d:SetInflictor(rebar)
    d:SetDamagePosition(tr.HitPos)
    d:SetDamageForce(dir * 4000)

    if part == "head" then
        GK.Decapitate(ply, dir, d)
        return "head"
    end

    if part == "legs" then
        ply:TakeDamageInfo(d)
        GK.RemoveLegs(ply)
        return "legs"
    end

    -- Torso / arms-that-aren't: run through. Hit from behind = went in your back.
    local face = Angle(0, ply:EyeAngles().y, 0):Forward()
    local flat = Vector(dir.x, dir.y, 0)
    if flat:LengthSqr() < 0.01 then flat = -face end
    flat:Normalize()
    local back = flat:Dot(face) > 0

    -- Something solid just behind them? Pin them to it.
    local center = ply:GetPos() + Vector(0, 0, 40)
    local wall = util.TraceLine({ start = center, endpos = center + flat * 72, mask = MASK_SOLID, filter = function(e) return not e:IsPlayer() end })
    local bar = ents.Create("gk_rebar_hold")
    local pin, axis, clear, floorPin
    if wall.Hit and not wall.StartSolid then
        axis = -flat
        bar:SetPos(wall.HitPos + flat * 6)               -- base sunk into the wall
        bar:SetAngles(axis:Angle())
        pin = Vector(wall.HitPos.x, wall.HitPos.y, ply:GetPos().z) - flat * 17
    else
        -- Staked to the floor where they stand.
        local floor = util.TraceLine({ start = center, endpos = center - Vector(0, 0, 400), mask = MASK_SOLID, filter = function(e) return not e:IsPlayer() end })
        local ground = floor.Hit and floor.HitPos or ply:GetPos()
        axis = (-flat + Vector(0, 0, 1.4)):GetNormalized()
        bar:SetPos(Vector(ply:GetPos().x, ply:GetPos().y, ground.z) - axis * 20 + Vector(0, 0, 18))
        bar:SetAngles(axis:Angle())
        pin = Vector(ply:GetPos().x, ply:GetPos().y, ground.z)
        floorPin = true
    end
    bar.GK_PinsPlayer = true
    bar.GKScale, bar.GKLength = 1, 49.7 -- full length, so it sticks well out of them
    bar:Spawn()
    local tip = bar:GetPos() + bar:GetForward() * bar.GKLength
    clear = Vector(tip.x, tip.y, pin.z) + Vector(axis.x, axis.y, 0):GetNormalized() * 18
    GK.Impale(ply, bar, {
        pos = pin, axis = axis, back = back, clear = clear,
        look = Angle(0, ply:EyeAngles().y, 0), damage = C.RebarDamage, attacker = attacker,
    })
    -- Staked to the floor: laid flat on it (sh_impale_prone.lua).
    if floorPin and GK.MakeProne then GK.MakeProne(ply) end
    -- The bar stays while they're on it, then lingers as a handhold like any stuck rebar.
    timer.Create("GK_PinBar_" .. bar:EntIndex(), 1, 0, function()
        if not IsValid(bar) then return end
        if not IsValid(ply) or ply:GetNW2Entity("gk_impaled") ~= bar then
            timer.Remove("GK_PinBar_" .. bar:EntIndex())
            SafeRemoveEntityDelayed(bar, 30)
        end
    end)
    return back and "impaled_back" or "impaled_front"
end
