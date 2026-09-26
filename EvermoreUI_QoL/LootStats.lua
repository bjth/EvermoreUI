if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  LootStats.lua
--  Who's the luckiest? Every need, greed, disenchant and pass you make, and
--  how it turned out, by item quality, kept per character in the account-
--  wide character store (DB:GetCharData("lootStats")) so the Loot Luck
--  window can line your characters up against each other. /evui luck.
--
--  Your choice is caught at the source: RollOnLoot is post-hooked, so it is
--  recorded whichever roll frame you click (ours or Blizzard's). The item
--  and its quality come from START_LOOT_ROLL. A roll you let time out counts
--  as a pass.
--
--  The OUTCOME arrives later, once everyone has rolled, and there are two
--  ways it can reach us, both used:
--    * the loot history (C_LootHistory, LOOT_HISTORY_UPDATE_DROP): a drop
--      with its winner and everyone's roll, flagged isSelf
--    * the loot chat lines, matched with the game's own format strings
--      (LOOT_ROLL_YOU_WON "You won: %s", LOOT_ROLL_WON "%s won: %s",
--      LOOT_ROLL_ROLLED_NEED "Need Roll - %d for %s by %s", ...), so it
--      reads the same in any language
--  Whichever answers first settles the roll; a chat line that comes back
--  secret is ignored. Rolls are matched to items by item ID, oldest first.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local issecret = issecretvalue or function() return false end

local M = EV:NewModule("LootStats", { enabled = true })
M.title = "Loot Luck"
M.description = "Counts the loot rolls each character wins, loses and passes, by quality, and ranks your luckiest characters. /evui luck"
ns.lootStats = M

local CHOICE = { [0] = "pass", [1] = "need", [2] = "greed", [3] = "de" }
local EXPIRE = 300   -- seconds a roll may wait for its result

--------------------------------------------------------------------------------
--  Storage
--------------------------------------------------------------------------------
local function Stats()
    local s = EV.DB:GetCharData("lootStats")
    for _, k in ipairs({ "need", "greed", "de" }) do
        s[k] = type(s[k]) == "table" and s[k] or {}
        s[k].won = type(s[k].won) == "table" and s[k].won or {}
        s[k].lost = type(s[k].lost) == "table" and s[k].lost or {}
    end
    s.pass = type(s.pass) == "table" and s.pass or {}
    s.rolls = type(s.rolls) == "table" and s.rolls or { sum = 0, n = 0 }
    return s
end

local function Bump(t, q) q = q or 1; t[q] = (t[q] or 0) + 1 end

--------------------------------------------------------------------------------
--  Rolls in flight
--------------------------------------------------------------------------------
local pending = {}   -- rollID -> { id, link, quality, choice, t, rolled }

local function ItemID(link) return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil end

local function Oldest(id, needChoice)
    local best, bestT
    for rid, p in pairs(pending) do
        if p.id == id and (not needChoice or (p.choice and p.choice ~= "pass")) and (not bestT or p.t < bestT) then
            best, bestT = rid, p.t
        end
    end
    return best
end

local function Settle(rid, won)
    local p = pending[rid]
    if not p then return end
    pending[rid] = nil
    local s = Stats()
    if p.choice and p.choice ~= "pass" then
        Bump(won and s[p.choice].won or s[p.choice].lost, p.quality)
        if won and (p.quality or 0) >= ((s.best and s.best.quality) or -1) then
            s.best = { link = p.link, quality = p.quality, when = time() }
        end
    end
end

local function RollValue(rid, value)
    local p = pending[rid]
    if not p or p.rolled or type(value) ~= "number" then return end
    p.rolled = true
    local r = Stats().rolls
    r.sum, r.n = (r.sum or 0) + value, (r.n or 0) + 1
    if value > (r.high or 0) then r.high = value end
    if value == 100 then r.hundreds = (r.hundreds or 0) + 1 end
end

local function Start(rollID)
    local ok, _, _, _, quality = pcall(GetLootRollItemInfo, rollID)
    local okL, link = pcall(GetLootRollItemLink, rollID)
    link = okL and link or nil
    pending[rollID] = { id = ItemID(link), link = link, quality = ok and quality or nil, t = GetTime() }
end

local function Chosen(rollID, rollType)
    local p = pending[rollID]
    if not p then
        Start(rollID)
        p = pending[rollID]
    end
    if not p or p.choice then return end
    p.choice = CHOICE[rollType]
    if p.choice == "pass" then
        Bump(Stats().pass, p.quality)
        pending[rollID] = nil
    end
end

local function Closed(rollID)
    local p = pending[rollID]
    if p and not p.choice then
        -- Timed out or passed for you (an item you can't use).
        Bump(Stats().pass, p.quality)
        pending[rollID] = nil
    end
end

local function Expire()
    local now = GetTime()
    for rid, p in pairs(pending) do
        if now - p.t > EXPIRE then pending[rid] = nil end
    end
end

--------------------------------------------------------------------------------
--  Results: the loot history
--------------------------------------------------------------------------------
local function FromHistory(encounterID, key)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
    local ok, drop = pcall(C_LootHistory.GetSortedInfoForDrop, encounterID, key)
    if not ok or type(drop) ~= "table" then return end
    local id = ItemID(drop.itemHyperlink)
    if not id then return end
    local rid = Oldest(id, true)
    if not rid then return end
    for _, r in ipairs(drop.rollInfos or {}) do
        if r.isSelf and type(r.roll) == "number" and not issecret(r.roll) then RollValue(rid, r.roll) end
    end
    if drop.winner then
        Settle(rid, drop.winner.isSelf == true)
    elseif drop.allPassed then
        pending[rid] = nil
    end
end

--------------------------------------------------------------------------------
--  Results: the loot chat
--------------------------------------------------------------------------------
--- A Lua pattern from a format string: %s -> (.+), %d -> (%d+), positional
--- forms too; everything else literal.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$s", "\1"):gsub("%%%d%$d", "\2"):gsub("%%s", "\1"):gsub("%%d", "\2")
    fmt = fmt:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    fmt = fmt:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. fmt .. "$"
end

local P = {}
local function Patterns()
    P.youWon = Pattern(LOOT_ROLL_YOU_WON)
    P.won = Pattern(LOOT_ROLL_WON)
    P.rolled = {}
    for _, g in ipairs({ "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_GREED", "LOOT_ROLL_ROLLED_DE",
                         "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS" }) do
        local pat = Pattern(_G[g])
        if pat then P.rolled[#P.rolled + 1] = { pat = pat, bonus = g:find("BONUS") ~= nil } end
    end
end

local function FromChat(msg)
    if type(msg) ~= "string" or issecret(msg) then return end
    local me = UnitName("player")
    if P.youWon then
        local link = msg:match(P.youWon)
        if link then
            local rid = Oldest(ItemID(link), true)
            if rid then Settle(rid, true) end
            return
        end
    end
    if P.won then
        local who, link = msg:match(P.won)
        if who and link then
            local rid = Oldest(ItemID(link), true)
            if rid then Settle(rid, Ambiguate(who, "short") == me) end
            return
        end
    end
    for _, r in ipairs(P.rolled) do
        local a, b, c, d = msg:match(r.pat)
        if a then
            local value, link, who
            if r.bonus then value, link, who = tonumber(a), c, d else value, link, who = tonumber(a), b, c end
            if who and (Ambiguate(who, "short") == me or who == YOU) then
                local rid = Oldest(ItemID(link), true)
                if rid then RollValue(rid, value) end
            end
            return
        end
    end
end

--------------------------------------------------------------------------------
--  Reading it back
--------------------------------------------------------------------------------
local function Sum(t)
    local n = 0
    for _, v in pairs(t or {}) do n = n + v end
    return n
end

--- Totals for one character's stats table.
function M.Summary(s)
    s = s or {}
    local out = { won = 0, lost = 0, passed = Sum(s.pass) }
    for _, k in ipairs({ "need", "greed", "de" }) do
        local w, l = Sum(s[k] and s[k].won), Sum(s[k] and s[k].lost)
        out[k .. "Won"], out[k .. "Lost"] = w, l
        out.won, out.lost = out.won + w, out.lost + l
    end
    out.rolled = out.won + out.lost
    out.rate = out.rolled > 0 and out.won / out.rolled or nil
    local r = s.rolls or {}
    out.avg = (r.n or 0) > 0 and r.sum / r.n or nil
    out.high, out.hundreds = r.high, r.hundreds or 0
    out.best = s.best
    return out
end

--- Every character with any rolls: { entry = EV.Alts entry, sum = Summary }.
function M.Board()
    local rows = {}
    for _, e in ipairs(EV.Alts:List()) do
        local s = e.data.lootStats
        if type(s) == "table" then
            local sum = M.Summary(s)
            if sum.rolled + sum.passed > 0 then rows[#rows + 1] = { entry = e, sum = sum, stats = s } end
        end
    end
    -- Luckiest first: win rate, then more rolls, then higher average roll.
    table.sort(rows, function(a, b)
        local ra, rb = a.sum.rate or -1, b.sum.rate or -1
        if ra ~= rb then return ra > rb end
        if a.sum.rolled ~= b.sum.rolled then return a.sum.rolled > b.sum.rolled end
        return (a.sum.avg or 0) > (b.sum.avg or 0)
    end)
    return rows
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
local hooked
function M:OnEnable()
    Patterns()
    if not hooked and type(RollOnLoot) == "function" then
        hooked = true
        hooksecurefunc("RollOnLoot", function(rollID, rollType)
            if M:IsEnabled() and type(rollID) == "number" then Chosen(rollID, rollType) end
        end)
    end
    self:RegisterEvent("START_LOOT_ROLL", function(_, _, rollID) Expire(); Start(rollID) end)
    self:RegisterEvent("CANCEL_LOOT_ROLL", function(_, _, rollID) Closed(rollID) end)
    self:RegisterEvent("CHAT_MSG_LOOT", function(_, _, msg) FromChat(msg) end)
    self:RegisterEvent("LOOT_HISTORY_UPDATE_DROP", function(_, _, enc, key) FromHistory(enc, key) end)
end

EV:RegisterSlash("luck", function() if ns.ShowLuck then ns.ShowLuck() end end)
