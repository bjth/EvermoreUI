if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Palette.lua
--  The suite's unit colours: hostility, threat, mob type, level difficulty.
--  One copy, here, so a red mob is the same red on its nameplate and on the
--  target frame. Nameplates built these first and the reasoning for each
--  value lives beside them (EvermoreUI_Nameplates/Colours.lua); this file is
--  the values and the two helpers every surface needs.
--
--  Everything here is UNSHADED. Shading is how far a surface dims its fill
--  so white text on it stays readable (full red under white text measures
--  4.00:1, under the 4.5:1 floor; 0.75 gives 6.53:1), and each surface owns
--  its own shade setting. Shade our constants, never a colour on its way to
--  a setter: a colour that came back from a C-side fold may be secret, and
--  arithmetic on a secret throws.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local P = {}
EV.Palette = P

local IsSecret = EV.IsSecret

--- Hostility, in the colours this game has used since 2004.
P.REACTION = {
    hostile    = { 1, 0, 0 },
    unfriendly = { 1, 0.506, 0 },
    neutral    = { 1, 1, 0 },
    friendly   = { 0, 1, 0 },
    tapped     = { 0.431, 0.431, 0.431 },
}

--- Threat, from the reference design's own threat colours.
P.THREAT = {
    safe       = { 0.502, 0.502, 1     },   -- periwinkle
    transition = { 1,     0.702, 0     },   -- amber
    warning    = { 1,     0.047, 0     },   -- red
    offtank    = { 0.682, 0.686, 0.980 },   -- pale blue
}

--- Mob type, sampled off the reference screenshots.
P.TYPE = {
    caster = { 1, 0.294, 0.898 },           -- magenta (255, 75, 229)
    melee  = { 1, 0.722, 0.663 },           -- salmon  (255, 184, 169)
}

P.TARGET = { 0.510, 0.690, 1 }              -- light blue
P.FOCUS  = { 0, 0.812, 1 }                  -- cyan

--- Power, keyed by UnitPowerType's token. Blizzard's PowerBarColor is built
--- to sit on their own textured bars at full strength, and on our flat,
--- shaded frames it does two things badly (measured, WCAG, shade 0.75):
---
---   * MANA (0, 0, 1) is 2.33:1 against the near-black bar background, so an
---     emptying bar reads as a hole rather than as blue. Lifted towards the
---     nameplates' own mana blue: shaded, this lands at 3.01:1 against the
---     background and 6.65:1 under white text, within a hair of the plate's
---     strip (3.07 / 6.53), so a caster's mana is the same weight on both.
---   * ENERGY (1, 1, 0) is 1.07:1 under white text, unreadable. Pulled to a
---     gold: distinct from neutral-yellow health, and 2.6:1 under white,
---     which the text's outline and shadow carry.
---
--- RAGE stays red but a touch crimson, 6.26:1 under white. FOCUS is a burnt
--- orange at 4.28:1. RUNIC_POWER a cyan. These are UNSHADED like everything
--- else here; the frame shades them with the same barShade as its health,
--- so a warrior's rage and a hostile mob's red sit at the same brightness.
P.POWER = {
    MANA        = { 0.18, 0.45, 1    },
    RAGE        = { 1,    0.12, 0.12 },
    ENERGY      = { 1,    0.82, 0.1  },
    FOCUS       = { 1,    0.5,  0.2  },
    RUNIC_POWER = { 0,    0.78, 1    },
}

--- Cast bars. A yellow cast and a green channel is the part of this look
--- people recognise: you read "something is coming" off the colour before
--- you read the spell name.
P.CAST = {
    cast        = { 1,     0.859, 0     },  -- yellow
    channel     = { 0,     1,     0     },  -- green
    shielded    = { 0.494, 0.498, 0.502 },  -- grey, uninterruptible
    interrupted = { 1,     0.102, 0.102 },  -- red
}

--- Class colours, Blizzard's by default (filled in below). Every surface
--- that colours by class asks P.ClassRGB rather than RAID_CLASS_COLORS, so
--- a colour set on the Colours page shows everywhere at once.
P.CLASS = {}

--- Level difficulty, Classic's five steps.
P.DIFFICULTY = {
    impossible    = { 1,    0.1,  0.1  },
    verydifficult = { 1,    0.5,  0.25 },
    difficult     = { 1,    0.82, 0    },
    standard      = { 0.25, 0.75, 0.25 },
    trivial       = { 0.5,  0.5,  0.5  },
}

--- The shade every surface starts at.
P.DEFAULT_SHADE = 0.75

--- dst = src * k, in place. dst is created if missing.
function P.Shade(dst, src, k)
    dst = dst or {}
    for i = 1, 3 do dst[i] = src[i] * k end
    return dst
