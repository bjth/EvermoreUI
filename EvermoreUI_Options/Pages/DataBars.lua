if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Data Bars. Only registers if the module is loaded.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("DataBars", true)
if not M then return end

local function Get(key) return function() return M.db.xp[key] end end
local function Set(key)
    return function(v)
        M.db.xp[key] = v
        if M:IsEnabled() then M:Refresh() end
    end
end
local function Toggle(key, text, tooltip, extra)
    local cfg = { type = "toggle", text = text, tooltip = tooltip, get = Get(key), set = Set(key),
                  disabled = function() return key ~= "enabled" and not M.db.xp.enabled end }
    if extra then for k, v in pairs(extra) do cfg[k] = v end end
    return cfg
end
local function Off() return not M.db.xp.enabled end

-- Framerate and latency readouts.
local function Every(v) return v == 0 and L["Hover"] or (v .. "s") end
local TAB_XP, TAB_PERF = L["Experience"], L["Performance"]
local function SG(group, key) return function() return M.db[group][key] end end
local function SS(group, key)
    return function(v)
        M.db[group][key] = v
        if M:IsEnabled() then M:Refresh() end
    end
end
local function ST(group, key, text, tooltip)
    return { type = "toggle", text = text, tooltip = tooltip, get = SG(group, key), set = SS(group, key),
             disabled = key ~= "enabled" and function() return not M.db[group].enabled end or nil }
end

local function Performance(p)
    p:Section(L["Framerate"])
    p:Dual(ST("fps", "enabled", L["Show framerate"]),
           ST("fps", "colourize", L["Colour by speed"], L["Green at or above the good value, amber at or above the ok value, red below."]))
    p:Dual(ST("fps", "showLabel", L["Show label"], L["Prefixes the number with FPS."]),
           ST("fps", "background", L["Background"], L["A panel and border behind the text."]))
    p:Dual(
        { type = "slider", text = L["Good at or above"], min = 15, max = 240, step = 5,
          get = SG("fps", "good"), set = SS("fps", "good"), disabled = function() return not M.db.fps.enabled end },
        { type = "slider", text = L["OK at or above"], min = 5, max = 120, step = 5,
          get = SG("fps", "ok"), set = SS("fps", "ok"), disabled = function() return not M.db.fps.enabled end })
    p:Dual(
        { type = "slider", text = L["Font size"], min = 8, max = 24, step = 1,
          get = SG("fps", "fontSize"), set = SS("fps", "fontSize"), disabled = function() return not M.db.fps.enabled end },
        { type = "slider", text = L["Update every"], min = 0, max = 30, step = 1, fmt = Every,
          tooltip = L["Seconds between updates. 0 only updates while your mouse is over it; hovering always updates every second."],
          get = SG("fps", "interval"), set = SS("fps", "interval"), disabled = function() return not M.db.fps.enabled end })
    p:Row{ type = "button", text = L["Position"], label = L["Reset"], width = 100,
           onClick = function() EV.Movers:Reset("FPS") end }

    p:Section(L["Latency"])
    p:Dual(ST("latency", "enabled", L["Show latency"]),
           { type = "dropdown", text = L["Show"], width = 170,
             values = { { value = "both", text = L["Home and world"] }, { value = "home", text = L["Home only"] },
                        { value = "world", text = L["World only"] } },
             tooltip = L["Home: your connection to the realm (chat, mail, auction house). World: your connection to the game world (combat, abilities, other players)."],
             get = SG("latency", "mode"), set = SS("latency", "mode"),
             disabled = function() return not M.db.latency.enabled end })
    p:Dual(ST("latency", "colourize", L["Colour by speed"], L["Green below the good value, amber below the ok value, red above."]),
           ST("latency", "showLabel", L["Show label"], L["Prefixes the number with MS, Home or World."]))
    p:Dual(
        { type = "slider", text = L["Good below (ms)"], min = 20, max = 300, step = 10,
          get = SG("latency", "good"), set = SS("latency", "good"), disabled = function() return not M.db.latency.enabled end },
        { type = "slider", text = L["OK below (ms)"], min = 50, max = 600, step = 10,
          get = SG("latency", "ok"), set = SS("latency", "ok"), disabled = function() return not M.db.latency.enabled end })
    p:Dual(ST("latency", "background", L["Background"], L["A panel and border behind the text."]),
        { type = "slider", text = L["Font size"], min = 8, max = 24, step = 1,
          get = SG("latency", "fontSize"), set = SS("latency", "fontSize"), disabled = function() return not M.db.latency.enabled end })
    p:Dual(
        { type = "slider", text = L["Update every"], min = 0, max = 60, step = 1, fmt = Every,
          tooltip = L["Seconds between updates. 0 only updates while your mouse is over it. The game itself only refreshes latency every 30 seconds."],
          get = SG("latency", "interval"), set = SS("latency", "interval"), disabled = function() return not M.db.latency.enabled end },
        { type = "button", text = L["Position"], label = L["Reset"], width = 100,
          onClick = function() EV.Movers:Reset("Latency") end })

    p:Section(L["Durability"])
    p:Dual(ST("durability", "enabled", L["Show durability"], L["Your worst item's durability. Hover for the item and what a repair will cost."]),
           ST("durability", "colourize", L["Colour by condition"], L["Green at or above the good value, amber at or above the ok value, red below."]))
    p:Dual(ST("durability", "showLabel", L["Show label"], L["Prefixes the number with Gear."]),
           ST("durability", "background", L["Background"], L["A panel and border behind the text."]))
    p:Dual(
        { type = "slider", text = L["Good at"], min = 10, max = 100, step = 5, fmt = function(v) return v .. "%" end,
          get = SG("durability", "good"), set = SS("durability", "good"), disabled = function() return not M.db.durability.enabled end },
        { type = "slider", text = L["Ok at"], min = 5, max = 95, step = 5, fmt = function(v) return v .. "%" end,
          get = SG("durability", "ok"), set = SS("durability", "ok"), disabled = function() return not M.db.durability.enabled end })
    p:Dual(
        { type = "slider", text = L["Font size"], min = 8, max = 24, step = 1,
          get = SG("durability", "fontSize"), set = SS("durability", "fontSize"), disabled = function() return not M.db.durability.enabled end },
        { type = "button", text = L["Position"], label = L["Reset"], width = 100,
          onClick = function() EV.Movers:Reset("Durability") end })
