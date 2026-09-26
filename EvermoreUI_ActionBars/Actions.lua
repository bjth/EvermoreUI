if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Actions.lua
--  Extra actions on a button behind a modifier: Alt+click button 3 casts
--  something else, or casts button 3's own spell on you. Plus right-click
--  self cast for every button.
--
--  All of it is secure attributes on Blizzard's buttons, read by
--  SecureActionButton_OnClick through SecureButton_GetModifiedAttribute:
--  "alt-type1" beats "type1" while Alt is held and the left button (or the
--  button's keybind) is pressed. A keybind counts too: with nothing bound to
--  ALT-1 the game runs the 1 binding with Alt still held, so the modified
--  attribute applies. Attributes can only be set out of combat and they
--  stay put, so everything here works in combat once it is set.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end

ns.ACTION_MODS = {
    { value = "alt",             text = "Alt" },
    { value = "ctrl",            text = "Ctrl" },
    { value = "shift",           text = "Shift" },
    { value = "alt-ctrl",        text = "Alt+Ctrl" },
    { value = "alt-shift",       text = "Alt+Shift" },
    { value = "ctrl-shift",      text = "Ctrl+Shift" },
}
ns.ACTION_BUTTONS = {
    { value = 1, text = EvermoreUI.L["Left click"] },
    { value = 2, text = EvermoreUI.L["Right click"] },
}
ns.ACTION_KINDS = {
    { value = "self",  text = EvermoreUI.L["This button, on me"] },
    { value = "focus", text = EvermoreUI.L["This button, on my focus"] },
    { value = "spell", text = EvermoreUI.L["A spell"] },
    { value = "item",  text = EvermoreUI.L["An item"] },
    { value = "macro", text = EvermoreUI.L["A macro"] },
}

local VALID_MOD, VALID_KIND = {}, {}
for _, m in ipairs(ns.ACTION_MODS) do VALID_MOD[m.value] = true end
for _, k in ipairs(ns.ACTION_KINDS) do VALID_KIND[k.value] = true end

--- The attributes one action sets, as name -> value.
local function Attributes(a)
    local prefix = a.mod .. "-"
    local sfx = tostring(a.button)
    if a.kind == "self" then
        return { [prefix .. "unit" .. sfx] = "player" }
    elseif a.kind == "focus" then
        return { [prefix .. "unit" .. sfx] = "focus" }
    elseif a.kind == "spell" or a.kind == "item" or a.kind == "macro" then
        if type(a.value) ~= "string" or not a.value:find("%S") then return nil end
        return { [prefix .. "type" .. sfx] = a.kind, [prefix .. a.kind .. sfx] = strtrim(a.value) }
    end
end
ns.ActionAttributes = Attributes

function ns.ValidAction(a)
    return type(a) == "table" and VALID_MOD[a.mod] and (a.button == 1 or a.button == 2)
        and VALID_KIND[a.kind] and ns.BY_KEY[a.bar] and type(a.index) == "number"
end

--- Clear what we set before, then set this bar's actions and the
--- right-click self cast (out of combat; Layout calls this).
function ns.ApplyActions(def)
    local selfCast = M.db.behaviour.rightClickSelf and not def.small
    for i, b in ipairs(ns.Buttons(def)) do
        if b.evAttrs then
            for name in pairs(b.evAttrs) do b:SetAttribute(name, nil) end
        end
        local set = {}
        if selfCast then set["*unit2"] = "player" end
        if not def.small then
            for _, a in ipairs(M.db.actions) do
                if ns.ValidAction(a) and a.bar == def.key and a.index == i then
                    local attrs = Attributes(a)
                    if attrs then for k, v in pairs(attrs) do set[k] = v end end
                end
            end
        end
        for name, v in pairs(set) do b:SetAttribute(name, v) end
        b.evAttrs = next(set) and set or nil
    end
end

--------------------------------------------------------------------------------
--  The game's own casting settings, for the options page. None of these
--  are EvermoreUI settings: they live in the game's key bindings and CVars.
--------------------------------------------------------------------------------
local G = {}
ns.Game = G

function G.Has(fn) return type(_G[fn]) == "function" end

function G.GetClickMod(action)
    if not G.Has("GetModifiedClick") then return nil end
    local ok, v = pcall(GetModifiedClick, action)
    return ok and v or nil
end

function G.SetClickMod(action, key)
    if InCombatLockdown() or not G.Has("SetModifiedClick") then return end
    pcall(SetModifiedClick, action, key)
    if G.Has("SaveBindings") and G.Has("GetCurrentBindingSet") then
        pcall(SaveBindings, GetCurrentBindingSet())
    end
end

function G.GetCVarBool(name)
    local v = GetCVar and GetCVar(name)
    return v == "1"
end

function G.HasCVar(name)
    if C_CVar and C_CVar.GetCVarInfo then
        local ok, v = pcall(C_CVar.GetCVarInfo, name)
        return ok and v ~= nil
    end
    return GetCVar and GetCVar(name) ~= nil
end

function G.SetCVarBool(name, on)
    if InCombatLockdown() then return end
    pcall(SetCVar, name, on and "1" or "0")
end
