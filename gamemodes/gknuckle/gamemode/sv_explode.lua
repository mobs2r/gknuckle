-- One explosion for everything that blows up, like WK's UT_Explosion: the boom
-- bug, the boom jar, explosive rebar and the gas bag all go off through
-- GK.Explode, so they hurt, throw and knock you off the wall by the same rules.
--   damage   falls off with distance to the edge of the radius
--   push     players are thrown out and up, by `force` falling off the same way;
--            loose props and roaches get the same shove
--   grip     anyone inside is knocked off the wall (WK's DropHang)
-- opts: radius, damage, force, attacker, inflictor, effect (default "Explosion"),
--       sound (optional), lift (upward share of the push, default 0.4)

function GK.Explode(pos, opts)
    opts = opts or {}
    local radius = opts.radius or 160
    local attacker = IsValid(opts.attacker) and opts.attacker or game.GetWorld()
    local inflictor = IsValid(opts.inflictor) and opts.inflictor or attacker
    local fx = EffectData() fx:SetOrigin(pos)
    util.Effect(opts.effect or "Explosion", fx, true, true)
    if opts.sound then sound.Play(opts.sound, pos, 95, math.random(95, 105)) end
    util.BlastDamage(inflictor, attacker, pos, radius, opts.damage or 35)
    local force, lift = opts.force or 520, opts.lift or 0.4
    for _, e in ipairs(ents.FindInSphere(pos, radius * 1.25)) do
        local c = e:WorldSpaceCenter()
        local d = c:Distance(pos)
        local k = math.max(0, 1 - d / (radius * 1.25))
        local dir = ((c - pos):GetNormalized() + Vector(0, 0, lift)):GetNormalized()
        if e:IsPlayer() and e:Alive() then
            e:SetVelocity(dir * force * math.max(0.2, k))
            if GK.DropHang then GK.DropHang(e, 0.1, 1) end
        elseif e:GetClass() == "gk_roach" and e.AddForce then
            e:AddForce(dir * force * 0.6 * k)
        elseif e ~= inflictor then
            local phys = e:GetPhysicsObject()
            if IsValid(phys) and phys:IsMotionEnabled() then phys:ApplyForceCenter(dir * force * phys:GetMass() * k * 0.5) end
        end
    end
    hook.Run("GK_Explosion", pos, opts)
end
