if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Cooldowns.lua
--  Your cooldowns and tracked buffs in EvermoreUI bars.
--
--  The game's Cooldown Manager (Blizzard_CooldownViewer) does the tracking:
--  which spells, their cooldowns, charges, procs, range and the buffs they
--  leave, all of it safe with secret values in combat. Its four viewers keep
--  a pool of item frames each. We don't build icons of our own; we take those
--  item frames, square them off in our style and set them out in our own bar
--  frames, which move with /evui edit like everything else.
--
--  Rules, most learnt the hard way by other addons doing the same:
--    * Never SetParent, SetScale, Show or Hide a viewer or an item, and never
--      write a field on one (not even one Blizzard owns). Per-frame state lives
--      in weak-keyed tables here. Reading fields is fine.
--    * Items only get SetPoint, SetSize, SetAlpha and a font or two. The
--      viewers themselves are Edit Mode systems and are left where they are.
--    * Blizzard lays its items out again whenever its list changes
--      (GridLayoutFrameMixin.Layout); a post-hook on each viewer's Layout puts
--      them back into our bars straight after.
--    * Buff items show and hide themselves as buffs come and go. Per-item
--      OnShow/OnHide hooks close the gaps.
--    * A bar that is hidden parks its items off screen rather than hiding
--      them: hiding a pooled frame makes Blizzard rebuild the pool.
--    * Each bar's size comes from everything it tracks, not what's showing,
--      so it doesn't jump about as buffs come and go.
--
--  The buff bar viewer (BuffBarCooldownViewer) is left to Blizzard for now.
--
--  Keybind and rank text: for each cooldown, the key of the first action
--  button that casts it (directly or through a macro) and the rank you'd
--  cast. Built from the action buttons themselves (their current `action`
--  slot and binding command), so paging, stances and our own Action Bars
--  module are all covered, and matched by spell name so every rank counts.
--
--  Linked timers: a swipe of our own over a cooldown's icon for a set time
--  after you cast it, e.g. Power Word: Shield showing Weakened Soul's 15
--  seconds. The game hides a friendly player's debuffs from addons in combat
--  in an instance, and won't match them by spell ID at all, so the timer runs
--  from your cast (UNIT_SPELLCAST_SUCCEEDED) rather than from the debuff. It
--  follows your last cast, whoever it was on. The overlay is our own Cooldown
--  frame fed plain numbers, a child of the item, keyed by spell name so it
--  covers every rank and survives the pool handing the icon to another frame.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local function BarDefaults(size, perRow, grow, rows, keys)
    return {
        keys       = keys,        -- keybind text
        keyPoint   = "TOPRIGHT", keyX = -2, keyY = -2, keySize = 0,     -- 0 = scaled to the icon
        rank       = false,       -- spell rank text
        rankPoint  = "TOPLEFT",  rankX = 2,  rankY = -2, rankSize = 0,
        enabled    = true,
        size       = size,
        spacing    = 2,
        perRow     = perRow,
        grow       = grow,        -- "CENTER", "RIGHT", "LEFT"
        rows       = rows,        -- "DOWN", "UP"
        visibility = "always",    -- "always", "combat", "fade", "hidden"
        fade       = 0.5,         -- opacity out of combat with "fade"
    }
end

local M = EV:NewModule("Cooldowns", {
    timers = {},        -- [CLASS] = { { spell = id, seconds = n }, ... }
    timersSeeded = {},  -- [CLASS] = true once the class starters are in
    bars = {
        essential = BarDefaults(42, 8, "CENTER", "DOWN", true),
        utility   = BarDefaults(32, 10, "CENTER", "DOWN", true),
        buffs     = BarDefaults(34, 10, "CENTER", "UP", false),
    },
})
M.title = "Cooldowns"
M.description = "Your cooldowns and tracked buffs in EvermoreUI bars, built on the game's own Cooldown Manager."
ns.module = M

local BARS = {
    { key = "essential", viewer = "EssentialCooldownViewer", label = L["Essential cooldowns"],
      pos = { "CENTER", "CENTER", 0, -190 } },
    { key = "utility",   viewer = "UtilityCooldownViewer",   label = L["Utility cooldowns"],
      pos = { "CENTER", "CENTER", 0, -236 } },
    { key = "buffs",     viewer = "BuffIconCooldownViewer",  label = L["Tracked buffs"],
      pos = { "CENTER", "CENTER", 0, -140 }, buff = true },
}
M.BARS = BARS

