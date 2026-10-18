-- First-person legs check: look down, count how often the legs were drawn and
-- whether the thighs land on screen. Only runs when data/gknuckle/fplegtest.txt
-- exists. Logs "[GKFPLEG]"; no screenshots.
if not file.Exists("gknuckle/fplegtest.txt", "DATA") then return end
if SERVER then
    hook.Add("PlayerInitialSpawn", "GK_FPLegTest", function(ply)
        if ply:IsBot() then return end
        timer.Simple(10, function() print("[GKFPLEG] server ready") end)
        timer.Simple(20, function() print("[GKFPLEG] DONE") end)
    end)
    return
end
timer.Simple(12, function()
    local ply = LocalPlayer()
    ply:SetEyeAngles(Angle(85, ply:EyeAngles().y, 0))
    local legs = GK.FPLegs and GK.FPLegs()
    local n0 = IsValid(legs) and (legs.GK_Drawn or 0) or 0
    timer.Simple(3, function()
        legs = GK.FPLegs and GK.FPLegs()
        local drawn = IsValid(legs) and (legs.GK_Drawn or 0) - n0 or -1
        local b = IsValid(legs) and legs:LookupBone("ValveBiped.Bip01_R_Calf")
        local on = false
        if b then
            local sp = legs:GetBonePosition(b):ToScreen()
            on = sp.visible and sp.x > 0 and sp.x < ScrW() and sp.y > 0 and sp.y < ScrH()
        end
        print("[GKFPLEG] legs entity", tostring(IsValid(legs)), "draw calls in 3 s", drawn, "calf on screen", tostring(on), "model", IsValid(legs) and legs:GetModel() or "")
    end)
end)
