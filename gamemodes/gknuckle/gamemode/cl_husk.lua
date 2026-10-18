-- Husk world-model visuals (third person only; first-person hands are cl_hands.lua).
--  * GKHuskColor matproxy: the hypervisor band, grin and the V Corp clamp's Xenium-lit
--    nodes read their tint per entity from GK.PlayerVisuals (sh_states.lua). The Husk has no mesh hands:
--    its only hands are the holo sprites cl_hands.lua draws (drawWorldHand).
--  * Scrolling username across the visor via cam.Start3D2D on the eyes attachment.
GK.Husk = GK.Husk or {}

local white = Color(255, 255, 255)

-- Fallback when sh_states isn't loaded (model used outside the gamemode).
local function fallbackVisuals(ply)
    local hp = ply.Health and ply:Health() or 100
    local c = hp >= 100 and white or hp >= 70 and Color(70, 235, 90) or hp >= 50 and Color(250, 220, 60)
        or hp >= 20 and Color(255, 140, 30) or hp >= 1 and Color(220, 30, 30) or Color(255, 80, 200)
    return { visor = c }
end

-- One GK.PlayerVisuals call per player per frame, however many materials ask.
local cache = {}
function GK.Husk.Visuals(ply)
    local fr = FrameNumber()
    local e = cache[ply]
    if e and e.frame == fr then return e.v end
    if GK.Husk.Override and GK.Husk.Override[ply] then return GK.Husk.Override[ply] end
    local v = (GK.PlayerVisuals and IsValid(ply) and ply:IsPlayer()) and GK.PlayerVisuals(ply) or fallbackVisuals(ply)
    cache[ply] = { frame = fr, v = v }
    return v
end

-- Ragdolls (server GK.Ragdoll props and clientside death ragdolls) use their owner's colours.
local function ownerOf(ent)
    if ent:IsPlayer() then return ent end
    -- Husk gibs: client props carry their owner, server props network it
    if ent.GK_HuskOwnerExplicit ~= nil then return IsValid(ent.GK_HuskOwnerExplicit) and ent.GK_HuskOwnerExplicit or false end
    local net = ent:GetNW2Entity("gk_husk_owner")
    if IsValid(net) then return net end
    if ent.GK_HuskOwner ~= nil and (ent.GK_HuskOwnerTime or 0) > CurTime() then return ent.GK_HuskOwner end
    local owner = false
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetNW2Entity("gk_ragdoll") == ent or ply:GetRagdollEntity() == ent then owner = ply break end
    end
    ent.GK_HuskOwner, ent.GK_HuskOwnerTime = owner, CurTime() + 1
    return owner
end

local SLOT = { visor = "visor" }

matproxy.Add({
    name = "GKHuskColor",
    init = function(self, mat, values)
        self.ResultTo = values.resultvar or "$color2"
        self.Slot = SLOT[values.slot or "visor"] or "visor"
    end,
    bind = function(self, mat, ent)
        if not IsValid(ent) then return end
        local ply = ownerOf(ent)
        local v = ply and GK.Husk.Visuals(ply) or fallbackVisuals(ent)
        local c = v[self.Slot] or white
        mat:SetVector(self.ResultTo, Vector(c.r / 255, c.g / 255, c.b / 255))
    end,
})

-- Per-leg pants tint (husk_pants_l / _r / _hip): the entity's own colour first (gibs and
-- reattached legs carry theirs), then its owner's, else the default near-black.
matproxy.Add({
    name = "GKHuskPants",
    init = function(self, mat, values)
        self.ResultTo = values.resultvar or "$color2"
        self.Slot = values.slot or "hip"
    end,
    bind = function(self, mat, ent)
        if not IsValid(ent) then return end
        local v = GK.Husk.PantsOf(ent, self.Slot)
        if not v then
            local o = ownerOf(ent)
            v = o and GK.Husk.PantsOf(o, self.Slot)
        end
        mat:SetVector(self.ResultTo, v or GK.Husk.PantsDefault)
    end,
})

