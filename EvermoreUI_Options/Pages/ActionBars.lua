if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Action Bars. Only registers if the module is loaded.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("ActionBars", true)
if not M then return end
local ns = EV._ModuleNS.EvermoreUI_ActionBars
local Game = ns.Game

local TAB_BARS, TAB_PAGING, TAB_BUTTONS = L["Bars"], L["Paging"], L["Buttons"]
local TAB_CASTING, TAB_ACTIONS, TAB_GENERAL = L["Casting"], L["Modifier actions"], L["General"]
local selected = "main"

local function Bar() return M.db.bars[selected] end
local function Def() return ns.BY_KEY[selected] end
local function Apply() if M:IsEnabled() then M:Refresh() end end
local function BG(key) return function() return Bar()[key] end end
local function BS(key) return function(v) Bar()[key] = v; Apply() end end
local function Off() return not Bar().enabled end

local VIS = {
    { value = "always",   text = L["Always"] },
    { value = "combat",   text = L["In combat"] },
    { value = "nocombat", text = L["Out of combat"] },
    { value = "hidden",   text = L["Hidden"] },
    { value = "custom",   text = L["Custom conditions"] },
}

local GROW_H = { { value = "RIGHT", text = L["Rightwards"] }, { value = "LEFT", text = L["Leftwards"] } }
local GROW_V = { { value = "DOWN", text = L["Downwards"] }, { value = "UP", text = L["Upwards"] } }
local POINTS = {
    { value = "TOPLEFT", text = L["Top left"] }, { value = "TOP", text = L["Top"] },
    { value = "TOPRIGHT", text = L["Top right"] }, { value = "LEFT", text = L["Left"] },
    { value = "CENTER", text = L["Centre"] }, { value = "RIGHT", text = L["Right"] },
    { value = "BOTTOMLEFT", text = L["Bottom left"] }, { value = "BOTTOM", text = L["Bottom"] },
    { value = "BOTTOMRIGHT", text = L["Bottom right"] },
}
local RANK_FORMATS = {
    { value = "short", text = "R3" }, { value = "number", text = "3" }, { value = "full", text = L["Rank 3"] },
}
local RANK_DEFAULT = { 1, 0.82, 0 }
local RANK_KEYS = { "rankText", "rankFormat", "rankPoint", "rankX", "rankY", "rankSize", "rankColour" }

local FADE_GROUPS = {
    { value = 0, text = L["None"] },
    { value = 1, text = L["Group 1"] }, { value = 2, text = L["Group 2"] }, { value = 3, text = L["Group 3"] },
}

