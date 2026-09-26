if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  GroupSettings.lua
--  Every party and raid frame setting, written once, for the designer's
--  inspector (GroupDesigner.lua).
--
--  ns.GroupSettings(p, kind, parts): p is an options page builder, kind
--  "party" or "raid", parts a list of part names from PARTS below, drawn in
--  that order. Changes are written straight to the settings; the designer
--  applies them to the real frames when it commits.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

local COLOURS = {
    { value = "class", text = L["Class"] },
    { value = "green", text = L["Green"] },
    { value = "dark",  text = L["Dark"] },
}
local HEALTH_TEXT = {
    { value = "none",    text = L["None"] },
    { value = "percent", text = L["87%"] },
    { value = "deficit", text = L["Missing (-1.8k)"] },
    { value = "current", text = L["12.3k"] },
}
local GROW = {
    { value = "DOWN", text = L["Downwards"] }, { value = "UP", text = L["Upwards"] },
    { value = "RIGHT", text = L["Rightwards"] }, { value = "LEFT", text = L["Leftwards"] },
}
local PARTY_SORT = {
    { value = "index", text = L["Group order"] }, { value = "role", text = L["Tank, healer, damage"] },
    { value = "name", text = L["Name"] },
}
local RAID_SORT = {
    { value = "group", text = L["By group"] }, { value = "role", text = L["Tank, healer, damage"] },
    { value = "class", text = L["By class"] },
}
local RAID_LAYOUT = {
    { value = "columns", text = L["Groups side by side"] }, { value = "rows", text = L["Groups stacked"] },
}
local TEXT_STYLE = {
    { value = "both",    text = L["Outline and shadow"] },
    { value = "shadow",  text = L["Shadow only"] },
    { value = "outline", text = L["Outline only"] },
}
local THREE = {
    { value = "LEFT", text = L["Left"] }, { value = "CENTER", text = L["Centre"] }, { value = "RIGHT", text = L["Right"] },
}
local NINE = {
    { value = "TOPLEFT", text = L["Top left"] }, { value = "TOP", text = L["Top"] },
    { value = "TOPRIGHT", text = L["Top right"] }, { value = "LEFT", text = L["Left"] },
    { value = "CENTER", text = L["Centre"] }, { value = "RIGHT", text = L["Right"] },
    { value = "BOTTOMLEFT", text = L["Bottom left"] }, { value = "BOTTOM", text = L["Bottom"] },
    { value = "BOTTOMRIGHT", text = L["Bottom right"] },
}
local AURA_GROW = { { value = "LEFT", text = L["Leftwards"] }, { value = "RIGHT", text = L["Rightwards"] } }

local function Textures()
    local list = {}
    for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
    return list
end
local function Fonts() return EV.Media:FontValues(true) end

local PARTS = {}

function ns.GroupSettings(p, kind, parts)
    local M = ns.group
    local function C() return M.db[kind] end
    local function G(k) return function() return C()[k] end end
    local function S(k) return function(v) C()[k] = v end end
    local function Off() return not C().enabled end
    local function OffUnless(k) return function() return Off() or not C()[k] end end
    local X = {}
    function X.T(k, text, tip, disabled)
        return { type = "toggle", text = text, tooltip = tip, get = G(k), set = S(k), disabled = disabled or Off }
    end
    function X.D(k, text, values, tip, disabled)
        return { type = "dropdown", text = text, values = values, tooltip = tip, get = G(k), set = S(k), disabled = disabled or Off }
    end
    function X.S(k, text, lo, hi, step, tip, disabled, fmt)
        return { type = "slider", text = text, min = lo, max = hi, step = step or 1, tooltip = tip, fmt = fmt,
                 get = G(k), set = S(k), disabled = disabled or Off }
    end
    local ctx = { kind = kind, C = C, X = X, Off = Off, OffUnless = OffUnless, M = M }
    for _, name in ipairs(parts) do
        local part = PARTS[name]
        if part then part(p, ctx) end
    end
end

