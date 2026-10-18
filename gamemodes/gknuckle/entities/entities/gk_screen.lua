AddCSLuaFile()

-- A wall screen in the hub: leaderboards and "run in progress" boards. The map
-- places them (keyvalues kind, width, height; angles face out from the wall);
-- this entity draws them. Content comes from gameplay through
--   GK.Screens.Set(kind, title, lines)      (server; broadcasts to clients)
-- kinds: leaderboard_kd, leaderboard_money, run_1 .. run_3. A run screen with no
-- lines shows "PLAY NOW!".
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Hub Screen"
ENT.Spawnable = false

GK.Screens = GK.Screens or { data = {} }

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "Kind")
    self:NetworkVar("Float", 0, "Width")
    self:NetworkVar("Float", 1, "Height")
end

function ENT:KeyValue(k, val)
    if k == "kind" then self.GKKind = val end
    if k == "width" then self.GKWidth = tonumber(val) end
    if k == "height" then self.GKHeight = tonumber(val) end
end

if SERVER then
    util.AddNetworkString("gk_screen")

    function ENT:Initialize()
        self:SetModel("models/hunter/plates/plate.mdl")
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetKind(self.GKKind or "run_1")
        self:SetWidth(self.GKWidth or 384)
        self:SetHeight(self.GKHeight or 224)
    end

    local function send(kind, ply)
        local d = GK.Screens.data[kind]
        net.Start("gk_screen")
        net.WriteString(kind)
        net.WriteString(d and d.title or "")
        net.WriteUInt(d and #d.lines or 0, 6)
        for _, l in ipairs(d and d.lines or {}) do net.WriteString(l) end
        if ply then net.Send(ply) else net.Broadcast() end
    end

    function GK.Screens.Set(kind, title, lines)
        GK.Screens.data[kind] = { title = title or "", lines = lines or {} }
        send(kind)
    end

    hook.Add("PlayerInitialSpawn", "GK_ScreensSync", function(ply)
        timer.Simple(5, function()
            if not IsValid(ply) then return end
            for kind in pairs(GK.Screens.data) do send(kind, ply) end
        end)
    end)
end

if CLIENT then
    net.Receive("gk_screen", function()
        local kind = net.ReadString()
        local title = net.ReadString()
        local n = net.ReadUInt(6)
        local lines = {}
        for i = 1, n do lines[i] = net.ReadString() end
        GK.Screens.data[kind] = { title = title, lines = lines }
    end)

    surface.CreateFont("GK_ScreenTitle", { font = "MonocleFixed", size = 32, weight = 500, antialias = false })
    surface.CreateFont("GK_ScreenLine", { font = "MonocleFixed", size = 24, weight = 500, antialias = false })
    surface.CreateFont("GK_ScreenBig", { font = "MonocleFixed", size = 62, weight = 500, antialias = false })

    local DEFAULT_TITLE = { leaderboard_kd = "V CORP // SUBJECT RANKING / K-D", leaderboard_money = "V CORP // SUBJECT RANKING / CRABCOIN",
        run_1 = "V CORP // TRIAL CHAMBER 1", run_2 = "V CORP // TRIAL CHAMBER 2", run_3 = "V CORP // TRIAL CHAMBER 3" }

    function ENT:Initialize()
        self:SetRenderBounds(Vector(-300, -300, -300), Vector(300, 300, 300))
    end

    function ENT:Draw()
        local w, h = self:GetWidth(), self:GetHeight()
        local kind = self:GetKind()
        local d = GK.Screens.data[kind]
        -- Gameplay's shared hub API (sh_hub.lua) wins when present; it decodes JSON,
        -- so refresh twice a second, not per frame.
        if GK.Hub and (self.GKNextHub or 0) < CurTime() then
            self.GKNextHub = CurTime() + 0.5
            if kind == "leaderboard_kd" and GK.Hub.TopKD then
                local lines = {}
                for i, r in ipairs(GK.Hub.TopKD(8) or {}) do lines[i] = ("%2d  %-14s %3d/%-3d %5.2f"):format(i, string.sub(r.name or "?", 1, 14), r.kills or 0, r.deaths or 0, r.kd or 0) end
                if #lines > 0 then d = { title = "", lines = lines } end
            elseif kind == "leaderboard_money" and GK.Hub.TopMoney then
                local lines = {}
                for i, r in ipairs(GK.Hub.TopMoney(8) or {}) do lines[i] = ("%2d  %-14s %6d"):format(i, string.sub(r.name or "?", 1, 14), r.roaches or 0) end
                if #lines > 0 then d = { title = "", lines = lines } end
            elseif string.StartWith(kind, "run_") and GK.Hub.Arenas then
                local a = (GK.Hub.Arenas() or {})[tonumber(string.sub(kind, 5)) or 0]
                if a and a.active then
                    d = { title = "", lines = { ("RUN iN PROGRESS"), ("SUBJECTS ALiVE  %d / %d"):format(a.alive or 0, a.total or 0),
                        ("ELAPSED  %s"):format(string.FormattedTime(CurTime() - (a.started or CurTime()), "%02i:%02i")), ("GAS  z %d"):format(a.gasHeight or 0) } }
                else d = nil end
            end
            self.GKHubData = d
        elseif GK.Hub then
            d = self.GKHubData
        end
        if EyePos():DistToSqr(self:GetPos()) > 2500 * 2500 then return end
        local t = CurTime()
        -- Face out of the wall: the entity's forward is the screen normal.
        local ang = self:GetAngles()
        ang:RotateAroundAxis(ang:Up(), 90)
        ang:RotateAroundAxis(ang:Forward(), 90)
        local scale = 0.5
        cam.Start3D2D(self:GetPos() + self:GetForward() * 1, ang, scale)
            local W, H = w / scale, h / scale
            surface.SetDrawColor(8, 12, 10, 255)
            surface.DrawRect(-W / 2, -H / 2, W, H)
            -- scanline band
            local sy = (t * 120) % H
            surface.SetDrawColor(40, 70, 50, 60)
            surface.DrawRect(-W / 2, -H / 2 + sy, W, 6)
            local amber = Color(255, 190, 90)
            draw.SimpleText(d and d.title ~= "" and d.title or DEFAULT_TITLE[kind] or kind, "GK_ScreenTitle", -W / 2 + 24, -H / 2 + 18, amber, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            surface.SetDrawColor(amber.r, amber.g, amber.b, 160)
            surface.DrawRect(-W / 2 + 24, -H / 2 + 62, W - 48, 2)
            if d and #d.lines > 0 then
                for i, l in ipairs(d.lines) do
                    if i > 8 then break end
                    draw.SimpleText(l, "GK_ScreenLine", -W / 2 + 28, -H / 2 + 76 + (i - 1) * 32, Color(220, 230, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end
            elseif string.StartWith(kind, "run_") then
                local pulse = 170 + 85 * math.sin(t * 3)
                draw.SimpleText("PLAY NOW!", "GK_ScreenBig", 0, 30, Color(120, 255, 140, pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText("step onto the pad, subject", "GK_ScreenLine", 0, 110, Color(160, 180, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText("NO DATA", "GK_ScreenLine", 0, 40, Color(120, 130, 110), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end
end
