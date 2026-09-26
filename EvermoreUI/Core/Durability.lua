if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Durability.lua
--  One reading of your gear's condition, shared by the QoL warning and the
--  Data Bars readout so neither depends on the other.
--
--    lowest     percent of the worst item (100 with nothing damageable)
--    worstSlot  inventory slot of that item
--    broken     items at 0
--    cost       what a full repair would cost, in copper, or nil if unknown
--    known      whether cost covers every damaged item
--
--  Durability is GetInventoryItemDurability(slot), which Blizzard's own
--  DurabilityFrame reads. The repair cost is in each item's tooltip data
--  (C_TooltipInfo.GetInventoryItem(...).repairCost, the same field
--  TooltipDataRules shows in repair mode), so the bill is known away from a
--  vendor. At a vendor GetRepairAllCost is the authority and wins.
--------------------------------------------------------------------------------
local EV = EvermoreUI

local FIRST = INVSLOT_FIRST_EQUIPPED or 1
local LAST  = INVSLOT_LAST_EQUIPPED or 19

local function Readable(v) return not (issecretvalue and issecretvalue(v)) end

function EV:ReadDurability()
    local r = { lowest = 100, worstSlot = nil, broken = 0, cost = 0, known = true, damaged = 0 }
    if type(GetInventoryItemDurability) ~= "function" then return r end
    local tip = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
    for slot = FIRST, LAST do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and Readable(cur) and Readable(max) and type(cur) == "number" and type(max) == "number" and max > 0 then
            local pct = cur / max * 100
            if pct < r.lowest then r.lowest, r.worstSlot = pct, slot end
            if cur == 0 then r.broken = r.broken + 1 end
            if cur < max then
                r.damaged = r.damaged + 1
                local cost
                if tip then
                    local okT, data = pcall(tip, "player", slot)
                    if okT and type(data) == "table" and Readable(data.repairCost) and type(data.repairCost) == "number" then
                        cost = data.repairCost
                    end
                end
                if cost then r.cost = r.cost + cost else r.known = false end
            end
        end
    end
    if type(GetRepairAllCost) == "function" and MerchantFrame and MerchantFrame:IsShown() then
        local ok, cost, can = pcall(GetRepairAllCost)
        if ok and can and type(cost) == "number" then r.cost, r.known = cost, true end
    end
    if r.damaged == 0 then r.cost = 0 end
    return r
end

--- The localised name of an inventory slot, for "worst: Chest".
-- Blizzard's global label for each equipment slot, in slot order (1-19).
local SLOT_LABELS = {
    "HEAD", "NECK", "SHOULDER", "SHIRT", "CHEST", "WAIST", "LEGS", "FEET", "WRIST", "HANDS",
    "FINGER0", "FINGER1", "TRINKET0", "TRINKET1", "BACK", "MAINHAND", "SECONDARYHAND", "RANGED", "TABARD",
}

function EV:SlotName(slot)
    local key = SLOT_LABELS[slot]
    local label = key and _G[key .. "SLOT"]
    if type(label) == "string" then return label end
    return "#" .. tostring(slot)
end

--------------------------------------------------------------------------------
--  Money, for chat and tooltips. Coin icons from Blizzard's own formatter
--  (MoneyFormatterUtil). Where that isn't available, and for zero, coloured
--  letters instead: each unit coloured from a theme token, zero units dropped
--  (319 reads "3s 19c"), and nothing at all reads "0c".
--------------------------------------------------------------------------------
local COIN = {
    { 10000, "coinGold",   "GOLD_AMOUNT_SYMBOL",   "g" },
    { 100,   "coinSilver", "SILVER_AMOUNT_SYMBOL", "s" },
    { 1,     "coinCopper", "COPPER_AMOUNT_SYMBOL", "c" },
}

-- Blizzard's own money formatter (MoneyFormatterUtil, the one their Sell
-- Price and money lines use): coin icons, and plain abbreviations when the
-- player has colourblind mode on. Its config is made once, on first use.
local coinConfig
local function Coins(copper)
    if not (MoneyFormatterUtil and MoneyFormatterUtil.FormatMoney and MoneyFormatterUtil.CreateFormatterConfig) then return nil end
    if not coinConfig then
        local ok, cfg = pcall(MoneyFormatterUtil.CreateFormatterConfig)
        coinConfig = ok and cfg or false
    end
    if not coinConfig then return nil end
    local ok, text = pcall(MoneyFormatterUtil.FormatMoney, copper, coinConfig)
    if ok and type(text) == "string" and text ~= "" then return text end
end

--- Money for chat, tooltips and our own windows: coin icons where the
--- client can draw them, coloured g / s / c otherwise.
function EV:FormatMoney(copper)
    if type(copper) ~= "number" then return "" end
    local whole = math.floor(math.abs(copper) + 0.5)
    local icons = whole > 0 and Coins(whole)
    if icons then return (copper < 0 and "-" or "") .. icons end
    local T = EV.Theme
    local function Hex(token) return (T and T.Hex and T.Hex(token)) or EV.ACCENT_HEX end
    local function Sym(global, fallback) local v = _G[global]; return type(v) == "string" and v or fallback end
    local left = math.floor(math.abs(copper) + 0.5)
    local parts = {}
    for _, unit in ipairs(COIN) do
        local value = math.floor(left / unit[1])
        left = left - value * unit[1]
        if value > 0 then parts[#parts + 1] = EV:Colour(value .. Sym(unit[3], unit[4]), Hex(unit[2])) end
    end
    if #parts == 0 then parts[1] = EV:Colour("0" .. Sym("COPPER_AMOUNT_SYMBOL", "c"), Hex("coinCopper")) end
    return (copper < 0 and "-" or "") .. table.concat(parts, " ")
end
