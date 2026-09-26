if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Objective Tracker. Only registers if the module is loaded.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Objectives", true)
if not M then return end

local TAB_LAYOUT, TAB_QUESTS, TAB_BEHAVIOUR, TAB_ITEMS, TAB_ALERTS =
    L["Layout"], L["Quests"], L["Behaviour"], L["Quest Items"], L["Alerts"]

local function Apply() if M:IsEnabled() then M:Refresh() end end
local function G(key) return function() return M.db[key] end end
local function S(key) return function(v) M.db[key] = v; Apply() end end
local function Toggle(key, text, tooltip, extra)
    local cfg = { type = "toggle", text = text, tooltip = tooltip, get = G(key), set = S(key) }
    if extra then for k, v in pairs(extra) do cfg[k] = v end end
    return cfg
end
local function IG(key) return function() return M.db.items[key] end end
local function IS(key) return function(v) M.db.items[key] = v; Apply() end end
local function ItemsOff() return not M.db.items.enabled end
local function Pct(v) return v .. "%" end

local SHOW = {
    { value = "show", text = L["Show"] },
    { value = "fade", text = L["Fade"] },
    { value = "hide", text = L["Hide"] },
}

local function Layout(p)
    p:Section(L["Size"])
    p:Dual(
        { type = "slider", text = L["Width"], min = M.LIMITS.wMin, max = M.LIMITS.wMax, step = 5,
          tooltip = L["Also in edit mode (/evui edit): drag the tracker's corner grip, or type a size."],
          get = G("width"), set = S("width") },
        { type = "slider", text = L["Maximum height"], min = M.LIMITS.hMin, max = M.LIMITS.hMax, step = 10,
          tooltip = L["Past this the tracker scrolls. Mouse wheel over it to scroll. In edit mode this is the box you resize."],
          get = G("height"), set = S("height") })
    p:Dual(
        Toggle("fitContent", L["Shrink to fit"], L["The panel is only as tall as your quests. Off: always the maximum height."]),
        Toggle("infoStrip", L["Quest count and XP"], L["Quests in your log against the cap, and the XP waiting in finished quests, along the top."]))

    p:Section(L["Look"])
    p:Dual(
        { type = "slider", text = L["Background opacity"], min = 0, max = 100, step = 5, fmt = Pct,
          get = function() return math.floor(M.db.bgAlpha * 100 + 0.5) end,
          set = function(v) M.db.bgAlpha = v / 100; Apply() end },
        Toggle("border", L["Border"]))
    p:Dual(
        { type = "button", text = L["Move it"], label = L["Edit mode"], width = 120,
          onClick = function() EV.Movers:Unlock() end },
        { type = "button", text = L["Position"], label = L["Reset"], width = 100,
          onClick = function() EV.Movers:Reset("OBJ_tracker") end })
end

local function Quests(p)
    p:Section(L["The list"])
    p:Dual(
        { type = "dropdown", text = L["Show"], width = 170, get = G("source"), set = S("source"),
          values = { { value = "tracked", text = L["Tracked quests"] }, { value = "all", text = L["Every quest in my log"] } },
          tooltip = L["Every quest: untracked ones show faded. Shift-click one to track or untrack it."] },
        { type = "dropdown", text = L["Group by"], width = 170, get = G("grouping"), set = S("grouping"),
          values = { { value = "zone", text = L["Zone"] }, { value = "campaign", text = L["Campaign and quests"] }, { value = "none", text = L["Nothing"] } },
          tooltip = L["Zone: one section per quest log zone, the zone you're in first. Each section collapses on its own."] })
    p:Dual(
        { type = "dropdown", text = L["Sort by"], width = 170, get = G("sort"), set = S("sort"),
          values = { { value = "distance", text = L["Nearest first"] }, { value = "watch", text = L["Order tracked"] }, { value = "level", text = L["Level"] } },
          tooltip = L["Nearest first re-sorts every few seconds as you move."] },
        { type = "dropdown", text = L["Finished objectives"], width = 170, get = G("finished"), set = S("finished"),
          values = { { value = "dim", text = L["Dimmed"] }, { value = "show", text = L["Shown"] }, { value = "hide", text = L["Hidden"] } } })

    p:Section(L["Quest names"])
    p:Dual(
        Toggle("levels", L["Levels"], L["[23] before each quest."]),
        Toggle("tags", L["Quest type tags"], L["Adds to the level: D dungeon, R raid, G group, P PvP, H heroic, S scenario, + elite."]))
    p:Dual(
        Toggle("difficulty", L["Difficulty colours"], L["Grey, green, yellow, orange and red by level."]),
        Toggle("completeColour", L["Finished quests in green"]))

    p:Section(L["Objectives"])
    p:Dual(
        Toggle("progressBars", L["Progress bars"], L["A thin bar under objectives like 3/10, and under percentage objectives."]),
        Toggle("timers", L["Quest timers"], L["Timed quests count down along the top of the panel, instead of in Blizzard's separate timer window."]))
    p:Dual(
        Toggle("zoneTrack", L["Track quests in this zone"],
            L["Tracks quests for the zone you're in and untracks them when you leave. Quests you tracked yourself are never untracked, and one you untrack here stays untracked until you leave."]),
        Toggle("blizzard", L["Blizzard's other objectives"],
            L["Scenarios, world quests, bonus objectives, tracked achievements and recipes: Blizzard's tracker shows them below your quests, only when there are any."]))
end

