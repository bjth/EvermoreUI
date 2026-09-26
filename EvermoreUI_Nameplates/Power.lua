if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Power.lua
--  The mob's power bar: a thin strip under the health bar, shown only for
--  units that actually have the resource.
--
--  Why this exists at all. The rule for telling a caster from a melee mob
--  is the game's own: there is no "is this a caster"
--  flag, so everyone infers it from whether the mob has mana. Colouring the
--  health bar on that inference is one way to say it; SHOWING the mana is the
--  other, and it is the honest one, because the bar is only there when the
--  resource is and it also tells you how much of it is left.
--
--  Blizzard do not draw this on mainline nameplates -- their nameplate mana
--  bar (Blizzard_ClassNameplateBar.lua:126) is the PLAYER's personal resource
--  and nothing else -- so the colour is taken from the same place theirs is
--  and the rest is built on the health bar's machinery.
--
--  Secret values. UnitPower is SecretWhenUnitPowerRestricted and UnitPowerMax
--  is SecretWhenUnitPowerMaxRestricted (UnitDocumentation.lua:2732, :2801), so
--  neither number may be compared or divided. They go straight to SetValue and
--  SetMinMaxValues, exactly as health does. The two calls that decide whether
--  the bar exists at all -- UnitPowerType and UnitHasPowerType (:2859, :1411)
--  -- carry no secret marker whatsoever, so the visibility test is plain Lua
--  and stays correct inside a dungeon.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

--------------------------------------------------------------------------------
--  Which resource, and does this unit have it
--------------------------------------------------------------------------------
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0

--- Two spellings of the same question, same as Colours.lua: UnitHasPowerType
--- is the newer call and not every build carries it.
local HasPower
if type(UnitHasPowerType) == "function" then
    HasPower = function(unit, t) return UnitHasPowerType(unit, t) end
else
    HasPower = function(unit, t) return UnitPowerType(unit) == t end
end

--- The power type to draw, or nil for "draw nothing".
---
--- In "mana" mode this is the caster test and nothing else: a wolf has rage
--- and a totem has none, and neither should grow a bar. In "any" mode we take
--- whatever the unit's display power is, which is what a unit frame does.
local function WantedPower(unit, mode)
    if mode == "any" then
        local ok, powerType, token, r, g, b = pcall(UnitPowerType, unit)
        -- MayReturnNothing: a unit with no power at all returns nothing.
        if not ok or type(powerType) ~= "number" then return nil end
        local okH, has = pcall(HasPower, unit, powerType)
        if not okH or has ~= true then return nil end
        return powerType, token, r, g, b
    end
    local ok, has = pcall(HasPower, unit, MANA)
    if not ok or has ~= true then return nil end
    return MANA, "MANA"
end

--- The suite's power colours (Core/Palette.lua, EV.Palette.POWER), the same
--- ones the unit frames use, shaded by this module's barShade exactly as the
--- health bar is. So a caster's mana on its plate and on the target frame is
--- one colour.
---
--- This replaces Blizzard's nameplate mana override (0.1, 0.25, 1.0,
--- Blizzard_ClassNameplateBar.lua:128), which existed because their unit
--- frame blue is too dark at plate size. Ours was chosen with that in mind:
--- palette mana at 0.75 measures 3.01:1 against the bar background against
--- the old override's 3.07:1, so the strip reads the same weight.
---
--- Anything outside our five falls back to Blizzard's colour (or the unit's
--- own alternate colour), shaded the same way. All of these are constants
--- or plain values; a secret component is skipped rather than multiplied.
local PAL = EV.Palette

local function PowerColour(powerType, token, r, g, b)
    local shade = PAL.ValidShade(ns.module and ns.module.db and ns.module.db.barShade)
    local src = token and PAL.POWER[token]
    if not src then
        local info = PowerBarColor and ((token and PowerBarColor[token]) or PowerBarColor[powerType])
        if info and type(info.r) == "number" and not ns.IsSecret(info.r) then
            src = { info.r, info.g, info.b }
        elseif type(r) == "number" and not (ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b)) then
            src = { r, g, b }
        else
            src = PAL.POWER.MANA
        end
    end
    return src[1] * shade, src[2] * shade, src[3] * shade
end

