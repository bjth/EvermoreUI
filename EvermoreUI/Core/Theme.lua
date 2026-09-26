if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Theme.lua
--  The one visual language for everything EvermoreUI draws: options, chat,
--  tooltips, skinned Blizzard windows and our own widgets.
--
--  Tokens, not colours: code asks for "surface1" or "textMuted", never an
--  RGB. Token tables are updated in place when the theme changes, so a
--  module holding a reference stays current; modules that cache derived
--  values listen for the EV_THEME_CHANGED message.
--
--  Accessibility (WCAG 2.1, checked in game by /evui theme audit):
--    * body text >= 7:1 on every surface, muted text >= 4.5:1
--    * control boundaries (buttons, inputs, toggles) >= 3:1 on the surface
--      they sit on, so controls are findable without relying on fill
--    * depth by lightness: base < raised < control < hover, plus a soft
--      shadow outside windows so they separate from the game world
--    * state is never colour alone: hover lightens, press darkens, focus
--      draws a ring, selected adds a bar
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme or {}
EV.Theme = T

local function hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end

-- Palettes. Every token must exist in every palette. This is the one place
-- colours live: warm stone surfaces, parchment text, WoW gold headings and a
-- burnished copper accent, so the interface sits with the game's own
-- materials rather than against them.
T.PALETTES = {
    standard = {
        surface0    = hex("1b1814"),        -- window base: dark warm stone
        surface1    = hex("221e19"),        -- raised: insets, cards, menus, tooltips
        surface2    = hex("2b2620"),        -- controls: buttons, inputs, tracks
        surface3    = hex("363029"),        -- control hover
        surfaceSunk = hex("13110e"),        -- pressed, wells
        titleBar    = hex("15120f"),        -- window title bar
        border      = hex("453d33"),        -- window and panel edges
        borderStrong = hex("857866"),       -- control boundaries (>= 3:1)
        divider     = { 1, 0.92, 0.8, 0.08 }, -- hairlines inside panels
        shadow      = { 0, 0, 0, 0.45 },    -- outer shadow strength
        text        = hex("ede6da"),        -- parchment white
        textMuted   = hex("b5aa99"),
        textDisabled = hex("8a7f70"),
        title       = hex("e8c46a"),        -- headings: WoW gold
        accent      = hex("d4924e"),        -- burnished copper
        onAccent    = hex("1c1208"),        -- text on accent fills
        danger      = hex("e46a55"),        -- brick
        success     = hex("93b75c"),        -- moss
        warning     = hex("e6a847"),        -- amber
        -- Data colours (experience bar and anything that charts progress).
        -- Earthy like the rest: copper to wheat for XP, sage for quest XP, teal rested.
        xp          = hex("b8733a"),        -- experience: deep copper, start of its gradient
        xpEnd       = hex("e3b464"),        -- experience: wheat gold, end of its gradient
        quest       = hex("9fb565"),        -- XP waiting in finished quests: sage
        rested      = hex("7aa3a8"),        -- rested experience: dusky teal
        -- Coin colours, for money printed as letters: the fallback when the
        -- client's money formatter (coin icons) isn't there, and for zero.
        -- Gold and copper sit with the palette, silver stays cool so the
        -- three never read as one colour.
        coinGold    = hex("e8c46a"),
        coinSilver  = hex("c5c8cc"),
        coinCopper  = hex("d4924e"),
    },
    high = {
        surface0    = hex("100e0b"),
        surface1    = hex("17140f"),
        surface2    = hex("211c17"),
        surface3    = hex("2f2821"),
        surfaceSunk = hex("080706"),
        titleBar    = hex("080706"),
        border      = hex("6c6052"),
        borderStrong = hex("ab9d8a"),
        divider     = { 1, 0.92, 0.8, 0.16 },
        shadow      = { 0, 0, 0, 0.6 },
        text        = hex("fffaf2"),
        textMuted   = hex("d8cebf"),
        textDisabled = hex("9e9384"),
        title       = hex("ffd772"),
        accent      = hex("eca867"),
        onAccent    = hex("000000"),
        danger      = hex("ff7d68"),
        success     = hex("a9d070"),
        warning     = hex("ffc15e"),
        xp          = hex("c07d42"),
        xpEnd       = hex("f0c070"),
        quest       = hex("b1c877"),
        rested      = hex("9cc2c6"),
        coinGold    = hex("ffd772"),
        coinSilver  = hex("dde1e6"),
        coinCopper  = hex("eca867"),
    },
}

-- Live token tables (mutated in place by Apply).
T.C = {}
for k, v in pairs(T.PALETTES.standard) do T.C[k] = { v[1], v[2], v[3], v[4] } end

