if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Restock.lua
--  Keep reagents, ammo, food and water topped up. Each character has its own
--  list (a mage's powders are no use to a hunter): an item and how many you
--  want to carry. At a vendor that sells something on the list, we buy the
--  difference.
--
--  Adding to the list: Alt + click the item in the vendor's window, which
--  asks how many to carry (a full stack is filled in). Alt + click a listed
--  item to change the amount or stop. The Quality of Life page edits the
--  list too. Items on your list get a mark in the vendor's window.
--
--  Buying follows Blizzard's own stack buying (MerchantItemButton_
--  BuyMultipleStacks): BuyMerchantItem(index, quantity) takes a count of
--  ITEMS, at most GetMerchantItemMaxStack per call, in steps of the batch the
--  vendor sells (stackCount, 200 for arrows). We round up to whole batches,
--  never spend more than you have, and skip anything with an item or
--  currency cost. Hold Shift as the window opens to skip, like the rest of
--  the module.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local R = {}
ns.Restock = R

function R.List() return EV.DB:GetCharData("restock") end

--- Items kept on the list but not bought for now: id -> true.
local function PausedSet() return EV.DB:GetCharData("restockPaused") end
function R.Paused(id) return PausedSet()[id] and true or false end
function R.SetPaused(id, on) PausedSet()[id] = on and true or nil end

function R.Remove(id)
    R.List()[id] = nil
    PausedSet()[id] = nil
end

function R.Icon(id)
    return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400
end

local function Count(id)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id, false)
        if ok and type(n) == "number" then return n end
    end
    return 0
end
R.Count = Count

-- The table from C_MerchantFrame.GetItemInfo, or the same fields built from
-- the older GetMerchantItemInfo returns (the vanilla-family merchant window
-- still uses those).
local function ItemInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and type(info) == "table" then return info end
    end
    if type(GetMerchantItemInfo) == "function" then
        local ok, name, _, price, stackCount, numAvailable, isPurchasable, _, extendedCost = pcall(GetMerchantItemInfo, index)
        if ok and name then
            return { price = price, stackCount = stackCount, numAvailable = numAvailable,
                     isPurchasable = isPurchasable, hasExtendedCost = extendedCost }
        end
    end
end

