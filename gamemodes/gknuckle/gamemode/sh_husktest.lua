-- Husk model screenshot test. Inert unless data/gknuckle/husktest.txt exists
-- (D:\MiscLibrary\gknuckle-tools\husk\tools\run_husktest.ps1 arms it).
-- Spawns a bot as the Husk, orbits the camera around it and saves PNGs to
-- data/gknuckle/husk_shots/, then prints "[GKHUSK] DONE".
AddCSLuaFile()
if not file.Exists("gknuckle/husktest.txt", "DATA") then return end

local C = {
    White = Color(255, 255, 255), Green = Color(70, 235, 90), Orange = Color(255, 140, 30),
    Blue = Color(60, 140, 255), Pink = Color(255, 80, 200), Red = Color(230, 40, 40),
}

if SERVER then
    hook.Add("InitPostEntity", "GK_HuskTest", function()
        timer.Simple(3, function() RunConsoleCommand("bot") end)
        -- bots can take a while to join on a cold start: retry for up to a minute
        timer.Create("GK_HuskTestSetup", 2, 30, function()
            local host, bot
            for _, p in ipairs(player.GetAll()) do if p:IsBot() then bot = p else host = host or p end end
            if not IsValid(bot) or not IsValid(host) or not bot:Alive() then print("[GKHUSK] waiting for bot/host") return end
            timer.Remove("GK_HuskTestSetup")
            -- husktest.txt may hold a model path to test (defaults to the v1 Husk)
            local want = string.Trim(string.Explode("|", file.Read("gknuckle/husktest.txt", "DATA") or "")[1] or "")
            bot:SetModel(want:find("%.mdl$") and want or GK.Husk.Model)
            if GK.ScaleArmBones then GK.ScaleArmBones(bot) end
            if GK.Husk.Dress then GK.Husk.Dress(bot) end
            local fwd = host:GetForward(); fwd.z = 0; fwd:Normalize()
            local tr = util.TraceLine({ start = host:GetPos() + Vector(0, 0, 40), endpos = host:GetPos() + Vector(0, 0, 40) + fwd * 140, filter = host })
            local pos = tr.HitPos - fwd * 20
            bot:SetPos(pos - Vector(0, 0, 40))
            bot:SetEyeAngles((-fwd):Angle())
            bot:SetMoveType(MOVETYPE_NONE)
            bot:StripWeapons()
            bot:Give("gk_mind") bot:SelectWeapon("gk_mind")
            SetGlobal2Entity("gk_husktest_bot", bot)
            local b = bot:LookupBone("ValveBiped.Bip01_L_UpperArm")
            print("[GKHUSK] bot", bot, bot:GetModel(), "upperarm scale", b and bot:GetManipulateBoneScale(b))
        end)
    end)
    -- hub sweep ("x_" filter): two more Husk bots scattered around the hall
    concommand.Add("gk_husktest_scatter", function(ply)
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        local vac = ents.FindByClass("gk_vacuum")[1]
        local c = IsValid(vac) and vac:GetPos() or vector_origin
        local i = 0
        for _, p in ipairs(player.GetAll()) do
            if p:IsBot() then
                i = i + 1
                local a = i * 2.1
                p:SetModel(GK.Husk.Model)
                p:SetPos(c + Vector(math.cos(a) * (700 + i * 350), math.sin(a) * (700 + i * 350), 8))
                p:SetHealth(({ 100, 80, 55, 30, 10 })[i] or 100)
                print("[GKHUSK] scatter", p, p:GetPos())
            end
        end
    end)
    concommand.Add("gk_husktest_func", function(ply)
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        local bot = GetGlobal2Entity("gk_husktest_bot")
        if not IsValid(bot) then print("[GKHUSK] FUNC no bot") return end
        bot:Give("weapon_pistol") bot:SelectWeapon("weapon_pistol")
        print("[GKHUSK] FUNC translate ACT_MP_RUN with pistol ->", hook.Run("TranslateActivity", bot, ACT_MP_RUN), "expect", ACT_HL2MP_RUN)
        print("[GKHUSK] FUNC anim event attack ->", hook.Run("DoAnimationEvent", bot, PLAYERANIMEVENT_ATTACK_PRIMARY, 0), "expect", ACT_INVALID)
        print("[GKHUSK] FUNC bot pants l/r/hip", GK.Husk.PantsOf(bot, "l"), GK.Husk.PantsOf(bot, "r"), GK.Husk.PantsOf(bot, "hip"))
        print("[GKHUSK] FUNC server valid head gib", util.IsValidModel("models/player/gknuckle/husk_v2_gib_head.mdl"))
        local hg = ents.Create("prop_physics") hg:SetModel("models/player/gknuckle/husk_v2_gib_head.mdl") hg:SetPos(bot:GetPos() + Vector(40, 0, 40)) hg:Spawn()
        print("[GKHUSK] FUNC head gib spawned", hg:GetModel(), "phys", IsValid(hg:GetPhysicsObject()), "mass", IsValid(hg:GetPhysicsObject()) and hg:GetPhysicsObject():GetMass())
        local ok, made = GK.Husk.OnLegsLost(bot)
        print("[GKHUSK] FUNC OnLegsLost", ok)
        for part, gib in pairs(made or {}) do
            local mn, mx = gib:OBBMins(), gib:OBBMaxs()
            local s = mx - mn
            local phys = gib:GetPhysicsObject()
            timer.Simple(1.5, function()
                if not IsValid(gib) then return end
                local c = gib:WorldSpaceCenter()
                local tr = util.TraceLine({ start = c + Vector(0, 0, 60), endpos = c - Vector(0, 0, 10) })
                print("[GKHUSK] FUNC gib", part, "group", gib:GetCollisionGroup(), "(WEAPON=" .. COLLISION_GROUP_WEAPON .. ")",
                    "obb", math.Round(s.x, 1), math.Round(s.y, 1), math.Round(s.z, 1), "mass", IsValid(phys) and phys:GetMass(),
                    "trace hits gib", tr.Entity == gib, "pants", GK.Husk.PantsOf(gib, part == "leg_l" and "l" or "r"))
            end)
        end
        bot:SetNW2Bool("gk_legless", true)
        -- ragdoll stability: knock the bot down, sample the physics 1 s and 5 s later
        timer.Simple(2, function()
            if not IsValid(bot) or not GK.Ragdoll then print("[GKHUSK] FUNC ragdoll: no GK.Ragdoll") return end
            GK.Ragdoll(bot, Vector(0, 0, 150) + Angle(0, bot:EyeAngles().y, 0):Forward() * 200, 12)
            local function sample(tag)
                local rag = bot:GetNW2Entity("gk_ragdoll")
                if not IsValid(rag) then print("[GKHUSK] FUNC ragdoll", tag, "none") return end
                local maxv, maxspread, bad = 0, 0, 0
                local root = rag:GetPhysicsObjectNum(0):GetPos()
                for i = 0, rag:GetPhysicsObjectCount() - 1 do
                    local p = rag:GetPhysicsObjectNum(i)
                    local v, pos = p:GetVelocity():Length(), p:GetPos()
                    if v ~= v or pos.x ~= pos.x then bad = bad + 1 end
                    maxv = math.max(maxv, v); maxspread = math.max(maxspread, pos:Distance(root))
                end
                print("[GKHUSK] FUNC ragdoll", tag, "solids", rag:GetPhysicsObjectCount(), "max speed", math.Round(maxv, 1), "max dist from pelvis", math.Round(maxspread, 1), "nan", bad)
            end
            timer.Simple(1, function() sample("t+1s") end)
            timer.Simple(5, function() sample("t+5s") end)
        end)
        timer.Simple(0.6, function()
            print("[GKHUSK] FUNC server bodygroup leg_l", bot:GetBodygroup(bot:FindBodygroupByName("leg_l")))
            SetGlobal2Int("gk_func_stage", 2)
        end)
    end)
    -- test-only state switches the client shot list drives
    concommand.Add("gk_husktest_state", function(ply, _, args)
        if IsValid(ply) and not ply:IsListenServerHost() then return end
        local bot = GetGlobal2Entity("gk_husktest_bot")
        if not IsValid(bot) then return end
        local what = args[1] or ""
        local grip = what == "grip" and 1 or 0
        for _, side in ipairs({ "l", "r" }) do
            bot:SetNW2Int("gk_hand_" .. side, grip)
            local yaw = Angle(0, bot:EyeAngles().y, 0)
            bot:SetNW2Vector("gk_grip_" .. side, bot:EyePos() + yaw:Forward() * 22 + yaw:Right() * (side == "r" and 11 or -11) + Vector(0, 0, 6))
        end
        if what == "skin" then bot:SetSkin(tonumber(args[2]) or 0) return end
        if what == "kill" then bot:Kill() return end
        if what == "ragdoll" and GK.Ragdoll then GK.Ragdoll(bot, Vector(0, 0, 60) + Angle(0, bot:EyeAngles().y, 0):Forward() * 120, 10) return end
        local e = GK.Emotes and GK.Emotes[args[2] or ""]
        bot:SetNW2String("gk_emote_id", e and e.id or "")
        bot:SetNW2Float("gk_emote_until", e and CurTime() + e.time or 0)
    end)
    return
