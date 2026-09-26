if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  EvermoreUI Minimap
--
--  Blizzard's Minimap (the one frame that can draw the map) is moved into an
--  EvermoreUI frame and made square, with a 1px border and everything else
--  laid over the map itself:
--
--    ┌──────────────────────┐
--    │45, 62   12:34    10H │  coordinates, clock, instance badge
--    │                    ▢ │
--    │                    ▢ │  Blizzard's buttons down the right edge
--    │        (map)       ▢ │
--    │                      │
--    └───[☾ The Crossroads]─┘  zone plate straddling the bottom edge
--
--  MinimapCluster (Blizzard's round frame, zone plate, clock and buttons) is
--  parked under a hidden frame once the pieces we keep are taken out of it.
--  Blizzard still owns every behaviour: pings, tracking, mail, calendar,
--  blips, the hybrid map in instances. We only move and dress.
--
--  Blizzard reparents the Minimap during some transitions (housing) and
--  re-sets its round mask when the rotate option changes; both are
--  post-hooked and put back.
--
--  Files: Core (frame, square map, zoom), Info (zone, clock, coordinates,
--  difficulty, day / night), Buttons (Blizzard's buttons, queue eye,
--  landing page), Flyout (other addons' buttons).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L
local T = EV.Theme
local floor, max, min = math.floor, math.max, math.min

local M = EV:NewModule("Minimap", {
    size       = 200,     -- map width and height
    zone       = true,    -- zone plate on the bottom edge
    zoneColour = true,    -- colour the zone by PvP status
    clock      = true,
    coords     = true,
    buttons    = true,
    difficulty = true,    -- instance size / difficulty badge on the map
    diel       = true,    -- sun / moon on the zone plate for Forever's day and night
    group      = true,    -- gather other addons' minimap buttons into one pop-out
    groupColumns = 5,
    fontSize   = 12,
    wheelZoom  = true,
    autoZoom   = 0,       -- seconds before zooming back out (0: never)
})
ns.module = M
M.title = "Minimap"
M.description = "A square minimap in the EvermoreUI style, with the zone, clock, coordinates and buttons around it."

ns.GLYPH = T.MEDIA

-- Solid white square (WHITE8X8, by file ID as Blizzard's own code passes
-- masks). The map only draws where the mask is opaque.
local SQUARE_MASK = 130937
ns.SQUARE_MASK = SQUARE_MASK

local hidden = CreateFrame("Frame", "EvermoreUIMinimapHidden", UIParent)
hidden:Hide()
ns.hidden = hidden

--------------------------------------------------------------------------------
--  Combat queue (the Minimap isn't protected on Forever today, but if it
--  ever is, moving it waits rather than failing).
--------------------------------------------------------------------------------
local queue = {}
local qf = CreateFrame("Frame")
qf:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local list = queue
    queue = {}
    for _, fn in pairs(list) do xpcall(fn, geterrorhandler()) end
end)
function ns.Safe(key, fn, frame)
    if not (InCombatLockdown() and frame and frame.IsProtected and frame:IsProtected()) then return fn() end
    queue[key] = fn
    qf:RegisterEvent("PLAYER_REGEN_ENABLED")
end

--------------------------------------------------------------------------------
--  Our frame
--------------------------------------------------------------------------------
local frame, map                     -- holder, and Blizzard's Minimap inside it
ns.frame = nil

local function Build()
    local f = CreateFrame("Frame", "EvermoreUIMinimap", UIParent)
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(2)
    f:SetSize(200, 200)
    f:EnableMouse(false)
    f.bg = T.Fill(f, "BACKGROUND", "surfaceSunk", 1, -8)
    f.bg:SetAllPoints()

    -- The Minimap sits in the well; the overlay (text, badges, buttons)
    -- sits above both the map and the wheel layer.
    f.well = CreateFrame("Frame", nil, f)
    f.well:SetAllPoints()
    f.overlay = CreateFrame("Frame", nil, f)
    f.overlay:SetAllPoints()
    f.overlay:EnableMouse(false)

    -- Border over the map.
    f.edge = CreateFrame("Frame", nil, f)
    f.edge:SetAllPoints()
    f.edge:EnableMouse(false)
    T.TokenBorder(f.edge, "border")

    f.Paint = function()
        f.bg:SetColorTexture(T.RGBA("surfaceSunk"))
        T.SetBorderToken(f.edge, "border")
    end
    T.Watch(f)
    frame = f
    ns.frame = f
    return f
end

--- A small plate for text or a button laid over the map: surface1 with a
--- 1px border, readable on any terrain.
function ns.Plate(parent, alpha)
    local p = CreateFrame("Frame", nil, parent)
    p.bg = T.Fill(p, "BACKGROUND", "surface1", alpha or 0.9)
    p.bg:SetAllPoints()
    p.edge = CreateFrame("Frame", nil, p)
    p.edge:SetAllPoints()
    p.edge:EnableMouse(false)
    T.TokenBorder(p.edge, "border")
    p.Paint = function()
        p.bg:SetColorTexture(T.RGBA("surface1", alpha or 0.9))
        T.SetBorderToken(p.edge, "border")
    end
    T.Watch(p)
    return p
end

--------------------------------------------------------------------------------
--  The square map
--------------------------------------------------------------------------------
local placing = false

local function Square()
    if not map then return end
    placing = true
    map:SetMaskTexture(SQUARE_MASK)
    -- The rings round quest and dig areas are drawn for a round map.
    for _, fn in ipairs({ "SetArchBlobRingScalar", "SetQuestBlobRingScalar", "SetTaskBlobRingScalar" }) do
        if map[fn] then pcall(map[fn], map, 0) end
    end
    placing = false
end

local function Place()
    if not (map and frame) then return end
    if InCombatLockdown() and map:IsProtected() then
        ns.Safe("place", Place, map)
        return
    end
    placing = true
    if map:GetParent() ~= frame.well then map:SetParent(frame.well) end
    map:ClearAllPoints()
    -- The Minimap draws at its own set size, not the size its anchors give
    -- it, so it gets an explicit size (whole pixels) and a centre anchor.
    local w = frame:GetWidth()
    map:SetPoint("CENTER", frame.well, "CENTER")
    map:SetSize(w, w)
    map:SetScale(1)
    map:SetFrameLevel(frame.well:GetFrameLevel() + 1)
    placing = false
    Square()
    -- The backdrop carries the compass art and the housing overlay; make it
    -- the map's size so nothing hangs off the square.
    local bd = MinimapBackdrop
    if bd then
        bd:ClearAllPoints()
        bd:SetAllPoints(map)
    end
    for _, name in ipairs({ "MinimapCompassTexture", "MinimapCompassTextureUnderlay" }) do
        local t = _G[name]
        -- Alpha, not Hide: encounter tools read the player's facing from the
        -- compass's rotation, which stops updating if it's hidden.
        if t then t:SetAlpha(0) end
    end
end
ns.Place = Place

-- Blizzard's round-map art hides in the zoom buttons too; ours is the wheel.
local function ParkZoom()
    for _, k in ipairs({ "ZoomIn", "ZoomOut", "ZoomHitArea" }) do
        local b = map and rawget(map, k)
        if type(b) == "table" and b.SetParent then b:SetParent(hidden) end
    end
end

--------------------------------------------------------------------------------
--  Mouse: wheel zoom anywhere on the square (the Minimap's own hit area is
--  round), auto zoom-out, and hover passing straight through to Blizzard.
--------------------------------------------------------------------------------
local zoomTimer
local function AutoZoom()
    if zoomTimer then zoomTimer:Cancel(); zoomTimer = nil end
    local secs = M.db.autoZoom or 0
    if secs <= 0 or not C_Timer.NewTimer then return end
    zoomTimer = C_Timer.NewTimer(secs, function()
        zoomTimer = nil
        if map and map:GetZoom() > 0 then map:SetZoom(0) end
    end)
end

local function Zoom(delta)
    if not map then return end
    local z = map:GetZoom()
    local top = (map.GetZoomLevels and map:GetZoomLevels() or 6) - 1
    z = delta > 0 and min(z + 1, top) or max(z - 1, 0)
    map:SetZoom(z)
    AutoZoom()
end

local function WheelLayer()
    local w = CreateFrame("Frame", nil, frame.well)
    w:SetAllPoints(frame.well)
    w:SetFrameLevel(map:GetFrameLevel() + 10)
    -- Clicks and hover go through to the map (pings, blip tooltips).
    if w.SetPassThroughButtons then w:SetPassThroughButtons("LeftButton", "RightButton", "MiddleButton") end
    if w.SetPropagateMouseMotion then w:SetPropagateMouseMotion(true) end
    if not (w.SetPassThroughButtons and w.SetPropagateMouseMotion) then
        -- Older client: let the map have the mouse and hook its wheel instead.
        w:Hide()
        map:EnableMouseWheel(true)
        map:HookScript("OnMouseWheel", function() AutoZoom() end)
        return w
    end
    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(_, delta)
        if M.db.wheelZoom then Zoom(delta) end
    end)
    return w