--------------------------------------------------------------------------------
--  Parts
--------------------------------------------------------------------------------
PARTS.group = function(p, x)
    local kind, X, C, M = x.kind, x.X, x.C, x.M
    p:Section(kind == "party" and L["Party"] or L["Raid"])
    p:Row(X.T("enabled", kind == "party" and L["Show party frames"] or L["Show raid frames"], nil,
              function() return false end))
    p:Row(X.T("hideBlizzard", L["Hide Blizzard's"], L["Takes effect after a reload."]))
    if kind == "party" then
        p:Row(X.T("showPlayer", L["Include yourself"]))
        p:Row(X.T("raidStyle", L["Use the raid frames in a party"],
                  L["Shows your party in the raid layout instead, for healers who want the same frames everywhere."]))
        p:Row(X.D("grow", L["Frames run"], GROW))
        p:Row(X.D("sort", L["Order"], PARTY_SORT))
    else
        p:Row(X.D("layout", L["Layout"], RAID_LAYOUT))
        p:Row(X.D("sort", L["Order"], RAID_SORT))
    end
    p:Row(X.S("spacing", L["Spacing"], 0, 20, 1))
    p:Section(L["On screen"])
    p:Row{ type = "toggle", text = L["Stand-ins on screen"],
           tooltip = L["Stand-in frames where the real ones go, so you can see them in place while you're on your own. Only until you turn it off or reload."],
           get = function() return M.preview[kind] end,
           set = function(v) M.preview[kind] = v end,
           disabled = x.Off }
    p:Row{ type = "button", text = L["Edit mode"], label = L["Open"], width = 90,
           onClick = function() EV.Movers:Unlock() end }
    p:Row{ type = "button", text = L["Default position"], label = L["Reset"], width = 90,
           onClick = function() EV.Movers:Reset("GF_" .. kind) end }
end

PARTS.frame = function(p, x)
    local X = x.X
    p:Section(L["Size"])
    p:Row(X.S("width", L["Width"], 40, 320))
    p:Row(X.S("height", L["Height"], 16, 90))
    p:Row(X.S("powerHeight", L["Power bar"], 0, 16, 1, L["0 hides the power bar."]))
    p:Section(L["Colours and texture"])
    p:Row(X.D("healthColour", L["Health colour"], COLOURS,
              L["Dark: a dark bar with the missing health shown in the class colour."]))
    p:Row(X.S("barShade", L["Bar brightness"], 0.5, 1, 0.05,
              L["Dims the colours so the text on them can be read."]))
    p:Row(X.D("texture", L["Texture"], Textures,
              L["Includes textures from other addons that share them through LibSharedMedia."]))
    p:Row(X.S("borderSize", L["Border thickness"], 0, 8, 1, L["In pixels. 0 is no border."]))
    p:Row(X.S("bgAlpha", L["Background opacity"], 0, 1, 0.05))
    p:Row(X.T("innerShadow", L["Inset shading"]))
    p:Row(X.T("healPrediction", L["Incoming heals"], L["Shades the health a heal already in flight will restore."]))
    p:Section(L["Text"])
    p:Row(X.D("font", L["Font"], Fonts, L["Global font follows General > Font."]))
    p:Row(X.D("textStyle", L["Text edge"], TEXT_STYLE))
    p:Row(X.S("fontSize", L["Font size"], 8, 18))
    p:Section(L["Range and aggro"])
    p:Row{ type = "slider", text = L["Out of range"], min = 10, max = 100, step = 5,
           fmt = function(v) return v .. "%" end,
           tooltip = L["How visible someone out of range stays."],
           get = function() return math.floor((x.C().rangeAlpha or 0.45) * 100 + 0.5) end,
           set = function(v) x.C().rangeAlpha = v / 100 end, disabled = x.Off }
    p:Row(X.T("aggroBorder", L["Glow when they have aggro"]))
end

--- A text's placement: which point of the health bar, and an offset.
local function TextPlace(p, x, prefix, disabled)
    local X = x.X
    p:Row(X.D(prefix .. "Point", L["Lined up"], THREE, nil, disabled))
    p:Row(X.S(prefix .. "X", L["Across"], -100, 100, 1, nil, disabled))
    p:Row(X.S(prefix .. "Y", L["Up and down"], -50, 50, 1, nil, disabled))
