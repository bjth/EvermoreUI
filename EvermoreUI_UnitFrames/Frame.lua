if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Frame.lua
--  Builds one unit frame and knows how to update each part of it.
--
--   +---------+------------------------------------------+
--   |         | 15  Name                     12.3k  87%  |  health
--   | portrait+------------------------------------------+
--   |         |                                    4,210 |  power
--   +---------+------------------------------------------+
--
--  The frame is a SecureUnitButtonTemplate button: left-click targets,
--  right-click opens the unit menu. Only plain secure attributes are used,
--  no restricted snippets, so it works on Forever's client.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local V = ns.Values
local L = EV.L

local UF = {}
ns.Frame = UF

local floor, max = math.floor, math.max

--------------------------------------------------------------------------------
--  Colours
--------------------------------------------------------------------------------
-- Hostility and tapped come from the suite palette (Core/Palette.lua), the
-- same values the nameplates use, so a mob is the same red on its plate and
-- on the target frame. Shaded by the frame's own barShade exactly as the
-- plates shade theirs: white text on full red is 4.00:1, at 0.75 it is 6.53:1.
-- Class colours are left at full strength, as they are on the plates.
local PAL  = EV.Palette
local DARK = { 0.13, 0.13, 0.15 }

-- shaded[shade][key] -> { r, g, b }. Built once per shade value, from our own
-- constants, so the arithmetic never touches anything secret.
-- Keyed by the source colour table itself, so hostility and power colours
-- share one cache without their names colliding.
local shaded = {}
local function ShadeOf(src, shade)
    shade = PAL.ValidShade(shade)
    local set = shaded[shade]
    if not set then set = {}; shaded[shade] = set end
    local c = set[src]
    if not c then c = PAL.Shade(nil, src, shade); set[src] = c end
    return c
end

--- Your own colours changed (Colours page): the shaded copies are stale.
function UF.ClearColourCache() wipe(shaded) end
local function Shaded(key, shade) return ShadeOf(PAL.REACTION[key], shade) end

local function ClassColour(unit)
    local _, class = UnitClass(unit)
    local r, g, b = PAL.ClassRGB(class)
    if r then return { r, g, b } end
end

-- Same ladder as the nameplate reaction rule: 1-2 hostile, 3 unfriendly
-- (orange), 4 neutral, 5+ friendly, tapped first. PAL.ReactionKey guards
-- every read, so a secret reaction reads as unknown rather than throwing.
local function ReactionColour(unit, shade)
    return Shaded(PAL.ReactionKey(unit), shade)
end

--------------------------------------------------------------------------------
--  Backgrounds
--
--  The nameplates' look: the unfilled part of a bar is a flat
--  near-black, not a darkened tint of the bar colour. That also retires the
--  old secret-colour problem here outright: the old Darken() multiplied the
--  bar colour, which threw 32 times in one instance when the colour came back
--  secret. A constant has nothing to guard.
--------------------------------------------------------------------------------
local BG_RGB   = { 0.031, 0.031, 0.031 }
local BG_ALPHA = 0.85

--- Colour the unit's health bar should be in this mode.
function UF.HealthColour(unit, mode, shade)
    if mode == "green" then return Shaded("friendly", shade) end
    if mode == "dark" then return DARK end
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okP and isPlayer == true then return ClassColour(unit) or Shaded("friendly", shade) end
    return ReactionColour(unit, shade)
end

-- Our five from the suite palette; anything else (a vehicle's resource,
-- whatever Forever adds) falls back to Blizzard's own colour. Both are
-- shaded with the health bar's barShade so the two bars sit at one
-- brightness. Blizzard's table is constants, never secret; the token is
-- guarded in case UnitPowerType ever is.
local fallbackPower = setmetatable({}, { __mode = "k" })
local function PowerColour(unit, shade)
    local ok, pType, token = pcall(UnitPowerType, unit)
    if not ok or V.IsSecret(pType) or V.IsSecret(token) then token, pType = "MANA", nil end
    local src = token and PAL.POWER[token]
    if not src then
        local c = PowerBarColor and ((token and PowerBarColor[token]) or (pType and PowerBarColor[pType]))
        if c and type(c.r) == "number" then
            src = fallbackPower[c]
            if not src then src = { c.r, c.g, c.b }; fallbackPower[c] = src end
        else
            src = PAL.POWER.MANA
        end
    end
    return ShadeOf(src, shade)
