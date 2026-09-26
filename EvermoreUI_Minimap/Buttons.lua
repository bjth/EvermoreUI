if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Buttons.lua
--  A column of flat glyph buttons down the map's right edge, each on a
--  small plate. Each is Blizzard's own button, moved into the column and
--  dressed, so its menu, tooltip and state logic are untouched:
--
--    tracking   MinimapCluster.Tracking.Button   (the tracking menu)
--    calendar   GameTimeFrame                    (copper while invites wait)
--    mail       MinimapCluster.IndicatorFrame.MailFrame        (copper)
--    orders     MinimapCluster.IndicatorFrame.CraftingOrderFrame (copper)
--    addons     AddonCompartmentFrame            (only with entries in it)
--
--  Blizzard shows and hides mail and orders itself and then calls
--  :Layout() on their parent; the row has one, so it reflows. Each button
--  is pinned: a post-hook on SetPoint / SetParent puts it back.
--
--  Also here: the queue eye (Blizzard anchors it to the round map's
--  corner) and the expansion landing-page button, both kept on the square.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local max = math.max

local CELL, GAP = 20, 3
local row
local entries = {}          -- { key, frame (what we move), click (what gets the glyph), glyph, alert() }

--------------------------------------------------------------------------------
--  Pinning
--------------------------------------------------------------------------------
local seats = setmetatable({}, { __mode = "k" })
local seating = false
local function Seat(f)
    local s = seats[f]
    if not s or seating then return end
    if InCombatLockdown() and f:IsProtected() then return end
    seating = true
    if f:GetParent() ~= s.parent then f:SetParent(s.parent) end
    f:ClearAllPoints()
    f:SetPoint(s.point, s.rel, s.relPoint, s.x, s.y)
    if s.w then f:SetSize(s.w, s.h) end
    seating = false
end
local function Pin(f, parent, point, rel, relPoint, x, y, w, h)
    local s = seats[f]
    if not s then
        s = {}
        seats[f] = s
        hooksecurefunc(f, "SetPoint", Seat)
        hooksecurefunc(f, "SetParent", Seat)
    end
    s.parent, s.point, s.rel, s.relPoint, s.x, s.y, s.w, s.h = parent, point, rel, relPoint, x, y, w, h
    Seat(f)
end
ns.Pin = Pin

--------------------------------------------------------------------------------
--  Dressing
--------------------------------------------------------------------------------
local function Fade(tex)
    if tex and tex.SetAlpha then tex:SetAlpha(0) end
end
local function FadeVertex(tex)
    if tex and tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 0) end
end

local function Paint(e)
    local hot = e.hover
    local alert = e.alert and e.alert()
    e.glyph:SetVertexColor(T.RGBA(alert and "accent" or (hot and "text" or "textMuted")))
    e.cell:SetColorTexture(T.RGBA(hot and "surface3" or "surface1", 0.92))
    T.SetBorderToken(e.edge, alert and "accent" or "border")
end

local function Dress(e)
    local host = e.click
    e.cell = host:CreateTexture(nil, "BACKGROUND", nil, 3)
    e.cell:SetAllPoints(e.frame)
    -- A plate so it reads on any terrain: our fill and a 1px border.
    e.edge = CreateFrame("Frame", nil, e.frame)
    e.edge:SetAllPoints(e.frame)
    e.edge:SetFrameLevel(host:GetFrameLevel() + 2)
    e.edge:EnableMouse(false)
    T.TokenBorder(e.edge, "border")
    e.glyph = host:CreateTexture(nil, "OVERLAY", nil, 3)
    e.glyph:SetTexture(ns.GLYPH .. e.glyphFile .. ".png")
    e.glyph:SetSize(13, 13)
    e.glyph:SetPoint("CENTER", e.frame, "CENTER")
    host:HookScript("OnEnter", function() e.hover = true; Paint(e) end)
    host:HookScript("OnLeave", function() e.hover = false; Paint(e) end)
    e.Paint = function() Paint(e) end
    T.Watch(e)
    Paint(e)
end
ns.PaintButtons = function() for _, e in ipairs(entries) do Paint(e) end end

--------------------------------------------------------------------------------
--  The row
--------------------------------------------------------------------------------
local function Visible(e)
    if e.visible then return e.visible() end
    if e.key == "addons" then
        local reg = e.frame.registeredAddons
        return type(reg) == "table" and #reg > 0
    end
    return e.frame:IsShown()
end

