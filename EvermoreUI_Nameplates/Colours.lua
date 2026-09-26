if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Colours.lua
--  What colour is this health bar, and which events can change the answer.
--
--  Colour is DATA, not an if-chain: an ordered list of rules, walked in
--  order, first match wins. Two things fall out of that shape and both
--  matter more than the tidiness:
--
--   1. The priority ladder is visible. Every nameplate addon grows an
--      eleven-branch colour function that nobody can reason about; this one
--      you can read top to bottom.
--   2. Each rule declares the events that can invalidate it, so the plate
--      registers the UNION OF EVENTS ACROSS ONLY THE RULES IN USE. Turn
--      threat colouring off and we stop listening to UNIT_THREAT_LIST_UPDATE
--      altogether. "Off" means silence, not a boolean check per event.
--
--  Secret values: threat is SecretWhenUnitThreatStateRestricted and the detailed
--  call is SecretWhenUnitThreatValuesRestricted, so in exactly the content
--  where threat matters we cannot branch on it. Anything that might be
--  secret is folded into the colour C-side through C_CurveUtil and handed
--  STRAIGHT TO A SETTER. Never compared, never cached, never multiplied.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local T = EV.Theme

-- The framework's, not a ninth copy of it (Core/Init.lua).
local IsSecret = EV.IsSecret
ns.IsSecret = IsSecret

--------------------------------------------------------------------------------
--  Palette
--------------------------------------------------------------------------------
-- The bar rules are an ordered list and the first match wins (RULES below):
-- focus, class, tapped, target, threat, quest, elite, reaction.
--- Hostility, in the colours this game has used since 2004. Red means it
--- will attack you, yellow means it will not unless you start it, green means
--- it never will. Nobody has to learn that, which is the entire argument for
--- it: a nameplate palette is read in the first tenth of a second of a pull
--- and anything you have to decode is worse than useless.
---
--- They are also what most nameplate addons show out of the box, so nobody
--- arriving from one has to relearn them.
--- SHADING, and why it is done to the palette rather than to the bar.
---
--- White text on full red measures 4.00:1 against WCAG, which is below the
--- 4.5:1 floor for body text and only just over the 3:1 one for large text.
--- That is not a matter of taste, it is why the name was hard to read at any
--- size. Dropping the fill to 75% takes it to 6.53:1, and to 65% takes it to
--- 8.08:1, while red at 191,0,0 is still unmistakably red.
---
--- It has to be applied to the CONSTANTS, not to the colour on its way to
--- SetStatusBarColor. The threat path folds its colours C-side through
--- C_CurveUtil.EvaluateColorValueFromBoolean, so what comes back may be a
--- secret, and multiplying a secret in Lua throws. Shading the source tables
--- is plain arithmetic on our own numbers and the folds then work on values
--- that are already correct.
-- The values themselves are the suite's (Core/Palette.lua), so the target
-- frame's red is this red. Shading stays here: it is this module's setting.
local PAL = EV.Palette
local BASE_REACTION = PAL.REACTION
local REACTION = {}

--- Mob type: caster or melee. The game has no "is this a caster" flag, so
--- it is inferred from whether the mob has a mana bar.
---
--- It survives secrecy. UnitHasPowerType and UnitClassification both carry
--- SecretArguments = "AllowedWhenUntainted" and NO SecretReturns or
--- SecretWhen... flag, so their returns are plain values even in restricted
--- content and an ordinary Lua branch on them is legal.
---
--- The two colours are read off the reference screenshots and the assignment
--- comes from the mobs in them: every plate on a "Cursed Thunderer" casting
--- Lightning Bolt is magenta, and the one "Cursed Rookguard" is salmon while
--- the three "Cursed Rooktender" casters beside it are magenta. So magenta is
--- the caster colour and it is also the colour of the whole look.
local TYPE_COLOUR = PAL.TYPE           -- caster magenta, melee salmon

local TARGET_COLOUR = PAL.TARGET       -- light blue
local FOCUS_COLOUR  = PAL.FOCUS        -- cyan