end

--------------------------------------------------------------------------------
--  Layout
--------------------------------------------------------------------------------
function ns.Layout()
    if not frame then return end
    -- Whole physical pixels, so the border lands on real pixels on every side.
    local size = EV.Pixel:Snap(frame, M.db.size)
    local was = frame:GetWidth()
    frame:SetSize(size, size)
    Place()
    -- The map only redraws its terrain for a new size on a zoom change.
    if map and was and math.abs(was - size) > 0.01 and map.GetZoom then
        local z = map:GetZoom()
        local top = (map.GetZoomLevels and map:GetZoomLevels() or 6) - 1
        map:SetZoom(z < top and z + 1 or z - 1)
        map:SetZoom(z)
    end
    -- Levels: map, wheel layer (+10), overlay (+20), border on top.
    local base = map:GetFrameLevel()
    if ns.wheel then ns.wheel:SetFrameLevel(base + 10) end
    frame.overlay:SetFrameLevel(base + 20)
    frame.edge:SetFrameLevel(base + 19)
    if frame.edge:GetParent() ~= map then
        -- On the map itself, so the terrain can't cover it.
        frame.edge:SetParent(map)
        frame.edge:ClearAllPoints()
        frame.edge:SetAllPoints(frame)
        frame.edge:SetFrameLevel(base + 19)
    end
    EV.Pixel:ResnapBorders()
    if ns.LayoutInfo then ns.LayoutInfo() end
    if ns.LayoutButtons then ns.LayoutButtons() end
    EV.Movers:Apply("Minimap")
