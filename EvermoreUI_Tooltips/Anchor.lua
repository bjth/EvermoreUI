if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Anchor.lua
--  Where the default tooltip goes (units, world objects, action buttons: the
--  ones Blizzard places with GameTooltip_SetDefaultAnchor).
--    fixed    our box, moved in EvermoreUI edit mode; first placed exactly
--             where Blizzard's tooltip spot is, so nothing moves until you do.
--             The tooltip grows away from the nearest screen edge.
--    cursor   follows the mouse, at a chosen side and offset
--    blizzard left alone
--  Owners handed to us can be forbidden frames (nameplate auras); those are
--  left entirely to Blizzard.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local issecret = ns.issecret

local KEY = "TOOLTIP_anchor"
local W, H = 250, 120

local function OwnerUsable(owner)
    if not owner then return false end
    local fn = owner.IsForbidden
    return not (type(fn) == "function" and fn(owner))
end

local function GlobalLike(tt)
    return tt == GameTooltip or (type(tt) == "table" and tt.LIKE_GLOBAL_GAMETOOLTIP == true)
end

--------------------------------------------------------------------------------
--  Fixed box
--------------------------------------------------------------------------------
local box = CreateFrame("Frame", "EvermoreUITooltipAnchor", UIParent)
box:SetSize(W, H)
box:EnableMouse(false)
box:SetClampedToScreen(true)

local function Owned()
    local core = EV.DB:GetCore()
    return core.movers[KEY] ~= nil or core.anchors[KEY] ~= nil
end

--- A rect's position in UIParent units, as x, y, width, height. Nil if any
--- of it is missing or secret.
local function RectInUI(f)
    local x, y, w, h = f:GetRect()
    for _, v in ipairs({ x or false, y or false, w or false, h or false }) do
        if not v or issecret(v) then return nil end
    end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x * k, y * k, w * k, h * k
end

--- Which quarter of the screen a rect's centre is in: "LEFT" or "RIGHT",
--- then "BOTTOM" or "TOP".
local function Quarter(x, y, w, h)
    local midX, midY = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    return (x + w / 2 < midX) and "LEFT" or "RIGHT", (y + h / 2 < midY) and "BOTTOM" or "TOP"
end

-- First sight: put our box's outer corner on Blizzard's tooltip spot. The
-- corner is the one facing the nearest screen edges, so the tooltip grows
-- inwards from wherever Blizzard had it.
local function Seed()
    if Owned() then return end
    local c = GameTooltipDefaultContainer
    if not (c and c.GetRect) then return end
    local x, y, w, h = RectInUI(c)
    if not x then return end
    local horiz, vert = Quarter(x, y, w, h)
    local edgeX = (horiz == "LEFT") and x or (x + w)
    local edgeY = (vert == "BOTTOM") and y or (y + h)
    -- The box's own centre sits half a box inwards from that corner.
    local boxX = edgeX + ((horiz == "LEFT") and W or -W) / 2
    local boxY = edgeY + ((vert == "BOTTOM") and H or -H) / 2
    EV.Movers:SetOffset(KEY, boxX - UIParent:GetWidth() / 2, boxY - UIParent:GetHeight() / 2)
end

local function Corner()
    local x, y = box:GetLeft(), box:GetBottom()
    if not (x and y) then return "BOTTOMRIGHT" end
    local horiz, vert = Quarter(x, y, box:GetWidth(), box:GetHeight())
    return vert .. horiz
end

--------------------------------------------------------------------------------
--  Fixed position
--
--  Between Blizzard's default anchor call and the next time anyone takes the
--  tooltip over (SetOwner), every SetPoint on it is answered by putting it
--  back on our corner. `claimed` is that window; `moving` stops us answering
--  our own SetPoint.
--------------------------------------------------------------------------------
local claimed, moving = false, false

local function OnOurCorner(tt, corner)
    if tt:GetNumPoints() ~= 1 then return false end
    local point, relativeTo = tt:GetPoint(1)
    if issecret(point) or issecret(relativeTo) then return false end
    return point == corner and relativeTo == box
end

local function Enforce(tt)
    if M.db.anchor ~= "fixed" or tt:IsForbidden() then return end
    local corner = Corner()
    if OnOurCorner(tt, corner) then return end
    moving = true
    tt:ClearAllPoints()
    tt:SetPoint(corner, box, corner, 0, 0)
    moving = false
