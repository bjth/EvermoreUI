if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Tabs.lua
--  Our own tab faces. Blizzard's tab strip stays alive but invisible
--  (GeneralDockManager alpha 0): every click, drag, right-click menu, new
--  window and whisper tab is still Blizzard's own, so none of it taints.
--  We draw a face over each docked tab: a mouse-transparent frame anchored
--  to the tab (anchored, never parented), so it follows the tab through
--  drags and scrolling in the same frame. Nothing is ever written to a tab.
--
--  Vertically every face sits in our tab band, which is glued to the top of
--  the chat panel, so the tabs always line up with the panel below them.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local CFD, issecret = ns.CFD, ns.issecret

local T = {}
ns.Tabs = T

--------------------------------------------------------------------------------
--  Band: our row above the panel. Always positioned; its background only
--  shows with "tabs inside the panel".
--------------------------------------------------------------------------------
local band = CreateFrame("Frame", nil, UIParent)
band:SetFrameStrata("BACKGROUND")
band:SetFrameLevel(1)
band:EnableMouse(false)
band.bg = band:CreateTexture(nil, "BACKGROUND")
band.bg:SetAllPoints()
EV.Pixel.NoSnap(band.bg)
band.div = band:CreateTexture(nil, "OVERLAY", nil, 7)
band.div:SetPoint("BOTTOMLEFT")
band.div:SetPoint("BOTTOMRIGHT")
EV.Pixel.NoSnap(band.div)
band:Hide()
T.band = band

-- Lane: hosts and clips the faces. Motion-only mouse with propagation, so
-- clicks and tooltips reach Blizzard's tabs beneath while we still learn
-- that the cursor is over the tabs (which wakes the chat and its watch).
local function PassThrough(f)
    if not f.SetMouseClickEnabled then
        f:EnableMouse(false) -- older client: no motion-only mode, stay out of the way
        return
    end
    f:SetMouseMotionEnabled(true)
    f:SetMouseClickEnabled(false)
    for _, setter in ipairs({ "SetPropagateMouseMotion", "SetPropagateMouseClicks" }) do
        if f[setter] then f[setter](f, true) end
    end
end

local lane = CreateFrame("Frame", nil, UIParent)
lane:SetAllPoints(band)
lane:SetClipsChildren(true)
-- Above the panel border, which sits a few levels below this in MEDIUM.
lane:SetFrameStrata("MEDIUM")
lane:SetFrameLevel(100)
PassThrough(lane)
lane:Hide()
T.lane = lane

-- Tabs that scroll on overflow (everything but the pinned General and Combat
-- Log) clip where Blizzard's scroll window clips them.
local scrollClip = CreateFrame("Frame", nil, lane)
scrollClip:SetClipsChildren(true)
scrollClip:EnableMouse(false)
local scrollClipReady = false
local function ScrollClip()
    if scrollClipReady then return scrollClip end
    local sf = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.scrollFrame
    if not sf then return nil end
    scrollClip:SetPoint("TOP", lane, "TOP")
    scrollClip:SetPoint("BOTTOM", lane, "BOTTOM")
    scrollClip:SetPoint("LEFT", sf, "LEFT")
    scrollClip:SetPoint("RIGHT", sf, "RIGHT")
    scrollClipReady = true
    return scrollClip
end

function T.SetHoverHandlers(onEnter, onLeave)
    lane:SetScript("OnEnter", onEnter)
    lane:SetScript("OnLeave", onLeave)
end

--------------------------------------------------------------------------------
--  Faces
--------------------------------------------------------------------------------
local docked, floating = {}, {}

