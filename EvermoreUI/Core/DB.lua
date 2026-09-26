if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  DB.lua
--  One SavedVariables table for the whole suite. Children declare none.
--
--  EvermoreUIDB = {
--      schema      = 1,
--      profileKeys = { ["Name - Realm"] = "Default" },
--      profiles    = { Default = { core = {...}, modules = { DataBars = {...} } } },
--      _probe      = { lastWrite = <time>, writes = <n> },
--  }
--
--  Defaults are deep-merged in on bind and stripped out at logout, so the
--  file only ever holds what the user changed.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local DB = {}
EV.DB = DB

local SCHEMA = 1
local DEFAULT_PROFILE = "Default"

local CORE_DEFAULTS = {
    movers   = {},   -- [key] = { point, relPoint, x, y }
    anchors  = {},   -- [key] = { target, side, align, x, y }
    matches  = {},   -- [key] = { w = targetKey, h = targetKey }
    disabled = {},   -- [moduleName] = true
    theme    = { contrast = "standard" },
    font     = "Roboto Condensed",   -- General > Font: every EvermoreUI surface, and Blizzard's
    blizzardFonts = true,  -- carry it into Blizzard's own font objects
    -- Blizzard's per-texture pixel snapping. Off across the whole UI: it
    -- rounds each region independently, which makes anything at a moving
    -- fractional position shimmer against itself. Long note in Pixel.lua.
    pixelSnapping = false,
    gameMenuButton = true,        -- EvermoreUI button in the Escape menu
    gameMenuEditButton = false,   -- and an Edit Mode button under it
}

local moduleDefaults = {}  -- name -> defaults (for stripping)
local touched = {}         -- profile names that had defaults merged this session
local charKey

--------------------------------------------------------------------------------
--  Table helpers
--------------------------------------------------------------------------------
local function Merge(dest, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(dest[k]) ~= "table" then dest[k] = {} end
            Merge(dest[k], v)
        elseif dest[k] == nil then
            dest[k] = v
        end
    end
end

local function Strip(dest, defaults)
    for k, v in pairs(defaults) do
        local cur = dest[k]
        if type(v) == "table" then
            if type(cur) == "table" then
                Strip(cur, v)
                if next(cur) == nil then dest[k] = nil end
            end
        elseif cur == v then
            dest[k] = nil
        end
    end
end

DB.Merge, DB.Strip = Merge, Strip

--------------------------------------------------------------------------------
--  Profile access
--------------------------------------------------------------------------------
local function Store() return EvermoreUIDB end

function DB:GetProfileName()
    return Store().profileKeys[charKey] or DEFAULT_PROFILE
end

local function ProfileTable(name)
    local profiles = Store().profiles
    local p = profiles[name]
    if type(p) ~= "table" then
        p = {}
        profiles[name] = p
    end
    if type(p.modules) ~= "table" then p.modules = {} end
    if type(p.core) ~= "table" then p.core = {} end
    touched[name] = true
    return p
end

function DB:GetProfile()
    return ProfileTable(self:GetProfileName())
end

function DB:GetCore()
    local core = self:GetProfile().core
    Merge(core, CORE_DEFAULTS)
    return core
end

--- Returns this module's table in the active profile with defaults merged.
function DB:BindModule(name, defaults)
    moduleDefaults[name] = defaults or {}
    local mods = self:GetProfile().modules
    if type(mods[name]) ~= "table" then mods[name] = {} end
    Merge(mods[name], moduleDefaults[name])
    return mods[name]
end

--- Account-wide settings that aren't part of any profile (the experimental
--- switches).
function DB:GetGlobal()
    local store = Store()
    if type(store.global) ~= "table" then store.global = {} end
    return store.global
end

--- Per-character data that isn't a setting (session stats and the like).
--- Lives outside profiles, so switching profile doesn't touch it.
function DB:GetCharData(key)
    local store = Store()
    if type(store.chars) ~= "table" then store.chars = {} end
    local c = store.chars[charKey]
    if type(c) ~= "table" then c = {}; store.chars[charKey] = c end
    if type(c[key]) ~= "table" then c[key] = {} end
    return c[key]
end

--- Every character's data table, keyed "Name - Realm": the account-wide
--- side of per-character data, for anything that compares characters.
function DB:AllChars()
    local store = Store()
    if type(store.chars) ~= "table" then store.chars = {} end
    return store.chars
end

--- Drop everything kept for a character (not the one you are playing).
function DB:ForgetChar(key)
    if key == charKey then return false end
    local all = self:AllChars()
    if all[key] == nil then return false end
    all[key] = nil
    return true
end