end

--------------------------------------------------------------------------------
--  Cursor
--------------------------------------------------------------------------------
--- The tooltip point that faces the cursor: the tooltip sits on `side` of it,
--- so it is anchored by the opposite point ("topleft" -> "BOTTOMRIGHT").
local function PointFor(side)
    local vert = (side:find("^top") and "BOTTOM") or (side:find("^bottom") and "TOP") or ""
    local horiz = (side:find("left$") and "RIGHT") or (side:find("right$") and "LEFT") or ""
    local point = vert .. horiz
    return point ~= "" and point or "LEFT"
end

local tracker = CreateFrame("Frame", "EvermoreUITooltipCursor", UIParent)
tracker:SetSize(1, 1)
tracker:SetFrameStrata("TOOLTIP")
tracker:Hide()
local function PlaceTracker()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    tracker:ClearAllPoints()
    tracker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end
tracker:SetScript("OnUpdate", PlaceTracker)

local hideHooked = setmetatable({}, { __mode = "k" })
local function Cursor(tt)
    if not hideHooked[tt] then
        hideHooked[tt] = true
        tt:HookScript("OnHide", function() tracker:Hide() end)
    end
    tracker:Show()
    PlaceTracker()
    -- Offsets are distances away from the cursor, whichever side it's on.
    local side = M.db.cursorPos
    local sx = side:find("left") and -1 or 1
    local sy = side:find("bottom") and -1 or 1
    tt:ClearAllPoints()
    tt:SetPoint(PointFor(side), tracker, "CENTER", sx * M.db.cursorX, sy * M.db.cursorY)
end

--------------------------------------------------------------------------------
--  Hooks
--------------------------------------------------------------------------------
local function OnDefaultAnchor(tt, owner)
    if not GlobalLike(tt) then return end
    if tt == GameTooltip then claimed = true end
    local mode = M.db.anchor
    if mode == "blizzard" or not M:IsEnabled() then return end
    if tt:IsForbidden() or not OwnerUsable(owner) then claimed = false; return end
    -- Blizzard has already owned it with ANCHOR_NONE; we only move it.
    if mode == "cursor" then Cursor(tt) else Enforce(tt) end
end

function ns.ApplyAnchor()
    if M.db.anchor ~= "cursor" then tracker:Hide() end
    EV.Movers:Apply(KEY)
end

function ns.InitAnchor()
    EV.Movers:Register(box, KEY, L["Tooltip"], { "BOTTOMRIGHT", "BOTTOMRIGHT", -120, 160 }, {
        group = L["Tooltips"], page = "tooltips",
        isDisabled = function() return M.db.anchor ~= "fixed" end,
    })
    hooksecurefunc("GameTooltip_SetDefaultAnchor", OnDefaultAnchor)
    -- Anything that re-owns the tooltip itself (action buttons with their own
    -- anchor, addons) is its business; stop enforcing until the next default.
    hooksecurefunc(GameTooltip, "SetOwner", function() claimed = false end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tt)
        if tt == GameTooltip and claimed and not moving and M.db.anchor == "fixed" then Enforce(tt) end
    end)
    -- The tracker stops with the tooltip, and also when a world unit's tip
    -- starts its slow fade: better it fades where it is than trails the mouse.
    local function StopTracking() tracker:Hide() end
    GameTooltip:HookScript("OnHide", StopTracking)
    if GameTooltip.FadeOut then
        hooksecurefunc(GameTooltip, "FadeOut", function(tt)
            if tt == GameTooltip and M.db.anchor == "cursor" then StopTracking() end
        end)
    end
    -- Seed once Edit Mode has placed Blizzard's container (its layout lands
    -- a little after entering the world).
    local seed = CreateFrame("Frame")
    seed:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(seed.RegisterEvent, seed, "EDIT_MODE_LAYOUTS_UPDATED")
    seed:SetScript("OnEvent", function(self)
        C_Timer.After(1, function()
            Seed()
            if Owned() then self:UnregisterAllEvents() end
        end)
    end)
end

-- A new profile has no saved spot: take Blizzard's again.
ns.SeedAnchor = Seed
