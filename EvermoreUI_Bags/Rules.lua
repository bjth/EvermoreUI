if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Rules.lua
--  What a custom bag section can test an item for. A section holds a list of
--  rules and matches when all of them hold (or any, if set so), plus any
--  items put in it by hand.
--
--    { kind = "type",    value = "7" or "7:9" }       item class, or class:subclass
--    { kind = "quality", op = "atleast" | "is" | "atmost", value = 0..7 }
--    { kind = "name",    value = "potion" }           name contains (any case)
--    { kind = "tooltip", value = "use:" }             tooltip contains (any case)
--    { kind = "bound",   value = "yes" | "no" }       soulbound or not
--    { kind = "slot",    value = "INVTYPE_HEAD" }     where it's worn
--    { kind = "ilvl",    op = "atleast" | "atmost", value = n }
--    { kind = "set" }                                 in a gear set
--    { kind = "novalue" }                             vendors won't buy it
--    { kind = "ids",     value = "2589, 2592" }       these item IDs
--
--  Item fields that cost something (name, item level, tooltip text) are read
--  only when a rule asks, and the slow ones are cached per item link.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L
local issecret = issecretvalue or function() return false end

local R = {}
ns.Rules = R

local tooltipCache, ilvlCache = {}, {}
local idCache = setmetatable({}, { __mode = "k" })   -- rule -> set of IDs

local function Name(i)
    if i.name == nil then
        local n = C_Item.GetItemNameByID and C_Item.GetItemNameByID(i.id)
        i.name = (type(n) == "string" and n:lower()) or false
    end
    return i.name or ""
end

local function ItemLevel(i)
    if i.ilvl == nil then
        local key = i.link or i.id
        local v = ilvlCache[key]
        if v == nil and i.link and C_Item.GetDetailedItemLevelInfo then
            local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, i.link)
            v = ok and type(lvl) == "number" and lvl or false
            if v then ilvlCache[key] = v end
        end
        i.ilvl = v or false
    end
    return i.ilvl or 0
end
R.ItemLevel = ItemLevel

local function Tooltip(i)
    local key = i.link or i.id
    local t = tooltipCache[key]
    if t then return t end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return "" end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, i.bag, i.slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines < 2 then return "" end
    local parts = {}
    for _, line in ipairs(data.lines) do
        for _, txt in ipairs({ line.leftText, line.rightText }) do
            if type(txt) == "string" and not issecret(txt) then parts[#parts + 1] = txt:lower() end
        end
    end
    t = table.concat(parts, "\n")
    tooltipCache[key] = t
    return t
end

local function EquipLoc(i)
    if i.equipLoc == nil then
        local _, _, _, loc = C_Item.GetItemInfoInstant(i.id)
        i.equipLoc = loc or false
    end
    return i.equipLoc or ""
end

local function Compare(a, op, b)
    if op == "is" then return a == b end
    if op == "atmost" then return a <= b end
    return a >= b
end

local function IDs(value)
    local set = {}
    for n in tostring(value or ""):gmatch("%d+") do set[tonumber(n)] = true end
    return set
end

local TESTS = {
    type = function(r, i)
        local c, s = tostring(r.value or ""):match("^(%d+):?(%d*)$")
        if not c then return false end
        if tonumber(c) ~= i.class then return false end
        return s == "" or tonumber(s) == i.sub
    end,
    quality = function(r, i) return i.quality ~= nil and Compare(i.quality, r.op, tonumber(r.value) or 0) end,
    name = function(r, i)
        local v = tostring(r.value or ""):lower()
        return v ~= "" and Name(i):find(v, 1, true) ~= nil
    end,
    tooltip = function(r, i)
        local v = tostring(r.value or ""):lower()
        return v ~= "" and Tooltip(i):find(v, 1, true) ~= nil
    end,
    bound = function(r, i) return (i.bound and true or false) == (r.value ~= "no") end,
    slot = function(r, i) return EquipLoc(i) == r.value end,
    ilvl = function(r, i)
        if i.class ~= 2 and i.class ~= 4 then return false end
        return Compare(ItemLevel(i), r.op, tonumber(r.value) or 0)
    end,
    set = function(_, i) return i.inSet and true or false end,
    novalue = function(_, i) return i.noValue and true or false end,
    ids = function(r, i)
        local set = idCache[r]
        if not set then set = IDs(r.value); idCache[r] = set end
        return set[i.id] or false
    end,
}

--- Does this section take the item? Items put in it by hand always match.
function R.Matches(section, i)
    if section.items and section.items[i.id] then return true end
    local rules = section.rules
    if not rules or #rules == 0 then return false end
    local any = section.match == "any"
    for _, r in ipairs(rules) do
        local test = TESTS[r.kind]
        local ok = test and test(r, i) or false
        if any and ok then return true end
        if not any and not ok then return false end
    end
    return not any
end

--- A rule changed: drop anything cached from its old value.
function R.Changed(r) idCache[r] = nil end

--------------------------------------------------------------------------------
--  Lists for the editor
--------------------------------------------------------------------------------
R.KINDS = {
    { value = "type",    text = L["Item type"] },
    { value = "quality", text = L["Quality"] },
    { value = "name",    text = L["Name contains"] },
    { value = "tooltip", text = L["Tooltip contains"] },
    { value = "bound",   text = L["Soulbound"] },
    { value = "slot",    text = L["Worn on"] },
    { value = "ilvl",    text = L["Item level"] },
    { value = "set",     text = L["In a gear set"] },
    { value = "novalue", text = L["Can't be sold"] },
    { value = "ids",     text = L["These items"] },
}

R.OPS = {
    { value = "atleast", text = L["at least"] },
    { value = "is",      text = L["exactly"] },
    { value = "atmost",  text = L["at most"] },
}

function R.Qualities()
    local out = {}
    for q = 0, 7 do
        local name = _G["ITEM_QUALITY" .. q .. "_DESC"]
        if name then
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            out[#out + 1] = { value = q, text = c and c.hex and (c.hex .. name .. "|r") or name }
        end
    end
    return out
end

local CLASSES = { 0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 12, 13, 15 }
local typeList
function R.Types()
    if typeList then return typeList end
    typeList = {}
    for _, c in ipairs(CLASSES) do
        local cname = C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(c)
        if cname then
            typeList[#typeList + 1] = { value = tostring(c), text = cname }
            for s = 0, 20 do
                local sname = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(c, s)
                if sname and sname ~= "" and sname ~= cname then
                    typeList[#typeList + 1] = { value = c .. ":" .. s, text = cname .. " - " .. sname }
                end
            end
        end
    end
    return typeList
end

local SLOTS = {
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST", "INVTYPE_ROBE",
    "INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS",
    "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE",
    "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_AMMO",
    "INVTYPE_BAG", "INVTYPE_QUIVER",
}
function R.Slots()
    local out = {}
    for _, s in ipairs(SLOTS) do
        local name = _G[s]
        if type(name) == "string" then out[#out + 1] = { value = s, text = name } end
    end
    return out
end

R.BOUND = { { value = "yes", text = L["Yes"] }, { value = "no", text = L["No"] } }

--- A starting rule of each kind.
function R.New(kind)
    local r = { kind = kind }
    if kind == "type" then r.value = "0"
    elseif kind == "quality" then r.op, r.value = "atleast", 2
    elseif kind == "ilvl" then r.op, r.value = "atleast", 20
    elseif kind == "bound" then r.value = "yes"
    elseif kind == "slot" then r.value = "INVTYPE_HEAD"
    else r.value = "" end
    return r
end