-- Threat, named for what each state MEANS rather than what it looks like.
-- One set, read through your role, so "warning" is whichever state is bad
-- for you: holding aggro as a dps, losing it as a tank.
--- Threat, in four colours. There are only ever three things a
--- threat colour has to say -- this is fine, this is slipping, this is wrong --
--- plus one for "another tank has it, leave it alone". Blue for fine, amber
--- for slipping, red for wrong, teal for the off-tank.
---
--- The same four colours mean opposite things to a tank and to everybody
--- else, which is why there are two sets rather than one: holding a mob is
--- the safe state for a tank and the alarm for a dps.
local BASE_SAFE       = PAL.THREAT.safe         -- periwinkle
local BASE_TRANSITION = PAL.THREAT.transition   -- amber
local BASE_WARNING    = PAL.THREAT.warning      -- red
local BASE_OFFTANK    = PAL.THREAT.offtank      -- pale blue

local THREAT = { tank = {}, dps = {} }

--- Rebuild both palettes at the configured shade. Called from Enable and
--- again whenever the settings pass runs, so the slider takes effect without
--- a reload. The tables are rewritten in place because the rule closures hold
--- references to them.
local function Shade(dst, src, k)
    for i = 1, 3 do dst[i] = src[i] * k end
    return dst
end

local builtAt
function ns.BuildPalette(shade, force)
    shade = (type(shade) == "number" and shade > 0 and shade <= 1) and shade or 0.75
    -- Idempotent, because this is called from the layout pass: rebuilding an
    -- unchanged palette on every plate of every settings change is pure churn.
    if builtAt == shade and not force then return end
    builtAt = shade
    for name, c in pairs(BASE_REACTION) do
        REACTION[name] = Shade(REACTION[name] or {}, c, shade)
    end
    local safe    = Shade(THREAT.tank.secure or {}, BASE_SAFE, shade)
    local trans   = Shade(THREAT.tank.losing or {}, BASE_TRANSITION, shade)
    local warning = Shade(THREAT.tank.lost or {}, BASE_WARNING, shade)
    local offtank = Shade(THREAT.tank.offtank or {}, BASE_OFFTANK, shade)
    THREAT.tank.secure, THREAT.tank.losing  = safe, trans
    THREAT.tank.lost,   THREAT.tank.offtank = warning, offtank
    THREAT.dps.secure,  THREAT.dps.losing   = warning, trans
    THREAT.dps.lost,    THREAT.dps.offtank  = safe, safe
end
ns.BuildPalette(0.75)
ns.THREAT = THREAT

--------------------------------------------------------------------------------
--  Role and instance gating, cached
--------------------------------------------------------------------------------
--- Does the unit have a mana bar? UnitHasPowerType is the newer way to ask
--- and not every build has it; the older one reads the primary power type.
local MANA = Enum.PowerType.Mana
local function HasMana(unit)
    if UnitHasPowerType then return UnitHasPowerType(unit, MANA) end
    return UnitPowerType(unit) == MANA
end

local isTank, inInstance = false, false

local function RefreshRole()
    local cfg = ns.module and ns.module.db
    local mode = cfg and cfg.tankMode or "auto"
    if mode == "tank" then isTank = true return end
    if mode == "dps" then isTank = false return end
    isTank = false
    if type(UnitGroupRolesAssigned) == "function" then
        -- UnitGroupRolesAssigned is SecretWhenUnitIdentityRestricted
        -- (UnitDocumentation.lua:1318), so the returned string may not be
        -- comparable. Our own role is the benign case; another group member's
        -- below is where it actually bites.
        local ok, role = pcall(UnitGroupRolesAssigned, "player")
        if ok and not ns.IsSecret(role) and role == "TANK" then isTank = true end
    end
end

local function RefreshInstance()
    inInstance = false
    if type(IsInInstance) ~= "function" then return end
    local ok, inside, kind = pcall(IsInInstance)
    if ok and inside and (kind == "party" or kind == "raid" or kind == "scenario") then
        inInstance = true
    end
end
ns.RefreshThreatCache = function() RefreshRole(); RefreshInstance() end

