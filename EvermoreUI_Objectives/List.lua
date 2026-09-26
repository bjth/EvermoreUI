if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  List.lua
--  Our own quest list: section headers with their own collapse, quest rows
--  (marker, level and tags, difficulty colour, objectives, progress bars),
--  auto quest pop-ups, tooltips, clicks and the right-click menu.
--
--  Everything here is our own frames reading the quest log, so there's no
--  Blizzard layout to fight and no taint to worry about: the list never
--  touches Blizzard's tracker. Blizzard's quest and campaign sections are
--  hidden in Panel.lua; its other sections (scenarios, world quests and so
--  on) still show below us.
--
--  Quest items: a secure item button down the right of the row, the full
--  height of the row, so it's easy to hit. A secure button makes the whole
--  list a protected frame, which can't be moved, resized or scrolled in
--  combat. So while you're in combat and a row has an item, rows keep their
--  places and only their text, colours and progress update; anything that
--  needs a re-layout waits for combat to end. With no item buttons on show
--  the list isn't protected and redraws normally in combat.
--
--  Clicks follow Blizzard's tracker: click opens the quest on the map (or
--  completes an auto-complete quest), shift-click untracks, a chat-link
--  click links it, right-click opens the menu.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T, U = EV.Theme, EV.UI
local floor, max, min, format = math.floor, math.max, math.min, string.format
local issecret = ns.issecret

local MARK = 12          -- quest marker
local TITLE_X = 22       -- title indent (marker sits left of it)
local OBJ_X = 30         -- objective indent
local HEADER_H = 22
local BLOCK_GAP = 5
local LINE_GAP = 2
local BAR_H = 3
local ITEM_W = 34        -- the row's item button: this wide, the row's full height
local SCROLLBAR = 12     -- always reserved, so text never rewraps when the bar appears

local list
local pools = { header = {}, block = {}, popup = {} }
local counts = { header = 0, block = 0, popup = 0 }
local flashes = {}       -- questID -> time the flash started
local height = 0

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------
local function Watched(id)
    return C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil
end

local function Str(s, fallback) return (type(s) == "string" and s ~= "") and s or fallback end

local function Width() return M.db.width - 2 - SCROLLBAR end
ns.ListWidth = Width

local TAGS
local function TagLetters()
    if TAGS then return TAGS end
    TAGS = {}
    local E = Enum and Enum.QuestTag
    if E then
        local map = { Group = "G", Dungeon = "D", Raid = "R", Raid10 = "R", Raid25 = "R",
                      PvP = "P", Heroic = "H", Scenario = "S", Delve = "Dv" }
        for k, v in pairs(map) do if E[k] then TAGS[E[k]] = v end end
    end
    return TAGS
end

local function TagInfo(id)
    if not C_QuestLog.GetQuestTagInfo then return nil end
    local ok, info = pcall(C_QuestLog.GetQuestTagInfo, id)
    return ok and type(info) == "table" and info or nil
end

local function Tag(id)
    local info = TagInfo(id)
    if not info then return "" end
    return (TagLetters()[info.tagID] or "") .. (info.isElite and "+" or "")
end

local function Level(q)
    local lvl = q.info.difficultyLevel
    if not lvl or lvl == 0 then lvl = q.info.level end
    return lvl
end

local function DifficultyRGB(id)
    if not (GetDifficultyColor and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer) then return nil end
    local ok, c = pcall(function() return GetDifficultyColor(C_PlayerInfo.GetContentDifficultyQuestForPlayer(id)) end)
    if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
end

local function IsCampaign(info)
    if info.campaignID and info.campaignID ~= 0 then return true end
    local E = Enum and Enum.QuestClassification
    return E and E.Campaign and info.questClassification == E.Campaign or false
end

local function SuperTracked()
    return C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() or 0
end

--------------------------------------------------------------------------------
--  Data: the quests to show, grouped and sorted
--------------------------------------------------------------------------------
local function Collect()
    local quests = {}
    local watchIndex = {}
    for i = 1, (C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() or 0) do
        local id = C_QuestLog.GetQuestIDForQuestWatchIndex and C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if id then watchIndex[id] = i end
    end
    local header
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif info.questID and not info.isHidden and not info.isTask and not info.isBounty then
                local id = info.questID
                local watched = watchIndex[id] ~= nil or Watched(id)
                if watched or M.db.source == "all" then
                    quests[#quests + 1] = {
                        id = id, logIndex = i, info = info, zone = header, watched = watched,
                        watchIndex = watchIndex[id] or (1000 + i),
                        done = ns.IsDone(id), campaign = IsCampaign(info),
                    }
                end
            end
        end
    end
    return quests
end

