if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Pixel.lua
--  Pixel-perfect scaling and snapping.
--
--  The maths: WoW lays the UI out in a 768-unit-tall virtual screen. At
--  UIParent scale s, one UI unit is (physicalHeight / 768) * s physical
--  pixels. So the scale where one unit is exactly one pixel is:
--
--      perfect = 768 / physicalHeight          (1080p 0.711, 1440p 0.533, 2160p 0.356)
--
--  We set UIParent:SetScale(perfect * size) directly (never the uiScale CVar,
--  which Blizzard clamps to 0.64+). "size" is the user's multiplier for a
--  bigger UI. Whatever the scale, one physical pixel in any frame's units is
--
--      onePixel(frame) = perfect / frame:GetEffectiveScale()
--
--  and every size, offset and border is snapped to whole multiples of that,
--  so edges land on real pixels even at 150% size. Frames with an odd pixel
--  width get their centre on a half pixel so both edges stay sharp.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local Pixel = {}
EV.Pixel = Pixel

local floor, max = math.floor, math.max
local physicalHeight = 768
local perfect = 1

local function ReadScreen()
    local _, h = GetPhysicalScreenSize()
    if h and h > 0 then physicalHeight = h end
    perfect = 768 / physicalHeight
end
ReadScreen()

function Pixel:Perfect() return perfect end
function Pixel:PhysicalHeight() return physicalHeight end

--- One physical pixel in this frame's coordinate space (UIParent if nil).
function Pixel:One(frame)
    local es = (frame or UIParent):GetEffectiveScale()
    return perfect / es
end

--- The thickness of a hairline n physical pixels wide (n defaults to 1), in
--- this frame's coordinate space.
---
--- A hair over the exact size, on purpose. An unsnapped texture lights the
--- pixels whose centres it covers, and its far edge is exclusive. `One` is a
--- float (768 over the screen height, over the effective scale), so a
--- "one pixel" strip comes out a few millionths short; when its edge lands on
--- a pixel centre, which it does whenever a frame sits on a half pixel (any
--- odd-width frame centred on the screen: every static pop-up), the strip
--- covers no centre at all and that side of the border is simply not drawn.
--- Half a percent over makes it cover one centre wherever it lands; it would
--- take an edge within a two-hundredth of a pixel of a centre to light two.
local LINE = 1.005
function Pixel:Line(frame, n)
    return self:One(frame) * (n or 1) * LINE
end

--- Round v to the nearest whole physical pixel (min 1px when v > 0).
function Pixel:Snap(frame, v)
    local one = self:One(frame)
    local snapped = one * floor(v / one + 0.5)
    if v > 0 and snapped < one then snapped = one end
    return snapped
end

--- Pixels <-> UIParent units.
function Pixel:ToPixels(v) return floor(v / self:One(UIParent) + 0.5) end
function Pixel:FromPixels(px) return px * self:One(UIParent) end

--- Snap a centre coordinate for a frame of size dim (same units): whole pixel
--- for even pixel sizes, half pixel for odd ones, so both edges are sharp.
function Pixel:SnapCenter(frame, v, dim)
    local one = self:One(frame)
    local dimPx = floor(dim / one + 0.5)
    if dimPx % 2 == 1 then
        return (floor(v / one) + 0.5) * one
    end
    return floor(v / one + 0.5) * one
end

function Pixel:SetSize(frame, w, h)
    frame:SetSize(self:Snap(frame, w), self:Snap(frame, h or w))
end

function Pixel:SetPoint(frame, point, rel, relPoint, x, y)
    frame:SetPoint(point, rel, relPoint, self:Snap(frame, x or 0), self:Snap(frame, y or 0))
end

