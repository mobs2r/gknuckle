-- Legs you can lose, carry, and put back (yours or someone else's).
--
--   A leg that comes off (sv_dismember.lua) drops as a leg you can pick up
--   (gk_item "leg_l" / "leg_r"), carrying the colour of the trousers it wore.
--   With a leg in your hand, its button puts it back on: on yourself if you
--   are missing one, otherwise on the husk you're looking at (a teammate, or
--   anyone: stealing legs is fair). With no legs at all you crawl until you
--   die or someone brings one back.
--   Trouser colours: random for everyone in the hub, one colour per team in
--   a run; a leg keeps its own colour wherever it ends up, so a replaced leg
--   shows. NW2 vectors gk_pants_l, gk_pants_r, gk_pants_hip (0-1), read by
--   the Husk model's GKHuskPants material proxy.
--   Looking down in first person you see your own legs.
AddCSLuaFile()

local SIDES = { l = "ValveBiped.Bip01_L_Calf", r = "ValveBiped.Bip01_R_Calf" }
local LEG_MODEL = { l = "models/player/gknuckle/husk_v2_gib_leg_l.mdl", r = "models/player/gknuckle/husk_v2_gib_leg_r.mdl" }

local function legGone(ply, side) return not GK.HasLegs(ply) or ply:GetNW2Bool("gk_leg_" .. side .. "_gone", false) end
function GK.MissingLeg(ply)
    if legGone(ply, "r") then return "r" end
    if legGone(ply, "l") then return "l" end
end

for _, side in ipairs({ "l", "r" }) do
    GK.RegisterItem("leg_" .. side, {
        name = side == "l" and "Left Leg" or "Right Leg",
        model = util.IsValidModel and util.IsValidModel(LEG_MODEL[side]) and LEG_MODEL[side] or "models/gibs/hgibs_scapula.mdl",
        weight = 3,
        pickupSound = "physics/flesh/flesh_squishy_impact_hard1.wav",
        -- Click with it in hand: on to yourself, or onto whoever you're looking at.
        Use = function(ply, hand, item)
            if CLIENT then return false end
            local target = GK.MissingLeg(ply) and ply
            if not target then
                local tr = util.TraceHull({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 90,
                    mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), mask = MASK_SHOT_HULL,
                    filter = function(e) return e ~= ply and (e:IsPlayer() or e:IsWorld()) end }) -- only husks (and walls) count
                if IsValid(tr.Entity) and tr.Entity:IsPlayer() and GK.MissingLeg(tr.Entity) then target = tr.Entity end
            end
            if not target then ply:EmitSound("physics/flesh/flesh_impact_bullet1.wav", 55, 130) return false end
            GK.AttachLeg(target, item.data and item.data.pants)
            return true -- the leg is used up
        end,
    })
end

if SERVER then
    -- Trouser colours.
    local function randomPants() local c = HSVToColor(math.random(0, 359), math.Rand(0.35, 0.8), math.Rand(0.35, 0.85)) return Vector(c.r / 255, c.g / 255, c.b / 255) end
    function GK.SetPants(ply, col)
        ply:SetNW2Vector("gk_pants_l", col) ply:SetNW2Vector("gk_pants_r", col) ply:SetNW2Vector("gk_pants_hip", col)
    end
    hook.Add("PlayerSpawn", "GK_Pants", function(ply)
        if GK.ArenaOf(ply) == 0 then GK.SetPants(ply, randomPants()) end
    end)
    hook.Add("GK_ArenaStart", "GK_TeamPants", function(a)
        local byTeam = {}
        for _, p in ipairs(a.players) do
            local t = a.teams[p] or 0
            byTeam[t] = byTeam[t] or randomPants()
            if IsValid(p) then GK.SetPants(p, byTeam[t]) end
        end
    end)

    -- A lost leg on the floor, ready to be picked up.
    function GK.DropLeg(ply, side, pos)
        local it = ents.Create("gk_item")
        it.GKItemClass = "leg_" .. side
        it.GKItemData = { pants = ply:GetNW2Vector("gk_pants_" .. side, Vector(0.4, 0.4, 0.4)), from = ply:SteamID64() }
        it:SetPos(pos or ply:GetPos() + Vector(0, 0, 12))
        it:Spawn()
        it:SetNW2Vector("gk_pants", it.GKItemData.pants)
        local phys = it:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(ply:GetVelocity() + VectorRand() * 60 + Vector(0, 0, 90)) end
        SafeRemoveEntityDelayed(it, 300)
        return it
    end

    -- Put a leg back: the missing side (right first), in the leg's own colour.
    function GK.AttachLeg(ply, pants)
        local side = GK.MissingLeg(ply)
        if not side then return false end
        if not GK.HasLegs(ply) then
            -- No legs at all: this becomes your one leg.
            ply:SetNW2Bool("gk_legless", false)
            ply:SetJumpPower(GK.Config.JumpPower)
            ply:SetNW2Bool("gk_leg_l_gone", side ~= "l")
            ply:SetNW2Bool("gk_leg_r_gone", side ~= "r")
            local other = side == "l" and "r" or "l"
            local b = ply:LookupBone(SIDES[other]) if b then ply:ManipulateBoneScale(b, vector_origin) end
            if GK.Husk and GK.Husk.SetLimbs then GK.Husk.SetLimbs(ply, false, nil) end
        else
            ply:SetNW2Bool("gk_leg_" .. side .. "_gone", false)
        end
        local bone = ply:LookupBone(SIDES[side])
        if bone then ply:ManipulateBoneScale(bone, Vector(1, 1, 1)) end
        ply.GK_LegHP = ply.GK_LegHP or {}
        ply.GK_LegHP[side] = GK.Config.LegHealth
        if pants then ply:SetNW2Vector("gk_pants_" .. side, pants) end
        ply:EmitSound("physics/flesh/flesh_bloody_impact_hard1.wav", 75, 90)
        if GK.CrystalBurst then
            local b = bone and ply:GetBonePosition(bone)
            if b then GK.CrystalBurst(ply, b, 6, vector_up) end
        end
        return true
    end
