if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Core.lua
--  The skinning library.
--
--  One rule, enforced by the API rather than by discipline: we never move
--  or resize anything Blizzard made. The painter handed to a part has no
--  SetPoint, no SetSize, no SetParent and no SetHeight. It can hide their
--  art, draw ours in its place, and restyle text. That is all. Every
--  layout bug this suite has had came from breaking that rule.
--
--  To be precise, because it matters for where this is going: the rule is
--  not "never move anything". It is "nothing that matches by GUESS may move anything". A
--  pack written against one named window, by a human who looked at it, is
--  a different thing and is allowed to. We do not have that layer yet.
--
--  We skin Blizzard's TEMPLATES, not their windows. Their UI is built from
--  a small set of XML templates reused everywhere: in this client 284
--  places inherit UIPanelButtonTemplate, 107 MinimalScrollBar, 76
--  WowStyle1Dropdown and 49 InsetFrame. Skin the template once and every
--  window that uses it is done, including load-on-demand ones we have
--  never seen. There is no list of windows to maintain.
--
--  A part declares what it recognises and what to paint:
--
--      S.Register{
--          name = "panelButton",
--          type = "Button",
--          keys = { "Left", "Middle", "Right", "Text" },
--          art  = { Left = "ui%-panel%-button%-up" },
--          paint = function(b, p)
--              p:Fade()
--              p:Fill("surface2")
--              p:Border("borderStrong")
--              p:Label(b.Text)
--          end,
--      }
--------------------------------------------------------------------------------
local ADDON, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON] = ns
local T = EV.Theme

-- This addon ships its own art. T.MEDIA points at EvermoreUI\Media\UI, which
-- is a DIFFERENT folder: asking for maximise.png through T.MEDIA resolved to
-- a file that does not exist, so the world map's maximise button was blanked
-- and then given nothing to draw. Use S.MEDIA for anything under
-- EvermoreUI_Skins\Media, T.MEDIA for the shared glyphs.
local SKIN_MEDIA = "Interface\\AddOns\\EvermoreUI_Skins\\Media\\"

local M = EV:NewModule("Skins", {
    enabled = true,
    fonts   = true,   -- restyle Blizzard's shared font objects
    parts   = {},     -- part name -> false to switch one off
    packs   = {},     -- window name -> false to switch one pack off
    hideSpellbookPages = false,  -- hide the spellbook's parchment (PlayerSpellsFrame pack)
})
ns.module = M
M.title = "Window Skins"
M.description = "Blizzard's own windows in the EvermoreUI palette. Their layout is never touched: we hide their art, draw ours in its place and restyle their text."

local S = {}
ns.S = S
S.MEDIA = SKIN_MEDIA
EV.Skins = S
S.module = M

local pairs, ipairs, type, select = pairs, ipairs, type, select
local issecret = issecretvalue or function() return false end

local MAX_DEPTH = 8

--------------------------------------------------------------------------------
--  Bookkeeping
--------------------------------------------------------------------------------
-- Objects we created. The walk never looks at them, and nothing else may.
S.ours = setmetatable({}, { __mode = "k" })
-- Objects a part has already claimed, and which part claimed them.
S.claimed = setmetatable({}, { __mode = "k" })
-- Parts that threw while painting: part name -> how many times.
S.errors = {}
-- Per-object scratch for the parts (hover state, our textures).
local data = setmetatable({}, { __mode = "k" })
function S.D(obj)
    local d = data[obj]
    if not d then d = {}; data[obj] = d end
    return d
end

function S.Alive(o)
    return type(o) == "table" and o.GetObjectType and not (o.IsForbidden and o:IsForbidden())
end

local function Num(v) return type(v) == "number" and not issecret(v) and v or nil end
S.Num = Num

--- Every texture and font string directly on an object.
local function Regions(obj)
    if not (obj and obj.GetRegions) then return {} end
    local ok, r = pcall(function() return { obj:GetRegions() } end)
    return ok and r or {}
end
S.Regions = Regions

local function Children(obj)
    if not (obj and obj.GetChildren) then return {} end
    local ok, r = pcall(function() return { obj:GetChildren() } end)
    return ok and r or {}
end
S.Children = Children

--------------------------------------------------------------------------------
--  The painter
--
--  The only handle a part gets on an object. Deliberately missing: every
--  call that would move, resize or reparent something of Blizzard's.
--------------------------------------------------------------------------------
local Painter = {}
Painter.__index = Painter

local function Ours(obj) S.ours[obj] = true; return obj end
S.Ours = Ours

--- Hide art without hiding the object: SetAlpha(0), never Hide(), because
--- Blizzard's own code and Edit Mode both measure frames that are shown.
--- Blank a button's state textures rather than fading them. It is the
--- stronger move: Blizzard's own code re-sets
--- the texture on state changes, which puts a faded one back at full
--- alpha with a new texture object we never saw.
local function Blank(button)
    if not button then return end
    for _, setter in ipairs({ "SetNormalTexture", "SetPushedTexture",
                              "SetHighlightTexture", "SetDisabledTexture",
                              "SetCheckedTexture" }) do
        if type(button[setter]) == "function" then pcall(button[setter], button, "") end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture",
                              "GetHighlightTexture", "GetDisabledTexture",
                              "GetCheckedTexture" }) do
        if type(button[getter]) == "function" then
            local ok, t = pcall(button[getter], button)
            if ok and t and t.SetAlpha then t:SetAlpha(0) end
        end
    end
end
S.Blank = Blank

local function Mute(region)
    if not (region and region.SetAlpha) then return end
    if S.ours[region] then return end
    if region.SetAtlas or region.SetTexture then
        region:SetAlpha(0)
        S.D(region).muted = true
        -- Deliberately NOT a permanent SetAlpha hook. Blizzard pools and
        -- recycles textures: a pooled texture muted while it was drawing
        -- chrome comes back as a map tile or a list row's icon, and a
        -- forever-hook would keep it invisible for the rest of the
        -- session with nothing to explain why. Art that Blizzard puts
        -- back is caught by the re-walk on the window's OnShow, and for
        -- buttons by Blank(), which clears the texture rather than
        -- fighting its alpha.
    end
