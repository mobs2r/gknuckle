AddCSLuaFile()

-- Falling trash (WK's HAZ_TrashSpawner in the garbage chutes): while anyone
-- is climbing below it, junk drops down the shaft every few seconds. A hit
-- stings and knocks you off your hold. Placed by sv_creatures.lua from the
-- room's spawner. No physics objects: the junk is tossed, not simulated.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Trash Chute"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

if SERVER then
    local JUNK = {
        "models/props_junk/garbage_metalcan001a.mdl", "models/props_junk/garbage_milkcarton001a.mdl",
        "models/props_junk/garbage_plasticbottle001a.mdl", "models/props_junk/garbage_newspaper001a.mdl",
        "models/props_junk/garbage_takeoutcarton001a.mdl", "models/props_junk/metal_paintcan001a.mdl",
    }
    local RANGE = 1600 -- climbers this far below (and roughly under) it

    function ENT:Initialize()
        self:SetModel("models/hunter/blocks/cube025x025x025.mdl")
        self:SetNoDraw(true) -- an invisible marker
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self.GK_Next = CurTime() + math.Rand(2, 5)
    end


    function ENT:Think()
        local ct = CurTime()
        if ct >= self.GK_Next then
            self.GK_Next = ct + math.Rand(3, 7)
            local pos = self:GetPos()
            for _, p in ipairs(player.GetAll()) do
                local d = p:GetPos() - pos
                if p:Alive() and d.z < 0 and d.z > -RANGE and Vector(d.x, d.y, 0):Length() < 400 then
                    local j = ents.Create("gk_trash")
                    j:SetModel(JUNK[math.random(#JUNK)])
                    j:SetPos(pos + VectorRand() * 30)
                    j:Spawn()
                    break
                end
            end
        end
        self:NextThink(ct + 0.5)
        return true
    end
end