function DB:ListProfiles()
    local list = {}
    for name in pairs(Store().profiles) do list[#list + 1] = name end
    table.sort(list)
    return list
end

--- Switch this character to a profile, creating it if needed.
function DB:SetProfile(name)
    if type(name) ~= "string" or name == "" then return end
    Store().profileKeys[charKey] = name
    ProfileTable(name)
    EV:_RebindModules()
end

--- Overwrite the active profile with a copy of another.
function DB:CopyProfile(from)
    if type(from) ~= "string" then return end
    local src = Store().profiles[from]
    if not src or from == self:GetProfileName() then return end
    local dest = self:GetProfile()
    wipe(dest)
    for k, v in pairs(EV.CopyTable(src)) do dest[k] = v end
    EV:_RebindModules()
end

--------------------------------------------------------------------------------
--  Profile strings (Core\Serialize.lua): share a profile, keep a backup, or
--  put one back after a reinstall.
--------------------------------------------------------------------------------
--- The active profile as a string, or nil and a reason.
function DB:ExportProfile()
    local p = self:GetProfile()
    local payload = {
        v = 1,
        schema = Store().schema or SCHEMA,
        name = self:GetProfileName(),
        profile = EV.CopyTable(p),
    }
    return EV.Serialize.Encode(payload)
end

--- Read a profile string without applying it: name, and the table itself.
function DB:ReadProfileString(text)
    local data, err = EV.Serialize.Decode(text)
    if not data then return nil, err end
    if type(data) ~= "table" or type(data.profile) ~= "table" then
        return nil, "that string doesn't hold a profile"
    end
    return data
end

--- Apply a profile string. Into the active profile by default, or into a
--- profile of the given name (created if it doesn't exist).
function DB:ImportProfile(text, intoName)
    local data, err = self:ReadProfileString(text)
    if not data then return false, err end
    local name = intoName or self:GetProfileName()
    local dest = ProfileTable(name)
    wipe(dest)
    for k, v in pairs(EV.CopyTable(data.profile)) do dest[k] = v end
    if type(dest.modules) ~= "table" then dest.modules = {} end
    if type(dest.core) ~= "table" then dest.core = {} end
    if name ~= self:GetProfileName() then
        self:SetProfile(name)
    else
        EV:_RebindModules()
    end
    return true, data.name
end

function DB:ResetProfile()
    wipe(self:GetProfile())
    EV:_RebindModules()
end

function DB:DeleteProfile(name)
    if type(name) ~= "string" or name == self:GetProfileName() or name == DEFAULT_PROFILE then return false end
    local store = Store()
    store.profiles[name] = nil
    for key, p in pairs(store.profileKeys) do
        if p == name then store.profileKeys[key] = nil end
    end
    touched[name] = nil
    return true
end

--------------------------------------------------------------------------------
--  Lifecycle (driven by Framework.lua)
--------------------------------------------------------------------------------
-- Keys left behind by the Sept 2026 beta workarounds (restore file, the
-- per-character mirror, the load trace). Cleared on load so old files shrink.
local LEGACY_KEYS = { "_loadTrace", "_svTimeline" }

local function Prepare(store)
    store.schema = store.schema or SCHEMA
    if type(store.profiles) ~= "table" then store.profiles = {} end
    if type(store.profileKeys) ~= "table" then store.profileKeys = {} end
    for _, k in ipairs(LEGACY_KEYS) do store[k] = nil end
end

function DB:Init()
    local loaded = type(EvermoreUIDB) == "table"
    EV.Caps.svLoaded = loaded
    if not loaded then EvermoreUIDB = {} end
    local store = EvermoreUIDB
    Prepare(store)

    -- What the last session wrote, for /evui caps and bug reports.
    local probe = type(store._probe) == "table" and store._probe or nil
    self.previousWrite = probe and probe.lastWrite or nil
    self.writeCount    = probe and probe.writes or 0

    charKey = (UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown")
    self.charKey = charKey
    ProfileTable(self:GetProfileName())
end

function DB:Shutdown()
    local store = EvermoreUIDB
    if type(store) ~= "table" then return end
    for name in pairs(touched) do
        local p = store.profiles[name]
        if p then
            if p.core then Strip(p.core, CORE_DEFAULTS) end
            if p.modules then
                for modName, defaults in pairs(moduleDefaults) do
                    local t = p.modules[modName]
                    if t then
                        Strip(t, defaults)
                        if next(t) == nil then p.modules[modName] = nil end
                    end
                end
            end
        end
    end
    store._probe = { lastWrite = time(), writes = (self.writeCount or 0) + 1 }
end
