-- Room hazards from White Knuckle's own placement (each room layout's
-- hazards[], from the build thread's tools/extract_hazards.js):
--   force   WK's UT_ForceZone: a steady push (steam vents, air currents). WK's
--           force is an acceleration of force/10 m/s^2; "noGrab" zones also
--           stop you holding on; steam vents scald and knock you off.
--   damage  WK's UT_DamageTrigger: caustic water, razorvine, urchins, grinders...
--           (WK damage x10 for our 100 hp; "dot" zones tick every `rate` s).
--   fire    WK's UT_Fire jets: gk_firejet, 3 s on / 3 s off.
--   spin / door with a mover mesh (models/gknuckle/wk/movers): gk_mover;
--           spinners turn, doors stand open.
-- Special handholds (holds[]): icy ones slip after a moment, breakable ones
-- crumble, sharp ones cut and make you let go (GK.HoldAt / GK.HoldTick, used
-- by the mind-hands).
-- Zones that only hurt while their part moves: fans and grinders always
-- spin, so theirs are live; doors and crushers are parked open, so theirs
-- wait until those parts move here. Zones live with their room: they appear and go as rooms stream.

local M = 39.4
local GRIP_BREAK = { steam = true, gasbag = true, turret = true, bloodbug = true, sturge = true }

GK.Hazards = GK.Hazards or {}
local zones = {} -- [info index] = { [room n] = { zone, ... } }
local holds = {} -- [info index] = { [room n] = { hold, ... } }
GK.Hazards.zones = zones -- (read by tests)

local function layoutOf(piece)
    return GK.LevelLayout(piece) -- cached and shared: read only
end

-- A zone's shape in world space.
local function makeShape(origin, h)
    local c = h.collider
    if not c then return nil end
    local centre = origin + GK.LevelToModel(c.center or h.pos)
    if c.shape == "sphere" then
        return { sphere = true, centre = centre, r = c.radius or 40 }
    end
    local size = c.size or { 40, 40, 40 }
    return { centre = centre, half = Vector(size[1] / 2, size[2] / 2, size[3] / 2), yaw = (c.yaw or h.yaw or 0) + 90 }
end

local function inside(shape, p)
    local d = p - shape.centre
    if shape.sphere then return d:LengthSqr() < shape.r * shape.r end
    local r = math.rad(-shape.yaw)
    local c, s = math.cos(r), math.sin(r)
    local lx, ly = d.x * c - d.y * s, d.x * s + d.y * c
    return math.abs(lx) <= shape.half.x and math.abs(ly) <= shape.half.y and math.abs(d.z) <= shape.half.z
end

