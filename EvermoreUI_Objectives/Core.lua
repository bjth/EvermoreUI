if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  EvermoreUI Objectives (experimental)
--
--  Quests are our own list (List.lua) in an EvermoreUI panel; Blizzard's
--  tracker keeps running for everything else and shows below it. Rules for
--  living alongside Blizzard's tracker (from Forever's source, and from
--  taint we hit ourselves):
--
--    * Never make the tracker refresh from our code (no Update, no
--      MarkDirty, no SetCollapsed): its dirty update runs in the caller's
--      execution, so a refresh started by us taints Blizzard's quest
--      machinery for the whole session (quest item buttons, map pins).
--      Everything we change shows at Blizzard's next natural refresh.
--    * Never use the tracker's SetPoint / ClearAllPoints: Edit Mode
--      replaces them with versions that ping its manager. We use the
--      originals Blizzard keeps as SetPointBase / ClearAllPointsBase.
--    * We release it from Blizzard's right-hand column with Blizzard's own
--      BreakFromFrameManager (what Edit Mode does when you drag it), once,
--      out of combat, and again only if Edit Mode re-anchors it.
--    * On Blizzard's tracker we only move and hide parts, with post-hooks;
--      we never write fields on its frames or blocks.
--
--  Files: Core (settings, combat queue), List (our quest list), Panel
--  (the panel, scroll, size, visibility, and what's left of Blizzard's
--  tracker), Quests (zone tracking, alerts, timers, info strip), Items (the
--  quest item bar), Diag (/evui objdiag).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L

local M = EV:NewModule("Objectives", {
    genesis    = false,   -- first run: size and place from Blizzard's tracker
    width      = 280,
    height     = 520,     -- the panel's maximum height; it scrolls past this
    fitContent = true,    -- shrink the panel to its content when shorter
    bgAlpha    = 0.85,
    border     = true,
    collapsed  = false,   -- our whole-panel collapse (remembered)
    -- behaviour
    combat     = "show",  -- show, fade, hide
    instances  = "show",  -- show, fade, hide (dungeons, raids, arenas, battlegrounds)
    mouseFade  = false,   -- fade when the mouse isn't over it
    fadeAlpha  = 0.35,
    -- the list
    source     = "tracked", -- tracked, all (every quest in the log)
    grouping   = "zone",    -- zone, campaign, none
    sort       = "distance",-- distance, watch (the order you tracked them), level
    finished   = "dim",     -- finished objectives: show, dim, hide
    blizzard   = true,      -- Blizzard's other sections (scenarios, world quests...) below ours
    -- quests
    levels     = true,    -- [23] before quest names
    tags       = true,    -- group, dungeon, raid, PvP and elite letters in that bracket
    difficulty = true,    -- quest names coloured by difficulty
    completeColour = true,-- finished quests' names turn green
    progressBars = true,  -- thin bars under x/y objectives
    zoneTrack  = false,   -- auto-track quests in the current zone
    infoStrip  = true,    -- quest count and XP ready above the tracker
    timers     = true,    -- timed quest countdowns in the panel
    -- alerts
    soundObjective = true,
    soundQuest = true,
    toast      = true,
    rowItems   = true,    -- a usable item button on each quest row that has one
    -- quest item bar
    -- The separate bar is optional now each quest row has its own button;
    -- it's there for anyone who wants item keybinds.
    items = {
        enabled = false,
        max     = 6,
        size    = 36,
        spacing = 4,
        perRow  = 6,
        trackedOnly = false,
        hotkeys = true,
    },
})
ns.module = M
M.title = "Objective Tracker"
M.description = "Your quests in our own list and panel, with levelling extras; Blizzard's other objectives below."

--------------------------------------------------------------------------------
--  Combat queue for anything that moves frames
--------------------------------------------------------------------------------
local queue = {}
local qf = CreateFrame("Frame")
qf:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local list = queue
    queue = {}
    for _, f in pairs(list) do
        local ok, err = pcall(f)
        if not ok then geterrorhandler()("EvermoreUI Objectives: " .. tostring(err)) end
    end
end)
function ns.Safe(key, fn)
    if not InCombatLockdown() then return fn() end
    queue[key] = fn
    qf:RegisterEvent("PLAYER_REGEN_ENABLED")
end

--- Size limits, shared by edit mode's grip and W/H boxes and the options
--- sliders so the two can never disagree.
ns.LIMITS = { wMin = 200, wMax = 600, hMin = 120, hMax = 1400 }
M.LIMITS = ns.LIMITS

--- Per-character state that isn't a setting.
function ns.Char() return EV.DB:GetCharData("objectives") end

ns.issecret = issecretvalue or function() return false end