end

--------------------------------------------------------------------------------
--  Aggro glow
--
--  The nameplates' aggro backdrop on a unit frame: Blizzard's eight piece
--  GlowBorder set, ADD blended, red at aggroAlpha, reaching aggroPad pixels
--  past the frame and drawn BEHIND it. Why each of those (ADD not BLEND,
--  eight pieces not four ramps) is written out in
--  EvermoreUI_Nameplates/Extras.lua and applies here unchanged.
--
--  Which question it answers depends on the unit:
--
--   * A hostile target or focus asks the PLATE's question, "is this mob on
--     me": UnitDetailedThreatSituation("player", unit). So the target frame
--     and the target's plate light together, for the same reason.
--   * Everything else asks "is this unit tanking something": its own threat
--     status, and under restriction whether it is tanking its target.
--
--  Threat is secret in exactly the content where it matters. UnitThreatSituation
--  is SecretWhenUnitThreatStateRestricted and UnitDetailedThreatSituation is
--  SecretWhenUnitThreatValuesRestricted, and the only fold on offer is from a
--  secret BOOLEAN (isTanking) through Frame:SetAlphaFromBoolean. So the glow
--  stays shown and its alpha carries the answer, decided C-side; Lua never
--  branches on anything it may not read.
--
--  Readable threat keeps one thing the plate cannot show: amber while threat
--  is climbing (status 1). A folded boolean only has two answers, so under
--  restriction it is red or nothing, exactly like the plate.
--------------------------------------------------------------------------------
local AGGRO_RED   = { 0.95, 0.1, 0.1 }        -- the plate's glow red
local AGGRO_AMBER = PAL.THREAT.transition

-- The mob to ask about when a friendly unit's status number is secret.
local AGGRO_MOB = { player = "target", target = "targettarget",
                    focus = "focustarget", pet = "pettarget" }

local function BuildGlow(f)
    -- A child one frame level BELOW its parent draws under the parent's own
    -- regions, which is what puts the glow behind the frame rather than
    -- washing over its bars. Not protected itself, so Show and Hide stay
    -- legal in combat.
    local panel = CreateFrame("Frame", nil, f)
    panel:EnableMouse(false)
    panel:SetFrameLevel(max(f:GetFrameLevel() - 1, 0))
    panel:Hide()
    local C = "Interface\\Common\\GlowBorder-Corner"
    local H = "Interface\\Common\\GlowBorder-Top"
    local Vt = "Interface\\Common\\GlowBorder-Left"
    local function Piece(file, l, r, t, b)
        local tex = panel:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(file)
        tex:SetBlendMode("ADD")
        tex:SetTexCoord(l, r, t, b)
        EV.Pixel.NoSnap(tex)
        return tex
    end
    panel.glow = {
        tl = Piece(C, 0, 1, 0, 1), tr = Piece(C, 1, 0, 0, 1),
        bl = Piece(C, 0, 1, 1, 0), br = Piece(C, 1, 0, 1, 0),
        top  = Piece(H, 0, 1, 0, 1),  bottom = Piece(H, 0, 1, 1, 0),
        left = Piece(Vt, 0, 1, 0, 1), right  = Piece(Vt, 1, 0, 0, 1),
    }
    return panel
end

