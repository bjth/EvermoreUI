if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  QoL.lua
--  The small automations: repair and sell greys at a vendor, loot without
--  clicking, take and hand in quests.
--
--  Everything here is a REPLY to something the game just told us. We never
--  poll, never run a ticker, and never act without an event: MERCHANT_SHOW,
--  LOOT_READY, QUEST_DETAIL and friends. That keeps the whole module dormant
--  until you actually walk up to something.
--
--  Every automation is off by default. Turning one on is a deliberate act,
--  because automation that surprises you is worse than no automation.
--
--  Holding SHIFT skips everything for that one interaction. The check is made
--  at the moment the event fires, so it is the key you are holding as the
--  window opens that decides, not the key you press afterwards.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L

local M = EV:NewModule("QoL", {
    -- Vendor
    autoRepair      = false,
    repairFromGuild = true,    -- try guild funds before your own
    autoSellJunk    = false,
    announceVendor  = true,    -- say what was repaired and sold, and for how much
    restock         = true,    -- buy up to the counts on this character's restock list (Restock.lua)

    -- Loot
    fastLoot        = false,

    -- Quests
    autoAccept      = false,
    autoTurnIn      = false,
    skipRepeatable  = true,    -- dailies, weeklies and anything flagged repeatable
    skipTrivial     = false,   -- quests below your level

    -- Gossip
    autoGossip      = false,   -- take a lone gossip option rather than clicking it
    gossipForced    = false,   -- ...even when the NPC asked for its menu to be shown

    -- Training (information and a button, so on by default)
    trainingNotify  = true,    -- a chat line on levelling when there is something to train
    trainingBadge   = true,    -- count on the micro menu's spellbook button
    trainAllButton  = true,    -- Train All on the class trainer

    -- Durability
    durabilityWarn  = true,    -- a warning when gear gets low
    durabilityAt    = 25,      -- percent

    -- Small fixes, each off until chosen
    easyDelete      = false,   -- fill in DELETE for you when destroying an item
    maxCamera       = false,   -- furthest camera distance the client allows
    quietErrors     = false,   -- drop the repeated "not ready yet" style errors
})
ns.module = M
M.title = "Quality of Life"
M.description = "Auto repair, sell greys, fast loot, and quest accept and hand-in. Hold Shift to skip."

--------------------------------------------------------------------------------
--  Shared helpers
--------------------------------------------------------------------------------

--- True when the player is holding the skip key right now.
--- Deliberately read at event time rather than cached: the answer is "is the
--- user asking me to stay out of this one", and only the current key state
--- can answer that.
function ns.Skip()
    return IsShiftKeyDown and IsShiftKeyDown()
end

--- One line in the chat frame, prefixed like the rest of the suite.
function ns.Say(fmt, ...)
    if select("#", ...) > 0 then
        EV:Print(fmt:format(...))
    else
        EV:Print(fmt)
    end
end

--- Money for chat, with coin icons. Lives in core (EV:FormatMoney,
--- Core/Durability.lua) so tooltips and the data bars format money the same way.
function ns.Money(copper) return EV:FormatMoney(copper) end

--- Guard every handler: a module that errors inside an event handler during
--- a vendor or quest interaction is a module that breaks the interaction.
function ns.Safe(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and EV.Debug then EV:Print(("QoL %s: %s"):format(what, tostring(err))) end
    return ok
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
    if ns.EnableVendor then ns.EnableVendor(self) end
    if ns.EnableLoot   then ns.EnableLoot(self)   end
    if ns.EnableQuests then ns.EnableQuests(self) end
    if ns.EnableTraining then ns.EnableTraining(self) end
    if ns.EnableDurability then ns.EnableDurability(self) end
    if ns.EnableTweaks then ns.EnableTweaks(self) end
    if ns.EnableRestock then ns.EnableRestock(self) end
end

function M:OnProfileChanged()
    -- Nothing to rebuild: every handler reads self.db at the moment it runs,
    -- so a profile switch takes effect on the next vendor or quest.
end