--------------------------------------------------------------------------------
--  Co-tanks, for the off-tank fold
--
--  In restricted content the mob-target's ROLE comes back secret, so no Lua
--  branch can ask "who is tanking this". Invert it: ask each of your
--  co-tanks "are YOU tanking this", and fold the possibly-secret answer into
--  the colour C-side. Exactly one tank holds a mob, so the fold resolves
--  itself without anything ever being read.
--
--  The token list is rebuilt lazily off events we already have, so this
--  costs no new registrations.
--------------------------------------------------------------------------------
local coTanks, coTanksDirty = {}, true

local function RefreshCoTanks()
    wipe(coTanks)
    coTanksDirty = false
    if type(IsInGroup) ~= "function" or not IsInGroup() then return end
    local prefix = (type(IsInRaid) == "function" and IsInRaid()) and "raid" or "party"
    if type(GetNumGroupMembers) ~= "function" then return end
    local okN, n = pcall(GetNumGroupMembers)
    if not okN or type(n) ~= "number" then return end
    for i = 1, n do
        local unit = prefix .. i
        local isMe, meSecret = ns.IsUnit(unit, "player")
        local okE, exists = pcall(UnitExists, unit)
        if not meSecret and not isMe and okE and exists then
            local ok, role = pcall(UnitGroupRolesAssigned, unit)
            if ok and not ns.IsSecret(role) and role == "TANK" then
                coTanks[#coTanks + 1] = unit
                if #coTanks >= 3 then return end
            end
        end
    end
end

--- Fold "does another tank have this" into a colour without reading anything.
--- Returns r, g, b which may be SECRET: hand them to a setter and nothing else.
local function OffTankFold(unit, base, target)
    if not (C_CurveUtil and type(C_CurveUtil.EvaluateColorValueFromBoolean) == "function") then
        return base[1], base[2], base[3]
    end
    if coTanksDirty then RefreshCoTanks() end
    if #coTanks == 0 then return base[1], base[2], base[3] end

    local r, g, b = base[1], base[2], base[3]
    for _, tank in ipairs(coTanks) do
        local ok, isTanking = pcall(UnitDetailedThreatSituation, tank, unit)
        if ok and type(isTanking) ~= "nil" then
            local okR, nr = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, isTanking, target[1], r)
            local okG, ng = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, isTanking, target[2], g)
            local okB, nb = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, isTanking, target[3], b)
            if okR and okG and okB then r, g, b = nr, ng, nb end
        end
    end
    return r, g, b
end

--------------------------------------------------------------------------------
--  State calculators
--
--  One slice of state per rule kind, recomputed only when an event that
--  affects that slice fires. state is a plain table on the plate.
--------------------------------------------------------------------------------
local Calc = {}

-- Two rules run through this file and both are easy to break:
--   * select(2, pcall(f)) hands back the ERROR MESSAGE when the call failed,
--     which is truthy, so a failure reads as "yes". Always unpack ok first.
--   * never put a possibly-secret value in a truthiness test, which includes
--     `ok and v or nil`. Assign it inside an `if ok then`.
function Calc.reaction(state, unit)
    local ok, attack = pcall(UnitCanAttack, "player", unit)
    state.canAttack = (ok and attack) and true or false
    local okR, react = pcall(UnitReaction, "player", unit)
    state.reaction = (okR and type(react) == "number") and react or nil
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    state.isPlayer = (okP and isPlayer) and true or false
end

function Calc.tapped(state, unit)
    local ok, tapped = pcall(UnitIsTapDenied, unit)
    state.tapped = (ok and tapped) and true or false
end

function Calc.threat(state, unit)
    -- UnitThreatSituation is SecretWhenUnitThreatStateRestricted, so `ok and
    -- status or nil` is a truthiness test on a secret and throws in exactly
    -- the content the threat feature exists for. This handler is reached
    -- from the plate's own OnEvent, which has no pcall, so that would be a
    -- raw error on every threat event in an instance.
    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if ok then state.threat = status else state.threat = nil end
end

function Calc.target(state, unit)
    -- Through the helper, never a bare truthiness test: UnitIsUnit is
    -- SecretWhenUnitComparisonRestricted (UnitDocumentation.lua:2410) and
    -- this runs from a raw OnEvent handler with no pcall around it, so a
    -- throw here is a visible Lua error on every threat and faction event
    -- for every plate. A secret answer resolves to false; the target and
    -- focus colour rules are off by default and the border carries that cue.
    local isTarget, tSecret = ns.IsUnit(unit, "target")
    local isFocus, fSecret = ns.IsUnit(unit, "focus")
    state.isTarget = (not tSecret) and isTarget or false
    state.isFocus  = (not fSecret) and isFocus or false
