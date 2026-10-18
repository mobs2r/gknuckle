-- Mind-hands rendering: hologram projections of the Xenium virus.
-- Frames are White Knuckle's climber-outline line art with a faint scanlined
-- fill (tools/bake_holo.ps1), drawn additively, tinted live with GK.HandColor
-- (health / action state, see sh_states.lua), with flicker, glow and a little
-- coloured light thrown on the world. The sprites are left hands; the right
-- hand is the same frame mirrored.

local FRAMES = {
    idle = "hnd_b1a1",
    reach = "hnd_b1b4",
    grip = "hnd_b3b3",
    hold = "hnd_b2c4",
    down = "hnd_b3d1",
}

local mats = {}
local function handMat(frame)
    if not mats[frame] then
        local png = Material("gknuckle/hands/holo/" .. frame .. ".png", "noclamp")
        mats[frame] = CreateMaterial("gk_holo_" .. frame, "UnlitGeneric", {
            ["$basetexture"] = png:GetTexture("$basetexture"):GetName(),
            ["$additive"] = 1,
            ["$vertexcolor"] = 1,
            ["$vertexalpha"] = 1,
            ["$nocull"] = 1,
        })
    end
    return mats[frame]
end

-- Projection flicker: a steady shimmer plus the odd dropout.
local function holoAlpha(ply, base)
    local t = CurTime() + ply:EntIndex() * 1.7
    local a = base * (0.82 + 0.18 * math.sin(t * 37) * math.sin(t * 5.3))
    if math.sin(t * 2.1) > 0.985 then a = a * 0.35 end
    return a
end

-- Draws one hand quad plus a soft oversized glow pass behind it.
local function drawHolo(mat, x, y, size, col, alpha, mirror)
    surface.SetMaterial(mat)
    local g = size * 0.08
    surface.SetDrawColor(col.r, col.g, col.b, alpha * 0.25)
    if mirror then
        surface.DrawTexturedRectUV(x - g, y - g, size + g * 2, size + g * 2, 1, 0, 0, 1)
        surface.SetDrawColor(col.r, col.g, col.b, alpha)
        surface.DrawTexturedRectUV(x, y, size, size, 1, 0, 0, 1)
    else
        surface.DrawTexturedRect(x - g, y - g, size + g * 2, size + g * 2)
        surface.SetDrawColor(col.r, col.g, col.b, alpha)
        surface.DrawTexturedRect(x, y, size, size)
    end
end

local function frameFor(ply, side, button)
    if GK.IsDowned(ply) then return FRAMES.down end
    local state = ply:GetNW2Int("gk_hand_" .. side, 0)
    if state == 1 then return FRAMES.grip end -- includes pulling on a rebar through your back
    if GK.IsImpaled(ply) then return FRAMES.down end
    if state == 2 then return FRAMES.hold end
    if ply:GetNW2String("gk_hitem_" .. side, "") ~= "" then return FRAMES.hold end -- holding an item
    if GK.HasFist and GK.HasFist(ply, side) then
        -- A raised fist (sh_melee.lua) stays closed, winding up and punching too
        -- (drawHand moves it).
        return FRAMES.grip
    end
    if button and ply:KeyDown(button) then return FRAMES.reach end
    return FRAMES.idle
end

local function showsHands(ply)
    local wep = ply:GetActiveWeapon()
    return (IsValid(wep) and wep.GKMindHands) or GK.IsDowned(ply) or GK.IsImpaled(ply)
end

local function isBusy(ply) return ply:GetNW2Float("gk_busy_until", 0) > CurTime() end

-- Both hands always draw; a hand holding an item shows the holding pose with
-- the item floating in it (cl_inventory.lua).
local function drawsHand(ply, side) return true end

