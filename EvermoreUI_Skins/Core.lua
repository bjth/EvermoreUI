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
    local d = S.D(obj)
    if not d.fill then
        if not (obj.CreateTexture) then return self end
        d.fill = Ours(obj:CreateTexture(nil, "BACKGROUND", nil, sub or -7))
        d.fill:SetAllPoints(obj)
        if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(d.fill) end
    end
    d.fillToken, d.fillAlpha = token, alpha
    d.fill:SetColorTexture(T.RGBA(token, alpha))
    T.Watch(d.fill)
    d.fill.Paint = function(self2) self2:SetColorTexture(T.RGBA(d.fillToken, d.fillAlpha)) end
    return self
end

--- One physical pixel of border, on four textures of our own.
---
--- Deliberately not EV.Pixel:CreateBorder, which stashes the border on
--- `frame.evBorder`. That is a field write on one of Blizzard's frames,
--- which can taint a protected one; our own widgets can afford it, a
--- skinned Blizzard window cannot. The edges live in our weak table
--- instead, so nothing of theirs is written to at all.
--- `on` borders something other than the painted object, the same way Fill's
--- fourth argument fills something else. A check box needs it: the button's
--- rect is its hit area, not its box (the auction house's is 36x36 for a box
--- that reads about 20), so the border belongs on the box we draw inside it.
--- Re-apply one border's thickness. Split out because it has to run again
--- whenever the scale changes: a strip sized for the old scale is no longer
--- one physical pixel at the new one.
local bordered = setmetatable({}, { __mode = "k" })   -- object -> true

local function Snap4(obj)
    local d = S.D(obj)
    local e = d.edges
    if not e then return end
    local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(obj)) or 1
    e[1]:SetHeight(px); e[2]:SetHeight(px)
    e[3]:SetWidth(px);  e[4]:SetWidth(px)
end

function S.ResnapBorders()
    for obj in pairs(bordered) do
        if S.Alive(obj) then Snap4(obj) end
    end
end

function Painter:Border(token, alpha, on)
    local obj = on or self.obj
    local d = S.D(obj)
    if not obj.CreateTexture then return self end
    if not d.edges then
        local e = {}
        for i = 1, 4 do
            e[i] = Ours(obj:CreateTexture(nil, "BORDER", nil, 7))
            -- Without this a one-physical-pixel strip is at the mercy of the
            -- renderer's own texel snapping, and where it lands decides
            -- whether you get a line, two lines, or none. The auction house
            -- money boxes lost their top edge outright while the quantity box
            -- two rows above drew its top edge twice. EV.Pixel:CreateBorder
            -- has always done this; Painter:Border never did.
            if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(e[i]) end
        end
        e[1]:SetPoint("TOPLEFT");    e[1]:SetPoint("TOPRIGHT")
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
        e[3]:SetPoint("TOPLEFT");    e[3]:SetPoint("BOTTOMLEFT")
        e[4]:SetPoint("TOPRIGHT");   e[4]:SetPoint("BOTTOMRIGHT")
        d.edges = e
        bordered[obj] = true
    end
    -- Thickness every call, not just on creation: a second Border on the same
    -- object used to keep whatever the first one measured.
    Snap4(obj)
    d.edgeToken, d.edgeAlpha = token or "border", alpha
    local function Paint()
        for _, t in ipairs(d.edges) do t:SetColorTexture(T.RGBA(d.edgeToken, d.edgeAlpha)) end
    end
    Paint()
    T.Watch(d.edges[1])
    d.edges[1].Paint = Paint
    d.border = d.edges
    return self
end

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
        fs:SetTextColor(T.RGBA(d.token))
        T.Watch(fs)
        fs.Paint = function(self2) self2:SetTextColor(T.RGBA(S.D(self2).token)) end
    end
    return self
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
    d.glyph:SetVertexColor(T.RGBA(d.glyphToken))
    T.Watch(d.glyph)
    d.glyph.Paint = function(self2) self2:SetVertexColor(T.RGBA(d.glyphToken)) end
    return self
end

--- Repaint the fill on hover, press and disable. The tokens are ours, the
--- states are Blizzard's own scripts.
function Painter:States(map)
    local obj, d = self.obj, S.D(self.obj)
    if d.states then d.stateMap = map; return self end
    d.states, d.stateMap = true, map
    local function Repaint()
        local m = d.stateMap or {}
        local token = d.fillToken
        if obj.IsEnabled and not obj:IsEnabled() then token = m.disabled or token
        elseif d.pressed then token = m.pressed or token
        elseif d.hovered then token = m.hover or token end
        if d.fill then d.fill:SetColorTexture(T.RGBA(token, d.fillAlpha)) end
    end
    d.Repaint = Repaint
    if obj.HookScript then
        obj:HookScript("OnEnter", function() d.hovered = true; Repaint() end)
        obj:HookScript("OnLeave", function() d.hovered = false; Repaint() end)
        obj:HookScript("OnMouseDown", function() d.pressed = true; Repaint() end)
        obj:HookScript("OnMouseUp", function() d.pressed = false; Repaint() end)
        obj:HookScript("OnShow", Repaint)
    end
    for _, m in ipairs({ "Enable", "Disable", "SetEnabled" }) do
        if type(obj[m]) == "function" then pcall(hooksecurefunc, obj, m, Repaint) end
    end
    Repaint()
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
--  The walk
--------------------------------------------------------------------------------
local stats

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
            elseif stats then
                stats[part.name] = (stats[part.name] or 0) + 1
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
                T.Watch(r)
                r.Paint = function(self2) self2:SetTextColor(T.RGBA(S.D(self2).token)) end
            end
        end
    end
end
S.LiftText = LiftText

--- Walk an object and everything under it once.
function S.Walk(obj, depth)
    depth = depth or 0
    if depth > MAX_DEPTH or not S.Alive(obj) or S.ours[obj] then return end
    local part = S.Dress(obj)
    -- A part may own a whole subtree. Tooltips are the case that matters:
    -- EvermoreUI_Tooltips skins them completely, so the walk claims them and
    -- goes no further rather than having two of our own addons paint the
    -- same frames.
    if part and part.stop then return end
    StripOrnate(obj)
    LiftText(obj)
    for _, c in ipairs(Children(obj)) do S.Walk(c, depth + 1) end
end

--- Walk a window and keep it fresh: pooled rows and lazily built panes
--- appear after the first pass, so walk again when it is next shown, and
--- follow its scroll boxes.
local watched = setmetatable({}, { __mode = "k" })
function S.Adopt(frame)
    if not S.Alive(frame) or S.ours[frame] or watched[frame] then return end
    watched[frame] = true
    S.Walk(frame, 0)
    -- The pack runs AFTER the walk, so it works on a window the generic
    -- layer has already dressed and only has to deal with what was left.
    if S.ApplyPack then S.ApplyPack(frame) end
    if frame.HookScript then
        frame:HookScript("OnShow", function()
            S.Walk(frame, 0)
            if S.ApplyPack then S.ApplyPack(frame) end
        end)
    end
end

--- Scroll boxes recycle their rows; dress each one as it is initialised.
function S.FollowScrollBox(box)
    if not S.Alive(box) or S.D(box).followed then return end
    if not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return end
    S.D(box).followed = true
    ScrollUtil.AddInitializedFrameCallback(box, function(_, row) S.Walk(row, 0) end, nil, false)
    if box.ForEachFrame then pcall(box.ForEachFrame, box, function(row) S.Walk(row, 0) end) end
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

