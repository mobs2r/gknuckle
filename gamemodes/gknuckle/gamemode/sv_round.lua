-- Course rounds: race to a gk_finish. The first mind to reach it wins CrabCoin.
-- Rounds only run when there's a finish. On a course map (finish placed in
-- Hammer) the map resets between rounds; on sandbox maps like gm_construct
-- there are no rounds until someone spawns a finish, and builds are never wiped.

local cvRoundTime = CreateConVar("gk_round_time", "300", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Course round length in seconds")
local cvReward = CreateConVar("gk_finish_reward", "25", FCVAR_ARCHIVE + FCVAR_NOTIFY, "CrabCoin for finishing first")

GK.Round = GK.Round or { finishers = {} }

local function setRoundEnd(t)
    SetGlobal2Float("gk_round_end", t)
end

local function courseMap()
    for _, ent in ipairs(ents.FindByClass("gk_finish")) do
        if ent:CreatedByMap() then return true end
    end
    return false
end

function GK.Round.Start()
    if #ents.FindByClass("gk_finish") == 0 then
        GK.Round.active = false
        setRoundEnd(0)
        return
    end
    GK.Round.finishers = {}
    GK.Round.active = true
    if courseMap() then
        game.CleanUpMap()
        for _, ply in ipairs(player.GetAll()) do ply:Spawn() end
    end
    setRoundEnd(CurTime() + cvRoundTime:GetFloat())
    SetGlobal2Float("gk_round_start", CurTime())
    for _, ply in ipairs(player.GetAll()) do ply:SetNW2Float("gk_finish_time", 0) end
end

function GK.Round.End(reason)
    if not GK.Round.active then return end
    GK.Round.active = false
    PrintMessage(HUD_PRINTTALK, "[gKnuckle] Round over: " .. reason)
    timer.Simple(8, GK.Round.Start)
end

-- Best course times per map, kept in data/gknuckle/best_<map>.json.
local function bestPath() return "gknuckle/best_" .. game.GetMap() .. ".json" end

local function loadBest()
    return util.JSONToTable(file.Read(bestPath(), "DATA") or "") or {}
end

local function saveBest(best)
    file.CreateDir("gknuckle")
    file.Write(bestPath(), util.TableToJSON(best))
end

function GK.Round.Finish(ply)
    if not GK.Round.active or GK.Round.finishers[ply] then return end
    local place = table.Count(GK.Round.finishers) + 1
    GK.Round.finishers[ply] = place

    local time = CurTime() - GetGlobal2Float("gk_round_start", CurTime())
    ply:SetNW2Float("gk_finish_time", time)
    local best = loadBest()
    local id = ply:SteamID64() or ply:Nick()
    local pb = best[id] and best[id].time
    local note = ""
    if not pb or time < pb then
        best[id] = { name = ply:Nick(), time = time }
        saveBest(best)
        note = pb and " - new personal best!" or " - first clear!"
    end
    PrintMessage(HUD_PRINTTALK, ("[gKnuckle] %s finished #%d in %s%s"):format(
        ply:Nick(), place, string.FormattedTime(time, "%02i:%02i.%02i"), note))
    if place == 1 then
        GK.Economy.Add(ply, cvReward:GetInt(), "gknuckle_course_win")
    end
    if place >= #player.GetAll() then GK.Round.End("everyone made it") end
end

hook.Add("InitPostEntity", "GK_FirstRound", function()
    timer.Simple(2, GK.Round.Start)
end)

hook.Add("Think", "GK_RoundTimer", function()
    if GK.Round.active and CurTime() > GetGlobal2Float("gk_round_end", math.huge) then
        GK.Round.End("time")
    end
end)
