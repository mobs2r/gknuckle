-- Husk v2 dismemberment visuals: bodygroups hide the lost lower legs / head behind a stump
-- cap (instead of only collapsed bones), and v2-matching gib models fly off with Xenium
-- crystals on the cut face (tinted by GK.Husk.CrystalColor, black once the owner is dead).
-- Gameplay owns the rules (sv_dismember.lua, sh_crystalgore.lua); this file only reads
-- gk_legless / GK.IsGored and offers GK.Husk.OnLegsLost(ply) for GK.RemoveLegs to call.
AddCSLuaFile()
GK.Husk = GK.Husk or {}

local P = "ValveBiped.Bip01_"
GK.Husk.Gibs = {
    leg_l = { model = "models/player/gknuckle/husk_v2_gib_leg_l.mdl", bone = P .. "L_Calf" },
    leg_r = { model = "models/player/gknuckle/husk_v2_gib_leg_r.mdl", bone = P .. "R_Calf" },
    head = { model = "models/player/gknuckle/husk_v2_gib_head.mdl", bone = P .. "Head1" },
}
local GIB_LIFE, GIB_FADE, MAX_CLIENT_GIBS = 20, 4, 12
-- Leg gibs are grippable / stealable (Gameplay reattaches them), so they live longer:
-- gk_husk_leggib_life seconds (0 = never removed by this file; Gameplay cleans up).
local cvLegLife = CreateConVar("gk_husk_leggib_life", "180", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Husk leg gib lifetime (0 = keep)")

-- Bodygroups "leg_l", "leg_r", "head": 0 attached, 1 gone (stump cap). Models without them are ignored.
function GK.Husk.SetLimbs(ent, legsGone, headGone)
    if not IsValid(ent) then return end
    for name, gone in pairs({ leg_l = legsGone, leg_r = legsGone, head = headGone }) do
        local id = ent:FindBodygroupByName(name)
        if id and id >= 0 and gone ~= nil then ent:SetBodygroup(id, gone and 1 or 0) end
    end
end

local function hasLimbGroups(ent) return IsValid(ent) and (ent:FindBodygroupByName("leg_l") or -1) >= 0 end

if SERVER then
    -- Gib props for lost legs. Returns true, { leg_l = gib, leg_r = gib } when it handled them
    -- (Husk v2), so GK.RemoveLegs can skip its generic gibs:
    --   if not (GK.Husk.OnLegsLost and GK.Husk.OnLegsLost(ply)) then ... end
    -- Leg gibs: prop_physics, COLLISION_GROUP_WEAPON (solid to traces and the world, players
    -- walk through), 9 kg, box hull >= 6u on every axis; they carry their own pants colour in
    -- NW2 gk_pants_l / gk_pants_r and their owner in NW2 entity gk_husk_owner.
    function GK.Husk.OnLegsLost(ply)
        if not hasLimbGroups(ply) then return false end
        GK.Husk.SetLimbs(ply, true, nil)
        local made = {}
        for _, part in ipairs({ "leg_l", "leg_r" }) do
            local g = GK.Husk.Gibs[part]
            local bone = ply:LookupBone(g.bone)
            local pos, ang
            if bone then pos, ang = ply:GetBonePosition(bone) end
            if pos then
                local gib = ents.Create("prop_physics")
                gib:SetModel(g.model)
                gib:SetPos(pos) gib:SetAngles(ang)
                gib:SetSkin(ply:GetSkin())
                gib:SetNW2Entity("gk_husk_owner", ply)
                local slot = part == "leg_l" and "l" or "r"
                GK.Husk.SetPants(gib, GK.Husk.PantsOf(ply, slot) or GK.Husk.PantsDefault, slot)
                gib.GK_HuskLeg = slot
                gib:Spawn()
                gib:SetCollisionGroup(COLLISION_GROUP_WEAPON)
                local phys = gib:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(ply:GetVelocity() + VectorRand() * 60 + Vector(0, 0, 90))
                    phys:AddAngleVelocity(VectorRand() * 300)
                end
                if cvLegLife:GetFloat() > 0 then SafeRemoveEntityDelayed(gib, cvLegLife:GetFloat()) end
                made[part] = gib
            end
        end
        return true, made
    end

    -- Keep the leg bodygroups in step with gk_legless however legs come and go.
    timer.Create("GK_HuskLimbSync", 0.25, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            if hasLimbGroups(ply) then
                local want = ply:GetNW2Bool("gk_legless", false) and 1 or 0
                local id = ply:FindBodygroupByName("leg_l")
                if ply:GetBodygroup(id) ~= want then GK.Husk.SetLimbs(ply, want == 1, false) end
            end
        end
    end)
end

if CLIENT then
    local live = {}
    local function clientGib(rag, part, owner)
        local g = GK.Husk.Gibs[part]
        local bone = rag:LookupBone(g.bone)
        local pos, ang
            if bone then pos, ang = rag:GetBonePosition(bone) end
        if not pos then return end
        while #live >= MAX_CLIENT_GIBS do local old = table.remove(live, 1) if IsValid(old) then old:Remove() end end
        local gib = ents.CreateClientProp(g.model)
        if not IsValid(gib) then return end
        gib:SetPos(pos) gib:SetAngles(ang)
        gib:SetSkin(rag:GetSkin())
        gib.GK_HuskOwnerExplicit = owner
        for _, s in ipairs(GK.Husk.PantsSlots) do
            local v = GK.Husk.PantsOf(rag, s) or GK.Husk.PantsOf(owner, s)
            if v then gib.GK_Pants = gib.GK_Pants or {} gib.GK_Pants[s] = v end
        end
        gib:Spawn()
        local phys = gib:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:SetVelocity(VectorRand() * 80 + Vector(0, 0, 120))
            phys:AddAngleVelocity(VectorRand() * 400)
        end
        gib.GK_DieAt = CurTime() + GIB_LIFE
        gib:SetRenderMode(RENDERMODE_TRANSCOLOR)
        live[#live + 1] = gib
    end

    hook.Add("Think", "GK_HuskClientGibs", function()
        local now = CurTime()
        for i = #live, 1, -1 do
            local g = live[i]
            if not IsValid(g) then table.remove(live, i)
            elseif now >= g.GK_DieAt then g:Remove() table.remove(live, i)
            elseif now > g.GK_DieAt - GIB_FADE then
                g:SetColor(Color(255, 255, 255, 255 * (g.GK_DieAt - now) / GIB_FADE))
            end
        end
    end)

    -- Death ragdolls: legless/gored Husks lose the meshes too (bone scaling alone leaves
    -- crumpled geometry); a gored death throws the head (and legs, if still attached).
    hook.Add("CreateClientsideRagdoll", "GK_HuskLimbs", function(owner, rag)
        if not (IsValid(owner) and owner:IsPlayer() and hasLimbGroups(rag)) then return end
        local legless = owner:GetNW2Bool("gk_legless", false)
        local gored = GK.IsGored and GK.IsGored(owner)
        timer.Simple(0, function()   -- after GK.Husk.CopyLook
            if not IsValid(rag) then return end
            GK.Husk.SetLimbs(rag, legless or gored, gored)
            if gored then
                clientGib(rag, "head", owner)
                if not legless then clientGib(rag, "leg_l", owner) clientGib(rag, "leg_r", owner) end
            end
        end)
    end)
end
