if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Sidebar.lua
--  The icon strip beside the main chat: friends and guild (with online
--  counts), copy chat, channels, EvermoreUI settings, and scroll to bottom
--  pinned at the foot (lit while you're scrolled back). Always shown,
--  shown on hover, or off. Our frames only, flush against the panel.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local CFD, Px, Snap = ns.CFD, ns.Px, ns.Snap

local S = {}
ns.Sidebar = S

local MEDIA = "Interface\\AddOns\\EvermoreUI_Chat\\Media\\"


local frame, buttons, counts = nil, {}, {}
local hoverAlpha, chatAlpha = 1, 1

local function Tip(owner, text)
    GameTooltip:SetOwner(owner, M.db.sidebarRight and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
    GameTooltip:SetText(text, 1, 1, 1)
    GameTooltip:Show()
end

local function SelectedWindow() return ns.Selected() or ChatFrame1 end

local ICONS = {
    { key = "iconFriends",  tex = "friends",  label = L["Friends"],
      click = function() if ToggleFriendsFrame then ToggleFriendsFrame() end end },
    { key = "iconGuild",    tex = "guild",    label = L["Guild"],
      click = function() if ToggleGuildFrame then ToggleGuildFrame() end end },
    { key = "iconCopy",     tex = "copy",     label = L["Copy chat"],
      click = function() if ns.ShowCopyChat then ns.ShowCopyChat(SelectedWindow()) end end },
    { key = "iconChannels", tex = "channels", label = L["Channels"],
      click = function() if ToggleChannelFrame then ToggleChannelFrame() end end },
    { key = "iconSettings", tex = "settings", label = L["Chat settings"],
      click = function()
          EV:OpenOptions()
          if EV.Options and EV.Options.ShowPage then EV.Options:ShowPage("chat") end
      end },
}

local function SetAlphaNow()
    if not frame then return end
    frame:SetAlpha(math.min(chatAlpha, hoverAlpha))
end

-- Icon colours from the theme: muted at rest, full text colour on hover,
-- accent when lit (like our icon buttons elsewhere).
local TH = EV.Theme
local function Idle(b)
    if b.lit then b.icon:SetVertexColor(TH.RGBA("accent")) else b.icon:SetVertexColor(TH.RGBA("textMuted")) end
    if b.count then b.count:SetTextColor(TH.RGBA("textMuted")) end
end
local function Hot(b)
    b.icon:SetVertexColor(TH.RGBA(b.lit and "accent" or "text"))
    if b.count then b.count:SetTextColor(TH.RGBA("text")) end
end

local function NewButton(tex, label, click)
    local b = CreateFrame("Button", nil, frame)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetPoint("TOPLEFT", -Px(3), Px(3))
    b.hl:SetPoint("BOTTOMRIGHT", Px(3), -Px(3))
    b.hl:SetColorTexture(TH.RGBA("surface2", 0.8))
    b.hl:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(MEDIA .. tex .. ".png")
    b.label = label
    Idle(b)
    b:SetScript("OnEnter", function(self)
        self.hl:SetColorTexture(TH.RGBA("surface2", 0.8))
        self.hl:Show()
        Hot(self)
        Tip(self, self.label)
    end)
    b:SetScript("OnLeave", function(self)
        self.hl:Hide()
        Idle(self)
        GameTooltip:Hide()
    end)
    b.Paint = Idle
    TH.Watch(b)
    b:SetScript("OnClick", click)
    return b
end

--------------------------------------------------------------------------------
--  Counts (recounted on their own events; never in combat)
--------------------------------------------------------------------------------
local dirty = false
local function Recount()
    if InCombatLockdown() then dirty = true; return end
    dirty = false
    if counts.friends then
        local wow = C_FriendList and C_FriendList.GetNumOnlineFriends and C_FriendList.GetNumOnlineFriends() or 0
        local bn = 0
        if BNGetNumFriends then local _, online = BNGetNumFriends(); bn = online or 0 end
        counts.friends:SetText((wow or 0) + bn)
    end
    if counts.guild then
        local online = 0
        if IsInGuild and IsInGuild() and GetNumGuildMembers then
            local _, on = GetNumGuildMembers()
            online = on or 0
        end
        counts.guild:SetText(online)
    end
end

local countFrame = CreateFrame("Frame")
countFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if dirty then Recount() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" and C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    end
    Recount()
end)

--------------------------------------------------------------------------------
--  Build and layout
--------------------------------------------------------------------------------
function S.Build()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    S.frame = frame
    frame.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.bg:SetAllPoints()
    EV.Pixel.NoSnap(frame.bg)
    frame.div = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    EV.Pixel.NoSnap(frame.div)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function()
        ns.WatchStart(); ns.Hover(true)
        if M.db.sidebar == "mouseover" then hoverAlpha = 1; SetAlphaNow() end
    end)
    frame:SetScript("OnLeave", function()
        ns.WatchEnd(); ns.Hover(false)
        if M.db.sidebar == "mouseover" then
            C_Timer.After(0.2, function()
                if frame:IsMouseOver() then return end
                hoverAlpha = 0
                SetAlphaNow()
            end)
        end
    end)

    for _, info in ipairs(ICONS) do
        local b = NewButton(info.tex, info.label, info.click)
        b.info = info
        -- Hovering an icon still counts as hovering the sidebar.
        b:HookScript("OnEnter", function() frame:GetScript("OnEnter")() end)
        b:HookScript("OnLeave", function() frame:GetScript("OnLeave")() end)
        buttons[#buttons + 1] = b
        if info.tex == "friends" or info.tex == "guild" then
            local c = frame:CreateFontString(nil, "OVERLAY")
            c:SetFont(ns.FontPath(), 9, "")
            c:SetTextColor(TH.RGBA("textMuted"))
            c:SetPoint("TOP", b, "BOTTOM", 0, Px(1))
            c:SetText("0")
            b.count = c
            counts[info.tex] = c
        end
    end

    local scroll = NewButton("scroll", L["Scroll to bottom"], function() ns.Engine.ScrollToBottom(SelectedWindow()) end)
    scroll:HookScript("OnEnter", function() frame:GetScript("OnEnter")() end)
    scroll:HookScript("OnLeave", function() frame:GetScript("OnLeave")() end)
    S.scroll = scroll

    -- Lit in the accent colour while the open window is scrolled back.
    ns.Engine.scrollListeners = ns.Engine.scrollListeners or {}
    table.insert(ns.Engine.scrollListeners, function(cf, back)
        if cf ~= SelectedWindow() then return end
        scroll.lit = back
        Idle(scroll)
    end)

    for _, e in ipairs({ "BN_FRIEND_LIST_SIZE_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
                         "FRIENDLIST_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
                         "PLAYER_ENTERING_WORLD", "BN_CONNECTED", "BN_DISCONNECTED", "PLAYER_REGEN_ENABLED" }) do
        pcall(countFrame.RegisterEvent, countFrame, e)
    end
    S.Layout()
    Recount()
end

function S.Layout()
    if not frame then return end
    local db = M.db
    local dock = ns.DockPanel()
    if not dock then return end
    local mode = db.sidebar
    local top = db.tabsInPanel and ns.Tabs.band or dock
    local w = Snap(Px(db.sidebarWidth))

    frame:SetFrameStrata(dock:GetFrameStrata())
    frame:SetFrameLevel(dock:GetFrameLevel() + 2)
    frame:ClearAllPoints()
    if db.sidebarRight then
        frame:SetPoint("TOPLEFT", top, "TOPRIGHT")
        frame:SetPoint("BOTTOMLEFT", dock, "BOTTOMRIGHT")
    else
        frame:SetPoint("TOPRIGHT", top, "TOPLEFT")
        frame:SetPoint("BOTTOMRIGHT", dock, "BOTTOMLEFT")
    end
    frame:SetWidth(w)
    local bg = ns.BG
    frame.bg:SetColorTexture(bg[1], bg[2], bg[3], db.bgAlpha)
    frame.div:ClearAllPoints()
    frame.div:SetWidth(Px(1))
    frame.div:SetColorTexture(unpack(ns.DIVIDER))
    if db.sidebarRight then
        frame.div:SetPoint("TOPLEFT"); frame.div:SetPoint("BOTTOMLEFT")
    else
        frame.div:SetPoint("TOPRIGHT"); frame.div:SetPoint("BOTTOMRIGHT")
    end
    frame.div:SetShown(db.dividers)

    -- Icons: a column from the top, counts under the social ones.
    local size = Snap(math.max(Px(14), w - Px(14)))
    local spacing = Snap(Px(10))
    local y = -spacing
    for _, b in ipairs(buttons) do
        local on = db[b.info.key]
        b:SetShown(on)
        if b.count then b.count:SetShown(on) end
        if on then
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOP", frame, "TOP", 0, y)
            y = y - size - spacing
            if b.count then
                b.count:SetFont(ns.FontPath(), 9, "")
                y = y - Snap(Px(9))
            end
        end
    end
    local scroll = S.scroll
    scroll:SetSize(size, size)
    scroll:ClearAllPoints()
    scroll:SetPoint("BOTTOM", frame, "BOTTOM", 0, spacing)
    scroll:SetShown(db.iconScroll)

    frame:SetShown(mode ~= "never" and not ns.hidden)
    hoverAlpha = (mode == "mouseover" and not frame:IsMouseOver()) and 0 or 1
    SetAlphaNow()
end

function S.SetAlpha(a)
    chatAlpha = a
    SetAlphaNow()
end
