-- gKnuckle Husk player model: registration, armless exemption, default model.
-- Lore: Husks carry the Xenium brain virus (gravity-defying abilities). V Corp abducted
-- them, amputated their arms and clamped a hypervisor/monitor to their heads to track
-- the infected; the glowing hypervisor, grin and nodes are the Xenium glow.
-- The Husk has no arm or hand geometry; its only hands are the holo sprites
-- cl_hands.lua draws. GK.ScaleArmBones (which zeroes UpperArm and every child bone)
-- skips Husk models so the hand bones keep animating for anything that reads them.
AddCSLuaFile()
if CLIENT then include("cl_husk.lua") else AddCSLuaFile("cl_husk.lua") end
include("sh_husktest.lua") -- inert unless data/gknuckle/husktest.txt exists
AddCSLuaFile("sh_husk_gore.lua") AddCSLuaFile("sh_husk_anims.lua") AddCSLuaFile("cl_husk_fplegs.lua")

GK.Husk = GK.Husk or {}
-- The Husk built from the hand-drawn sheet (the 1.0 Husk, husk.mdl, was removed in 0.4.4).
-- ModelV2 stays as an alias for code written while both existed.
GK.Husk.Model = "models/player/gknuckle/husk_v2.mdl"
GK.Husk.ModelV2 = GK.Husk.Model

-- Models whose mesh is already armless (their hands are separate floating meshes).
GK.Husk.ArmlessModels = GK.Husk.ArmlessModels or {}
GK.Husk.ArmlessModels[GK.Husk.Model] = true

function GK.IsArmless(ent)
    return IsValid(ent) and GK.Husk.ArmlessModels[string.lower(ent:GetModel() or "")] == true
end

function GK.IsHusk(ent)
    return GK.IsArmless(ent)
end

player_manager.AddValidModel("gKnuckle Husk", GK.Husk.Model)
list.Set("PlayerOptionsModel", "gKnuckle Husk", GK.Husk.Model)

-- Xenium crystal colour, shared with Gameplay's crystal gore (GK.CrystalColor calls this):
-- black once the Husk is dead (or gored), otherwise the hand action colour from
-- GK.PlayerVisuals: that hand's colour when side is "l"/"r", else the average of both.
local BLACK = Color(0, 0, 0)
function GK.Husk.CrystalColor(ply, side)
    if not IsValid(ply) or not ply:IsPlayer() then return BLACK end
    if (GK.IsGored and GK.IsGored(ply)) or (not ply:Alive() and not (GK.IsDowned and GK.IsDowned(ply))) then return BLACK end
    local v = GK.PlayerVisuals and GK.PlayerVisuals(ply)
    if not v then return Color(255, 255, 255) end
    if side == "l" then return v.handL end
    if side == "r" then return v.handR end
    local a, b = v.handL or v.handR, v.handR or v.handL
    return Color((a.r + b.r) / 2, (a.g + b.g) / 2, (a.b + b.b) / 2)
end

-- Per-Husk crystal rash: bodygroups picked from a seed (SteamID64, or EntIndex for
-- bots), set on the server so every client agrees; skin 0 = flesh, 1 = bandaged.
local function seedOf(ply)
    local id = ply.SteamID64 and ply:SteamID64()
    return tonumber(util.CRC((id and id ~= "0" and id) or ("bot" .. ply:EntIndex()))) or ply:EntIndex()
end
function GK.Husk.ApplyCrystals(ent, seed)
    if not IsValid(ent) then return end
    local function pick(name, lo, hi)
        local id = ent:FindBodygroupByName(name)
        if id and id >= 0 then
            local n = ent:GetBodygroupCount(id)
            ent:SetBodygroup(id, math.min(n - 1, math.floor(util.SharedRandom("gk_husk_" .. name, lo, hi + 0.999, seed))))
        end
    end
    pick("crystal_l", 1, 3)
    pick("crystal_r", 1, 3)
    pick("crystal_chest", 0, 3)
end
-- Per-leg pants colour (Husk v2 materials husk_pants_l / _r / _hip, GKHuskPants proxy):
-- NW2 vectors gk_pants_l, gk_pants_r, gk_pants_hip (0..1 RGB). Unset = the old near-black.
-- Clientside entities (death ragdolls, client gibs) carry ent.GK_Pants[slot] instead.
GK.Husk.PantsSlots = { "l", "r", "hip" }
GK.Husk.PantsDefault = Vector(0.25, 0.25, 0.27)
local UNSET = Vector(-1, -1, -1)
function GK.Husk.PantsOf(ent, slot)
    if not IsValid(ent) then return GK.Husk.PantsDefault end
    local v = ent:GetNW2Vector("gk_pants_" .. slot, UNSET)
    if v.x >= 0 then return v end
    if ent.GK_Pants and ent.GK_Pants[slot] then return ent.GK_Pants[slot] end
    return nil
end
-- slot nil = all three
function GK.Husk.SetPants(ent, col, slot)
    if not IsValid(ent) then return end
    local v = isvector(col) and col or Vector(col.r / 255, col.g / 255, col.b / 255)
    for _, s in ipairs(slot and { slot } or GK.Husk.PantsSlots) do
        if SERVER then ent:SetNW2Vector("gk_pants_" .. s, v) end   -- client-only ents use GK_Pants
        ent.GK_Pants = ent.GK_Pants or {}
        ent.GK_Pants[s] = v
    end