--- Blizzard's proportions: a corner twice the overhang, edges spanning
--- between the corners (Blizzard_HelpPlate.xml:486-538). Out of combat only.
local function LayoutGlow(f, cfg)
    local panel = f.aggro
    local g = panel.glow
    local pad = EV.Pixel:One(f) * (cfg.aggroPad or 8)
    local size = pad * 2
    panel:ClearAllPoints()
    panel:SetAllPoints(f)
    g.tl:ClearAllPoints(); g.tl:SetSize(size, size); g.tl:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
    g.tr:ClearAllPoints(); g.tr:SetSize(size, size); g.tr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", pad, pad)
    g.bl:ClearAllPoints(); g.bl:SetSize(size, size); g.bl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -pad, -pad)
    g.br:ClearAllPoints(); g.br:SetSize(size, size); g.br:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)
    g.top:ClearAllPoints();    g.top:SetPoint("TOPLEFT", g.tl, "TOPRIGHT");    g.top:SetPoint("BOTTOMRIGHT", g.tr, "BOTTOMLEFT")
    g.bottom:ClearAllPoints(); g.bottom:SetPoint("TOPLEFT", g.bl, "TOPRIGHT");  g.bottom:SetPoint("BOTTOMRIGHT", g.br, "BOTTOMLEFT")
    g.left:ClearAllPoints();   g.left:SetPoint("TOPLEFT", g.tl, "BOTTOMLEFT"); g.left:SetPoint("BOTTOMRIGHT", g.bl, "TOPRIGHT")
    g.right:ClearAllPoints();  g.right:SetPoint("TOPLEFT", g.tr, "BOTTOMLEFT"); g.right:SetPoint("BOTTOMRIGHT", g.br, "TOPRIGHT")
    panel.evTint = nil   -- repaint at the current alpha on the next update
end

local function Tint(panel, c, a)
    if panel.evTint == c then return end
    panel.evTint = c
    for _, tex in pairs(panel.glow) do tex:SetVertexColor(c[1], c[2], c[3], a) end
end

local function HideGlow(panel)
    panel:SetAlpha(1)   -- drop any secret alpha a fold left behind
    panel:Hide()
end

--- Show the glow with an answer that may be secret. Folded, never compared.
local function FoldGlow(panel, isTanking)
    panel:Show()
    if V.IsSecret(isTanking) then
        if not pcall(panel.SetAlphaFromBoolean, panel, isTanking, 1, 0) then HideGlow(panel) end
    else
        panel:SetAlpha(isTanking == true and 1 or 0)
    end
end

local function Hostile(unit)
    local ok, v = pcall(UnitCanAttack, "player", unit)
    return ok and not V.IsSecret(v) and v == true
end

--- Show, colour or hide the aggro glow for this unit.
function UF.UpdateAggro(f, cfg)
    local panel = f.aggro
    if not panel then return end
    if not cfg.aggroBorder or not UnitExists(f.unit) then HideGlow(panel); return end
    local a = cfg.aggroAlpha or 0.35

    -- A mob: the plate's question.
    if f.unit ~= "player" and Hostile(f.unit) then
        local ok, isTanking = pcall(UnitDetailedThreatSituation, "player", f.unit)
        if not ok or type(isTanking) == "nil" then HideGlow(panel); return end
        Tint(panel, AGGRO_RED, a)
        FoldGlow(panel, isTanking)
        return
    end

    -- A friend: is this unit tanking something?
    local ok, status = pcall(UnitThreatSituation, f.unit)
    if not ok or type(status) == "nil" then HideGlow(panel); return end
    if V.IsSecret(status) then
        local mob = AGGRO_MOB[f.key]
        if not mob or not UnitExists(mob) or type(panel.SetAlphaFromBoolean) ~= "function" then
            HideGlow(panel); return
        end
        local okT, isTanking = pcall(UnitDetailedThreatSituation, f.unit, mob)
        if not okT or type(isTanking) == "nil" then HideGlow(panel); return end
        Tint(panel, AGGRO_RED, a)
        FoldGlow(panel, isTanking)
        return
    end
    if status <= 0 then HideGlow(panel); return end
    Tint(panel, status == 1 and AGGRO_AMBER or AGGRO_RED, a)
    panel:SetAlpha(1)
    panel:Show()
end

