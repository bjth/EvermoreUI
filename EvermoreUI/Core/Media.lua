if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Media.lua
--  Our own media registry. No vendored libraries: if another addon has loaded
--  LibSharedMedia, we register into it and can resolve its media too, but
--  nothing here depends on it being present.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local Media = {}
EV.Media = Media

local registry = {
    font = {
        -- Roboto Condensed SemiBold, Apache 2.0. A static instance cut from
        -- Google's variable master at wght=600. Chosen on measurement rather
        -- than taste: x-height is 52.8% of the em against Barlow's 50.9%, so
        -- it renders visibly larger at the same nominal height, it is the
        -- narrowest of the candidates per character so long mob names fit,
        -- and it carries all 64 core Cyrillic letters where Barlow carries
        -- none.
        ["Roboto Condensed"] = "Interface\\AddOns\\EvermoreUI\\Media\\Fonts\\RobotoCondensed-SemiBold.ttf",
        -- Barlow Semi Condensed, SIL Open Font License (Media/Fonts/OFL.txt)
        ["Barlow"]          = "Interface\\AddOns\\EvermoreUI\\Media\\Fonts\\Barlow-Medium.ttf",
        ["Barlow SemiBold"] = "Interface\\AddOns\\EvermoreUI\\Media\\Fonts\\Barlow-SemiBold.ttf",
        ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
        ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    },
    statusbar = {
        ["Flat"]     = "Interface\\Buttons\\WHITE8X8",
        ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    },
}

local DEFAULTS = { font = "Roboto Condensed", statusbar = "Flat" }

-- The heavier cut we use for titles and emphasis, per family. A font with no
-- entry here is its own bold.
local BOLD = {
    ["Barlow"] = "Barlow SemiBold",
}
Media.BOLD = BOLD

-- Our own media folder: Interface\AddOns\EvermoreUI\Media\...
Media.PATH = "Interface\\AddOns\\EvermoreUI\\Media\\"

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function Media:Register(kind, name, path)
    registry[kind] = registry[kind] or {}
    registry[kind][name] = path
    local lsm = LSM()
    if lsm then lsm:Register(kind, "EvermoreUI " .. name, path) end
end

--- The font every EvermoreUI surface uses unless a module picks its own:
--- General > Font. Before the saved variables load it's the default.
function Media:GlobalFontName()
    local core = EV.dbReady and EV.DB:GetCore()
    local name = core and core.font
    if type(name) == "string" and name ~= "" and (registry.font[name] or (LSM() and LSM():IsValid("font", name))) then
        return name
    end
    return DEFAULTS.font
end

--- Resolve a media name to a path. Falls back to LibSharedMedia, then the default.
--- A font with no name (or "", a module's "use the global font") is the global font.
function Media:Fetch(kind, name)
    if kind == "font" and (name == nil or name == "") then name = self:GlobalFontName() end
    local own = registry[kind]
    if own and name and own[name] then return own[name] end
    local lsm = LSM()
    if lsm and name then
        local p = lsm:Fetch(kind, name, true)
        if p then return p end
    end
    return own and own[DEFAULTS[kind]]
end

--- The bold partner of a font name (or of the global font when name is nil).
function Media:FetchBold(name)
    if name == nil or name == "" then name = self:GlobalFontName() end
    return self:Fetch("font", BOLD[name] or name)
end

function Media:List(kind)
    local seen, list = {}, {}
    for name in pairs(registry[kind] or {}) do seen[name] = true; list[#list + 1] = name end
    local lsm = LSM()
    if lsm then
        for _, name in ipairs(lsm:List(kind) or {}) do
            if not seen[name] then list[#list + 1] = name end
        end
    end
    table.sort(list)
    return list
end

--- Dropdown values for a font picker. With inherit, the first entry is ""
--- ("follow General > Font"), labelled with what that currently is.
function Media:FontValues(inherit)
    local list = {}
    if inherit then
        list[1] = { value = "", text = (EV.L and EV.L["Global font"] or "Global font") .. " (" .. self:GlobalFontName() .. ")" }
    end
    for _, name in ipairs(self:List("font")) do list[#list + 1] = { value = name, text = name } end
    return list
end

--- Push our media into LibSharedMedia if something else loaded it.
local function Publish()
    local lsm = LSM()
    if not lsm then return end
    for kind, entries in pairs(registry) do
        for name, path in pairs(entries) do
            lsm:Register(kind, "EvermoreUI " .. name, path)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Publish()
end)

