-- Fists, blocks, kicks and staggers, by numbers. Only runs when
-- data/gknuckle/meleetest.txt exists. Logs "[GKMELEE]"; no screenshots.
if not file.Exists("gknuckle/meleetest.txt", "DATA") then return end
local function log(...) print("[GKMELEE]", ...) end
if CLIENT then return end

local steps = {}
local function step(delay, fn) steps[#steps + 1] = { delay, fn } end
local P, B

local function face(a, b) a:SetEyeAngles((b:WorldSpaceCenter() - a:GetShootPos()):Angle()) end
local function place()
    local fwd = Angle(0, P:EyeAngles().y, 0):Forward()
    B:SetPos(P:GetPos() + fwd * 50) B:SetHealth(100) P:SetHealth(100)
    B:SetLocalVelocity(vector_origin) P:SetLocalVelocity(vector_origin)
    face(P, B) face(B, P)
end

step(0, function()
    P = player.GetHumans()[1]
    P:SelectWeapon("gk_mind")
    if #player.GetBots() == 0 then RunConsoleCommand("bot") end
end)
step(2, function()
    B = player.GetBots()[1]
    place()
    -- Fists: Q with empty hand and pocket raises the left fist.
    GK.Melee.ToggleFist(P, "l")
    log("left fist up", tostring(GK.HasFist(P, "l")))
    GK.Melee.Punch(P, "l")
    log("punch: bot hp", B:Health(), "(expect 90)", "ragdolled", tostring(GK.IsRagdolled(B)))
end)
-- Danger Zone punches: a tap jabs, a held press winds up the heavy one; the fist stays up.
step(0.6, function()
    place()
    P.GK_NextPunch_l = 0
    P:SetNW2Float("gk_punch_charge_l", CurTime() - 0.08) -- pressed and let go at once
    GK.Melee.PunchInput(P, "l", false)
    log("quick jab: bot hp", B:Health(), "(expect 95)", "fist still up", tostring(GK.HasFist(P, "l")))
end)
step(0.6, function()
    place()
    P.GK_NextPunch_l = 0
    P:SetNW2Float("gk_punch_charge_l", CurTime() - 0.5) -- held half way
    log("winding half way: charge", math.floor(GK.Melee.Charge(P, "l") * 100) / 100)
    GK.Melee.PunchInput(P, "l", false)
    log("half wound punch: bot hp", B:Health(), "(expect 93)")
end)
step(0.6, function()
    place()
    P.GK_NextPunch_l = 0
    P:SetNW2Float("gk_punch_charge_l", CurTime() - 1.2) -- held past full
    GK.Melee.PunchInput(P, "l", false)
    log("full wind-up punch: bot hp", B:Health(), "(expect 90)", "fist still up", tostring(GK.HasFist(P, "l")), "winding cleared", tostring(P:GetNW2Float("gk_punch_charge_l", 0) == 0))
end)
step(0.6, function()
    place()
    local inv = GK.Inv.Get(B) inv.slots = {} GK.Inv.Sync(B) -- bots pick things up wandering the hub
    GK.Melee.ToggleFist(B, "l") GK.Melee.ToggleFist(B, "r")
    B:SetNW2Bool("gk_blocking", true) -- holding R with both fists up
    log("block check: fists", tostring(GK.HasFist(B, "l")), tostring(GK.HasFist(B, "r")), "blocking", tostring(GK.IsBlocking(B)), "mult", GK.Melee.BlockMult(B, P:GetPos()))
    GK.SetStamina(P, 50) GK.SetStamina(B, 50)
    GK.Melee.Punch(P, "l")
    log("punch into a double block: bot hp", B:Health(), "(expect 100)", "puncher stamina", P:GetNW2Float("gk_stamina"), "(expect 46)", "blocker stamina", B:GetNW2Float("gk_stamina"), "(expect 42)")
    place() B:SetNW2Bool("gk_blocking", true) GK.SetStamina(B, 3) P.GK_NextPunch_l = 0
    GK.Melee.Punch(P, "l")
    log("too tired to hold the guard: bot hp", B:Health(), "(expect 90)")
    P.GK_NextPunch_l = 0 GK.SetStamina(P, 2) local hp = B:Health()
    GK.Melee.Punch(P, "l")
    log("too tired to punch: bot hp unchanged", tostring(B:Health() == hp))
    GK.SetStamina(P, 100) GK.SetStamina(B, 100)
end)
-- One fist covers only its own side.
step(0.6, function()
    GK.Melee.ToggleFist(B, "l") -- left down, right still up
    B:SetNW2Bool("gk_blocking", true)
    local right = B:GetPos() + B:GetRight() * 60
    local left = B:GetPos() - B:GetRight() * 60
    log("right fist only, blocking: blow from its right", GK.Melee.BlockMult(B, right), "(expect 0.4)", "from its left", GK.Melee.BlockMult(B, left), "(expect 1)")
    GK.Melee.ToggleFist(B, "l")
end)
step(0.6, function()
    place()
    B:SetNW2Bool("gk_blocking", false)
    GK.Melee.ToggleFist(B, "l") GK.Melee.ToggleFist(B, "r")
    P.GK_NextKick = 0
    GK.Kick(P)
    log("kick to the body: bot hp", B:Health(), "(expect 95)", "ragdolled", tostring(GK.IsRagdolled(B)), "kick anim time set", tostring(P:GetNW2Float("gk_kick_at", 0) > 0))
end)
step(0.6, function()
    place()
    -- Head at kick height: aim straight at the bot's head.
    local b = B:LookupBone("ValveBiped.Bip01_Head1")
    local head = b and B:GetBonePosition(b) or B:EyePos()
    local r = GK.Melee.Hit(P, B, GK.Melee.KICK_DAMAGE, head, P:GetAimVector(), true)
    log("kick to the head:", r, "bot ragdolled", tostring(GK.IsRagdolled(B)))
end)
step(2.5, function()
    log("light stagger over: bot ragdolled", tostring(GK.IsRagdolled(B)))
    -- The full stagger: the red bar shatters.
    place()
    GK.Stagger.Full(P)
    log("full stagger: staggered", tostring(GK.IsStaggered(P)), "body", tostring(IsValid(GK.Stagger.Ragdoll(P))), "hands", tostring(GK.HandColor(P, "l")))
    GK.SetStamina(P, 10)
end)
step(1, function()
    local rag = GK.Stagger.Ragdoll(P)
    local head, fwd = GK.Stagger.Head(rag)
    log("lying: eye at the head", math.floor(P:EyePos():Distance(head)), "stamina", math.floor(P:GetNW2Float("gk_stamina", 0)), "cone clamp of a backward look",
        math.floor(math.deg(math.acos(GK.Stagger.Clamp((-fwd):Angle(), fwd):Forward():Dot(fwd)))))
end)
step(8, function()
    log("after 9 s lying: staggered", tostring(GK.IsStaggered(P)), "(up once stamina refills)", "immune", tostring(P:GetNW2Float("gk_stagger_immune", 0) > CurTime()))
    GK.Stagger.Full(P)
    log("staggered again while immune", tostring(GK.IsStaggered(P)), "(expect false)")
end)
step(5, function()
    -- A teammate pulls you up: the bot staggers, we grab its body.
    place()
    GK.LeaveSquad(P) GK.LeaveSquad(B) log("squad up with the bot", tostring(GK.JoinSquads(P, B)), "same side", tostring(GK.SameSide(P, B)))
    GK.Stagger.Full(B)
    local rag = GK.Stagger.Ragdoll(B)
    log("bot staggered", tostring(GK.IsStaggered(B)))
    timer.Simple(0.8, function()
        if not IsValid(rag) then return end
        P:SetEyeAngles((rag:WorldSpaceCenter() - P:GetShootPos()):Angle())
        -- GetEyeTrace is cached for the tick: look first, grab on the next one.
        timer.Simple(0.1, function()
            if not IsValid(rag) then return end
            local mind = P:GetWeapon("gk_mind")
            local t = mind:Trace(P) log("  aiming at", tostring(t and t.Entity), "owner on it", tostring(t and IsValid(t.Entity) and t.Entity.GK_StaggerOwner), "same side", tostring(GK.SameSide(P, B)), "P staggered", tostring(GK.IsStaggered(P)))
            mind:TryGrip(P, "r")
            log("grabbed its body: bot staggered", tostring(GK.IsStaggered(B)), "(expect false)")
        end)
    end)
end)
-- One leg: no kick.
step(1, function()
    GK.RemoveLeg(P, "r")
    log("right leg off: one-legged", tostring(GK.OneLegged(P)), "legless", tostring(not GK.HasLegs(P)))
    local t0 = P:GetNW2Float("gk_kick_at", 0)
    P.GK_NextKick = 0
    GK.Kick(P)
    log("kick on one leg happened", tostring(P:GetNW2Float("gk_kick_at", 0) ~= t0), "(expect false)")
    GK.RemoveLeg(P, "l")
    log("second leg off: legless", tostring(not GK.HasLegs(P)))
end)
-- Impaled to the floor: lying flat, looking at the floor or out along the rod.
step(1, function()
    P:Spawn() P:SelectWeapon("gk_mind")
    place()
    local dir = Angle(0, B:EyeAngles().y + 180, 0):Forward() -- from in front of it
    local tr = { HitPos = B:WorldSpaceCenter(), HitGroup = HITGROUP_STOMACH, Entity = B }
    local res = GK.RebarHit(B, tr, dir, P, P)
    log("rebar into the bot:", res, "impaled", tostring(GK.IsImpaled(B)), "prone", tostring(GK.ImpaleProne(B)), "view height", math.floor(B:GetViewOffset().z), "hull top", math.floor(select(2, B:GetHull()).z), "look pitch", math.floor(B:EyeAngles().p))
end)
step(0.5, function()
    GK.Unimpale(B)
end)
step(1, function()
    log("slid off: impaled", tostring(GK.IsImpaled(B)), "prone", tostring(B:GetNW2Bool("gk_impale_prone", false)), "view height", math.floor(B:GetViewOffset().z), "bleeding", tostring((B.GK_BleedUntil or 0) > CurTime()))
end)
-- An explosive rod, direct hit: gibbed.
step(1, function()
    if not B:Alive() then B:Spawn() end
    place()
    local trash0 = #ents.FindByClass("gk_trash")
    GK.Gib(B, P, B:WorldSpaceCenter())
    log("gibbed: bot alive", tostring(B:Alive()), "gibbed flag", tostring(B:GetNW2Bool("gk_gibbed", false)), "chunks", #ents.FindByClass("gk_trash") - trash0)
    timer.Simple(0.5, function() log("gib corpse left", tostring(IsValid(B:GetRagdollEntity()))) end)
end)
-- Legs: blown off, picked up, put back on someone (theirs or not).
step(1, function()
    if not B:Alive() then B:Spawn() end
    if not P:Alive() then P:Spawn() end
    P:SelectWeapon("gk_mind")
    place()
    local inv = GK.Inv.Get(P) inv.slots = {} GK.Inv.Sync(P)
    GK.RestoreLegs(P) -- our own legs back on, so the leg goes to the bot
    local n0 = 0
    for _, e in ipairs(ents.FindByClass("gk_item")) do if string.find(e.GKItemClass or "", "^leg_") then n0 = n0 + 1 end end
    log("pants: mine", tostring(P:GetNW2Vector("gk_pants_l")), "bot", tostring(B:GetNW2Vector("gk_pants_l")))
    GK.RemoveLegs(B)
    local legs = {}
    for _, e in ipairs(ents.FindByClass("gk_item")) do if string.find(e.GKItemClass or "", "^leg_") then legs[#legs + 1] = e end end
    log("bot legless", tostring(not GK.HasLegs(B)), "leg items dropped", #legs - n0)
    local leg = legs[#legs]
    local ok = GK.Inv.PickupToHand(P, leg, "l")
    log("picked up a leg", tostring(ok), "hand", tostring(GK.Inv.HandItem(P, "l") and GK.Inv.HandItem(P, "l").class))
    face(P, B)
    local tr = util.TraceHull({ start = P:GetShootPos(), endpos = P:GetShootPos() + P:GetAimVector() * 90, mins = Vector(-6, -6, -6), maxs = Vector(6, 6, 6), filter = P, mask = MASK_SHOT_HULL })
    log("before use: my missing leg", GK.MissingLeg(P) or "none", "bot missing", GK.MissingLeg(B) or "none", "aim hits", tostring(tr.Entity), "busy", tostring(P:GetNW2Float("gk_busy_until", 0) > CurTime()), "dist", math.floor(P:GetPos():Distance(B:GetPos())))
    GK.Inv.Use(P, "l")
    log("put it on the bot: has legs", tostring(GK.HasLegs(B)), "one-legged", tostring(GK.OneLegged(B)), "hand now", tostring(GK.Inv.HandItem(P, "l")))
end)
-- A raised fist grounds you: no grabbing the floor or walls with the other hand either.
step(1, function()
    local inv = GK.Inv.Get(P) inv.slots = {} GK.Inv.Sync(P)
    P:SetNW2Bool("gk_fist_l", false) P:SetNW2Bool("gk_fist_r", false)
    B:SetPos(P:GetPos() + Vector(400, 0, 0)) -- out of the way
    P:SetEyeAngles(Angle(80, P:EyeAngles().y, 0)) -- at the floor
    local mind = P:GetWeapon("gk_mind")
    local t = mind:Trace(P)
    log("debug: trace", tostring(t and t.Entity), t and math.floor(t.HitPos:Distance(P:GetShootPos())) or "miss", "staggered", tostring(GK.IsStaggered(P)), "fist", tostring(GK.HasFist(P, "l")), tostring(GK.HasFist(P, "r")), "alive", tostring(P:Alive()), "eye z", math.floor(P:EyePos().z - P:GetPos().z))
    local open = mind:TryGrip(P, "r")
    GK.Melee.ToggleFist(P, "l")
    local fisted = mind:TryGrip(P, "r")
    log("grab the floor: open hands", open and open.kind or "none", "with a fist up", fisted and fisted.kind or "none", "(expect none, none: WK hands take ledges, not a bare floor)")
end)
-- WK drop keys: 1 drops the left hand, 2 the right (sh_keys.lua -> Inv.DropHand(ply, side)).
step(0.5, function()
    local inv = GK.Inv.Get(P) inv.slots = {} inv.bag = {}
    GK.Inv.Give(P, "brick") GK.Inv.Give(P, "flare")
    for _, it in ipairs(table.Copy(inv.bag)) do GK.Inv.Move(P, it.id, it.class == "brick" and "hand_l" or "hand_r") end
    GK.Inv.Sync(P)
    hook.Run("PlayerButtonDown", P, KEY_1)
    log("pressed 1: left", tostring(GK.Inv.HandItem(P, "l") and GK.Inv.HandItem(P, "l").class), "(expect nil)", "right", tostring(GK.Inv.HandItem(P, "r") and GK.Inv.HandItem(P, "r").class), "(expect flare)")
    hook.Run("PlayerButtonDown", P, KEY_2)
    log("pressed 2: right", tostring(GK.Inv.HandItem(P, "r") and GK.Inv.HandItem(P, "r").class), "(expect nil)")
end)
-- "MY LEG": 70% on the first leg; exactly one of the two legs plays it; fresh each life.
step(0.5, function()
    local first, one = 0, 0
    for _ = 1, 1000 do
        local n = 0
        local fake = { EmitSound = function() n = n + 1 end }
        GK.MyLeg(fake) local a = n
        GK.MyLeg(fake)
        if a == 1 then first = first + 1 end
        if n == 1 then one = one + 1 end
    end
    P.GK_MyLegLast = true P:Spawn()
    log("my leg: first leg played", first / 10 .. "%", "(expect about 70)", "exactly one per pair", one / 10 .. "%", "(expect 100)", "reset on respawn", tostring(P.GK_MyLegLast == nil))
end)
step(2, function() log("DONE") end)
hook.Add("PlayerInitialSpawn", "GK_MeleeTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_MeleeTest")
    timer.Simple(10, function()
        local t = 0
        for _, s in ipairs(steps) do
            t = t + s[1]
            timer.Simple(t, function()
                local ok, err = pcall(s[2])
                if not ok then log("STEP ERROR", err) end
            end)
        end
    end)
end)
