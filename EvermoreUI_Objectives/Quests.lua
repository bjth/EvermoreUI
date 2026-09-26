if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Quests.lua
--  Quest state around the list: zone auto-tracking, alerts (sounds, toast,
--  flashes on the list), and the info strip (quest count, XP ready, quest
--  timers). The list itself is List.lua.
--
--  Zone tracking uses the ordinary watch API. It only ever untracks quests
--  it tracked itself, and respects you untracking one.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T, U = EV.Theme, EV.UI
local floor, max, min, format = math.floor, math.max, math.min, string.format
local issecret = ns.issecret

local TIMER_ROW = 16
local STRIP_TOP = 22

--------------------------------------------------------------------------------
--  Small helpers
--------------------------------------------------------------------------------
local function IsDone(questID)
    if type(questID) ~= "number" then return false end
    local ok, c = pcall(C_QuestLog.IsComplete, questID)
    if ok and c then return true end
    if C_QuestLog.ReadyForTurnIn then
        ok, c = pcall(C_QuestLog.ReadyForTurnIn, questID)
        return ok and c and true or false
    end
    return false
end

local function Watched(questID)
    return C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil
end

--- Every real quest in the log (no headers, hidden quests, tasks or bounties).
local function EachQuest(fn)
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and not info.isTask and not info.isBounty and info.questID then
            fn(info, i)
        end
    end
end
ns.EachQuest = EachQuest
ns.IsDone = IsDone


--------------------------------------------------------------------------------
--  Zone auto-tracking
--------------------------------------------------------------------------------
local declined = {} -- quests you untracked in this zone; left alone until you leave

local function MaxWatches()
    local c = Constants and Constants.QuestWatchConsts
    return c and c.MAX_QUEST_WATCHES or 25
end

function ns.UpdateZoneTracking()
    if not (C_QuestLog.AddQuestWatch and C_QuestLog.GetQuestWatchType) then return end
    local char = ns.Char()
    if type(char.auto) ~= "table" then char.auto = {} end
    local auto = char.auto
    if not M.db.zoneTrack then
        -- Switched off: hand back what we tracked.
        for id in pairs(auto) do
            if Watched(id) then C_QuestLog.RemoveQuestWatch(id) end
            auto[id] = nil
        end
        return
    end
    local here = {}
    EachQuest(function(info) if info.isOnMap then here[info.questID] = true end end)
    for id in pairs(auto) do
        if not here[id] then
            if Watched(id) then C_QuestLog.RemoveQuestWatch(id) end
            auto[id] = nil
        elseif not Watched(id) then
            declined[id] = true
            auto[id] = nil
        end
    end
    local limit = MaxWatches()
    for id in pairs(here) do
        if not declined[id] and not Watched(id) and (C_QuestLog.GetNumQuestWatches() or 0) < limit then
            if C_QuestLog.AddQuestWatch(id) then auto[id] = true end
        end
    end
end

--------------------------------------------------------------------------------
--  Alerts
--------------------------------------------------------------------------------
local snapshot

local function Snapshot()
    local s = {}
    EachQuest(function(info)
        local done, total = 0, 0
        local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(info.questID)
        if type(objs) == "table" then
            for _, o in ipairs(objs) do
                total = total + 1
                if o.finished then done = done + 1 end
            end
        end
        s[info.questID] = { done = done, total = total, complete = IsDone(info.questID), title = info.title }
    end)
    return s
end