--------------------------------------------------------------------------------
--  Construction
--------------------------------------------------------------------------------
local function Bar(parent)
    local sb = CreateFrame("StatusBar", nil, parent)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(1)
    sb.bg = sb:CreateTexture(nil, "BACKGROUND")
    sb.bg:SetAllPoints()
    return sb
end

--------------------------------------------------------------------------------
--  Incoming heals
--
--  Both UnitGetIncomingHeals and UnitHealthMax return secret values, so we
--  cannot add, divide or compare them. We never need to: the bar's left edge
--  is anchored to the health fill's right edge, so the client moves it as
--  health changes, and the fill width comes out of SetMinMaxValues(0, max) +
--  SetValue(incoming), which the client also works out. A clip frame covering
--  the missing-health portion stops it drawing past the end of the bar.
--
--  UnitHealPredictionCalculator is the preferred source: it applies the
--  client's own clamping (incoming heals reduced by heal absorbs, capped at
--  missing health plus overflow) inside the client, so the value we hand to
--  SetValue is already the amount Blizzard would draw. UnitGetIncomingHeals
--  is the fallback on clients without it, unclamped.
--------------------------------------------------------------------------------
local healCalc
if type(CreateUnitHealPredictionCalculator) == "function" then
    local ok, c = pcall(CreateUnitHealPredictionCalculator)
    if ok then healCalc = c end
end

--- Incoming heals and the health maximum to scale them against.
--- Either may be secret. Returns nil when the client can't tell us.
local function Incoming(unit)
    if healCalc and type(UnitGetDetailedHealPrediction) == "function" then
        if pcall(UnitGetDetailedHealPrediction, unit, nil, healCalc) then
            local okAmt, amount = pcall(healCalc.GetIncomingHeals, healCalc)
            local okMax, maxHP  = pcall(healCalc.GetMaximumHealth, healCalc)
            if okAmt and okMax and type(amount) ~= "nil" and type(maxHP) ~= "nil" then
                return amount, maxHP
            end
        end
    end
    if type(UnitGetIncomingHeals) == "function" then
        local ok, amount = pcall(UnitGetIncomingHeals, unit)
        if ok and type(amount) ~= "nil" then
            return amount, UnitHealthMax(unit)
        end
    end
    return nil
end

