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
local offState, onState = {}, { on = true }
local offOut, onOut = {}, {}

function U.Toggle(parent, get, set)
    local look = T.LOOK.toggle
    local TW, TH, PAD = look.width, look.height, look.pad
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TW, TH)
    local track = T.Fill(b, "BACKGROUND", "surface2")
    track:SetAllPoints()
    T.TokenBorder(b, "borderStrong")
    local knob = T.Solid(b, "ARTWORK", 1, 1, 1, 1)
    knob:SetSize(TH - PAD * 2, TH - PAD * 2)
    U.Init(b)

    local pos, state = 0, nil
    -- The slide tweens between the two resolved ends of the Look.
    function b:Paint()
        local p = pos
        offState.hover, offState.disabled = self._hover, self._disabled
        onState.hover, onState.disabled = self._hover, self._disabled
        local off = T.Resolve(look, offState, offOut)
        local on = T.Resolve(look, onState, onOut)
        local a, z = off.fill, on.fill
        track:SetColorTexture(T.Lerp(a[1], z[1], p), T.Lerp(a[2], z[2], p), T.Lerp(a[3], z[3], p), 1)
        local lit = p > 0.5
        T.SetEdge(self, lit and on.edge or off.edge)
        knob:SetColorTexture(T.C4(lit and on.knob or off.knob))
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
    local look = T.LOOK.checkbox
    local BOX = look.box
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(math.max(BOX, 18))
    local box = CreateFrame("Frame", nil, b)
    box:SetSize(BOX, BOX)
    box:SetPoint("LEFT")
    local fill = T.Fill(box, "BACKGROUND", "surfaceSunk")
    fill:SetAllPoints()
    T.TokenBorder(box, "borderStrong")
    local tick = U.Glyph(box, "check", look.tick)
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

    function b:Paint()
        local r = T.Resolve(look, self)
        fill:SetColorTexture(T.C4(r.fill))
        T.SetEdge(box, r.edge)
        tick:SetShown(self._checked and true or false)
        if r.glyph then tick:SetVertexColor(T.C4(r.glyph)) end
        if text and r.label then text:SetTextColor(T.C4(r.label)) end
        box:ClearAllPoints()
        box:SetPoint("LEFT", 0, self._pressed and -1 or 0)
    end
    function b:Refresh()
        self._checked = get() and true or false
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
    local look = T.LOOK.radio
    local DOT = look.ring
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
        local dot = U.Glyph(b, "circle", look.dot, "ARTWORK")
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
            ctl._selected = get() == o.value
            local r = T.Resolve(look, ctl)
            ring:SetVertexColor(T.C4(r.ring))
            fill:SetVertexColor(T.C4(r.fill))
            dot:SetShown(ctl._selected)
            if r.dot then dot:SetVertexColor(T.C4(r.dot)) end
            if r.label then text:SetTextColor(T.C4(r.label)) end
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
