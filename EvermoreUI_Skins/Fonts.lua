if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Fonts.lua
--  Blizzard's XML names a font object 3,000-odd times: in this client
--  GameFontNormal alone is inherited in 464 places, GameFontHighlight in
--  274, GameFontNormalSmall in 165, GameFontHighlightSmall in 150. Every one
--  of those font strings takes its face and its colour from the shared
--  object, so restyling the objects restyles the whole game's text at
--  once, with no walking and nothing to maintain per window. This is what
--  takes the gold out of windows we have never looked at.
--
--  Sizes, flags and justification stay Blizzard's: we are not re-flowing
--  their text, only changing what it is drawn with.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S, T = ns.S, EV.Theme
if not S then return end

-- Font object name -> our colour token. A name ending in a wildcard takes
-- every size variant with it (GameFontNormalSmall, ...Large, ...Med3).
local ROLES = {
    ["GameFontNormal*"]       = "title",       -- Blizzard's gold
    ["GameFontHighlight*"]    = "text",        -- their white
    ["GameFontDisable*"]      = "textDisabled",
    ["GameFontGreen*"]        = "success",
    ["GameFontRed*"]          = "danger",
    ["GameFontWhite*"]        = "text",
    ["GameFontBlack*"]        = "text",
    ["QuestFont*"]            = "text",
    -- Parchment-era text, all of it near-black because it sat on paper:
    -- ItemTextFontNormal 0.18/0.12/0.06, SubSpellFont 0.35/0.2/0
    -- (Blizzard_Fonts_Shared/Shared/GameFontStyles.xml:94-108).
    ["ItemTextFont*"]         = "text",
    ["MailTextFont*"]         = "text",
    ["InvoiceTextFont*"]      = "text",
    ["SubSpellFont"]          = "textMuted",
    ["NewSubSpellFont"]       = "textMuted",
    ["ObjectiveFont*"]        = "text",
    ["DialogButtonNormalText"] = "title",
    ["DialogButtonHighlightText"] = "text",
    ["FriendsFont*"]          = "text",
    ["ChatFontNormal"]        = "text",
    ["NumberFontNormal*"]     = "text",
    ["SystemFont*"]           = "text",
    ["Game11Font*"]           = "text",
    ["Game12Font*"]           = "text",
    ["Game13Font*"]           = "text",
    ["Game15Font*"]           = "text",
}

local touched = {}

local function Matching(pattern)
    local out = {}
    if pattern:sub(-1) ~= "*" then
        local o = _G[pattern]
        if o then out[#out + 1] = { pattern, o } end
        return out
    end
    local stem = pattern:sub(1, -2)
    for name, obj in pairs(_G) do
        if type(name) == "string" and name:sub(1, #stem) == stem
            and type(obj) == "table" and obj.GetFont and obj.SetFont and obj.SetTextColor then
            out[#out + 1] = { name, obj }
        end
    end
    return out
end

-- Blizzard's decorative faces are content, not chrome: a quest title in
-- Morpheus and combat text in Skurri are meant to look like that, and the
-- core font module already leaves them alone.
local DECORATIVE = { "morpheus", "skurri", "nim_____", "2002" }

local function IsDecorative(path)
    if type(path) ~= "string" then return false end
    path = path:lower()
    for _, face in ipairs(DECORATIVE) do
        if path:find(face, 1, true) then return true end
    end
    return false
end

--- Take one font object's face and colour.
local function Take(name, obj, token)
    local ok, path, size, flags = pcall(obj.GetFont, obj)
    if not ok or not size then return end
    if issecretvalue and issecretvalue(size) then return end
    -- A decorative face keeps its face. It does not keep its colour:
    -- QuestTitleFont is Morpheus AND pure black, and skipping the whole
    -- call left it unreadable the moment the parchment went.
    if not IsDecorative(path) then
        local ours = T.FontPath()
        if ours then pcall(obj.SetFont, obj, ours, size, flags or "") end
    end
    pcall(obj.SetTextColor, obj, T.RGBA(token))
    touched[name] = { obj = obj, token = token }
end

--------------------------------------------------------------------------------
--  Materials
--
--  The quest and book windows do not take their text colour from a font
--  object at all: QuestInfo_Display, QuestFrame_SetTextColor and friends look
--  it up per repaint from MATERIAL_TEXT_COLOR_TABLE, keyed on the background
--  material, and push it onto every string by hand. Painting those strings
--  ourselves loses the argument, because the next QuestInfo_Display paints
--  them back.
--
--  Blizzard already built the way out. The QuestTextContrast accessibility
--  setting has a dark-background mode, and every one of those call sites
--  asks QuestTextContrast.UseLightText() and switches to the "Stone"
--  material when it is on -- including the pooled greeting buttons, the
--  objectives created on demand and the completed-objective colour
--  (Blizzard_UIPanels_Game/Mainline/QuestInfo.lua:66-90, 240-256;
--  QuestFrame.lua:340, 389, 612-637).
--
--  So we say yes to that question and point Stone at our own colours. From
--  there Blizzard's code keeps the quest UI readable through every repaint,
--  and we maintain none of it. IsEnabled also makes their code hide the seal
--  material behind the text, which is art we would otherwise have to strip.
--------------------------------------------------------------------------------
-- Materials whose backgrounds we darken, so their text has to lighten.
-- Default is left alone: it is the one that was already meant for a dark
-- background, and Blizzard uses it where there is no parchment.
local PARCHMENT_MATERIALS = {
    Stone = true, Parchment = true, ParchmentLarge = true,
    Marble = true, Silver = true, Bronze = true,
}

local function Repoint(tbl, token)
    if type(tbl) ~= "table" then return end
    for name, colour in pairs(tbl) do
        if PARCHMENT_MATERIALS[name] and type(colour) == "table" and colour.SetRGB then
            pcall(colour.SetRGB, colour, T.RGBA(token))
        end
    end
end

local materialsTaken = false
function S.ApplyMaterials()
    -- Answer the dark-background question with a yes, once.
    if not materialsTaken and type(QuestTextContrast) == "table" then
        materialsTaken = true
        QuestTextContrast.UseLightText = function() return true end
        QuestTextContrast.IsEnabled    = function() return true end
    end

    Repoint(MATERIAL_TEXT_COLOR_TABLE, "text")
    Repoint(MATERIAL_TITLETEXT_COLOR_TABLE, "title")

    -- The one colour their dark branch names directly rather than looking up.
    local done = QUEST_OBJECTIVE_COMPLETED_FONT_COLOR_DARK_BACKGROUND
    if type(done) == "table" and done.SetRGB then
        pcall(done.SetRGB, done, T.RGBA("success"))
    end
end

local applied = false
function S.ApplyFonts()
    for pattern, token in pairs(ROLES) do
        for _, pair in ipairs(Matching(pattern)) do
            Take(pair[1], pair[2], token)
        end
    end
    applied = true
end

--- A font object only takes a colour that is genuinely a role colour, so
--- repainting on a theme change is the same call again.
T.OnTheme(function()
    if applied then S.ApplyFonts(); S.ApplyMaterials() end
end)

S.fontsTouched = touched
