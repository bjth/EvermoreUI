if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Quests.lua
--  Take quests and hand them in.
--
--  There are THREE ways an NPC offers a quest in this client, and they share
--  no API at all. All three are handled, because an NPC you meet decides
--  which one you get, not you.
--
--   1. Gossip menu (GOSSIP_SHOW). Quests sit alongside "Train me" options.
--      C_GossipInfo.GetAvailableQuests() / GetActiveQuests() return
--      GossipQuestUIInfo, and selection is BY questID:
--      C_GossipInfo.SelectAvailableQuest(questID).
--      (GossipInfoDocumentation.lua:404-419, GossipFrameShared.lua:44-60)
--
--   2. Quest greeting panel (QUEST_GREETING). An NPC with quests and nothing
--      else to say. Same idea, different API and selection is BY INDEX:
--      GetNumAvailableQuests() / GetAvailableQuestInfo(i) / SelectAvailableQuest(i).
--      (Mainline/QuestFrame.lua:321-380, 459-461)
--
--   3. Straight to the quest itself (QUEST_DETAIL), when there is only one.
--
--  Then the hand-in chain, whichever way you arrived:
--      QUEST_PROGRESS  -> IsQuestCompletable() then CompleteQuest()
--      QUEST_COMPLETE  -> GetQuestReward(choice)
--
--  Plus the lone gossip option, which is its own thing and documented at
--  section 1b, because Blizzard already handles half of that case themselves.
--
--  The rule on rewards: we only ever hand in when there is NO choice to make.
--  GetNumQuestChoices() > 1 means the quest is asking you a question, and a
--  robot answering it for you is how you end up vendoring the item you
--  wanted. The window just opens as normal.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

--------------------------------------------------------------------------------
--  Filters
--------------------------------------------------------------------------------

--- Daily, weekly or otherwise repeatable?
--- Two sources because the two menu types describe it differently: the
--- gossip struct carries isRepeatable and frequency, the greeting panel
--- returns them positionally, and QUEST_DETAIL has neither so it asks
--- C_QuestLog.
local function IsRepeatable(info)
    if type(info) == "table" then
        if info.repeatable or info.isRepeatable then return true end
        local f = info.frequency
        if type(f) == "number" and f ~= 0 then
            local default = Enum and Enum.QuestFrequency and Enum.QuestFrequency.Default
            if type(default) ~= "number" or f ~= default then return true end
        end
        if type(info.questID) == "number" and C_QuestLog then
            if type(C_QuestLog.IsRepeatableQuest) == "function" then
                local ok, r = pcall(C_QuestLog.IsRepeatableQuest, info.questID)
                if ok and r then return true end
            end
        end
    end
    return false
end

local function IsTrivial(info)
    if type(info) ~= "table" then return false end
    if info.isTrivial then return true end
    if type(info.questID) == "number" and C_QuestLog
       and type(C_QuestLog.IsQuestTrivial) == "function" then
        local ok, t = pcall(C_QuestLog.IsQuestTrivial, info.questID)
        if ok and t then return true end
    end
    return false
end

--- Should we take this one? info is a table of whatever the caller could
--- find out; missing fields simply do not filter.
local function Wanted(db, info)
    if type(info) == "table" and info.isIgnored then return false end
    if db.skipRepeatable and IsRepeatable(info) then return false end
    if db.skipTrivial and IsTrivial(info) then return false end
    return true
end