local toast
local function BuildToast()
    if not toast then
        toast = CreateFrame("Frame", "EvermoreUIObjectivesToast", UIParent)
        toast:SetSize(280, 46)
        toast:SetFrameStrata("HIGH")
        toast.bg = T.Fill(toast, "BACKGROUND", "surface1", 0.95)
        toast.bg:SetAllPoints()
        T.TokenBorder(toast, "border")
        toast.edge = T.Fill(toast, "BORDER", "success", 1)
        toast.edge:SetPoint("TOPLEFT")
        toast.edge:SetPoint("BOTTOMLEFT")
        toast.edge:SetWidth(3)
        toast.title = U.Label(toast, "", "success", "small", true)
        toast.title:SetPoint("TOPLEFT", 12, -8)
        toast.text = U.Label(toast, "", "text", "body")
        toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -3)
        toast.text:SetPoint("RIGHT", -10, 0)
        function toast:Paint()
            self.bg:SetColorTexture(T.RGBA("surface1", 0.95))
            self.edge:SetColorTexture(T.RGBA("success", 1))
            T.SetBorderToken(self, "border")
        end
        T.Watch(toast)
        toast:SetAlpha(0)
        toast:Hide()
        toast:SetScript("OnUpdate", function(self, dt)
            self.t = self.t + dt
            local t = self.t
            if t < 0.2 then self:SetAlpha(t / 0.2)
            elseif t < 3.2 then self:SetAlpha(1)
            elseif t < 3.8 then self:SetAlpha(1 - (t - 3.2) / 0.6)
            else self:SetAlpha(0); self:Hide() end
        end)
        EV.Movers:Register(toast, "OBJ_toast", L["Quest Alerts"], { "TOP", "TOP", 0, -180 }, {
            group = L["Objectives"], page = "objectives",
            isDisabled = function() return not M.db.toast end,
        })
    end
end

local function Toast(title, text)
    BuildToast()
    toast.title:SetText(title)
    toast.text:SetText(text or "")
    toast.t = 0
    toast:Show()
end
ns.Toast = Toast

local function Sound(kit, fallback)
    local id = SOUNDKIT and SOUNDKIT[kit] or fallback
    if id then PlaySound(id) end
end

local function CheckAlerts()
    local now = Snapshot()
    local before = snapshot
    snapshot = now
    if not before then return end
    local quest, objective
    for id, q in pairs(now) do
        local o = before[id]
        if o then
            if q.complete and not o.complete then
                quest = quest or q
                if ns.FlashQuest then ns.FlashQuest(id) end
            elseif q.done > o.done then
                objective = objective or q
                if ns.FlashQuest then ns.FlashQuest(id) end
            end
        end
    end
    if quest then
        if M.db.soundQuest then Sound("IG_QUEST_LIST_COMPLETE", 878) end
        if M.db.toast then Toast(L["Quest complete"], quest.title) end
    elseif objective and M.db.soundObjective then
        Sound("IG_QUEST_LIST_SELECT", 875)
    end
end

--------------------------------------------------------------------------------
--  Info strip: quest count, XP ready, timers
--------------------------------------------------------------------------------
local timers = {}

local function FetchTimers()
    wipe(timers)
    if not M.db.timers then return end
    local list
    if C_QuestLog.GetQuestTimers then
        local ok, r = pcall(C_QuestLog.GetQuestTimers)
        list = ok and r
    end
    for _, t in ipairs(type(list) == "table" and list or {}) do
        local left = t.questTimer
        if t.questID and type(left) == "number" and not issecret(left) and left > 0 then
            timers[#timers + 1] = {
                questID = t.questID,
                title = C_QuestLog.GetTitleForQuestID(t.questID) or "",
                ends = GetTime() + left,
            }
        end
    end
end

function ns.TimerCount() return #timers end

local function Clock(s)
    s = max(0, floor(s + 0.5))
    if s >= 3600 then return format("%d:%02d:%02d", floor(s / 3600), floor(s / 60) % 60, s % 60) end
    return format("%d:%02d", floor(s / 60), s % 60)
end

local function QuestCount()
    local n = 0
    EachQuest(function() n = n + 1 end)
    local cap = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or MAX_QUESTS or 35
    return n, cap
end

local function ReadyXP()
    if not GetQuestLogRewardXP then return 0 end
    local xp = 0
    EachQuest(function(info)
        if IsDone(info.questID) then
            local ok, v = pcall(GetQuestLogRewardXP, info.questID)
            if ok and type(v) == "number" and not issecret(v) then xp = xp + v end
        end
    end)
    return xp
end

local function TimerRow(strip, i)
    local row = strip.timers[i]
    if row then return row end
    row = CreateFrame("Frame", nil, strip)
    row:SetHeight(TIMER_ROW)
    row:SetPoint("TOPLEFT", 8, -STRIP_TOP - (i - 1) * TIMER_ROW)
    row:SetPoint("TOPRIGHT", -8, -STRIP_TOP - (i - 1) * TIMER_ROW)
    row.time = U.Label(row, "", "warning", "small", true)
    row.time:SetPoint("RIGHT")
    row.name = U.Label(row, "", "text", "small")
    row.name:SetPoint("LEFT")
    row.name:SetPoint("RIGHT", row.time, "LEFT", -6, 0)
    strip.timers[i] = row
    return row