local function Text(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs   -- face, size and edge are set in Layout (EV.Fonts:StyleText)
end

function UF.Create(key, unit)
    local name = "EvermoreUI_" .. key .. "Frame"
    local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
    f:SetFrameStrata("LOW")
    f:SetAttribute("unit", unit)
    return UF.Dress(f, key, unit)
end

--- Build the frame's parts onto a button that already exists: ours from
--- UF.Create, or one a group header made (GroupFrames.lua). Out of combat.
function UF.Dress(f, key, unit)
    f.key, f.unit = key, unit
    if f.GetAttribute and f:IsProtected() then
        f:SetAttribute("*type1", "target")
        f:SetAttribute("*type2", "togglemenu")
        f:RegisterForClicks("AnyUp")
    end

    -- Click-casting addons (Clique and friends) look here.
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true

    f:SetScript("OnEnter", function(self)
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
        else GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT") end
        if self.unit then GameTooltip:SetUnit(self.unit) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Room below us for the aggro glow, which sits one level under the frame.
    f:SetFrameLevel(max(f:GetFrameLevel(), 2))

    -- Background and border: the plate's near-black and hard black edge.
    -- Thickness is applied in Layout (cfg.borderSize).
    f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.bg:SetAllPoints()
    EV.Pixel.NoSnap(f.bg)
    EV.Pixel:CreateBorder(f, 2, 0, 0, 0, 1)

    f.aggro = BuildGlow(f)

    -- Hairline between health and power: the plates' power strip carries a
    -- one pixel black edge rather than the full border, for the same reason
    -- (a thick border eats a thin bar).
    f.divider = f:CreateTexture(nil, "BORDER")
    f.divider:SetColorTexture(0, 0, 0, 1)
    EV.Pixel.NoSnap(f.divider)

    f.health = Bar(f)
    f.power = Bar(f)

    -- Incoming heals. Anchored in Layout, once the health bar has a texture.
    f.healClip = CreateFrame("Frame", nil, f.health)
    f.healClip:SetClipsChildren(true)
    f.heal = CreateFrame("StatusBar", nil, f.healClip)
    f.heal:SetFrameLevel(f.health:GetFrameLevel() + 1)
    f.heal:SetMinMaxValues(0, 1)
    f.heal:SetValue(0)
    f.heal:Hide()

    -- Portrait: a 3D model and a texture share one slot.
    f.portrait = CreateFrame("Frame", nil, f)
    f.portrait.bg = f.portrait:CreateTexture(nil, "BACKGROUND")
    f.portrait.bg:SetAllPoints()
    f.portrait.bg:SetColorTexture(EV.Theme.RGBA("surfaceSunk", 0.6))
    f.portrait.model = CreateFrame("PlayerModel", nil, f.portrait)
    f.portrait.model:SetAllPoints()
    f.portrait.tex = f.portrait:CreateTexture(nil, "ARTWORK")
    f.portrait.tex:SetAllPoints()
    -- Black hairline between the portrait and the bars, drawn on the frame
    -- in the gap Layout leaves for it.
    f.portrait.edge = f:CreateTexture(nil, "BORDER")
    f.portrait.edge:SetColorTexture(0, 0, 0, 1)
    EV.Pixel.NoSnap(f.portrait.edge)

    -- Text sits above both bars.
    f.overlay = CreateFrame("Frame", nil, f)
    f.overlay:SetAllPoints()
    f.overlay:SetFrameLevel(f:GetFrameLevel() + 5)

    -- Inset shading on the health bar, the plates' measured ramp: dark under
    -- the top border fading down into the fill, a shallower one at the
    -- bottom. On the overlay so it sits above the fill (ARTWORK) but at an
    -- ARTWORK sublevel below the text. File backed: a colour texture ignores
    -- SetGradient.
    -- The power bar gets the same pair, so the two bars read as one inset
    -- panel rather than a shaded bar sitting on a flat one.
    local function Shade()
        local t = f.overlay:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        return t
    end
    f.shadeTop, f.shadeBottom = Shade(), Shade()
    f.powerShadeTop, f.powerShadeBottom = Shade(), Shade()
    f.nameText   = Text(f.overlay, "LEFT")
    f.healthText = Text(f.overlay, "RIGHT")
    f.powerText  = Text(f.overlay, "RIGHT")
    f.statusText = Text(f.overlay, "CENTER")

    f.raidIcon = f.overlay:CreateTexture(nil, "OVERLAY")
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    f.raidIcon:SetSize(18, 18)
    f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raidIcon:Hide()

    if key == "player" then
        f.stateIcon = f.overlay:CreateTexture(nil, "OVERLAY")
        f.stateIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
        f.stateIcon:SetSize(18, 18)
        f.stateIcon:SetPoint("CENTER", f, "TOPLEFT", 2, -2)
        f.stateIcon:Hide()
    end

    return f
end

--------------------------------------------------------------------------------
--  Layout (out of combat only: the frame is protected)
--------------------------------------------------------------------------------

--- The plates' measured inset ramp on one bar: 16% of its height dark under
--- the top edge, 10% at the bottom. Below 8 tall the top strip would be a
--- single pixel of near-black and just reads as a thicker border, so a thin
--- bar goes without. (The plate's own rule is 10 on a 26 tall bar; 8 lets a
--- 10 tall power bar, the player default, have it.)
local function InsetShade(top, bottom, bar, h, on, one)
    on = on and h >= 8
    top:SetShown(on)
    bottom:SetShown(on)
    if not on then return end
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    top:SetHeight(max(one * floor(h * 0.16 + 0.5), one))
    -- VERTICAL runs min at the bottom to max at the top.
    pcall(top.SetGradient, top, "VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.55))
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(max(one * floor(h * 0.10 + 0.5), one))
    pcall(bottom.SetGradient, bottom, "VERTICAL", CreateColor(0, 0, 0, 0.4), CreateColor(0, 0, 0, 0))
end
function UF.Layout(f, cfg)
    local w, h = cfg.width, cfg.height
    EV.Pixel:SetSize(f, w, h)
    local one = EV.Pixel:One(f)
    local bpx = cfg.borderSize or 2
    local b = one * bpx
    f.bg:SetColorTexture(BG_RGB[1], BG_RGB[2], BG_RGB[3], cfg.bgAlpha)
    EV.Pixel:CreateBorder(f, bpx, 0, 0, 0, 1)
    f.portrait.bg:SetColorTexture(BG_RGB[1], BG_RGB[2], BG_RGB[3], BG_ALPHA)
    LayoutGlow(f, cfg)

    local tex = EV.Media:Fetch("statusbar", cfg.texture)
    f.health:SetStatusBarTexture(tex)
    f.health.bg:SetTexture(tex)
    f.power:SetStatusBarTexture(tex)
    f.power.bg:SetTexture(tex)
    f.power.bg:SetVertexColor(BG_RGB[1], BG_RGB[2], BG_RGB[3], BG_ALPHA)

    -- Everything sits inside the border. Portrait: a square the height of
    -- that inner box, then a one pixel black hairline, then the bars.
    local innerH = max(h - b * 2, 1)
    local pw = 0          -- portrait plus its hairline
    local edge = f.portrait.edge
    edge:ClearAllPoints()
    if cfg.portrait ~= "none" then
        local p = f.portrait
        p:ClearAllPoints()
        p:SetSize(innerH, innerH)
        pw = innerH + one
        if cfg.portraitSide == "right" then
            p:SetPoint("TOPRIGHT", f, "TOPRIGHT", -b, -b)
            edge:SetPoint("TOPRIGHT", p, "TOPLEFT", 0, 0)
            edge:SetPoint("BOTTOMRIGHT", p, "BOTTOMLEFT", 0, 0)
        else
            p:SetPoint("TOPLEFT", f, "TOPLEFT", b, -b)
            edge:SetPoint("TOPLEFT", p, "TOPRIGHT", 0, 0)
            edge:SetPoint("BOTTOMLEFT", p, "BOTTOMRIGHT", 0, 0)
        end
        edge:SetWidth(one)
        edge:Show()
        p:Show()
    else
        f.portrait:Hide()
        edge:Hide()
    end

    local left  = (cfg.portraitSide ~= "right") and pw or 0
    local right = (cfg.portraitSide == "right") and pw or 0
    local ph = cfg.powerHeight
    local gap = ph > 0 and one or 0

    f.health:ClearAllPoints()
    f.health:SetPoint("TOPLEFT", f, "TOPLEFT", b + left, -b)
    f.health:SetPoint("TOPRIGHT", f, "TOPRIGHT", -b - right, -b)
    local healthH = max(innerH - ph - gap, 1)
    f.health:SetHeight(healthH)

    InsetShade(f.shadeTop, f.shadeBottom, f.health, healthH, cfg.innerShadow, one)
    InsetShade(f.powerShadeTop, f.powerShadeBottom, f.power, ph, cfg.innerShadow and ph > 0, one)

    -- Incoming heals ride the health fill's right edge into the empty part of
    -- the bar. The bar is given the health bar's full width so that
    -- value/maximum scales the fill exactly as it does on the health bar.
    local fill = f.health:GetStatusBarTexture()
    if fill then
        local barW = max(w - b * 2 - pw, 1)
        f.healClip:ClearAllPoints()
        f.healClip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        f.healClip:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", 0, 0)

        f.heal:ClearAllPoints()
        f.heal:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        f.heal:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
        f.heal:SetWidth(barW)
        f.heal:SetStatusBarTexture(tex)
        f.heal:SetStatusBarColor(EV.Theme.RGBA("success", 0.45))
        f.heal:SetFrameLevel(f.health:GetFrameLevel() + 1)
    end

    f.divider:ClearAllPoints()
    if ph > 0 then
        f.divider:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, 0)
        f.divider:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, 0)
        f.divider:SetHeight(gap)
        f.divider:Show()
        f.power:ClearAllPoints()
        f.power:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -gap)
        f.power:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -gap)
        f.power:SetHeight(ph)
        f.power:Show()
    else
        f.divider:Hide()
        f.power:Hide()
    end

    -- Text
    -- Same face, slug objects and text edge as the nameplates
    -- (EV.Fonts:StyleText). Unit frames sit still, so slug is not fixing a
    -- bounce here; it is so the two render the same glyphs.
    local size, style = cfg.fontSize, cfg.textStyle
    EV.Fonts:StyleText(f.nameText, size, style, true)
    EV.Fonts:StyleText(f.healthText, size, style, true)
    EV.Fonts:StyleText(f.statusText, size, style, true)
    EV.Fonts:StyleText(f.powerText, max(size - 2, 8), style, true)
    f.nameText:SetTextColor(1, 1, 1)

    f.healthText:ClearAllPoints()
    f.healthText:SetPoint("RIGHT", f.health, "RIGHT", -5, 0)
    f.nameText:ClearAllPoints()
    f.nameText:SetPoint("LEFT", f.health, "LEFT", 5, 0)
    f.nameText:SetPoint("RIGHT", f.healthText, "LEFT", -6, 0)
    f.statusText:ClearAllPoints()
    f.statusText:SetPoint("CENTER", f.health, "CENTER", 0, 0)
    f.powerText:ClearAllPoints()
    f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -5, 0)
    f.powerText:SetShown(ph >= 9 and cfg.powerText ~= "none")
    f.nameText:SetShown(cfg.showName)
