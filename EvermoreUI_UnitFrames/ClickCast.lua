if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  ClickCast.lua
--  Click casting on our unit frames: Shift + left click on the player,
--  target, focus, pet, target of target, party or raid frames casts a spell
--  on that unit.
--
--  Our frames are SecureUnitButtonTemplate buttons, and their OnClick
--  (SecureUnitButton_OnClick) reads secure attributes with the modifiers
--  folded in: "shift-type1" and "shift-spell1" beat "*type1" (target) while
--  Shift is held. So a binding is two attributes on each frame, set out of
--  combat, and after that it works in combat with no code of ours running.
--  Forever also has Blizzard's own click binding system (C_ClickBindings),
--  which these frames honour first; its setter is restricted to Blizzard's
--  window, so ours is separate and the two can be used side by side.
--
--  Bindings: { mod = "shift", button = 1, kind = "spell", value = "Flash Heal" }
--  mod "" is an unmodified click, which replaces targeting (left) or the
--  menu (right) for that button.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

ns.CLICK_MODS = {
    { value = "",                text = L["No modifier"] },
    { value = "shift",           text = "Shift" },
    { value = "ctrl",            text = "Ctrl" },
    { value = "alt",             text = "Alt" },
    { value = "ctrl-shift",      text = "Ctrl+Shift" },
    { value = "alt-shift",       text = "Alt+Shift" },
    { value = "alt-ctrl",        text = "Alt+Ctrl" },
}
ns.CLICK_BUTTONS = {
    { value = 1, text = L["Left click"] },
    { value = 2, text = L["Right click"] },
    { value = 3, text = L["Middle click"] },
    { value = 4, text = L["Mouse button 4"] },
    { value = 5, text = L["Mouse button 5"] },
}
ns.CLICK_KINDS = {
    { value = "spell",  text = L["Cast a spell"] },
    { value = "macro",  text = L["Run a macro"] },
    { value = "target", text = L["Target"] },
    { value = "focus",  text = L["Set focus"] },
    { value = "assist", text = L["Assist"] },
    { value = "menu",   text = L["Open the menu"] },
}

local VALID_MOD, VALID_KIND = {}, {}
for _, m in ipairs(ns.CLICK_MODS) do VALID_MOD[m.value] = true end
for _, k in ipairs(ns.CLICK_KINDS) do VALID_KIND[k.value] = true end

function ns.ValidClick(c)
    return type(c) == "table" and VALID_MOD[c.mod] and VALID_KIND[c.kind]
        and type(c.button) == "number" and c.button >= 1 and c.button <= 5
        and (c.kind ~= "spell" and c.kind ~= "macro" or (type(c.value) == "string" and c.value:find("%S")))
end

local function Attributes(c)
    local prefix = c.mod ~= "" and (c.mod .. "-") or ""
    local sfx = tostring(c.button)
    local out = {}
    if c.kind == "menu" then
        out[prefix .. "type" .. sfx] = "togglemenu"
    else
        out[prefix .. "type" .. sfx] = c.kind
    end
    if c.kind == "spell" or c.kind == "macro" then
        out[prefix .. c.kind .. sfx] = strtrim(c.value)
    end
    return out
end

local pending = false

--- Put the bindings on every frame (out of combat; waits otherwise).
function ns.ApplyClickCast()
    local M = ns.module
    local frames = ns.frames or {}
    if not M then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local cfg = M.db.clickCast
    local set = {}
    if cfg and cfg.enabled then
        for _, c in ipairs(cfg.binds) do
            if ns.ValidClick(c) then
                for k, v in pairs(Attributes(c)) do set[k] = v end
            end
        end
    end
    local all = {}
    for _, f in pairs(frames) do all[#all + 1] = f end
    if ns.group and ns.group.Children then
        for _, f in ipairs(ns.group.Children()) do all[#all + 1] = f end
    end
    for _, f in ipairs(all) do
        if f.evClick then
            for name in pairs(f.evClick) do f:SetAttribute(name, nil) end
        end
        -- The frame's own defaults, which an unmodified binding may replace.
        f:SetAttribute("*type1", "target")
        f:SetAttribute("*type2", "togglemenu")
        for name, v in pairs(set) do f:SetAttribute(name, v) end
        f.evClick = next(set) and CopyTable(set) or nil
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if pending then ns.ApplyClickCast() end
end)

--- Whether Blizzard's own click casting window can be opened here.
function ns.HasBlizzardClickBinding()
    return type(ToggleClickBindingFrame) == "function" and C_ClickBindings ~= nil
end
