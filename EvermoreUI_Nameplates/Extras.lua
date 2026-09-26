if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Extras.lua
--  Name, level, target and focus treatment, raid marker, execute glow.
--
--  Two things here are worth reading rather than skimming.
--
--  The TARGET widget only ever touches TWO plates on a target change, the
--  one losing it and the one gaining it, because those are the only two
--  whose answer can have changed. Target churn is constant in combat, and a
--  full sweep of every plate on every swap is the classic way a nameplate
--  addon becomes the thing eating your frames. The one full sweep is the
--  non-target fade, which genuinely does flip every plate, and it is
--  skipped entirely when the setting is off.
--
--  The EXECUTE glow never reads health. The below-threshold gate is a colour
--  curve evaluated C-side by UnitHealthPercent feeding SetVertexColor, and
--  the pulse is a looping C-side alpha animation. Two separate channels that
--  multiply, so they never fight, and the whole thing renders identically
--  inside and outside restricted combat because Lua never branches on a
--  health value. Alpha stays 1 at every curve point and only RGB varies:
--  curve alpha interpolation is deliberately not relied on.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local T = EV.Theme

--------------------------------------------------------------------------------
--  Name and level
--------------------------------------------------------------------------------
--- The level's colour is the whole reason it is worth showing. Retail has
--- C_PlayerInfo.GetContentDifficultyCreatureForPlayer, which is plain valued
--- here (no SecretReturns on it), and where it is missing the level
--- difference is the rule Classic has always used.
-- Shared with the unit frames' level text (Core/Palette.lua).
local Difficulty = EV.Palette.Difficulty

--- The classic elite mark: "+" after the level for elites and rare elites,
--- in the level's own colour. A world boss already reads "??", so it gets
--- no mark. UnitClassification carries no SecretReturns, so this is a plain
--- string even in restricted content; guarded anyway so a surprise costs
--- only the "+".
local ELITE = { elite = true, rareelite = true }
local function EliteMark(unit)
    local ok, class = pcall(UnitClassification, unit)
    if ok and type(class) == "string" and not ns.IsSecret(class) and ELITE[class] then return "+" end
    return ""
end

--- "??" for a level the game will not tell you, which is what -1 means.
local function SetLevel(f)
    local fs = f.levelText
    if not fs then return end
    local ok, lvl = pcall(UnitLevel, f.unit)
    if not ok or ns.IsSecret(lvl) or type(lvl) ~= "number" then fs:SetText(""); return end
    local c = Difficulty(f.unit, lvl)
    fs:SetTextColor(c[1], c[2], c[3])
    if lvl < 0 then fs:SetText("??") else pcall(fs.SetFormattedText, fs, "%d%s", lvl, EliteMark(f.unit)) end
end