end

--- A clamped shade value, so a bad saved number cannot blank a bar.
function P.ValidShade(k)
    if type(k) == "number" and k > 0 and k <= 1 then return k end
    return P.DEFAULT_SHADE
end

--- Which hostility key applies to this unit: hostile, unfriendly, neutral,
--- friendly or tapped. Same ladder as the nameplate reaction rule. Every
--- read is guarded: UnitReaction can come back secret, and a secret is
--- treated as unknown rather than compared.
function P.ReactionKey(unit)
    local okT, tapped = pcall(UnitIsTapDenied, unit)
    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if okT and tapped == true and not (okP and isPlayer == true) then return "tapped" end
    local okR, react = pcall(UnitReaction, "player", unit)
    if okR and type(react) == "number" and not IsSecret(react) then
        if react <= 2 then return "hostile" end
        if react == 3 then return "unfriendly" end
        if react == 4 then return "neutral" end
        return "friendly"
    end
    local okA, attack = pcall(UnitCanAttack, "player", unit)
    return (okA and attack == true) and "hostile" or "friendly"
end

--- The difficulty colour for a unit at a level. Retail's content difficulty
--- API where it exists (plain valued here), Classic's level gap otherwise.
function P.Difficulty(unit, lvl)
    local D = P.DIFFICULTY
    local E = Enum and Enum.RelativeContentDifficulty
    if E and C_PlayerInfo and type(C_PlayerInfo.GetContentDifficultyCreatureForPlayer) == "function" then
        local ok, d = pcall(C_PlayerInfo.GetContentDifficultyCreatureForPlayer, unit)
        if ok and type(d) ~= "nil" and not IsSecret(d) then
            if d == E.Trivial then return D.trivial end
            if d == E.Easy then return D.standard end
            if d == E.Fair then return D.difficult end
            if d == E.Difficult then return D.verydifficult end
            if d == E.Impossible then return D.impossible end
        end
    end
    local okP, mine = pcall(UnitEffectiveLevel, "player")
    if not okP or type(mine) ~= "number" or IsSecret(mine)
       or type(lvl) ~= "number" or IsSecret(lvl) then
        return D.difficult
    end
    if lvl == -1 then return D.impossible end
    local diff = lvl - mine
    if diff >= 5 then return D.impossible end
    if diff >= 3 then return D.verydifficult end
    if diff >= -2 then return D.difficult end
    local okG, green = pcall(GetQuestGreenRange)
    if not okG or type(green) ~= "number" then green = 5 end
    if -diff <= green then return D.standard end
    return D.trivial
end

--------------------------------------------------------------------------------
--  Your own colours
--
--  The tables above are the defaults. A profile can override any entry
--  (core.palette[group][key] = { r, g, b }), and Apply writes the result
--  back INTO the same tables, so every surface holding a reference to
--  P.REACTION or P.THREAT.safe sees the change without re-reading anything.
--  Surfaces that cache shaded copies listen for EV_PALETTE_CHANGED.
--------------------------------------------------------------------------------

--- The groups the Colours page shows, in order, and the keys in each.
--- CLASS is filled from the game's own class list.
P.GROUPS = {
    { key = "CLASS",      keys = {} },
    { key = "REACTION",   keys = { "hostile", "unfriendly", "neutral", "friendly", "tapped" } },
    { key = "POWER",      keys = { "MANA", "RAGE", "ENERGY", "FOCUS", "RUNIC_POWER" } },
    { key = "THREAT",     keys = { "safe", "transition", "warning", "offtank" } },
    { key = "TYPE",       keys = { "caster", "melee" } },
    { key = "MARK",       keys = { "target", "focus" } },
    { key = "CAST",       keys = { "cast", "channel", "shielded", "interrupted" } },
    { key = "DIFFICULTY", keys = { "impossible", "verydifficult", "difficult", "standard", "trivial" } },
}

-- Target and focus are single colours rather than a table of them; MARK is
-- the group the page and the saved settings use for the pair.
P.MARK = { target = P.TARGET, focus = P.FOCUS }

