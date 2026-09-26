if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  GroupDesigner.lua
--  The party and raid frames' surface for the designer
--  (EvermoreUI_Options/Designer.lua documents the contract). The copy is a
--  party of five, or three raid groups, laid out as the real ones would be;
--  the first frame's parts are the ones you pick and drag, and every frame
--  follows. Everything is a view over the settings in GroupSettings.lua.
--
--  Offsets are in frame units, as GroupFrames.lua and Frame.lua use them.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule and EvermoreUI.Designers) then return end
local EV = EvermoreUI
local L = EV.L
local M = ns.group
if not M then return end
local floor, max, min = math.floor, math.max, math.min

local function Round(v) return floor(v + 0.5) end
local function Clamp(v, lo, hi) return max(lo, min(hi, v)) end

local function C(kind) return M.db[kind] end

--- Some settings of one kind back to their defaults.
local function ResetKeys(kind, keys)
    local d, c = M.defaults[kind], M.db[kind]
    for _, k in ipairs(keys) do
        local v = d[k]
        c[k] = type(v) == "table" and EV.CopyTable(v) or v
    end
end

local function Options(kind, parts)
    return function(p) ns.GroupSettings(p, kind, parts) end
end

--------------------------------------------------------------------------------
--  Element builders
--------------------------------------------------------------------------------
--- A text on the first frame's health bar: a point (left, centre, right)
--- and an offset, picked by where you drop it.
local function TextElement(kind, key, label, prefix, field, shown, part)
    local d = M.defaults[kind]
    return {
        key = key, label = label,
        region = function(pv) return pv.first and pv.first[field] end,
        shown = shown,
        move = "free", points = "three", anchor = "same", text = true,
        parent = function(pv) return pv.first and pv.first.health end,
        snapX = { d[prefix .. "X"] or 0, -(d[prefix .. "X"] or 0) },
        get = function() local c = C(kind); return c[prefix .. "Point"], c[prefix .. "X"] or 0, c[prefix .. "Y"] or 0 end,
        set = function(point, x, y)
            local c = C(kind)
            c[prefix .. "Point"], c[prefix .. "X"], c[prefix .. "Y"] = point, Clamp(x, -100, 100), Clamp(y, -50, 50)
        end,
        Nudge = function(dx, dy)
            local c = C(kind)
            c[prefix .. "X"] = Clamp((c[prefix .. "X"] or 0) + dx, -100, 100)
            c[prefix .. "Y"] = Clamp((c[prefix .. "Y"] or 0) + dy, -50, 50)
        end,
        Reset = function() ResetKeys(kind, { prefix .. "Point", prefix .. "X", prefix .. "Y" }) end,
        Options = Options(kind, { part }),
    }
end

--- An icon centred on one of nine points of the first frame (or its health
--- bar), with an offset and a size.
local function IconElement(kind, key, label, prefix, field, shown, part, onHealth)
    return {
        key = key, label = label,
        region = function(pv) return pv.first and pv.first[field] end,
        shown = shown,
        move = "free", points = "nine", anchor = "center",
        parent = function(pv) return pv.first and (onHealth and pv.first.health or pv.first) end,
        get = function() local c = C(kind); return c[prefix .. "Point"], c[prefix .. "X"] or 0, c[prefix .. "Y"] or 0 end,
        set = function(point, x, y)
            local c = C(kind)
            c[prefix .. "Point"], c[prefix .. "X"], c[prefix .. "Y"] = point, Clamp(x, -60, 60), Clamp(y, -60, 60)
        end,
        Nudge = function(dx, dy)
            local c = C(kind)
            c[prefix .. "X"] = Clamp((c[prefix .. "X"] or 0) + dx, -60, 60)
            c[prefix .. "Y"] = Clamp((c[prefix .. "Y"] or 0) + dy, -60, 60)
        end,
        getSize = function() local s = C(kind)[prefix .. "Size"] or 16; return s, s end,
        setSize = function(w, h) C(kind)[prefix .. "Size"] = Clamp(Round(max(w, h)), 8, 40) end,
        Reset = function() ResetKeys(kind, { prefix .. "Point", prefix .. "X", prefix .. "Y", prefix .. "Size" }) end,
        Options = Options(kind, { part }),
    }
end

