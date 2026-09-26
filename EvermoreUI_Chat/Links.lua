if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Links.lua
--  Clickable web links, a copy-link popup and the copy-chat window (opened
--  from the sidebar or /evui copy).
--
--  Links are added with a message event filter, the same hook Blizzard gives
--  every addon. Secret messages (restricted content) are passed on untouched,
--  and so is everything during chat lockdown. The link itself uses the
--  "addon" hyperlink type, which Blizzard routes to EventRegistry's
--  "SetItemRef" callback, so no Blizzard function is replaced.
--------------------------------------------------------------------------------
local _, ns = ...
local EV = EvermoreUI
if not (EV and ns.module) then return end
local M = ns.module
local L = EV.L

local LINK_PREFIX = "addon:EvermoreUI:url:"

--------------------------------------------------------------------------------
--  Finding URLs
--------------------------------------------------------------------------------
local function IsURL(s)
    return s:find("^https?://[%w%-]") or s:find("^www%.[%w%-]+%.%a") ~= nil
end

local function Linkify(token)
    -- Anything carrying escape codes (item links, colours, textures) is left alone.
    if token:find("|", 1, true) then return token end
    local lead, body = token:match("^([%(%[\"']*)(.*)$")
    local core, trail = body:match("^(.-)([%.,;:!%?%)%]\"']*)$")
    if not core or core == "" or not IsURL(core) then return token end
    return ("%s|cff%s|H%s%s|h[%s]|h|r%s"):format(lead, EV.Theme.Hex("accent"), LINK_PREFIX, core, core, trail)
end

local function InLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function Filter(_, _, msg, ...)
    if not M.db.urls then return false end
    if issecretvalue and issecretvalue(msg) then return false end
    if type(msg) ~= "string" or InLockdown() then return false end
    if not (msg:find("://", 1, true) or msg:find("www.", 1, true)) then return false end
    local out = msg:gsub("%S+", Linkify)
    if out == msg then return false end
    return false, out, ...
end
ns.Linkify = function(msg) return (msg:gsub("%S+", Linkify)) end

local FILTER_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD",
    "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_SYSTEM",
}

--------------------------------------------------------------------------------
--  Shared little window (copy link and copy chat both use it)
--------------------------------------------------------------------------------
local popup

-- A read-only text well in our field style.
local function Well(frame)
    local T = EV.Theme
    local bg = T.Fill(frame, "BACKGROUND", "surfaceSunk", 1)
    bg:SetAllPoints()
    T.TokenBorder(frame, "borderStrong")
    function frame:Paint()
        bg:SetColorTexture(T.RGBA("surfaceSunk", 1))
        T.SetBorderToken(frame, "borderStrong")
    end
    T.Watch(frame)
end

--- Our standard window (EvermoreUI/UI/Containers.lua) with a single-line
--- field for a link, or a scrolling multi-line one for a chat window.
local function Popup()
    if popup then return popup end
    local T, U = EV.Theme, EV.UI
    local f = U.Window("EvermoreUIChatCopy", { width = 520, height = 88, strata = "DIALOG" })
    f.hint = T.Text(f.titleBar, "small", "textMuted")
    f.hint:SetPoint("RIGHT", f.closeButton or f.titleBar, f.closeButton and "LEFT" or "RIGHT", -10, 0)
    f.hint:SetText(L["Ctrl+C to copy, Esc to close"])
    local font = EV.Media:Fetch("font")

    -- Single line (a link)
    local line = CreateFrame("EditBox", nil, f.body)
    line:SetAutoFocus(false)
    line:SetFont(font, 14, "")
    line:SetTextColor(T.RGBA("text"))
    line:SetHeight(28)
    line:SetPoint("TOPLEFT", 12, -12)
    line:SetPoint("TOPRIGHT", -12, -12)
    line:SetTextInsets(8, 8, 0, 0)
    Well(line)
    f.line = line

    -- Many lines (a chat window), with the shared scroll bar.
    local box = CreateFrame("Frame", nil, f.body)
    box:SetPoint("TOPLEFT", 12, -12)
    box:SetPoint("BOTTOMRIGHT", -12, 12)
    Well(box)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -16, 6)
    local multi = CreateFrame("EditBox", nil, scroll)
    multi:SetMultiLine(true)
    multi:SetAutoFocus(false)
    multi:SetFont(font, 13, "")
    multi:SetTextColor(T.RGBA("text"))
    multi:SetWidth(560)
    multi:SetTextInsets(2, 2, 2, 2)
    scroll:SetScrollChild(multi)
    local bar = U.ScrollBar(box, {
        range = function() return scroll:GetVerticalScrollRange() end,
        offset = function() return scroll:GetVerticalScroll() end,
        visible = function() return scroll:GetHeight() end,
        set = function(v) scroll:SetVerticalScroll(v) end,
        step = 40,
    })
    bar:SetPoint("TOPRIGHT", -4, -4)
    bar:SetPoint("BOTTOMRIGHT", -4, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        bar:Update()
    end)
    scroll:SetScript("OnScrollRangeChanged", function() bar:Update() end)
    scroll:SetScript("OnVerticalScroll", function() bar:Update() end)
    f.box, f.scroll, f.multi, f.bar = box, scroll, multi, bar

    for _, eb in ipairs({ line, multi }) do
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        -- Read-only: put the text back if someone types into it.
        eb:SetScript("OnTextChanged", function(self, user)
            if user and self.evText then self:SetText(self.evText); self:HighlightText() end
        end)
    end
    f:SetScript("OnHide", function() line:ClearFocus(); multi:ClearFocus() end)
    f:Hide()
    popup = f
    return f
