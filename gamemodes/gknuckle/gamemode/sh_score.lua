-- White Knuckle's run score (its GamemodeModule_Standard / CL_ScoreManager),
-- shown when your trial ends: when you die in it, or when the run is over.
--
--   SCORE  = height climbed (m) x average climb speed (m/s)
--   bonus  = Roaches Smashed +10 each, Roaches Banked +20 each, Kills +50 each
--   FINAL  = (SCORE + bonus) x multipliers, rounded to 0.01
--   multipliers: positive ones add onto 1 (Won x5 as in WK, each stage beyond
--   the first +0.25); negative ones onto 1 separately; the two are multiplied.
AddCSLuaFile()

GK.Score = GK.Score or {}
local SC = GK.Score
local M = 39.37 -- Source units per metre

if SERVER then
    util.AddNetworkString("gk_score")

    local function add(s, id, title, bonus, mult, count)
        local e = s.items[id]
        if not e then
            e = { id = id, title = title, bonus = 0, mult = 0, count = 0 }
            s.items[id] = e
            s.order[#s.order + 1] = id
        end
        e.bonus, e.mult, e.count = e.bonus + (bonus or 0), e.mult + (mult or 0), e.count + (count or 0)
    end
    SC.Add = function(ply, ...) if ply.GK_Score then add(ply.GK_Score, ...) end end

    -- The numbers for ply's run so far.
    function SC.Compute(ply)
        local s = ply.GK_Score
        if not s then return nil end
        local t = math.max(1, (s.t1 or CurTime()) - s.t0)
        local dist = math.max(0, (s.maxZ - s.z0) / M)
        local speed = dist / t
        local base = dist * speed
        local bonus, pos, neg = 0, 1, 1
        for _, id in ipairs(s.order) do
            local e = s.items[id]
            bonus = bonus + e.bonus
            if e.mult > 0 then pos = pos + e.mult else neg = neg + e.mult end
        end
        local mult = math.max(0, pos * neg)
        local rows = {}
        for _, id in ipairs(s.order) do
            local e = s.items[id]
            rows[#rows + 1] = { title = e.title, count = e.count, bonus = e.bonus, mult = e.mult ~= 0 and (1 + e.mult) or nil }
        end
        return {
            dist = dist, speed = speed, time = t, base = base, rows = rows, cause = s.cause,
            final = math.Round((base + bonus) * mult, 2),
        }
    end

    function SC.Send(ply)
        -- Count where they are right now too (the height sampler runs twice a second).
        local s = ply.GK_Score
        if s and not s.paused and GK.ArenaOf(ply) == s.arena then s.maxZ = math.max(s.maxZ, ply:GetPos().z + (s.carried or 0)) end
        local r = SC.Compute(ply)
        if not r then return end
        ply.GK_Score = nil
        net.Start("gk_score")
        net.WriteTable(r)
        net.Send(ply)
        hook.Run("GK_RunScored", ply, r)
    end

    hook.Add("GK_ArenaStart", "GK_Score", function(a)
        local z0 = a.info and a.info.spawn and a.info.spawn.z or 0
        for _, p in ipairs(a.players) do
            if IsValid(p) then
                p.GK_Score = { t0 = CurTime(), z0 = z0, maxZ = z0, items = {}, order = {}, stage = 1, arena = a.index }
            end
        end
    end)
    -- Height climbed: the best you got to, as WK's best travel distance.
    timer.Create("GK_ScoreHeight", 0.5, 0, function()
        for _, p in ipairs(player.GetAll()) do
            local s = p.GK_Score
            if s and not s.paused and p:Alive() and GK.ArenaOf(p) == s.arena and not p.GK_RiseTo then
                s.maxZ = math.max(s.maxZ, p:GetPos().z)
            end
        end
    end)
    -- The break room between regions does not count as climbing.
    hook.Add("GK_ArenaBreak", "GK_Score", function(a)
        for _, p in ipairs(a.players) do if IsValid(p) and p.GK_Score then p.GK_Score.paused = true end end
    end)
    -- A squad that made the top first rests while the others climb.
    hook.Add("GK_TeamBreak", "GK_Score", function(a, t, members)
        for _, p in ipairs(members) do if IsValid(p) and p.GK_Score then p.GK_Score.paused = true end end
    end)
    hook.Add("GK_ArenaStage", "GK_Score", function(a, stage)
        for _, p in ipairs(a.players) do
            local s = IsValid(p) and p.GK_Score
            if s then
                add(s, "stages", "Stages Cleared", 0, 0.25, 1)
                -- The next region starts lower in its own shaft: carry the
                -- climb so far and measure the new one from its spawn.
                s.carried = (s.carried or 0) + (s.maxZ - s.z0)
                s.z0 = a.info and a.info.spawn and a.info.spawn.z or p:GetPos().z
                s.maxZ = s.z0
                s.paused = nil
            end
        end
    end)
    hook.Add("GK_RoachKilled", "GK_Score", function(roach, how, by)
        if IsValid(by) and by:IsPlayer() and by.GK_Score then add(by.GK_Score, "smashed", "Roaches Smashed", 10, 0, 1) end
    end)
    hook.Add("GK_RoachesBanked", "GK_Score", function(ply, n)
        if ply.GK_Score and n > 0 then add(ply.GK_Score, "banked", "Roaches Banked", 20 * n, 0, n) end
    end)
    -- What killed you, in White Knuckle's own words (its deathmessages table);
    -- fights between players, which WK doesn't have, get their own.
    local CLASS_CAUSE = {
        gk_barnacle = "HORRIBLY DEVOURED", gk_turret = "RIDDLED WITH HOLES", gk_bloodbug = "BUMPED TO DEATH",
        gk_ventthing = "GNASHED", gk_gas = "FUSED INTO THE MASS", gk_firejet = "BURNED TO A CRISP",
        gk_gasbag = "TURNED INTO A FINE MIST", gk_drone = "ANALYZED... TO DEATH.", gk_hopper = "FED TO THE FLOCK",
        gk_roach = "SERIOUSLY?", gk_mover = "CRUSHED TO A PULP",
        gk_teeth = "EATEN ALIVE", gk_laddernightmare = "LA..D DER. ER. DDER", -- the Face has none of its own in WK
    }
    function SC.Cause(ply, attacker, inf, dmg)
        for _, e in ipairs({ inf, attacker }) do
            if IsValid(e) and CLASS_CAUSE[e:GetClass()] then return CLASS_CAUSE[e:GetClass()] end
        end
        local t = dmg or 0
        if ply:GetNW2Bool("gk_gibbed", false) or bit.band(t, DMG_BLAST) ~= 0 then return "SPREAD ALL OVER THE WALLS" end
        if GK.IsImpaled and GK.IsImpaled(ply) then return "SKEWERED" end
        if bit.band(t, DMG_FALL) ~= 0 then return "FELL TO YOUR DEATH" end
        if bit.band(t, DMG_DISSOLVE) ~= 0 then return "ATOMIZED" end
        if bit.band(t, bit.bor(DMG_NERVEGAS, DMG_POISON, DMG_ACID, DMG_RADIATION)) ~= 0 then return "FUSED INTO THE MASS" end
        if bit.band(t, DMG_BURN) ~= 0 then return "BURNED TO A CRISP" end
        if bit.band(t, DMG_DROWN) ~= 0 then return "DROWNED" end
        if bit.band(t, bit.bor(DMG_BULLET, DMG_BUCKSHOT)) ~= 0 then return IsValid(attacker) and attacker:IsPlayer() and "SHOT DOWN" or "RIDDLED WITH HOLES" end
        if bit.band(t, DMG_CLUB) ~= 0 and IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply then return "BEATEN TO DEATH" end
        if bit.band(t, DMG_SHOCK) ~= 0 then return "BLASTED APART" end
        if bit.band(t, DMG_CRUSH) ~= 0 then return "CRUSHED TO A PULP" end
        if bit.band(t, DMG_SLASH) ~= 0 then return "SLICED AND DICED" end
        return "KILLED MYSTERIOUSLY"
    end
    hook.Add("DoPlayerDeath", "GK_ScoreCause", function(ply, attacker, dmg)
        ply.GK_DeathDmg = dmg and dmg:GetDamageType() or 0
    end)

    hook.Add("PlayerDeath", "GK_Score", function(victim, inf, attacker)
        if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim and attacker.GK_Score then
            add(attacker.GK_Score, "kills", "Kills", 50, 0, 1)
        end
        -- Died in the run: your score is final now.
        if victim.GK_Score then
            victim.GK_Score.t1 = CurTime()
            victim.GK_Score.cause = SC.Cause(victim, attacker, inf, victim.GK_DeathDmg)
            local s = victim.GK_Score
            s.maxZ = s.maxZ + (s.carried or 0)
            SC.Send(victim)
        end
    end)
    hook.Add("GK_ArenaEnd", "GK_Score", function(a, winners)
        local won = {}
        for _, p in ipairs(winners or {}) do won[p] = true end
        for _, p in ipairs(a.players) do
            local s = IsValid(p) and p.GK_Score
            if s then
                s.t1 = CurTime()
                s.maxZ = s.maxZ + (s.carried or 0)
                if won[p] then add(s, "win", "Won", 0, 4, 1) end -- WK: x5
                SC.Send(p)
            end
        end
    end)
end

if CLIENT then
    surface.CreateFont("GK_ScoreTitle", { font = "Impact", size = ScreenScale(34), weight = 800 })
    surface.CreateFont("GK_ScoreRow", { font = "Courier New", size = ScreenScale(9), weight = 800 })
    surface.CreateFont("GK_ScoreBig", { font = "Courier New", size = ScreenScale(13), weight = 900 })
    surface.CreateFont("GK_ScoreFinal", { font = "Courier New", size = ScreenScale(17), weight = 900 })

    surface.CreateFont("GK_DiedTitle", { font = "Impact", size = ScreenScale(46), weight = 900 })
    surface.CreateFont("GK_DiedCause", { font = "Impact", size = ScreenScale(17), weight = 600 })
    surface.CreateFont("GK_DiedTop", { font = "Courier New", size = ScreenScale(11), weight = 900 })
    local shown, showUntil = nil, 0
    local SHOW, DIED = 10, 3.5
    local died, diedAt = nil, 0
    net.Receive("gk_score", function()
        shown = net.ReadTable()
        if shown.cause then
            -- Died in the run: WK's death screen first, the score after it.
            died, diedAt = shown, CurTime()
            showUntil = CurTime() + DIED + SHOW
            timer.Simple(DIED, function() surface.PlaySound("gknuckle/ui/computer_chime_new.wav") end)
        else
            died = nil
            showUntil = CurTime() + SHOW
            surface.PlaySound("gknuckle/ui/computer_chime_new.wav")
        end
    end)
    -- YOU DIED: a blood splat, the words in red, what did it underneath, and
    -- how far you got along the top.
    hook.Add("HUDPaint", "GK_DeathScreen", function()
        if not died then return end
        local t = CurTime() - diedAt
        if t > DIED + SHOW then died = nil return end
        local w, h = ScrW(), ScrH()
        local fade = math.Clamp(t / 0.4, 0, 1)
        surface.SetDrawColor(0, 0, 0, 200 * fade) surface.DrawRect(0, 0, w, h)
        draw.SimpleText(("CLIMBED %d METERS"):format(math.floor(died.dist)), "GK_DiedTop", w / 2, h * 0.04, Color(220, 220, 220, 230 * fade), TEXT_ALIGN_CENTER)
        if t > DIED then return end -- the score panel takes the middle now
        local a = math.Clamp((DIED - t) / 0.5, 0, 1) * fade
        -- The splat: a fixed scatter of dark red blots behind the words.
        draw.NoTexture()
        for i = 1, 22 do
            local rx, ry = math.sin(i * 12.9898) * 43758.5453 % 1, math.sin(i * 78.233) * 43758.5453 % 1
            local r = h * (0.02 + 0.05 * (math.sin(i * 3.1) * 0.5 + 0.5))
            local cx, cy = w / 2 + (rx - 0.5) * w * 0.32, h / 2 + (ry - 0.5) * h * 0.28
            surface.SetDrawColor(110, 8, 8, 170 * a)
            local poly = {}
            for k = 0, 11 do local ang = k / 12 * math.pi * 2 poly[#poly + 1] = { x = cx + math.cos(ang) * r, y = cy + math.sin(ang) * r } end
            surface.DrawPoly(poly)
        end
        draw.SimpleText("YOU DIED", "GK_DiedTitle", w / 2, h / 2, Color(190, 10, 10, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(died.cause or "", "GK_DiedCause", w / 2, h / 2 + ScreenScale(34), Color(150, 150, 150, 220 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)
    SC.Shown = function() return shown, showUntil end

    local YELLOW, RED, GREEN, DIM = Color(250, 205, 60), Color(220, 40, 40), Color(110, 220, 90), Color(200, 170, 120)
    local function dots(x0, x1, y, left, right, font, col)
        surface.SetFont(font)
        local lw = surface.GetTextSize(left)
        local rw = surface.GetTextSize(right)
        local dw = surface.GetTextSize(".")
        local n = math.max(0, math.floor((x1 - x0 - lw - rw) / dw))
        draw.SimpleText(left .. string.rep(".", n), font, x0, y, col)
        draw.SimpleText(right, font, x1, y, col, TEXT_ALIGN_RIGHT)
    end

    hook.Add("HUDPaint", "GK_ScoreScreen", function()
        if not shown or CurTime() > showUntil or CurTime() < showUntil - SHOW then return end
        local a = math.Clamp((showUntil - CurTime()) / 0.6, 0, 1) * math.Clamp((CurTime() - (showUntil - SHOW)) / 0.3, 0, 1)
        surface.SetAlphaMultiplier(a)
        local w, h = ScrW(), ScrH()
        local pw, ph = math.min(w * 0.34, 640), h * 0.52
        local x, y = (w - pw) / 2, h * 0.22
        -- The WK panel: a dark amber card with a lit edge.
        surface.SetDrawColor(30, 18, 6, 235) surface.DrawRect(x, y, pw, ph)
        surface.SetDrawColor(170, 110, 30, 255) surface.DrawOutlinedRect(x, y, pw, ph, 3)
        surface.SetDrawColor(120, 75, 20, 255) surface.DrawOutlinedRect(x + 10, y + 10, pw - 20, ph - 20, 2)
        draw.SimpleText("SCORE", "GK_ScoreTitle", w / 2, y - ScreenScale(14), YELLOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local lx, rx = x + 28, x + pw - 28
        local cy = y + ScreenScale(14)
        dots(lx, rx, cy, "DISTANCE:", ("%dM"):format(math.floor(shown.dist)), "GK_ScoreBig", YELLOW)
        cy = cy + ScreenScale(13)
        dots(lx, rx, cy, "SPEED:", ("%.2fm/s"):format(shown.speed), "GK_ScoreBig", YELLOW)
        cy = cy + ScreenScale(16)
        surface.SetDrawColor(200, 140, 40, 255) surface.DrawRect(lx, cy, rx - lx, 2)
        cy = cy + ScreenScale(5)
        draw.SimpleText("MODIFIERS", "GK_ScoreBig", lx, cy, YELLOW)
        draw.SimpleText(("SCORE: %d"):format(math.floor(shown.base)), "GK_ScoreBig", rx, cy, DIM, TEXT_ALIGN_RIGHT)
        cy = cy + ScreenScale(15)
        -- Modifier rows, two to a line like WK's.
        local colW = (rx - lx - 10) / 2
        for i, r in ipairs(shown.rows) do
            local cx = lx + ((i - 1) % 2) * (colW + 10)
            local ry = cy + math.floor((i - 1) / 2) * ScreenScale(11)
            surface.SetDrawColor(60, 36, 10, 255) surface.DrawRect(cx, ry - 2, colW, ScreenScale(10))
            local label = r.title .. (r.count > 0 and r.mult == nil and (" (" .. r.count .. ")") or "")
            draw.SimpleText(label, "GK_ScoreRow", cx + 6, ry, YELLOW)
            local val, col
            if r.mult then val, col = ("%.2fX"):format(r.mult), r.mult >= 1 and YELLOW or RED
            else val, col = ("+%d"):format(math.floor(r.bonus)), GREEN end
            draw.SimpleText(val, "GK_ScoreRow", cx + colW - 6, ry, col, TEXT_ALIGN_RIGHT)
        end
        surface.SetDrawColor(200, 140, 40, 255) surface.DrawRect(lx, y + ph - ScreenScale(30), rx - lx, 2)
        draw.SimpleText(("FINAL: %.2f"):format(shown.final), "GK_ScoreFinal", w / 2, y + ph - ScreenScale(17), RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        surface.SetAlphaMultiplier(1)
    end)
end
