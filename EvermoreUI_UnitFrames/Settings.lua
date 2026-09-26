if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Settings.lua
--  Every unit frame setting, written once. The designer shows them with the
--  part they belong to; the options page opens the designer. One copy, so the
--  two can never disagree.
--
--  ns.Settings(p, key, pick): p is an options page builder, key the unit.
--  pick = { sections = { [title] = true | { [path] = true } } }: a section
--  mapped to true is drawn whole, to a set of paths only those settings, and
--  a section not named is skipped. nil draws everything.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

local _, CLASS = UnitClass("player")

local PORTRAITS = {
    { value = "none",  text = L["None"] },
    { value = "3d",    text = L["3D model"] },
    { value = "2d",    text = L["2D picture"] },
    { value = "class", text = L["Class icon"] },
}
local SIDES = { { value = "left", text = L["Left"] }, { value = "right", text = L["Right"] } }
local COLOURS = {
    { value = "class",  text = L["Class / reaction"] },
    { value = "green",  text = L["Green"] },
    { value = "dark",   text = L["Dark"] },
    { value = "custom", text = L["Your own colour"] },
}
local POWER_COLOURS = {
    { value = "type",   text = L["By resource"] },
    { value = "class",  text = L["Class colour"] },
    { value = "custom", text = L["Your own colour"] },
}
local NAME_COLOURS = {
    { value = "white", text = L["White"] },
    { value = "class", text = L["Class / reaction"] },
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
local TEXT_STYLE = {
    { value = "both",    text = L["Outline and shadow"] },
    { value = "shadow",  text = L["Shadow only"] },
    { value = "outline", text = L["Outline only"] },
}
local ALIGN3 = {
    { value = "LEFT",   text = L["Left"] },
    { value = "CENTER", text = L["Centre"] },
    { value = "RIGHT",  text = L["Right"] },
}
local CORNERS = {
    { value = "TOPLEFT",     text = L["Top left"] },
    { value = "TOP",         text = L["Top"] },
    { value = "TOPRIGHT",    text = L["Top right"] },
    { value = "LEFT",        text = L["Left"] },
    { value = "CENTER",      text = L["Centre"] },
    { value = "RIGHT",       text = L["Right"] },
    { value = "BOTTOMLEFT",  text = L["Bottom left"] },
    { value = "BOTTOM",      text = L["Bottom"] },
    { value = "BOTTOMRIGHT", text = L["Bottom right"] },
}
local AURA_SIDES = {
    { value = "TOP",    text = L["Above"] },
    { value = "BOTTOM", text = L["Below"] },
    { value = "LEFT",   text = L["Left"] },
    { value = "RIGHT",  text = L["Right"] },
}
local ABOVE_BELOW = {
    { value = "TOP",    text = L["Above"] },
    { value = "BOTTOM", text = L["Below"] },
}
local STARTS = {
    { value = "START", text = L["Left end"] },
    { value = "END",   text = L["Right end"] },
}
local AURA_SORT = {
    { value = "default", text = L["Game's order"] },
    { value = "time",    text = L["Time left"] },
}
local CAST_PLACES = {
    { value = "attached", text = L["Under the frame"] },
    { value = "detached", text = L["Anywhere (edit mode)"] },
}
local ICON_SIDES = { { value = "LEFT", text = L["Left"] }, { value = "RIGHT", text = L["Right"] } }
local TIME_FORMATS = {
    { value = "remaining", text = L["1.2"] },
    { value = "both",      text = L["1.2 / 3.0"] },
}

local function Textures(follow)
    return function()
        local list = {}
        if follow then list[1] = { value = "", text = L["Same as the frame"] } end
        for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
        return list
    end
end
local function Fonts() return EV.Media:FontValues(true) end

local UNIT_CHOICES = {}
for _, u in ipairs(ns.UNITS) do UNIT_CHOICES[#UNIT_CHOICES + 1] = { value = u.key, text = L[u.title] } end


local function Picker(p, pick)
    local sections = pick and pick.sections
    local want = not sections
    local q = {}
    local function Wanted(cfg)
        if not cfg then return false end
        if not sections or want == true then return want and true or false end
        if type(want) == "table" then return cfg.key ~= nil and want[cfg.key] == true end
        return false
    end
    function q:Section(text)
        want = not sections or sections[text]
        if want then p:Section(text) end
    end
    function q:Dual(a, b)
        if not sections then p:Dual(a, b) return end
        if Wanted(a) then p:Row(a) end
        if Wanted(b) then p:Row(b) end
    end
    function q:Row(cfg) if Wanted(cfg) then p:Row(cfg) end end
    function q:Note(text) if want == true then p:Note(text) end end
    function q:Refresh() if p.Refresh then p:Refresh() end end
    return q
end

function ns.Settings(builder, key, pick)
    local M = ns.module
    local p = Picker(builder, pick)
    local moverKey = "UF_" .. key
    local DEF = M.DEFAULTS and M.DEFAULTS[key] or {}
    local function C() return M.db[key] end

    -- Settings live at paths: "width", or "castbar.height".
    local function Split(path)
        local a, b = path:match("^([^.]+)%.(.+)$")
        return a or path, b
    end
    local function GetP(path, from)
        local a, b = Split(path)
        local t = from or C()
        if b then t = t[a]; return t and t[b] end
        return t[a]
    end
    local function SetP(path, v)
        local a, b = Split(path)
        if b then C()[a][b] = v else C()[a] = v end
    end
    local function Apply(reload)
        if reload then EV.Options:MarkReloadNeeded() end
        if M:IsEnabled() then M:ApplyFrame(key) end
        if ns and ns.ClassPower and M:IsEnabled() then ns.ClassPower.Refresh() end
    end
    local function Get(path) return function() return GetP(path) end end
    local function Set(path, reload)
        return function(v) SetP(path, v); Apply(reload) end
    end
    local function Off() return not C().enabled end
    -- "on" is a path whose toggle has to be on for this row to matter.
    local function OffUnless(on)
        return function() return Off() or not GetP(on) end
    end
    local function With(cfg, extra)
        if extra then for a, b in pairs(extra) do cfg[a] = b end end
        return cfg
    end
    -- Every control carries its setting's path, so the designer can pick
    -- which ones a part shows.
    local function Keyed(path, cfg) cfg.key = path; return cfg end
    local function T(path, text, tip, extra)
        return Keyed(path, With({ type = "toggle", text = text, tooltip = tip, get = Get(path), set = Set(path),
                      disabled = path ~= "enabled" and Off or nil }, extra))
    end
    local function S(path, text, lo, hi, step, extra)
        return Keyed(path, With({ type = "slider", text = text, min = lo, max = hi, step = step,
                      get = Get(path), set = Set(path), disabled = Off }, extra))
    end
    local function D(path, text, values, width, extra)
        return Keyed(path, With({ type = "dropdown", text = text, values = values, width = width or 170,
                      get = Get(path), set = Set(path), disabled = Off }, extra))
    end
    local function Col(path, text, extra)
        local function Default() return GetP(path, DEF) or { 1, 1, 1 } end
        return With({
            type = "colour", text = text, disabled = Off,
            get = function()
                local c = GetP(path) or Default()
                return c[1], c[2], c[3]
            end,
            set = function(r, g, b) SetP(path, { r, g, b }); Apply() end,
            reset = function() local d = Default(); SetP(path, { d[1], d[2], d[3] }); Apply() end,
            isCustom = function()
                local c, d = GetP(path), Default()
                if type(c) ~= "table" then return false end
                for i = 1, 3 do
                    if math.abs((c[i] or 0) - (d[i] or 0)) > 0.002 then return true end
                end
                return false
            end,
        }, extra)
    end

    ------------------------------------------------------------------------

    p:Section(L["Frame"])
    p:Dual(T("enabled", L["Show this frame"]),
           T("hideBlizzard", L["Hide Blizzard's frame"],
             L["Retires Blizzard's frame for this unit. Bringing it back needs a reload."],
             { set = Set("hideBlizzard", true) }))
    p:Dual(S("width", L["Width"], 60, 500, 1), S("height", L["Height"], 12, 100, 1))
    p:Dual(S("powerHeight", L["Power bar height"], 0, 30, 1, { tooltip = L["0 hides the power bar."] }),
           S("bgAlpha", L["Background opacity"], 0, 1, 0.05))
    local copyFrom
    p:Dual({ type = "dropdown", text = L["Copy settings from"], width = 170, disabled = Off,
             tooltip = L["Takes size, colours, text, cast bar and aura settings from another frame. Position and what only that frame has stay as they are."],
             values = function()
                 local list = {}
                 for _, c in ipairs(UNIT_CHOICES) do if c.value ~= key then list[#list + 1] = c end end
                 return list
             end,
             get = function() return copyFrom end, set = function(v) copyFrom = v end },
           { type = "button", text = L["Copy onto this frame"], label = L["Copy"], width = 110,
             disabled = function() return Off() or not copyFrom end,
             onClick = function()
                 if copyFrom then M:CopyUnit(copyFrom, key); p:Refresh() end
             end })

    ------------------------------------------------------------------------
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

    ------------------------------------------------------------------------
    p:Section(L["Colours and texture"])
    p:Dual(D("healthColour", L["Health colour"], COLOURS, 170,
             { tooltip = L["Dark: a dark bar with the missing health shown in the unit's colour."] }),
           Col("healthCustom", L["Your health colour"],
               { disabled = function() return Off() or C().healthColour ~= "custom" end }))
    p:Dual(D("powerColour", L["Power colour"], POWER_COLOURS, 170,
             { tooltip = L["Class colour applies to players; anything else keeps its resource's colour."] }),
           Col("powerCustom", L["Your power colour"],
               { disabled = function() return Off() or C().powerColour ~= "custom" end }))
    p:Dual(S("barShade", L["Bar brightness"], 0.5, 1, 0.05,
             { tooltip = L["Dims the hostility and power colours so the text on them can be read, the same as the nameplates. White on a full red bar measures 4.0:1 contrast, below the readable floor; at 0.75 it is 6.5:1. Class colours and your own colours are left at full strength."] }),
           D("texture", L["Texture"], Textures(false), 150,
             { tooltip = L["Includes textures from other addons that share them through LibSharedMedia."] }))
    p:Dual(S("borderSize", L["Border thickness"], 0, 8, 1, { tooltip = L["In pixels. 0 is no border."] }),
           Col("borderColour", L["Border colour"]))
    p:Dual(Col("bgColour", L["Background colour"],
               { tooltip = L["The empty part of the bars and the frame behind them."] }),
           T("innerShadow", L["Inset shading"],
             L["A dark ramp just inside the top and bottom of the health and power bars, the same as the nameplates. Skipped on a bar under 8 tall, where it would just look like a thicker border."]))
    p:Dual(T("healPrediction", L["Incoming heals"],
             L["Shades the health a heal already in flight will restore."]), nil)

    ------------------------------------------------------------------------
    p:Section(L["Text"])
    p:Dual(D("font", L["Font"], Fonts, 190,
             { tooltip = L["Global font follows General > Font. Fonts from other addons work too."] }),
           D("textStyle", L["Text edge"], TEXT_STYLE, 190,
             { tooltip = L["Matches the nameplates' setting of the same name. Shadow only is cleaner at small sizes because nothing closes up the inside of a letter."] }))
    p:Dual(S("fontSize", L["Font size"], 8, 24, 1),
           S("powerFontSize", L["Power text size"], 0, 24, 1, { tooltip = L["0 is two points under the font size."] }))
    p:Dual(T("showName", L["Name"]), T("showLevel", L["Level"], nil, { disabled = OffUnless("showName") }))
    p:Dual(D("nameColour", L["Name colour"], NAME_COLOURS, 170, { disabled = OffUnless("showName") }),
           S("nameWidth", L["Name width (%)"], 0, 100, 5, { disabled = OffUnless("showName"),
             tooltip = L["How much of the bar a long name may use. 0 lets it run up to the health text when the two share a line, or across the whole bar otherwise."] }))
    p:Dual(D("namePoint", L["Name position"], ALIGN3, 120, { disabled = OffUnless("showName") }),
           nil)
    p:Dual(S("nameX", L["Name X"], -100, 100, 1, { disabled = OffUnless("showName") }),
           S("nameY", L["Name Y"], -50, 50, 1, { disabled = OffUnless("showName") }))
    p:Dual(D("healthText", L["Health text"], HEALTH_TEXT, 170), D("healthPoint", L["Health text position"], ALIGN3, 120))
    p:Dual(S("healthX", L["Health text X"], -100, 100, 1), S("healthY", L["Health text Y"], -50, 50, 1))
    p:Dual(D("powerText", L["Power text"], POWER_TEXT, 150,
             { tooltip = L["Shown when the power bar is at least 9 tall."] }),
           D("powerPoint", L["Power text position"], ALIGN3, 120))
    p:Dual(S("powerX", L["Power text X"], -100, 100, 1), S("powerY", L["Power text Y"], -50, 50, 1))

    ------------------------------------------------------------------------
    p:Section(L["Portrait"])
    p:Dual(D("portrait", L["Style"], PORTRAITS, 150,
             { tooltip = L["Class icon shows for players; NPCs fall back to the 2D picture."] }),
           D("portraitSide", L["Side"], SIDES, 120,
             { disabled = function() return Off() or C().portrait == "none" end }))

    ------------------------------------------------------------------------
    p:Section(L["Icons"])
    p:Dual(S("raidIconSize", L["Raid mark size"], 8, 48, 1), D("raidIconPoint", L["Raid mark position"], CORNERS, 150))
    p:Dual(S("raidIconX", L["Raid mark X"], -100, 100, 1), S("raidIconY", L["Raid mark Y"], -100, 100, 1))
    p:Dual(T("leaderIcon", L["Leader and assist"], L["The crown for the group leader, the flag for an assistant."]),
           D("leaderIconPoint", L["Position"], CORNERS, 150, { disabled = OffUnless("leaderIcon") }))
    p:Dual(T("pvpIcon", L["PvP flag"]),
           D("pvpIconPoint", L["Position"], CORNERS, 150, { disabled = OffUnless("pvpIcon") }))
    if key == "player" then
        p:Dual(T("combatIcon", L["In combat"], L["Crossed swords while you're in combat."]),
               T("restingIcon", L["Resting"], L["The Zzz while you're in an inn or a city."]))
        p:Dual(S("stateIconSize", L["Combat and resting size"], 8, 40, 1),
               D("stateIconPoint", L["Position"], CORNERS, 150))
    end

    -- Target of target gets no cast or aura events from the game, so
    -- neither can be shown on it.
    if key == "targettarget" then
        p:Section(L["Cast bar, buffs and debuffs"])
        p:Note(L["The game doesn't send cast or aura updates for your target's target, so this frame can't show them."])
    else
        ------------------------------------------------------------------------
        p:Section(L["Cast bar"])
        local function CastOff() return Off() or not C().castbar.enabled end
        p:Dual(T("castbar.enabled", L["Show a cast bar"],
                 key == "target" and L["Your target's casts: the one to interrupt. Blizzard's went with its target frame."] or nil),
               { type = "dropdown", text = L["Placement"], values = CAST_PLACES, width = 190, disabled = CastOff,
                 tooltip = L["Under the frame: hangs below it and hides with it. Anywhere: place it in edit mode, like any other element."],
                 get = function() return C().castbar.detached and "detached" or "attached" end,
                 set = function(v) C().castbar.detached = (v == "detached"); Apply() end })
        p:Dual(S("castbar.width", L["Width"], 0, 600, 1, { disabled = CastOff,
                 tooltip = L["0 matches the frame's width."] }),
               S("castbar.height", L["Height"], 4, 60, 1, { disabled = CastOff }))
        p:Dual(S("castbar.gap", L["Gap under the frame"], 0, 60, 1,
                 { disabled = function() return CastOff() or C().castbar.detached end }),
               S("castbar.x", L["Nudge sideways"], -300, 300, 1,
                 { disabled = function() return CastOff() or C().castbar.detached end }))
        p:Dual(T("castbar.icon", L["Spell icon"], nil, { disabled = CastOff }),
               D("castbar.iconSide", L["Icon side"], ICON_SIDES, 120,
                 { disabled = function() return CastOff() or not C().castbar.icon end }))
        p:Dual(T("castbar.showName", L["Spell name"], nil, { disabled = CastOff }),
               T("castbar.showTime", L["Time left"], nil, { disabled = CastOff }))
        p:Dual(D("castbar.timeFormat", L["Time format"], TIME_FORMATS, 130,
                 { disabled = function() return CastOff() or not C().castbar.showTime end }),
               S("castbar.fontSize", L["Font size"], 7, 24, 1, { disabled = CastOff }))
        p:Dual(T("castbar.spark", L["Spark"], L["A bright line on the leading edge of the fill."], { disabled = CastOff }),
               D("castbar.texture", L["Texture"], Textures(true), 170, { disabled = CastOff }))
        if key == "player" then
            p:Dual(T("castbar.latency", L["Latency"],
                     L["A red block at the end of the bar: the time between pressing the key and the server starting the cast. Once the fill reaches it, the cast has effectively finished, so you can queue the next."],
                     { disabled = CastOff }),
                   T("castbar.hideBlizzard", L["Hide Blizzard's cast bar"],
                     L["Bringing it back needs a reload."], { disabled = CastOff, set = Set("castbar.hideBlizzard", true) }))
        elseif key == "pet" then
            p:Dual(T("castbar.hideBlizzard", L["Hide Blizzard's pet cast bar"],
                     L["Bringing it back needs a reload."], { disabled = CastOff, set = Set("castbar.hideBlizzard", true) }), nil)
        end
        p:Note(L["Cast, channel, uninterruptible and interrupted colours are on the Colours page, shared with the nameplates."])

        ------------------------------------------------------------------------
        local function AuraSection(kind, title, mineTip)
            local base = kind .. "."
            local function AOff() return Off() or not C()[kind].enabled end
            p:Section(title)
            p:Dual(T(base .. "enabled", title == L["Debuffs"] and L["Show debuffs"] or L["Show buffs"]),
                   T(base .. "onlyMine", L["Only mine"], mineTip, { disabled = AOff }))
            p:Dual(D(base .. "side", L["Side"], AURA_SIDES, 120, { disabled = AOff }),
                   D(base .. "align", L["Start from"], STARTS, 130, {
                       disabled = function()
                           local s = C()[kind].side
                           return AOff() or s == "LEFT" or s == "RIGHT"
                       end,
                       tooltip = L["Which end of the frame the first icon sits at; the row grows towards the other."] }))
            p:Dual(S(base .. "size", L["Icon size"], 10, 60, 1, { disabled = AOff }),
                   S(base .. "spacing", L["Spacing"], 0, 12, 1, { disabled = AOff }))
            p:Dual(S(base .. "perRow", L["Per row"], 1, 20, 1, { disabled = AOff }),
                   S(base .. "max", L["Most shown"], 1, 40, 1, { disabled = AOff }))
            p:Dual(S(base .. "x", L["Nudge X"], -200, 200, 1, { disabled = AOff }),
                   S(base .. "y", L["Nudge Y"], -200, 200, 1, { disabled = AOff }))
            p:Dual(T(base .. "showTimer", L["Time left"], nil, { disabled = AOff }),
                   S(base .. "timerSize", L["Timer size"], 7, 20, 1,
                     { disabled = function() return AOff() or not C()[kind].showTimer end }))
            p:Dual(T(base .. "showSwipe", L["Swipe"], L["The clock sweep across the icon as it runs down."], { disabled = AOff }),
                   D(base .. "sort", L["Order"], AURA_SORT, 140, { disabled = AOff }))
        end
        AuraSection("debuffs", L["Debuffs"],
            L["Only the debuffs you put on. Off shows everyone's, so you can see who has Sunder or a curse up and whether it's already crowd controlled. The game won't say which are yours in restricted combat, so it's one or the other rather than yours highlighted."])
        AuraSection("buffs", L["Buffs"],
            L["Only the buffs you cast. Handy on friends when you're checking who needs a rebuff."])
        if key == "player" then
            p:Note(L["Your own buffs and debuffs are also on the Buffs & Debuffs page as their own movable blocks; turn these on if you'd rather have them on the frame."])
        elseif not (EV.AuraContainer and EV.AuraContainer.Supported()) then
            p:Note(L["This client has no aura containers, so buffs and debuffs can't be shown on frames."])
        end
        p:Note(L["When buffs and debuffs share a side, the second block starts past the room the first could fill, because the game doesn't tell addons how many there are while you fight."])
    end

    ------------------------------------------------------------------------
    if key == "player" then
        local function Classic(k)
            return function(v) C()[k] = v; if ns and ns.RefreshClassic then ns.RefreshClassic() end end
        end
        p:Section(L["Classic"])
        p:Dual(T("powerTicks", L["Energy tick and five-second rule"],
                 L["A strip along the bottom of the power bar. It fills over the two seconds to your next energy or mana tick, and turns amber for the five seconds after you spend mana. It appears once it has seen regeneration arrive in two-second steps, and fades away at full power."],
                 { set = Classic("powerTicks") }),
               T("powerTickGhost", L["Next tick preview"],
                 L["A faint segment past the end of your power showing what the next tick adds. Mana's shrinks to nothing inside the five-second rule, because your regeneration has stopped."],
                 { set = Classic("powerTickGhost") }))

        if CLASS == "ROGUE" or CLASS == "DRUID" then
            local function CPOff() return Off() or not C().classPower.enabled end
            p:Section(L["Combo points"])
            p:Dual(T("classPower.enabled", L["Show combo points"],
                     CLASS == "DRUID" and L["Shown while you're in Cat Form."] or nil),
                   D("classPower.side", L["Side"], ABOVE_BELOW, 120, { disabled = CPOff }))
            p:Dual(S("classPower.height", L["Height"], 2, 30, 1, { disabled = CPOff }),
                   S("classPower.spacing", L["Spacing"], 0, 12, 1, { disabled = CPOff }))
            p:Dual(S("classPower.width", L["Width"], 0, 500, 1,
                     { disabled = CPOff, tooltip = L["0 matches the frame's width."] }),
                   Col("classPower.colour", L["Colour"], { disabled = CPOff }))
            p:Dual(S("classPower.x", L["Nudge X"], -200, 200, 1, { disabled = CPOff }),
                   S("classPower.y", L["Nudge Y"], -200, 200, 1, { disabled = CPOff }))
            p:Dual(T("classPower.hideEmpty", L["Hide when empty out of combat"], nil, { disabled = CPOff }), nil)
        end

        if CLASS == "SHAMAN" then
            local function TOff() return Off() or not C().totems.enabled end
            p:Section(L["Totems"])
            p:Dual(T("totems.enabled", L["Show totems"],
                     L["One button per element with the time left. Right click one to destroy that totem."]),
                   D("totems.side", L["Side"], ABOVE_BELOW, 120, { disabled = TOff }))
            p:Dual(S("totems.size", L["Size"], 12, 60, 1, { disabled = TOff }),
                   S("totems.spacing", L["Spacing"], 0, 20, 1, { disabled = TOff }))
            p:Dual(D("totems.align", L["Start from"], STARTS, 130, { disabled = TOff }),
                   T("totems.showTimer", L["Time left"], nil, { disabled = TOff }))
            p:Dual(S("totems.x", L["Nudge X"], -200, 200, 1, { disabled = TOff }),
                   S("totems.y", L["Nudge Y"], -200, 200, 1, { disabled = TOff }))
        end
    elseif key == "pet" then
        p:Section(L["Classic"])
        p:Dual(T("happiness", L["Pet happiness"],
                 L["A marker on the pet frame: green happy, amber content, red unhappy. Hover for damage, loyalty and diet."],
                 { set = function(v) C().happiness = v; if ns and ns.RefreshClassic then ns.RefreshClassic() end end }), nil)
    end

    ------------------------------------------------------------------------
    if key == "player" or key == "pet" then
        local function FOff() return Off() or not C().fader.enabled end
        p:Section(L["Fade out of combat"])
        p:Dual(T("fader.enabled", L["Fade when idle"],
                 L["Fades the frame when none of the things below are happening. It still works while faded: hover it to bring it back."]),
               S("fader.alpha", L["Faded opacity"], 0, 1, 0.05, { disabled = FOff }))
        p:Dual(T("fader.combat", L["Show in combat"], nil, { disabled = FOff }),
               T("fader.target", L["Show with a target"], nil, { disabled = FOff }))
        p:Dual(T("fader.casting", L["Show while casting"], nil, { disabled = FOff }),
               T("fader.health", L["Show when hurt"], nil, { disabled = FOff }))
        p:Dual(T("fader.power", L["Show when power isn't full"],
                 L["For rage, whenever you have any."], { disabled = FOff }),
               T("fader.mouseover", L["Show under the mouse"], nil, { disabled = FOff }))
    end

    ------------------------------------------------------------------------
    p:Section(L["Aggro glow"])
    local function NoGlow() return Off() or not C().aggroBorder end
    p:Dual(T("aggroBorder", L["Aggro glow"],
             L["The nameplates' red glow, behind the frame. On an enemy it lights when that mob is on you, so it matches the mob's plate. On you or a friend it lights when they're tanking something: amber while threat is climbing, red once they have it. In instances the game hides threat numbers, so there it's red or nothing, and only for the unit's current target."]),
           nil)
    p:Dual(S("aggroAlpha", L["Glow strength"], 0.1, 1, 0.05, { disabled = NoGlow }),
           S("aggroPad", L["Glow reach"], 2, 16, 1, { disabled = NoGlow,
             tooltip = L["How far past the frame the glow reaches, in pixels."] }))
end
