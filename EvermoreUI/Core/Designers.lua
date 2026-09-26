if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Designers.lua
--  The registry the designer window reads. The window itself lives in
--  EvermoreUI_Options (Designer.lua), which loads on demand; modules register
--  their surfaces here at load, so the list is complete whenever the window
--  opens.
--
--  A surface is one thing you can design (Unit Frames, Nameplates, the
--  Cooldown Manager's order). Its shape is written out in full at the top of
--  EvermoreUI_Options/Designer.lua, next to the code that uses it.
--
--  /evui design [surface]  opens it (unitframes, nameplates, cooldowns).
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local D = { surfaces = {}, order = {} }
EV.Designers = D

function D:Register(def)
    assert(type(def) == "table" and type(def.key) == "string", "designer surface needs a key")
    if not self.surfaces[def.key] then self.order[#self.order + 1] = def.key end
    self.surfaces[def.key] = def
    return def
end

function D:Get(key) return self.surfaces[key] end

--- Surfaces whose module is on, in registration order.
function D:List()
    local list = {}
    for _, key in ipairs(self.order) do
        local s = self.surfaces[key]
        local mod = s.module and EV:GetModule(s.module, true)
        if not s.module or (mod and mod:IsEnabled()) then list[#list + 1] = s end
    end
    return list
end

--- Open the designer on a surface (and optionally one of its tabs).
function D:Open(key, tab)
    if InCombatLockdown() then EV:Print(L["The designer is available out of combat."]) return end
    if not C_AddOns.IsAddOnLoaded("EvermoreUI_Options") then
        local ok, reason = C_AddOns.LoadAddOn("EvermoreUI_Options")
        if not ok then EV:Print(L["Couldn't load EvermoreUI_Options:"], tostring(reason)) return end
    end
    if EV.DesignerUI then EV.DesignerUI:Open(key, tab) end
end

-- Short names for /evui design: a word opens its surface (and tab).
local ALIASES = {
    uf = { "unitframes" }, frames = { "unitframes" },
    np = { "nameplates" }, plates = { "nameplates" },
    cd = { "cooldowns" }, cdm = { "cooldowns" },
    party = { "groupframes", "party" }, raid = { "groupframes", "raid" }, group = { "groupframes" },
}

EV:RegisterSlash("design", function(rest)
    rest = (rest or ""):lower():match("^%s*(.-)%s*$")
    local alias = ALIASES[rest]
    if alias then D:Open(alias[1], alias[2]) return end
    D:Open(rest ~= "" and rest or nil)
end)
EV:RegisterSlash("designer", function(rest) D:Open(rest ~= "" and rest:lower() or nil) end)
