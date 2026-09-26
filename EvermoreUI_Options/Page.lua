if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Page.lua
--  Declarative page builder. A page's build function gets a builder `p`:
--
--    p:Section("DISPLAY")
--    p:Row{ type = "toggle", text = "Show bar", get = ..., set = ... }
--    p:Dual({ type = "slider", ... }, { type = "dropdown", ... })
--    p:Note("Plain explanatory text.")
--
--  Row config (all types): text, tooltip, get, set, disabled = function() end
--    toggle
--    slider   min, max, step, fmt
--    dropdown values = { {value=, text=}, ... } or function, width
--    button   label, onClick, style, confirm = true (two-click)
--    input    placeholder, onCommit(text)
--    colour   get() -> r, g, b; set(r, g, b); reset(); isCustom()
--    custom   build = function(host) return control end
--
--  Rows alternate their shading, restart it at each section, and grey out
--  (with their control locked) whenever disabled() returns true.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local W = EV.UI

local Builder = {}
Builder.__index = Builder

function EV.Options_NewBuilder(parent, width, onChanged)
    return setmetatable({
        parent = parent, width = width, y = -6, stripe = 0,
        rows = {}, onChanged = onChanged,
    }, Builder)
end

--------------------------------------------------------------------------------
--  Controls from config
--------------------------------------------------------------------------------
local function MakeControl(host, cfg, onChanged)
    local c
    local t = cfg.type
    if t == "toggle" then
        c = W.Toggle(host, cfg.get, cfg.set)
    elseif t == "slider" then
        c = W.Slider(host, cfg.min, cfg.max, cfg.step, cfg.get, cfg.set, cfg.fmt, cfg.width)
    elseif t == "dropdown" then
        c = W.Dropdown(host, cfg.width, cfg.values, cfg.get, cfg.set)
    elseif t == "button" then
        if cfg.confirm then
            c = W.ConfirmButton(host, cfg.label or cfg.text, cfg.width or 150, cfg.onClick)
        else
            c = W.Button(host, cfg.label or cfg.text, cfg.width or 150, cfg.onClick, cfg.style)
        end
    elseif t == "input" then
        c = W.Input(host, cfg.width, cfg.placeholder, cfg.onCommit or (cfg.set and function(txt) cfg.set(txt) end))
        if cfg.get then
            local base = c.Refresh
            function c:Refresh()
                if not self:HasFocus() then self:SetText(cfg.get() or "") end
                base(self)
            end
            c:Refresh()
        end
    elseif t == "colour" then
        -- A swatch, and a small Reset beside it that only shows once the
        -- colour is your own (isCustom).
        c = CreateFrame("Frame", nil, host)
        c:SetSize(W.HEIGHT + 8 + 70, W.HEIGHT)
        local sw = W.ColorSwatch(c, cfg.get, cfg.set)
        sw:SetPoint("RIGHT")
        local rs = W.Button(c, EV.L["Reset"], 62, function()
            if cfg.reset then cfg.reset() end
            c:Refresh()
        end)
        rs:SetPoint("RIGHT", sw, "LEFT", -8, 0)
        function c:Refresh()
            sw:Refresh()
            rs:SetShown(cfg.isCustom and cfg.isCustom() or false)
        end
        sw.onChanged = function() c:Refresh() end
        function c:SetDisabled(off)
            if sw.SetDisabled then sw:SetDisabled(off) end
            if rs.SetDisabled then rs:SetDisabled(off) end
            self:SetAlpha(off and 0.5 or 1)
        end
        c:Refresh()
    elseif t == "custom" then
        c = cfg.build(host)
    end
    if c then c.onChanged = onChanged end
    return c
end

-- One labelled cell: label on the left, control on the right.
local function BuildCell(builder, host, cfg)
    local label
    if cfg.text and cfg.type ~= "button" or (cfg.type == "button" and cfg.label) then
        label = T.Text(host, 14, "text")
        label:SetPoint("LEFT", host, "LEFT", 20, 0)
        label:SetText(cfg.text)
    end
    local ctrl = MakeControl(host, cfg, function() builder:Refresh() end)
    if ctrl then
        ctrl:SetParent(host)
        ctrl:ClearAllPoints()
        if cfg.type == "button" and not cfg.label then
            ctrl:SetPoint("LEFT", host, "LEFT", 20, 0)
        else
            ctrl:SetPoint("RIGHT", host, "RIGHT", -20, 0)
        end
        ctrl:SetFrameLevel(host:GetFrameLevel() + 2)
        if label then label:SetPoint("RIGHT", ctrl, "LEFT", -14, 0) end
    end

    -- Hover: faint highlight and the tooltip, if there is one.
    local hl = T.Fill(host, "BORDER", "surface2", 0.35)
    hl:SetAllPoints()
    hl:Hide()
    host:EnableMouse(true)
    host:SetScript("OnEnter", function(self)
        hl:Show()
        if cfg.tooltip then T.ShowTooltip(self, cfg.text, cfg.tooltip) end
    end)
    host:SetScript("OnLeave", function() hl:Hide(); T.HideTooltip() end)

    return { host = host, ctrl = ctrl, label = label, cfg = cfg }
