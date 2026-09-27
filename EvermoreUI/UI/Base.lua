if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Base.lua
--  EvermoreUI's own control library. Template-free (nothing here inherits a
--  Blizzard template, so a template missing or changed on Forever can't break
--  it), drawn entirely from theme tokens, and shared by the options window,
--  the modules and any interface we build for the Forever community.
--
--  Every control follows the same contract:
--    ctrl:Refresh()           re-read its value from get()
--    ctrl:SetDisabled(bool)   greys out, eats the mouse
--    ctrl:Paint()             redraw from state + theme (called on theme change)
--    ctrl.onChanged(ctrl)     set by the owner; fired after a user change
--    ctrl:SetTooltip(title, body)
--
--  What each state looks like is not decided here: every control resolves
--  its colours through its Look (Core/Looks.lua, T.Resolve), the same recipe
--  the skins paint Blizzard's templates with. A control keeps its state in
--  _hover, _pressed, _focus, _selected, _disabled and passes itself as the
--  state. Pressed also nudges content down 1px; that is movement, not colour.
--  A control whose Look paints a full disabled state sets _look, and is not
--  faded; any other control fades to 45% when disabled.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme

local U = EV.UI or {}
EV.UI = U
EV.Widgets = U -- the options window's name for it

U.HEIGHT = 28        -- standard control height
U.COMPACT = 22       -- compact rows

local function Changed(ctrl)
    if ctrl.onChanged then ctrl.onChanged(ctrl) end
end
U.Changed = Changed

--------------------------------------------------------------------------------
--  Shared behaviour
--------------------------------------------------------------------------------
local Control = {}
U.ControlMixin = Control

function Control:SetDisabled(off)
    off = off and true or false
    self._disabled = off
    if self._blocker then self._blocker:SetShown(off) end
    -- A control with a Look paints its own disabled state.
    self:SetAlpha((off and not self._look) and 0.45 or 1)
    if off then self._hover, self._pressed = false, false end
    if self.Paint then self:Paint() end
end

function Control:IsDisabled() return self._disabled end

function Control:SetTooltip(title, body)
    self._tipTitle, self._tipBody = title, body
end

function Control:ShowTip()
    if self._tipTitle or self._tipBody then T.ShowTooltip(self, self._tipTitle, self._tipBody) end
end

function Control:HideTip()
    if self._tipTitle or self._tipBody then T.HideTooltip() end
end

--- Wire hover and press states on a frame (a Button, or any mouse frame)
--- to ctrl:Paint(). `target` is the frame receiving the mouse.
function U.Interactive(ctrl, target)
    target = target or ctrl
    target:HookScript("OnEnter", function()
        ctrl._hover = true
        ctrl:Paint()
        ctrl:ShowTip()
    end)
    target:HookScript("OnLeave", function()
        ctrl._hover, ctrl._pressed = false, false
        ctrl:Paint()
        ctrl:HideTip()
    end)
    target:HookScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" and not ctrl._disabled then ctrl._pressed = true; ctrl:Paint() end
    end)
    target:HookScript("OnMouseUp", function()
        ctrl._pressed = false
        ctrl:Paint()
    end)
end

--- Make a frame a control: mixin, disabled blocker, theme watch.
function U.Init(ctrl)
    for k, v in pairs(Control) do
        if ctrl[k] == nil then ctrl[k] = v end
    end
    local b = CreateFrame("Frame", nil, ctrl)
    b:SetAllPoints()
    b:SetFrameLevel(ctrl:GetFrameLevel() + 10)
    b:EnableMouse(true)
    b:Hide()
    ctrl._blocker = b
    T.Watch(ctrl)
    return ctrl
end

--------------------------------------------------------------------------------
--  Surfaces shared by several controls
--------------------------------------------------------------------------------
--- The standard control box: fill + 1px edge, in the rest state of a Look
--- (the plain control box by default). Returns the fill texture; the edge
--- is the frame's pixel border.
function U.Box(frame, look)
    if type(look) == "string" then look = T.LOOK[look] end
    local r = T.Resolve(look or T.LOOK.control)
    local fill = T.Solid(frame, "BACKGROUND", T.C4(r.fill))
    fill:SetAllPoints()
    T.TokenBorder(frame, "borderStrong")
    T.SetEdge(frame, r.edge)
    return fill
end

--- Paint a control box for its state, through its Look. `state` defaults to
--- the control itself. Returns the resolved colours (text, glyph and the
--- rest), valid until the next resolve.
function U.PaintBox(ctrl, fill, look, state)
    local r = T.Resolve(look or T.LOOK.button, state or ctrl)
    fill:SetColorTexture(T.C4(r.fill))
    T.SetEdge(ctrl, r.edge)
    return r
end

--- A surface of ours in a surface Look (window, raised, inset, control):
--- its fill and its border, kept in step with the theme. For module frames
--- that are panels rather than controls, so they don't compose one from raw
--- tokens. alpha overrides the fill's.
function U.Surface(frame, look, alpha)
    if type(look) == "string" then look = T.LOOK[look] end
    look = look or T.LOOK.raised
    local fill = EV.Pixel:Fill(frame, "BACKGROUND", -8)
    T.TokenBorder(frame, "border")
    local function Paint()
        local r = T.Resolve(look)
        local c1, c2, c3, c4 = T.C4(r.fill)
        fill:SetColorTexture(c1, c2, c3, alpha or c4)
        T.SetEdge(frame, r.edge)
    end
    Paint()
    T.Watch(fill, Paint)
    return fill
end

--- A texture from our own media (circle, ring, check, search, close).
function U.Glyph(parent, name, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(T.MEDIA .. name .. ".png")
    t:SetSize(size or 12, size or 12)
    return t
end

--- Plus / minus glyphs drawn from solids (crisp at any scale).
function U.PlusMinus(parent, plus, size)
    size = size or 10
    local h = T.Solid(parent, "ARTWORK", 1, 1, 1, 1)
    h:SetSize(size, 2)
    h:SetPoint("CENTER")
    local v
    if plus then
        v = T.Solid(parent, "ARTWORK", 1, 1, 1, 1)
        v:SetSize(2, size)
        v:SetPoint("CENTER")
    end
    return { h, v, SetColor = function(self, r, g, b, a)
        h:SetColorTexture(r, g, b, a or 1)
        if v then v:SetColorTexture(r, g, b, a or 1) end
    end }
end

--- Hold-to-repeat on a button: fires fn immediately, then repeats while
--- held, speeding up.
function U.Repeat(button, fn)
    local held, t, delay
    local ticker = CreateFrame("Frame", nil, button)
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t >= delay then
            t = 0
            delay = math.max(0.04, delay * 0.8)
            fn()
        end
    end)
    button:HookScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" or (button.IsDisabled and button:IsDisabled()) then return end
        held, t, delay = true, 0, 0.4
        fn()
        ticker:Show()
    end)
    local function stop() held = false; ticker:Hide() end
    button:HookScript("OnMouseUp", stop)
    button:HookScript("OnHide", stop)
end
