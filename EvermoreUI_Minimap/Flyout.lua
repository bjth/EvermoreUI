if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Flyout.lua
--  Other addons' minimap buttons (LibDBIcon and the rest), gathered off the
--  map into one pop-out grid behind a single button in the map's column.
--
--  A button qualifies when it's a named child of the Minimap (or its
--  backdrop), wide enough to be a button, and not a map pin (HandyNotes,
--  TomTom, Questie and friends) or one of Blizzard's own. Each is moved
--  into the grid and dressed like our other buttons: its round border and
--  background art hidden, its icon cropped square on a sunk well. It keeps
--  its own click, tooltip and menu. Dragging is switched off (LibDBIcon
--  would drag it round the map) and it's pinned, so an addon re-placing its
--  button can't pull it back out.
--
--  Scans happen at login, a couple of times after (addons make buttons
--  late), when LibDBIcon reports a new icon, and whenever the grid opens.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local CELL, GAP, PAD = 26, 4, 6

local grouped = {}                                   -- in the order found
local isGrouped = setmetatable({}, { __mode = "k" })
local panel, toggle, entry

-- Blizzard's own children of the map, and ours.
local SKIP = {
    MinimapBackdrop = true, ExpansionLandingPageMinimapButton = true, HybridMinimap = true,
    MinimapZoomIn = true, MinimapZoomOut = true, GameTimeFrame = true, AddonCompartmentFrame = true,
    QueueStatusButton = true, TimeManagerClockButton = true,
}
-- Map pins and trackers: they belong on the map.
local PINS = { "^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate", "^Pin", "^pin", "^RareScanner" }

-- Round-button decoration (border ring, background disc, highlight).
local JUNK_ID = { [136467] = true, [136430] = true, [136477] = true }
local JUNK_PATH = { "minimap%-trackingborder", "ui%-minimap%-background", "zoombutton%-highlight" }

local function IsJunk(r)
    if not (r and r.IsObjectType and r:IsObjectType("Texture")) then return false end
    local id = r.GetTextureFileID and r:GetTextureFileID()
    if id and JUNK_ID[id] then return true end
    local path = (r.GetTextureFilePath and r:GetTextureFilePath()) or r:GetTexture()
    if type(path) == "string" then
        path = path:lower()
        for _, pat in ipairs(JUNK_PATH) do if path:find(pat) then return true end end
    end
    return false
end

local function Qualifies(f)
    if isGrouped[f] then return true end
    local name = f.GetName and f:GetName()
    if not name or SKIP[name] then return false end
    for _, pat in ipairs(PINS) do if name:find(pat) then return false end end
    local isButton = f:IsObjectType("Button")
    if not (isButton or name:find("^LibDBIcon10_")) then return false end
    if name:find("%d+$") and not name:find("^LibDBIcon10_") then return false end   -- numbered pins
    local w = f:GetWidth() or 0
    return w >= 16 and w <= 64
end

--------------------------------------------------------------------------------
--  Dressing
--------------------------------------------------------------------------------
local function IconOf(b)
    local icon = rawget(b, "icon") or rawget(b, "Icon")
    if type(icon) == "table" and icon.SetTexCoord then return icon end
    -- Otherwise the biggest texture that isn't decoration.
    local best, area = nil, 0
    for _, r in ipairs({ b:GetRegions() }) do
        if r:IsObjectType("Texture") and not IsJunk(r) and r ~= b:GetHighlightTexture() then
            local a = (r:GetWidth() or 0) * (r:GetHeight() or 0)
            if a > area then best, area = r, a end
        end
    end
    return best
end

local function Dress(b)
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    for _, r in ipairs({ b:GetRegions() }) do
        if r ~= hl and IsJunk(r) then r:SetAlpha(0); r:Hide() end
    end
    local icon = IconOf(b)
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    if hl then
        hl:SetColorTexture(T.RGBA("text", 0.15))
        hl:SetBlendMode("BLEND")
        hl:ClearAllPoints()
        hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end
    if not b.evWell then
        b.evWell = T.Fill(b, "BACKGROUND", "surfaceSunk", 0.9, -8)
        b.evWell:SetAllPoints()
        local edge = CreateFrame("Frame", nil, b)
        edge:SetAllPoints()
        edge:SetFrameLevel(b:GetFrameLevel() + 3)
        edge:EnableMouse(false)
        T.TokenBorder(edge, "border")
        b.evEdge = edge
    end
end

--------------------------------------------------------------------------------
--  The grid
--------------------------------------------------------------------------------
local function Shown()
    local list = {}
    for _, b in ipairs(grouped) do
        if b:IsShown() then list[#list + 1] = b end
    end
    return list
end
ns.FlyoutCount = function() return #Shown() end

-- Beside the map, on whichever side of the screen has room.
local function Anchor()
    local f = ns.frame
    panel:ClearAllPoints()
    local cx = f:GetCenter()
    local ux = UIParent:GetCenter()
    if not (cx and ux) or cx >= ux then
        panel:SetPoint("TOPRIGHT", f, "TOPLEFT", -6, 0)
    else
        panel:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, 0)
    end