-- Xenium crystals on the model (husk_crystal material): owner's GK.Husk.CrystalColor,
-- so they go black on corpses (death ragdolls resolve to their dead owner).
matproxy.Add({
    name = "GKHuskCrystal",
    init = function(self, mat, values) self.ResultTo = values.resultvar or "$color2" end,
    bind = function(self, mat, ent)
        if not IsValid(ent) then return end
        local ply = ownerOf(ent)
        local c = ply and GK.Husk.CrystalColor and GK.Husk.CrystalColor(ply) or Color(0, 0, 0)
        mat:SetVector(self.ResultTo, Vector(c.r / 255, c.g / 255, c.b / 255))
    end,
})

-- Hologram mouth expressions ------------------------------------------------------
-- The mouth plate's material is a 4-frames-per-expression atlas
-- (materials/models/player/gknuckle/face/husk_face_mouth.vtf, tools\make_face.py).
-- The expression name comes from GK.PlayerVisuals(ply).expression (Gameplay owns
-- the mapping); unknown names fall back to neutral. Idle animation, the glitch
-- on switching and the talking mouth (voice chat) are handled here.
GK.Husk.Faces = { "neutral", "grin", "scream", "stunned", "pain", "taunt", "strain", "dead",
    "laugh", "cry", "love", "skull", "cat", "rage", "wink", "worried", "panicked", "determined", "talk", "shy" }
local FACE_INDEX = {}
for i, n in ipairs(GK.Husk.Faces) do FACE_INDEX[n] = i - 1 end
FACE_INDEX[":3"] = FACE_INDEX.cat
local FACE_FPS = { shy = 3, neutral = 1.2, dead = 3, cat = 2, love = 3, skull = 2, wink = 2, worried = 4 } -- default 7
local CAN_TALK = { shy = true, neutral = true, grin = true, taunt = true, laugh = true, cat = true, love = true, wink = true, determined = true, worried = true }

local faceState = setmetatable({}, { __mode = "k" })
function GK.Husk.FaceFrame(ply)
    local v = GK.Husk.Visuals(ply)
    local name = v.expression
    if not FACE_INDEX[name] then name = "neutral" end
    local st = faceState[ply]
    if not st then st = { name = name, since = 0 } faceState[ply] = st end
    local now = CurTime()
    if st.name ~= name then st.name, st.since = name, now end

    local idx, sub = FACE_INDEX[name], 0
    if CAN_TALK[name] and ply.IsSpeaking and ply:IsSpeaking() then
        idx = FACE_INDEX.talk
        sub = math.Clamp(math.floor(ply:VoiceVolume() * 9), 0, 3)
    else
        sub = math.floor((now + ply:EntIndex() * 0.37) * (FACE_FPS[name] or 7)) % 4
    end
    -- glitch for 0.22s after a switch: flickers brightness and briefly shows the old frame
    local glitch = now - st.since < 0.22
    local bright = glitch and (math.random() < 0.5 and 0.25 or 1.15) or (0.92 + 0.08 * math.sin(now * 9 + ply:EntIndex()))
    return idx * 4 + sub, bright
end

matproxy.Add({
    name = "GKHuskFace",
    init = function(self, mat, values)
        self.FrameVar = values.framevar or "$frame"
        self.ColorVar = values.colorvar
    end,
    bind = function(self, mat, ent)
        if not IsValid(ent) then return end
        local ply = ownerOf(ent)
        if not ply then mat:SetInt(self.FrameVar, 0) return end
        local frame, bright = GK.Husk.FaceFrame(ply)
        mat:SetInt(self.FrameVar, frame)
        if self.ColorVar then
            local c = mat:GetVector(self.ColorVar)
            if c then mat:SetVector(self.ColorVar, c * bright) end
        end
    end,
})

-- Visor username ----------------------------------------------------------------
surface.CreateFont("GKHuskVisor", { font = "Consolas", size = 64, weight = 900, antialias = true })
surface.CreateFont("GKHuskTag", { font = "Trebuchet MS", size = 72, weight = 800, antialias = true })

