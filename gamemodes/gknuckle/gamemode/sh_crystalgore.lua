-- Xenium crystal gore. The virus has crystallised in every husk, so when one
-- is wounded (legs blown off, head off, killed) the wound bursts into
-- crystal shards and glowing blood in the husk's current action colour, and
-- crystal stays grown into the stump. Dead husks' crystal goes black. Loose
-- shards and blood lose their glow, fade to black, then stop rendering.
-- Colour: GK.Husk.CrystalColor(ply) (the Husk thread's, from the hand
-- colours; black when dead), falling back to GK.HandColor.
AddCSLuaFile()

-- Shards are drawn, not models: the converted WK crystal meshes crashed GMod
-- when spawned (access violation), so each shard is a small faceted spike.

function GK.CrystalColor(ply)
    if not IsValid(ply) then return Color(0, 0, 0) end
    if GK.Husk and GK.Husk.CrystalColor then
        local c = GK.Husk.CrystalColor(ply)
        if c then return c end
    end
    if not ply:Alive() and not GK.IsDowned(ply) then return Color(0, 0, 0) end
    return GK.HandColor(ply, "l")
end

if SERVER then
    util.AddNetworkString("gk_crystal_burst")

    -- A burst of shards and blood at pos, in that player's colour right now.
    function GK.CrystalBurst(ply, pos, count, dir)
        GK.CrystalBurstColor(pos, count, dir, GK.CrystalColor(ply))
    end

    -- The same burst in any colour (the hub's husk pods bleed orange).
    function GK.CrystalBurstColor(pos, count, dir, c)
        net.Start("gk_crystal_burst")
        net.WriteVector(pos)
        net.WriteVector(dir or vector_up)
        net.WriteUInt(count or 8, 6)
        net.WriteColor(Color(c.r, c.g, c.b))
        net.SendPVS(pos)
    end

    local function bonePos(ply, name)
        local b = ply:LookupBone(name)
        return b and ply:GetBonePosition(b) or ply:WorldSpaceCenter()
    end

    -- Wrap the wound functions (sv_dismember.lua, sh_impale.lua) once they exist.
    local function wrap()
        -- (Re-wrapped if a Lua refresh redefines them.)
        if GK.RemoveLegs and GK.RemoveLegs ~= GK.GK_CrystalLegs then
            local orig = GK.RemoveLegs
            GK.RemoveLegs = function(ply, ...)
                local had = GK.HasLegs(ply)
                local r = orig(ply, ...)
                if had and IsValid(ply) then
                    GK.CrystalBurst(ply, bonePos(ply, "ValveBiped.Bip01_L_Calf"), 7)
                    GK.CrystalBurst(ply, bonePos(ply, "ValveBiped.Bip01_R_Calf"), 7)
                end
                return r
            end
            GK.GK_CrystalLegs = GK.RemoveLegs
        end
        if GK.Decapitate and GK.Decapitate ~= GK.GK_CrystalHead then
            local orig = GK.Decapitate
            GK.Decapitate = function(ply, dir, ...)
                if IsValid(ply) then GK.CrystalBurst(ply, bonePos(ply, "ValveBiped.Bip01_Head1"), 12, dir) end
                return orig(ply, dir, ...)
            end
            GK.GK_CrystalHead = GK.Decapitate
        end
    end
    hook.Add("Initialize", "GK_CrystalGore", wrap)
    timer.Create("GK_CrystalGore", 2, 0, wrap)
    wrap()

    -- Where they were last hit, for the burst when they die.
    hook.Add("EntityTakeDamage", "GK_CrystalGore", function(ent, d)
        if ent:IsPlayer() then ent.GK_LastHitPos = d:GetDamagePosition() ~= vector_origin and d:GetDamagePosition() or ent:WorldSpaceCenter() end
    end)
    hook.Add("DoPlayerDeath", "GK_CrystalGore", function(ply)
        -- Still in its living colour as it bursts; it goes black after.
        GK.CrystalBurst(ply, ply.GK_LastHitPos or ply:WorldSpaceCenter(), 10)
    end)
end

if CLIENT then
    local pieces = {} -- { m = model, pos, vel, ang, spin, col, born, life, blood }

    local white = CreateMaterial("gk_crystal_shard", "UnlitGeneric", {
        ["$basetexture"] = "color/white", ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1,
    })
    -- One shard: a four-sided spike of length len along ang's forward.
    local function drawShard(pos, ang, len, r, g, b, a)
        local f, u, ri = ang:Forward(), ang:Up(), ang:Right()
        local w = len * 0.28
        local tip, base = pos + f * len, pos
        local c1, c2, c3, c4 = base + u * w, base + ri * w, base - u * w, base - ri * w
        render.SetMaterial(white)
        local col = Color(r, g, b, a)
        local shade = Color(r * 0.6, g * 0.6, b * 0.6, a)
        render.DrawQuad(c1, tip, tip, c2, col)
        render.DrawQuad(c2, tip, tip, c3, shade)
        render.DrawQuad(c3, tip, tip, c4, col)
        render.DrawQuad(c4, tip, tip, c1, shade)
    end
    local glow = Material("sprites/light_glow02_add")
    local LIFE, FADE = 6, 2 -- seconds glowing (dimming to black), then fading out

    net.Receive("gk_crystal_burst", function()
        local pos, dir, n, col = net.ReadVector(), net.ReadVector(), net.ReadUInt(6), net.ReadColor()
        for i = 1, n do
            pieces[#pieces + 1] = {
                shard = math.Rand(1.5, 4), pos = pos + VectorRand() * 3, vel = (dir * 120 + VectorRand() * 160 + Vector(0, 0, 90)),
                ang = AngleRand(), spin = AngleRand() * 2, col = col, born = CurTime(),
            }
            -- Glowing blood droplets.
            pieces[#pieces + 1] = {
                pos = pos, vel = dir * 80 + VectorRand() * 200 + Vector(0, 0, 60), col = col, born = CurTime(),
                blood = true, size = math.Rand(2, 5),
            }
        end
        sound.Play("physics/glass/glass_impact_bullet" .. math.random(1, 4) .. ".wav", pos, 70, math.random(120, 150))
    end)

    -- How bright a loose piece still is: full colour, dimming to black over LIFE.
    local function fadeCol(p, age)
        local k = math.Clamp(1 - age / LIFE, 0, 1)
        return p.col.r * k, p.col.g * k, p.col.b * k
    end

    hook.Add("Think", "GK_CrystalPieces", function()
        local dt = FrameTime()
        for i = #pieces, 1, -1 do
            local p = pieces[i]
            local age = CurTime() - p.born
            if age > LIFE + FADE then
                table.remove(pieces, i)
            elseif not p.rest then
                p.vel.z = p.vel.z - 600 * dt
                local np = p.pos + p.vel * dt
                local tr = util.TraceLine({ start = p.pos, endpos = np, mask = MASK_SOLID_BRUSHONLY })
                if tr.Hit then
                    p.pos = tr.HitPos + tr.HitNormal
                    p.rest = true
                    p.normal = tr.HitNormal
                else
                    p.pos = np
                    if p.spin then p.ang = p.ang + p.spin * dt end
                end
            end
        end
    end)

    hook.Add("PostDrawTranslucentRenderables", "GK_CrystalPieces", function(depth, sky)
        if depth or sky then return end
        render.SuppressEngineLighting(true)
        for _, p in ipairs(pieces) do
            local age = CurTime() - p.born
            local r, g, b = fadeCol(p, age)
            local a = age > LIFE and math.Clamp(1 - (age - LIFE) / FADE, 0, 1) or 1
            if p.blood then
                render.SetMaterial(glow)
                render.DrawSprite(p.pos, p.size * 2.5, p.size * 2.5, Color(r, g, b, 200 * a))
            elseif p.shard then
                drawShard(p.pos, p.ang, p.shard, math.max(r, 12), math.max(g, 12), math.max(b, 12), 255 * a)
            end
        end
        render.SuppressEngineLighting(false)
    end)

    -- Crystal grown into the stumps: legs gone, or (on a corpse) head gone.
    local function drawStump(ent, bone, seed, col)
        local b = ent:LookupBone(bone)
        if not b then return end
        local mtx = ent:GetBoneMatrix(b)
        if not mtx then return end
        local pos, ang = mtx:GetTranslation(), mtx:GetAngles()
        for i = 0, 3 do
            local a = Angle(ang.p, ang.y, ang.r)
            a:RotateAroundAxis(a:Up(), seed * 37 + i * 90)
            a:RotateAroundAxis(a:Right(), 25 + (i % 2) * 20)
            drawShard(pos, a, 3 + ((seed + i) % 3) * 1.2, math.max(col.r, 12), math.max(col.g, 12), math.max(col.b, 12), 255)
        end
    end
    local function drawStumps(ent, owner, legs, head)
        local col = GK.CrystalColor(owner)
        render.SuppressEngineLighting(true)
        if legs then
            drawStump(ent, "ValveBiped.Bip01_L_Calf", 1, col)
            drawStump(ent, "ValveBiped.Bip01_R_Calf", 2, col)
        end
        if head then drawStump(ent, "ValveBiped.Bip01_Neck1", 3, col) end
        render.SuppressEngineLighting(false)
    end

    hook.Add("PostPlayerDraw", "GK_CrystalStumps", function(ply)
        if not ply:Alive() or GK.HasLegs(ply) then return end
        drawStumps(ply, ply, true, false)
    end)

    -- Corpses keep their stumps, black.
    hook.Add("CreateClientsideRagdoll", "GK_CrystalStumps", function(owner, rag)
        if not IsValid(owner) or not owner:IsPlayer() then return end
        local legs, head = not GK.HasLegs(owner), GK.IsGored(owner)
        if not legs and not head then return end
        rag.RenderOverride = function(self)
            self:DrawModel()
            drawStumps(self, owner, legs, head)
        end
    end)
end
