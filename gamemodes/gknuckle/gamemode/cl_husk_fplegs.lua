-- First-person legs for Husks: look down and you see your own pants and boots.
-- A clientside copy of the local player's model mirrors its animation every frame, with
-- everything above the waist collapsed (ValveBiped.Bip01_Spine1 scaled to 0: torso, head,
-- hypervisor, mouth, crystals and the outline shell all go with it), so only the hips and
-- legs remain. Hidden in third person, when dead or legless, in vehicles and when the view
-- isn't your own eyes. Pants colours / skin / leg bodygroups follow the real player.
-- No visor name tag or mouth is drawn: those only render for real players (cl_husk.lua).
GK.Husk = GK.Husk or {}

local cvLegs = CreateClientConVar("gk_husk_fplegs", "1", true, false, "Draw your Husk legs in first person")
local BACK = 6          -- push the legs back a little so the hips don't clip the near plane when looking down

local legs, legsModel, spineBone, sync
local function ensure(ply)
    local mdl = ply:GetModel()
    if IsValid(legs) and legsModel == mdl then return legs end
    if IsValid(legs) then legs:Remove() end
    legs = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
    if not IsValid(legs) then return end
    -- drawn by the engine in the normal opaque pass (no shared render hook to be cut short)
    legs:SetNoDraw(false)
    legs:SetRenderBounds(Vector(-40, -40, -10), Vector(40, 40, 80))
    legs.RenderOverride = function(self)
        local p = LocalPlayer()
        if not self.GK_Show then return end
        sync(p, self)
        self:DrawModel()
    end
    legs.GK_HuskOwnerExplicit = ply           -- matproxies (pants, crystals) resolve to the player
    legsModel = mdl
    spineBone = legs:LookupBone("ValveBiped.Bip01_Spine1")
    return legs
end
GK.Husk.FPLegsEntity = function() return legs end

local function shouldDraw(ply)
    if not cvLegs:GetBool() or not IsValid(ply) or not ply:Alive() then return false end
    -- Gameplay's sh_legs.lua (GK_FirstPersonLegs) owns first-person legs when present: never draw a second pair
    local pd = hook.GetTable().PostDrawOpaqueRenderables
    if pd and pd.GK_FirstPersonLegs then return false end
    if not (GK.IsHusk and GK.IsHusk(ply)) then return false end
    if ply:ShouldDrawLocalPlayer() or ply:InVehicle() or GetViewEntity() ~= ply then return false end
    if ply:GetNW2Bool("gk_legless", false) then return false end
    if GK.IsRagdolled and GK.IsRagdolled(ply) then return false end
    return true
end

function sync(ply, ent)
    ent:SetSkin(ply:GetSkin())
    for _, bg in ipairs(ply:GetBodyGroups() or {}) do ent:SetBodygroup(bg.id, ply:GetBodygroup(bg.id)) end
    ent:SetSequence(ply:GetSequence())
    ent:SetCycle(ply:GetCycle())
    ent:SetPlaybackRate(0)
    for i = 0, ply:GetNumPoseParameters() - 1 do
        local name = ply:GetPoseParameterName(i)
        local lo, hi = ply:GetPoseParameterRange(i)
        local v = ply:GetPoseParameter(name)           -- client: 0..1 of the range
        if lo and hi then ent:SetPoseParameter(name, lo + (hi - lo) * v) end
    end
    -- Gameplay's bone scaling (legless calves etc.) carries over; then hide the upper body
    for b = 0, ply:GetBoneCount() - 1 do ent:ManipulateBoneScale(b, ply:GetManipulateBoneScale(b)) end
    if spineBone then ent:ManipulateBoneScale(spineBone, vector_origin) end
    local yaw = Angle(0, ply:GetRenderAngles().y, 0)
    ent:SetPos(ply:GetPos() - yaw:Forward() * BACK)
    ent:SetAngles(yaw)
    ent:InvalidateBoneCache()
end

hook.Add("Think", "GK_HuskFPLegs", function()
    local ply = LocalPlayer()
    local show = shouldDraw(ply)
    if not show then
        if IsValid(legs) then legs.GK_Show = false end
        return
    end
    local ent = ensure(ply)
    if IsValid(ent) then ent.GK_Show = true sync(ply, ent) end   -- keep position fresh for culling
end)

hook.Add("ShutDown", "GK_HuskFPLegs", function() if IsValid(legs) then legs:Remove() end end)
