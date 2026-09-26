if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Cooldowns: one tab per bar (essential, utility, tracked buffs), and one
--  for linked timers.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Cooldowns", true)
if not M then return end

local GROW = {
    { value = "CENTER", text = L["From the middle"] },
    { value = "RIGHT",  text = L["Rightwards"] },
    { value = "LEFT",   text = L["Leftwards"] },
}
local ROWS = {
    { value = "DOWN", text = L["Downwards"] },
    { value = "UP",   text = L["Upwards"] },
}
local SHOW = {
    { value = "always", text = L["Always"] },
    { value = "fade",   text = L["Faded out of combat"] },
    { value = "combat", text = L["Only in combat"] },
    { value = "hidden", text = L["Never"] },
}

local TAB_TIMERS = L["Linked timers"]

local function Timers(p)
    local list = M:Timers()
    p:Section(TAB_TIMERS)
    p:Note(L["A timer over a cooldown's icon for a set time after you cast it. Power Word: Shield, for example, can count down Weakened Soul. It runs from your cast, not the debuff, because the game hides other players' debuffs from addons in combat; so it follows your last cast, whoever it was on."], 0.7)
    if #list == 0 then p:Note(L["No timers yet."], 0.6) end
    for i, t in ipairs(list) do
        local name = M.SpellName(t.spell) or ("#" .. tostring(t.spell))
        p:Dual({ type = "slider", text = name, min = 1, max = 60, step = 0.5,
                 fmt = function(v) return (v % 1 == 0 and ("%ds") or ("%.1fs")):format(v) end,
                 get = function() return t.seconds end,
                 set = function(v) t.seconds = v end },
               { type = "button", text = "", label = L["Remove"], width = 90,
                 onClick = function() table.remove(list, i); EV.Options:Rebuild() end })
    end
    local spells = M.BarSpells()
    if #spells == 0 then
        p:Note(L["Spells appear here once they're in your cooldown bars."], 0.6)
    else
        p:Row{ type = "dropdown", text = L["Add a timer to"], width = 220, values = spells,
               get = function() return nil end,
               set = function(id)
                   list[#list + 1] = { spell = id, seconds = 10 }
                   EV.Options:Rebuild()
               end }
    end
end

local function DefFor(tab)
    for _, def in ipairs(M.BARS) do
        if def.label == tab then return def end
    end
    return M.BARS[1]
end

local function Build(p, def)
    local db = M.db.bars[def.key]
    local function G(k) return function() return db[k] end end
    local function S(k) return function(v) db[k] = v; if M:IsEnabled() then M:Refresh() end end end
    local off = function() return not db.enabled end

    if M:IsEnabled() then
        local problem = M.Problem(def)
        if problem then
            if not M.BlizzardOn() then
                p:Banner(problem, L["Switch it on"], function() M.SetBlizzardOn(true); EV.Options:Rebuild() end)
            else
                p:Banner(problem)
            end
        end
    end

    p:Section(def.label)
    p:Dual({ type = "toggle", text = L["Use this bar"],
             tooltip = L["Off leaves these icons where the game puts them. Takes effect after a reload."],
             get = G("enabled"), set = function(v) db.enabled = v end },
           { type = "dropdown", text = L["Show"], width = 180, values = SHOW,
             get = G("visibility"), set = S("visibility"), disabled = off })
    p:Dual({ type = "slider", text = L["Fade to"], min = 0, max = 1, step = 0.05,
             fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
             get = G("fade"), set = S("fade"),
             disabled = function() return off() or db.visibility ~= "fade" end }, nil)

    p:Section(L["Layout"])
    p:Dual({ type = "slider", text = L["Icon size"], min = 16, max = 72, step = 1, get = G("size"), set = S("size"), disabled = off },
           { type = "slider", text = L["Spacing"], min = 0, max = 16, step = 1, get = G("spacing"), set = S("spacing"), disabled = off })
    p:Dual({ type = "slider", text = L["Icons per row"], min = 1, max = 20, step = 1, get = G("perRow"), set = S("perRow"), disabled = off },
           { type = "dropdown", text = L["Icons run"], width = 180, values = GROW, get = G("grow"), set = S("grow"), disabled = off })
    p:Dual({ type = "dropdown", text = L["New rows go"], width = 180, values = ROWS, get = G("rows"), set = S("rows"), disabled = off },
           { type = "button", text = L["Position"], label = L["Reset"], width = 100,
             onClick = function() EV.Movers:Reset("CD_" .. def.key) end })

    local POINTS = {
        { value = "TOPLEFT", text = L["Top left"] }, { value = "TOP", text = L["Top"] },
        { value = "TOPRIGHT", text = L["Top right"] }, { value = "LEFT", text = L["Left"] },
        { value = "CENTER", text = L["Centre"] }, { value = "RIGHT", text = L["Right"] },
        { value = "BOTTOMLEFT", text = L["Bottom left"] }, { value = "BOTTOM", text = L["Bottom"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
    local function TextRows(prefix, title, tip)
        local hidden = function() return off() or not db[prefix == "key" and "keys" or "rank"] end
        p:Section(title)
        p:Dual({ type = "toggle", text = L["Show"], tooltip = tip,
                 get = G(prefix == "key" and "keys" or "rank"), set = S(prefix == "key" and "keys" or "rank"), disabled = off },
               { type = "dropdown", text = L["Position"], width = 150, values = POINTS,
                 get = G(prefix .. "Point"), set = S(prefix .. "Point"), disabled = hidden })
        p:Dual({ type = "slider", text = L["Offset X"], min = -30, max = 30, step = 1,
                 get = G(prefix .. "X"), set = S(prefix .. "X"), disabled = hidden },
               { type = "slider", text = L["Offset Y"], min = -30, max = 30, step = 1,
                 get = G(prefix .. "Y"), set = S(prefix .. "Y"), disabled = hidden })
        p:Dual({ type = "slider", text = L["Text size"], min = 0, max = 24, step = 1,
                 fmt = function(v) return v == 0 and L["Auto"] or tostring(v) end,
                 tooltip = L["Auto scales with the icon size."],
                 get = G(prefix .. "Size"), set = S(prefix .. "Size"), disabled = hidden }, nil)
    end
    TextRows("key", L["Keybind"], L["The key of the action button that casts it. Found on your action bars, macros included."])
    TextRows("rank", L["Spell rank"], L["The rank you'd cast: the one on your action bar, or the highest you know."])

    p:Section(L["Which spells"])
    p:Note(L["The game's Cooldown Manager decides what goes in each bar. Its settings let you move spells between bars, reorder them and hide the ones you don't want."], 0.7)
    p:Row{ type = "button", text = L["Blizzard's Cooldown Manager settings"], label = L["Open"], width = 100,
           onClick = function()
               if InCombatLockdown() then return end
               if CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
                   EV.Options:Toggle()
                   CooldownViewerSettings:TogglePanel()
               end
           end }
end

EV.Options:RegisterPage{
    key = "cooldowns", title = L["Cooldowns"], group = "Combat", module = "Cooldowns",
    description = L["Your cooldowns and the buffs they leave, in EvermoreUI bars. The game's own Cooldown Manager does the tracking, so it keeps working in combat; these bars decide how it looks and where it sits."],
    tabs = (function() local t = {} for _, def in ipairs(M.BARS) do t[#t + 1] = def.label end
                          t[#t + 1] = TAB_TIMERS; return t end)(),
    build = function(p, tab)
        if tab == TAB_TIMERS then Timers(p) else Build(p, DefFor(tab)) end
    end,
    onReset = function(tab)
        if tab == TAB_TIMERS then return end
        local def = DefFor(tab)
        wipe(M.db.bars[def.key])
        EV.DB.Merge(M.db.bars[def.key], M.defaults.bars[def.key])
        if M:IsEnabled() then M:Refresh() end
    end,
}
