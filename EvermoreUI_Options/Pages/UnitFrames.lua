if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Unit Frames: everything is set in the designer, with the part it belongs
--  to. This page is the way in, one tab per unit.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("UnitFrames", true)
if not M then return end

local TABS, KEY_FOR_TAB = {}, {}
for _, u in ipairs(M.UNITS) do
    local title = L[u.title]
    TABS[#TABS + 1] = title
    KEY_FOR_TAB[title] = u.key
end

EV.Options:RegisterPage{
    key = "unitframes", title = L["Unit Frames"], group = "Combat", module = "UnitFrames",
    description = L["Player, target, target of target, focus and pet. Clean bars, your layout."],
    tabs = TABS,
    build = function(p, tab)
        local key = KEY_FOR_TAB[tab]
        p:Banner(L["Unit frames are set up in the designer: pick a part of the frame to change how it looks and where it sits. Everything about the frame as a whole (size, colours, fading, the aggro glow) is under Frame in its list."],
                 L["Open designer"], function() EV.Designers:Open("unitframes", key) end)
        p:Note(L["Also /evui design. Where the frame sits on your screen is edit mode: /evui edit."])
    end,
}
