if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Settings.lua
--  Every Cooldowns setting, written once, for the designer's inspector.
--
--  ns.BarSettings(p, def)     one bar: visibility, layout, keybind and rank
--  ns.TimerList(p, rebuild)   every linked timer, with add and remove
--  ns.IconTimer(p, spellID)   the linked timer on one cooldown
--  ns.ResetBar(def)           a bar back to its defaults
--
--  p is an options page builder. rebuild(commit) is called when the list
--  itself changes (a timer added or removed), so the rows can be drawn again;
--  commit is true when no control change has recorded it (a button).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

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
local POINTS = {
    { value = "TOPLEFT", text = L["Top left"] }, { value = "TOP", text = L["Top"] },
    { value = "TOPRIGHT", text = L["Top right"] }, { value = "LEFT", text = L["Left"] },
    { value = "CENTER", text = L["Centre"] }, { value = "RIGHT", text = L["Right"] },
    { value = "BOTTOMLEFT", text = L["Bottom left"] }, { value = "BOTTOM", text = L["Bottom"] },
    { value = "BOTTOMRIGHT", text = L["Bottom right"] },
}

local function Seconds(v) return (v % 1 == 0 and ("%ds") or ("%.1fs")):format(v) end

local function Refresh()
    local M = ns.module
    if M:IsEnabled() then M:Refresh() end
end

function ns.BarSettings(p, def)
    local M = ns.module
    local db = M.db.bars[def.key]
    local function G(k) return function() return db[k] end end
    local function S(k) return function(v) db[k] = v; Refresh() end end
    local off = function() return not db.enabled end

    if M:IsEnabled() and M.Problem then
        local problem = M.Problem(def)
        if problem and not M.BlizzardOn() then
            p:Banner(problem, L["Switch it on"], function() M.SetBlizzardOn(true); Refresh() end)
        elseif problem then
            p:Banner(problem)
        end
    end

    p:Section(L["General"])
    p:Row{ type = "toggle", text = L["Use this bar"],
           tooltip = L["Off leaves these icons where the game puts them. Takes effect after a reload."],
           get = G("enabled"),
           set = function(v)
               db.enabled = v
               if EV.Options and EV.Options.MarkReloadNeeded then EV.Options:MarkReloadNeeded() end
           end }
    p:Row{ type = "dropdown", text = L["Show"], values = SHOW,
           get = G("visibility"), set = S("visibility"), disabled = off }
    p:Row{ type = "slider", text = L["Fade to"], min = 0, max = 1, step = 0.05,
           fmt = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
           get = G("fade"), set = S("fade"),
           disabled = function() return off() or db.visibility ~= "fade" end }

    p:Section(L["Layout"])
    p:Row{ type = "slider", text = L["Icon size"], min = 16, max = 72, step = 1, get = G("size"), set = S("size"), disabled = off }
    p:Row{ type = "slider", text = L["Spacing"], min = 0, max = 16, step = 1, get = G("spacing"), set = S("spacing"), disabled = off }
    p:Row{ type = "slider", text = L["Icons per row"], min = 1, max = 20, step = 1, get = G("perRow"), set = S("perRow"), disabled = off }
    p:Row{ type = "dropdown", text = L["Icons run"], values = GROW, get = G("grow"), set = S("grow"), disabled = off }
    p:Row{ type = "dropdown", text = L["New rows go"], values = ROWS, get = G("rows"), set = S("rows"), disabled = off }
    p:Row{ type = "button", text = L["Position on screen"], label = L["Reset"], width = 90,
           onClick = function() EV.Movers:Reset("CD_" .. def.key) end }
    p:Note(L["Move the bar itself in edit mode: /evui edit."], 0.6)

    local function TextRows(flag, prefix, title, tip)
        local hidden = function() return off() or not db[flag] end
        p:Section(title)
        p:Row{ type = "toggle", text = L["Show"], tooltip = tip, get = G(flag), set = S(flag), disabled = off }
        p:Row{ type = "dropdown", text = L["Position"], values = POINTS,
               get = G(prefix .. "Point"), set = S(prefix .. "Point"), disabled = hidden }
        p:Row{ type = "slider", text = L["Offset X"], min = -30, max = 30, step = 1,
               get = G(prefix .. "X"), set = S(prefix .. "X"), disabled = hidden }
        p:Row{ type = "slider", text = L["Offset Y"], min = -30, max = 30, step = 1,
               get = G(prefix .. "Y"), set = S(prefix .. "Y"), disabled = hidden }
        p:Row{ type = "slider", text = L["Text size"], min = 0, max = 24, step = 1,
               fmt = function(v) return v == 0 and L["Auto"] or tostring(v) end,
               tooltip = L["Auto scales with the icon size."],
               get = G(prefix .. "Size"), set = S(prefix .. "Size"), disabled = hidden }
    end
    if not def.buff then
        TextRows("keys", "key", L["Keybind"], L["The key of the action button that casts it. Found on your action bars, macros included."])
        TextRows("rank", "rank", L["Spell rank"], L["The rank you'd cast: the one on your action bar, or the highest you know."])
    end
