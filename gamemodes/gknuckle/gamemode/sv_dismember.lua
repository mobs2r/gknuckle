local C = GK.Config

-- Everyone is armless; legs come off when they take enough leg damage.
local ARM_BONES = { "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_R_UpperArm" }
local LEG_BONES = { "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf" }

local function scaleBones(ent, names, scale)
    for _, name in ipairs(names) do
        local bone = ent:LookupBone(name)
        if bone then ent:ManipulateBoneScale(bone, scale) end
    end
end

-- Models whose mesh is already armless (the Husk: its hologram hands hang off
-- the arm bones) keep their arm bones; everything else loses them.
GK.ScaleArmBones = function(ent)
    if GK.IsArmless and GK.IsArmless(ent) then return end
    scaleBones(ent, ARM_BONES, vector_origin)
end

function GK.RestoreLegs(ply)
    ply.GK_LegHealth = C.LegHealth
    ply.GK_LegHP = { l = C.LegHealth, r = C.LegHealth }
    ply:SetNW2Bool("gk_leg_l_gone", false)
    ply:SetNW2Bool("gk_leg_r_gone", false)
    ply:SetNW2Bool("gk_legless", false)
    ply:SetJumpPower(C.JumpPower)
    scaleBones(ply, LEG_BONES, Vector(1, 1, 1))
    timer.Simple(0, function() if IsValid(ply) then GK.ScaleArmBones(ply) end end)
end

-- "MY LEG!" about every other time you lose your legs: a 70% chance, but
-- never twice in a row, and always if it stayed quiet the time before.
-- HL2's citizen line (vo/npc/male01/myleg01-02).
local MY_LEG = { "vo/npc/male01/myleg01.wav", "vo/npc/male01/myleg02.wav" }
function GK.MyLeg(ply)
    local play
    if ply.GK_MyLegLast == true then play = false
    elseif ply.GK_MyLegLast == false then play = true
    else play = math.random() < 0.7 end
    -- After a forced play or skip, the next time is a fresh 70% roll again.
    -- (Not "x and play or nil": that turns a skipped first line into nil and re-rolls.)
    if ply.GK_MyLegLast == nil then ply.GK_MyLegLast = play else ply.GK_MyLegLast = nil end
    if play then ply:EmitSound(MY_LEG[math.random(#MY_LEG)], 85) end
end

-- Each life starts fresh: the first leg lost is the 70% roll again.
hook.Add("PlayerSpawn", "GK_MyLegReset", function(ply) ply.GK_MyLegLast = nil end)

function GK.RemoveLegs(ply)
    if not GK.HasLegs(ply) then return end
    ply:SetNW2Bool("gk_legless", true)
    ply:SetJumpPower(0)
    scaleBones(ply, LEG_BONES, vector_origin)
    ply:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav")
    GK.MyLeg(ply)

    -- The legs drop as legs you can pick up and put back on (sh_legs.lua).
    if GK.Husk and GK.Husk.SetLimbs then GK.Husk.SetLimbs(ply, true, nil) end
    for side, name in pairs({ l = "ValveBiped.Bip01_L_Calf", r = "ValveBiped.Bip01_R_Calf" }) do
        if not ply:GetNW2Bool("gk_leg_" .. side .. "_gone", false) and GK.DropLeg then
            local bone = ply:LookupBone(name)
            GK.DropLeg(ply, side, bone and ply:GetBonePosition(bone) or nil)
        end
    end
    util.Decal("Blood", ply:GetPos() + Vector(0, 0, 8), ply:GetPos() - Vector(0, 0, 32), ply)
end

-- One leg at a time: shoot a leg enough and that one comes off; lose the
-- second and you're legless (GK.RemoveLegs).
function GK.RemoveLeg(ply, side)
    if not GK.HasLegs(ply) or ply:GetNW2Bool("gk_leg_" .. side .. "_gone", false) then return end
    local other = side == "l" and "r" or "l"
    if ply:GetNW2Bool("gk_leg_" .. other .. "_gone", false) then GK.RemoveLegs(ply) return end
    ply:SetNW2Bool("gk_leg_" .. side .. "_gone", true)
    local name = side == "l" and "ValveBiped.Bip01_L_Calf" or "ValveBiped.Bip01_R_Calf"
    local bone = ply:LookupBone(name)
    if bone then
        ply:ManipulateBoneScale(bone, vector_origin)
        local pos = ply:GetBonePosition(bone)
        if GK.CrystalBurst and pos then GK.CrystalBurst(ply, pos, 14, vector_up) end
        if GK.DropLeg then GK.DropLeg(ply, side, pos) end
    end
    ply:EmitSound("physics/body/body_medium_break" .. math.random(2, 4) .. ".wav")
    GK.MyLeg(ply)
end

hook.Add("ScalePlayerDamage", "GK_LegDamage", function(ply, hitgroup, dmginfo)
    if hitgroup ~= HITGROUP_LEFTLEG and hitgroup ~= HITGROUP_RIGHTLEG then return end
    if not GK.HasLegs(ply) then return end
    local side = hitgroup == HITGROUP_LEFTLEG and "l" or "r"
    ply.GK_LegHP = ply.GK_LegHP or { l = C.LegHealth, r = C.LegHealth }
    ply.GK_LegHP[side] = ply.GK_LegHP[side] - dmginfo:GetDamage()
    if ply.GK_LegHP[side] <= 0 then GK.RemoveLeg(ply, side) end
end)

-- Explosions don't report hitgroups, so a big blast near the feet also takes legs.
hook.Add("EntityTakeDamage", "GK_BlastLegs", function(ply, dmginfo)
    if not ply:IsPlayer() or not dmginfo:IsExplosionDamage() then return end
    if dmginfo:GetDamage() >= C.LegHealth and dmginfo:GetDamagePosition().z < ply:GetPos().z + 24 then
        GK.RemoveLegs(ply)
    end
end)

-- Player model: the gKnuckle Husk (gk_playermodel).
-- Whatever the model, the arms are always gone: the Xenium virus does all the
-- handling (lore), so the arm bones are scaled away on spawn, on any model
-- change, and re-checked every second in case something resets them.
local cvModel = CreateConVar("gk_playermodel", "models/player/gknuckle/husk_v2.mdl", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Player model (arms are always removed)")
-- If the chosen model is missing: Husk v2, then Husk v1, then the plain soldier.
local FALLBACKS = { "models/player/gknuckle/husk_v2.mdl", "models/player/soldier_stripped.mdl" }

function GM:PlayerSetModel(ply)
    local mdl = cvModel:GetString()
    for _, f in ipairs(FALLBACKS) do
        if util.IsValidModel(mdl) then break end
        mdl = f
    end
    ply:SetModel(mdl)
    timer.Simple(0, function() if IsValid(ply) then GK.ScaleArmBones(ply) end end)
end

timer.Create("GK_KeepArmless", 1, 0, function()
    for _, ply in ipairs(player.GetAll()) do
        local bone = ply:LookupBone(ARM_BONES[1])
        if bone and ply:GetManipulateBoneScale(bone):LengthSqr() > 0.001 then GK.ScaleArmBones(ply) end
    end
end)
