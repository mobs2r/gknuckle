-- Grip test on the hub's training-tower pitons. Only runs when
-- data/gknuckle/pitontest.txt exists. Logs "[GKPITON]" lines.
if not file.Exists("gknuckle/pitontest.txt", "DATA") then return end
if CLIENT then
    local held, untilT = 0, 0
    net.Receive("gk_pitontest", function() held = net.ReadUInt(32) untilT = CurTime() + net.ReadFloat() end)
    hook.Add("CreateMove", "GK_PitonTestInput", function(cmd)
        if CurTime() < untilT then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), held))
            if bit.band(held, IN_FORWARD) ~= 0 then cmd:SetForwardMove(250) end
        end
    end)
    return
end
util.AddNetworkString("gk_pitontest")
local function log(...) print("[GKPITON]", ...) end

hook.Add("PlayerInitialSpawn", "GK_PitonTest", function(ply)
    if ply:IsBot() then return end
    hook.Remove("PlayerInitialSpawn", "GK_PitonTest")
    timer.Simple(10, function()
        local P = ply
        P:SelectWeapon("gk_mind")
        local mind = P:GetWeapon("gk_mind")
        local pieces = ents.FindByClass("gk_level_piece")
        log("level pieces", #pieces)
        local n, ok = 0, 0
        local spots = {}
        for _, piece in ipairs(pieces) do
            local per = 0
            for _, box in ipairs(GK.Handholds.BoxesOf(piece:GetPiece())) do
                if box.piton and per < 4 then
                    per = per + 1
                    n = n + 1
                    local c = piece:GetPos() + (box.mins + box.maxs) * 0.5
                    -- Stand off it on whichever side is open.
                    local best
                    for _, d in ipairs({ Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0) }) do
                        local tr = util.TraceLine({ start = c + d * 14, endpos = c + d * 60, mask = MASK_PLAYERSOLID })
                        if not tr.Hit then best = d break end
                    end
                    if best then
                        P:SetPos(c + best * 50 - Vector(0, 0, 64))
                        P:SetEyeAngles((c - P:EyePos()):Angle())
                        local tr = P:GetEyeTrace()
                        local hh, d = GK.HandholdHit(P:GetShootPos(), P:GetAimVector(), 180)
                        local g = mind:TryGrip(P, "l")
                        local good = g and g.kind == "world" and g.hitpos:Distance(c) < 30
                        if good then ok = ok + 1 spots[#spots + 1] = { pos = P:GetPos(), ang = P:EyeAngles(), piece = piece:GetPiece() } end
                        log(piece:GetPiece(), ("box %d"):format(n), "eye trace", tr.Entity and tr.Entity:GetClass() or "?", ("%.0f"):format(tr.HitPos:Distance(P:GetShootPos())),
                            "handhold hit", hh and ("%.0f"):format(d) or "none", "grip", g and g.kind or "none", g and g.hitpos and ("%.0f"):format(g.hitpos:Distance(c)) or "-")
                    else
                        log(piece:GetPiece(), "box", n, "no open side")
                    end
                end
            end
        end
        log("pitons gripped (direct)", ok, "of", n)
        -- The real thing: hang in the air in front of one and hold the button.
        local t = 0
        for i, sp in ipairs(spots) do
            if i > 3 then break end
            timer.Simple(t, function()
                P:SetPos(sp.pos) P:SetEyeAngles(sp.ang) P:SetLocalVelocity(vector_origin)
                net.Start("gk_pitontest") net.WriteUInt(IN_ATTACK, 32) net.WriteFloat(1.5) net.Send(P)
            end)
            timer.Simple(t + 1, function() log("held button at", sp.piece, "gripping", P:GetNW2Int("gk_hand_l", 0), "anchored", tostring(P:GetNW2Bool("gk_anchor_l", false))) end)
            t = t + 2
        end
        -- Bunnyhop (KZ): hold W and jump on open floor; speed shouldn't drop hop to hop.
        timer.Simple(t + 0.5, function()
            local spot = ents.FindByClass("info_player_start")[1]
            if spot then P:SetPos(spot:GetPos()) end
            P:SetEyeAngles(Angle(0, 0, 0)) GK.SetStamina(P, 100)
            net.Start("gk_pitontest") net.WriteUInt(bit.bor(IN_FORWARD, IN_JUMP), 32) net.WriteFloat(3) net.Send(P)
            local samples = {}
            for k = 1, 6 do timer.Simple(k * 0.5, function() samples[#samples + 1] = ("%.0f"):format(P:GetVelocity():Length2D()) end) end
            timer.Simple(3.2, function() log("kz", tostring(GK.KZ:GetBool()), "airaccelerate", GetConVar("sv_airaccelerate"):GetFloat(), "hop speeds", table.concat(samples, " ")) end)
        end)
        -- The garden's roach rotation.
        timer.Simple(t + 4, function()
            local spots = {}
            for _, e in ipairs(ents.FindByClass("info_target")) do if e:GetName() == "gk_gored_spawn" then spots[#spots + 1] = e end end
            local c = Vector() for _, e in ipairs(spots) do c:Add(e:GetPos()) end
            if #spots > 0 then c = c / #spots end
            local n = 0
            for _, r in ipairs(ents.FindInSphere(c, 900)) do if r:GetClass() == "gk_roach" then n = n + 1 end end
            log("garden spots", #spots, "roaches in the garden", n)
            -- A vending machine's wallet screen, then a slot machine spin.
            local v = ents.FindByClass("gk_vendor")[1]
            if v then
                P:SetNW2Int("gk_roaches", 23)
                P:SetPos(v:GetPos() + v:GetForward() * 70 - Vector(0, 0, 0))
                P:SetEyeAngles((v:GetPos() + Vector(0, 0, 70) - P:EyePos()):Angle())
            end
            local sm = ents.FindByClass("gk_slots")[1]
            log("slot machines", #ents.FindByClass("gk_slots"))
            if sm then
                timer.Simple(1.5, function()
                    P:SetPos(sm:GetPos() + sm:GetForward() * 70)
                    P:SetEyeAngles((sm:GetPos() + Vector(0, 0, 70) - P:EyePos()):Angle())
                    local before = GK.Roaches.Count(P)
                    sm:Press(P)
                    timer.Simple(3.2, function()
                        log("slot spin: roaches", before, "->", GK.Roaches.Count(P), "reels", sm:GetReel1(), sm:GetReel2(), sm:GetReel3())
                        -- (no screenshots)
                        log("DONE")
                    end)
                end)
            else
                log("DONE")
            end
        end)
    end)
end)
