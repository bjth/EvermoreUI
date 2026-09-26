if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Window.lua
--  The options window.
--
--   +-----------+------------------------------------------------+
--   | EvermoreUI |  Page title                                  x |
--   | v0.1      |  Description                                    |
--   |           |  Tab  Tab  Tab                                  |
--   | GENERAL   +------------------------------------------------+
--   |  General  |  SECTION                                        |
--   |  Profiles |  [row] label ................... control        |
--   | INTERFACE |  [row] label ..... control | label ... control  |
--   |  Data Bars|                                                 |
--   |           +------------------------------------------------+
--   | [Unlock]  |  Reset Page  Reload UI                    Done  |
--   +-----------+------------------------------------------------+
--
--  EV.Options:RegisterPage{
--      key = "databars", title = "Data Bars", group = "Interface",
--      description = "...", module = "DataBars", tabs = { "Experience" },
--      build = function(p, tab) ... end,   -- p = Page.lua builder
--      onReset = function(tab) ... end,
--  }
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local W = EV.UI
local U = EV.UI
local L = EV.L

local Options = {}
EV.Options = Options

local GROUPS = { "General", "Combat", "Interface", "Chat & Tooltips", "Extras", "Experimental" }
local pages, order = {}, {}
local window, content, scroll, scrollChild, scrollbar
local header = {}
local navButtons = {}
local tabButtons = {}
local current, currentTab
local built = {}   -- "key:tab" -> { frame, builder }

Options.reloadNeeded = false