end

local function PaintTimers()
    local strip = ns.strip
    if not strip then return end
    local now = GetTime()
    for i, t in ipairs(timers) do
        local row = TimerRow(strip, i)
        local left = t.ends - now
        row.name:SetText(t.title)
        row.time:SetText(Clock(left))
        row.time:SetTextColor(T.RGBA(left < 60 and "danger" or "warning"))
        row:Show()
    end
    for i = #timers + 1, #strip.timers do strip.timers[i]:Hide() end
end

function ns.UpdateStrip()
    local strip = ns.strip
    if not strip then return end
    if M.db.infoStrip then
        local n, cap = QuestCount()
        strip.left:SetText(format(L["Quests %d/%d"], n, cap))
        strip.left:SetTextColor(T.RGBA(n >= cap and "danger" or "textMuted"))
        local xp = ReadyXP()
        strip.right:SetText(xp > 0 and format(L["%s XP to hand in"], BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)) or "")
    else
        strip.left:SetText("")
        strip.right:SetText("")
    end
    PaintTimers()
end

-- A one-second clock while timers run; the list itself only changes on
-- quest log updates.
local ticker
local function Tick()
    local before = #timers
    for i = #timers, 1, -1 do
        if timers[i].ends <= GetTime() then table.remove(timers, i) end
    end
    if #timers ~= before then ns.Layout() else PaintTimers() end
    if #timers == 0 and ticker then ticker:Cancel(); ticker = nil end
end
local function StartTicker()
    if #timers > 0 and not ticker then ticker = C_Timer.NewTicker(1, Tick) end
end

--- Blizzard's own timer window (Camelot's) steps aside while ours shows.
--- It lives in the right-hand column; parking it also drops the top gap it
--- adds to the tracker.
local timerParent
function ns.ApplyTimerFrame()
    local f = QuestTimerFrame
    if not f then return end
    ns.Safe("timerFrame", function()
        if M.db.timers then
            if f:GetParent() ~= ns.hiddenParent then
                timerParent = timerParent or f:GetParent()
                f:SetParent(ns.hiddenParent)
            end
        elseif timerParent and f:GetParent() == ns.hiddenParent then
            f:SetParent(timerParent)
        end
    end)
end

--------------------------------------------------------------------------------
--  Settings and events
--------------------------------------------------------------------------------
--- Earlier builds drew levels and colours through Blizzard's CVars, which
--- also changed the quest log. The list draws its own now; put the CVars
--- back to Blizzard's defaults once.
local function RestoreCVars()
    if M.db.cvarsRestored then return end
    M.db.cvarsRestored = true
    local get = C_CVar and C_CVar.GetCVarDefault
    for _, name in ipairs({ "showQuestLevel", "showQuestDifficultyColor" }) do
        local def = get and get(name)
        if def ~= nil and GetCVar and GetCVar(name) ~= def then pcall(SetCVar, name, def) end
    end
end

function ns.ApplyQuestSettings()
    ns.Safe("cvars", RestoreCVars)
    ns.UpdateZoneTracking()
    ns.ApplyTimerFrame()
    FetchTimers()
    StartTicker()
    if ns.Layout then ns.Layout() end
end

local events = CreateFrame("Frame")
local logPending = false
local function OnQuestLog()
    if logPending then return end
    logPending = true
    C_Timer.After(0.2, function()
        logPending = false
        CheckAlerts()
        ns.UpdateZoneTracking()
        local had = #timers
        FetchTimers()
        StartTicker()
        if had ~= #timers or had > 0 then ns.Layout() else ns.UpdateStrip() end
    end)
end

events:SetScript("OnEvent", function(_, event)
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        wipe(declined)
        C_Timer.After(1, ns.UpdateZoneTracking) -- the map settles a moment after
    else
        OnQuestLog()
    end
end)

function ns.EnableQuests()
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, e)
    end
    BuildToast() -- registered up front so /evui edit can place it
    snapshot = Snapshot()
    ns.ApplyQuestSettings()
end