local function NewFace(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:EnableMouse(false)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    EV.Pixel.NoSnap(g.bg)
    g.text = g:CreateFontString(nil, "OVERLAY")
    g.text:SetWordWrap(false)
    g.text:SetJustifyH("CENTER")
    g.text:SetFont(ns.FontPath(), M.db.tabFontSize, ns.FontFlags())
    g.line = g:CreateTexture(nil, "OVERLAY", nil, 7)
    g.line:SetPoint("BOTTOMLEFT")
    g.line:SetPoint("BOTTOMRIGHT")
    EV.Pixel.NoSnap(g.line)
    g.sep = g:CreateTexture(nil, "OVERLAY", nil, 7)
    g.sep:SetPoint("TOPLEFT", g, "TOPRIGHT")
    g.sep:SetPoint("BOTTOMLEFT", g, "BOTTOMRIGHT")
    EV.Pixel.NoSnap(g.sep)
    g.edge = CreateFrame("Frame", nil, g)
    g.edge:SetAllPoints()
    -- Whisper alert: Blizzard's glow art on our own texture and animation.
    g.glow = g:CreateTexture(nil, "OVERLAY", nil, 6)
    g.glow:SetTexture("Interface\\ChatFrame\\ChatFrameTab-NewMessage")
    g.glow:SetBlendMode("ADD")
    if g.glow.SetDesaturated then g.glow:SetDesaturated(true) end
    g.glow:SetPoint("TOPLEFT", g, "TOPLEFT", 6, -8)
    g.glow:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -6, 0)
    g.glow:Hide()
    g.pulse = g.glow:CreateAnimationGroup()
    g.pulse:SetLooping("BOUNCE")
    local a = g.pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.2)
    a:SetToAlpha(0.8)
    a:SetDuration(0.5)
    function g:Flash(on)
        if on then
            if not self.pulse:IsPlaying() then self.glow:Show(); self.pulse:Play() end
        elseif self.pulse:IsPlaying() or self.glow:IsShown() then
            self.pulse:Stop(); self.glow:Hide()
        end
    end
    return g
end

local function Alerting(tab)
    if tab.alerting then return true end
    local lca = LibStub and LibStub("LibChatAnims", true)
    return lca and lca.IsAlerting and lca:IsAlerting(tab) and true or false
end

-- Tabs the mouse is over (Blizzard's tab buttons take the mouse; our
-- faces only draw), so they light up like every other EvermoreUI tab.
local hovered = setmetatable({}, { __mode = "k" })
local hookedTabs = setmetatable({}, { __mode = "k" })
local function WatchHover(tab)
    if hookedTabs[tab] or not tab.HookScript then return end
    hookedTabs[tab] = true
    tab:HookScript("OnEnter", function(self) hovered[self] = true; T.Refresh() end)
    tab:HookScript("OnLeave", function(self) hovered[self] = nil; T.Refresh() end)
end

local function TextColour(cf, active, hover)
    if cf.isTemporary then
        local info = ChatTypeInfo and ChatTypeInfo[cf.chatType == "BN_WHISPER" and "BN_WHISPER" or "WHISPER"]
        if info then return info.r, info.g, info.b, 1 end
    end
    if not active then return EV.Theme.RGBA(hover and "text" or "textMuted") end
    local mode = M.db.tabActiveText
    if mode == "accent" then return EV.Theme.RGBA("accent") end
    if mode == "class" then local r, g, b = ns.ClassColour(); return r, g, b, 1 end
    return EV.Theme.RGBA("text")
end

local function Label(g, cf, tab)
    -- The tab's own label is the truth (renamed windows, whisper names). It
    -- can be a secret value; SetText takes those as they are.
    local text = tab.Text or (tab.GetFontString and tab:GetFontString())
    local label = text and text.GetText and text:GetText()
    if not issecret(label) and label == nil then
        label = GetChatWindowInfo and GetChatWindowInfo(cf:GetID()) or ""
    end
    g.text:SetText(label)
end