--------------------------------------------------------------------------------
--  Pixel snapping, turned off on our own regions
--
--  Snapping is a property of each texture OBJECT and it defaults ON. It rounds
--  that region's coordinates to the pixel grid INDEPENDENTLY of every other
--  region. For anything that sits still that is free and occasionally helpful.
--  For anything at a fractional, moving position it is the bug: each region
--  crosses its own rounding boundary at its own moment, so the bar steps left,
--  the text has not yet, the border already has. Nameplates are the worst case
--  because their position comes from the 3D projection and is fractional on
--  every single frame, but it is the same defect anywhere a frame moves.
--
--  Snapping every region off means the whole thing moves as ONE unit, very
--  slightly soft, instead of shimmering against itself. That is the trade and
--  it is the right way round: coherent and a touch blurry beats crisp and
--  crawling.
--
--  Doing it per call site does not work, and we proved that the expensive way
--  in the nameplates module. There were six NoSnap calls on a plate carrying
--  thirty regions, and the two that mattered most were the two that were
--  missed: font strings, and the StatusBar FILL, which is a brand new texture
--  object after every SetStatusBarTexture.
--
--  It used to be hooked once, at the widget metatables (SetTexture,
--  SetColorTexture, SetAtlas, SetStatusBarTexture, SetSnapToPixelGrid), so
--  every region in the game was unsnapped on first touch. That cannot be done
--  on Forever. The metatables are shared with Blizzard's secure code, and
--  under the secret-value rules a hooked method counts as ours when that code
--  calls it with secrets in play: the taint log showed "An attempt to call a
--  secret value was blocked because of taint from EvermoreUI -
--  SetStatusBarTexture()" from the cast bar on every cast, and with that hook
--  gone the XP bar's next line, SetAtlas, was blocked the same way.
--
--  So snapping is taken off OUR regions, by us:
--
--   * Pixel.NoSnap(region), for a texture, mask or font string, or a
--     StatusBar's current fill.
--   * Pixel:Bar(bar), once after CreateFrame("StatusBar"): SetStatusBarTexture
--     mints a new fill texture every call, so each of our bars is hooked on
--     its own to unsnap the new one. Our frame, never Blizzard's.
--   * Anything that moves walks its own regions: the nameplates' layout pass
--     (Nameplates/Core.lua, SnapOff) does every region on every plate.
--
--  Blizzard's own regions keep the client's default snapping, which is what
--  it was built for.
--
--  Never a field written onto a widget: the cache is an external weak-keyed
--  table, because a stray key on a Blizzard frame taints it.
--------------------------------------------------------------------------------
local snapOff = true
local done = setmetatable({}, { __mode = "k" })

-- Regions that have deliberately been put back ON the grid (nameplates in
-- crisp mode), so NoSnap leaves them alone.
local keep = setmetatable({}, { __mode = "k" })

--- Mark a region as intentionally snapped (true) or hand it back to the
--- suite wide default (false). Marking one snapped also forgets that it was
--- unsnapped, so handing it back later unsnaps it again rather than stopping
--- at the cache (crisp mode switched back to smooth).
function Pixel.KeepSnap(r, on)
    if r == nil then return end
    keep[r] = on and true or nil
    if on then done[r] = nil end
end

local function Usable(obj)
    if obj == nil then return false end
    if issecretvalue and issecretvalue(obj) then return false end
    if issecrettable and issecrettable(obj) then return false end
    if type(obj) ~= "table" then return false end
    local ok, forbidden = pcall(obj.IsForbidden, obj)
    if ok and forbidden then return false end
    return true
end

local function UnsnapRegion(r)
    if not r.SetSnapToPixelGrid then return end
    pcall(r.SetSnapToPixelGrid, r, false)
    pcall(r.SetTexelSnappingBias, r, 0)
    done[r] = true
end

--- Textures, mask textures and font strings carry the setter themselves; a
--- StatusBar is a frame and carries it on the fill it owns.
---
--- Order matters here: nameplates call this for every region on every layout.
--- The secret guards are one C call each and have to come first, since a
--- secret is not safe to use as a table key. The cache lookup comes next and
--- is where the hot path ends: a texture that has already been unsnapped never
--- reaches the pcall below it. A StatusBar is the exception and is meant to
--- be -- the cache is keyed on the FILL, so a bar handed a new fill texture
--- unsnaps it rather than being skipped as already done.
local function NoSnap(obj)
    if not snapOff or obj == nil then return end
    if issecretvalue and issecretvalue(obj) then return end
    if issecrettable and issecrettable(obj) then return end
    if done[obj] or keep[obj] then return end
    if not Usable(obj) then return end
    if obj.SetSnapToPixelGrid then
        UnsnapRegion(obj)
        return
    end
    if obj.GetStatusBarTexture then
        local ok, t = pcall(obj.GetStatusBarTexture, obj)
        if ok and t ~= nil and not done[t] and not keep[t] and Usable(t) then UnsnapRegion(t) end
    end
end
Pixel.NoSnap = NoSnap