-- Starter linked timers per class, by rank 1 spell ID (names come from the
-- client, so they match every rank and any language).
local TIMER_SEEDS = {
    PRIEST = { { spell = 17, seconds = 15 } },   -- Power Word: Shield -> Weakened Soul
}

local PARK_X, PARK_Y = -10000, 10000
local OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local state = setmetatable({}, { __mode = "k" })   -- item frame -> our notes
local hookedViewer = setmetatable({}, { __mode = "k" })
local holders = {}                                  -- bar key -> our frame
local busy = {}                                     -- bar key -> laying out now
local inCombat = false

--------------------------------------------------------------------------------
--  Reading the game's side
--------------------------------------------------------------------------------
local function Viewer(def) return _G[def.viewer] end

--- Items with a cooldown assigned, in Blizzard's order. `all` includes the
--- ones currently hidden (inactive buffs).
local function Items(def, all)
    local out = {}
    local v = Viewer(def)
    local pool = v and v.itemFramePool
    if not pool then return out end
    for f in pool:EnumerateActive() do
        if f.cooldownID ~= nil and (all or f:IsShown()) then out[#out + 1] = f end
    end
    table.sort(out, function(a, b) return (a.layoutIndex or 0) < (b.layoutIndex or 0) end)
    return out
end

function M.BlizzardOn()
    return GetCVar and GetCVar("cooldownViewerEnabled") == "1"
end

function M.SetBlizzardOn(on)
    pcall(SetCVar, "cooldownViewerEnabled", on and "1" or "0")
end

--- Why a bar might be empty, in words, or nil when all is well.
function M.Problem(def)
    if not M.BlizzardOn() then
        return L["The game's Cooldown Manager is switched off."]
    end
    if C_CooldownViewer and C_CooldownViewer.IsCooldownViewerAvailable then
        local ok, available = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
        if ok and available == false then return L["The game says its Cooldown Manager isn't available on this character."] end
    end
    local v = Viewer(def)
    if not v then return L["The game's Cooldown Manager hasn't loaded."] end
    local VS = Enum and Enum.CooldownViewerVisibleSetting
    if VS and v.visibleSetting and v.visibleSetting ~= VS.Always then
        return L["In Blizzard's Edit Mode this viewer isn't set to always show, so it can only appear when the game allows. Set its Visibility to Always and use the setting here instead."]
    end
end

--------------------------------------------------------------------------------
--  The look: square icons, our border, our fonts
--------------------------------------------------------------------------------
local function Flatten(region)
    if region and region.IsObjectType and region:IsObjectType("MaskTexture") then
        pcall(region.SetTexture, region, WHITE)
    end
end

local Relayout

local function Skin(f, def)
    local s = state[f]
    if s then return s end
    s = { def = def }
    state[f] = s

    for _, r in ipairs({ f:GetRegions() }) do
        Flatten(r)
        if r ~= f.Icon and r.GetObjectType and r:GetObjectType() == "Texture"
           and r.GetAtlas and r:GetAtlas() == OVERLAY_ATLAS then
            r:SetAlpha(0)
        end
    end
    local cd = f.Cooldown
    if cd then
        for _, r in ipairs({ cd:GetRegions() }) do Flatten(r) end
        if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, WHITE) end
    end
    if f.Icon and f.Icon.SetTexCoord then f.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    local edge = CreateFrame("Frame", nil, f)
    edge:SetAllPoints(f)
    edge:EnableMouse(false)
    edge:SetFrameLevel(f:GetFrameLevel() + 3)
    T.TokenBorder(edge, "border")
    s.edge = edge

    if def.buff then
        f:HookScript("OnShow", function() Relayout(def) end)
        f:HookScript("OnHide", function() Relayout(def) end)
    end
    return s
end

local function Fonts(f, s, size)
    if s.fontSize == size then return end
    s.fontSize = size
    local font = EV.Media:Fetch("font")
    local cd = f.Cooldown
    local timer = cd and cd.GetCountdownFontString and cd:GetCountdownFontString()
    if timer then timer:SetFont(font, max(9, floor(size * 0.36 + 0.5)), "OUTLINE") end
    local small = max(8, floor(size * 0.3 + 0.5))
    local charges = f.ChargeCount and f.ChargeCount.Current
    local stacks = f.Applications and f.Applications.Applications
    if charges then charges:SetFont(font, small, "OUTLINE") end
    if stacks then stacks:SetFont(font, small, "OUTLINE") end
end

