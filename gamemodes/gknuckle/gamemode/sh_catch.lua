-- Catching roaches, decided on your own screen: with ping, a roach the server
-- has already moved on from was impossible to grab. The client picks the roach
-- under its crosshair (a forgiving cone) the moment a free hand clicks, hides
-- it straight away, and tells the server, which checks loosely and catches it.
AddCSLuaFile()

local REACH_SLACK = 64   -- extra units allowed for lag
local CONE = 0.82        -- about 35 degrees off the crosshair
local BUTTONS = { l = IN_ATTACK, r = IN_ATTACK2 }

local function pick(ply)
    local src, aim = ply:GetShootPos(), ply:GetAimVector()
    local reach = GK.GripRange(ply)
    local best, bd
    for _, r in ipairs(ents.FindInSphere(src, reach + 40)) do
        if r:GetClass() == "gk_roach" and (r.GK_HideUntil or 0) < CurTime() then
            local to = r:WorldSpaceCenter() - src
            local d = to:Length()
            if d <= reach + 24 and to:GetNormalized():Dot(aim) > CONE and (not bd or d < bd) then
                local tr = util.TraceLine({ start = src, endpos = r:WorldSpaceCenter(), mask = MASK_SOLID_BRUSHONLY })
                if not tr.Hit then best, bd = r, d end
            end
        end
    end
    return best
end

if CLIENT then
    hook.Add("CreateMove", "GK_CatchRoach", function(cmd)
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "gk_mind" then return end
        for side, button in pairs(BUTTONS) do
            local down = cmd:KeyDown(button)
            local was = ply["GK_CatchDown_" .. side]
            ply["GK_CatchDown_" .. side] = down
            if down and not was and ply:GetNW2String("gk_hitem_" .. side, "") == "" and not (GK.HasFist and GK.HasFist(ply, side)) then
                local r = pick(ply)
                if IsValid(r) then
                    r.GK_HideUntil = CurTime() + 1 -- gone from view at once; the server confirms (or it reappears)
                    net.Start("gk_catch") net.WriteEntity(r) net.WriteString(side) net.SendToServer()
                end
            end
        end
    end)
end

if SERVER then
    util.AddNetworkString("gk_catch")
    net.Receive("gk_catch", function(_, ply)
        local r, side = net.ReadEntity(), net.ReadString()
        if side ~= "l" and side ~= "r" then return end
        if not IsValid(r) or r:GetClass() ~= "gk_roach" or not ply:Alive() then return end
        -- Loose checks: near enough (with lag slack) and roughly in front.
        local src = ply:GetShootPos()
        local reach = GK.GripRange(ply) + REACH_SLACK
        local to = r:WorldSpaceCenter() - src
        if to:Length() > reach or to:GetNormalized():Dot(ply:GetAimVector()) < 0.5 then return end
        ply.GK_PressSide = side
        r:Press(ply)
    end)
end
