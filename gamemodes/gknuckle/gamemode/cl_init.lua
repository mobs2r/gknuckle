-- Mount a cached playable-pack before anything else creates materials.
include("cl_pack.lua")
include("shared.lua")
include("cl_hands.lua")
include("cl_hud.lua")
include("cl_regionsky.lua")
include("cl_drawhh.lua")
include("cl_roomlights.lua")
include("cl_mirror.lua")
include("cl_inventory.lua")
include("cl_post.lua")
include("cl_status.lua")
include("cl_pausemenu.lua")

-- Gored corpses: charred grey, no head, no legs (matches their grey hands).
hook.Add("CreateClientsideRagdoll", "GK_GoredRagdoll", function(owner, rag)
    if not IsValid(owner) or not owner:IsPlayer() or not GK.IsGored(owner) then return end
    rag:SetColor(GK.Colors.Gored)
    rag:SetMaterial("models/charple/charple1_sheet")
    for _, name in ipairs({ "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_L_Calf", "ValveBiped.Bip01_R_Calf" }) do
        local bone = rag:LookupBone(name)
        if bone then rag:ManipulateBoneScale(bone, vector_origin) end
    end
end)

-- Every corpse is armless too (the Xenium virus did the handling).
hook.Add("CreateClientsideRagdoll", "GK_ArmlessRagdoll", function(owner, rag)
    if not IsValid(owner) or not owner:IsPlayer() or (GK.IsArmless and GK.IsArmless(owner)) then return end
    for _, name in ipairs({ "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_R_UpperArm" }) do
        local bone = rag:LookupBone(name)
        if bone then rag:ManipulateBoneScale(bone, vector_origin) end
    end
end)
