-- Squads of up to 3, formed in the hub: hold a player with your left
-- mind-hand for a moment and you're in a squad together (if it fits). Inside
-- an arena your squad is your team (no friendly fire); in force-started
-- free-for-alls everyone is on their own. Squadmates get a small coloured
-- marker over their heads (no text anywhere).
--
-- NW2 on the player: gk_squad (int, 0 = none), gk_arena (int, 0 = in the hub),
-- gk_team (int, team inside the arena).

GK.SquadSize = 3
GK.SquadColors = {
    Color(255, 140, 30), Color(70, 150, 255), Color(70, 235, 90), Color(255, 20, 230),
    Color(255, 230, 40), Color(0, 230, 230), Color(255, 255, 255), Color(170, 90, 255),
    Color(255, 80, 80), Color(140, 255, 200), Color(255, 180, 140), Color(120, 120, 255),
}

function GK.SquadOf(ply) return ply:GetNW2Int("gk_squad", 0) end
function GK.ArenaOf(ply) return ply:GetNW2Int("gk_arena", 0) end
function GK.TeamOf(ply) return ply:GetNW2Int("gk_team", 0) end

function GK.SquadMembers(id)
    local out = {}
    if id == 0 then return out end
    for _, p in ipairs(player.GetAll()) do
        if GK.SquadOf(p) == id then out[#out + 1] = p end
    end
    return out
end

-- Same side: same team in an arena, or same squad in the hub.
function GK.SameSide(a, b)
    if a == b then return true end
    if GK.ArenaOf(a) ~= 0 and GK.ArenaOf(a) == GK.ArenaOf(b) then
        return GK.TeamOf(a) ~= 0 and GK.TeamOf(a) == GK.TeamOf(b)
    end
    return GK.SquadOf(a) ~= 0 and GK.SquadOf(a) == GK.SquadOf(b)
end

if SERVER then
    local nextId = 1
    local function newId()
        nextId = nextId + 1
        return nextId
    end

    function GK.LeaveSquad(ply)
        local id = GK.SquadOf(ply)
        ply:SetNW2Int("gk_squad", 0)
        local left = GK.SquadMembers(id)
        if #left == 1 then left[1]:SetNW2Int("gk_squad", 0) end -- a squad of one isn't a squad
    end

    -- Puts a and b in one squad if everyone fits. Returns true on success.
    function GK.JoinSquads(a, b)
        if GK.ArenaOf(a) ~= 0 or GK.ArenaOf(b) ~= 0 then return false end
        local sa, sb = GK.SquadOf(a), GK.SquadOf(b)
        if sa ~= 0 and sa == sb then return false end
        local members = {}
        for _, p in ipairs(sa ~= 0 and GK.SquadMembers(sa) or { a }) do members[#members + 1] = p end
        for _, p in ipairs(sb ~= 0 and GK.SquadMembers(sb) or { b }) do members[#members + 1] = p end
        if #members > GK.SquadSize then return false end
        local id = sa ~= 0 and sa or (sb ~= 0 and sb or newId())
        for _, p in ipairs(members) do p:SetNW2Int("gk_squad", id) end
        for _, p in ipairs(members) do p:EmitSound("buttons/button17.wav", 60, 120) end
        return true
    end

    -- Holding someone with the left mind-hand in the hub for 1.5s squads you up.
    hook.Add("PlayerTick", "GK_SquadUp", function(ply)
        local wep = ply:GetActiveWeapon()
        local g = IsValid(wep) and wep.Grips and wep.Grips.l
        local other = g and g.kind == "player" and g.entity
        if not IsValid(other) or GK.ArenaOf(ply) ~= 0 then ply.GK_SquadHold = nil return end
        if not ply.GK_SquadHold or ply.GK_SquadHold.who ~= other then
            ply.GK_SquadHold = { who = other, since = CurTime() }
        elseif CurTime() - ply.GK_SquadHold.since > 1.5 then
            ply.GK_SquadHold.since = math.huge
            GK.JoinSquads(ply, other)
        end
    end)

    concommand.Add("gk_squad_leave", function(ply) if IsValid(ply) then GK.LeaveSquad(ply) end end)
    hook.Add("PlayerDisconnected", "GK_SquadLeave", GK.LeaveSquad)
end

if CLIENT then
    -- A small diamond over squadmates / teammates, in the squad's colour.
    hook.Add("PostPlayerDraw", "GK_SquadMarker", function(ply)
        local me = LocalPlayer()
        if ply == me or not ply:Alive() or not GK.SameSide(me, ply) then return end
        local id = GK.ArenaOf(me) ~= 0 and GK.TeamOf(ply) or GK.SquadOf(ply)
        local col = GK.SquadColors[(id - 1) % #GK.SquadColors + 1] or color_white
        local pos = ply:EyePos() + Vector(0, 0, 16)
        local ang = (EyePos() - pos):Angle()
        ang:RotateAroundAxis(ang:Right(), -90)
        ang:RotateAroundAxis(ang:Up(), 90)
        cam.Start3D2D(pos, ang, 0.25)
            draw.NoTexture()
            surface.SetDrawColor(col.r, col.g, col.b, 230)
            surface.DrawPoly({ { x = 0, y = -10 }, { x = 10, y = 0 }, { x = 0, y = 10 }, { x = -10, y = 0 } })
        cam.End3D2D()
    end)
end

-- The vacuum's queue, as the hub's ring screen shows it:
--   "5/12 SUBJECTS_iNiTiATED | STARTiNG iN... 0:42:310" (m:s:ms), or
--   "5/12 SUBJECTS_iNiTiATED | WAiTiNG..." until there are enough (or someone
--   forces a start). Returns the text plus count, max and the start time (or nil).
function GK.VacuumQueue(vac)
    local n, max = vac:GetNW2Int("gk_queue", 0), vac:GetNW2Int("gk_queue_max", 12)
    local at = vac:GetNW2Bool("gk_queue_ready", false) and vac.GetNextPull and vac:GetNextPull() or nil
    if at and at <= 0 then at = nil end
    return n, max, at
end

function GK.VacuumQueueText(vac)
    local n, max, at = GK.VacuumQueue(vac)
    local head = ("%d/%d SUBJECTS_iNiTiATED | "):format(n, max)
    if not at then return head .. "WAiTiNG...", n, max, nil end
    local left = math.max(0, at - CurTime())
    return head .. ("STARTiNG iN... %d:%02d:%03d"):format(math.floor(left / 60), math.floor(left % 60), math.floor((left % 1) * 1000)), n, max, at
end