end
S.Mute = Mute

--- Fade every texture on an object (font strings are left alone: they are
--- content, and Label handles their styling).
--- Mute every texture on an object. A sweep cannot tell chrome from content,
--- so pass `keep` (a list of regions) for anything that is content: an icon,
--- a coin. Anything kept is left exactly as Blizzard has it.
function Painter:Fade(obj, keep)
    obj = obj or self.obj
    if not S.Alive(obj) then return self end
    local spare
    if keep then
        spare = {}
        for _, r in ipairs(keep) do if type(r) == "table" then spare[r] = true end end
    end
    for _, r in ipairs(Regions(obj)) do
        if not (spare and spare[r]) and r.GetObjectType and r:GetObjectType() == "Texture" then Mute(r) end
    end
    return self
end

--- Fade named keys only (some templates keep a texture we want).
function Painter:FadeKeys(...)
    for i = 1, select("#", ...) do
        local r = self.obj[(select(i, ...))]
        if type(r) == "table" and r.SetAlpha then
            if r.GetObjectType and r:GetObjectType() == "Texture" then Mute(r) else self:Fade(r) end
        end
    end
    return self
end

--- Fade a NineSlice's eight edges and corners plus its centre.
function Painter:FadeSlice(slice)
    slice = slice or self.obj.NineSlice
    if not S.Alive(slice) then return self end
    self:Fade(slice)
    for _, k in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
                         "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }) do
        local r = slice[k]
        if type(r) == "table" then Mute(r) end
    end
    return self
end

--- A colour for a painter: a token, or any Look colour spec (a mix, a token
--- with an alpha). `alpha` overrides the spec's own.
local specScratch = {}
local function Colour(spec, alpha)
    if type(spec) ~= "table" then return T.RGBA(spec or "text", alpha) end
    local r, g, b, a = T.C4(T.SpecRGBA(spec, specScratch))
    return r, g, b, alpha or a
end
S.Colour = Colour

--- Who repaints an object on a theme change, once a part paints its state.
---
--- Fill, Border, Label and Glyph each paint a rest colour and watch for the
--- theme. On a control that also paints its state (States, or a part's own
--- Sync), that left two painters on one colour, and which ran last on a
--- theme change was down to pairs() order: a checked box could come back
--- with a plain edge, a selected tab with a muted label. The state painter
--- registers here as the owner of the object and its label, and the rest
--- painters defer to it whichever order they are called in.
local owners = setmetatable({}, { __mode = "k" })
function S.Own(fn, ...)
    for i = 1, select("#", ...) do
        local obj = select(i, ...)
        if type(obj) == "table" then
            owners[obj] = fn
            T.Watch(obj, fn)
            local rec = EV.Pixel:EdgesOf(obj)
            if rec then T.Watch(rec.edges[1], fn) end
            local d = data[obj]
            if d and d.fill then T.Watch(d.fill, fn) end
            if d and d.glyph then T.Watch(d.glyph, fn) end
        end
    end
end
function S.Owner(obj) return owners[obj] end

--- Our flat surface, behind everything the object draws.
---
--- `on` paints a DIFFERENT object. That exists because a frame can be chrome
--- drawn over content, and the background then belongs on something lower.
--- Blizzard's own answer for the world map is Blizzard_WorldMap.lua line 28:
---
---     self.BorderFrame.Bg:SetParent(self);
---
--- BorderFrame is frameStrata="HIGH" and setAllPoints, so anything painted
--- on it covers the map, the nav bar and every overlay button. See
--- FillTarget in Parts.lua, which follows the Bg to wherever Blizzard put it.
function Painter:Fill(token, alpha, sub, on)
    local obj = on or self.obj
    if not (obj and obj.CreateTexture) then return self end
    local d = S.D(obj)
    -- EV.Pixel keeps the texture; d.fill is the same one, for the parts
    -- that recolour it (States, panelTab) and the packs that hide it.
    d.fill = d.fill or Ours(EV.Pixel:Fill(obj, "BACKGROUND", sub or -7))
    d.fillToken, d.fillAlpha = token, alpha
    d.fill:SetColorTexture(Colour(token, alpha))
    local own = owners[obj]
    if own then
        T.Watch(d.fill, own)
        own()
    else
        T.Watch(d.fill, function(t) t:SetColorTexture(Colour(d.fillToken, d.fillAlpha)) end)
    end
    return self
end

--- One physical pixel of border, on EV.Pixel's hairlines, which live in its
--- weak table: nothing is written onto the object, so a Blizzard frame is
--- safe to border.
---
--- `on` borders something other than the painted object, the same way Fill's
--- fourth argument fills something else. A check box needs it: the button's
--- rect is its hit area, not its box (the auction house's is 36x36 for a box
--- that reads about 20), so the border belongs on the box we draw inside it.
function Painter:Border(token, alpha, on)
    local obj = on or self.obj
    if not (obj and obj.CreateTexture) then return self end
    local d = S.D(obj)
    if not EV.Pixel:EdgesOf(obj) and S.UserScaled(obj) then self:Unscaled(obj) end
    local edges = EV.Pixel:Edges(obj, { size = 1 })
    if not d.edges then
        for _, e in ipairs(edges) do Ours(e) end
        d.edges = edges
    end
    d.edgeToken, d.edgeAlpha = token or "border", alpha
    local function Paint()
        EV.Pixel:SetEdgeColor(obj, Colour(d.edgeToken, d.edgeAlpha))
    end
    Paint()
    local own = owners[obj]
    if own then
        T.Watch(edges[1], own)
        own()
    else
        T.Watch(edges[1], Paint)
    end
    d.border = edges
    return self
end