local SCALE = 0.022                       -- 64px font -> ~1.4u tall, fits the 2.3u band
local SPEED = 70                          -- px/s
local LIFT = 0.12                         -- text floats just off the band
local MAX_DIST = 600 * 600

-- Per-model visor strap: band front surface relative to the eyes attachment
-- (fwd, down) and the strap radius from its axis every 7.5 deg from -75..75
-- (positive = the Husk's left), measured from the compiled mesh so the glyphs
-- sit on the curved strap.
GK.Husk.Visor = GK.Husk.Visor or {}
GK.Husk.Visor["models/player/gknuckle/husk_v2.mdl"] = { fwd = 1.39, down = 1.08, profile = {
    3.91, 3.95, 4.01, 4.08, 4.15, 4.23, 4.30, 4.36, 4.46, 4.59, 4.66,
    4.62, 4.53, 4.40, 4.31, 4.23, 4.15, 4.08, 4.01, 3.95, 3.91 } }

local function buildStrap(def)
    local P = def.profile
    local st = { fwd = def.fwd, down = def.down, frontR = P[11] }
    function st.radius(d)
        local f = (math.Clamp(d, -75, 75) + 75) / 7.5 + 1
        local i = math.min(math.floor(f), #P - 1)
        return P[i] + (P[i + 1] - P[i]) * (f - i)
    end
    function st.point(d) local r = st.radius(d) return math.cos(math.rad(d)) * r, math.sin(math.rad(d)) * r end
    -- arc length (units) <-> angle, 1 degree steps, 0 at the front
    local ARC, s, px, py = {}, 0
    for d = -75, 75 do
        local x, y = st.point(d)
        if px then s = s + math.sqrt((x - px) ^ 2 + (y - py) ^ 2) end
        px, py = x, y
        ARC[#ARC + 1] = { d, s }
    end
    local s0 = ARC[76][2]
    for _, e in ipairs(ARC) do e[2] = e[2] - s0 end
    function st.arcToDeg(u)
        if u <= ARC[1][2] or u >= ARC[#ARC][2] then return end
        local lo, hi = 1, #ARC
        while hi - lo > 1 do
            local mid = math.floor((lo + hi) / 2)
            if ARC[mid][2] < u then lo = mid else hi = mid end
        end
        local a, b = ARC[lo], ARC[hi]
        return a[1] + (b[1] - a[1]) * (u - a[2]) / (b[2] - a[2])
    end
    st.halfPx = ARC[#ARC][2] / SCALE
    return st
end

local straps = {}
local function strapFor(ply)
    local mdl = string.lower(ply:GetModel() or "")
    local def = GK.Husk.Visor[mdl] or GK.Husk.Visor["models/player/gknuckle/husk_v2.mdl"]
    local st = straps[def]
    if not st then st = buildStrap(def) straps[def] = st end
    return st
end

local glyphCache = {}
local function glyphs(text)
    local g = glyphCache[text]
    if g then return g end
    surface.SetFont("GKHuskVisor")
    g = { total = 0 }
    for _, code in utf8.codes(text) do
        local ch = utf8.char(code)
        local w = surface.GetTextSize(ch)
        g[#g + 1] = { ch = ch, x = g.total + w / 2 }
        g.total = g.total + w
    end
    glyphCache[text] = g
    return g
end

function GK.Husk.VisorFrame(ply)
    local id = ply:LookupAttachment("eyes")
    if not id or id <= 0 then return end
    local att = ply:GetAttachment(id)
    if not att then return end
    local st = strapFor(ply)
    local ang = att.Ang
    return att.Pos + ang:Forward() * st.fwd - ang:Up() * st.down, ang, st
end

local function drawVisor(ply)
    local pos, ang, st = GK.Husk.VisorFrame(ply)
    if not pos then return end
    local c = GK.Husk.Visuals(ply).visor or white
    local fwd, left = ang:Forward(), -ang:Right()
    local axis = pos - fwd * st.frontR
    local core = Color(math.min(255, c.r + 90), math.min(255, c.g + 90), math.min(255, c.b + 90))
    local glow = Color(c.r, c.g, c.b)

    local g = glyphs(string.upper(ply:Nick()))
    local loop = g.total + 90
    local x0 = -st.halfPx - (CurTime() * SPEED + ply:EntIndex() * 37) % loop
    while x0 < st.halfPx do
        for _, gl in ipairs(g) do
            local d = st.arcToDeg((x0 + gl.x) * SCALE)
            if d then
                local fade = math.Clamp((75 - math.abs(d)) / 15, 0, 1)
                local cs, sn = math.cos(math.rad(d)), math.sin(math.rad(d))
                local gp = axis + (fwd * cs + left * sn) * (st.radius(d) + LIFT)
                local x1, y1 = st.point(d + 1)
                local x2, y2 = st.point(d - 1)
                local yaw = math.deg(math.atan2(-(x1 - x2), y1 - y2)) -- outward normal of the strap
                local a = Angle(ang.p, ang.y, ang.r)
                a:RotateAroundAxis(a:Up(), yaw + 90)
                a:RotateAroundAxis(a:Forward(), 90)
                cam.Start3D2D(gp, a, SCALE)
                    glow.a = 90 * fade; core.a = 255 * fade
                    draw.SimpleText(gl.ch, "GKHuskVisor", 2, 2, glow, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    draw.SimpleText(gl.ch, "GKHuskVisor", 0, 0, core, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end
        x0 = x0 + loop
    end
end

-- WEBFISHING-style name tag floating over the head (from the sheet), always facing the viewer.
local TAG_MAX = 600 * 600
local function drawTag(ply)
    local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
    local hp = bone and ply:GetBonePosition(bone)
    if not hp then return end
    local dist = hp:DistToSqr(EyePos())
    if dist > TAG_MAX then return end
    local pos = hp + Vector(0, 0, 9 + math.sin(CurTime() * 2 + ply:EntIndex()) * 0.4)
    local yaw = (EyePos() - pos):Angle().y
    local a = 255 * math.Clamp((TAG_MAX - dist) / (TAG_MAX * 0.25), 0, 1)
    cam.Start3D2D(pos, Angle(0, yaw + 90, 90), 0.05)
        draw.SimpleTextOutlined(ply:Nick(), "GKHuskTag", 0, 0, Color(255, 255, 255, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 4, Color(20, 20, 24, a * 0.8))
    cam.End3D2D()
end

-- Visor name + name tag are NOT drawn from PostPlayerDraw: halos, outlines and overlay
-- passes re-render players with depth testing off, which made the text show through
-- walls. PostPlayerDraw only marks who was really rendered this frame; the text is
-- drawn in the depth-tested translucent pass, with a line-of-sight trace and range cut.
local drawnFrame = setmetatable({}, { __mode = "k" })
hook.Add("PostPlayerDraw", "GK_HuskVisor", function(ply)
    drawnFrame[ply] = FrameNumber()
end)

local function visible(ply, eye)
    local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
    local head = bone and ply:GetBonePosition(bone)
    if not head then return false end
    if head:DistToSqr(eye) > MAX_DIST then return false end
    local tr = util.TraceLine({ start = eye, endpos = head, mask = MASK_VISIBLE, filter = { LocalPlayer(), ply } })
    return not tr.Hit
end

hook.Add("PostDrawTranslucentRenderables", "GK_HuskVisor", function(depth, skybox, skybox3d)
    if depth or skybox or skybox3d then return end
    local me = LocalPlayer()
    if not IsValid(me) or (GK.IsChipOnline and not GK.IsChipOnline(me)) then return end -- stun static
    local eye, frame = EyePos(), FrameNumber()
    for _, ply in ipairs(player.GetAll()) do
        if drawnFrame[ply] == frame and not ply:IsDormant() and GK.IsHusk(ply)
            and (ply ~= me or me:ShouldDrawLocalPlayer())
            and (ply:Alive() or (GK.IsDowned and GK.IsDowned(ply)))
            and not (GK.IsGored and GK.IsGored(ply)) and visible(ply, eye) then
            drawVisor(ply)
            drawTag(ply)
        end
    end
end)
