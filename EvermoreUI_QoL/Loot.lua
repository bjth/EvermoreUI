if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Loot.lua
--  Take everything, instantly.
--
--  LootSlot(i) on every slot, all in the same frame, on LOOT_READY. READY
--  fires as soon as the server has the contents, before the loot window is
--  built, so everything is asked for at once and the window usually never
--  has anything left to show. That is the whole trick, and it is what makes
--  this faster than the client's own auto loot, which takes one slot at a
--  time and plays a slide-out for each (LootFrameMixin, LOOT_SLOT_CLEARED).
--
--  C_LootFrame.TryAutoLoot() is NOT used. It is the gamepad's "Loot All"
--  (Mainline/LootFrame.lua, SetupGamepad), i.e. that same paced auto loot,
--  and because it returns nothing a pcall around it always "succeeded", so
--  the instant path below never ran. That is why fast loot was not fast.
--
--  Slots are visited backwards: LootSlot renumbers the remaining slots as
--  they empty, so counting down is the only order that reaches every one.
--  Locked slots (someone else's roll, a quest item you cannot take) are
--  skipped rather than asked for and refused.
--
--  LOOT_OPENED is a second chance for anything that was not ready the first
--  time. A short guard stops READY and OPENED for the same corpse both
--  sweeping, which would double every request.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local GUARD = 0.3     -- seconds: one sweep per corpse, not one per event
local last = 0

local function Locked(i)
    if type(GetLootSlotInfo) ~= "function" then return false end
    local ok, _, _, _, _, _, locked = pcall(GetLootSlotInfo, i)
    return ok and locked == true
end

local function TakeAll()
    if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then return false end
    local now = GetTime()
    if now - last < GUARD then return true end
    last = now
    local ok, n = pcall(GetNumLootItems)
    if not ok or type(n) ~= "number" then return false end
    for i = n, 1, -1 do
        if not Locked(i) then pcall(LootSlot, i) end
    end
    return true
end

function ns.EnableLoot(M)
    local function Loot(self)
        if not self.db.fastLoot then return end
        if ns.Skip() then return end
        ns.Safe("loot", TakeAll)
    end

    -- Not every client fires LOOT_READY; RegisterEvent returns false rather
    -- than erroring when it does not know one, so asking is free.
    M:RegisterEvent("LOOT_READY", Loot)
    M:RegisterEvent("LOOT_OPENED", Loot)
    -- A new corpse must never be refused because the last one was looted
    -- inside the guard window.
    M:RegisterEvent("LOOT_CLOSED", function() last = 0 end)
end
