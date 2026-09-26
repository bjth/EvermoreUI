if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Chat: Window, Messages, Tabs, Sidebar.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local floor = math.floor

local M = EV:GetModule("Chat", true)
if not M then return end
local ns = EV._ModuleNS["EvermoreUI_Chat"]

local TAB_WINDOW, TAB_MESSAGES, TAB_TABS, TAB_SIDEBAR = L["Window"], L["Messages"], L["Tabs"], L["Sidebar"]

local OUTLINES = {
    { value = "NONE", text = L["None"] }, { value = "OUTLINE", text = L["Outline"] },
    { value = "THICKOUTLINE", text = L["Thick outline"] },
}
local STAMPS = {
    { value = "blizzard", text = L["Blizzard's setting"] },
    { value = "none", text = L["Off"] },
    { value = "%H:%M ", text = "15:04" },
    { value = "%H:%M:%S ", text = "15:04:27" },
    { value = "[%H:%M] ", text = "[15:04]" },
    { value = "[%H:%M:%S] ", text = "[15:04:27]" },
    { value = "%I:%M %p ", text = "03:04 PM" },
}
local SIDEBAR = {
    { value = "always", text = L["Always"] }, { value = "mouseover", text = L["On hover"] },
    { value = "never", text = L["Off"] },
}
local ACTIVE_TEXT = {
    { value = "white", text = L["White"] }, { value = "accent", text = L["Accent"] },
    { value = "class", text = L["Class colour"] },
}

local function Get(k) return function() return M.db[k] end end
local function Set(k, after)
    return function(v)
        M.db[k] = v
        if after then after(v) end
        M:Refresh()
    end
end
local function T(k, text, tip, extra)
    local c = { type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k) }
    if extra then for kk, v in pairs(extra) do c[kk] = v end end
    return c
end
local function S(k, text, lo, hi, step, fmt, tip, disabled)
    return { type = "slider", text = text, min = lo, max = hi, step = step or 1, tooltip = tip,
             fmt = fmt, disabled = disabled, get = Get(k), set = Set(k) }
end
local function Pct(k, text, lo, hi, tip, disabled)
    return { type = "slider", text = text, min = lo, max = hi, step = 5, tooltip = tip,
             fmt = function(v) return v .. "%" end, disabled = disabled,
             get = function() return floor((M.db[k] or 0) * 100 + 0.5) end,
             set = function(v) M.db[k] = v / 100; M:Refresh() end }
end
local function Px(v) return v .. "px" end
local function Sec(v) return v .. "s" end

local function Fonts() return EV.Media:FontValues(true) end

local function Window(p)
    p:Section(L["Panel"])
    p:Dual(Pct("bgAlpha", L["Background opacity"], 0, 100),
           T("border", L["Border"], L["A 1px border round the whole chat, tabs and sidebar included."]))
    p:Dual(T("dividers", L["Dividers"], L["Hairlines between the tabs, text, input box and sidebar."]),
           { type = "dropdown", text = L["Scroll bar"], width = 170, values = {
                 { value = "always", text = L["Always"] }, { value = "scrolled", text = L["While scrolled back"] },
                 { value = "never", text = L["Off"] } },
             tooltip = L["A thin bar on the right of the text. Drag it, or use the mouse wheel (Shift jumps to the top or bottom)."],
             get = Get("scrollBar"), set = Set("scrollBar") })

    p:Section(L["Text"])
    p:Dual({ type = "dropdown", text = L["Font"], width = 170, values = Fonts, get = Get("font"), set = Set("font") },
           { type = "dropdown", text = L["Outline"], width = 150, values = OUTLINES, get = Get("outline"), set = Set("outline") })
    p:Dual(T("shadow", L["Text shadow"], L["Only without an outline."]),
           T("overrideSize", L["Same size in every window"], L["Off: each window keeps the size set from its tab's menu."]))
    p:Dual(S("fontSize", L["Text size"], 8, 24, 1, nil, nil, function() return not M.db.overrideSize end), nil)

    p:Section(L["Input box"])
    p:Dual(T("inputOnTop", L["Input at the top"], L["Puts the input box at the top of the panel, under the tabs."]),
           S("editHeight", L["Input height"], 16, 40, 1, Px))
    p:Dual(S("editFontSize", L["Input text size"], 0, 24, 1, function(v) return v == 0 and L["Same as chat"] or v end),
           T("recall", L["Up/Down recalls messages"], L["Plain Up and Down step through what you've sent. Alt+Up/Down still works as Blizzard's."]))

    p:Section(L["Idle fade"])
    p:Dual(T("idleFade", L["Fade when quiet"], L["Fades the chat when nothing's happening, and brings it straight back on a message, hover or typing."]),
           S("idleDelay", L["After"], 5, 120, 5, Sec, nil, function() return not M.db.idleFade end))
    p:Dual(S("idleStrength", L["Fade strength"], 10, 90, 5, function(v) return v .. "%" end, nil,
             function() return not M.db.idleFade end), nil)

    p:Section(L["Position"])
    p:Dual({ type = "button", text = L["Move and resize"], label = L["Edit mode"], width = 120,
             tooltip = L["The whole chat moves as one block, with snapping and anchoring like everything else. Drag its corner to resize."],
             onClick = function() EV.Movers:Unlock() end },
           { type = "button", text = L["Chat position"], label = L["Reset"], width = 100,
             tooltip = L["Back to where Blizzard puts it."],
             onClick = function() EV.Movers:Reset("CHAT_main") end })
end

