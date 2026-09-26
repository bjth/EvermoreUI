if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Chat.lua
--  Panels, the input box, Blizzard chrome, the main window's position and
--  size, idle fade, and the passes that keep it all in step.
--
--  Layout (main window, top to bottom, all edges on whole pixels):
--      [ tab band      ]   our own tab faces (Tabs.lua), inside the panel or islands
--      [ text area     ]   our message frame over Blizzard's invisible text
--      [ divider       ]
--      [ input box     ]
--  with the sidebar flush on the left or right, and one border round it all.
--
--  The panel is ours (a UIParent child) and is placed numerically from the
--  chat frame's rectangle, one tick after anything changes; nothing of ours
--  ever sits in Blizzard's anchor chain. The docked windows share one panel,
--  so switching tabs only swaps the text, never the background.
--
--  The main window's position belongs to EvermoreUI once we've first seen it:
--  an invisible block the size of the whole stack is registered with our
--  edit mode (drag to move, corner grip to resize), and ChatFrame1 is placed
--  inside it by two corner anchors (so its size never needs SetSize, which
--  would run Blizzard's dock code tainted).
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local CFD, issecret, Px, Snap = ns.CFD, ns.issecret, ns.Px, ns.Snap
local E, T = ns.Engine, ns.Tabs
local max, min, floor, abs = math.max, math.min, math.floor, math.abs

local MOVER_KEY = "CHAT_main"
local skinned = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
--  Geometry (UIParent units, whole pixels)
--------------------------------------------------------------------------------
local G = {}
ns.G = G

function G.padX() return Snap(Px(8)) end
function G.padR() return Snap(Px(14)) end           -- room for our scroll bar
function G.padTop() return Snap(Px(6)) end
function G.gap() return Snap(Px(4)) end              -- text to divider
function G.editH() return Snap(Px(M.db.editHeight)) end
function G.tabH() return Snap(Px(M.db.tabHeight)) end
function G.padBottom()
    if M.db.inputOnTop then return Snap(Px(6)) end
    return G.gap() + G.editH()
end

-- Sidebar space the main block reserves (only when always visible).
function G.sideW()
    if M.db.sidebar ~= "always" then return 0 end
    return Snap(Px(M.db.sidebarWidth))
end

--- Insets from ChatFrame1's rect to the outer edge of the whole stack.
function G.blockInsets()
    local sw = G.sideW()
    local l = G.padX() + (M.db.sidebarRight and 0 or sw)
    local r = G.padR() + (M.db.sidebarRight and sw or 0)
    return l, r, G.padTop() + G.tabH(), G.padBottom()
end

--------------------------------------------------------------------------------
--  Panels
--------------------------------------------------------------------------------
local function NewPanel(cf)
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata(cf:GetFrameStrata())
    p:SetFrameLevel(max(0, cf:GetFrameLevel() - 1))
    p.bg = p:CreateTexture(nil, "BACKGROUND", nil, -8)
    p.bg:SetAllPoints()
    EV.Pixel.NoSnap(p.bg)
    p.div = p:CreateTexture(nil, "OVERLAY", nil, 7)
    EV.Pixel.NoSnap(p.div)
    p:EnableMouse(false)
    return p
end

--- The panel shared by every docked window (ChatFrame1's).
function ns.DockPanel() return ChatFrame1 and CFD(ChatFrame1).panel end

--- Which panel a window's text lives on.
function ns.HostOf(cf)
    if cf.isDocked or cf == ChatFrame1 then return ns.DockPanel() end
    local d = CFD(cf)
    if not d.panel then d.panel = NewPanel(cf) end
    return d.panel
end

local function StylePanel(p)
    local db, bg = M.db, ns.BG
    p.bg:SetColorTexture(bg[1], bg[2], bg[3], db.bgAlpha)
    p.div:ClearAllPoints()
    p.div:SetHeight(Px(1))
    p.div:SetColorTexture(unpack(ns.DIVIDER))
    if db.inputOnTop then
        p.div:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -(G.padTop() + G.editH()))
        p.div:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -(G.padTop() + G.editH()))
    else
        p.div:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, G.editH())
        p.div:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, G.editH())
    end
    p.div:SetShown(db.dividers)
end

--- A frame's edges in UIParent units: left, top, right, bottom. Nil while it
--- has no rect yet, or when any part of it reads secret.
local function RectInUI(f)
    local x, y, w, h = f:GetRect()
    for _, v in ipairs({ x or false, y or false, w or false, h or false }) do
        if not v or issecret(v) then return nil end
    end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, (y + h) * k, (x + w) * k, y * k
end

-- Place one panel from its window's rect. Only from our own deferred or
-- watch execution: reading a chat frame's rect mid-dock is as bad as
-- writing it.
local function PlacePanel(cf, p)
    local l, t, r, b = RectInUI(cf)
    if not l then return end
    l, r = l - G.padX(), r + G.padR()
    t, b = t + G.padTop(), b - G.padBottom()
    if r - l < 1 or t - b < 1 then return end
    local d = CFD(p)
    if d.l and abs(d.l - l) < 0.05 and abs(d.t - t) < 0.05 and abs(d.r - r) < 0.05 and abs(d.b - b) < 0.05 then
        return
    end
    d.l, d.t, d.r, d.b = l, t, r, b
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    p:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", r, b)
end

