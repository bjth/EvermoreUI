if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Health.lua
--  The health bar, its text, and the one piece of machinery this addon is
--  built around: the dirty-set coalescer.
--
--  Health, max and absorb edges for one mob arrive from the server in a
--  batch, and only the last paint of a frame is ever seen. So the events
--  MARK rather than paint, and a single shared OnUpdate drains the set once
--  per frame. That OnUpdate hides itself whenever the set is empty, so the
--  idle cost is zero, and it paints inside the same frame the events
--  arrived in, so nothing is displayed later than it would have been.
--
--  This is the shape Blizzard's own CompactUnitFrame uses (healthDirty,
--  drained at most once per frame) and the reason is in their comment:
--  avoid having an OnUpdate registered unless absolutely necessary.
--
--  Secret values: health is secret in restricted content. We never compare
--  or add it, only hand it to SetValue, and the text memo below refuses to
--  cache a secret because a secret in a cache freezes the display on a
--  stale value for good.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local T = EV.Theme
local L = EV.L
local floor = math.floor

--------------------------------------------------------------------------------
--  The coalescer
--------------------------------------------------------------------------------
local dirty = {}
local flush = CreateFrame("Frame")
flush:Hide()
flush:SetScript("OnUpdate", function(self)
    for f in pairs(dirty) do
        dirty[f] = nil
        -- A plate recycled between the mark and this drain is not ours any
        -- more. Skip it rather than painting somebody else's unit.
        if f.unit and ns.plates[f.unit] == f then ns.Safe("paint", ns.PaintHealth, f) end
    end
    if next(dirty) == nil then self:Hide() end
end)

local function Mark(f)
    dirty[f] = true
    flush:Show()
end
ns.MarkHealth = Mark

--------------------------------------------------------------------------------
--  Painting
--------------------------------------------------------------------------------
local function ShortNumber(n)
    if type(n) ~= "number" then return "" end
    if n >= 1e9 then return ("%.1fb"):format(n / 1e9) end
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.0fk"):format(n / 1e3) end
    return tostring(floor(n + 0.5))
end

--- Text, memoised on the DISPLAYED value rather than the raw one.
--- The raw percent is a float that moves every tick, so a raw key never
--- repeats and the memo never hits. Quantise to what the user can actually
--- see and most health events stop touching a string at all.
local function Text(f, cur, maxHP, cfg)
    local fs = f.healthText
    if not fs then return end
    local mode = cfg.healthText
    if mode == "none" then fs:SetText(""); f._hText = nil; return end

    local secret = ns.IsSecret(cur) or ns.IsSecret(maxHP)
    if secret then
        -- Cannot divide, cannot compare, cannot memo. Let the client render
        -- it and clear the key so the next plain value repaints.
        f._hText = nil
        if mode == "percent" and type(UnitHealthPercent) == "function" then
            local curve = CurveConstants and CurveConstants.ScaleTo100
            local ok, pct = pcall(UnitHealthPercent, f.unit, true, curve)
            if ok and type(pct) ~= "nil" then
                pcall(fs.SetFormattedText, fs, "%.0f%%", pct)
                return
            end
        end
        if type(AbbreviateNumbers) == "function" then
            local ok, s = pcall(AbbreviateNumbers, cur)
            if ok then pcall(fs.SetFormattedText, fs, "%s", s); return end
        end
        fs:SetText("")
        return
    end

    cur, maxHP = cur or 0, maxHP or 0
    local pct = maxHP > 0 and (cur / maxHP * 100) or 0

    -- Memo on the RENDERED STRING, not a hand-rolled numeric key. A key has
    -- to be quantised to exactly the granularity the text is, and getting
    -- that wrong fails both ways at once: too coarse and the number goes
    -- stale on screen (5049 -> 5001 both floor to the same bucket), too fine
    -- and a boss whose text only moves every 50k busts the memo on every
    -- tick. Building the string and comparing it is one concat against being
    -- certain, and it is still cheaper than the SetText it saves.
    local out
    if mode == "percent" then
        out = ("%d%%"):format(floor(pct + 0.5))
    elseif mode == "current" then
        out = ShortNumber(cur)
    else
        out = ("%s  %d%%"):format(ShortNumber(cur), floor(pct + 0.5))
    end
    if f._hText == out then return end
    f._hText = out
    fs:SetText(out)
end

