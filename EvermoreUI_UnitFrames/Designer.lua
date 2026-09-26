if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Designer.lua
--  The unit frames' surface for the designer (EvermoreUI_Options/Designer.lua,
--  which documents the contract). Every element here is a view over settings
--  the options page already has: dragging writes the same values the sliders
--  do, so the two can never disagree.
--
--  Units: text offsets and icon offsets are in frame units, as Frame.lua uses
--  them; cast bar, aura and pip nudges are pixels, as their files use them.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule and EvermoreUI.Designers) then return end
local EV = EvermoreUI
local L = EV.L
local M = ns.module
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local _, CLASS = UnitClass("player")

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
local PARENTS = {
    { value = "health", text = L["Health bar"] }, { value = "power", text = L["Power bar"] },
    { value = "frame", text = L["Whole frame"] },
}
local SIDES4 = {
    { value = "TOP", text = L["Above"] }, { value = "BOTTOM", text = L["Below"] },
    { value = "LEFT", text = L["Left"] }, { value = "RIGHT", text = L["Right"] },
}
local SIDES2 = { { value = "TOP", text = L["Above"] }, { value = "BOTTOM", text = L["Below"] } }
local STARTS = { { value = "START", text = L["Left end"] }, { value = "END", text = L["Right end"] } }
local PORTRAITS = {
    { value = "none", text = L["None"] }, { value = "3d", text = L["3D model"] },
    { value = "2d", text = L["2D picture"] }, { value = "class", text = L["Class icon"] },
}
local HEALTH_TEXT = {
    { value = "curpercent", text = L["12.3k  87%"] }, { value = "percent", text = L["87%"] },
    { value = "current", text = L["12.3k"] }, { value = "curmax", text = L["12.3k / 14.1k"] },
    { value = "deficit", text = L["Missing (-1.8k)"] }, { value = "none", text = L["None"] },
}
local POWER_TEXT = {
    { value = "current", text = L["4,210"] }, { value = "percent", text = L["87%"] },
    { value = "curmax", text = L["4.2k / 5k"] }, { value = "none", text = L["None"] },
}

local HEALTH_COLOURS = {
    { value = "class", text = L["Class / reaction"] }, { value = "green", text = L["Green"] },
    { value = "dark", text = L["Dark"] }, { value = "custom", text = L["Your own colour"] },
}
local POWER_COLOURS = {
    { value = "type", text = L["By resource"] }, { value = "class", text = L["Class colour"] },
    { value = "custom", text = L["Your own colour"] },
}
local TEXT_STYLE = {
    { value = "both", text = L["Outline and shadow"] }, { value = "shadow", text = L["Shadow only"] },
    { value = "outline", text = L["Outline only"] },
}
local NAME_COLOURS = { { value = "white", text = L["White"] }, { value = "class", text = L["Class / reaction"] } }
local function TEXTURES()
    local list = {}
    for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
    return list
end
local function FONTS() return EV.Media:FontValues(true) end

local function Round(v) return floor(v + 0.5) end
--- Keep a dragged value inside what the inspector's slider can show, so the
--- two never disagree and a wheel tick can't snap it somewhere else.
local function Clamp(v, lo, hi) return max(lo, min(hi, v)) end

