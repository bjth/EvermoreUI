if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Dropdown.lua
--  Dropdown and the one shared popup menu behind it.
--
--  W.Dropdown(parent, width, values, get, set)
--    values: list (or function returning one) of entries:
--      { value = x, text = "Label" }                 a choice
--      { value = x, text = "Label", icon = tex }     with an icon
--      { value = x, text = "Label", disabled = true }
--      { value = x, text = "Label", detail = "1:42" } with muted text on the right
--      { header = "Section" }                         non-clickable heading
--      { separator = true }                           divider line
--  Long lists get a filter box at the top. The menu is as wide as its
--  widest entry (never narrower than its owner), up to MAX_W.
--
--  U.Menu:Open(owner, list, current, onPick) is usable on its own for
--  context menus.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local U = EV.UI
local max, min = math.max, math.min

local ITEM_H, MAX_VISIBLE, SEARCH_OVER = 26, 12, 14
local MIN_W, MAX_W = 140, 420
local PAD_L, PAD_ICON, PAD_R, DETAIL_GAP = 12, 32, 10, 16
local MENU, DROP = T.LOOK.menu, T.LOOK.dropdown
local rowState, rowOut = {}, {}

local Menu

local function BuildMenu()
    local m = CreateFrame("Frame", "EvermoreUIDropdownMenu", UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    m:Hide()
    m._bg = T.Fill(m, "BACKGROUND", "surface1")
    m._bg:SetAllPoints()
    T.TokenBorder(m, "border")
    T.Shadow(m, 8)

    -- Clicking anywhere else closes the menu.
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetAllPoints(WorldFrame)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function() m:Hide() end)
    catcher:Hide()
    m.catcher = catcher

    local filter = U.SearchBox(m, 100, function(txt) m:Filter(txt) end, EV.L["Filter"])
    filter:SetPoint("TOPLEFT", 6, -6)
    filter:SetPoint("TOPRIGHT", -6, -6)
    filter:SetHeight(24)
    filter:Hide()
    m.filterBox = filter

    -- Measures entries for the menu's width: shown, so it lays out, but
    -- clear and without a shadow.
    m.measure = T.Font(m, T.SIZE.body, false, 0)
    T.TextShadow(m.measure, false)
    m.measure:SetPoint("TOPLEFT")

    m.items = {}
    m.offset = 0
    m:SetScript("OnShow", function(self)
        catcher:SetFrameLevel(max(self:GetFrameLevel() - 5, 0))
        catcher:Show()
    end)
    m:SetScript("OnHide", function(self)
        catcher:Hide()
        filter:SetText("")
        filter:ClearFocus()
        if self.owner and self.owner.OnMenuClosed then self.owner:OnMenuClosed() end
        self.owner = nil
    end)
    m:SetScript("OnMouseWheel", function(self, delta)
        local maxOff = max(0, #self.view - MAX_VISIBLE)
        self.offset = max(0, min(maxOff, self.offset - delta))
        self:Layout()
    end)

    local function Item(i)
        local it = m.items[i]
        if it then return it end
        it = CreateFrame("Button", nil, m)
        it:SetHeight(ITEM_H)
        it.hl = T.Fill(it, "BACKGROUND", "surface3")
        it.hl:SetAllPoints()
        it.hl:Hide()
        it.mark = T.Fill(it, "ARTWORK", "accent")
        it.mark:SetPoint("TOPLEFT", 0, 0)
        it.mark:SetPoint("BOTTOMLEFT", 0, 0)
        it.mark:SetWidth(2)
        it.sep = T.Solid(it, "ARTWORK", 1, 1, 1, 0.1)
        it.sep:SetHeight(1)
        it.sep:SetPoint("LEFT", 8, 0)
        it.sep:SetPoint("RIGHT", -8, 0)
        it.icon = it:CreateTexture(nil, "ARTWORK")
        it.icon:SetSize(16, 16)
        it.icon:SetPoint("LEFT", 10, 0)
        it.text = T.Font(it, T.SIZE.body, false, 1)
        it.text:SetPoint("RIGHT", -PAD_R, 0)
        it.detail = T.Font(it, T.SIZE.body, false, 1, "RIGHT")
        it.detail:SetPoint("RIGHT", -PAD_R, 0)
        it:SetScript("OnEnter", function(self) if self.pickable then self.hl:Show() end end)
        it:SetScript("OnLeave", function(self) self.hl:Hide() end)
        it:SetScript("OnClick", function(self)
            if not self.pickable then return end
            local pick, value = m.onPick, self.value
            m:Hide()
            if pick then pick(value) end
        end)
        m.items[i] = it
        return it
    end

    function m:Filter(txt)
        txt = (txt or ""):lower()
        self.view = {}
        for _, e in ipairs(self.list) do
            if txt == "" or (e.text and not e.header and not e.separator and e.text:lower():find(txt, 1, true)) then
                self.view[#self.view + 1] = e
            end
        end
        self.offset = 0
        self:Layout()
    end

    function m:Layout()
        local top = self.filterBox:IsShown() and 36 or 1
        local n = min(#self.view, MAX_VISIBLE)
        for _, it in ipairs(self.items) do it:Hide() end
        for i = 1, n do
            local e = self.view[i + self.offset]
            local it = Item(i)
            it:ClearAllPoints()
            it:SetPoint("TOPLEFT", 1, -top - (i - 1) * ITEM_H)
            it:SetPoint("TOPRIGHT", -1, -top - (i - 1) * ITEM_H)
            it.value = e.value
            it.pickable = not (e.header or e.separator or e.disabled)
            it.sep:SetShown(e.separator and true or false)
            local selected = it.pickable and e.value == self.current
            rowState.on, rowState.disabled, rowState.hover = selected, e.disabled, true
            local r = T.Resolve(MENU, rowState, rowOut)
            it.sep:SetColorTexture(T.C4(r.divider))
            it.mark:SetShown(selected)
            if r.mark then it.mark:SetColorTexture(T.C4(r.mark)) end
            it.hl:SetColorTexture(T.C4(r.row))
            it.icon:SetShown(e.icon ~= nil)
            if e.icon then it.icon:SetTexture(e.icon) end
            it.text:ClearAllPoints()
            it.text:SetPoint("LEFT", e.icon and PAD_ICON or PAD_L, 0)
            local detail = not e.header and e.detail
            it.detail:SetShown(detail and true or false)
            if detail then
                it.detail:SetText(detail)
                it.detail:SetTextColor(T.RGBA("textMuted"))
                it.text:SetPoint("RIGHT", it.detail, "LEFT", -DETAIL_GAP, 0)
            else
                it.text:SetPoint("RIGHT", -PAD_R, 0)
            end
            it.text:SetText(e.header or e.text or "")
            if e.header then
                it.text:SetFont(T.FontBoldPath(), T.SIZE.small, "")
                it.text:SetTextColor(T.C4(r.header))
            else
                it.text:SetFont(T.FontPath(), T.SIZE.body, "")
                it.text:SetTextColor(T.C4(r.text))
            end
            it:Show()
        end
        self:SetHeight(max(n, 1) * ITEM_H + top + 1)
    end

    -- The widest entry, text and detail, with its padding.
    function m:Widest()
        local fs, widest = self.measure, 0
        for _, e in ipairs(self.list) do
            if not e.separator then
                local w = e.icon and PAD_ICON or PAD_L
                if e.header then
                    fs:SetFont(T.FontBoldPath(), T.SIZE.small, "")
                    fs:SetText(e.header)
                else
                    fs:SetFont(T.FontPath(), T.SIZE.body, "")
                    fs:SetText(e.text or "")
                end
                w = w + fs:GetUnboundedStringWidth()
                if e.detail and not e.header then
                    fs:SetFont(T.FontPath(), T.SIZE.body, "")
                    fs:SetText(e.detail)
                    w = w + DETAIL_GAP + fs:GetUnboundedStringWidth()
                end
                widest = max(widest, w + PAD_R + 2)
            end
        end
        return math.ceil(widest)
    end

    function m:Paint()
        local r = T.Resolve(MENU)
        self._bg:SetColorTexture(T.C4(r.fill))
        T.SetEdge(self, r.edge)
        if self:IsShown() then self:Layout() end
    end
    T.Watch(m)

    function m:Open(owner, list, current, onPick)
        if self:IsShown() and self.owner == owner then self:Hide(); return end
        if self:IsShown() then self:Hide() end
        self.owner, self.list, self.current, self.onPick = owner, list, current, onPick
        local choices = 0
        for _, e in ipairs(list) do if not (e.header or e.separator) then choices = choices + 1 end end
        self.filterBox:SetShown(choices > SEARCH_OVER)
        self:Filter("")
        for i, e in ipairs(self.view) do
            if e.value == current and i > MAX_VISIBLE then self.offset = min(i - 1, #self.view - MAX_VISIBLE) end
        end
        self:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())
        self:SetFrameLevel(100)
        self:SetWidth(min(max(owner:GetWidth(), MIN_W, self:Widest()), MAX_W))
        self:Layout()
        self:ClearAllPoints()
        local bottom = owner:GetBottom() or 0
        if bottom * owner:GetEffectiveScale() - self:GetHeight() * self:GetEffectiveScale() < 20 then
            self:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
        else
            self:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
        end
        self:Show()
        self:Raise()
        if self.filterBox:IsShown() then self.filterBox:SetFocus() end
    end

    return m
end

function U.GetMenu()
    Menu = Menu or BuildMenu()
    return Menu
end

function U.Dropdown(parent, width, values, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 190, U.HEIGHT)
    local fill = T.Fill(b, "BACKGROUND", "surface2")
    fill:SetAllPoints()
    T.TokenBorder(b, "borderStrong")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 8, 0)
    icon:Hide()
    local label = T.Font(b, T.SIZE.body, false, 1)
    label:SetPoint("RIGHT", -28, 0)
    local chev = T.Chevron(b, DROP.chevron, 1)
    chev:SetPoint("RIGHT", -10, 0)
    U.Init(b)
    b._look = DROP

    local function List() return type(values) == "function" and values() or values end

    function b:Paint()
        self._open = Menu and Menu.owner == self and Menu:IsShown() or false
        local r = U.PaintBox(self, fill, DROP)
        label:SetTextColor(T.C4(r.text))
        chev:SetColorLines(T.C4(r.glyph))
    end

    function b:Refresh()
        local cur = get()
        local found
        for _, e in ipairs(List()) do
            if not (e.header or e.separator) and e.value == cur then found = e; break end
        end
        label:SetText(found and found.text or (cur ~= nil and tostring(cur) or ""))
        icon:SetShown(found and found.icon ~= nil or false)
        if found and found.icon then icon:SetTexture(found.icon) end
        label:ClearAllPoints()
        label:SetPoint("LEFT", icon:IsShown() and 30 or 10, 0)
        label:SetPoint("RIGHT", -28, 0)
    end

    function b:OnMenuClosed() chev:Flip(false); self:Paint() end
    b:SetScript("OnClick", function(self)
        local m = U.GetMenu()
        chev:Flip(true)
        m:Open(self, List(), get(), function(v)
            set(v)
            self:Refresh()
            U.Changed(self)
        end)
        self:Paint()
    end)
    b:SetScript("OnHide", function(self) if Menu and Menu.owner == self then Menu:Hide() end end)
    U.Interactive(b)
    b:Paint()
    b:Refresh()
    return b
end
