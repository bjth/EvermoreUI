if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Looks.lua
--  One visual recipe per kind of control, shared by the two things that draw
--  controls: our own widgets (EvermoreUI/UI) and the skins of Blizzard's
--  templates (EvermoreUI_Skins/Parts.lua). Neither keeps a map of states to
--  colours of its own any more; both resolve through the Look.
--
--  Three layers:
--    tokens   Theme.lua: colours by name
--    looks    this file: per control, its geometry and a token for every state
--    drawing  UI/*.lua and Parts.lua, which ask T.Resolve for the colours
--
--  A Look is data. It holds token names and numbers, never an RGB, a frame or
--  a function. `text` is drawn on the look's own fill; `label` beside the
--  control, on whatever surface it sits on.
--
--  A colour spec is one of:
--    "surface2"                 a token
--    { "borderStrong", "text", 0.35 }   T.Mix of two tokens
--    { "danger", a = 0.2 }      a token at another alpha
--    { "accent", k = 1.12 }     a token brightened (k > 1) or darkened
--    "none"                     nothing drawn (fully transparent)
--
--  State layers, applied in this order, each overriding the ones before:
--    rest, on, hover, onHover, pressed, focus, disabled
--  "on" is whichever of selected / checked / open the control has; onHover
--  applies only when it is both on and hovered, so an on control can keep its
--  look under the mouse. disabled wins over everything, pressed beats hover,
--  and focus sits above both because a pressed, focused input still needs its
--  ring. T.Resolve is the only place this order is decided.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local min = math.min

local L = {}
T.LOOK = L

local MIX = 0.35   -- the one hover mix of an edge towards the text colour
local HOVER_EDGE = { "borderStrong", "text", MIX }

--------------------------------------------------------------------------------
--  Buttons
--------------------------------------------------------------------------------
L.button = {                                   -- secondary: the default
    height = 30,
    rest     = { fill = "surface2", edge = "borderStrong", text = { "textMuted", "text", 0.55 }, glyph = "textMuted" },
    on       = { glyph = "accent", bar = "accent" },
    hover    = { fill = "surface3", edge = HOVER_EDGE, text = "text", glyph = "text" },
    onHover  = { glyph = "accent" },
    pressed  = { fill = "surfaceSunk", text = "text" },
    focus    = { edge = "accent" },
    disabled = { fill = "surface1", edge = "border", text = "textDisabled", glyph = "textDisabled" },
}
L.buttonPrimary = {
    height = 30, shadow = false,               -- dark text on the accent: no shadow
    rest     = { fill = "accent", edge = "none", text = "onAccent", glyph = "onAccent" },
    hover    = { fill = { "accent", k = 1.12 } },
    pressed  = { fill = { "accent", k = 0.8 } },
    focus    = { edge = "text" },
    disabled = { fill = "surface1", text = "textDisabled", glyph = "textDisabled" },
}
L.buttonGhost = {                              -- text only; a box on hover
    height = 30,
    rest     = { fill = "none", edge = "none", text = "textMuted", glyph = "textMuted" },
    on       = { fill = "surface2", glyph = "accent", bar = "accent" },
    hover    = { fill = "surface3", edge = "border", text = "text", glyph = "text" },
    onHover  = { fill = "surface2", glyph = "accent" },
    pressed  = { fill = "surfaceSunk", text = "text" },
    focus    = { edge = "accent" },
    disabled = { text = "textDisabled", glyph = "textDisabled" },
}
L.buttonDanger = {
    height = 30,
    rest     = { fill = { "danger", a = 0.08 }, edge = { "danger", a = 0.75 }, text = { "danger", "text", 0.6 } },
    hover    = { fill = { "danger", a = 0.2 }, edge = "danger" },
    pressed  = { fill = { "danger", a = 0.3 } },
    focus    = { edge = "danger" },
    disabled = { fill = "surface1", edge = "border", text = "textDisabled" },
}
L.reset = {                                    -- a small "clear these filters" badge: copper while
    glyphSize = 7, box = 13,                   -- there is something to clear, red under the mouse
    rest     = { fill = "surface2", edge = "borderStrong", glyph = "accent" },
    hover    = { fill = "danger", edge = "danger", glyph = "onAccent" },
    pressed  = { fill = { "danger", k = 0.8 }, edge = "danger", glyph = "onAccent" },
    disabled = { glyph = "textDisabled" },
}
L.close = {
    glyphSize = 10,
    rest     = { fill = "none", edge = "none", glyph = "textMuted" },
    hover    = { fill = "danger", glyph = "onAccent" },
    pressed  = { fill = { "danger", k = 0.8 }, glyph = "onAccent" },
    disabled = { glyph = "textDisabled" },
}

L.pager = {                                    -- previous / next page: the button Look, this size
    box = 24, chevron = 5,
}
L.popout = {                                   -- the tab beside an equipment slot that opens its flyout:
    short = 10, long = 22, chevron = 3,        -- the button Look, this size, on while the flyout is open
}
L.windowTab = {                                -- an icon tab on a window's edge: on, it is part of
    rest     = { fill = "surfaceSunk", edge = "border", icon = { "text", a = 0.7 }, bar = "none" },   -- the window
    on       = { fill = "surface0", icon = "text", bar = "accent" },
    hover    = { fill = "surface2", icon = "text" },
    onHover  = { fill = "surface0" },
    bar = 2,                                   -- the accent bar's width on the tab's outer edge
    inset = 2,                                 -- a black ring inside the edge, round the icon
}
L.sideTab = {                                  -- a mode tab down a window's edge (the character window's):
    box = 36, icon = 30, gap = -1,             -- icon = box less the edge and the inset ring                                               -- windowTab faces, `gap` over the window's one-pixel
                                               -- border so the chosen tab opens into it
}
L.section = {                                  -- a section heading inside a pane: its name between two rules
    rest = { text = "title", rule = "border" },
    pad = 6, gap = 8,                          -- rule to the pane's edge, rule to the name
}

--------------------------------------------------------------------------------
--  Choices
--------------------------------------------------------------------------------
L.checkbox = {
    box = 16, tick = 12,
    rest     = { fill = "surfaceSunk", edge = "borderStrong", label = "text" },
    on       = { fill = "accent", edge = "accent", glyph = "onAccent" },
    hover    = { fill = "surface2", edge = HOVER_EDGE },
    onHover  = { fill = "accent", edge = "accent" },
    disabled = { label = "textDisabled" },
}
L.radio = {
    ring = 16, dot = 6,
    rest     = { ring = "borderStrong", fill = "surfaceSunk", label = "text" },
    on       = { ring = "accent", fill = "accent", dot = "onAccent" },
    hover    = { ring = HOVER_EDGE, fill = "surface2" },
    onHover  = { ring = "accent", fill = "accent" },
    disabled = { label = "textDisabled" },
}
L.toggle = {
    width = 40, height = 20, pad = 3,
    rest     = { fill = "surface2", edge = "borderStrong", knob = "textMuted" },
    -- The knob goes dark on the accent: a light one reads at only about 2:1.
    on       = { fill = "accent", edge = "accent", knob = "onAccent" },
    hover    = { fill = "surface3", edge = HOVER_EDGE },
    onHover  = { fill = "accent", edge = "accent" },
}

--------------------------------------------------------------------------------
--  Text entry and pickers
--------------------------------------------------------------------------------
L.input = {
    pad = 6,        -- clear space inside the edge, before any icon
    inset = 10,     -- text inset in a plain box
    rest     = { fill = "surfaceSunk", edge = "borderStrong", text = "text", placeholder = "textDisabled", glyph = "textMuted" },
    hover    = { fill = "surface1", edge = HOVER_EDGE },
    focus    = { fill = "surfaceSunk", edge = "accent" },
    disabled = { text = "textDisabled" },
}
L.dropdown = {
    chevron = 5,
    rest     = { fill = "surface2", edge = "borderStrong", text = "text", glyph = "textMuted" },
    on       = { fill = "surface3", edge = "accent", glyph = "text" },   -- open
    hover    = { fill = "surface3", edge = HOVER_EDGE, glyph = "text" },
    onHover  = { edge = "accent" },
    disabled = { fill = "surface1", text = "textDisabled", glyph = "textDisabled" },
}
L.menu = {                                     -- the list a dropdown opens
    rest     = { fill = "surface1", edge = "border", text = "text", header = "title", divider = "divider" },
    hover    = { row = "surface3" },
    on       = { text = "accent", mark = "accent" },
    disabled = { text = "textDisabled" },
}
L.slider = {
    track = 4, thumb = 12, thumbHover = 14, halo = 16, haloHover = 18,
    rest     = { bar = "surface3", fill = "accent", thumb = "accent", halo = "surface0" },
    hover    = { bar = "borderStrong" },
    -- A Blizzard slider is a box with a thumb in it, not a thin track.
    groove   = { fill = "surfaceSunk", edge = "border" },
}
L.swatch = {
    rest  = { edge = "borderStrong" },
    hover = { edge = "text" },
}
L.stepper = {                                  -- the +/- glyphs of a stepper
    rest     = { glyph = "text" },
    disabled = { glyph = "textDisabled" },
}

--------------------------------------------------------------------------------
--  Scrolling
--------------------------------------------------------------------------------
L.scrollbar = {
    width = 6, thin = 4, minThumb = 24,
    rest    = { track = { "surface2", a = 0.7 }, thumb = "borderStrong" },
    hover   = { thumb = "textMuted" },
    pressed = { thumb = "accent" },            -- dragging
}
L.scrollStep = {                               -- a scroll bar's arrow buttons
    chevron = 4,
    rest  = { glyph = "textMuted" },
    hover = { glyph = "text" },
}

--------------------------------------------------------------------------------
--  Tabs
--  Ours are text with a bar under the selected one; Blizzard's bottom tabs are
--  boxes. One look, and each reads the parts it draws: fill and edge for a
--  box, bar for an underline, text for both.
--------------------------------------------------------------------------------
L.tab = {
    rest     = { fill = "surface1", edge = "border", text = "textMuted", bar = "none", highlight = "none" },
    on       = { fill = "surface2", text = "title", bar = "accent" },
    hover    = { fill = "surface2", text = "text", bar = "borderStrong", highlight = { "text", a = 0.04 } },
    onHover  = { text = "title", bar = "accent", highlight = "none" },
    disabled = { text = "textDisabled", bar = "none" },
}

--------------------------------------------------------------------------------
--  Surfaces
--------------------------------------------------------------------------------
L.window = {
    rest = { fill = "surface0", edge = "border", title = "title", titleBar = "titleBar", divider = "divider" },
}
L.raised = { rest = { fill = "surface1", edge = "border" } }    -- panels, dialogs, nineslice boxes, menus
L.inset  = { rest = { fill = "surfaceSunk", edge = "border" } } -- wells inside a window
L.control = { rest = { fill = "surface2", edge = "borderStrong" } } -- a plain control box

--------------------------------------------------------------------------------
--  Slots, rows and lists: the repeated pieces modules draw many of
--------------------------------------------------------------------------------
L.slot = {                                     -- the well behind an icon: action, bag, item buttons
    rest    = { fill = { "surfaceSunk", a = 0.9 }, edge = "border" },
    on      = { edge = "accent" },             -- open, picked, the one you're on
    hover   = { edge = HOVER_EDGE },
    onHover = { edge = "accent" },
    pressed = { fill = { "surfaceSunk", a = 0.5 } },
}
L.slotEquipped = {                             -- an action slot holding something you're wearing
    rest = { fill = { "surfaceSunk", a = 0.9 }, edge = "success" },
}
L.plateButton = {                              -- a small button on a plate over the map
    rest    = { fill = { "surface1", a = 0.92 }, edge = "border", glyph = "textMuted" },
    on      = { edge = "accent", glyph = "accent" },                    -- wants your attention
    hover   = { fill = { "surface3", a = 0.92 }, glyph = "text" },
    onHover = { glyph = "accent" },
}
L.row = {                                      -- striped rows in a table or options page
    rest  = { fill = { "surfaceSunk", a = 0.25 }, highlight = "none" },
    on    = { fill = { "surfaceSunk", a = 0.5 } },   -- every other row
    hover = { highlight = { "surface2", a = 0.35 } },
}
L.tile = {                                     -- a card holding one thing: a spell, an ability, a set
    rest     = { fill = "surface1", edge = { "border", "surface1", 0.5 }, mark = "accent" },
    on       = { fill = { "accent", a = 0.13 }, edge = { "accent", a = 0.45 } },   -- the chosen one
    hover    = { fill = "surface2", edge = "borderStrong" },
    onHover  = { fill = { "accent", a = 0.2 }, edge = "accent" },
    disabled = { fill = { "surface1", a = 0.45 }, edge = { "border", a = 0.45 } },   -- not learned yet
}
L.tileQuiet = {                                -- the same card for something passive: a step back
    rest     = { fill = { "surface1", a = 0.55 }, edge = { "border", a = 0.55 }, mark = "accent" },
    hover    = { fill = "surface2", edge = "borderStrong" },
    disabled = { fill = { "surface1", a = 0.3 }, edge = { "border", a = 0.35 } },
}
L.listItem = {                                 -- a pickable line in a list or sidebar
    rest    = { fill = "none", text = "textMuted" },
    on      = { fill = { "accent", a = 0.25 }, text = "text" },
    hover   = { fill = { "surface2", a = 0.6 }, text = "text" },
    onHover = { fill = { "accent", a = 0.25 } },
    disabled = { text = "textDisabled" },
}
L.mover = {                                    -- an edit mode handle over a frame you can move
    rest    = { fill = { "accent", a = 0.13 }, backing = { "surfaceSunk", a = 0.55 }, edge = { "accent", a = 0.75 } },
    on      = { fill = { "accent", a = 0.32 }, edge = "text" },            -- selected
    hover   = { fill = { "accent", a = 0.22 }, edge = "accent" },
    onHover = { edge = "text" },
    focus   = { edge = "warning" },            -- the target of an anchor pick, under the mouse
}
L.chatTab = {                                  -- the chat's tabs; their opacity is the chat's setting
    rest    = { fill = "surface0", edge = "border", bar = "none", text = "textMuted" },
    on      = { fill = "surface1", bar = "accent", text = "text" },
    hover   = { fill = "surface1", bar = "borderStrong", text = "text" },
    onHover = { bar = "accent" },
}

--------------------------------------------------------------------------------
--  Resolving
--------------------------------------------------------------------------------
local ORDER = { "rest", "on", "hover", "onHover", "pressed", "focus", "disabled" }

local pick = {}      -- key -> spec, rebuilt on every call
local scratch = {}   -- the default out table
local NONE = { 0, 0, 0, 0 }

local function Into(t, r, g, b, a)
    t[1], t[2], t[3], t[4] = r, g, b, a
    return t
end

--- Resolve one colour spec into t ({ r, g, b, a }).
function T.SpecRGBA(spec, t)
    t = t or {}
    if spec == nil or spec == "none" then return Into(t, 0, 0, 0, 0) end
    if type(spec) == "string" then
        local c = T.C[spec] or T.C.text
        return Into(t, c[1], c[2], c[3], c[4] or 1)
    end
    if type(spec[3]) == "number" then
        local r, g, b, a = T.Mix(spec[1], spec[2], spec[3])
        return Into(t, r, g, b, spec.a or a)
    end
    local c = T.C[spec[1]] or T.C.text
    local k = spec.k or 1
    return Into(t, min(c[1] * k, 1), min(c[2] * k, 1), min(c[3] * k, 1), spec.a or c[4] or 1)
end

--- Is the layer active for this state?
local function Active(layer, s)
    if layer == "rest" then return true end
    local on = s.on or s.selected or s.checked or s.open or s._selected or s._checked or s._open
    local hover = s.hover or s._hover
    if layer == "on" then return on end
    if layer == "hover" then return hover end
    if layer == "onHover" then return on and hover end
    if layer == "pressed" then return s.pressed or s._pressed or s.dragging end
    if layer == "focus" then return s.focus or s._focus end
    if layer == "disabled" then return s.disabled or s._disabled end
end

--- Colours for a control in a state.
---
--- `state` is any table with booleans: on / selected / checked / open,
--- hover, pressed (or dragging), focus, disabled. Our controls pass
--- themselves (they keep _hover, _pressed, _disabled, _selected, _focus);
--- the skin parts pass their scratch table.
---
--- Returns `out` (a reused table unless you pass one) with an { r, g, b, a }
--- per key the look declares, e.g. out.fill, out.edge, out.text. A key no
--- layer sets is absent. Don't hold on to the result past the next call.
function T.Resolve(look, state, out)
    out = out or scratch
    wipe(pick)
    state = state or NONE
    for _, name in ipairs(ORDER) do
        local layer = look[name]
        if layer and Active(name, state) then
            for k, v in pairs(layer) do pick[k] = v end
        end
    end
    for k in pairs(out) do if pick[k] == nil then out[k] = nil end end
    for k, spec in pairs(pick) do
        local t = out[k]
        if type(t) ~= "table" then t = {}; out[k] = t end
        T.SpecRGBA(spec, t)
    end
    return out
end

--- r, g, b, a from a resolved colour (or zeroes when there isn't one).
function T.C4(c)
    if not c then return 0, 0, 0, 0 end
    return c[1], c[2], c[3], c[4]
end

--- Is a resolved colour drawn at all?
function T.Visible(c) return c ~= nil and (c[4] or 1) > 0 end

--------------------------------------------------------------------------------
--  Audit: every text-like colour a Look puts on a fill must keep the contrast
--  the theme promises. Walked for every combination of states a control can
--  be in, so a hover or an on layer can't quietly break it.
--------------------------------------------------------------------------------
local TEXTLIKE = { text = 4.5, glyph = 3, title = 4.5, placeholder = 3, knob = 3, dot = 3, header = 4.5 }
local STATES = {
    {}, { on = true }, { hover = true }, { on = true, hover = true },
    { pressed = true }, { focus = true }, { on = true, pressed = true },
}

--- Failures as strings, for the looks against the given palette.
function T.AuditLooks(mode)
    local fails = {}
    local p = T.PALETTES[mode or T.mode or "standard"]
    -- Resolve against that palette, not the live one.
    local saved = T.C
    T.C = p
    local ok, err = pcall(function()
        local out = {}
        for name, look in pairs(L) do
            for _, st in ipairs(STATES) do
                T.Resolve(look, st, out)
                local fill = out.fill or out.track
                if fill and fill[4] and fill[4] >= 0.95 then
                    for key, need in pairs(TEXTLIKE) do
                        local c = out[key]
                        if c and T.Visible(c) then
                            local r = T.Contrast(c, fill)
                            if r < need then
                                local tag = {}
                                for k in pairs(st) do tag[#tag + 1] = k end
                                fails[#fails + 1] = ("look %s [%s] %s on fill %.2f < %.1f"):format(
                                    name, #tag > 0 and table.concat(tag, "+") or "rest", key, r, need)
                            end
                        end
                    end
                end
            end
        end
    end)
    T.C = saved
    if not ok then fails[#fails + 1] = "audit error: " .. tostring(err) end
    table.sort(fails)
    return fails
end