--- r, g, b, a for a token, with an optional alpha override.
function T.RGBA(token, a)
    local c = T.C[token] or T.C.text
    return c[1], c[2], c[3], a or c[4]
end

--- The tokens the Colours page lets you change, in the order it shows them.
--- Everything else (hover, pressed, dividers, shadows) stays derived from
--- the contrast setting so a custom palette cannot make controls unfindable.
T.CUSTOM = {
    "accent", "onAccent", "title", "text", "textMuted",
    "surface0", "surface1", "surface2", "border", "borderStrong",
    "danger", "success", "warning",
    "xp", "xpEnd", "quest", "rested",
}

--- Apply a palette ("standard" or "high"), then any colours of your own
--- on top (core.theme.custom[token] = { r, g, b }).
function T.Apply(name)
    local p = T.PALETTES[name] or T.PALETTES.standard
    T.mode = T.PALETTES[name] and name or "standard"
    local custom = T.Settings and T.Settings().custom
    for k, v in pairs(p) do
        local c = T.C[k] or {}
        c[1], c[2], c[3], c[4] = v[1], v[2], v[3], v[4]
        local o = type(custom) == "table" and custom[k]
        if type(o) == "table" and type(o[1]) == "number" and type(o[2]) == "number" and type(o[3]) == "number" then
            c[1], c[2], c[3] = o[1], o[2], o[3]
        end
        T.C[k] = c
    end
    for obj in pairs(T.watchers) do
        if obj.Paint then pcall(obj.Paint, obj) end
    end
    if EV.SendMessage then EV:SendMessage("EV_THEME_CHANGED", T.mode) end
end

--- "rrggbb" for a token, for |cff colour codes in text.
function T.Hex(token)
    local r, g, b = T.RGBA(token)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

--- Objects with a :Paint() method repaint themselves when the theme changes.
T.watchers = setmetatable({}, { __mode = "k" })
function T.Watch(obj) T.watchers[obj] = true; return obj end