--------------------------------------------------------------------------------
--  1. Gossip menu
--------------------------------------------------------------------------------
--- Returns true when it selected something, because the menu is gone the
--- moment it does and nothing after that point is looking at the same NPC.
local function GossipQuests(self)
    local db = self.db
    if not (db.autoAccept or db.autoTurnIn) then return false end
    if not (C_GossipInfo and type(C_GossipInfo.GetAvailableQuests) == "function") then return false end

    -- Hand-ins before pickups: finishing a quest can make the next one
    -- available from the same NPC, and doing it the other way round means
    -- walking away with a quest you could have turned in.
    if db.autoTurnIn and type(C_GossipInfo.GetActiveQuests) == "function" then
        local ok, active = pcall(C_GossipInfo.GetActiveQuests)
        if ok and type(active) == "table" then
            for _, q in ipairs(active) do
                if q.isComplete and type(q.questID) == "number" then
                    pcall(C_GossipInfo.SelectActiveQuest, q.questID)
                    return true   -- menu gone; the next GOSSIP_SHOW takes the rest
                end
            end
        end
    end

    if db.autoAccept and type(C_GossipInfo.SelectAvailableQuest) == "function" then
        local ok, avail = pcall(C_GossipInfo.GetAvailableQuests)
        if ok and type(avail) == "table" then
            for _, q in ipairs(avail) do
                if Wanted(db, q) and type(q.questID) == "number" then
                    pcall(C_GossipInfo.SelectAvailableQuest, q.questID)
                    return true
                end
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
--  1b. The lone gossip option
--
--  Read GossipFrameSharedMixin:HandleShow before changing anything here
--  (Blizzard_UIPanels_Game/Shared/GossipFrameShared.lua:191-201). The client
--  ALREADY does the safe half of this:
--
--      if numAvailableQuests == 0 and numActiveQuests == 0
--         and #options == 1 and not C_GossipInfo.ForceGossip() then
--          if options[1].selectOptionWhenOnlyOption then
--              C_GossipInfo.SelectOptionByIndex(options[1].orderIndex)
--
--  selectOptionWhenOnlyOption is the SERVER saying this option is safe to
--  take unattended, and it is why a vendor or a flight master usually opens
--  straight away already. So we are not adding "skip single-option menus".
--  We are adding exactly the cases Blizzard chose to leave on screen: an
--  option the server did not flag, and, if you ask for it, one on a menu the
--  server asked to be shown.
--
--  ForceGossip means the NPC wants you to read the menu. Respected by
--  default. The toggle that overrides it is where most of the remaining
--  clicks are, and also where the only real risk is, so it is off and
--  labelled plainly rather than hidden in the default.
--------------------------------------------------------------------------------

-- Selecting an option can open another single-option menu, which we would
-- select, and so on. A legitimate chain is short; anything longer is a loop.
local CHAIN_MAX  = 4
local CHAIN_GAP  = 2   -- seconds of quiet that ends a chain
local chain, chainAt = 0, 0

local function Only(self)
    local db = self.db
    if not db.autoGossip then return end
    if not (C_GossipInfo and type(C_GossipInfo.GetOptions) == "function") then return end

    -- Quests first, always: a menu with a quest on it is not a lone option,
    -- and skipping past a quest giver is the one thing this must never do.
    local function Count(fn)
        if type(fn) ~= "function" then return 0 end
        local ok, n = pcall(fn)
        return (ok and type(n) == "number") and n or 0
    end
    if Count(C_GossipInfo.GetNumAvailableQuests) > 0 then return end
    if Count(C_GossipInfo.GetNumActiveQuests) > 0 then return end

    if not db.gossipForced and type(C_GossipInfo.ForceGossip) == "function" then
        local ok, forced = pcall(C_GossipInfo.ForceGossip)
        if ok and forced then return end
    end

    local ok, options = pcall(C_GossipInfo.GetOptions)
    if not ok or type(options) ~= "table" or #options ~= 1 then return end

    local o = options[1]
    if type(o) ~= "table" or type(o.orderIndex) ~= "number" then return end

    -- Unavailable, Locked and AlreadyComplete options are on the menu to be
    -- read, not clicked (GossipOptionStatus, GossipInfoDocumentation:301).
    local available = Enum and Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available
    if type(o.status) == "number" and type(available) == "number" and o.status ~= available then return end

    local now = GetTime and GetTime() or 0
    if now - chainAt > CHAIN_GAP then chain = 0 end
    chain, chainAt = chain + 1, now
    if chain > CHAIN_MAX then return end

    pcall(C_GossipInfo.SelectOptionByIndex, o.orderIndex)
end

local function Gossip(self)
    if GossipQuests(self) then return end
    Only(self)
end