--- For a frame Blizzard scales after we paint it (UserScaledFrameTemplate:
--- the static pop-up's buttons and field). Call before Border. A strip sized
--- to one pixel at the old scale comes out under a pixel at the new one and
--- a side rounds away, so the strips go on a container of ours that ignores
--- the frame's scale (Pixel:Edges, `decouple`, the nameplates' fix for the
--- same fault): exactly one pixel whatever the frame is scaled to. The
--- container sits a level above the frame, so a backdrop's NineSlice, a
--- child at the frame's own level, cannot draw over it either.
---
--- Border calls this itself for anything carrying UserScaledElementMixin (or
--- its by-height sibling), so every user-scaled control is covered: the
--- pop-ups, the add-friend frame, text to speech.
local function UserScaled(obj)
    return type(obj.OnLoad_UserScaledElement) == "function"
        or type(obj.OnLoad_UserScaledByHeight) == "function"
end
S.UserScaled = UserScaled

function Painter:Unscaled(obj)
    obj = obj or self.obj
    if not (obj and obj.CreateTexture) or EV.Pixel:EdgesOf(obj) then return self end
    local _, rec = EV.Pixel:Edges(obj, { size = 1, decouple = true })
    if rec.host then Ours(rec.host) end
    return self
end

--- A painter for any object, for code outside a part (the packs' Kit).
function S.PainterFor(obj) return setmetatable({ obj = obj }, Painter) end
S.Painter = Painter

--- Every hairline is EV.Pixel's now; one resnap covers them all.
function S.ResnapBorders() EV.Pixel:ResnapAll() end

--- A font string takes our face and one of our colours. Size and
--- justification are Blizzard's; we do not re-flow their text.
function Painter:Label(fs, token, bold)
    fs = fs or self.obj.Text
    if not (fs and fs.GetFont and fs.SetFont) then return self end
    local ok, _, size = pcall(fs.GetFont, fs)
    if not ok then return self end
    size = Num(size) or 12
    local path = bold and T.FontBoldPath() or T.FontPath()
    if path then pcall(fs.SetFont, fs, path, size, "") end
    if token ~= false then
        local d = S.D(fs)
        d.token = token or "text"
        local own = owners[fs]
        if own then
            T.Watch(fs, own)
            own()
        else
            S.RepaintText(fs)
            T.Watch(fs, S.RepaintText)
        end
    end
    return self
end

--- A drop shadow is there to lift light text off a dark ground. Under dark
--- text on a light fill (a primary button's label) the same black shadow
--- smears the letters into the fill, so dark text drops it and light text
--- gets back whatever shadow the font string had before we touched it.
local shadows = setmetatable({}, { __mode = "k" })  -- font string -> its own shadow
local shadowScratch = {}
function S.ShadowFor(fs, r, g, b)
    if not (fs and fs.SetShadowColor and fs.GetShadowColor) then return end
    local saved = shadows[fs]
    if not saved then
        local ok, sr, sg, sb, sa = pcall(fs.GetShadowColor, fs)
        local okO, ox, oy = pcall(fs.GetShadowOffset, fs)
        if not (ok and okO) then return end
        saved = { sr or 0, sg or 0, sb or 0, sa or 0, ox or 0, oy or 0 }
        shadows[fs] = saved
    end
    shadowScratch[1], shadowScratch[2], shadowScratch[3] = r, g, b
    if T.Luminance(shadowScratch) < 0.18 then
        fs:SetShadowColor(0, 0, 0, 0)
    else
        fs:SetShadowColor(saved[1], saved[2], saved[3], saved[4])
        fs:SetShadowOffset(saved[5], saved[6])
    end
end

--- Theme repaint for a font string we coloured: its token lives in S.D.
function S.RepaintText(fs)
    local r, g, b, a = Colour(S.D(fs).token or "text")
    fs:SetTextColor(r, g, b, a)
    S.ShadowFor(fs, r, g, b)
end

--- One of our glyphs, centred on the object.
function Painter:Glyph(name, size, token)
    local obj = self.obj
    local d = S.D(obj)
    if not d.glyph then
        if not obj.CreateTexture then return self end
        d.glyph = Ours(obj:CreateTexture(nil, "OVERLAY", nil, 7))
        d.glyph:SetPoint("CENTER")
    end
    d.glyph:SetTexture(T.MEDIA .. name .. ".png")
    local s = size or 10
    d.glyph:SetSize(s, s)
    d.glyphToken = token or "text"
    d.glyph:SetVertexColor(Colour(d.glyphToken))
    d.glyph.Paint = function(self2) self2:SetVertexColor(Colour(d.glyphToken)) end
    local own = owners[obj]
    if own then
        T.Watch(d.glyph, own)
        own()
    else
        T.Watch(d.glyph)
    end
    return self
end

--- Repaint through a Look on hover, press, focus and disable, from
--- Blizzard's own scripts. The same Look, and the same T.Resolve, that our
--- widget of that kind is drawn with, so the two cannot drift.
---
--- What it paints: the fill (Painter:Fill), the edge (Painter:Border, on
--- `opts.edgesOn` when the border lives on a box inside the button), the
--- label (`opts.label`, a font string or an edit box), the glyph
--- (Painter:Glyph, or `opts.glyph`) and a chevron (`opts.chev`). An edit box
--- also follows its focus. `opts.on` returns whether the control is on
--- (checked, selected, open).
---
--- State lives in S.D(obj) as hover / pressed / focus / disabled / on, the
--- names T.Resolve reads.
function Painter:States(look, opts)
    local obj, d = self.obj, S.D(self.obj)
    d.look, d.stateOpts = look, opts or d.stateOpts or {}
    if d.states then d.Repaint(); return self end
    d.states = true
    local out = {}
    local function Repaint()
        local o = d.stateOpts
        local okE, enabled = true, true
        if obj.IsEnabled then okE, enabled = pcall(obj.IsEnabled, obj) end
        d.disabled = okE and enabled == false or false
        if o.on then
            local okO, on = pcall(o.on)
            d.on = okO and on and true or false
        end
        local r = T.Resolve(d.look, d, out)
        -- The Look's own alpha: a transparent rest ("none") that fills on
        -- hover is a Look, not a Fill with alpha 0.
        if d.fill and r.fill then d.fill:SetColorTexture(T.C4(r.fill)) end
        local edgesOn = o.edgesOn or obj
        if r.edge and EV.Pixel:EdgesOf(edgesOn) then T.SetEdge(edgesOn, r.edge) end
        if o.label and r.text and o.label.SetTextColor then
            local tr, tg, tb, ta = T.C4(r.text)
            o.label:SetTextColor(tr, tg, tb, ta)
            S.ShadowFor(o.label, tr, tg, tb)
        end
        local glyph = o.glyph or d.glyph
        if glyph and r.glyph then glyph:SetVertexColor(T.C4(r.glyph)) end
        if o.chev and r.glyph then o.chev:SetColorLines(T.C4(r.glyph)) end
        if o.after then o.after(r) end
    end
    d.Repaint = Repaint
    if obj.HookScript then
        local hooks = {
            OnEnter     = function() d.hover = true; Repaint() end,
            OnLeave     = function() d.hover = false; d.pressed = false; Repaint() end,
            OnMouseDown = function() d.pressed = true; Repaint() end,
            OnMouseUp   = function() d.pressed = false; Repaint() end,
            OnShow      = Repaint,
        }
        if obj.GetObjectType and obj:GetObjectType() == "EditBox" then
            hooks.OnEditFocusGained = function() d.focus = true; Repaint() end
            hooks.OnEditFocusLost = function() d.focus = false; Repaint() end
        end
        for script, fn in pairs(hooks) do obj:HookScript(script, fn) end
        -- SetScript drops every hook on that script along with the handler,
        -- and some of Blizzard's code sets scripts on every use. The game
        -- menu does: MainMenuFrameMixin:AddButton sets OnEnter and OnLeave
        -- on each button every time the menu opens, so its hover worked on
        -- the first opening and never again. Put ours back after, through
        -- hooksecurefunc, which leaves Blizzard's own call secure.
        if type(obj.SetScript) == "function" then
            pcall(hooksecurefunc, obj, "SetScript", function(self, script)
                local fn = hooks[script]
                if fn then self:HookScript(script, fn) end
            end)
        end
    end
    for _, m in ipairs({ "Enable", "Disable", "SetEnabled" }) do
        if type(obj[m]) == "function" then pcall(hooksecurefunc, obj, m, Repaint) end
    end
    -- The theme repaints through the same path, and only through it: this
    -- owns the object, its box and its label (see S.Own).
    local o = d.stateOpts
    S.Own(Repaint, obj, o.edgesOn, o.label, o.glyph)
    Repaint()
    return self
end

--- A surface Look (window, raised, inset, control) in one: fill and border
--- in its rest colours. `on` as for Fill.
function Painter:Surface(look, alpha, sub, on)
    if type(look) == "string" then look = T.LOOK[look] end
    local r = look and look.rest or T.LOOK.raised.rest
    self:Fill(r.fill or "surface1", alpha, sub, on)
    if r.edge and r.edge ~= "none" then self:Border(r.edge) end
    return self
end

--- Re-seat a control's OWN furniture, because our border is not where
--- Blizzard's border was.
---
--- This is the single place a part may move anything of Blizzard's, and it
--- is deliberately not a general SetPoint. The justification is narrow:
---
---   Blizzard's input art is anchored OUTSIDE the frame rect.
---   InputBoxVisualTemplate anchors its Left texture at LEFT x="-5";
---   InputBoxTemplate's corners sit at TOPLEFT x="-5" y="5". So the visible
---   left edge of a search box is 5px outside the rect, and the search icon
---   at LEFT x="1" reads as 6px inside that edge.
---
---   Our border is drawn ON the rect. The moment we swap the art, that same
---   icon is 1px from the line and the text crowds it. The geometry we are
---   correcting is geometry WE broke.
---
--- The guards are what keep this from becoming the generic layout pass that
--- broke the friends list and the merchant window:
---
---   * the region must be parented to the very object being painted, so it
---     can never reach a sibling, a parent, or another window
---   * it anchors only to that object, and only to the same point name
---     Blizzard used, so a LEFT region stays on the left
---   * it sets offsets, never sizes, never parents
---   * the values are absolute, so the OnShow re-walk re-applies rather than
---     accumulating
function Painter:Reseat(region, points)
    local obj = self.obj
    if type(region) ~= "table" or not (region.ClearAllPoints and region.SetPoint) then return self end
    if not region.GetParent then return self end
    local ok, parent = pcall(region.GetParent, region)
    if not ok or parent ~= obj then return self end
    if type(points) ~= "table" or #points == 0 then return self end
    region:ClearAllPoints()
    for _, pt in ipairs(points) do
        pcall(region.SetPoint, region, pt[1], obj, pt[1], pt[2] or 0, pt[3] or 0)
    end
    return self
end

--- Guarantee a minimum breathing space for an edit box's text.
---
--- Only ever INCREASES an inset. A window that deliberately set a larger one
--- keeps it, and running this twice is the same as running it once, because
--- max is idempotent and the OnShow re-walk will run it again.
function Painter:TextPad(left, right)
    local e = self.obj
    if type(e.SetTextInsets) ~= "function" or type(e.GetTextInsets) ~= "function" then return self end
    local ok, l, r, t, b = pcall(e.GetTextInsets, e)
    if not ok then return self end
    l, r = Num(l) or 0, Num(r) or 0
    t, b = Num(t) or 0, Num(b) or 0
    pcall(e.SetTextInsets, e, math.max(l, left or 0), math.max(r, right or 0), t, b)
    return self
end

--- Post-hook a script. Never replaces Blizzard's.
function Painter:Hook(script, fn)
    if self.obj.HookScript then self.obj:HookScript(script, fn) end
    return self
end

--- Post-hook a method. Never replaces Blizzard's.
function Painter:After(method, fn)
    if type(self.obj[method]) == "function" then pcall(hooksecurefunc, self.obj, method, fn) end
    return self
end

--------------------------------------------------------------------------------
--  The registry
--------------------------------------------------------------------------------
local parts = {}
S.parts = parts

function S.Register(part)
    assert(type(part) == "table" and part.name and part.paint, "a part needs a name and a paint")
    -- A part MUST say what it recognises. `type` alone is not a
    -- fingerprint: a part registered as just type="CheckButton" claimed
    -- every check button in the game, blanked their normal textures and
    -- drew a tick box over the top, which is how the quest log and the
    -- community roster lost their icons. Nothing ships without one.
    assert(part.keys or part.art or part.test or part.layout or part.file or part.artOrFile,
        ("part '%s' has no fingerprint: give it keys, art, file, layout or a test"):format(part.name))
    parts[#parts + 1] = part
    return part
end

--- A key counts as present only when it holds a real object. Frames in the
--- game return nil for keys they do not have; testing for a table keeps
--- this honest under any metatable.
local function HasKeys(obj, keys)
    for _, k in ipairs(keys) do
        if type(rawget(obj, k) or obj[k]) ~= "table" then return false end
    end
    return true
end

--- Does a region carry this texture or atlas? Patterns are lower case.
local function ArtIs(region, pattern)
    if type(region) ~= "table" then return false end
    if region.GetAtlas then
        local ok, a = pcall(region.GetAtlas, region)
        if ok and type(a) == "string" and a:lower():find(pattern) then return true end
    end
    if region.GetTexture then
        local ok, t = pcall(region.GetTexture, region)
        if ok and type(t) == "string" and t:lower():find(pattern) then return true end
    end
    return false
end
S.ArtIs = ArtIs

--- Does a region carry this FILE texture?
---
--- File art looks unmatchable at first, because GetTexture() on a texture
--- declared in XML with file="Interface\\..." hands back
--- "FileData ID 123456" rather than the path. But we never have to parse that string: we put
--- the same path on a scratch texture of our own and compare what the client
--- gives back for both. Whatever form it uses, both sides use it.
---
--- This is what brings the classic half of the UI back in range. Forever
--- draws a great deal of its chrome from files rather than atlases
--- (UI-Background-Marble, UI-DialogBox-Background, UI-CheckBox-Up), and
--- until now no part could see any of it.
local scratch
local resolved = {}
function S.TexID(path)
    local hit = resolved[path]
    if hit ~= nil then return hit or nil end
    if not scratch then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        scratch = Ours(holder:CreateTexture(nil, "BACKGROUND"))
    end
    local id = false
    -- Clear first and check the value actually CHANGED. On a path the client
    -- cannot resolve, SetTexture can leave the previous texture in place, and
    -- we would read that one's id back: two unrelated paths would then resolve
    -- to the same art and every texture drawn from the first would be muted
    -- as if it were the second.
    pcall(scratch.SetTexture, scratch, nil)
    local _, before = pcall(scratch.GetTexture, scratch)
    if pcall(scratch.SetTexture, scratch, path) then
        local ok, got = pcall(scratch.GetTexture, scratch)
        if ok and got ~= nil and got ~= "" and got ~= before then id = got end
    end
    resolved[path] = id
    return id or nil
end

local function ArtIsFile(region, path)
    if type(region) ~= "table" or not region.GetTexture then return false end
    -- Atlas-backed regions are excluded deliberately. Dozens of unrelated
    -- atlases share one sheet file, so comparing an atlas region by file
    -- would claim half the interface at once. An atlas is matched by name,
    -- through ArtIs, or not at all.
    if region.GetAtlas then
        local ok, a = pcall(region.GetAtlas, region)
        if ok and a and a ~= "" then return false end
    end
    local want = S.TexID(path)
    if not want then return false end
    local ok, got = pcall(region.GetTexture, region)
    return ok and got ~= nil and got == want
end
S.ArtIsFile = ArtIsFile

--- Blizzard's own name for the frame's chrome.
---
--- NineSliceUtil reads `frame.layoutType` to pick which slice art a panel
--- gets, so Blizzard maintains it, it is inherited with the template, and it
--- says plainly what a frame IS: "InsetFrameTemplate", "PortraitFrameTemplate",
--- "Dialog", "TooltipDefaultLayout", "HeldBagLayout". It is a far better
--- fingerprint than guessing from art, and reading a field is not a write, so
--- there is no taint risk. Prefer it wherever a frame has one.
local function LayoutType(f)
    if type(f) ~= "table" then return nil end
    local ok, lt = pcall(function() return f.layoutType end)
    if ok and type(lt) == "string" then return lt end
    return nil
end
S.LayoutType = LayoutType

--- A named sub-region, however Blizzard attached it.
---
--- Modern templates use parentKey, so the region is a field: frame.Left.
--- Older ones name the region "$parentLeft" and attach nothing, so the only
--- handle is the global FrameNameLeft. Both are everywhere in this client
--- (the mail edit boxes are the second kind), and a fingerprint that only
--- knows the first silently misses every old template.
function S.Sub(obj, suffix)
    if type(obj) ~= "table" then return nil end
    local v = obj[suffix]
    if type(v) == "table" then return v end
    local name = obj.GetName and obj:GetName()
    if not name then return nil end
    v = _G[name .. suffix]
    if type(v) == "table" then return v end
    return nil
end

local function Matches(part, obj)
    if part.layout then
        local lt = LayoutType(obj)
        if not lt then return false end
        local want = part.layout
        if type(want) == "string" then
            if lt ~= want then return false end
        else
            local any = false
            for _, v in ipairs(want) do if lt == v then any = true break end end
            if not any then return false end
        end
    end
    if part.notLayout then
        local lt = LayoutType(obj)
        if lt then
            for _, v in ipairs(part.notLayout) do if lt == v then return false end end
        end
    end
    if part.type then
        if not obj.IsObjectType then return false end
        local ok, is = pcall(obj.IsObjectType, obj, part.type)
        if not (ok and is) then return false end
    end
    if part.keys and not HasKeys(obj, part.keys) then return false end
    if part.without then
        for _, k in ipairs(part.without) do
            if type(obj[k]) == "table" then return false end
        end
    end
    if part.art then
        for k, pattern in pairs(part.art) do
            local region = (k == 1 or k == "self") and obj or obj[k]
            if k == "normal" and obj.GetNormalTexture then
                local ok, n = pcall(obj.GetNormalTexture, obj); region = ok and n or nil
            end
            if not ArtIs(region, pattern) then return false end
        end
    end
    if part.file then
        for k, path in pairs(part.file) do
            local region = (k == 1 or k == "self") and obj or obj[k]
            if k == "normal" and obj.GetNormalTexture then
                local ok, n = pcall(obj.GetNormalTexture, obj); region = ok and n or nil
            end
            if not ArtIsFile(region, path) then return false end
        end
    end
    -- art OR file: for a template whose art is an atlas on one client and a
    -- file on another, which is most of the shared ones.
    if part.artOrFile then
        for k, pair in pairs(part.artOrFile) do
            local region = (k == 1 or k == "self") and obj or obj[k]
            if k == "normal" and obj.GetNormalTexture then
                local ok, n = pcall(obj.GetNormalTexture, obj); region = ok and n or nil
            end
            local hit = false
            for _, pattern in ipairs(pair.atlas or {}) do
                if ArtIs(region, pattern) then hit = true break end
            end
            if not hit then
                for _, path in ipairs(pair.files or {}) do
                    if ArtIsFile(region, path) then hit = true break end
                end
            end
            if not hit then return false end
        end
    end
    if part.test then
        local ok, res = pcall(part.test, obj)
        if not (ok and res) then return false end
    end
    return true
end
S.Matches = Matches

--------------------------------------------------------------------------------
--  Claiming
--------------------------------------------------------------------------------
local stats
local running      -- the budgeted walk whose slice is running (see The walk)

--- Try every part against one object, first match wins.
function S.Dress(obj)
    if not S.Alive(obj) or S.ours[obj] or S.claimed[obj] then return end
    if M.db and M.db.enabled == false then return end
    for _, part in ipairs(parts) do
        if (not M.db or M.db.parts[part.name] ~= false) and Matches(part, obj) then
            S.claimed[obj] = part.name
            local p = setmetatable({ obj = obj, part = part }, Painter)
            local ok, err = pcall(part.paint, obj, p)
            if not ok then
                -- Recorded as well as raised: a part that throws is a bug
                -- in the part, and `/evui skin` should say so rather than
                -- leaving it to scroll past in the error frame.
                S.errors[part.name] = (S.errors[part.name] or 0) + 1
                S.lastError = ("%s: %s"):format(part.name, tostring(err))
                geterrorhandler()(("EvermoreUI Skins (%s): %s"):format(part.name, tostring(err)))
            else
                if stats then stats[part.name] = (stats[part.name] or 0) + 1 end
                if running then running.dressed = running.dressed + 1 end
            end
            return part
        end
    end
end

--- Blizzard's decoration is not all inside a template. Windows hang loose
--- chrome straight onto themselves: the communities list is
--- Interface\\Common\\bluemenu-main, the guild panels are one big
--- GuildFrame sheet. So every region the walk meets is checked against
--- the decoration list, wherever it hangs. This is the pass that was
--- missing: the list existed but only the diagnostic ever read it.
local function StripOrnate(obj)
    if not S.IsOrnate then return end
    for _, r in ipairs(Regions(obj)) do
        if not S.ours[r] and r.GetObjectType and r:GetObjectType() == "Texture" and S.IsOrnate(r) then
            Mute(r)
        end
    end
end
S.StripOrnate = StripOrnate

--------------------------------------------------------------------------------
--  Dark-on-dark text
--
--  Blizzard's quest, gossip, mail, book and petition windows draw their text
--  in near-black, because for twenty years it sat on paper: QuestFont is
--  Color r="0" g="0" b="0" (Blizzard_Fonts_Shared/Shared/FontStyles.xml:46)
--  and ItemTextFontNormal is 0.18/0.12/0.06. We take the paper away, so the
--  text has to come with it.
--
--  Restyling the shared font objects (Fonts.lua) covers most of the game but
--  cannot cover this: a font string with its own <Color> in XML, a runtime
--  SetTextColor, or a |cff000000 run baked into the string itself all beat
--  the font object. NORMAL_QUEST_DISPLAY is the last of those, which is why
--  a gossip quest title stayed pure black while everything around it lifted.
--
--  So this is measured rather than named. Anything already dark enough to
--  disappear against our surfaces is repainted in our body colour, whatever
--  put it there. SetFixedColor is what makes it stick over a baked colour
--  run; Blizzard's own dark-background mode uses it in exactly this spot
--  (Blizzard_UIPanels_Game/Mainline/QuestFrame.lua:341).
--------------------------------------------------------------------------------
-- Relative luminance. Every parchment colour Blizzard ships lands under 0.22
-- (the brightest is SubSpellFont at 0.35/0.20/0); our lightest token that is
-- ever deliberately dark is onAccent, and that only reaches a font string
-- through Painter:Label, which stamps a token we skip on.
local DARK_TEXT = 0.35

local function Lum(r, g, b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

local function LiftText(obj)
    for _, r in ipairs(Regions(obj)) do
        if not S.ours[r] and r.GetObjectType and r.GetTextColor
           and r:GetObjectType() == "FontString" and not S.D(r).token then
            local ok, cr, cg, cb, ca = pcall(r.GetTextColor, r)
            cr, cg, cb = Num(cr), Num(cg), Num(cb)
            ca = Num(ca) or 1
            -- Alpha 0 is somebody hiding the string on purpose. Leave it.
            if ok and cr and cg and cb and ca > 0 and Lum(cr, cg, cb) < DARK_TEXT then
                if type(r.SetFixedColor) == "function" then pcall(r.SetFixedColor, r, true) end
                S.D(r).token = "text"
                pcall(r.SetTextColor, r, T.RGBA("text"))
                T.Watch(r, S.RepaintText)
            end
        end
    end
end
S.LiftText = LiftText

--------------------------------------------------------------------------------
--  The walk
--
--  S.Walk is synchronous: a whole subtree in one go. That is what a scroll
--  box's row callback and a pack's k:Dress need, because both run inside
--  Blizzard's own code and the row has to be dressed before it is drawn.
--
--  A window is walked differently. The professions and auction house windows
--  run to thousands of frames, each one tried against every part, and in one
--  go that is a hitch you feel when the window opens, and again at login when
--  the sweep adopts every panel the game knows about. So a window's walk is a
--  coroutine on a time budget: it does as much as fits in S.WALK_BUDGET_MS,
--  lets the frame draw, and carries on in the next.
--
--  The first slice of a window that is on screen runs at once, inside the
--  OnShow that asked for it, so a small window is dressed before it is ever
--  drawn. Only a big one is seen part-dressed, and only for a frame or two.
--  Windows walked while hidden (the login sweep) wait their turn and share
--  one budget per frame, the one on screen first.
--
--  Lua 5.1 cannot yield across a pcall or a C function. The yield point is in
--  Visit, between objects, never inside a part's paint (pcalled) or a callback
--  Blizzard makes into us (a C boundary). Anything that walks from inside one
--  of those goes through S.Walk, which holds yields off until it returns.
--------------------------------------------------------------------------------
S.WALK_BUDGET_MS = 4

local now = debugprofilestop
local hold = 0            -- > 0 while a synchronous walk is running: no yields

local function Visit(obj, depth)
    if depth > MAX_DEPTH or not S.Alive(obj) or S.ours[obj] then return end
    local w = running
    if w then
        w.nodes = w.nodes + 1
        if hold == 0 and now() >= w.deadline and coroutine.running() == w.co then
            coroutine.yield()
            -- The frame may have gone while we were away.
            if not S.Alive(obj) then return end
        end
    end
    -- Where the time goes, for /evui skin profile: trying the parts, taking
    -- decoration down, lifting dark text.
    local prof = w and S.profiling
    local t0 = prof and now()
    local part = S.Dress(obj)
    local t1 = prof and now()
    -- A part may own a whole subtree. Tooltips are the case that matters:
    -- EvermoreUI_Tooltips skins them completely, so the walk claims them and
    -- goes no further rather than having two of our own addons paint the
    -- same frames.
    if part and part.stop then
        if prof then w.tParts = w.tParts + (t1 - t0) end
        return
    end
    StripOrnate(obj)
    local t2 = prof and now()
    LiftText(obj)
    if prof then
        local t3 = now()
        w.tParts, w.tArt, w.tText = w.tParts + (t1 - t0), w.tArt + (t2 - t1), w.tText + (t3 - t2)
    end
    for _, c in ipairs(Children(obj)) do Visit(c, depth + 1) end
end

--- Walk an object and everything under it, now, in one go.
function S.Walk(obj, depth)
    hold = hold + 1
    local ok, err = pcall(Visit, obj, depth or 0)
    hold = hold - 1
    if not ok then geterrorhandler()(("EvermoreUI Skins walk: %s"):format(tostring(err))) end
end

--- Budgeted walks: root -> its walk while one is going, and the order they
--- take their turns in.
local walks = setmetatable({}, { __mode = "k" })
local queue = {}
S.walkQueue = queue

local function Shown(f)
    if not (f and f.IsVisible) then return false end
    local ok, v = pcall(f.IsVisible, f)
    return ok and v == true
end

local function Step(w, budget)
    local outer = running
    running = w
    local t0 = now()
    w.deadline = t0 + budget
    local ok, err = coroutine.resume(w.co)
    local spent = now() - t0
    running = outer
    w.ms, w.slices = w.ms + spent, w.slices + 1
    if spent > w.worst then w.worst = spent end
    if not ok then
        walks[w.root] = nil
        geterrorhandler()(("EvermoreUI Skins walk: %s"):format(tostring(err)))
        -- The window's pack still runs: one bad object must not leave the
        -- whole window without its layout.
        if w.after then pcall(w.after, w.root) end
        return true
    end
    if coroutine.status(w.co) ~= "dead" then return false end
    walks[w.root] = nil
    if S.profiling and S.ReportWalk then S.ReportWalk(w) end
    if w.after then
        local okA, errA = pcall(w.after, w.root)
        if not okA then geterrorhandler()(("EvermoreUI Skins: %s"):format(tostring(errA))) end
    end
    -- Asked for again while it ran: what it asked about may already have
    -- been passed, so go over the whole window once more.
    if w.again then S.Rewalk(w.root, w.after) end
    return true
end

local function Dequeue(w)
    for i = #queue, 1, -1 do
        if queue[i] == w then table.remove(queue, i) end
    end
end

local runner = CreateFrame("Frame")
runner:Hide()
S.walkRunner = runner
runner:SetScript("OnUpdate", function(self)
    local t0 = now()
    while queue[1] do
        local left = S.WALK_BUDGET_MS - (now() - t0)
        if left <= 0 then break end
        local w = queue[1]
        if Step(w, left) then Dequeue(w) else break end
    end
    if not queue[1] then self:Hide() end
end)

--- Walk a window on the budget, then call `after(root)` (the window's pack).
--- Asking again while its walk is still going does not start a second one:
--- it is noted, and the window is gone over once more when this one ends.
function S.Rewalk(root, after)
    if not S.Alive(root) or S.ours[root] then return end
    if M.db and M.db.enabled == false then return end
    local w = walks[root]
    local shown = Shown(root)
    if w then
        -- Only if it has started: one still waiting will see everything.
        if w.nodes > 0 then w.again = true end
        w.after = after or w.after
        -- Asked from inside its own slice (a part's paint): the note is
        -- enough, a running coroutine cannot be resumed.
        if coroutine.status(w.co) ~= "suspended" then return end
        if shown and queue[1] ~= w then
            -- Opened while it waited its turn: it goes first, and starts now.
            Dequeue(w)
            table.insert(queue, 1, w)
            if Step(w, S.WALK_BUDGET_MS) then Dequeue(w) end
        end
        return
    end
    w = { root = root, after = after, nodes = 0, dressed = 0, ms = 0, slices = 0, worst = 0,
          tParts = 0, tArt = 0, tText = 0 }
    w.co = coroutine.create(function() Visit(root, 0) end)
    walks[root] = w
    -- From inside a synchronous walk we cannot yield, so do not start a
    -- slice here at all: queue it for the next frame.
    if shown and hold == 0 then
        if Step(w, S.WALK_BUDGET_MS) then return end
        table.insert(queue, 1, w)
    else
        queue[#queue + 1] = w
    end
    runner:Show()
end

--- Is a budgeted walk still going over this frame?
function S.Walking(root) return walks[root] ~= nil end

--- Walk a window and keep it fresh: pooled rows and lazily built panes
--- appear after the first pass, so walk again when it is next shown, and
--- follow its scroll boxes.
local watched = setmetatable({}, { __mode = "k" })

local function Pack(frame)
    -- The pack runs AFTER the walk, so it works on a window the generic
    -- layer has already dressed and only has to deal with what was left.
    if S.ApplyPack then S.ApplyPack(frame) end
end

function S.Adopt(frame)
    if not S.Alive(frame) or S.ours[frame] or watched[frame] then return end
    watched[frame] = true
    -- The pack once straight away as well as after the walk. A window whose
    -- addon loads as it opens (professions) is shown before its budgeted walk
    -- can finish, and its layout arrived a few frames late: the buttons were
    -- seen to jump. Packs are written to be run again (every mover keeps
    -- Blizzard's origin and sets absolute values), so the second run after
    -- the walk only finishes what the parts' paint needed.
    Pack(frame)
    S.Rewalk(frame, Pack)
    if frame.HookScript then
        -- Once per opening. A second pass the frame after was tried and
        -- taken out: on a window whose walk spans frames it arrived while
        -- the first was still going and made it go over the whole window
        -- again, doubling the cost of every opening for nothing seen to
        -- need it. Content built later is the packs' and the row
        -- callbacks' to catch.
        frame:HookScript("OnShow", function() S.Rewalk(frame, Pack) end)
    end
end

--- What the row passes cost, for `/evui skin profile`.
S.rowCost = { passes = 0, ms = 0 }

local function RowWalk(_, row)
    if S.profiling then
        local t0 = now()
        S.Walk(row, 0)
        S.rowCost.passes = S.rowCost.passes + 1
        S.rowCost.ms = S.rowCost.ms + (now() - t0)
    else
        S.Walk(row, 0)
    end
end

--- Scroll boxes recycle their rows; dress each one as it is initialised.
---
--- OnInitializedFrame fires after the row's initializer has run
--- (ScrollBox.lua, OnViewInitializedFrame), so a row is finished when we see
--- it. What that misses is a list rebuilt and then touched up (a selection
--- set, a header collapsed) straight after, so a rebuild also gets one pass
--- over the rows on show, the frame after, however many rebuilds there were.
---
--- It hooks FullUpdateInternal, not Update. Update runs on every step of a
--- scroll (SetScrollPercentageInternal calls it), and re-walking the rows on
--- each would be a cost paid every frame the wheel turns; a rebuild is a data
--- change (OnViewDataChanged -> FullUpdate -> FullUpdateInternal).
function S.FollowScrollBox(box)
    if not S.Alive(box) or S.D(box).followed then return end
    if not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    S.D(box).followed = true
    ScrollUtil.AddInitializedFrameCallback(box, RowWalk, nil, false)
    local function All()
        if box.ForEachFrame then pcall(box.ForEachFrame, box, function(row) RowWalk(nil, row) end) end
    end
    All()
    local pending = false
    local function Soon()
        if pending or not (C_Timer and C_Timer.After) then return end
        pending = true
        C_Timer.After(0, function() pending = false; All() end)
    end
    if type(box.FullUpdateInternal) == "function" then
        pcall(hooksecurefunc, box, "FullUpdateInternal", Soon)
    end
end

--------------------------------------------------------------------------------
--  Diagnostics support
--------------------------------------------------------------------------------
--- Count what one walk claims. Used by /evui skin.
function S.Measure(frame)
    stats = {}
    S.Walk(frame, 0)
    local out = stats
    stats = nil
    return out
end

--------------------------------------------------------------------------------
--  Module lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
    if self.db.fonts and S.ApplyFonts then
        S.ApplyFonts()
        if S.ApplyMaterials then S.ApplyMaterials() end
    end
    -- A scale change makes every hairline the wrong thickness, and the walk
    -- will not redraw them: Adopt only ever claims a window once.
    self:RegisterMessage("EV_PIXEL_CHANGED", function()
        if S.ResnapBorders then S.ResnapBorders() end
    end)
    if S.Sweep then S.Sweep() end
end

--- A theme change repaints through T.Watch; this is for the settings
--- changing which parts run.
function M:Refresh()
    if self.db.fonts and S.ApplyFonts then
        S.ApplyFonts()
        if S.ApplyMaterials then S.ApplyMaterials() end
    end
    if S.ResnapBorders then S.ResnapBorders() end
    if S.Sweep then S.Sweep() end
end

