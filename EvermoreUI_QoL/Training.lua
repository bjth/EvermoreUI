if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Training.lua
--  What your class trainer has for you, without a spell database.
--
--  Two sources, in order:
--    * The spellbook. Where the client lists unlearnt spells, they come back
--      from C_SpellBook as Enum.SpellBookItemType.FutureSpell with the level
--      they unlock at (GetSpellBookItemLevelLearned), the same data Blizzard's
--      spellbook prints "Available at level N" from.
--    * The class trainer. Forever currently sends no FutureSpell entries, so
--      every trainer visit records what it lists (name, rank, level, cost),
--      account-wide per class. A spell counts as ready when its level is at
--      or below yours and your spellbook has neither it nor a higher rank.
--      One visit teaches the list for every character of that class.
--
--  Prices are only known at the trainer, so the level-up line says "about"
--  when only part of the bill has been seen.
--
--  Three things come out of this:
--    * EV_TRAINING_CHANGED (count, nextLevel), which the micro menu turns into
--      a badge on the spellbook button
--    * one chat line on levelling, when there is something new to train
--    * a Train All button on the class trainer, for everything it lists as
--      available that you can afford
--
--  Everything runs on events on this file's own frame (so it never competes
--  with the module's other handlers for an event), and nothing is secret:
--  none of these calls carries a SecretReturns flag.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

local T = {}            -- this file's state
ns.Training = T
T.count, T.nextLevel, T.ready = 0, nil, {}

