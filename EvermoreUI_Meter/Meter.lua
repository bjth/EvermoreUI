if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Meter.lua
--  Our own damage meter: windows we draw, fed by C_DamageMeter, the data
--  the game's built-in meter reads. Blizzard_DamageMeter is the reference
--  for how that data behaves; nothing of Blizzard's meter is reused or
--  touched here, apart from the option to switch its windows off.
--
--  The one rule everything else follows: in combat the numbers are secret
--  to addons (SecretWhenInCombat). They can be shown (a status bar and a
--  font string take them, AbbreviateNumbers accepts them) but never
--  compared or worked out with. So in combat a window shows the game's
--  order, bar and amounts as they come; anything computed (a share of the
--  total, a sort, a realm stripped off a name) waits until the values are
--  readable again. EV.Usable says which is which.
--
--  This file: the module and its settings, the modes, reading sessions,
--  formatting values, and the update loop. Window.lua draws the windows,
--  Breakdown.lua a source's spells, Report.lua sends a summary to chat.
--------------------------------------------------------------------------------
local ADDON, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON] = ns
local L = EV.L

ns.MAX_WINDOWS = 4

local function WindowDefaults(mode)
    return {
        mode         = mode,        -- Enum.DamageMeterType
        session      = "current",   -- "current" or "overall"
        numbers      = "compact",   -- "minimal", "compact" or "complete"
        barHeight    = 18,
        spacing      = 1,
        textSize     = 12,
        texture      = "",          -- "" follows the suite's statusbar
        opacity      = 0.9,         -- the window's background
        classColours = true,
        icons        = true,
        rank         = true,
        showSelf     = true,        -- keep your own row in view
        width        = 240,
        height       = 152,
    }
end

local M = EV:NewModule("Meter", {
    count         = 1,              -- windows shown, 1 to MAX_WINDOWS
    hidden        = false,          -- /evui meter hides them all
    hideBlizzard  = true,           -- turn the game's own meter windows off
    reportLines   = 5,
    reportChannel = "PARTY",
    windows = {
        WindowDefaults(0),          -- damage done
        WindowDefaults(2),          -- healing done
        WindowDefaults(5),          -- interrupts
        WindowDefaults(7),          -- damage taken
    },
})
ns.module = M
M.title = "Damage Meter"
M.description = "Damage, healing, interrupts and more in our own windows, from the game's own meter data."

--------------------------------------------------------------------------------
--  Modes, as Blizzard's meter groups and treats them
--  (Blizzard_DamageMeter/DamageMeterSessionWindow.lua).
--------------------------------------------------------------------------------
local TYPE = Enum and Enum.DamageMeterType or {}
local SESSION = Enum and Enum.DamageMeterSessionType or {}
ns.TYPE, ns.SESSION = TYPE, SESSION

ns.CATEGORIES = {
    { name = _G.DAMAGE_METER_CATEGORY_DAMAGE or L["Damage"],
      types = { TYPE.DamageDone, TYPE.Dps, TYPE.DamageTaken, TYPE.AvoidableDamageTaken, TYPE.EnemyDamageTaken } },
    { name = _G.DAMAGE_METER_CATEGORY_HEALING or L["Healing"],
      types = { TYPE.HealingDone, TYPE.Hps, TYPE.Absorbs } },
    { name = _G.DAMAGE_METER_CATEGORY_ACTIONS or L["Actions"],
      types = { TYPE.Interrupts, TYPE.Dispels, TYPE.Deaths } },
}

local TYPE_NAMES = {
    DamageDone = { "DAMAGE_METER_TYPE_DAMAGE_DONE", "Damage Done" },
    Dps = { "DAMAGE_METER_TYPE_DPS", "Damage per Second" },
    HealingDone = { "DAMAGE_METER_TYPE_HEALING_DONE", "Healing Done" },
    Hps = { "DAMAGE_METER_TYPE_HPS", "Healing per Second" },
    Absorbs = { "DAMAGE_METER_TYPE_ABSORBS", "Absorbs" },
    Interrupts = { "DAMAGE_METER_TYPE_INTERRUPTS", "Interrupts" },
    Dispels = { "DAMAGE_METER_TYPE_DISPELS", "Dispels" },
    DamageTaken = { "DAMAGE_METER_TYPE_DAMAGE_TAKEN", "Damage Taken" },
    AvoidableDamageTaken = { "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN", "Avoidable Damage Taken" },
    Deaths = { "DAMAGE_METER_TYPE_DEATHS", "Deaths" },
    EnemyDamageTaken = { "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN", "Enemy Damage Taken" },
}

