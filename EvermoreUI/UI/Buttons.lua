if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Buttons.lua
--  Button, IconButton, ConfirmButton.
--
--  W.Button(parent, text, width, onClick, style)
--    style: "secondary" (default, outlined), "primary" (accent fill),
--           "ghost" (text only, fills on hover), "danger" (red outline)
--    Legacy names from the options code: nil = secondary, "accent" = primary.
--  b:SetText(s), b:SetStyle(s), b:SetIcon(texture or atlas, size)
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local U = EV.UI

local STYLE_ALIAS = { accent = "primary" }
local STYLES = { secondary = "button", primary = "buttonPrimary", ghost = "buttonGhost", danger = "buttonDanger" }

local function LookFor(style) return T.LOOK[STYLES[style] or "button"] end

local function PaintButton(b)
    local look = LookFor(b._style)
    b._look = look
    local r = U.PaintBox(b, b._fill, look)
    b.label:SetTextColor(T.C4(r.text))
    T.TextShadow(b.label, look.shadow ~= false)
    -- Press nudges the content down a pixel.
    local dy = b._pressed and -1 or 0
    b._content:ClearAllPoints()
    b._content:SetPoint("CENTER", b, "CENTER", 0, dy)
    if b.icon then b.icon:SetVertexColor(b.label:GetTextColor()) end
end

local function Layout(b)
    local w = b.label:GetStringWidth() or 0
    local iw = b.icon and b.icon:IsShown() and (b._iconSize + 6) or 0
    b._content:SetSize(math.max(w + iw, 1), 16)
    b.label:ClearAllPoints()
    b.label:SetPoint("RIGHT", b._content, "RIGHT", 0, 0)
    if b.icon then
        b.icon:ClearAllPoints()
        b.icon:SetPoint("LEFT", b._content, "LEFT", 0, 0)
    end
end

function U.Button(parent, text, width, onClick, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 150, T.LOOK.button.height)
    b._fill = T.Fill(b, "BACKGROUND", "surface2")
    b._fill:SetAllPoints()
    T.TokenBorder(b, "borderStrong")
    b._content = CreateFrame("Frame", nil, b)
    b._content:SetSize(1, 16)
    local label = T.Font(b._content, T.SIZE.body, true, 1, "CENTER")
    label:SetText(text or "")
    b.label = label
    U.Init(b)

    b.Paint = PaintButton
    function b:SetStyle(s)
        self._style = STYLE_ALIAS[s] or s or "secondary"
        self._look = LookFor(self._style)
        if self._disabled ~= nil then self:SetDisabled(self._disabled) end
        self:Paint()
    end
    function b:SetText(s) label:SetText(s or ""); Layout(self) end
    function b:GetText() return label:GetText() end
    function b:SetIcon(tex, size)
        if not tex then if self.icon then self.icon:Hide() end; Layout(self); return end
        self.icon = self.icon or self._content:CreateTexture(nil, "ARTWORK")
        self._iconSize = size or 14
        self.icon:SetSize(self._iconSize, self._iconSize)
        if type(tex) == "string" and not tex:find("[\\/]") and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tex) then
            self.icon:SetAtlas(tex)
        else
            self.icon:SetTexture(tex)
        end
        self.icon:Show()
        Layout(self)
        self:Paint()
    end

    U.Interactive(b)
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    Layout(b)
    b:SetStyle(style)
    return b
end

--- Two-click confirm: the first click arms (turns danger, "Click again"),
--- the second runs. Disarms after 3 seconds.
function U.ConfirmButton(parent, text, width, onConfirm, confirmText)
    local armed = false
    local b
    b = U.Button(parent, text, width, function(self)
        if not armed then
            armed = true
            self:SetStyle("danger")
            self:SetText(confirmText or EV.L["Click again to confirm"])
            C_Timer.After(3, function()
                if armed then armed = false; b:SetStyle(nil); b:SetText(text) end
            end)
            return
        end
        armed = false
        self:SetStyle(nil)
        self:SetText(text)
        onConfirm(self)
    end)
    return b
end

--------------------------------------------------------------------------------
--  IconButton: a square button showing an icon or one of our glyphs.
--  opts: { size = 24, glyph = "close" | texture = path/fileID | atlas = name,
--          style = "ghost" | "secondary", look = a Look (overrides style),
--          tooltip = "...", toggle = bool }
--  With toggle, b:SetSelected(bool) marks it active (accent icon + bar).
--------------------------------------------------------------------------------
function U.IconButton(parent, opts, onClick)
    opts = opts or {}
    local size = opts.size or 24
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b._fill = T.Fill(b, "BACKGROUND", "surface2")
    b._fill:SetAllPoints()
    T.TokenBorder(b, "borderStrong")
    local icon = b:CreateTexture(nil, "ARTWORK")
    local inner = opts.iconSize or math.floor(size * 0.58 + 0.5)
    icon:SetSize(inner, inner)
    icon:SetPoint("CENTER")
    if opts.glyph then
        icon:SetTexture(T.MEDIA .. opts.glyph .. ".png")
    elseif opts.atlas then
        icon:SetAtlas(opts.atlas)
    elseif opts.texture then
        icon:SetTexture(opts.texture)
        if type(opts.texture) == "number" or tostring(opts.texture):lower():find("icons") then
            icon:SetTexCoord(EV.Icons:Coords()) -- trim the icon border
        end
    end
    b.icon = icon
    b._tint = opts.glyph ~= nil or opts.tint
    b._look = opts.look or LookFor(opts.style or "ghost")
    local bar = T.Fill(b, "OVERLAY", "accent")
    bar:SetPoint("BOTTOMLEFT"); bar:SetPoint("BOTTOMRIGHT"); bar:SetHeight(2)
    bar:Hide()
    b._bar = bar
    U.Init(b)

    function b:Paint()
        local r = U.PaintBox(self, self._fill, self._look)
        if self._tint then
            if r.glyph then icon:SetVertexColor(T.C4(r.glyph)) end
        elseif self._disabled then
            -- A picture can't take the Look's disabled glyph colour, so it
            -- greys and dims the way a faded control would.
            icon:SetDesaturated(true)
            icon:SetVertexColor(1, 1, 1, 0.45)
        else
            icon:SetDesaturated(opts.toggle and not self._selected and not self._hover or false)
            icon:SetVertexColor(1, 1, 1, (self._selected or self._hover or not opts.toggle) and 1 or 0.7)
        end
        local showBar = self._selected and T.Visible(r.bar)
        bar:SetShown(showBar and true or false)
        if showBar then bar:SetColorTexture(T.C4(r.bar)) end
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", 0, self._pressed and -1 or 0)
    end
    function b:SetSelected(on) self._selected = on and true or false; self:Paint() end
    function b:IsSelected() return self._selected end
    function b:SetGlyph(name) icon:SetTexture(T.MEDIA .. name .. ".png"); self._tint = true; self:Paint() end

    if opts.tooltip then b:SetTooltip(opts.tooltip, opts.tooltipBody) end
    U.Interactive(b)
    b:SetScript("OnClick", function(self, ...) if onClick then onClick(self, ...) end end)
    b:Paint()
    return b
end

--- Close button in the house style (used by our windows).
function U.CloseButton(parent, size, onClick)
    local b = U.IconButton(parent, { glyph = "close", size = size or 22, iconSize = math.floor((size or 22) * 0.5),
                                     tooltip = CLOSE, look = T.LOOK.close })
    b:SetScript("OnClick", function(self) if onClick then onClick(self) else parent:Hide() end end)
    return b
end