--------------------------------------------------------------------------------
--  Registration
--------------------------------------------------------------------------------
function Options:RegisterPage(def)
    def.group = def.group or "General"
    def.tabs = def.tabs or { def.title }
    pages[def.key] = def
    order[#order + 1] = def.key
end

local function ModuleEnabled(def)
    if not def.module then return true end
    local mod = EV:GetModule(def.module, true)
    return mod and mod:IsWanted()
end

--------------------------------------------------------------------------------
--  Scrolling (smooth wheel, draggable thumb)
--------------------------------------------------------------------------------
local targetScroll = 0

local function MaxScroll()
    return math.max(0, scrollChild:GetHeight() - scroll:GetHeight())
end

local function UpdateScrollbar()
    if scrollbar then scrollbar:Update() end
end

local function ScrollTo(v, instant)
    targetScroll = math.max(0, math.min(MaxScroll(), v))
    if instant then
        scroll:SetVerticalScroll(targetScroll)
        UpdateScrollbar()
        return
    end
    local from = scroll:GetVerticalScroll()
    T.Tween("ev_scroll", 0.18, function(e)
        scroll:SetVerticalScroll(T.Lerp(from, targetScroll, e))
        UpdateScrollbar()
    end)
end

--------------------------------------------------------------------------------
--  Nav + tabs state
--------------------------------------------------------------------------------
local function PaintNav()
    for key, b in pairs(navButtons) do
        local def = pages[key]
        local selected = key == current
        local enabled = ModuleEnabled(def)
        b.bar:SetShown(selected)
        b.glow:SetShown(selected)
        b.bar:SetColorTexture(T.RGBA("accent"))
        local ar, ag, ab = T.RGBA("accent")
        if b.glow.SetGradient and CreateColor then
            b.glow:SetColorTexture(1, 1, 1, 1)
            b.glow:SetGradient("HORIZONTAL", CreateColor(ar, ag, ab, 0.16), CreateColor(ar, ag, ab, 0))
        else
            b.glow:SetColorTexture(ar, ag, ab, 0.08)
        end
        b.hl:SetColorTexture(T.RGBA("surface2", 0.5))
        local token = (selected or b:IsMouseOver()) and "text" or (enabled and "textMuted" or "textDisabled")
        b.text:SetTextColor(T.RGBA(token))
        if b.dot then
            if enabled then b.dot:SetColorTexture(T.RGBA("accent", selected and 1 or 0.7))
            else b.dot:SetColorTexture(T.RGBA("textDisabled", 0.5)) end
        end
    end
end

local function PaintTabs()
    for _, b in ipairs(tabButtons) do
        local active = b.tab == currentTab
        b.text:SetTextColor(T.RGBA((active or b:IsMouseOver()) and "text" or "textMuted"))
        b.line:SetColorTexture(T.RGBA("accent"))
        b.line:SetShown(active)
    end
end

local function PaintReload()
    local rb = window and window.reloadBtn
    if not rb then return end
    if Options.reloadNeeded then
        rb:SetStyle("accent")
        rb:SetText(L["Reload to apply"])
    else
        rb:SetStyle(nil)
        rb:SetText(L["Reload UI"])
    end
end

function Options:MarkReloadNeeded()
    self.reloadNeeded = true
    PaintReload()
end

local function BuildTabs(def)
    for _, b in ipairs(tabButtons) do b:Hide() end
    local show = #def.tabs > 1
    header.tabs:SetShown(show)
    if not show then return end
    local x = 0
    for i, tab in ipairs(def.tabs) do
        local b = tabButtons[i]
        if not b then
            b = CreateFrame("Button", nil, header.tabs)
            b:SetHeight(T.TABS_H)
            b.text = T.Text(b, 14, "textMuted", true, "CENTER")
            b.text:SetPoint("CENTER", 0, 2)
            b.line = T.Fill(b, "ARTWORK", "accent")
            b.line:SetHeight(2)
            b.line:SetPoint("BOTTOMLEFT", 0, 0)
            b.line:SetPoint("BOTTOMRIGHT", 0, 0)
            b:SetScript("OnEnter", PaintTabs)
            b:SetScript("OnLeave", PaintTabs)
            b:SetScript("OnClick", function(self) Options:ShowPage(current, self.tab) end)
            tabButtons[i] = b
        end
        b.tab = tab
        b.text:SetText(tab)
        b:SetWidth((b.text:GetStringWidth() or 60) + 8)
        b:ClearAllPoints()
        b:SetPoint("BOTTOMLEFT", header.tabs, "BOTTOMLEFT", x, 0)
        x = x + b:GetWidth() + 26
        b:Show()
    end
end

--------------------------------------------------------------------------------
--  Pages
--------------------------------------------------------------------------------
function Options:ShowPage(key, tab)
    local def = pages[key]
    if not def then return end
    tab = tab or (key == current and currentTab) or def.tabs[1]
    current, currentTab = key, tab

    header.title:SetText(def.title)
    header.desc:SetText(def.description or "")
    BuildTabs(def)
    PaintTabs()
    PaintNav()
    if self.RevealNav then self:RevealNav(key) end

    -- The header grows when the description wraps; tabs and content follow.
    local descH = header.desc:GetStringHeight() or 0
    local lineH = select(2, header.desc:GetFont()) or 14
    local headerH = math.floor(T.HEADER_H + math.max(0, descH - lineH * 1.25) + 0.5)
    header.frame:SetHeight(headerH)
    header.tabs:ClearAllPoints()
    header.tabs:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, -headerH)
    header.tabs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -T.PAD, -headerH)

    -- Content area starts under the header, lower when tabs show.
    local top = headerH + (#def.tabs > 1 and T.TABS_H or 0)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top - 1)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -14, T.FOOTER_H)
    header.sep:ClearAllPoints()
    header.sep:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -top)
    header.sep:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -top)

    for _, b in pairs(built) do b.frame:Hide() end
    local id = key .. ":" .. tab
    local entry = built[id]
    if not entry then
        local frame = CreateFrame("Frame", nil, scrollChild)
        frame:SetPoint("TOPLEFT")
        frame:SetWidth(scrollChild:GetWidth())
        local p = EV.Options_NewBuilder(frame, scrollChild:GetWidth() - T.PAD * 2, function() PaintNav() end)
        if def.experimental then
            p:Banner(L["Experimental: unfinished, and may misbehave. Report anything odd."])
        end
        if def.module and not ModuleEnabled(def) then
            p:Banner(L["This module is switched off."], L["Turn it on"], function()
                EV.DB:GetCore().disabled[def.module] = nil
                Options:MarkReloadNeeded()
                Options:Rebuild()
            end)
        end
        def.build(p, tab)
        frame:SetHeight(p:Height())
        entry = { frame = frame, builder = p }
        built[id] = entry
    end
    entry.frame:Show()
    scrollChild:SetHeight(entry.frame:GetHeight())
    entry.builder:Refresh()
    ScrollTo(0, true)
    UpdateScrollbar()
    window.resetBtn:SetShown(def.onReset ~= nil)
end

function Options:RefreshCurrent()
    if not (current and currentTab) then return end
    local entry = built[current .. ":" .. currentTab]
    if entry then entry.builder:Refresh() end
    PaintNav()
end

--- Drop cached pages (e.g. after a profile switch the page lists change).
function Options:Rebuild()
    for _, b in pairs(built) do b.frame:Hide() end
    wipe(built)
    if current then self:ShowPage(current, currentTab) end
end