function ns.PaintHealth(f)
    local unit, bar = f.unit, f.health
    if not (unit and bar) then return end
    local cfg = ns.module.db

    local cur = UnitHealth(unit)
    -- Bounds are event driven, not per paint: the max only moves on
    -- UNIT_MAXHEALTH, so the steady state is one read and one SetValue.
    if not f._maxValid then
        local maxHP = UnitHealthMax(unit)
        bar:SetMinMaxValues(0, maxHP)
        f._maxHP = maxHP
        f._maxValid = true
    end
    bar:SetValue(cur)
    Text(f, cur, f._maxHP, cfg)

    -- Anything else that keys off health rides the SAME coalesced paint
    -- rather than registering UNIT_HEALTH a second time. One event, one
    -- drain, one pass over the widgets that asked.
    ns.ForEachWidget("Health", f)
end

function ns.PaintColour(f)
    if not (f.unit and f.health) then return end
    local r, g, b = ns.HealthColour(f)
    -- May be secret. Straight to the setter, never compared or cached.
    pcall(f.health.SetStatusBarColor, f.health, r, g, b, 1)
    -- The unfilled portion is a flat near-black, not a darkened tint of
    -- the bar colour, so there is no arithmetic here and nothing to guard.
    if f.health.bg then
        f.health.bg:SetVertexColor(0.031, 0.031, 0.031, 0.85)
    end
end