end

local function LayoutPanel()
    if not panel then return end
    local list = Shown()
    local cols = max(1, min(M.db.groupColumns or 5, #list))
    local rows = max(1, ceil(#list / cols))
    panel:SetSize(PAD * 2 + cols * CELL + (cols - 1) * GAP, PAD * 2 + rows * CELL + (rows - 1) * GAP)
    for i, b in ipairs(list) do
        local r, c = floor((i - 1) / cols), (i - 1) % cols
        ns.Pin(b, panel, "TOPLEFT", panel, "TOPLEFT", PAD + c * (CELL + GAP), -(PAD + r * (CELL + GAP)), CELL, CELL)
        b:SetFrameLevel(panel:GetFrameLevel() + 2)
    end
    Anchor()
end

--------------------------------------------------------------------------------
--  Gathering
--------------------------------------------------------------------------------
local refresh                         -- set below

local function Group(b)
    if isGrouped[b] then return end
    if InCombatLockdown() and b:IsProtected() then return end
    isGrouped[b] = true
    grouped[#grouped + 1] = b
    if b.RegisterForDrag then b:RegisterForDrag() end     -- no dragging round the map
    b:SetScale(1)
    ns.Pin(b, panel, "TOPLEFT", panel, "TOPLEFT", PAD, -PAD, CELL, CELL)
    Dress(b)
    -- The addon showing or hiding its button (LibDBIcon's "hide" option).
    hooksecurefunc(b, "Show", refresh)
    hooksecurefunc(b, "Hide", refresh)
end

local function Scan()
    if not (ns.map and panel and M.db.group) then return end
    for _, parent in ipairs({ ns.map, MinimapBackdrop }) do
        if parent then
            for _, c in ipairs({ parent:GetChildren() }) do
                if Qualifies(c) then Group(c) end
            end
        end
    end
    refresh()
end
ns.ScanFlyout = Scan

local pending = false
function refresh()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if panel:IsShown() then LayoutPanel() end
        if entry and ns.LayoutButtons then ns.LayoutButtons() end
        if entry then entry.Paint() end
    end)
end

--------------------------------------------------------------------------------
--  Open / close. Closes itself a moment after the mouse leaves.
--------------------------------------------------------------------------------
local away = 0
local function Watch(self, dt)
    if self:IsMouseOver(4, -4, -4, 4) or (toggle and toggle:IsMouseOver()) then
        away = 0
        return
    end
    away = away + dt
    if away > 1.2 then self:Hide() end
end

local function Open()
    Scan()
    LayoutPanel()
    away = 0
    panel:Show()
end

function ns.AdoptFlyout()
    panel = CreateFrame("Frame", "EvermoreUIMinimapButtons", UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(20)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    panel:Hide()
    panel.bg = T.Fill(panel, "BACKGROUND", "surface1", 0.97, -8)
    panel.bg:SetAllPoints()
    panel.edge = CreateFrame("Frame", nil, panel)
    panel.edge:SetAllPoints()
    panel.edge:EnableMouse(false)
    T.TokenBorder(panel.edge, "border")
    panel.Paint = function()
        panel.bg:SetColorTexture(T.RGBA("surface1", 0.97))
        T.SetBorderToken(panel.edge, "border")
    end
    T.Watch(panel)
    panel:SetScript("OnUpdate", Watch)
    panel:SetScript("OnShow", function() if entry then entry.Paint() end end)
    panel:SetScript("OnHide", function() if entry then entry.Paint() end end)
    tinsert(UISpecialFrames, "EvermoreUIMinimapButtons")          -- Escape closes it

    toggle = CreateFrame("Button", "EvermoreUIMinimapButtonsToggle", ns.frame.overlay)
    toggle:RegisterForClicks("LeftButtonUp")
    toggle:SetScript("OnClick", function() if panel:IsShown() then panel:Hide() else Open() end end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Addon buttons"], T.RGBA("text"))
        GameTooltip:AddLine(L["Other addons' minimap buttons, gathered in one place."], T.RGBA("textMuted"))
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    entry = ns.AddRowButton("flyout", toggle, "map_buttons",
        function() return panel:IsShown() end,
        function() return M.db.group and ns.FlyoutCount() > 0 end)

    -- Addons make their buttons at all sorts of times.
    Scan()
    for _, t in ipairs({ 2, 8 }) do C_Timer.After(t, Scan) end
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and lib.RegisterCallback then
        lib.RegisterCallback(ns, "LibDBIcon_IconCreated", function() C_Timer.After(0, Scan) end)
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("ADDON_LOADED")
    local later = false
    ev:SetScript("OnEvent", function()
        if later then return end
        later = true
        C_Timer.After(0.5, function() later = false; Scan() end)
    end)
end
