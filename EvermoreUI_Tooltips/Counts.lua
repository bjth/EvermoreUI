if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Counts.lua
--  How many of an item you have across your characters, on its tooltip:
--
--      Thorvald           20  (bags 12, bank 8)
--      Elowen              4  (mail)
--      Account bank       40
--      Total              64
--
--  The numbers come from EV.Alts (EvermoreUI/Core/Alts.lua), which keeps a
--  snapshot of every character's bags, bank and mail. Only characters in
--  the scope set there count (your faction by default). With a single
--  place holding the item and it being your own bags, the tooltip already
--  says as much, so nothing is added.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EV = EvermoreUI
local M = ns.module
if not M then return end
local L = EV.L
local T = EV.Theme
local issecret = issecretvalue or function() return false end

M.defaults.itemCounts = true     -- counts across your characters
M.defaults.countsDetail = true   -- where each character keeps them

local PLACE_TEXT = {
    bags = L["bags"], bank = L["bank"], mail = L["mail"], equipped = L["equipped"],
}

local function Detail(row)
    local parts = {}
    for _, place in ipairs(EV.Alts.PLACES) do
        local n = row[place]
        if n then
            -- "equipped" and "mail" read better without a count when it's all of them.
            if n == row.total and (place == "equipped" or place == "mail") then
                parts[#parts + 1] = PLACE_TEXT[place]
            else
                parts[#parts + 1] = PLACE_TEXT[place] .. " " .. n
            end
        end
    end
    return table.concat(parts, ", ")
end

local function OnItem(tt, data)
    if not (M.db.itemCounts and data and EV.Alts) or tt.isShopping then return end
    if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
    if not EV.Alts:Settings().track then return end
    local id = data.id
    if not id or issecret(id) then return end
    local c = EV.Alts:Counts(id)
    if not c or c.total == 0 then return end
    -- Only in your own bags: nothing the tooltip doesn't already tell you.
    if #c.chars == 1 and c.account == 0 and c.chars[1].entry.me
       and c.chars[1].bags == c.total then
        return
    end
    local mr, mg, mb = T.RGBA("textMuted")
    local tr, tg, tb = T.RGBA("text")
    tt:AddLine(" ")
    for _, row in ipairs(c.chars) do
        local right = tostring(row.total)
        if M.db.countsDetail then right = right .. "  |cff" .. T.Hex("textMuted") .. "(" .. Detail(row) .. ")|r" end
        tt:AddDoubleLine(EV.Alts:Coloured(row.entry.info), right, 1, 1, 1, tr, tg, tb)
    end
    if c.account > 0 then
        tt:AddDoubleLine(L["Account bank"], tostring(c.account), mr, mg, mb, tr, tg, tb)
    end
    if #c.chars + (c.account > 0 and 1 or 0) > 1 then
        local ar, ag, ab = T.RGBA("accent")
        tt:AddDoubleLine(L["Total"], tostring(c.total), ar, ag, ab, ar, ag, ab)
    end
end

local hooked = false
function ns.EnableCounts()
    if hooked then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        hooked = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if M:IsEnabled() then pcall(OnItem, tt, data) end
        end)
    end
end
