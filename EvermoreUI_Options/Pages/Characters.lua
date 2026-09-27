if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Characters: what EvermoreUI remembers about your characters, and whose
--  characters count. The settings are account-wide (EV.Alts), so they're the
--  same on every character.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Characters", true)
if not M then return end

local SCOPES = {
    { value = "faction", text = L["My faction, any realm"] },
    { value = "realm",   text = L["My realm and faction"] },
    { value = "all",     text = L["Every character"] },
}

EV.Options:RegisterPage{
    key = "characters", title = L["Characters"], group = "Interface", module = "Characters",
    description = L["Every character's gold, rested XP, professions, bags, bank and mail, remembered as you play them, so you can see any of it from any of them."],
    build = function(p)
        local A = EV.Alts
        local function S() return A:Settings() end
        p:Section(L["Remembering"])
        p:Dual({ type = "toggle", text = L["Remember my characters"],
                 tooltip = L["Records each character's gold, bags, bank and mail as you play it. Off: nothing new is recorded, and item counts and the gold readout stop."],
                 get = function() return S().track end,
                 set = function(v) S().track = v; A:Invalidate("settings") end },
               { type = "dropdown", text = L["Whose characters count"], width = 200, values = SCOPES,
                 tooltip = L["For item counts in tooltips, the gold readout and the Characters window. Mail and banks can only move items within a faction."],
                 get = function() return S().scope end,
                 set = function(v) S().scope = v; A:Invalidate("scope") end })
        p:Dual({ type = "slider", text = L["Warn about mail running out"], min = 0, max = 7, step = 1,
                 fmt = function(v) return v == 0 and L["Never"] or (L["%d |4day:days;"]):format(v) end,
                 tooltip = L["At login, a line in chat for any character with mail that runs out within this many days."],
                 disabled = function() return not S().track end,
                 get = function() return S().mailWarn end,
                 set = function(v) S().mailWarn = v end },
               { type = "button", text = L["Characters window"], label = L["Open"], width = 120,
                 tooltip = "/evui alts",
                 onClick = function() EV.Options:Toggle(); M:Show() end })

        p:Section(L["Where it shows"])
        local tips = EV:GetModule("Tooltips", true)
        if tips and tips.db then
            p:Dual({ type = "toggle", text = L["Item counts in tooltips"],
                     tooltip = L["How many each of your characters has, and where. Also on the Tooltips page."],
                     get = function() return tips.db.itemCounts end,
                     set = function(v) tips.db.itemCounts = v end }, nil)
        end
        local bars = EV:GetModule("DataBars", true)
        if bars and bars.db and bars.db.gold then
            p:Dual({ type = "toggle", text = L["Gold readout"],
                     tooltip = L["Your gold on screen; hover it for every character's. More on the Data Bars page."],
                     get = function() return bars.db.gold.enabled end,
                     set = function(v)
                         bars.db.gold.enabled = v
                         if bars:IsEnabled() and bars.Refresh then bars:Refresh() end
                     end }, nil)
        end
        p:Note(L["A character joins the list the first time you log in on it with EvermoreUI. Its bank is known once you've visited a banker, and its mail once you've opened the mailbox."], 0.7)
    end,
}
