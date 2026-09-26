if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Vendor.lua
--  Repair, and sell the greys.
--
--  Read out of Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua rather than
--  reinvented:
--
--    GetRepairAllCost()        -> cost, canRepair      (line 961)
--    CanMerchantRepair()                                (line 988)
--    CanGuildBankRepair()                               (line 990)
--    RepairAllItems(useGuildBank)                       (GameDialogDefs.lua:565)
--    C_MerchantFrame.SellAllJunkItems()                 (line 1125)
--
--  SellAllJunkItems is the whole reason this file is short. Every other
--  addon walks the bags calling UseContainerItem slot by slot, which is
--  slow, rate limited, and one typo away from selling something that is not
--  grey. The client will do the entire job in one call, and it is the same
--  call the Sell All Junk button makes.
--
--  Repair order is guild funds first, then your own, which mirrors the
--  GUILDBANK_REPAIR popup: its accept button spends your gold and its cancel
--  button spends the guild's. We pick rather than ask.
--
--  Reporting a repair is one question with two halves: HOW MUCH, which is the
--  drop in GetRepairAllCost and is authoritative, and WHO PAID, which is
--  whether your own gold moved with it. Both are read by Reconcile below, off
--  PLAYER_MONEY and UPDATE_INVENTORY_DURABILITY, rather than announced by the
--  code that called RepairAllItems. That costs a few lines and buys two
--  things: the amount is what actually left the repair bill rather than what
--  we predicted, and repairs you make yourself with Blizzard's button get the
--  same line as ours.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

--- Money before the transaction, so we can report what a sale actually paid.
--- GetMoney is plain (not a secret value) but it is still read through a
--- guard, because a nil here would turn a helpful line into an error.
local function Money()
    if type(GetMoney) ~= "function" then return nil end
    local ok, m = pcall(GetMoney)
    if ok and type(m) == "number" then return m end
    return nil
end

--- What it would cost to repair everything right now, or 0 when the client
--- cannot say. A drop in this number is the only reliable signal that
--- durability was actually bought back.
local function RepairCost()
    if type(GetRepairAllCost) ~= "function" then return 0 end
    local ok, cost = pcall(GetRepairAllCost)
    if ok and type(cost) == "number" then return cost end
    return 0
end

--------------------------------------------------------------------------------
--  Watching a merchant visit
--
--  visit holds the last money and repair bill we saw while a merchant window
--  is open. It is nil the rest of the time, so the two events below cost a
--  table lookup out in the world.
--------------------------------------------------------------------------------
local visit = nil

local function Baseline()
    visit = { money = Money() or 0, cost = RepairCost() }
end

--- Could the guild have paid? Outside a guild, or without repair rights,
--- the answer is always your own gold, whatever the money delta says.
local function GuildCanPay()
    if type(IsInGuild) == "function" and not IsInGuild() then return false end
    if type(CanGuildBankRepair) ~= "function" then return false end
    local ok, can = pcall(CanGuildBankRepair)
    return ok and can and true or false
end

--- Say who paid once gold has settled. UPDATE_INVENTORY_DURABILITY can land
--- before PLAYER_MONEY, so reading the money delta on the same event sees no
--- gold spent yet.
local function Report(v, db)
    local p = v.pending
    v.pending = nil
    if not p then return end
    local money = Money() or v.money
    v.money = money
    if not db.announceVendor then return end
    local guild
    if p.purse then
        guild = p.purse == "guild"
    else
        guild = GuildCanPay() and (p.money - money) < p.amount
    end
    if guild then
        ns.Say(L["Repaired for %s from guild funds."], ns.Money(p.amount))
    else
        ns.Say(L["Repaired for %s."], ns.Money(p.amount))
    end
end

--- Called whenever gold or durability moves with a merchant open. The repair
--- bill going down is the trigger and gives the amount; who paid is decided
--- by Report a moment later. Our own auto repair records the purse it chose,
--- so the money delta is only a guess for repairs made with Blizzard's button.
local function Reconcile(db)
    local v = visit
    if not v then return end
    local cost = RepairCost()
    local repaired = v.cost - cost
    v.cost = cost
    if repaired <= 0 then
        if not v.pending then v.money = Money() or v.money end
        return
    end
    if v.pending then
        v.pending.amount = v.pending.amount + repaired
        return
    end
    v.pending = { amount = repaired, money = v.money, purse = v.purse }
    v.purse = nil
    C_Timer.After(0.5, function() Report(v, db) end)
end

--------------------------------------------------------------------------------
--  Repair
--------------------------------------------------------------------------------
local function Repair(db)
    if not db.autoRepair then return end
    if type(CanMerchantRepair) ~= "function" or not CanMerchantRepair() then return end
    if type(GetRepairAllCost) ~= "function" then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or type(cost) ~= "number" or cost <= 0 then return end

    -- Guild funds first when the guild allows it. CanGuildBankRepair answers
    -- "is this character permitted to", not "is there enough in the tab", so
    -- the guild attempt can still silently do nothing; we compare gold
    -- afterwards to find out which one actually paid.
    local before = Money()
    local triedGuild = false
    if db.repairFromGuild and GuildCanPay() then
        triedGuild = true
        RepairAllItems(true)
    end

    -- Did the guild attempt cover it? A second GetRepairAllCost tells us
    -- plainly: still repairable means it did not.
    local stillCost, stillCan = GetRepairAllCost()
    local guildPaid = triedGuild and not (stillCan and type(stillCost) == "number" and stillCost > 0)

    if visit then visit.purse = guildPaid and "guild" or "own" end

    if not guildPaid then
        if type(before) == "number" and before < cost then
            if db.announceVendor then
                ns.Say(L["Not enough gold to repair (%s needed)."], ns.Money(cost))
            end
            return
        end
        RepairAllItems()
    end

    -- No announcement here: Reconcile says what was repaired and who paid,
    -- once the server has confirmed both.
    if PlaySound and SOUNDKIT and SOUNDKIT.ITEM_REPAIR then
        pcall(PlaySound, SOUNDKIT.ITEM_REPAIR)
    end
end

--------------------------------------------------------------------------------
--  Sell greys
--------------------------------------------------------------------------------
local function SellJunk(db)
    if not db.autoSellJunk then return end
    if not (C_MerchantFrame and type(C_MerchantFrame.SellAllJunkItems) == "function") then return end

    local before = Money()
    C_MerchantFrame.SellAllJunkItems()

    if not db.announceVendor then return end
    -- The sale settles on the server, so the gold has not moved yet. Look
    -- again on the next frame rather than reporting zero every time.
    if type(before) ~= "number" then return end
    C_Timer.After(0.5, function()
        local after = Money()
        if type(after) == "number" and after > before then
            ns.Say(L["Sold greys for %s."], ns.Money(after - before))
        end
    end)
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
function ns.EnableVendor(M)
    M:RegisterEvent("MERCHANT_SHOW", function(self)
        -- Baseline first and outside the skip guard: holding Shift stands our
        -- automation down, it does not stop us reporting what you then do
        -- yourself at the same window.
        Baseline()
        if ns.Skip() then return end
        local db = self.db
        ns.Safe("repair", Repair, db)
        ns.Safe("selljunk", SellJunk, db)
    end)

    M:RegisterEvent("MERCHANT_CLOSED", function() visit = nil end)

    -- Either event can arrive first, and whichever is second completes the
    -- picture, so both run the same reconcile.
    local function Changed(self) ns.Safe("vendorwatch", Reconcile, self.db) end
    M:RegisterEvent("PLAYER_MONEY", Changed)
    M:RegisterEvent("UPDATE_INVENTORY_DURABILITY", Changed)
end
