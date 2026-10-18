-- White Knuckle style inventory UI.
-- Hold Tab: your bag opens. Items sit loose in it; drag them around, drag one
-- onto a hand (bottom left/right) to hold it, onto a pocket to stow it, or out
-- of the bag to drop it. Q / E pocket the left / right hand's item.
-- Also draws held items floating in your mind-hands.

GK.ClientInv = GK.ClientInv or { bag = {}, slots = {}, maxWeight = 12 }

net.Receive("gk_inv", function()
    GK.ClientInv = net.ReadTable()
    if IsValid(GK.InvPanel) then GK.InvPanel:Rebuild() end
end)

local function sendMove(id, target, x, y)
    net.Start("gk_inv_move")
    net.WriteUInt(id, 16)
    net.WriteString(target)
    net.WriteFloat(x or 0.5)
    net.WriteFloat(y or 0.5)
    net.SendToServer()
end

local function label(item)
    local def = GK.ItemDef(item.class)
    if not def then return item.class end
    return def.Label and (def.name .. " " .. def.Label(item)) or def.name
end

-- WK shows items in the inventory as the same 2D sprites you hold them by:
-- the item layer of each held layout (data_static/gknuckle/held.json).
local spriteOf = {}
hook.Add("GK_PackMounted", "GK_InvSprites", function() spriteOf = {} end) -- sprites come from playable-pack
local function itemSprite(class)
    if spriteOf[class] == nil then
        spriteOf[class] = false
        local held = util.JSONToTable(file.Read("data_static/gknuckle/held.json", "GAME") or "") or {}
        local lay = held[class]
        for _, l in ipairs(lay and lay.layers or {}) do
            if l.kind == "item" and l.png then
                -- "icon": a different picture for the bag than in the hand (the roaches).
                spriteOf[class] = { mat = Material(l.icon or l.png, "noclamp"), tint = l.tint or lay.tint }
                break
            end
        end
    end
    if spriteOf[class] then return spriteOf[class] end
    -- No WK sprite: the item's model rendered flat, so the bag reads as one set.
    local ms = GK.ModelSprite and GK.ModelSprite(class)
    return ms and { mat = ms.mat } or nil
end
GK.ItemSprite = itemSprite

-- One item icon (draggable): its WK sprite, or a 3D model icon if it has none.
local function itemIcon(parent, item, size)
    local def = GK.ItemDef(item.class)
    local sprite = itemSprite(item.class)
    local icon
    if sprite then
        icon = vgui.Create("DPanel", parent)
        icon:SetSize(size, size)
        icon.Paint = function(_, w, h)
            local t = sprite.tint
            surface.SetDrawColor(t and t[1] or 255, t and t[2] or 255, t and t[3] or 255, 255)
            surface.SetMaterial(sprite.mat)
            local mw, mh = sprite.mat:Width(), sprite.mat:Height()
            local k = math.min(w / mw, h / mh) * 0.9
            surface.DrawTexturedRect((w - mw * k) / 2, (h - mh * k) / 2, mw * k, mh * k)
        end
        icon:SetCursor("hand")
    else
        icon = vgui.Create("SpawnIcon", parent)
        icon:SetSize(size, size)
        icon:SetModel(def and def.model or "models/error.mdl")
        icon:SetTooltip(false)
    end
    icon.GKItem = item
    icon:Droppable("gk_item")
    -- No text on screen: counts (rebar left, rounds in the cylinder) are pips.
    icon.PaintOver = function(s, w, h)
        local n = item.data and (item.data.count or item.data.clip)
        if not n then return end
        for i = 1, n do
            surface.SetDrawColor(GK.Colors.Orange.r, GK.Colors.Orange.g, GK.Colors.Orange.b, 230)
            surface.DrawRect(w - 4 - i * 7, h - 9, 5, 5)
        end
    end
    return icon
end

local function slotPanel(parent, slot, x, y, size)
    local p = vgui.Create("DPanel", parent)
    p:SetPos(x, y)
    p:SetSize(size, size)
    p.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(20, 16, 12, s:IsHovered() and 235 or 200))
        surface.SetDrawColor(GK.Colors.Orange.r, GK.Colors.Orange.g, GK.Colors.Orange.b, 160)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
    end
    p:Receiver("gk_item", function(self, panels, dropped)
        if dropped and panels[1] and panels[1].GKItem then sendMove(panels[1].GKItem.id, slot) end
    end)
    local item = GK.ClientInv.slots[slot]
    if item then
        local icon = itemIcon(p, item, size - 12)
        icon:SetPos(6, 6)
    end
    return p
end

local PANEL = {}

function PANEL:Init()
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:Rebuild()
end