function ns.PositionPanelsNow()
    local dock = ns.DockPanel()
    if dock and ChatFrame1 then PlacePanel(ChatFrame1, dock) end
    for _, cf in ipairs(ns.ChatFrames()) do
        local p = CFD(cf).panel
        if p and p ~= dock and not cf.isDocked and cf:IsShown() then PlacePanel(cf, p) end
    end
end

-- The border and the hover area wrap the whole main stack.
local border = CreateFrame("Frame", nil, UIParent)
border:SetFrameStrata("MEDIUM")
border:SetFrameLevel(96)
border:EnableMouse(false)
ns.border = border
-- The same soft outer shadow our windows have, so chat separates from the
-- world the same way.
border.shadow = EV.Theme.Shadow(border, 8)

local function PlaceBorder()
    local dock = ns.DockPanel()
    if not dock then return end
    local db = M.db
    local side = ns.Sidebar and ns.Sidebar.frame
    -- Only an always-on sidebar is part of the stack; a hover one floats.
    local useSide = side and side:IsShown() and db.sidebar == "always"
    local top = db.tabsInPanel and T.band or dock
    border:ClearAllPoints()
    -- The sidebar spans exactly the band and panel, so its corners are the
    -- stack's corners on its side.
    if useSide and not db.sidebarRight then
        border:SetPoint("TOPLEFT", side, "TOPLEFT")
    else
        border:SetPoint("TOPLEFT", top, "TOPLEFT")
    end
    if useSide and db.sidebarRight then
        border:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT")
    else
        border:SetPoint("BOTTOMRIGHT", dock, "BOTTOMRIGHT")
    end
    EV.Pixel:CreateBorder(border, 1, unpack(ns.BORDER))
    border:SetShown(db.border and not ns.hidden)
end
ns.PlaceBorder = PlaceBorder

--------------------------------------------------------------------------------
--  Input box
--------------------------------------------------------------------------------
local function EditFontSize(cf)
    local s = M.db.editFontSize
    return (s and s > 0) and s or ns.FontSize(cf:GetID())
end

local function EditHeaderFont(eb)
    local cf = eb.chatFrame or eb:GetParent()
    local size = cf and cf.GetID and EditFontSize(cf) or 14
    for _, fs in ipairs({ eb.header, eb.headerSuffix }) do
        if fs and fs.SetFont then fs:SetFont(ns.FontPath(), size, ns.FontFlags()) end
    end
end

function ns.PlaceEditBox(cf)
    local eb = ns.EditBoxOf(cf)
    if not eb then return end
    local db = M.db
    eb:ClearAllPoints()
    if db.inputOnTop then
        eb:SetPoint("TOPLEFT", cf, "TOPLEFT", -G.padX(), 0)
        eb:SetPoint("TOPRIGHT", cf, "TOPRIGHT", G.padR(), 0)
    else
        eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -G.padX(), -G.gap())
        eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", G.padR(), -G.gap())
    end
    eb:SetHeight(G.editH())
    eb:SetFont(ns.FontPath(), EditFontSize(cf), ns.FontFlags())
    ns.ApplyShadow(eb)
    eb:SetTextInsets(G.padX(), G.padX(), 0, 0)
    EditHeaderFont(eb)
end

-- With the input on top, our text gives up the strip the box covers, but
-- only while that box is up.
function ns.RefreshInputStrips()
    local db = M.db
    for _, cf in ipairs(ns.ChatFrames()) do
        local d = CFD(cf)
        local want = 0
        if db.inputOnTop then
            local eb = ns.EditBoxOf(cf)
            local up = eb and eb:IsShown()
            if not up and cf.isDocked then
                local main = ChatFrame1EditBox
                up = main and main:IsShown()
            end
            if up then want = G.editH() + G.gap() end
        end
        if d.inputTopExtra ~= want then
            d.inputTopExtra = want
            E.Layout(cf)
        end
    end
end