end

ns.Calc = Calc

--------------------------------------------------------------------------------
--  Rules, in priority order
--
--  Each rule: kind, the events that dirty it, and Colour(state, unit, cfg)
--  returning r,g,b or nil to fall through. First non-nil wins.
--------------------------------------------------------------------------------
local RULES = {
    {
        kind = "tapped",
        events = { "UNIT_FLAGS" },
        active = function() return true end,
        Colour = function(state)
            if state.tapped then local c = REACTION.tapped return c[1], c[2], c[3] end
        end,
    },
    {
        kind = "threat",
        events = { "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE" },
        active = function(cfg) return cfg.threatColour end,
        Colour = function(state, unit, cfg)
            if cfg.threatInInstancesOnly and not inInstance then return end
            -- Combat only: out of combat nothing has threat on
            -- anything, so the colour would only ever be noise.
            if cfg.threatInCombatOnly then
                local okC, inCombat = pcall(UnitAffectingCombat, "player")
                if okC and not inCombat then return end
            end
            if type(IsInGroup) == "function" and not IsInGroup() then return end  -- solo, you always have it
            local status = state.threat
            if type(status) == "nil" then return end
            local set = isTank and THREAT.tank or THREAT.dps

            -- A secret status cannot be compared. Rather than guess, fall
            -- through to reaction colour: a wrong threat colour is worse
            -- than none, and the execute/target cues still work.
            if IsSecret(status) then return end

            -- The safe colour is OFF by default, and it is the setting
            -- that makes threat quiet. With it off the safe state does not
            -- recolour at all, it falls through to hostility, so the bar only
            -- changes when something is actually going wrong. Combined with
            -- combatOnly and instancesOnly, threat says nothing at all until
            -- you are in an instance, in combat, and losing or holding
            -- something you should not be.
            local safeColours = cfg.threatSafeColour == true

            if isTank then
                if status >= 3 then
                    if not safeColours then return end
                    return set.secure[1], set.secure[2], set.secure[3]
                end
                if status == 2 then return set.losing[1], set.losing[2], set.losing[3] end
                -- We are a tank and do not have it. Another tank holding it
                -- is normal; a dps holding it is not. Fold, do not branch.
                return OffTankFold(unit, set.lost, set.offtank)
            end
            -- As a dps, holding it IS the alarm, so secure always paints.
            if status >= 3 then return set.secure[1], set.secure[2], set.secure[3] end
            if status >= 1 then return set.losing[1], set.losing[2], set.losing[3] end
            if not safeColours then return end
            return set.lost[1], set.lost[2], set.lost[3]
        end,
    },
    {
        kind = "focus",
        events = { "PLAYER_FOCUS_CHANGED" },
        active = function(cfg) return cfg.targetColour == true end,
        Colour = function(state)
            if state.isFocus then return FOCUS_COLOUR[1], FOCUS_COLOUR[2], FOCUS_COLOUR[3] end
        end,
    },
    {
        -- Off by default, and the reason is the whole point of this palette.
        -- The bar has one colour to give and two things worth saying with it,
        -- threat and hostility. Which plate you are targeting is the third,
        -- and it does not need the bar: the plate grows, and its border goes
        -- white. Painting the target blue costs you the threat colour on the
        -- one mob you are most likely to be pulling off the tank.
        kind = "target",
        events = { "PLAYER_TARGET_CHANGED" },
        active = function(cfg) return cfg.targetColour == true end,
        Colour = function(state)
            if state.isTarget then return TARGET_COLOUR[1], TARGET_COLOUR[2], TARGET_COLOUR[3] end
        end,
    },
    {
        -- Above reaction, below target: a mob's type does not change, so this
        -- is the base colour for anything we can classify, and reaction is
        -- the fallback for everything we cannot.
        kind = "mobType",
        events = { "UNIT_FACTION" },
        active = function(cfg) return cfg.typeColour == true end,
        Colour = function(state, unit, cfg)
            if cfg.typeInInstancesOnly and not inInstance then return end
            if state.isPlayer or not state.canAttack then return end

            local okC, class = pcall(UnitClassification, unit)
            if not okC or type(class) ~= "string" then return end
            -- Bosses and rares keep the reaction colour: they are already
            -- unmistakable and a boss recoloured as "melee" reads as trash.
            if class == "worldboss" or class == "rare" or class == "rareelite" then return end

            local okM, mana = pcall(HasMana, unit)
            if not okM then return end
            if mana == true then
                local c = TYPE_COLOUR.caster
                return c[1], c[2], c[3]
            end
            -- Only elites get the melee colour. A normal-classification mob
            -- with no mana is a critter or a totem as often as it is a melee
            -- pull, and colouring those is noise.
            if class == "elite" then
                local c = TYPE_COLOUR.melee
                return c[1], c[2], c[3]
            end
        end,
    },
    {
        kind = "reaction",
        events = { "UNIT_FACTION" },
        active = function() return true end,
        Colour = function(state, unit, cfg)
            if cfg.healthColour == "class" and state.isPlayer then
                local ok, _, class = pcall(UnitClass, unit)
                local r, g, b = PAL.ClassRGB(ok and class or nil)
                if r then return r, g, b end
            end
            local react = state.reaction
            if type(react) == "number" then
                local c
                if react <= 2 then c = REACTION.hostile
                elseif react == 3 then c = REACTION.unfriendly
                elseif react == 4 then c = REACTION.neutral
                else c = REACTION.friendly end
                return c[1], c[2], c[3]
            end
            local c = state.canAttack and REACTION.hostile or REACTION.friendly
            return c[1], c[2], c[3]
        end,
    },
}
ns.RULES = RULES

