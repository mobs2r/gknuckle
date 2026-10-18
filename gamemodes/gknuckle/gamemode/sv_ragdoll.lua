local C = GK.Config

-- Knock a player into a physics ragdoll for a few seconds, then stand them back up
-- where the ragdoll ended up. Used by bricks and anything else heavy.
function GK.Ragdoll(ply, velocity, duration)
    if not IsValid(ply) or not ply:Alive() or GK.IsRagdolled(ply) then return end

    local rag = ents.Create("prop_ragdoll")
    rag:SetModel(ply:GetModel())
    rag:SetPos(ply:GetPos())
    rag:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    rag:SetSkin(ply:GetSkin())
    rag:Spawn()
    rag:Activate()
    GK.ScaleArmBones(rag)
    if not GK.HasLegs(ply) then
        for _, name in ipairs({ "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf" }) do
            local bone = rag:LookupBone(name)
            if bone then rag:ManipulateBoneScale(bone, vector_origin) end
        end
    end

    local vel = (velocity or vector_origin) + ply:GetVelocity()
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local bone = rag:TranslatePhysBoneToBone(i)
            local pos, ang = ply:GetBonePosition(bone)
            if pos then phys:SetPos(pos) phys:SetAngles(ang) end
            phys:SetVelocity(vel)
        end
    end

    ply.GK_SavedWeapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or nil
    ply.GK_SavedWeapons = {}
    for _, wep in ipairs(ply:GetWeapons()) do table.insert(ply.GK_SavedWeapons, wep:GetClass()) end
    ply:SetNW2Entity("gk_ragdoll", rag)
    ply:Spectate(OBS_MODE_CHASE)
    ply:SpectateEntity(rag)
    ply:SetNoDraw(true)

    timer.Create("GK_Unragdoll_" .. ply:EntIndex(), duration or C.RagdollTime, 1, function()
        GK.Unragdoll(ply)
    end)
end

function GK.Unragdoll(ply)
    if not IsValid(ply) then return end
    local rag = ply:GetNW2Entity("gk_ragdoll")
    timer.Remove("GK_Unragdoll_" .. ply:EntIndex())
    ply:SetNW2Entity("gk_ragdoll", NULL)
    ply:UnSpectate()
    ply:SetNoDraw(false)
    if not IsValid(rag) then return end

    local pos = rag:GetPos()
    local hp, legless, stamina = ply:Health(), not GK.HasLegs(ply), GK.Stamina(ply)
    local surge = ply:GetNW2Float("gk_surge_until", 0)
    ply:Spawn()
    ply:SetNW2Float("gk_surge_until", surge)
    ply:SetPos(pos + Vector(0, 0, 8))
    ply:SetHealth(hp)
    GK.SetStamina(ply, stamina)
    if legless then GK.RemoveLegs(ply) end
    for _, class in ipairs(ply.GK_SavedWeapons or {}) do
        if not ply:HasWeapon(class) then ply:Give(class) end
    end
    if ply.GK_SavedWeapon and ply:HasWeapon(ply.GK_SavedWeapon) then ply:SelectWeapon(ply.GK_SavedWeapon) end
    rag:Remove()
end

hook.Add("PlayerDisconnected", "GK_RagdollCleanup", function(ply)
    local rag = ply:GetNW2Entity("gk_ragdoll")
    if IsValid(rag) then rag:Remove() end
end)

hook.Add("DoPlayerDeath", "GK_RagdollDeath", function(ply)
    local rag = ply:GetNW2Entity("gk_ragdoll")
    if IsValid(rag) then rag:Remove() end
    ply:SetNW2Entity("gk_ragdoll", NULL)
end)
