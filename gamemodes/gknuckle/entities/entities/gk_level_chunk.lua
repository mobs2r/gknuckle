AddCSLuaFile()

-- A 512-unit cell of a level piece's collision. Big level pieces are split
-- into these so movement traces only test the triangles near the player
-- instead of a whole room's worth (one giant mesh tanked the framerate).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Level Collision"
ENT.Spawnable = false

-- 1024 (not 512): every chunk is a networked edict, and a 95k-triangle Nest
-- room at 512 made ~400 of them; four such rooms blew past the 2048 networked
-- edict limit and crashed the engine.
GK.LEVEL_CELL = 1024
-- Diagnostic switch (default on): build the chunk collide on the client too.
CreateConVar("gk_chunk_maxtris", "400", { FCVAR_REPLICATED }, "Most triangles in one level collision chunk")
CreateConVar("gk_chunk_pool", "1", { FCVAR_REPLICATED }, "Reuse retired level chunks (0: remove them as before)")
CreateConVar("gk_chunk_trace", "0", { FCVAR_REPLICATED }, "Diagnostic: print every chunk collide build")
CreateConVar("gk_chunk_keepcache", "0", { FCVAR_REPLICATED }, "Diagnostic: keep cached chunk triangles after a piece goes")
CreateConVar("gk_chunk_physdestroy", "1", { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "PhysicsDestroy level chunks before removing them")
local cvClPhys = CreateConVar("gk_chunk_clphys", "1", { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Build level chunk collision on the client as well")

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Piece")
    self:NetworkVar("Int", 0, "Cell")
    self:NetworkVar("Int", 1, "Gen")
end

local chunkCache = {}
-- Live chunks per piece; the cached triangles are dropped once the last chunk of
-- a piece is gone (a few hundred rooms of cached triangles exhausted Lua's heap).
local liveChunks = {}

-- All triangles of a piece, read straight from its compiled model parts
-- (util.GetModelMeshes), so no separate collision file is needed. Falls back
-- to the old data_static/<piece>_col.txt if the model can't be read.
function GK.LevelTriangles(piece)
    local layout = GK.LevelLayout(piece)
    local verts, dropped = {}, 0
    for _, part in ipairs(layout.parts or { piece }) do
        local path = "models/gknuckle/levels/" .. part .. ".mdl"
        util.PrecacheModel(path)
        local meshes = util.GetModelMeshes(path)
        for _, mesh in ipairs(meshes or {}) do
            local tri = mesh.triangles
            for i = 1, #tri - 2, 3 do
                -- Skip degenerate triangles (repeated vertices, zero area): vphysics
                -- prints "Degenerate Triangle" for them and the resulting collide can
                -- later fault inside vphysics.dll when another object touches it.
                local a, b, c = tri[i].pos, tri[i + 1].pos, tri[i + 2].pos
                local n = (b - a):Cross(c - a)
                if n:LengthSqr() > 1e-4 and a:DistToSqr(b) > 1e-4 and b:DistToSqr(c) > 1e-4 and a:DistToSqr(c) > 1e-4 then
                    verts[#verts + 1] = { pos = a }
                    verts[#verts + 1] = { pos = b }
                    verts[#verts + 1] = { pos = c }
                else
                    dropped = dropped + 1
                end
            end
        end
    end
    if #verts == 0 then
        local fallback = GK.LevelCollision(piece)
        print(("[gKnuckle] level %s: no model mesh data, collision from data file (%d tris)"):format(piece, fallback and #fallback / 3 or 0))
        return fallback
    end
    print(("[gKnuckle] level %s: collision from model (%d tris, %d degenerate dropped)"):format(piece, #verts / 3, dropped))
    return verts
end

-- Triangles of a piece grouped by cell (keyed by an int built from cell x/y/z).
function GK.LevelChunks(piece)
    if chunkCache[piece] then return chunkCache[piece] end
    local verts = GK.LevelTriangles(piece)
    if not verts then return nil end
    -- Bucket by 1024 u cell, then split any cell over MAX_CELL_TRIS into eighths (512,
    -- then 256 u). Dense cells must stay small: vphysics builds a big cell collide in a
    -- buffer of its own pages and reads a few bytes past its end, which faulted
    -- (vphysics.dll+0x8a88c, read at the first byte of an unmapped page) whenever the next
    -- page happened to be unmapped (2026-10-11: 2,239-triangle cells in Pipeworks rooms).
    -- Key: level * 2^27 + (cx+256) * 2^18 + (cy+256) * 2^9 + (cz+256), fits a signed int.
    local MAX_CELL_TRIS = GetConVar("gk_chunk_maxtris"):GetInt()
    local cells = {}
    local function split(list, S, level)
        local sub = {}
        for i = 1, #list, 3 do
            local a, b, c = list[i].pos, list[i + 1].pos, list[i + 2].pos
            local cx = math.floor((a.x + b.x + c.x) / 3 / S)
            local cy = math.floor((a.y + b.y + c.y) / 3 / S)
            local cz = math.floor((a.z + b.z + c.z) / 3 / S)
            local key = level * 134217728 + (cx + 256) * 262144 + (cy + 256) * 512 + (cz + 256)
            local cell = sub[key]
            if not cell then cell = {} sub[key] = cell end
            cell[#cell + 1] = list[i]
            cell[#cell + 1] = list[i + 1]
            cell[#cell + 1] = list[i + 2]
        end
        -- Pack the pieces of a split cell back into as few chunks as fit (first fit by
        -- size), so splitting does not multiply the entity count (edicts are capped at 2048).
        local small, keys = {}, {}
        for key, cell in pairs(sub) do
            if #cell > MAX_CELL_TRIS * 3 and S > 128 then split(cell, S / 2, level + 1)
            elseif level == 0 then cells[key] = cell
            else small[#small + 1] = { key, cell } end
        end
        table.sort(small, function(x, y) return #x[2] > #y[2] end)
        local bins = {}
        for _, it in ipairs(small) do
            local placed = false
            for _, bin in ipairs(bins) do
                if #bin.list + #it[2] <= MAX_CELL_TRIS * 3 then
                    for _, vv in ipairs(it[2]) do bin.list[#bin.list + 1] = vv end
                    placed = true break
                end
            end
            if not placed then
                local list = {}
                for _, vv in ipairs(it[2]) do list[#list + 1] = vv end
                bins[#bins + 1] = { key = it[1], list = list }
            end
        end
        for _, bin in ipairs(bins) do cells[bin.key] = bin.list end
    end
    split(verts, GK.LEVEL_CELL, 0)
    chunkCache[piece] = cells
    GK.ChunkKeys = GK.ChunkKeys or {}
    if not GK.ChunkKeys[piece] then
        local keys = {}
        for key in pairs(cells) do keys[#keys + 1] = key end
        GK.ChunkKeys[piece] = keys
    end
    return cells
end
-- The triangle cache is only needed while chunks are being built: drop it a few seconds
-- after the last build of a piece (pooled chunks keep their collides, not the triangles).
local function releaseCache(piece)
    timer.Create("GKChunkCache_" .. piece, 3, 1, function() chunkCache[piece] = nil end)
end

-- ---- Chunk pool (server) --------------------------------------------------------------
-- Collides made with PhysicsFromMesh are never freed when their entity is removed (GMod
-- leaks them: ~9 MB per build of a 65k-triangle room), and in the 32-bit game a long
-- session of runs exhausted the address space until vphysics faulted (0.3.10.2 / 0.4,
-- vphysics.dll+0x8a88c). So chunks are not removed when their room goes: they are parked
-- (no collisions, not solid) and the next spawn of the same piece takes them back and
-- moves them, reusing the collide. The pool is capped; only chunks evicted past the cap
-- are removed (and leak), which a normal rotation of regions rarely reaches.
GK.ChunkPool = GK.ChunkPool or { byKey = {}, count = 0, seq = 0 }
GK.CHUNK_POOL_CAP = 250
local function poolKey(piece, cell) return piece .. "#" .. cell end
function GK.ChunkTake(piece, cell)
    local pool = GK.ChunkPool
    local list = pool.byKey[poolKey(piece, cell)]
    while list and #list > 0 do
        local c = table.remove(list)
        pool.count = pool.count - 1
        if IsValid(c) and c.GKParked then return c end
    end
    return nil
end
local function evict()
    local pool = GK.ChunkPool
    local tooMany = function() return pool.count > GK.CHUNK_POOL_CAP or ents.GetEdictCount() > 1500 end
    if not tooMany() then return end
    local all = {}
    for _, list in pairs(pool.byKey) do for _, c in ipairs(list) do if IsValid(c) then all[#all + 1] = c end end end
    table.sort(all, function(a, b) return (a.GKParkSeq or 0) < (b.GKParkSeq or 0) end)
    local i = 1
    while tooMany() and i <= #all do
        local c = all[i]
        local list = pool.byKey[poolKey(c:GetPiece(), c:GetCell())]
        for k, x in ipairs(list or {}) do if x == c then table.remove(list, k) pool.count = pool.count - 1 break end end
        c.GKParked = false
        c:Remove()
        i = i + 1
    end
end
function GK.ChunkPark(c)
    local pool = GK.ChunkPool
    local key = poolKey(c:GetPiece(), c:GetCell())
    pool.byKey[key] = pool.byKey[key] or {}
    pool.seq = pool.seq + 1
    c.GKParked, c.GKParkSeq = true, pool.seq
    table.insert(pool.byKey[key], c)
    pool.count = pool.count + 1
    evict()
end
function GK.ChunkPoolStats()
    local pool, keys = GK.ChunkPool, 0
    for _ in pairs(pool.byKey) do keys = keys + 1 end
    return pool.count, keys
end

function ENT:BuildPhysics()
    local cells = GK.LevelChunks(self:GetPiece())
    local verts = cells and cells[self:GetCell()]
    if not verts or #verts == 0 then return end
    if SERVER and GetConVar("gk_chunk_trace"):GetBool() then print(("[GKCHUNK] build %s/%d tris %d at %s"):format(self:GetPiece(), self:GetCell(), #verts / 3, tostring(self:GetPos()))) end
    if not self:PhysicsFromMesh(verts) then
        print(("[gKnuckle] chunk %s/%d: PhysicsFromMesh failed (%d tris)"):format(self:GetPiece(), self:GetCell(), #verts / 3))
        return
    end
    self:SetSolid(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:EnableCustomCollisions(true)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    -- Tight bounds so the engine only considers this chunk near its triangles.
    local mins, maxs = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, v in ipairs(verts) do
        mins.x = math.min(mins.x, v.pos.x) mins.y = math.min(mins.y, v.pos.y) mins.z = math.min(mins.z, v.pos.z)
        maxs.x = math.max(maxs.x, v.pos.x) maxs.y = math.max(maxs.y, v.pos.y) maxs.z = math.max(maxs.z, v.pos.z)
    end
    self:SetCollisionBounds(mins, maxs)
    liveChunks[self:GetPiece()] = (liveChunks[self:GetPiece()] or 0) + 1
    self.GKCounted = true
    self.GKGen = self:GetGen()
    releaseCache(self:GetPiece())
end

-- Stop colliding now and free the collide a few ticks later, after vphysics has
-- simulated without this chunk and dropped every contact pair with it.
function ENT:Retire()
    if self.GKRetired then return end
    self.GKRetired = true
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableCollisions(false) end
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    -- Park a few ticks later, after vphysics has simulated without this chunk and dropped
    -- every contact pair with it; a chunk that never got a collide is simply removed.
    timer.Simple(0.25, function()
        if not IsValid(self) then return end
        if IsValid(self:GetPhysicsObject()) and GetConVar("gk_chunk_pool"):GetBool() then GK.ChunkPark(self) else self:Remove() end
    end)
end

-- Bring a parked chunk back for a new copy of its piece at `pos`.
function ENT:Unpark(pos)
    self.GKParked, self.GKRetired = false, false
    self:SetPos(pos)
    self:SetAngles(angle_zero)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetPos(pos)
        phys:SetAngles(angle_zero)
        phys:EnableMotion(false)
        phys:EnableCollisions(true)
    end
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:SetGen(self:GetGen() + 1)
end

function ENT:OnRemove()
    if CLIENT and GetConVar("gk_chunk_physdestroy"):GetBool() then self:PhysicsDestroy() end
    if not self.GKCounted then return end
    local piece = self:GetPiece()
    liveChunks[piece] = (liveChunks[piece] or 1) - 1
    if liveChunks[piece] <= 0 then
        liveChunks[piece] = nil
        if not GetConVar("gk_chunk_keepcache"):GetBool() then chunkCache[piece] = nil end
    end
end

function ENT:Initialize()
    self:DrawShadow(false)
    if SERVER then self:SetNoDraw(true) end
    if self:GetPiece() ~= "" and (SERVER or cvClPhys:GetBool()) then
        self.GKBuilt = true
        -- Built inside Initialize on both realms: deferring the server build a tick
        -- (tried 2026-10-09) crashed vphysics when a player was already inside the
        -- chunk's bounds, so the collide exists before anything can touch it.
        self:BuildPhysics()
    end
end

if CLIENT then
    function ENT:Think()
        if not self.GKBuilt and self:GetPiece() ~= "" and cvClPhys:GetBool() then
            self.GKBuilt = true
            self:BuildPhysics()
        end
        if self.GKGen and self.GKGen ~= self:GetGen() then
            self.GKGen = self:GetGen()
            local phys = self:GetPhysicsObject()
            if IsValid(phys) then phys:SetPos(self:GetPos()) phys:SetAngles(self:GetAngles()) end
        end
    end
    function ENT:Draw() end
end