--------------------------------------------------------------------------------
--  The widget
--------------------------------------------------------------------------------
ns.Widget{
    name = "health",

    Build = function(f)
        -- Anchored in Layout, once f.health exists: the plate root is 1x1 now
        -- and everything on the plate hangs off the BAR.
        f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        EV.Pixel.NoSnap(f.bg)

        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        EV.Pixel.NoSnap(bar.bg)
        f.health = bar

        f.overlay = CreateFrame("Frame", nil, f)
        f.overlay:SetFrameLevel(f:GetFrameLevel() + 5)

        -- Inner shadow. Measured off the reference rather than invented:
        -- sampling a column down its bar gives (2,0,0), (11,0,3), (25,0,16),
        -- (125,45,113), (226,83,206) and only then the full colour, so under
        -- the black border there is a three row ramp from dark up to the
        -- fill, and a two row one at the bottom. That ramp is what makes it
        -- read as inset rather than as a flat block of colour.
        --
        -- On f.overlay so it sits above the StatusBar's fill, which draws on
        -- ARTWORK, but at an ARTWORK sublevel here so it stays under the text.
        -- File backed, for the same reason as the aggro glow: a colour
        -- texture ignores SetGradient.
        f.shadeTop = f.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
        f.shadeTop:SetTexture("Interface\\Buttons\\WHITE8X8")
        f.shadeBottom = f.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
        f.shadeBottom:SetTexture("Interface\\Buttons\\WHITE8X8")

        f.healthText = f.overlay:CreateFontString(nil, "OVERLAY")
        f.healthText:SetJustifyH("RIGHT")
        f.healthText:SetWordWrap(false)
    end,

    --- The plate frame IS the health bar's box. Nothing else is laid out
    --- inside it: the cast bar hangs below, the name sits above. That is why
    --- this is now a plain inset rather than a height calculation.
    --- The bar: a near-black background at 0.031 grey and 0.85 alpha, a
    --- solid fill so the colour rules own the hue, and a hard BLACK 1px
    --- border rather than a themed one. The border is what makes the bar read
    --- against the world at a glance, which is the whole point of the look.
    Layout = function(f, cfg)
        -- Here rather than on EV_PROFILE_CHANGED, which nothing in the suite
        -- actually sends: the layout pass is what a settings change runs, so
        -- it is what has to pick up a new bar brightness. BuildPalette is
        -- idempotent, so calling it per plate costs one comparison.
        if ns.BuildPalette then ns.BuildPalette(cfg.barShade) end
        local one = EV.Pixel:One(f)
        f.bg:SetColorTexture(0.031, 0.031, 0.031, 0.85)
        f.bg:SetAllPoints(f.health)
        f.overlay:SetAllPoints(f.health)

        local tex = EV.Media:Fetch("statusbar", cfg.texture)
        f.health:SetStatusBarTexture(tex)
        f.health.bg:SetTexture(tex)

        -- CENTRE PLUS SIZE, not two opposite edges: one SetPoint on the
        -- plate's centre, then an explicit SetSize.
        --
        -- The two forms are not equivalent once anything quantises. A bar
        -- derived from a point and a size rounds ONE position and keeps an
        -- exact size. A bar derived from the plate's two opposite edges
        -- rounds TWO independent positions, and its size is whatever falls
        -- out between them -- which changes as the plate slides. Every text
        -- string on the plate then hangs off that bar, so its width breathing
        -- by a pixel moves the text with it.
        --
        -- Even numbers of pixels, for the same reason the plate itself uses
        -- them: an odd size on a centre anchor puts both edges on half pixels.
        -- The bar is the plate's geometry now: a centre and a size, taken
        -- straight from the settings rather than derived from a parent box.
        -- The root is 1x1 (see Core.lua) so there are no edges to inherit and
        -- exactly one position to round.
        local function EvenPx(v)
            local px = math.floor(v / one + 0.5)
            if px % 2 == 1 then px = px - 1 end
            return math.max(px, 2) * one
        end
        f.health:ClearAllPoints()
        f.health:SetPoint("CENTER", f, "CENTER", 0, 0)
        f.health:SetSize(EvenPx(cfg.width), EvenPx(cfg.height))

        -- Decoupled: the last argument. The plate's scale changes when it
        -- becomes your target and changes back when it does not, and a border
        -- snapped in the plate's own coordinate space loses whole SIDES as it
        -- slides across the screen afterwards. See Pixel:CreateBorder.
        --
        -- Decoupling also puts the strips on their own container a frame level
        -- up, which is what keeps the health bar's fill from painting over
        -- them: a StatusBar fill draws on ARTWORK, above the BORDER layer.
        f.plateBorder = EV.Pixel:CreateBorder(f.health, cfg.borderSize, 0, 0, 0, 1, true)

        local shadeOn = cfg.innerShadow and cfg.height >= 10
        f.shadeTop:SetShown(shadeOn)
        f.shadeBottom:SetShown(shadeOn)
        if shadeOn then
            local topH = math.max(one * math.floor(cfg.height * 0.16 + 0.5), one)
            local botH = math.max(one * math.floor(cfg.height * 0.10 + 0.5), one)
            -- To the BAR, not to the plate's edges. The bar is now the thing
            -- with exact geometry, so everything drawn on it anchors to it and
            -- they quantise as one.
            f.shadeTop:ClearAllPoints()
            f.shadeTop:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
            f.shadeTop:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", 0, 0)
            f.shadeTop:SetHeight(topH)
            -- VERTICAL runs min at the bottom to max at the top, so the dark
            -- end goes in maxColor for the top strip and minColor for the
            -- bottom one. Deeper at the top, which is what the reference
            -- measures and what reads as light from above.
            pcall(f.shadeTop.SetGradient, f.shadeTop, "VERTICAL",
                  CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.55))
            f.shadeBottom:ClearAllPoints()
            f.shadeBottom:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT", 0, 0)
            f.shadeBottom:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", 0, 0)
            f.shadeBottom:SetHeight(botH)
            pcall(f.shadeBottom.SetGradient, f.shadeBottom, "VERTICAL",
                  CreateColor(0, 0, 0, 0.4), CreateColor(0, 0, 0, 0))
        end

        -- Health percent, right aligned, ON the bar, at the plate's font
        -- size: it is already small, so there is no extra scale on top.
        ns.SetText(f.healthText, cfg.fontSize, true)
        f.healthText:ClearAllPoints()
        -- Fixed width as well as a fixed anchor. A right aligned string whose
        -- width follows its content pushes nothing around on its own, but the
        -- name reserves space for it in pixels (Extras.lua), and the two have
        -- to agree on how much.
        ns.AnchorInBar(f.healthText, f, "RIGHT", -one * 2)
        -- No fixed width: a right-anchored string that sizes itself cannot
        -- truncate, and at 2.6x the font size "100%" in the outlined face did
        -- ("10..."). The name's reserve for it lives in Extras.lua.
        f.healthText:SetWidth(0)
        if f.healthText.SetWordWrap then f.healthText:SetWordWrap(false) end
        f.healthText:SetShown(cfg.healthText ~= "none")
        f._hText = nil
    end,

    --- Everything the active colour rules need, plus health itself.
    Events = function(cfg)
        local out = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
        for _, e in ipairs(ns.ColourEvents(cfg)) do out[#out + 1] = e end
        return out
    end,

    SetUnit = function(f)
        f._maxValid = false
        f._hText = nil
        ns.RefreshState(f)
        ns.PaintHealth(f)
        ns.PaintColour(f)
    end,

    Clear = function(f)
        dirty[f] = nil
        f._maxValid, f._hText = false, nil
        if f.state then wipe(f.state) end
    end,
}

--------------------------------------------------------------------------------
--  Event handlers. Health marks; everything else recolours.
--------------------------------------------------------------------------------
ns.eventHandlers.UNIT_HEALTH = function(f) ns.MarkHealth(f) end
ns.eventHandlers.UNIT_MAXHEALTH = function(f) f._maxValid = false; ns.MarkHealth(f) end

local function Recolour(f)
    ns.RefreshState(f)
    ns.PaintColour(f)
end
for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
                     "UNIT_FACTION", "UNIT_FLAGS" }) do
    ns.eventHandlers[e] = Recolour
end
