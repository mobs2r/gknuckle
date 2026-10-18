-- Hand items, White Knuckle style: items live in your bag (Tab), a hand, or a
-- pocket (Q = left, E = right). A hand holding an item can't climb; its mouse
-- button uses the item instead. Reloading takes both hands.
--
-- Each item: name, model (world + held), weight, stack (max count), and
-- server-side Use(ply, side, item) returning true if the item was used up.

local C = GK.Config

GK.Items = GK.Items or {}

local function register(class, def)
    def.class = class
    GK.Items[class] = def
end

function GK.ItemDef(class) return GK.Items[class] end
GK.RegisterItem = register -- more items: sh_items_more.lua

-- WK reloading: a gun only takes ammo you're physically holding. Click it
-- empty (or press R) with its ammo in your other hand and you load from that:
-- a flare into the flare gun, rounds from a box into the revolver or handgun.
-- spec = { ammo = item class, max = rounds it holds, time = s, sound }
function GK.AmmoReload(ply, side, item, spec)
    if item.data.clip >= spec.max then return false end
    local otherSide = side == "l" and "r" or "l"
    local other = GK.Inv.HandItem(ply, otherSide)
    if not other or other.class ~= spec.ammo then
        ply:EmitSound("Weapon_Pistol.Empty")
        return false
    end
    local have = other.data and other.data.count or 1
    local take = math.min(spec.max - item.data.clip, have)
    ply:SetNW2Float("gk_busy_until", CurTime() + spec.time)
    ply:EmitSound(spec.sound)
    timer.Simple(spec.time, function()
        if not IsValid(ply) then return end
        -- Still holding both?
        if GK.Inv.HandItem(ply, side) ~= item or GK.Inv.HandItem(ply, otherSide) ~= other then return end
        item.data.clip = item.data.clip + take
        other.data = other.data or {}
        other.data.count = have - take
        if other.data.count <= 0 then GK.Inv.Get(ply).slots["hand_" .. otherSide] = nil end
        GK.Inv.Sync(ply)
    end)
    return true
end

-- Throws an entity from the hand on that side.
local function throwFrom(ply, side, class, speed, setup)
    local right = ply:EyeAngles():Right() * (side == "r" and 8 or -8)
    local ent = ents.Create(class)
    if not IsValid(ent) then return end
    ent:SetPos(ply:GetShootPos() + ply:GetAimVector() * 18 + right)
    ent:SetAngles(ply:EyeAngles())
    ent:SetOwner(ply)
    if setup then setup(ent) end
    ent:Spawn()
    ent:Activate()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(ply:GetAimVector() * speed + ply:GetVelocity())
        phys:AddAngleVelocity(Vector(math.Rand(-400, 400), math.Rand(200, 600), 0))
    end
    ply:EmitSound("weapons/slam/throw.wav", 65, 105)
    return ent
end
GK.ThrowFrom = throwFrom