local function SortKey(q)
    local mode = M.db.sort
    if mode == "distance" and C_QuestLog.GetDistanceSqToQuest then
        local d = C_QuestLog.GetDistanceSqToQuest(q.id)
        return (type(d) == "number" and not issecret(d)) and d or math.huge
    elseif mode == "level" then
        return Level(q) or 0
    end
    return q.watchIndex
end

local function ByKey(a, b)
    if a.watched ~= b.watched then return a.watched end
    if a.key ~= b.key then return a.key < b.key end
    return a.logIndex < b.logIndex
end

-- The quests as last drawn, in drawn order: the distance ticker re-sorts
-- these (no API tables, no garbage) and only redraws if the order moved.
local drawn, resort = {}, {}

local function Sections(quests)
    for _, q in ipairs(quests) do q.key = SortKey(q) end
    table.sort(quests, ByKey)
    wipe(drawn)
    for i, q in ipairs(quests) do drawn[i] = q end
    local mode = M.db.grouping
    local sections, byKey = {}, {}
    local here = GetRealZoneText and GetRealZoneText() or nil
    for rank, q in ipairs(quests) do
        local key, title
        if mode == "zone" then
            key = "zone:" .. (q.zone or "?")
            title = q.zone or L["Other"]
        elseif mode == "campaign" then
            key = q.campaign and "campaign" or "quests"
            title = q.campaign and Str(TRACKER_HEADER_CAMPAIGN_QUESTS, L["Campaign"]) or Str(TRACKER_HEADER_QUESTS, L["Quests"])
        else
            key = "quests"
            title = Str(TRACKER_HEADER_QUESTS, L["Quests"])
        end
        local s = byKey[key]
        if not s then
            s = { key = key, title = title, quests = {}, rank = rank, here = (mode == "zone" and q.zone == here) }
            byKey[key] = s
            sections[#sections + 1] = s
        end
        s.quests[#s.quests + 1] = q
    end
    table.sort(sections, function(a, b)
        if a.here ~= b.here then return a.here end
        if mode == "campaign" and a.key ~= b.key then return a.key == "campaign" end
        return a.rank < b.rank
    end)
    return sections
end

--------------------------------------------------------------------------------
--  Pooled rows
--------------------------------------------------------------------------------
local function Acquire(kind, make)
    counts[kind] = counts[kind] + 1
    local f = pools[kind][counts[kind]]
    if not f then
        f = make()
        pools[kind][counts[kind]] = f
    end
    f:Show()
    return f
end

local function ReleaseRest()
    for kind, list in pairs(pools) do
        for i = counts[kind] + 1, #list do list[i]:Hide() end
    end
end

--------------------------------------------------------------------------------
--  Section headers
--------------------------------------------------------------------------------
local function Collapsed(key)
    local c = ns.Char()
    if type(c.sections) ~= "table" then c.sections = {} end
    return c.sections[key] == true
end

local function NewHeader()
    local h = CreateFrame("Button", nil, list)
    h:SetHeight(HEADER_H)
    h.bg = T.Fill(h, "BACKGROUND", "surface1", 0.9)
    h.bg:SetAllPoints()
    h.line = T.Fill(h, "BORDER", "accent", 0.9)
    h.line:SetPoint("BOTTOMLEFT")
    h.line:SetPoint("BOTTOMRIGHT")
    h.line:SetHeight(1)
    h.hover = T.Fill(h, "HIGHLIGHT", "accent", 0.08)
    h.hover:SetAllPoints()
    h.chev = T.Chevron(h, 4, 0.8)
    h.chev:SetPoint("LEFT", 8, 0)
    -- Text sits a pixel above the geometric middle: Barlow's glyphs ride low
    -- in their line box, and the accent line takes the bottom pixel.
    local lift = EV.Pixel:One(h)
    h.text = U.Label(h, "", "title", "small", true)
    h.text:SetPoint("LEFT", 22, lift)
    -- Counts in a fixed column, centred: digits are proportional in Barlow,
    -- so right-aligning left a narrow "1" looking out of line.
    h.count = U.Label(h, "", "textMuted", "small")
    h.count:SetPoint("RIGHT", -6, lift)
    h.count:SetWidth(22)
    h.count:SetJustifyH("CENTER")
    h.text:SetPoint("RIGHT", h.count, "LEFT", -4, 0)
    h.text:SetJustifyH("LEFT")
    function h:Paint()
        self.bg:SetColorTexture(T.RGBA("surface1", 0.9))
        self.line:SetColorTexture(T.RGBA("accent", 0.9))
        self.hover:SetColorTexture(T.RGBA("accent", 0.08))
        self.chev:SetColorLines(T.RGBA("textMuted"))
    end
    T.Watch(h)
    h:Paint()
    h:SetScript("OnClick", function(self)
        local c = ns.Char()
        if type(c.sections) ~= "table" then c.sections = {} end
        c.sections[self.key] = not c.sections[self.key] or nil
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        ns.RefreshList(true)
    end)
    return h
end

--------------------------------------------------------------------------------
--  Quest blocks
--------------------------------------------------------------------------------
local function OnMarkerClick(self)
    local id = self:GetParent().questID
    if not id or not C_SuperTrack then return end
    C_SuperTrack.SetSuperTrackedQuestID(SuperTracked() == id and 0 or id)
end

local function Menu(owner, id)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(C_QuestLog.GetTitleForQuestID(id) or "")
        if SuperTracked() ~= id then
            root:CreateButton(Str(SUPER_TRACK_QUEST, L["Focus this quest"]), function() C_SuperTrack.SetSuperTrackedQuestID(id) end)
        else
            root:CreateButton(Str(STOP_SUPER_TRACK_QUEST, L["Stop focusing"]), function() C_SuperTrack.SetSuperTrackedQuestID(0) end)
        end
        if QuestUtil and QuestUtil.OpenQuestDetails then
            local showing = QuestUtil.IsShowingQuestDetails and QuestUtil.IsShowingQuestDetails(id)
            root:CreateButton(Str(showing and OBJECTIVES_HIDE_VIEW_IN_QUESTLOG or OBJECTIVES_VIEW_IN_QUESTLOG, L["Quest details"]),
                function() QuestUtil.OpenQuestDetails(id) end)
        end
        if QuestMapFrame_OpenToQuestDetails then
            root:CreateButton(Str(OBJECTIVES_SHOW_QUEST_MAP, L["Show on map"]), function() QuestMapFrame_OpenToQuestDetails(id) end)
        end
        if Watched(id) then
            if not (QuestUtil and QuestUtil.CanRemoveQuestWatch) or QuestUtil.CanRemoveQuestWatch() then
                root:CreateButton(Str(OBJECTIVES_STOP_TRACKING, L["Untrack"]), function() C_QuestLog.RemoveQuestWatch(id) end)
            end
        else
            root:CreateButton(L["Track"], function() C_QuestLog.AddQuestWatch(id) end)
        end
        if C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(id) and IsInGroup() and QuestUtil and QuestUtil.ShareQuest then
            root:CreateButton(Str(SHARE_QUEST, L["Share"]), function() QuestUtil.ShareQuest(id) end)
        end
        if GetQuestLink then
            root:CreateButton(Str(SHARE_IN_CHAT, L["Link in chat"]), function()
                local link = GetQuestLink(id)
                if link and ChatFrameUtil and not ChatFrameUtil.InsertLink(link) then ChatFrameUtil.OpenChat(link) end
            end)
        end
        if QuestMapQuestOptions_AbandonQuest then
            root:CreateButton(Str(ABANDON_QUEST_ABBREV, L["Abandon"]), function() QuestMapQuestOptions_AbandonQuest(id) end)
        end
    end)
end

local function OnBlockClick(self, button)
    local id = self.questID
    if not id then return end
    if ChatFrameUtil and ChatFrameUtil.TryInsertQuestLinkForQuestID and ChatFrameUtil.TryInsertQuestLinkForQuestID(id) then return end
    if button == "RightButton" then return Menu(self, id) end
    if IsModifiedClick("QUESTWATCHTOGGLE") then
        if Watched(id) then
            if not (QuestUtil and QuestUtil.CanRemoveQuestWatch) or QuestUtil.CanRemoveQuestWatch() then C_QuestLog.RemoveQuestWatch(id) end
        else
            C_QuestLog.AddQuestWatch(id)
        end
        return
    end
    if self.autoComplete and ns.IsDone(id) and ShowQuestComplete then
        if RemoveAutoQuestPopUp then RemoveAutoQuestPopUp(id) end
        ShowQuestComplete(id)
        return
    end
    if QuestMapFrame_OpenToQuestDetails then QuestMapFrame_OpenToQuestDetails(id) end
end

local function Tooltip(self)
    local id, q = self.questID, self.quest
    if not (id and q) then return end
    local left = (self:GetCenter() or 0) > (UIParent:GetWidth() / 2)
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if left then GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -10, 0)
    else GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 10, 0) end
    local r, g, b = DifficultyRGB(id)
    GameTooltip:AddLine(q.info.title or "", r or 1, g or 0.82, b or 0, true)
    local bits = {}
    local lvl = Level(q)
    if lvl and lvl > 0 then bits[#bits + 1] = format(L["Level %d"], lvl) end
    local tag = TagInfo(id)
    if tag and tag.tagName then bits[#bits + 1] = tag.tagName end
    if q.zone then bits[#bits + 1] = q.zone end
    if #bits > 0 then GameTooltip:AddLine(table.concat(bits, "  |  "), T.RGBA("textMuted")) end
    local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    if type(objs) == "table" and #objs > 0 then
        GameTooltip:AddLine(" ")
        for _, o in ipairs(objs) do
            local cr, cg, cb = T.RGBA(o.finished and "success" or "text")
            GameTooltip:AddLine((o.finished and "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t " or "- ") .. (o.text or ""), cr, cg, cb, true)
        end
    end
    if GetQuestLogRewardXP then
        local ok, xp = pcall(GetQuestLogRewardXP, id)
        if ok and type(xp) == "number" and xp > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(format(L["%s XP"], EV.FormatNumber(xp)), T.RGBA("accent"))
        end
    end
    if IsInGroup() and QuestUtils_GetNumPartyMembersOnQuest then
        local n = QuestUtils_GetNumPartyMembersOnQuest(id)
        if n and n > 0 then GameTooltip:AddLine(format(L["%d party members on this quest"], n), T.RGBA("textMuted")) end
    end
    GameTooltip:AddLine(" ")
    local hint = { T.RGBA("textDisabled") }
    GameTooltip:AddLine(L["Click: show on map   Shift-click: untrack"], hint[1], hint[2], hint[3])
    GameTooltip:AddLine(L["Right-click: options   Marker: focus"], hint[1], hint[2], hint[3])
    GameTooltip:Show()
end

local function NewBlock()
    local b = CreateFrame("Button", nil, list)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.hover = T.Fill(b, "BACKGROUND", "surface2", 0)
    b.hover:SetAllPoints()
    b.flash = T.Fill(b, "BORDER", "accent", 0)
    b.flash:SetAllPoints()
    -- Marker: focus (super track) toggle. Dot in progress, ring when focused,
    -- filled gold with ? when ready to hand in.
    b.mark = CreateFrame("Button", nil, b)
    b.mark:SetSize(MARK + 6, MARK + 6)
    b.mark:SetPoint("TOPLEFT", 3, -1)
    b.mark.ring = U.Glyph(b.mark, "ring", MARK, "ARTWORK")
    b.mark.ring:SetPoint("CENTER")
    b.mark.dot = U.Glyph(b.mark, "circle", 6, "OVERLAY")
    b.mark.dot:SetPoint("CENTER")
    b.mark.q = b.mark:CreateFontString(nil, "OVERLAY")
    b.mark.q:SetFont(EV.Media:Fetch("font"), 10, "")
    b.mark.q:SetPoint("CENTER", 0, 0)
    b.mark.q:SetText("?")
    b.mark:SetScript("OnClick", OnMarkerClick)
    b.mark:SetScript("OnEnter", function(self)
        T.ShowTooltip(self, L["Focus"], L["Points your map and minimap arrow at this quest."])
    end)
    b.mark:SetScript("OnLeave", T.HideTooltip)
    b.title = T.Text(b, "body", "text", true)
    b.title:SetWordWrap(true)
    b.title:SetJustifyH("LEFT")
    b.lines = {}
    b:SetScript("OnClick", OnBlockClick)
    b:SetScript("OnEnter", function(self)
        self.hover:SetColorTexture(T.RGBA("surface2", 0.6))
        Tooltip(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.hover:SetColorTexture(T.RGBA("surface2", 0))
        GameTooltip:Hide()
    end)
    return b
end

local function Line(b, i)
    local ln = b.lines[i]
    if ln then return ln end
    ln = {}
    ln.text = T.Text(b, "small", "text")
    ln.text:SetWordWrap(true)
    ln.text:SetJustifyH("LEFT")
    ln.dash = T.Text(b, "small", "textMuted")
    ln.dash:SetText("-")
    ln.bar = CreateFrame("StatusBar", nil, b)
    ln.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    ln.bar:SetHeight(BAR_H)
    ln.bar.bg = ln.bar:CreateTexture(nil, "BACKGROUND")
    ln.bar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    ln.bar.bg:SetAllPoints()
    b.lines[i] = ln
    return ln
end

--- The lines under a quest's title: { text, role, done, cur, total }.
local function Objectives(q)
    local id, out = q.id, {}
    if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then
        out[1] = { text = Str(FAILED, L["Failed"]), role = "danger" }
        return out
    end
    if q.done then
        local text
        if q.info.isAutoComplete then
            text = Str(QUEST_WATCH_CLICK_TO_COMPLETE, L["Click to complete"])
        else
            text = GetQuestLogCompletionText and GetQuestLogCompletionText(q.logIndex)
            text = Str(text, Str(QUEST_WATCH_QUEST_READY, L["Ready for turn-in"]))
        end
        out[1] = { text = text, role = "success" }
        return out
    end
    if SuperTracked() == id and C_QuestLog.GetNextWaypointText then
        local w = C_QuestLog.GetNextWaypointText(id)
        if type(w) == "string" and w ~= "" then out[#out + 1] = { text = w, role = "accent" } end
    end
    local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    for _, o in ipairs(type(objs) == "table" and objs or {}) do
        if not (o.finished and M.db.finished == "hide") then
            local line = { text = o.text or "", role = "text", done = o.finished }
            if o.type == "progressbar" and GetQuestProgressBarPercent then
                local pct = GetQuestProgressBarPercent(id) or 0
                line.cur, line.total = pct, 100
                if not line.text:find("%%") then line.text = format("%s (%d%%)", line.text, floor(pct + 0.5)) end
            elseif (o.numRequired or 0) > 1 then
                line.cur, line.total = o.numFulfilled or 0, o.numRequired
            end
            out[#out + 1] = line
        end
    end
    local need = C_QuestLog.GetRequiredMoney and C_QuestLog.GetRequiredMoney(id) or 0
    if need and need > 0 and GetMoney() < need and GetMoneyString then
        out[#out + 1] = { text = GetMoneyString(GetMoney()) .. " / " .. GetMoneyString(need), role = "text" }
    end
    if #out == 0 then
        -- No objective text (some quests only have a description): say where to go.
        out[1] = { text = Str(q.info.title and C_QuestLog.GetNextWaypointText and C_QuestLog.GetNextWaypointText(id), L["In progress"]), role = "textMuted" }
    end
    return out
end

local function TitleText(q)
    local s = q.info.title or ""
    local lvl, tag = Level(q), (M.db.tags and Tag(q.id) or "")
    if M.db.levels and lvl and lvl > 0 then
        s = "[" .. lvl .. tag .. "] " .. s
    elseif tag ~= "" then
        s = "[" .. tag .. "] " .. s
    end
    return s
end

local function PaintMarker(b, q)
    local m = b.mark
    local focused = SuperTracked() == q.id
    if q.done then
        m.ring:SetVertexColor(T.RGBA("warning"))
        m.dot:SetSize(MARK - 2, MARK - 2)
        m.dot:SetVertexColor(T.RGBA("warning"))
        m.q:Show()
        m.q:SetTextColor(T.RGBA("onAccent"))
    else
        m.q:Hide()
        m.dot:SetSize(6, 6)
        m.ring:SetVertexColor(T.RGBA(focused and "accent" or "borderStrong"))
        m.dot:SetVertexColor(T.RGBA(focused and "accent" or "textMuted"))
    end
    m.ring:SetShown(focused or q.done)
    m.ring:SetAlpha(1)
end

--------------------------------------------------------------------------------
--  Row item buttons (secure)
--------------------------------------------------------------------------------
-- Unused buttons wait here, outside the panel, so the list is only a
-- protected frame while a row actually has an item.
local park = CreateFrame("Frame", nil, UIParent)
park:Hide()
local itemButtons = {}
local itemUsed = 0
local combatDraw = false   -- drawing in combat: leave the secure buttons alone

local function ItemLogIndex(u)
    return u.questID and C_QuestLog.GetLogIndexForQuestID(u.questID) or u.logIndex
end

local function ItemCooldown(u)
    local idx = ItemLogIndex(u)
    if not (idx and GetQuestLogSpecialItemCooldown) then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(idx)
    if start and not issecret(start) then
        CooldownFrame_Set(u.cd, start, duration, enable)
        u.icon:SetDesaturated((duration and duration > 0 and enable == 0) and true or false)
    end
end

local function NewItemButton(i)
    local u = CreateFrame("Button", "EvermoreUIQuestRowItem" .. i, park, "SecureActionButtonTemplate")
    u:RegisterForClicks("AnyUp", "AnyDown")
    u:SetAttribute("type", "item")
    u.well = T.Fill(u, "BACKGROUND", "surfaceSunk", 1)
    u.well:SetAllPoints()
    u.icon = u:CreateTexture(nil, "ARTWORK")
    u.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    u.icon:SetPoint("CENTER")
    u.cd = CreateFrame("Cooldown", nil, u, "CooldownFrameTemplate")
    u.cd:SetAllPoints(u.icon)
    u.hover = T.Fill(u, "HIGHLIGHT", "accent", 0.2)
    u.hover:SetAllPoints()
    local top = CreateFrame("Frame", nil, u)
    top:SetAllPoints()
    top:SetFrameLevel(u.cd:GetFrameLevel() + 2)
    u.count = T.Text(top, 11, "text", true, "RIGHT")
    u.count:SetPoint("BOTTOMRIGHT", -3, 3)
    u.key = T.Text(top, 9, "textMuted", true, "RIGHT")
    u.key:SetPoint("TOPRIGHT", -3, -3)
    T.TokenBorder(u, "borderStrong")
    function u:Paint()
        self.well:SetColorTexture(T.RGBA("surfaceSunk", 1))
        self.hover:SetColorTexture(T.RGBA("accent", 0.2))
        self.count:SetTextColor(T.RGBA("text"))
        self.key:SetTextColor(T.RGBA("textMuted"))
        T.SetBorderToken(self, "borderStrong")
    end
    T.Watch(u)
    u:SetScript("OnEnter", function(self)
        local idx = ItemLogIndex(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if not (idx and pcall(GameTooltip.SetQuestLogSpecialItem, GameTooltip, idx)) and self.link then
            GameTooltip:SetHyperlink(self.link)
        end
        GameTooltip:Show()
    end)
    u:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Red while out of range, like Blizzard's own quest item buttons.
    u:SetScript("OnUpdate", function(self, dt)
        self.range = (self.range or 0) - dt
        if self.range > 0 then return end
        self.range = 0.2
        local idx = ItemLogIndex(self)
        local valid = idx and IsQuestLogSpecialItemInRange and IsQuestLogSpecialItemInRange(idx)
        if valid == 0 then self.icon:SetVertexColor(EV.Theme.RGBA("danger")) else self.icon:SetVertexColor(1, 1, 1) end
    end)
    itemButtons[i] = u
    return u
end

--- The item a quest shows on its row: texture, link, itemID, charges.
local function QuestItem(q)
    if not (M.db.rowItems and GetQuestLogSpecialItemInfo) then return nil end
    local link, tex, charges, showWhenComplete = GetQuestLogSpecialItemInfo(q.logIndex)
    if type(link) ~= "string" or issecret(link) or not tex then return nil end
    if q.done and not showWhenComplete then return nil end
    return { tex = tex, link = link, charges = charges, itemID = tonumber(link:match("item:(%d+)")) }
end

--- Put a secure item button down the right of a block (out of combat only).
local function PlaceItem(b, q, item, h)
    itemUsed = itemUsed + 1
    local u = itemButtons[itemUsed] or NewItemButton(itemUsed)
    u:SetParent(b)
    u:ClearAllPoints()
    u:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
    u:SetSize(ITEM_W, max(ITEM_W - 8, h - 4))
    local icon = min(ITEM_W - 6, h - 10)
    u.icon:SetSize(icon, icon)
    u.icon:SetTexture(item.tex)
    u:SetAttribute("item", item.itemID and ("item:" .. item.itemID) or item.link)
    u.questID, u.logIndex, u.link = q.id, q.logIndex, item.link
    u.count:SetText((item.charges and item.charges > 1) and item.charges or "")
    u.key:SetText(ns.ItemKeyForQuest and ns.ItemKeyForQuest(q.id) or "")
    ItemCooldown(u)
    u:Show()
end

local function ParkUnusedItems()
    for i = itemUsed + 1, #itemButtons do
        local u = itemButtons[i]
        if u:GetParent() ~= park then
            u:SetAttribute("item", nil)
            u.questID, u.logIndex, u.link = nil, nil, nil
            u:ClearAllPoints()
            u:SetParent(park)
        end
    end
end

local cdEvents = CreateFrame("Frame")
cdEvents:RegisterEvent("BAG_UPDATE_COOLDOWN")
cdEvents:SetScript("OnEvent", function()
    for i = 1, itemUsed do if itemButtons[i] then ItemCooldown(itemButtons[i]) end end
end)

--- Draw one quest at y; returns its height.
local function DrawQuest(q, y)
    local b = Acquire("block", NewBlock)
    local w = Width()
    b.questID, b.quest, b.autoComplete = q.id, q, q.info.isAutoComplete
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
    b:SetWidth(w)
    b.hover:SetColorTexture(T.RGBA("surface2", b:IsMouseOver() and 0.6 or 0))
    PaintMarker(b, q)

    -- The item button takes the right-hand edge; text wraps short of it.
    local item = QuestItem(q)
    local reserve = item and (ITEM_W + 6) or 0
    local tw = w - TITLE_X - 6 - reserve
    b.title:ClearAllPoints()
    b.title:SetPoint("TOPLEFT", TITLE_X, -3)
    b.title:SetWidth(tw)
    b.title:SetText(TitleText(q))
    if q.done and M.db.completeColour then
        b.title:SetTextColor(T.RGBA("success"))
    else
        local r, g, bb = nil
        if M.db.difficulty then r, g, bb = DifficultyRGB(q.id) end
        if r then b.title:SetTextColor(r, g, bb) else b.title:SetTextColor(T.RGBA("title")) end
    end
    b.title:SetAlpha(q.watched and 1 or 0.6)
    local h = 3 + max(b.title:GetStringHeight() or 14, MARK)

    local lines = Objectives(q)
    for i, o in ipairs(lines) do
        local ln = Line(b, i)
        h = h + LINE_GAP
        ln.dash:ClearAllPoints()
        ln.dash:SetPoint("TOPLEFT", OBJ_X - 8, -h)
        ln.text:ClearAllPoints()
        ln.text:SetPoint("TOPLEFT", OBJ_X, -h)
        ln.text:SetWidth(w - OBJ_X - 6 - reserve)
        ln.text:SetText(o.text)
        ln.text:SetTextColor(T.RGBA((o.done and M.db.finished == "dim") and "textMuted" or (o.done and "success") or o.role))
        local a = (o.done and M.db.finished == "dim") and 0.55 or 1
        ln.text:SetAlpha(a)
        ln.dash:SetAlpha(a)
        ln.text:Show()
        ln.dash:Show()
        h = h + (ln.text:GetStringHeight() or 12)
        if M.db.progressBars and o.total and o.total > 1 and not o.done then
            h = h + 2
            ln.bar:ClearAllPoints()
            ln.bar:SetPoint("TOPLEFT", OBJ_X, -h)
            ln.bar:SetWidth(max(20, w - OBJ_X - 14 - reserve))
            ln.bar:SetMinMaxValues(0, o.total)
            ln.bar:SetValue(min(o.cur or 0, o.total))
            ln.bar:SetStatusBarColor(T.RGBA("accent", 0.9))
            ln.bar.bg:SetVertexColor(T.RGBA("surfaceSunk", 1))
            ln.bar:Show()
            h = h + BAR_H
        else
            ln.bar:Hide()
        end
    end
    for i = #lines + 1, #b.lines do
        local ln = b.lines[i]
        ln.text:Hide(); ln.dash:Hide(); ln.bar:Hide()
    end
    h = h + 4
    if item then h = max(h, ITEM_W) end
    b:SetHeight(h)
    if item and not combatDraw then PlaceItem(b, q, item, h) end
    return h
end

--------------------------------------------------------------------------------
--  Auto quest pop-ups (quest offers and click-to-complete)
--------------------------------------------------------------------------------
local function NewPopup()
    local p = CreateFrame("Button", nil, list)
    p:SetHeight(40)
    p.bg = T.Fill(p, "BACKGROUND", "accent", 0.14)
    p.bg:SetAllPoints()
    p.edge = T.Fill(p, "BORDER", "accent", 1)
    p.edge:SetPoint("TOPLEFT"); p.edge:SetPoint("BOTTOMLEFT"); p.edge:SetWidth(3)
    p.hover = T.Fill(p, "HIGHLIGHT", "accent", 0.12)
    p.hover:SetAllPoints()
    p.top = U.Label(p, "", "accent", "small", true)
    p.top:SetPoint("TOPLEFT", 12, -6)
    p.name = U.Label(p, "", "text", "body", true)
    p.name:SetPoint("TOPLEFT", p.top, "BOTTOMLEFT", 0, -3)
    p.name:SetPoint("RIGHT", -8, 0)
    p.name:SetJustifyH("LEFT")
    function p:Paint()
        self.bg:SetColorTexture(T.RGBA("accent", 0.14))
        self.edge:SetColorTexture(T.RGBA("accent", 1))
        self.hover:SetColorTexture(T.RGBA("accent", 0.12))
    end
    T.Watch(p)
    p:SetScript("OnClick", function(self)
        local id = self.questID
        if not id then return end
        if self.popType == "OFFER" then
            if ShowQuestOffer then ShowQuestOffer(id) end
        elseif ShowQuestComplete then
            ShowQuestComplete(id)
        end
        if RemoveAutoQuestPopUp then RemoveAutoQuestPopUp(id) end
        ns.RefreshList()
    end)
    return p
end

local function DrawPopups(y)
    if not (GetNumAutoQuestPopUps and GetAutoQuestPopUp) then return y end
    for i = 1, GetNumAutoQuestPopUps() do
        local id, kind = GetAutoQuestPopUp(i)
        local title = id and C_QuestLog.GetTitleForQuestID(id)
        if title and title ~= "" then
            local p = Acquire("popup", NewPopup)
            p.questID, p.popType = id, kind
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
            p:SetWidth(Width())
            p.top:SetText(kind == "OFFER" and Str(QUEST_WATCH_POPUP_CLICK_TO_VIEW, L["New quest: click to view"])
                or Str(QUEST_WATCH_POPUP_CLICK_TO_COMPLETE, L["Quest complete: click to hand in"]))
            p.name:SetText(title)
            y = y + 40 + BLOCK_GAP
        end
    end
    return y
end

--------------------------------------------------------------------------------
--  Draw
--------------------------------------------------------------------------------
--- In combat with item buttons on show, the list is protected: rows can't
--- move or resize. Refresh what's drawn where it is (text, colours,
--- progress, markers); the full redraw runs when combat ends.
local function UpdateInPlace()
    local byID = {}
    for _, q in ipairs(Collect()) do byID[q.id] = q end
    for i = 1, counts.block do
        local b = pools.block[i]
        local q = b and b.questID and byID[b.questID]
        if q then
            b.quest = q
            PaintMarker(b, q)
            b.title:SetText(TitleText(q))
            if q.done and M.db.completeColour then b.title:SetTextColor(T.RGBA("success")) end
            local lines = Objectives(q)
            for li, ln in ipairs(b.lines) do
                local o = lines[li]
                if o and ln.text:IsShown() then
                    ln.text:SetText(o.text)
                    local dim = o.done and M.db.finished == "dim"
                    ln.text:SetTextColor(T.RGBA(dim and "textMuted" or (o.done and "success") or o.role))
                    ln.text:SetAlpha(dim and 0.55 or 1)
                    if o.total and ln.bar:IsShown() then ln.bar:SetValue(min(o.cur or 0, o.total)) end
                end
            end
        end
    end
end

local Draw
local function AfterCombat()
    Draw()
    if ns.Layout then ns.Layout() end
end

Draw = function()
    if not list then return end
    if InCombatLockdown() then
        ns.Safe("list", AfterCombat)
        if list:IsProtected() then return UpdateInPlace() end
        combatDraw = true -- not protected: draw, but leave the secure buttons for later
    end
    itemUsed = 0
    counts.header, counts.block, counts.popup = 0, 0, 0
    local w = Width()
    list:SetWidth(w)
    local y = DrawPopups(0)
    local quests = Collect()
    local sections = Sections(quests)
    for _, s in ipairs(sections) do
        local h = Acquire("header", NewHeader)
        h.key = s.key
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -y)
        h:SetWidth(w)
        h.text:SetText(s.title)
        h.count:SetText(#s.quests)
        local collapsed = Collapsed(s.key)
        h.chev:Point(collapsed and "right" or "down")
        y = y + HEADER_H + 3
        if not collapsed then
            for _, q in ipairs(s.quests) do
                y = y + DrawQuest(q, y) + BLOCK_GAP
            end
        end
        y = y + 3
    end
    if not combatDraw then ParkUnusedItems() end
    combatDraw = false
    ReleaseRest()
    height = (#sections > 0 or counts.popup > 0) and y or 0
    list:SetHeight(max(height, 1))
    ns.listEmpty = height == 0
end

-- Flashes when an objective or quest finishes (from the alerts in Quests.lua).
local flasher = CreateFrame("Frame")
flasher:Hide()
flasher:SetScript("OnUpdate", function(self)
    local now, any = GetTime(), false
    for _, b in ipairs(pools.block) do
        local t0 = b:IsShown() and b.questID and flashes[b.questID]
        if t0 then
            local t = now - t0
            if t < 1.2 then
                any = true
                b.flash:SetColorTexture(T.RGBA("accent", 0.35 * (1 - t / 1.2)))
            else
                b.flash:SetColorTexture(T.RGBA("accent", 0))
            end
        end
    end
    for id, t0 in pairs(flashes) do if now - t0 >= 1.2 then flashes[id] = nil end end
    if not any and not next(flashes) then self:Hide() end
end)

function ns.FlashQuest(id)
    flashes[id] = GetTime()
    flasher:Show()
end

local pending, lastDraw = false, nil
--- Redraw on the next frame (many events arrive together). now: redraw at once.
function ns.RefreshList(now)
    if now then
        Draw()
        if ns.Layout then ns.Layout() end
        return
    end
    if pending then return end
    pending = true
    -- Quest events come in bursts (a kill fires several); draw at most
    -- every quarter second.
    local wait = math.max(0, (lastDraw or 0) + 0.25 - GetTime())
    C_Timer.After(wait, function()
        pending = false
        lastDraw = GetTime()
        Draw()
        if ns.Layout then ns.Layout() end
    end)
end

function ns.ListHeight() return height end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function() ns.RefreshList() end)

-- Distance sort: re-sort now and then while moving.
local ticker
local function UpdateTicker()
    local want = M.db.sort == "distance"
    if want and not ticker then
        ticker = C_Timer.NewTicker(3, function()
            if not (ns.panel and ns.panel:IsVisible()) or #drawn < 2 then return end
            -- Re-sort what's on screen by the new distances; redraw only if
            -- that changes the order. Standing still costs nothing.
            wipe(resort)
            for i, q in ipairs(drawn) do q.key = SortKey(q); resort[i] = q end
            table.sort(resort, ByKey)
            for i = 1, #resort do
                if resort[i] ~= drawn[i] then ns.RefreshList(); return end
            end
        end)
    elseif not want and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function ns.ApplyListSettings()
    UpdateTicker()
    ns.RefreshList()
end

function ns.CreateList(parent)
    list = CreateFrame("Frame", "EvermoreUIQuestList", parent)
    list:SetSize(Width(), 1)
    ns.list = list
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
                         "QUEST_AUTOCOMPLETE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                         "ZONE_CHANGED_NEW_AREA", "PLAYER_MONEY", "QUEST_POI_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(events.RegisterEvent, events, e)
    end
    UpdateTicker()
    return list
end