end

EV.Options:RegisterPage{
    key = "databars", title = L["Data Bars"], group = "Interface", module = "DataBars",
    description = L["An experience bar built for levelling, plus framerate and latency readouts."],
    tabs = { TAB_XP, TAB_PERF },
    build = function(p, tab)
        if tab == TAB_PERF then return Performance(p) end
        p:Section(L["General"])
        p:Dual(
            Toggle("enabled", L["Show experience bar"]),
            Toggle("hideBlizzardBar", L["Hide Blizzard's bar"], L["Fades out Blizzard's own experience bar while this one is showing."]))
        p:Dual(
            Toggle("showAtMax", L["Show at max level"]),
            Toggle("animations", L["Animations"], L["A flash on every XP gain and a level-up burst."]))

        p:Section(L["Text"])
        p:Dual(
            Toggle("showBarText", L["Text on the bar"], L["Level, XP numbers and percentage inside the bar."]),
            Toggle("showQuestLine", L["Quests and rested line"], L["Completed Quests: x%  -  Rested Experience: y%"]))
        p:Dual(
            Toggle("showRateLine", L["Rate line"], L["Time spent this level, XP per hour and time to level."]),
            Toggle("showSessionLine", L["Session line"], L["How long this session has run and the XP gained in it."]))
        p:Dual(
            Toggle("showPlayed", L["Total played time"], L["Adds /played to the session line."],
                { disabled = function() return Off() or not M.db.xp.showSessionLine end }),
            Toggle("resetSessionOnReload", L["Reset session on reload"], L["Off: the session carries on through /reload and only resets when you log in."]))

        p:Section(L["Bar"])
        p:Dual(
            { type = "slider", text = L["Width"], min = 100, max = 1600, step = 10,
              get = Get("width"), set = Set("width"), disabled = Off },
            { type = "slider", text = L["Height"], min = 4, max = 60, step = 1,
              get = Get("height"), set = Set("height"), disabled = Off })
        p:Dual(
            { type = "slider", text = L["Font size"], min = 8, max = 24, step = 1,
              get = Get("fontSize"), set = Set("fontSize"), disabled = Off },
            { type = "dropdown", text = L["Texture"], width = 150, disabled = Off,
              values = function()
                  local list = {}
                  for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
                  return list
              end,
              get = Get("texture"), set = Set("texture") })
        p:Dual(
            Toggle("showQuestLog", L["Incomplete quests layer"], L["A faint segment for every quest in your log, finished or not."]),
            { type = "button", text = L["Position"], label = L["Reset"], width = 100, disabled = Off,
              onClick = function() EV.Movers:Reset("XPBar") end })
    end,
    onReset = function(tab)
        local group = tab == TAB_PERF and { "fps", "latency", "durability" } or { "xp" }
        for _, g in ipairs(group) do
            wipe(M.db[g])
            EV.DB.Merge(M.db[g], M.defaults[g])
        end
        if M:IsEnabled() then M:Refresh() end
    end,
}
