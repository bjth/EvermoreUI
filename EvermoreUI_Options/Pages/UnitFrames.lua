if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Unit Frames: one tab per unit, same layout on each.
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

local PORTRAITS = {
    { value = "none",  text = L["None"] },
    { value = "3d",    text = L["3D model"] },
    { value = "2d",    text = L["2D picture"] },
    { value = "class", text = L["Class icon"] },
}
local SIDES = { { value = "left", text = L["Left"] }, { value = "right", text = L["Right"] } }
local COLOURS = {
    { value = "class", text = L["Class / reaction"] },
    { value = "green", text = L["Green"] },
    { value = "dark",  text = L["Dark"] },
}
local HEALTH_TEXT = {
    { value = "curpercent", text = L["12.3k  87%"] },
    { value = "percent",    text = L["87%"] },
    { value = "current",    text = L["12.3k"] },
    { value = "curmax",     text = L["12.3k / 14.1k"] },
    { value = "deficit",    text = L["Missing (-1.8k)"] },
    { value = "none",       text = L["None"] },
}
local POWER_TEXT = {
    { value = "current", text = L["4,210"] },
    { value = "percent", text = L["87%"] },
    { value = "curmax",  text = L["4.2k / 5k"] },
    { value = "none",    text = L["None"] },
}

-- Same three edges, same wording, as the nameplates page.
local TEXT_STYLE = {
    { value = "both",    text = L["Outline and shadow"] },
    { value = "shadow",  text = L["Shadow only"] },
    { value = "outline", text = L["Outline only"] },
}

local function Textures()
    local list = {}
    for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
    return list
end