-- Held items, White Knuckle style: the item's own sprite sits between the
-- hand frame and a fingers frame drawn over it, from WK's Item_Hands_<X>
-- prefabs (gameplay_tools/wk_held_sprites.js -> data_static/gknuckle/held.json).
-- Items WK doesn't have (the HL2 ones) float their 3D model in the palm instead
-- (cl_inventory.lua, drawn after the hands so it isn't hidden behind them).
local HELD = util.JSONToTable(file.Read("data_static/gknuckle/held.json", "GAME") or "") or {}

-- Items WK has no hand sprite for (the HL2 crowbar, battery, health vial...):
-- their model is rendered once into a small transparent texture and held like
-- any WK item, in a WK grip pose (the hammer's), so every item reads the same.
-- Guns (hold.centre) keep their 3D model out in front (cl_inventory.lua).
local synth = {}
local RT_SIZE = 256
local function spriteFromModel(class, def)
    local rt = GetRenderTargetEx("gk_heldrt_" .. class, RT_SIZE, RT_SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_SEPARATE,
        bit.bor(2, 256), 0, IMAGE_FORMAT_RGBA8888)
    local ent = ClientsideModel(def.model, RENDERGROUP_OPAQUE)
    if not IsValid(ent) then return nil end
    ent:SetNoDraw(true)
    local mins, maxs = ent:GetModelBounds()
    local c, r = (mins + maxs) * 0.5, (maxs - mins):Length() * 0.5
    -- Long side diagonal across the sprite, seen from the side.
    local sz = maxs - mins
    local ang = Angle(0, sz.y > sz.x and 90 or 0, 0) -- long side across the view, not towards it
    if sz.z < math.max(sz.x, sz.y) then ang:RotateAroundAxis(Vector(0, 1, 0), 45) end
    ent:SetAngles(ang)
    ent:SetPos(-LocalToWorld(c, angle_zero, vector_origin, ang))
    ent:SetupBones() -- boned models (the crowbar) otherwise draw where they were made
    render.PushRenderTarget(rt)
    render.OverrideAlphaWriteEnable(true, true)
    render.Clear(0, 0, 0, 0, true, true)
    cam.Start3D(Vector(0, -r * 2.6, 0), Angle(0, 90, 0), 45, 0, 0, RT_SIZE, RT_SIZE)
        render.SuppressEngineLighting(true)
        render.ResetModelLighting(0.75, 0.75, 0.75)
        render.SetModelLighting(BOX_TOP, 1, 1, 1)
        render.SetModelLighting(BOX_FRONT, 0.9, 0.9, 0.9)
        render.SetWriteDepthToDestAlpha(false) -- otherwise models leave alpha 0 (see-through)
        ent:DrawModel()
        render.SetWriteDepthToDestAlpha(true)
        render.SuppressEngineLighting(false)
    cam.End3D()
    render.OverrideAlphaWriteEnable(false)
    render.PopRenderTarget()
    ent:Remove()
    return r, CreateMaterial("gk_heldrt_" .. class, "UnlitGeneric", {
        ["$basetexture"] = rt:GetName(), ["$translucent"] = "1", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1",
    })
end
-- The rendered sprite of any item with a model (also the inventory icon of
-- items WK has no sprite for, guns included): material and model radius.
local modelSprites = {}
function GK.ModelSprite(class)
    if modelSprites[class] == nil then
        modelSprites[class] = false
        local def = GK.ItemDef(class)
        if def and def.model then
            local r, mat = spriteFromModel(class, def)
            if mat then modelSprites[class] = { mat = mat, r = r } end
        end
    end
    return modelSprites[class] or nil
end
local function synthLayout(class)
    if synth[class] ~= nil then return synth[class] or nil end
    synth[class] = false
    local def = GK.ItemDef(class)
    local base = HELD.hammer
    if not def or not def.model or (def.hold and def.hold.centre) or not base then return nil end
    local ms = GK.ModelSprite(class)
    if not ms then return nil end
    local r, mat = ms.r, ms.mat
    local size = math.Clamp(0.3 + r * 0.045, 0.55, 1.35)
    local lay = table.Copy(base)
    for _, l in ipairs(lay.layers) do
        if l.kind == "item" then l.png = nil l.mat = mat l.x, l.y, l.w, l.h, l.rot = 0.32 - size / 2, 0.75 - size / 2, size, size, 0 end -- across the hammer grip
    end
    synth[class] = lay
    return lay
end
function GK.HeldLayout(class)
    if not class then return nil end
    return HELD[class] or synthLayout(class)
end

-- The held item's class (and, for your own hands, its data: a gun's clip).
local function heldClass(ply, side)
    if ply == LocalPlayer() and GK.ClientInv and GK.ClientInv.slots then
        local it = GK.ClientInv.slots["hand_" .. side]
        if it then return it.class, it.data end
    end
    local c = ply:GetNW2String("gk_hitem_" .. side, "")
    return c ~= "" and c or nil
end

local itemMats = {}
local GLOW_MAT = Material("sprites/light_glow02_add")
local function itemMat(png)
    if type(png) ~= "string" then return png end -- already a material (a rendered sprite)
    if not itemMats[png] then itemMats[png] = Material(png, "noclamp") end
    return itemMats[png]
end

-- A textured quad centred on (cx, cy), rotated (degrees, counter-clockwise)
-- and optionally flipped left-right.
local function quad(mat, cx, cy, w, h, rot, flip)
    surface.SetMaterial(mat)
    local r = math.rad(-rot)
    local c, s = math.cos(r), math.sin(r)
    local u0, u1 = flip and 1 or 0, flip and 0 or 1
    local function pt(dx, dy, u, v) return { x = cx + dx * c - dy * s, y = cy + dx * s + dy * c, u = u, v = v } end
    surface.DrawPoly({ pt(-w / 2, -h / 2, u0, 0), pt(w / 2, -h / 2, u1, 0), pt(w / 2, h / 2, u1, 1), pt(-w / 2, h / 2, u0, 1) })
end

-- Draws a held-item layout in the hand's box (x, y, size): hand, item, fingers.
local function drawHeld(layout, x, y, size, mirror, col, alpha, data)
    local handL
    for _, l in ipairs(layout.layers) do if l.kind == "hand" then handL = l break end end
    local swap = mirror ~= (handL and handL.flip or false) -- our hand faces the other way to WK's
    local hx, hy = x + size / 2, y + size / 2
    for _, l in ipairs(layout.layers) do
        local lx = swap and -l.x or l.x
        local cx, cy = hx + lx * size, hy - l.y * size
        local w, h = l.w * size, l.h * size
        if l.kind == "loaded" then
            -- Something showing it's loaded (the flare in the flare gun's barrel).
            if not data or (data.clip or 1) > 0 then
                surface.SetDrawColor(255, 255, 255, math.min(255, alpha * 1.1))
                quad(itemMat(l.png), cx, cy, w, h, swap and -l.rot or l.rot, l.flip ~= swap)
            end
        elseif l.kind == "item" then
            local t = l.tint -- e.g. the xenium roach is WK's gold one, glowing orange
            local rot = swap and -l.rot or l.rot
            -- A live roach wriggles in your palm (WK's held roach is animated).
            if l.wiggle then rot = rot + math.sin(CurTime() * 14) * l.wiggle + math.sin(CurTime() * 23) * l.wiggle * 0.3 end
            if l.glow and t then
                -- A soft bloom behind it (the xenium roach).
                local pulse = 0.85 + math.sin(CurTime() * 3) * 0.15
                surface.SetMaterial(GLOW_MAT)
                surface.SetDrawColor(t[1], t[2], t[3], 70 * pulse * alpha / 255)
                surface.DrawTexturedRect(cx - w * 0.8, cy - h * 0.8, w * 1.6, h * 1.6)
            end
            if l.outline then
                -- A soft glow hugging the outline: the sprite again, a touch
                -- bigger and additive in the glow colour, behind it.
                local o = l.outline
                render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
                surface.SetDrawColor(o[1], o[2], o[3], 120 * alpha / 255)
                quad(itemMat(l.mat or l.png), cx, cy, w * 1.1, h * 1.1, rot, l.flip ~= swap)
                surface.SetDrawColor(o[1], o[2], o[3], 60 * alpha / 255)
                quad(itemMat(l.mat or l.png), cx, cy, w * 1.2, h * 1.2, rot, l.flip ~= swap)
                render.OverrideBlend(false)
            end
            surface.SetDrawColor(t and t[1] or 255, t and t[2] or 255, t and t[3] or 255, math.min(255, alpha * 1.1))
            quad(itemMat(l.mat or l.png), cx, cy, w, h, rot, l.flip ~= swap)
            if l.shimmer then
                -- WK's roach shimmer: a bright gleam passing over the shell about once a second.
                local g = math.max(0, 1 - math.abs((CurTime() * 0.9) % 1 - 0.5) / 0.12)
                if g > 0 then
                    render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
                    surface.SetDrawColor(255, 245, 210, 160 * g)
                    quad(itemMat(l.mat or l.png), cx, cy, w, h, rot, l.flip ~= swap)
                    render.OverrideBlend(false)
                    -- WK's glimmer: a star glint running across the shell with the gleam.
                    local p = ((CurTime() * 0.9) % 1 - 0.38) / 0.24
                    local gx, gy = cx + (p - 0.5) * w * 0.5, cy + (0.5 - p) * h * 0.3
                    local s = w * 0.45 * g
                    surface.SetMaterial(GLOW_MAT)
                    surface.SetDrawColor(255, 250, 225, 255 * g * alpha / 255)
                    surface.DrawTexturedRect(gx - s / 2, gy - s / 2, s, s)
                    surface.DrawTexturedRect(gx - s / 6, gy - s / 6, s / 3, s / 3)
                end
            end
        else
            drawHolo(handMat(l.frame), cx - w / 2, cy - h / 2, w, col, alpha, mirror)
        end
    end
end

-- Offline chips make the hands flicker and jitter.
local function glitch(ply)
    return not GK.IsChipOnline(ply)
end

-- First person -------------------------------------------------------------

local smooth = { l = Vector(), r = Vector() }

local function drawHand(ply, side, button)
    local w, h = ScrW(), ScrH()
    local size = math.floor(h * 0.42)
    local mirror = side == "r"
    local t = CurTime()
    local speed = ply:GetVelocity():Length2D()

    -- Rest position, with a little walk bob and a float when idle.
    local bob = math.sin(t * (speed > 20 and 9 or 1.5) + (mirror and math.pi or 0)) * (speed > 20 and 10 or 4)
    local x = mirror and (w - size * 1.05) or (size * 0.05)
    local y = h - size * 0.95 + bob
    if GK.IsDowned(ply) then y = h - size * 0.6 end
    if isBusy(ply) then -- both hands working the gun, centre-right
        x = mirror and (w * 0.62) or (w * 0.42)
        y = h - size * 0.8 + bob
    end

    -- Gripping hands slide toward where they're holding on.
    if ply:GetNW2Int("gk_hand_" .. side, 0) == 1 then
        local s = ply:GetNW2Vector("gk_grip_" .. side):ToScreen()
        if s.visible then
            x = math.Clamp(s.x - size * 0.5, -size * 0.2, w - size * 0.8)
            y = math.Clamp(s.y - size * 0.35, h * 0.15, h - size * 0.6)
        end
    end

    smooth[side] = LerpVector(math.min(FrameTime() * 18, 1), smooth[side], Vector(x, y, 0))
    local pos = smooth[side]
    -- Fists (sh_melee.lua): drawn back and down while winding up (trembling at
    -- full), then thrown up toward the crosshair on the punch.
    if GK.HasFist and GK.HasFist(ply, side) and GK.Melee then
        local c, winding = GK.Melee.Charge(ply, side)
        local out = mirror and 1 or -1
        if winding then
            pos = pos + Vector(out * size * 0.1 * c, size * (0.04 + 0.16 * c), 0)
            if c >= 1 then
                pos = pos + Vector(math.Rand(-2, 2), math.Rand(-2, 2), 0)
                -- Fully wound: the knuckles creak once, so you can feel it is ready.
                if not ply["GK_WoundFull_" .. side] then
                    ply["GK_WoundFull_" .. side] = true
                    surface.PlaySound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav")
                end
            end
        end
        if not winding or c < 1 then ply["GK_WoundFull_" .. side] = nil end
        local pt = CurTime() - ply:GetNW2Float("gk_punch_" .. side, 0)
        if pt >= 0 and pt < 0.2 then
            local k = math.sin(pt / 0.2 * math.pi)
            pos = pos + Vector(-out * size * 0.38 * k, -size * 0.3 * k, 0)
        end
    end
    -- Where the palm is on screen, so held items (cl_inventory.lua) sit in it.
    GK.HandPalm = GK.HandPalm or {}
    GK.HandPalm[side] = { x = pos.x + size * (mirror and 0.42 or 0.58), y = pos.y + size * 0.42, size = size }

    local col = GK.HandColor(ply, side)
    local alpha = holoAlpha(ply, 235)
    if glitch(ply) then
        alpha = math.random(30, 160)
        pos = pos + Vector(math.random(-10, 10), math.random(-3, 3), 0)
    end

    -- An emote: the hand makes its gesture where the emote puts it.
    local emote, et
    if GK.EmoteOf then emote, et = GK.EmoteOf(ply) end
    local pose = emote and emote.hands(et, side)
    if pose then
        local s = size * (pose.size or 1)
        local cx, cy = pose.x * w, pose.y * h
        local mat = handMat(pose.frame)
        surface.SetDrawColor(col.r, col.g, col.b, alpha * 0.25)
        quad(mat, cx, cy, s * 1.16, s * 1.16, mirror and -pose.rot or pose.rot, mirror)
        surface.SetDrawColor(col.r, col.g, col.b, alpha)
        quad(mat, cx, cy, s, s, mirror and -pose.rot or pose.rot, mirror)
        smooth[side] = Vector(cx - size / 2, cy - size / 2, 0) -- glide back from here after
        return
    end

    local hclass, hdata = heldClass(ply, side)
    local layout = GK.HeldLayout(hclass)
    if layout then
        drawHeld(layout, pos.x, pos.y, size, mirror, col, alpha, hdata)
        return
    end
    local frame = isBusy(ply) and FRAMES.hold or frameFor(ply, side, button)
    drawHolo(handMat(frame), pos.x, pos.y, size, col, alpha, mirror)
end

hook.Add("HUDPaintBackground", "GK_MindHands", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or GK.IsRagdolled(ply) or not showsHands(ply) then return end
    if ply:ShouldDrawLocalPlayer() then return end
    if drawsHand(ply, "l") then drawHand(ply, "l", IN_ATTACK) end
    if drawsHand(ply, "r") then drawHand(ply, "r", IN_ATTACK2) end
    if GK.DrawHeldModels then GK.DrawHeldModels() end -- HL2 items' models, over the hands
end)

-- Third person: other players' mind-hands float beside them or sit on their grip.

local HAND_WORLD_SIZE = 14

local function handWorldPos(ply, side)
    if ply:GetNW2Int("gk_hand_" .. side, 0) == 1 then
        return ply:GetNW2Vector("gk_grip_" .. side)
    end
    local ang = ply:EyeAngles()
    local right = ang:Right() * (side == "r" and 14 or -14)
    local bob = Vector(0, 0, math.sin(CurTime() * 2 + (side == "r" and 1 or 0)) * 2)
    return ply:EyePos() + ang:Forward() * 18 + right - Vector(0, 0, 14) + bob
end

local function drawWorldHand(ply, side)
    local pos = handWorldPos(ply, side)
    local ang = (EyePos() - pos):GetNormalized():Angle()
    ang:RotateAroundAxis(ang:Right(), -90)
    ang:RotateAroundAxis(ang:Up(), 90)

    local alpha = glitch(ply) and math.random(30, 140) or holoAlpha(ply, 235)
    local half = HAND_WORLD_SIZE / 2
    -- Seen from in front, the hands face you: the sprites flip like a mirror.
    local front = ply:EyeAngles():Forward():Dot(EyePos() - ply:EyePos()) > 0
    local mirror = (side == "r") ~= front
    cam.Start3D2D(pos, ang, 1)
        local layout = GK.HeldLayout(heldClass(ply, side))
        local emote, et
        if GK.EmoteOf then emote, et = GK.EmoteOf(ply) end
        local pose = emote and emote.hands(et, side)
        if pose then
            surface.SetDrawColor(GK.HandColor(ply, side).r, GK.HandColor(ply, side).g, GK.HandColor(ply, side).b, alpha)
            quad(handMat(pose.frame), 0, 0, HAND_WORLD_SIZE, HAND_WORLD_SIZE, mirror and -pose.rot or pose.rot, mirror)
        elseif layout then
            drawHeld(layout, -half, -half, HAND_WORLD_SIZE, mirror, GK.HandColor(ply, side), alpha)
        else
            drawHolo(handMat(frameFor(ply, side)), -half, -half, HAND_WORLD_SIZE, GK.HandColor(ply, side), alpha, mirror)
        end
    cam.End3D2D()
end

-- Ambient glow: each player's projection lights the world around their hands.
hook.Add("Think", "GK_HoloLight", function()
    local me = LocalPlayer()
    for _, ply in ipairs(player.GetAll()) do
        if ply:Alive() and showsHands(ply) and not ply:IsDormant() then
        local pos
        if ply == me and not ply:ShouldDrawLocalPlayer() then
            pos = ply:EyePos() + ply:GetAimVector() * 24 - Vector(0, 0, 10)
        else
            pos = (handWorldPos(ply, "l") + handWorldPos(ply, "r")) * 0.5
        end
        local col = GK.HandColor(ply)
        local light = DynamicLight(ply:EntIndex() + 4096)
        if light then
            light.pos = pos
            light.r, light.g, light.b = col.r, col.g, col.b
            light.brightness = glitch(ply) and math.Rand(0, 0.6) or 0.6
            light.decay = 1000
            light.size = 110
            light.dietime = CurTime() + 0.1
        end
        end
    end
end)

hook.Add("PostPlayerDraw", "GK_WorldMindHands", function(ply)
    if not ply:Alive() or not showsHands(ply) then return end
    if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then return end
    drawWorldHand(ply, "l")
    drawWorldHand(ply, "r")
end)
