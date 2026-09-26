if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Settings.lua
--  Every nameplate setting, written once. The designer shows them with the
--  part they belong to (the health bar's look with the health bar, the cast
--  bar's with the cast bar) and the rest under Plate behaviour; the options
--  page opens the designer. One copy, so the two can never disagree.
--
--  ns.Settings(p, pick): p is an options page builder. pick chooses what to
--  draw: { sections = { [title] = true | { [key] = true } } }. A section
--  mapped to true is drawn whole; to a key set, only those settings; a
--  section not named is skipped. nil draws everything.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L

local HEALTH_TEXT = {
    { value = "none",       text = L["None"] },
    { value = "percent",    text = L["87%"] },
    { value = "current",    text = L["12.3k"] },
    { value = "curpercent", text = L["12.3k  87%"] },
}
local SLOT_SIDE = {
    { value = "none",      text = L["Nothing"] },
    { value = "levelname", text = L["Level and name"] },
    { value = "name",      text = L["Name"] },
    { value = "level",     text = L["Level"] },
    { value = "health",    text = L["Health"] },
}
local SLOT_CENTRE = {
    { value = "none",   text = L["Nothing"] },
    { value = "name",   text = L["Name"] },
    { value = "level",  text = L["Level"] },
    { value = "health", text = L["Health"] },
}
local COLOURS = {
    { value = "reaction", text = L["Reaction"] },
    { value = "class",    text = L["Class (players)"] },
}
local TEXT_STYLE = {
    { value = "both",    text = L["Outline and shadow"] },
    { value = "shadow",  text = L["Shadow only"] },
    { value = "outline", text = L["Outline only"] },
}
local POWER_MODE = {
    { value = "mana", text = L["Only units with mana"] },
    { value = "any",  text = L["Any resource"] },
}
local PIXEL_MODE = {
    { value = "smooth", text = L["Smooth (follows the mob exactly)"] },
    { value = "crisp",  text = L["Crisp (snaps to pixels, steps as it moves)"] },
}
local COMBO_SPOT = {
    { value = "bottom", text = L["Bottom edge of the bar"] },
    { value = "top",    text = L["Top edge of the bar"] },
}
local TANK_MODE = {
    { value = "auto", text = L["Auto (from your role)"] },
    { value = "tank", text = L["Always tank colours"] },
    { value = "dps",  text = L["Always dps colours"] },
}

local function Textures()
    local list = {}
    for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
    return list
end


--- A builder that draws only what `pick` asks for, one setting per row (the
--- designer's inspector is narrow, so pairs go one under the other).
local function Picker(p, pick)
    local sections = pick and pick.sections
    local current, want = nil, not sections
    local q = {}
    local function Wanted(cfg)
        if not cfg then return false end
        if not sections then return true end
        if want == true then return true end
        if type(want) == "table" then return cfg.key ~= nil and want[cfg.key] == true end
        return false
    end
    function q:Section(text)
        current = text
        want = not sections or sections[text]
        if want then p:Section(text) end
    end
    function q:Dual(a, b)
        if not sections then
            p:Dual(a, b)
            return
        end
        if Wanted(a) then p:Row(a) end
        if Wanted(b) then p:Row(b) end
    end
    function q:Row(cfg) if Wanted(cfg) then p:Row(cfg) end end
    function q:Note(text) if want == true then p:Note(text) end end
    function q:Banner(...) if not sections then p:Banner(...) end end
    return q
end

function ns.Settings(builder, pick)
    local M = ns.module
    local p = Picker(builder, pick)
    local function Get(k) return function() return M.db[k] end end
    local function Set(k) return function(v) M.db[k] = v; M:Restyle() end end
    local function T(k, text, tip, extra)
        local cfg = { key = k, type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k) }
        if extra then for a, b in pairs(extra) do cfg[a] = b end end
        return cfg
    end
    local function S(k, text, lo, hi, step, extra)
        local cfg = { key = k, type = "slider", text = text, min = lo, max = hi, step = step,
                      get = Get(k), set = Set(k) }
        if extra then for a, b in pairs(extra) do cfg[a] = b end end
        return cfg
    end
    local function D(k, text, values, width, extra)
        local cfg = { key = k, type = "dropdown", text = text, values = values, width = width or 170,
                      get = Get(k), set = Set(k) }
        if extra then for a, b in pairs(extra) do cfg[a] = b end end
        return cfg
    end

    p:Section(L["Plate"])
    p:Dual(S("scale", L["Overall scale"], 0.6, 2, 0.05,
             { tooltip = L["Scales the whole plate, text and icons included. Everything below stays in the units it is written in; this multiplies the lot."] }),
           S("targetScale", L["Target scale"], 1, 1.5, 0.05,
             { tooltip = L["Applied by the game rather than by us, through its own nameplateSelectedScale. Scaling the target frame ourselves made it the one plate in the game computing its geometry in a different space from every other, which is why it behaved differently from the rest."] }))
    p:Dual(S("width", L["Width"], 60, 320, 1), S("height", L["Height"], 8, 48, 1))
    p:Dual(T("offscreenPlates", L["Keep plates on screen"],
             L["Off. On, the game pins a plate to the edge of the screen once its mob walks out of view, so the plate stops following the mob and starts following the window."]),
           T("stackPlates", L["Stack plates so they never overlap"],
             L["On, and it is doing more than stopping plates overlapping. Stacking is the game's motion system: with it on, plate positions are interpolated instead of taken raw from the 3D projection every frame, and that interpolation is the only movement smoothing that exists. It lives on the C side because that is the only place a plate's position can be read at all, which is why no addon can build its own. Turning this off makes plates track the mob exactly, frame by frame, judder included."]))
    -- nameplateMotionSpeed doesn't exist on Forever (nppx: CVAR ABSENT),
    -- so the slider only appears on a client that has it.
    if C_CVar and C_CVar.GetCVarInfo and C_CVar.GetCVarInfo("nameplateMotionSpeed") ~= nil then
        p:Dual(S("plateMotionSpeed", L["Movement smoothing"], 0.005, 0.5, 0.005,
                 { tooltip = L["Lower is smoother and laggier. 0.025 is the usual choice. It only does anything while stacking is on, because it rides the same system."],
                   disabled = function() return not M.db.stackPlates end }), nil)
    end
    p:Dual(D("pixelMode", L["Movement"], PIXEL_MODE, 250,
             { tooltip = L["Opposites, not a dial. Smooth quantises nothing: the glyphs and the textures both draw at exact sub pixel positions, so the plate translates with the mob and nothing on it moves relative to anything else, at the cost of being very slightly soft. Crisp is Blizzard's combination: edges land on exact pixels and the whole plate steps one pixel at a time as the mob walks. Mixing the two is what made everything jump."] }), nil)
    p:Dual(T("pinPlateScale", L["Pin Blizzard's plate scaling"],
             L["On, and it is what stops the jitter. The game rescales its own nameplates continuously as a mob's distance changes, and ours are drawn inside them, so every border and every letter is being rounded against a scale that has already moved. Pinning it to 1 makes the scale sliders above the only ones in play. Turning this off hands your own settings back."]), nil)
    p:Dual(S("verticalOffset", L["Height above the mob"], -40, 40, 1,
             { tooltip = L["Nudges the whole plate up or down over the model. Scaling the plate up moves its centre with it, so a larger plate usually wants pulling back down."] }),
           S("friendlyVerticalOffset", L["Friendly height above the mob"], -60, 40, 1,
             { tooltip = L["The same for friendly plates, which are a separate number because they are a separate problem. Blizzard anchor a name-only plate's name to the top of its health bar, above its cast bar, and neither bar gives up its height when hidden, so the name floats a whole bar stack clear of the unit. Negative pulls it down."] }))
    p:Dual(D("texture", L["Texture"], Textures, 150),
           D("healthColour", L["Health colour"], COLOURS, 170))
    p:Dual(S("barShade", L["Bar brightness"], 0.5, 1, 0.05,
             { tooltip = L["Dims the fill so the text on it can be read. White on a full red bar measures 4.0:1 contrast, which is below the readable floor; at 0.75 it is 6.5:1 and the red is still unmistakably red."] }), nil)
    p:Dual(T("typeColour", L["Colour casters differently"],
             L["Off by default. The game has no flag for it, so it is inferred from whether the mob has a mana bar, and on the bar it competes with threat and hostility for the same colour."]),
           T("typeInInstancesOnly", L["Only in instances"],
             nil, { disabled = function() return not M.db.typeColour end }))
    p:Dual(T("doFriendly", L["Draw friendly plates too"],
             L["Off by default: ours are built for enemies, and a friendly plate mostly wants to be a name. Blizzard's friendly plates are left alone apart from the height slider above, which moves theirs too."]), nil)

    p:Section(L["Text"])
    p:Dual(D("textLeft", L["Left of the bar"], SLOT_SIDE, 170),
           D("textRight", L["Right of the bar"], SLOT_SIDE, 170))
    p:Dual(D("textCentre", L["Middle of the bar"], SLOT_CENTRE, 170,
             { tooltip = L["Each thing can only be in one place. If two slots ask for the same one, the first reading left to right keeps it. The level is coloured by difficulty, Classic style, and shows ?? for a skull."] }), nil)
    p:Dual(T("showQuest", L["Quest objective count"],
             L["How many of this mob you still need, top right above the plate. Read from the unit tooltip, once per plate."]), nil)
    p:Dual(D("healthText", L["Health format"], HEALTH_TEXT, 170),
           S("fontSize", L["Font size"], 8, 20, 1))
    p:Dual(D("textStyle", L["Text edge"], TEXT_STYLE, 190,
             { tooltip = L["The default is both: an outline on every side of a glyph plus a shadow below it. Shadow only is cleaner at small sizes because nothing closes up the inside of a letter."] }),
           S("borderSize", L["Border thickness"], 1, 3, 1))
    p:Dual(T("innerShadow", L["Inset shading"],
             L["A dark ramp just inside the border, top and bottom, which is what makes the bar look inset rather than flat."]), nil)

    p:Section(L["Cast bar"])
    local function noCast() return not M.db.showCast end
    p:Dual(T("showCast", L["Show cast bar"]),
           S("castHeight", L["Cast bar height"], 0, 20, 1, { disabled = noCast }))
    p:Dual(S("castGap", L["Gap above the cast bar"], 0, 10, 1, { disabled = noCast }),
           T("showCastText", L["Spell name and time"], nil, { disabled = noCast }))
    p:Dual(T("showCastTarget", L["Who it is aimed at"],
             L["The cast target, class coloured, on the right of the cast bar. Worth having on a healer or an interrupter."],
             { disabled = noCast }), nil)

    p:Section(L["Power"])
    local function noPower() return not M.db.showPower end
    p:Dual(T("showPower", L["Show the mob's resource"],
             L["A thin strip under the health bar. The game has no flag for a caster, so having mana IS the caster test -- and showing the mana says the same thing as recolouring the bar while also telling you how much is left."]),
           D("powerMode", L["Which units"], POWER_MODE, 190,
             { disabled = noPower }))
    p:Dual(S("powerHeight", L["Strip height"], 2, 16, 1, { disabled = noPower }),
           S("powerGap", L["Gap below the plate"], 0, 10, 1, { disabled = noPower }))

    p:Section(L["Auras"])
    p:Dual(T("showAuras", L["Your dots"],
             L["Tracked by the client's own aura containers, so the timers keep working in instances where an addon cannot read auras at all."]),
           T("showCC", L["Crowd control"]))
    p:Dual(T("showBuffs", L["Enemy buffs"]),
           S("auraSize", L["Icon size"], 12, 32, 1))
    p:Dual(S("auraRatio", L["Icon shape"], 0.5, 1, 0.05,
             { tooltip = L["How tall your dot icons are against their width. Below 1 they are letterboxed, which is how a row of six fits over the bar without towering above it."] }), nil)
    p:Note(L["A change here rebuilds the icon pools: the client fixes an aura group's filter and element size when the group is created, so they cannot be resized in place."])

    p:Section(L["Aggro"])
    p:Dual(T("aggroBackdrop", L["Red glow when it is on you"],
             L["A soft halo around the plate, built from the client's own glow border art. Driven by a secret boolean folded into alpha by the client, so unlike threat numbers it keeps working in instances."]),
           S("aggroAlpha", L["Glow strength"], 0.1, 0.6, 0.05,
             { disabled = function() return not M.db.aggroBackdrop end }))
    p:Dual(S("aggroPad", L["How far it reaches"], 2, 16, 1,
             { disabled = function() return not M.db.aggroBackdrop end }), nil)

    p:Section(L["Threat"])
    p:Dual(T("threatColour", L["Colour health by threat"]),
           D("tankMode", L["Colour set"], TANK_MODE, 190,
             { disabled = function() return not M.db.threatColour end }))
    p:Dual(T("threatInCombatOnly", L["Only in combat"],
             L["Out of combat nothing holds threat on anything, so the colour would only ever be noise."],
             { disabled = function() return not M.db.threatColour end }),
           T("threatSafeColour", L["Colour the safe state too"],
             L["Off by default. With it off the bar keeps its hostility colour until something is actually going wrong, which is what makes threat quiet rather than a light show."],
             { disabled = function() return not M.db.threatColour end }))
    p:Dual(T("threatInInstancesOnly", L["Only in instances"],
             L["Threat colouring is already skipped when you are not in a group, so this only removes it from world group content."],
             { disabled = function() return not M.db.threatColour end }), nil)

    p:Section(L["Target"])
    p:Dual(T("targetHalo", L["Light glow around the target"],
             L["A soft white halo outside the plate, the same glow as the aggro one. Marks the target without drawing inside the bar, so the plate does not look inset. With this on, the target's border stays black."]),
           S("targetHaloAlpha", L["Glow strength"], 0.1, 0.8, 0.05,
             { disabled = function() return not M.db.targetHalo end }))
    p:Dual(T("targetBorder", L["Coloured border on target and focus"],
             L["The focus's border goes cyan. The target's goes white only when the glow above is off."]), nil)
    p:Dual(T("targetColour", L["Colour the target's bar as well"],
             L["Paints the target's health bar light blue. It reads well, but it costs you the threat colour on the one mob you are most likely to pull off the tank."]),
           T("showTargetGlow", L["Underline the target"],
             L["A glow below the plate. Off: on a mob with no cast bar showing it reads as a mana bar."]))
    p:Dual(S("nonTargetAlpha", L["Other plates opacity"], 0.3, 1, 0.05,
             { tooltip = L["1 disables the fade entirely, and with it the only pass that touches every plate on a target change."] }), nil)

    if EV.HasComboClass and EV.HasComboClass() then
        local function noCombo() return not M.db.comboPoints end
        p:Section(L["Combo points"])
        p:Dual(T("comboPoints", L["On your target's plate"],
                 L["Your combo points as a row of pips across the edge of your target's health bar, so you can read them without looking away from the mob. They're on the player frame too."]),
               D("comboSpot", L["Where"], COMBO_SPOT, 190, { disabled = noCombo }))
        p:Dual(S("comboWidth", L["Pip width"], 4, 30, 1, { disabled = noCombo }),
               S("comboHeight", L["Pip height"], 2, 16, 1, { disabled = noCombo }))
        p:Dual(S("comboSpacing", L["Spacing"], 0, 10, 1, { disabled = noCombo }),
               S("comboY", L["Nudge up or down"], -30, 30, 1, { disabled = noCombo }))
        p:Dual({ key = "comboColour", type = "colour", text = L["Colour"], disabled = noCombo,
                 get = function() local c = M.db.comboColour or { 1, 0.86, 0.1 }; return c[1], c[2], c[3] end,
                 set = function(r, g, b) M.db.comboColour = { r, g, b }; M:Restyle() end,
                 reset = function() M.db.comboColour = { 1, 0.86, 0.1 }; M:Restyle() end,
                 isCustom = function()
                     local c = M.db.comboColour
                     return type(c) == "table" and (math.abs(c[1] - 1) > 0.002 or math.abs(c[2] - 0.86) > 0.002
                                                    or math.abs(c[3] - 0.1) > 0.002)
                 end }, nil)
    end

    p:Section(L["Execute range"])
    p:Dual(T("executeGlow", L["Glow below a health threshold"]),
           S("executeAt", L["Threshold"], 0.1, 0.5, 0.05,
             { disabled = function() return not M.db.executeGlow end }))

    p:Note(L["Everything here is event driven. The only per-frame work in this module is the cast bar fill, which is attached when a cast starts and removed when it stops."])
end
