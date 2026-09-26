if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Party & Raid frames.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("GroupFrames", true)
if not M then return end

local TAB_PARTY, TAB_RAID = L["Party"], L["Raid"]

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
local ALIGN = { { value = "LEFT", text = L["Left"] }, { value = "CENTER", text = L["Centre"] } }
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

local function Build(p, kind)
    local c = M.db[kind]
    local function Apply() if M:IsEnabled() then M:Apply() end end
    local function G(k) return function() return c[k] end end
    local function S(k) return function(v) c[k] = v; Apply() end end
    local function Off() return not c.enabled end
    local function T(k, text, tip, dis)
        return { type = "toggle", text = text, tooltip = tip, get = G(k), set = S(k), disabled = dis or Off }
    end
    local function D(k, text, values, width)
        return { type = "dropdown", text = text, values = values, width = width or 170, get = G(k), set = S(k), disabled = Off }
    end
    local function Sl(k, text, lo, hi, step, fmt)
        return { type = "slider", text = text, min = lo, max = hi, step = step or 1, fmt = fmt,
                 get = G(k), set = S(k), disabled = Off }
    end

    p:Section(kind == "party" and L["Party frames"] or L["Raid frames"])
    p:Dual(T("enabled", kind == "party" and L["Show party frames"] or L["Show raid frames"], nil, function() return false end),
           { type = "toggle", text = L["Preview"],
             tooltip = L["Stand-in frames so you can place and size them on your own. Only while this is on."],
             get = function() return M.preview[kind] end,
             set = function(v) M.preview[kind] = v; M:Apply() end,
             disabled = Off })
    p:Dual(T("hideBlizzard", L["Hide Blizzard's"], L["Takes effect after a reload."]),
           { type = "button", text = L["Position"], label = L["Reset"], width = 100,
             onClick = function() EV.Movers:Reset("GF_" .. kind) end })
    if kind == "party" then
        p:Dual(T("showPlayer", L["Include yourself"]),
               T("raidStyle", L["Use the raid frames in a party"],
                 L["Shows your party in the raid layout instead, for healers who want the same frames everywhere."]))
        p:Dual(D("grow", L["Frames run"], GROW, 150), D("sort", L["Order"], PARTY_SORT, 190))
    else
        p:Dual(D("layout", L["Layout"], RAID_LAYOUT, 190), D("sort", L["Order"], RAID_SORT, 190))
    end

    p:Section(L["Size"])
    p:Dual(Sl("width", L["Width"], 40, 320), Sl("height", L["Height"], 16, 90))
    p:Dual(Sl("powerHeight", L["Power bar"], 0, 16), Sl("spacing", L["Spacing"], 0, 20))

    p:Section(L["Health and text"])
    p:Dual(D("healthColour", L["Health colour"], COLOURS, 150), D("healthText", L["Health text"], HEALTH_TEXT, 170))
    p:Dual(D("nameAlign", L["Name"], ALIGN, 130), Sl("fontSize", L["Text size"], 8, 18))
    p:Dual({ type = "slider", text = L["Out of range"], min = 10, max = 100, step = 5,
             fmt = function(v) return v .. "%" end,
             tooltip = L["How visible someone out of range stays."],
             get = function() return math.floor((c.rangeAlpha or 0.45) * 100 + 0.5) end,
             set = function(v) c.rangeAlpha = v / 100; Apply() end, disabled = Off },
           T("aggroBorder", L["Glow when they have aggro"]))

    p:Section(L["Icons"])
    p:Dual(T("roleIcon", L["Role"]), T("leaderIcon", L["Leader and assist"]))
    p:Dual(T("readyCheck", L["Ready check answers"]), nil)

    p:Section(L["Auras"])
    p:Note(L["Drawn by the game itself, so they keep working in combat in dungeons and raids, where addons can't read other players' auras."], 0.7)
    local noDebuffs = function() return Off() or not c.debuffs end
    local noBuffs = function() return Off() or not c.myBuffs end
    p:Dual(T("debuffs", L["Debuffs"]),
           T("dispellableOnly", L["Only ones you can remove"], nil, noDebuffs))
    p:Dual({ type = "slider", text = L["Debuff size"], min = 8, max = 32, step = 1, get = G("debuffSize"), set = S("debuffSize"), disabled = noDebuffs },
           { type = "slider", text = L["How many"], min = 1, max = 6, step = 1, get = G("debuffMax"), set = S("debuffMax"), disabled = noDebuffs })
    p:Dual(T("myBuffs", L["Your buffs and heals over time"]), nil)
    p:Dual({ type = "slider", text = L["Buff size"], min = 8, max = 28, step = 1, get = G("buffSize"), set = S("buffSize"), disabled = noBuffs },
           { type = "slider", text = L["How many"], min = 1, max = 6, step = 1, get = G("buffMax"), set = S("buffMax"), disabled = noBuffs })
end

EV.Options:RegisterPage{
    key = "groupframes", title = L["Party & Raid"], group = "Combat", module = "GroupFrames",
    description = L["Party and raid frames in the style of your unit frames, laid out by the game's own group headers so they keep up in combat. Click casting works on them too."],
    tabs = { TAB_PARTY, TAB_RAID },
    build = function(p, tab) Build(p, tab == TAB_RAID and "raid" or "party") end,
    onReset = function(tab)
        local kind = tab == TAB_RAID and "raid" or "party"
        wipe(M.db[kind])
        EV.DB.Merge(M.db[kind], M.defaults[kind])
        if M:IsEnabled() then M:Apply() end
    end,
}
