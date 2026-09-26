if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Inputs.lua
--  Input, SearchBox, Slider, Stepper.
--
--  W.Input(parent, width, placeholder, onCommit)       commit on Enter
--  W.SearchBox(parent, width, onSearch, placeholder)   live, debounced
--  W.Slider(parent, min, max, step, get, set, fmt, width)
--  W.Stepper(parent, min, max, step, get, set, fmt, width)
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local U = EV.UI
local floor, max, min = math.floor, math.max, math.min

--- A themed edit box: sunk well, strong edge, accent edge on focus.
local function Field(parent, width, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 190, height or U.HEIGHT)
    e:SetAutoFocus(false)
    e:SetFont(T.FontPath(), T.SIZE.body, "")
    e:SetTextInsets(10, 10, 0, 0)
    e._fill = T.Fill(e, "BACKGROUND", "surfaceSunk")
    e._fill:SetAllPoints()
    T.TokenBorder(e, "borderStrong")
    U.Init(e)
    function e:Paint()
        e._fill:SetColorTexture(T.RGBA(self._hover and not self:HasFocus() and "surface1" or "surfaceSunk"))
        if self:HasFocus() then T.SetBorderToken(self, "accent")
        elseif self._hover then T.SetBorderColor(self, T.Mix("borderStrong", "text", 0.35))
        else T.SetBorderToken(self, "borderStrong") end
        self:SetTextColor(T.RGBA("text"))
        if self._ph then self._ph:SetTextColor(T.RGBA("textDisabled")) end
    end
    e:HookScript("OnEnter", function(self) self._hover = true; self:Paint(); self:ShowTip() end)
    e:HookScript("OnLeave", function(self) self._hover = false; self:Paint(); self:HideTip() end)
    e:HookScript("OnEditFocusGained", function(self) self:Paint() end)
    e:HookScript("OnEditFocusLost", function(self) self:Paint() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return e
end
U.Field = Field

--------------------------------------------------------------------------------
--  Input with placeholder
--------------------------------------------------------------------------------
function U.Input(parent, width, placeholder, onCommit)
    local e = Field(parent, width)
    local ph = T.Font(e, T.SIZE.body, false, 1)
    ph:SetPoint("LEFT", 10, 0)
    ph:SetPoint("RIGHT", -10, 0)
    ph:SetText(placeholder or "")
    e._ph = ph

    local function UpdatePH() ph:SetShown((e:GetText() or "") == "" and not e:HasFocus()) end
    e:HookScript("OnEditFocusGained", UpdatePH)
    e:HookScript("OnEditFocusLost", UpdatePH)
    e:HookScript("OnTextChanged", UpdatePH)
    e:SetScript("OnEnterPressed", function(self)
        local txt = strtrim(self:GetText() or "")
        self:ClearFocus()
        if onCommit then onCommit(txt, self) end
    end)
    function e:Refresh() UpdatePH() end
    e:Paint()
    UpdatePH()
    return e
end

--------------------------------------------------------------------------------
--  SearchBox: magnifier, clear button, fires onSearch(text) as you type
--  (debounced 0.15s) and on Enter.
--------------------------------------------------------------------------------
function U.SearchBox(parent, width, onSearch, placeholder)
    local e = U.Input(parent, width, placeholder or SEARCH, function(txt) if onSearch then onSearch(txt) end end)
    e:SetTextInsets(28, 26, 0, 0)
    e._ph:ClearAllPoints()
    e._ph:SetPoint("LEFT", 28, 0)
    local glass = U.Glyph(e, "search", 13, "ARTWORK")
    glass:SetPoint("LEFT", 9, 0)
    local clear = U.IconButton(e, { glyph = "close", size = 18, iconSize = 8, style = "ghost" }, function()
        e:SetText("")
        e:ClearFocus()
        if onSearch then onSearch("") end
    end)
    clear:SetPoint("RIGHT", -4, 0)
    clear:Hide()
    local pending
    e:HookScript("OnTextChanged", function(self, user)
        clear:SetShown((self:GetText() or "") ~= "")
        if not user then return end
        pending = (pending or 0) + 1
        local mine = pending
        C_Timer.After(0.15, function()
            if mine == pending and onSearch then onSearch(strtrim(e:GetText() or "")) end
        end)
    end)
    local basePaint = e.Paint
    function e:Paint()
        basePaint(self)
        glass:SetVertexColor(T.RGBA(self:HasFocus() and "accent" or "textMuted"))
    end
    e:Paint()
    return e
end

--------------------------------------------------------------------------------
--  Slider: track, accent fill, square thumb with a halo, editable value.
--  Drag, click to jump, mouse wheel steps.
--------------------------------------------------------------------------------
function U.Slider(parent, minV, maxV, step, get, set, fmt, width)
    step = step or 1
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 230, 22)

    local input = Field(f, 52, 24)
    input:SetPoint("RIGHT")
    input:SetJustifyH("CENTER")
    input:SetTextInsets(4, 4, 0, 0)
    input:SetMaxLetters(8)

    local track = CreateFrame("Frame", nil, f)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT", input, "LEFT", -14, 0)
    track:SetHeight(20)
    track:EnableMouse(true)
    track:EnableMouseWheel(true)

    local bar = T.Fill(track, "BACKGROUND", "surface3")
    bar:SetHeight(4)
    bar:SetPoint("LEFT"); bar:SetPoint("RIGHT")
    local fill = T.Fill(track, "BORDER", "accent")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", bar, "LEFT")
    local halo = T.Fill(track, "ARTWORK", "surface0", 1, 0)
    local thumb = T.Fill(track, "ARTWORK", "accent", 1, 1)
    halo:SetPoint("CENTER", thumb, "CENTER")
    U.Init(f)

    local current
    local function Snap(v)
        v = minV + floor((v - minV) / step + 0.5) * step
        return max(minV, min(maxV, v))
    end
    local function Format(v)
        if fmt then return fmt(v) end
        if step >= 1 then return tostring(floor(v + 0.5)) end
        if step < 0.1 then return ("%.2f"):format(v) end
        return ("%.1f"):format(v)
    end
    local function Place(v)
        local w = bar:GetWidth()
        if not w or w <= 0 then return end
        local frac = (maxV > minV) and (v - minV) / (maxV - minV) or 0
        fill:SetWidth(max(w * frac, 0.01))
        thumb:ClearAllPoints()
        thumb:SetPoint("CENTER", bar, "LEFT", w * frac, 0)
        if not input:HasFocus() then input:SetText(Format(v)) end
    end
    local function Commit(v)
        v = Snap(v)
        if v == current then return end
        current = v
        set(v)
        Place(v)
        U.Changed(f)
    end
    local function ValueAtCursor()
        local x = GetCursorPosition() / track:GetEffectiveScale()
        local left, w = bar:GetLeft(), bar:GetWidth()
        if not left or w <= 0 then return current end
        return minV + (x - left) / w * (maxV - minV)
    end

    function f:Paint()
        local big = self._hover or self._dragging
        thumb:SetSize(big and 14 or 12, big and 14 or 12)
        halo:SetSize(big and 18 or 16, big and 18 or 16)
        thumb:SetColorTexture(T.RGBA("accent"))
        fill:SetColorTexture(T.RGBA("accent"))
        bar:SetColorTexture(T.RGBA(self._hover and "borderStrong" or "surface3"))
        halo:SetColorTexture(T.RGBA("surface0"))
    end

    track:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        f._dragging = true
        Commit(ValueAtCursor())
        f:Paint()
        self:SetScript("OnUpdate", function() Commit(ValueAtCursor()) end)
    end)
    local function StopDrag(self) self:SetScript("OnUpdate", nil); f._dragging = false; f:Paint() end
    track:SetScript("OnMouseUp", StopDrag)
    track:SetScript("OnHide", StopDrag)
    track:SetScript("OnMouseWheel", function(_, delta) Commit((current or minV) + delta * step) end)
    track:SetScript("OnSizeChanged", function() if current then Place(current) end end)
    track:SetScript("OnEnter", function() f._hover = true; f:Paint(); f:ShowTip() end)
    track:SetScript("OnLeave", function() f._hover = false; f:Paint(); f:HideTip() end)

    input:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText())
        self:ClearFocus()
        if n then Commit(n) end
        Place(current)
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Place(current) end)
    input:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    input:HookScript("OnEditFocusLost", function() Place(current) end)

    function f:Refresh()
        current = Snap(get() or minV)
        Place(current)
    end
    f:Paint()
    f:Refresh()
    return f
