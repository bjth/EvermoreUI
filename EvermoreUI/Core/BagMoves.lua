if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  BagMoves.lua
--  Moving items between your bags, one pickup at a time. Used by the bag
--  bar's "empty this bag" (Alt + click a bag), so a bag can be swapped out.
--
--  EV.Bags:Empty(bag)   move everything in that bag into free space in the
--                       others; returns false with a reason if it can't start
--
--  The whole plan is made up front against a copy of the free slots, then run
--  one move per step: pick up from the source, drop on the target, wait for
--  both slots to unlock. Each step re-checks that the source still holds the
--  item and the target is still free, so a bag change mid-way (loot, a sale)
--  just skips that move.
--
--  Where an item may go:
--    * a partial stack of the same item with room for the whole stack first,
--      so nothing is split and space is saved
--    * then an empty slot in a bag that takes it: a normal bag takes anything,
--      a special bag (quiver, soul bag, herb bag) only items whose family
--      matches, and the reagent bag only crafting reagents
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local band = bit and bit.band

local Bags = {}
EV.Bags = Bags

local STEP = 0.15   -- seconds between moves, while slots unlock

local function NumBags() return NUM_BAG_SLOTS or 4 end
local function ReagentBag() return (NUM_BAG_SLOTS or 4) + 1 end

local function Info(bag, slot)
    local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
    return ok and info or nil
end

local function Slots(bag)
    local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
    return ok and n or 0
end

local function Family(bag)
    local ok, _, fam = pcall(C_Container.GetContainerNumFreeSlots, bag)
    return ok and fam or 0
end

local function MaxStack(id)
    local ok, n = pcall(C_Item.GetItemMaxStackSizeByID, id)
    return ok and n or 1
end

local function Fits(id, bag, bagFamily)
    if bag == ReagentBag() then
        local ok, isReagent = pcall(function() return select(17, C_Item.GetItemInfo(id)) end)
        return ok and isReagent == true
    end
    if not bagFamily or bagFamily == 0 then return true end
    local ok, fam = pcall(C_Item.GetItemFamily, id)
    return ok and type(fam) == "number" and band and band(fam, bagFamily) ~= 0 or false
end

--- The bags an item from `source` can go to, special bags first so a quiver
--- fills before your normal bags do.
local function Targets(source)
    local list = {}
    for bag = 0, ReagentBag() do
        if bag ~= source and Slots(bag) > 0 then
            list[#list + 1] = { bag = bag, family = Family(bag) }
        end
    end
    table.sort(list, function(a, b)
        local sa, sb = (a.family or 0) ~= 0, (b.family or 0) ~= 0
        if sa ~= sb then return sa end
        return a.bag < b.bag
    end)
    return list
end

--- { { from = {bag, slot}, to = {bag, slot} }, ... } and how many won't fit.
function Bags:Plan(source)
    local moves, left = {}, 0
    local targets = Targets(source)
    -- A working copy of what's in the other bags.
    local held = {}
    for _, t in ipairs(targets) do
        held[t.bag] = {}
        for slot = 1, Slots(t.bag) do
            local info = Info(t.bag, slot)
            held[t.bag][slot] = info and { id = info.itemID, count = info.stackCount or 1 } or false
        end
    end
    for slot = 1, Slots(source) do
        local info = Info(source, slot)
        if info and info.itemID then
            local id, count = info.itemID, info.stackCount or 1
            local dest
            -- Top up a partial stack, whole stack only.
            local max = MaxStack(id)
            if max > 1 then
                for _, t in ipairs(targets) do
                    for s, h in pairs(held[t.bag]) do
                        if h and h.id == id and h.count + count <= max then dest = { t.bag, s }; h.count = h.count + count; break end
                    end
                    if dest then break end
                end
            end
            if not dest then
                for _, t in ipairs(targets) do
                    if Fits(id, t.bag, t.family) then
                        for s = 1, Slots(t.bag) do
                            if held[t.bag][s] == false then
                                dest = { t.bag, s }
                                held[t.bag][s] = { id = id, count = count }
                                break
                            end
                        end
                    end
                    if dest then break end
                end
            end
            if dest then
                moves[#moves + 1] = { from = { source, slot }, to = dest, id = id }
            else
                left = left + 1
            end
        end
    end
    return moves, left
end

local running

local function Finish(source, moved, left)
    running = nil
    local name = C_Container.GetBagName and C_Container.GetBagName(source) or (L["Bag"] .. " " .. source)
    if left > 0 then
        EV:Print((L["Emptied what fits from %s: %d moved, %d still in it (no room elsewhere)."]):format(name, moved, left))
    else
        EV:Print((L["%s is empty (%d moved). You can swap it now."]):format(name, moved))
    end
end

local function Locked(bag, slot)
    local info = Info(bag, slot)
    return info and info.isLocked
end

local function Step()
    local r = running
    if not r then return end
    if CursorHasItem and CursorHasItem() then
        -- Something is on the cursor that isn't ours: stop rather than drop it.
        running = nil
        EV:Print(L["Stopped emptying the bag: something is on your cursor."])
        return
    end
    local m = r.moves[r.i]
    if not m then return Finish(r.source, r.moved, r.left + r.skipped) end
    local fb, fs, tb, ts = m.from[1], m.from[2], m.to[1], m.to[2]
    if (Locked(fb, fs) or Locked(tb, ts)) and r.waits < 20 then
        r.waits = r.waits + 1
        C_Timer.After(STEP, Step)
        return
    end
    r.waits = 0
    r.i = r.i + 1
    local src = Info(fb, fs)
    local dst = Info(tb, ts)
    if src and src.itemID == m.id and (not dst or dst.itemID == m.id) then
        C_Container.PickupContainerItem(fb, fs)
        C_Container.PickupContainerItem(tb, ts)
        if CursorHasItem and CursorHasItem() then ClearCursor() end
        r.moved = r.moved + 1
    else
        r.skipped = r.skipped + 1
    end
    C_Timer.After(STEP, Step)
end

--- Move everything out of `bag` into the others. false, reason if it can't.
function Bags:Empty(bag)
    if running then return false, L["Already emptying a bag."] end
    if type(bag) ~= "number" or bag < 1 or bag > ReagentBag() then return false, L["That isn't a bag you can empty."] end
    if Slots(bag) == 0 then return false, L["There's no bag in that slot."] end
    if CursorHasItem and CursorHasItem() then return false, L["Put down what's on your cursor first."] end
    local moves, left = self:Plan(bag)
    if #moves == 0 then
        if left > 0 then return false, L["There's no room in your other bags."] end
        return false, L["That bag is already empty."]
    end
    running = { source = bag, moves = moves, i = 1, moved = 0, left = left, skipped = 0, waits = 0 }
    Step()
    return true
end

function Bags:IsBusy() return running ~= nil end