--- Controls over one unit's settings, the same shapes the options page uses.
--- Paths are "width" or "castbar.height".
local function Controls(tab)
    local function C() return M.db[tab] end
    local function Split(path)
        local a, b = path:match("^([^.]+)%.(.+)$")
        return a or path, b
    end
    local function Get(path)
        return function()
            local a, b = Split(path)
            if b then return C()[a][b] end
            return C()[a]
        end
    end
    local function Set(path)
        return function(v)
            local a, b = Split(path)
            if b then C()[a][b] = v else C()[a] = v end
        end
    end
    local X = {}
    function X.T(path, text, tip)
        return { type = "toggle", text = text, tooltip = tip, get = Get(path), set = Set(path) }
    end
    function X.S(path, text, lo, hi, step, tip)
        return { type = "slider", text = text, min = lo, max = hi, step = step or 1, tooltip = tip,
                 get = Get(path), set = Set(path) }
    end
    function X.D(path, text, values, width, tip)
        return { type = "dropdown", text = text, values = values, width = width or 130, tooltip = tip,
                 get = Get(path), set = Set(path) }
    end
    --- A colour setting ({ r, g, b }), with Reset back to the unit's default.
    function X.C(path, text, disabled)
        local function Default()
            local a, b = Split(path)
            local d = M.DEFAULTS[tab]
            local v = b and d[a] and d[a][b] or d[a]
            return type(v) == "table" and v or { 1, 1, 1 }
        end
        return {
            type = "colour", text = text, disabled = disabled,
            get = function() local c = Get(path)() or Default(); return c[1], c[2], c[3] end,
            set = function(r, g, b) Set(path)({ r, g, b }) end,
            reset = function() local d = Default(); Set(path)({ d[1], d[2], d[3] }) end,
            isCustom = function()
                local c, d = Get(path)(), Default()
                if type(c) ~= "table" then return false end
                for i = 1, 3 do if math.abs((c[i] or 0) - (d[i] or 0)) > 0.002 then return true end end
                return false
            end,
        }
    end
    function X.Off(path, value) return function() return Get(path)() ~= value end end
    return X
end

--- Reset some keys of a unit (or of one of its tables) to the defaults.
local function ResetKeys(tab, keys, sub)
    local d = M.DEFAULTS[tab]
    local c = M.db[tab]
    if sub then d, c = d[sub], c[sub] end
    for _, k in ipairs(keys) do
        local v = d[k]
        c[k] = type(v) == "table" and EV.CopyTable(v) or v
    end
end

--------------------------------------------------------------------------------
--  Element builders
--------------------------------------------------------------------------------
local function TextElement(tab, key, label, prefix, field, parentDefault, shown, formatPath, formatValues)
    local function C() return M.db[tab] end
    local function Host(pf)
        local which = C()[prefix .. "Parent"] or parentDefault
        if which == "frame" then return pf end
        if which == "power" and (C().powerHeight or 0) > 0 then return pf.power end
        return pf.health
    end
    local d = M.DEFAULTS[tab]
    return {
        key = key, label = label,
        region = function(pf) return pf[field] end,
        shown = shown,
        move = "free", points = "three", anchor = "same", text = true,
        parent = Host,
        snapX = { d[prefix .. "X"] or 0, -(d[prefix .. "X"] or 0) },
        get = function() return C()[prefix .. "Point"], C()[prefix .. "X"] or 0, C()[prefix .. "Y"] or 0 end,
        set = function(point, x, y)
            local c = C()
            c[prefix .. "Point"], c[prefix .. "X"], c[prefix .. "Y"] = point, Clamp(x, -150, 150), Clamp(y, -60, 60)
        end,
        Nudge = function(dx, dy)
            local c = C()
            c[prefix .. "X"] = Clamp((c[prefix .. "X"] or 0) + dx, -150, 150)
            c[prefix .. "Y"] = Clamp((c[prefix .. "Y"] or 0) + dy, -60, 60)
        end,
        Reset = function() ResetKeys(tab, { prefix .. "Point", prefix .. "X", prefix .. "Y", prefix .. "Parent" }) end,
        Options = function(p)
            local X = Controls(tab)
            if formatPath then p:Row(X.D(formatPath, L["Shows"], formatValues, 170)) end
            p:Row(X.D(prefix .. "Parent", L["Sits on"], PARENTS, 150))
            p:Row(X.D(prefix .. "Point", L["Lined up"], THREE, 130))
            p:Row(X.S(prefix .. "X", L["Across"], -150, 150, 1))
            p:Row(X.S(prefix .. "Y", L["Up and down"], -60, 60, 1))
        end,
    }
end