end

--------------------------------------------------------------------------------
--  Stepper: [-] value [+]. Hold a button to repeat; wheel over it steps;
--  the value is editable.
--------------------------------------------------------------------------------
function U.Stepper(parent, minV, maxV, step, get, set, fmt, width)
    step = step or 1
    local H = U.HEIGHT
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 120, H)
    f:EnableMouseWheel(true)

    local minus = U.IconButton(f, { size = H, style = "secondary" })
    minus:SetPoint("LEFT")
    local plus = U.IconButton(f, { size = H, style = "secondary" })
    plus:SetPoint("RIGHT")
    local mg = U.PlusMinus(minus, false, 10)
    local pg = U.PlusMinus(plus, true, 10)

    local input = Field(f, 10, H)
    input:SetPoint("LEFT", minus, "RIGHT", -1, 0)
    input:SetPoint("RIGHT", plus, "LEFT", 1, 0)
    input:SetJustifyH("CENTER")
    input:SetTextInsets(2, 2, 0, 0)
    U.Init(f)

    local current
    local function Snap(v)
        v = minV + floor((v - minV) / step + 0.5) * step
        return max(minV, min(maxV, v))
    end
    local function Format(v)
        if fmt then return fmt(v) end
        if step >= 1 then return tostring(floor(v + 0.5)) end
        return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", ""))
    end
    function f:Paint()
        local r, g, b = T.RGBA("text")
        local dr, dg, db = T.RGBA("textDisabled")
        local atMin, atMax = current and current <= minV, current and current >= maxV
        mg:SetColor(atMin and dr or r, atMin and dg or g, atMin and db or b)
        pg:SetColor(atMax and dr or r, atMax and dg or g, atMax and db or b)
    end
    local function Show()
        if not input:HasFocus() then input:SetText(Format(current)) end
        f:Paint()
    end
    local function Commit(v)
        v = Snap(v)
        if v == current then return end
        current = v
        set(v)
        Show()
        U.Changed(f)
    end
    U.Repeat(minus, function() Commit((current or minV) - step) end)
    U.Repeat(plus, function() Commit((current or minV) + step) end)
    f:SetScript("OnMouseWheel", function(_, delta) Commit((current or minV) + delta * step) end)
    input:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText())
        self:ClearFocus()
        if n then Commit(n) end
        Show()
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Show() end)
    input:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    input:HookScript("OnEditFocusLost", Show)

    function f:Refresh()
        current = Snap(get() or minV)
        Show()
    end
    f:Refresh()
    return f
end