-- Classes in the game's own order. GetClassInfo only answers for classes
-- this client has, so Forever lists its nine and not retail's thirteen.
do
    local keys = P.GROUPS[1].keys
    local rcc = RAID_CLASS_COLORS or {}
    local n = type(GetNumClasses) == "function" and GetNumClasses() or 0
    for i = 1, n do
        local ok, _, file = pcall(GetClassInfo, i)
        if ok and type(file) == "string" and rcc[file] then
            keys[#keys + 1] = file
        end
    end
    if #keys == 0 then
        for file in pairs(rcc) do keys[#keys + 1] = file end
        table.sort(keys)
    end
    for _, file in ipairs(keys) do
        local c = rcc[file]
        P.CLASS[file] = { c.r, c.g, c.b }
    end
end

-- Snapshot of the shipped values, taken before any profile is applied.
local DEFAULTS = {}
for _, grp in ipairs(P.GROUPS) do
    local src, dst = P[grp.key], {}
    for _, k in ipairs(grp.keys) do
        local c = src[k]
        if c then dst[k] = { c[1], c[2], c[3] } end
    end
    DEFAULTS[grp.key] = dst
end
P.DEFAULTS = DEFAULTS

--- The profile's overrides, created on first use.
function P.Settings()
    local core = EV.DB and EV.DB.GetCore and EV.dbReady and EV.DB:GetCore()
    if not core then return {} end
    if type(core.palette) ~= "table" then core.palette = {} end
    return core.palette
end

local function ValidColour(c)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

local pending
local function Announce()
    if pending then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        if EV.SendMessage then EV:SendMessage("EV_PALETTE_CHANGED") end
    end)
end

--- Defaults first, then the profile's overrides, written into the live
--- tables in place.
function P.Apply()
    local over = P.Settings()
    for _, grp in ipairs(P.GROUPS) do
        local live, def, mine = P[grp.key], DEFAULTS[grp.key], over[grp.key]
        for k, d in pairs(def) do
            local c = live[k]
            if not c then c = {}; live[k] = c end
            local o = type(mine) == "table" and mine[k]
            local src = ValidColour(o) and o or d
            c[1], c[2], c[3] = src[1], src[2], src[3]
        end
    end
    Announce()
end

function P.Get(group, key)
    local c = P[group] and P[group][key]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

function P.Set(group, key, r, g, b)
    if not (DEFAULTS[group] and DEFAULTS[group][key]) then return end
    local over = P.Settings()
    over[group] = type(over[group]) == "table" and over[group] or {}
    over[group][key] = { r, g, b }
    P.Apply()
end

function P.IsCustom(group, key)
    local over = P.Settings()
    return type(over[group]) == "table" and ValidColour(over[group][key]) or false
end

function P.Reset(group, key)
    local over = P.Settings()
    if type(over[group]) == "table" then
        over[group][key] = nil
        if next(over[group]) == nil then over[group] = nil end
    end
    P.Apply()
end

function P.ResetAll()
    local core = EV.DB and EV.dbReady and EV.DB:GetCore()
    if core then core.palette = {} end
    P.Apply()
end

--- A class colour as r, g, b: yours if you set one, the game's otherwise.
function P.ClassRGB(classFile)
    -- UnitClass can hand back a secret in restricted content, and a secret
    -- can't be used as a table key. No colour then; callers fall back.
    if type(classFile) ~= "string" or (issecretvalue and issecretvalue(classFile)) then return nil end
    local c = P.CLASS[classFile]
    if c then return c[1], c[2], c[3] end
    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if rc then return rc.r, rc.g, rc.b end
end

--------------------------------------------------------------------------------
--  Sharing: unit colours and interface colours as one line of text
--------------------------------------------------------------------------------
function P.Export()
    local theme = EV.Theme and EV.Theme.Settings and EV.Theme.Settings() or {}
    return EV.Serialize.Encode({
        v = 1, kind = "palette",
        units = EV.CopyTable(P.Settings()),
        ui = EV.CopyTable(type(theme.custom) == "table" and theme.custom or {}),
    })
end

function P.Import(text)
    local data, err = EV.Serialize.Decode(text)
    if not data then return false, err end
    if type(data) ~= "table" or data.kind ~= "palette" then
        return false, "that string doesn't hold a colour palette"
    end
    local core = EV.DB:GetCore()
    core.palette = {}
    if type(data.units) == "table" then
        for group, keys in pairs(data.units) do
            if DEFAULTS[group] and type(keys) == "table" then
                for k, c in pairs(keys) do
                    if DEFAULTS[group][k] and ValidColour(c) then
                        core.palette[group] = core.palette[group] or {}
                        core.palette[group][k] = { c[1], c[2], c[3] }
                    end
                end
            end
        end
    end
    if EV.Theme and EV.Theme.ImportCustom then EV.Theme.ImportCustom(data.ui) end
    P.Apply()
    return true
end

--------------------------------------------------------------------------------
--  Apply once the DB is up, and after profile switches
--------------------------------------------------------------------------------
hooksecurefunc(EV, "_RebindModules", function() P.Apply() end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= EV.name then return end
    if event == "PLAYER_LOGIN" then self:UnregisterAllEvents() end
    if EV.dbReady then P.Apply() end
end)
