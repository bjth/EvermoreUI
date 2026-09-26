if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Nameplates: everything is set in the designer, with the part it belongs
--  to. This page is the way in.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Nameplates", true)
if not M then return end

EV.Options:RegisterPage{
    key = "nameplates", title = L["Nameplates"], group = "Combat",
    module = "Nameplates",
    description = L["Our own nameplates on Blizzard's: health, cast, your dots with their timers, threat colouring and target highlighting. Targeting stays Blizzard's throughout."],
    build = function(p)
        p:Banner(L["Nameplates are set up in the designer: pick a part of the plate to change how it looks and where it sits. Threat, target highlighting and how plates move are under Plate behaviour in its list."],
                 L["Open designer"], function() EV.Designers:Open("nameplates") end)
        p:Note(L["Also /evui design nameplates."])
    end,
}