--------------------------------------------------------------------------------
--  Reading the spellbook
--------------------------------------------------------------------------------
local function Bank()
    return (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
end

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end

local function RankNum(rank)
    return tonumber(type(rank) == "string" and rank:match("(%d+)") or nil) or 0
end

local function ClassKey()
    local _, class = UnitClass("player")
    return class or "UNKNOWN"
end

local function ClassTable(field)
    local g = EV.DB:GetGlobal()
    if type(g[field]) ~= "table" then g[field] = {} end
    local class = ClassKey()
    if type(g[field][class]) ~= "table" then g[field][class] = {} end
    return g[field][class]
end

local function CostBook() return ClassTable("trainerCosts") end
--- What class trainers have listed: key -> { name, rank, level }.
local function TrainerBook() return ClassTable("trainerSpells") end

local function Key(name, rank) return tostring(name) .. "|" .. tostring(rank or "") end

--- Walk the spellbook once: unlearnt spells if the client sends them, and
--- the highest rank known of each spell by name.
local function ReadBook()
    local future, known = {}, {}
    local sb = C_SpellBook
    if not (sb and sb.GetNumSpellBookSkillLines and sb.GetSpellBookItemInfo) then return future, known end
    local FUTURE = Enum.SpellBookItemType and Enum.SpellBookItemType.FutureSpell
    local bank = Bank()
    local okN, lines = pcall(sb.GetNumSpellBookSkillLines)
    if not okN or type(lines) ~= "number" then return future, known end
    for i = 1, lines do
        local ok, line = pcall(sb.GetSpellBookSkillLineInfo, i)
        if ok and type(line) == "table" and not line.offSpecID then
            local first = (line.itemIndexOffset or 0) + 1
            local last = (line.itemIndexOffset or 0) + (line.numSpellBookItems or 0)
            for slot = first, last do
                local okI, item = pcall(sb.GetSpellBookItemInfo, slot, bank)
                if okI and type(item) == "table" and type(item.name) == "string" then
                    if FUTURE and item.itemType == FUTURE then
                        if not item.isOffSpec and not line.shouldHide then
                            local learn
                            if sb.GetSpellBookItemLevelLearned then
                                local okL, l = pcall(sb.GetSpellBookItemLevelLearned, slot, bank)
                                learn = (okL and Plain(l) and type(l) == "number") and l or nil
                            end
                            future[#future + 1] = { name = item.name, rank = item.subName or "", level = learn }
                        end
                    else
                        local r = RankNum(item.subName)
                        if (known[item.name] or -1) < r then known[item.name] = r end
                    end
                end
            end
        end
    end
    return future, known
end

--- Ready-to-train spells (name, rank, level) and the next level with more.
function T.Scan()
    local ready, soon, later = {}, nil, {}
    local level = UnitLevel("player") or 0
    local future, known = ReadBook()

    local function Consider(name, rank, learn)
        if learn and learn > level then
            soon = soon and math.min(soon, learn) or learn
            later[#later + 1] = { name = name, rank = rank or "", level = learn }
        else
            ready[#ready + 1] = { name = name, rank = rank or "", level = learn or 0 }
        end
    end

    if #future > 0 then
        for _, f in ipairs(future) do Consider(f.name, f.rank, f.level) end
    else
        for _, e in pairs(TrainerBook()) do
            if type(e) == "table" and e.name then
                -- A book entry with no rank text can't be compared, so it
                -- counts as known: better to miss a rank than nag wrongly.
                local have = known[e.name]
                if not (have and (have == 0 or have >= RankNum(e.rank))) then
                    Consider(e.name, e.rank, e.level)
                end
            end
        end
    end
    table.sort(ready, function(a, b) return a.level < b.level or (a.level == b.level and a.name < b.name) end)
    local upcoming = {}
    for _, e in ipairs(later) do
        if e.level == soon then upcoming[#upcoming + 1] = e end
    end
    table.sort(upcoming, function(a, b) return a.name < b.name end)
    return ready, soon, upcoming
end

--------------------------------------------------------------------------------
--  Trainer visits: prices, and the class list
--------------------------------------------------------------------------------

--- The known cost of these spells, and whether every one was known.
function T.Estimate(list)
    local book, total, all = CostBook(), 0, true
    for _, s in ipairs(list) do
        local c = book[Key(s.name, s.rank)]
        if type(c) == "number" then total = total + c else all = false end
    end
    return total, all
end

local function ClassTrainer()
    if type(IsTradeskillTrainer) == "function" then
        local ok, trade = pcall(IsTradeskillTrainer)
        if ok and trade then return false end
    end
    return true
end

local function RecordTrainer()
    if type(GetNumTrainerServices) ~= "function" then return end
    local ok, n = pcall(GetNumTrainerServices)
    if not ok or type(n) ~= "number" then return end
    local costs = CostBook()
    local spells = ClassTrainer() and TrainerBook() or nil
    for i = 1, n do
        local okI, name, kind, _, reqLevel, rank = pcall(GetTrainerServiceInfo, i)
        if okI and name and kind ~= "header" then
            local okC, cost, isProfession = pcall(GetTrainerServiceCost, i)
            if okC and type(cost) == "number" then costs[Key(name, rank)] = cost end
            if spells and not (okC and isProfession) and type(reqLevel) == "number" and reqLevel > 0 then
                spells[Key(name, rank)] = { name = name, rank = rank or "", level = reqLevel }
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Count, badge and the level-up line
--------------------------------------------------------------------------------
local function Refresh()
    local ready, soon, upcoming = T.Scan()
    local changed = (#ready ~= T.count) or (soon ~= T.nextLevel)
    T.ready, T.count, T.nextLevel, T.upcoming = ready, #ready, soon, upcoming
    if changed then EV:SendMessage("EV_TRAINING_CHANGED", T.count, T.nextLevel) end
end
T.Refresh = Refresh

local pendingAnnounce = false
local function Announce()
    local db = ns.module and ns.module.db
    if not (db and db.trainingNotify) then return end
    if T.count == 0 then return end
    local names = {}
    for i, s in ipairs(T.ready) do
        if i > 6 then names[#names + 1] = L["and more"]; break end
        names[#names + 1] = s.rank ~= "" and ("%s (%s)"):format(s.name, s.rank) or s.name
    end
    local total, all = T.Estimate(T.ready)
    local price = ""
    if total > 0 then
        price = " " .. (all and L["for"] or L["for about"]) .. " " .. ns.Money(total)
    end
    ns.Say("%s%s: %s", (T.count == 1 and L["1 spell to train"] or (T.count .. " " .. L["spells to train"])),
           price, table.concat(names, ", "))
end

--------------------------------------------------------------------------------
--  The list again, away from the trainer: on the spellbook micro button's
--  tooltip, under Blizzard's own lines.
--------------------------------------------------------------------------------
local function SpellLine(s)
    return s.rank ~= "" and ("%s (%s)"):format(s.name, s.rank) or s.name
end

function T.AddTooltip(tt)
    local db = ns.module and ns.module.db
    if not (db and db.trainingBadge) then return end
    tt:AddLine(" ")
    local costs = CostBook()
    if T.count > 0 then
        tt:AddLine(T.count == 1 and L["1 spell to train"] or (T.count .. " " .. L["spells to train"]), 1, 0.82, 0)
        for i, s in ipairs(T.ready) do
            if i > 12 then tt:AddLine(L["and more"], 0.7, 0.7, 0.7); break end
            local c = costs[Key(s.name, s.rank)]
            tt:AddDoubleLine(SpellLine(s), type(c) == "number" and ns.Money(c) or "", 1, 1, 1, 1, 1, 1)
        end
    end
    if T.nextLevel then
        tt:AddLine((L["Next at level %d"]):format(T.nextLevel), 1, 0.82, 0)
        for i, s in ipairs(T.upcoming or {}) do
            if i > 8 then tt:AddLine(L["and more"], 0.7, 0.7, 0.7); break end
            tt:AddLine(SpellLine(s), 0.8, 0.8, 0.8)
        end
    end
    if T.count == 0 and not T.nextLevel then
        if next(TrainerBook()) then
            tt:AddLine(L["Nothing to train right now."], 0.7, 0.7, 0.7)
        else
            tt:AddLine(L["Visit your class trainer once to see what's coming."], 0.7, 0.7, 0.7, true)
        end
    end
    tt:Show()
end

local hooked = {}
local function HookMicro()
    for _, name in ipairs({ "SpellbookMicroButton", "PlayerSpellsMicroButton" }) do
        local b = _G[name]
        if b and not hooked[b] and b.HookScript then
            hooked[b] = true
            b:HookScript("OnEnter", function(self)
                if GameTooltip:IsOwned(self) then ns.Safe("training tooltip", T.AddTooltip, GameTooltip) end
            end)
        end
    end
end

--------------------------------------------------------------------------------
--  Train All, on Blizzard's class trainer
--------------------------------------------------------------------------------
local button
local queue, buying = {}, false

local function Affordable()
    local list, total = {}, 0
    if type(GetNumTrainerServices) ~= "function" then return list, 0 end
    local okM, money = pcall(GetMoney)
    money = okM and type(money) == "number" and money or 0
    local ok, n = pcall(GetNumTrainerServices)
    if not ok or type(n) ~= "number" then return list, 0 end
    for i = 1, n do
        local okI, _, kind = pcall(GetTrainerServiceInfo, i)
        if okI and kind == "available" then
            local okC, cost, isProfession = pcall(GetTrainerServiceCost, i)
            -- Professions ask for a slot confirmation; they are left to you.
            if okC and type(cost) == "number" and not isProfession and total + cost <= money then
                list[#list + 1] = i
                total = total + cost
            end
        end
    end
    return list, total
end

local function UpdateButton()
    if not button then return end
    local db = ns.module and ns.module.db
    local want = db and db.trainAllButton and ClassTrainerFrame and ClassTrainerFrame:IsShown()
    button:SetShown(want and true or false)
    if not want then return end
    if button._fit then button._fit() end
    local list, total = Affordable()
    button._total = total
    button:SetText(#list > 0 and (L["Train all"] .. " (" .. #list .. ")") or L["Train all"])
    button:SetEnabled(#list > 0 and not buying)
end

local function BuyNext()
    local i = table.remove(queue)   -- highest index first
    if not i then
        buying = false
        UpdateButton()
        Refresh()
        return
    end
    local okI, _, kind = pcall(GetTrainerServiceInfo, i)
    local okC, cost = pcall(GetTrainerServiceCost, i)
    local okM, money = pcall(GetMoney)
    if okI and kind == "available" and okC and type(cost) == "number"
       and okM and type(money) == "number" and cost <= money then
        pcall(BuyTrainerService, i)
    end
    -- A short gap between purchases: the server answers each with a
    -- TRAINER_UPDATE, and hammering it drops requests.
    C_Timer.After(0.25, BuyNext)
end

local function TrainAll()
    if buying then return end
    local list = Affordable()
    if #list == 0 then return end
    queue = list
    buying = true
    UpdateButton()
    BuyNext()
end

local function BuildButton()
    if button or not ClassTrainerFrame or not (EV.UI and EV.UI.Button) then return end
    button = EV.UI.Button(ClassTrainerFrame, L["Train all"], 120, TrainAll)
    -- Between the money box and Train, matching Train's height. The money
    -- text sits up to 8px past its box, hence the gap on the left.
    local train = ClassTrainerFrame.TrainButton or ClassTrainerTrainButton
    local moneyBg = ClassTrainerFrameMoneyBg
    if train then
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", train, "TOPLEFT", -2, 0)
        button:SetPoint("BOTTOMRIGHT", train, "BOTTOMLEFT", -2, 0)
        button._fit = function()
            local l, r = moneyBg and moneyBg:GetRight(), train:GetLeft()
            if l and r then button:SetWidth(math.max(70, math.min(140, r - l - 14))) end
        end
    else
        button:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -110, 4)
    end
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Train all"], 1, 1, 1)
        GameTooltip:AddLine(L["Learns everything this trainer lists as available that you can afford. Professions are left to you."], nil, nil, nil, true)
        if self._total and self._total > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Cost:"] .. " " .. ns.Money(self._total), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ClassTrainerFrame:HookScript("OnShow", UpdateButton)
    ClassTrainerFrame:HookScript("OnHide", function() queue = {}; buying = false end)
    UpdateButton()
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local soonRefresh = false
local function RefreshSoon()
    if soonRefresh then return end
    soonRefresh = true
    C_Timer.After(0.5, function()
        soonRefresh = false
        Refresh()
        if pendingAnnounce then pendingAnnounce = false; Announce() end
    end)
end

ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LEVEL_UP" then
        -- The spellbook catches up a moment after the level does.
        pendingAnnounce = true
        C_Timer.After(1.5, RefreshSoon)
    elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        RefreshSoon()
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        ns.Safe("trainer list", RecordTrainer); RefreshSoon()
        BuildButton()
        UpdateButton()
    elseif event == "TRAINER_CLOSED" then
        queue = {}; buying = false
    elseif event == "PLAYER_MONEY" then
        UpdateButton()
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_TrainerUI" then
        BuildButton()
    end
end)

function ns.EnableTraining(M)
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
                         "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED", "PLAYER_MONEY", "ADDON_LOADED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_TrainerUI") then BuildButton() end
    HookMicro()
    C_Timer.After(1, HookMicro)
    C_Timer.After(2, Refresh)
end
