AddCSLuaFile()

-- White Knuckle's vending machine (the classic red VENDOR one): three item
-- slots across the front, each showing WK's vending icon and its price in
-- roaches. Like WK, each machine stocks three random items. Press a slot (E,
-- or click it with an empty mind-hand): your roaches go in at the inserter
-- (sv_shop.lua / sh_roaches.lua) and the real item drops out, with physics.
--
-- Model: models/gknuckle/wk/vendor_t1.mdl (origin bottom centre, front +X).
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Vending Machine"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.GKModel = "models/gknuckle/wk/vendor_t1.mdl" -- WK's classic red VENDOR machine (build thread)
ENT.GKYawOffset = 0    -- the model's front is its +X: it faces along the entity's forward
ENT.GKDepth = 31       -- origin to the back panel, for standing it against a wall

-- Model-space markers on vendor_t1 (from the build thread): three item slots
-- in a row across the front, the roach inserter, where bought items drop, and
-- the three-digit roach dial (top-left corner of its hundreds window, then a
-- step per digit). Machines built on this one (gk_vendor_big) swap the layout.
ENT.SlotRadius = 4.5 -- the roach hole: this close to Layout.inserter (model units)
-- On the hole, seen from the front (the hole is recessed, so depth is ignored).
function ENT:AtRoachSlot(lp)
    local ins = self.Layout and self.Layout.inserter
    if not ins then return false end
    return Vector(0, lp.y - ins.y, lp.z - ins.z):Length() < (self.SlotRadius or 4.5)
end
-- Measured off vendor_t1's mesh: the three red item windows on the panel at
-- x 30.6 (each 12.9 wide), the three counter drums at x 30.2, the recessed
-- VENDOR sign at x 25.2 and the roach hole under the gold roach.
ENT.Layout = {
    slots = { Vector(30.62, -15.75, 67.6), Vector(30.62, 0, 67.6), Vector(30.62, 15.75, 67.6) },
    slotSize = 13,
    win = { w = 12.4, h = 14 },  -- each window's glass (model units); price lights sit under it
    inserter = Vector(24.2, 16.5, 81.1),
    spawn = Vector(13.9 + 8, 0, 28.1),
    dial = { pos = Vector(30.25, -19.9, 91.2), step = 7.9, w = 6.7, h = 7 },
    sign = { pos = Vector(25.3, -23, 111.6), w = 46, h = 11.4 },
}
local MAX_SLOTS = 8
function ENT:SlotAt(lp)
    local L = self.Layout
    if lp.x < L.slots[1].x - 12 then return end -- not the front
    local w, h = L.win and L.win.w or L.slotSize, L.win and L.win.h or L.slotSize
    for i, c in ipairs(L.slots) do
        if math.abs(lp.y - c.y) <= w / 2 + 1 and math.abs(lp.z - c.z) <= h / 2 + 2 then return i end
    end
end

sound.Add({ name = "GK.VendAccept", channel = CHAN_STATIC, volume = 0.8, level = 70, sound = "gknuckle/vending/accept.wav" })
sound.Add({ name = "GK.VendDeny", channel = CHAN_STATIC, volume = 0.8, level = 70, sound = "gknuckle/vending/deny.wav" })
sound.Add({ name = "GK.VendFeed", channel = CHAN_STATIC, volume = 0.9, level = 75,
    sound = { "gknuckle/vending/feed1.wav", "gknuckle/vending/feed3.wav", "gknuckle/vending/feed4.wav" } })
sound.Add({ name = "GK.VendTick", channel = CHAN_STATIC, volume = 0.6, level = 65, sound = "gknuckle/vending/tick.wav" })

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "LitSlot")       -- slot last pressed (lights up)
    self:NetworkVar("Float", 0, "LitUntil")
    self:NetworkVar("Int", 1, "Stock1")        -- index into GK.ShopSlots
    self:NetworkVar("Int", 2, "Stock2")
    self:NetworkVar("Int", 3, "Stock3")
    for i = 4, MAX_SLOTS do self:NetworkVar("Int", i, "Stock" .. i) end
    -- A roach just went into the hole: everyone sees it crawl in, and the
    -- feeder's counter rolls once it's inside.
    self:NetworkVar("Float", 1, "FedAt")
    self:NetworkVar("Int", 9, "Sold") -- a bit per slot: sold out (WK sells each once)
    self:NetworkVar("Entity", 0, "FedBy")
