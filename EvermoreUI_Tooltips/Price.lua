if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Price.lua
--  What an item sells for, on its tooltip.
--
--  The client already has a sell price line: the server puts a SellPrice line
--  (Enum.TooltipDataLineType.SellPrice) in an item's tooltip data and
--  TooltipDataRules.SellPrice turns it into "Sell Price: ...". Where it is
--  there we leave it alone and only add the price of one when you are looking
--  at a stack. Where it is not (the server does not always send it), we add
--  our own from the item's own sell price, C_Item.GetItemInfo's eleventh
--  return, times the stack.
--
--  Stack size comes from the bag slot the tooltip belongs to (its owner
--  answers GetBagID and GetID, as every container item button does). Anything
--  else counts as one.
--
--  The per-item line is added from a line post call on the SellPrice line
--  itself, the same hook Blizzard uses to write "Sell Price:", so it lands
--  directly under it rather than at the foot of the tooltip. Money is written
--  with Blizzard's own formatter and tooltip format (MoneyFormatterUtil,
--  GameTooltipMoneyFormat), so it has the same coin icons as their line.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EV = EvermoreUI
local M = ns.module
if not M then return end
local L = EV.L
local issecret = issecretvalue or function() return false end

M.defaults.sellPrice = true

local SELL_LINE = Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice

local function StackCount(tt)
    local owner = tt.GetOwner and tt:GetOwner()
    if not owner then return 1 end
    local okB, bag = pcall(function() return owner.GetBagID and owner:GetBagID() end)
    local okS, slot = pcall(function() return owner.GetID and owner:GetID() end)
    if okB and okS and type(bag) == "number" and type(slot) == "number"
       and C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" and type(info.stackCount) == "number" and not issecret(info.stackCount) then
            return math.max(1, info.stackCount)
        end
    end
    return 1
end

--- Money as Blizzard's tooltips write it: their tooltip money format when
--- it's there, the suite's (also coin icons) otherwise.
local function Money(copper)
    if MoneyFormatterUtil and MoneyFormatterUtil.FormatMoney and GameTooltipMoneyFormat then
        local ok, text = pcall(MoneyFormatterUtil.FormatMoney, copper, GameTooltipMoneyFormat)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return EV:FormatMoney(copper)
end

local function Line(tt, label, copper)
    local text = ("%s: %s"):format(label, Money(copper))
    if GameTooltip_AddHighlightLine then GameTooltip_AddHighlightLine(tt, text) else tt:AddLine(text, 1, 1, 1) end
end

local function BlizzardHasPrice(data)
    if not (SELL_LINE and data and type(data.lines) == "table") then return false end
    for _, line in ipairs(data.lines) do
        if line and line.type == SELL_LINE and line.price then return true end
    end
    return false
end

local function OnPrice(tt, data)
    if not M.db.sellPrice or not data or tt.isShopping then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local id = data.id
    if not id or issecret(id) then return end
    local ok, sell = pcall(function() return select(11, C_Item.GetItemInfo(id)) end)
    if not ok or type(sell) ~= "number" or issecret(sell) or sell <= 0 then return end
    -- Blizzard's line is there: the per-item line was added under it by
    -- OnSellLine below.
    if BlizzardHasPrice(data) then return end
    local count = StackCount(tt)
    Line(tt, SELL_PRICE or L["Sell Price"], sell * count)
    if count > 1 then Line(tt, L["Each"], sell) end
end

--- Straight after Blizzard's "Sell Price:" line: the price of one, for a stack.
local function OnSellLine(tt, line)
    if not M.db.sellPrice or tt.isShopping or not line then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    local price = line.price
    if type(price) ~= "number" or issecret(price) or price <= 0 or (line.maxPrice and line.maxPrice > 0) then return end
    local count = StackCount(tt)
    if count > 1 then Line(tt, L["Each"], math.floor(price / count + 0.5)) end
end

local hooked = false
function ns.EnablePrice()
    if hooked then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if M:IsEnabled() then pcall(OnPrice, tt, data) end
        end)
        if SELL_LINE and TooltipDataProcessor.AddLinePostCall then
            TooltipDataProcessor.AddLinePostCall(SELL_LINE, function(tt, line)
                if M:IsEnabled() then pcall(OnSellLine, tt, line) end
            end)
        end
    end
end
