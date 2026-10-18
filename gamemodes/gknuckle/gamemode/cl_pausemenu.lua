-- gKnuckle's pause menu, in place of Garry's Mod's on ESC. Laid out like
-- White Knuckle's (its Game-Main scene): a dim red "PAUSED", then RESUME,
-- SETTINGS and LEAVE RUN (with WK's "ARE YOU SURE?" warning), in the
-- MonocleFixed terminal font. Two more lines reach what a gamemode can't
-- replace: GARRY'S MOD MENU opens the normal menu (options, servers, quit),
-- DISCONNECT leaves the server. ESC closes it again. gk_pausemenu 0 brings
-- back the plain Garry's Mod menu.

local cvOn = CreateClientConVar("gk_pausemenu", "1", true, false, "Use gKnuckle's own pause menu on ESC")

local function fonts()
    local h = ScrH()
    surface.CreateFont("GK_PauseTitle", { font = "MonocleFixed", size = math.floor(h / 11), weight = 500, antialias = false })
    surface.CreateFont("GK_PauseItem", { font = "MonocleFixed", size = math.floor(h / 22), weight = 500, antialias = false })
    surface.CreateFont("GK_PauseSmall", { font = "MonocleFixed", size = math.floor(h / 40), weight = 500, antialias = false })
end
fonts()
hook.Add("OnScreenSizeChanged", "GK_PauseFonts", fonts)

-- WK's colours: the PAUSED title is red at 45% (0.72, 0.19, 0.19), items off-white.
local RED = Color(183, 47, 47, 115)
local TEXT, DIM, HOT = Color(225, 220, 210), Color(140, 132, 120), Color(255, 196, 64)

local menu
local passThrough = false -- let the next ESC through to Garry's Mod's own menu

local function close()
    if IsValid(menu) then menu:Remove() end
    menu = nil
end

local function item(parent, text, onClick, small)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetTall(math.floor(ScrH() / (small and 26 or 15)))
    b:Dock(TOP)
    b.Label = text
    b.Paint = function(s, w, h)
        local hot = s:IsHovered()
        local label = (hot and "> " or "  ") .. (isfunction(s.Label) and s.Label() or s.Label)
        draw.SimpleText(label, small and "GK_PauseSmall" or "GK_PauseItem", 0, h / 2, hot and HOT or (small and DIM or TEXT), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        return true
    end
    b.OnCursorEntered = function() surface.PlaySound("buttons/lightswitch2.wav") end
    b.DoClick = function() surface.PlaySound("buttons/button9.wav") onClick(b) end
    return b
end

-- Settings: gKnuckle's own client options, plus the two keys it binds. FOV,
-- mouse and volume are engine settings Lua may not change: they stay in the
-- Garry's Mod menu's options.
local function settings(parent)
    local p = vgui.Create("DScrollPanel", parent)
    p:Dock(FILL)
    local function check(label, cv)
        local c = p:Add("DCheckBoxLabel")
        c:Dock(TOP) c:DockMargin(0, 6, 0, 0)
        c:SetText(label) c:SetFont("GK_PauseSmall") c:SetTextColor(TEXT)
        c:SetConVar(cv)
    end
    local function slider(label, cv, lo, hi, dec)
        local s = p:Add("DNumSlider")
        s:Dock(TOP) s:DockMargin(0, 6, 0, 0) s:SetTall(32)
        s:SetText(label) s:SetMin(lo) s:SetMax(hi) s:SetDecimals(dec or 0)
        s:SetConVar(cv)
        s.Label:SetFont("GK_PauseSmall") s.Label:SetTextColor(TEXT)
    end
    local function binder(label, cv)
        local row = p:Add("DPanel")
        row:Dock(TOP) row:DockMargin(0, 6, 0, 0) row:SetTall(34) row:SetPaintBackground(false)
        local l = vgui.Create("DLabel", row)
        l:Dock(LEFT) l:SetWide(ScrW() * 0.16) l:SetFont("GK_PauseSmall") l:SetTextColor(TEXT) l:SetText(label)
        local b = vgui.Create("DBinder", row)
        b:Dock(LEFT) b:SetWide(160) b:SetConVar(cv)
    end
    check("White Knuckle screen effects", "gk_post")
    check("Room lamps as real lights", "gk_roomlights")
    slider("Room lamps lit at once", "gk_roomlights_max", 2, 24)
    check("See your legs", "gk_husk_fplegs")
    binder("Kick", "gk_kick_key")
    binder("Drop held item", "gk_drop_key")
    check("Use this pause menu (off: Garry's Mod's)", "gk_pausemenu")
    return p
end

local function open()
    close()
    local f = vgui.Create("EditablePanel")
    menu = f
    f:SetSize(ScrW(), ScrH())
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f.Opened = SysTime()
    f.Paint = function(s, w, h)
        Derma_DrawBackgroundBlur(s, s.Opened)
        surface.SetDrawColor(8, 4, 4, 200)
        surface.DrawRect(0, 0, w, h)
        -- faint scanlines, like WK's terminals
        surface.SetDrawColor(0, 0, 0, 60)
        for y = 0, h, 4 do surface.DrawRect(0, y, w, 1) end
        draw.SimpleText("PAUSED", "GK_PauseTitle", w * 0.08, h * 0.12, RED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("gKnuckle  |  " .. game.GetMap() .. "  |  " .. (GetHostName() or ""), "GK_PauseSmall", w * 0.08, h * 0.94, DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    end
    f.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE then close() end end

    local col = vgui.Create("DPanel", f)
    col:SetPaintBackground(false)
    col:SetPos(ScrW() * 0.08, ScrH() * 0.30)
    col:SetSize(ScrW() * 0.34, ScrH() * 0.6)
    f.Col = col

    local side -- the settings panel, beside the list
    local confirm = false
    item(col, "RESUME", close)
    item(col, "SETTINGS", function()
        if IsValid(side) then side:Remove() side = nil return end
        side = vgui.Create("DPanel", f)
        side:SetPos(ScrW() * 0.46, ScrH() * 0.30)
        side:SetSize(ScrW() * 0.44, ScrH() * 0.55)
        side.Paint = function(s, w, h)
            surface.SetDrawColor(20, 12, 12, 220) surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(RED.r, RED.g, RED.b, 160) surface.DrawOutlinedRect(0, 0, w, h)
        end
        side:DockPadding(16, 12, 16, 12)
        settings(side)
        f.Side = side
    end)
    local leave = item(col, function()
        return confirm and "ARE YOU SURE?  YOU WILL LOSE THIS RUN" or "LEAVE RUN"
    end, function()
        if not confirm then confirm = true return end
        RunConsoleCommand("gk_leaverun")
        close()
    end)
    leave.OnCursorExited = function() confirm = false end
    item(col, "", function() end, true).Paint = function() end -- a gap
    item(col, "GARRY'S MOD MENU", function()
        close()
        passThrough = true
        gui.ActivateGameUI()
    end, true)
    item(col, "DISCONNECT", function()
        close()
        RunConsoleCommand("disconnect")
    end, true)
    GK.PauseMenu = f
    return f
end
GK.OpenPauseMenu = open
GK.ClosePauseMenu = close

function GM:OnPauseMenuShow()
    if passThrough or not cvOn:GetBool() then passThrough = false return true end
    if IsValid(menu) then close() else open() end
    return false
end