ns.Widget{
    name = "name",

    Build = function(f)
        f.nameText = f.overlay:CreateFontString(nil, "OVERLAY")
        f.nameText:SetJustifyH("LEFT")
        f.nameText:SetWordWrap(false)
        f.levelText = f.overlay:CreateFontString(nil, "OVERLAY")
        f.levelText:SetJustifyH("LEFT")
        f.levelText:SetWordWrap(false)
    end,

    --- The name sits LEFT ALIGNED ON THE BAR, opposite the health percent,
    --- rather than above it: hard against the left edge, truncated at 80%
    --- width.
    --- Two texts on one row is why the bar wants to be 12 tall, not 8.
    --- The text SLOTS: left, centre and right on the bar, each holding one
    --- element (ns.TextSlots in Core.lua). This widget owns the placement of
    --- every string on the bar, the health text included, so there is one
    --- place that knows what sits beside what.
    ---
    --- The rules the jitter work settled on, all kept:
    ---   * every string anchors to the BAR, never to another string;
    ---   * by its bottom edge, lifted whole pixels (ns.AnchorInBar);
    ---   * every offset and every width a whole number of pixels;
    ---   * the name is the only flexible element, and its width is the bar
    ---     minus fixed numeric reserves for its neighbours, never the gap
    ---     between two live strings.
    Layout = function(f, cfg)
        for _, fs in ipairs({ f.nameText, f.levelText }) do
            ns.SetText(fs, cfg.fontSize, true)
        end
        f.nameText:SetTextColor(1, 1, 1)

        local one = EV.Pixel:One(f)
        local function px(v) return math.floor(v + 0.5) end
        local W       = px(f.health:GetWidth() / one)
        local pad     = 2
        local inset   = 2                     -- the level's extra step in from an outer edge
        -- Room for "60+": two digits and the elite mark. Fixed for every
        -- plate rather than measured, so an elite's name starts where a
        -- normal mob's does and nothing shifts as the mark comes and goes.
        local levelW  = px(cfg.fontSize * 2.0 + 3)
        local healthW = px(cfg.fontSize * 3.2 + 3)
        local hasHealth = cfg.healthText ~= "none"

        local slots = ns.TextSlots(cfg)
        -- What each slot reserves when something ELSE has to fit beside it.
        local function Reserve(what)
            if what == "level" then return levelW + inset
            elseif what == "health" then return hasHealth and healthW or 0
            elseif what == "levelname" then return levelW + inset   -- plus the flexible name
            end
            return 0
        end
        local function Flexible(what) return what == "name" or what == "levelname" end

        local centre = slots.centre
        local centreW = 0
        if centre == "level" then centreW = levelW
        elseif centre == "health" then centreW = hasHealth and healthW or 0 end

        -- Room for a flexible slot. A side slot runs from its edge to the
        -- centre element if there is one, otherwise to the other side's
        -- reserve. A centred name is symmetric, so it gives up the larger of
        -- the two side reserves on BOTH sides and stays centred.
        local function SideRoom(side)
            local other = slots[side == "left" and "right" or "left"]
            if centre ~= "none" and not Flexible(centre) then
                return px(W / 2 - centreW / 2) - pad - 2
            end
            if Flexible(centre) then return px((W - pad * 2) / 3) end  -- sharing with a centred name
            local room = W - pad * 2 - Reserve(other)
            if Flexible(other) then room = px(room / 2) end   -- two names share
            return room
        end

        local nameOn, levelOn, healthOn = false, false, false
        local fsName, fsLevel, fsHealth = f.nameText, f.levelText, f.healthText

        local function Place(side, what)
            if what == "none" then return end
            local sgn = side == "right" and -1 or 1
            local edge = side == "left" and "LEFT" or (side == "right" and "RIGHT" or "")
            local justify = side == "left" and "LEFT" or (side == "right" and "RIGHT" or "CENTER")
            local x0 = side == "centre" and 0 or sgn * pad

            if what == "health" then
                if not (fsHealth and hasHealth) then return end
                healthOn = true
                ns.AnchorInBar(fsHealth, f, edge, x0 * one)
                fsHealth:SetWidth(0)                       -- self-sized, cannot truncate
                fsHealth:SetJustifyH(justify)
            elseif what == "level" then
                levelOn = true
                local x = side == "centre" and 0 or sgn * (pad + inset)
                ns.AnchorInBar(fsLevel, f, edge, x * one)
                fsLevel:SetWidth(levelW * one)
                fsLevel:SetJustifyH(justify)
            elseif what == "name" then
                nameOn = true
                local w
                if side == "centre" then
                    w = W - pad * 2 - 2 * math.max(Reserve(slots.left), Reserve(slots.right))
                else
                    w = SideRoom(side)
                end
                ns.AnchorInBar(fsName, f, edge, x0 * one)
                fsName:SetWidth(math.max(w, 8) * one)
                fsName:SetJustifyH(justify)
            elseif what == "levelname" then
                -- Level on the outer edge, name inboard of it.
                levelOn, nameOn = true, true
                ns.AnchorInBar(fsLevel, f, edge, sgn * (pad + inset) * one)
                fsLevel:SetWidth(levelW * one)
                fsLevel:SetJustifyH(justify)
                ns.AnchorInBar(fsName, f, edge, sgn * (pad + inset + levelW) * one)
                fsName:SetWidth(math.max(SideRoom(side) - inset - levelW, 8) * one)
                fsName:SetJustifyH(justify)
            end
        end
        Place("left", slots.left)
        Place("centre", slots.centre)
        Place("right", slots.right)

        fsName:SetShown(nameOn)
        fsLevel:SetShown(levelOn)
        if fsHealth then fsHealth:SetShown(healthOn) end
        f._slotName, f._slotLevel = nameOn, levelOn
    end,

    Events = function(cfg)
        local _, owner = ns.TextSlots(cfg)
        if not (owner.name or owner.level) then return nil end
        return { "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CLASSIFICATION_CHANGED" }
    end,

    SetUnit = function(f)
        if f._slotLevel then SetLevel(f) end
        if not f._slotName then return end
        local ok, name = pcall(UnitName, f.unit)
        if not ok or type(name) == "nil" then f.nameText:SetText(""); return end
        pcall(f.nameText.SetFormattedText, f.nameText, "%s", name)
    end,
}
ns.eventHandlers.UNIT_NAME_UPDATE = function(f) ns.ForEachWidget("SetUnit", f) end
ns.eventHandlers.UNIT_LEVEL = ns.eventHandlers.UNIT_NAME_UPDATE
ns.eventHandlers.UNIT_CLASSIFICATION_CHANGED = ns.eventHandlers.UNIT_NAME_UPDATE

--------------------------------------------------------------------------------
--  Target, focus and the non-target fade
--------------------------------------------------------------------------------
-- Pooled frames, so these have to be dropped on release or a recycled frame
-- keeps a stale "was the target" identity.
local lastTarget, lastFocus

function ns.ForgetPlate(f)
    if lastTarget == f then lastTarget = nil end
    if lastFocus == f then lastFocus = nil end
end

