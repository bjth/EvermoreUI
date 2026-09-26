if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UnitFrames.lua
--  Module: creates the frames, routes events to them, applies settings, and
--  retires Blizzard's frames for any unit we're drawing.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L
local UF = ns.Frame

--------------------------------------------------------------------------------
--  Units and defaults
--------------------------------------------------------------------------------
local UNITS = {
    { key = "player",       unit = "player",       title = "Player" },
    { key = "target",       unit = "target",       title = "Target" },
    { key = "targettarget", unit = "targettarget", title = "Target of Target" },
    { key = "focus",        unit = "focus",        title = "Focus" },
    { key = "pet",          unit = "pet",          title = "Pet" },
}
ns.UNITS = UNITS

local function Unit(t)
    local base = {
        enabled = true, width = 240, height = 46, powerHeight = 10,
        portrait = "3d", portraitSide = "left",
        healthColour = "class", healthText = "curpercent", powerText = "current",
        showName = true, showLevel = true, fontSize = 13,
        -- Text edge and bar shade match the nameplates' defaults, so the
        -- target frame and the target's plate read as one design.
        textStyle = "both", barShade = 0.75,
        texture = "Flat", bgAlpha = 0.85, hideBlizzard = true,
        -- The plates' frame: a hard black 2px edge, the measured inset ramp
        -- on the health bar, and their red aggro glow at their strength.
        borderSize = 2, innerShadow = true,
        healPrediction = true, aggroBorder = false, aggroAlpha = 0.35, aggroPad = 8,
    }
    for k, v in pairs(t) do base[k] = v end
    return base
end

local DEFAULTS = {
    player       = Unit{ aggroBorder = true, powerTicks = true, powerTickGhost = true },
    -- On for the target: it answers the plate's question ("is this mob on
    -- me"), so the frame and the plate light together.
    target       = Unit{ portraitSide = "right", aggroBorder = true },
    targettarget = Unit{ width = 130, height = 26, powerHeight = 4, portrait = "none",
                         healthText = "percent", powerText = "none", fontSize = 11, showLevel = false },
    focus        = Unit{ width = 180, height = 32, powerHeight = 6, portrait = "none",
                         healthText = "percent", powerText = "none", fontSize = 12 },
    pet          = Unit{ width = 130, height = 26, powerHeight = 5, portrait = "none",
                         healthText = "percent", powerText = "none", fontSize = 11, showLevel = false,
                         happiness = true },
    -- Click casting on these frames (ClickCast.lua).
    clickCast    = { enabled = true, binds = {} },
}

-- Default HUD: player and target either side of centre, small frames tucked
-- under their outer edges. Centre offsets from the middle of the screen.
local POSITIONS = {
    player       = { "CENTER", "CENTER", -280, -200 },
    target       = { "CENTER", "CENTER",  280, -200 },
    targettarget = { "CENTER", "CENTER",  335, -242 },
    pet          = { "CENTER", "CENTER", -335, -242 },
    focus        = { "CENTER", "CENTER", -280, -110 },
}

local M = EV:NewModule("UnitFrames", DEFAULTS)
ns.module = M
M.title = "Unit Frames"
M.description = "Clean, resizable player, target, target of target, focus and pet frames."
M.UNITS = UNITS

local frames = {}      -- key -> frame
local byUnit = {}      -- unit token -> frame
local pendingLayout = false

--------------------------------------------------------------------------------
--  Blizzard's frames
--------------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local BLIZZARD = {
    player = "PlayerFrame", target = "TargetFrame", focus = "FocusFrame",
    pet = "PetFrame", targettarget = "TargetFrameToT",
}

local function RetireBlizzard(key)
    local f = _G[BLIZZARD[key]]
    if not f or f.evRetired then return end
    f.evRetired = true
    if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    f:Hide()
    f:SetParent(hiddenParent)
end

--------------------------------------------------------------------------------
--  Applying settings
--------------------------------------------------------------------------------
function M:ApplyFrame(key)
    local f, cfg = frames[key], self.db[key]
    if not f then return end
    if InCombatLockdown() then pendingLayout = true; return end
    UF.Layout(f, cfg)
    if cfg.enabled then
        if f.unit == "player" then
            f:Show()
        else
            RegisterUnitWatch(f)
        end
    else
        if f.unit ~= "player" then UnregisterUnitWatch(f) end
        f:Hide()
    end
    EV.Movers:Apply("UF_" .. key)
    UF.UpdateAll(f, cfg)
end

function M:Refresh()
    for _, u in ipairs(UNITS) do self:ApplyFrame(u.key) end
    -- The power tick strip anchors to the player's power bar, which the
    -- layout may just have moved or resized.
    if ns.RefreshClassic and self:IsEnabled() then ns.RefreshClassic() end
    if ns.ApplyClickCast and self:IsEnabled() then ns.ApplyClickCast() end
end

function M:UpdateUnit(key)
    local f = frames[key]
    if f and f:IsShown() then UF.UpdateAll(f, self.db[key]) end
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local function ForUnit(unit, fn)
    local f = byUnit[unit]
    if f and f:IsShown() then fn(f, M.db[f.key]) end
end