end

if CLIENT then
    -- First-person legs: a copy of our own model, posed like us, drawn from the
    -- hips down a little behind the camera, so looking down shows them.
    -- Drawn in the engine's own opaque pass (a RenderOverride), not from a
    -- shared render hook: another addon's PostDrawOpaqueRenderables returning
    -- a value cut ours short, and the legs never showed (0.3.8).
    local UPPER = { "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Neck1", "ValveBiped.Bip01_Head1" }
    local legs
    local function shows(ply)
        if not IsValid(ply) or not ply:Alive() or ply:ShouldDrawLocalPlayer() or GetViewEntity() ~= ply or ply:InVehicle() then return false end
        if GK.IsRagdolled(ply) or (GK.IsStaggered and GK.IsStaggered(ply)) or not GK.HasLegs(ply) then return false end
        return true
    end
    local function pose(ply, ent)
        local yaw = Angle(0, ply:GetRenderAngles().y, 0)
        ent:SetPos(ply:GetPos() - yaw:Forward() * 16)
        ent:SetAngles(yaw)
        ent:SetSequence(ply:GetSequence())
        ent:SetCycle(ply:GetCycle())
        for _, pp in ipairs({ "move_x", "move_y", "move_yaw" }) do
            local id = ply:LookupPoseParameter(pp)
            if id >= 0 then ent:SetPoseParameter(pp, ply:GetPoseParameter(pp)) end
        end
        ent:SetSkin(ply:GetSkin())
        for i = 0, ply:GetNumBodyGroups() - 1 do ent:SetBodygroup(i, ply:GetBodygroup(i)) end
        -- A lost calf stays lost here too.
        for side, name in pairs(SIDES) do
            local b = ent:LookupBone(name)
            if b then ent:ManipulateBoneScale(b, ply:GetNW2Bool("gk_leg_" .. side .. "_gone", false) and vector_origin or Vector(1, 1, 1)) end
        end
        -- The kick: the right leg comes up here too (sh_melee.lua drives the same in third person).
        if GK.KickPose then GK.KickPose(ent, ply) end
    end
    GK.FPLegs = function() return legs end
    hook.Add("Think", "GK_FirstPersonLegs", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local mdl = ply:GetModel()
        if not IsValid(legs) or legs:GetModel() ~= mdl then
            if IsValid(legs) then legs:Remove() end
            legs = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
            if not IsValid(legs) then return end
            legs:SetNoDraw(false)
            legs:SetRenderBounds(Vector(-48, -48, -10), Vector(48, 48, 90))
            legs.GK_HuskOwnerExplicit = ply -- trouser colours resolve to us (GKHuskPants)
            for _, n in ipairs(UPPER) do
                local b = legs:LookupBone(n)
                if b then legs:ManipulateBoneScale(b, vector_origin) end
            end
            legs.RenderOverride = function(self)
                local p = LocalPlayer()
                if not shows(p) then return end
                pose(p, self)
                self.GK_Drawn = (self.GK_Drawn or 0) + 1
                self:SetupBones()
                self:DrawModel()
            end
        end
        -- Keep it where we are, so the engine considers it on screen.
        legs:SetPos(ply:GetPos())
    end)
    -- (Marks that this file draws the legs: the Husk fallback, cl_husk_fplegs.lua, backs off.)
    hook.Add("PostDrawOpaqueRenderables", "GK_FirstPersonLegs", function() end)
end