--- Target and focus, without ever asking Lua which one it is.
---
--- UnitIsUnit is SecretWhenUnitComparisonRestricted (UnitDocumentation.lua
--- :2410-2414), so in restricted content the answer is a secret boolean and
--- `isTarget and x or y` throws. This function used to do that five times.
---
--- The engine gives us exactly three folds for a secret boolean, and no more:
---   Region:SetVertexColorFromBoolean(b, ifTrue, ifFalse)   SimpleRegionAPI:205
---   Region:SetAlphaFromBoolean(b, ifTrue, ifFalse)         SimpleRegionAPI:133
---   Frame:SetAlphaFromBoolean(b, ifTrue, ifFalse)          SimpleFrameAPI:1144
---
--- Colour and alpha are therefore expressible and SCALE IS NOT: there is no
--- SetScaleFromBoolean. So under restriction the target keeps its border and
--- its opacity and loses its size bump, and that is not a shortcut, it is the
--- whole of what the API offers. Blizzard's own nameplate has the same limit
--- and does the same thing -- UpdateIsTarget only recolours
--- (Blizzard_NamePlateUnitFrame.lua:399-410).
---
--- Out of restricted content the value is a plain boolean and everything
--- works, scale included. One code path, two fidelities.
--------------------------------------------------------------------------------
--  Halo: the aggro glow's construction, shared with the target
--
--  Blizzard's eight piece GlowBorder set (Blizzard_HelpPlate.xml:486-538),
--  ADD blended because the art carries the glow over a black field. See the
--  aggro widget below for why each of those choices was made.
--------------------------------------------------------------------------------
local function BuildHalo()
    -- DESATURATED. The GlowBorder art is gold (it is the help plate glow),
    -- and a vertex colour only multiplies it, so tinting it white left it
    -- yellow. Greyscale first, then the tint is the colour you see.
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:EnableMouse(false)
    panel:Hide()
    local C = "Interface\\Common\\GlowBorder-Corner"
    local H = "Interface\\Common\\GlowBorder-Top"
    local V = "Interface\\Common\\GlowBorder-Left"
    local function Piece(file, l, r, t, b)
        local tex = panel:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(file)
        tex:SetBlendMode("ADD")
        tex:SetTexCoord(l, r, t, b)
        if tex.SetDesaturated then tex:SetDesaturated(true) end
        EV.Pixel.NoSnap(tex)
        return tex
    end
    panel.glow = {
        tl = Piece(C, 0, 1, 0, 1), tr = Piece(C, 1, 0, 0, 1),
        bl = Piece(C, 0, 1, 1, 0), br = Piece(C, 1, 0, 1, 0),
        top = Piece(H, 0, 1, 0, 1), bottom = Piece(H, 0, 1, 1, 0),
        left = Piece(V, 0, 1, 0, 1), right = Piece(V, 1, 0, 0, 1),
    }
    return panel
end

local function LayoutHalo(panel, f, cfg, r, g, b, a)
    local gl = panel and panel.glow
    if not gl then return end
    local one = EV.Pixel:One(f)
    local pad = one * (cfg.aggroPad or 8)
    local bottom = (f.power and cfg.showPower) and f.power or f.health
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)
    for _, tex in pairs(gl) do tex:SetVertexColor(r, g, b, a) end
    local size = pad * 2
    gl.tl:ClearAllPoints(); gl.tl:SetSize(size, size); gl.tl:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
    gl.tr:ClearAllPoints(); gl.tr:SetSize(size, size); gl.tr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", pad, pad)
    gl.bl:ClearAllPoints(); gl.bl:SetSize(size, size); gl.bl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -pad, -pad)
    gl.br:ClearAllPoints(); gl.br:SetSize(size, size); gl.br:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)
    gl.top:ClearAllPoints();    gl.top:SetPoint("TOPLEFT", gl.tl, "TOPRIGHT");     gl.top:SetPoint("BOTTOMRIGHT", gl.tr, "BOTTOMLEFT")
    gl.bottom:ClearAllPoints(); gl.bottom:SetPoint("TOPLEFT", gl.bl, "TOPRIGHT");  gl.bottom:SetPoint("BOTTOMRIGHT", gl.br, "BOTTOMLEFT")
    gl.left:ClearAllPoints();   gl.left:SetPoint("TOPLEFT", gl.tl, "BOTTOMLEFT");  gl.left:SetPoint("BOTTOMRIGHT", gl.bl, "TOPRIGHT")
    gl.right:ClearAllPoints();  gl.right:SetPoint("TOPLEFT", gl.tr, "BOTTOMLEFT");  gl.right:SetPoint("BOTTOMRIGHT", gl.br, "TOPRIGHT")
    ns.RoundLayout(panel)
end

-- Light, cool white: pure white added over snow and sky clips flat, a touch
-- of blue keeps the halo reading as light rather than as a hole.
local HALO_R, HALO_G, HALO_B = 0.94, 0.97, 1

local TARGET_EDGE = CreateColor(1, 1, 1, 1)
local FOCUS_EDGE  = CreateColor(0, 0.812, 1, 1)
local PLAIN_EDGE  = CreateColor(0, 0, 0, 1)