end

function ns.ShowCopyLink(url)
    local f = Popup()
    f:SetSize(520, 88)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetTitle(L["Copy link"])
    f.box:Hide(); f.line:Show()
    f.line.evText = url
    f.line:SetText(url)
    f:Show()
    f.line:SetFocus()
    f.line:HighlightText()
end

--------------------------------------------------------------------------------
--  Copy a chat window
--------------------------------------------------------------------------------
local function Clean(text)
    text = text:gsub("|K.-|k", "?")                   -- protected Battle.net names
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "") -- textures and atlases
    text = text:gsub("|H.-|h(.-)|h", "%1")            -- keep a link's visible text
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    -- Plural escapes: "5 |4second:seconds;" becomes "5 seconds".
    text = text:gsub("(%d+)(%s*)|4([^:;]*):([^;]*);", function(n, sp, one, many)
        return n .. sp .. (tonumber(n) == 1 and one or many)
    end)
    text = text:gsub("|4[^:;]*:([^;]*);", "%1")
    text = text:gsub("|n", "\n"):gsub("||", "|")
    return text
end
ns.CleanLine = Clean

function ns.ShowCopyChat(cf)
    cf = cf or ChatFrame1
    local lines, hidden = {}, 0
    for _, text in ipairs(ns.Engine.Lines(cf)) do
        if issecretvalue and issecretvalue(text) then
            hidden = hidden + 1
        elseif type(text) == "string" then
            local ok, clean = pcall(Clean, text)
            if ok then lines[#lines + 1] = clean end
        end
    end
    local body = table.concat(lines, "\n")

    local f = Popup()
    f:SetSize(600, 420)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    local r, g, b = EV.Theme.RGBA("textMuted")
    local muted = ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
    f:SetTitle(hidden > 0 and ("%s  %s(%d %s)|r"):format(L["Copy chat"], muted, hidden, L["hidden lines left out"])
        or L["Copy chat"])
    f.line:Hide(); f.box:Show()
    f.multi:SetWidth(f.scroll:GetWidth() > 0 and f.scroll:GetWidth() or 576)
    f.multi.evText = body
    f.multi:SetText(body)
    f:Show()
    f.multi:SetFocus()
    f.multi:HighlightText()
    C_Timer.After(0, function()
        f.scroll:SetVerticalScroll(f.scroll:GetVerticalScrollRange())
        f.bar:Update()
    end)
end

--------------------------------------------------------------------------------
--  Install
--------------------------------------------------------------------------------
local LINK_PATTERN = "^" .. LINK_PREFIX:gsub("%p", "%%%0") .. "(.+)$"
local function OnLinkClicked(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then
            local url = v:match(LINK_PATTERN)
            if url then ns.ShowCopyLink(url); return end
        end
    end
end

local installed = false
function ns.InstallLinks()
    if installed then return end
    installed = true
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if add then
        for _, e in ipairs(FILTER_EVENTS) do pcall(add, e, Filter) end
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", OnLinkClicked, M)
    elseif SetItemRef then
        hooksecurefunc("SetItemRef", function(link) OnLinkClicked(link) end)
    end
end

-- /evui copy: copy the main chat window
function M:CopyMain() ns.ShowCopyChat(ns.Selected() or ChatFrame1) end