end

--------------------------------------------------------------------------------
--  Updates
--------------------------------------------------------------------------------
function UF.UpdateHealthColour(f, cfg)
    local c = UF.HealthColour(f.unit, cfg.healthColour, cfg.barShade)
    f.health:SetStatusBarColor(c[1], c[2], c[3], 1)
    if cfg.healthColour == "dark" then
        -- Dark bars: the missing health shows in the unit's colour.
        local u = UF.HealthColour(f.unit, "class", cfg.barShade)
        f.health.bg:SetVertexColor(u[1], u[2], u[3], 0.55)
    else
        f.health.bg:SetVertexColor(BG_RGB[1], BG_RGB[2], BG_RGB[3], BG_ALPHA)
    end
end

--- Incoming heals, drawn past the end of the health fill.
function UF.UpdateHeals(f, cfg)
    local bar = f.heal
    if not bar then return end
    if not cfg.healPrediction then bar:Hide(); return end

    local amount, maxHP = Incoming(f.unit)
    -- No comparison against amount: it may be secret, and a zero heal simply
    -- draws an empty bar.
    if type(amount) == "nil" or type(maxHP) == "nil" then bar:Hide(); return end
    bar:SetMinMaxValues(0, maxHP)
    bar:SetValue(amount)
    bar:Show()