--------------------------------------------------------------------------------
--  Collapsing
--
--  The strip is always anchored under the plate and everything below it -- the
--  cast bar, the aggro glow -- anchors to the STRIP rather than to the plate
--  plus a number. When the unit has no resource the strip collapses: zero
--  height, zero gap, so its bottom edge is the plate's bottom edge and the
--  things below it close up against the plate on their own. That is what
--  keeps a wolf from carrying a six pixel hole where a caster's mana goes.
--------------------------------------------------------------------------------
local function SetStrip(f, cfg, on)
    local bar = f.power
    if not bar then return end
    local gap = on and (cfg.powerGap or 0) or 0
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", f.health, "BOTTOMLEFT", 0, -gap)
    bar:SetPoint("TOPRIGHT", f.health, "BOTTOMRIGHT", 0, -gap)
    -- Not zero: a frame with no height is not laid out and its anchors stop
    -- resolving, which would strand the cast bar. One hundredth of a pixel is
    -- invisible and keeps the chain intact.
    bar:SetHeight(on and cfg.powerHeight or 0.01)
    bar:SetShown(on and true or false)
end

--------------------------------------------------------------------------------
--  Painting
--------------------------------------------------------------------------------
local function Paint(f)
    local bar, unit = f.power, f.unit
    if not (bar and unit) then return end
    if not f._powerType then return end
    if not f._powerMaxValid then
        local ok, maxP = pcall(UnitPowerMax, unit, f._powerType)
        if ok and type(maxP) ~= "nil" then
            bar:SetMinMaxValues(0, maxP)
            f._powerMaxValid = true
        end
    end
    local ok, cur = pcall(UnitPower, unit, f._powerType)
    -- Secret or plain, it only ever goes to the setter.
    if ok and type(cur) ~= "nil" then pcall(bar.SetValue, bar, cur) end
end
ns.PaintPower = Paint

--- Decide whether the bar exists for this unit, and in what colour. Cheap
--- enough to run on unit assignment and on UNIT_DISPLAYPOWER, which are the
--- only two moments a mob's resource can change identity.
local function Refresh(f)
    local bar, unit = f.power, f.unit
    if not bar then return end
    local cfg = ns.module.db
    if not (unit and cfg.showPower and (cfg.powerHeight or 0) > 0) then
        SetStrip(f, cfg, false)
        f._powerType, f._powerMaxValid = nil, false
        return
    end

    local powerType, token, r, g, b = WantedPower(unit, cfg.powerMode)
    if not powerType then
        SetStrip(f, cfg, false)
        f._powerType, f._powerMaxValid = nil, false
        return
    end

    f._powerType = powerType
    f._powerMaxValid = false
    bar:SetStatusBarColor(PowerColour(powerType, token, r, g, b))
    SetStrip(f, cfg, true)
    Paint(f)
end
ns.RefreshPower = Refresh

--------------------------------------------------------------------------------
--  The widget
--------------------------------------------------------------------------------
ns.Widget{
    name = "power",

    Build = function(f)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:Hide()
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        EV.Pixel.NoSnap(bar.bg)
        f.power = bar
    end,

    Layout = function(f, cfg)
        local bar = f.power
        if not bar then return end
        -- Collapsed until a unit proves it has the resource. Refresh at the
        -- foot of this function opens it back up if the current one does.
        SetStrip(f, cfg, false)
        if not (cfg.showPower and (cfg.powerHeight or 0) > 0) then
            f._powerType = nil
            return
        end

        local tex = EV.Media:Fetch("statusbar", cfg.texture)
        bar:SetStatusBarTexture(tex)
        bar.bg:SetTexture(tex)
        bar.bg:SetVertexColor(0.031, 0.031, 0.031, 0.85)

        -- ONE pixel, not the plate's borderSize. The strip is eight tall and
        -- a two pixel border top and bottom would leave four pixels of mana
        -- inside six pixels of black. The cast bar hairlines for the same
        -- reason (Cast.lua). Decoupled, like both of theirs: this rides the
        -- plate and rescales with it when it becomes your target.
        EV.Pixel:CreateBorder(bar, 1, 0, 0, 0, 1, true)

        Refresh(f)
    end,

    Events = function(cfg)
        if not (cfg.showPower and (cfg.powerHeight or 0) > 0) then return nil end
        return { "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }
    end,

    SetUnit = function(f)
        Refresh(f)
    end,

    Clear = function(f)
        -- Collapsed, not merely hidden. A hidden strip that kept its height
        -- would hand the next unit's cast bar a hole to sit under until the
        -- assignment pass caught up.
        SetStrip(f, ns.module.db, false)
        f._powerType, f._powerMaxValid = nil, false
    end,
}

ns.eventHandlers.UNIT_POWER_UPDATE   = function(f) ns.Safe("power", Paint, f) end
ns.eventHandlers.UNIT_POWER_FREQUENT = function(f) ns.Safe("power", Paint, f) end
ns.eventHandlers.UNIT_MAXPOWER       = function(f)
    f._powerMaxValid = false
    ns.Safe("power", Paint, f)
end
ns.eventHandlers.UNIT_DISPLAYPOWER   = function(f) ns.Safe("power", Refresh, f) end