--------------------------------------------------------------------------------
--  2. Quest greeting panel
--------------------------------------------------------------------------------
local function Greeting(self)
    local db = self.db
    if not (db.autoAccept or db.autoTurnIn) then return end

    if db.autoTurnIn and type(GetNumActiveQuests) == "function"
       and type(SelectActiveQuest) == "function" then
        local ok, n = pcall(GetNumActiveQuests)
        if ok and type(n) == "number" then
            for i = 1, n do
                local okT, _, isComplete = pcall(GetActiveTitle, i)
                if okT and isComplete then
                    pcall(SelectActiveQuest, i)
                    return
                end
            end
        end
    end

    if db.autoAccept and type(GetNumAvailableQuests) == "function"
       and type(SelectAvailableQuest) == "function" then
        local ok, n = pcall(GetNumAvailableQuests)
        if ok and type(n) == "number" then
            for i = 1, n do
                local info
                if type(GetAvailableQuestInfo) == "function" then
                    -- isTrivial, frequency, isRepeatable, isLegendary, questID, ...
                    local okI, isTrivial, frequency, isRepeatable, _, questID = pcall(GetAvailableQuestInfo, i)
                    if okI then
                        info = { isTrivial = isTrivial, frequency = frequency,
                                 isRepeatable = isRepeatable, questID = questID }
                    end
                end
                if Wanted(db, info or {}) then
                    pcall(SelectAvailableQuest, i)
                    return
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
--  3. The quest itself
--------------------------------------------------------------------------------
local function Detail(self)
    local db = self.db
    if not db.autoAccept then return end

    -- Blizzard puts a confirmation in front of a PvP quest. Leave it alone.
    if type(QuestFlagsPVP) == "function" and QuestFlagsPVP() then return end
    -- Auto-offered quests from an area trigger or a quest item get Blizzard's
    -- own popup treatment (QuestFrame.lua:42-60); do not race it.
    if type(QuestIsFromAreaTrigger) == "function" and QuestIsFromAreaTrigger() then return end
    if type(QuestIsFromAdventureMap) == "function" and QuestIsFromAdventureMap() then return end

    local info = {}
    if type(GetQuestID) == "function" then
        local ok, id = pcall(GetQuestID)
        if ok and type(id) == "number" and id > 0 then info.questID = id end
    end
    if not Wanted(db, info) then return end

    if type(QuestGetAutoAccept) == "function" and QuestGetAutoAccept() then
        if type(AcknowledgeAutoAcceptQuest) == "function" then
            pcall(AcknowledgeAutoAcceptQuest)
        end
        return
    end
    if type(AcceptQuest) == "function" then pcall(AcceptQuest) end
end

local function Progress(self)
    if not self.db.autoTurnIn then return end
    if type(IsQuestCompletable) ~= "function" or not IsQuestCompletable() then return end
    if type(CompleteQuest) == "function" then pcall(CompleteQuest) end
end

local function Complete(self)
    if not self.db.autoTurnIn then return end
    if type(GetQuestReward) ~= "function" then return end

    -- A choice of rewards is a question for you, not for us.
    local choices = 0
    if type(GetNumQuestChoices) == "function" then
        local ok, n = pcall(GetNumQuestChoices)
        if ok and type(n) == "number" then choices = n end
    end
    if choices > 1 then return end

    -- Some quests take gold from you on hand-in. Blizzard raises a popup for
    -- those (QuestFrame.lua:154-160) and so should we: let it through.
    if type(GetQuestMoneyToGet) == "function" then
        local ok, money = pcall(GetQuestMoneyToGet)
        if ok and type(money) == "number" and money > 0 then return end
    end

    pcall(GetQuestReward, choices == 1 and 1 or 0)
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
function ns.EnableQuests(M)
    local function Guard(name, fn)
        return function(self)
            if ns.Skip() then return end
            ns.Safe(name, fn, self)
        end
    end

    M:RegisterEvent("GOSSIP_SHOW",    Guard("gossip",   Gossip))
    M:RegisterEvent("QUEST_GREETING", Guard("greeting", Greeting))
    M:RegisterEvent("QUEST_DETAIL",   Guard("detail",   Detail))
    M:RegisterEvent("QUEST_PROGRESS", Guard("progress", Progress))
    M:RegisterEvent("QUEST_COMPLETE", Guard("complete", Complete))
end
