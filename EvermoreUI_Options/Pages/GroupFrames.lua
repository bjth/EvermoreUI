if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Party & Raid: everything is set in the designer, with the part it belongs
--  to. This page is the way in, one tab per kind.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("GroupFrames", true)
if not M then return end

local TAB_PARTY, TAB_RAID = L["Party"], L["Raid"]

EV.Options:RegisterPage{
    key = "groupframes", title = L["Party & Raid"], group = "Combat", module = "GroupFrames",
    description = L["Party and raid frames in the style of your unit frames, laid out by the game's own group headers so they keep up in combat. Click casting works on them too."],
    tabs = { TAB_PARTY, TAB_RAID },
    build = function(p, tab)
        local kind = tab == TAB_RAID and "raid" or "party"
        p:Banner(L["Party and raid frames are set up in the designer, on a sample group: pick a part of the first frame to change how it looks and where it sits, or the rest of the group for the layout and order."],
                 L["Open designer"], function() EV.Designers:Open("groupframes", kind) end)
        p:Note(L["Also /evui design. Where the frames sit on your screen is edit mode: /evui edit."])
    end,
}