function M:OnEnable()
    for _, u in ipairs(UNITS) do
        local f = UF.Create(u.key, u.unit)
        frames[u.key], byUnit[u.unit] = f, f
        f:HookScript("OnShow", function(self) UF.UpdateAll(self, M.db[self.key]) end)
        local key = u.key
        EV.Movers:Register(f, "UF_" .. key, L[u.title], POSITIONS[key], {
            group = L["Unit Frames"], page = "unitframes", tab = L[u.title],
            getSize = function() return M.db[key].width, M.db[key].height end,
            setSize = function(w, h)
                if w then M.db[key].width = w end
                if h then M.db[key].height = h end
                M:ApplyFrame(key)
            end,
            isDisabled = function() return not (M:IsEnabled() and M.db[key].enabled) end,
        })
        if self.db[u.key].hideBlizzard and self.db[u.key].enabled then RetireBlizzard(u.key) end
    end
    ns.frames = frames

    local function Health(_, _, unit) ForUnit(unit, UF.UpdateHealth) end
    local function MaxHealth(_, _, unit) ForUnit(unit, function(f, c) UF.UpdateHealth(f, c) end) end
    local function Power(_, _, unit) ForUnit(unit, UF.UpdatePower) end
    local function Name(_, _, unit) ForUnit(unit, UF.UpdateName) end
    local function Colour(_, _, unit)
        -- Aggro too: turning hostile or friendly changes which question the
        -- glow asks (Frame.lua, UF.UpdateAggro).
        ForUnit(unit, function(f, c)
            UF.UpdateHealthColour(f, c); UF.UpdateHealth(f, c); UF.UpdateName(f, c); UF.UpdateAggro(f, c)
        end)
    end
    local function Portrait(_, _, unit) ForUnit(unit, UF.UpdatePortrait) end
    local function Aggro(_, _, unit) ForUnit(unit, UF.UpdateAggro) end
    local function AggroAll()
        for _, f in pairs(frames) do
            if f:IsShown() then UF.UpdateAggro(f, M.db[f.key]) end
        end
    end

    self:RegisterEvent("UNIT_HEALTH", Health)
    self:RegisterEvent("UNIT_MAXHEALTH", MaxHealth)
    -- Incoming heals share the health update: the calculator clamps them
    -- against current health, so a health change moves them too.
    self:RegisterEvent("UNIT_HEAL_PREDICTION", Health)
    self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", Health)
    self:RegisterEvent("UNIT_POWER_UPDATE", Power)
    self:RegisterEvent("UNIT_POWER_FREQUENT", Power)
    self:RegisterEvent("UNIT_MAXPOWER", Power)
    self:RegisterEvent("UNIT_DISPLAYPOWER", Power)
    self:RegisterEvent("UNIT_NAME_UPDATE", Name)
    self:RegisterEvent("UNIT_LEVEL", Name)
    self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED", Name)
    self:RegisterEvent("UNIT_FACTION", Colour)
    self:RegisterEvent("UNIT_CONNECTION", Colour)
    self:RegisterEvent("UNIT_FLAGS", Colour)
    self:RegisterEvent("UNIT_PORTRAIT_UPDATE", Portrait)
    self:RegisterEvent("UNIT_MODEL_CHANGED", Portrait)
    -- UNIT_THREAT_SITUATION_UPDATE names the unit whose threat moved, so it
    -- routes like any other unit event. UNIT_THREAT_LIST_UPDATE names the mob,
    -- which is never a unit of ours, so that one refreshes the lot: five
    -- frames, and only while something is in combat.
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", Aggro)
    self:RegisterEvent("UNIT_THREAT_LIST_UPDATE", AggroAll)
    self:RegisterEvent("RAID_TARGET_UPDATE", function()
        for _, f in pairs(frames) do if f:IsShown() then UF.UpdateRaidIcon(f) end end
    end)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        self:UpdateUnit("target"); self:UpdateUnit("targettarget")
        AggroAll()   -- the restricted aggro path asks about the unit's target
    end)
    self:RegisterEvent("UNIT_TARGET", function(_, _, unit)
        if unit == "target" then self:UpdateUnit("targettarget") end
    end)
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", function() self:UpdateUnit("focus") end)
    self:RegisterEvent("UNIT_PET", function(_, _, unit)
        if unit == "player" then self:UpdateUnit("pet") end
    end)
    self:RegisterEvent("PLAYER_UPDATE_RESTING", function() self:UpdateUnit("player") end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() UF.UpdateState(frames.player) end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        UF.UpdateState(frames.player)
        AggroAll()   -- threat drops out of combat without an event of its own
        if pendingLayout then pendingLayout = false; self:Refresh() end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)

    -- Target of target has no events of its own; poll it while it's up.
    C_Timer.NewTicker(0.2, function()
        local f = frames.targettarget
        if f and f:IsShown() then
            local c = self.db.targettarget
            UF.UpdateHealthColour(f, c); UF.UpdateHealth(f, c); UF.UpdatePower(f, c); UF.UpdateName(f, c)
        end
    end)

    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
    self:RegisterMessage("EV_THEME_CHANGED", function() self:Refresh() end)
    self:RegisterMessage("EV_PALETTE_CHANGED", function()
        UF.ClearColourCache()
        self:Refresh()
    end)
    -- General > Font: the slug object follows the face, so restyle now
    -- rather than waiting for a reload.
    self:RegisterMessage("EV_FONT_CHANGED", function() self:Refresh() end)
    self:Refresh()
    if ns.EnableClassic then ns.EnableClassic() end
end

function M:OnProfileChanged()
    self:Refresh()
end

--- Reset one unit to defaults (options page).
function M:ResetUnit(key)
    wipe(self.db[key])
    EV.DB.Merge(self.db[key], DEFAULTS[key])
    EV.Movers:Reset("UF_" .. key)
    self:ApplyFrame(key)
end

function M:GetFrame(key) return frames[key] end