local function ApplyTarget(f)
    if not f.unit then return end
    local cfg = ns.module.db
    local okT, isTarget = pcall(UnitIsUnit, f.unit, "target")
    local okF, isFocus = pcall(UnitIsUnit, f.unit, "focus")
    if not okT then return end
    if not okF then isFocus = false end
    local secret = ns.IsSecret(isTarget) or ns.IsSecret(isFocus)

    local border = cfg.targetBorder and f.plateBorder
    -- With the halo marking the target, the target's border is just a border.
    local targetEdge = cfg.targetHalo and PLAIN_EDGE or TARGET_EDGE
    local halo = cfg.targetHalo and f.targetHalo

    if secret then
        if halo then
            halo:Show()
            pcall(halo.SetAlphaFromBoolean, halo, isTarget, 1, 0)
        elseif f.targetHalo then
            f.targetHalo:Hide()
        end
        -- Folded C-side. Focus first, then target on top, so a unit that is
        -- both ends up white: each call overwrites the last, and the target
        -- is the one you want to see.
        if border then
            f._border = nil
            for i = 1, 4 do
                local e = border.edges[i]
                pcall(e.SetVertexColorFromBoolean, e, isFocus, FOCUS_EDGE, PLAIN_EDGE)
                pcall(e.SetVertexColorFromBoolean, e, isTarget, targetEdge, PLAIN_EDGE)
            end
        end
        if f.glow and cfg.showTargetGlow then
            f.glow:Show()
            pcall(f.glow.SetAlphaFromBoolean, f.glow, isTarget, 0.75, 0)
        elseif f.glow then
            f.glow:Hide()
        end
        if cfg.nonTargetAlpha < 1 then
            f._alpha = nil
            pcall(f.SetAlphaFromBoolean, f, isTarget, 1, cfg.nonTargetAlpha)
        end
        return
    end

    if f.targetHalo then
        f.targetHalo:SetAlpha(1)
        f.targetHalo:SetShown(halo and isTarget and true or false)
    end

    if f.glow then
        f.glow:SetShown(cfg.showTargetGlow and (isTarget or isFocus))
        if isFocus and not isTarget then
            f.glow:SetVertexColor(0, 0.812, 1, 0.75)
        else
            f.glow:SetVertexColor(0, 0.522, 1, 0.75)
        end
    end

    -- Scaling is a RELAYOUT, not a SetScale. Everything on this plate was
    -- snapped against the old effective scale, so changing the scale on its
    -- own leaves every hairline a fraction of a pixel thick. ns.Layout sets
    -- the scale and then snaps to it, which is the only order that works.
    local scale = isTarget and cfg.targetScale or 1
    if f._scale ~= scale then ns.Layout(f) end

    -- The border, not the bar. AFTER the relayout above, because Health's own
    -- layout repaints this border black on the way past.
    if border then
        local key = isTarget and 2 or (isFocus and 1 or 0)
        if f._border ~= key then
            f._border = key
            local c = isTarget and targetEdge or (isFocus and FOCUS_EDGE or PLAIN_EDGE)
            for i = 1, 4 do border.edges[i]:SetColorTexture(c.r, c.g, c.b, 1) end
        end
    end

    local okE, hasTarget = pcall(UnitExists, "target")
    local alpha = ((not okE or not hasTarget) or isTarget) and 1 or cfg.nonTargetAlpha
    if f._alpha ~= alpha then f._alpha = alpha; f:SetAlpha(alpha) end
end
ns.ApplyTarget = ApplyTarget

ns.Widget{
    name = "target",

    --- The target cue is a soft glow UNDER the plate, not a border: near the
    --- full plate width, in (0, 0.522, 1) blue, on the lowest layer so it
    --- sits behind everything. A glow
    --- below reads instantly in a pack without thickening the plate itself.
    Build = function(f)
        local g = f:CreateTexture(nil, "BACKGROUND", nil, -7)
        g:SetTexture("Interface\\Buttons\\WHITE8X8")
        g:SetBlendMode("ADD")
        g:Hide()
        EV.Pixel.NoSnap(g)
        f.glow = g
        f.targetHalo = BuildHalo()
        -- The gate: an empty frame between the target halo and the plate,
        -- whose alpha is the INVERSE of aggro. Alpha multiplies down the
        -- parent chain, so the halo shows only when targeted AND not on you.
        -- Both glows are ADD blended, so draw order cannot put one "above"
        -- the other -- they would just sum to pink. Hiding the white one is
        -- the only way for red to win, and this does it C-side, because the
        -- two answers are secret booleans we are not allowed to AND in Lua.
        local gate = CreateFrame("Frame", nil, UIParent)
        gate:EnableMouse(false)
        f.targetGate = gate
    end,

    -- An underline rather than a border: a glow ring around a plate fights
    -- the plate's own border at every scale, and the underline reads at a
    -- glance in a pack, which is the only moment it matters.
    Layout = function(f, cfg)
        f.glow:ClearAllPoints()
        f.glow:SetPoint("TOP", f.health, "BOTTOM", 0, 1)
        EV.Pixel:SetSize(f.glow, cfg.width * 0.99, math.max(cfg.height * 0.54, 3))
        LayoutHalo(f.targetHalo, f, cfg, HALO_R, HALO_G, HALO_B, cfg.targetHaloAlpha or 0.55)
        -- Forget the cached border key: Health.lua repaints the border black
        -- on a layout pass, so the colour we think is on it is not there any
        -- more. _scale is NOT cleared here -- Core's Layout owns it and sets
        -- it after every widget has run, and clearing it would make the next
        -- ApplyTarget relayout all over again.
        f._alpha, f._border = nil, nil
    end,

    SetUnit = function(f)
        -- Same parent and level as the aggro halo: Blizzard's plate, one
        -- below our frame, so it translates with the bar and draws behind it.
        local h, gate, under = f.targetHalo, f.targetGate, f.plate
        if h and gate and under then
            gate:SetParent(under)
            gate:SetFrameLevel(under:GetFrameLevel() or 0)
            gate:Show()
            h:SetParent(gate)
            h:SetFrameLevel(under:GetFrameLevel() or 0)
        end
        ApplyTarget(f)
    end,

    Clear = function(f)
        f._scale, f._alpha, f._border = nil, nil, nil  -- released: forget everything
        if f.targetHalo then
            f.targetHalo:Hide()
            f.targetHalo:ClearAllPoints()
        end
        if f.targetGate then
            f.targetGate:SetAlpha(1)
            f.targetGate:SetParent(UIParent)
        end
    end,

    Enable = function(M)
        M:RegisterEvent("PLAYER_TARGET_CHANGED", function()
            local cfg = ns.module.db

            -- "target" is not a nameplate token, so find the plate whose own
            -- token IS the target. Under restriction we cannot: the answer is
            -- a secret boolean and comparing it throws. Then there is nothing
            -- to find and every plate re-folds its own answer instead, which
            -- is the same sweep the fade already does.
            local now, anySecret
            for unit, f in pairs(ns.plates) do
                local isT, secret = ns.IsUnit(unit, "target")
                if secret then anySecret = true break end
                if isT then now = f break end
            end

            if anySecret then
                for _, f in pairs(ns.plates) do ns.Safe("target", ApplyTarget, f) end
                lastTarget = nil
                return
            end

            -- Only two plates can have changed their answer: the one losing
            -- the target and the one gaining it.
            if lastTarget and lastTarget ~= now and lastTarget.unit
               and ns.plates[lastTarget.unit] == lastTarget then
                ns.Safe("target", ApplyTarget, lastTarget)
            end
            if now then ns.Safe("target", ApplyTarget, now) end
            lastTarget = now

            -- The one genuine full sweep: gaining or losing a target flips
            -- every other plate's fade. Zero cost while the setting is off.
            if cfg.nonTargetAlpha < 1 then
                for _, f in pairs(ns.plates) do
                    if f ~= now then ns.Safe("fade", ApplyTarget, f) end
                end
            end
        end)

        M:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
            local now, anySecret
            for unit, f in pairs(ns.plates) do
                local isF, secret = ns.IsUnit(unit, "focus")
                if secret then anySecret = true break end
                if isF then now = f break end
            end
            if anySecret then
                for _, f in pairs(ns.plates) do ns.Safe("focus", ApplyTarget, f) end
                lastFocus = nil
                return
            end
            for _, f in ipairs({ lastFocus, now }) do
                if f and f.unit and ns.plates[f.unit] == f then ns.Safe("focus", ApplyTarget, f) end
            end
            lastFocus = now
        end)
    end,
}