local function Behaviour(p)
    p:Section(L["Visibility"])
    p:Dual(
        { type = "dropdown", text = L["In combat"], width = 150, values = SHOW, get = G("combat"), set = S("combat") },
        { type = "dropdown", text = L["In instances"], width = 150, values = SHOW,
          tooltip = L["Dungeons, raids, battlegrounds, arenas and scenarios."],
          get = G("instances"), set = S("instances") })
    p:Dual(
        Toggle("mouseFade", L["Fade until moused over"]),
        { type = "slider", text = L["Faded opacity"], min = 0, max = 100, step = 5, fmt = Pct,
          get = function() return math.floor(M.db.fadeAlpha * 100 + 0.5) end,
          set = function(v) M.db.fadeAlpha = v / 100; Apply() end })
    p:Section(L["How this works"])
    p:Note(L["Quests are EvermoreUI's own list: click a quest to open it on the map, shift-click to untrack, right-click for options, and click its marker to focus it. Quest items are used from the quest item bar. Blizzard's tracker still runs underneath for everything else, and Blizzard's Edit Mode no longer moves it. Turn the feature off and reload to hand it all back."], 0.75)
end

local function Items(p)
    p:Section(L["On the quest"])
    p:Row(Toggle("rowItems", L["Item button on the quest"],
        L["A button down the right of the quest, the full height of it, to use the quest's item. While you're in combat with one on show, the list keeps its layout (text and progress still update) and re-lays out when combat ends."]))
    p:Section(L["Quest item bar"])
    p:Dual(
        { type = "toggle", text = L["Show the quest item bar"],
          tooltip = L["A separate bar with every usable quest item in your log, for keybinds (Key Bindings > AddOns > EvermoreUI). Off by default now each quest has its own item button. Works in combat; which items it holds updates after combat."],
          get = IG("enabled"), set = IS("enabled") },
        { type = "toggle", text = L["Tracked quests only"], get = IG("trackedOnly"), set = IS("trackedOnly"), disabled = ItemsOff })
    p:Dual(
        { type = "slider", text = L["Most buttons"], min = 1, max = 12, step = 1, get = IG("max"), set = IS("max"), disabled = ItemsOff },
        { type = "slider", text = L["Buttons per row"], min = 1, max = 12, step = 1, get = IG("perRow"), set = IS("perRow"), disabled = ItemsOff })
    p:Dual(
        { type = "slider", text = L["Button size"], min = 20, max = 64, step = 1, get = IG("size"), set = IS("size"), disabled = ItemsOff },
        { type = "slider", text = L["Spacing"], min = 0, max = 16, step = 1, get = IG("spacing"), set = IS("spacing"), disabled = ItemsOff })
    p:Dual(
        { type = "toggle", text = L["Show keybinds"],
          tooltip = L["Set them in Key Bindings > AddOns > EvermoreUI > Quest Items."],
          get = IG("hotkeys"), set = IS("hotkeys"), disabled = ItemsOff },
        { type = "button", text = L["Position"], label = L["Reset"], width = 100, disabled = ItemsOff,
          onClick = function() EV.Movers:Reset("OBJ_items") end })
end

local function Alerts(p)
    p:Section(L["Sounds"])
    p:Dual(
        Toggle("soundObjective", L["Objective finished"]),
        Toggle("soundQuest", L["Quest ready to hand in"]))
    p:Section(L["Pop-up"])
    p:Dual(
        Toggle("toast", L["Quest complete pop-up"], L["A small notice when a quest is ready to hand in. Move it with /evui edit."]),
        { type = "button", text = L["Preview"], label = L["Show"], width = 100,
          onClick = function()
              local ns = EV._ModuleNS.EvermoreUI_Objectives
              if ns and ns.Toast then ns.Toast(L["Quest complete"], L["The Missing Diplomat"]) end
          end,
          disabled = function() return not M:IsEnabled() end })
end

EV.Options:RegisterPage{
    key = "objectives", title = L["Objective Tracker"], group = "Interface", module = "Objectives",
    description = L["Your quests in an EvermoreUI panel: grouped, sorted and styled our way, with levelling extras. Blizzard's other objectives show below."],
    tabs = { TAB_LAYOUT, TAB_QUESTS, TAB_BEHAVIOUR, TAB_ITEMS, TAB_ALERTS },
    build = function(p, tab)
        if tab == TAB_QUESTS then return Quests(p) end
        if tab == TAB_BEHAVIOUR then return Behaviour(p) end
        if tab == TAB_ITEMS then return Items(p) end
        if tab == TAB_ALERTS then return Alerts(p) end
        return Layout(p)
    end,
    onReset = function(tab)
        local keys
        if tab == TAB_ITEMS then
            wipe(M.db.items); EV.DB.Merge(M.db.items, M.defaults.items)
            M.db.rowItems = M.defaults.rowItems
        else
            keys = ({
                [TAB_LAYOUT] = { "width", "height", "fitContent", "infoStrip", "bgAlpha", "border" },
                [TAB_QUESTS] = { "source", "grouping", "sort", "finished", "levels", "tags", "difficulty", "completeColour",
                                 "progressBars", "timers", "zoneTrack", "blizzard" },
                [TAB_BEHAVIOUR] = { "combat", "instances", "mouseFade", "fadeAlpha" },
                [TAB_ALERTS] = { "soundObjective", "soundQuest", "toast" },
            })[tab] or {}
            for _, k in ipairs(keys) do M.db[k] = M.defaults[k] end
        end
        Apply()
    end,
}