local function Style(g, cf, tab, active, inBand)
    local db = M.db
    local one = ns.Px(1)
    local TH = EV.Theme
    WatchHover(tab)
    local hover = hovered[tab] and not active
    g.text:SetFont(ns.FontPath(), db.tabFontSize, ns.FontFlags())
    ns.ApplyShadow(g.text)
    local r, gg, b, a = TextColour(cf, active, hover)
    g.text:SetTextColor(r, gg, b, a)
    g.glow:SetVertexColor(r, gg, b)
    Label(g, cf, tab)
    -- Blizzard sizes each tab for its own font; ours can be wider. The
    -- padding gives way (down to 4px) before the label is cut short.
    local pad = ns.Px(db.tabPadding)
    local w = g:GetWidth()
    local sw = g.text.GetUnboundedStringWidth and g.text:GetUnboundedStringWidth()
    if w and sw and not issecret(w) and not issecret(sw) and w > 0 then
        pad = math.max(ns.Px(4), math.min(pad, (w - sw) / 2))
    end
    g.text:ClearAllPoints()
    g.text:SetPoint("LEFT", g, "LEFT", pad, 0)
    g.text:SetPoint("RIGHT", g, "RIGHT", -pad, 0)

    -- Selected: a raised surface; hover: a lighter one (our tab language).
    -- In the band the fill stops a pixel short of the top, so the panel's
    -- border runs unbroken over the tabs instead of the selected one
    -- poking up through it.
    g.bg:ClearAllPoints()
    g.bg:SetPoint("TOPLEFT", g, "TOPLEFT", 0, inBand and -one or 0)
    g.bg:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", 0, 0)
    if inBand then
        if active then g.bg:SetColorTexture(TH.RGBA("surface1", 1))
        elseif hover then g.bg:SetColorTexture(TH.RGBA("surface1", 0.5))
        else g.bg:SetColorTexture(0, 0, 0, 0) end
    else
        local token = (active or hover) and "surface1" or "surface0"
        g.bg:SetColorTexture(TH.RGBA(token, active and db.tabActiveBgAlpha or db.tabBgAlpha))
    end

    g.line:SetHeight(ns.Px(2))
    if active and db.tabUnderline then
        g.line:SetColorTexture(TH.RGBA("accent"))
        g.line:Show()
    elseif hover and db.tabUnderline then
        g.line:SetColorTexture(TH.RGBA("borderStrong"))
        g.line:Show()
    else
        g.line:Hide()
    end

    g.sep:SetWidth(one)
    g.sep:SetColorTexture(unpack(ns.DIVIDER))
    g.sep:SetShown(inBand and db.dividers)

    local showEdge = not inBand and db.border
    local er, eg, eb = TH.RGBA("border")
    EV.Pixel:CreateBorder(g.edge, 1, er, eg, eb, showEdge and 1 or 0)
    g.edge:SetShown(showEdge)
end

--------------------------------------------------------------------------------
--  Placement
--------------------------------------------------------------------------------

--- Position the band on the dock panel. Called whenever panels move.
function T.PlaceBand()
    local panel = ns.DockPanel and ns.DockPanel()
    if not panel then return end
    local db = M.db
    local h = ns.Snap(ns.Px(db.tabHeight))
    band:ClearAllPoints()
    band:SetPoint("BOTTOMLEFT", panel, "TOPLEFT")
    band:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT")
    band:SetHeight(h)
    local bg = ns.BG
    band.bg:SetColorTexture(bg[1], bg[2], bg[3], db.bgAlpha)
    band.bg:SetShown(db.tabsInPanel)
    band.div:SetHeight(ns.Px(1))
    band.div:SetColorTexture(unpack(ns.DIVIDER))
    band.div:SetShown(db.tabsInPanel and db.dividers)
    local visible = not ns.hidden
    band:SetShown(visible)
    lane:SetShown(visible)
end