--------------------------------------------------------------------------------
--  Window construction
--------------------------------------------------------------------------------
local function BuildSidebar()
    local sb = CreateFrame("Frame", nil, window)
    sb:SetPoint("TOPLEFT")
    sb:SetPoint("BOTTOMLEFT")
    sb:SetWidth(T.SIDEBAR_W)
    -- Theme surfaces: the sidebar is the sunk side of the window, with a
    -- divider line where it meets the content.
    local sbg = T.Fill(sb, "BACKGROUND", "surfaceSunk", 0.6)
    sbg:SetAllPoints()
    local edge = T.Fill(sb, "BORDER", "divider")
    edge:SetWidth(1)
    edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT")

    -- Brand
    local brand = T.Text(sb, 26, "text", true)
    brand:SetPoint("TOPLEFT", 24, -24)
    local ver = T.Text(sb, 12, "textDisabled")
    ver:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 1, -4)
    local c = EV.Caps
    ver:SetText(("v%s  -  %s"):format(EV.version, tostring(c.version or "")))
    local groupLabels = {}
    T.OnTheme(function()
        sbg:SetColorTexture(T.RGBA("surfaceSunk", 0.6))
        edge:SetColorTexture(T.RGBA("divider"))
        local r, g, b = T.RGBA("accent")
        brand:SetTextColor(T.RGBA("text"))
        brand:SetText(("Evermore|cff%02x%02x%02xUI|r"):format(r * 255, g * 255, b * 255))
        ver:SetTextColor(T.RGBA("textDisabled"))
        for _, gl in ipairs(groupLabels) do gl:SetTextColor(T.RGBA("textDisabled")) end
    end)

    -- Drag the window by the brand area
    local drag = CreateFrame("Frame", nil, sb)
    drag:SetPoint("TOPLEFT"); drag:SetPoint("TOPRIGHT"); drag:SetHeight(84)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() window:StartMoving() end)
    drag:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    -- The page list scrolls between the brand and the Edit Mode button once
    -- there are more pages than fit (the shared scroll bar, on the divider).
    local nav = CreateFrame("ScrollFrame", nil, sb)
    local navChild = CreateFrame("Frame", nil, nav)
    navChild:SetSize(T.SIDEBAR_W - 1, 10)
    nav:SetScrollChild(navChild)
    nav:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -88)
    nav:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -1, -88)
    local navTarget = 0
    local navBar
    local function NavMax() return math.max(0, navChild:GetHeight() - nav:GetHeight()) end
    local function NavTo(v, instant)
        navTarget = math.max(0, math.min(NavMax(), v))
        if instant then
            nav:SetVerticalScroll(navTarget)
            navBar:Update()
            return
        end
        local from = nav:GetVerticalScroll()
        T.Tween("ev_navscroll", 0.18, function(e)
            nav:SetVerticalScroll(T.Lerp(from, navTarget, e))
            navBar:Update()
        end)
    end
    nav:EnableMouseWheel(true)
    nav:SetScript("OnMouseWheel", function(_, delta) NavTo(navTarget - delta * T.NAV_H * 2) end)
    nav:SetScript("OnSizeChanged", function() NavTo(navTarget, true) end)
    navBar = U.ScrollBar(sb, {
        range = NavMax,
        offset = function() return nav:GetVerticalScroll() end,
        visible = function() return nav:GetHeight() end,
        set = function(v) NavTo(v, true) end,
        step = T.NAV_H * 2,
    })
    navBar:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -3, -2)
    navBar:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -3, 2)
    --- Scroll just enough to show a page's button (opening a page from
    --- elsewhere, e.g. Edit Mode's "settings" link).
    function Options:RevealNav(key)
        local b = navButtons[key]
        if not b then return end
        local top = b.navY or 0
        local bottom = top + T.NAV_H
        local view = nav:GetHeight()
        if top < navTarget then NavTo(top - 8)
        elseif bottom > navTarget + view then NavTo(bottom - view + 8) end
    end

    local y = -4
    for _, group in ipairs(GROUPS) do
        local any = false
        for _, key in ipairs(order) do if pages[key].group == group then any = true end end
        if any then
            local gl = T.Text(navChild, 11, "textDisabled", true)
            groupLabels[#groupLabels + 1] = gl
            gl:SetPoint("TOPLEFT", 24, y - 8)
            gl:SetText(L[group]:upper())
            y = y - 30
            for _, key in ipairs(order) do
                local def = pages[key]
                if def.group == group then
                    local b = CreateFrame("Button", nil, navChild)
                    b:SetSize(T.SIDEBAR_W - 1, T.NAV_H)
                    b:SetPoint("TOPLEFT", 0, y)
                    b.navY = -y
                    -- Colours come from PaintNav (theme tokens).
                    b.glow = T.Fill(b, "BACKGROUND", "accent", 0.08)
                    b.glow:SetAllPoints()
                    b.bar = T.Fill(b, "ARTWORK", "accent")
                    b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
                    b.hl = T.Fill(b, "HIGHLIGHT", "surface2", 0.5)
                    b.hl:SetAllPoints()
                    b.text = T.Text(b, 15, "textMuted")
                    b.text:SetPoint("LEFT", 26, 0)
                    b.text:SetText(def.title)
                    if def.module then
                        b.dot = T.Fill(b, "ARTWORK", "accent")
                        b.dot:SetSize(6, 6)
                        b.dot:SetPoint("RIGHT", -20, 0)
                    end
                    b:SetScript("OnEnter", PaintNav)
                    b:SetScript("OnLeave", PaintNav)
                    b:SetScript("OnClick", function() Options:ShowPage(key) end)
                    navButtons[key] = b
                    y = y - T.NAV_H
                end
            end
            y = y - 12
        end
    end

    navChild:SetHeight(-y + 4)

    -- Unlock frames, bottom of the sidebar
    local unlock = W.Button(sb, L["Edit Mode"], T.SIDEBAR_W - 48, function()
        EV.Movers:Unlock()
    end, "accent")
    unlock:SetPoint("BOTTOM", sb, "BOTTOM", 0, 18)
    nav:SetPoint("BOTTOM", unlock, "TOP", 0, 14)
    -- A hairline over the button when the list runs underneath it.
    local foot = T.Fill(sb, "ARTWORK", "divider")
    foot:SetHeight(1)
    foot:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 0, -1)
    foot:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", 0, -1)
    local function Foot()
        foot:SetColorTexture(T.RGBA("divider"))
        foot:SetShown(NavMax() > 0)
    end
    T.OnTheme(Foot)
    nav:HookScript("OnSizeChanged", Foot)
    navBar:Update()
    return sb
