if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Classic.lua
--  The classic-era staples: a swing timer, the energy tick and five-second
--  rule on the player's power bar, and a hunter's pet happiness.
--
--  SWING TIMER. Addons lost the combat log in 12.0, so the old recipe (time
--  SWING_DAMAGE / SWING_MISSED) is gone. Forever ships the answer natively,
--  and Blizzard's own hidden timer (Blizzard_SwingTimer, AllowLoadGameType
--  camelot) is built on it:
--      PLAYER_SWING(swingDuration, swingType)        one per swing you make
--      C_SwingTimer.EnableRangeCheck(swingType, on)   opt in to range events
--      PLAYER_SWING_RANGE_UPDATE(type, inRange, checksRange)
--      C_SwingTimer.IsTargetWithinSwingRange(type)    nil = no check possible
--  We follow Blizzard's semantics (SwingTimerMixin): a row per swing type
--  that can swing (UnitAttackSpeed reports a speed for the slot; main hand
--  always), restart on PLAYER_SWING, empty when the swing lands, dimmed out
--  of range, where nil is NOT out of range. Our own frames; Blizzard's timer
--  is only ever switched off through its own CVar, showSwingTimer, and the
--  value you had is put back when ours is switched off.
--
--  POWER TICKS. Classic energy comes in lumps every two seconds, and mana
--  stops regenerating for five seconds after you spend it. A strip along
--  the power bar times both, and a preview past the end of the fill shows
--  what the next tick adds. Built so it never has to read your power: see
--  the section below for how.
--
--  PET HAPPINESS. The same reading Blizzard's PetHappiness.lua makes:
--  C_PetInfo.GetPetHappiness for a hunter pet (HasPetUI's second return), on
--  UNIT_HAPPINESS and UNIT_PET. A coloured marker on our pet frame with the
--  same tooltip lines Blizzard's indicator has.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min = math.floor, math.max, math.min
local issecret = issecretvalue or function() return false end
local function Plain(v) return not issecret(v) end

--------------------------------------------------------------------------------
--  Swing timer: a module of its own, so it can be switched off on its own
--------------------------------------------------------------------------------
local SW = EV:NewModule("SwingTimer", {
    enabled      = true,
    width        = 220,
    rowHeight    = 10,
    rowGap       = 3,
    showOffHand  = true,
    showRanged   = true,
    showText     = true,
    showLabel    = true,
    visibility   = "combat",   -- combat | always
    activeOnly   = true,       -- a bar only while that weapon is swinging
    hideBlizzard = true,       -- switch Blizzard's timer off (its CVar) while ours is on
})
SW.title = "Swing Timer"
SW.description = "A bar per weapon showing time to your next auto attack, dimmed when your target is out of reach."
ns.swing = SW

local SWING = Enum.PlayerSwingType
local HAS_API = C_SwingTimer and SWING and true or false

local ROWS = HAS_API and {
    { type = SWING.MainHand, key = "mh", tag = "MH", token = "accent" },
    { type = SWING.OffHand,  key = "oh", tag = "OH", token = "xpEnd",  opt = "showOffHand" },
    { type = SWING.Ranged,   key = "r",  tag = "R",  token = "rested", opt = "showRanged" },
} or {}

local holder, ticker
local rows, byType = {}, {}

-- The last readable answer per swing type. UnitAttackSpeed can come back
-- secret in combat, and a secret can't be compared, so in combat we go on
-- what it said last time it could be read (and a swing event is proof).
local canSwing = {}

local function CanSwing(swingType)
    if swingType == SWING.MainHand then return true end
    local ok, _, oh, ranged = pcall(UnitAttackSpeed, "player")
    local v = ok and (swingType == SWING.OffHand and oh or ranged) or nil
    if ok and Plain(v) then
        canSwing[swingType] = type(v) == "number" and v > 0
    end
    return canSwing[swingType] or false
end

local function Allowed(def) return not def.opt or SW.db[def.opt] end

local function RowWanted(def)
    return Allowed(def) and CanSwing(def.type)
end

-- How long a finished swing keeps its bar before it counts as stopped. The
-- next swing's PLAYER_SWING lands as the last one ends, so this only has to
-- cover the gap between them.
local GRACE = 0.6

local function Unlocked() return EV.Movers and EV.Movers.IsUnlocked and EV.Movers:IsUnlocked() end

--- Whether a row is on screen: it can swing, and (with activeOnly) it is
--- swinging now. A priest shooting a wand gets the ranged bar alone.
local function RowShown(r)
    if not Allowed(r.def) then return false end
    -- Swinging is its own proof that this weapon can swing.
    if SW.db.activeOnly and not Unlocked() then return r.active and true or false end
    return RowWanted(r.def)
end

local function BuildRow(def)
    local r = CreateFrame("Frame", nil, holder)
    r.def = def
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetAllPoints()
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(0)
    r.spark = r.bar:CreateTexture(nil, "OVERLAY")
    r.spark:SetWidth(2)
    r.spark:SetBlendMode("ADD")
    r.spark:Hide()
    r.time = r.bar:CreateFontString(nil, "OVERLAY")
    r.time:SetPoint("RIGHT", r, "RIGHT", -3, 0)
    r.label = r.bar:CreateFontString(nil, "OVERLAY")
    r.label:SetPoint("LEFT", r, "LEFT", 3, 0)
    EV.Pixel:CreateBorder(r, 1, 0, 0, 0, 1)
    r.outOfRange = false
    return r
end

local function PaintRow(r)
    local db = SW.db
    local font = EV.Media:Fetch("font")
    local size = max(8, min(14, db.rowHeight))
    r.bg:SetColorTexture(T.RGBA("surfaceSunk", 0.85))
    r.bar:SetStatusBarTexture(EV.Media:Fetch("statusbar", "Flat"))
    local cr, cg, cb = T.RGBA(r.def.token)
    r.bar:SetStatusBarColor(cr, cg, cb, 1)
    r.spark:SetColorTexture(1, 1, 1, 0.9)
    r.spark:SetHeight(db.rowHeight)
    for _, fs in ipairs({ r.time, r.label }) do
        fs:SetFont(font, size, "OUTLINE")
        fs:SetTextColor(T.RGBA("text"))
    end
    r.label:SetText(db.showLabel and r.def.tag or "")
    r.time:SetShown(db.showText)
    r:SetAlpha(r.outOfRange and 0.4 or 1)
end

local function Clear(r)
    r.start, r.dur = nil, nil
    r.bar:SetValue(0)
    r.spark:Hide()
    r.time:SetText("")
end

local function AnyLive()
    for _, r in ipairs(rows) do if r:IsShown() and r.start then return true end end
    return false
end

local function UpdateVisibility()
    if not holder then return end
    local want
    if not SW:IsEnabled() or not SW.db.enabled then
        want = false
    elseif Unlocked() then
        want = true
    elseif SW.db.visibility == "always" then
        want = true
    else
        want = (UnitAffectingCombat and UnitAffectingCombat("player")) or AnyLive()
    end
    holder:SetShown(want and true or false)
end

local function Layout()
    if not holder then return end
    local db = SW.db
    local y, shown = 0, 0
    for _, r in ipairs(rows) do
        r:ClearAllPoints()
        if RowShown(r) then
            r:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
            r:SetSize(db.width, db.rowHeight)
            r:Show()
            PaintRow(r)
            y = y + db.rowHeight + db.rowGap
            shown = shown + 1
        else
            r:Hide()
            Clear(r)
        end
    end
    holder:SetSize(db.width, max(db.rowHeight, y - db.rowGap))
    EV.Movers:Apply("SwingTimer")
    UpdateVisibility()
end

local function Tick()
    local now = GetTime()
    local live, relayout = false, false
    for _, r in ipairs(rows) do
        if r.active and not r.start and now >= (r.idleAt or 0) then
            -- No new swing followed the last: this weapon has stopped.
            r.active = false
            relayout = true
        elseif r.active then
            live = true
        end
        if r.start and r.dur then
            local done = now - r.start
            if done >= r.dur then
                r.idleAt = r.start + r.dur + GRACE
                Clear(r)
                live = true
            else
                live = true
                local p = done / r.dur
                r.bar:SetValue(p)
                r.spark:ClearAllPoints()
                r.spark:SetPoint("CENTER", r.bar, "LEFT", r:GetWidth() * p, 0)
                r.spark:Show()
                if SW.db.showText then r.time:SetFormattedText("%.1f", r.dur - done) end
            end
        end
    end
    if relayout and SW.db.activeOnly then Layout() end
    if not live then
        ticker:Hide()
        UpdateVisibility()
    end
end

local function SetRange(r, out)
    if r.outOfRange == out then return end
    r.outOfRange = out
    r:SetAlpha(out and 0.4 or 1)
end

local function UpdateRange()
    for _, r in ipairs(rows) do
        if r:IsShown() then
            local ok, inRange = pcall(C_SwingTimer.IsTargetWithinSwingRange, r.def.type)
            -- nil means no check could be made: NOT out of range.
            SetRange(r, ok and Plain(inRange) and inRange == false or false)
        end
    end
end

local rangeOn = {}
local function RangeChecks(on)
    for _, def in ipairs(ROWS) do
        local want = on and RowWanted(def) or false
        if rangeOn[def.type] ~= want then
            rangeOn[def.type] = want
            pcall(C_SwingTimer.EnableRangeCheck, def.type, want)
        end
    end
end

--- Blizzard's timer, off through its own CVar while ours is on.
local CVAR = "showSwingTimer"
local function BlizzardTimer(ours)
    local g = EV.DB:GetGlobal()
    if ours and SW.db.hideBlizzard then
        if g.swingCVarBefore == nil then
            local ok, v = pcall(GetCVar, CVAR)
            g.swingCVarBefore = ok and v or false
        end
        pcall(SetCVar, CVAR, "0")
    elseif g.swingCVarBefore ~= nil then
        if g.swingCVarBefore then pcall(SetCVar, CVAR, g.swingCVarBefore) end
        g.swingCVarBefore = nil
    end
end

--- /evui swing: what each bar thinks is going on, for bug reports.
EV:RegisterSlash("swing", function()
    if not holder then EV:Print(L["The swing timer isn't running on this client."]); return end
    local blizz = GetCVar and GetCVar(CVAR)
    EV:Print(("activeOnly=%s  visibility=%s  showSwingTimer(Blizzard)=%s  holder shown=%s"):format(
        tostring(SW.db.activeOnly), tostring(SW.db.visibility), tostring(blizz), tostring(holder:IsShown())))
    local now = GetTime()
    for _, r in ipairs(rows) do
        EV:Print(("%s: wanted=%s shown=%s active=%s swinging=%s last swing %s"):format(
            r.def.tag, tostring(RowWanted(r.def)), tostring(r:IsShown()), tostring(r.active and true or false),
            tostring(r.start ~= nil),
            r.lastEvent and ("%.1fs ago (%.2fs)"):format(now - r.lastEvent, r.lastDur or 0) or "never"))
    end
end)

function SW:Refresh()
    if not holder then return end
    local on = self:IsEnabled() and self.db.enabled
    BlizzardTimer(on)
    RangeChecks(on)
    Layout()
    UpdateRange()
end

function SW:OnEnable()
    if not HAS_API then return end
    holder = CreateFrame("Frame", "EvermoreUISwingTimer", UIParent)
    holder:SetFrameStrata("MEDIUM")
    holder:SetSize(self.db.width, self.db.rowHeight)
    ticker = CreateFrame("Frame", nil, holder)
    ticker:Hide()
    ticker:SetScript("OnUpdate", Tick)
    for _, def in ipairs(ROWS) do
        local r = BuildRow(def)
        rows[#rows + 1] = r
        byType[def.type] = r
        -- Fonts and colours now: a bar that stays hidden is still cleared
        -- (its text set to ""), and a font string with no font set errors.
        PaintRow(r)
    end
    EV.Movers:Register(holder, "SwingTimer", L["Swing Timer"], { "CENTER", "CENTER", 0, -170 }, {
        group = L["Unit Frames"], page = "swingtimer",
        getSize = function() return self.db.width, holder:GetHeight() end,
        setSize = function(w) if w then self.db.width = floor(w + 0.5); self:Refresh() end end,   -- height follows the rows
        isDisabled = function() return not (self:IsEnabled() and self.db.enabled) end,
    })

    self:RegisterEvent("PLAYER_SWING", function(_, _, dur, swingType)
        if not (Plain(dur) and Plain(swingType)) or type(dur) ~= "number" or dur <= 0 then return end
        local r = byType[swingType]
        if r then r.lastEvent, r.lastDur = GetTime(), dur end
        if not (r and Allowed(r.def)) then return end
        if r.def.type ~= SWING.MainHand then canSwing[r.def.type] = true end
        r.start, r.dur = GetTime(), dur
        local wasActive = r.active
        r.active = true
        if not wasActive and SW.db.activeOnly then Layout() end
        ticker:Show()
        UpdateVisibility()
    end)
    self:RegisterEvent("PLAYER_SWING_RANGE_UPDATE", function(_, _, swingType, inRange, checks)
        if not (Plain(swingType) and Plain(inRange) and Plain(checks)) then return end
        local r = byType[swingType]
        if r then SetRange(r, checks and not inRange or false) end
    end)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", UpdateRange)
    self:RegisterEvent("UNIT_ATTACK_SPEED", function(_, _, unit) if unit == "player" then Layout() end end)
    self:RegisterEvent("WEAPON_SLOT_CHANGED", function() self:Refresh() end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:Refresh() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", UpdateVisibility)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", UpdateVisibility)
    -- Moving it shows every bar it can have, so you can see its full size.
    self:RegisterMessage("EV_UNLOCK", Layout)
    self:RegisterMessage("EV_LOCK", Layout)
    self:RegisterMessage("EV_THEME_CHANGED", function() self:Refresh() end)
    self:RegisterMessage("EV_FONT_CHANGED", function() self:Refresh() end)
    self:Refresh()
end

function SW:OnProfileChanged() self:Refresh() end

--------------------------------------------------------------------------------
--  Power ticks on the player frame's power bar
--
--  Two pieces, both drawn by the engine rather than by an OnUpdate:
--
--    The STRIP, a thin bar along the bottom of the power bar. It fills over
--    the two seconds to the next tick, restarting on each one; after you
--    spend mana it turns amber and fills over the five seconds of the rule
--    instead. A StatusBar given a duration object (SetTimerDuration) animates
--    itself, so there is nothing to run per frame.
--
--    The PREVIEW, a faint segment riding the end of the power fill, showing
--    what the next tick will add: the incoming heals trick from Frame.lua,
--    anchored to the fill's right edge and clipped at the bar's end. Its
--    value is the game's own regeneration PER SECOND (GetPowerRegenForPowerType
--    for energy, GetManaRegen for mana), which already includes Spirit, mp5,
--    talents, haste and effects like Adrenaline Rush. A tick's worth is that
--    times the tick interval, and the multiplication is done by the bar
--    rather than by us: the preview bar is the power bar's width TIMES the
--    interval, so a per-second value against the power maximum draws exactly
--    one tick. That matters because the regen figures can come back secret,
--    and a secret can be handed to SetValue but never multiplied. Mana picks
--    the in-rule or out-of-rule figure from our own timer, so the preview
--    shrinks to what still regenerates while the rule holds.
--
--  Both sit in one holder whose alpha is UnitPowerPercent run through a
--  curve (full at anything below 99%, clear at 100%), so they step aside at
--  full power without our code ever comparing the value. That holds when
--  power is secret: the curve is evaluated on the C side and SetAlpha
--  accepts the secret result.
--
--  Ticks are found by timing, not by value. A player power event with no
--  spell cast in the moment before it is regeneration. The INTERVAL is
--  learned, not assumed: two regen events the same gap apart set it (or one
--  at the classic two seconds, the likely case), later ticks refine it, and
--  a run of events off the rhythm drops it and starts again. Events well
--  under a second apart are smooth regeneration, and nothing is shown. When
--  the value is readable it is used as well (a rise is a tick, and the size
--  of an energy rise is the fallback gain if the regen API says nothing).
--  The five-second rule starts on a successful cast of a spell that costs
--  mana (C_Spell.GetSpellPowerCost), which is the rule's own definition,
--  so mana burned off you by a mob does not start it.
--------------------------------------------------------------------------------
local PT_ENERGY = (Enum.PowerType and Enum.PowerType.Energy) or 3
local PT_MANA   = (Enum.PowerType and Enum.PowerType.Mana) or 0
local TICK, FIVE = 2.0, 5.0    -- TICK is only the starting guess
local ENERGY_GAIN = 20
local SLACK = 0.3               -- how far off the rhythm a tick may land
local WHITE = "Interface\\Buttons\\WHITE8X8"

local tick = {
    ptype = nil,        -- power type being tracked
    last = nil,         -- last readable value
    lastTick = nil,     -- GetTime() of the last regen tick seen
    learned = false,    -- ticks arrive in steps on this client
    interval = TICK,    -- seconds between ticks, learned
    candidate = nil,    -- a gap seen once, waiting for a second to confirm it
    misses = 0,         -- regen events off the learned rhythm, in a row
    gain = ENERGY_GAIN, -- energy per tick, refined when readable
    spentAt = nil,      -- mana: when the five-second rule last started
    castAt = 0,         -- last successful player cast
}

local pt                -- holder, strip, clip, ghost
local gen = 0           -- bumps to cancel a pending restart
local fullCurve

local function Frame() return ns.frames and ns.frames.player end

local function FullCurve()
    if fullCurve ~= nil then return fullCurve or nil end
    fullCurve = false
    if C_CurveUtil and C_CurveUtil.CreateCurve then
        local ok, c = pcall(C_CurveUtil.CreateCurve)
        if ok and c then
            c:AddPoint(0, 1); c:AddPoint(0.99, 1); c:AddPoint(1, 0)
            fullCurve = c
        end
    end
    return fullCurve or nil
end

local function Build(f)
    if pt then return pt end
    pt = {}
    local h = CreateFrame("Frame", nil, f.power)
    h:SetAllPoints(f.power)
    pt.holder = h

    local strip = CreateFrame("StatusBar", nil, h)
    strip:SetStatusBarTexture(WHITE)
    strip:SetMinMaxValues(0, 1)
    strip:SetValue(0)
    strip.bg = strip:CreateTexture(nil, "BACKGROUND")
    strip.bg:SetAllPoints()
    strip.bg:SetColorTexture(0, 0, 0, 0.5)
    pt.strip = strip

    local clip = CreateFrame("Frame", nil, h)
    clip:SetClipsChildren(true)
    pt.clip = clip
    local ghost = CreateFrame("StatusBar", nil, clip)
    ghost:SetStatusBarTexture(WHITE)
    ghost:SetMinMaxValues(0, 1)
    ghost:SetValue(0)
    pt.ghost = ghost
    return pt
end

local function HideAll()
    gen = gen + 1
    if pt then pt.holder:Hide() end
end

--- Size and anchor to the bar as it is now (called on refresh and layout).
local function Place(f)
    local p = Build(f)
    local lvl = f.power:GetFrameLevel() + 1
    if f.overlay then lvl = math.min(lvl, f.overlay:GetFrameLevel() - 1) end
    p.holder:SetFrameLevel(lvl)
    local ph = f.power:GetHeight() or 0
    local one = EV.Pixel:One(f)
    local sh = math.max(2 * one, floor(ph * 0.3 / one + 0.5) * one)
    p.strip:ClearAllPoints()
    p.strip:SetPoint("BOTTOMLEFT", f.power, "BOTTOMLEFT", 0, 0)
    p.strip:SetPoint("BOTTOMRIGHT", f.power, "BOTTOMRIGHT", 0, 0)
    p.strip:SetHeight(sh)

    local fill = f.power:GetStatusBarTexture()
    if fill then
        p.clip:ClearAllPoints()
        p.clip:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        p.clip:SetPoint("BOTTOMRIGHT", f.power, "BOTTOMRIGHT", 0, 0)
        p.ghost:ClearAllPoints()
        p.ghost:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        p.ghost:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    end
end

--- Run the strip from `start` for `len` seconds.
local function Run(bar, start, len)
    if bar.SetTimerDuration and C_DurationUtil and C_DurationUtil.CreateDuration then
        bar._dur = bar._dur or C_DurationUtil.CreateDuration()
        local ok = pcall(bar._dur.SetTimeFromStart, bar._dur, start, len)
        if ok and pcall(bar.SetTimerDuration, bar, bar._dur,
                        Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0,
                        Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0) then
            bar:SetScript("OnUpdate", nil)
            return
        end
    end
    -- Older clients: fill it by hand.
    bar:SetMinMaxValues(0, 1)
    bar:SetScript("OnUpdate", function(self)
        self:SetValue(math.min((GetTime() - start) / len, 1))
    end)
end

--- Regeneration per second, straight from the game. May be secret: the
--- only thing done with it is SetValue. Plain zero means nothing to show.
local function PerSecond()
    local v
    if tick.ptype == PT_ENERGY then
        if type(GetPowerRegenForPowerType) == "function" then
            local ok, base = pcall(GetPowerRegenForPowerType, PT_ENERGY)
            if ok then v = base end
        end
        -- No answer from the API: what we measured, per second.
        if type(v) ~= "number" or (not issecret(v) and v <= 0) then
            v = tick.gain / tick.interval
        end
    else
        local ok, base, casting = pcall(GetManaRegen)
        if not ok then return nil end
        local inRule = tick.spentAt and GetTime() - tick.spentAt < FIVE
        v = inRule and casting or base
    end
    if type(v) ~= "number" then return nil end
    if not issecret(v) and v <= 0 then return nil end
    return v
end

local Update

--- Put the strip and preview into whichever state applies now, and come
--- back when that state's time is up.
local function Schedule()
    local f = Frame()
    local M = ns.module
    if not (pt and f and M) then return end
    gen = gen + 1
    local my = gen
    local now = GetTime()
    local cfg = M.db.player
    local strip, ghost = pt.strip, pt.ghost
    local wait

    if tick.ptype == PT_MANA and tick.spentAt and now - tick.spentAt < FIVE then
        strip:SetStatusBarColor(T.RGBA("warning", 0.95))
        Run(strip, tick.spentAt, FIVE)
        strip:Show()
        wait = tick.spentAt + FIVE - now
    elseif tick.learned and tick.lastTick then
        local iv = tick.interval
        local start = tick.lastTick + floor((now - tick.lastTick) / iv) * iv
        strip:SetStatusBarColor(T.RGBA("text", 0.85))
        Run(strip, start, iv)
        strip:Show()
        wait = start + iv - now
    else
        strip:Hide()
    end

    local perSec = cfg.powerTickGhost and tick.learned and PerSecond()
    if perSec then
        local okM, maxP = pcall(UnitPowerMax, "player", tick.ptype)
        if okM and type(maxP) ~= "nil" then
            -- interval x the bar's width, so per second reads as per tick.
            ghost:SetWidth(math.max((f.power:GetWidth() or 1) * tick.interval, 1))
            pcall(ghost.SetMinMaxValues, ghost, 0, maxP)
            pcall(ghost.SetValue, ghost, perSec)
            local r, g, b = f.power:GetStatusBarColor()
            if type(r) == "number" and not issecret(r) and not issecret(g) and not issecret(b) then
                ghost:SetStatusBarColor(math.min(r * 1.35, 1), math.min(g * 1.35, 1), math.min(b * 1.35, 1), 0.45)
            else
                ghost:SetStatusBarColor(1, 1, 1, 0.3)
            end
            ghost:Show()
        else
            ghost:Hide()
        end
    else
        ghost:Hide()
    end

    pt.holder:SetShown(strip:IsShown() or ghost:IsShown())
    if wait then
        C_Timer.After(math.max(wait, 0.05) + 0.02, function()
            if my == gen then Schedule() end
        end)
    end
end

--- Alpha from the power percentage: clear at full, without reading it.
local function Fade()
    if not pt then return end
    local curve = FullCurve()
    if curve and UnitPowerPercent then
        local ok, a = pcall(UnitPowerPercent, "player", tick.ptype, false, curve)
        if ok and type(a) ~= "nil" and pcall(pt.holder.SetAlpha, pt.holder, a) then return end
    end
    local okC, c = pcall(UnitPower, "player", tick.ptype)
    local okM, m = pcall(UnitPowerMax, "player", tick.ptype)
    if okC and okM and type(c) == "number" and type(m) == "number" and not issecret(c) and not issecret(m) then
        pt.holder:SetAlpha(c >= m and 0 or 1)
    else
        pt.holder:SetAlpha(1)
    end
end

--- Full reset and redraw: power type change, settings, layout, login.
function Update()
    local M = ns.module
    local f = Frame()
    if not (M and f and f.power and f.power:IsShown() and M.db.player.powerTicks) then return HideAll() end
    local okT, ptype = pcall(UnitPowerType, "player")
    if not okT or issecret(ptype) or (ptype ~= PT_ENERGY and ptype ~= PT_MANA) then return HideAll() end
    if tick.ptype ~= ptype then
        tick.ptype, tick.last, tick.lastTick, tick.learned, tick.spentAt = ptype, nil, nil, false, nil
        tick.gain, tick.interval, tick.candidate, tick.misses = ENERGY_GAIN, TICK, nil, 0
    end
    Place(f)
    Fade()
    Schedule()
end

local function OnPower(token)
    if not (pt and ns.module and ns.module.db.player.powerTicks) then return end
    local want = tick.ptype == PT_ENERGY and "ENERGY" or tick.ptype == PT_MANA and "MANA" or nil
    if not want or (token and token ~= want) then return end
    local now = GetTime()
    local okV, cur = pcall(UnitPower, "player", tick.ptype)
    local readable = okV and type(cur) == "number" and not issecret(cur)
    local rose
    if readable and tick.last then
        rose = cur > tick.last
        if cur < tick.last and tick.ptype == PT_MANA and now - tick.castAt < 0.3 then
            tick.spentAt = tick.spentAt and math.max(tick.spentAt, tick.castAt) or tick.castAt
        end
    elseif not readable then
        rose = now - tick.castAt > 0.15
    end
    if rose then
        local dt = tick.lastTick and now - tick.lastTick
        local onBeat = true
        if dt then
            local iv = tick.interval
            if tick.learned then
                -- On the rhythm, allowing for ticks skipped at full power.
                local k = floor(dt / iv + 0.5)
                if k >= 1 and math.abs(dt - k * iv) <= SLACK then
                    tick.misses = 0
                    if k == 1 then tick.interval = iv * 0.75 + dt * 0.25 end
                    if readable and tick.last and tick.ptype == PT_ENERGY and k == 1 then
                        local d = cur - tick.last
                        if d > 0 and d <= 60 then tick.gain = d end
                    end
                else
                    -- Off the beat: a potion, a drink, a talent proc. Keep
                    -- the phase, and only give up on a run of them (which
                    -- is also how smooth regeneration shows itself).
                    onBeat = false
                    tick.misses = tick.misses + 1
                    if tick.misses >= 3 then
                        tick.learned, tick.candidate, tick.misses = false, nil, 0
                        onBeat = true
                    end
                end
            elseif dt < 0.9 then
                -- Rises well under a second apart with no casts: smooth
                -- regeneration, and nothing to time.
                tick.candidate = nil
            elseif tick.candidate and math.abs(dt - tick.candidate) <= SLACK then
                tick.learned, tick.interval, tick.candidate = true, (dt + tick.candidate) / 2, nil
            elseif math.abs(dt - TICK) <= SLACK then
                -- The classic two seconds: likely enough to trust at once.
                tick.learned, tick.interval, tick.candidate = true, dt, nil
            elseif dt <= 6 then
                tick.candidate = dt
            end
        end
        if onBeat then tick.lastTick = now end
    end
    if readable then tick.last = cur end
    Fade()
    if rose then Schedule() end
end

local function OnCast(spellID)
    tick.castAt = GetTime()
    if tick.ptype ~= PT_MANA or type(spellID) ~= "number" or issecret(spellID) then return end
    local ok, costs = pcall(C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost, spellID)
    if not ok or type(costs) ~= "table" then return end
    for _, c in ipairs(costs) do
        local isMana = c.type == PT_MANA or c.name == "MANA"
        local amount = c.cost or c.minCost
        if isMana and type(amount) == "number" and not issecret(amount) and amount > 0 then
            tick.spentAt = tick.castAt
            if pt then Schedule() end
            return
        end
    end
end

--------------------------------------------------------------------------------
--  Pet happiness on the pet frame
--------------------------------------------------------------------------------
local happy
local HAPPY_TOKEN = { [1] = "danger", [2] = "warning", [3] = "success" }

local function UpdateHappiness()
    local M = ns.module
    local f = ns.frames and ns.frames.pet
    if not (M and f) then return end
    if not M.db.pet.happiness then if happy then happy:Hide() end return end
    local ok, level, damage, loyalty = pcall(function()
        return C_PetInfo and C_PetInfo.GetPetHappiness and C_PetInfo.GetPetHappiness()
    end)
    local okH, hasUI, isHunter = pcall(HasPetUI)
    if not (ok and okH and level and isHunter and Plain(level)) then
        if happy then happy:Hide() end
        return
    end
    if not happy then
        happy = CreateFrame("Frame", nil, f)
        happy:SetSize(9, 9)
        happy.fill = happy:CreateTexture(nil, "OVERLAY")
        happy.fill:SetAllPoints()
        EV.Pixel:CreateBorder(happy, 1, 0, 0, 0, 1)
        happy:EnableMouse(true)
        happy:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tip or "")
            if self.damage then GameTooltip:AddLine(self.damage, 1, 1, 1) end
            if self.loyalty then GameTooltip:AddLine(self.loyalty, 1, 1, 1) end
            local okD, diet = pcall(C_PetInfo.GetPetFoodTypes)
            if okD and type(diet) == "table" and #diet > 0 and PET_DIET_TEMPLATE then
                GameTooltip:AddLine(PET_DIET_TEMPLATE:format(table.concat(diet, PET_FOOD_DELIMIT or ", ")), nil, nil, nil, true)
            end
            GameTooltip:Show()
        end)
        happy:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    happy:ClearAllPoints()
    happy:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    happy:SetFrameLevel(f:GetFrameLevel() + 6)
    happy.fill:SetColorTexture(T.RGBA(HAPPY_TOKEN[level] or "textMuted"))
    happy.tip = _G["PET_HAPPINESS" .. level] or ""
    happy.damage = (type(damage) == "number" and PET_DAMAGE_PERCENTAGE) and PET_DAMAGE_PERCENTAGE:format(damage) or nil
    happy.loyalty = type(loyalty) == "number" and ((loyalty < 0 and LOSING_LOYALTY) or (loyalty > 0 and GAINING_LOYALTY)) or nil
    happy:Show()
end
ns.UpdateHappiness = UpdateHappiness

--------------------------------------------------------------------------------
--  Wiring (called from UnitFrames.lua's OnEnable)
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event, unit, a2, a3)
    if event == "UNIT_POWER_FREQUENT" then
        if unit == "player" then OnPower(a2) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" then OnCast(a3) end
    elseif event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER" then
        if unit == "player" then Update() end
    elseif event == "UNIT_HAPPINESS" or event == "UNIT_PET" or event == "PET_UI_UPDATE"
        or event == "PLAYER_ENTERING_WORLD" then
        UpdateHappiness()
        if event == "PLAYER_ENTERING_WORLD" then Update() end
    end
end)

function ns.EnableClassic()
    for _, e in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_DISPLAYPOWER", "UNIT_MAXPOWER",
                         "UNIT_SPELLCAST_SUCCEEDED", "UNIT_HAPPINESS", "UNIT_PET",
                         "PET_UI_UPDATE", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    UpdateHappiness()
    Update()
end

--- Settings and layout changes: the bar may have moved or resized.
function ns.RefreshClassic()
    UpdateHappiness()
    Update()
end
