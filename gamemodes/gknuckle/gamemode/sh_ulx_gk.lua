-- Optional ULX commands. Does nothing unless ULX is installed; registers on Initialize
-- so it works whichever of ULX and the gamemode loads first.
if SERVER then AddCSLuaFile() end

local function register()
    if not (ulx and ulx.command and ULib and ULib.cmds) or GK.ULXRegistered then return end
    GK.ULXRegistered = true
    local CAT = "gKnuckle"

    local give = ulx.command(CAT, "ulx gkgive", function(calling, targets, amount, reason)
        if not GK.HasAccess(calling, "gknuckle.economy_admin") then return ULib.tsayError(calling, "You need gknuckle.economy_admin", true) end
        reason = string.sub(reason ~= "" and reason or "admin_grant", 1, 60)
        for _, t in ipairs(targets) do
            GK.Economy.Add(t, amount, "gknuckle_admin:" .. reason, GK.ApiAuth.EventId("ulx_give", t), true)
        end
        ulx.fancyLogAdmin(calling, "#A gave #T #s CrabCoin (#s)", targets, amount, reason)
    end, "!gkgive")
    give:addParam({ type = ULib.cmds.PlayersArg })
    give:addParam({ type = ULib.cmds.NumArg, min = 1, max = 1000, hint = "coins", ULib.cmds.round })
    give:addParam({ type = ULib.cmds.StringArg, hint = "reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine })
    give:defaultAccess(ULib.ACCESS_SUPERADMIN)
    give:help("Give CrabCoin to players (logged with an event id).")

    local take = ulx.command(CAT, "ulx gktake", function(calling, targets, amount, reason)
        if not GK.HasAccess(calling, "gknuckle.economy_admin") then return ULib.tsayError(calling, "You need gknuckle.economy_admin", true) end
        reason = string.sub(reason ~= "" and reason or "admin_take", 1, 60)
        for _, t in ipairs(targets) do GK.Economy.Deduct(t, amount, "gknuckle_admin:" .. reason) end
        ulx.fancyLogAdmin(calling, "#A took #s CrabCoin from #T (#s)", amount, targets, reason)
    end, "!gktake")
    take:addParam({ type = ULib.cmds.PlayersArg })
    take:addParam({ type = ULib.cmds.NumArg, min = 1, max = 100000, hint = "coins", ULib.cmds.round })
    take:addParam({ type = ULib.cmds.StringArg, hint = "reason", ULib.cmds.optional, ULib.cmds.takeRestOfLine })
    take:defaultAccess(ULib.ACCESS_SUPERADMIN)
    take:help("Take CrabCoin from players.")

    local arena = ulx.command(CAT, "ulx gkarena", function(calling, index)
        if not GK.HasAccess(calling, "gknuckle.runs") then return ULib.tsayError(calling, "You need gknuckle.runs", true) end
        game.ConsoleCommand("gk_arena_start " .. math.floor(index) .. "\n")
        ulx.fancyLogAdmin(calling, "#A started arena #s", index)
    end, "!gkarena")
    arena:addParam({ type = ULib.cmds.NumArg, min = 1, max = 8, default = 1, hint = "arena", ULib.cmds.optional, ULib.cmds.round })
    arena:defaultAccess(ULib.ACCESS_ADMIN)
    arena:help("Start a WK arena run.")

    local pack = ulx.command(CAT, "ulx gkpack", function(calling)
        if not GK.HasAccess(calling, "gknuckle.pack_status") then return end
        for _, p in ipairs(player.GetHumans()) do
            ULib.console(calling, ("%s ready=%s"):format(p:Nick(), tostring(p:GetNW2Bool("gk_pack_ready", false))))
        end
    end, "!gkpack")
    pack:defaultAccess(ULib.ACCESS_ADMIN)
    pack:help("Show who has the gKnuckle content pack.")
end

hook.Add("Initialize", "GK_ULXCommands", register)
if ulx then register() end
