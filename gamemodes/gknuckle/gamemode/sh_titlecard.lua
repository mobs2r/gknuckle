-- WK's region title card: as you drop into a region its name fades up in the
-- middle of the screen for a moment ("SILOS", "PIPEWORKS"...), from the
-- region's own introText, then it's gone. The only text in a run besides the
-- death screen.

if SERVER then
    util.AddNetworkString("gk_titlecard")

    local function introText(region)
        local data = util.JSONToTable(file.Read("data_static/gknuckle/regions.json", "GAME") or "") or {}
        local r = data.regions and data.regions[region or ""]
        return r and (r.introText or r.name) or nil
    end

    function GK.TitleCard(players, title, sub)
        if not title or title == "" then return end
        net.Start("gk_titlecard")
        net.WriteString(string.upper(title))
        net.WriteString(sub or "")
        net.Send(players)
    end

    local function show(a)
        local list = {}
        for _, p in ipairs(a.players) do if IsValid(p) and p:Alive() then list[#list + 1] = p end end
        local stages = GetConVar("gk_run_regions") and GetConVar("gk_run_regions"):GetInt() or 3
        -- After the tube ride / the break's fade-in, not under it.
        timer.Simple(1.2, function()
            local ok = {}
            for _, p in ipairs(list) do if IsValid(p) then ok[#ok + 1] = p end end
            local mode = a.mode == "iron" and "  IRON KNUCKLE" or a.mode == "hard" and "  HARD" or ""
            GK.TitleCard(ok, introText(a.info and a.info.region), ("%d / %d"):format(a.stage or 1, stages) .. mode)
        end)
    end
    hook.Add("GK_ArenaStart", "GK_TitleCard", show)
    hook.Add("GK_ArenaStage", "GK_TitleCard", show)
end

if CLIENT then
    surface.CreateFont("GK_TitleCard", { font = "Impact", size = ScreenScale(40), weight = 900 })
    surface.CreateFont("GK_TitleSub", { font = "Courier New", size = ScreenScale(10), weight = 900 })
    local title, sub, at = nil, nil, 0
    local IN, HOLD, OUT = 0.6, 2.2, 1.2
    net.Receive("gk_titlecard", function()
        title, sub, at = net.ReadString(), net.ReadString(), CurTime()
        surface.PlaySound("gknuckle/ui/computer_chime_new.wav")
    end)
    hook.Add("HUDPaint", "GK_TitleCard", function()
        if not title then return end
        local t = CurTime() - at
        if t > IN + HOLD + OUT then title = nil return end
        local a = t < IN and t / IN or (t < IN + HOLD and 1 or 1 - (t - IN - HOLD) / OUT)
        local w, h = ScrW(), ScrH()
        -- Letter spacing opens out a little as it holds, like WK's.
        local spread = 1 + 0.06 * math.min(1, t / (IN + HOLD))
        local text = table.concat(string.Explode("", title), string.rep(" ", spread > 1.03 and 1 or 0))
        draw.SimpleText(text, "GK_TitleCard", w / 2 + 3, h * 0.33 + 3, Color(0, 0, 0, 160 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(text, "GK_TitleCard", w / 2, h * 0.33, Color(235, 230, 220, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if sub ~= "" then
            draw.SimpleText(sub, "GK_TitleSub", w / 2, h * 0.33 + ScreenScale(30), Color(190, 180, 160, 200 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end)
end