--- An aura row, pinned by its own point to the same point of the health
--- bar. The grip sets the icon size.
local function AuraElement(kind, key, label, prefix, holder, on, part)
    return {
        key = key, label = label,
        region = function(pv) return pv.first and pv.first[holder] end,
        shown = function() return C(kind)[on] end,
        move = "free", points = "nine", anchor = "same",
        parent = function(pv) return pv.first and pv.first.health end,
        get = function() local c = C(kind); return c[prefix .. "Point"], c[prefix .. "X"] or 0, c[prefix .. "Y"] or 0 end,
        set = function(point, x, y)
            local c = C(kind)
            c[prefix .. "Point"], c[prefix .. "X"], c[prefix .. "Y"] = point, Clamp(x, -100, 100), Clamp(y, -60, 60)
        end,
        Nudge = function(dx, dy)
            local c = C(kind)
            c[prefix .. "X"] = Clamp((c[prefix .. "X"] or 0) + dx, -100, 100)
            c[prefix .. "Y"] = Clamp((c[prefix .. "Y"] or 0) + dy, -60, 60)
        end,
        getSize = function()
            local c = C(kind)
            return M.RowWidth(c[prefix .. "Size"], c[prefix .. "Max"]), c[prefix .. "Size"]
        end,
        setSize = function(w, h)
            local hi = prefix == "debuff" and 32 or 28
            C(kind)[prefix .. "Size"] = Clamp(Round(h), 8, hi)
        end,
        Reset = function()
            ResetKeys(kind, { prefix .. "Point", prefix .. "X", prefix .. "Y", prefix .. "Grow",
                              prefix .. "Size", prefix .. "Max" })
        end,
        Options = Options(kind, { part }),
    }
end

--------------------------------------------------------------------------------
--  The surface
--------------------------------------------------------------------------------
local LAYOUT_KEYS = { "grow", "sort", "layout", "spacing", "showPlayer", "raidStyle", "hideBlizzard" }
local FRAME_KEYS = { "width", "height", "powerHeight", "healthColour", "barShade", "texture", "borderSize",
                     "bgAlpha", "innerShadow", "healPrediction", "font", "textStyle", "fontSize",
                     "rangeAlpha", "aggroBorder" }

local function Elements(kind)
    local list = {}
    local function Add(e) list[#list + 1] = e end
    Add{
        key = "group", label = kind == "party" and L["Party layout"] or L["Raid layout"],
        region = function(pv) return pv end,
        sub = L["How the frames are laid out and sorted. Where they sit on screen is edit mode."],
        Reset = function() ResetKeys(kind, LAYOUT_KEYS) end,
        Options = Options(kind, { "group" }),
    }
    Add{
        key = "frame", label = L["Frame"],
        region = function(pv) return pv.first end,
        sub = L["Drag the corner to resize every frame."],
        getSize = function() return C(kind).width, C(kind).height end,
        setSize = function(w, h)
            C(kind).width = Clamp(Round(w), 40, 320)
            C(kind).height = Clamp(Round(h), 16, 90)
        end,
        Reset = function() ResetKeys(kind, FRAME_KEYS) end,
        Options = Options(kind, { "frame" }),
    }
    Add(TextElement(kind, "name", L["Name"], "name", "nameText",
        function() return C(kind).showName end, "name"))
    Add(TextElement(kind, "healthText", L["Health text"], "health", "healthText",
        function() return C(kind).healthText ~= "none" end, "healthText"))
    Add(IconElement(kind, "role", L["Role"], "roleIcon", "role",
        function() return C(kind).roleIcon end, "role"))
    Add(IconElement(kind, "leader", L["Leader and assist"], "leaderIcon", "leaderIcon",
        function() return C(kind).leaderIcon end, "leader"))
    Add(IconElement(kind, "ready", L["Ready check"], "readyIcon", "ready",
        function() return C(kind).readyCheck end, "ready", true))
    Add(IconElement(kind, "raidIcon", L["Raid mark"], "raidIcon", "raidIcon", nil, "raidIcon"))
    Add(AuraElement(kind, "debuffs", L["Debuffs"], "debuff", "debuffHolder", "debuffs", "debuffs"))
    Add(AuraElement(kind, "buffs", L["Your buffs"], "buff", "buffHolder", "myBuffs", "buffs"))
    return list
end

EV.Designers:Register{
    key = "groupframes", title = L["Party & Raid"], module = "GroupFrames", kind = "canvas",
    page = "groupframes",
    help = L["Pick a part of the first frame to change it; every frame follows. Click the other frames for the layout."],
    note = L["Sample group, laid out as yours will be. Screen position is edit mode's."],
    Tabs = function()
        return { { value = "party", text = L["Party"] }, { value = "raid", text = L["Raid"] } }
    end,
    Build = function(host, kind) return M:BuildDesignerPreview(kind, host) end,
    Layout = function(pv) M:LayoutDesignerPreview(pv) end,
    Elements = function(kind) return Elements(kind) end,
    Snapshot = function(kind) return EV.CopyTable(M.db[kind]) end,
    Restore = function(kind, snap)
        local c = M.db[kind]
        wipe(c)
        for k, v in pairs(EV.CopyTable(snap)) do c[k] = v end
        if M:IsEnabled() then M:Apply() end
    end,
    Apply = function()
        if M:IsEnabled() then M:Apply() end
    end,
}