end

--------------------------------------------------------------------------------
--  Adoption
--------------------------------------------------------------------------------
local adopted = false
local function Adopt()
    if adopted or not Minimap then return end
    adopted = true
    map = Minimap
    ns.map = map
    Build()
    EV.Movers:Register(frame, "Minimap", L["Minimap"], { "TOPRIGHT", "TOPRIGHT", -12, -12 }, {
        group = L["Minimap"], page = "minimap",
    })

    Place()
    ParkZoom()
    if map.SetFixedFrameStrata then
        map:SetFrameStrata("LOW")
        map:SetFixedFrameStrata(true)
    end
    -- Blizzard moves the map during some transitions; put it back.
    hooksecurefunc(map, "SetParent", function()
        if placing or map:GetParent() == frame.well then return end
        ns.Safe("place", Place, map)
    end)
    -- The rotate option re-sets the round mask.
    hooksecurefunc(map, "SetMaskTexture", function()
        if not placing then Square() end
    end)
    ns.wheel = WheelLayer()

    -- Blizzard's cluster goes once everything we keep is out of it.
    -- Each part on its own: one failing mustn't leave Blizzard's cluster up.
    if ns.AdoptInfo then xpcall(ns.AdoptInfo, geterrorhandler()) end
    if ns.AdoptButtons then xpcall(ns.AdoptButtons, geterrorhandler()) end
    -- Blizzard's cluster stays parented and shown, but invisible and
    -- click-through: hiding it would leave its children without a screen
    -- rect, and Blizzard's Edit Mode measures them.
    if MinimapCluster then
        MinimapCluster:SetAlpha(0)
        MinimapCluster:EnableMouse(false)
        -- And out of Blizzard's Edit Mode: no highlight, nothing to select.
        if type(MinimapCluster.HighlightSystem) == "function" then
            MinimapCluster.defaultHideSelection = true
            hooksecurefunc(MinimapCluster, "HighlightSystem", function(f)
                if f.ClearHighlight then f:ClearHighlight() end
            end)
            if MinimapCluster.isHighlighted and MinimapCluster.ClearHighlight then MinimapCluster:ClearHighlight() end
        end
    end

    ns.Layout()
end

-- Addons that place buttons round the map ask for its shape (LibDBIcon).
if not GetMinimapShape then
    function GetMinimapShape() return "SQUARE" end
end

-- The hybrid map (some instances) masks its own canvas round.
local function SquareHybrid()
    local h = HybridMinimap
    if h and h.CircleMask then h.CircleMask:SetTexture(SQUARE_MASK) end
end

function M:Refresh()
    if not adopted then return end
    ns.Safe("layout", ns.Layout, map)
    if ns.RefreshInfo then ns.RefreshInfo() end
end

function M:OnEnable()
    ns.Safe("adopt", Adopt, Minimap)
    SquareHybrid()
    self:RegisterEvent("ADDON_LOADED", function(_, _, name)
        if name == "Blizzard_HybridMinimap" then SquareHybrid() end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        self:Refresh()
        SquareHybrid()
    end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
end

function M:OnProfileChanged() self:Refresh() end