local function BarPicker(p, filter)
    local list = {}
    for _, def in ipairs(ns.BARS) do
        if not filter or filter(def) then list[#list + 1] = { value = def.key, text = def.label } end
    end
    if filter and not filter(Def()) then selected = list[1] and list[1].value or "main" end
    return { type = "dropdown", text = L["Editing"], width = 180, values = list,
             get = function() return selected end,
             set = function(v) selected = v; EV.Options:Rebuild() end }
end

--------------------------------------------------------------------------------
--  Bars
--------------------------------------------------------------------------------
-- A control built up front (so its height is known) and handed to a row.
local function Embed(p, ctrl, pad)
    p:Row{ type = "custom", height = ctrl:GetHeight() + (pad or 20), build = function() return ctrl end }
end

local function Editor(p)
    local def = Def()
    p:Section(L["Buttons on this bar"])
    if def.small then
        p:Note(def.stance and L["The stance bar always holds your forms and stances; the game fills it for you."]
            or L["The pet bar holds your pet's abilities; the game fills it for you."], 0.7)
        return
    end
    if not Bar().enabled then
        p:Note(L["Switch the bar on to edit its buttons."], 0.7)
        return
    end
    local width = p.width - 40
    Embed(p, ns.Editor.Bar(UIParent, width, selected))
    p:Note(L["This is the bar as the game has it right now, on the page it is showing. Changes happen on the real bar as you make them."], 0.6)
    p:Section(L["Spellbook"])
    Embed(p, ns.Editor.Book(UIParent, width))
end

local function Bars(p)
    p:Section(L["Bar"])
    p:Dual(BarPicker(p), { type = "toggle", text = L["Show this bar"], get = BG("enabled"), set = BS("enabled") })
    Editor(p)

    p:Section(L["Layout"])
    p:Dual(
        { type = "slider", text = L["Buttons"], min = 1, max = Def().count, step = 1,
          tooltip = Def().stance and L["The most to show. The stance bar only ever shows the forms you have, and doesn't appear at all for a class with none."] or nil,
          get = BG("buttons"), set = BS("buttons"), disabled = Off },
        { type = "slider", text = L["Buttons per row"], min = 1, max = Def().count, step = 1,
          tooltip = L["1 makes a vertical bar."],
          get = BG("perRow"), set = BS("perRow"), disabled = Off })
    p:Dual(
        { type = "slider", text = L["Button size"], min = 20, max = 64, step = 1,
          get = BG("size"), set = BS("size"), disabled = Off },
        { type = "slider", text = L["Spacing"], min = 0, max = 16, step = 1,
          get = BG("spacing"), set = BS("spacing"), disabled = Off })
    p:Dual(
        { type = "dropdown", text = L["Buttons run"], width = 150, values = GROW_H,
          tooltip = L["Which way the buttons run from the first one."],
          get = BG("growH"), set = BS("growH"), disabled = Off },
        { type = "dropdown", text = L["New rows go"], width = 150, values = GROW_V,
          get = BG("growV"), set = BS("growV"), disabled = Off })
    p:Dual(
        { type = "slider", text = L["Scale"], min = 50, max = 200, step = 5,
          fmt = function(v) return v .. "%" end,
          tooltip = L["The whole bar, text included. Button size changes the buttons and leaves the text alone."],
          get = function() return math.floor(ns.ValidScale(Bar().scale) * 100 + 0.5) end,
          set = function(v) Bar().scale = v / 100; Apply() end, disabled = Off },
        { type = "slider", text = L["Opacity"], min = 10, max = 100, step = 5,
          fmt = function(v) return v .. "%" end,
          get = function() return math.floor((Bar().alpha or 1) * 100 + 0.5) end,
          set = function(v) Bar().alpha = v / 100; Apply() end, disabled = Off })
    p:Dual(
        { type = "toggle", text = L["Show empty slots"],
          tooltip = L["Empty slots stay visible. Off: they only appear while you drag a spell."],
          get = BG("showEmpty"), set = BS("showEmpty"), disabled = function() return Off() or Def().small end },
        { type = "button", text = L["Position"], label = L["Reset"], width = 100,
          onClick = function() EV.Movers:Reset("AB_" .. selected) end })

    p:Section(L["Text on this bar"])
    p:Note(L["These sit on top of the switches on the Buttons tab: text shows only where both are on."], 0.7)
    p:Dual({ type = "toggle", text = L["Keybinds"], get = BG("showHotkey"), set = BS("showHotkey"), disabled = Off },
           { type = "toggle", text = L["Counts"], get = BG("showCount"), set = BS("showCount"), disabled = Off })
    p:Dual({ type = "toggle", text = L["Macro names"], get = BG("showMacro"), set = BS("showMacro"), disabled = Off }, nil)

    p:Section(L["Spell rank"])
    local rankOff = function() return Off() or not Bar().rankText end
    p:Dual({ type = "toggle", text = L["Show spell rank"],
             tooltip = L["The rank of the spell on each button, or of the spell a macro casts."],
             get = BG("rankText"), set = BS("rankText"), disabled = Off },
           { type = "dropdown", text = L["Format"], width = 130, values = RANK_FORMATS,
             get = BG("rankFormat"), set = BS("rankFormat"), disabled = rankOff })
    p:Dual({ type = "dropdown", text = L["Position"], width = 150, values = POINTS,
             get = BG("rankPoint"), set = BS("rankPoint"), disabled = rankOff },
           { type = "slider", text = L["Text size"], min = 6, max = 24, step = 1,
             get = BG("rankSize"), set = BS("rankSize"), disabled = rankOff })
    p:Dual({ type = "slider", text = L["Offset X"], min = -30, max = 30, step = 1,
             get = BG("rankX"), set = BS("rankX"), disabled = rankOff },
           { type = "slider", text = L["Offset Y"], min = -30, max = 30, step = 1,
             get = BG("rankY"), set = BS("rankY"), disabled = rankOff })
    p:Dual({ type = "colour", text = L["Colour"],
             get = function() local c = Bar().rankColour or RANK_DEFAULT; return c[1], c[2], c[3] end,
             set = function(r, g, b) Bar().rankColour = { r, g, b }; Apply() end,
             reset = function() Bar().rankColour = { RANK_DEFAULT[1], RANK_DEFAULT[2], RANK_DEFAULT[3] }; Apply() end,
             isCustom = function()
                 local c = Bar().rankColour or RANK_DEFAULT
                 return math.abs(c[1] - RANK_DEFAULT[1]) + math.abs(c[2] - RANK_DEFAULT[2]) + math.abs(c[3] - RANK_DEFAULT[3]) > 0.004
             end,
             disabled = rankOff },
           { type = "button", text = L["Same on every bar"], label = L["Copy"], width = 90,
             tooltip = L["Copies this bar's spell rank settings to all the other action bars."],
             onClick = function()
                 local src = Bar()
                 for _, def in ipairs(ns.BARS) do
                     if not def.small and def.key ~= selected then
                         local dst = ns.Bar(def.key)
                         for _, k in ipairs(RANK_KEYS) do
                             local v = src[k]
                             dst[k] = type(v) == "table" and { v[1], v[2], v[3] } or v
                         end
                     end
                 end
                 Apply()
             end, disabled = Off })

    p:Section(L["Visibility"])
    p:Dual(
        { type = "dropdown", text = L["Show"], width = 180, values = VIS,
          tooltip = L["Bars always step aside for pet battles and vehicles with their own bar."],
          get = BG("visibility"), set = BS("visibility"), disabled = Off },
        { type = "input", text = L["Custom conditions"], width = 220,
          placeholder = "[combat] show; hide",
          tooltip = L["Macro conditions, like [combat] show; hide or [mod:shift] show; hide. Applies when Show is Custom conditions."],
          get = BG("custom"), set = BS("custom"),
          disabled = function() return Off() or Bar().visibility ~= "custom" end })
    p:Dual(
        { type = "toggle", text = L["Fade out"], tooltip = L["Fades the bar while the mouse isn't over it."],
          get = BG("fade"), set = BS("fade"), disabled = Off },
        { type = "slider", text = L["Faded opacity"], min = 0, max = 100, step = 5,
          fmt = function(v) return v .. "%" end,
          get = function() return math.floor(Bar().fadeAlpha * 100 + 0.5) end,
          set = function(v) Bar().fadeAlpha = v / 100; Apply() end,
          disabled = function() return Off() or not Bar().fade end })
    p:Dual(
        { type = "toggle", text = L["Keep fading in combat"],
          tooltip = L["Off: the bar is always fully visible in combat."],
          get = BG("fadeInCombat"), set = BS("fadeInCombat"),
          disabled = function() return Off() or not Bar().fade end },
        { type = "dropdown", text = L["Fade with"], width = 130, values = FADE_GROUPS,
          tooltip = L["Bars in the same group fade in together: the mouse over any of them shows them all."],
          get = BG("fadeGroup"), set = BS("fadeGroup"),
          disabled = function() return Off() or not Bar().fade end })
end

--------------------------------------------------------------------------------
--  Paging
--------------------------------------------------------------------------------
local function PageList(none)
    local list = { { value = 0, text = none } }
    for i = 1, 10 do list[#list + 1] = { value = i, text = L["Page"] .. " " .. i } end
    return list
end

local function Paging(p)
    p:Section(L["Bar"])
    p:Dual(BarPicker(p, function(def) return not def.small end), nil)
    p:Note(L["Which page of actions this bar shows. Anything you leave alone stays as Blizzard has it, including the main bar's stance, form and stealth pages, and the main bar always hands over to vehicles and possession. Pages 7 to 10 are the ones Blizzard uses for forms and stances, so check a page is free before using it."], 0.75)

    local off = function() return Off() or (Bar().pageCustom or ""):find("%S") ~= nil end
    p:Section(L["Pages"])
    p:Dual(
        { type = "dropdown", text = L["Shows"], width = 160,
          values = PageList(Def().main and L["Blizzard's (1, forms)"] or L["Blizzard's page"]),
          get = BG("page"), set = BS("page"), disabled = Off }, nil)
    p:Dual(
        { type = "dropdown", text = L["While Alt is held"], width = 130, values = PageList(L["No change"]),
          get = BG("pageAlt"), set = BS("pageAlt"), disabled = off },
        { type = "dropdown", text = L["While Ctrl is held"], width = 130, values = PageList(L["No change"]),
          get = BG("pageCtrl"), set = BS("pageCtrl"), disabled = off })
    p:Dual(
        { type = "dropdown", text = L["While Shift is held"], width = 130, values = PageList(L["No change"]),
          get = BG("pageShift"), set = BS("pageShift"), disabled = off }, nil)

    p:Section(L["Your own conditions"])
    p:Row{ type = "input", text = L["Conditions"], width = 320,
           placeholder = "[mod:alt] 2; [stealth] 7",
           tooltip = L["Macro conditions ending in a page number, in the usual action bar format. They replace the modifier pages above. Anything that matches nothing falls back to the page chosen in Shows."],
           get = BG("pageCustom"), set = BS("pageCustom"), disabled = Off }
    local cond = ns.PageCondition(Def(), Bar())
    p:Note((L["In use: %s"]):format(cond or L["Blizzard's paging"]), 0.7)
end

--------------------------------------------------------------------------------
--  Buttons
--------------------------------------------------------------------------------
local function Buttons(p)
    local t = M.db.text
    local function G(k) return function() return t[k] end end
    local function S(k) return function(v) t[k] = v; Apply() end end
    p:Section(L["Text"])
    p:Dual({ type = "toggle", text = L["Keybinds"], get = G("hotkey"), set = S("hotkey") },
           { type = "slider", text = L["Keybind size"], min = 8, max = 20, step = 1, get = G("hotkeySize"), set = S("hotkeySize"),
             disabled = function() return not t.hotkey end })
    p:Dual({ type = "toggle", text = L["Short keybind names"],
             tooltip = L["S1 for Shift-1, CM4 for Ctrl and mouse button 4, WU for the wheel."],
             get = G("shortKeys"), set = S("shortKeys"), disabled = function() return not t.hotkey end }, nil)
    p:Dual({ type = "toggle", text = L["Charges and counts"], get = G("count"), set = S("count") },
           { type = "slider", text = L["Count size"], min = 8, max = 22, step = 1, get = G("countSize"), set = S("countSize"),
             disabled = function() return not t.count end })
    p:Dual({ type = "toggle", text = L["Reagent and ammo counts"], get = G("reagents"), set = S("reagents"),
             tooltip = L["Where Blizzard shows no count, shows how many casts your reagents cover, your ammo on Auto Shot and Shoot, and your stack on Throw."],
             disabled = function() return not t.count end }, nil)
    p:Dual({ type = "toggle", text = L["Macro names"], get = G("macro"), set = S("macro") },
           { type = "slider", text = L["Macro name size"], min = 8, max = 16, step = 1, get = G("macroSize"), set = S("macroSize"),
             disabled = function() return not t.macro end })

    local look = M.db.look
    p:Section(L["Feedback"])
    p:Dual({ type = "toggle", text = L["Red when out of range"],
             tooltip = L["The whole icon, not just the keybind. Blizzard's own blue for no mana and grey for unusable still apply."],
             get = function() return look.rangeTint end, set = function(v) look.rangeTint = v; Apply() end },
           { type = "toggle", text = L["Edge on equipped items"],
             get = function() return look.equipped end, set = function(v) look.equipped = v; Apply() end })
    if Game.HasCVar("countdownForCooldowns") then
        p:Dual({ type = "toggle", text = L["Cooldown numbers"],
                 tooltip = L["The game's own setting: seconds left, written on the cooldown swipe."],
                 get = function() return Game.GetCVarBool("countdownForCooldowns") end,
                 set = function(v) Game.SetCVarBool("countdownForCooldowns", v) end }, nil)
    end
end

--------------------------------------------------------------------------------
--  Casting
--------------------------------------------------------------------------------
local MODKEYS = {
    { value = "NONE", text = L["None"] },
    { value = "ALT", text = "Alt" }, { value = "CTRL", text = "Ctrl" }, { value = "SHIFT", text = "Shift" },
}

local function Casting(p)
    p:Section(L["Keybinds"])
    p:Dual({ type = "button", text = L["Keybind mode"], label = L["Start"], width = 110,
             tooltip = L["Hover a button and press a key. Also /evui kb."],
             onClick = function() EV.Options:Toggle(); ns.Keybind.Start() end },
           { type = "toggle", text = L["Save for this character only"],
             get = function() return M.db.behaviour.bindPerCharacter end,
             set = function(v) M.db.behaviour.bindPerCharacter = v end })

    p:Section(L["Casting on yourself"])
    p:Dual({ type = "toggle", text = L["Right click casts on me"],
             tooltip = L["Right clicking any action button casts its spell on yourself. Handy for buffs and heals."],
             get = function() return M.db.behaviour.rightClickSelf end,
             set = function(v) M.db.behaviour.rightClickSelf = v; Apply() end }, nil)

    p:Section(L["The game's own settings"])
    p:Note(L["These are the game's settings rather than EvermoreUI's. They apply with or without the addon."], 0.7)
    if Game.Has("GetModifiedClick") then
        p:Dual({ type = "dropdown", text = L["Self cast key"], width = 110, values = MODKEYS,
                 tooltip = L["Hold it to cast a spell on yourself whatever you have targeted."],
                 get = function() return Game.GetClickMod("SELFCAST") or "NONE" end,
                 set = function(v) Game.SetClickMod("SELFCAST", v) end },
               { type = "dropdown", text = L["Focus cast key"], width = 110, values = MODKEYS,
                 tooltip = L["Hold it to cast a spell on your focus."],
                 get = function() return Game.GetClickMod("FOCUSCAST") or "NONE" end,
                 set = function(v) Game.SetClickMod("FOCUSCAST", v) end })
    end
    if Game.HasCVar("autoSelfCast") then
        p:Dual({ type = "toggle", text = L["Auto self cast"],
                 tooltip = L["A helpful spell with no friendly target goes on you."],
                 get = function() return Game.GetCVarBool("autoSelfCast") end,
                 set = function(v) Game.SetCVarBool("autoSelfCast", v) end }, nil)
    end
    if Game.HasCVar("lockActionBars") then
        p:Dual({ type = "toggle", text = L["Lock action buttons"],
                 tooltip = L["Spells can't be dragged off the bars by accident. Hold the pick up key to move them."],
                 get = function() return Game.GetCVarBool("lockActionBars") end,
                 set = function(v) Game.SetCVarBool("lockActionBars", v) end },
               Game.Has("GetModifiedClick") and { type = "dropdown", text = L["Pick up key"], width = 110, values = MODKEYS,
                 get = function() return Game.GetClickMod("PICKUPACTION") or "NONE" end,
                 set = function(v) Game.SetClickMod("PICKUPACTION", v) end } or nil)
    end
    local cells = {}
    if Game.HasCVar("SpellQueueWindow") then
        cells[#cells + 1] = { type = "slider", text = L["Spell queue window"], min = 0, max = 400, step = 10,
            fmt = function(v) return v .. " ms" end,
            tooltip = L["How early you can press your next spell and have it queue. Higher is more forgiving; very high can make a spell you changed your mind about go off anyway."],
            get = function() return tonumber(GetCVar("SpellQueueWindow")) or 400 end,
            set = function(v) pcall(SetCVar, "SpellQueueWindow", v) end }
    end
    if Game.HasCVar("ActionButtonUseKeyDown") then
        cells[#cells + 1] = { type = "toggle", text = L["Cast on key press"],
            tooltip = L["Buttons fire when the key goes down rather than when it comes back up."],
            get = function() return Game.GetCVarBool("ActionButtonUseKeyDown") end,
            set = function(v) Game.SetCVarBool("ActionButtonUseKeyDown", v) end }
    end
    if #cells > 0 then p:Dual(cells[1], cells[2]) end
end

--------------------------------------------------------------------------------
--  Modifier actions
--------------------------------------------------------------------------------
local draft = { bar = "main", index = 1, mod = "alt", button = 1, kind = "self", value = "" }

local function TextOf(list, v)
    for _, e in ipairs(list) do if e.value == v then return e.text end end
    return tostring(v)
end

local function Describe(a)
    local def = ns.BY_KEY[a.bar]
    local what = TextOf(ns.ACTION_KINDS, a.kind)
    if a.kind == "spell" or a.kind == "item" or a.kind == "macro" then what = what .. ": " .. (a.value or "") end
    return ("%s, %s %d: %s + %s = %s"):format(def and def.label or a.bar, L["button"], a.index,
        TextOf(ns.ACTION_MODS, a.mod), TextOf(ns.ACTION_BUTTONS, a.button), what)
end

local function Actions(p)
    p:Note(L["Give a button a second job behind a modifier. Alt + left click on button 3 can cast a different spell, or cast button 3's own spell on you. It works for the button's keybind too: with Alt held, the key does the Alt action, as long as Alt plus that key isn't bound to something else."], 0.75)

    p:Section(L["Your actions"])
    if #M.db.actions == 0 then
        p:Note(L["None yet."], 0.6)
    end
    for i, a in ipairs(M.db.actions) do
        p:Row{ type = "button", text = Describe(a), label = L["Remove"], width = 90,
               onClick = function()
                   table.remove(M.db.actions, i)
                   Apply()
                   EV.Options:Rebuild()
               end }
    end

    p:Section(L["Add one"])
    local bars = {}
    for _, def in ipairs(ns.BARS) do
        if not def.small then bars[#bars + 1] = { value = def.key, text = def.label } end
    end
    local function DG(k) return function() return draft[k] end end
    local function DS(k) return function(v) draft[k] = v; EV.Options:RefreshCurrent() end end
    p:Dual({ type = "dropdown", text = L["Bar"], width = 160, values = bars, get = DG("bar"), set = DS("bar") },
           { type = "slider", text = L["Button"], min = 1, max = 12, step = 1, get = DG("index"), set = DS("index") })
    p:Dual({ type = "dropdown", text = L["Modifier"], width = 130, values = ns.ACTION_MODS, get = DG("mod"), set = DS("mod") },
           { type = "dropdown", text = L["Click"], width = 130, values = ns.ACTION_BUTTONS, get = DG("button"), set = DS("button") })
    local needsValue = function() return not (draft.kind == "spell" or draft.kind == "item" or draft.kind == "macro") end
    p:Dual({ type = "dropdown", text = L["Does"], width = 190, values = ns.ACTION_KINDS, get = DG("kind"), set = DS("kind") },
           { type = "input", text = L["Name"], width = 180, placeholder = L["Spell, item or macro name"],
             get = DG("value"), set = function(v) draft.value = v end, disabled = needsValue })
    p:Row{ type = "button", text = L["Add this action"], label = L["Add"], width = 90,
           onClick = function()
               local a = { bar = draft.bar, index = draft.index, mod = draft.mod, button = draft.button,
                           kind = draft.kind, value = draft.value }
               if not ns.ValidAction(a) or not ns.ActionAttributes(a) then
                   EV:Print(L["That action needs a name."])
                   return
               end
               -- One action per button, modifier and click: a new one replaces.
               for i = #M.db.actions, 1, -1 do
                   local o = M.db.actions[i]
                   if o.bar == a.bar and o.index == a.index and o.mod == a.mod and o.button == a.button then
                       table.remove(M.db.actions, i)
                   end
               end
               M.db.actions[#M.db.actions + 1] = a
               draft.value = ""
               Apply()
               EV.Options:Rebuild()
           end }
end

--------------------------------------------------------------------------------
--  General
--------------------------------------------------------------------------------
local function General(p)
    p:Section(L["How this works"])
    p:Note(L["Your action buttons are still Blizzard's, so paging, keybinds, casting and drag and drop are Blizzard's too. EvermoreUI places, sizes and styles them, and Blizzard's Edit Mode no longer moves them."], 0.75)
    p:Section(L["General"])
    p:Dual(
        { type = "button", text = L["Move bars"], label = L["Edit mode"], width = 120,
          onClick = function() EV.Movers:Unlock() end },
        { type = "toggle", text = L["Note in Blizzard's Edit Mode"],
          tooltip = L["A reminder in chat, once per session, that action bars move with /evui edit."],
          get = function() return M.db.editModeNote end,
          set = function(v) M.db.editModeNote = v end })
    p:Row{ type = "button", text = L["Start again from Blizzard's layout"], label = L["Reset"], width = 100,
           tooltip = L["Copies Blizzard's bar layout and positions again after a reload."],
           onClick = function()
               M.db.genesis = false
               for _, def in ipairs(ns.BARS) do EV.DB:GetCore().movers["AB_" .. def.key] = nil end
               EV.Options:MarkReloadNeeded()
           end }
end

EV.Options:RegisterPage{
    key = "actionbars", title = L["Action Bars"], group = "Combat", module = "ActionBars",
    description = L["Blizzard's action buttons in EvermoreUI bars, placed with /evui edit."],
    tabs = { TAB_BARS, TAB_PAGING, TAB_BUTTONS, TAB_CASTING, TAB_ACTIONS, TAB_GENERAL },
    build = function(p, tab)
        if tab == TAB_PAGING then return Paging(p) end
        if tab == TAB_BUTTONS then return Buttons(p) end
        if tab == TAB_CASTING then return Casting(p) end
        if tab == TAB_ACTIONS then return Actions(p) end
        if tab == TAB_GENERAL then return General(p) end
        return Bars(p)
    end,
    onReset = function(tab)
        local d = M.defaults
        if tab == TAB_BUTTONS then
            wipe(M.db.text); EV.DB.Merge(M.db.text, d.text)
            wipe(M.db.look); EV.DB.Merge(M.db.look, d.look)
        elseif tab == TAB_PAGING then
            local b, db = M.db.bars[selected], d.bars[selected]
            for _, k in ipairs({ "page", "pageAlt", "pageCtrl", "pageShift", "pageCustom" }) do b[k] = db[k] end
        elseif tab == TAB_BARS then
            wipe(M.db.bars[selected]); EV.DB.Merge(M.db.bars[selected], d.bars[selected])
        elseif tab == TAB_CASTING then
            wipe(M.db.behaviour); EV.DB.Merge(M.db.behaviour, d.behaviour)
        elseif tab == TAB_ACTIONS then
            wipe(M.db.actions)
        end
        Apply()
    end,
}
