--------------------------------------------------------------------------------
--  tools/looks/audit.lua
--  Runs the palette contrast audit and the control Looks audit outside the
--  game, the same checks as /evui theme audit. Run from the repo root:
--
--      lua5.1 tools/looks/audit.lua
--
--  tools/check.py runs it when lua5.1 is on the PATH (CI installs it). Exits
--  non-zero on any failure.
--------------------------------------------------------------------------------
EV_BLOCKED = false
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc() end
local function Stub()
    return setmetatable({}, { __index = function() return function() end end })
end
function CreateFrame() return Stub() end
GameTooltip = Stub()
EvermoreUI = { Media = { Fetch = function() return "" end, FetchBold = function() return "" end } }

local function Load(path)
    local f = assert(loadfile(path))
    f("EvermoreUI", {})
end
Load("EvermoreUI/Core/Theme.lua")
Load("EvermoreUI/Core/Looks.lua")

local T = EvermoreUI.Theme
local bad = 0
for _, mode in ipairs({ "standard", "high" }) do
    for _, line in ipairs(T.Audit(mode)) do print(mode .. " palette: " .. line); bad = bad + 1 end
    for _, line in ipairs(T.AuditLooks(mode)) do print(mode .. " " .. line); bad = bad + 1 end
end
print(bad == 0 and "looks audit: all pass" or ("looks audit: %d failure(s)"):format(bad))
os.exit(bad == 0 and 0 or 1)