end

function ns.ResetBar(def)
    local M = ns.module
    local db = M.db.bars[def.key]
    wipe(db)
    EV.DB.Merge(db, M.defaults.bars[def.key])
    Refresh()
end

--- The timer on a spell, matched by name so every rank counts.
local function TimerOn(spellID)
    local M = ns.module
    local name = M.SpellName(spellID)
    if not name then return nil end
    for i, t in ipairs(M:Timers()) do
        if M.SpellName(t.spell) == name then return t, i end
    end
end
ns.TimerOn = TimerOn

local EXPLAIN = L["A timer over a cooldown's icon for a set time after you cast it. Power Word: Shield, for example, can count down Weakened Soul. It runs from your cast, not the debuff, because the game hides other players' debuffs from addons in combat; so it follows your last cast, whoever it was on."]

function ns.IconTimer(p, spellID)
    local M = ns.module
    p:Section(L["Linked timer"])
    p:Note(EXPLAIN, 0.7)
    p:Row{ type = "toggle", text = L["Count down after I cast it"],
           get = function() return TimerOn(spellID) ~= nil end,
           set = function(v)
               local t, i = TimerOn(spellID)
               if v and not t then
                   local list = M:Timers()
                   list[#list + 1] = { spell = spellID, seconds = 10 }
               elseif not v and i then
                   table.remove(M:Timers(), i)
               end
               Refresh()
           end }
    p:Row{ type = "slider", text = L["For"], min = 1, max = 60, step = 0.5, fmt = Seconds,
           get = function() local t = TimerOn(spellID); return t and t.seconds or 10 end,
           set = function(v) local t = TimerOn(spellID); if t then t.seconds = v; Refresh() end end,
           disabled = function() return TimerOn(spellID) == nil end }
end

function ns.TimerList(p, rebuild)
    local M = ns.module
    local list = M:Timers()
    p:Section(L["Linked timers"])
    p:Note(EXPLAIN, 0.7)
    p:Note(L["Or pick a cooldown on the grid to set its timer."], 0.6)
    if #list == 0 then p:Note(L["No timers yet."], 0.6) end
    for i, t in ipairs(list) do
        local name = M.SpellName(t.spell) or ("#" .. tostring(t.spell))
        p:Row{ type = "slider", text = name, min = 1, max = 60, step = 0.5, fmt = Seconds,
               get = function() return t.seconds end,
               set = function(v) t.seconds = v; Refresh() end }
        p:Row{ type = "button", text = "", label = L["Remove"], width = 90,
               onClick = function()
                   for j, x in ipairs(list) do if x == t then table.remove(list, j) break end end
                   Refresh()
                   rebuild(true)   -- a button: nothing else records the change
               end }
    end
    local spells = M.BarSpells()
    if #spells == 0 then
        p:Note(L["Spells appear here once they're in your cooldown bars."], 0.6)
    else
        p:Row{ type = "dropdown", text = L["Add a timer to"], values = spells,
               get = function() return nil end,
               set = function(id)
                   if not TimerOn(id) then list[#list + 1] = { spell = id, seconds = 10 } end
                   Refresh()
                   rebuild(false)  -- the dropdown's own change is recorded
               end }
    end
end