--- The events the active rules need. Health.lua folds this into the plate's
--- registration, which is how an inactive rule costs nothing.
function ns.ColourEvents(cfg)
    local out, seen = {}, {}
    for _, rule in ipairs(RULES) do
        if rule.active(cfg) then
            for _, e in ipairs(rule.events) do
                if not seen[e] then seen[e] = true; out[#out + 1] = e end
            end
        end
    end
    return out
end

--- Recompute every state slice the active rules need. Cheap, and only runs
--- when something said it changed.
function ns.RefreshState(f)
    local cfg = ns.module.db
    local state = f.state
    if not state then state = {}; f.state = state end
    local unit = f.unit
    if not unit then return state end
    for _, rule in ipairs(RULES) do
        if rule.active(cfg) then
            local calc = Calc[rule.kind]
            if calc then calc(state, unit) end
        end
    end
    Calc.target(state, unit)
    return state
end

--- First match wins.
function ns.HealthColour(f)
    local cfg = ns.module.db
    local state = f.state or ns.RefreshState(f)
    for _, rule in ipairs(RULES) do
        if rule.active(cfg) then
            local r, g, b = rule.Colour(state, f.unit, cfg)
            if type(r) ~= "nil" then return r, g, b end
        end
    end
    local c = REACTION.hostile
    return c[1], c[2], c[3]
end

--------------------------------------------------------------------------------
--  Cache invalidation, on events we would be registering anyway
--------------------------------------------------------------------------------
ns.Widget{
    name = "colourCache",
    Enable = function(M)
        ns.BuildPalette(ns.module.db.barShade)
        M:RegisterMessage("EV_PROFILE_CHANGED", function()
            ns.BuildPalette(ns.module.db.barShade)
        end)
        -- Your own colours (Colours page): rebuild the shaded copies even
        -- though the shade has not moved, then repaint every plate.
        M:RegisterMessage("EV_PALETTE_CHANGED", function()
            ns.BuildPalette(ns.module.db.barShade, true)
            if M.Refresh then M:Refresh() end
        end)
        ns.RefreshThreatCache()
        local function role() RefreshRole(); coTanksDirty = true end
        local function zone() ns.RefreshThreatCache(); coTanksDirty = true end
        M:RegisterEvent("PLAYER_ENTERING_WORLD", zone)
        M:RegisterEvent("GROUP_ROSTER_UPDATE", role)
        M:RegisterEvent("PLAYER_ROLES_ASSIGNED", role)
        M:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", role)
    end,
}
