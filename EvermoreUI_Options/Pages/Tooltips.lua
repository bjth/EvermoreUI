if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Tooltips: Look, Units, Position.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local floor = math.floor

local M = EV:GetModule("Tooltips", true)
if not M then return end

local TAB_LOOK, TAB_UNITS, TAB_POSITION = L["Look"], L["Units"], L["Position"]

local OUTLINES = {
    { value = "NONE", text = L["None"] }, { value = "OUTLINE", text = L["Outline"] },
    { value = "THICKOUTLINE", text = L["Thick outline"] },
}
local ANCHORS = {
    { value = "fixed", text = L["Fixed (edit mode)"] }, { value = "cursor", text = L["Follow the cursor"] },
    { value = "blizzard", text = L["Blizzard's spot"] },
}
local CURSOR_POS = {
    { value = "right", text = L["Right"] }, { value = "left", text = L["Left"] },
    { value = "top", text = L["Above"] }, { value = "bottom", text = L["Below"] },
    { value = "topright", text = L["Above right"] }, { value = "topleft", text = L["Above left"] },
    { value = "bottomright", text = L["Below right"] }, { value = "bottomleft", text = L["Below left"] },
}

local function Get(k) return function() return M.db[k] end end
local function Set(k) return function(v) M.db[k] = v; M:Refresh() end end
local function Off() return not M.db.skin end
local function T(k, text, tip, disabled)
    return { type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k), disabled = disabled }
end
local function S(k, text, lo, hi, disabled, fmt)
    return { type = "slider", text = text, min = lo, max = hi, step = 1, fmt = fmt, get = Get(k), set = Set(k), disabled = disabled }
end

local function Fonts() return EV.Media:FontValues(true) end

local function Look(p)
    p:Section(L["Panel"])
    p:Dual(T("skin", L["EvermoreUI style"], L["Our panel colour, border and font on every tooltip and right-click menu. Turning it off fully needs a reload."]),
           { type = "slider", text = L["Background opacity"], min = 50, max = 100, step = 5, disabled = Off,
             fmt = function(v) return v .. "%" end,
             get = function() return floor(M.db.bgAlpha * 100 + 0.5) end,
             set = function(v) M.db.bgAlpha = v / 100; M:Refresh() end })
    p:Dual(T("qualityBorder", L["Quality-coloured border"], L["Uncommon and better items colour the tooltip's border."], Off),
           T("menus", L["Right-click menus too"], L["Menus get the same panel and border. Turning it off needs a reload."]))

    p:Dual({ type = "slider", text = L["Gap between comparisons"], min = 0, max = 8, step = 1, disabled = Off,
             fmt = function(v) return v .. "px" end,
             tooltip = L["Space between an item's tooltip and the Equipped ones beside it, so their borders don't double up."],
             get = Get("compareGap"), set = Set("compareGap") }, nil)

    p:Section(L["Text"])
    p:Dual({ type = "dropdown", text = L["Font"], width = 170, values = Fonts, get = Get("font"), set = Set("font"), disabled = Off },
           { type = "dropdown", text = L["Outline"], width = 150, values = OUTLINES, get = Get("outline"), set = Set("outline"), disabled = Off })
    p:Dual(S("titleSize", L["Title size"], 10, 20, Off), S("bodySize", L["Text size"], 8, 16, Off))

    p:Section(L["Health bar"])
    p:Dual(T("healthBar", L["Show the health bar"], L["A slim bar inside the bottom edge of unit tooltips."]),
           S("barHeight", L["Bar height"], 2, 10, function() return Off() or not M.db.healthBar end, function(v) return v .. "px" end))
end

local function Units(p)
    p:Section(L["Players"])
    p:Dual(T("classColours", L["Class colours"], L["Player names and health bars in class colour; creatures' bars in their reaction colour."]),
           T("hideTitles", L["Hide titles"], L["Just the name (and realm) on the first line."]))
    p:Dual(T("guildRank", L["Guild rank"], L["Adds their rank after the guild name."]),
           T("itemLevel", L["Item level"], L["Inspects quietly (out of combat, once per person) and remembers it for two minutes."]))
    p:Section(L["Everyone"])
    p:Dual(T("targetLine", L["Who they're targeting"], L["A Target: row, updated while the tooltip is up. Shows You in red when it's you."]),
           T("showIds", L["Spell and item IDs"], L["Handy for addon work."]))
    p:Section(L["Items"])
    p:Dual(T("sellPrice", L["Sell price"], L["What an item sells for at a vendor, with the price of one when it's a stack."]), nil)
end

local function Position(p)
    p:Section(L["Where tooltips go"])
    p:Dual({ type = "dropdown", text = L["Position"], width = 190, values = ANCHORS, get = Get("anchor"), set = Set("anchor"),
             tooltip = L["Fixed starts exactly where Blizzard's is, and you move it in edit mode. It grows away from the nearest screen edge."] },
           { type = "button", text = L["Move it"], label = L["Edit mode"], width = 120,
             disabled = function() return M.db.anchor ~= "fixed" end,
             onClick = function() EV.Movers:Unlock() end })
    p:Section(L["Following the cursor"])
    local function NotCursor() return M.db.anchor ~= "cursor" end
    p:Dual({ type = "dropdown", text = L["Side"], width = 150, values = CURSOR_POS, get = Get("cursorPos"), set = Set("cursorPos"), disabled = NotCursor },
           nil)
    p:Dual(S("cursorX", L["Distance across"], -60, 60, NotCursor), S("cursorY", L["Distance up/down"], -60, 60, NotCursor))
end

EV.Options:RegisterPage{
    key = "tooltips", title = L["Tooltips"], group = "Chat & Tooltips", module = "Tooltips",
    description = L["Tooltips and right-click menus in the EvermoreUI style, with class colours, item level and a movable or cursor anchor."],
    tabs = { TAB_LOOK, TAB_UNITS, TAB_POSITION },
    build = function(p, tab)
        if tab == TAB_UNITS then return Units(p) end
        if tab == TAB_POSITION then return Position(p) end
        return Look(p)
    end,
    onReset = function(tab)
        local keys = {
            [TAB_LOOK] = { "skin", "bgAlpha", "qualityBorder", "menus", "compareGap", "font", "outline", "titleSize", "bodySize", "healthBar", "barHeight" },
            [TAB_UNITS] = { "classColours", "hideTitles", "guildRank", "itemLevel", "targetLine", "showIds", "sellPrice" },
            [TAB_POSITION] = { "anchor", "cursorPos", "cursorX", "cursorY" },
        }
        for _, k in ipairs(keys[tab] or keys[TAB_LOOK]) do M.db[k] = M.defaults[k] end
        M:Refresh()
    end,
}