function ns.TypeName(t)
    for key, v in pairs(TYPE_NAMES) do
        if TYPE[key] == t then return _G[v[1]] or L[v[2]] end
    end
    return L["Unknown"]
end

-- Per second is the main number for these; the total goes in brackets.
ns.PER_SECOND_FIRST = { [TYPE.Dps or -1] = true, [TYPE.Hps or -1] = true }
-- No per second at all for these.
ns.NO_PER_SECOND = { [TYPE.Interrupts or -1] = true, [TYPE.Dispels or -1] = true, [TYPE.Deaths or -1] = true }
-- No class icon: the sources are enemies, coloured by who they fought for.
ns.NO_ICON = { [TYPE.EnemyDamageTaken or -1] = true }
-- Modes where your own row is kept in view.
ns.KEEP_SELF = {}
for _, key in ipairs({ "DamageDone", "Dps", "HealingDone", "Hps", "Absorbs", "Interrupts", "Dispels",
                       "DamageTaken", "AvoidableDamageTaken" }) do
    if TYPE[key] then ns.KEEP_SELF[TYPE[key]] = true end
end

--------------------------------------------------------------------------------
--  Reading sessions
--------------------------------------------------------------------------------
--- Can this client give us meter data at all? ok, reason.
function ns.Available()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then
        return false, L["This client has no damage meter data."]
    end
    if C_DamageMeter.IsDamageMeterAvailable then
        local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
        if ok and available == false then return false, reason end
    end
    return true
end

function ns.SessionType(win)
    return win.db.session == "overall" and SESSION.Overall or SESSION.Current
end

--- The session a window shows: { combatSources, maxAmount, totalAmount,
--- durationSeconds }, or nil. A picked past fight (win.sessionID) lives for
--- the session only; fight IDs don't survive a reload.
function ns.Session(win)
    if not ns.Available() then return nil end
    local ok, s
    if win.sessionID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, win.sessionID, win.db.mode)
    else
        ok, s = pcall(C_DamageMeter.GetCombatSessionFromType, ns.SessionType(win), win.db.mode)
    end
    return ok and s or nil
end

--- One source's spells, or nil with a reason. The source is asked for by
--- GUID, which the game only takes from us when it isn't secret.
function ns.Source(win, src)
    if not src then return nil end
    local guid, creature = src.sourceGUID, src.sourceCreatureID
    if EV.IsSecret(guid) or EV.IsSecret(creature) then
        return nil, L["The breakdown fills in when combat ends."]
    end
    local ok, s
    if win.sessionID then
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromID, win.sessionID, win.db.mode, guid, creature)
    else
        ok, s = pcall(C_DamageMeter.GetCombatSessionSourceFromType, ns.SessionType(win), win.db.mode, guid, creature)
    end
    if ok and s then return s end
    return nil, L["No breakdown for this one."]
end

--- Past fights, newest first: { sessionID, name, durationSeconds }.
function ns.Fights()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return {} end
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(list) ~= "table" then return {} end
    local out = {}
    for i = #list, 1, -1 do out[#out + 1] = list[i] end
    return out
end

--------------------------------------------------------------------------------
--  Formatting. Everything here takes a secret value without looking at it.
--------------------------------------------------------------------------------
local Abbrev = AbbreviateNumbers or AbbreviateLargeNumbers

-- One set of steps for both paths: two decimals below ten of a unit, one
-- below a hundred, none above ("1.23K", "12.3K", "123K"). Under a thousand a
-- whole number stays whole and anything else gets two decimals ("2.87").
local UNITS = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }

