if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Items.lua
--  The quest item bar: every usable quest item in your log on one movable
--  bar, with cooldowns, charges, range and keybinds.
--
--  The buttons are our own secure action buttons (type "item"), so clicking
--  them and their keybinds work in combat. Which items they hold can only
--  change out of combat; changes during a fight wait for it to end.
--  Keybinds: Key Bindings > AddOns > EvermoreUI > Quest Items (the binding
--  file lives in the core addon so it's always there).
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local issecret = ns.issecret

local MAX_BUTTONS = 12
local RANGE_EVERY = 0.2

local bar
local buttons = {}
local items = {}   -- what the bar should hold, in order
local shown = 0

local function Cfg() return M.db.items end

--------------------------------------------------------------------------------
--  What's in the log
--------------------------------------------------------------------------------
local function Collect()
    wipe(items)
    local cfg = Cfg()
    if not (cfg.enabled and GetQuestLogSpecialItemInfo) then return end
    local seen = {}
    ns.EachQuest(function(info, logIndex)
        local link, texture, charges, showWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
        if type(link) ~= "string" or issecret(link) then return end
        local questID = info.questID
        if ns.IsDone(questID) and not showWhenComplete then return end
        local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) ~= nil
        if cfg.trackedOnly and not watched then return end
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID and seen[itemID] then return end
        if itemID then seen[itemID] = true end
        items[#items + 1] = {
            questID = questID, logIndex = logIndex, link = link, itemID = itemID,
            texture = texture, charges = charges, watched = watched, title = info.title,
        }
    end)
    -- Tracked quests first, then log order.
    table.sort(items, function(a, b)
        if a.watched ~= b.watched then return a.watched end
        return a.logIndex < b.logIndex
    end)
    for i = #items, min(cfg.max, MAX_BUTTONS) + 1, -1 do items[i] = nil end
end

--------------------------------------------------------------------------------
--  Buttons
--------------------------------------------------------------------------------
local function LogIndex(b)
    return b.questID and C_QuestLog.GetLogIndexForQuestID(b.questID) or b.logIndex
end

local function UpdateCooldown(b)
    local idx = LogIndex(b)
    if not (idx and GetQuestLogSpecialItemCooldown) then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(idx)
    if start and not issecret(start) then
        CooldownFrame_Set(b.cd, start, duration, enable)
        local grey = duration and duration > 0 and enable == 0
        b.icon:SetDesaturated(grey and true or false)
    end
end

local function UpdateHotkey(b, i)
    local key = Cfg().hotkeys and GetBindingKey("CLICK EvermoreUIQuestItem" .. i .. ":LeftButton")
    b.hotkey:SetText(key and GetBindingText(key, 1) or "")
end

local function OnEnter(self)
    self.hover:Show()
    local idx = LogIndex(self)
    if not idx then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if not pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, idx) and self.link then
        GameTooltip:SetHyperlink(self.link)
    end
    if self.title then GameTooltip:AddLine(self.title, T.RGBA("textMuted")) end
    GameTooltip:Show()
end

local function OnLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

-- Range: red when out of range, like Blizzard's own quest item buttons.
local function OnUpdate(self, dt)
    self.range = (self.range or 0) - dt
    if self.range > 0 then return end
    self.range = RANGE_EVERY
    local idx = LogIndex(self)
    local valid = idx and IsQuestLogSpecialItemInRange and IsQuestLogSpecialItemInRange(idx)
    if valid == 0 then self.icon:SetVertexColor(EV.Theme.RGBA("danger")) else self.icon:SetVertexColor(1, 1, 1) end
end

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", "EvermoreUIQuestItem" .. i, bar, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b.well = T.Fill(b, "BACKGROUND", "surfaceSunk", 1)
    b.well:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.hover = T.Fill(b, "HIGHLIGHT", "accent", 0.18)
    b.hover:SetAllPoints(b.icon)
    b.hover:Hide()
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.count = T.Text(top, 11, "text", true, "RIGHT")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.hotkey = T.Text(top, 10, "textMuted", false, "RIGHT")
    b.hotkey:SetPoint("TOPRIGHT", -2, -2)
    T.TokenBorder(b, "borderStrong")
    function b:Paint()
        self.well:SetColorTexture(T.RGBA("surfaceSunk", 1))
        self.hover:SetColorTexture(T.RGBA("accent", 0.18))
        self.count:SetTextColor(T.RGBA("text"))
        self.hotkey:SetTextColor(T.RGBA("textMuted"))
        T.SetBorderToken(self, "borderStrong")
    end
    T.Watch(b)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", OnLeave)
    b:SetScript("OnUpdate", OnUpdate)
    buttons[i] = b
    return b
