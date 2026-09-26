if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Cooldowns: everything is set in the designer, with the bar or cooldown it
--  belongs to. This page is the way in.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Cooldowns", true)
if not M then return end

EV.Options:RegisterPage{
    key = "cooldowns", title = L["Cooldowns"], group = "Combat", module = "Cooldowns",
    description = L["Your cooldowns and the buffs they leave, in EvermoreUI bars. The game's own Cooldown Manager does the tracking, so it keeps working in combat; these bars decide how it looks and where it sits."],
    build = function(p)
        if M:IsEnabled() and M.Problem then
            local problem = M.Problem(M.BARS[1])
            if problem and not M.BlizzardOn() then
                p:Banner(problem, L["Switch it on"], function() M.SetBlizzardOn(true); EV.Options:Rebuild() end)
            elseif problem then
                p:Banner(problem)
            end
        end
        p:Banner(L["Cooldowns are set up in the designer. Drag icons to arrange your bars, click a bar for its size, layout and text, or click a cooldown to give it a linked timer."],
                 L["Open designer"], function() EV.Designers:Open("cooldowns") end)
        p:Note(L["Also /evui design. Where the bars sit on your screen is edit mode: /evui edit."])
    end,
}