-- Plain Up/Down recall of what you sent (the Midnight box only recalls with
-- Alt). Physical key input only; never in restricted content, never secure
-- slash commands (text we put in the box would make their send tainted).
local function InstallRecall(eb)
    local d = CFD(eb)
    if d.recall then return end
    d.recall, d.history, d.index = true, {}, 0
    if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
    eb:HookScript("OnKeyDown", function(self, key)
        if not M.db.recall or (key ~= "UP" and key ~= "DOWN") or IsAltKeyDown() then return end
        if ns.Restricted() then return end
        local s = CFD(self)
        local h = s.history
        if #h == 0 then return end
        s.index = key == "UP" and min(#h, s.index + 1) or max(0, s.index - 1)
        self:SetText(s.index == 0 and "" or (h[#h - s.index + 1] or ""))
    end)
end

--------------------------------------------------------------------------------
--  Sent-line memory for Up/Down recall
--------------------------------------------------------------------------------
local RECALL_MAX = 50

--- Worth remembering? Checked for type and secrecy before anything compares
--- it: this runs one step before the line is sent, and an error here would
--- swallow the message. Secure slash commands are never kept.
local function Recallable(text)
    if type(text) ~= "string" or issecret(text) or text == "" then return false end
    local command = text:match("^%s*(/%S+)")
    return not (command and IsSecureCmd and IsSecureCmd(command))
end

local function Remember(list, text)
    if list[#list] == text then return end -- same line twice in a row: once
    list[#list + 1] = text
    if #list > RECALL_MAX then table.remove(list, 1) end
end

-- Edit box state from Blizzard's chat events, permanent windows only.
local EDIT_BOX_EVENTS = {
    OnEditBoxShow = function() ns.RefreshInputStrips() end,
    OnEditBoxHide = function() ns.RefreshInputStrips() end,
    OnEditBoxFocusGained = function(eb)
        EditHeaderFont(eb)
        ns.Activity(true)
    end,
    OnEditBoxFocusLost = function(eb)
        CFD(eb).index = 0
        ns.Activity(false)
    end,
    OnEditBoxPreSendText = function(eb)
        local list = CFD(eb).history
        if not list then return end
        local text = eb:GetText()
        if Recallable(text) then Remember(list, text) end
    end,
}

local callbacksDone = false
local function ChatStateCallbacks()
    if callbacksDone or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    callbacksDone = true
    for name, handler in pairs(EDIT_BOX_EVENTS) do
        EventRegistry:RegisterCallback("ChatFrame." .. name, function(_, eb)
            if ns.IsPermanent(eb) then handler(eb) end
        end, "EvermoreUIChat." .. name)
    end
end

local function SkinEditBox(cf)
    local eb = ns.EditBoxOf(cf)
    if not eb then return end
    local d = CFD(eb)
    if not d.skinned then
        d.skinned = true
        local name = cf:GetName()
        for _, suffix in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
            local tex = _G[name .. "EditBox" .. suffix]
            if tex then tex:SetAlpha(0) end
        end
        for _, key in ipairs({ "focusLeft", "focusMid", "focusRight" }) do
            if eb[key] then eb[key]:SetAlpha(0) end
        end
        -- Hooks only on permanent windows (1-10); temporary whisper windows
        -- handle secret names in their own secure code.
        if ns.IsPermanent(cf) then
            ChatStateCallbacks()
            InstallRecall(eb)
            eb:HookScript("OnChar", function() ns.Activity() end)
        end
    end
    ns.PlaceEditBox(cf)
end

--------------------------------------------------------------------------------
--  Blizzard chrome: hidden by alpha and mouse, re-asserted, never reparented
--------------------------------------------------------------------------------
local CHROME = {
    "QuickJoinToastButton", "ChatFrameMenuButton", "ChatFrameChannelButton",
    "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton",
}

-- Buttons Blizzard fades back in (UIFrameFadeIn), which no re-asserted
-- alpha can beat, so they hide themselves the moment they show. Only for
-- plain buttons that nothing secure reads the shown state of.
local keptHidden = setmetatable({}, { __mode = "k" })
local function KeepHidden(button)
    if not keptHidden[button] then
        keptHidden[button] = true
        button:HookScript("OnShow", function(self) self:Hide() end)
    end
    button:Hide()
end

local function Zero(f)
    if type(f) ~= "table" or not f.GetAlpha then return end
    local a = f:GetAlpha()
    if issecret(a) or a ~= 0 then f:SetAlpha(0) end
end

local function DeadMouse(f)
    if type(f) ~= "table" then return end
    if f.SetMouseClickEnabled then
        f:SetMouseClickEnabled(false)
        f:SetMouseMotionEnabled(false)
    elseif f.EnableMouse then
        f:EnableMouse(false)
    end
end

local function Strip(region)
    if not (region and region.IsObjectType and region:IsObjectType("Texture")) then return end
    if CFD(region).ours then return end
    region:SetTexture("")
    if region.SetAtlas then pcall(region.SetAtlas, region, "") end
    region:SetAlpha(0)
end

local function StripAll(frame)
    if frame and frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do Strip(r) end
    end
end

local function ChromeFor(cf)
    local name = cf:GetName()
    local bf = cf.buttonFrame or _G[name .. "ButtonFrame"]
    if bf then Zero(bf); DeadMouse(bf) end
    local mb = _G[name .. "MinimizeButton"]
    if mb then Zero(mb); DeadMouse(mb) end
    local sb = cf.ScrollToBottomButton
    if sb then
        Zero(sb); DeadMouse(sb)
        KeepHidden(sb)
    end
end

local function GlobalChrome()
    for _, n in ipairs(CHROME) do
        local f = _G[n]
        if f then Zero(f); DeadMouse(f) end
    end
end

-- The combat log's filter bar: our background, our font, accent for the
-- selected filter.
local function SkinCombatLogBar()
    local bar = CombatLogQuickButtonFrame_Custom
    if not bar or CFD(bar).skinned then return end
    CFD(bar).skinned = true
    StripAll(bar)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    CFD(bg).ours = true
    bg:SetAllPoints()
    bg:SetColorTexture(ns.BG[1], ns.BG[2], ns.BG[3], 0.9)
    local div = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    CFD(div).ours = true
    div:SetHeight(Px(1))
    div:SetColorTexture(unpack(ns.DIVIDER))
    div:SetPoint("BOTTOMLEFT")
    div:SetPoint("BOTTOMRIGHT")
    local buttons = {}
    local function colour()
        for _, b in ipairs(buttons) do
            local fs = b:GetFontString()
            if fs then
                fs:SetTextColor(EV.Theme.RGBA((b.GetChecked and b:GetChecked()) and "accent" or "textMuted"))
            end
        end
    end
    for _, b in ipairs({ bar:GetChildren() }) do
        if b.IsObjectType and (b:IsObjectType("CheckButton") or b:IsObjectType("Button")) then
            buttons[#buttons + 1] = b
            StripAll(b)
            local fs = b.GetFontString and b:GetFontString()
            if fs then fs:SetFont(ns.FontPath(), 12, ns.FontFlags()) end
            b:HookScript("OnClick", colour)
        end
    end
    colour()
end

--------------------------------------------------------------------------------
--  Hyperlink tooltips on hover
--------------------------------------------------------------------------------
local TOOLTIP_TYPES = {
    item = true, spell = true, achievement = true, quest = true, enchant = true, talent = true,
    currency = true, unit = true, instancelock = true, glyph = true, keystone = true, mount = true,
    battlepet = false, azessence = true, conduit = true, transmogillusion = true,
}

local function LinkEnter(frame, link)
    if not M.db.linkTooltips or issecret(link) or type(link) ~= "string" then return end
    local kind = link:match("^(%a+):")
    if not (kind and TOOLTIP_TYPES[kind]) then return end
    GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
        GameTooltip:Show()
        CFD(frame).tip = true
    else
        GameTooltip:Hide()
    end
end

local function LinkLeave(frame)
    if CFD(frame).tip then
        CFD(frame).tip = nil
        GameTooltip:Hide()
    end
end

--------------------------------------------------------------------------------
--  Skinning one window
--------------------------------------------------------------------------------
local function ApplyWindowFont(cf)
    ns.ApplyFont(cf, cf:GetID())
    if cf.SetFading then cf:SetFading(false) end
    -- Must match our message frame, or wrapped lines' link zones drift.
    if cf.SetIndentedWordWrap then cf:SetIndentedWordWrap(true) end
end

--- A window dropped with no anchors at all: centre it under the cursor, or
--- mid-screen if we cannot read where that is.
local function RescueUnanchored(f)
    if f.isDocked or f:GetNumPoints() > 0 then return end
    local scale = f:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local width, height = f:GetSize()
    local readable = scale and scale > 0 and cx and cy
    for _, v in ipairs({ cx or 0, cy or 0, width or 0, height or 0 }) do
        if issecret(v) then readable = false end
    end
    if not readable then
        f:SetPoint("CENTER", UIParent, "CENTER")
        return
    end
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale - width / 2, cy / scale + height / 2)
end

local function SkinChatFrame(cf)
    if skinned[cf] then return end
    skinned[cf] = true
    local name = cf:GetName()
    if not name then return end

    if cf == ChatFrame1 then
        local p = NewPanel(cf)
        CFD(cf).panel = p
        StylePanel(p)
    end

    -- 12.1 can end an undock drag with the window's anchors stripped, and
    -- Blizzard's very next line (the position save) then errors every frame.
    -- This has to land synchronously, between the two; it only ever acts on
    -- that broken, point-less state.
    hooksecurefunc(cf, "StopMovingOrSizing", RescueUnanchored)

    StripAll(cf)
    if cf.Background then
        cf.Background:SetAlpha(0)
        StripAll(cf.Background)
    end
    ApplyWindowFont(cf)
    if cf.SetHyperlinksEnabled then cf:SetHyperlinksEnabled(true) end

    if ns.IsPermanent(cf) then
        cf:HookScript("OnHyperlinkEnter", LinkEnter)
        cf:HookScript("OnHyperlinkLeave", LinkLeave)
    end

    SkinEditBox(cf)
    ChromeFor(cf)
    if name == "ChatFrame2" then SkinCombatLogBar() end
end

--------------------------------------------------------------------------------
--  State sync: what a parent would have done for us, plus re-asserted alphas
--------------------------------------------------------------------------------
local function Owned()
    local core = EV.DB:GetCore()
    return core.movers[MOVER_KEY] ~= nil or core.anchors[MOVER_KEY] ~= nil
end
ns.Owned = Owned

function ns.Sync()
    local cf1 = ChatFrame1
    if not cf1 then return end
    -- Blizzard clamps the window to the screen with a box that keeps room
    -- for the old tab strip and input box below it, and Edit Mode re-sets
    -- that box (from its selection frame) every time it applies a layout.
    -- That held the whole stack up off the bottom of the screen. Our block
    -- (which holds the tabs, text and input) is clamped to the screen
    -- itself, and the window always sits inside it, so the window's own
    -- clamp goes.
    if cf1.IsClampedToScreen and cf1:IsClampedToScreen() then cf1:SetClampedToScreen(false) end
    if cf1.GetClampRectInsets then
        local insets = { cf1:GetClampRectInsets() }
        for i = 1, 4 do
            if insets[i] ~= 0 then cf1:SetClampRectInsets(0, 0, 0, 0); break end
        end
    end
    -- Our edit mode owns the main window; Blizzard's selection overlay goes.
    if Owned() and ns.positionLive then
        for _, f in ipairs({ cf1.Selection, cf1.EditModeResizeButton }) do
            if f then Zero(f); DeadMouse(f) end
        end
    end
    for _, cf in ipairs(ns.ChatFrames()) do
        if cf:IsShown() then ChromeFor(cf) end
        local p = CFD(cf).panel
        if p and p ~= ns.DockPanel() then
            local shown = cf:IsShown() and not cf.isDocked and not ns.hidden
            if p:IsShown() ~= shown then p:SetShown(shown) end
        end
        if p and cf:IsShown() then
            -- Directly beneath its window, in the same strata.
            local strata, level = cf:GetFrameStrata(), max(0, cf:GetFrameLevel() - 1)
            if p:GetFrameLevel() ~= level then p:SetFrameLevel(level) end
            if p:GetFrameStrata() ~= strata then p:SetFrameStrata(strata) end
        end
    end
    local dock = ns.DockPanel()
    if dock then dock:SetShown(not ns.hidden) end
    GlobalChrome()
    T.Sweep()
    E.SyncShown()
end

--------------------------------------------------------------------------------
--  Main window position and size
--------------------------------------------------------------------------------
local block = CreateFrame("Frame", "EvermoreUIChatBlock", UIParent)
block:SetSize(460, 220)
block:SetClampedToScreen(true)
ns.block = block

local function MainSize()
    local s = M.db.size
    if type(s) == "table" and s.w and s.h then return s.w, s.h end
    return 430, 180
end

local function SizeBlock()
    local w, h = MainSize()
    local l, r, t, b = G.blockInsets()
    block:SetSize(Snap(w + l + r), Snap(h + t + b))
end

--- Put ChatFrame1 inside the block, as two corner anchors.
function ns.PlaceMain()
    if not (ns.positionLive and Owned()) then return end
    local cf1 = ChatFrame1
    local l, t, r, b = block:GetLeft(), block:GetTop(), block:GetRight(), block:GetBottom()
    if not (l and t and r and b) then return end
    local il, ir, it, ib = G.blockInsets()
    local k = UIParent:GetEffectiveScale() / cf1:GetEffectiveScale()
    cf1:ClearAllPoints()
    cf1:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (l + il) * k, (t - it) * k)
    cf1:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", (r - ir) * k, (b + ib) * k)
    ns.PositionPanelsNow()
    ns.ResyncSoon()
end

ns.ResyncSoon = ns.Deferred(function()
    ns.PositionPanelsNow()
    T.RefreshNow()
    PlaceBorder()
end)

-- First sight: take the window where Blizzard (or its Edit Mode) put it.
function ns.CaptureGenesis()
    if Owned() then return end
    local l, t, r, b = RectInUI(ChatFrame1)
    if not l then return end
    M.db.size = { w = Snap(r - l), h = Snap(t - b) }
    SizeBlock()
    local il, ir, it, ib = G.blockInsets()
    local ux, uy = UIParent:GetCenter()
    local cx = ((l - il) + (r + ir)) / 2 - ux
    local cy = ((t + it) + (b - ib)) / 2 - uy
    EV.Movers:SetOffset(MOVER_KEY, cx, cy)
end

local function RegisterMover()
    EV.Movers:Register(block, MOVER_KEY, L["Chat"], { "BOTTOMLEFT", "BOTTOMLEFT", 24, 24 }, {
        group = L["Chat"], page = "chat",
        getSize = function() return block:GetWidth(), block:GetHeight() end,
        setSize = function(w, h)
            local il, ir, it, ib = G.blockInsets()
            local cw, ch = MainSize()
            if w then cw = max(200, w - il - ir) end
            if h then ch = max(80, h - it - ib) end
            M.db.size = { w = Snap(cw), h = Snap(ch) }
            SizeBlock()
        end,
        -- Reset puts the chat back in the bottom-left corner at the default
        -- size, still ours. (Asking Blizzard to re-anchor it would run its
        -- Edit Mode code from ours.)
        onReset = function()
            M.db.size = { w = Snap(430), h = Snap(180) }
            SizeBlock()
            C_Timer.After(0, function()
                local x, y = EV.Movers:GetOffset(MOVER_KEY)
                EV.Movers:SetOffset(MOVER_KEY, x, y)
                ns.ResyncSoon()
            end)
        end,
    })
    -- Blizzard's Edit Mode re-anchors the window on layout changes; put ours
    -- back a tick later, outside its code.
    local cf1 = ChatFrame1
    if cf1.ApplySystemAnchor and not CFD(cf1).guarded then
        CFD(cf1).guarded = true
        hooksecurefunc(cf1, "ApplySystemAnchor", function()
            if Owned() then C_Timer.After(0, ns.PlaceMain) end
        end)
    end
end

--------------------------------------------------------------------------------
--  Watch: per-frame work, only while chat is being touched
--
--  Runs while the cursor is over the chat, while something holds it open
--  (unlocked movers, Edit Mode, an open menu), and for a few seconds after.
--  Then it sleeps until the next reason to wake.
--------------------------------------------------------------------------------
do
    local watch = CreateFrame("Frame")
    watch:Hide()
    local SLOW_EVERY, LINGER = 0.1, 4
    local reasons = { over = 0, hold = false, editMode = false }
    local sleepAfter, sinceSlow = 0, 0
    local seen = { selected = nil, docked = nil, shown = {}, size = {} }

    -- Every frame: the tab under a click should light the window up on the
    -- frame it happens, not a tick later.
    local function EveryFrame()
        ns.PositionPanelsNow()
        local list = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
        local docked = type(list) == "table" and #list or 0
        local selected = ns.Selected()
        if selected ~= seen.selected or docked ~= seen.docked then
            seen.selected, seen.docked = selected, docked
            T.RefreshNow()
            E.UpdateCombatLog()
        end
        E.SyncShown()
    end

    -- Ten times a second: things Blizzard changes without telling anyone,
    -- like a font size picked from a tab's menu.
    local function Slow()
        if reasons.editMode and EditModeManagerFrame and not EditModeManagerFrame:IsShown() then
            reasons.editMode = false
        end
        local visibilityChanged = false
        for _, cf in ipairs(ns.ChatFrames()) do
            local size = ns.FontSize(cf:GetID())
            local before = seen.size[cf]
            seen.size[cf] = size
            if before and before ~= size then
                ApplyWindowFont(cf)
                E.ApplyFont(cf)
            end
            local shown = cf:IsShown()
            if seen.shown[cf] ~= shown then
                seen.shown[cf] = shown
                visibilityChanged = true
            end
        end
        if visibilityChanged then ns.FullPass() end
        ns.Sync()
    end

    local function MenuOpen()
        local manager = Menu and Menu.GetManager and Menu.GetManager()
        return manager and manager:IsAnyMenuOpen() or false
    end

    local function CanSleep()
        if reasons.over > 0 or reasons.hold or reasons.editMode then return false end
        return GetTime() >= sleepAfter and not MenuOpen()
    end

    watch:SetScript("OnUpdate", function(self, elapsed)
        EveryFrame()
        sinceSlow = sinceSlow + elapsed
        if sinceSlow < SLOW_EVERY then return end
        sinceSlow = 0
        Slow()
        if CanSleep() then
            ns.PositionPanelsNow()
            self:Hide()
        end
    end)

    function ns.WatchStart()
        reasons.over = reasons.over + 1
        watch:Show()
    end
    function ns.WatchEnd()
        reasons.over = max(0, reasons.over - 1)
        if reasons.over == 0 then sleepAfter = GetTime() + LINGER end
    end
    function ns.WatchHold(on)
        reasons.hold = not not on
        if on then watch:Show() end
    end
    function ns.WatchEditMode(on)
        reasons.editMode = not not on
        if on then watch:Show() end
    end
end

--------------------------------------------------------------------------------
--  Undocked windows: Blizzard moves and resizes them with no event, so while
--  any are open a light watcher keeps their panels on them, and hovering one
--  wakes the per-frame watch for smooth drags.
--------------------------------------------------------------------------------
do
    local watch = CreateFrame("Frame")
    local acc, armed = 0, false
    watch:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        local any, over = false, false
        for _, cf in ipairs(ns.ChatFrames()) do
            if not cf.isDocked and cf:IsShown() and CFD(cf).panel then
                any = true
                local tab = ns.TabOf(cf)
                local o = cf:IsMouseOver() or (tab and tab:IsMouseOver())
                if o and not issecret(o) then over = true end
            end
        end
        if not any then
            if armed then armed = false; ns.WatchEnd() end
            return
        end
        if over ~= armed then
            armed = over
            if over then ns.WatchStart() else ns.WatchEnd() end
        end
        if not over then ns.PositionPanelsNow() end
    end)
end

--------------------------------------------------------------------------------
--  Idle fade
--------------------------------------------------------------------------------
do
    local current, target = 1, 1
    local faded = false
    local timer
    local hoverCount, focusCount = 0, 0
    local fader = CreateFrame("Frame")
    fader:Hide()

    local function Apply(a)
        local dock = ns.DockPanel()
        if dock then dock:SetAlpha(a) end
        for _, cf in ipairs(ns.ChatFrames()) do
            local p = CFD(cf).panel
            if p and p ~= dock then p:SetAlpha(a) end
            if cf:IsShown() then
                cf:SetAlpha(a)
                local eb = ns.EditBoxOf(cf)
                if eb then
                    local focused = eb:HasFocus()
                    if issecret(focused) then focused = false end
                    eb:SetAlpha((focused and not cf.isTemporary) and 1 or a)
                end
            end
        end
        T.SetAlpha(a)
        border:SetAlpha(a)
        if ns.Sidebar then ns.Sidebar.SetAlpha(a) end
    end

    fader:SetScript("OnUpdate", function(self, dt)
        if current == target then self:Hide(); Apply(current); return end
        local speed = dt / (target > current and 0.35 or 2.0)
        current = target > current and min(target, current + speed) or max(target, current - speed)
        Apply(current)
    end)

    local function FadeTo(a) target = a; fader:Show() end

    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("BACKGROUND")
    overlay:SetAllPoints(border)
    if overlay.SetMouseClickEnabled then
        overlay:SetMouseClickEnabled(false)
        overlay:SetMouseMotionEnabled(false)
        if overlay.SetPropagateMouseMotion then overlay:SetPropagateMouseMotion(true) end
    else
        overlay:EnableMouse(false)
    end

    local function StartFade()
        timer = nil
        if not M.db.idleFade or hoverCount > 0 or focusCount > 0 then return end
        faded = true
        FadeTo(1 - min(90, M.db.idleStrength) / 100)
        if overlay.SetMouseMotionEnabled then overlay:SetMouseMotionEnabled(true) end
    end

    local function Wake()
        if timer then timer:Cancel(); timer = nil end
        if faded then
            faded = false
            if overlay.SetMouseMotionEnabled then overlay:SetMouseMotionEnabled(false) end
        end
        FadeTo(1)
    end

    local function Restart()
        Wake()
        if M.db.idleFade and hoverCount == 0 and focusCount == 0 then
            timer = C_Timer.NewTimer(M.db.idleDelay, StartFade)
        end
    end
    ns.ResetIdle = Restart

    local last = 0
    --- Something happened in chat. focus: true/false for input focus edges.
    function ns.Activity(focus)
        if focus == true then focusCount = 1 elseif focus == false then focusCount = 0 end
        local now = GetTime()
        if focus == nil and now - last < 1 and not faded then return end
        last = now
        Restart()
    end

    function ns.Hover(on)
        hoverCount = max(0, hoverCount + (on and 1 or -1))
        Restart()
    end

    overlay:SetScript("OnEnter", function() ns.Activity() end)

    -- Chat's own frame takes the mouse over the text, so while faded also
    -- poll for the cursor over the whole stack.
    local poll = CreateFrame("Frame")
    local pollAcc = 0
    poll:SetScript("OnUpdate", function(_, dt)
        pollAcc = pollAcc + dt
        if pollAcc < 0.1 then return end
        pollAcc = 0
        if not faded then return end
        local over = border:IsMouseOver() or (ChatFrame1 and ChatFrame1:IsMouseOver())
        if issecret(over) then over = false end
        if over then ns.Activity() end
    end)

    local ACTIVE_EVENTS = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
    }
    local activeFrame = CreateFrame("Frame")
    for _, e in ipairs(ACTIVE_EVENTS) do pcall(activeFrame.RegisterEvent, activeFrame, e) end
    activeFrame:SetScript("OnEvent", function() ns.Activity() end)

    function ns.ApplyFade() Restart(); Apply(current) end
end

--------------------------------------------------------------------------------
--  Whisper sound
--------------------------------------------------------------------------------
ns.WHISPER_SOUNDS = {
    { value = "none", text = L["None"] },
    { value = "tell", text = L["Whisper chime"], kit = "TELL_MESSAGE" },
    { value = "bell", text = L["Bell"], kit = "RAID_WARNING" },
    { value = "ping", text = L["Soft ping"], kit = "UI_BNET_TOAST" },
}

local function PlayWhisperSound()
    local key = M.db.whisperSound
    for _, s in ipairs(ns.WHISPER_SOUNDS) do
        if s.value == key and s.kit and SOUNDKIT and SOUNDKIT[s.kit] then
            PlaySound(SOUNDKIT[s.kit], "Master")
            return
        end
    end
end
ns.PlayWhisperSound = PlayWhisperSound

do
    local QUIET_FOR = 5 -- seconds between whisper sounds, however many arrive
    local quietUntil = 0
    local f = CreateFrame("Frame")
    for _, event in ipairs({ "CHAT_MSG_BN_WHISPER", "CHAT_MSG_WHISPER" }) do f:RegisterEvent(event) end
    f:SetScript("OnEvent", function()
        ns.Activity()
        if M.db.whisperSound == "none" or GetTime() < quietUntil then return end
        quietUntil = GetTime() + QUIET_FOR
        PlayWhisperSound()
    end)
end

--------------------------------------------------------------------------------
--  CVars: timestamps are added by Blizzard's own formatter
--------------------------------------------------------------------------------
local function SetCV(name, value)
    if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, name, value)
    elseif SetCVar then pcall(SetCVar, name, value) end
end

function ns.ApplyCVars()
    local ts = M.db.timestamps
    if ts and ts ~= "blizzard" then SetCV("showTimestamps", ts) end
    SetCV("chatMouseScroll", "1")
end

--------------------------------------------------------------------------------
--  Passes
--------------------------------------------------------------------------------
local function SkinPass()
    for _, cf in ipairs(ns.ChatFrames()) do
        if not skinned[cf] then
            SkinChatFrame(cf)
        else
            -- Blizzard resets these on its own passes.
            local font = cf:GetFont()
            if font ~= ns.FontPath() then ApplyWindowFont(cf) end
            if cf.SetIndentedWordWrap then cf:SetIndentedWordWrap(true) end
        end
    end
end

local function AdoptAll()
    for _, cf in ipairs(ns.ChatFrames()) do
        if skinned[cf] then E.Adopt(cf, ns.HostOf(cf)) end
    end
    E.UpdateCombatLog()
end

local function LayoutAll()
    local dock = ns.DockPanel()
    if dock then StylePanel(dock) end
    for _, cf in ipairs(ns.ChatFrames()) do
        local p = CFD(cf).panel
        if p and p ~= dock then StylePanel(p) end
        if skinned[cf] then ns.PlaceEditBox(cf) end
    end
    ns.RefreshInputStrips()
    E.LayoutAll()
    SizeBlock()
end

ns.FullPass = ns.Deferred(function()
    SkinPass()
    AdoptAll()
    ns.Sync()
    ns.PositionPanelsNow()
    T.Sweep()
    T.RefreshNow()
    if ns.Sidebar then ns.Sidebar.Layout() end
    PlaceBorder()
end)

ns.TabPass = ns.Deferred(function()
    T.Sweep()
    T.RefreshNow()
    ns.Sync()
    ns.PositionPanelsNow()
    E.UpdateCombatLog()
end)

--- Everything, after a settings change.
function M:Refresh()
    if not self:IsEnabled() then return end
    ns.ApplyCVars()
    E.SetTransforms(self.db)
    for _, cf in ipairs(ns.ChatFrames()) do
        if skinned[cf] then ApplyWindowFont(cf) end
    end
    E.ApplyFonts()
    LayoutAll()
    E.RebuildAllSoon()
    EV.Movers:Apply(MOVER_KEY)
    ns.PlaceMain()
    ns.FullPass()
    ns.ApplyFade()
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
    local db = self.db
    E.SetTransforms(db)
    SkinPass()
    AdoptAll()
    T.Init()
    T.SetHoverHandlers(function() ns.WatchStart(); ns.Hover(true) end,
                       function() ns.WatchEnd(); ns.Hover(false) end)
    if ns.Sidebar then ns.Sidebar.Build() end
    if ns.InstallLinks then ns.InstallLinks() end
    SizeBlock()
    RegisterMover()
    LayoutAll()
    ns.ApplyCVars()
    C_Timer.After(2, ns.ApplyCVars)

    -- Everything that can make or reset a window, on our own frame.
    local pass = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS",
                         "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CHAT_MSG_WHISPER",
                         "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }) do
        pcall(pass.RegisterEvent, pass, e)
    end
    pass:SetScript("OnEvent", function(...) ns.ChatFramesDirty(); ns.FullPass(...) end)

    local em = CreateFrame("Frame")
    pcall(em.RegisterEvent, em, "EDIT_MODE_LAYOUTS_UPDATED")
    em:SetScript("OnEvent", function()
        ns.TabPass()
        C_Timer.After(0.1, ns.TabPass)
    end)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function() ns.WatchEditMode(true) end)
        EditModeManagerFrame:HookScript("OnHide", function() ns.WatchEditMode(false); ns.TabPass() end)
    end

    -- Position ownership starts at the first settled sight of the world.
    local live = CreateFrame("Frame")
    local function GoLive()
        if ns.positionLive then return end
        ns.positionLive = true
        live:UnregisterAllEvents()
        ns.CaptureGenesis()
        ns.PlaceMain()
        ns.FullPass()
        -- A short, bounded heal window for Edit Mode's late writes.
        local ticks, acc = 0, 0
        live:SetScript("OnUpdate", function(f, dt)
            acc = acc + dt
            if acc < 0.1 then return end
            acc = 0
            ticks = ticks + 1
            ns.Sync()
            ns.PositionPanelsNow()
            if ticks >= 30 then f:SetScript("OnUpdate", nil) end
        end)
    end
    live:RegisterEvent("LOADING_SCREEN_DISABLED")
    live:SetScript("OnEvent", GoLive)
    C_Timer.After(5, GoLive)

    self:RegisterMessage("EV_LAYOUT_CHANGED", function(_, _, key)
        if key == MOVER_KEY then ns.PlaceMain() end
    end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
    -- Contrast changes: repaint panels, tabs, sidebar and border.
    self:RegisterMessage("EV_THEME_CHANGED", function()
        ns.FullPass()
        if ns.Tabs and ns.Tabs.Refresh then ns.Tabs.Refresh() end
        if ns.PlaceBorder then ns.PlaceBorder() end
    end)
    self:RegisterMessage("EV_UNLOCK", function() ns.WatchHold(true) end)
    self:RegisterMessage("EV_LOCK", function() ns.WatchHold(false); ns.FullPass() end)

    ns.FullPass()
    ns.ApplyFade()
end

function M:OnProfileChanged()
    -- A new or reset profile has no saved chat position: take the chat
    -- where it is now rather than letting the block wander off.
    if ns.positionLive and not Owned() then ns.CaptureGenesis() end
    self:Refresh()
end
