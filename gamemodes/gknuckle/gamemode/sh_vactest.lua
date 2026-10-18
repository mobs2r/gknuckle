-- Hub vacuum check (needs the hub3 map): the held force-start button, the
-- full-chamber zap, and rising up the staging tube into the trial.
-- Only runs when data/gknuckle/vactest.txt exists. Logs "[GKVAC]"; no screenshots.
if not file.Exists("gknuckle/vactest.txt", "DATA") then return end
local function log(...) print("[GKVAC]", ...) end
if CLIENT then return end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, btn, vac

step(0, function()
    P = player.GetHumans()[1]
    btn = ents.FindByName("gk_force_start_1")[1] or ents.FindByClass("gk_force_start")[1]
    vac = ents.FindByName("gk_vacuum_1")[1] or ents.FindByClass("gk_vacuum")[1]
    log("button", tostring(IsValid(btn)), btn and tostring(btn:GetPos()) or "", "vacuums", #ents.FindByClass("gk_vacuum"), "buttons", #ents.FindByClass("gk_force_start"), "top_1", tostring(IsValid(ents.FindByName("gk_vacuum_top_1")[1])),
        "pads", #ents.FindByName("gk_vacuum_pad_1") + #ents.FindByName("gk_vacuum_pad_2") + #ents.FindByName("gk_vacuum_pad_3"))
end)
-- Held for 1.5 s, let go: not armed, resets.
for _ = 1, 15 do step(0.1, function() if IsValid(btn) then btn:Press(P) end end) end
step(0.4, function() log("held 1.5 s then let go: held", math.floor((btn:GetHeld()) * 100) / 100, "armed", tostring(btn:GetArmedUntil() > CurTime())) end)
-- Held for 3.3 s: armed.
for _ = 1, 33 do step(0.1, function() if IsValid(btn) then btn:Press(P) end end) end
step(0.1, function() log("held 3.3 s: armed", tostring(btn:GetArmedUntil() > CurTime()), "pad 1 force window", tostring((GK.Rounds.forceFor and GK.Rounds.forceFor[1] or 0) > CurTime()), "global", tostring(GK.Rounds.forceUntil > CurTime())) end)
-- Full chamber: with the cap at 1, we are its one; stepping to the edge zaps us back.
step(0.5, function()
    RunConsoleCommand("gk_arena_max", "1")
    P:SetPos(vac:GetPos() + Vector(0, 0, 8)) P:SetLocalVelocity(vector_origin)
end)
step(0.6, function()
    P:SetPos(vac:GetPos() + Vector(vac:GetRadius() * 0.92, 0, 8)) P:SetLocalVelocity(vector_origin)
end)
step(0.3, function()
    local d = P:GetPos() - vac:GetPos() d.z = 0
    log("at the edge of a full chamber: moving inward", tostring(P:GetVelocity():Dot(-d:GetNormalized()) > 50), "speed", math.floor(P:GetVelocity():Length()))
    RunConsoleCommand("gk_arena_max", "12")
end)
-- The glass hypervisor: solid where it is glass (south), open at the portal openings (north).
local hy = (GK.HubLayout and GK.HubLayout() or {}).vacuum
hy = hy and hy.hyper
local R = hy and hy.r or 560
local function yawDir(y) return Angle(0, y, 0):Forward() end
for _, dir in ipairs({ { "opening 30", yawDir(30) }, { "opening 150", yawDir(150) }, { "opening 270", yawDir(270) }, { "glass 90 (behind button 1)", yawDir(90) }, { "glass 210", yawDir(210) } }) do
    step(0.5, function()
        local vp = (GK.HubLayout() or {}).vacuum and GK.HubLayout().vacuum.pos -- the hypervisor centre, not pad 1
        local c = vp and Vector(vp[1], vp[2], vac:GetPos().z) or vac:GetPos()
        P:SetPos(c + dir[2] * (R + 40) + Vector(0, 0, 8)) P:SetEyeAngles((-dir[2]):Angle())
        P:SetLocalVelocity(-dir[2] * 1100)
        P.GK_TestC = c
        -- The floor profile walking in: height of whatever is underfoot every 16 u.
        local prof = {}
        for rr = R + 40, R - 80, -16 do
            local p = c + dir[2] * rr
            local tr = util.TraceLine({ start = p + Vector(0, 0, 100), endpos = p - Vector(0, 0, 200), mask = MASK_PLAYERSOLID, filter = player.GetAll() })
            prof[#prof + 1] = rr .. ":" .. math.floor(tr.HitPos.z)
        end
        log(dir[1], "floor profile (radius:z)", table.concat(prof, " "))
        for _, h in ipairs({ 20, 60, 120, 200 }) do
            local tr = util.TraceLine({ start = c + dir[2] * (R + 40) + Vector(0, 0, h), endpos = c + Vector(0, 0, h), mask = MASK_PLAYERSOLID, filter = player.GetAll() })
            local hp = tr.HitPos - c hp.z = 0
            log(dir[1], "trace in at +" .. h .. ": hit", tostring(tr.Hit), "at radius", math.floor(hp:Length()), tr.HitTexture or "", "z", math.floor(c.z + h))
        end
    end)
    step(1.2, function()
        local d = P:GetPos() - P.GK_TestC d.z = 0
        log(dir[1], "walked at the hypervisor from outside: now", math.floor(d:Length()), "from centre (glass radius", R .. ")", "inside", tostring(d:Length() < R - 20))
    end)
end
-- Up the tube: a forced solo start.
step(1, function()
    local top = ents.FindByName("gk_vacuum_top_1")[1] or ents.FindByName("gk_vacuum_top")[1]
    P:SetPos(vac:GetPos() + Vector(0, 0, 8)) P:SetLocalVelocity(vector_origin)
    local free = GK.Arena.Free()
    log("starting arena", tostring(free), "top z above us", top and math.floor(top:GetPos().z - P:GetPos().z) or "none")
    GK.StartArena(free, { P }, true)
    log("rising", tostring(P.GK_RiseTo ~= nil))
end)
step(1, function() log("1 s: rising", tostring(P.GK_RiseTo ~= nil), "z", math.floor(P:GetPos().z), "arena", GK.ArenaOf(P)) end)
step(0.6, function()
    local a = GK.Rounds.arenas[GK.ArenaOf(P)]
    local sp = a and a.info and a.info.spawn
    log("just arrived: dist to spawn", sp and math.floor(P:GetPos():Distance(sp)) or "?", "z below spawn", sp and math.floor(sp.z - P:GetPos().z) or "?", "on ground", tostring(P:OnGround()))
end)
for k = 1, 6 do
    step(0.5, function()
        local a = GK.Rounds.arenas[GK.ArenaOf(P)]
        local sp = a and a.info and a.info.spawn
        local g = P:GetGroundEntity()
        log("after arrival +" .. (k * 0.5) .. " s: dist", sp and math.floor(P:GetPos():Distance(sp)) or "?", "dz", sp and math.floor(P:GetPos().z - sp.z) or "?", "vel", tostring(P:GetVelocity()), "ground", tostring(g), "grips", tostring(P:GetNW2Int("gk_hand_l", 0)) .. tostring(P:GetNW2Int("gk_hand_r", 0)), "ragdoll", tostring(GK.IsRagdolled(P)))
    end)
end
step(0.4, function()
    local a = GK.Rounds.arenas[GK.ArenaOf(P)]
    local sp = a and a.info and a.info.spawn
    log("5 s: rising", tostring(P.GK_RiseTo ~= nil), "in the trial (near its spawn)", tostring(a ~= nil and P:GetPos():Distance(sp or P:GetPos()) < 300), "arena", GK.ArenaOf(P), "dist to spawn", sp and math.floor(P:GetPos():Distance(sp)) or "no spawn", "pos", tostring(P:GetPos()), "alive", tostring(P:Alive()))
end)
-- The score on a believable climb: raised at about 1.2 m/s for 12 s, then the run ends.
hook.Add("GK_RunScored", "GK_VacTestScore", function(ply, r)
    if ply:IsBot() then return end
    local rows = {}
    for _, x in ipairs(r.rows) do rows[#rows + 1] = x.title .. "(" .. x.count .. ")" .. (x.mult and ("x" .. x.mult) or ("+" .. x.bonus)) end
    log("score shown: dist", ("%.1f"):format(r.dist), "m time", math.floor(r.time), "s speed", ("%.2f"):format(r.speed), "m/s base", math.floor(r.base), "rows", table.concat(rows, " "), "FINAL", r.final, "death cause", tostring(r.cause))
end)
for _ = 1, 24 do
    step(0.5, function()
        P:SetPos(P:GetPos() + Vector(0, 0, 23.6)) P:SetLocalVelocity(vector_origin) P:SetMoveType(MOVETYPE_NOCLIP)
    end)
end
step(0.6, function()
    P:SetMoveType(MOVETYPE_WALK)
    -- Bank 7, carry 5, then die in the run: the bank stays, the carried ones drop.
    P:SetNW2Int("gk_bank", 7) P:SetNW2Int("gk_roaches", 5)
    P.GK_TestRoaches0 = #ents.FindByClass("gk_roach")
    P:Kill()
end)
step(0.5, function()
    log("after dying in the run: bank", GK.Roaches.Banked(P), "(expect 7)", "carried", GK.Roaches.Count(P), "(expect 0)", "roaches dropped", #ents.FindByClass("gk_roach") - (P.GK_TestRoaches0 or 0))
end)
step(0.5, function() log("DONE") end)

hook.Add("PlayerInitialSpawn", "GK_VacTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_VacTest")
    timer.Simple(12, function()
        local t = 0
        for _, s in ipairs(steps) do
            t = t + s[1]
            timer.Simple(t, function()
                local ok, err = pcall(s[2])
                if not ok then log("STEP ERROR", err) end
            end)
        end
    end)
end)