--------------------------------------------------------------------------------
--  Aggro backdrop
--
--  A red panel behind the plate, padded out beyond it, shown when the mob is
--  attacking YOU. This is the one threat feature that survives restriction
--  cleanly, and the reason is worth stating.
--
--  UnitThreatSituation returns a NUMBER and is SecretWhenUnitThreatStateRestricted
--  (UnitDocumentation.lua:3277), and there is no fold from a secret number.
--  UnitDetailedThreatSituation's first return is isTanking, a secret BOOLEAN
--  (:1086-1100), and booleans are exactly what the engine will fold for us:
--
--      Frame:SetAlphaFromBoolean(value, alphaIfTrue, alphaIfFalse)
--      SimpleFrameAPIDocumentation.lua:1144, SecretArguments AllowedWhenTainted
--
--  So the panel is always shown and its ALPHA carries the answer, decided
--  C-side. Nothing in Lua ever learns whether you have aggro, which is the
--  only way this can work in a dungeon.
--
--  It is parented to Blizzard's base plate rather than to ours, one frame
--  level below, because a child frame draws above its parent's regions and a
--  backdrop that covers the health bar is not a backdrop.
--------------------------------------------------------------------------------
local function ApplyAggro(f)
    local panel = f.aggro
    if not panel then return end
    local gate = f.targetGate
    local cfg = ns.module.db
    if not (cfg.aggroBackdrop and f.unit) then
        panel:Hide(); if gate then gate:SetAlpha(1) end; return
    end

    local ok, isTanking = pcall(UnitDetailedThreatSituation, "player", f.unit)
    if not ok or type(isTanking) == "nil" then
        panel:Hide(); if gate then gate:SetAlpha(1) end; return
    end

    panel:Show()
    if ns.IsSecret(isTanking) then
        -- Folded. Never compared. The gate takes the opposite fold, so the
        -- white target halo steps aside whenever the red one is lit.
        pcall(panel.SetAlphaFromBoolean, panel, isTanking, 1, 0)
        if gate then pcall(gate.SetAlphaFromBoolean, gate, isTanking, 0, 1) end
    else
        panel:SetAlpha(isTanking == true and 1 or 0)
        if gate then gate:SetAlpha(isTanking == true and 0 or 1) end
    end
end