end

--- Fill the buttons that already show (cooldowns, charges, hotkeys). Safe
--- in combat: nothing secure changes.
local function Paint()
    for i = 1, shown do
        local b, it = buttons[i], items[i]
        if b and it then
            b.icon:SetTexture(it.texture)
            b.count:SetText(it.charges and it.charges > 1 and it.charges or "")
            UpdateCooldown(b)
            UpdateHotkey(b, i)
        end
    end
end

--- Re-seat the bar (out of combat only).
local function Layout()
    local cfg = Cfg()
    local n = cfg.enabled and #items or 0
    local per = max(1, min(cfg.perRow, max(n, 1)))
    local size, gap = cfg.size, cfg.spacing
    local rows = max(1, ceil(n / per))
    bar:SetSize(per * size + (per - 1) * gap, rows * size + (rows - 1) * gap)
    for i = 1, max(n, #buttons) do
        local it = items[i]
        if i <= n and it then
            local b = Button(i)
            b:ClearAllPoints()
            local r, c = floor((i - 1) / per), (i - 1) % per
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", c * (size + gap), -r * (size + gap))
            b:SetSize(size, size)
            b:SetAttribute("item", it.itemID and ("item:" .. it.itemID) or it.link)
            b.questID, b.logIndex, b.link, b.title = it.questID, it.logIndex, it.link, it.title
            b:Show()
        elseif buttons[i] then
            local b = buttons[i]
            b:SetAttribute("item", nil)
            b.questID, b.logIndex, b.link, b.title = nil, nil, nil, nil
            b:Hide()
        end
    end
    shown = n
    RegisterStateDriver(bar, "visibility", n > 0 and "[petbattle][vehicleui] hide; show" or "hide")
    EV.Movers:Apply("OBJ_items")
    Paint()
    -- The list shows each quest's item keybind; slots may have moved.
    if ns.RefreshList then ns.RefreshList() end
end

--- The keybind (short form) of the bar button holding a quest's item.
function ns.ItemKeyForQuest(questID)
    for i = 1, shown do
        local b = buttons[i]
        if b and b.questID == questID then
            local key = GetBindingKey("CLICK EvermoreUIQuestItem" .. i .. ":LeftButton")
            return key and GetBindingText(key, 1) or ""
        end
    end
    return ""
end

--- Has the set of items changed (not just charges or cooldowns)?
local function Signature()
    local parts = {}
    for i, it in ipairs(items) do parts[i] = (it.itemID or it.link) .. ":" .. it.questID end
    return table.concat(parts, ",")
end
local lastSig

function ns.RefreshItems(force)
    if not bar then return end
    Collect()
    local sig = Signature()
    if force or sig ~= lastSig then
        ns.Safe("items", function()
            Collect() -- the log may have moved on while we waited for combat to end
            lastSig = Signature()
            Layout()
        end)
    else
        -- Same items: indices, charges and cooldowns may still have moved.
        for i = 1, shown do
            local b, it = buttons[i], items[i]
            if b and it then b.logIndex = it.logIndex end
        end
        Paint()
    end
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local pending = false
events:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_COOLDOWN" then
        for i = 1, shown do if buttons[i] then UpdateCooldown(buttons[i]) end end
        return
    elseif event == "UPDATE_BINDINGS" then
        for i = 1, shown do if buttons[i] then UpdateHotkey(buttons[i], i) end end
        if ns.RefreshList then ns.RefreshList() end
        return
    end
    if pending then return end
    pending = true
    C_Timer.After(0.1, function()
        pending = false
        ns.RefreshItems()
    end)
end)

function ns.EnableItems()
    bar = CreateFrame("Frame", "EvermoreUIQuestItemBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetSize(40, 40)
    ns.itemBar = bar
    EV.Movers:Register(bar, "OBJ_items", L["Quest Items"], { "TOPRIGHT", "TOPRIGHT", -60, -215 }, {
        group = L["Objectives"], page = "objectives",
        isDisabled = function() return not Cfg().enabled end,
    })
    RegisterStateDriver(bar, "visibility", "hide")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "BAG_UPDATE_DELAYED",
                         "BAG_UPDATE_COOLDOWN", "UPDATE_BINDINGS", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, e)
    end
    ns.RefreshItems(true)
end
