-- The facility's PA, like WK's announcer: now and then during a run, an alert
-- or notice for the region you're in plays over the speakers ("Alert: water
-- seepage detected...", "Notice: system flush..."). White Knuckle's own lines
-- (sound/gknuckle/announcer), picked by region: Silos (m1), Pipeworks (m2),
-- Habitation (m3), Chimney; the facility-wide ones can come up anywhere. The
-- scripted hatch-event chain is left out (it belongs to its own room).
-- Voice only: no subtitles, keeping the screen clear.

if SERVER then
    util.AddNetworkString("gk_announce")
    local cvOn = CreateConVar("gk_announcer", "1", FCVAR_ARCHIVE, "The facility PA plays White Knuckle's announcements during runs")
    local cvGap = CreateConVar("gk_announcer_gap", "90", FCVAR_ARCHIVE, "Average seconds between announcements in a run")

    local lines -- [prefix] = { file, ... }
    local function load()
        if lines then return lines end
        lines = { m1 = {}, m2 = {}, m3 = {}, chimney = {}, any = {} }
        for _, f in ipairs(file.Find("sound/gknuckle/announcer/*.wav", "GAME")) do
            if not f:find("hatchevent") then
                local key = f:match("^ann_(m%d)_") or (f:find("^ann_chimney") and "chimney") or "any"
                table.insert(lines[key] or lines.any, "gknuckle/announcer/" .. f)
            end
        end
        return lines
    end

    local function pick(region)
        local L = load()
        local key = region:find("Silos") and "m1" or region:find("Pipeworks") and "m2" or region:find("Habitation") and "m3"
            or region:find("Chimney") and "chimney" or nil
        local pool = key and L[key] or {}
        -- Mostly the region's own, sometimes a facility-wide one.
        if #pool == 0 or (#L.any > 0 and math.random() < 0.25) then pool = L.any end
        return #pool > 0 and pool[math.random(#pool)] or nil
    end

    function GK.Announce(players, path)
        if not path or #players == 0 then return end
        net.Start("gk_announce") net.WriteString(path) net.Send(players)
    end

    timer.Create("GK_Announcer", 5, 0, function()
        if not cvOn:GetBool() or not GK.Rounds then return end
        for index, a in pairs(GK.Rounds.arenas) do
            a.nextAnnounce = a.nextAnnounce or (CurTime() + 25)
            if not a.inBreak and CurTime() >= a.nextAnnounce then
                a.nextAnnounce = CurTime() + cvGap:GetFloat() * math.Rand(0.6, 1.4)
                local list = {}
                for _, p in ipairs(a.players) do
                    -- Climbers and anyone watching them hear it; the break room doesn't.
                    if IsValid(p) and GK.ArenaOf(p) == index and not (GK.AtBreak and GK.AtBreak(p)) then list[#list + 1] = p end
                end
                GK.Announce(list, pick(a.info and a.info.region or ""))
            end
        end
    end)
    -- A new region: its first announcement a little while in.
    hook.Add("GK_ArenaStage", "GK_Announcer", function(a) a.nextAnnounce = CurTime() + 25 end)
end

if CLIENT then
    net.Receive("gk_ascended", function() surface.PlaySound("gknuckle/ui/ascended.ogg") end)
    net.Receive("gk_announce", function()
        local path = net.ReadString()
        -- A PA chime first, then the voice, a touch quieter than the world.
        surface.PlaySound("gknuckle/ui/computer_chime_new.wav")
        timer.Simple(0.6, function()
            local me = LocalPlayer()
            if IsValid(me) then me:EmitSound(path, 0, 100, 0.8, CHAN_STATIC) end
        end)
    end)
end
