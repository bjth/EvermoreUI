if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Swing Timer: time to your next auto attack, a bar per weapon.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("SwingTimer", true)
if not M then return end

local VISIBILITY = {
    { value = "combat", text = L["In combat"] },
    { value = "always", text = L["Always"] },
}

local STATE = {
    ["in use"]     = L["in use, confirmed by %d of your swings"],
    ["testing"]    = L["testing, %d of %d confirmations so far; Blizzard's timing until then"],
    ["not in use"] = L["not in use, a swing contradicted it; Blizzard's timing until %d swings in a row confirm it"],
}

local function RuleLine(name, rule, on)
    local E = EV.Swing
    if not on then return name .. ": " .. L["off, Blizzard's timing"] end
    local state, rec = E:RuleState(rule)
    local text
    if state == "in use" then text = STATE[state]:format(rec.yes)
    elseif state == "testing" then text = STATE[state]:format(rec.streak, E.CONFIRMATIONS)
    else text = STATE[state]:format(E.CONFIRMATIONS) end
    return name .. ": " .. text
end

EV.Options:RegisterPage{
    key = "swingtimer", title = L["Swing Timer"], group = "Combat", module = "SwingTimer",
    description = L["Time to your next auto attack, a bar per weapon, dimmed when your target is out of reach. Built on Forever's own swing timer events, so it keeps working now the combat log is closed to addons."],
    build = function(p)
        local function Get(k) return function() return M.db[k] end end
        local function Set(k) return function(v) M.db[k] = v; if M:IsEnabled() then M:Refresh() end end end
        local function Off() return not M.db.enabled end
        local function T(k, text, tip)
            return { type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k),
                     disabled = k ~= "enabled" and Off or nil }
        end
        local function S(k, text, lo, hi, step)
            return { type = "slider", text = text, min = lo, max = hi, step = step or 1,
                     get = Get(k), set = Set(k), disabled = Off }
        end

        p:Section(L["Swing timer"])
        p:Dual(T("enabled", L["Show the swing timer"]),
               { type = "dropdown", text = L["Show"], width = 150, values = VISIBILITY,
                 get = Get("visibility"), set = Set("visibility"), disabled = Off })
        p:Dual(T("activeOnly", L["Only bars that are swinging"],
                 L["A bar appears when that weapon swings and goes when it stops, so shooting a wand shows the ranged bar alone. Edit mode shows them all."]), nil)
        p:Dual(T("showOffHand", L["Off hand"], L["A second bar when you are dual wielding."]),
               T("showRanged", L["Ranged"], L["A bar for bows, guns, crossbows, thrown weapons and wands."]))
        p:Dual(T("showText", L["Time left"]), T("showLabel", L["Weapon label"], L["MH, OH or R at the start of each bar."]))
        p:Dual(T("hideBlizzard", L["Hide Blizzard's swing timer"],
                 L["Forever has its own swing timer. This switches it off while ours is on, and puts your setting back when ours is switched off."]), nil)

        if EV.Swing then
            p:Section(L["On the bar"])
            local layers = EV.Swing:Layers()
            for i = 1, #layers, 2 do
                local cells = {}
                for j = 0, 1 do
                    local layer = layers[i + j]
                    if layer then
                        cells[j + 1] = {
                            type = "toggle", text = layer.title or layer.key, tooltip = layer.description,
                            get = function() return M.LayerOn(layer) end,
                            set = function(v) M:SetLayer(layer.key, v) end,
                            disabled = Off,
                        }
                    end
                end
                p:Dual(cells[1], cells[2])
            end

            p:Section(L["Accuracy"])
            p:Note(L["A swing lasts the length the game announces when it starts, exactly as on Blizzard's bar. Two classic rules can move a swing already running, and neither is documented for Forever, so each only moves the bar once your own swings have confirmed it twice in a row. One swing that goes against it puts the bar back on Blizzard's timing. The record starts over with each game patch."])
            p:Dual(T("parryHaste", L["Parry haste"],
                     L["When you parry, the swing in progress loses 40% of your weapon speed, but never drops below 20% of it."]),
                   T("hasteRescale", L["Haste mid-swing"],
                     L["When your attack speed changes, the rest of the swing in progress speeds up or slows down with it."]))
            p:Note(RuleLine(L["Parry haste"], "parry", M.db.parryHaste) .. "\n"
                .. RuleLine(L["Haste mid-swing"], "haste", M.db.hasteRescale))
        end

        p:Section(L["Size"])
        p:Dual(S("width", L["Width"], 80, 500, 1), S("rowHeight", L["Bar height"], 4, 30, 1))
        p:Dual(S("rowGap", L["Gap between bars"], 0, 12, 1),
               { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                 onClick = function() EV.Movers:Reset("SwingTimer") end })
    end,
    onReset = function()
        wipe(M.db)
        EV.DB.Merge(M.db, M.defaults)
        if M:IsEnabled() then M:Refresh() end
    end,
}