EV.Options:RegisterPage{
    key = "unitframes", title = L["Unit Frames"], group = "Combat", module = "UnitFrames",
    description = L["Player, target, target of target, focus and pet. Clean bars, your layout."],
    tabs = TABS,
    build = function(p, tab)
        local key = KEY_FOR_TAB[tab]
        local moverKey = "UF_" .. key
        local function C() return M.db[key] end
        local function Get(k) return function() return C()[k] end end
        local function Set(k, reload)
            return function(v)
                C()[k] = v
                if reload then EV.Options:MarkReloadNeeded() end
                if M:IsEnabled() then M:ApplyFrame(key) end
            end
        end
        local function Off() return not C().enabled end
        local function T(k, text, tip, extra)
            local cfg = { type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k),
                          disabled = k ~= "enabled" and Off or nil }
            if extra then for a, b in pairs(extra) do cfg[a] = b end end
            return cfg
        end
        local function S(k, text, lo, hi, step, extra)
            local cfg = { type = "slider", text = text, min = lo, max = hi, step = step,
                          get = Get(k), set = Set(k), disabled = Off }
            if extra then for a, b in pairs(extra) do cfg[a] = b end end
            return cfg
        end
        local function D(k, text, values, width, extra)
            local cfg = { type = "dropdown", text = text, values = values, width = width or 170,
                          get = Get(k), set = Set(k), disabled = Off }
            if extra then for a, b in pairs(extra) do cfg[a] = b end end
            return cfg
        end

        p:Section(L["Frame"])
        p:Dual(T("enabled", L["Show this frame"]),
               T("hideBlizzard", L["Hide Blizzard's frame"],
                 L["Retires Blizzard's frame for this unit. Bringing it back needs a reload."],
                 { set = Set("hideBlizzard", true) }))
        p:Dual(S("width", L["Width"], 60, 500, 1), S("height", L["Height"], 12, 100, 1))
        p:Dual(S("powerHeight", L["Power bar height"], 0, 30, 1, { tooltip = L["0 hides the power bar."] }),
               S("bgAlpha", L["Background opacity"], 0, 1, 0.05))
        p:Dual(S("borderSize", L["Border thickness"], 1, 3, 1),
               T("innerShadow", L["Inset shading"],
                 L["A dark ramp just inside the top and bottom of the health and power bars, the same as the nameplates. Skipped on a bar under 8 tall, where it would just look like a thicker border."]))

        p:Section(L["Aggro glow"])
        local function NoGlow() return Off() or not C().aggroBorder end
        p:Dual(T("aggroBorder", L["Aggro glow"],
                 L["The nameplates' red glow, behind the frame. On an enemy it lights when that mob is on you, so it matches the mob's plate. On you or a friend it lights when they're tanking something: amber while threat is climbing, red once they have it. In instances the game hides threat numbers, so there it's red or nothing, and only for the unit's current target."]),
               nil)
        p:Dual(S("aggroAlpha", L["Glow strength"], 0.1, 1, 0.05, { disabled = NoGlow }),
               S("aggroPad", L["Glow reach"], 2, 16, 1, { disabled = NoGlow,
                 tooltip = L["How far past the frame the glow reaches, in pixels."] }))

        p:Section(L["Position"])
        p:Dual(
            { type = "slider", text = L["X (pixels)"], min = -2000, max = 2000, step = 1, disabled = Off,
              tooltip = L["Pixels from the centre of the screen. Rough placement in edit mode, fine-tune here or with the arrow keys."],
              get = function() return (EV.Movers:GetOffsetPx(moverKey)) end,
              set = function(v) local _, y = EV.Movers:GetOffsetPx(moverKey); EV.Movers:SetOffsetPx(moverKey, v, y) end },
            { type = "slider", text = L["Y (pixels)"], min = -1200, max = 1200, step = 1, disabled = Off,
              get = function() return select(2, EV.Movers:GetOffsetPx(moverKey)) end,
              set = function(v) local x = EV.Movers:GetOffsetPx(moverKey); EV.Movers:SetOffsetPx(moverKey, x, v) end })
        p:Dual(
            { type = "button", text = L["Edit mode"], label = L["Open"], width = 110, disabled = Off,
              onClick = function() EV.Movers:Unlock() end },
            { type = "button", text = L["Default position"], label = L["Reset"], width = 110, disabled = Off,
              onClick = function() EV.Movers:Reset(moverKey) end })

        p:Section(L["Portrait"])
        p:Dual(D("portrait", L["Style"], PORTRAITS, 150,
                 { tooltip = L["Class icon shows for players; NPCs fall back to the 2D picture."] }),
               D("portraitSide", L["Side"], SIDES, 120,
                 { disabled = function() return Off() or C().portrait == "none" end }))

        p:Section(L["Bars"])
        p:Dual(D("healthColour", L["Health colour"], COLOURS, 170,
                 { tooltip = L["Dark: a dark bar with the missing health shown in the unit's colour."] }),
               D("texture", L["Texture"], Textures, 150))
        p:Dual(S("barShade", L["Bar brightness"], 0.5, 1, 0.05,
                 { tooltip = L["Dims the hostility and power colours so the text on them can be read, the same as the nameplates. White on a full red bar measures 4.0:1 contrast, below the readable floor; at 0.75 it is 6.5:1. Class colours are left at full strength."] }),
               T("healPrediction", L["Incoming heals"],
                 L["Shades the health a heal already in flight will restore."]))

        p:Section(L["Text"])
        p:Dual(D("healthText", L["Health text"], HEALTH_TEXT, 170),
               D("powerText", L["Power text"], POWER_TEXT, 150,
                 { tooltip = L["Shown when the power bar is at least 9 tall."] }))
        p:Dual(T("showName", L["Name"]), T("showLevel", L["Level"], nil,
                 { disabled = function() return Off() or not C().showName end }))
        p:Dual(S("fontSize", L["Font size"], 8, 24, 1),
               D("textStyle", L["Text edge"], TEXT_STYLE, 190,
                 { tooltip = L["Matches the nameplates' setting of the same name. Shadow only is cleaner at small sizes because nothing closes up the inside of a letter."] }))

        local ns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_UnitFrames"]
        local function Classic(k)
            return function(v) C()[k] = v; if ns and ns.RefreshClassic then ns.RefreshClassic() end end
        end
        if key == "player" then
            p:Section(L["Classic"])
            p:Dual(T("powerTicks", L["Energy tick and five-second rule"],
                     L["A strip along the bottom of the power bar. It fills over the two seconds to your next energy or mana tick, and turns amber for the five seconds after you spend mana. It appears once it has seen regeneration arrive in two-second steps, and fades away at full power."],
                     { set = Classic("powerTicks") }),
                   T("powerTickGhost", L["Next tick preview"],
                     L["A faint segment past the end of your power showing what the next tick adds. Mana's shrinks to nothing inside the five-second rule, because your regeneration has stopped."],
                     { set = Classic("powerTickGhost") }))
        elseif key == "pet" then
            p:Section(L["Classic"])
            p:Dual(T("happiness", L["Pet happiness"],
                     L["A marker on the pet frame: green happy, amber content, red unhappy. Hover for damage, loyalty and diet."],
                     { set = Classic("happiness") }), nil)
        end
    end,
    onReset = function(tab)
        local key = KEY_FOR_TAB[tab]
        if key then M:ResetUnit(key) end
    end,
}
