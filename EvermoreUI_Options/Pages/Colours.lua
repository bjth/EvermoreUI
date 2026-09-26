if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Colours: your own palette. Unit colours (class, hostility, power, threat,
--  mob type, target and focus, cast bars, level) are EV.Palette; interface
--  colours are theme tokens. Both are saved in the profile, travel with a
--  profile string, and can be shared on their own as a palette string.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local P = EV.Palette
local T = EV.Theme

local TAB_UNITS = L["Units"]
local TAB_UI    = L["Interface"]

local SECTIONS = {
    CLASS      = L["Class"],
    REACTION   = L["Hostility"],
    POWER      = L["Power"],
    THREAT     = L["Threat"],
    TYPE       = L["Mob type"],
    MARK       = L["Target and focus"],
    CAST       = L["Cast bars"],
    DIFFICULTY = L["Level"],
}

local LABELS = {
    REACTION = {
        hostile = L["Hostile"], unfriendly = L["Unfriendly"], neutral = L["Neutral"],
        friendly = L["Friendly"], tapped = L["Tapped"],
    },
    THREAT = {
        safe = L["Safe"], transition = L["Slipping"], warning = L["Warning"], offtank = L["Off-tank"],
    },
    TYPE = { caster = L["Caster"], melee = L["Melee"] },
    MARK = { target = L["Target"], focus = L["Focus"] },
    CAST = {
        cast = L["Cast"], channel = L["Channel"], shielded = L["Can't be interrupted"],
        interrupted = L["Interrupted"],
    },
    DIFFICULTY = {
        impossible = L["Skull (5+ above)"], verydifficult = L["Orange (3-4 above)"],
        difficult = L["Yellow (around you)"], standard = L["Green"], trivial = L["Grey"],
    },
}

local TIPS = {
    THREAT = L["Safe is the good state for your role and warning the bad one: holding aggro is safe for a tank and a warning for everyone else."],
    TYPE = L["Nameplates colour mobs that are not attacking you by what they are: casters (they have mana) and melee."],
    CAST = L["Nameplate cast bars."],
    DIFFICULTY = L["Level text on unit frames and nameplates."],
}

local UI_LABELS = {
    accent = L["Accent"], onAccent = L["Text on accent"], title = L["Headings"],
    text = L["Text"], textMuted = L["Muted text"],
    surface0 = L["Window background"], surface1 = L["Panels"], surface2 = L["Controls"],
    border = L["Borders"], borderStrong = L["Control edges"],
    danger = L["Danger"], success = L["Success"], warning = L["Warning"],
    xp = L["Experience (start)"], xpEnd = L["Experience (end)"], quest = L["Quest experience"],
    rested = L["Rested"],
}

local function Label(group, key)
    if group == "CLASS" then
        return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[key]) or key
    elseif group == "POWER" then
        local g = _G[key]
        return type(g) == "string" and g or key
    end
    return (LABELS[group] and LABELS[group][key]) or key
end

local function UnitCell(group, key)
    return {
        type = "colour", text = Label(group, key),
        get = function() return P.Get(group, key) end,
        set = function(r, g, b) P.Set(group, key, r, g, b) end,
        reset = function() P.Reset(group, key) end,
        isCustom = function() return P.IsCustom(group, key) end,
    }
end

local function UICell(token)
    return {
        type = "colour", text = UI_LABELS[token] or token,
        get = function() return T.RGBA(token) end,
        set = function(r, g, b) T.SetCustom(token, r, g, b) end,
        reset = function() T.ResetCustom(token) end,
        isCustom = function() return T.IsCustom(token) end,
    }
end

-- Two swatches to a row.
local function Pairs(p, cells)
    for i = 1, #cells, 2 do p:Dual(cells[i], cells[i + 1]) end
end

local function Share(p)
    p:Section(L["Share"])
    p:Note(L["A palette string is every colour on this page, units and interface, as one line of text. It is also part of your profile, so a profile string carries it too."], 0.8)
    p:Dual(
        { type = "button", text = L["Copy your colours out"], label = L["Export"], width = 110,
          onClick = function()
              local str, err = P.Export()
              if not str then EV:Print(L["Couldn't export:"], tostring(err)); return end
              EV.UI.ShowCopyText(L["Export palette"], str, L["Select all is done for you. Ctrl+C to copy."])
          end },
        { type = "button", text = L["Paste a palette in"], label = L["Import"], width = 110,
          onClick = function()
              EV.UI.ShowPasteText(L["Import palette"],
                  L["Paste a palette string. It replaces the colours in your active profile."],
                  L["Import"], function(text)
                      local ok, err = P.Import(text)
                      if not ok then return err end
                      EV:Print(L["Palette imported."])
                      EV.Options:RefreshCurrent()
                  end)
          end })
end

local function Units(p)
    p:Note(L["Your own colours for everything that shows a unit: unit frames, nameplates, tooltips and chat. Bars are dimmed by each surface's own bar brightness setting, so pick the full strength colour."], 0.8)
    for _, grp in ipairs(P.GROUPS) do
        p:Section(SECTIONS[grp.key] or grp.key)
        if TIPS[grp.key] then p:Note(TIPS[grp.key], 0.7) end
        local cells = {}
        for _, k in ipairs(grp.keys) do cells[#cells + 1] = UnitCell(grp.key, k) end
        Pairs(p, cells)
    end
    Share(p)
end

local function Contrast(p)
    local function mark(a, b, floor)
        local v = T.Contrast(a, b)
        local tok = v >= floor and "success" or "danger"
        return "|cff" .. T.Hex(tok) .. ("%.1f:1"):format(v) .. "|r"
    end
    p:Note(L["Readability check (WCAG): text on panels %s, muted text %s, text on accent %s, control edges %s. Green meets the level the built-in colours are held to."]:format(
        mark("text", "surface1", 7), mark("textMuted", "surface1", 4.5),
        mark("onAccent", "accent", 4.5), mark("borderStrong", "surface1", 3)), 0.9)
end

local function Interface(p)
    p:Note(L["Your own colours for EvermoreUI's windows, chat, tooltips, bars and skinned Blizzard windows. They sit on top of the contrast setting on the General page, and hover and pressed states still follow it."], 0.8)
    Contrast(p)
    local groups = {
        { L["Accent and text"], { "accent", "onAccent", "title", "text", "textMuted" } },
        { L["Surfaces"], { "surface0", "surface1", "surface2", "border", "borderStrong" } },
        { L["States"], { "danger", "success", "warning" } },
        { L["Progress bars"], { "xp", "xpEnd", "quest", "rested" } },
    }
    for _, g in ipairs(groups) do
        p:Section(g[1])
        local cells = {}
        for _, token in ipairs(g[2]) do cells[#cells + 1] = UICell(token) end
        Pairs(p, cells)
    end
    Share(p)
end

EV.Options:RegisterPage{
    key = "colours", title = L["Colours"], group = "General",
    description = L["Build your own palette: class, hostility, power and every other unit colour, plus the interface itself."],
    tabs = { TAB_UNITS, TAB_UI },
    build = function(p, tab)
        if tab == TAB_UI then return Interface(p) end
        return Units(p)
    end,
    onReset = function(tab)
        if tab == TAB_UI then
            T.ResetCustom()
        else
            P.ResetAll()
        end
    end,
}