--------------------------------------------------------------------------------
--  Keybinds and ranks
--------------------------------------------------------------------------------
-- Button name prefix -> binding command prefix, main bar first so its key
-- wins when a spell is on more than one bar.
local BUTTONS = {
    { "ActionButton",              "ACTIONBUTTON" },
    { "MultiBarBottomLeftButton",  "MULTIACTIONBAR1BUTTON" },
    { "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
    { "MultiBarRightButton",       "MULTIACTIONBAR3BUTTON" },
    { "MultiBarLeftButton",        "MULTIACTIONBAR4BUTTON" },
    { "MultiBar5Button",           "MULTIACTIONBAR5BUTTON" },
    { "MultiBar6Button",           "MULTIACTIONBAR6BUTTON" },
    { "MultiBar7Button",           "MULTIACTIONBAR7BUTTON" },
}

local keysByName, keysDirty = {}, true

--- The spell an action slot casts, or nil.
local function SlotSpell(slot)
    if type(slot) ~= "number" then return nil end
    local ok, kind, id = pcall(GetActionInfo, slot)
    if not ok then return nil end
    if kind == "spell" then return id end
    if kind == "macro" and type(GetMacroSpell) == "function" then
        local okM, sid = pcall(GetMacroSpell, id)
        return okM and sid or nil
    end
end

local SpellName

local function BuildKeys()
    keysDirty = false
    wipe(keysByName)
    for _, def in ipairs(BUTTONS) do
        for i = 1, 12 do
            local b = _G[def[1] .. i]
            local slot = b and b.action
            local spell = SlotSpell(slot)
            local name = spell and SpellName(spell)
            if name and not keysByName[name] then
                local command = b.bindingAction or b.commandName or (def[2] .. i)
                local key = GetBindingKey(command)
                keysByName[name] = { key = key and EV.ShortKey(key) or nil, spell = spell }
            end
        end
    end
end

--- Rank number you'd cast: the bar's copy if it's on one, else the highest
--- the spellbook knows by that name.
local function RankOf(name)
    local entry = keysByName[name]
    local id = entry and entry.spell
    if not id and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        id = ok and type(info) == "table" and info.spellID or nil
    end
    if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return nil end
    local ok, sub = pcall(C_Spell.GetSpellSubtext, id)
    if not ok or type(sub) ~= "string" or (issecretvalue and issecretvalue(sub)) then return nil end
    return sub:match("(%d+)")
end

local ItemSpell

local JUSTIFY = {
    TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT",
    TOP = "CENTER", CENTER = "CENTER", BOTTOM = "CENTER",
    TOPRIGHT = "RIGHT", RIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
}

--- One of the two corner texts, placed and sized from the bar's settings.
local function Label(s, field, text, db, prefix, size, r, g, b)
    local fs = s[field]
    if not text then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = s.edge:CreateFontString(nil, "OVERLAY")
        s[field] = fs
    end
    local point = db[prefix .. "Point"] or "CENTER"
    local px = tonumber(db[prefix .. "Size"]) or 0
    if px <= 0 then px = max(8, floor(size * 0.28 + 0.5)) end
    fs:SetFont(EV.Media:Fetch("font"), px, "OUTLINE")
    fs:ClearAllPoints()
    fs:SetPoint(point, s.edge, point, tonumber(db[prefix .. "X"]) or 0, tonumber(db[prefix .. "Y"]) or 0)
    fs:SetJustifyH(JUSTIFY[point] or "CENTER")
    fs:SetTextColor(r, g, b)
    fs:SetText(text)
    fs:Show()
end

local function Texts(f, s, db, size)
    if keysDirty then BuildKeys() end
    local name = ItemSpell(f)
    local key = db.keys and name and keysByName[name] and keysByName[name].key or nil
    Label(s, "key", key, db, "key", size, 1, 1, 1)
    local rank = db.rank and name and RankOf(name) or nil
    Label(s, "rank", rank and ("R" .. rank) or nil, db, "rank", size, 1, 0.82, 0)
end

--------------------------------------------------------------------------------
--  Linked timers
--------------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local running = {}      -- spell name -> { start, duration }
local playerClass

function SpellName(id)
    if type(id) ~= "number" or issecret(id) then return nil end
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and type(n) == "string" and not issecret(n) then return n end
end
M.SpellName = SpellName

--- The spell an item stands for, by name.
function ItemSpell(f)
    local info = f.cooldownInfo
    if type(info) ~= "table" then return nil end
    return SpellName(info.overrideSpellID) or SpellName(info.spellID)
end

function M:Timers()
    local all = self.db.timers
    playerClass = playerClass or select(2, UnitClass("player"))
    if not playerClass then return {} end
    if not self.db.timersSeeded[playerClass] then
        self.db.timersSeeded[playerClass] = true
        all[playerClass] = all[playerClass] or {}
        for _, seed in ipairs(TIMER_SEEDS[playerClass] or {}) do
            all[playerClass][#all[playerClass] + 1] = { spell = seed.spell, seconds = seed.seconds }
        end
    end
    all[playerClass] = all[playerClass] or {}
    return all[playerClass]
end

local function TimerFor(name)
    if not name then return nil end
    for _, t in ipairs(M:Timers()) do
        if SpellName(t.spell) == name then return t end
    end
end

-- While a linked timer runs, the item's own cooldown (swipe and countdown)
-- is out of sight under ours, and comes straight back when ours ends. Only
-- the alpha of Blizzard's Cooldown child is touched; its timing is left alone.
local function Under(f, s, a)
    if s.underAlpha == a or not f.Cooldown then return end
    s.underAlpha = a
    f.Cooldown:SetAlpha(a)
end

local function EndTimer(f, s)
    if s.timer then
        s.timer:Clear()
        s.timer:Hide()
    end
    s.ends = nil
    Under(f, s, 1)
    if s.edge then T.SetBorderToken(s.edge, "border") end
end

local function Overlay(f, s)
    if s.timer then return s.timer end
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetFrameLevel(f:GetFrameLevel() + 4)
    cd:SetDrawEdge(false)
    cd:SetDrawBling(false)
    cd:SetSwipeTexture(WHITE)
    cd:SetHideCountdownNumbers(false)
    cd:SetScript("OnCooldownDone", function() EndTimer(f, s) end)
    s.timer = cd
    return cd
end

local function ShowTimer(f, s)
    local name = ItemSpell(f)
    local r = name and running[name]
    local now = GetTime()
    if r and now < r[1] + r[2] then
        local cd = Overlay(f, s)
        local ar, ag, ab = T.RGBA("accent")
        cd:SetSwipeColor(ar, ag, ab, 0.35)
        cd:SetCooldown(r[1], r[2])
        cd:Show()
        s.ends = r[1] + r[2]
        Under(f, s, 0)
        local font = EV.Media:Fetch("font")
        local fs = cd.GetCountdownFontString and cd:GetCountdownFontString()
        if fs then fs:SetFont(font, max(9, floor((s.size or 36) * 0.36 + 0.5)), "OUTLINE") end
        if s.edge then T.SetBorderToken(s.edge, "accent") end
    elseif s.timer or s.underAlpha ~= nil then
        EndTimer(f, s)
    end
end

local function TimerBars()
    for _, def in ipairs(BARS) do
        if not def.buff then
            for _, f in ipairs(Items(def, true)) do
                local s = state[f]
                if s then ShowTimer(f, s) end
            end
        end
    end
end

local function OnCast(spellID)
    local name = SpellName(spellID)
    local t = TimerFor(name)
    if not t then return end
    running[name] = { GetTime(), tonumber(t.seconds) or 15 }
    TimerBars()
end

--------------------------------------------------------------------------------
--  Layout
--------------------------------------------------------------------------------
--- Opacity for a bar right now, or nil when it should be out of sight.
local function Opacity(db)
    local v = db.visibility
    if v == "hidden" then return nil end
    if not inCombat then
        if v == "combat" then return nil end
        if v == "fade" then return db.fade end
    end
    return 1
end

local function Park(f)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", PARK_X, PARK_Y)
end

local function Place(bar, def)
    local db = M.db.bars[def.key]
    local all = Items(def, true)
    local shown = def.buff and Items(def, false) or all

    local size, gap = db.size, db.spacing
    local per = max(1, db.perRow)
    local n = max(1, #all)
    local cols, rows = min(n, per), ceil(n / per)
    local W = cols * size + (cols - 1) * gap
    local H = rows * size + (rows - 1) * gap
    bar:SetSize(W, H)

    -- Skin (and hook) every item, not only the ones showing: an inactive buff
    -- needs its OnShow hook in place before it first appears.
    for _, f in ipairs(all) do Skin(f, def) end

    local alpha = Opacity(db)
    local count = #shown
    local barScale = bar:GetEffectiveScale()
    for i, f in ipairs(shown) do
        local s = Skin(f, def)
        if alpha then
            -- SetPoint offsets and sizes are in the item's own scale, which is
            -- the viewer's icon scale from Edit Mode; convert from ours.
            local k = barScale / f:GetEffectiveScale()
            local idx = i - 1
            local r, c = floor(idx / per), idx % per
            local inRow = min(per, count - r * per)
            local x
            if db.grow == "LEFT" then
                x = W - size - c * (size + gap)
            elseif db.grow == "CENTER" then
                x = (W - (inRow * size + (inRow - 1) * gap)) / 2 + c * (size + gap)
            else
                x = c * (size + gap)
            end
            local y = r * (size + gap)
            if s.size ~= size or s.k ~= k then
                s.size, s.k = size, k
                f:SetSize(size * k, size * k)
            end
            f:ClearAllPoints()
            if db.rows == "UP" then
                f:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x * k, y * k)
            else
                f:SetPoint("TOPLEFT", bar, "TOPLEFT", x * k, -y * k)
            end
            f:SetAlpha(alpha)
            Fonts(f, s, size)
            Texts(f, s, db, size)
            if not def.buff then ShowTimer(f, s) end
        else
            Park(f)
        end
    end
end

function Relayout(def)
    if not M:IsEnabled() then return end
    local db = M.db.bars[def.key]
    local bar = holders[def.key]
    if not (bar and db and db.enabled) or busy[def.key] then return end
    busy[def.key] = true
    local ok, err = pcall(Place, bar, def)
    busy[def.key] = nil
    if not ok then geterrorhandler()(err) end
end

function M:LayoutAll()
    for _, def in ipairs(BARS) do Relayout(def) end
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
local function Build(def)
    if holders[def.key] then return end
    local bar = CreateFrame("Frame", "EvermoreUICooldowns_" .. def.key, UIParent)
    bar:SetSize(40, 40)
    holders[def.key] = bar
    EV.Movers:Register(bar, "CD_" .. def.key, def.label, def.pos, {
        group = L["Combat"], page = "cooldowns", tab = def.label,
        isDisabled = function() return not (M:IsEnabled() and M.db.bars[def.key].enabled) end,
    })
end

local function Attach()
    for _, def in ipairs(BARS) do
        local v = Viewer(def)
        if v and not hookedViewer[v] and type(v.Layout) == "function" then
            hookedViewer[v] = true
            hooksecurefunc(v, "Layout", function() Relayout(def) end)
        end
    end
    M:LayoutAll()
end

function M:OnEnable()
    for _, def in ipairs(BARS) do Build(def) end

    -- The module is built on the game's Cooldown Manager, which is off by
    -- default. Switch it on once; after that it's the user's to change.
    if not M.BlizzardOn() and not self.db.turnedOn then
        self.db.turnedOn = true
        M.SetBlizzardOn(true)
        EV:Print(L["Switched on the game's Cooldown Manager, which the Cooldowns bars are built on."])
    end

    inCombat = InCombatLockdown() and true or false
    if C_AddOns.IsAddOnLoaded("Blizzard_CooldownViewer") then
        Attach()
    else
        self:RegisterEvent("ADDON_LOADED", function(_, _, name)
            if name == "Blizzard_CooldownViewer" then Attach() end
        end)
    end
    self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", function(_, _, _, _, spellID)
        OnCast(spellID)
    end, "player")
    -- Keybind and rank text follow the action bars.
    local queued = false
    local function KeysChanged()
        keysDirty = true
        if queued then return end
        queued = true
        C_Timer.After(0.1, function() queued = false; M:LayoutAll() end)
    end
    for _, e in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
                         "UPDATE_BONUS_ACTIONBAR", "UPDATE_MACROS", "SPELLS_CHANGED",
                         "UPDATE_SHAPESHIFT_FORM", "SPELL_TEXT_UPDATE" }) do
        self:RegisterEvent(e, KeysChanged)
    end
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() inCombat = true; M:LayoutAll() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() inCombat = false; M:LayoutAll() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        inCombat = InCombatLockdown() and true or false
        Attach()
    end)
end

--- Spells in the cooldown bars right now, for choosing a timer: { value = id, text = name }.
function M.BarSpells()
    local out, seen = {}, {}
    for _, def in ipairs(BARS) do
        if not def.buff then
            for _, f in ipairs(Items(def, true)) do
                local info = f.cooldownInfo
                local id = type(info) == "table" and info.spellID
                local name = ItemSpell(f)
                if name and not seen[name] and type(id) == "number" and not issecret(id) then
                    seen[name] = true
                    out[#out + 1] = { value = id, text = name }
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

function M:Refresh()
    for _, s in pairs(state) do s.fontSize = nil end
    self:LayoutAll()
end
