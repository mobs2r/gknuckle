AddCSLuaFile()

-- A slot machine for the hub's gambling spots: a White Knuckle vending
-- machine whose dials spin White Knuckle symbols instead of numbers. Click it
-- (mind-hand or E) to pay and pull; three reels spin and stop one by one.
-- Paid and paid out in roaches.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Slot Machine"
ENT.Spawnable = true
ENT.Category = "gKnuckle"

-- Symbols (WK vending icons) and what three in a row pays, in roaches.
local SYMBOLS = {
    { icon = "rebar",     pay = 6 },
    { icon = "piton",     pay = 8 },
    { icon = "beans",     pay = 10 },
    { icon = "grub",      pay = 15 },
    { icon = "injector",  pay = 25 },
    { icon = "blinkeye",  pay = 50 },
}
local WEIGHTS = { 30, 25, 20, 12, 8, 5 } -- how often each lands
local COST = 2
local SPIN = 1.6 -- seconds; the reels stop 0.5 s apart after this

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Reel1")
    self:NetworkVar("Int", 1, "Reel2")
    self:NetworkVar("Int", 2, "Reel3")
    self:NetworkVar("Float", 0, "SpinAt")
end

if SERVER then
    local function roll()
        local total = 0
        for _, w in ipairs(WEIGHTS) do total = total + w end
        local r = math.random() * total
        for i, w in ipairs(WEIGHTS) do r = r - w if r <= 0 then return i end end
        return 1
    end

    function ENT:Initialize()
        local mdl = "models/gknuckle/wk/vendor_t1.mdl"
        self:SetModel(util.IsValidModel(mdl) and mdl or "models/props_interiors/VendingMachineSoda01a.mdl")
        self:PhysicsInit(SOLID_VPHYSICS)
        if not IsValid(self:GetPhysicsObject()) then self:PhysicsInitBox(self:OBBMins(), self:OBBMaxs()) end
        self:SetMoveType(MOVETYPE_NONE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:SetUseType(SIMPLE_USE)
        self:SetReel1(1) self:SetReel2(2) self:SetReel3(3)
    end

    function ENT:Press(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return true end
        if self:GetSpinAt() + SPIN + 1.2 > CurTime() then return true end -- still spinning
        -- Always paid in roaches (never free, even where vending is).
        if not GK.Roaches.SpendBank(ply, COST) then self:EmitSound("GK.VendDeny") return true end -- fed roaches only
        local a, b, c = roll(), roll(), roll()
        self:SetReel1(a) self:SetReel2(b) self:SetReel3(c)
        self:SetSpinAt(CurTime())
        self:EmitSound("buttons/lever" .. math.random(1, 3) .. ".wav", 70)
        timer.Simple(SPIN + 1.1, function()
            if not IsValid(self) or not IsValid(ply) then return end
            local win = 0
            if a == b and b == c then win = SYMBOLS[a].pay
            elseif a == b or b == c or a == c then win = 2 end -- a pair gets your coins back
            if win > 0 then
                -- Winnings go into the bank, the same roaches the machines take.
                ply:SetNW2Int("gk_bank", math.min(GK.RoachCap, GK.Roaches.Banked(ply) + win))
                self:EmitSound(win >= 10 and "gknuckle/ui/ascended.ogg" or "GK.VendAccept", 75)
                for _ = 1, math.min(win, 12) do
                    local fx = EffectData() fx:SetOrigin(self:GetPos() + self:GetForward() * 34 + Vector(0, 0, 30))
                    util.Effect("cball_bounce", fx, true, true)
                end
            else
                self:EmitSound("GK.VendDeny")
            end
        end)
        return true
    end

    function ENT:Use(ply) self:Press(ply) end
end

if CLIENT then
    local icons = {}
    local function icon(name)
        icons[name] = icons[name] or Material("gknuckle/vending/" .. name .. ".png", "noclamp")
        return icons[name]
    end
    local SCALE = 0.1

    function ENT:Draw()
        self:DrawModel()
        if EyePos():DistToSqr(self:GetPos()) > 700 * 700 then return end
        local ang = self:LocalToWorldAngles(Vector(0, 1, 0):AngleEx(Vector(1, 0, 0)))
        local t = CurTime() - self:GetSpinAt()
        local reels = { self:GetReel1(), self:GetReel2(), self:GetReel3() }
        -- Three reel windows where the vendor's three slots sit.
        local size = 13 / SCALE
        for i = 1, 3 do
            local y = (i - 2) * 16
            cam.Start3D2D(self:LocalToWorld(Vector(31.8, y - 6.5, 73.5)), ang, SCALE)
                surface.SetDrawColor(14, 12, 10, 250)
                surface.DrawRect(0, 0, size, size)
                local stop = SPIN + (i - 1) * 0.5
                local spinning = t >= 0 and t < stop
                -- While spinning, symbols blur past; then it lands on the result.
                local sym = spinning and (math.floor(t * 18 + i * 3) % #SYMBOLS + 1) or reels[i]
                local off = 0
                surface.SetDrawColor(255, 255, 255, spinning and 170 or 255)
                surface.SetMaterial(icon(SYMBOLS[sym].icon))
                local is = size * 0.7
                surface.DrawTexturedRect((size - is) / 2, (size - is) / 2 + off, is, is)
                -- Frame (the dial bezel).
                surface.SetDrawColor(spinning and 255 or 150, spinning and 170 or 80, 40, 255)
                surface.DrawOutlinedRect(0, 0, size, size, 4)
            cam.End3D2D()
        end
    end
end