--- Our own status bars, one at a time: SetStatusBarTexture mints a new fill
--- texture on every call, so each bar of ours is hooked on its own to unsnap
--- the new one. Call once, right after CreateFrame("StatusBar"). Never on a
--- bar of Blizzard's (see the header: the metatable version of this was what
--- tainted the cast bar).
local barred = setmetatable({}, { __mode = "k" })
function Pixel:Bar(bar)
    if bar == nil or barred[bar] then return bar end
    barred[bar] = true
    hooksecurefunc(bar, "SetStatusBarTexture", NoSnap)
    NoSnap(bar)
    return bar
end

--------------------------------------------------------------------------------
--  Hairlines and fills
--
--  The one implementation of "four one-physical-pixel textures in a colour"
--  and "a flat texture behind everything", for our own frames and Blizzard's
--  alike. Both live in weak tables keyed by the object, so nothing is ever
--  written onto the object itself: a field on one of Blizzard's frames can
--  taint it, and the skins paint Blizzard's frames with these same calls.
--
--    Pixel:Edges(obj, opts)      create or return; opts: size (px), decouple,
--                                layer, sub. Returns the edge list and the
--                                border record { edges, size, host }.
--    Pixel:EdgesOf(obj)          the record, or nil
--    Pixel:SetEdgeColor(obj, r, g, b, a)
--    Pixel:ShowEdges(obj, shown)
--    Pixel:Fill(obj, layer, sub) create or return the fill texture
--    Pixel:FillOf(obj)           the fill texture, or nil
--    Pixel:ResnapAll()           every hairline, after a scale change
--------------------------------------------------------------------------------
local borders = setmetatable({}, { __mode = "k" })  -- object -> border record
local fills = setmetatable({}, { __mode = "k" })    -- object -> fill texture

--- Snap against the frame the strips actually LIVE on, which is not always
--- the frame the border belongs to. See the decoupled case below.
local function Snap4(obj, border)
    local px = Pixel:Line(border.host or obj, border.size or 1)
    local e = border.edges
    e[1]:SetHeight(px); e[2]:SetHeight(px); e[3]:SetWidth(px); e[4]:SetWidth(px)
end

--- A one-pixel border.
---
--- `decouple` is for a frame whose scale MOVES: a nameplate, which we scale up
--- when it is your target and back down when it is not, and which Blizzard
--- also rescales and recycles underneath us.
---
--- Without it the strip thickness bakes in at whatever the scale was when it
--- was snapped. Scale the frame afterwards and a "one pixel" strip becomes
--- 1.2 pixels, or 0.8; at 0.8 it covers no pixel centre at many sub-pixel
--- positions and the side simply is not drawn. The plate slides with the
--- camera, the positions change every frame, and individual SIDES of the
--- border blink in and out. Turning pixel snapping off does not fix it --
--- that stops a strip rounding to zero, it does not make the geometry exact.
---
--- The fix is to take the strips out of the frame's coordinate space
--- altogether. They go on a container with SetIgnoreParentScale(true) and
--- SetScale(1), so its effective scale is pinned at 1 forever while its
--- anchors still track the frame's live rect. The thickness is then exactly
--- one physical pixel however the frame is scaled afterwards, because nothing
--- about the frame's scale reaches the strips any more.
---
--- The symptom this cures is distinctive: border sides vanish and reappear
--- as a plate slides with the camera.
---
--- The container also sits a frame level ABOVE its frame, which matters for a
--- StatusBar: a bar's fill texture draws on the ARTWORK layer, above the
--- BORDER layer, so a border drawn on the bar itself is underneath its own
--- fill.
function Pixel:Edges(obj, opts)
    opts = opts or {}
    local border = borders[obj]
    if not border then
        local host = obj
        local decouple = opts.decouple
        if decouple then
            local c = CreateFrame("Frame", nil, obj)
            c.ignoreInLayout = true
            c:SetAllPoints(obj)
            c:SetFrameLevel((obj:GetFrameLevel() or 0) + 1)
            if c.SetIgnoreParentScale then
                c:SetIgnoreParentScale(true)
                c:SetScale(1)
            end
            host = c
        end
        border = { edges = {}, host = (host ~= obj) and host or nil }
        for i = 1, 4 do
            local t = host:CreateTexture(nil, opts.layer or (decouple and "OVERLAY" or "BORDER"), nil, opts.sub or 7)
            -- Snapping stays OFF, deliberately. Its job here is to stop a
            -- one-pixel strip rounding to zero width; with the container
            -- decoupled the geometry is already exact.
            NoSnap(t)
            -- Ours, and not content: a LayoutFrame measures every region it
            -- has (LayoutFrame.lua, GetLayoutChildren) unless told not to.
            t.ignoreInLayout = true
            border.edges[i] = t
        end
        local e = border.edges
        e[1]:SetPoint("TOPLEFT");    e[1]:SetPoint("TOPRIGHT")
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
        e[3]:SetPoint("TOPLEFT");    e[3]:SetPoint("BOTTOMLEFT")
        e[4]:SetPoint("TOPRIGHT");   e[4]:SetPoint("BOTTOMRIGHT")
        borders[obj] = border
    end
    if opts.size then border.size = opts.size end
    Snap4(obj, border)
    return border.edges, border