end
ENT.FeedTime = 0.8 -- how long a roach takes to crawl into the hole

function ENT:StockSlot(i)
    return GK.ShopSlots[self["GetStock" .. i](self)]
end

function ENT:IsSold(i) return bit.band(self:GetSold(), bit.lshift(1, i - 1)) ~= 0 end

if SERVER then
    function ENT:Initialize()
        self:SetModel(self.GKModel)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:Restock()
    end

    -- Different random items in every slot, like a WK vendor.
    function ENT:Restock()
        local pool = {}
        for i = 1, #GK.ShopSlots do pool[i] = i end
        for i = 1, math.min(#self.Layout.slots, #pool) do
            self["SetStock" .. i](self, table.remove(pool, math.random(#pool)))
        end
        self:SetSold(0)
    end

    -- Press whatever slot `ply` is pointing at. Returns true if it hit one.
    function ENT:Press(ply, hitpos)
        -- The roach hole beside the counter: in the hub, feed it your roaches to bank them.
        local L = self.Layout
        local lp = self:WorldToLocal(hitpos)
        if self:AtRoachSlot(lp) then -- feed it: hub or run, roaches go into the machine
            local n = (GK.RunMode and GK.RunMode(ply) == "iron") and 0 or GK.Roaches.Bank(ply) -- Iron Knuckle: no bank
            if n > 0 then
                self:Fed(ply)
                ply:EmitSound("gknuckle/roach/pickup_cockroach1.wav", 60, 80)
            else
                self:EmitSound("GK.VendDeny")
            end
            return true
        end
        local i = self:SlotAt(lp)
        local slot = i and self:StockSlot(i)
        if not slot then return false end
        if (self.GK_Busy or 0) > CurTime() then return true end
        if self:IsSold(i) then self:EmitSound("GK.VendDeny") return true end
        self.GK_Busy = CurTime() + 1.2
        self:SetLitSlot(i)
        self:SetLitUntil(CurTime() + 1.2)
        self:EmitSound("GK.VendTick")
        GK.Economy.Refresh(ply)
        GK.Shop.Charge(ply, slot, function(ok)
            if not IsValid(self) then return end
            if not ok then
                self:EmitSound("GK.VendDeny")
                return
            end
            self:EmitSound("GK.VendAccept")
            self:SetSold(bit.bor(self:GetSold(), bit.lshift(1, i - 1)))
            timer.Simple(0.5, function()
                if not IsValid(self) then return end
                self:EmitSound("GK.VendFeed")
                self:Dispense(slot)
            end)
        end)
        return true
    end

    -- A roach held in a hand, put into the hole (WK): banked, at its worth.
    function ENT:FeedRoach(ply, worth)
        if GK.RunMode and GK.RunMode(ply) == "iron" then self:EmitSound("GK.VendDeny") return false end -- Iron Knuckle: no bank
        local room = GK.RoachCap - GK.Roaches.Banked(ply)
        if room <= 0 then self:EmitSound("GK.VendDeny") return false end
        local n = math.min(worth, room)
        ply:SetNW2Int("gk_bank", GK.Roaches.Banked(ply) + n)
        hook.Run("GK_RoachesBanked", ply, n)
        self:Fed(ply)
        ply:EmitSound("gknuckle/roach/pickup_cockroach" .. math.random(3) .. ".wav", 60, 80)
        return true
    end

    -- The roach crawls in (drawn client side), then the machine takes it.
    function ENT:Fed(ply)
        self:SetFedAt(CurTime())
        self:SetFedBy(ply)
        self:EmitSound("GK.VendFeed")
        timer.Simple(self.FeedTime, function()
            if IsValid(self) then self:EmitSound("GK.VendAccept") end
        end)
    end

    -- Pops an item out of the tray at WK's 5 m/s, out and down.
    function ENT:Dispense(slot)
        local ent = GK.Shop.SpawnItem(slot, self:LocalToWorld(self.Layout.spawn),
            self:LocalToWorldAngles(Angle(0, math.Rand(-30, 30), 0)))
        local phys = IsValid(ent) and ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:SetVelocity((self:LocalToWorld(Vector(1, 0, -0.3)) - self:GetPos()):GetNormalized() * 197)
            phys:AddAngleVelocity(VectorRand() * 200)
        end
        return ent
    end

    -- WK: blow a vending machine up and it coughs up two items for free
    -- (once; it takes a while to be worth robbing again).
    function ENT:OnTakeDamage(d)
        if not d:IsExplosionDamage() or (self.GK_RobbedUntil or 0) > CurTime() then return end
        self.GK_RobbedUntil = CurTime() + 60
        local fx = EffectData() fx:SetOrigin(self:LocalToWorld(self.Layout.spawn)) fx:SetMagnitude(3) fx:SetScale(2)
        util.Effect("Sparks", fx, true, true)
        self:EmitSound("GK.VendDeny")
        for n = 1, 2 do
            timer.Simple(0.2 * n, function()
                if not IsValid(self) then return end
                local slot = self:StockSlot(math.random(#self.Layout.slots))
                if slot then self:Dispense(slot) end
            end)
        end
    end

    function ENT:Use(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local tr = ply:GetEyeTrace()
        if tr.Entity == self then self:Press(ply, tr.HitPos) end
    end
end


if CLIENT then
    -- White Knuckle's machine, lit: the VENDOR sign glows, the three counter
    -- drums are backlit and roll as a roach crawls into the hole, and each red
    -- window shows the real item turning slowly behind the glass, with small
    -- yellow price lights under it (lit when you've banked enough).
    local SCALE = 0.1 -- 3D2D units per pixel: 10 px per model unit
    local FRONT = Vector(0, 1, 0):AngleEx(Vector(1, 0, 0)) -- x along model +Y, y down, facing out (+X)
    surface.CreateFont("GK_VendDial", { font = "Courier New", size = 60, weight = 900, antialias = false })

    local function additive(on)
        if on then render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
        else render.OverrideBlend(false) end
    end

    -- A flat rect on the machine's front, top-left at local `tl`.
    local function rect(self, tl, w, h, col, add)
        cam.Start3D2D(self:LocalToWorld(tl), self:LocalToWorldAngles(FRONT), SCALE)
            if add then additive(true) end
            surface.SetDrawColor(col)
            surface.DrawRect(0, 0, w / SCALE, h / SCALE)
            if add then additive(false) end
        cam.End3D2D()
    end

    local function winSize(L) return L.win and L.win.w or L.slotSize, L.win and L.win.h or L.slotSize end

    function ENT:OnRemove()
        for _, m in pairs(self.GK_Models or {}) do if IsValid(m.ent) then m.ent:Remove() end end
    end

    -- One hidden clientside model per key, sized so its longest side is `fit`.
    function ENT:ShowModel(key, path, fit)
        self.GK_Models = self.GK_Models or {}
        local m = self.GK_Models[key]
        if m and m.path == path and IsValid(m.ent) then return m end
        if m and IsValid(m.ent) then m.ent:Remove() end
        self.GK_Models[key] = nil
        if not path or not util.IsValidModel(path) then return end
        local e = ClientsideModel(path, RENDERGROUP_OPAQUE)
        if not IsValid(e) then return end
        e:SetNoDraw(true)
        local mn, mx = e:GetModelBounds()
        local size = mx - mn
        local s = fit / math.max(size.x, size.y, size.z, 1)
        e:SetModelScale(s)
        m = { path = path, ent = e, center = (mn + mx) * 0.5 * s }
        self.GK_Models[key] = m
        return m
    end

    -- Draw `m` centred on local point `lp`, at local angles `la`.
    function ENT:DrawShown(m, lp, la)
        local ang = self:LocalToWorldAngles(la)
        local off = Vector(m.center) off:Rotate(ang)
        m.ent:SetPos(self:LocalToWorld(lp) - off)
        m.ent:SetAngles(ang)
        m.ent:SetupBones()
        m.ent:DrawModel()
    end

    local function slotModel(slot)
        if slot.model then return slot.model end
        local def = slot.item and GK.ItemDef(slot.item)
        return def and def.model
    end

    function ENT:Think()
        -- The sign's warm light on the floor in front, and the windows' red.
        local L = self.Layout
        if not L.sign or EyePos():DistToSqr(self:GetPos()) > 1500 * 1500 then return end
        local fwd = self:GetForward()
        local d = DynamicLight(0x8000 + self:EntIndex() * 2)
        if d then
            d.pos = self:LocalToWorld(L.sign.pos + Vector(0, L.sign.w / 2, -L.sign.h / 2)) + fwd * 14
            d.r, d.g, d.b = 255, 222, 170
            d.brightness = 1.2
            d.size = 150
            d.decay = 0
            d.dietime = CurTime() + 0.2
        end
        local r = DynamicLight(0x8000 + self:EntIndex() * 2 + 1)
        if r then
            r.pos = self:LocalToWorld(L.slots[2] or L.slots[1]) + fwd * 10
            r.r, r.g, r.b = 255, 40, 25
            r.brightness = 0.7
            r.size = 90
            r.decay = 0
            r.dietime = CurTime() + 0.2
        end
    end

    function ENT:DrawSign(L)
        local S = L.sign
        if not S then return end
        local flick = 0.92 + 0.08 * math.sin(CurTime() * 23 + self:EntIndex()) * math.sin(CurTime() * 3.1)
        rect(self, S.pos + Vector(0.05, 0, 0), S.w, S.h, Color(255, 225, 170, 70 * flick), true)
        rect(self, S.pos + Vector(0.1, 1.5, -1.2), S.w - 3, S.h - 2.4, Color(255, 235, 200, 45 * flick), true)
    end

    -- The three counter drums: each digit rolls into the next like an
    -- odometer, backlit warm white. The shown count is your banked roaches.
    function ENT:DrawDial(L, me)
        local D = L.dial
        local target = math.min(GK.Roaches.Banked(me), GK.RoachCap)
        -- Your roach is still crawling in: hold the old count until it's inside.
        local hold = self:GetFedBy() == me and CurTime() < self:GetFedAt() + self.FeedTime
        local v = self.GK_DialV or target
        if v ~= target and not hold then
            local step = math.max(math.abs(target - v) * FrameTime() * 3, FrameTime() * 8)
            local nv = math.Approach(v, target, step)
            if math.floor(nv) ~= math.floor(v) and CurTime() > (self.GK_NextTick or 0) then
                self.GK_NextTick = CurTime() + 0.06
                self:EmitSound("GK.VendTick")
            end
            v = nv
        end
        self.GK_DialV = v
        local function cog(place) -- 0-10 position of the drum for 10^place
            local d = math.floor(v / 10 ^ place) % 10
            local below = (v / 10 ^ place) % 1 * 10 ^ place
            local carry = math.max(0, below - (10 ^ place - 1)) -- turns only as the one below rolls 9 -> 0
            return d + (place == 0 and v % 1 or carry)
        end
        local full = target >= GK.RoachCap
        local col = full and Color(200, 20, 20) or Color(28, 20, 14)
        local dw, dh = D.w / SCALE, D.h / SCALE
        local ang = self:LocalToWorldAngles(FRONT)
        for i = 1, 3 do
            local p = cog(3 - i)
            cam.Start3D2D(self:LocalToWorld(D.pos + Vector(0.05, (i - 1) * D.step, 0)), ang, SCALE)
                render.SetStencilEnable(true)
                render.ClearStencil()
                render.SetStencilWriteMask(255) render.SetStencilTestMask(255) render.SetStencilReferenceValue(1)
                render.SetStencilCompareFunction(STENCIL_ALWAYS)
                render.SetStencilPassOperation(STENCIL_REPLACE)
                render.SetStencilFailOperation(STENCIL_KEEP) render.SetStencilZFailOperation(STENCIL_KEEP)
                surface.SetDrawColor(255, 244, 218, 255) -- lit from behind
                surface.DrawRect(0, 0, dw, dh)
                render.SetStencilCompareFunction(STENCIL_EQUAL)
                render.SetStencilPassOperation(STENCIL_KEEP)
                local f = p % 1
                for k = -1, 1 do
                    local d = (math.floor(p) + k) % 10
                    draw.SimpleText(d, "GK_VendDial", dw / 2, dh / 2 + (k - f) * dh * 0.95, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                -- The drum's curve: darker toward its top and bottom edges.
                surface.SetDrawColor(60, 30, 0, 90) surface.DrawRect(0, 0, dw, dh * 0.14) surface.DrawRect(0, dh * 0.86, dw, dh * 0.14)
                surface.SetDrawColor(60, 30, 0, 35) surface.DrawRect(0, dh * 0.14, dw, dh * 0.12) surface.DrawRect(0, dh * 0.74, dw, dh * 0.12)
                render.SetStencilEnable(false)
                -- The backlight bleeding round the drum.
                additive(true)
                surface.SetDrawColor(255, 200, 120, 40)
                surface.DrawRect(-8, -8, dw + 16, dh + 16)
                additive(false)
            cam.End3D2D()
        end
    end

    -- Both windings, so a face shows whichever way it's seen from.
    local function quad(a, b, c, d, col)
        render.DrawQuad(a, b, c, d, col)
        render.DrawQuad(d, c, b, a, col)
    end

    -- The box an item sits in: back, sides, roof and floor, `depth` deep.
    function ENT:DrawBay(c, w, h, depth)
        local function P(x, y, z) return self:LocalToWorld(c + Vector(x, y, z)) end
        local y0, y1, z0, z1, x0, x1 = -w / 2, w / 2, -h / 2, h / 2, 0, -depth
        render.SetColorMaterial()
        quad(P(x1, y0, z1), P(x1, y1, z1), P(x1, y1, z0), P(x1, y0, z0), Color(34, 7, 5))  -- back
        quad(P(x0, y0, z1), P(x1, y0, z1), P(x1, y0, z0), P(x0, y0, z0), Color(52, 11, 8)) -- left
        quad(P(x1, y1, z1), P(x0, y1, z1), P(x0, y1, z0), P(x1, y1, z0), Color(52, 11, 8)) -- right
        quad(P(x0, y0, z1), P(x0, y1, z1), P(x1, y1, z1), P(x1, y0, z1), Color(18, 4, 3))  -- roof
        quad(P(x1, y0, z0), P(x1, y1, z0), P(x0, y1, z0), P(x0, y0, z0), Color(78, 17, 12)) -- floor
        -- The little lamp along the roof, just behind the glass.
        quad(P(-0.6, y0 + 0.4, z1 - 0.05), P(-0.6, y1 - 0.4, z1 - 0.05), P(-1.6, y1 - 0.4, z1 - 0.05), P(-1.6, y0 + 0.4, z1 - 0.05), Color(255, 120, 90))
    end

    -- Each window: a recess cut through the panel (stencil), the item turning
    -- inside it under red light, red glass over it, and the price lights below.
    function ENT:DrawWindows(L, me)
        local w, h = winSize(L)
        local lit = self:GetLitUntil() > CurTime() and self:GetLitSlot() or 0
        local bank = GK.Roaches.Banked(me)
        local ang = self:LocalToWorldAngles(FRONT)
        for i, c in ipairs(L.slots) do
            local slot = self:StockSlot(i)
            local sold = self:IsSold(i)
            if sold then slot = nil end -- sold out: an empty, dark window, no price lights
            local on = lit == i
            local tl = c + Vector(0.03, -w / 2, h / 2)
            render.SetStencilEnable(true)
            render.ClearStencil()
            render.SetStencilWriteMask(255) render.SetStencilTestMask(255) render.SetStencilReferenceValue(1)
            render.SetStencilCompareFunction(STENCIL_ALWAYS)
            render.SetStencilPassOperation(STENCIL_REPLACE)
            render.SetStencilFailOperation(STENCIL_KEEP) render.SetStencilZFailOperation(STENCIL_KEEP)
            render.OverrideColorWriteEnable(true, false)
            cam.Start3D2D(self:LocalToWorld(tl), ang, SCALE)
                surface.SetDrawColor(0, 0, 0, 255)
                surface.DrawRect(0, 0, w / SCALE, h / SCALE)
            cam.End3D2D()
            render.OverrideColorWriteEnable(false, false)
            render.SetStencilCompareFunction(STENCIL_EQUAL)
            render.SetStencilPassOperation(STENCIL_KEEP)
            render.ClearBuffersObeyStencil(12, 3, 2, 255, true)
            -- The bay behind the glass: a deep box, lit from its top front edge.
            self:DrawBay(c, w, h, L.bayDepth or 16)
            if slot then
                local m = self:ShowModel(i, slotModel(slot), math.min(w, h) * 0.95)
                if m then
                    render.SuppressEngineLighting(true)
                    -- Lit from above inside the bay, warm, with the red glass tinting it.
                    local k = on and 1.5 or 1
                    render.ResetModelLighting(0.45 * k, 0.3 * k, 0.26 * k)
                    render.SetModelLighting(BOX_TOP, 1.4 * k, 1.1 * k, 0.9 * k)
                    render.SetColorModulation(1, 0.9, 0.85)
                    self:DrawShown(m, c - Vector((L.bayDepth or 16) * 0.38, 0, -0.5), Angle(15, CurTime() * 35 + i * 120, 0))
                    render.SetColorModulation(1, 1, 1)
                    render.SuppressEngineLighting(false)
                end
            end
            -- Red glass: tinted, a little brighter when its item was just bought.
            rect(self, tl, w, h, Color(255, 25, 15, sold and 12 or (on and 70 or 38)), true)
            rect(self, tl + Vector(0.01, 0, 0), w, h * 0.12, Color(255, 120, 100, 30), true)
            render.SetStencilEnable(false)

            -- Price: small yellow lights in a row under the window, eight to a row.
            if slot then
                local n = tonumber(slot.price) or 0
                local ok = bank >= n
                local dot, gap = 0.8, 0.65
                cam.Start3D2D(self:LocalToWorld(c + Vector(0.05, -w / 2, -h / 2 - 1.2)), ang, SCALE)
                    for p = 0, n - 1 do
                        local row, col = math.floor(p / 8), p % 8
                        local inRow = math.min(8, n - row * 8)
                        local x0 = (w - (inRow * dot + (inRow - 1) * gap)) / 2
                        local x, y = (x0 + col * (dot + gap)) / SCALE, row * (dot + gap) / SCALE
                        local d = dot / SCALE
                        if ok then
                            surface.SetDrawColor(255, 220, 60, 255) surface.DrawRect(x, y, d, d)
                            additive(true)
                            surface.SetDrawColor(255, 200, 40, 60) surface.DrawRect(x - 3, y - 3, d + 6, d + 6)
                            additive(false)
                        else
                            surface.SetDrawColor(95, 72, 20, 255) surface.DrawRect(x, y, d, d)
                        end
                    end
                cam.End3D2D()
            end
        end
    end

    -- A roach crawling into the hole after it's fed in: everyone sees it.
    function ENT:DrawFeed(L)
        local fedAt = self:GetFedAt()
        local t = (CurTime() - fedAt) / self.FeedTime
        if fedAt <= 0 or t < 0 or t > 1 then return end
        local m = self:ShowModel("feed", "models/gknuckle/items/roach_gold.mdl", 5)
        if not m then return end
        local ease = t * t * (3 - 2 * t)
        local p = L.inserter + Vector(13 * (1 - ease), math.sin(t * 25) * 0.3, 0)
        -- Lit gold by the counter's glow, so it doesn't vanish against the dark hole.
        render.SuppressEngineLighting(true)
        render.ResetModelLighting(0.7, 0.6, 0.45)
        render.SetModelLighting(BOX_TOP, 1.3, 1.15, 0.9)
        self:DrawShown(m, p, Angle(0, 180 + math.sin(t * 30) * 12, 0))
        render.SuppressEngineLighting(false)
    end

    function ENT:Draw()
        self:DrawModel()
        local d2 = EyePos():DistToSqr(self:GetPos())
        if d2 > 1500 * 1500 then return end
        if self:WorldToLocal(EyePos()).x <= 0 then return end -- only from the front
        local L = self.Layout
        self:DrawSign(L)
        if d2 > 800 * 800 then return end
        local me = LocalPlayer()
        if not IsValid(me) then return end
        self:DrawWindows(L, me)
        self:DrawDial(L, me)
        self:DrawFeed(L)
    end
end
