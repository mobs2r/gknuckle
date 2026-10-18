AddCSLuaFile()

-- One White Knuckle level piece: the converted static model for looks, plus
-- solid collision built from the level's own triangles (data_static/gknuckle/levels).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Level Piece"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Piece")
    self:NetworkVar("Bool", 0, "CollisionOnly")
end

-- Placed in compiled gk_ maps (tools/make_wk_map.js): the map's prop_static
-- draws the room, this entity only supplies its solid collision.
function ENT:KeyValue(k, v)
    if k == "piece" then self.GKPiece = v end
    if k == "collisiononly" then self.GKCollisionOnly = tobool(v) end
end

local cache = {}

-- Collision triangles, one per line (9 numbers). Cached per piece.
function GK.LevelCollision(piece)
    if cache[piece] then return cache[piece] end
    local path = "gknuckle/levels/" .. piece .. "_col.txt"
    local text = file.Read(path, "DATA") or file.Read("data_static/" .. path, "GAME")
    if not text then return nil end
    local verts = {}
    for line in string.gmatch(text, "[^\n]+") do
        local n = {}
        for num in string.gmatch(line, "%S+") do n[#n + 1] = tonumber(num) end
        if #n == 9 then
            verts[#verts + 1] = { pos = Vector(n[1], n[2], n[3]) }
            verts[#verts + 1] = { pos = Vector(n[4], n[5], n[6]) }
            verts[#verts + 1] = { pos = Vector(n[7], n[8], n[9]) }
        end
    end
    cache[piece] = verts
    return verts
end

-- Collision lives in gk_level_chunk entities (one per 512-unit cell); the
-- server spawns them, clients build each chunk's mesh as it arrives.
function ENT:BuildPhysics()
    if CLIENT then return end
    -- Cell keys come from a small per-piece list once known, so a piece whose chunks are
    -- all in the pool is rebuilt without reading its model meshes again.
    local piece = self:GetPiece()
    local keys = GK.ChunkKeys and GK.ChunkKeys[piece]
    if not keys then
        if not GK.LevelChunks(piece) then return end
        keys = GK.ChunkKeys[piece]
    end
    self.GKChunks = {}
    for _, key in ipairs(keys) do
        local chunk = GK.ChunkTake and GK.ChunkTake(piece, key)
        if chunk then
            chunk:Unpark(self:GetPos())
        else
            chunk = ents.Create("gk_level_chunk")
            chunk:SetPiece(piece)
            chunk:SetCell(key)
            chunk:SetPos(self:GetPos())
            chunk:Spawn()
        end
        table.insert(self.GKChunks, chunk)
    end
end

function ENT:OnRemove()
    -- Chunks retire in two steps (collisions off now, entity gone a few ticks
    -- later) so nothing in vphysics still holds a contact with a freed collide.
    for _, chunk in ipairs(self.GKChunks or {}) do
        if IsValid(chunk) then
            if chunk.Retire then chunk:Retire() else chunk:Remove() end
        end
    end
end

function ENT:Initialize()
    if SERVER then
        if self.GKPiece then self:SetPiece(self.GKPiece) end
        if self.GKCollisionOnly then self:SetCollisionOnly(true) end
        self:SetModel("models/gknuckle/levels/" .. self:GetPiece() .. ".mdl")
        self:DrawShadow(false)
        -- In compiled maps the prop_static draws the room; this is collision only.
        if self:GetCollisionOnly() then self:SetNoDraw(true) end
    end
    if SERVER or self:GetPiece() ~= "" then
        self.GKBuilt = true
        self:BuildPhysics()
    end
end

if CLIENT then
    -- The piece name can arrive after Initialize on clients; build then.
    function ENT:Think()
        if not self.GKBuilt and self:GetPiece() ~= "" then
            self.GKBuilt = true
            self:BuildPhysics()
            local mins, maxs = self:GetModelBounds()
            if mins then self:SetRenderBounds(mins, maxs) end
        end
    end

    function ENT:Draw()
        if not self:GetCollisionOnly() then self:DrawModel() end
    end
end
