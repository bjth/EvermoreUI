if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Combo.lua
--  Your combo points on your target's plate.
--
--  In classic the points live on the mob: switch target and they go. So
--  the natural place to read them is on the mob you're hitting, which is
--  where a melee player is already looking. The player frame carries them
--  too (EvermoreUI_UnitFrames/ClassPower.lua); this is the same reading in
--  the other place.
--
--  A row of pips straddling the bottom (or top) edge of the health bar, so
--  it adds nothing to the plate's box: the engine is told how tall a plate
--  is (Core.lua, Extent), and a row that hung below the cast bar would move
--  every plate for the sake of one.
--
--  Which plate. "target" is not a nameplate token, so each plate asks
--  UnitIsUnit(its unit, "target"). In restricted content the answer is a
--  secret boolean: then every plate keeps its row shown and folds the
--  answer into the row's alpha, C-side, the way the target halo does
--  (Extras.lua, ApplyTarget). The count is secret-safe by construction (see
--  Core/Combo.lua).
--
--  Its own event frame, not the module's: a module keeps one handler per
--  event, and PLAYER_TARGET_CHANGED already belongs to the target widget.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local max = math.max
local WHITE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_COLOUR = { 1, 0.86, 0.1 }

local function On(cfg)
    return cfg.comboPoints and EV.HasComboClass()
end

local function Colour(cfg)
    local c = cfg.comboColour
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return DEFAULT_COLOUR
end

--- How many pips: the game's maximum when it says, otherwise five.
local pipCount = 5

local function Pip(row, i)
    local p = row.pips[i]
    if p then return p end
    p = CreateFrame("StatusBar", nil, row)
    p:SetStatusBarTexture(WHITE)
    p:SetMinMaxValues(i - 1, i)
    p:SetValue(0)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    EV.Pixel.NoSnap(p.bg)
    row.pips[i] = p
    return p
end

--- Show the row on the target's plate only, and light the pips you have.
local function Apply(f)
    local row = f.combo
    if not (row and f.unit) then return end
    local cfg = ns.module.db
    if not On(cfg) or not EV.WantsComboPoints() then row:Hide() return end

    local ok, isTarget = pcall(UnitIsUnit, f.unit, "target")
    if not ok then row:Hide() return end
    if ns.IsSecret(isTarget) then
        row:Show()
        if not pcall(row.SetAlphaFromBoolean, row, isTarget, 1, 0) then row:Hide() return end
    elseif isTarget then
        row:SetAlpha(1)
        row:Show()
    else
        row:Hide()
        return
    end

    local v = EV.ComboPoints()
    if type(v) == "nil" then row:Hide() return end
    for i = 1, pipCount do
        local p = row.pips[i]
        if p then pcall(p.SetValue, p, v) end
    end
end

local function ApplyAll()
    for _, f in pairs(ns.plates) do ns.Safe("combo", Apply, f) end
end

ns.Widget{
    name = "combo",

    Build = function(f)
        local row = CreateFrame("Frame", nil, f)
        row.pips = {}
        row:Hide()
        f.combo = row
    end,

    Layout = function(f, cfg)
        local row = f.combo
        if not row then return end
        if not On(cfg) then row:Hide() return end
        local one = EV.Pixel:One(f)
        local n = pipCount
        local w = max(cfg.comboWidth or 12, 4)
        local h = max(cfg.comboHeight or 6, 2)
        local gap = one * (cfg.comboSpacing or 2)
        EV.Pixel:SetSize(row, n * w + (n - 1) * gap, h)
        row:ClearAllPoints()
        local edge = (cfg.comboSpot == "top") and "TOP" or "BOTTOM"
        row:SetPoint("CENTER", f.health, edge, 0, one * (cfg.comboY or 0))
        -- Above the bar's text and the cast bar, so it's never covered.
        local base = (f.overlay and f.overlay:GetFrameLevel()) or f:GetFrameLevel()
        row:SetFrameLevel(base + 3)

        local c = Colour(cfg)
        local tex = EV.Media:Fetch("statusbar", cfg.texture)
        for i = 1, max(n, #row.pips) do
            local p = Pip(row, i)
            if i <= n then
                p:ClearAllPoints()
                p:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + gap), 0)
                EV.Pixel:SetSize(p, w, h)
                p:SetStatusBarTexture(tex)
                p:SetStatusBarColor(c[1], c[2], c[3], 1)
                p.bg:SetColorTexture(0.031, 0.031, 0.031, 0.9)
                -- Decoupled: the plate rescales, and a border on the bar
                -- itself would sit under its own fill (Pixel.lua).
                EV.Pixel:CreateBorder(p, 1, 0, 0, 0, 1, true)
                p:Show()
            else
                p:Hide()
            end
        end
        Apply(f)
    end,

    SetUnit = function(f) Apply(f) end,

    Clear = function(f)
        if f.combo then
            f.combo:SetAlpha(1)   -- drop any secret alpha a fold left behind
            f.combo:Hide()
        end
    end,

    Enable = function()
        if not EV.HasComboClass() then return end
        local ev = CreateFrame("Frame")
        for _, e in ipairs(EV.COMBO_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        ev:SetScript("OnEvent", function(_, event, unit, token)
            if not ns.module:IsEnabled() or not ns.module.db.comboPoints then return end
            if not EV.IsComboEvent(event, unit, token) then return end
            if event == "UNIT_MAXPOWER" or event == "PLAYER_ENTERING_WORLD" then
                local _, m = EV.ComboPoints()
                if m and m ~= pipCount and m <= 10 then
                    pipCount = m
                    ns.module:Restyle()
                    return
                end
            end
            ApplyAll()
        end)
    end,
}
