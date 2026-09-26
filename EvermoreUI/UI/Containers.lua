if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Containers.lua
--  Tabs, Scroll, Window, Panel, Section, Divider, Label, ColorSwatch.
--
--  W.Tabs(parent, tabs, get, set)       tabs: { { value, text, icon? }, ... }
--  W.Scroll(parent)                     .content child, thin themed bar
--  W.Window(name, opts)                 our own top-level window
--      opts: { title, width, height, movable = true, escape = true, closable = true }
--  W.Panel(parent, token)               raised box (surface1 + border)
--  W.Section(parent, text)              heading with a hairline under it
--  W.Divider(parent)                    1px hairline
--  W.Label(parent, text, role, size)    role: text, textMuted, title, accent...
--  W.ColorSwatch(parent, get, set, hasAlpha)  opens the colour picker
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local U = EV.UI
local max, min = math.max, math.min

--------------------------------------------------------------------------------
--  Tabs: text (or icon) with an accent underline on the selected one. The
--  same look the skins give Blizzard's tabs.
--------------------------------------------------------------------------------
function U.Tabs(parent, tabs, get, set, opts)
    opts = opts or {}
    local H = opts.height or 32
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(H)
    f.buttons = {}
    local line = T.Solid(f, "BACKGROUND", 1, 1, 1, 0.08)
    line:SetPoint("BOTTOMLEFT"); line:SetPoint("BOTTOMRIGHT"); line:SetHeight(1)
    U.Init(f)

    local x = 0
    for i, t in ipairs(tabs) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(H)
        b:SetPoint("BOTTOMLEFT", x, 0)
        local text = T.Font(b, T.SIZE.label, true, 1, "CENTER")
        text:SetText(t.text or "")
        local icon
        if t.icon then
            icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetTexture(t.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        local w = (text:GetStringWidth() or 0) + (icon and 22 or 0) + 28
        if opts.minWidth then w = max(w, opts.minWidth) end
        b:SetWidth(w)
        if icon then
            icon:SetPoint("LEFT", 14, 0)
            text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        else
            text:SetPoint("CENTER", 0, 1)
        end
        local hl = T.Solid(b, "BACKGROUND", 1, 1, 1, 0.04)
        hl:SetAllPoints()
        local bar = T.Fill(b, "ARTWORK", "accent")
        bar:SetPoint("BOTTOMLEFT", 6, 0); bar:SetPoint("BOTTOMRIGHT", -6, 0); bar:SetHeight(2)
        local ctl = { _hover = false }
        function ctl.Paint()
            local sel = get() == t.value
            bar:SetShown(sel or ctl._hover)
            if sel then bar:SetColorTexture(T.RGBA("accent")) else bar:SetColorTexture(T.RGBA("borderStrong")) end
            hl:SetShown(ctl._hover and not sel)
            text:SetTextColor(T.RGBA((sel or ctl._hover) and "text" or "textMuted"))
            if icon then icon:SetDesaturated(not sel and not ctl._hover) end
        end
        function ctl.ShowTip() if t.tooltip then T.ShowTooltip(b, t.text, t.tooltip) end end
        function ctl.HideTip() if t.tooltip then T.HideTooltip() end end
        U.Interactive(ctl, b)
        b:SetScript("OnClick", function()
            if get() == t.value then return end
            set(t.value)
            f:Refresh()
            U.Changed(f)
        end)
        b.ctl = ctl
        f.buttons[i] = b
        x = x + w + (opts.gap or 0)
    end
    f:SetWidth(max(x, 1))
    function f:Paint()
        line:SetColorTexture(T.RGBA("divider"))
        for _, b in ipairs(self.buttons) do b.ctl.Paint() end
    end
    function f:Refresh() self:Paint() end
    f:Refresh()
    return f
end

--------------------------------------------------------------------------------
--  Scroll: a scroll frame with our thin bar (hidden when content fits).
--  scroll.content is the child to fill; its height drives the range, or call
--  scroll:SetContentHeight(h).
--------------------------------------------------------------------------------
function U.Scroll(parent, opts)
    opts = opts or {}
    local GAP = 4
    local holder = CreateFrame("Frame", nil, parent)
    local sf = CreateFrame("ScrollFrame", nil, holder)
    sf:SetPoint("TOPLEFT")
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    holder.content, holder.scrollFrame = content, sf

    local function Range() return max(0, content:GetHeight() - sf:GetHeight()) end
    -- Content with secure children (quest item buttons) makes all of this a
    -- protected frame, which can't be moved, resized or scrolled in combat.
    local function Locked() return InCombatLockdown() and sf:IsProtected() end

    local bar = U.ScrollBar(holder, {
        range = Range,
        offset = function() return sf:GetVerticalScroll() end,
        visible = function() return sf:GetHeight() end,
        set = function(v) if not Locked() then sf:SetVerticalScroll(max(0, min(Range(), v))) end end,
        step = opts.step or 40,
    }, { mode = opts.mode or "auto" })
    bar:SetPoint("TOPRIGHT", -2, 0)
    bar:SetPoint("BOTTOMRIGHT", -2, 0)
    holder.bar = bar

    local lastRoom
    local function Update()
        bar:Update()
        if Locked() then return end
        -- Room for the bar only while it shows (or always, if asked).
        local room = (opts.reserve or bar:IsShown()) and (bar:GetWidth() + GAP + 2) or 0
        if room ~= lastRoom then
            sf:SetPoint("BOTTOMRIGHT", -room, 0)
            lastRoom = room
        end
        content:SetWidth(sf:GetWidth())
        -- Content shrank under us: don't leave the view past the end.
        local range = Range()
        if sf:GetVerticalScroll() > range then sf:SetVerticalScroll(range) end
        bar:Update()
    end
    function holder:ScrollTo(y)
        if Locked() then return end
        sf:SetVerticalScroll(max(0, min(Range(), y)))
        bar:Update()
    end
    function holder:SetContentHeight(h)
        if Locked() then return end
        content:SetHeight(max(h, 1))
        Update()
    end
    function holder:GetScroll() return sf:GetVerticalScroll() end

    holder:EnableMouseWheel(true)
    holder:SetScript("OnMouseWheel", function(_, delta) holder:ScrollTo(sf:GetVerticalScroll() - delta * (opts.step or 40)) end)
    content:SetScript("OnSizeChanged", Update)
    sf:SetScript("OnSizeChanged", Update)
    C_Timer.After(0, Update)
    holder.Update = Update
    return holder
end

--------------------------------------------------------------------------------
--  Panel, Section, Divider, Label
--------------------------------------------------------------------------------
function U.Panel(parent, token)
    local p = CreateFrame("Frame", nil, parent)
    p._token = token or "surface1"
    p._bg = T.Fill(p, "BACKGROUND", p._token)
    p._bg:SetAllPoints()
    T.TokenBorder(p, "border")
    function p:Paint()
        self._bg:SetColorTexture(T.RGBA(self._token))
        T.SetBorderToken(self, "border")
    end
    T.Watch(p)
    return p
end

function U.Label(parent, text, role, size, bold)
    local fs = T.Text(parent, size or "body", role or "text", bold)
    fs:SetText(text or "")
    local holder = { Paint = function() fs:SetTextColor(T.RGBA(role or "text")) end }
    T.Watch(holder)
    fs._themeHolder = holder -- keep it alive with the font string
    return fs
end

function U.Divider(parent)
    local d = T.Solid(parent, "ARTWORK", T.RGBA("divider"))
    d:SetHeight(1)
    local holder = { Paint = function() d:SetColorTexture(T.RGBA("divider")) end }
    T.Watch(holder)
    d._themeHolder = holder
    return d
end

function U.Section(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(28)
    local fs = U.Label(f, text, "title", "label", true)
    fs:SetPoint("BOTTOMLEFT", 0, 7)
    local d = U.Divider(f)
    d:SetPoint("BOTTOMLEFT"); d:SetPoint("BOTTOMRIGHT")
    f.text = fs
    return f
end

--------------------------------------------------------------------------------
--  Window: our own top-level frame in the house style.
--------------------------------------------------------------------------------
function U.Window(name, opts)
    opts = opts or {}
    local w = CreateFrame("Frame", name, UIParent)
    w:SetSize(opts.width or 480, opts.height or 360)
    w:SetPoint("CENTER")
    w:SetFrameStrata(opts.strata or "HIGH")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:Hide()
    w._bg = T.Fill(w, "BACKGROUND", "surface0", 0.97)
    w._bg:SetAllPoints()
    T.TokenBorder(w, "border")
    T.Shadow(w, 12)

    local TB = opts.titleHeight or 32
    local bar = CreateFrame("Frame", nil, w)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TB)
    bar._bg = T.Fill(bar, "BACKGROUND", "titleBar")
    bar._bg:SetAllPoints()
    local rule = T.Solid(bar, "BORDER", 1, 1, 1, 0.08)
    rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
    local title = T.Text(bar, "title", "text", true)
    title:SetPoint("LEFT", 12, 0)
    title:SetText(opts.title or "")
    w.titleBar, w.title = bar, title

    if opts.closable ~= false then
        local close = U.CloseButton(bar, TB - 8, function() w:Hide() end)
        close:SetPoint("RIGHT", -4, 0)
        w.closeButton = close
    end
    if opts.movable ~= false then
        w:SetMovable(true)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", function() w:StartMoving() end)
        bar:SetScript("OnDragStop", function() w:StopMovingOrSizing() end)
    end
    if name and opts.escape ~= false then tinsert(UISpecialFrames, name) end

    local body = CreateFrame("Frame", nil, w)
    body:SetPoint("TOPLEFT", 1, -(TB + 1))
    body:SetPoint("BOTTOMRIGHT", -1, 1)
    w.body = body

    function w:SetTitle(s) title:SetText(s or "") end
    function w:Paint()
        self._bg:SetColorTexture(T.RGBA("surface0", 0.97))
        bar._bg:SetColorTexture(T.RGBA("titleBar"))
        rule:SetColorTexture(T.RGBA("divider"))
        title:SetTextColor(T.RGBA("text"))
        T.SetBorderToken(self, "border")
    end
    T.Watch(w)
    return w
end

--------------------------------------------------------------------------------
--  ColorSwatch: shows a colour; click opens Blizzard's colour picker.
--  get() returns r, g, b[, a]; set(r, g, b, a).
--------------------------------------------------------------------------------
function U.ColorSwatch(parent, get, set, hasAlpha)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(U.HEIGHT + 8, U.HEIGHT - 6)
    -- Checker behind the colour so alpha is visible.
    local c1 = T.Solid(b, "BACKGROUND", 0.8, 0.8, 0.8, 1)
    c1:SetAllPoints()
    local q = {}
    for i = 1, 2 do
        q[i] = T.Solid(b, "BACKGROUND", 0.55, 0.55, 0.55, 1, 1)
    end
    q[1]:SetPoint("TOPLEFT"); q[1]:SetPoint("BOTTOMRIGHT", b, "CENTER")
    q[2]:SetPoint("TOPLEFT", b, "CENTER"); q[2]:SetPoint("BOTTOMRIGHT")
    local swatch = T.Solid(b, "ARTWORK", 1, 1, 1, 1)
    swatch:SetAllPoints()
    T.TokenBorder(b, "borderStrong")
    U.Init(b)

    function b:Paint()
        if self._hover then T.SetBorderToken(self, "text") else T.SetBorderToken(self, "borderStrong") end
    end
    function b:Refresh()
        local r, g, bl, a = get()
        swatch:SetColorTexture(r or 1, g or 1, bl or 1, hasAlpha and (a or 1) or 1)
    end
    b:SetScript("OnClick", function(self)
        local r, g, bl, a = get()
        local picker = ColorPickerFrame
        if not picker then return end
        local function apply()
            local nr, ng, nb = picker:GetColorRGB()
            local na = hasAlpha and picker.GetColorAlpha and picker:GetColorAlpha() or a
            set(nr, ng, nb, na)
            self:Refresh()
            U.Changed(self)
        end
        local info = {
            r = r or 1, g = g or 1, b = bl or 1, opacity = a or 1, hasOpacity = hasAlpha and true or false,
            swatchFunc = apply, opacityFunc = apply,
            cancelFunc = function()
                set(r, g, bl, a)
                self:Refresh()
                U.Changed(self)
            end,
        }
        if picker.SetupColorPickerAndShow then picker:SetupColorPickerAndShow(info) end
    end)
    U.Interactive(b)
    b:Paint()
    b:Refresh()
    return b
end