end

function UF.UpdateHealth(f, cfg)
    local unit = f.unit
    local cur, maxHP = UnitHealth(unit), UnitHealthMax(unit)
    f.health:SetMinMaxValues(0, maxHP)
    f.health:SetValue(cur)
    UF.UpdateHeals(f, cfg)

    local status
    if not UnitIsConnected(unit) then status = L["Offline"]
    elseif UnitIsGhost(unit) then status = L["Ghost"]
    elseif UnitIsDead(unit) then status = L["Dead"] end

    if status then
        f.statusText:SetText(status)
        f.statusText:Show()
        f.healthText:SetText("")
    else
        f.statusText:Hide()
        V.Write(f.healthText, cfg.healthText, "health", unit, cur, maxHP)
    end
end

function UF.UpdatePower(f, cfg)
    if cfg.powerHeight <= 0 then return end
    local unit = f.unit
    local pType = UnitPowerType(unit)
    local cur, maxP = UnitPower(unit, pType), UnitPowerMax(unit, pType)
    local c = PowerColour(unit, cfg.barShade)
    f.power:SetStatusBarColor(c[1], c[2], c[3], 1)
    f.power:SetMinMaxValues(0, maxP)
    f.power:SetValue(cur)
    if f.powerText:IsShown() then
        V.Write(f.powerText, cfg.powerText, "power", unit, cur, maxP)
    end
