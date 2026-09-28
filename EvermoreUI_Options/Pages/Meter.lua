if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Damage Meter: our own meter windows, fed by the game's meter data.
--  General: how many windows, the game's own meter, reporting. Then a tab
--  per window: what it shows and how.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Meter", true)
if not M then return end
local ns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_Meter"]

local TAB_GENERAL = L["General"]
local WINDOW_TABS = {}
for i = 1, 4 do WINDOW_TABS[i] = L["Window"] .. " " .. i end

local NUMBERS = {
    { value = "minimal", text = L["Amount"] },
    { value = "compact", text = L["Amount (per second)"] },
    { value = "complete", text = L["Amount (per second, share)"] },
}
local FIGHTS = {
    { value = "current", text = L["Current fight"] },
    { value = "overall", text = L["Overall"] },
}

local function Modes()
    local list = {}
    if not ns then return list end
    for _, cat in ipairs(ns.CATEGORIES) do
        list[#list + 1] = { header = cat.name }
        for _, t in ipairs(cat.types) do
            if t then list[#list + 1] = { value = t, text = ns.TypeName(t) } end
        end
    end
    return list
end

local function Textures()
    local list = { { value = "", text = L["As the rest of the interface"] } }
    for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
    return list
end

local function Apply() if M:IsEnabled() then M:Refresh() end end

EV.Options:RegisterPage{
    key = "meter", title = L["Damage Meter"], group = "Interface", module = "Meter",
    description = L["Damage, healing, interrupts and more in our own windows, fed by the game's own meter. In combat the game keeps the numbers to itself: the windows show its order and amounts, and shares, breakdowns of other players and reports fill in once combat ends."],
    tabs = { TAB_GENERAL, WINDOW_TABS[1], WINDOW_TABS[2], WINDOW_TABS[3], WINDOW_TABS[4] },
    build = function(p, tab)
        if tab == TAB_GENERAL or tab == nil then
            local function Get(k) return function() return M.db[k] end end
            local function Set(k) return function(v) M.db[k] = v; Apply() end end
            p:Section(L["Windows"])
            p:Dual({ type = "slider", text = L["Windows shown"], min = 1, max = 4, step = 1,
                     get = Get("count"), set = Set("count") },
                   { type = "toggle", text = L["Hide the windows"], tooltip = L["/evui meter shows and hides them too."],
                     get = Get("hidden"), set = Set("hidden") })
            p:Row{ type = "toggle", text = L["Switch off the game's own meter windows"],
                   tooltip = L["Uses the game's own setting, and puts it back when you turn this off."],
                   get = Get("hideBlizzard"), set = Set("hideBlizzard") }
            p:Row{ type = "button", text = L["Breakdown position"], label = L["Beside its window"], width = 150,
                   tooltip = L["Drag a breakdown by its title bar and it opens there from then on. This, or right-clicking its title bar, puts it back beside its window."],
                   onClick = function() if ns and ns.Breakdown then ns.Breakdown:ResetPosition() end end }
            p:Section(L["Reporting"])
            p:Row{ type = "slider", text = L["Lines to report"], min = 1, max = 25, step = 1,
                   get = Get("reportLines"), set = Set("reportLines") }
            p:Note(L["Report from the chevron on a window's title bar. Reports are sent once combat ends."])
            return
        end

        local i
        for n, name in ipairs(WINDOW_TABS) do if name == tab then i = n end end
        if not i then return end
        local function Get(k) return function() return M.db.windows[i][k] end end
        local function Set(k) return function(v) M.db.windows[i][k] = v; Apply() end end
        local function Off() return i > (M.db.count or 1) end

        p:Note(L["Shown when Windows shown on the General tab reaches this window."])
        p:Section(L["What it shows"])
        p:Dual({ type = "dropdown", text = L["Mode"], width = 190, values = Modes, get = Get("mode"), set = Set("mode"), disabled = Off },
               { type = "dropdown", text = L["Fight"], width = 150, values = FIGHTS, get = Get("session"), set = Set("session"), disabled = Off })
        p:Dual({ type = "dropdown", text = L["Numbers"], width = 210, values = NUMBERS, get = Get("numbers"), set = Set("numbers"), disabled = Off },
               { type = "toggle", text = L["Keep yourself in view"], get = Get("showSelf"), set = Set("showSelf"), disabled = Off })
        p:Section(L["Rows"])
        p:Dual({ type = "slider", text = L["Row height"], min = 12, max = 32, step = 1, get = Get("barHeight"), set = Set("barHeight"), disabled = Off },
               { type = "slider", text = L["Row spacing"], min = 0, max = 6, step = 1, get = Get("spacing"), set = Set("spacing"), disabled = Off })
        p:Dual({ type = "slider", text = L["Text size"], min = 9, max = 18, step = 1, get = Get("textSize"), set = Set("textSize"), disabled = Off },
               { type = "dropdown", text = L["Bar texture"], width = 190, values = Textures, get = Get("texture"), set = Set("texture"), disabled = Off })
        p:Dual({ type = "toggle", text = L["Class colours"], get = Get("classColours"), set = Set("classColours"), disabled = Off },
               { type = "toggle", text = L["Spec and class icons"], get = Get("icons"), set = Set("icons"), disabled = Off })
        p:Row{ type = "toggle", text = L["Rank numbers"], get = Get("rank"), set = Set("rank"), disabled = Off }
        p:Section(L["Window"])
        p:Dual({ type = "slider", text = L["Width"], min = 160, max = 600, step = 1, get = Get("width"), set = Set("width"), disabled = Off },
               { type = "slider", text = L["Height"], min = 80, max = 600, step = 1, get = Get("height"), set = Set("height"), disabled = Off })
        p:Dual({ type = "slider", text = L["Background opacity"], min = 0, max = 1, step = 0.05,
                 get = Get("opacity"), set = Set("opacity"), disabled = Off },
               { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                 onClick = function() EV.Movers:Reset("Meter" .. i) end })
    end,
    onReset = function(tab)
        if tab == TAB_GENERAL or tab == nil then
            local windows = M.db.windows
            wipe(M.db)
            EV.DB.Merge(M.db, M.defaults)
            if windows then M.db.windows = windows end
        else
            for n, name in ipairs(WINDOW_TABS) do
                if name == tab then
                    wipe(M.db.windows[n])
                    EV.DB.Merge(M.db.windows[n], M.defaults.windows[n])
                end
            end
        end
        Apply()
    end,
}
