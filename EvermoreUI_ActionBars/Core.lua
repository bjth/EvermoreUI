if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  EvermoreUI Action Bars
--
--  Forever can't run secure snippets, so bars of our own couldn't page in
--  combat. Instead we adopt Blizzard's buttons:
--
--    * Each button is re-parented into an EvermoreUI bar frame and laid out
--      by us. Blizzard's buttons find their page through button.bar (their
--      Blizzard bar), not their parent, so stance / form / stealth /
--      possess / vehicle paging, fixed pages for bars 2-8, keybinds, drag
--      and drop, flyouts, cooldowns and proc glows all keep working.
--    * Blizzard's bar frames are emptied and parked under a hidden parent,
--      so Edit Mode has nothing of ours to move or resize, and its action
--      bar highlights disappear. (Edit Mode only ever positions those bar
--      frames and the holder round each button, never the buttons.)
--    * Show/hide conditions use Blizzard's state driver, which needs no
--      snippet. Fading is alpha only, so it works in combat.
--    * Everything that moves or re-parents a protected frame waits for the
--      end of combat.
--
--  Files: Core (settings, bar list, combat queue), Skin (the button look),
--  Bars (adoption, layout, visibility, fade, Edit Mode lockout).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L

-- Blizzard's bars, in Blizzard's own numbering.
ns.BARS = {
    { key = "main",   label = L["Action Bar 1"], shell = "MainActionBar",       prefix = "ActionButton",              count = 12, main = true },
    { key = "bar2",   label = L["Action Bar 2"], shell = "MultiBarBottomLeft",  prefix = "MultiBarBottomLeftButton",  count = 12 },
    { key = "bar3",   label = L["Action Bar 3"], shell = "MultiBarBottomRight", prefix = "MultiBarBottomRightButton", count = 12 },
    { key = "bar4",   label = L["Action Bar 4"], shell = "MultiBarRight",       prefix = "MultiBarRightButton",       count = 12 },
    { key = "bar5",   label = L["Action Bar 5"], shell = "MultiBarLeft",        prefix = "MultiBarLeftButton",        count = 12 },
    { key = "bar6",   label = L["Action Bar 6"], shell = "MultiBar5",           prefix = "MultiBar5Button",           count = 12 },
    { key = "bar7",   label = L["Action Bar 7"], shell = "MultiBar6",           prefix = "MultiBar6Button",           count = 12 },
    { key = "bar8",   label = L["Action Bar 8"], shell = "MultiBar7",           prefix = "MultiBar7Button",           count = 12 },
    { key = "stance", label = L["Stance Bar"],   shell = "StanceBar",           prefix = "StanceButton",              count = 10, small = true, stance = true },
    { key = "pet",    label = L["Pet Bar"],      shell = "PetActionBar",        prefix = "PetActionButton",           count = 10, small = true, pet = true },
}
ns.BY_KEY = {}
for _, b in ipairs(ns.BARS) do ns.BY_KEY[b.key] = b end

local function BarDefaults(size, enabled)
    return {
        enabled    = enabled,
        buttons    = 12,
        perRow     = 12,
        size       = size,
        spacing    = 4,
        visibility = "always",   -- always, combat, nocombat, hidden, custom
        custom     = "[combat] show; hide",
        fade       = false,      -- fade when the mouse isn't over it
        fadeAlpha  = 0,          -- opacity while faded
        fadeInCombat = false,    -- keep fading in combat (off: full in combat)
        showEmpty  = false,      -- show empty slots
        growH      = "RIGHT",    -- first button's side: RIGHT grows rightwards, LEFT leftwards
        growV      = "DOWN",     -- DOWN adds rows below, UP above
        scale      = 1,          -- the whole bar, buttons and text together
        alpha      = 1,          -- opacity when not faded
        fadeGroup  = 0,          -- 1-3: bars in one group fade in together
        showHotkey = true,       -- per bar, on top of the Buttons tab switches
        showCount  = true,
        showMacro  = true,
        -- Paging (Paging.lua). 0 = Blizzard's own page for this bar.
        page       = 0,
        pageAlt    = 0,          -- page while Alt is held (0: none)
        pageCtrl   = 0,
        pageShift  = 0,
        pageCustom = "",         -- macro conditions, e.g. [mod:alt] 2; [stealth] 7
        -- Spell rank text (Skin.lua)
        rankText   = false,
        rankFormat = "short",    -- short (R3), number (3), full (Rank 3)
        rankPoint  = "TOPLEFT",
        rankX      = 2,
        rankY      = -2,
        rankSize   = 10,
        rankColour = { 1, 0.82, 0 },
    }
end

local defaults = {
    genesis = false,             -- first run: bars copied from Blizzard's layout
    stanceCapFixed = false,      -- one-off: lift the stance cap genesis used to copy (Bars.lua)
    editModeNote = true,         -- chat note when Blizzard's Edit Mode opens
    text = {
        hotkey = true,  hotkeySize = 12,
        count = true,   countSize = 13,
        reagents = true,             -- reagent / ammo counts where Blizzard shows none (Skin.lua)
        macro = false,  macroSize = 10,
        shortKeys = true,            -- S1, CM4, AWU instead of Blizzard's key names
    },
    look = {
        rangeTint = true,            -- icon goes red when the target is out of range
        equipped = true,             -- green edge on equipped items
    },
    behaviour = {
        rightClickSelf = false,      -- right click casts the button's spell on yourself
        bindPerCharacter = false,    -- keybind mode saves to this character's bindings
    },
    -- Modifier actions (Actions.lua): { bar, index, mod, button, kind, value }
    actions = {},
    bars = {},
}
for _, b in ipairs(ns.BARS) do
    local d = BarDefaults(b.small and 30 or 40, b.key == "main" or b.key == "stance" or b.key == "pet")
    if b.small then d.buttons, d.perRow = 10, 10 end
    defaults.bars[b.key] = d
end

local M = EV:NewModule("ActionBars", defaults)
ns.module = M
M.title = "Action Bars"
M.description = "Blizzard's action buttons in EvermoreUI bars: our layout, look and movers."

--------------------------------------------------------------------------------
--  Combat queue: protected changes wait for the end of combat.
--------------------------------------------------------------------------------
local queue = {}
local qf = CreateFrame("Frame")
qf:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local list = queue
    queue = {}
    for _, f in pairs(list) do
        local ok, err = pcall(f)
        if not ok then geterrorhandler()("EvermoreUI Action Bars: " .. tostring(err)) end
    end
end)
function ns.Safe(key, fn)
    if not InCombatLockdown() then return fn() end
    queue[key] = fn
    qf:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function ns.Bar(key) return M.db.bars[key] end
