if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Panel.lua
--  Our panel, scrolling, size and visibility, and what's left of Blizzard's
--  tracker.
--
--  holder (the mover: a fixed box, width x max height; the panel hangs from
--  its top edge, so it grows downwards and never jumps about)
--    panel ─┬─ strip      quest count, XP ready, timers, collapse (ours)
--           └─ scroll     our scroll area (clips)
--                └─ content
--                     ├─ list     our quest list (List.lua)
--                     └─ sheet    below it, very tall, so Blizzard lays out
--                          │      every section it still owns
--                          └─ ObjectiveTrackerFrame (anchored with its Base
--                             SetPoint, never Edit Mode's)
--
--  Blizzard's tracker keeps running untouched; we only move and hide parts
--  of it (no calls into its code, no field writes):
--    * its "All Objectives" header and background are parked on a hidden
--      frame, and it sits up by its top padding so its first section
--      starts at the top of the sheet;
--    * its quest and campaign sections (ours now) are parked on a hidden
--      frame, and a post-hook on each section's SetPoint skips anything
--      anchored to a parked section, so what's left closes up;
--    * the rest (scenarios, world quests, bonus objectives, achievements,
--      recipes...) shows below our list, only when it has something.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T, U = EV.Theme, EV.UI
local floor, max, min = math.floor, math.max, math.min

local SHEET_H = 6000      -- tall enough for any tracker; nothing is ever cut
local POI_MARGIN = 20     -- quest icons hang left of Blizzard's tracker
local STRIP_H = 22
local GAP = 8             -- between our list and Blizzard's sections
local SCROLLBAR = 12

local holder, panel, strip, scroll, sheet, list
local hidden = CreateFrame("Frame", nil, UIParent)
hidden:Hide()
ns.hiddenParent = hidden

local function Tracker() return ObjectiveTrackerFrame end

-- Blizzard's sections that our list replaces.
local OURS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
local suppressed = {}
local function IsSuppressed(module) return suppressed[module] == true end
local function RefreshSuppressed()
    wipe(suppressed)
    for _, name in ipairs(OURS) do
        local m = _G[name]
        if m then suppressed[m] = true end
    end
end

--------------------------------------------------------------------------------
--  Sizes
--------------------------------------------------------------------------------
local function TrackerWidth() return M.db.width - POI_MARGIN - 8 - SCROLLBAR end

--- Resize Blizzard's sections to our width. Its 260 is hard-coded per
--- section; blocks anchor to their section's edges and wrap with it. Text
--- rewraps at Blizzard's next refresh (we never force one).
local function SizeModule(module, w)
    if not module or not module.SetWidth then return end
    module:SetWidth(w - (module.leftMargin or 0))
    local h = module.Header
    if h and h.SetWidth then
        h:SetWidth(w - (module.leftMargin or 0))
        if h.Text and h.Text.SetWidth then h.Text:SetWidth(max(60, w - 60)) end
    end
end

local function SizeTracker()
    local tracker = Tracker()
    if not tracker then return end
    local w = TrackerWidth()
    for _, module in ipairs(tracker.modules or {}) do SizeModule(module, w) end
end

--- Height of what Blizzard still shows, from its own module heights (no
--- screen geometry, so it's right even while scrolled or hidden).
local function BlizzardHeight()
    local tracker = Tracker()
    if not (tracker and M.db.blizzard) then return 0 end
    local h, n = 0, 0
    for _, module in ipairs(tracker.modules or {}) do
        if not IsSuppressed(module) then
            local c = module.GetContentsHeight and module:GetContentsHeight() or 0
            if type(c) == "number" and not ns.issecret(c) and c > 0 then
                h = h + c + (n > 0 and (tracker.moduleSpacing or 10) or 0)
                n = n + 1
            end
        end
    end
    return n > 0 and (h + 10) or 0
end
ns.BlizzardHeight = BlizzardHeight

local function ContentHeight()
    local listH = ns.ListHeight and ns.ListHeight() or 0
    local bh = BlizzardHeight()
    if bh > 0 then return max(listH, 1) + GAP + bh end
    return listH
end
ns.ContentHeight = ContentHeight

--------------------------------------------------------------------------------
--  Blizzard's remaining section headers, dressed like ours
--------------------------------------------------------------------------------
local dressed = setmetatable({}, { __mode = "k" })
local function DressHeader(h)
    if not (h and h.IsForbidden) or h:IsForbidden() then return end
    local d = dressed[h]
    if h.Background then h.Background:SetAlpha(0) end
    if not d then
        d = {}
        dressed[h] = d
        d.bar = T.Fill(h, "BACKGROUND", "surface1", 0.9, -8)
        d.bar:SetPoint("TOPLEFT", -4, 0)
        d.bar:SetPoint("BOTTOMRIGHT", 0, 2)
        d.line = T.Fill(h, "BORDER", "accent", 0.9)
        d.line:SetPoint("BOTTOMLEFT", d.bar, "BOTTOMLEFT")
        d.line:SetPoint("BOTTOMRIGHT", d.bar, "BOTTOMRIGHT")
        d.line:SetHeight(1)
        function d.Paint()
            d.bar:SetColorTexture(T.RGBA("surface1", 0.9))
            d.line:SetColorTexture(T.RGBA("accent", 0.9))
            if h.Text then h.Text:SetTextColor(T.RGBA("title")) end
        end
        T.Watch(d)
    end
    local text = h.Text
    if text and text.GetFont then
        local _, size = text:GetFont()
        if size and not ns.issecret(size) then text:SetFont(EV.Media:Fetch("font"), size, "") end
    end
    d.Paint()
end

local function DressAll()
    local tracker = Tracker()
    if not tracker then return end
    for _, module in ipairs(tracker.modules or {}) do
        if not IsSuppressed(module) then DressHeader(module.Header) end
    end
end

local FONT_OBJECTS = { "ObjectiveTrackerHeaderFont", "ObjectiveTrackerLineFont", "ObjectiveFont", "ObjectiveTitleFont" }
local function Fonts()
    local path = EV.Media:Fetch("font")
    for _, name in ipairs(FONT_OBJECTS) do
        local fo = _G[name]
        if fo and fo.GetFont then
            local _, size, flags = fo:GetFont()
            if size and size > 0 then fo:SetFont(path, size, flags or "") end
        end
    end
end

--------------------------------------------------------------------------------
--  The panel
--------------------------------------------------------------------------------
local function Build()
    holder = CreateFrame("Frame", "EvermoreUIObjectivesHolder", UIParent)
    holder:SetSize(M.db.width, M.db.height)
    holder:SetClampedToScreen(true)
    panel = CreateFrame("Frame", "EvermoreUIObjectives", holder)
    panel:SetFrameStrata("LOW")
    panel:SetPoint("TOPLEFT", holder, "TOPLEFT")
    panel:SetSize(M.db.width, M.db.height)
    panel.bg = T.Fill(panel, "BACKGROUND", "surface0", M.db.bgAlpha)
    panel.bg:SetAllPoints()
    T.TokenBorder(panel, "border")
    function panel:Paint()
        self.bg:SetColorTexture(T.RGBA("surface0", M.db.bgAlpha))
        T.SetBorderToken(self, "border")
        for _, e in ipairs(self.evBorder and self.evBorder.edges or {}) do e:SetShown(M.db.border) end
    end
    T.Watch(panel)

    strip = CreateFrame("Frame", nil, panel)
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(STRIP_H)
    strip.left = U.Label(strip, "", "textMuted", "small")
    strip.left:SetPoint("TOPLEFT", 8, -5)
    strip.right = U.Label(strip, "", "success", "small")
    strip.right:SetPoint("TOPRIGHT", -28, -5)
    strip.timers = {}
    local collapse = U.IconButton(strip, { size = 18, style = "ghost", tooltip = L["Collapse"] })
    collapse:SetPoint("TOPRIGHT", -3, -2)
    local chev = T.Chevron(collapse, 4, 1)
    chev:SetPoint("CENTER")
    collapse.chev = chev
    collapse:SetScript("OnClick", function()
        M.db.collapsed = not M.db.collapsed
        ns.Layout()
    end)
    strip.collapse = collapse

    scroll = U.Scroll(panel, { step = 48, reserve = true })
    scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -1, 4)

    list = ns.CreateList(scroll.content)
    list:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 2, 0)

    sheet = CreateFrame("Frame", nil, scroll.content)
    sheet:SetPoint("TOPLEFT", list, "BOTTOMLEFT", POI_MARGIN, -GAP)
    sheet:SetWidth(TrackerWidth())
    sheet:SetHeight(SHEET_H)

    ns.holder, ns.panel, ns.strip, ns.scroll, ns.sheet = holder, panel, strip, scroll, sheet

    EV.Movers:Register(holder, "OBJ_tracker", L["Objective Tracker"], { "TOPRIGHT", "TOPRIGHT", -40, -260 }, {
        group = L["Objectives"], page = "objectives",
        getSize = function() return M.db.width, M.db.height end,
        -- Edit mode's corner grip and its W/H boxes. Height is the maximum:
        -- the box you see in edit mode is the most the panel will use, and
        -- with "shrink to fit" on the panel itself is often shorter.
        setSize = function(w, h)
            local lim = ns.LIMITS
            if w then M.db.width = min(lim.wMax, max(lim.wMin, floor(w + 0.5))) end
            if h then M.db.height = min(lim.hMax, max(lim.hMin, floor(h + 0.5))) end
            ns.Safe("size", function() SizeTracker(); sheet:SetWidth(TrackerWidth()) end)
            ns.RefreshList(true)
        end,
    })
