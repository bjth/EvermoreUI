if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Bags: layout and which category sections to use.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Bags", true)
if not M then return end

EV.Options:RegisterPage{
    key = "bags", title = L["Bags"], group = "Interface", module = "Bags",
    description = L["All your bags in one window, split into sections by category. Replaces Blizzard's bag windows. Alt + click a bag on the bag bar to empty it into the others."],
    build = function(p)
        local db = M.db
        local function G(k) return function() return db[k] end end
        local function S(k) return function(v) db[k] = v; M:Refresh() end end

        p:Section(L["Layout"])
        p:Dual({ type = "slider", text = L["Icons per row"], min = 6, max = 24, step = 1, get = G("columns"), set = S("columns") },
               { type = "slider", text = L["Icon size"], min = 24, max = 48, step = 1, get = G("size"), set = S("size") })
        p:Dual({ type = "slider", text = L["Spacing"], min = 0, max = 10, step = 1, get = G("spacing"), set = S("spacing") },
               { type = "button", text = L["Your bags"], label = L["Open"], width = 100,
                 onClick = function() M:Open() end })

        p:Section(L["Sections"])
        p:Note(L["Items go in the first section that fits, in this order. Switch one off and its items fall through to the next that fits: with Herbs off, herbs go in Trade goods. Anything left over goes in Everything else."], 0.7)
        local cats = M.CATEGORIES
        for n = 1, #cats, 2 do
            local function Toggle(c)
                if not c then return nil end
                return { type = "toggle", text = c.label,
                         tooltip = c.gather and L["For gatherers: its own section."] or nil,
                         get = function() return db.categories[c.key] ~= false end,
                         set = function(v) db.categories[c.key] = v; M:Refresh() end }
            end
            p:Dual(Toggle(cats[n]), Toggle(cats[n + 1]))
        end
    end,
    onReset = function()
        wipe(M.db.categories)
        EV.DB.Merge(M.db, M.defaults)
        M:Refresh()
    end,
}
