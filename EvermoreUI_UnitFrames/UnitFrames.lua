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

-- The parts a frame carries beyond its bars. Each unit starts from these
-- and overrides what differs (below).
local function Castbar(t)
    local c = {
        enabled = true, detached = false, width = 0, height = 18, gap = 4, x = 0,
        icon = true, iconSide = "LEFT", spark = true, showName = true, showTime = true,
        timeFormat = "remaining", fontSize = 11, texture = "", latency = true,
        hideBlizzard = true,
    }
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end

local function Auras(t)
    local a = {
        enabled = false, size = 24, spacing = 2, perRow = 8, max = 16,
        side = "TOP", align = "START", x = 0, y = 0,
        onlyMine = false, showTimer = true, timerSize = 10, showSwipe = true, sort = "default",
    }
    for k, v in pairs(t or {}) do a[k] = v end
    return a
end

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
        -- Colours. The border and background defaults are the plates' black
        -- and near-black; custom health and power only apply in "custom".
        borderColour = { 0, 0, 0 }, bgColour = { 0.031, 0.031, 0.031 },
        healthCustom = { 0.2, 0.75, 0.3 }, powerColour = "type", powerCustom = { 0.18, 0.45, 1 },
        nameColour = "white",
        -- Text: "" is General > Font. Positions are the layout this frame
        -- always had; offsets are pixels.
        font = "", powerFontSize = 0,
        namePoint = "LEFT", nameX = 5, nameY = 0, nameWidth = 0, nameParent = "health",
        healthPoint = "RIGHT", healthX = -5, healthY = 0, healthParent = "health",
        powerPoint = "RIGHT", powerX = -5, powerY = 0, powerParent = "power",
        -- Indicators.
        raidIconSize = 18, raidIconPoint = "TOP", raidIconX = 0, raidIconY = 0,
        leaderIcon = true, leaderIconSize = 14, leaderIconPoint = "TOPLEFT", leaderIconX = 8, leaderIconY = 0,
        pvpIcon = false, pvpIconSize = 24, pvpIconPoint = "BOTTOMLEFT", pvpIconX = 0, pvpIconY = 0,
        castbar = Castbar(),
        buffs = Auras(), debuffs = Auras(),
    }
    for k, v in pairs(t) do base[k] = v end
    return base
end

local DEFAULTS = {
    player       = Unit{ aggroBorder = true, powerTicks = true, powerTickGhost = true,
                         combatIcon = true, restingIcon = true, stateIconSize = 18, stateIconPoint = "TOPLEFT",
                         stateIconX = 2, stateIconY = -2,
                         -- Your own buffs and debuffs are the Buffs & Debuffs module's
                         -- job; these are here for anyone who wants them on the frame.
                         buffs = Auras{ side = "BOTTOM", perRow = 10 },
                         debuffs = Auras{ side = "TOP", perRow = 8, size = 26 },
                         -- Combo points above the frame, totems below it.
                         classPower = { enabled = true, side = "TOP", height = 8, spacing = 2,
                                        width = 0, x = 0, y = 0, colour = { 1, 0.86, 0.1 },
                                        hideEmpty = false },
                         totems = { enabled = true, size = 26, spacing = 3, side = "BOTTOM",
                                    align = "START", x = 0, y = 0, showTimer = true },
                         fader = { enabled = false, alpha = 0, combat = true, target = true,
                                   casting = true, health = true, power = false, mouseover = true } },
    -- On for the target: it answers the plate's question ("is this mob on
    -- me"), so the frame and the plate light together.
    -- Target auras: everyone's debuffs above the frame (who has Sunder up,
    -- whether it's sheeped), buffs under the cast bar (what to Purge or
    -- Tranquilize, or whether a friend already has your buff).
    target       = Unit{ portraitSide = "right", aggroBorder = true,
                         debuffs = Auras{ enabled = true, side = "TOP", size = 26, perRow = 8, max = 16 },
                         buffs = Auras{ enabled = true, side = "BOTTOM", size = 20, perRow = 10, max = 20 } },
    targettarget = Unit{ width = 130, height = 26, powerHeight = 4, portrait = "none",
                         healthText = "percent", powerText = "none", fontSize = 11, showLevel = false,
                         castbar = Castbar{ enabled = false, height = 12, icon = false, fontSize = 10 } },
    -- Focus: your own debuffs, the sheep or the sap you're keeping up.
    focus        = Unit{ width = 180, height = 32, powerHeight = 6, portrait = "none",
                         healthText = "percent", powerText = "none", fontSize = 12,
                         castbar = Castbar{ height = 16 },
                         debuffs = Auras{ side = "TOP", size = 22, perRow = 7, max = 7, onlyMine = true } },
    pet          = Unit{ width = 130, height = 26, powerHeight = 5, portrait = "none",
                         healthText = "percent", powerText = "none", fontSize = 11, showLevel = false,
                         happiness = true,
                         castbar = Castbar{ height = 12, icon = false, fontSize = 10 },
                         fader = { enabled = false, alpha = 0, combat = true, target = true,
                                   casting = true, health = true, power = false, mouseover = true } },
    -- Click casting on these frames (ClickCast.lua).
    clickCast    = { enabled = true, binds = {} },
}

