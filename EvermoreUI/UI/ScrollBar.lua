if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  ScrollBar.lua
--  The one scroll bar every EvermoreUI surface uses: the options window,
--  chat, the objective tracker, U.Scroll and anything built later.
--
--  It drives whatever scrolls through a small source table, so it doesn't
--  care whether that's a ScrollFrame, a chat window or a list we draw:
--
--    U.ScrollBar(parent, {
--        range   = function() return maxOffset end,  -- 0: nothing to scroll
--        offset  = function() return current end,
--        visible = function() return viewSize end,   -- same units as range
--        set     = function(v) ... end,              -- move there (we clamp)
--        fromBottom = true,  -- offset 0 is the bottom (chat); default top
--        step    = 40,       -- mouse wheel over the bar
--    }, { mode = "auto" })
--
--  Modes: "auto"/"always" (shown whenever there's something to scroll),
--  "scrolled" (only while away from the resting end, or dragging), "never".
--
--  Look: a slim track in surface2 with a borderStrong thumb. Hover lifts the
--  thumb to textMuted and widens it; dragging turns it accent. Click the
--  track to jump there and keep dragging. Call bar:Update() whenever the
--  source changes; the owner handles its own mouse wheel.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T, U = EV.Theme, EV.UI
local max, min, floor = math.max, math.min, math.floor

local WIDTH = 6        -- the hit area and track
local THIN = 4         -- the thumb at rest
local MIN_THUMB = 24

function U.ScrollBar(parent, source, opts)
    opts = opts or {}
    local bar = CreateFrame("Button", nil, parent)
    bar:SetWidth(opts.width or WIDTH)
    bar:EnableMouse(true)
    bar:EnableMouseWheel(true)
    bar:RegisterForClicks("LeftButtonDown")
    bar.source = source
    bar.mode = opts.mode or "auto"

    bar.track = T.Fill(bar, "BACKGROUND", "surface2", 0.7)
    bar.track:SetPoint("TOP")
    bar.track:SetPoint("BOTTOM")
    bar.track:SetWidth(opts.width or WIDTH)
    bar.thumb = T.Fill(bar, "ARTWORK", "borderStrong", 1)
    bar.thumb:SetWidth(THIN)

    local function Range() return max(0, source.range() or 0) end

    function bar:Paint()
        local token = self.dragging and "accent" or (self.hover and "textMuted") or "borderStrong"
        self.thumb:SetColorTexture(T.RGBA(token, 1))
        self.thumb:SetWidth((self.hover or self.dragging) and (opts.width or WIDTH) or THIN)
        self.track:SetColorTexture(T.RGBA("surface2", 0.7))
    end
    T.Watch(bar)

    --- Should the bar be on screen right now?
    function bar:Wanted()
        local range = Range()
        if range <= 0.5 or self.mode == "never" then return false end
        if self.mode == "scrolled" then
            return self.dragging or (source.offset() or 0) > 0.5
        end
        return true
    end

    function bar:Update()
        local show = self:Wanted()
        if self:IsShown() ~= show then self:SetShown(show) end
        if not show then return end
        local h = self:GetHeight()
        local range = Range()
        if not h or h <= 0 or range <= 0 then return end
        local visible = max(1, source.visible() or 1)
        local th = max(MIN_THUMB, min(h, h * visible / (range + visible)))
        local frac = max(0, min(1, (source.offset() or 0) / range))
        self.thumb:SetHeight(th)
        self.thumb:ClearAllPoints()
        if source.fromBottom then
            self.thumb:SetPoint("BOTTOM", self, "BOTTOM", 0, frac * (h - th))
        else
            self.thumb:SetPoint("TOP", self, "TOP", 0, -frac * (h - th))
        end
    end

    function bar:SetMode(mode)
        self.mode = mode or "auto"
        self:Update()
    end

    -- Drag: from where you grabbed the thumb, or its middle after a track click.
    local function FromCursor(self)
        local h, th = self:GetHeight(), self.thumb:GetHeight()
        local travel = h - th
        local range = Range()
        if travel <= 0 or range <= 0 then return end
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local pos
        if source.fromBottom then
            pos = (cy - (self:GetBottom() or 0) - self.grab) / travel
        else
            pos = ((self:GetTop() or 0) - cy - self.grab) / travel
        end
        source.set(max(0, min(1, pos)) * range)
        self:Update()
    end

    bar:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local _, cy = GetCursorPosition()
        cy = cy / self:GetEffectiveScale()
        local top, bottom = self.thumb:GetTop(), self.thumb:GetBottom()
        local onThumb = top and bottom and cy <= top and cy >= bottom
        if source.fromBottom then
            self.grab = onThumb and (cy - bottom) or self.thumb:GetHeight() / 2
        else
            self.grab = onThumb and (top - cy) or self.thumb:GetHeight() / 2
        end
        self.dragging = true
        self:Paint()
        FromCursor(self)
        self:SetScript("OnUpdate", function(s)
            if not IsMouseButtonDown("LeftButton") then
                s.dragging = nil
                s:SetScript("OnUpdate", nil)
                s:Paint()
                s:Update()
                return
            end
            FromCursor(s)
        end)
    end)
    bar:SetScript("OnMouseUp", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        self:Paint()
        self:Update()
    end)
    bar:SetScript("OnEnter", function(self) self.hover = true; self:Paint() end)
    bar:SetScript("OnLeave", function(self) self.hover = nil; self:Paint() end)
    bar:SetScript("OnMouseWheel", function(self, delta)
        local step = source.step or 40
        local v = (source.offset() or 0) + (source.fromBottom and delta or -delta) * step
        source.set(max(0, min(Range(), v)))
        self:Update()
    end)
    bar:SetScript("OnSizeChanged", function(self) self:Update() end)

    bar:Paint()
    bar:Hide()
    return bar
end