end

--------------------------------------------------------------------------------
--  Taking the tracker
--------------------------------------------------------------------------------
local function Genesis()
    if M.db.genesis then return end
    local tracker = Tracker()
    M.db.genesis = true
    if not tracker then return end
    local cx, cy = tracker:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local w = tracker:GetWidth()
    if cx and ux and not ns.issecret(cx) and w and w > 0 then
        M.db.width = max(260, floor(w + POI_MARGIN + 8 + 0.5))
        local k = tracker:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local top = tracker:GetTop()
        -- Keep its top edge where it was; our panel hangs down from there.
        if top and not ns.issecret(top) then
            local py = top * k - M.db.height / 2 - uy
            EV.DB:GetCore().movers.OBJ_tracker = { "CENTER", "CENTER", cx * k - ux, py }
        end
    end
end

--- Park the sections our list replaces (Blizzard re-parents a section each
--- time it's added to the tracker, so this runs again then).
local function ParkOurs()
    RefreshSuppressed()
    for m in pairs(suppressed) do
        if m:GetParent() ~= hidden then m:SetParent(hidden) end
    end
end

local anchoredPad
local function AnchorTracker(tracker)
    -- Sit up by Blizzard's top padding (the room its header used), so its
    -- first section starts at the top of the sheet.
    local pad = tonumber(tracker.topModulePadding) or 0
    if ns.issecret(pad) then pad = 0 end
    local clear = tracker.ClearAllPointsBase or tracker.ClearAllPoints
    local set = tracker.SetPointBase or tracker.SetPoint
    clear(tracker)
    set(tracker, "TOPLEFT", sheet, "TOPLEFT", 0, pad)
    set(tracker, "BOTTOMRIGHT", sheet, "BOTTOMRIGHT", 0, 0)
    anchoredPad = pad
end

local taking = false
function ns.Take()
    local tracker = Tracker()
    if not (tracker and panel) or taking then return end
    ns.Safe("take", function()
        taking = true
        -- Out of Blizzard's right-hand column, the way Edit Mode does it.
        if tracker.BreakFromFrameManager and not tracker.ignoreFramePositionManager then
            pcall(tracker.BreakFromFrameManager, tracker)
        end
        tracker:SetParent(sheet)
        -- Edit Mode's system template clamps the tracker to the screen. In
        -- our scroll area it's far taller than the screen, so the clamp pins
        -- it in place and scrolling can't move it. Our holder is clamped
        -- instead.
        if tracker.SetClampedToScreen then tracker:SetClampedToScreen(false) end
        AnchorTracker(tracker)
        -- Blizzard's own background and "All Objectives" bar go; ours is
        -- the panel and strip.
        if tracker.NineSlice and tracker.NineSlice:GetParent() ~= hidden then tracker.NineSlice:SetParent(hidden) end
        if tracker.Header and tracker.Header:GetParent() ~= hidden then tracker.Header:SetParent(hidden) end
        -- Out of Edit Mode's reach: its highlight box can't be seen or grabbed.
        if tracker.Selection then
            tracker.Selection:SetAlpha(0)
            if tracker.Selection.EnableMouse then tracker.Selection:EnableMouse(false) end
        end
        ParkOurs()
        SizeTracker()
        Fonts()
        DressAll()
        taking = false
        ns.Layout()
    end)
end

--------------------------------------------------------------------------------
--  Layout: panel height, strip, scroll range
--------------------------------------------------------------------------------
function ns.Layout()
    if not panel then return end
    -- A quest row with an item button makes the panel a protected frame: it
    -- can't be resized in combat. Keep the strip's text current and lay out
    -- when combat ends.
    if InCombatLockdown() and panel:IsProtected() then
        if ns.UpdateStrip then ns.UpdateStrip() end
        ns.Safe("layout", ns.Layout)
        return
    end
    -- The strip always shows: it carries the collapse button. The info
    -- text on it is the optional part.
    local stripH = STRIP_H + ((ns.TimerCount and ns.TimerCount()) or 0) * 16
    if ns.UpdateStrip then ns.UpdateStrip() end
    strip:SetHeight(stripH)
    strip.collapse.chev:Flip(not M.db.collapsed)

    -- Blizzard's padding can change (timer windows add to it); follow it.
    local tracker = Tracker()
    if tracker and tracker:GetParent() == sheet and tonumber(tracker.topModulePadding) ~= anchoredPad then
        ns.Safe("anchor", function() AnchorTracker(tracker) end)
    end
    local bh = BlizzardHeight()
    sheet:SetShown(M.db.blizzard and true or false)
    sheet:SetAlpha(bh > 0 and 1 or 0)

    local content = ContentHeight()
    scroll:SetContentHeight(max(content, 1))
    local maxView = max(40, M.db.height - stripH - 8)
    local view = M.db.fitContent and min(maxView, content) or maxView
    if M.db.collapsed then view = 0 end
    scroll:SetShown(view > 0)
    local h = stripH + (view > 0 and (view + 8) or 2)
    panel:SetSize(M.db.width, max(h, 4))
    if holder:GetWidth() ~= M.db.width or holder:GetHeight() ~= M.db.height then
        holder:SetSize(M.db.width, M.db.height)
    end
    -- Nothing to show at all: no quests, no timers, not collapsed.
    ns.empty = content <= 0 and not M.db.collapsed and not ((ns.TimerCount and ns.TimerCount() or 0) > 0)
    panel:Paint()
    EV.Movers:Apply("OBJ_tracker")
end

--- After each of Blizzard's refreshes: dress new headers, re-measure.
local pending = false
local function AfterUpdate()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        DressAll()
        ns.Layout()
    end)
