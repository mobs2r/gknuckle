AddCSLuaFile()

-- An item lying in the world. Click it with an empty mind-hand to pick it up.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Item"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ItemClass")
end

function ENT:KeyValue(k, v)
    if k == "itemclass" then self.GKItemClass = v end
end

if SERVER then
    function ENT:Initialize()
        local class = self.GKItemClass or self:GetItemClass()
        local def = GK.ItemDef(class) or GK.ItemDef("brick")
        self.GKItemClass = def.class
        self:SetItemClass(def.class)
        -- A missing or bad model must never take the server down: fall back.
        local m = def.model
        if not m or not util.IsValidModel(m) then m = "models/props_junk/cardboard_box004a.mdl" end
        self:SetModel(m)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        -- A model with a broken collision mesh (the foodbar's spans thousands of
        -- units) would swallow every trace and click near it: use a box round
        -- what you can see instead.
        local function sane(mn, mx) return (mx - mn):Length() < 150 end
        local function seenBox()
            local mn, mx = self:GetModelRenderBounds()
            if not sane(mn, mx) then mn, mx = Vector(-4, -4, 0), Vector(4, 4, 4) end
            return mn, mx
        end
        if self.GK_Asleep then
            -- Placed by a run room (GK_Asleep, set before Spawn): no physics
            -- object at all, it just sits where WK put it until someone takes
            -- it. Physics objects spawned by room building are what crashed
            -- vphysics in runs (see gk_turret.lua); dropped items are normal.
            self:SetSolid(SOLID_BBOX)
            if sane(self:OBBMins(), self:OBBMaxs()) then self:SetCollisionBounds(self:OBBMins(), self:OBBMaxs())
            else self:SetCollisionBounds(seenBox()) end
            self:SetMoveType(MOVETYPE_NONE)
            -- Set down on whatever is just below (WK places them a little high).
            local p = self:GetPos()
            local tr = util.TraceLine({ start = p, endpos = p - Vector(0, 0, 48), mask = MASK_SOLID, filter = self }) -- (room collision is entities)
            if tr.Hit and not tr.StartSolid then self:SetPos(tr.HitPos - Vector(0, 0, (self:GetCollisionBounds()).z)) end
            return
        end
        self:PhysicsInit(SOLID_VPHYSICS)
        local ph = self:GetPhysicsObject()
        if IsValid(ph) and not sane(ph:GetAABB()) then ph = nil end
        if not IsValid(ph) then
            if sane(self:OBBMins(), self:OBBMaxs()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs())
            else self:PhysicsInitBox(seenBox()) end
        end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end
end

-- Spawn menu entries, one per item.
hook.Add("Initialize", "GK_ItemSpawnList", function()
    for class, def in pairs(GK.Items) do
        if not def.worldClass then
            list.Set("SpawnableEntities", "gk_item_" .. class, {
                PrintName = def.name, ClassName = "gk_item", Category = "gKnuckle",
                KeyValues = { itemclass = class },
            })
        end
    end
end)