local function Readable(v)
    local n = math.abs(v)
    for _, u in ipairs(UNITS) do
        if n >= u[1] then
            local x = v / u[1]
            local ax = math.abs(x)
            local fmt = ax < 10 and "%.2f%s" or ax < 100 and "%.1f%s" or "%.0f%s"
            return fmt:format(x, u[2])
        end
    end
    if v == math.floor(v) then return ("%d"):format(v) end
    return ("%.2f"):format(v)
end

-- The same steps for a secret, which only the game can format: breakpoints
-- for AbbreviateNumbers, in the pairs its documentation describes
-- (significand x fraction = the unit). Rates get one more step below a
-- thousand for the two decimals; totals are whole and need none.
local function Steps(rate)
    local data = {}
    for _, u in ipairs(UNITS) do
        local unit = u[1]
        data[#data + 1] = { breakpoint = unit * 100, abbreviation = u[2], significandDivisor = unit, fractionDivisor = 1, abbreviationIsGlobal = false }
        data[#data + 1] = { breakpoint = unit * 10, abbreviation = u[2], significandDivisor = unit / 10, fractionDivisor = 10, abbreviationIsGlobal = false }
        data[#data + 1] = { breakpoint = unit, abbreviation = u[2], significandDivisor = unit / 100, fractionDivisor = 100, abbreviationIsGlobal = false }
    end
    if rate then
        data[#data + 1] = { breakpoint = 0, abbreviation = "", significandDivisor = 0.01, fractionDivisor = 100, abbreviationIsGlobal = false }
    end
    local opts = { breakpointData = data }
    if CreateAbbreviateConfig then
        local ok, config = pcall(CreateAbbreviateConfig, data)
        if ok and config then opts.config = config end
    end
    return opts
end

local STEPS, stepsRefused = {}, false

local function Secret(v, rate)
    if not stepsRefused then
        local key = rate and "rate" or "whole"
        STEPS[key] = STEPS[key] or Steps(rate)
        local ok, s = pcall(Abbrev, v, STEPS[key])
        if ok and type(s) ~= "nil" then return s end
        stepsRefused = true -- the game won't take our steps: its own from now on
    end
    local ok, s = pcall(Abbrev, v)
    if ok and type(s) ~= "nil" then return s end
    return v
end

--- A number for display. `rate` marks a per second value, which keeps two
--- decimals below a thousand.
-- Nil checks go by type(): comparing a secret, even with nil, is an error.
function ns.Short(v, rate)
    if type(v) == "nil" then return "0" end
    if EV.Usable(v) then
        if type(v) == "number" then return Readable(v) end
        return tostring(v)
    end
    if Abbrev then return Secret(v, rate) end
    return v
end

--- m:ss for a readable number of seconds, or nil.
function ns.Clock(seconds)
    if not EV.Usable(seconds) then return nil end
    seconds = math.floor(seconds + 0.5)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

--- A whole-number share, only when both values are readable.
function ns.Share(value, total)
    if EV.Usable(value) and EV.Usable(total) and total > 0 then
        return math.floor(value / total * 100 + 0.5)
    end
end

--- "main (paren, pct%)" into a font string. Formatting a secret happens in
--- the widget, which may refuse; then the main value is shown on its own.
function ns.SetValueText(fs, main, paren, pct, mainIsRate)
    local a = ns.Short(main, mainIsRate)
    local hasParen = type(paren) ~= "nil"
    local b = hasParen and ns.Short(paren, not mainIsRate) or nil
    local ok
    if hasParen and pct then ok = pcall(fs.SetFormattedText, fs, "%s (%s, %d%%)", a, b, pct)
    elseif hasParen then ok = pcall(fs.SetFormattedText, fs, "%s (%s)", a, b)
    elseif pct then ok = pcall(fs.SetFormattedText, fs, "%s (%d%%)", a, pct)
    else ok = pcall(fs.SetText, fs, a) end
    if not ok then pcall(fs.SetText, fs, a) end
end

--- A bar's colour: the class colour taken down, so white text reads on
--- the bright ones (rogue, priest, shaman) as well as the dark.
local BAR_SHADE = 0.6
function ns.BarColour(bar, r, g, b)
    bar:SetStatusBarColor(r * BAR_SHADE, g * BAR_SHADE, b * BAR_SHADE, 1)
end

--- Text on a bar: a solid shadow rather than the suite's soft one.
function ns.BarText(fs)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
end

--- A source's name: without its realm when we can read it.
function ns.Name(name)
    if EV.Usable(name) and type(name) == "string" then
        return Ambiguate and Ambiguate(name, "short") or name
    end
    return name
end

--------------------------------------------------------------------------------
--  The update loop: events mark windows dirty, a short ticker redraws them.
--  The ticker only does work while a window is shown and something changed.
--------------------------------------------------------------------------------
ns.windows = {}

function ns.MarkDirty(match)
    for _, w in ipairs(ns.windows) do
        if not match or match(w) then w.dirty = true end
    end
    if ns.Breakdown and ns.Breakdown.MarkDirty then ns.Breakdown:MarkDirty() end
end

local function Tick()
    if M.db.hidden and not EV.Movers:IsUnlocked() then return end
    for _, w in ipairs(ns.windows) do
        if w.dirty and w.frame:IsShown() then
            w.dirty = false
            w:Refresh()
        end
    end
    if ns.Breakdown and ns.Breakdown.Tick then ns.Breakdown:Tick() end
end

--------------------------------------------------------------------------------
--  The game's own meter windows. Switched off through its own setting
--  (the damageMeterEnabled CVar, which Blizzard_DamageMeter only reads to
--  decide whether to show its windows), and only put back if we were the
--  ones who switched it off.
--------------------------------------------------------------------------------
local BLIZZARD_CVAR = "damageMeterEnabled"

local function GetCVarValue(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

local function SetCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then return pcall(C_CVar.SetCVar, name, value) end
    if SetCVar then return pcall(SetCVar, name, value) end
end

function ns.ApplyBlizzard()
    local store = EV.DB:GetCharData("meter")
    local current = GetCVarValue(BLIZZARD_CVAR)
    if current == nil then return end
    if M.db.hideBlizzard and M:IsWanted() then
        if current ~= "0" and SetCVarValue(BLIZZARD_CVAR, "0") then
            store.turnedBlizzardOff = true
        end
    elseif store.turnedBlizzardOff then
        if SetCVarValue(BLIZZARD_CVAR, "1") then store.turnedBlizzardOff = nil end
    end
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
--- Runs whether or not the module is wanted, so switching the meter off
--- (which skips OnEnable) still gives the game's own meter back.
function M:OnInitialize()
    ns.ApplyBlizzard()
end

--- Called by the options page after any change.
function M:Refresh()
    for _, w in ipairs(ns.windows) do w:Apply() end
    ns.ApplyBlizzard()
    ns.MarkDirty()
end

function M:ShowAll(show)
    self.db.hidden = not show
    self:Refresh()
end

function M:OnEnable()
    for i = 1, ns.MAX_WINDOWS do
        ns.windows[i] = ns.CreateWindow(i)
    end

    local function ByType(t) return function(w) return w.db.mode == t end end
    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", function(_, _, t) ns.MarkDirty(ByType(t)) end)
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", function()
        ns.MarkDirty(function(w) return not w.sessionID and w.db.session == "current" end)
    end)
    self:RegisterEvent("DAMAGE_METER_RESET", function()
        for _, w in ipairs(ns.windows) do w.sessionID = nil; w.offset = 0 end
        ns.MarkDirty()
    end)
    -- Values become readable again: shares, names and breakdowns fill in.
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() ns.MarkDirty() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() ns.MarkDirty() end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
    self:RegisterMessage("EV_UNLOCK", function() self:Refresh() end)
    self:RegisterMessage("EV_LOCK", function() self:Refresh() end)

    C_Timer.NewTicker(0.2, Tick)

    EV:RegisterSlash("meter", function()
        self:ShowAll(self.db.hidden)
    end)

    self:Refresh()
end

function M:OnProfileChanged()
    self:Refresh()
end