end

PARTS.name = function(p, x)
    local X = x.X
    local off = x.OffUnless("showName")
    p:Section(L["Name"])
    p:Row(X.T("showName", L["Show the name"]))
    p:Row(X.S("nameWidth", L["Name width (%)"], 0, 100, 5,
              L["How much of the bar a long name may use. 0 lets it run up to the health text when the two share a line, or across the whole bar otherwise."], off))
    TextPlace(p, x, "name", off)
end

PARTS.healthText = function(p, x)
    local X = x.X
    local off = function() return x.Off() or x.C().healthText == "none" end
    p:Section(L["Health text"])
    p:Row(X.D("healthText", L["Shows"], HEALTH_TEXT))
    TextPlace(p, x, "health", off)
end

--- An icon's placement: centred on a point of the frame, with an offset.
local function IconPlace(p, x, prefix, off)
    local X = x.X
    p:Row(X.D(prefix .. "Point", L["Corner"], NINE, nil, off))
    p:Row(X.S(prefix .. "Size", L["Size"], 8, 40, 1, nil, off))
    p:Row(X.S(prefix .. "X", L["Across"], -60, 60, 1, nil, off))
    p:Row(X.S(prefix .. "Y", L["Up and down"], -60, 60, 1, nil, off))
end

PARTS.role = function(p, x)
    p:Section(L["Role"])
    p:Row(x.X.T("roleIcon", L["Show"], L["Tank, healer or damage, as the group finder set it."]))
    IconPlace(p, x, "roleIcon", x.OffUnless("roleIcon"))
end

PARTS.leader = function(p, x)
    p:Section(L["Leader and assist"])
    p:Row(x.X.T("leaderIcon", L["Show"], L["The crown for the group leader, the flag for an assistant."]))
    IconPlace(p, x, "leaderIcon", x.OffUnless("leaderIcon"))
end

PARTS.ready = function(p, x)
    p:Section(L["Ready check"])
    p:Row(x.X.T("readyCheck", L["Show answers"], L["Each member's answer, while a check runs and for a few seconds after."]))
    IconPlace(p, x, "readyIcon", x.OffUnless("readyCheck"))
    p:Note(L["Placed on the health bar."], 0.6)
end

PARTS.raidIcon = function(p, x)
    p:Section(L["Raid mark"])
    IconPlace(p, x, "raidIcon", x.Off)
end

--- An aura row: which point of the health bar it hangs from, the offset,
--- and which way it fills.
local function RowPlace(p, x, prefix, off)
    local X = x.X
    p:Row(X.D(prefix .. "Grow", L["Fills"], AURA_GROW, nil, off))
    p:Row(X.D(prefix .. "Point", L["Corner"], NINE, nil, off))
    p:Row(X.S(prefix .. "X", L["Across"], -100, 100, 1, nil, off))
    p:Row(X.S(prefix .. "Y", L["Up and down"], -60, 60, 1, nil, off))
end

PARTS.debuffs = function(p, x)
    local X = x.X
    local off = x.OffUnless("debuffs")
    p:Section(L["Debuffs"])
    p:Note(L["Drawn by the game itself, so they keep working in combat in dungeons and raids, where addons can't read other players' auras."], 0.7)
    p:Row(X.T("debuffs", L["Show"]))
    p:Row(X.T("dispellableOnly", L["Only ones you can remove"], nil, off))
    p:Row(X.S("debuffSize", L["Size"], 8, 32, 1, nil, off))
    p:Row(X.S("debuffMax", L["How many"], 1, 6, 1, nil, off))
    RowPlace(p, x, "debuff", off)
end

PARTS.buffs = function(p, x)
    local X = x.X
    local off = x.OffUnless("myBuffs")
    p:Section(L["Your buffs"])
    p:Row(X.T("myBuffs", L["Show your buffs and heals over time"]))
    p:Row(X.S("buffSize", L["Size"], 8, 28, 1, nil, off))
    p:Row(X.S("buffMax", L["How many"], 1, 6, 1, nil, off))
    RowPlace(p, x, "buff", off)
end
