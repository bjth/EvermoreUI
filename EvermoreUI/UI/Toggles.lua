if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Toggles.lua
--  Toggle (switch), Checkbox, RadioGroup.
--
--  W.Toggle(parent, get, set)
--  W.Checkbox(parent, label, get, set)          label optional, clickable
--  W.RadioGroup(parent, options, get, set, opts)
--      options: { { value = x, text = "Label", tooltip = "..." }, ... }
--      opts: { direction = "vertical" | "horizontal", spacing = 8 }
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local U = EV.UI

--------------------------------------------------------------------------------
--  Toggle: pill track with a sliding knob, animated. Off: outlined track so
--  it is findable (3:1). On: accent track, dark knob edge.
--------------------------------------------------------------------------------
function U.Toggle(parent, get, set)
    local TW, TH, PAD = 40, 20, 3
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TW, TH)
    local track = T.Fill(b, "BACKGROUND", "surface2")
    track:SetAllPoints()
    T.TokenBorder(b, "borderStrong")
    local knob = T.Solid(b, "ARTWORK", 1, 1, 1, 1)
    knob:SetSize(TH - PAD * 2, TH - PAD * 2)
    U.Init(b)

    local pos, state = 0, nil
    function b:Paint()
        local p = pos
        local r1, g1, b1 = T.RGBA(self._hover and "surface3" or "surface2")
        local r2, g2, b2 = T.RGBA("accent")
        track:SetColorTexture(T.Lerp(r1, r2, p), T.Lerp(g1, g2, p), T.Lerp(b1, b2, p), 1)
        if p > 0.5 then
            T.SetBorderColor(self, r2, g2, b2, 1)
        elseif self._hover then
            T.SetBorderColor(self, T.Mix("borderStrong", "text", 0.35))
        else
            T.SetBorderToken(self, "borderStrong")
        end
        local kr, kg, kb = T.RGBA("textMuted")
        local on = p > 0.5
        knob:SetColorTexture(on and 1 or kr, on and 1 or kg, on and 1 or kb, 1)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", self, "LEFT", PAD + p * (TW - TH), 0)
    end

    function b:Refresh(animate)
        local v = get() and true or false
        if v == state then return end
        state = v
        local from, to = pos, v and 1 or 0
        if animate then
            T.Tween(b, 0.16, function(e) pos = T.Lerp(from, to, e); b:Paint() end)
        else
            pos = to; b:Paint()
        end
    end

    b:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh(true)
        U.Changed(self)
    end)
    U.Interactive(b)
    b:Refresh(false)
    return b
end

--------------------------------------------------------------------------------
--  Checkbox: 16px box; checked fills accent with a dark tick.
--------------------------------------------------------------------------------
function U.Checkbox(parent, label, get, set)
    local BOX = 16
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(math.max(BOX, 18))
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(BOX, BOX)
    box:SetPoint("LEFT")
    local fill = T.Fill(box, "BACKGROUND", "surfaceSunk")
    fill:SetAllPoints()
    T.TokenBorder(box, "borderStrong")
    local tick = U.Glyph(box, "check", BOX - 4)
    tick:SetPoint("CENTER")
    local text
    if label then
        text = T.Text(b, "body", "text")
        text:SetPoint("LEFT", box, "RIGHT", 8, 0)
        text:SetText(label)
        b:SetWidth(BOX + 8 + (text:GetStringWidth() or 0) + 2)
        b.label = text
    else
        b:SetWidth(BOX)
    end
    U.Init(b)

    local checked = false
    function b:Paint()
        if checked then
            fill:SetColorTexture(T.RGBA("accent"))
            T.SetBorderToken(box, "accent")
            tick:SetVertexColor(T.RGBA("onAccent"))
            tick:Show()
        else
            fill:SetColorTexture(T.RGBA(self._hover and "surface2" or "surfaceSunk"))
            if self._hover then T.SetBorderColor(box, T.Mix("borderStrong", "text", 0.4))
            else T.SetBorderToken(box, "borderStrong") end
            tick:Hide()
        end
        box:ClearAllPoints()
        box:SetPoint("LEFT", 0, self._pressed and -1 or 0)
    end
    function b:Refresh()
        checked = get() and true or false
        self:Paint()
    end
    function b:SetLabel(s)
        if text then text:SetText(s); self:SetWidth(BOX + 8 + (text:GetStringWidth() or 0) + 2) end
    end
    b:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
        U.Changed(self)
    end)
    U.Interactive(b)
    b:Refresh()
    return b
end

--------------------------------------------------------------------------------
--  RadioGroup: one choice from a short list.
--------------------------------------------------------------------------------
function U.RadioGroup(parent, options, get, set, opts)
    opts = opts or {}
    local vertical = opts.direction ~= "horizontal"
    local spacing = opts.spacing or (vertical and 6 or 18)
    local g = CreateFrame("Frame", nil, parent)
    local DOT = 16
    g.buttons = {}
    U.Init(g)
    g._blocker:SetFrameLevel(g:GetFrameLevel() + 20)

    local w, h = 0, 0
    for i, o in ipairs(options) do
        local b = CreateFrame("Button", nil, g)
        b:SetHeight(18)
        local ring = U.Glyph(b, "ring", DOT, "BORDER")
        ring:SetPoint("LEFT")
        local fill = U.Glyph(b, "circle", DOT - 2, "BACKGROUND")
        fill:SetPoint("CENTER", ring, "CENTER")
        local dot = U.Glyph(b, "circle", 6, "ARTWORK")
        dot:SetPoint("CENTER", ring, "CENTER")
        local text = T.Text(b, "body", "text")
        text:SetPoint("LEFT", ring, "RIGHT", 8, 0)
        text:SetText(o.text)
        local bw = DOT + 8 + (text:GetStringWidth() or 0) + 2
        b:SetWidth(bw)
        if vertical then
            b:SetPoint("TOPLEFT", 0, -h)
            h = h + 18 + spacing
            w = math.max(w, bw)
        else
            b:SetPoint("TOPLEFT", w, 0)
            w = w + bw + spacing
            h = 18
        end
        b.value = o.value
        local ctl = { _hover = false }
        function ctl.Paint()
            local on = get() == o.value
            if on then
                ring:SetVertexColor(T.RGBA("accent"))
                fill:SetVertexColor(T.RGBA("accent"))
                dot:SetVertexColor(T.RGBA("onAccent"))
                dot:Show()
            else
                if ctl._hover then ring:SetVertexColor(T.Mix("borderStrong", "text", 0.4))
                else ring:SetVertexColor(T.RGBA("borderStrong")) end
                fill:SetVertexColor(T.RGBA(ctl._hover and "surface2" or "surfaceSunk"))
                dot:Hide()
            end
        end
        function ctl.ShowTip() if o.tooltip then T.ShowTooltip(b, o.text, o.tooltip) end end
        function ctl.HideTip() if o.tooltip then T.HideTooltip() end end
        U.Interactive(ctl, b)
        b:SetScript("OnClick", function()
            if get() == o.value then return end
            set(o.value)
            g:Refresh()
            U.Changed(g)
        end)
        b.ctl = ctl
        g.buttons[i] = b
    end
    if vertical then h = h - spacing else w = w - spacing end
    g:SetSize(math.max(w, 1), math.max(h, 1))

    function g:Paint() for _, b in ipairs(self.buttons) do b.ctl.Paint() end end
    function g:Refresh() self:Paint() end
    g:Refresh()
    return g
end