local function IconElement(tab, key, label, prefix, field, fallbackPoint, shown, extraOptions)
    local function C() return M.db[tab] end
    return {
        key = key, label = label,
        region = function(pf) return pf[field] end,
        shown = shown,
        move = "free", points = "nine", anchor = "center",
        parent = function(pf) return pf end,
        get = function()
            local c = C()
            return c[prefix .. "Point"] or fallbackPoint, c[prefix .. "X"] or 0, c[prefix .. "Y"] or 0
        end,
        set = function(point, x, y)
            local c = C()
            c[prefix .. "Point"], c[prefix .. "X"], c[prefix .. "Y"] = point, Clamp(x, -150, 150), Clamp(y, -150, 150)
        end,
        Nudge = function(dx, dy)
            local c = C()
            c[prefix .. "X"] = Clamp((c[prefix .. "X"] or 0) + dx, -150, 150)
            c[prefix .. "Y"] = Clamp((c[prefix .. "Y"] or 0) + dy, -150, 150)
        end,
        getSize = function() local s = C()[prefix .. "Size"] or 16; return s, s end,
        setSize = function(w, h) C()[prefix .. "Size"] = max(8, min(64, Round(max(w, h)))) end,
        Reset = function() ResetKeys(tab, { prefix .. "Point", prefix .. "X", prefix .. "Y", prefix .. "Size" }) end,
        Options = function(p)
            local X = Controls(tab)
            if extraOptions then extraOptions(p, X) end
            p:Row(X.D(prefix .. "Point", L["Corner"], NINE, 150))
            p:Row(X.S(prefix .. "Size", L["Size"], 8, 64, 1))
            p:Row(X.S(prefix .. "X", L["Across"], -150, 150, 1))
            p:Row(X.S(prefix .. "Y", L["Up and down"], -150, 150, 1))
        end,
    }
end

local function AuraElement(tab, kind, label)
    local function A() return M.db[tab][kind] end
    local C = EV.AuraContainer
    return {
        key = kind, label = label,
        region = function(pf) return pf.auraHolders and pf.auraHolders[kind] end,
        shown = function() return A().enabled and M.db[tab].enabled end,
        move = "slot", slots = "sides", aligned = true,
        getSlot = function() return A().side or "TOP", A().align or "START" end,
        setSlot = function(side, align) A().side, A().align = side, align end,
        Nudge = function(dx, dy)
            A().x = Clamp((A().x or 0) + dx, -200, 200)
            A().y = Clamp((A().y or 0) + dy, -200, 200)
        end,
        -- The grip sets the icon size: the box it would draw at that size.
        getSize = function()
            local a = A()
            local cols = max(1, min(a.perRow, a.max))
            local rows = max(1, ceil(a.max / a.perRow))
            return cols * a.size + (cols - 1) * a.spacing, rows * a.size + (rows - 1) * a.spacing
        end,
        setSize = function(w, h)
            local a = A()
            local rows = max(1, ceil(a.max / a.perRow))
            a.size = max(10, min(60, Round((h - (rows - 1) * a.spacing) / rows)))
        end,
        Reset = function()
            local keep = A().enabled
            ResetKeys(tab, { "side", "align", "x", "y", "size", "spacing", "perRow", "max" }, kind)
            A().enabled = keep
        end,
        Options = function(p)
            ns.Settings(p, tab, { sections = { [label] = true } })
        end,
    }
end

