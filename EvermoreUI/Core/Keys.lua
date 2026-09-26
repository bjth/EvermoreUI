if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Keys.lua
--  Short keybind text, shared by the action bars and the cooldown bars:
--  modifiers as single letters, mouse buttons as M4, the wheel as WU / WD,
--  the number pad as N. EV.ShortKey("SHIFT-BUTTON4") -> "SM4".
--------------------------------------------------------------------------------
local EV = EvermoreUI

local MODS = { ALT = "A", CTRL = "C", SHIFT = "S", META = "M" }
local KEYS = {
    MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD", MIDDLEMOUSE = "M3",
    SPACE = "Sp", BACKSPACE = "Bs", ESCAPE = "Esc", CAPSLOCK = "Caps",
    INSERT = "Ins", DELETE = "Del", HOME = "Hm", END = "End",
    PAGEUP = "PU", PAGEDOWN = "PD", ENTER = "Ent", TAB = "Tab",
    UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
    NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*",
    NUMPADDIVIDE = "N/", NUMPADDECIMAL = "N.",
}

function EV.ShortKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    local parts = { strsplit("-", key) }
    local base = table.remove(parts)
    if base == "" and #parts > 0 then base = "-"; table.remove(parts) end   -- the minus key
    local out = ""
    for _, m in ipairs(parts) do out = out .. (MODS[m] or m:sub(1, 1)) end
    local k = KEYS[base]
        or base:match("^BUTTON(%d+)$") and ("M" .. base:match("^BUTTON(%d+)$"))
        or base:match("^NUMPAD(%d)$") and ("N" .. base:match("^NUMPAD(%d)$"))
        or base
    return out .. k
end

