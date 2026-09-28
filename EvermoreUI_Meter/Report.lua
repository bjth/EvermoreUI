if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Report.lua
--  A window's top lines, to chat:
--
--    EvermoreUI: Damage Done, Current (1:42)
--    1. Name 124.5K (1.2K)
--    2. Name 98.1K (962)
--
--  Out of combat only: in combat the values are secret, and a secret can't
--  be written into a chat message. The number of lines is the options
--  page's; a whisper goes to your target.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
local M = ns.module
if not (EV and M) then return end
local L = EV.L

ns.REPORT_CHANNELS = {
    { value = "SAY", text = _G.SAY or L["Say"] },
    { value = "PARTY", text = _G.PARTY or L["Party"] },
    { value = "RAID", text = _G.RAID or L["Raid"] },
    { value = "INSTANCE_CHAT", text = _G.INSTANCE_CHAT or L["Instance"] },
    { value = "GUILD", text = _G.GUILD or L["Guild"] },
    { value = "WHISPER", text = L["Whisper your target"] },
}

local function Send(text, channel, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, channel, nil, target)
    elseif SendChatMessage then
        SendChatMessage(text, channel, nil, target)
    end
end

local function Plain(v, rate)
    local s = ns.Short(v, rate)
    return EV.Usable(s) and tostring(s) or "?"
end

function ns.Report(win, channel)
    if InCombatLockdown() then
        EV:Print(L["The meter can report once combat ends."])
        return
    end
    local target
    if channel == "WHISPER" then
        if not UnitIsPlayer("target") then
            EV:Print(L["Target a player to whisper the report to."])
            return
        end
        target = GetUnitName("target", true)
    end
    local s = ns.Session(win)
    local sources = s and s.combatSources or {}
    if #sources == 0 then
        EV:Print(L["Nothing to report yet."])
        return
    end
    for _, src in ipairs(sources) do
        if not EV.Usable(src.totalAmount) or not EV.Usable(src.name) then
            EV:Print(L["The meter can report once combat ends."])
            return
        end
    end

    local mode = win.db.mode
    local fight = win.sessionID and (L["Fight"] .. " " .. win.sessionID)
        or (win.db.session == "overall" and L["Overall"] or L["Current"])
    local clock = ns.Clock(s.durationSeconds)
    local head = ("EvermoreUI: %s, %s"):format(ns.TypeName(mode), fight)
    if clock then head = head .. (" (%s)"):format(clock) end
    Send(head, channel, target)

    local lines = math.max(1, math.min(M.db.reportLines or 5, 25))
    for i = 1, math.min(lines, #sources) do
        local src = sources[i]
        local main, paren = src.totalAmount, src.amountPerSecond
        if ns.PER_SECOND_FIRST[mode] then main, paren = src.amountPerSecond, src.totalAmount end
        if ns.NO_PER_SECOND[mode] then paren = nil end
        local rate = ns.PER_SECOND_FIRST[mode] and true or false
        local line = ("%d. %s %s"):format(i, ns.Name(src.name), Plain(main, rate))
        if paren ~= nil then line = line .. (" (%s)"):format(Plain(paren, not rate)) end
        Send(line, channel, target)
    end
end