--------------------------------------------------------------------------------
--  The surface
--------------------------------------------------------------------------------
local function Elements(tab)
    local function C() return M.db[tab] end
    local list = {}
    local function Add(e) list[#list + 1] = e end

    Add{
        key = "frame", label = L["Frame"],
        region = function(pf) return pf end,
        getSize = function() return C().width, C().height end,
        setSize = function(w, h)
            C().width = max(60, min(500, w))
            C().height = max(12, min(100, h))
        end,
        -- The whole frame back to its defaults. Where it sits on screen is
        -- edit mode's and stays.
        Reset = function()
            local c = M.db[tab]
            wipe(c)
            EV.DB.Merge(c, M.DEFAULTS[tab])
        end,
        Options = function(p)
            ns.Settings(p, tab, { sections = {
                [L["General"]] = true, [L["Position"]] = true, [L["Colours and texture"]] = true,
                [L["Text"]] = { font = true, textStyle = true, fontSize = true, powerFontSize = true },
                [L["Classic"]] = true, [L["Fade out of combat"]] = true, [L["Aggro glow"]] = true,
                [L["Cast bar, buffs and debuffs"]] = true,
            } })
            p:Note(L["Reset (top right) puts this whole frame back to its defaults; where it sits on screen stays."])
        end,
    }
    Add{
        key = "portrait", label = L["Portrait"],
        region = function(pf) return pf.portrait end,
        shown = function() return C().portrait ~= "none" end,
        move = "slot", slots = "horizontal",
        getSlot = function() return C().portraitSide == "right" and "RIGHT" or "LEFT" end,
        setSlot = function(side) C().portraitSide = side == "RIGHT" and "right" or "left" end,
        Reset = function() ResetKeys(tab, { "portrait", "portraitSide" }) end,
        Options = function(p) ns.Settings(p, tab, { sections = { [L["Portrait"]] = true } }) end,
    }
    local name = TextElement(tab, "name", L["Name"], "name", "nameText", "health",
        function() return C().showName end)
    local placeName = name.Options
    name.Options = function(p)
        local X = Controls(tab)
        p:Row(X.T("showName", L["Show the name"]))
        p:Row(X.T("showLevel", L["Level"]))
        p:Row(X.D("nameColour", L["Name colour"], NAME_COLOURS, 170))
        p:Row(X.S("nameWidth", L["Name width (%)"], 0, 100, 5,
                  L["How much of the bar a long name may use. 0 lets it run up to the health text when the two share a line."]))
        placeName(p)
    end
    Add(name)
    Add(TextElement(tab, "healthText", L["Health text"], "health", "healthText", "health",
        function() return C().healthText ~= "none" end, "healthText", HEALTH_TEXT))
    Add(TextElement(tab, "powerText", L["Power text"], "power", "powerText", "power",
        function() return C().powerText ~= "none" end, "powerText", POWER_TEXT))
    Add(IconElement(tab, "raidIcon", L["Raid mark"], "raidIcon", "raidIcon", "TOP", nil))
    Add(IconElement(tab, "leaderIcon", L["Leader and assist"], "leaderIcon", "leaderIcon", "TOPLEFT",
        function() return C().leaderIcon end,
        function(p, X) p:Row(X.T("leaderIcon", L["Show"])) end))
    Add(IconElement(tab, "pvpIcon", L["PvP flag"], "pvpIcon", "pvpIcon", "BOTTOMLEFT",
        function() return C().pvpIcon end,
        function(p, X) p:Row(X.T("pvpIcon", L["Show"])) end))
    if tab == "player" then
        Add(IconElement(tab, "stateIcon", L["Combat and resting"], "stateIcon", "stateIcon", "TOPLEFT",
            function() return C().combatIcon ~= false or C().restingIcon ~= false end,
            function(p, X)
                p:Row(X.T("combatIcon", L["In combat"]))
                p:Row(X.T("restingIcon", L["Resting"]))
            end))
    end

    if ns.CastBar.LIVE[tab] then
        local function CC() return C().castbar end
        Add{
            key = "castbar", label = L["Cast bar"],
            region = function(pf) return pf.castbar end,
            shown = function() return CC().enabled and C().enabled end,
            move = "nudge",
            get = function() return CC().x or 0, -(CC().gap or 4) end,
            set = function(x, y) CC().x = Clamp(x, -300, 300); CC().gap = Clamp(-y, 0, 60) end,
            Nudge = function(dx, dy)
                CC().x = Clamp((CC().x or 0) + dx, -300, 300)
                CC().gap = Clamp((CC().gap or 4) - dy, 0, 60)
            end,
            getSize = function()
                local c = CC()
                return (c.width and c.width > 0) and c.width or C().width, c.height
            end,
            setSize = function(w, h)
                local c = CC()
                -- Within a pixel of the frame's width means "match the frame".
                c.width = math.abs(w - C().width) <= 1 and 0 or max(40, min(600, w))
                c.height = max(4, min(60, h))
            end,
            Reset = function()
                local keep = CC().enabled
                ResetKeys(tab, { "width", "height", "gap", "x", "icon", "iconSide" }, "castbar")
                CC().enabled = keep
            end,
            Options = function(p) ns.Settings(p, tab, { sections = { [L["Cast bar"]] = true } }) end,
        }
        Add(AuraElement(tab, "debuffs", L["Debuffs"]))
        Add(AuraElement(tab, "buffs", L["Buffs"]))
    end

    if tab == "player" and EV.HasComboClass and EV.HasComboClass() then
        local function CP() return C().classPower end
        Add{
            key = "combo", label = L["Combo points"],
            region = function(pf) return pf.pvCombo end,
            shown = function() return CP().enabled and C().enabled end,
            move = "slot", slots = "vertical",
            getSlot = function() return CP().side == "BOTTOM" and "BOTTOM" or "TOP" end,
            setSlot = function(side) CP().side = side end,
            Nudge = function(dx, dy) CP().x = (CP().x or 0) + dx; CP().y = (CP().y or 0) + dy end,
            getSize = function()
                local c = CP()
                return (c.width and c.width > 0) and c.width or C().width, c.height
            end,
            setSize = function(w, h)
                local c = CP()
                c.width = math.abs(w - C().width) <= 1 and 0 or max(30, min(500, w))
                c.height = max(2, min(30, h))
            end,
            Reset = function()
                local keep = CP().enabled
                ResetKeys(tab, { "side", "height", "spacing", "width", "x", "y" }, "classPower")
                CP().enabled = keep
            end,
            Options = function(p) ns.Settings(p, tab, { sections = { [L["Combo points"]] = true } }) end,
        }
    end

    if tab == "player" and CLASS == "SHAMAN" then
        local function TT() return C().totems end
        Add{
            key = "totems", label = L["Totems"],
            region = function(pf) return pf.pvTotems end,
            shown = function() return TT().enabled and C().enabled end,
            move = "slot", slots = "vertical", aligned = true,
            getSlot = function() return TT().side == "TOP" and "TOP" or "BOTTOM", TT().align or "START" end,
            setSlot = function(side, align) TT().side, TT().align = side, align end,
            Nudge = function(dx, dy) TT().x = (TT().x or 0) + dx; TT().y = (TT().y or 0) + dy end,
            getSize = function()
                local t = TT()
                return 4 * t.size + 3 * (t.spacing or 3), t.size
            end,
            setSize = function(w, h) TT().size = max(12, min(60, Round(h))) end,
            Reset = function()
                local keep = TT().enabled
                ResetKeys(tab, { "size", "spacing", "side", "align", "x", "y" }, "totems")
                TT().enabled = keep
            end,
            Options = function(p) ns.Settings(p, tab, { sections = { [L["Totems"]] = true } }) end,
        }
    end
    return list
end

EV.Designers:Register{
    key = "unitframes", title = L["Unit Frames"], module = "UnitFrames", kind = "canvas",
    page = "unitframes",
    note = L["A copy bound to you, with samples, so every part is on screen. Screen position is edit mode's."],
    Tabs = function()
        local list = {}
        for _, u in ipairs(M.UNITS) do list[#list + 1] = { value = u.key, text = L[u.title] } end
        return list
    end,
    PageTab = function(tab)
        for _, u in ipairs(M.UNITS) do if u.key == tab then return L[u.title] end end
    end,
    Build = function(host, tab) return M:BuildPreview(tab, host) end,
    Layout = function(pf) M:LayoutPreview(pf) end,
    Elements = function(tab) return Elements(tab) end,
    Snapshot = function(tab) return EV.CopyTable(M.db[tab]) end,
    Restore = function(tab, snap)
        local c = M.db[tab]
        wipe(c)
        for k, v in pairs(EV.CopyTable(snap)) do c[k] = v end
        if M:IsEnabled() then M:ApplyFrame(tab) end
    end,
    Apply = function(tab)
        if M:IsEnabled() then M:ApplyFrame(tab) end
    end,
}