function R.Name(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return name or ("item:" .. id)
end

function R.Link(id)
    local _, link = C_Item.GetItemInfo(id)
    return link or R.Name(id)
end

--- A sensible starting target: one full stack (a quiver's worth is up to you).
function R.DefaultTarget(id)
    local fn = C_Item and (C_Item.GetItemMaxStackSizeByID or C_Item.GetItemMaxStackSize)
    local ok, n = false, nil
    if fn then ok, n = pcall(fn, id) end
    return (ok and type(n) == "number" and n > 0) and n or 20
end

--- The purchases this vendor would make now: { index, id, qty, cost }.
function R.Plan()
    local list = R.List()
    local plan = {}
    if not next(list) or type(GetMerchantNumItems) ~= "function" then return plan end
    local money = GetMoney()
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        local target = id and list[id]
        if type(target) == "number" and target > 0 and not R.Paused(id) then
            local info = ItemInfo(i)
            local need = target - Count(id)
            if info and need > 0 and info.isPurchasable ~= false and not info.hasExtendedCost then
                local batch = max(1, info.stackCount or 1)
                local qty = ceil(need / batch) * batch
                if (info.numAvailable or -1) >= 0 and info.numAvailable < qty / batch then
                    qty = (info.numAvailable or 0) * batch
                end
                local each = (info.price or 0) / batch
                if each > 0 then
                    qty = min(qty, floor(money / each / batch) * batch)
                end
                if qty > 0 then
                    local cost = floor(each * qty + 0.5)
                    money = money - cost
                    plan[#plan + 1] = { index = i, id = id, qty = qty, cost = cost }
                end
            end
        end
    end
    return plan
end

local function Buy(plan)
    local spent, lines = 0, {}
    local calls = {}
    for _, p in ipairs(plan) do
        local maxStack = max(1, GetMerchantItemMaxStack(p.index) or 1)
        local left = p.qty
        while left > 0 do
            local q = min(left, maxStack)
            calls[#calls + 1] = { p.index, q }
            left = left - q
        end
        spent = spent + p.cost
        lines[#lines + 1] = ("%s x%d"):format(R.Link(p.id), p.qty)
    end
    -- A little apart, as a person clicking would; the server drops purchases
    -- sent in the same instant.
    for n, c in ipairs(calls) do
        C_Timer.After((n - 1) * 0.2, function()
            if MerchantFrame and MerchantFrame:IsShown() then BuyMerchantItem(c[1], c[2]) end
        end)
    end
    if #lines > 0 and ns.module.db.announceVendor then
        ns.Say(L["Restocked %s for %s."], table.concat(lines, ", "), ns.Money(spent))
    end
end

local function OnMerchant()
    local db = ns.module and ns.module.db
    if not (db and db.restock) or ns.Skip() then return end
    -- After the sale of greys (Vendor.lua) has had a moment to pay out.
    C_Timer.After(0.4, function()
        if not (MerchantFrame and MerchantFrame:IsShown()) then return end
        local plan = R.Plan()
        if #plan > 0 then Buy(plan) end
    end)
end

--------------------------------------------------------------------------------
--  Alt + click in the vendor's window, and marks on listed items
--------------------------------------------------------------------------------
local function Mark(button, on)
    local m = button.evRestock
    if not m then
        m = button:CreateTexture(nil, "OVERLAY", nil, 7)
        m:SetSize(14, 14)
        m:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        m:SetAtlas("common-icon-checkmark")
        button.evRestock = m
    end
    m:SetShown(on)
end

local function MarkAll()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local list = R.List()
    local on = ns.module and ns.module.db.restock
    for i = 1, MERCHANT_ITEMS_PER_PAGE or 10 do
        local b = _G["MerchantItem" .. i .. "ItemButton"]
        if b then
            local id = MerchantFrame.selectedTab == 1 and b:IsShown() and GetMerchantItemID(b:GetID())
            Mark(b, on and id and list[id] ~= nil or false)
        end
    end
end
R.MarkAll = MarkAll

--- Buy for the list right away, as if the window had just opened.
local function BuyNow()
    local db = ns.module and ns.module.db
    if not (db and db.restock and MerchantFrame and MerchantFrame:IsShown()) then return end
    local plan = R.Plan()
    if #plan > 0 then Buy(plan) end
end

--- Set how many to carry; 0 or less takes it off the list.
function R.Set(id, amount)
    local list = R.List()
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        if list[id] then
            R.Remove(id)
            ns.Say(L["No longer restocking %s."], R.Link(id))
        end
    else
        amount = floor(amount)
        list[id] = amount
        R.SetPaused(id, false)
        ns.Say(L["Restocking %s up to %d."], R.Link(id), amount)
        BuyNow()
    end
    MarkAll()
end

local function Ask(id)
    local listed = R.List()[id]
    EV.UI.AskNumber{
        title = L["Restock"],
        text = (L["How many %s do you want to carry?"]):format(R.Link(id)),
        value = listed or R.DefaultTarget(id),
        min = 0, max = 99999,
        onSave = function(n) R.Set(id, n) end,
        extra = listed and { text = L["Stop restocking"], style = "danger",
                             onClick = function() R.Set(id, 0) end } or nil,
    }
end

local function OnModifiedClick(self)
    local db = ns.module and ns.module.db
    if not (db and db.restock) or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    if not (MerchantFrame and MerchantFrame.selectedTab == 1) then return end
    local id = GetMerchantItemID(self:GetID())
    if not id then return end
    Ask(id)
end

--------------------------------------------------------------------------------
--  A hint on the vendor's item tooltip, directly under Blizzard's
--  "<Shift click to buy a different amount>" line and in its colour. A line
--  post call on that line puts it there as the tooltip is built; items that
--  don't stack have no Shift line, so the tooltip post call adds it at the
--  end instead. Both run on every rebuild, so refreshes keep it.
--------------------------------------------------------------------------------
local SHIFT_LINE = ITEM_VENDOR_STACK_BUY

local function HintText(tt)
    if tt ~= GameTooltip then return nil end
    local db = ns.module and ns.module.db
    if not (db and db.restock and MerchantFrame and MerchantFrame:IsShown() and MerchantFrame.selectedTab == 1) then return nil end
    local owner = tt:GetOwner()
    local oname = owner and owner.GetName and owner:GetName()
    if not (oname and oname:find("^MerchantItem%d+ItemButton$")) then return nil end
    local id = GetMerchantItemID(owner:GetID())
    if not id then return nil end
    local listed = R.List()[id]
    if listed then
        local state = R.Paused(id) and L["paused"] or (L["keeping %d"]):format(listed)
        return (L["<Alt click to change restock, %s>"]):format(state)
    end
    return L["<Alt click to restock this item>"]
end

local function IsShiftLine(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
    if SHIFT_LINE and text == SHIFT_LINE then return true end
    return text:find("^<Shift") ~= nil
end

local function OnLine(tt, line)
    if not (line and IsShiftLine(line.leftText)) then return end
    local text = HintText(tt)
    if not text then return end
    local c = line.leftColor
    local r, g, b = 0, 1, 0
    if c and c.GetRGB then r, g, b = c:GetRGB() end
    tt:AddLine(text, r, g, b)
    tt._evRestockHint = true
end

local function OnItemTooltip(tt)
    if tt._evRestockHint then tt._evRestockHint = nil; return end
    local text = HintText(tt)
    if text then tt:AddLine(text, 0, 1, 0) end
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then OnMerchant() end
    MarkAll()
end)

function ns.EnableRestock()
    ev:RegisterEvent("MERCHANT_SHOW")
    ev:RegisterEvent("MERCHANT_UPDATE")
    if R.hooked then return end
    R.hooked = true
    if type(MerchantItemButton_OnModifiedClick) == "function" then
        hooksecurefunc("MerchantItemButton_OnModifiedClick", OnModifiedClick)
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        if TooltipDataProcessor.AddLinePostCall and Enum.TooltipDataLineType then
            TooltipDataProcessor.AddLinePostCall(Enum.TooltipDataLineType.None, function(tt, line)
                ns.Safe("restock hint", OnLine, tt, line)
            end)
        end
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
            ns.Safe("restock hint", OnItemTooltip, tt)
        end)
    end
    if type(MerchantFrame_UpdateMerchantInfo) == "function" then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", MarkAll)
    end
end
