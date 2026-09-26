if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Loot & Ready Check: loot rolls, loot luck and the ready check.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local LR = EV:GetModule("LootRolls", true)
local RC = EV:GetModule("ReadyCheck", true)
if not (LR or RC) then return end

local function Note(p, mod)
    if not mod:IsEnabled() then
        p:Note(L["Switched off on the Modules page."], 0.7)
        return true
    end
end

EV.Options:RegisterPage{
    key = "group", title = L["Loot & Ready Check"], group = "Interface",
    description = L["Loot rolls and the ready check, in the EvermoreUI style. Each can be switched off on the Modules page to get Blizzard's back."],
    build = function(p)
        if LR then
            local function G(k) return function() return LR.db[k] end end
            local function S(k) return function(v) LR.db[k] = v; if LR:IsEnabled() then LR:Refresh() end end end
            p:Section(L["Loot rolls"])
            if not Note(p, LR) then
                p:Dual({ type = "slider", text = L["Width"], min = 220, max = 480, step = 10, get = G("width"), set = S("width") },
                       { type = "slider", text = L["Height"], min = 26, max = 56, step = 1, get = G("height"), set = S("height") })
                p:Dual({ type = "toggle", text = L["New rolls stack upwards"], get = G("growUp"), set = S("growUp") },
                       { type = "slider", text = L["Spacing"], min = 0, max = 16, step = 1, get = G("spacing"), set = S("spacing") })
                p:Dual({ type = "button", text = L["Show a pretend roll"], label = L["Test"], width = 100,
                         onClick = function() LR:Test() end },
                       { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                         onClick = function() EV.Movers:Reset("LootRolls") end })
            end
        end
        local LS = EV:GetModule("LootStats", true)
        local qns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_QoL"]
        if LS and qns and qns.ShowLuck then
            p:Section(L["Loot luck"])
            p:Note(L["Every need, greed and pass you make is counted, by quality, for each of your characters. The board ranks them by how often they win."], 0.7)
            p:Row{ type = "button", text = L["Which character is luckiest?"], label = L["Open"], width = 100,
                   tooltip = "/evui luck",
                   onClick = function() EV.Options:Toggle(); qns.ShowLuck() end }
        end
        if RC then
            local function G(k) return function() return RC.db[k] end end
            local function S(k) return function(v) RC.db[k] = v end end
            p:Section(L["Ready check"])
            if not Note(p, RC) then
                p:Dual({ type = "toggle", text = L["Play a sound"], get = G("sound"), set = S("sound") },
                       { type = "toggle", text = L["Flash the taskbar icon"],
                         tooltip = L["So you notice it when the game is in the background."],
                         get = G("flash"), set = S("flash") })
                p:Dual({ type = "toggle", text = L["Say who wasn't ready"],
                         tooltip = L["A line in chat when the check ends: who said not ready and who didn't answer."],
                         get = G("summary"), set = S("summary") }, nil)
                p:Dual({ type = "button", text = L["Show the prompt"], label = L["Test"], width = 100,
                         onClick = function() RC:Test() end },
                       { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                         onClick = function() EV.Movers:Reset("ReadyCheck") end })
            end
        end
    end,
}