function PANEL:Rebuild()
    self:Clear()
    local w, h = ScrW(), ScrH()

    -- Bag: items lie where you put them (positions are 0-1 in the bag area).
    local bw, bh = math.min(w * 0.5, 760), math.min(h * 0.5, 420)
    local bag = vgui.Create("DPanel", self)
    bag:SetSize(bw, bh)
    bag:SetPos((w - bw) / 2, h * 0.18)
    bag.Paint = function(s, pw, ph)
        draw.RoundedBox(10, 0, 0, pw, ph, Color(20, 16, 12, 245))
        surface.SetDrawColor(120, 90, 50, 200)
        surface.DrawOutlinedRect(0, 0, pw, ph, 3)
        local inv = GK.ClientInv
        local weight = 0
        for _, it in ipairs(inv.bag) do weight = weight + ((GK.ItemDef(it.class) or {}).weight or 1) end
        -- Weight as a bar along the top edge.
        surface.SetDrawColor(GK.Colors.Orange.r, GK.Colors.Orange.g, GK.Colors.Orange.b, 200)
        surface.DrawRect(12, 10, (pw - 24) * math.min(weight / (inv.maxWeight or 12), 1), 6)
        -- Roaches in the bag, as WK's roach sprites along the bottom edge:
        -- a platinum one for every 5, gold for the rest.
        local n = LocalPlayer():GetNW2Int("gk_roaches", 0)
        local x = 12
        local gold, plat = itemSprite("roach"), itemSprite("roach_platinum")
        local function bug(sp, fr, fg, fb)
            if sp then
                surface.SetDrawColor(255, 255, 255, 255) surface.SetMaterial(sp.mat)
                surface.DrawTexturedRect(x, ph - 30, 26, 26)
            else
                surface.SetDrawColor(fr, fg, fb, 230) surface.DrawRect(x + 9, ph - 16, 8, 8)
            end
            x = x + 22
        end
        for _ = 1, math.min(math.floor(n / 5), 30) do bug(plat, 220, 230, 240) end
        for _ = 1, n % 5 do bug(gold, 255, 200, 40) end
    end
    bag:Receiver("gk_item", function(s, panels, dropped, _, x, y)
        if dropped and panels[1] and panels[1].GKItem then
            sendMove(panels[1].GKItem.id, "bag", x / bw, y / bh)
        end
    end)
    local isize = 72
    for _, item in ipairs(GK.ClientInv.bag) do
        local icon = itemIcon(bag, item, isize)
        icon:SetPos(math.Clamp(item.x * bw - isize / 2, 4, bw - isize - 4), math.Clamp(item.y * bh - isize / 2, 30, bh - isize - 4))
    end

    -- Hands and pockets along the bottom.
    local s = 110
    slotPanel(self, "hand_l", w * 0.18, h - s - 70, s)
    slotPanel(self, "pocket_l", w * 0.18 + s + 24, h - s * 0.7 - 70, s * 0.7)
    slotPanel(self, "pocket_r", w * 0.82 - s - 24 - s * 0.7, h - s * 0.7 - 70, s * 0.7)
    slotPanel(self, "hand_r", w * 0.82 - s, h - s - 70, s)
end

-- Dropping onto empty screen (outside bag/slots) throws the item into the world.
function PANEL:Paint() end
vgui.Register("GKInventory", PANEL, "EditablePanel")

local function openInv()
    if IsValid(GK.InvPanel) then return end
    GK.InvPanel = vgui.Create("GKInventory")
    GK.InvPanel:Receiver("gk_item", function(s, panels, dropped)
        if dropped and panels[1] and panels[1].GKItem then sendMove(panels[1].GKItem.id, "world") end
    end)
    gui.EnableScreenClicker(true)
end

local function closeInv()
    if IsValid(GK.InvPanel) then GK.InvPanel:Remove() end
    gui.EnableScreenClicker(false)
end

-- Tab is the bag (hold it, like White Knuckle). The scoreboard moves to nothing.
function GM:ScoreboardShow() openInv() return true end
function GM:ScoreboardHide() closeInv() return true end

-- (Q never opens the spawn menu now: sh_emotes.lua.)

-- HUD: a small square in each bottom corner, filled when that pocket holds something.
hook.Add("HUDPaint", "GK_Pockets", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local s = GK.ClientInv.slots
    for _, side in ipairs({ "l", "r" }) do
        local x = side == "l" and 20 or ScrW() - 34
        surface.SetDrawColor(255, 255, 255, 90)
        surface.DrawOutlinedRect(x, ScrH() - 34, 14, 14, 2)
        local pk = s["pocket_" .. side]
        if pk then
            -- What is in that pocket, as its WK sprite (a filled pip if it has none).
            local sp = GK.ItemSprite and GK.ItemSprite(pk.class)
            if sp then
                surface.SetDrawColor(255, 255, 255, 230) surface.SetMaterial(sp.mat)
                surface.DrawTexturedRect(x - 9, ScrH() - 58, 32, 32)
            else
                surface.SetDrawColor(GK.Colors.Orange.r, GK.Colors.Orange.g, GK.Colors.Orange.b, 220)
                surface.DrawRect(x + 3, ScrH() - 31, 8, 8)
            end
        end
    end
end)

