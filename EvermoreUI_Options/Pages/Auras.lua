if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Auras: Buffs and Debuffs tabs.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Auras", true)
if not M then return end
local ns = EV._ModuleNS["EvermoreUI_Auras"]

local TAB_BUFFS, TAB_DEBUFFS = L["Buffs"], L["Debuffs"]

local GROW_X = { { value = "LEFT", text = L["Left"] }, { value = "RIGHT", text = L["Right"] } }
local GROW_Y = { { value = "DOWN", text = L["Down"] }, { value = "UP", text = L["Up"] } }
local SORTS  = { { value = "default", text = L["Blizzard order"] }, { value = "time", text = L["Time left"] } }

local function Supported() return ns and ns.Container and ns.Container.Supported() end

--------------------------------------------------------------------------------
--  Shared layout section (buffs and debuffs)
--------------------------------------------------------------------------------
local function LayoutRows(p, cfgFn, off)
    local function Get(k) return function() local c = cfgFn(); return c and c[k] end end
    local function Set(k) return function(v) local c = cfgFn(); if c then c[k] = v; M:Rebuild() end end end
    local function S(k, text, lo, hi, tip)
        return { type = "slider", text = text, min = lo, max = hi, step = 1, tooltip = tip,
                 get = Get(k), set = Set(k), disabled = off }
    end
    local function D(k, text, values, w)
        return { type = "dropdown", text = text, values = values, width = w or 120,
                 get = Get(k), set = Set(k), disabled = off }
    end
    local function T(k, text, tip)
        return { type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k), disabled = off }
    end

    p:Section(L["Layout"])
    p:Dual(S("size", L["Icon size"], 16, 80), S("spacing", L["Spacing"], 0, 20))
    p:Dual(S("perRow", L["Icons per row"], 1, 40), S("max", L["Most icons shown"], 1, 40))
    p:Dual(D("growX", L["Grow"], GROW_X), D("growY", L["Then wrap"], GROW_Y))
    p:Section(L["Timers"])
    p:Dual(T("showSwipe", L["Cooldown swipe"]), T("showTimer", L["Time left text"]))
    p:Dual(S("timerSize", L["Timer text size"], 8, 24), D("sort", L["Order"], SORTS, 150))
end

local function Unsupported(p)
    p:Note(L["This client doesn't provide Blizzard's aura containers (needs the 12.1 addon API), so EvermoreUI leaves buffs to Blizzard for now."])
end

--------------------------------------------------------------------------------
--  Buffs / Debuffs
--------------------------------------------------------------------------------
local function BuildGrid(p, which)
    if not Supported() then return Unsupported(p) end
    local function cfg() return M.db[which] end
    local function Off() return not cfg().enabled end
    local isBuffs = which == "buffs"

    p:Section(L["General"])
    p:Dual(
        { type = "toggle", text = isBuffs and L["Show my buffs"] or L["Show my debuffs"],
          get = function() return cfg().enabled end,
          set = function(v) cfg().enabled = v; M:Rebuild() end },
        { type = "toggle", text = L["Hide Blizzard's"], disabled = Off,
          tooltip = L["Hides Blizzard's own buff frames. Bringing them back needs a reload."],
          get = function() return cfg().hideBlizzard end,
          set = function(v) cfg().hideBlizzard = v; if not v then EV.Options:MarkReloadNeeded() end; M:Rebuild() end })
    if isBuffs then
        p:Dual(
            { type = "toggle", text = L["Right-click to cancel"], disabled = Off,
              get = function() return cfg().cancel end, set = function(v) cfg().cancel = v; M:Rebuild() end },
            { type = "toggle", text = L["Tooltips"], disabled = Off,
              get = function() return cfg().tooltip end, set = function(v) cfg().tooltip = v; M:Rebuild() end })
    else
        p:Row({ type = "toggle", text = L["Tooltips"], disabled = Off,
                get = function() return cfg().tooltip end, set = function(v) cfg().tooltip = v; M:Rebuild() end })
    end
    LayoutRows(p, cfg, Off)
end

EV.Options:RegisterPage{
    key = "auras", title = L["Buffs & Debuffs"], group = "Combat", module = "Auras",
    description = L["Move your buffs and debuffs. To keep an eye on particular auras in your HUD, use Combat > Cooldowns."],
    tabs = { TAB_BUFFS, TAB_DEBUFFS },
    build = function(p, tab)
        BuildGrid(p, tab == TAB_DEBUFFS and "debuffs" or "buffs")
    end,
    onReset = function(tab)
        local key = tab == TAB_DEBUFFS and "debuffs" or "buffs"
        wipe(M.db[key])
        EV.DB.Merge(M.db[key], M.defaults[key])
        M:Rebuild()
        EV.Options:Rebuild()
    end,
}