ns.Widget{
    name = "aggro",

    Build = function(f)
        -- A GLOW, using Blizzard's own glow art.
        --
        -- A bordered rectangle reads as a hard red box. Four gradient strips
        -- give a soft ramp on each edge but are still a rectangle, because two ramps meeting at a corner
        -- make a corner. Blizzard ship the eight piece set that solves this:
        -- Interface\Common\GlowBorder-Corner, -Top and -Left, laid out in
        -- Blizzard_HelpPlate.xml:486-538 as four 16x16 corners overhanging by
        -- 8 with the edges stretched between them. That is a real halo, it
        -- rounds off, and it tints with SetVertexColor.
        --
        -- ADD, because the art requires it. BLEND looks tempting (red added to
        -- snow clips to white), but these glow
        -- textures carry the glow in RGB over a BLACK field, so under BLEND
        -- the black field paints and the plate grows a dark halo. Blizzard
        -- set alphaMode="ADD" on every one of the eight pieces
        -- (Blizzard_HelpPlate.xml:486-538) for exactly that reason. Black
        -- adds nothing; only the glow lands.
        local panel = CreateFrame("Frame", nil, UIParent)
        panel:EnableMouse(false)
        panel:Hide()
        local C = "Interface\\Common\\GlowBorder-Corner"
        local H = "Interface\\Common\\GlowBorder-Top"
        local V = "Interface\\Common\\GlowBorder-Left"
        local function Piece(file, l, r, t, b)
            local tex = panel:CreateTexture(nil, "BACKGROUND")
            tex:SetTexture(file)
            tex:SetBlendMode("ADD")
            tex:SetTexCoord(l, r, t, b)
            EV.Pixel.NoSnap(tex)
            return tex
        end
        panel.glow = {
            tl = Piece(C, 0, 1, 0, 1),
            tr = Piece(C, 1, 0, 0, 1),
            bl = Piece(C, 0, 1, 1, 0),
            br = Piece(C, 1, 0, 1, 0),
            top    = Piece(H, 0, 1, 0, 1),
            bottom = Piece(H, 0, 1, 1, 0),
            left   = Piece(V, 0, 1, 0, 1),
            right  = Piece(V, 1, 0, 0, 1),
        }
        f.aggro = panel
    end,

    Layout = function(f, cfg)
        local panel = f.aggro
        if not panel then return end
        local g = panel.glow
        if not g then return end
        local one = EV.Pixel:One(f)
        local pad = one * (cfg.aggroPad or 8)

        -- The panel hugs the plate, and its bottom edge is the power strip's
        -- rather than the cast bar's. Anchored to the FRAME, not to a sum of
        -- heights, because the strip collapses to nothing for a unit with no
        -- resource and the glow then closes up on its own.
        --
        -- Deliberately not the cast bar. That bar is laid out whether or not
        -- anything is casting, so anchoring to it would leave the glow
        -- reaching fourteen pixels past the plate into empty space on every
        -- mob standing still.
        local bottom = (f.power and cfg.showPower) and f.power or f.health
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", f.health, "TOPLEFT", 0, 0)
        panel:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 0, 0)

        local a = cfg.aggroAlpha or 0.35
        for _, tex in pairs(g) do
            tex:SetVertexColor(0.95, 0.1, 0.1, a)
        end

        -- Blizzard's proportions: a corner twice the overhang, edges spanning
        -- between the corners (Blizzard_HelpPlate.xml:486-538).
        local size = pad * 2
        g.tl:ClearAllPoints(); g.tl:SetSize(size, size)
        g.tl:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
        g.tr:ClearAllPoints(); g.tr:SetSize(size, size)
        g.tr:SetPoint("TOPRIGHT", panel, "TOPRIGHT", pad, pad)
        g.bl:ClearAllPoints(); g.bl:SetSize(size, size)
        g.bl:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -pad, -pad)
        g.br:ClearAllPoints(); g.br:SetSize(size, size)
        g.br:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)

        g.top:ClearAllPoints()
        g.top:SetPoint("TOPLEFT", g.tl, "TOPRIGHT")
        g.top:SetPoint("BOTTOMRIGHT", g.tr, "BOTTOMLEFT")
        g.bottom:ClearAllPoints()
        g.bottom:SetPoint("TOPLEFT", g.bl, "TOPRIGHT")
        g.bottom:SetPoint("BOTTOMRIGHT", g.br, "BOTTOMLEFT")
        g.left:ClearAllPoints()
        g.left:SetPoint("TOPLEFT", g.tl, "BOTTOMLEFT")
        g.left:SetPoint("BOTTOMRIGHT", g.bl, "TOPRIGHT")
        g.right:ClearAllPoints()
        g.right:SetPoint("TOPLEFT", g.tr, "BOTTOMLEFT")
        g.right:SetPoint("BOTTOMRIGHT", g.br, "TOPRIGHT")

        ns.RoundLayout(panel)
    end,

    SetUnit = function(f)
        local panel = f.aggro
        if not panel then return end
        -- Blizzard's plate, the same frame our root is centred on, so the
        -- glow and the bar translate together. Its level is the plate's,
        -- one below ours, so the glow still draws behind the bar.
        local under = f.plate
        if under then
            panel:SetParent(under)
            panel:SetFrameLevel(under:GetFrameLevel() or 0)
        end
        ApplyAggro(f)
    end,

    Clear = function(f)
        if f.aggro then
            f.aggro:Hide()
            f.aggro:ClearAllPoints()
            f.aggro:SetParent(UIParent)
        end
    end,

    -- UNIT_THREAT_LIST_UPDATE carries the MOB whose list changed, which for
    -- this widget is the plate's own unit, so unlike the colour rules it can
    -- be routed by token.
    Events = function(cfg)
        if not cfg.aggroBackdrop then return nil end
        return { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }
    end,
}
-- CHAINED, not replaced. Health.lua already owns these two for the colour
-- rules, and this file loads after it, so assigning over the top would have
-- silently taken threat recolouring with it. ns.eventHandlers is a single
-- table keyed by event, which makes that an easy mistake and a quiet one.
for _, e in ipairs({ "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" }) do
    local prev = ns.eventHandlers[e]
    ns.eventHandlers[e] = function(f, ...)
        if prev then prev(f, ...) end
        ns.Safe("aggro", ApplyAggro, f)
    end
