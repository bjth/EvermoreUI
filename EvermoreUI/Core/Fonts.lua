if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Fonts.lua
--  One font for the whole interface. Our own addons read General > Font
--  through EV.Media:Fetch("font"); this file carries it into Blizzard's UI by
--  swapping the face on every named font object the client knows about
--  (GetFonts), keeping each object's size and flags.
--
--  Only Blizzard's plain text faces are swapped. Decorative faces (the quest
--  parchment titles, damage numbers and so on) are left as they are, and so
--  is everything on clients whose language our fonts don't cover.
--
--  Taint: SetFont on a Font object is a plain widget call and is what the
--  text size setting does itself. We never touch the STANDARD_TEXT_FONT style
--  globals, which secure code reads.
--
--  Font objects loaded later (load-on-demand Blizzard addons bring their own)
--  are picked up on ADDON_LOADED. Turning it off puts the original faces back.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local Fonts = {}
EV.Fonts = Fonts

-- Our fonts cover Latin scripts only.
local LATIN = {
    enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true,
    itIT = true, ptBR = true, ptPT = true,
}

-- Blizzard's plain text faces, by file name.
local PLAIN = {
    ["frizqt__.ttf"] = true,
    ["arialn.ttf"]   = true,
    ["arial.ttf"]    = true,
}

local original = {}   -- [name] = original face path, for every object we swapped
-- This was `v ~= nil and not issecret(v)`, which compares BEFORE testing.
-- Values.lua's rule, written after the suite's first run-in with secrets, is
-- that a secret must be checked with type() and issecretvalue() only, never
-- with ==. EV.Usable follows that rule; see Core/Init.lua.
local Clean = EV.Usable

local function FileName(path)
    return (path:match("[^\\/]+$") or path):lower()
end

function Fonts:Supported()
    return LATIN[GetLocale and GetLocale() or "enUS"] == true
end

--- Is General > "Use our font in Blizzard's interface" on?
function Fonts:Enabled()
    local core = EV.dbReady and EV.DB:GetCore()
    return core and core.blizzardFonts ~= false and self:Supported()
end

local function ObjectFor(name)
    local obj = _G[name]
    if type(obj) == "table" and obj.GetFont and obj.SetFont then return obj end
    if GetFontInfo then
        local info = GetFontInfo(name)
        obj = info and info.fontObject
        if type(obj) == "table" and obj.GetFont and obj.SetFont then return obj end
    end
end

-- Swap (or restore) one object. Size comes from the object as it is now, so
-- the game's text size scaling is kept.
local function Paint(name, obj, target)
    local path, size, flags = obj:GetFont()
    if not (Clean(path) and Clean(size)) or size <= 0 then return end
    if not original[name] then
        if not PLAIN[FileName(path)] then return end
        original[name] = path
    end
    local want = target or original[name]
    if path ~= want then obj:SetFont(want, size, Clean(flags) and flags or "") end
end

--- Walk every font object: swap to our font when enabled, restore when not.
function Fonts:Apply()
    if not GetFonts then return end
    local on = self:Enabled()
    local target = on and EV.Media:Fetch("font") or nil
    if not on and not next(original) then return end
    local names = GetFonts()
    if type(names) ~= "table" then return end
    for _, name in ipairs(names) do
        local obj = ObjectFor(name)
        if obj then Paint(name, obj, target) end
    end
    self.applied = on
end

--- How many objects are on our font right now (for /evui fonts and the tests).
function Fonts:Count()
    local n = 0
    for _ in pairs(original) do n = n + 1 end
    return n
end

--- Change General > Font: our own text follows on reload, Blizzard's now.
function Fonts:SetGlobal(name)
    EV.DB:GetCore().font = name
    self:Apply()
    if EV.SendMessage then EV:SendMessage("EV_FONT_CHANGED", name) end
end

function Fonts:SetBlizzard(on)
    EV.DB:GetCore().blizzardFonts = on and true or false
    self:Apply()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
    if not EV.dbReady then return end
    -- Nothing to do for later addons while it's off and nothing was swapped.
    if not Fonts:Enabled() and not next(original) then return end
    Fonts:Apply()
end)

-- Profile switches can change the setting.
hooksecurefunc(EV, "_RebindModules", function() Fonts:Apply() end)

--------------------------------------------------------------------------------
--  Styled text for our own surfaces
--
--  Lifted out of EvermoreUI_Nameplates (was ns.SetText) so unit frames and
--  nameplates render text identically. The reasoning, in short; the long
--  form is in Core/FontObjects.xml and the nameplate module's history:
--
--   * Slug rendering is an XML-only <Font> attribute. A string built with
--     SetFont is never slug, so we go through a named font object per face.
--   * SetFontHeight after SetFontObject, never SetTextHeight: SetTextHeight
--     re-specifies the font and drops slug on the very next line.
--   * A face we have no object for (anything from LibSharedMedia) falls back
--     to SetFont and loses slug. Stated, not hidden: StyleText says so.
--
--  style is the user's "text edge": "outline", "shadow" or "both".
--  wantsEdge is the caller saying whether this element would like an edge at
--  all; false means shadow only, whatever the style. Callers pass true.
--------------------------------------------------------------------------------
Fonts.SLUG = {
    ["Roboto Condensed"] = { plain = "EvermoreSlugFont",       outline = "EvermoreSlugFontOutline" },
    ["Barlow"]           = { plain = "EvermoreSlugFontBarlow", outline = "EvermoreSlugFontBarlowOutline" },
    ["Barlow SemiBold"]  = { plain = "EvermoreSlugFontBarlow", outline = "EvermoreSlugFontBarlowOutline" },
    ["Friz Quadrata"]    = { plain = "EvermoreSlugFontFriz",   outline = "EvermoreSlugFontFrizOutline" },
}

--- True when the configured face renders through slug.
function Fonts:HasSlug()
    local name = EV.Media:GlobalFontName()
    local set = name and self.SLUG[name]
    return (set and _G[set.plain]) and true or false
end

--- Style a font string. Returns usedSlug, keptSlug: the second is false only
--- when a slug object was applied and then sizing it failed or had to fall
--- back to SetTextHeight, which is the case that makes text bounce.
function Fonts:StyleText(fs, size, style, wantsEdge)
    if not fs then return false, true end
    style = style or "both"
    local wantOutline = wantsEdge ~= false and (style == "outline" or style == "both")
    local wantShadow  = (style == "shadow" or style == "both") or not wantsEdge

    local used, kept = false, true
    local name = EV.Media:GlobalFontName()
    local set = name and self.SLUG[name]
    local obj = set and _G[wantOutline and set.outline or set.plain]
    if obj then
        used = true
        fs:SetFontObject(obj)
        if fs.SetFontHeight then
            if not pcall(fs.SetFontHeight, fs, size) then kept = false end
        else
            kept = false
            pcall(fs.SetTextHeight, fs, size)
        end
    else
        fs:SetFont(EV.Media:Fetch("font"), size, wantOutline and "OUTLINE" or "")
    end

    if wantShadow then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    end
    return used, kept
end