-- Default HUD: player and target either side of centre, small frames tucked
-- under their outer edges, below the cast bars and the target's buffs that
-- hang under the big frames. Centre offsets from the middle of the screen.
local POSITIONS = {
    player       = { "CENTER", "CENTER", -280, -200 },
    target       = { "CENTER", "CENTER",  280, -200 },
    targettarget = { "CENTER", "CENTER",  335, -310 },
    pet          = { "CENTER", "CENTER", -335, -310 },
    focus        = { "CENTER", "CENTER", -280, -110 },
}

-- Where a cast bar goes the first time you detach it: the player's in the
-- classic spot above the action bars, the others under their frames.
local CAST_POSITIONS = {
    player       = { "CENTER", "CENTER", 0, -260 },
    target       = { "CENTER", "CENTER", 280, -250 },
    targettarget = { "CENTER", "CENTER", 335, -335 },
    focus        = { "CENTER", "CENTER", -280, -145 },
    pet          = { "CENTER", "CENTER", -335, -335 },
}

local M = EV:NewModule("UnitFrames", DEFAULTS)
ns.module = M
M.title = "Unit Frames"
M.description = "Clean, resizable player, target, target of target, focus and pet frames, with cast bars, buffs and debuffs, combo points and totems."
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
    if EV:Locked() then pendingLayout = true; return end
    if InCombatLockdown() then pendingLayout = true end   -- loading: again after combat
    -- Visibility first, before anything else is laid out: if a later step
    -- ever fails, a target or target-of-target frame must still be handed to
    -- the unit watch, not left standing on screen with no unit ("Offline").
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
    UF.Layout(f, cfg)
    ns.CastBar.Layout(f, cfg)
    ns.UnitAuras.Layout(f, cfg)
    EV.Movers:Apply("UF_" .. key)
    if f.castbar then EV.Movers:Apply("UF_" .. key .. "Cast") end
    UF.UpdateAll(f, cfg)
    ns.CastBar.Check(f.castbar)
    ns.Fader.Update(f)
    -- Combo points and totems size and sit by the player frame.
    if key == "player" and self:IsEnabled() then ns.ClassPower.Refresh() end
end