end

-- Level coloured by difficulty from the suite palette, the same five steps
-- the nameplates use. The colours are our own constants, so building the
-- colour code is plain arithmetic; only the level itself can be secret.
local function LevelString(unit)
    local ok, lvl = pcall(UnitLevel, unit)
    if not ok or type(lvl) ~= "number" or V.IsSecret(lvl) then return "" end
    local text = lvl > 0 and tostring(lvl) or "??"
    local c = PAL.Difficulty(unit, lvl > 0 and lvl or -1)
    local okC, class = pcall(UnitClassification, unit)
    if okC and type(class) == "string" and not V.IsSecret(class) then
        if class == "elite" or class == "worldboss" then text = text .. "+"
        elseif class == "rareelite" then text = text .. "R+"
        elseif class == "rare" then text = text .. "R" end
    end
    return ("|cff%02x%02x%02x%s|r "):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5),
                                            floor(c[3] * 255 + 0.5), text)
end

function UF.UpdateName(f, cfg)
    if not cfg.showName then return end
    local unit = f.unit
    local level = cfg.showLevel and LevelString(unit) or ""
    local ok = pcall(f.nameText.SetFormattedText, f.nameText, "%s%s", level, UnitName(unit) or "")
    if not ok then f.nameText:SetText("") end
end

-- Class icon: Blizzard's own class atlases where they exist, the old circle
-- sheet otherwise.
local function SetClassIcon(tex, unit)
    local _, class = UnitClass(unit)
    if type(class) ~= "string" or (issecretvalue and issecretvalue(class)) then return false end
    local atlas = "classicon-" .. class:lower()
    if tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
        tex:SetTexCoord(0, 1, 0, 1)
        return true
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        tex:SetTexCoord(unpack(coords))
        return true
    end
    return false
end

function UF.UpdatePortrait(f, cfg)
    local mode = cfg.portrait
    if mode == "none" then return end
    local p, unit = f.portrait, f.unit
    if mode == "3d" then
        p.tex:Hide()
        p.model:Show()
        if UnitIsVisible(unit) and UnitIsConnected(unit) then
            p.model:SetUnit(unit)
            p.model:SetPortraitZoom(1)
            p.model:SetCamDistanceScale(1)
            p.model:SetPosition(0, 0, 0)
        else
            -- Out of view: show the 2D picture instead of an empty box.
            p.model:Hide()
            p.tex:Show()
            SetPortraitTexture(p.tex, unit)
            p.tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
        end
        return
    end
    p.model:Hide()
    p.tex:Show()
    if mode == "class" and UnitIsPlayer(unit) and SetClassIcon(p.tex, unit) then return end
    SetPortraitTexture(p.tex, unit)
    p.tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
end

function UF.UpdateRaidIcon(f)
    local idx = GetRaidTargetIndex(f.unit)
    if idx and SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(f.raidIcon, idx)
        f.raidIcon:Show()
    else
        f.raidIcon:Hide()
    end
end

function UF.UpdateState(f)
    local icon = f.stateIcon
    if not icon then return end
    if UnitAffectingCombat("player") then
        icon:SetTexCoord(0.5, 1, 0, 0.49)
        icon:Show()
    elseif IsResting() then
        icon:SetTexCoord(0, 0.5, 0, 0.421875)
        icon:Show()
    else
        icon:Hide()
    end
end

function UF.UpdateAll(f, cfg)
    if not UnitExists(f.unit) then return end
    UF.UpdateHealthColour(f, cfg)
    UF.UpdateHealth(f, cfg)
    UF.UpdatePower(f, cfg)
    UF.UpdateName(f, cfg)
    UF.UpdatePortrait(f, cfg)
    UF.UpdateRaidIcon(f)
    UF.UpdateAggro(f, cfg)
    UF.UpdateState(f)
end
