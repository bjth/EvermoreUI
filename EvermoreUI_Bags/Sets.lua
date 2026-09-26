if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Sets.lua
--  Section setups: ready-made ones to add, and your whole setup as a string
--  to share or keep.
--
--  A ready-made set adds its sections (a section of yours with the same name
--  gets the set's rules instead of a copy), puts them at the top in the
--  set's order followed by the built-in sections it cares about, and
--  switches those built-ins on. Everything else you have stays.
--
--  A shared string is the whole setup: your sections, the order, which
--  built-ins are on, and what you've dropped where. Importing replaces yours.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

local Sets = {}
ns.Sets = Sets

local function BOE() return (ITEM_BIND_ON_EQUIP or "Binds when equipped"):lower() end

--- name, description, sections = { { name, match, rules } }, top = built-in keys
Sets.READY = {
    {
        key = "gatherer", name = L["Gatherer"],
        description = L["Herbs, ore and stone, leather and cloth near the top, with sections for your tools, cooking, elemental and enchanting materials."],
        sections = function()
            return {
                { name = L["Gathering tools"], match = "any", rules = {
                    { kind = "ids", value = "2901, 7005, 6256, 6365, 6366, 6367, 12225, 19022, 19970, 5956" },
                    { kind = "name", value = L["fishing pole"] } } },
                { name = L["Cooking"], rules = { { kind = "type", value = "7:8" } } },
                { name = L["Elemental"], rules = { { kind = "type", value = "7:10" } } },
                { name = L["Enchanting"], rules = { { kind = "type", value = "7:12" } } },
            }
        end,
        top = { "herbs", "ore", "leather", "cloth" },
    },
    {
        key = "raider", name = L["Dungeons and raids"],
        description = L["Potions, elixirs and flasks, food, bandages and gear you haven't bound yet, with your gear sets and equipment first."],
        sections = function()
            return {
                { name = L["Potions"], rules = { { kind = "type", value = "0:1" } } },
                { name = L["Elixirs and flasks"], match = "any", rules = {
                    { kind = "type", value = "0:2" }, { kind = "type", value = "0:3" } } },
                { name = L["Food and drink"], rules = { { kind = "type", value = "0:5" } } },
                { name = L["Bandages"], rules = { { kind = "type", value = "0:7" } } },
                { name = L["Bind on equip"], rules = {
                    { kind = "bound", value = "no" }, { kind = "tooltip", value = BOE() } } },
            }
        end,
        top = { "sets", "equipment" },
    },
    {
        key = "levelling", name = L["Levelling"],
        description = L["New items and quest items first, then food, potions and bandages, then gear."],
        sections = function()
            return {
                { name = L["Food and drink"], rules = { { kind = "type", value = "0:5" } } },
                { name = L["Potions"], rules = { { kind = "type", value = "0:1" } } },
                { name = L["Bandages"], rules = { { kind = "type", value = "0:7" } } },
            }
        end,
        top = { "new", "quest" },
        first = true,   -- its top built-ins go above its own sections
    },
}

--- Add a ready-made set to your setup.
function Sets.Apply(set)
    local M = ns.module
    local db = M.db
    local keys = {}
    for _, def in ipairs(set.sections()) do
        local sec
        for _, mine in ipairs(db.custom) do
            if mine.name == def.name then sec = mine; break end
        end
        if not sec then sec = M.NewSection(def.name) end
        sec.on = true
        sec.match = def.match or "all"
        sec.rules = def.rules
        keys[#keys + 1] = sec.key
    end
    for _, k in ipairs(set.top or {}) do db.categories[k] = true end

    local front = {}
    if set.first then
        for _, k in ipairs(set.top or {}) do front[#front + 1] = k end
        for _, k in ipairs(keys) do front[#front + 1] = k end
    else
        for _, k in ipairs(keys) do front[#front + 1] = k end
        for _, k in ipairs(set.top or {}) do front[#front + 1] = k end
    end
    local placed = {}
    local order = {}
    for _, k in ipairs(front) do if not placed[k] then placed[k] = true; order[#order + 1] = k end end
    for _, e in ipairs(M.All()) do
        if not placed[e.key] then placed[e.key] = true; order[#order + 1] = e.key end
    end
    db.order = order
    M:Refresh()
end

--- Your whole setup as a string.
function Sets.Export()
    local db = ns.module.db
    return EV.Serialize.Encode({
        v = 1, kind = "bagsections",
        custom = EV.CopyTable(db.custom), order = EV.CopyTable(db.order),
        categories = EV.CopyTable(db.categories), assign = EV.CopyTable(db.assign),
    })
end

--- Replace your setup with one from a string. nil, reason if it isn't one.
function Sets.Import(text)
    local data, err = EV.Serialize.Decode(text)
    if not data then return nil, err end
    if type(data) ~= "table" or data.kind ~= "bagsections" then
        return nil, L["That string isn't a bag sections setup."]
    end
    local M = ns.module
    local db = M.db
    db.custom = type(data.custom) == "table" and data.custom or {}
    db.order = type(data.order) == "table" and data.order or {}
    db.assign = type(data.assign) == "table" and data.assign or {}
    if type(data.categories) == "table" then
        for k, v in pairs(data.categories) do db.categories[k] = v and true or false end
    end
    M:Refresh()
    return true
end
