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
local SIDE_GROW = {
    { value = "RIGHT", text = L["Rightwards"] },
    { value = "LEFT",  text = L["Leftwards"] },
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

    if M:IsEnabled() and M.Problem and not def.own then
        local problem = M.Problem(def)
        if problem and not M.BlizzardOn() then
            p:Banner(problem, L["Switch it on"], function() M.SetBlizzardOn(true); Refresh() end)
        elseif problem then
            p:Banner(problem)
        end
    end

    p:Section(L["General"])
    if def.own then
        p:Row{ type = "toggle", text = L["Use this bar"], get = G("enabled"), set = S("enabled") }
    else
        p:Row{ type = "toggle", text = L["Use this bar"],
               tooltip = L["Off leaves these icons where the game puts them. Takes effect after a reload."],
               get = G("enabled"),
               set = function(v)
                   db.enabled = v
                   if EV.Options and EV.Options.MarkReloadNeeded then EV.Options:MarkReloadNeeded() end
               end }
    end
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
    -- The engine lays out Your buffs from one corner, so it can't centre them.
    p:Row{ type = "dropdown", text = L["Icons run"], values = def.own and SIDE_GROW or GROW,
           get = G("grow"), set = S("grow"), disabled = off }
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

--------------------------------------------------------------------------------
--  Your own icons
--------------------------------------------------------------------------------
local BARS_FOR_NEW = {
    { value = "essential", text = L["Essential cooldowns"] },
    { value = "utility",   text = L["Utility cooldowns"] },
}

--- Everything you've added, with Remove, and the ways to add more.
--- rebuild(commit) redraws the rows when the list changes; commit is true
--- when no control records the change itself (buttons and text boxes do
--- not; dropdowns do).
function ns.CustomSettings(p, rebuild)
    local M = ns.module
    local list = M:CustomList()
    local target = "essential"
    p:Section(L["Your own icons"])
    p:Note(L["Trinkets, potions and other items, and spells the game's Cooldown Manager doesn't list. They sit in your cooldown bars and drag about like the rest; the list is for this class, where they sit is per spec."], 0.7)
    if #list == 0 then p:Note(L["Nothing added yet."], 0.6) end
    for _, e in ipairs(list) do
        local f
        for _, x in ipairs(ns.CustomFrames and ns.CustomFrames() or {}) do if x.evUID == e.uid then f = x end end
        local label = f and f.evLabel or ("#" .. tostring(e.id))
        if f and f.evWhat and f.evWhat ~= label then label = label .. "  |cff8a8f99" .. f.evWhat .. "|r" end
        p:Row{ type = "button", text = label, label = L["Remove"], width = 90,
               onClick = function() M:RemoveCustom(e.uid); rebuild(true) end }
    end
    p:Section(L["Add"])
    p:Row{ type = "dropdown", text = L["Goes on"], values = BARS_FOR_NEW,
          get = function() return target end, set = function(v) target = v end }
    p:Row{ type = "dropdown", text = L["A trinket slot"],
           values = { { value = 13, text = ns.TRINKETS[13] }, { value = 14, text = ns.TRINKETS[14] } },
           tooltip = L["Shows whatever trinket is in that slot, while it has a Use."],
           get = function() return nil end,
           set = function(v) M:AddCustom("slot", v, target); rebuild(false) end }
    p:Row{ type = "input", text = L["An item"], width = 170,
           placeholder = L["Name, ID or link"],
           tooltip = L["A potion, Healthstone or anything else with a cooldown. By name it has to be in your bags; an ID or a shift-clicked link always works."],
           get = function() return "" end,
           set = function(v)
               local id = M.ResolveItem(v)
               if id then M:AddCustom("item", id, target); rebuild(true)
               elseif v ~= "" then EV:Print(L["No item found by that name. Try its ID or shift-click it in."]) end
           end }
    p:Row{ type = "input", text = L["A spell"], width = 170,
           placeholder = L["Name, ID or link"],
           tooltip = L["A spell of yours the game's Cooldown Manager doesn't track. By name you need to know it."],
           get = function() return "" end,
           set = function(v)
               local id = M.ResolveSpell(v)
               if id then M:AddCustom("spell", id, target); rebuild(true)
               elseif v ~= "" then EV:Print(L["No spell of yours by that name. Try its ID."]) end
           end }
end

--- One of your own icons, picked on the grid.
function ns.CustomIconSettings(p, f, done)
    local M = ns.module
    local e = f.evEntry
    p:Section(f.evWhat or L["Your own icon"])
    local explain = {
        slot = L["Whatever trinket is in this slot, shown while it has a Use."],
        item = L["Greyed when you have none left; the number is how many you carry."],
        spell = L["Shown once you know the spell."],
    }
    p:Note(explain[e.kind] or "", 0.7)
    if not f.evActive then p:Note(L["Nothing to show right now, so it's hidden in game."], 0.6) end
    p:Row{ type = "button", text = L["Take it out of your bars"], label = L["Remove"], width = 90,
           onClick = function() M:RemoveCustom(e.uid); done() end }
    if e.kind == "spell" then ns.IconTimer(p, e.id) end
end

--------------------------------------------------------------------------------
--  Your buffs
--------------------------------------------------------------------------------
function ns.MyBuffSettings(p, rebuild)
    local M = ns.module
    local list = M:MyBuffs()
    p:Section(L["Your buffs"])
    p:Note(L["A bar of just the buffs you name, whoever cast them: your seals, say, or an aura you keep up. Drawn by the game, so it keeps working in combat. Every rank counts."], 0.7)
    if EV.AuraContainer and not EV.AuraContainer.Supported() then
        p:Note(L["This client doesn't provide the aura containers this bar needs."], 0.6)
    end
    if #list == 0 then p:Note(L["No buffs named yet."], 0.6) end
    for i, e in ipairs(list) do
        p:Row{ type = "button", text = M.MyBuffName(e) or "?", label = L["Remove"], width = 90,
               onClick = function() M.RemoveMyBuff(i); Refresh(); rebuild(true) end }
    end
    p:Row{ type = "input", text = L["Add a buff"], width = 170,
           placeholder = L["Name, ID or link"],
           tooltip = L["Its name covers every rank. Seal of Righteousness, for example."],
           get = function() return "" end,
           set = function(v)
               if v ~= "" and M.AddMyBuff(v) then Refresh(); rebuild(true) end
           end }
    ns.BarSettings(p, ns.MINE)
end
