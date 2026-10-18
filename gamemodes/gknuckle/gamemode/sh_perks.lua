-- Perks: White Knuckle's upgrade cards, bought at the perk console in each
-- break room between regions (gk_perk_console). Like WK's interludes, each
-- visit offers three cards: the first two you take are free, the third costs
-- roaches. Perks last for the rest of the run (cleared when you die or the
-- run ends). Card art is WK's own (materials/gknuckle/perks).
--
-- Effects are multipliers on the fields GK.BuffMult already uses, plus a few
-- of their own: speed, jump, drain, regen (shared with buffs), climb, reach,
-- groundregen, griploss, damage, melee, bufftime, capacity; and a few flags
-- (extra air jumps, roaches love you, one-swing pitons).
AddCSLuaFile()

GK.Perks = {
    -- Tier 1 (WK T1)
    armored      = { tier = 1, card = "armored",      mult = { damage = 0.8, griploss = 0.5 } },
    latissimus   = { tier = 1, card = "latissimus",   mult = { climb = 1.2 } },
    regenpads    = { tier = 1, card = "regenpads",    mult = { groundregen = 1.5 } },
    painkillers  = { tier = 1, card = "painkillers",  mult = { drain = 0.8 } },
    steadied     = { tier = 1, card = "steadied",     mult = { damage = 0.85, griploss = 0.75 } },
    tissue       = { tier = 1, card = "tissue",       mult = { regen = 1.3 } },
    backstrength = { tier = 1, card = "backstrength", mult = { capacity = 1.25 } },
    -- Tier 2 (WK T2)
    pulse        = { tier = 2, card = "pulse",        airJumps = 1 },
    elastic      = { tier = 2, card = "elastic",      mult = { reach = 1.25 } },
    heavystrike  = { tier = 2, card = "heavystrike",  mult = { melee = 1.5 }, onePiton = true },
    ligament     = { tier = 2, card = "ligament",     mult = { jump = 1.2 } },
    metabolic    = { tier = 2, card = "metabolic",    mult = { bufftime = 1.5 } },
    pheromone    = { tier = 2, card = "pheromone",    roachLove = true },
    sysreorg     = { tier = 2, card = "sysreorg",     mult = { speed = 1.1, jump = 1.1, climb = 1.1, regen = 1.1 } },
    profit       = { tier = 2, card = "profit" },     -- faster the more roaches you carry
    velocity     = { tier = 1, card = "velocity",     mult = { speed = 1.25 } },          -- WK Velocity Augments: +25% walk
    rabbit       = { tier = 2, card = "rabbit",       mult = { jump = 1.35, drain = 1.15 } }, -- WK Rabbit DNA (unstable): big jumps, worse grip
}
GK.PerkPrice = 15 -- (kept for the card UI; WK's consoles give one free perk each)
-- WK's "Biological Backup" program, on every console in a run: buy one (from
-- the bank) and if you die later in the run, you come back at the next break
-- room your squad reaches, instead of being out. One per run.
GK.BackupPrice = 25
function GK.HasBackup(ply) return ply:GetNW2Bool("gk_backup", false) end

function GK.PerkList(ply)
    local s = ply:GetNW2String("gk_perks", "")
    return s == "" and {} or string.Explode(",", s)
end

function GK.HasPerk(ply, id)
    return IsValid(ply) and ("," .. ply:GetNW2String("gk_perks", "") .. ","):find("," .. id .. ",", 1, true) ~= nil
end

-- Product of a field over the player's perks.
function GK.PerkMult(ply, field)
    local s = IsValid(ply) and ply:GetNW2String("gk_perks", "") or ""
    if s == "" then return 1 end
    local m = 1
    for _, id in ipairs(string.Explode(",", s)) do
        local p = GK.Perks[id]
        if p and p.mult and p.mult[field] then m = m * p.mult[field] end
        if id == "profit" and field == "speed" then
            m = m * math.min(1.2, 1 + 0.004 * (GK.Roaches and GK.Roaches.Count(ply) or 0))
        end
    end
    return m
end

function GK.PerkAirJumps(ply)
    local n = 0
    for _, id in ipairs(GK.PerkList(ply)) do n = n + ((GK.Perks[id] or {}).airJumps or 0) end
    return n
end