hook.Add("GK_ArenaRoomSpawned", "GK_RoomHazards", function(info, n)
    local step = info.plan and info.plan[n]
    if not step then return end
    local list = {}
    for _, h in ipairs(layoutOf(step.piece).hazards or {}) do
        local kinds = h.kinds or { h.kind }
        local isForce, isDamage = table.HasValue(kinds, "force"), table.HasValue(kinds, "damage")
        local shape = makeShape(step.pos, h)
        -- Moving parts (doors, spinners, rollers) with their own mesh: gk_mover.
        if h.model and (h.kind == "spin" or h.kind == "door") then
            local e = ents.Create("gk_mover")
            local pos = step.pos + GK.LevelToModel(h.pos)
            if h.kind == "door" and h.move then pos = pos + GK.LevelToModel(h.move) end -- open
            e.GK_Model = "models/" .. h.model .. ".mdl"
            e.GK_Kind = h.kind
            if h.kind == "spin" and h.spinning ~= false and h.rotate then
                local w = GK.LevelToModel(h.rotate) * (h.multiplier or 1)
                e.GK_Rate = w:Length()
                e.GK_Axis = w:GetNormalized()
            end
            e:SetPos(pos)
            e:SetAngles(Angle(0, (h.yaw or 0) + 90, 0))
            e:Spawn()
            local room = info.rooms and info.rooms[n]
            if room then room.ents[#room.ents + 1] = e end
            info.ents[#info.ents + 1] = e
        end
        if h.kind == "fire" and shape and not shape.sphere then
            -- Fire jets are their own entity (flames, on/off timer): gk_firejet.
            local e = ents.Create("gk_firejet")
            e:SetPos(shape.centre) e:SetAngles(Angle(0, shape.yaw, 0))
            e:Spawn()
            e:SetHalf(shape.half)
            local room = info.rooms and info.rooms[n]
            if room then room.ents[#room.ents + 1] = e end
            info.ents[#info.ents + 1] = e
        end
        -- "Only while moving" zones: fans and grinders spin all the time in WK,
        -- so they always hurt. Crushers and silo doors stay parked open here,
        -- so theirs stay off (a kill zone with nothing moving would be unfair).
        local alwaysMoving = h.whenMoving and (h.type == "fan" or h.type == "grinder")
        local live = isDamage and (not h.whenMoving or alwaysMoving)
        if shape and (isForce or live) then
            local z = { shape = shape, name = h.name, type = h.type }
            if isForce and h.force then
                local f = GK.LevelToModel(h.force)
                z.accel = f * (M / 10) -- u/s^2
                z.radial = h.radial
                z.noGrab = h.noGrab
            end
            if live and h.damage then
                z.damage = h.damage * 10
                z.dot = h.dot
                z.rate = math.max(h.rate or 0.5, 0.1)
            end
            if z.accel or z.damage then list[#list + 1] = z end
        end
    end
    zones[info.index] = zones[info.index] or {}
    zones[info.index][n] = list

    -- Special handholds (WK's CL_Handhold_Icy / _Breakable / _Damage).
    local hl = {}
    for _, h in ipairs(layoutOf(step.piece).holds or {}) do
        local shape = makeShape(step.pos, h)
        if shape and not shape.sphere then shape.half = shape.half + Vector(6, 6, 6) end
        shape = shape or { sphere = true, centre = step.pos + GK.LevelToModel(h.pos), r = 20 }
        hl[#hl + 1] = { kind = h.kind, shape = shape, maxHold = h.maxHold or (h.kind == "damage" and 0 or 3), damage = (h.damage or 1) * 10 }
    end
    holds[info.index] = holds[info.index] or {}
    holds[info.index][n] = hl
end)

-- The special handhold (if any) at a grip point.
function GK.HoldAt(pos)
    for _, rooms in pairs(holds) do
        for _, list in pairs(rooms) do
            for _, h in ipairs(list) do
                if not h.broken and inside(h.shape, pos) then return h end
            end
        end
    end
end

-- Called by the mind-hands every tick for each hand on a special hold.
-- Returns true when the hand comes off.
function GK.HoldTick(ply, h, heldFor)
    if h.kind == "icy" then
        if heldFor > h.maxHold then
            ply:EmitSound("physics/glass/glass_sheet_step" .. math.random(1, 4) .. ".wav", 65, 120)
            ply:SetVelocity(Vector(0, 0, -60)) -- slides off
            return true
        end
    elseif h.kind == "breakable" then
        if heldFor > h.maxHold then
            h.broken = true
            local fx = EffectData() fx:SetOrigin(h.shape.centre) fx:SetScale(1) fx:SetMagnitude(1)
            util.Effect("WheelDust", fx, true, true)
            sound.Play("physics/concrete/concrete_break" .. math.random(2, 3) .. ".wav", h.shape.centre, 75)
            return true
        end
    elseif h.kind == "damage" then
        if heldFor > h.maxHold and (h.nextHurt or 0) < CurTime() then
            h.nextHurt = CurTime() + 1
            local d = DamageInfo()
            d:SetDamage(h.damage) d:SetDamageType(DMG_SLASH)
            d:SetAttacker(game.GetWorld()) d:SetInflictor(game.GetWorld())
            ply:TakeDamageInfo(d)
            ply:EmitSound("physics/flesh/flesh_impact_bullet" .. math.random(1, 5) .. ".wav", 65)
            return true -- WK drops the hand when it hurts
        end
    end
end

hook.Add("GK_ArenaRoomRemoved", "GK_RoomHazards", function(info, n)
    if zones[info.index] then zones[info.index][n] = nil end
    if holds[info.index] then holds[info.index][n] = nil end
end)
hook.Add("GK_ArenaCleared", "GK_RoomHazards", function(index) zones[index] = nil holds[index] = nil end)

local TICK = 0.1
timer.Create("GK_Hazards", TICK, 0, function()
    local ct = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() then
            local index = GK.ArenaOf(ply)
            local rooms = index ~= 0 and zones[index]
            if rooms then
                local p = ply:WorldSpaceCenter()
                for _, list in pairs(rooms) do
                    for _, z in ipairs(list) do
                        if inside(z.shape, p) then
                            if z.accel then
                                local a = z.accel
                                if z.radial then a = (p - z.shape.centre):GetNormalized() * z.accel:Length() end
                                -- WK's force curve: full strength at the zone's heart, fading
                                -- toward its edges, and ramping up over your first moment in it.
                                local reach = z.shape.sphere and z.shape.r or math.max(z.shape.half.x, z.shape.half.y, z.shape.half.z)
                                local edge = 1 - 0.6 * math.Clamp(p:Distance(z.shape.centre) / math.max(reach, 1), 0, 1)
                                ply.GK_ForceIn = ply.GK_ForceIn or {}
                                if (ply.GK_ForceIn[z] or 0) < ct - 0.5 then ply.GK_ForceStart = ply.GK_ForceStart or {} ply.GK_ForceStart[z] = ct end
                                ply.GK_ForceIn[z] = ct
                                local ramp = math.Clamp((ct - (ply.GK_ForceStart and ply.GK_ForceStart[z] or ct)) / 0.3, 0.3, 1)
                                ply:SetVelocity(a * TICK * edge * ramp)
                                if z.noGrab then GK.DropHang(ply, 0.2, 0) end
                            end
                            if z.damage then
                                ply.GK_HazardNext = ply.GK_HazardNext or {}
                                if (ply.GK_HazardNext[z] or 0) <= ct then
                                    ply.GK_HazardNext[z] = ct + (z.dot and z.rate or 1)
                                    local d = DamageInfo()
                                    d:SetDamage(z.damage)
                                    d:SetDamageType(z.type == "steam" and DMG_BURN or DMG_GENERIC)
                                    d:SetAttacker(game.GetWorld()) d:SetInflictor(game.GetWorld())
                                    ply:TakeDamageInfo(d)
                                    if GRIP_BREAK[z.type] then GK.DropHang(ply, 0.1, 1) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Debug: gk_hazards_here lists the zones you're standing in.
concommand.Add("gk_hazards_here", function(ply)
    if not IsValid(ply) then return end
    local rooms = zones[GK.ArenaOf(ply)] or {}
    for n, list in pairs(rooms) do
        for _, z in ipairs(list) do
            if inside(z.shape, ply:WorldSpaceCenter()) then print(n, z.name, z.type, z.damage, z.accel) end
        end
    end
end)
GK.Hazards.Zones = zones
GK.Hazards.Holds = holds