local laying = false
local function LayoutRow()
    if not row or laying then return end
    laying = true
    row:SetShown(M.db.buttons and true or false)
    local shown = {}
    for _, e in ipairs(entries) do
        if Visible(e) then
            shown[#shown + 1] = e
        elseif e.key == "addons" or e.visible then
            -- Blizzard shows the compartment even when it's empty; park it
            -- until an addon registers an entry.
            Pin(e.frame, ns.hidden, "CENTER", ns.hidden, "CENTER", 0, 0, CELL, CELL)
        end
        -- Mail and orders stay in the row while hidden: Blizzard shows them
        -- itself and then calls :Layout() on their parent (the row).
    end
    local height = #shown * CELL + max(#shown - 1, 0) * GAP
    row:SetSize(CELL, max(height, 1))
    for i, e in ipairs(shown) do
        Pin(e.frame, row, "TOP", row, "TOP", 0, -(i - 1) * (CELL + GAP), CELL, CELL)
        e.frame:SetAlpha(1)
        Paint(e)
    end
    laying = false
end

--------------------------------------------------------------------------------
--  Adoption
--------------------------------------------------------------------------------
local function Add(key, f, click, glyphFile, alert, visible)
    if not f then return end
    local e = { key = key, frame = f, click = click or f, glyphFile = glyphFile, alert = alert, visible = visible }
    entries[#entries + 1] = e
    Pin(f, row, "TOP", row, "TOP", 0, 0, CELL, CELL)
    Dress(e)
    f:HookScript("OnShow", LayoutRow)
    f:HookScript("OnHide", LayoutRow)
    return e
end

local function Tracking()
    local t = MinimapCluster and MinimapCluster.Tracking
    local b = t and t.Button
    if not b then return end
    Fade(t.Background)
    Fade(b:GetNormalTexture()); Fade(b:GetPushedTexture()); Fade(b:GetHighlightTexture())
    b:ClearAllPoints()
    b:SetAllPoints(t)
    Add("tracking", t, b, "search")
end

local function Calendar()
    local g = GameTimeFrame
    if not g then return end
    local function Art()
        Fade(g:GetNormalTexture()); Fade(g:GetPushedTexture()); Fade(g:GetHighlightTexture())
        if g.GetFontString and g:GetFontString() then g:GetFontString():SetAlpha(0) end
    end
    Art()
    if GameTimeFrame_SetDate then hooksecurefunc("GameTimeFrame_SetDate", Art) end
    FadeVertex(GameTimeCalendarInvitesTexture)
    FadeVertex(GameTimeCalendarInvitesGlow)
    FadeVertex(GameTimeCalendarEventAlarmTexture)
    local e = Add("calendar", g, g, "map_calendar", function()
        return GameTimeCalendarInvitesTexture and GameTimeCalendarInvitesTexture:IsShown()
    end)
    local inv = GameTimeCalendarInvitesTexture
    if e and inv then
        hooksecurefunc(inv, "Show", function() Paint(e) end)
        hooksecurefunc(inv, "Hide", function() Paint(e) end)
    end
end

local function Mail()
    local ind = MinimapCluster and MinimapCluster.IndicatorFrame
    local mf = ind and ind.MailFrame
    if not mf then return end
    Fade(mf.MailIcon)
    FadeVertex(mf.NewMailFlipbook); FadeVertex(mf.MailReminderFlipbook)
    Add("mail", mf, mf, "map_mail", function() return true end)
end

local function Orders()
    local ind = MinimapCluster and MinimapCluster.IndicatorFrame
    local cf = ind and ind.CraftingOrderFrame
    if not cf then return end
    Fade(MiniMapCraftingOrderIcon)
    for _, r in ipairs({ cf:GetRegions() }) do Fade(r) end
    Add("orders", cf, cf, "micro_professions", function() return true end)
end

local function Addons()
    local a = AddonCompartmentFrame
    if not a then return end
    Fade(a:GetNormalTexture()); Fade(a:GetPushedTexture()); Fade(a:GetHighlightTexture())
    if a.Text then a.Text:SetAlpha(0) end
    local e = Add("addons", a, a, "map_addons")
    if e and a.UpdateDisplay then hooksecurefunc(a, "UpdateDisplay", LayoutRow) end
end

-- Queue eye: Blizzard puts it at the round map's lower-left edge.
local function Eye()
    local q = QueueStatusButton
    if not q or type(q.UpdateDefaultAnchor) ~= "function" then return end
    local function Place()
        if q.IsInDefaultPosition and not q:IsInDefaultPosition() then return end
        if InCombatLockdown() and q:IsProtected() then return end
        q:ClearAllPoints()
        q:SetPoint("CENTER", ns.frame, "BOTTOMLEFT", 20, 24)
    end
    hooksecurefunc(q, "UpdateDefaultAnchor", Place)
    Place()
end

-- Expansion landing page: kept small in the map's top-left corner.
local function Landing()
    local b = ExpansionLandingPageMinimapButton
    if not b then return end
    b:SetScale(0.6)
    Pin(b, ns.map, "TOPLEFT", ns.map, "TOPLEFT", 2, -22)
end

function ns.AdoptButtons()
    row = CreateFrame("Frame", nil, ns.frame.overlay)
    -- Down the right edge, under the instance badge.
    row:SetPoint("TOPRIGHT", ns.frame, "TOPRIGHT", -4, -26)
    row:SetSize(CELL, 1)
    -- Blizzard's mail and order frames call :Layout() on their parent.
    row.Layout = LayoutRow
    Tracking()
    Calendar()
    Mail()
    Orders()
    Addons()
    Eye()
    Landing()
    if ns.AdoptFlyout then ns.AdoptFlyout() end
    -- Blizzard's instance banner is replaced by our badge.
    local diff = MinimapCluster and MinimapCluster.InstanceDifficulty
    if diff then diff:SetParent(ns.hidden) end
end

--- For our own row buttons (the flyout toggle): key, frame, glyph file,
--- alert() and visible() callbacks.
function ns.AddRowButton(key, f, glyphFile, alert, visible)
    local e = Add(key, f, f, glyphFile, alert, visible)
    LayoutRow()
    return e
end

function ns.LayoutButtons()
    LayoutRow()
end