if SERVER then
    util.AddNetworkString("gk_perk_offer")
    util.AddNetworkString("gk_perk_pick")

    function GK.GivePerk(ply, id)
        if not GK.Perks[id] or GK.HasPerk(ply, id) then return false end
        local list = GK.PerkList(ply)
        list[#list + 1] = id
        ply:SetNW2String("gk_perks", table.concat(list, ","))
        return true
    end

    -- A console offers you three cards you don't have yet, mixing tiers, and
    -- you take one (WK). The offer is fixed per console: walking off and
    -- coming back shows the same cards, and once you've taken one it's spent.
    function GK.OfferPerks(ply, console)
        ply.GK_PerkOffers = ply.GK_PerkOffers or {}
        local o = ply.GK_PerkOffers[console]
        if not o then
            local pool = {}
            for id in pairs(GK.Perks) do if not GK.HasPerk(ply, id) then pool[#pool + 1] = id end end
            local cards = {}
            for _ = 1, math.min(3, #pool) do cards[#cards + 1] = table.remove(pool, math.random(#pool)) end
            o = { console = console, cards = cards, taken = 0 }
            ply.GK_PerkOffers[console] = o
        end
        ply.GK_PerkOffer = o
        local iron = GK.RunMode and GK.RunMode(ply) == "iron"
        local backup = GK.ArenaOf(ply) ~= 0 and not GK.HasBackup(ply) and not iron
        local show = {}
        if o.taken < 1 and not iron then for _, id in ipairs(o.cards) do show[#show + 1] = id end end
        if backup then show[#show + 1] = "backup" end
        if o.taken < 1 and not iron and #o.cards > 0 then show[#show + 1] = "reroll" end -- WK: a fresh three, for 15
        show[#show + 1] = "logs" -- WK's text logs program, always there
        net.Start("gk_perk_offer")
        net.WriteUInt(#show, 3)
        for _, id in ipairs(show) do net.WriteString(id) end
        net.WriteUInt(o.taken, 3)
        net.WriteUInt(GK.PerkPrice, 8)
        net.Send(ply)
    end

    -- Taking a card from the current offer. Returns true if it was taken.
    function GK.PickPerk(ply, id)
        local o = ply.GK_PerkOffer
        if not o or not IsValid(o.console) or ply:GetPos():Distance(o.console:GetPos()) > 160 then return false end
        if id == "logs" then return false end -- read on the client
        if id == "reroll" then
            if o.taken >= 1 or (GK.RunMode and GK.RunMode(ply) == "iron") then return false end
            if not GK.Roaches.SpendBank(ply, GK.PerkPrice) then ply:EmitSound("GK.VendDeny") return false end
            local pool = {}
            for pid in pairs(GK.Perks) do if not GK.HasPerk(ply, pid) and not table.HasValue(o.cards, pid) then pool[#pool + 1] = pid end end
            local cards = {}
            for _ = 1, math.min(3, #pool) do cards[#cards + 1] = table.remove(pool, math.random(#pool)) end
            if #cards > 0 then o.cards = cards end
            ply:EmitSound("gknuckle/ui/computer_chime_new.wav", 70)
            GK.OfferPerks(ply, o.console)
            return true
        end
        if id == "backup" then
            if GK.ArenaOf(ply) == 0 or GK.HasBackup(ply) then return false end
            if not GK.Roaches.SpendBank(ply, GK.BackupPrice) then ply:EmitSound("GK.VendDeny") return false end
            ply:SetNW2Bool("gk_backup", true)
            ply:EmitSound("gknuckle/ui/comp_upgradeInjection.wav", 70)
            GK.OfferPerks(ply, o.console)
            return true
        end
        if GK.RunMode and GK.RunMode(ply) == "iron" then return false end -- Iron Knuckle: no perks
        if not table.HasValue(o.cards, id) then return false end
        if o.taken >= 1 then ply:EmitSound("GK.VendDeny") return false end -- one per console
        if not GK.GivePerk(ply, id) then return false end
        o.taken = o.taken + 1
        table.RemoveByValue(o.cards, id)
        ply:EmitSound("gknuckle/ui/comp_upgradeInjection.wav", 70)
        o.cards = {}
        GK.OfferPerks(ply, o.console) -- the backup card stays up if it's still to buy, else this closes the cards
        return true
    end
    net.Receive("gk_perk_pick", function(_, ply) GK.PickPerk(ply, net.ReadString()) end)

    -- Perks last the run: gone when you die or come back to the hub.
    hook.Add("PlayerSpawn", "GK_PerksReset", function(ply)
        ply:SetNW2String("gk_perks", "")
        ply.GK_PerkOffer = nil
        ply.GK_PerkOffers = nil
    end)

    -- Armour-type perks cut damage taken.
    hook.Add("EntityTakeDamage", "GK_PerkDamage", function(ent, d)
        if ent:IsPlayer() then
            local m = GK.PerkMult(ent, "damage")
            if m ~= 1 then d:ScaleDamage(m) end
        end
    end)
end

-- Extra midair jumps (Pulse Organ): jump again in the air.
hook.Add("SetupMove", "GK_PerkAirJump", function(ply, mv)
    if ply:OnGround() then ply.GK_AirJumpsUsed = 0 return end
    if not mv:KeyPressed(IN_JUMP) or ply:GetMoveType() ~= MOVETYPE_WALK then return end
    if (GK.OnLadder and GK.OnLadder(ply)) or ply:GetNW2Int("gk_hand_l", 0) == 1 or ply:GetNW2Int("gk_hand_r", 0) == 1 then return end
    if (ply.GK_AirJumpsUsed or 0) >= GK.PerkAirJumps(ply) then return end
    ply.GK_AirJumpsUsed = (ply.GK_AirJumpsUsed or 0) + 1
    local v = mv:GetVelocity()
    mv:SetVelocity(Vector(v.x, v.y, ply:GetJumpPower()))
    if SERVER then ply:EmitSound("player/suit_sprint.wav", 60, 140) end
end)

if CLIENT then
    local mats = {}
    local function mat(name)
        mats[name] = mats[name] or Material("gknuckle/perks/" .. name .. ".png", "noclamp")
        return mats[name]
    end
    local roachIcon = Material("gknuckle/perks/roach.png", "noclamp")

    -- WK's terminal logs (data_static/gknuckle/logs, from WK's own TextAssets),
    -- read on the console's orange CRT. Picked for where you are: Habitation's
    -- and the Nest's own first, the facility's anywhere.
    local logs
    local function loadLogs()
        if logs then return logs end
        logs = { hab = {}, nest = {}, any = {} }
        for _, f in ipairs(file.Find("data_static/gknuckle/logs/*.txt", "GAME")) do
            local key = f:find("^hab") and "hab" or (f:find("nest") and "nest") or "any"
            table.insert(logs[key], f)
        end
        return logs
    end
    local texts = {}
    local function logText(f)
        if texts[f] then return texts[f] end
        local t = file.Read("data_static/gknuckle/logs/" .. f, "GAME") or ""
        t = t:gsub("\r", "")
        -- WK fills these in at run time (door codes and the like): a code of our own.
        t = t:gsub("{flagData:[^}]*}", function() return ("%04d"):format(math.random(0, 9999)) end)
        texts[f] = t
        return t
    end
    surface.CreateFont("GK_CRT", { font = "Courier New", size = math.max(14, math.floor(ScrH() / 52)), weight = 700, antialias = true })
    surface.CreateFont("GK_CRTBold", { font = "Courier New", size = math.max(16, math.floor(ScrH() / 46)), weight = 900, antialias = true })
    function GK.OpenLogs()
        local L = loadLogs()
        local region = GetGlobal2String("gk_arena_region_" .. (GK.ArenaOf and GK.ArenaOf(LocalPlayer()) or 0), "")
        local list = {}
        local mine = region:find("Habitation") and L.hab or region:find("Nest") and L.nest or nil
        for _, f in ipairs(mine or {}) do list[#list + 1] = f end
        for _, f in ipairs(L.any) do list[#list + 1] = f end
        if not mine then for _, f in ipairs(L.hab) do list[#list + 1] = f end for _, f in ipairs(L.nest) do list[#list + 1] = f end end
        if #list == 0 then return end
        local i = 1
        local pw, ph = ScrH() * 0.95, ScrH() * 0.7
        local crt = vgui.Create("DPanel")
        crt:SetSize(pw, ph) crt:Center() crt:MakePopup()
        crt.OnKeyCodePressed = function(self, key)
            if key == KEY_E or key == KEY_ESCAPE then self:Remove()
            elseif key == KEY_D or key == KEY_RIGHT then i = i % #list + 1 surface.PlaySound("gknuckle/ui/computer_chime_new.wav")
            elseif key == KEY_A or key == KEY_LEFT then i = (i - 2) % #list + 1 surface.PlaySound("gknuckle/ui/computer_chime_new.wav") end
        end
        crt.Paint = function(self, w, h)
            surface.SetDrawColor(14, 8, 2, 250) surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(255, 150, 40, 120) surface.DrawOutlinedRect(6, 6, w - 12, h - 12, 2)
            local x, y = 28, 24
            local orange, dim = Color(255, 170, 60), Color(200, 120, 40)
            for line in (logText(list[i]) .. "\n"):gmatch("(.-)\n") do
                local bold = line:find("<b>") ~= nil
                line = line:gsub("<[^>]+>", "")
                -- wrap long lines to the screen
                local font = bold and "GK_CRTBold" or "GK_CRT"
                surface.SetFont(font)
                local words, cur = string.Explode(" ", line), ""
                for _, wd in ipairs(words) do
                    local try = cur == "" and wd or (cur .. " " .. wd)
                    if surface.GetTextSize(try) > w - 56 and cur ~= "" then
                        draw.SimpleText(cur, font, x, y, bold and orange or dim)
                        y = y + select(2, surface.GetTextSize("M")) + 2
                        cur = wd
                    else cur = try end
                end
                draw.SimpleText(cur, font, x, y, bold and orange or dim)
                y = y + select(2, surface.GetTextSize("M")) + 2
                if y > h - 40 then break end
            end
            -- page dots along the bottom (no words)
            local n = math.min(#list, 40)
            for k = 1, n do
                local on = (k == ((i - 1) % n) + 1)
                surface.SetDrawColor(255, 150, 40, on and 255 or 70)
                surface.DrawRect(w / 2 - n * 7 + (k - 1) * 14, h - 22, 8, 8)
            end
            -- scanlines
            surface.SetDrawColor(0, 0, 0, 60)
            for sy = 0, h, 4 do surface.DrawRect(0, sy, w, 1) end
        end
        surface.PlaySound("gknuckle/ui/computer_chime_new.wav")
        return crt, #list
    end

    local frame
    net.Receive("gk_perk_offer", function()
        local cards = {}
        for i = 1, net.ReadUInt(3) do cards[i] = net.ReadString() end
        local taken, price = net.ReadUInt(3), net.ReadUInt(8)
        if IsValid(frame) then frame:Remove() end
        if #cards == 0 then return end
        local h = ScrH() * 0.42
        local w = h * 0.5
        frame = vgui.Create("DPanel")
        frame:SetSize(#cards * (w + 24) + 24, h + 48)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(self, pw, ph)
            surface.SetDrawColor(10, 12, 16, 235)
            surface.DrawRect(0, 0, pw, ph)
        end
        frame.OnKeyCodePressed = function(self, key) if key == KEY_E or key == KEY_ESCAPE then self:Remove() end end
        for i, id in ipairs(cards) do
            local p = id == "backup" and { tier = 2, card = "backup", backup = true }
                or id == "logs" and { tier = 1, card = "logs", logs = true }
                or id == "reroll" and { tier = 1, card = "roach", backup = true, reroll = true } or GK.Perks[id]
            local b = vgui.Create("DButton", frame)
            b:SetText("")
            b:SetPos(24 + (i - 1) * (w + 24), 24)
            b:SetSize(w, h)
            local paid = p.backup
            local cost = p.reroll and GK.PerkPrice or (p.backup and GK.BackupPrice or price)
            b.Paint = function(self, bw, bh)
                local hov = self:IsHovered()
                surface.SetDrawColor(255, 255, 255, 255)
                surface.SetMaterial(mat(p.tier == 2 and "frame_advanced" or "frame_basic"))
                surface.DrawTexturedRect(0, 0, bw, bh)
                surface.SetMaterial(mat(p.card))
                local m = bw * 0.08
                surface.DrawTexturedRect(m, bh * 0.12, bw - m * 2, bh * 0.82)
                if hov then
                    surface.SetDrawColor(120, 255, 140, 60)
                    surface.DrawRect(0, 0, bw, bh)
                end
                if paid then
                    -- The price, as roaches (no text): one icon per 5.
                    surface.SetMaterial(roachIcon)
                    surface.SetDrawColor(255, 255, 255, 255)
                    for k = 1, math.ceil(cost / 5) do surface.DrawTexturedRect(4 + (k - 1) * 20, bh - 24, 18, 18) end
                end
            end
            b.DoClick = function()
                if p.logs then frame:Remove() GK.OpenLogs() return end
                surface.PlaySound("gknuckle/ui/comp_upgradeSelect" .. math.random(1, 2) .. ".wav")
                net.Start("gk_perk_pick") net.WriteString(id) net.SendToServer()
                frame:Remove()
            end
        end
    end)
end