end
-- Seeded random pants colour for a player (saturated, mid-bright so the tint reads on the grime)
function GK.Husk.PantsSeedColor(ply, seed)
    local hue = util.SharedRandom("gk_pants_h", 0, 360, seed)
    local sat = util.SharedRandom("gk_pants_s", 0.55, 0.9, seed)
    local val = util.SharedRandom("gk_pants_v", 0.45, 0.85, seed)
    local c = HSVToColor(hue, sat, val)
    return Vector(c.r / 255, c.g / 255, c.b / 255)
end

function GK.Husk.CopyLook(from, to)
    if not (IsValid(from) and IsValid(to)) then return end
    to:SetSkin(from:GetSkin())
    for _, s in ipairs(GK.Husk.PantsSlots) do
        local v = GK.Husk.PantsOf(from, s)
        if v then GK.Husk.SetPants(to, v, s) end
    end
    for _, bg in ipairs(from:GetBodyGroups() or {}) do to:SetBodygroup(bg.id, from:GetBodygroup(bg.id)) end
end

if SERVER then
    local cvSkin = CreateConVar("gk_husk_skin", "0", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
        "Husk v2 body skin: 0 flesh (default), 1 bandaged, -1 random per player")
    local function dress(ply)
        if not GK.IsHusk(ply) then return end
        local seed = seedOf(ply)
        GK.Husk.ApplyCrystals(ply, seed)
        -- pants: random per Husk; Gameplay can return a Vector/Color from the GK_HuskPants hook
        -- (team colours) to override. Reset to the owner's colour on every spawn (new legs).
        local col = hook.Run("GK_HuskPants", ply) or GK.Husk.PantsSeedColor(ply, seed + (ply.GK_PantsRoll or 0))
        GK.Husk.SetPants(ply, col)
        local skin = cvSkin:GetInt()
        if skin < 0 then skin = math.floor(util.SharedRandom("gk_husk_skin", 0, 1.999, seed)) end
        if ply:SkinCount() > skin then ply:SetSkin(skin) end
    end
    GK.Husk.Dress = dress
    hook.Add("PlayerSpawn", "GK_HuskCrystals", function(ply) timer.Simple(0, function() if IsValid(ply) then dress(ply) end end) end)
    hook.Add("PlayerSetModel", "GK_HuskCrystals", function(ply) timer.Simple(0, function() if IsValid(ply) then dress(ply) end end) end)
    -- knockdown ragdolls (GK.Ragdoll) wear the same crystals/skin as their player
    hook.Add("OnEntityCreated", "GK_HuskCrystals", function(ent)
        if ent:GetClass() ~= "prop_ragdoll" then return end
        timer.Simple(0, function()
            if not IsValid(ent) then return end
            for _, ply in ipairs(player.GetAll()) do
                if ply:GetNW2Entity("gk_ragdoll") == ent and GK.IsHusk(ply) then GK.Husk.CopyLook(ply, ent) end
            end
        end)
    end)
end

if CLIENT then
    -- death ragdolls too
    hook.Add("CreateClientsideRagdoll", "GK_HuskCrystals", function(owner, rag)
        if IsValid(owner) and owner:IsPlayer() and GK.IsHusk(owner) then GK.Husk.CopyLook(owner, rag) end
    end)
end

if SERVER then
    local ARM_BONES = { "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_R_UpperArm" }
    local ONE = Vector(1, 1, 1)

    -- Wrap GK.ScaleArmBones (sv_dismember loads after this file, and may be
    -- refreshed) so armless models keep, or get back, full-size arm bones.
    local function wrap()
        local cur = GK.ScaleArmBones
        if not cur or cur == GK.Husk.ScaleWrapper then return end
        GK.Husk.ScaleOriginal = cur
        GK.Husk.ScaleWrapper = function(ent)
            if GK.IsArmless(ent) then
                for _, name in ipairs(ARM_BONES) do
                    local bone = ent:LookupBone(name)
                    if bone and ent:GetManipulateBoneScale(bone) ~= ONE then ent:ManipulateBoneScale(bone, ONE) end
                end
                return
            end
            return GK.Husk.ScaleOriginal(ent)
        end
        GK.ScaleArmBones = GK.Husk.ScaleWrapper
    end
    hook.Add("Initialize", "GK_HuskWrapArms", wrap)
    timer.Create("GK_HuskWrapArms", 2, 0, wrap)
    wrap()

    -- Make the Husk the default model. gk_playermodel is created in
    -- sv_dismember with the old placeholder as its default; switch only that
    -- placeholder value, so an explicit admin choice is left alone.
    -- gk_playermodel's old defaults (the soldier_stripped placeholder and the removed 1.0
    -- Husk) move to the Husk; any other explicit admin choice is left alone.
    local OLD_DEFAULTS = { ["models/player/soldier_stripped.mdl"] = true, ["models/player/gknuckle/husk.mdl"] = true }
    hook.Add("Initialize", "GK_HuskDefaultModel", function()
        local cv = GetConVar("gk_playermodel")
        local cur = cv and string.lower(cv:GetString())
        if cur and OLD_DEFAULTS[cur] and util.IsValidModel(GK.Husk.Model) then
            RunConsoleCommand("gk_playermodel", GK.Husk.Model)
        end
    end)
end

include("sh_husk_gore.lua")   -- dismemberment bodygroups + v2 gibs
include("sh_husk_anims.lua")  -- armless third-person animation
if CLIENT then include("cl_husk_fplegs.lua") end  -- first-person legs