end
ns.AfterUpdate = AfterUpdate

--------------------------------------------------------------------------------
--  Visibility: combat, instances, mouse
--------------------------------------------------------------------------------
local current = 1
local fader = CreateFrame("Frame")
fader:Hide()   -- shown by OnEnable, so a switched-off module costs nothing
local acc = 0
fader:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.05 or not panel then return end
    local step = acc
    acc = 0
    local combat = InCombatLockdown() or UnitAffectingCombat("player")
    local inInstance, kind = IsInInstance()
    inInstance = inInstance and kind ~= "none"
    local hideIt = ns.empty or (combat and M.db.combat == "hide") or (inInstance and M.db.instances == "hide")
    local fade = (combat and M.db.combat == "fade") or (inInstance and M.db.instances == "fade") or M.db.mouseFade
    local target = 1
    if hideIt then
        target = 0
    elseif fade and not panel:IsMouseOver(4, -4, -4, 4) then
        target = M.db.fadeAlpha
    end
    if current ~= target then
        local speed = step * 5
        if current < target then current = min(target, current + speed) else current = max(target, current - speed) end
        panel:SetAlpha(current)
    end
end)

--------------------------------------------------------------------------------
--  Hooks on Blizzard's tracker (post-hooks only)
--------------------------------------------------------------------------------
-- Closing the gaps our parked sections leave. Blizzard anchors each
-- section's TOP to the one before it (or to the tracker for the first).
-- After it does, if that's a parked section, we take the parked section's
-- own TOP anchor instead; parked sections anchored "to their parent" (the
-- hidden frame now) are pointed at the tracker. Chains of parked sections
-- resolve because Blizzard anchors them in order.
local fixing = false
local function OnModuleSetPoint(self, point, rel, relPoint, x, y)
    if fixing or point ~= "TOP" then return end
    local tracker = Tracker()
    local target, tp, tx, ty
    if type(rel) ~= "table" then
        -- SetPoint("TOP", x, y): relative to the parent.
        if self:GetParent() == tracker then return end
        target, tp, tx, ty = tracker, "TOP", tonumber(rel) or 0, tonumber(relPoint) or 0
    elseif IsSuppressed(rel) then
        for i = 1, rel:GetNumPoints() do
            local p, r, rp, rx, ry = rel:GetPoint(i)
            if p == "TOP" then target, tp, tx, ty = r, rp, rx, ry break end
        end
        if not target then return end
    else
        return
    end
    fixing = true
    self:SetPoint("TOP", target, tp, tx, ty)
    fixing = false
