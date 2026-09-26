if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Init.lua
--  Namespace, colours, strings and small helpers shared by the whole suite.
--------------------------------------------------------------------------------
local ADDON_NAME = ...
local EV = EvermoreUI

EV.name = ADDON_NAME

local v = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
if v:find("^@") then v = "dev" end
EV.version = v

-- Brand accent before the theme loads (the theme's copper accent after)
EV.ACCENT     = { r = 0.831, g = 0.573, b = 0.306 }
EV.ACCENT_HEX = "d4924e"

-- Child addons drop their private namespace here so the LoadOnDemand
-- options addon can reach module internals without leaking globals.
EV._ModuleNS = EV._ModuleNS or {}

-- String table. enGB only for now; every user-facing string goes through L
-- so localisation later is a data job, not a refactor.
EV.L = setmetatable({}, { __index = function(_, k) return k end })

function EV:Print(...)
    print("|cff" .. ((self.Theme and self.Theme.Hex and self.Theme.Hex("accent")) or self.ACCENT_HEX) .. "EvermoreUI|r:", ...)
end

function EV:Colour(text, hex)
    return "|cff" .. (hex or (self.Theme and self.Theme.Hex and self.Theme.Hex("accent")) or self.ACCENT_HEX) .. tostring(text) .. "|r"
end

--- Is this a "secret" value the client is withholding?
---
--- Blizzard hands back secret numbers for information it is restricting: a
--- targettarget's class colour inside an instance, the player's run speed
--- under some restrictions, a restricted unit's health. Two rules govern
--- them, and getting either wrong throws with OUR addon named, because our
--- execution is already tainted:
---
---   1. A secret can be PASSED to the API. SetStatusBarColor is perfectly
---      happy with one. Only ARITHMETIC on it throws.
---   2. Comparison throws. `== 0` on a secret speed is what took down the
---      minimap's coordinate ticker 162 times in a few minutes.
---
--- Values.lua's note adds that comparing one even against nil can error,
--- which is why this is not written `v ~= nil and issecretvalue(v)`: that
--- compares before it tests. Unverified by us either way, and checking with
--- type() costs nothing and cannot be wrong, so that is what we do.
---
--- One implementation, here, in the file that loads second. The suite had
--- nine, and most had one of those two faults.
function EV.IsSecret(v)
    return issecretvalue ~= nil and type(v) ~= "nil" and issecretvalue(v)
end

--- Present, and safe to compare or do arithmetic on.
function EV.Usable(v)
    return type(v) ~= "nil" and not EV.IsSecret(v)
end

-- Deep copy a plain data table (no metatables, no cycles).
function EV.CopyTable(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, val in pairs(src) do
        t[k] = EV.CopyTable(val)
    end
    return t
end

-- Thousands separator for display ("12,345").
function EV.FormatNumber(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local sign, int = s:match("^(-?)(%d+)$")
    if not int then return s end
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. int
end