end

local function BuildHeader()
    local h = CreateFrame("Frame", nil, content)
    h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT")
    h:SetHeight(T.HEADER_H)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnDragStart", function() window:StartMoving() end)
    h:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    header.title = T.Text(h, 26, "text", true)
    header.title:SetPoint("TOPLEFT", T.PAD, -28)
    header.desc = T.Text(h, 14, "textMuted")
    header.desc:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -6)
    -- Wraps inside the content area, clear of the close button.
    header.desc:SetWidth(T.W - T.SIDEBAR_W - T.PAD - 60)
    header.desc:SetWordWrap(true)
    header.desc:SetMaxLines(3)
    header.frame = h

    -- Close: an X drawn from two lines
    local close = CreateFrame("Button", nil, h)
    close:SetSize(30, 30)
    close:SetPoint("TOPRIGHT", -14, -14)
    -- Our close glyph, like every other EvermoreUI window: muted, red on hover.
    local hbg = T.Fill(close, "BACKGROUND", "surface2")
    hbg:SetAllPoints(); hbg:Hide()
    local x = U.Glyph(close, "close", 14)
    x:SetPoint("CENTER")
    local function Idle() hbg:Hide(); x:SetVertexColor(T.RGBA("textMuted")) end
    close:SetScript("OnEnter", function()
        hbg:SetColorTexture(T.RGBA("surface2")); hbg:Show()
        x:SetVertexColor(T.RGBA("danger"))
    end)
    close:SetScript("OnLeave", Idle)
    T.OnTheme(Idle)
    T.OnTheme(function()
        header.title:SetTextColor(T.RGBA("text"))
        header.desc:SetTextColor(T.RGBA("textMuted"))
    end)
    close:SetScript("OnClick", function() window:Hide() end)

    header.tabs = CreateFrame("Frame", nil, content)
    header.tabs:SetPoint("TOPLEFT", content, "TOPLEFT", T.PAD, -T.HEADER_H)
    header.tabs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -T.PAD, -T.HEADER_H)
    header.tabs:SetHeight(T.TABS_H)

    header.sep = T.Fill(content, "ARTWORK", "divider")
    T.OnTheme(function() header.sep:SetColorTexture(T.RGBA("divider")) end)
    header.sep:SetHeight(1)
end