local function RefreshNow()
    T.PlaceBand()
    local db = M.db
    local inBand = db.tabsInPanel
    local selected = ns.Selected()
    local sc = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.scrollFrame
    local scrollChild = sc and sc.GetScrollChild and sc:GetScrollChild()

    -- The first face reaches left to the panel's edge, so the row starts
    -- where the panel does (Blizzard's first tab starts at the frame edge).
    local stretch = 0
    local list = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
    local first = type(list) == "table" and list[1]
    local firstTab = first and ns.TabOf(first)
    local bl, tl = band:GetLeft(), firstTab and firstTab:GetLeft()
    if bl and tl and not issecret(bl) and not issecret(tl) then
        local d = bl - tl
        if d < 0 and d > -80 then stretch = d end
    end

    local count, seenScrolling = 0, false
    local gap = ns.Px(db.tabSpacing)
    if type(list) == "table" then
        for i = 1, #list do
            local cf = list[i]
            local tab = cf and ns.TabOf(cf)
            if tab then
                count = count + 1
                local g = docked[count]
                if not g then g = NewFace(lane); docked[count] = g end
                g.cf = cf
                local scrolling = scrollChild and tab:GetParent() == scrollChild
                local parent = (scrolling and ScrollClip()) or lane
                if g:GetParent() ~= parent then g:SetParent(parent) end
                -- Blizzard leaves one unit between tabs in each group.
                local nativeGap = (scrolling and not seenScrolling) and 0 or 1
                if scrolling then seenScrolling = true end
                local left = (count == 1) and stretch or 0
                if count > 1 and not inBand then left = gap - nativeGap end
                g:ClearAllPoints()
                g:SetPoint("TOP", band, "TOP")
                g:SetPoint("BOTTOM", band, "BOTTOM")
                g:SetPoint("LEFT", tab, "LEFT", left, 0)
                g:SetPoint("RIGHT", tab, "RIGHT")
                local active = cf == selected
                Style(g, cf, tab, active, inBand)
                g:Flash(not active and Alerting(tab))
                g:Show()
            end
        end
    end
    for i = count + 1, #docked do
        docked[i].cf = nil
        docked[i]:Flash(false)
        docked[i]:Hide()
    end

    -- Undocked windows: their own face on their own panel.
    local seen = {}
    for _, cf in ipairs(ns.ChatFrames()) do
        local tab = ns.TabOf(cf)
        local panel = CFD(cf).panel
        if tab and panel and not cf.isDocked and cf:IsShown()
            and (not cf.isTemporary or cf.inUse) then
            local g = floating[cf]
            if not g then g = NewFace(panel); floating[cf] = g end
            if g:GetParent() ~= panel then g:SetParent(panel) end
            g.cf = cf
            g:SetFrameLevel(panel:GetFrameLevel() + 8)
            g:ClearAllPoints()
            g:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT")
            g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT")
            g:SetHeight(ns.Snap(ns.Px(db.tabHeight)))
            Style(g, cf, tab, true, false)
            g:Show()
            seen[cf] = true
        end
    end
    for cf, g in pairs(floating) do
        if not seen[cf] then g.cf = nil; g:Flash(false); g:Hide() end
    end
end
T.RefreshNow = RefreshNow

-- Many things ask for a refresh in the same frame; one pass next frame
-- answers them all.
T.Refresh = ns.Deferred(function() RefreshNow() end)

--------------------------------------------------------------------------------
--  Keep Blizzard's tab strip invisible (re-asserted; Blizzard never writes the
--  dock manager's own alpha, but its tabs fade themselves constantly)
--------------------------------------------------------------------------------
--- Alpha 0, written only when it is not already (a secret reads as "not").
local function Invisible(obj)
    if not obj.SetAlpha then return end
    local alpha = obj:GetAlpha()
    if issecret(alpha) or alpha ~= 0 then obj:SetAlpha(0) end
end

local function HideRegions(tab)
    for _, region in ipairs({ tab:GetRegions() }) do Invisible(region) end
end

function T.Sweep()
    local dock = GeneralDockManager
    if dock then
        Invisible(dock)
        -- Except the overflow button (too many tabs) and its list, which
        -- stay visible and usable.
        local overflow = dock.overflowButton
        for _, f in ipairs({ overflow or false, overflow and overflow.list or false }) do
            if f and f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
        end
    end
    for _, cf in ipairs(ns.ChatFrames()) do
        if not cf.isDocked then
            local tab = ns.TabOf(cf)
            if tab then HideRegions(tab) end
        end
    end
end

--------------------------------------------------------------------------------
--  Whisper flash, driven from the engine's message tail
--------------------------------------------------------------------------------
local FLASH = { WHISPER = true, BN_WHISPER = true }

local function FaceOf(cf)
    for _, g in ipairs(docked) do if g.cf == cf and g:IsShown() then return g end end
    return floating[cf]
end

--- Whether a line of this type should flash cf's tab: whispers only, only a
--- docked tab you are not looking at, and only if the chat type's own
--- setting (a separate one for the General window) says so.
local function WantsFlash(cf, chatType)
    if not (FLASH[chatType] and cf.isDocked) or cf == ns.Selected() then return false end
    local info = ChatTypeInfo and ChatTypeInfo[chatType]
    if not info then return false end
    return info[cf == DEFAULT_CHAT_FRAME and "flashTabOnGeneral" or "flashTab"] and true or false
end

local function OnMessage(cf, event)
    -- A window that just got its first line may need a tab drawn.
    if not FaceOf(cf) and (cf.isDocked or cf:IsShown()) then T.Refresh() end
    if not event or issecret(event) then return end
    if not WantsFlash(cf, (event:gsub("^CHAT_MSG_", ""))) then return end
    local g = FaceOf(cf)
    if g then g:Flash(true) end
end

function T.Init()
    if ns.Engine then ns.Engine.AddTailObserver(OnMessage) end
    T.Sweep()
    RefreshNow()
end

function T.SetAlpha(a)
    band:SetAlpha(a)
    lane:SetAlpha(a)
end

function T.SetShown(shown)
    band:SetShown(shown)
    lane:SetShown(shown)
end