--- Run fn now and again on every theme change (for code that colours plain
--- regions rather than objects with a :Paint()). Kept for good: use it for
--- long-lived frames (windows, edit mode), not per-row pools.
local themed = {}
T.Watch({ Paint = function() for _, fn in ipairs(themed) do pcall(fn) end end })
function T.OnTheme(fn)
    themed[#themed + 1] = fn
    fn()
    return fn
end

T.MEDIA = "Interface\\AddOns\\EvermoreUI\\Media\\UI\\"

-- Our text follows General > Font. These read it at call time, so anything
-- created after a change picks it up; existing text follows on reload.
function T.FontPath() return EV.Media:Fetch("font") end
function T.FontBoldPath() return EV.Media:FetchBold() end

-- Every text shadow in the suite: a soft 1px drop.
T.SHADOW = { 0, 0, 0, 0.6 }
function T.TextShadow(fs, on)
    if on == false then
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    else
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(T.SHADOW[1], T.SHADOW[2], T.SHADOW[3], T.SHADOW[4])
    end
end

-- Type scale (px at 100% UI size).
T.SIZE = { caption = 11, small = 12, body = 13, label = 14, title = 16, heading = 20 }

--------------------------------------------------------------------------------
--  Drawing helpers
--------------------------------------------------------------------------------
function T.Solid(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    t:SetColorTexture(r, g, b, a or 1)
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
    return t
end

--- A solid texture in a token colour.
function T.Fill(parent, layer, token, a, sub)
    local r, g, b, al = T.RGBA(token, a)
    return T.Solid(parent, layer, r, g, b, al, sub)
end

function T.Font(parent, size, bold, alpha, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(bold and T.FontBoldPath() or T.FontPath(), size or 14, "")
    fs:SetTextColor(1, 1, 1, alpha or 1)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    T.TextShadow(fs)
    return fs
end

--- A font string coloured by token: T.Text(parent, "body", "textMuted").
function T.Text(parent, size, token, bold, justify)
    local fs = T.Font(parent, type(size) == "number" and size or T.SIZE[size or "body"], bold, 1, justify)
    fs:SetTextColor(T.RGBA(token or "text"))
    return fs
end

function T.TokenBorder(frame, token, a)
    local r, g, b, al = T.RGBA(token or "border", a)
    return EV.Pixel:CreateBorder(frame, 1, r, g, b, al)
end

function T.SetBorderColor(frame, r, g, b, a)
    local border = frame.evBorder
    if not border then return end
    for _, e in ipairs(border.edges) do e:SetColorTexture(r, g, b, a) end
end

function T.SetBorderToken(frame, token, a)
    T.SetBorderColor(frame, T.RGBA(token, a))
end

--- Soft drop shadow: stacked black rings outside the frame.
function T.Shadow(frame, size, strength)
    size = size or 10
    strength = strength or T.C.shadow[4]
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    holder:SetPoint("TOPLEFT", -size, size)
    holder:SetPoint("BOTTOMRIGHT", size, -size)
    holder:EnableMouse(false)
    for i = 1, size do
        local ring = CreateFrame("Frame", nil, holder)
        ring:SetPoint("TOPLEFT", i - 1, -(i - 1))
        ring:SetPoint("BOTTOMRIGHT", -(i - 1), i - 1)
        EV.Pixel:CreateBorder(ring, 1, 0, 0, 0, strength * (i / size) ^ 2 * 0.5)
    end
    return holder
end

function T.Lerp(a, b, t) return a + (b - a) * t end

--- Blend two tokens (0 = a, 1 = b).
function T.Mix(a, b, t)
    local x, y = T.C[a], T.C[b]
    return T.Lerp(x[1], y[1], t), T.Lerp(x[2], y[2], t), T.Lerp(x[3], y[3], t), T.Lerp(x[4] or 1, y[4] or 1, t)
end

--------------------------------------------------------------------------------
--  Contrast maths (used by the sim and by /evui theme)
--------------------------------------------------------------------------------
local function lin(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
function T.Luminance(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end
function T.Contrast(a, b)
    local la, lb = T.Luminance(a), T.Luminance(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

-- The pairs the theme promises, with their minimum ratio.
T.CONTRACT = {
    { "text", "surface0", 7 }, { "text", "surface1", 7 }, { "text", "surface2", 7 }, { "text", "surface3", 7 },
    { "textMuted", "surface0", 4.5 }, { "textMuted", "surface1", 4.5 }, { "textMuted", "surface2", 4.5 },
    { "title", "surface0", 4.5 }, { "title", "titleBar", 4.5 }, { "text", "titleBar", 7 },
    { "accent", "surface0", 4.5 }, { "accent", "surface2", 3 }, { "onAccent", "accent", 4.5 },
    { "borderStrong", "surface0", 3 }, { "borderStrong", "surface1", 3 },
    { "danger", "surface0", 4.5 }, { "success", "surface0", 4.5 }, { "warning", "surface0", 4.5 },
    { "xp", "surface0", 4.5 }, { "xpEnd", "surface0", 4.5 }, { "quest", "surface0", 4.5 }, { "rested", "surface0", 4.5 },
    { "coinGold", "surface0", 4.5 }, { "coinSilver", "surface0", 4.5 }, { "coinCopper", "surface0", 4.5 },
}

function T.Audit(mode)
    local fails = {}
    local p = T.PALETTES[mode or T.mode or "standard"]
    for _, row in ipairs(T.CONTRACT) do
        local r = T.Contrast(p[row[1]], p[row[2]])
        if r < row[3] then fails[#fails + 1] = ("%s on %s %.2f < %.1f"):format(row[1], row[2], r, row[3]) end
    end
    return fails
end

--------------------------------------------------------------------------------
--  Tiny tween driver: one OnUpdate for every running animation.
--  T.Tween(key, duration, fn) calls fn(progress 0..1) each frame; a new tween
--  with the same key replaces the old one.
--------------------------------------------------------------------------------
local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
    local any = false
    for key, tw in pairs(tweens) do
        tw.t = tw.t + elapsed
        local p = math.min(1, tw.t / tw.d)
        tw.fn(1 - (1 - p) ^ 3) -- ease out cubic
        if p >= 1 then tweens[key] = nil else any = true end
    end
    if not any then self:Hide() end
end)

function T.Tween(key, duration, fn)
    tweens[key] = { t = 0, d = math.max(duration, 0.001), fn = fn }
    driver:Show()
end

--------------------------------------------------------------------------------
--  Tooltip in the house style (reuses GameTooltip)
--------------------------------------------------------------------------------
function T.ShowTooltip(owner, title, body)
    if not body and not title then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT", 0, 4)
    if title then GameTooltip:AddLine(title, T.RGBA("text")) end
    if body then
        local r, g, b = T.RGBA("textMuted")
        GameTooltip:AddLine(body, r, g, b, true)
    end
    GameTooltip:Show()
end

function T.HideTooltip() GameTooltip:Hide() end

--- Chevron drawn from two rotated lines (no texture files needed).
function T.Chevron(parent, size, alpha)
    size = size or 6
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size * 2, size)
    local l = T.Solid(holder, "OVERLAY", 1, 1, 1, alpha or 0.6)
    local r = T.Solid(holder, "OVERLAY", 1, 1, 1, alpha or 0.6)
    local len = size * 1.05
    l:SetSize(len, 1.5); r:SetSize(len, 1.5)
    l:SetPoint("CENTER", holder, "CENTER", -size * 0.36, 0)
    r:SetPoint("CENTER", holder, "CENTER", size * 0.36, 0)
    l:SetRotation(math.rad(-45)); r:SetRotation(math.rad(45))
    holder.lines = { l, r }
    function holder:SetAlphaLines(a) for _, t in ipairs(self.lines) do t:SetAlpha(a) end end
    function holder:SetColorLines(r2, g2, b2, a2) for _, t in ipairs(self.lines) do t:SetColorTexture(r2, g2, b2, a2 or 1) end end
    function holder:Flip(up)
        l:SetRotation(math.rad(up and 45 or -45)); r:SetRotation(math.rad(up and -45 or 45))
    end
    function holder:Point(dir) -- "down", "up", "left", "right"
        local rot = ({ down = 0, up = 180, left = -90, right = 90 })[dir] or 0
        local a = math.rad(rot)
        l:SetRotation(math.rad(-45) + a); r:SetRotation(math.rad(45) + a)
        local dx, dy = size * 0.36, 0
        local c, s = math.cos(a), math.sin(a)
        l:ClearAllPoints(); r:ClearAllPoints()
        l:SetPoint("CENTER", holder, "CENTER", -dx * c + dy * s, -dx * s - dy * c)
        r:SetPoint("CENTER", holder, "CENTER", dx * c - dy * s, dx * s + dy * c)
    end
    return holder
end

--------------------------------------------------------------------------------
--  Setting: stored in the profile's core table; applied once the DB is up
--  and after profile switches.
--------------------------------------------------------------------------------
function T.Settings()
    local core = EV.DB and EV.DB.GetCore and EV.dbReady and EV.DB:GetCore()
    if not core then return { contrast = "standard" } end
    if type(core.theme) ~= "table" then core.theme = {} end
    core.theme.contrast = core.theme.contrast or "standard"
    return core.theme
end

function T.SetContrast(mode)
    T.Settings().contrast = mode
    T.Apply(mode)
end

-- Colour picker drags call Set many times a second, and a theme change
-- rebuilds the options pages, so the repaint waits for the drag to settle.
local reapply
local function Reapply()
    if reapply then reapply:Cancel() end
    reapply = C_Timer.NewTimer(0.15, function()
        reapply = nil
        T.Apply(T.Settings().contrast)
    end)
end

--- A token's colour as the contrast setting has it, ignoring your own.
function T.DefaultRGB(token)
    local p = T.PALETTES[T.mode] or T.PALETTES.standard
    local c = p[token]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

function T.IsCustom(token)
    local custom = T.Settings().custom
    return type(custom) == "table" and type(custom[token]) == "table" or false
end

function T.SetCustom(token, r, g, b)
    local st = T.Settings()
    if type(st.custom) ~= "table" then st.custom = {} end
    st.custom[token] = { r, g, b }
    -- The live token follows at once so the swatch and anything painted
    -- from T.C show the new colour while the full repaint waits.
    local c = T.C[token]
    if c then c[1], c[2], c[3] = r, g, b end
    Reapply()
end

function T.ResetCustom(token)
    local st = T.Settings()
    if type(st.custom) ~= "table" then return end
    if token then st.custom[token] = nil else st.custom = nil end
    Reapply()
end

--- From a shared palette string: only tokens we offer, only real colours.
function T.ImportCustom(ui)
    local st = T.Settings()
    st.custom = nil
    if type(ui) == "table" then
        local allowed = {}
        for _, k in ipairs(T.CUSTOM) do allowed[k] = true end
        for k, c in pairs(ui) do
            if allowed[k] and type(c) == "table" and type(c[1]) == "number"
               and type(c[2]) == "number" and type(c[3]) == "number" then
                st.custom = st.custom or {}
                st.custom[k] = { c[1], c[2], c[3] }
            end
        end
    end
    T.Apply(st.contrast)
end

--- WCAG contrast ratio between two tokens, for the Colours page's check.
function T.Contrast(a, b)
    local function lum(token)
        local r, g, bl = T.RGBA(token)
        local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(bl)
    end
    local la, lb = lum(a), lum(b)
    if la < lb then la, lb = lb, la end
    return (la + 0.05) / (lb + 0.05)
end

T.Apply("standard")

-- Profile switches can change the setting.
hooksecurefunc(EV, "_RebindModules", function()
    T.Apply(T.Settings().contrast)
end)

-- Apply the saved setting once the DB is up (ADDON_LOADED, after the
-- framework binds it) and again at login in case event order differs.
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name ~= EV.name then return end
    if event == "PLAYER_LOGIN" then self:UnregisterAllEvents() end
    if not EV.dbReady then return end
    local st = T.Settings()
    if st.contrast ~= T.mode or type(st.custom) == "table" then T.Apply(st.contrast) end
end)