end

local function NewRowFrame(builder, height)
    local row = CreateFrame("Frame", nil, builder.parent)
    row:SetSize(builder.width, height)
    row:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", T.PAD, builder.y)
    builder.y = builder.y - height
    builder.stripe = builder.stripe + 1
    -- Alternate rows: a light and a deeper sunk stripe.
    T.Fill(row, "BACKGROUND", "surfaceSunk", (builder.stripe % 2 == 1) and 0.25 or 0.5):SetAllPoints()
    return row
end

--------------------------------------------------------------------------------
--  Builder API
--------------------------------------------------------------------------------
function Builder:Section(text)
    local f = CreateFrame("Frame", nil, self.parent)
    f:SetSize(self.width, T.SECTION_H)
    f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", T.PAD, self.y - (self.y < -10 and 14 or 0))
    self.y = self.y - T.SECTION_H - (self.y < -10 and 14 or 0)
    local label = T.Text(f, 12, "textDisabled", true)
    label:SetPoint("BOTTOMLEFT", 2, 9)
    label:SetText(text:upper())
    local sep = T.Fill(f, "ARTWORK", "divider")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT")
    sep:SetPoint("BOTTOMRIGHT")
    self.stripe = 0
    return f
end

function Builder:Row(cfg)
    local row = NewRowFrame(self, cfg.height or T.ROW_H)
    local cell = BuildCell(self, row, cfg)
    self.rows[#self.rows + 1] = cell
    return cell
end

function Builder:Dual(left, right)
    local row = NewRowFrame(self, T.ROW_H)
    local half = self.width / 2
    local cells = {}
    for i, cfg in ipairs({ left, right }) do
        if cfg then
            local host = CreateFrame("Frame", nil, row)
            host:SetSize(half, T.ROW_H)
            host:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * half, 0)
            host:SetFrameLevel(row:GetFrameLevel() + 1)
            local cell = BuildCell(self, host, cfg)
            self.rows[#self.rows + 1] = cell
            cells[i] = cell
        end
    end
    local div = T.Fill(row, "ARTWORK", "divider")
    div:SetWidth(1)
    div:SetPoint("TOP", row, "TOP", 0, -10)
    div:SetPoint("BOTTOM", row, "BOTTOM", 0, 10)
    return cells[1], cells[2]
end

function Builder:Note(text, alpha)
    local f = CreateFrame("Frame", nil, self.parent)
    f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", T.PAD + 2, self.y - 10)
    f:SetWidth(self.width - 4)
    local fs = T.Text(f, 13, "textMuted")
    fs:SetWordWrap(true)
    fs:SetPoint("TOPLEFT")
    fs:SetWidth(self.width - 4)
    fs:SetText(text)
    local h = math.max(fs:GetStringHeight() or 16, 16)
    f:SetHeight(h)
    self.y = self.y - h - 20
    f.text = fs
    return f
end

function Builder:Spacer(h) self.y = self.y - (h or 16) end

--- A banner across the top of the page (e.g. "this module is off").
function Builder:Banner(text, actionLabel, onAction)
    local f = CreateFrame("Frame", nil, self.parent)
    f:SetPoint("TOPLEFT", self.parent, "TOPLEFT", T.PAD, self.y - 6)
    T.Fill(f, "BACKGROUND", "accent", 0.10):SetAllPoints()
    local bar = T.Fill(f, "BORDER", "accent", 0.9)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(3)
    -- Wraps beside the button (if any) and the banner grows to fit.
    local fs = T.Text(f, 14, "text")
    fs:SetWordWrap(true)
    fs:SetWidth(self.width - 18 - (actionLabel and 174 or 16))
    fs:SetPoint("LEFT", 18, 0)
    fs:SetText(text)
    local h = math.max(48, math.ceil((fs:GetStringHeight() or 16) + 24))
    f:SetSize(self.width, h)
    self.y = self.y - h - 14
    if actionLabel then
        local b = W.Button(f, actionLabel, 150, onAction, "accent")
        b:SetPoint("RIGHT", -10, 0)
    end
    return f
end

--- Re-read every control and re-evaluate disabled states.
function Builder:Refresh()
    for _, cell in ipairs(self.rows) do
        local off = cell.cfg.disabled and cell.cfg.disabled() or false
        if cell.ctrl then
            if cell.ctrl.Refresh then cell.ctrl:Refresh() end
            if cell.ctrl.SetDisabled then cell.ctrl:SetDisabled(off) end
        end
        if cell.label then cell.label:SetAlpha(off and 0.4 or 1) end
    end
    if self.onChanged then self.onChanged() end
end

function Builder:Height() return -self.y + 30 end