end

--------------------------------------------------------------------------------
--  Quest objectives
--
--  "Three of the five I need are in this pack" is the one thing a nameplate
--  can tell you that the quest log cannot, and the game exposes it in exactly
--  one place: the unit tooltip. There is no C_QuestLog call that answers
--  "does killing THIS mob count", because the answer lives in the objective
--  text the server builds per unit.
--
--  So we read the tooltip data, which is what every addon that does this
--  reads. The line
--  types are QuestTitle, QuestPlayer and QuestObjective; QuestPlayer names
--  whose objective the following lines belong to, which is how a party
--  member's quest gets skipped.
--
--  Two things make it cheap enough to do per plate. It is read ONCE per unit
--  and cached, dropped when the plate goes; and it is read in Late, off the
--  spawn tick, because a quest count one frame after the plate appears is a
--  quest count nobody noticed was late.
--------------------------------------------------------------------------------
local questCache = {}
local QUEST_LINES = {
    [(Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or 8]  = "objective",
    [(Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestTitle) or 17]     = "title",
    [(Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestPlayer) or 18]    = "player",
}

local function ReadQuest(unit)
    if type(C_TooltipInfo) ~= "table" or type(C_TooltipInfo.GetUnit) ~= "function" then return "" end
    -- A unit whose identity is secret has no readable tooltip, and asking is
    -- how you get an error rather than an empty string.
    if C_Secrets and type(C_Secrets.ShouldUnitIdentityBeSecret) == "function" then
        local okS, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
        if okS and secret == true then return "" end
    end

    local ok, info = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(info) ~= "table" or type(info.lines) ~= "table" then return "" end

    local me = UnitName("player")
    local skip, parts = false, nil
    for _, line in ipairs(info.lines) do
        local kind = QUEST_LINES[line.type]
        if kind == "player" then
            -- Somebody else's progress on the same quest. Their numbers are
            -- not ours, so everything under their name is skipped.
            skip = (line.leftText ~= me)
        elseif kind == "title" then
            skip = false
        elseif kind == "objective" and not skip then
            local text = line.leftText
            if type(text) == "string" then
                local have, need = text:match("(%d+)%s*/%s*(%d+)")
                if have and have ~= need then
                    parts = parts or {}
                    parts[#parts + 1] = have .. "/" .. need
                else
                    local pct = text:match("(%d+)%%")
                    if pct and pct ~= "100" then
                        parts = parts or {}
                        parts[#parts + 1] = pct .. "%"
                    end
                end
            end
        end
    end
    return parts and table.concat(parts, " ") or ""
end

local function SetQuest(f)
    local fs = f.questText
    if not fs then return end
    if not ns.module.db.showQuest or not f.unit then fs:SetText(""); return end
    -- Keyed on the GUID ONLY. Falling back to the unit token looked
    -- harmless and is not: a token is recycled, Clear only evicts by GUID, so
    -- the entry outlives the plate and the next mob on "nameplate3" inherits
    -- the last one's quest count for the rest of the session.
    local guid = f.guid
    local text
    if guid then
        text = questCache[guid]
        if text == nil then
            text = ReadQuest(f.unit)
            questCache[guid] = text
        end
    else
        text = ReadQuest(f.unit)
    end
    fs:SetText(text)
end

ns.Widget{
    name = "quest",

    Build = function(f)
        local fs = f.overlay:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("RIGHT")
        fs:SetWordWrap(false)
        f.questText = fs
    end,

    -- Top right, above the plate, on the same line as the debuff row. The
    -- debuff row grows from the left and wraps short of this (see Auras.lua),
    -- so a full six dots and a quest count do not sit on top of each other.
    Layout = function(f, cfg)
        local fs = f.questText
        ns.SetText(fs, cfg.fontSize, true)
        fs:SetTextColor(1, 0.82, 0)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOMRIGHT", f.health, "TOPRIGHT", 0, 3)
        fs:SetShown(cfg.showQuest)
        -- Restyle runs Layout and SetUnit, never Late, so a plate already on
        -- screen would show an empty slot until the next QUEST_LOG_UPDATE.
        -- ns.active is set after Layout on the spawn path and before it on the
        -- restyle path, which is how the auras widget tells them apart too.
        if ns.active[f] then SetQuest(f) end
    end,

    -- Late, not SetUnit: reading a tooltip is the most expensive thing this
    -- module does per plate and it is never urgent.
    Late = SetQuest,

    Clear = function(f)
        if f.questText then f.questText:SetText("") end
        -- A GUID is per spawn, not per creature, so an entry left behind is
        -- one that can never be hit again. Over a dungeon that is thousands.
        if f.guid then questCache[f.guid] = nil end
    end,

    Enable = function(M)
        -- The cache is per GUID and only these can change what it holds.
        local function Refresh()
            wipe(questCache)
            if not ns.module.db.showQuest then return end
            for _, f in pairs(ns.plates) do ns.Safe("quest", SetQuest, f) end
        end
        M:RegisterEvent("QUEST_LOG_UPDATE", Refresh)
        M:RegisterEvent("QUEST_ACCEPTED", Refresh)
        M:RegisterEvent("QUEST_REMOVED", Refresh)
        M:RegisterEvent("UNIT_QUEST_LOG_CHANGED", Refresh)
    end,
}

--------------------------------------------------------------------------------
--  Raid target marker
--------------------------------------------------------------------------------
--- GetRaidTargetIndex is SecretReturns = true: the index is ALWAYS secret,
--- unconditionally, so `index > 0` throws and `type(index) == "number"` is
--- true for a secret number, which is exactly how the old version got past
--- its own guard and into the compare.
---
--- There are two things to do with the index and neither of them is a
--- comparison. The nil test is `type(index) == "nil"`, because a unit with no
--- marker returns a real nil rather than a secret, and that is the only
--- question we need answered in Lua. The index itself goes straight to
--- Texture:SetSpriteSheetCell, which is SecretArguments = "AllowedWhenTainted"
--- and picks the cell C-side. That is the same call Blizzard's own
--- SetRaidTargetIconTexture makes (TargetFrame.lua:685); we inline it only
--- because that helper is a plain Lua global and we want the pcall around the
--- method itself.
local RAID_ROWS, RAID_COLS = 4, 4
local function Mark(f)
    local t = f.raidMark
    if not t then return end
    local ok, index = pcall(GetRaidTargetIndex, f.unit)
    if ok and type(index) ~= "nil" then
        if pcall(t.SetSpriteSheetCell, t, index,
                 RAID_TARGET_TEXTURE_ROWS or RAID_ROWS,
                 RAID_TARGET_TEXTURE_COLUMNS or RAID_COLS) then
            t:Show()
            return
        end
    end
    t:Hide()
end

ns.Widget{
    name = "raidMark",

    Build = function(f)
        local t = f.overlay:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        t:Hide()
        f.raidMark = t
    end,

    Layout = function(f, cfg)
        f.raidMark:ClearAllPoints()
        f.raidMark:SetPoint("RIGHT", f.health, "LEFT", -4, 0)
        EV.Pixel:SetSize(f.raidMark, cfg.height + 4, cfg.height + 4)
    end,

    SetUnit = function(f) Mark(f) end,

    Clear = function(f) f.raidMark:Hide() end,

    Enable = function(M)
        M:RegisterEvent("RAID_TARGET_UPDATE", function()
            for _, f in pairs(ns.plates) do ns.Safe("raidmark", Mark, f) end
        end)
    end,
}

--------------------------------------------------------------------------------
--  Execute glow
--------------------------------------------------------------------------------
local lowCurve, curveAt

local function Curve(threshold)
    if not (C_CurveUtil and type(C_CurveUtil.CreateCurve) == "function") then return nil end
    if lowCurve and curveAt == threshold then return lowCurve end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not ok or not c then return nil end
    pcall(c.SetType, c, Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear)
    -- Red below the threshold, black above it. Black contributes nothing
    -- under an ADD blend, which is how "hidden" is expressed without a
    -- branch. Alpha is never varied; only RGB.
    pcall(c.AddPoint, c, 0.0, 1.0)
    pcall(c.AddPoint, c, threshold, 1.0)
    pcall(c.AddPoint, c, threshold + 0.0001, 0.0)
    pcall(c.AddPoint, c, 1.0, 0.0)
    lowCurve, curveAt = c, threshold
    return c
end

ns.Widget{
    name = "execute",

    Build = function(f)
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:SetBlendMode("ADD")
        t:Hide()
        EV.Pixel.NoSnap(t)
        f.execute = t
    end,

    Layout = function(f, cfg)
        f.execute:ClearAllPoints()
        f.execute:SetAllPoints(f.health)
        f.execute:SetShown(cfg.executeGlow)
        if not f._executeAnim and cfg.executeGlow then
            local g = f.execute:CreateAnimationGroup()
            g:SetLooping("BOUNCE")
            local a = g:CreateAnimation("Alpha")
            a:SetFromAlpha(0.15); a:SetToAlpha(0.45); a:SetDuration(0.6)
            f._executeAnim = g
        end
        if f._executeAnim then
            if cfg.executeGlow then f._executeAnim:Play() else f._executeAnim:Stop() end
        end
    end,

    -- No Events: UNIT_HEALTH is already registered and already coalesced,
    -- so this rides the health paint instead of registering it twice.
    Health = function(f)
        local cfg = ns.module.db
        if not cfg.executeGlow then return end
        local curve = Curve(cfg.executeAt)
        if not (curve and type(UnitHealthPercent) == "function") then return end
        local ok, v = pcall(UnitHealthPercent, f.unit, true, curve)
        if not ok or type(v) == "nil" then return end
        -- v may be secret. Straight into the setter: red when below the
        -- threshold, black (invisible under ADD) when above.
        pcall(f.execute.SetVertexColor, f.execute, v, 0, 0, 1)
    end,

    SetUnit = function(f)
        local w = ns.widgets
        for i = 1, #w do
            if w[i].name == "execute" then w[i].Health(f) return end
        end
    end,
}
