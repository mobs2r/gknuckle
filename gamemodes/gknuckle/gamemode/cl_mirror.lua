-- The hub mirror (gk_style 0.4.4) is a func_reflective_glass. The engine renders a second
-- view of the scene for it every frame the glass is in the PVS, which took the whole hub
-- from ~150 fps to ~20. Hide it on this client unless you are close, in front of it and
-- facing it, so the reflection pass only runs while you are actually using the mirror.
local RANGE2 = 900 * 900
local mirror, nextFind = nil, 0
hook.Add("Think", "GK_MirrorCull", function()
    if not IsValid(mirror) then
        if CurTime() < nextFind then return end
        nextFind = CurTime() + 2
        mirror = ents.FindByClass("func_reflective_glass")[1]
        if not IsValid(mirror) then return end
    end
    local hub = GK.HubLayout and GK.HubLayout() or nil
    local m = hub and hub.mirror
    if not m then return end
    local c = Vector(m.pos[1], m.pos[2], m.pos[3])
    local n = Angle(0, m.yaw, 0):Forward()                 -- faces into the room
    local eye = EyePos()
    local toEye = eye - c
    local show = toEye:LengthSqr() < RANGE2 and toEye:Dot(n) > 8 and EyeAngles():Forward():Dot(-n) > 0.2
    if mirror.GKShown ~= show then
        mirror.GKShown = show
        mirror:SetNoDraw(not show)
    end
end)