local function Messages(p)
    p:Section(L["Timestamps"])
    p:Dual({ type = "dropdown", text = L["Timestamps"], width = 170, values = STAMPS,
             tooltip = L["Blizzard adds these to player chat itself, so they work in restricted content too."],
             get = Get("timestamps"), set = Set("timestamps") },
           T("stampAll", L["Stamp every line"], L["Also stamps system, loot and addon lines, which Blizzard leaves bare. Pauses in restricted content."],
             { disabled = function() return M.db.timestamps == "none" end }))

    p:Section(L["Names and channels"])
    p:Dual(T("shortChannels", L["Short channel names"], L["[Party] becomes [P], [Guild] [G], [2. Trade] [2]. Pauses in restricted content."]),
           T("classNames", L["Class colours in messages"], L["Colours your group's names when they're typed in Say, Yell, Party, Raid and Guild."]))

    p:Section(L["Links"])
    p:Dual(T("urls", L["Clickable web links"], L["Web addresses become links; click one to copy it."]),
           T("linkTooltips", L["Tooltips on hover"], L["Item, spell and achievement links show their tooltip when you hover them."]))

    p:Section(L["Whispers"])
    p:Dual({ type = "dropdown", text = L["Whisper sound"], width = 170, values = ns and ns.WHISPER_SOUNDS or {},
             get = Get("whisperSound"),
             set = Set("whisperSound", function() if ns and ns.PlayWhisperSound then ns.PlayWhisperSound() end end) },
           nil)

    p:Section(L["History"])
    p:Dual(S("history", L["Lines kept through a reload"], 0, 500, 25, nil,
             L["Each chat window keeps its last this-many lines, so a /reload or relog doesn't wipe them. 0 turns it off. Kept for this character only; restricted-content lines are never kept."]),
           { type = "button", text = L["Forget kept history"], label = L["Clear"], width = 100,
             tooltip = L["Deletes the saved lines for this character. What's on screen now stays until you reload."],
             onClick = function()
                 if ns and ns.Engine and ns.Engine.ClearHistory then ns.Engine.ClearHistory() end
                 EV:Print(L["Chat history cleared."])
             end })
end

local function Tabs(p)
    p:Section(L["Layout"])
    p:Dual(T("tabsInPanel", L["Tabs inside the panel"], L["One continuous panel with the tabs across the top. Off: tabs float above as their own boxes."]),
           S("tabHeight", L["Tab height"], 16, 36, 1, Px))
    p:Dual(S("tabPadding", L["Text padding"], 4, 24, 1, Px),
           S("tabSpacing", L["Gap between tabs"], 0, 8, 1, Px, nil, function() return M.db.tabsInPanel end))

    p:Section(L["Look"])
    p:Dual(S("tabFontSize", L["Tab text size"], 8, 18),
           { type = "dropdown", text = L["Open tab text"], width = 150, values = ACTIVE_TEXT,
             get = Get("tabActiveText"), set = Set("tabActiveText") })
    p:Dual(T("tabUnderline", L["Underline the open tab"]),
           Pct("tabBgAlpha", L["Tab background"], 0, 100, L["Floating tabs only."], function() return M.db.tabsInPanel end))
end

local function Sidebar(p)
    p:Section(L["Sidebar"])
    p:Dual({ type = "dropdown", text = L["Show"], width = 150, values = SIDEBAR, get = Get("sidebar"), set = Set("sidebar") },
           T("sidebarRight", L["On the right"]))
    p:Dual(S("sidebarWidth", L["Width"], 24, 56, 1, Px), nil)

    p:Section(L["Icons"])
    p:Dual(T("iconFriends", L["Friends"], L["Opens your friends list; shows how many are online."]),
           T("iconGuild", L["Guild"], L["Opens the guild window; shows how many are online."]))
    p:Dual(T("iconCopy", L["Copy chat"], L["Copies the open window's text. Also /evui copy."]),
           T("iconChannels", L["Channels"]))
    p:Dual(T("iconSettings", L["Chat settings"], L["Opens this page."]),
           T("iconScroll", L["Scroll to bottom"], L["Lights up while you're scrolled back."]))
end

EV.Options:RegisterPage{
    key = "chat", title = L["Chat"], group = "Chat & Tooltips", module = "Chat",
    description = L["A clean chat panel: our own text, tabs and sidebar over Blizzard's chat, which keeps doing all the real work."],
    tabs = { TAB_WINDOW, TAB_MESSAGES, TAB_TABS, TAB_SIDEBAR },
    build = function(p, tab)
        if tab == TAB_MESSAGES then return Messages(p) end
        if tab == TAB_TABS then return Tabs(p) end
        if tab == TAB_SIDEBAR then return Sidebar(p) end
        return Window(p)
    end,
    onReset = function(tab)
        local keys = {
            [TAB_WINDOW] = { "bgAlpha", "border", "dividers", "scrollBar", "font", "outline", "shadow", "overrideSize",
                             "fontSize", "inputOnTop", "editHeight", "editFontSize", "recall", "idleFade", "idleDelay",
                             "idleStrength" },
            [TAB_MESSAGES] = { "timestamps", "stampAll", "shortChannels", "classNames", "urls", "linkTooltips", "whisperSound", "history" },
            [TAB_TABS] = { "tabsInPanel", "tabHeight", "tabPadding", "tabSpacing", "tabFontSize", "tabActiveText",
                           "tabUnderline", "tabBgAlpha" },
            [TAB_SIDEBAR] = { "sidebar", "sidebarRight", "sidebarWidth", "iconFriends", "iconGuild", "iconCopy",
                              "iconChannels", "iconSettings", "iconScroll" },
        }
        for _, k in ipairs(keys[tab] or keys[TAB_WINDOW]) do M.db[k] = M.defaults[k] end
        M:Refresh()
    end,
}
