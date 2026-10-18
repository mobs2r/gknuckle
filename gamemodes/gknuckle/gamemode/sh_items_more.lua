-- The rest of White Knuckle's items (models decompiled from WK by
-- gameplay_tools/make_wk_items.ps1, buffs from its Item_Hands_* prefabs) and
-- more Half-Life gear. Everything sits in a hologram palm when held; mouse
-- button on that hand uses it. Buffs: sh_buffs.lua.

local C = GK.Config
local register = GK.RegisterItem

local function mdl(name) return "models/gknuckle/items/" .. name .. ".mdl" end

if SERVER then
    function GK.Heal(ply, amount)
        ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + amount))
    end
end

-- Eat / drink / inject: a short busy moment, a sound, then the effect.
local function consume(sound, seconds, effect)
    return function(ply, side, item)
        if (item.usingUntil or 0) > CurTime() then return end
        item.usingUntil = CurTime() + seconds
        ply:EmitSound(sound, 65)
        timer.Simple(seconds, function()
            if IsValid(ply) and ply:Alive() then effect(ply) end
        end)
        if item.data.count then
            item.data.count = item.data.count - 1
            GK.Inv.Sync(ply)
            return item.data.count <= 0
        end
        return true
    end
end

-- Melee swing (hammer, crowbar): players are knocked down (ragdolled, which
-- is how they end up on a spike), props are knocked about, and anything that
-- can break (supply crates, creatures, turrets) takes the blow (WK's hammer
-- opens crates).
local function swing(damage, force, ragdollTime, hitSound)
    return function(ply, side, item)
        if (item.nextSwing or 0) > CurTime() then return end
        item.nextSwing = CurTime() + 0.55
        ply:EmitSound("Weapon_Crowbar.Single")
        ply:ViewPunch(Angle(2, side == "r" and -4 or 4, 0))
        local tr = util.TraceHull({
            start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 75,
            mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), filter = ply, mask = MASK_SHOT_HULL,
        })
        if not tr.Hit then return end
        local ent = tr.Entity
        local dir = ply:GetAimVector()
        if IsValid(ent) and ent:IsPlayer() then
            local d = DamageInfo()
            d:SetDamage(damage * GK.BuffMult(ply, "melee")) d:SetAttacker(ply) d:SetInflictor(ply) d:SetDamageType(DMG_CLUB)
            d:SetDamagePosition(tr.HitPos) d:SetDamageForce(dir * force * 20)
            ent:TakeDamageInfo(d)
            if ragdollTime > 0 and ent:Alive() then
                timer.Simple(0, function()
                    if IsValid(ent) then GK.Ragdoll(ent, (dir + Vector(0, 0, 0.35)) * force, ragdollTime) end
                end)
            end
            ent:EmitSound(hitSound)
        elseif IsValid(ent) and ent.Hammer then
            ent:Hammer(GK.HasPerk(ply, "heavystrike")) -- a piton: one hit drives it deeper (Heavy Strike: all the way)
            ply:EmitSound("Weapon_Crowbar.Melee_HitWorld")
        elseif IsValid(ent) then
            if SERVER then
                local d = DamageInfo()
                d:SetDamage(damage * GK.BuffMult(ply, "melee")) d:SetAttacker(ply) d:SetInflictor(ply) d:SetDamageType(DMG_CLUB)
                d:SetDamagePosition(tr.HitPos) d:SetDamageForce(dir * force * 20)
                ent:TakeDamageInfo(d)
            end
            local phys = IsValid(ent) and ent:GetPhysicsObject()
            if IsValid(phys) then phys:ApplyForceOffset(dir * force * phys:GetMass() * 0.6, tr.HitPos) end
            if IsValid(ent) then ent:EmitSound("Weapon_Crowbar.Melee_Hit") end
        else
            ply:EmitSound("Weapon_Crowbar.Melee_HitWorld")
            util.Decal("ManhackCut", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
        end
    end
end

-- Puts a piton handhold in the wall you're looking at. Returns the new piton,
-- or (false, piton) when you're looking at one already set, so it can be
-- hammered further instead.
local function placePiton(ply)
    local tr = util.TraceLine({
        start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 110, -- WK: 2.8 m
        filter = ply, mask = MASK_SOLID,
    })
    if IsValid(tr.Entity) and tr.Entity:GetClass() == "gk_piton_hold" then return false, tr.Entity end
    local cls = IsValid(tr.Entity) and tr.Entity:GetClass() or ""
    if cls == "gk_level_chunk" or cls == "gk_level_piece" then tr.HitWorld = true end -- WK room walls take pitons
    if not tr.HitWorld and not (IsValid(tr.Entity) and IsValid(tr.Entity:GetPhysicsObject())
        and not tr.Entity:GetPhysicsObject():IsMotionEnabled()) then
        return false
    end
    local p = ents.Create("gk_piton_hold")
    p.GK_WallPos, p.GK_WallNormal = tr.HitPos, tr.HitNormal -- it seats itself (gk_piton_hold)
    p:SetPos(tr.HitPos + tr.HitNormal * 1)
    p:SetAngles(tr.HitNormal:Angle())
    p:Spawn()
    sound.Play("gknuckle/items/piton_hit.wav", tr.HitPos, 75, math.random(95, 105))
    return p
end

-- White Knuckle -------------------------------------------------------------

-- The bug: crush the Slug Grub in your hands and the goop makes them stick to
-- anything, and they never tire (WK's grabAnything + gooped).
register("grub", {
    name = "Slug Grub", model = mdl("grub"), weight = 1,
    hold = { ang = Angle(0, 90, 0) },
    Use = consume("npc/barnacle/barnacle_crunch2.wav", 0.4, function(ply)
        GK.AddBuff(ply, "gooped", 10) -- WK: about 10 s
        ply:EmitSound("npc/antlion_grub/squashed.wav", 70)
        ply:ScreenFade(SCREENFADE.IN, Color(120, 220, 40, 90), 0.6, 0)
    end),
})

-- The needle: speed, jump and a wider view for a while (WK's injector buffs).
register("injector", {
    name = "Injector", model = mdl("injector"), weight = 1,
    hold = { ang = Angle(0, 90, 0) },
    pickupSound = "gknuckle/items/injector_pickup.wav",
    Use = consume("gknuckle/items/injector_inject.wav", 0.5, function(ply)
        GK.AddBuff(ply, "injected", 40) -- WK: 40 s
        GK.Heal(ply, 10)
        GK.SetStamina(ply, C.StaminaMax)
        ply:ScreenFade(SCREENFADE.IN, Color(255, 40, 40, 90), 0.4, 0)
    end),
})

register("pills", {
    name = "Pill Bottle", model = mdl("pills"), weight = 1, stack = 3,
    newData = function() return { count = 3 } end,
    hold = {},
    pickupSound = "gknuckle/items/pillspickup.wav",
    Use = consume("gknuckle/items/pillspickup.wav", 0.4, function(ply) GK.AddBuff(ply, "pilled", 100) end),
})

register("foodbar", {
    name = "Bean Bar", model = mdl("foodbar"), weight = 1,
    hold = { ang = Angle(0, 90, 0) },
    pickupSound = "gknuckle/items/foodbar_pickup.wav",
    Use = consume("gknuckle/items/foodbar_use.wav", 0.8, function(ply)
        GK.Heal(ply, 15)
        GK.AddBuff(ply, "fed", 45)
        GK.SetStamina(ply, C.StaminaMax)
    end),
})

register("beans", {
    name = "Can of Beans", model = mdl("beans"), weight = 1,
    hold = {},
    Use = consume("npc/barnacle/barnacle_gulp1.wav", 1.2, function(ply)
        GK.Heal(ply, 30)
        GK.AddBuff(ply, "fed", 30)
        GK.SetStamina(ply, C.StaminaMax) -- WK: a can of beans is a full hand of grip
    end),
})

register("meat", {
    name = "Meat", model = mdl("meat"), weight = 1,
    hold = {},
    Use = consume("npc/barnacle/barnacle_crunch2.wav", 1.2, function(ply)
        GK.Heal(ply, 40)
        GK.AddStamina(ply, C.StaminaMax * 0.5) -- and half a hand of grip
    end),
})

register("milk", {
    name = "Milk", model = mdl("milk"), weight = 1,
    hold = {},
    -- Calms the virus: brings the link straight back online.
    Use = consume("npc/barnacle/barnacle_gulp2.wav", 1, function(ply)
        GK.Heal(ply, 15)
        ply:SetNW2Float("gk_chip_offline_until", 0)
    end),
})

register("bandage", {
    name = "Bandage", model = mdl("bandage"), weight = 1, stack = 3,
    newData = function() return { count = 2 } end,
    hold = {},
    -- Stops the bleeding (impalement wounds) and patches you up.
    Use = consume("items/smallmedkit1.wav", 1.5, function(ply)
        ply.GK_BleedUntil = 0
        GK.Heal(ply, 30)
    end),
})

-- Pitons, as in WK: click a wall within reach and it's in, used up; it only
-- just holds until it's hammered (a hammer in either hand, hit it three times).
-- Missing a wall keeps the piton. The auto piton drills itself in fully.
register("piton", {
    name = "Piton", model = mdl("piton"), weight = 1,
    hold = { ang = Angle(0, 90, 0) },
    pickupSound = "gknuckle/items/piton_pickup.wav",
    Use = function(ply, side, item)
        if (item.nextUse or 0) > CurTime() then return end
        item.nextUse = CurTime() + 0.4
        local placed = placePiton(ply)
        if not placed then
            ply:EmitSound("physics/metal/metal_solid_impact_soft1.wav", 60, 140)
            return
        end
        return true -- this piton is in the wall now
    end,
})

register("autopiton", {
    name = "Auto Piton", model = mdl("autopiton"), weight = 1,
    pickupSound = "gknuckle/items/piton_pickup.wav",
    hold = { ang = Angle(0, 90, 0) },
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        local placed = placePiton(ply)
        if not placed then return end
        placed:Hammer(true) -- drills itself all the way in
        ply:EmitSound("gknuckle/items/autopiton_use.wav", 75)
        return true
    end,
})

register("hammer", {
    name = "Hammer", model = mdl("hammer"), weight = 2,
    hold = { ang = Angle(0, 90, 0) },
    Use = swing(20, 300, 1.5, "physics/body/body_medium_impact_hard3.wav"),
})

-- Rebar Rope: throw it into a wall and a rope hangs from it to climb.
register("rebarrope", {
    name = "Rebar Rope", model = mdl("rebarrope"), weight = 1,
    pickupSound = "gknuckle/rebar/pickup.wav",
    hold = { pos = Vector(14, 8, -9), ang = Angle(0, 6, 0), scale = 0.5, centre = true },
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        GK.ThrowRebar(ply, "rope")
        return true
    end,
})

register("rebarexplo", {
    name = "Rebar-Explosive", model = mdl("rebarexplo"), weight = 1,
    pickupSound = "gknuckle/rebar/pickup.wav",
    hold = { pos = Vector(14, 8, -9), ang = Angle(0, 6, 0), scale = 0.5, centre = true },
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        GK.ThrowRebar(ply, "explosive")
        return true
    end,
})

-- Blink Eye: look somewhere and you're there.
register("blinkeye", {
    name = "Blink Eye", model = mdl("blinkeye"), weight = 1,
    pickupSound = "gknuckle/items/peripheraleye_pickup.wav",
    hold = {},
    -- WK's blink eye: three jumps of up to 10 m. Your holds let go, anything
    -- holding you (a barnacle's tongue, a Vent Thing's hand) loses you, and
    -- landing inside someone kills them and gives the jump back.
    newData = function() return { uses = 3 } end,
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        item.data = item.data or {}
        item.data.uses = item.data.uses or 3
        local start = ply:GetPos() + Vector(0, 0, 36)
        local tr = util.TraceHull({
            start = start, endpos = start + ply:GetAimVector() * 394,
            mins = Vector(-16, -16, -36), maxs = Vector(16, 16, 36), filter = function(e) return not e:IsPlayer() end, mask = MASK_PLAYERSOLID,
        })
        local fx = EffectData() fx:SetOrigin(ply:WorldSpaceCenter())
        util.Effect("cball_explode", fx, true, true)
        local mind = ply:GetWeapon("gk_mind")
        if IsValid(mind) and mind.ReleaseAll then mind:ReleaseAll() end
        ply:SetNW2Entity("gk_tongue", NULL)
        ply:SetNW2Entity("gk_ventgrab", NULL)
        local dest = tr.HitPos - Vector(0, 0, 36)
        local refund = false
        for _, v in ipairs(ents.FindInBox(dest + Vector(-16, -16, 0), dest + Vector(16, 16, 72))) do
            if v:IsPlayer() and v ~= ply and v:Alive() then
                local d = DamageInfo() d:SetDamage(v:Health() + 1000) d:SetDamageType(DMG_DISSOLVE) d:SetAttacker(ply) d:SetInflictor(ply)
                v.GK_Goring = true v:TakeDamageInfo(d) v.GK_Goring = false
                if v:Alive() then v:Kill() end
                refund = true
            end
        end
        ply:SetPos(dest)
        ply:SetNW2Float("gk_blink_at", CurTime()) -- the inverted outline flash (cl_status.lua)
        ply:SetLocalVelocity(vector_origin)
        ply:EmitSound("gknuckle/items/peripheraleye_use.wav", 72)
        ply:ScreenFade(SCREENFADE.IN, Color(255, 255, 255, 120), 0.3, 0)
        if not refund then item.data.uses = item.data.uses - 1 end
        GK.Inv.Sync(ply)
        return item.data.uses <= 0 -- used up after its third jump
    end,
})

-- Flaregun: a burning flare that sets players alight. Three shots.
-- WK's flare gun: one flare at a time. Empty, it loads from a flare held in
-- your other hand (GK.AmmoReload).
register("flaregun", {
    name = "Flaregun", model = mdl("flaregun"), weight = 2,
    pickupSound = "gknuckle/items/flaregun_pickup.wav",
    newData = function() return { clip = 1 } end,
    hold = { pos = Vector(18, 0, -8), ang = Angle(0, 90, 0), centre = true },
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) or (item.nextFire or 0) > CurTime() then return end
        item.nextFire = CurTime() + 0.5
        if item.data.clip <= 0 then
            if not GK.AmmoReload(ply, side, item, GK.FlareAmmo) then ply:EmitSound("gknuckle/items/flaregun_dryfire.wav") end
            return
        end
        item.data.clip = item.data.clip - 1
        local f = ents.Create("gk_flare")
        f:SetPos(ply:GetShootPos() + ply:GetAimVector() * 16)
        f:SetOwner(ply)
        f:Spawn()
        local phys = f:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(ply:GetAimVector() * 2950) end -- WK shootSpeed 75 m/s
        ply:EmitSound("gknuckle/items/flaregun_fire.wav", 85)
        ply:ViewPunch(Angle(-8, 0, 0))
        -- WK movement tech: the flare gun kicks you back the other way (fire it
        -- at your feet mid-jump for a boost).
        ply:SetVelocity(-ply:GetAimVector() * 260)
        GK.Inv.Sync(ply)
    end,
    Reload = function(ply, side, item) GK.AmmoReload(ply, side, item, GK.FlareAmmo) end,
})
GK.FlareAmmo = { ammo = "flare", max = 1, time = 1.2, sound = "gknuckle/items/flaregun_load.wav" }

-- A flare cartridge (WK Item_Flaregun_Ammo).
register("flare", {
    name = "Flare", model = mdl("flare"), weight = 1, stack = 4,
    pickupSound = "gknuckle/items/flaregun_ammo_pickup.wav",
    newData = function() return { count = 1 } end,
    hold = {},
    Label = function(item) return tostring(item.data.count or 1) end,
})

-- Flashlight: a beam from your hand while it's switched on.
-- WK's flashlight is hand-cranked: each click winds it (one crank always
-- gives at least half a charge), and it dims and dies as the charge runs out
-- over about 40 s.
register("flashlight", {
    name = "Flashlight", model = mdl("flashlight"), weight = 1,
    pickupSound = "gknuckle/items/flashlight_pickup.wav",
    hold = { ang = Angle(0, 90, 0) },
    Use = function(ply, side, item)
        if (item.nextCrank or 0) > CurTime() then return end
        item.nextCrank = CurTime() + 0.25
        local c = math.min(1, math.max(ply:GetNW2Float("gk_flash_charge", 0) + 0.25, 0.5))
        ply:SetNW2Float("gk_flash_charge", c)
        ply:SetNW2Bool("gk_flashlight", true)
        ply:EmitSound("gknuckle/items/flashlight_charge.wav", 60, math.random(95, 110))
    end,
})

if SERVER then
    hook.Add("PlayerTick", "GK_FlashCharge", function(ply)
        if not ply:GetNW2Bool("gk_flashlight", false) then return end
        local c = ply:GetNW2Float("gk_flash_charge", 0) - FrameTime() / 40
        if c <= 0 then
            ply:SetNW2Bool("gk_flashlight", false)
            ply:EmitSound("HL2Player.FlashLightOff")
            c = 0
        end
        ply:SetNW2Float("gk_flash_charge", c)
    end)
end

-- Half-Life ------------------------------------------------------------------

register("crowbar", {
    name = "Crowbar", model = "models/weapons/w_crowbar.mdl", weight = 2,
    hold = {},
    Use = swing(30, 380, 2, "Weapon_Crowbar.Melee_Hit"),
})

register("healthvial", {
    name = "Health Vial", model = "models/healthvial.mdl", weight = 1,
    hold = {},
    Use = consume("items/smallmedkit1.wav", 0.3, function(ply) GK.Heal(ply, 25) end),
})

-- HEV suit battery, wired into your Xenium link: it can't be stunned for a while.
register("battery", {
    name = "Suit Battery", model = "models/items/battery.mdl", weight = 1,
    hold = {},
    Use = consume("items/battery_pickup.wav", 0.3, function(ply)
        GK.AddBuff(ply, "shielded", 40)
        ply:SetNW2Float("gk_chip_offline_until", 0)
        ply:ScreenFade(SCREENFADE.IN, Color(90, 170, 255, 70), 0.4, 0)
    end),
})

-- Flashlight beams (client): one projected light per player who has one on.
if CLIENT then
    local lights = {}
    hook.Add("Think", "GK_Flashlights", function()
        for _, ply in ipairs(player.GetAll()) do
            local on = ply:Alive() and ply:GetNW2Bool("gk_flashlight", false)
                and (ply:GetNW2String("gk_hitem_l", "") == "flashlight" or ply:GetNW2String("gk_hitem_r", "") == "flashlight"
                    or ply:GetNW2Bool("gk_flash_pocket", false))
            local pt = lights[ply]
            if on then
                if not IsValid(pt) then
                    pt = ProjectedTexture()
                    pt:SetTexture("effects/flashlight001")
                    pt:SetFarZ(900)
                    pt:SetFOV(50)
                    pt:SetBrightness(2)
                    lights[ply] = pt
                end
                local c = ply:GetNW2Float("gk_flash_charge", 1)
                -- Dims with the charge, and sputters near the end.
                local b = 0.4 + 1.6 * c
                if c < 0.2 and math.random() < 0.15 then b = b * 0.2 end
                pt:SetBrightness(b)
                pt:SetPos(ply:EyePos() - Vector(0, 0, 6))
                pt:SetAngles(ply:EyeAngles())
                pt:Update()
            elseif IsValid(pt) then
                pt:Remove()
                lights[ply] = nil
            end
        end
    end)
end