-- Throws a rebar of the given kind (gk_rebar_thrown) dead straight down the crosshair.
function GK.ThrowRebar(ply, kind)
    local bar = ents.Create("gk_rebar_thrown")
    -- The tip starts at your eye (it traces from its tip), the shaft trails behind,
    -- and it doesn't pick up your drift.
    bar:SetPos(ply:GetShootPos() - ply:GetAimVector() * 49.7 * 0.75)
    bar:SetAngles(ply:EyeAngles())
    bar:SetOwner(ply)
    bar.GK_Kind = kind
    bar.GK_Vel = ply:GetAimVector() * GK.Config.RebarThrowSpeed
    bar:Spawn()
    -- Like WK, the throw takes you off the wall with a small shove (a little
    -- more on the ground; in the air it's capped at 0.5 m/s), and your hands
    -- can't grab again for 0.3 s.
    ply:SetVelocity(-ply:GetAimVector() * (ply:OnGround() and 60 or 20))
    local mind = ply:GetWeapon("gk_mind")
    if IsValid(mind) and mind.Grips then
        for side, g in pairs(mind.Grips) do if g.kind == "world" then mind:Release(side) end end
        mind.GripOutUntil = math.max(mind.GripOutUntil or 0, CurTime() + 0.3)
    end
    ply:EmitSound("gknuckle/rebar/throw.wav", 70, math.random(95, 105))
    return bar
end

-- HL2 .357, demade. Six in the cylinder; reload it WK-style from a box of
-- .357 rounds held in your other hand (GK.AmmoReload). It kicks hard (your view jumps and you're
-- shoved back), and it's held dead centre where the shot goes. A head hit
-- takes the head off; a leg hit takes the legs (no arms to take, they're gone).
register("revolver", {
    name = "Revolver",
    model = "models/weapons/w_357.mdl",
    weight = 2,
    clip = 6,
    newData = function() return { clip = 6 } end,
    hold = { pos = Vector(20, 0, -8), ang = Angle(0, 180, 0), centre = true }, -- out in the middle, where the shot goes
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) or (item.nextFire or 0) > CurTime() then return end
        item.nextFire = CurTime() + 0.7
        if item.data.clip <= 0 then
            GK.AmmoReload(ply, side, item, GK.RevolverAmmo)
            return
        end
        item.data.clip = item.data.clip - 1
        ply:EmitSound("Weapon_357.Single")
        local dir = ply:GetAimVector()
        ply:FireBullets({
            Src = ply:GetShootPos(), Dir = dir, Spread = Vector(0.012, 0.012, 0),
            Damage = 45, Force = 8, Num = 1, Attacker = ply, Tracer = 1,
            Callback = function(_, tr, dmg)
                local victim = tr.Entity
                if not IsValid(victim) or not victim:IsPlayer() or victim == ply then return end
                local part = GK.RebarBodyPart(victim, tr, dir)
                timer.Simple(0, function()
                    if not IsValid(victim) or not victim:Alive() then return end
                    if part == "head" then
                        local d = DamageInfo()
                        d:SetAttacker(ply) d:SetInflictor(ply) d:SetDamage(100) d:SetDamageType(DMG_BULLET)
                        GK.Decapitate(victim, dir, d)
                    elseif part == "legs" then
                        GK.RemoveLegs(victim)
                    end
                end)
            end,
        })
        -- Recoil: a real kick to where you're looking, not just a shake.
        local kick = Angle(-math.Rand(7, 10), math.Rand(-2.5, 2.5), 0)
        ply:SetEyeAngles(ply:EyeAngles() + kick)
        ply:ViewPunch(Angle(-12, kick.y, math.Rand(-3, 3)))
        ply:SetVelocity(-dir * 110)
        ply:SetAnimation(PLAYER_ATTACK1)
        GK.Inv.Sync(ply)
    end,
    Reload = function(ply, side, item) GK.AmmoReload(ply, side, item, GK.RevolverAmmo) end,
    Label = function(item) return tostring(item.data.clip) end,
})
GK.RevolverAmmo = { ammo = "bullet", max = 6, time = 2.4, sound = "weapons/357/357_reload1.wav" }

-- A .357 round, the only bullet there is (the revolver's the only gun). They
-- stack in your hand; hold them in the other hand to load the revolver.
register("bullet", {
    name = ".357 Round", model = "models/weapons/rifleshell.mdl", weight = 1, stack = 6,
    newData = function() return { count = 1 } end,
    hold = { scale = 1.6 },
    Label = function(item) return tostring(item.data.count or 1) end,
})

register("grenade", {
    name = "Grenade",
    model = "models/weapons/w_grenade.mdl",
    weight = 1,
    hold = { ang = Angle(-20, 0, 0) }, -- sits in the palm like a WK item
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        throwFrom(ply, side, "npc_grenade_frag", 1000, function(ent) ent:Fire("SetTimer", "2.5") end)
        return true
    end,
})

-- A boom bug in a jar (gk_boomjar_thrown): throw it and it goes off on impact
-- with the boom bug's blast. An impact grenade.
register("boomjar", {
    name = "Boom Jar",
    model = "models/props_lab/jar01a.mdl",
    weight = 1,
    hold = { ang = Angle(0, 0, 0) },
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        throwFrom(ply, side, "gk_boomjar_thrown", 900)
        return true
    end,
})

register("stun", {
    name = "Stun Grenade",
    model = "models/items/combine_rifle_ammo01.mdl",
    weight = 1,
    hold = { ang = Angle(0, 0, 0) },
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        throwFrom(ply, side, "gk_stun_grenade_thrown", 1000)
        return true
    end,
})

-- White Knuckle's "Rubble": weight 1, pocketable, thrown at 60 m/s, shatters on hit.
register("brick", {
    name = "Brick",
    model = "models/gknuckle/items/brick.mdl",
    weight = 1,
    hold = { ang = Angle(0, 30, 0) },
    worldClass = "gk_brick",     -- dropped/thrown as the physics brick
    pickupSound = "GK.BrickPickup",
    Use = function(ply, side, item)
        throwFrom(ply, side, "gk_brick", 2360)
        -- WK movement tech: throwing a brick hard shoves you back a little.
        ply:SetVelocity(-ply:GetAimVector() * 70)
        return true
    end,
})

-- White Knuckle's rebar: the real model and texture (gameplay_tools/make_rebar.ps1).
register("rebar", {
    name = "Rebar",
    model = "models/gknuckle/items/rebar.mdl",
    weight = 1,
    hold = { pos = Vector(14, 8, -9), ang = Angle(0, 6, 0), scale = 0.5, centre = true }, -- a spear, pointing where it goes
    pickupSound = "gknuckle/rebar/pickup.wav",
    -- Thrown like a spear (gk_rebar_thrown): sticks into walls as a handhold,
    -- takes heads and legs off, or runs a player through and pins them.
    Use = function(ply, side, item)
        if not GK.IsChipOnline(ply) then return end
        GK.ThrowRebar(ply, "rebar")
        ply:ViewPunch(Angle(-2, side == "r" and 1 or -1, 0))
        return true -- one rebar, one throw (WK)
    end,
})

-- What the vending machine (gk_vendor) sells, in button order (3 across):
-- item class or entity, CrabCoin price, and either White Knuckle's vending
-- icon or, for Half-Life gear, its HL2 HUD weapon glyph.
GK.ShopSlots = {
    { name = "brick",      price = 1,  icon = "brick",           item = "brick" },
    { name = "rebar",      price = 3,  icon = "rebar",           item = "rebar" },
    { name = "rebarrope",  price = 6,  icon = "rebarrope",       item = "rebarrope" },
    { name = "rebarexplo", price = 9,  icon = "rebar_explosive", item = "rebarexplo" },
    { name = "piton",      price = 1,  icon = "piton",           item = "piton" },
    { name = "autopiton",  price = 8,  icon = "autopiton",       item = "autopiton" },
    { name = "hammer",     price = 5,  icon = "grapplepiton",    item = "hammer" },
    { name = "grub",       price = 7,  icon = "grub",            item = "grub" },
    { name = "injector",   price = 8,  icon = "injector",        item = "injector" },
    { name = "pills",      price = 6,  icon = "pills",           item = "pills" },
    { name = "foodbar",    price = 3,  icon = "foodbar",         item = "foodbar" },
    { name = "bandage",    price = 4,  icon = "bandage",         item = "bandage" },
    { name = "blinkeye",   price = 8,  icon = "blinkeye",        item = "blinkeye" },
    { name = "beans",      price = 3,  icon = "foodbar",         item = "beans" },
    { name = "flaregun",   price = 10, icon = "flaregun",        item = "flaregun" },
    { name = "grenade",    price = 5,  glyph = "k",              item = "grenade" },
    { name = "stun",       price = 8,  glyph = "o",              item = "stun" },
    { name = "boomjar",    price = 6,  glyph = "k",              item = "boomjar" },
    { name = "revolver",   price = 15, glyph = "e",              item = "revolver" },
    { name = "bullet",     price = 2,  glyph = "q",              item = "bullet", data = { count = 3 } },
    { name = "flare",      price = 3,  icon = "flares",          item = "flare", data = { count = 2 } },
    { name = "crowbar",    price = 7,  glyph = "c",              item = "crowbar" },
    { name = "battery",    price = 6,  glyph = "*",              item = "battery" },
    { name = "surge",      price = 12, glyph = "m",              entity = "gk_surge", model = "models/items/combine_rifle_ammo01.mdl" },
}