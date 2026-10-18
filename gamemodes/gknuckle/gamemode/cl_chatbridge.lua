-- COMMUNiTY: lines from the gk.style web chat and other servers (sv_chatbridge.lua).
local cvShow = CreateClientConVar("gk_community_show", "1", true, false, "Show gk.style COMMUNiTY chat in game")
local AMBER, WEB, SRV, DIM = Color(255, 154, 31), Color(140, 200, 255), Color(150, 230, 150), Color(200, 200, 200)

local function strip(s, max)
    s = string.gsub(tostring(s or ""), "[%z\1-\31\127]", " ")
    if utf8.len(s) and utf8.len(s) > max then s = string.sub(s, 1, (utf8.offset(s, max + 1) or (#s + 1)) - 1) end
    return s
end

net.Receive("gk_community", function()
    local where, name, body, rank = net.ReadString(), strip(net.ReadString(), 48), strip(net.ReadString(), 300), strip(net.ReadString(), 12)
    if not cvShow:GetBool() then return end
    if where == "notice" then
        chat.AddText(AMBER, "[COMMUNiTY] ", DIM, body)
        return
    end
    local tag = "[COMMUNiTY] " -- where: "web" (a gk.style/Omerta user) or "server" (another game server's bot)
    local parts = { AMBER, tag }
    if rank ~= "" then parts[#parts + 1] = DIM parts[#parts + 1] = rank .. " " end
    -- N4: always say where a name comes from, so a web user called "server" or named
    -- like an in-game admin can't pass for one.
    parts[#parts + 1] = DIM
    parts[#parts + 1] = where == "web" and "web:" or "server:"
    parts[#parts + 1] = where == "web" and WEB or SRV
    parts[#parts + 1] = string.gsub(name, ":", "")
    parts[#parts + 1] = color_white
    parts[#parts + 1] = ": " .. body
    chat.AddText(unpack(parts))
end)