end

-- Blizzard's container refreshes through a closure it captured at load
-- (SetDirtyMethod(GenerateClosure(self.Update, ...))), so a hook on the
-- tracker's Update field misses every normal update. Each section is still
-- called as module:Update(...), and its height is set as it lays out, so we
-- watch the sections: their Update, their size and show/hide.
local moduleHooked = setmetatable({}, { __mode = "k" })
local function HookModule(module)
    if not module or moduleHooked[module] or not module.HookScript then return end
    moduleHooked[module] = true
    if type(module.Update) == "function" then hooksecurefunc(module, "Update", AfterUpdate) end
    hooksecurefunc(module, "SetPoint", OnModuleSetPoint)
    module:HookScript("OnSizeChanged", AfterUpdate)
    module:HookScript("OnShow", AfterUpdate)
    module:HookScript("OnHide", AfterUpdate)
end

local hooked = false
local function Hook()
    local tracker = Tracker()
    if hooked or not tracker then return end
    hooked = true
    for _, module in ipairs(tracker.modules or {}) do HookModule(module) end
    -- Direct calls (not the dirty path) still come through here.
    if type(tracker.Update) == "function" then hooksecurefunc(tracker, "Update", AfterUpdate) end
    if type(tracker.AddModule) == "function" then
        hooksecurefunc(tracker, "AddModule", function(_, module)
            HookModule(module)
            ns.Safe("sizeModule", function()
                ParkOurs() -- Blizzard just re-parented it to the tracker
                SizeModule(module, TrackerWidth())
            end)
            AfterUpdate()
        end)
    end
    -- Edit Mode re-anchors its systems when a layout applies. Take the
    -- ANCHOR back, and nothing else.
    --
    -- This used to call the whole of ns.Take() from here, and that is what
    -- broke the aura systems on 21 Sep. The chain, from Blizzard's source:
    --
    --   PLAYER_SPECIALIZATION_CHANGED (dinging 20 fires it)
    --     EditModeManager.lua:210  UpdateLayoutInfo
    --       :1465  secureexecuterange(registeredSystemFrames, initSystemAnchor)
    --                -> ApplySystemAnchor -> THIS HOOK -> all of ns.Take():
    --                   SetParent, SetClampedToScreen, reparenting NineSlice
    --                   and Header, SizeTracker, Fonts, DressAll, Layout
    --       :1021  InvokeOnAnyEditModeSystemAnchorChanged
    --       :1039    secureexecuterange(registeredSystemFrames, ...)
    --                -> every system's OnAnyEditModeSystemAnchorChanged, now
    --                   carrying our taint -> GetAuraDataByIndex refused.
    --
    -- Re-anchoring is all this hook was ever for, and AnchorTracker uses
    -- SetPointBase: the original Blizzard keeps unhooked precisely so it does
    -- not ping the manager. If Edit Mode has taken the frame away from us
    -- entirely, a full re-adoption is far too heavy to run inside its own
    -- pass, so that goes to the next frame instead.
    if type(tracker.ApplySystemAnchor) == "function" then
        hooksecurefunc(tracker, "ApplySystemAnchor", function()
            if tracker:GetParent() == sheet then
                AnchorTracker(tracker)
            elseif not taking then
                C_Timer.After(0, function() ns.Safe("retake", ns.Take) end)
            end
        end)
    end
    tracker:HookScript("OnShow", AfterUpdate)
    tracker:HookScript("OnHide", AfterUpdate)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", function()
            if ns.noted then return end
            ns.noted = true
            EV:Print(L["The objective tracker is handled by EvermoreUI: move it with /evui edit."])
        end)
    end
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function M:Refresh()
    if not panel then return end
    ns.Safe("refresh", function()
        SizeTracker()
        sheet:SetWidth(TrackerWidth())
        Fonts()
        DressAll()
    end)
    if ns.ApplyQuestSettings then ns.ApplyQuestSettings() end
    if ns.ApplyListSettings then ns.ApplyListSettings() end
    if ns.RefreshItems then ns.RefreshItems(true) end
    ns.RefreshList(true)
end

function M:OnEnable()
    fader:Show()
    Build()
    Genesis()
    Hook()
    ns.Take()
    if ns.EnableQuests then ns.EnableQuests() end
    if ns.EnableItems then ns.EnableItems() end
    if ns.DiagHook then ns.DiagHook() end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        ns.Take()
        AfterUpdate()
    end)
    pcall(self.RegisterEvent, self, "EDIT_MODE_LAYOUTS_UPDATED", function() ns.Take() end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
    self:RegisterMessage("EV_THEME_CHANGED", function() ns.RefreshList(); AfterUpdate() end)
    ns.RefreshList(true)
    AfterUpdate()
end

function M:OnProfileChanged() self:Refresh() end