end

GK.Husk = GK.Husk or {}

local SHOTS = {
    -- name, camera offset (bot-local: forward, right, up), look-at height, visor, handL, handR, hp
    { "front", Vector(95, 0, 40), 38, C.White, C.White, C.White },
    { "side", Vector(0, -95, 40), 38, C.White, C.White, C.White },
    { "back", Vector(-80, 25, 55), 50, C.Green, C.White, C.White },
    { "head_closeup", Vector(24, -9, 66), 64.5, C.Green, C.White, C.White },
    { "head_closeup_critical", Vector(24, 9, 66), 64.5, C.Red, C.White, C.White },
    { "hands_grip_menu", Vector(60, -6, 40), 36, C.Orange, C.Orange, C.Blue },
    { "hands_downed_emote", Vector(60, 6, 40), 36, C.Pink, C.Pink, C.Green },
}
-- the single (holo sprite) hand set in third person: idle, gripping, every emote
local WF, WS = Vector(70, 0, 58), Vector(8, -72, 58)
for _, s in ipairs({ { "w_idle_front", WF, "idle" }, { "w_idle_side", WS, "idle" }, { "w_grip_front", WF, "grip" }, { "w_grip_side", WS, "grip" } }) do
    SHOTS[#SHOTS + 1] = { s[1], s[2], 56, C.White, C.White, C.White, nil, nil, { s[3] } }
end
local WB = Vector(-70, 0, 58)
SHOTS[#SHOTS + 1] = { "w_idle_back", WB, 56, C.White, C.White, C.White, nil, nil, { "idle" } }
for _, id in ipairs(GK.EmoteOrder or {}) do
    SHOTS[#SHOTS + 1] = { "w_emote_" .. id, WF, 56, C.Green, C.Green, C.Green, nil, nil, { "emote", id } }
    SHOTS[#SHOTS + 1] = { "w_emote_" .. id .. "_back", WB, 56, C.Green, C.Green, C.Green, nil, nil, { "emote", id } }
end
SHOTS[#SHOTS + 1] = { "w_ragdoll", Vector(90, 40, 70), 10, C.White, C.White, C.White, nil, nil, { "ragdoll" } }
-- Xenium crystals (c_): seeded rash on both skins, grip tint, black on death
local CF, CS, CB = Vector(58, 0, 56), Vector(6, -58, 56), Vector(-55, 10, 56)
for _, s in ipairs({ { "c_front", CF, { "skin", "0" } }, { "c_side", CS, { "skin", "0" } }, { "c_back", CB, { "skin", "0" } },
        { "c_stump_closeup", Vector(22, 18, 60), { "skin", "0" } },
        { "c_skin1_front", CF, { "skin", "1" } }, { "c_grip_front", CF, { "grip" } } }) do
    SHOTS[#SHOTS + 1] = { s[1], s[2], 54, C.White, C.White, C.White, nil, nil, s[3] }
end
SHOTS[#SHOTS + 1] = { "c_dead", Vector(30, 45, 45), 4, C.White, C.White, C.White, nil, nil, { "kill" } }
-- one front close-up per Gameplay expression (7th field = GK.PlayerVisuals().expression)
local FACE_SHOTS = { { "neutral", C.White }, { "grin", C.Green }, { "scream", C.Orange }, { "stunned", Color(250, 220, 60) },
    { "pain", C.Red }, { "taunt", C.Green }, { "strain", C.Orange }, { "dead", C.Pink } }
-- third-person hand emotes (8th field = emote id)
for _, id in ipairs({ "middle", "sixseven", "shy", "vulcan", "wave", "thumbsup", "fingerguns", "rock", "clap", "fist" }) do
    SHOTS[#SHOTS + 1] = { "emote_" .. id, Vector(55, -30, 52), 52, C.Green, C.Green, C.Green, nil, id }
end
for _, f in ipairs(FACE_SHOTS) do
    SHOTS[#SHOTS + 1] = { "face_" .. f[1], Vector(26, 0, 64.5), 64, f[2], C.White, C.White, f[1] }
end

-- "model|prefix" in husktest.txt keeps only shots whose name starts with prefix
local FILTER = string.Trim(string.Explode("|", file.Read("gknuckle/husktest.txt", "DATA") or "")[2] or "")
if FILTER and FILTER ~= "" then
    local keep = {}
    for _, s in ipairs(SHOTS) do if s[1]:sub(1, #FILTER) == FILTER then keep[#keep + 1] = s end end
    SHOTS = keep
end
-- FUNCTEST ("func" filter): numeric checks only, no captures
if FILTER == "func" then
    SHOTS = {}
    timer.Simple(14, function() RunConsoleCommand("gk_husktest_func") end)
    timer.Create("GK_HuskFuncClient", 1, 40, function()
        local b = GetGlobal2Entity("gk_husktest_bot")
        if not IsValid(b) or not b.GK_FuncDone and GetGlobal2Int("gk_func_stage", 0) < 2 then return end
        if b.GK_FuncDone then return end
        b.GK_FuncDone = true
        -- lean check: read the head bone in PostPlayerDraw with no lean, then with a 20 deg lean
        local spine, head = b:LookupBone("ValveBiped.Bip01_Spine2"), b:LookupBone("ValveBiped.Bip01_Head1")
        local stage, p0 = 0
        hook.Add("PostPlayerDraw", "GK_HuskFuncLean", function(ply)
            if ply ~= b then return end
            stage = stage + 1
            if stage == 3 then p0 = ply:GetBonePosition(head) ply:ManipulateBoneAngles(spine, Angle(0, 20, 0), false) end
            if stage == 8 then
                local p1 = ply:GetBonePosition(head)
                ply:ManipulateBoneAngles(spine, Angle(0, 0, 0), false)
                local fwd = Angle(0, ply:GetRenderAngles().y, 0):Forward()
                print("[GKHUSK] FUNC lean: head moves", math.Round((p1 - p0):Dot(fwd), 2), "u forward,", math.Round(p1.z - p0.z, 2), "u up (expect +fwd, -up)")
                hook.Remove("PostPlayerDraw", "GK_HuskFuncLean")
            end
        end)
        hook.Remove("PrePlayerDraw", "GK_HuskLean")   -- keep the live lean from fighting the probe
        local me = LocalPlayer()
        print("[GKHUSK] FUNC local model", me:GetModel(), "isHusk", GK.IsHusk(me), "3p", me:ShouldDrawLocalPlayer())
        local errs = {}
        for _, f in ipairs(file.Find("materials/models/player/gknuckle/husk_v2/*.vmt", "GAME")) do
            local m = Material("models/player/gknuckle/husk_v2/" .. f:sub(1, -5))
            if m:IsError() or m:GetTexture("$basetexture"):IsError() then errs[#errs + 1] = f end
        end
        for _, f in ipairs(file.Find("materials/models/player/gknuckle/face/*.vtf", "GAME")) do end
        print("[GKHUSK] FUNC materials checked", #file.Find("materials/models/player/gknuckle/husk_v2/*.vmt", "GAME"), "errors", #errs, table.concat(errs, ","))
        for _, m in ipairs({ "husk_v2", "husk_v2_gib_leg_l", "husk_v2_gib_leg_r", "husk_v2_gib_head" }) do
            print("[GKHUSK] FUNC model", m, "valid", util.IsValidModel("models/player/gknuckle/" .. m .. ".mdl"))
        end
        timer.Simple(1, function()
            local L = GK.Husk.FPLegsEntity and GK.Husk.FPLegsEntity()
            if not IsValid(L) then
                print("[GKHUSK] FUNC fplegs: none", "cvar", (GetConVar("gk_husk_fplegs") and GetConVar("gk_husk_fplegs"):GetFloat()), "alive", me:Alive(), "veh", me:InVehicle(),
                    "viewent", GetViewEntity(), "legless", me:GetNW2Bool("gk_legless", false), "ragdolled", GK.IsRagdolled and GK.IsRagdolled(me),
                    "hooked", hook.GetTable().PostDrawOpaqueRenderables and hook.GetTable().PostDrawOpaqueRenderables.GK_HuskFPLegs ~= nil)
                return
            end
            local sb = L:LookupBone("ValveBiped.Bip01_Spine1")
            local i = me:LookupPoseParameter("move_x")
            print("[GKHUSK] FUNC fplegs model", L:GetModel(), "spine1 scale", L:GetManipulateBoneScale(sb), "seq", L:GetSequence(), "/", me:GetSequence(),
                "move_x", i >= 0 and math.Round(L:GetPoseParameter("move_x"), 3), "/", i >= 0 and math.Round(me:GetPoseParameter("move_x"), 3),
                "dist", math.Round(L:GetPos():Distance(me:GetPos()), 1))
        end)
        print("[GKHUSK] FUNC client bodygroups leg_l/leg_r/head", b:GetBodygroup(b:FindBodygroupByName("leg_l")), b:GetBodygroup(b:FindBodygroupByName("leg_r")), b:GetBodygroup(b:FindBodygroupByName("head")))
        for _, g in ipairs(ents.FindByClass("prop_physics")) do
            if string.find(g:GetModel() or "", "husk_v2_gib") then
                print("[GKHUSK] FUNC gib", g:GetModel(), "owner", g:GetNW2Entity("gk_husk_owner"), "crystal", tostring(GK.Husk.CrystalColor(g:GetNW2Entity("gk_husk_owner"))))
            end
        end
        timer.Simple(9, function() print("[GKHUSK] DONE") end)
    end)
end
local SWEEP
if FILTER == "x_" then
    SWEEP = {}
    for k = 0, 11 do
        local a = k / 12 * math.pi * 2
        local r = ({ 500, 1200, 2100 })[k % 3 + 1]
        SWEEP[#SWEEP + 1] = { "x_sweep_" .. k, a, r, (k % 2 == 0) and 80 or 260 }
    end
    SHOTS = {}
    for _, s in ipairs(SWEEP) do SHOTS[#SHOTS + 1] = { s[1], Vector(), 0, C.White, C.White, C.White, nil, nil, nil, s } end
    timer.Simple(8, function() RunConsoleCommand("bot") RunConsoleCommand("bot") end)
    timer.Simple(12, function() RunConsoleCommand("gk_husktest_scatter") end)
end
local idx, nextAt, capture, phase = 0, nil, nil, "set"
RunConsoleCommand("mat_motion_blur_enabled", "0")
local function bot() return GetGlobal2Entity("gk_husktest_bot") end

hook.Add("HUDShouldDraw", "GK_HuskTest", function(name) if IsValid(bot()) then return false end end)
hook.Add("ShouldDrawLocalPlayer", "GK_HuskTest", function() return false end)

hook.Add("CalcView", "GK_HuskTest", function(ply, origin, angles, fov)
    local b = bot()
    local s = SHOTS[math.max(idx, 1)]
    if not IsValid(b) or not s then return end
    if s[10] then
        local vac = ents.FindByClass("gk_vacuum")[1]
        local c = IsValid(vac) and vac:GetPos() or b:GetPos()
        local a, r, z = s[10][2], s[10][3], s[10][4]
        local cp = c + Vector(math.cos(a) * r, math.sin(a) * r, z)
        local look = c + Vector(math.cos(a + 1.2) * r * 0.6, math.sin(a + 1.2) * r * 0.6, 60)
        return { origin = cp, angles = (look - cp):Angle(), fov = 90, drawviewer = false }
    end
    if s[1] == "c_dead" then   -- frame the death ragdoll's chest
        local rag = b:GetRagdollEntity()
        local bone = IsValid(rag) and rag:LookupBone("ValveBiped.Bip01_Spine4")
        local p = bone and rag:GetBonePosition(bone)
        if p then
            local cp = p + Vector(22, 18, 26)
            return { origin = cp, angles = (p - cp):Angle(), fov = 60, drawviewer = false }
        end
    end
    local yaw = Angle(0, b:GetRenderAngles().y, 0)
    local base = b:GetPos()
    local camPos = base + yaw:Forward() * s[2].x + yaw:Right() * s[2].y + Vector(0, 0, s[2].z)
    local target = base + Vector(0, 0, s[3])
    return { origin = camPos, angles = (target - camPos):Angle(), fov = ((s[1]:find("closeup") or s[1]:find("^face_")) and 40 or 60), drawviewer = false }
end)

hook.Add("Think", "GK_HuskTest", function()
    if FILTER == "func" then return end
    local b = bot()
    if not IsValid(b) then return end
    if not nextAt then nextAt = CurTime() + (FILTER == "x_" and 16 or 3) return end
    if CurTime() < nextAt or capture then return end
    if phase == "shoot" then capture = SHOTS[idx][1]; phase = "set"; nextAt = CurTime() + 0.3 return end
    idx = idx + 1
    local s = SHOTS[idx]
    if not s then
        print("[GKHUSK] DONE")
        hook.Remove("Think", "GK_HuskTest")
        return
    end
    GK.Husk.Override = GK.Husk.Override or {}
    GK.Husk.Override[b] = { visor = s[4], handL = s[5], handR = s[6], gripL = s[5] == C.Orange and 1 or 0, gripR = 0, expression = s[7] or (s[8] and GK.Emotes and GK.Emotes[s[8]] and GK.Emotes[s[8]].expression) or "neutral",
        emote = s[8], emoteStart = CurTime() - 0.6 }
    if s[9] then
        local args = s[9]
        if args[1] == "emote" then
            RunConsoleCommand("gk_husktest_state", "idle")
            timer.Simple(1.3, function() RunConsoleCommand("gk_husktest_state", "idle", args[2]) end)
        else
            RunConsoleCommand("gk_husktest_state", unpack(args))
        end
        GK.Husk.Override[b] = nil -- world hands read the real NW2 state
    end
    phase = "shoot"
    nextAt = CurTime() + ((s[9] and s[9][1] == "kill") and 1.5 or 2.5)   -- catch the corpse before a bot respawns
end)

hook.Add("PostRender", "GK_HuskTest", function()
    if not capture then return end
    local data = render.Capture({ format = "png", x = 0, y = 0, w = ScrW(), h = ScrH(), alpha = false })
    file.CreateDir("gknuckle/husk_shots")
    file.Write("gknuckle/husk_shots/" .. capture .. ".png", data)
    print("[GKHUSK] shot", capture, data and #data)
    capture = nil
end)
