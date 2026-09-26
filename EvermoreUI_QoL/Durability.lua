if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Durability.lua
--  One chat line when your gear gets low, with what the repair will cost.
--
--  The reading is EV:ReadDurability (core), which the Data Bars readout
--  shares. This file only decides when to speak: once when the worst item
--  drops below the threshold, and again if something breaks. It re-arms once
--  you are back above the line, so it never nags about the same wear twice.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

local warnedLow, warnedBroken = false, false

local function Check()
    local db = ns.module and ns.module.db
    if not (db and db.durabilityWarn) then return end
    local d = EV:ReadDurability()
    local at = tonumber(db.durabilityAt) or 25
    if d.lowest >= at then warnedLow = false end
    if d.broken == 0 then warnedBroken = false end

    local cost = ""
    if d.cost and d.cost > 0 then
        cost = " " .. (d.known and L["Repair:"] or L["Repair, at least:"]) .. " " .. ns.Money(d.cost) .. "."
    end
    if d.broken > 0 and not warnedBroken then
        warnedBroken, warnedLow = true, true
        ns.Say("%s%s", (d.broken == 1 and L["1 item is broken and doing nothing."]
            or (d.broken .. " " .. L["items are broken and doing nothing."])), cost)
    elseif d.lowest < at and not warnedLow then
        warnedLow = true
        ns.Say("%s %d%% (%s).%s", L["Gear durability is down to"], math.floor(d.lowest + 0.5),
               EV:SlotName(d.worstSlot), cost)
    end
end
ns.CheckDurability = Check

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function() ns.Safe("durability", Check) end)

function ns.EnableDurability(M)
    ev:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
end