-- Held items: float a model in each hand that holds one.
local held = {}
local function heldModel(side, class)
    local def = GK.ItemDef(class)
    if not def then return end
    local m = held[side]
    if not IsValid(m) or m.GKClass ~= class then
        if IsValid(m) then m:Remove() end
        m = ClientsideModel(def.model, RENDERGROUP_OPAQUE)
        if not IsValid(m) then return end
        m:SetNoDraw(true)
        m:SetModelScale(def.hold and def.hold.scale or 1)
        m.GKClass = class
        held[side] = m
    end
    return m, def
end

-- Called by cl_hands.lua right after it draws the hands, so the model sits
-- in front of the hand sprite. Items with WK held sprites are drawn there instead.
function GK.DrawHeldModels()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or ply:ShouldDrawLocalPlayer() then return end
    local busy = ply:GetNW2Float("gk_busy_until", 0) > CurTime()
    local eye, ang = EyePos(), EyeAngles()
    cam.Start3D(eye, ang, 62)
    render.DepthRange(0, 0.05) -- always on top, like a viewmodel
    for _, side in ipairs({ "l", "r" }) do
        local item = GK.ClientInv.slots["hand_" .. side]
        if item and not (GK.HeldLayout and GK.HeldLayout(item.class)) then
            local m, def = heldModel(side, item.class)
            if IsValid(m) then
                local hold = def.hold or {}
                local a = Angle(ang.p, ang.y, ang.r)
                if hold.ang then
                    a:RotateAroundAxis(a:Up(), hold.ang.y)
                    if hold.ang.p ~= 0 then a:RotateAroundAxis(a:Right(), hold.ang.p) end
                    if hold.ang.r ~= 0 then a:RotateAroundAxis(a:Forward(), hold.ang.r) end
                end
                local bob = math.sin(CurTime() * 1.6 + (side == "r" and 1 or 0)) * 0.4
                local pos
                local palm = GK.HandPalm and GK.HandPalm[side]
                if hold.centre or busy or not palm then
                    -- Guns are held out in the middle where the shot goes, and
                    -- both hands come together to reload.
                    local off = hold.pos or Vector(16, 8, -7)
                    local y = side == "r" and -off.y or off.y
                    if busy then y = y * 0.3 end
                    pos = eye + ang:Forward() * off.x - ang:Right() * y + ang:Up() * (off.z + bob)
                else
                    -- Everything else sits in the palm of that hologram hand,
                    -- centred on the model rather than its origin.
                    -- Far enough out that it looks palm-sized next to the big hologram hand.
                    local dir = util.AimVector(ang, 62, palm.x, palm.y, ScrW(), ScrH())
                    local dist = hold.dist or math.Clamp(m:BoundingRadius() * (hold.scale or 1) * 9, 18, 90)
                    pos = eye + dir * dist + ang:Up() * bob
                    pos = pos - LocalToWorld(m:OBBCenter() * (hold.scale or 1), angle_zero, vector_origin, a)
                end
                m:SetPos(pos)
                m:SetAngles(a)
                m:SetupBones()
                -- Lit evenly like a viewmodel, not by whatever wall it's poking into.
                render.SuppressEngineLighting(true)
                render.ResetModelLighting(0.55, 0.55, 0.55)
                render.SetModelLighting(BOX_TOP, 1, 1, 1)
                render.SetModelLighting(BOX_FRONT, 0.85, 0.85, 0.85)
                m:DrawModel()
                render.SuppressEngineLighting(false)
            end
        end
    end
    render.DepthRange(0, 1)
    cam.End3D()
end

-- Third person: other players' held items sit in their floating hands.
hook.Add("PostPlayerDraw", "GK_HeldItemsWorld", function(ply)
    if not ply:Alive() then return end
    for _, side in ipairs({ "l", "r" }) do
        local class = ply:GetNW2String("gk_hitem_" .. side, "")
        local def = class ~= "" and not (GK.HeldLayout and GK.HeldLayout(class)) and GK.ItemDef(class)
        if def then
            ply.GK_HeldModels = ply.GK_HeldModels or {}
            local m = ply.GK_HeldModels[side]
            if not IsValid(m) or m:GetModel() ~= def.model then
                if IsValid(m) then m:Remove() end
                m = ClientsideModel(def.model, RENDERGROUP_OPAQUE)
                m:SetNoDraw(true)
                m:SetModelScale(def.hold and def.hold.scale or 1)
                ply.GK_HeldModels[side] = m
            end
            local ang = ply:EyeAngles()
            m:SetPos(ply:EyePos() + ang:Forward() * 18 + ang:Right() * (side == "r" and 14 or -14) - Vector(0, 0, 14))
            m:SetAngles(ang)
            m:DrawModel()
        end
    end
end)
