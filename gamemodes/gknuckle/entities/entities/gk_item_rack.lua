AddCSLuaFile()

-- A hub item rack: a small plinth with one free item lying on it (pitons,
-- hammers, whatever the map asks for). Take it (click it with an empty
-- mind-hand) and a fresh one appears a few seconds later. Free, unlike the
-- vending machines in a run.
-- Keyvalues: item = item class (GK.Items key), respawn = seconds (default 4),
-- plinth = 0 for no block (the item just lies on a shelf or the floor).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Item Rack"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Category = "gKnuckle"

ENT.GKItem = "piton"
ENT.GKRespawn = 4

function ENT:KeyValue(k, v)
    if k == "item" then self.GKItem = v end
    if k == "respawn" then self.GKRespawn = tonumber(v) or self.GKRespawn end
    if k == "plinth" then self.GKNoPlinth = v == "0" end
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
        self:SetMaterial("models/gknuckle/items/brick/defaultmaterial")
        if self.GKNoPlinth then
            self:SetNoDraw(true)
            self:SetSolid(SOLID_NONE)
            self:SetMoveType(MOVETYPE_NONE)
            self:Restock()
            return
        end
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:Restock()
    end

    function ENT:Restock()
        if not GK.ItemDef(self.GKItem) then return end
        local def = GK.ItemDef(self.GKItem)
        local it = ents.Create(def.worldClass or "gk_item")
        it.GKItemClass = self.GKItem
        if it.SetItemClass then it:SetItemClass(self.GKItem) end
        it:SetPos(self:GetPos() + Vector(0, 0, self.GKNoPlinth and 6 or self:OBBMaxs().z + 6))
        it:SetAngles(self:GetAngles())
        it:Spawn()
        it.GK_FromRack = self
        self.GK_Current = it
    end

    function ENT:Think()
        -- Taken (or knocked off and picked up): put another one out.
        local it = self.GK_Current
        if not IsValid(it) and not self.GK_RestockAt then
            self.GK_RestockAt = CurTime() + self.GKRespawn
        elseif IsValid(it) and it:GetPos():DistToSqr(self:GetPos()) > 120 * 120 then
            self.GK_Current = nil -- someone knocked it away; it's theirs now
        end
        if self.GK_RestockAt and CurTime() >= self.GK_RestockAt then
            self.GK_RestockAt = nil
            self:Restock()
        end
        self:NextThink(CurTime() + 0.5)
        return true
    end
end