function M:Refresh()
    for _, u in ipairs(UNITS) do self:ApplyFrame(u.key) end
    -- The power tick strip anchors to the player's power bar, which the
    -- layout may just have moved or resized.
    if ns.RefreshClassic and self:IsEnabled() then ns.RefreshClassic() end
    if ns.ApplyClickCast and self:IsEnabled() then ns.ApplyClickCast() end
    if self:IsEnabled() then ns.ClassPower.Refresh() end
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
        ns.CastBar.Build(f)
        ns.UnitAuras.Build(f)
        f:HookScript("OnShow", function(self)
            UF.UpdateAll(self, M.db[self.key])
            ns.UnitAuras.Update(self)
        end)
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

        -- The cast bar's stand-in for edit mode, used when it's detached.
        EV.Movers:Register(f.castbar.proxy, "UF_" .. key .. "Cast", L[u.title] .. " " .. L["Cast Bar"],
            CAST_POSITIONS[key], {
            group = L["Unit Frames"], page = "unitframes", tab = L[u.title],
            getSize = function()
                local c = M.db[key].castbar
                return (c.width > 0) and c.width or M.db[key].width, c.height
            end,
            setSize = function(w, h)
                local c = M.db[key].castbar
                if w then c.width = w end
                if h then c.height = h end
                M:ApplyFrame(key)
            end,
            isDisabled = function()
                local c = M.db[key].castbar
                return not (M:IsEnabled() and M.db[key].enabled and c.enabled and c.detached)
            end,
        })
        local cc = self.db[u.key].castbar
        if cc.enabled and cc.hideBlizzard and self.db[u.key].enabled then ns.CastBar.RetireBlizzard(u.unit) end
        if u.key == "player" or u.key == "pet" then ns.Fader.Attach(f) end
    end
    ns.frames = frames

    local function Health(_, _, unit) ForUnit(unit, UF.UpdateHealth) end
    local function MaxHealth(_, _, unit) ForUnit(unit, function(f, c) UF.UpdateHealth(f, c) end) end
    local function Power(_, _, unit) ForUnit(unit, UF.UpdatePower) end
    local function Name(_, _, unit) ForUnit(unit, UF.UpdateName) end
    -- Declared here, defined below: the faction handler calls it, and a
    -- local declared after a closure is a global inside that closure.
    local Indicators
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
    -- A module keeps one handler per event, so faction does both jobs here:
    -- the unit's colours and its PvP flag.
    self:RegisterEvent("UNIT_FACTION", function(...)
        Colour(...)
        Indicators()
    end)
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
    -- A token that now means someone else: the aura containers follow the
    -- token, not the unit, so they are told to read again.
    local function Retoken(key)
        self:UpdateUnit(key)
        if frames[key] then ns.UnitAuras.Update(frames[key]) end
    end
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        Retoken("target"); Retoken("targettarget")
        AggroAll()   -- the restricted aggro path asks about the unit's target
    end)
    self:RegisterEvent("UNIT_TARGET", function(_, _, unit)
        if unit == "target" then Retoken("targettarget") end
    end)
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", function() Retoken("focus") end)
    self:RegisterEvent("UNIT_PET", function(_, _, unit)
        if unit == "player" then Retoken("pet") end
    end)
    Indicators = function()
        for _, f in pairs(frames) do
            if f:IsShown() then UF.UpdateIndicators(f, self.db[f.key]) end
        end
    end
    self:RegisterEvent("PARTY_LEADER_CHANGED", Indicators)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", Indicators)
    self:RegisterEvent("PLAYER_FLAGS_CHANGED", Indicators)
    self:RegisterEvent("PLAYER_UPDATE_RESTING", function() self:UpdateUnit("player") end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() UF.UpdateState(frames.player, self.db.player) end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        UF.UpdateState(frames.player, self.db.player)
        AggroAll()   -- threat drops out of combat without an event of its own
        if pendingLayout then pendingLayout = false; self:Refresh() end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)

    -- Target of target has no events of its own; poll it while it's up.
    C_Timer.NewTicker(0.2, function()
        local f = frames.targettarget
        if f and f:IsShown() and UnitExists("targettarget") then
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
    ns.CastBar.Enable(self)
    ns.Fader.Enable(self)
    -- Edit mode: cast bars show a preview to place, faded frames come back.
    self:RegisterMessage("EV_UNLOCK", function()
        ns.CastBar.PreviewAll(true); ns.Fader.UpdateAll()
    end)
    self:RegisterMessage("EV_LOCK", function()
        ns.CastBar.PreviewAll(false); ns.Fader.UpdateAll()
    end)
    ns.ClassPower.Enable(self)
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
    EV.Movers:Reset("UF_" .. key .. "Cast")
    self:ApplyFrame(key)
    if self:IsEnabled() then ns.ClassPower.Refresh() end
end

-- What "copy settings from" leaves alone: whether the frame is on at all,
-- Blizzard's frame, and the things only one unit has.
local NO_COPY = {
    enabled = true, hideBlizzard = true, happiness = true, powerTicks = true, powerTickGhost = true,
    classPower = true, totems = true, combatIcon = true, restingIcon = true,
    stateIconSize = true, stateIconPoint = true, stateIconX = true, stateIconY = true, fader = true,
}

--- Copy one unit's look onto another (options page). Sizes, colours, text,
--- cast bar and aura settings come across; position stays where it is.
function M:CopyUnit(from, to)
    if from == to or not (self.db[from] and self.db[to]) then return end
    local src, dest = self.db[from], self.db[to]
    for k, v in pairs(src) do
        if not NO_COPY[k] and DEFAULTS[to][k] ~= nil then
            dest[k] = type(v) == "table" and EV.CopyTable(v) or v
        end
    end
    self:ApplyFrame(to)
end

M.DEFAULTS = DEFAULTS

function M:GetFrame(key) return frames[key] end

--------------------------------------------------------------------------------
--  Designer preview
--
--  A copy of one frame for the designer's canvas: the same parts and the same
--  layout code as the real frame, on a plain (insecure) frame bound to you so
--  there is always a unit to draw. Casts, auras, pips and icons show samples,
--  so everything you might place is on screen at once.
--------------------------------------------------------------------------------
local PREVIEW_HEALTH = {
    curpercent = "12.3k  87%", percent = "87%", current = "12.3k",
    curmax = "12.3k / 14.1k", deficit = "-1.8k",
}
local PREVIEW_POWER = { current = "4,210", percent = "60%", curmax = "4.2k / 5k" }

function M:BuildPreview(key, parent)
    local f = CreateFrame("Frame", nil, parent)
    UF.Dress(f, key, "player", true)
    UF.AddSingleExtras(f)
    if key == "player" and not f.stateIcon then
        f.stateIcon = f.overlay:CreateTexture(nil, "OVERLAY")
        f.stateIcon:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
    end
    ns.CastBar.Build(f, true)
    ns.UnitAuras.Build(f)
    return f
end

--- Lay the preview out from the saved settings and fill in samples.
function M:LayoutPreview(f)
    local cfg = self.db[f.key]
    UF.Layout(f, cfg)
    ns.CastBar.Layout(f, cfg)
    ns.UnitAuras.Layout(f, cfg)
    ns.ClassPower.Preview(f, cfg)
    UF.UpdateAll(f, cfg)
    -- Plain samples over whatever the unit gave us. Health, power and even
    -- your name can come back secret, and anything showing a secret reports
    -- secret geometry, which the designer can't measure or drag.
    f.health:SetMinMaxValues(0, 1); f.health:SetValue(0.87)
    f.power:SetMinMaxValues(0, 1); f.power:SetValue(0.6)
    f.heal:Hide()
    f.statusText:Hide()
    local okN, name = pcall(UnitName, "player")
    if not okN or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then name = L["Name"] end
    f.nameText:SetText((cfg.showLevel and "60 " or "") .. name)
    f.healthText:SetText(PREVIEW_HEALTH[cfg.healthText] or "")
    f.powerText:SetText(PREVIEW_POWER[cfg.powerText] or "")
    ns.CastBar.Preview(f.castbar, true)
    -- Every icon you can place, shown whether or not it applies to you now.
    f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    if SetRaidTargetIconTexture then SetRaidTargetIconTexture(f.raidIcon, 8) end
    f.raidIcon:Show()
    if f.leaderIcon then
        f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        f.leaderIcon:SetShown(cfg.leaderIcon and true or false)
    end
    if f.pvpIcon then
        f.pvpIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Horde")
        f.pvpIcon:SetTexCoord(0, 0.62, 0, 0.62)
        f.pvpIcon:SetShown(cfg.pvpIcon and true or false)
    end
    if f.stateIcon then
        f.stateIcon:SetTexCoord(0.5, 1, 0, 0.49)
        f.stateIcon:SetShown(cfg.combatIcon ~= false or cfg.restingIcon ~= false)
    end
    f:SetAlpha(1)
    f:Show()
end

M.CAST_LIVE = ns.CastBar.LIVE