end

function Pixel:EdgesOf(obj) return borders[obj] end

function Pixel:SetEdgeColor(obj, r, g, b, a)
    local border = borders[obj]
    if not border then return end
    for _, e in ipairs(border.edges) do e:SetColorTexture(r or 0, g or 0, b or 0, a or 1) end
end

function Pixel:ShowEdges(obj, shown)
    local border = borders[obj]
    if not border then return end
    for _, e in ipairs(border.edges) do e:SetShown(shown and true or false) end
end

--- A border `size` physical pixels thick in one colour: Edges plus a colour.
function Pixel:CreateBorder(frame, size, r, g, b, a, decouple)
    local _, border = self:Edges(frame, { size = size or 1, decouple = decouple })
    self:SetEdgeColor(frame, r, g, b, a)
    return border
end

function Pixel:ResnapAll()
    for obj, border in pairs(borders) do Snap4(obj, border) end
end
Pixel.ResnapBorders = Pixel.ResnapAll

--- The flat texture behind an object's own drawing, created once.
function Pixel:Fill(obj, layer, sub)
    local t = fills[obj]
    if not t then
        t = obj:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -7)
        t.ignoreInLayout = true
        t:SetAllPoints(obj)
        NoSnap(t)
        fills[obj] = t
    end
    return t
end

function Pixel:FillOf(obj) return fills[obj] end

function Pixel:CreateBackdrop(frame, r, g, b, a)
    local bg = self:Fill(frame, "BACKGROUND", -8)
    bg:SetColorTexture(r or 0.05, g or 0.05, b or 0.06, a or 0.85)
    return bg
end

--------------------------------------------------------------------------------
--  UI scale management
--------------------------------------------------------------------------------
local SCALE_DEFAULTS = { managed = true, size = 1.0 }
local pendingScale = false

local function ScaleSettings()
    local core = EV.DB and EV.DB.GetCore and EV.dbReady and EV.DB:GetCore()
    if not core then return SCALE_DEFAULTS end
    core.scale = core.scale or {}
    EV.DB.Merge(core.scale, SCALE_DEFAULTS)
    return core.scale
end
Pixel.ScaleSettings = ScaleSettings

--- The UIParent scale we want (nil when the user lets Blizzard manage it).
function Pixel:TargetScale()
    local s = ScaleSettings()
    if not s.managed then return nil end
    return perfect * (s.size or 1)
end

local function Changed()
    Pixel:ResnapAll()
    if EV.Movers and EV.dbReady then EV.Movers:ApplyAll() end
    EV:SendMessage("EV_PIXEL_CHANGED")
end

function Pixel:ApplyScale()
    ReadScreen()
    -- Read here rather than at file scope: Pixel loads before the DB is ready.
    -- Turning snapping back ON only stops us unsnapping anything NEW; the
    -- regions already done stay done until a reload, and the options page says
    -- so rather than pretending otherwise.
    local core = EV.DB and EV.DB.GetCore and EV.dbReady and EV.DB:GetCore()
    if core and core.pixelSnapping ~= nil then snapOff = not core.pixelSnapping end
    local target = self:TargetScale()
    if target then
        if InCombatLockdown() then pendingScale = true; return end
        if math.abs(UIParent:GetScale() - target) > 0.0001 then
            UIParent:SetScale(target)
        end
    end
    Changed()
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, arg1)
    -- Our own ADDON_LOADED: the DB is ready (Framework's handler ran first),
    -- so frames built from here on see the right scale.
    if event == "ADDON_LOADED" then
        if arg1 == EV.name then Pixel:ApplyScale() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingScale then pendingScale = false; Pixel:ApplyScale() end
        return
    end
    -- Blizzard re-applies its own scale on some of these; put ours back.
    Pixel:ApplyScale()
end)