local function BuildScroll()
    scroll = CreateFrame("ScrollFrame", nil, content)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(T.W - T.SIDEBAR_W - 14, 10)
    scroll:SetScrollChild(scrollChild)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) ScrollTo(targetScroll - delta * 70) end)
    scroll:SetScript("OnSizeChanged", UpdateScrollbar)

    -- The shared scroll bar (EvermoreUI/UI/ScrollBar.lua), like every
    -- other EvermoreUI surface. The wheel stays smooth; dragging is direct.
    scrollbar = U.ScrollBar(content, {
        range = MaxScroll,
        offset = function() return scroll:GetVerticalScroll() end,
        visible = function() return scroll:GetHeight() end,
        set = function(v) ScrollTo(v, true) end,
        step = 70,
    })
    scrollbar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 10, -8)
    scrollbar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 10, 8)
end

local function BuildFooter()
    local f = CreateFrame("Frame", nil, content)
    f:SetPoint("BOTTOMLEFT"); f:SetPoint("BOTTOMRIGHT")
    f:SetHeight(T.FOOTER_H)
    local sep = T.Fill(f, "ARTWORK", "divider")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT"); sep:SetPoint("TOPRIGHT")
    T.OnTheme(function() sep:SetColorTexture(T.RGBA("divider")) end)

    window.resetBtn = W.ConfirmButton(f, L["Reset Page"], 150, function()
        local def = pages[current]
        if def and def.onReset then
            def.onReset(currentTab)
            Options:RefreshCurrent()
            EV:Print(L["Settings reset to defaults:"], def.title)
        end
    end)
    window.resetBtn:SetPoint("LEFT", T.PAD, 0)

    window.reloadBtn = W.Button(f, L["Reload UI"], 150, function() ReloadUI() end)
    window.reloadBtn:SetPoint("LEFT", window.resetBtn, "RIGHT", 10, 0)

    local done = W.Button(f, L["Done"], 120, function() window:Hide() end, "accent")
    done:SetPoint("RIGHT", -T.PAD, 0)
end

local function BuildWindow()
    window = CreateFrame("Frame", "EvermoreUIOptionsFrame", UIParent)
    window:SetSize(T.W, T.H)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetScale(EV.DB:GetCore().panelScale or 1)
    tinsert(UISpecialFrames, "EvermoreUIOptionsFrame")  -- Esc closes

    T.Shadow(window, 12)
    -- Our window: base surface, theme border, and a faint accent wash
    -- across the top.
    local base = T.Fill(window, "BACKGROUND", "surface0", 0.97)
    base:SetAllPoints()
    local wash = T.Fill(window, "BACKGROUND", "accent", 0, 1)
    wash:SetPoint("TOPLEFT"); wash:SetPoint("TOPRIGHT"); wash:SetHeight(220)
    T.TokenBorder(window, "border")
    T.OnTheme(function()
        base:SetColorTexture(T.RGBA("surface0", 0.97))
        if wash.SetGradient and CreateColor then
            local r, g, b = T.RGBA("accent")
            wash:SetColorTexture(1, 1, 1, 1)
            wash:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.07))
        else
            wash:Hide()
        end
        T.SetBorderToken(window, "border")
    end)

    content = CreateFrame("Frame", nil, window)
    content:SetPoint("TOPLEFT", T.SIDEBAR_W, 0)
    content:SetPoint("BOTTOMRIGHT")

    BuildSidebar()
    BuildHeader()
    BuildScroll()
    BuildFooter()
    -- Contrast changes repaint the nav and tabs (their colours are tokens),
    -- and pages (built once, coloured at build time) are rebuilt.
    local firstTheme = true
    T.OnTheme(function()
        PaintNav(); PaintTabs()
        if firstTheme then firstTheme = false return end
        Options:Rebuild()
    end)

    window:SetScript("OnShow", function() Options:RefreshCurrent(); PaintReload() end)
    window:SetScript("OnHide", function() T.HideTooltip() end)
    window:Hide()
end

function Options:SetScale(s)
    EV.DB:GetCore().panelScale = s
    if window then window:SetScale(s) end
end

function Options:Toggle()
    if InCombatLockdown() then
        EV:Print(L["Options are available out of combat."])
        return
    end
    if not window then
        BuildWindow()
        window:Show()
        self:ShowPage(order[1])
        return
    end
    window:SetShown(not window:IsShown())
end

function Options:Frame() return window end

-- Close in combat: nothing here is protected, but keeping the panel out of
-- the way mid-fight is kinder and avoids fighting with movers.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function() if window and window:IsShown() then window:Hide() end end)
