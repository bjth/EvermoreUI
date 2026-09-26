if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Core.lua
--  Plate lifecycle: our frame on Blizzard's plate, and Blizzard's own plate
--  stood down.
--
--  Four constraints shape this file, all checked against Blizzard's source.
--  Read them before changing anything here:
--
--   1. The UnitFrame is POOLED AND TRANSIENT. NAME_PLATE_UNIT_ADDED calls
--      AcquireUnitFrame, NAME_PLATE_UNIT_REMOVED calls ReleaseUnitFrame and
--      sets plate.UnitFrame = nil. Cache it and you are holding a frame that
--      will belong to a different unit later. Hook the MIXIN, never an
--      instance.
--   2. Nameplates are not mouse-interactive. EnableMouse(false) is explicit
--      and hit testing is done in C++ from the plate's hit-test points. We
--      never touch those, so targeting stays exactly Blizzard's.
--   3. C_NamePlate is four functions here. No size-per-faction, no
--      click-through, no preferred alpha. Do not reach for retail's API.
--   4. Reading auras in Lua throws while tainted in restricted content, so
--      aura work lives in Auras.lua on engine containers, not here.
--
--  Everything is event driven. The only OnUpdate scripts in this addon are
--  the health flush (self-hiding, see Health.lua) and the cast bar fill
--  (installed on cast start, removed on cast stop, see Cast.lua).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L

local M = EV:NewModule("Nameplates", {
    enabled        = true,

    -- Geometry. The plate frame IS the health bar's box: the cast bar hangs
    -- below it and the auras sit above it, both OUTSIDE it.
    --
    -- Ours is a little wider than most because Camelot's own plate is 190.
    --  Proportions are measured off the reference screenshots. In the
    --  reference the health bar
    --  is 44px tall on a 337px bar, so the ratio is 7.7:1, not 11.7:1. It is
    --  a chunky bar.
    --
    --  The cast bar is exactly half the health bar's height and sits directly
    --  underneath it sharing a border, with no gap at all: the reference has
    --  three pixels of black between the two fills, which is just the two
    --  borders touching.
    --
    --  The design is drawn at an overall scale of 1.6, so every size in it is
    --  1.6x bigger than it first reads. Miss that and the plate looks thin.
    --
    --  Base plate, derived from the design's own anchors: the health text
    --  sits at x 60 and the name at -58.5, so the bar is 123 wide; the cast
    --  bar is anchored TOP,0,-7.5, so the health bar's half height is 7.5 and
    --  its height is 15. Then:
    --      123 x 1.6                    = 196.8 -> 196 wide
    --      15 x 1.6 x border height 1.1 = 26 tall
    --      15 x 1.6 x border height 0.6 = 14 cast
    --
    --  196 and not 197, and the rounding direction is the point. The plate is
    --  anchored by its CENTRE to Blizzard's, so an ODD pixel width puts its
    --  left and right edges on half pixels while its centre is whole. Regions
    --  anchored to an edge then round in a different direction from regions
    --  anchored to the middle, and they cross their rounding boundaries at
    --  different moments as the mob walks. Our own Pixel.lua has said this
    --  since the day it was written -- see SnapCenter, "whole pixel for even
    --  pixel sizes, half pixel for odd ones" -- and the plate was the one
    --  place we never applied it. Every size here is even for that reason.
    width          = 196,
    height         = 26,        -- the health bar itself
    castHeight     = 14,
    borderSize     = 2,         -- the reference measures a 2px black edge
    innerShadow    = true,      -- and a dark ramp under it, which is what
                                -- makes the bar read as inset
    castGap        = 0,         -- attached, sharing a border
    texture        = "Flat",    -- a solid white fill; the colour rules own the hue
    -- Name and health text are scale 0.88 in the design, which against the
    -- 1.6 global works out at 1.41x a base font.
    fontSize       = 16,
    -- outline, shadow, or both. Measured off the reference: dark pixels sit
    -- on every side of a glyph but 37% more of them below than above, so it
    -- carries an outline AND a downward shadow.
    -- Blizzard's nameplate fonts use one or the other, never both, which is
    -- why this is a choice rather than a constant.
    textStyle      = "both",

    -- What to show
    showName       = true,
    -- On. This is a Classic-shaped game: the level is the difficulty, and a
    -- red 32 next to a name is information you act on.
    showLevel      = true,
    showQuest      = true,
    healthText     = "percent", -- percentage, right aligned
    -- Text slots on the bar: three fixed positions, each holding one
    -- element. "levelname" is the level with the name after it,
    -- which is how the left slot has always looked. showName and showLevel
    -- above are superseded by these: an element is shown when a slot has it.
    textLeft       = "levelname",
    textCentre     = "none",
    textRight      = "health",
    showCast       = true,
    -- The mob's own resource, as a thin strip under the health bar. On,
    -- because this is the honest form of the caster test: the bar is there
    -- exactly when the mana is, and it also says how much is left. "mana"
    -- shows it only for units with mana, which is the caster test; "any"
    -- shows whatever resource the unit displays, rage and energy included.
    showPower      = true,
    powerMode      = "mana",
    powerHeight    = 8,         -- 6 of mana inside a one pixel hairline
    powerGap       = 0,         -- attached, sharing a border, like the cast bar
    showCastText   = true,      -- spell name below left, time below right
    showCastTarget = true,      -- on the cast bar, right, class coloured
    showAuras      = true,
    showCC         = true,
    showBuffs      = false,
    -- A base icon of 20, debuffs at scale 0.9 and height 0.75, so
    -- 20 x 0.9 x 1.6 = 29 wide and 22 tall. They ARE letterboxed, even
    -- though a quick screenshot measurement suggests square.
    auraSize       = 29,
    -- Square. A "height 0.75" is a per-row multiplier against a square icon
    -- and the reference rows are all height 1 -- the debuff icons
    -- measure 37x40 on a 44px bar, so they are square and very nearly as tall
    -- as the bar. Do not letterbox them.
    auraRatio      = 0.75,

    -- Colour
    healthColour   = "reaction",
    -- How bright the bar fill is. White text on FULL red measures 4.00:1,
    -- under the 4.5:1 WCAG floor for body text; at 0.75 it is 6.53:1 and at
    -- 0.65 it is 8.08:1. This is the single biggest readability lever on the
    -- plate, bigger than the typeface or the size.
    barShade       = 0.75,
    -- Caster or melee, inferred from whether the mob has mana. Off: it is a
    -- retail habit, and on a Classic-shaped game it spends the bar's colour
    -- on something you can already tell by looking at the mob. The rule is
    -- still there if you want it.
    typeColour     = false,
    typeInInstancesOnly = false,
    threatColour   = true,
    tankMode       = "auto",
    -- Off. The solo case is already handled -- Colours.lua skips threat
    -- entirely when you are not in a group, because solo everything is on you
    -- and the colour says nothing -- so gating on instances as well would
    -- only cost you threat colouring in world group content, which is exactly
    -- where an unexpected pull hurts.
    threatInInstancesOnly = true,
    threatInCombatOnly    = true,
    -- Off means the SAFE state does not recolour
    -- at all and the bar keeps its hostility colour, so threat only ever
    -- speaks up when something is wrong. This is what makes it subtle.
    threatSafeColour      = false,
    -- A red panel behind the plate when the mob is on you. Driven by a
    -- secret boolean folded into alpha C-side, so it works in restricted
    -- content where threat numbers cannot be read at all.
    aggroBackdrop  = true,
    aggroPad       = 8,         -- how far the glow reaches past the plate
    aggroAlpha     = 0.35,      -- at the plate edge, fading to nothing
    executeGlow    = false,
    executeAt      = 0.35,

    -- Target and focus
    -- The target is the plate that grew and went white round the edge. It
    -- does not also need the bar colour: see the "target" rule in Colours.lua.
    targetColour   = false,
    targetBorder   = true,
    -- The target is marked by a light HALO outside the plate, the same
    -- eight piece glow as the aggro one, rather than by turning the border
    -- white. A white border is drawn INSIDE the bar's box, so on the target
    -- it read as the bar being inset. With the halo on, the target's border
    -- stays black like every other plate's; focus keeps its cyan border.
    targetHalo      = true,
    targetHaloAlpha = 0.55,
    -- Pin Blizzard's plate scaling to 1. This is half the fix for the jitter,
    -- and the long note is at PinPlateScale below.
    pinPlateScale  = true,
    -- How the plate behaves as the mob walks, and the two answers are
    -- opposites rather than a dial.
    --
    --   "smooth" -- nothing is quantised. Slug renders glyphs as outlines at
    --     exact sub pixel positions and unsnapped textures draw at exact sub
    --     pixel positions, so the whole plate translates with the mob and
    --     nothing on it moves relative to anything else. Very slightly soft.
    --
    --   "crisp" -- Blizzard's combination. Layout rounds to whole pixels and
    --     textures snap to the grid, so edges are exact and the entire plate
    --     steps one pixel at a time as the mob moves.
    --
    -- The one thing you must not do is mix them: slug text and unsnapped
    -- textures wanting to glide, with layout rounding quantising the frames
    -- they sit in, makes everything jump.
    --
    -- This setting governs the plate's CONTENT: whether the regions on it
    -- quantise together or each draw at its own exact sub pixel position.
    -- Where the PLATE itself sits is a different problem, solved on the
    -- engine side: the size fight with NamePlateDriverFrame, the scale CVars,
    -- baseOffset and target scaling. None of those touch this.
    --
    -- "smooth": no layout rounding anywhere. Sizes and offsets are quantised
    -- once, at layout time, through PixelUtil, and recomputed only when the
    -- effective scale changes. Nothing quantises
    -- POSITION, because position belongs to the engine.
    --
    -- "crisp" is Blizzard's own: round the layout and snap the
    -- textures. Edges are exact and the whole plate steps a pixel at a time.
    --
    -- The default is CRISP. In smooth the bar's textures glide at sub pixel
    -- positions but the renderer still places glyphs on whole pixels, so the
    -- text steps while the bar under it slides, and reads as the text
    -- bouncing inside the bar. Crisp puts everything on the grid so it all
    -- steps together, which is Blizzard's own model.
    --
    -- Crisp only breaks if a frame in the chain has a rounded centre that
    -- moves with the plate. The engine hands the plate box back at 63.75 UI
    -- units, a fractional number of physical pixels, so a host frame rounded
    -- to that box flips height and its centre moves half a pixel. Nothing
    -- here is sized to that box, and the root is sized in Layout to an even
    -- number of physical pixels. The suite-wide unsnap hook in Pixel.lua is
    -- countered per region in crisp mode (Pixel.KeepSnap).
    pixelMode      = "crisp",
    -- Off. On, the game pins a plate to the edge of the screen when its mob
    -- walks out of view, so the plate stops tracking the mob and starts
    -- tracking the window. CVar nameplateShowOffscreen.
    offscreenPlates = false,
    -- ON, and this is the answer to why plates in other suites held still
    -- over their mobs and ours did not: they ship with stacking on.
    --
    -- Stacking does slide plates around each other, which is movement
    -- unrelated to the mob, but the stacking system is also the ENGINE'S MOTION SYSTEM: with it on, plate
    -- positions are interpolated rather than taken raw from the projection
    -- every frame. That interpolation is the smoothing, it is the thing a
    -- Lua deadzone was trying and failing to reimplement, and it only exists
    -- on the C side because that is the only place plate positions can be
    -- read at all. Turning stacking off takes it with it.
    --
    -- Friendly stacking stays off.
    stackPlates     = true,
    -- How hard the engine smooths a plate's movement, 0 to 1, lower is
    -- smoother. This is the only smoothing available to anyone: it runs where
    -- the plate positions actually are, which is the C side, and it is why a
    -- deadzone in Lua is impossible. 0.025 is the common choice.
    --
    -- It rides the stacking system, so it does nothing while stackPlates is
    -- off. That is the trade: stacking slides plates around each other, and
    -- it is also what stops them snapping about as the mob walks.
    plateMotionSpeed = 0.025,
    -- One knob for the lot. The design's own 1.6 overall scale is already
    -- baked into our defaults, so this is the tuning on top of it.
    scale          = 1,
    -- Nudge the whole plate up or down over the mob. Negative moves it down.
    -- A fine tune, and it should be zero. The engine now knows how tall our
    -- plate is (ns.UpdatePlateSize) and positions it accordingly, so the -25
    -- this used to carry was us compensating for a disagreement that no longer
    -- exists.
    verticalOffset = 0,
    -- The same, for friendly plates, which are a different problem: those are
    -- Blizzard's and their name sits a whole hidden bar stack above the unit.
    -- See NudgeFriendly.
    friendlyVerticalOffset = -25,   -- measured in game, not guessed
    -- 1, meaning off. No plate changes scale, ever, which
    -- removes the last thing that made one plate behave differently from
    -- another. Turn it up once the base case is proven quiet.
    targetScale    = 1,
    nonTargetAlpha = 1,         -- no fade at all on plates you are not targeting
    -- Off. The reference does not underline the target at all: the bar turning
    -- light blue plus the scale bump IS the target indicator. An underline
    -- reads as a mana bar.
    showTargetGlow = false,

    -- Sub pixel nudge for the text on the bar, in PHYSICAL pixels, -0.5 to
    -- 0.5. Measured off screenshots: bar and text are both
    -- snapped to whole pixels (font strings have no SetSnapToPixelGrid on
    -- this client at all, and layout rounding is on everywhere), yet the text
    -- flips between two heights exactly one pixel apart as the plate moves.
    -- That is the glyphs' own offset inside the font string -- (box height -
    -- line height) / 2 plus the ascent -- carrying a fraction the bar does
    -- not, so the two cross their rounding boundaries at different moments.
    -- Cancelling that fraction is the only lever: position is the engine's
    -- and cannot be read. Found by eye with /evui nptext.
    textPhase      = 0,

    -- Friendly plates: the reference uses a name-only design for these, so ours
    -- stay out of the way and Blizzard's are left alone.
    doFriendly     = false,
})
ns.module = M
M.title = "Nameplates"
M.description = "Our own nameplates: health, cast, your dots with their timers, threat colouring and target highlighting."

--------------------------------------------------------------------------------
--  Shared state
--------------------------------------------------------------------------------
ns.plates = {}                                  -- unitToken -> our frame
ns.active = {}                                  -- our frame -> true
ns.styleGen = 1                                 -- bumped on a settings pass

-- Blizzard frames are protected-adjacent and a stray field write can taint
-- one, so anything we need to remember about THEIR frames lives out here.
ns.blizState = setmetatable({}, { __mode = "k" })

local alphaHooked = setmetatable({}, { __mode = "k" })

--- "Is this unit that one", answered in a way that cannot throw.
---
--- UnitIsUnit is SecretWhenUnitComparisonRestricted (UnitDocumentation.lua
--- :2410), so in restricted content the answer is a secret boolean. Returns
--- the plain answer plus a flag; when the flag is set the caller must NOT
--- test the value -- only fold it through a *FromBoolean setter, or stop
--- trying to find one plate and act on all of them.
function ns.IsUnit(unit, other)
    local ok, v = pcall(UnitIsUnit, unit, other)
    if not ok then return false, false end
    if ns.IsSecret(v) then return nil, true end
    return v == true, false
end

--------------------------------------------------------------------------------
--  Text
--
--  Every string on a plate goes through here rather than through SetFont, so
--  that it gets SLUG rendering. See Fonts.xml for why that matters and why it
--  cannot be done from Lua: slug is an XML-only <Font> attribute, and a
--  FontString built with SetFont is not slug whatever path you hand it.
--
--  SetFontHeight after SetFontObject, NOT SetTextHeight. This was the text
--  bounce, and the API documentation says it outright: SetFontHeight is the
--  only one of the two carrying "Preserves all flags, does correct height
--  conversion due to fixedHeight" (SimpleFontAPIDocumentation.lua:216).
--  SetTextHeight carries no such note because it does not: it re-specifies
--  the font, and a font re-specified from Lua is not slug whatever path you
--  hand it, which is the rule stated four lines above. So every string on the
--  plate picked up its slug object and lost slug again on the very next line,
--  the moment we set its size.
--
--  Non-slug text is rasterised with hinting and each glyph snaps to the pixel
--  grid on its own, so as the plate slides the letters redistribute inside the
--  word. That is the bounce, and it is why it survived pinning the plate
--  scale, rounding the layout and unsnapping every texture: not one of those
--  touches how a glyph is rasterised.
--
--  Blizzard use SetFontHeight on their own nameplate name for this reason
--  (Blizzard_NamePlateUnitFrame.lua:776), and their own docs note that
--  non-slug fonts "may cause significant pixelation of the font text"
--  (UISharedDocumentation.lua:14).
--
--  A face we have no slug object for -- anything the user picks out of
--  LibSharedMedia -- falls back to SetFont and loses slug. That is a real
--  downgrade and it is better stated than hidden: the options page says so.
--
--  The font objects and the styling itself now live in the core
--  (Core/FontObjects.xml, EV.Fonts:StyleText) so unit frames share them.
local SLUG = EV.Fonts.SLUG

--- True when the current font choice renders through slug.
function ns.HasSlug()
    return EV.Fonts:HasSlug()
end

--- Which slot each text element is in, resolved once per layout.
---
--- Each element appears at most once. If two slots ask for the same one, the
--- first in reading order (left, centre, right) keeps it and the later slot
--- is treated as empty, so a plate can never draw the name twice. "levelname"
--- claims both level and name.
local SLOT_ORDER = { "left", "centre", "right" }
local SLOT_KEY = { left = "textLeft", centre = "textCentre", right = "textRight" }
local CLAIMS = {
    name = { "name" }, level = { "level" }, health = { "health" },
    levelname = { "level", "name" },
}
function ns.TextSlots(cfg)
    local slots, owner = {}, {}
    for _, side in ipairs(SLOT_ORDER) do
        local want = cfg[SLOT_KEY[side]] or "none"
        -- The centre is one element: a level-and-name pair has no fixed
        -- width to centre on, and measuring the name is not reliable inside
        -- a nameplate. Offered as name there instead.
        if side == "centre" and want == "levelname" then want = "name" end
        local claims = CLAIMS[want]
        local free = claims ~= nil
        if claims then for _, e in ipairs(claims) do if owner[e] then free = false end end end
        if free then
            slots[side] = want
            for _, e in ipairs(claims) do owner[e] = side end
        else
            slots[side] = "none"
        end
    end
    return slots, owner
end

--- The configured text nudge, in UI units for this plate.
function ns.TextPhase(f)
    local p = ns.module and ns.module.db and ns.module.db.textPhase or 0
    if p == 0 then return 0 end
    return p * EV.Pixel:One(f)
end

--- Style a font string at a size, keeping slug wherever we can.
function ns.SetText(fs, size, outline)
    if not fs then return end
    -- The caller passes whether the element WANTS an outline; the user's
    -- textStyle decides what that actually means.
    local style = ns.module and ns.module.db and ns.module.db.textStyle or "both"
    -- `outline` from the caller means "this element would like an edge"; the
    -- user's textStyle decides what kind. There is no separate outline
    -- toggle any more, because two controls for one thing is how you end up
    -- with a tickbox that appears to do nothing.
    -- Shared with unit frames: see EV.Fonts:StyleText in Core/Fonts.lua for
    -- the slug, SetFontHeight and outline-versus-shadow rules that used to be
    -- written out here.
    local _, kept = EV.Fonts:StyleText(fs, size, style, outline)
    if not kept then ns.slugKept = false end

    -- No explicit height: the string sizes itself to its own line height,
    -- which is what Blizzard's steady name does. Text is held steady by
    -- anchoring it by an edge instead (ns.AnchorInBar).
    if fs.SetHeight then pcall(fs.SetHeight, fs, 0) end
end

--- Put a string INSIDE a bar the way Blizzard puts its name ABOVE one.
---
--- Side by side, Blizzard's plate jiggles as a whole, but
--- its name does not move against its bar; ours does. The difference is the
--- anchor. Blizzard's name hangs by its BOTTOM EDGE off the bar's top edge,
--- self-sized (Blizzard_NamePlateUnitFrame.lua:767, forever branch). Ours
--- hung by its vertical CENTRE, so the glyphs sat half a line height from
--- the anchor, a fraction of a pixel the bar does not carry, and the two
--- rounded apart. Their one centre-anchored string, the health text on the
--- classic bar, gets a hand nudge of -0.5 for this (:754).
---
--- So: bottom edge on the bar's bottom edge, lifted a WHOLE number of pixels
--- to centre it by eye. Every offset from the bar is integral, so text and
--- bar share the plate's pixel phase and cross boundaries together.
function ns.AnchorInBar(fs, f, side, x)
    local cfg = M.db
    local one = EV.Pixel:One(f)
    local barPx = math.floor(cfg.height / one + 0.5)
    if barPx % 2 == 1 then barPx = barPx - 1 end
    local okL, lh = pcall(fs.GetLineHeight, fs)
    local linePx = (okL and type(lh) == "number" and lh > 0) and (lh / one) or (cfg.fontSize * 1.2 / one)
    local lift = math.floor((barPx - linePx) / 2 + 0.5)
    if lift < 0 then lift = 0 end
    local y = lift * one + (ns.TextPhase and ns.TextPhase(f) or 0)
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOM" .. side, f.health, "BOTTOM" .. side, x, y)
    if fs.SetJustifyV then fs:SetJustifyV("BOTTOM") end
end

-- Offscreen holder for Blizzard's plate parts. Declared here and nowhere else:
-- it was briefly an implicit GLOBAL called "hidden", which is a name half the
-- addons on the planet could be using.
local hidden

--------------------------------------------------------------------------------
--  Following Blizzard's scale
--
--  This is the piece we were missing, and both reference addons have it.
--
--  Every pixel measurement in this module is taken against the frame's
--  effective scale at the moment we lay it out. Blizzard then rescales the
--  base plate underneath us -- for the nameplate size setting, for the
--  spawn and despawn animations, for the target -- and from that moment our
--  "one pixel" is not one pixel any more. Nothing tells us. The plate simply
--  starts to shimmer.
--
--  So we watch the plate's OnSizeChanged and re-run our own Layout there,
--  which re-derives every size and anchor at the new scale.
--
--  Two details, both earned:
--
--   * DEFER. OnSizeChanged fires repeatedly while a plate eases in or out, so
--     relayouting on the event itself is a relayout per frame per plate for
--     the whole animation. We mark and drain on the next frame, which is the
--     same coalescer the health bar uses.
--   * SKIP THE COLLAPSE. A plate being removed is scaled towards zero, and
--     snapping against that rect is pure churn. Below about 0.4 scale the
--     plate is treated as leaving. It also never comes back, because the plate is released straight after.
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--  Native pixel rounding
--
--  This is how Blizzard makes a nameplate pixel stable, and it is one call.
--
--      PixelUtil.SetRoundLayoutToNearestPixelRecursively(self, true)
--
--  They do it to the nameplate unit frame (Blizzard_NamePlateUnitFrame.lua:88),
--  to the nameplate casting bar (Blizzard_NamePlateCastingBar.lua:11) and to
--  the class nameplate bars. Frame:SetRoundLayoutToNearestPixel is a native
--  method: the engine rounds the frame's laid-out rect to whole pixels in C,
--  every frame, wherever the plate happens to be.
--
--  That is the piece none of our snapping could ever supply. We round SIZES at
--  layout time, once. A nameplate's POSITION comes from the 3D projection and
--  is fractional on every frame, so a child anchored inside it lands between
--  pixels and its glyphs round independently of the bar underneath them. Hence
--  contents that crawl around inside the health bar as the mob moves.
--
--  WRONG, and left here because the correction matters more than the claim:
--  this used to say a font string "cannot be unsnapped" because
--  SetSnapToPixelGrid is documented on SimpleTextureBase and nowhere else.
--  That is a fact about the documentation, not about the method. See SnapOff
--  below: the method is there on font strings and it works.
--
--  PixelUtil's own SetSize and SetPoint now carry "DEPRECATED: Use
--  SetRoundLayoutToNearestPixel instead for native code to automatically apply
--  the same adjustment", which is Blizzard saying the manual approach we built
--  is the old way.
--
--  It is marked IsProtectedFunction, which is the same flag EnableMouse
--  carries: it applies to protected FRAMES, and every frame we round here is
--  one we created. Guarded anyway, and never recursed into a forbidden child,
--  because the aura holders carry engine-owned containers we have no business
--  touching.
--------------------------------------------------------------------------------
--- Counted, not assumed. SetRoundLayoutToNearestPixel is IsProtectedFunction,
--- and a pcall that quietly returns false looks exactly like one that worked.
--- ns.roundStats is what /evui nppx reports.
ns.roundStats = { ok = 0, missing = 0, failed = 0, refusedBy = {} }

--------------------------------------------------------------------------------
--  Two questions, answered at load instead of guessed at
--
--  Text is still moving, and there are exactly two mechanisms it can be, which
--  need opposite fixes. Rather than reason about which, probe both on a
--  throwaway frame the moment this file loads. Neither probe touches a plate,
--  so the answer is available before the first mob is ever seen.
--
--   1. Can a font string be unsnapped at all? SetSnapToPixelGrid is documented
--      on SimpleTextureBase and nowhere else (SimpleTextureBaseAPIDocumentation
--      .lua:551 is the only hit in the whole generated API), but other addons
--      call it on font strings anyway. The method either exists on the object
--      or it does not.
--
--   2. Will the engine let US round layout? SetRoundLayoutToNearestPixel is
--      IsProtectedFunction (SimpleScriptRegionAPIDocumentation.lua:697-700).
--      It is the mechanism Blizzard use on their own nameplates, with the
--      comment "Prevent flickering caused by nameplate movement, particularly
--      on the borders" (Blizzard_NamePlateUnitFrame.lua:87-88), and if it is
--      refused for addons then the whole pixel approach in this file is the
--      wrong one and the plate has to be reparented to UIParent instead.
--
--  A pcall that returns true is not proof the call DID anything, so this is
--  evidence rather than a verdict. But a pcall that returns false is proof it
--  did not.
--------------------------------------------------------------------------------
ns.probe = {}
do
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(10, 10)
    ns.probe.frameRound = f.SetRoundLayoutToNearestPixel ~= nil
    if ns.probe.frameRound then
        ns.probe.frameRoundOK = pcall(f.SetRoundLayoutToNearestPixel, f, true)
    end

    local t = f:CreateTexture()
    ns.probe.texSnap = t.SetSnapToPixelGrid ~= nil

    local fs = f:CreateFontString(nil, "OVERLAY")
    ns.probe.fontSnap = fs.SetSnapToPixelGrid ~= nil
    if ns.probe.fontSnap then
        ns.probe.fontSnapOK = pcall(fs.SetSnapToPixelGrid, fs, false)
    end
    ns.probe.fontRound = fs.SetRoundLayoutToNearestPixel ~= nil
    if ns.probe.fontRound then
        ns.probe.fontRoundOK = pcall(fs.SetRoundLayoutToNearestPixel, fs, true)
    end
    f:Hide()
end

--- What the probe found, for /evui bug and /evui nppx. Never printed to chat:
--- on Forever font strings have no SetSnapToPixelGrid at all, so a login
--- message would fire for every player, every session, about a known fact.
function ns.ProbeSummary()
    local p = ns.probe
    if type(p) ~= "table" or p.frameRound == nil then return nil end   -- not run yet
    local bad = {}
    if not p.frameRound then bad[#bad + 1] = "frames cannot round layout"
    elseif not p.frameRoundOK then bad[#bad + 1] = "layout rounding REFUSED for addons" end
    if not p.fontSnap then bad[#bad + 1] = "font strings cannot be unsnapped"
    elseif not p.fontSnapOK then bad[#bad + 1] = "font unsnap refused" end
    if not p.fontRound then bad[#bad + 1] = "font strings cannot round layout"
    elseif not p.fontRoundOK then bad[#bad + 1] = "font layout rounding refused" end
    if #bad == 0 then return nil end
    return "Nameplates probe: " .. table.concat(bad, "; ")
end

function ns.ReportProbe()
    if EV.Report and EV.Report.AddLine and not ns.probeInReport then
        ns.probeInReport = true
        EV.Report:AddLine(ns.ProbeSummary)
    end
end
--- Counting a refusal is not enough: 420 of them told us the mechanism is
--- partly blocked and nothing about WHICH parts, which is the difference
--- between "the aura icons do not round, and do not matter" and "the health
--- bar text does not round, which is the whole complaint". So refusals are
--- tallied by object type, and separately by whether the object is one the
--- engine considers protected.
local function RoundRegion(r)
    if not r then return false end
    if not r.SetRoundLayoutToNearestPixel then
        ns.roundStats.missing = ns.roundStats.missing + 1
        return false
    end
    -- Explicitly false rather than skipped in smooth mode: plates are pooled,
    -- so a frame that was rounded under the other setting would stay rounded
    -- for the rest of the session.
    local want = (M.db.pixelMode ~= "smooth")
    -- Experiment switch (/evui nptextround): leave the font strings out of
    -- layout rounding while everything else keeps it.
    if want and M.db.textRound == false then
        local okT, kind = pcall(r.GetObjectType, r)
        if okT and kind == "FontString" then want = false end
    end
    local applied = pcall(r.SetRoundLayoutToNearestPixel, r, want)
    if applied then
        ns.roundStats.ok = ns.roundStats.ok + 1
        return true
    end
    ns.roundStats.failed = ns.roundStats.failed + 1
    local okT, kind = pcall(r.GetObjectType, r)
    kind = (okT and type(kind) == "string") and kind or "?"
    local okP, prot = pcall(r.IsProtected, r)
    if okP and prot then kind = kind .. " (protected)" end
    local by = ns.roundStats.refusedBy
    by[kind] = (by[kind] or 0) + 1
    return false
end

--------------------------------------------------------------------------------
--  Turning pixel snapping OFF, everywhere on the plate
--
--  This is the other half, and it is the half that was missing.
--
--  Pixel snapping is a property of each texture OBJECT and it defaults ON. It
--  rounds that region's texture coordinates to the pixel grid INDEPENDENTLY of
--  every other region. A nameplate's position comes from the 3D projection and
--  is fractional on every single frame, so as the mob walks each region
--  crosses its own rounding boundary at its own moment: the bar steps left, the
--  text has not yet, the border already has. That is content moving inside the
--  plate, and no amount of rounding our own layout fixes it, because the thing
--  doing the rounding is the renderer, once per region, per frame.
--
--  We had NoSnap, and it was called on about six textures out of the thirty on
--  a plate. The two most visible misses:
--
--   * The StatusBar FILL. SetStatusBarTexture mints a brand new texture every
--     time it is called, so unsnapping bar.bg never touched the fill, which is
--     the largest moving thing on the plate. It has to be unsnapped AFTER
--     every SetStatusBarTexture, which is why this runs at the end of the
--     layout pass rather than at build time.
--   * FontStrings. SetSnapToPixelGrid is only documented on
--     SimpleTextureBase, but that is a fact about the DOCUMENTATION. The
--     load-time probe below shows font strings have it, and unsnapped text
--     stops crawling. The call is guarded on the method existing either way, so it costs
--     nothing if that client ever drops it.
--
--  The suite-wide version, hooking the widget metatables so every image
--  setter in the game disables snapping on first touch, is a decision for the
--  parent addon, not for this module. This one is scoped: every region on OUR
--  plates, on every layout.
--------------------------------------------------------------------------------
--- One implementation, in Pixel.lua, which also hooks the widget metatables so
--- every texture in the game is covered whether or not this walk reaches it.
--- This walk stays because it is cheap and because it is the belt to that
--- braces: the engine's aura buttons are minted in batches and the plate's
--- regions are the ones that actually have to be right.
--- In "crisp" mode this puts snapping BACK ON for the plate's own regions,
--- against the suite wide hook in Pixel.lua. The two modes have to agree with
--- each other across every region on the plate or we are back to the mix that
--- caused the jumping.
local function SnapOff(r)
    if not r then return end
    local KS = EV.Pixel.KeepSnap
    if M.db.pixelMode ~= "crisp" then
        if KS then KS(r, false) end
        EV.Pixel.NoSnap(r)
        return
    end
    local t = r
    if not r.SetSnapToPixelGrid and r.GetStatusBarTexture then
        local ok, fill = pcall(r.GetStatusBarTexture, r)
        t = (ok and type(fill) == "table") and fill or nil
    end
    -- Exempt from the suite wide unsnap hook, or the next SetTexture on this
    -- region silently undoes the line below.
    if KS then KS(r, true); if t then KS(t, true) end end
    if t and t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, true) end
end
ns.SnapOff = SnapOff

--- GetRegions and GetChildren return MULTIPLE VALUES, not a table, so their
--- results are consumed as varargs straight off the pcall. Binding them to a
--- single local silently takes the first one and drops the rest.
local function PassEach(round, ok, ...)
    if not ok then return end
    for i = 1, select("#", ...) do
        local r = (select(i, ...))
        if round then RoundRegion(r) end
        SnapOff(r)
    end
end

local function PassChildren(depth, ok, ...)
    if not ok then return end
    for i = 1, select("#", ...) do ns.RoundLayout((select(i, ...)), depth + 1) end
end

--- One walk, two jobs: round the layout where the engine will let us, and turn
--- the renderer's per-region snapping off everywhere.
---
--- Rounding is allowed to fail. Unsnapping is NOT skipped when it does -- the
--- old walk returned early the moment RoundRegion said no, which meant that on
--- any client refusing the protected call nothing below that frame was
--- touched at all.
function ns.RoundLayout(frame, depth)
    depth = depth or 0
    if not frame or depth > 5 then return end
    local okF, forbidden = pcall(frame.IsForbidden, frame)
    if okF and forbidden then return end
    local rounded = RoundRegion(frame)
    SnapOff(frame)
    PassEach(rounded, pcall(frame.GetRegions, frame))
    PassChildren(depth, pcall(frame.GetChildren, frame))
end

--------------------------------------------------------------------------------
--  Telling the engine how big a plate is
--
--  This is the structural fix, and the reason verticalOffset existed at all.
--
--  C++ places a nameplate from the size the engine has been told it is: it
--  puts the BOTTOM of that box above the unit. We never told it, so it went on
--  positioning plates for Blizzard's much shorter bar while we drew a taller
--  one centred on the same point, and then we dragged the whole thing down 25
--  pixels to compensate. Every one of those pixels was us disagreeing with the
--  engine about where the plate was.
--
--  The fix is to derive the box from our own design and push it into the
--  engine, then work out where our content sits INSIDE that box. The offset
--  each plate gets is then not a fudge, it is "where the health bar sits
--  within a box the engine now agrees with us about".
--
--  So baseOffset is the distance from the centre of the plate
--  box to the centre of our health bar, which is zero when there is as much
--  above the bar as below it and non-zero when there is not.
--
--  SetNamePlateSize is global -- one size for every plate in the game, and
--  there is no per type setter -- so it moves Blizzard's friendly plates too.
--  That is what the friendly offset is for, and why it exists separately.
--------------------------------------------------------------------------------
ns.baseOffset = 0

--- What hangs below the health bar, and what sits above it, in the same units
--- the widgets are laid out in. These read the widget anchors rather than
--- inventing numbers: the aura row's lift is Auras.lua:148 and the quest count
--- shares that line (Auras.lua "Wrap", which shortens the row to make room).
local function Extent(cfg)
    local below = (ns.PowerDrop and ns.PowerDrop(cfg) or 0)
    if cfg.showCast and cfg.castHeight > 0 then
        below = below + cfg.castGap + cfg.castHeight
    end
    local above = 0
    if cfg.showAuras or cfg.showCC or cfg.showBuffs then
        above = 2 + cfg.auraSize * (cfg.auraRatio or 1)    -- LIFT + icon height
    end
    if cfg.showQuest and cfg.fontSize > above then above = cfg.fontSize end
    return above, below
end

--- Read back, never assumed. SetNamePlateSize is HasRestrictions
--- (NamePlateDocumentation.lua:46) and a pcall that returns true tells us the
--- call did not throw, not that the engine accepted it. GetNamePlateSize is
--- the only honest check, and nppx prints both numbers.
ns.sizeAsked = { w = 0, h = 0 }

local sizeRetry = CreateFrame("Frame")
sizeRetry:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ns.Safe("platesize", ns.UpdatePlateSize)
end)

function ns.UpdatePlateSize()
    if not (C_NamePlate and C_NamePlate.SetNamePlateSize) then return true end
    -- Refused in combat, but no longer dropped: the old version returned
    -- false and nothing ever asked again, so a size Blizzard pushed mid-pull
    -- stood until something else happened to call us.
    if InCombatLockdown() then
        sizeRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    local cfg = M.db
    local above, below = Extent(cfg)
    local h = above + cfg.height + below
    ns.sizeAsked.w, ns.sizeAsked.h = cfg.width, h
    pcall(C_NamePlate.SetNamePlateSize, cfg.width, h)

    -- baseOffset stays ZERO. Blizzard's plate grows from its CENTRE, not its
    -- base: a taller SetNamePlateSize enlarges the box evenly above and below
    -- the unit.
    --
    -- The box is centred, not bottom-anchored above the unit, so there is
    -- nothing to correct; any correction here pushes the bar off centre.
    --
    -- READ BACK, and recompute from what the engine actually took.
    --
    -- We asked for 64 and it reports 63.75: it quantises the box to its own
    -- grid. Small, but it is a disagreement about where the plate is, and a
    -- disagreement about where the plate is has been the story of this whole
    -- module. baseOffset is the distance from the box centre to the bar
    -- centre, so it has to be measured against the box the ENGINE has, not
    -- the one we asked for.
    if C_NamePlate.GetNamePlateSize then
        local okZ, _, gh = pcall(C_NamePlate.GetNamePlateSize)
        if okZ and type(gh) == "number" and gh > 0 then h = gh end
    end
    ns.baseOffset = 0
    return true
end

--- Put the plate where it belongs: the configured height over the mob.
--- One owner for the anchor, so nothing else has to know how it is computed.
function ns.PlacePlate(f)
    local plate = f.plate
    if not plate then return end
    local cfg = M.db
    local off = cfg.verticalOffset or 0
    -- Friendly plates get their own number, and only when we are the ones
    -- drawing them. UnitIsFriend carries no secret marker in
    -- UnitDocumentation.lua:1977, so this is a plain test.
    if cfg.doFriendly and f.unit then
        local okF, friend = pcall(UnitIsFriend, "player", f.unit)
        if okF and friend then off = cfg.friendlyVerticalOffset or 0 end
    end
    -- baseOffset is where the bar sits inside the box the engine now agrees
    -- with us about; the configured offset is a fine tune on top of it and
    -- should normally be zero.
    -- Straight onto Blizzard's plate, CENTER to CENTER, the offset left
    -- exactly as configured.
    -- Position belongs to the engine. Quantising it, or hanging it off a
    -- rounded intermediate frame, is what turns the engine's smooth motion
    -- into steps.
    f:SetPoint("CENTER", plate, "CENTER", 0, (ns.baseOffset or 0) + off)
    f._offY = (ns.baseOffset or 0) + off
end

--------------------------------------------------------------------------------
--  Stacking bounds and click region
--
--  The piece we never had, and both references do. Without a bounds frame the
--  stacking solver works from the whole engine box we hand SetNamePlateSize,
--  which includes the aura row and the cast row whether or not either is
--  showing. That box is nearly three times the height of the bar, so in a
--  pack every plate is "overlapping" its neighbours most of the time and the
--  solver keeps sliding them up and down past each other. That is the plates
--  moving up and down.
--
--  The fix is to hand the engine a bounds frame covering only the BARS -- health, cast, and name
--  where the name sits outside the bar. Ours sits inside it. The aura row is
--  left out on purpose, the same call Blizzard make for a second debuff row
--  ("A second row of debuffs can cause overlap when stacking nameplates",
--  Blizzard_NamePlates.lua:347-352). Constant size, so the solver never sees
--  a plate change shape because a mob started casting.
--
--  Load-bearing detail: the engine reads the frame's RENDERED
--  bounds, the union of its regions, not its SetSize. Without a full size
--  texture the rect is empty and plates silently stop stacking.
--
--  It lives in Blizzard plate space, not ours, so our own SetScale is folded
--  in by hand. One per Blizzard plate, kept in the weak side table, never a
--  field on their frame.
--------------------------------------------------------------------------------
local function BoundsFrame(plate)
    local st = ns.blizState[plate]
    if not st then st = {}; ns.blizState[plate] = st end
    local b = st.bounds
    if not b then
        b = CreateFrame("Frame", nil, plate)
        b:EnableMouse(false)
        local t = b:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(1, 0, 0, 0)
        t:SetAllPoints(b)
        st.bounds = b
    end
    return b
end

--- Size and place the bounds frame for our plate, and hand it to the engine.
--- Returns the frame so the click region can be the same rect.
function ns.UpdateBounds(f)
    local plate = f.plate
    if not plate then return nil end
    local cfg = M.db
    local s = cfg.scale or 1
    local below = 0
    if cfg.showPower then below = below + (cfg.powerGap or 0) + (cfg.powerHeight or 0) end
    if cfg.showCast and (cfg.castHeight or 0) > 0 then
        below = below + (cfg.castGap or 0) + cfg.castHeight
    end
    local b = BoundsFrame(plate)
    b:ClearAllPoints()
    b:SetPoint("TOP", plate, "CENTER", 0, ((f._offY or 0) + cfg.height / 2) * s)
    b:SetSize(cfg.width * s, (cfg.height + below) * s)
    b:Show()
    ns.boundsSize = ns.boundsSize or {}
    ns.boundsSize.w, ns.boundsSize.h = cfg.width * s, (cfg.height + below) * s
    if plate.SetStackingBoundsFrame then
        ns.Safe("stackbounds", plate.SetStackingBoundsFrame, plate, b)
    end
    return b
end

--- A recycled Blizzard plate may be handed a unit we do not draw, and a stale
--- bounds rect would keep steering the solver for it, so it is hidden on
--- release.
function ns.ReleaseBounds(plate)
    local st = plate and ns.blizState[plate]
    if st and st.bounds then st.bounds:Hide() end
end

--------------------------------------------------------------------------------
--  The host is gone
--
--  We used to centre our plate on a rounded frame the size of Blizzard's
--  plate, with a two point anchor. That only works when the plate box is a
--  whole number of pixels; ours is whatever the engine quantises
--  SetNamePlateSize to (63.75 here), which rounds to a height that changes as
--  the plate moves, so its centre wandered by half a pixel and took our whole
--  plate with it. There is no intermediate frame now: our root is centred on
--  the raw base plate.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--  The deadzone: not possible, and the reason is worth keeping
--
--  A hold threshold (a plate only moves once it has moved far enough to be
--  worth moving) cannot be built, by us or by anyone, because
--  it needs the plate's screen position and Blizzard removed that in 8.2:
--  GetPoint, GetCenter and GetLeft on nameplate children no longer answer.
--
--  That is the same restriction nppx has been reporting as UNREADABLE all
--  along, and it is not a Forever quirk. No nameplate addon can read a
--  plate's position, so none has a deadzone, hysteresis, threshold or
--  smoothing of its own. The position belongs to the engine and the only
--  thing an addon can do is attach to it well.
--------------------------------------------------------------------------------

local sizeHooked = setmetatable({}, { __mode = "k" })
local rescale = {}
local rescaler = CreateFrame("Frame")
rescaler:Hide()
rescaler:SetScript("OnUpdate", function(self)
    for f in pairs(rescale) do
        rescale[f] = nil
        if f.unit and ns.plates[f.unit] == f then
            local ok, es = pcall(f.GetEffectiveScale, f)
            -- A relayout is not free and it is not invisible: every child
            -- re-snaps and can land a pixel from where it was. So it has to be
            -- worth doing. If this client varies plate scale continuously --
            -- with distance, say -- then reacting to every change is a
            -- relayout every frame, which is the contents crawling rather than
            -- a crisp plate. One per cent is below anything you could see in
            -- a border's thickness and well above that kind of drift.
            local prev = f._es
            if ok and type(es) == "number" and es > 0.1
               and (type(prev) ~= "number" or math.abs(es - prev) > prev * 0.01) then
                f._es = es
                ns.Safe("rescale", ns.Layout, f)
            end
        end
    end
    if next(rescale) == nil then self:Hide() end
end)

--- Watch a Blizzard plate for the scale changes it never tells us about.
--- Hooked once per plate frame and never removed: HookScript cannot be undone
--- and Blizzard's plates are pooled, so a hook per attach would accumulate one
--- closure per spawn for the whole session.
local function WatchScale(plate, f)
    f._es = select(2, pcall(f.GetEffectiveScale, f)) or nil
    if sizeHooked[plate] then return end
    sizeHooked[plate] = true
    plate:HookScript("OnSizeChanged", function(self)
        -- Through the weak side table, not a field on their frame. A stray
        -- write onto a nameplate taints it, which is the rule this module
        -- opens with, and a hook that fires during every spawn animation is
        -- the last place to make an exception.
        local st = ns.blizState[self]
        local ours = st and st.ours
        if not ours then return end
        rescale[ours] = true
        rescaler:Show()
    end)
end

--- Guarded call. A nameplate handler that errors mid-pull is a nameplate
--- handler that takes the pull with it, so every entry point is wrapped.
---
--- But a swallowed error is a bug you never find. This module's first review
--- turned up five defects that all failed INVISIBLY for exactly that reason:
--- the cast bar simply never appeared, the aura rows simply stayed empty,
--- and nothing was ever printed. So each distinct site reports ONCE, through
--- the normal error handler, and then goes quiet. Loud enough to notice,
--- quiet enough to play through.
local reported = {}
function ns.Safe(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported[what] then
        reported[what] = true
        geterrorhandler()(("EvermoreUI Nameplates [%s]: %s"):format(what, tostring(err)))
    end
    return ok
end

--- Let a reload surface a fault that has already been reported once.
function ns.ResetReports() wipe(reported) end

--------------------------------------------------------------------------------
--  Widget registry
--
--  One file per visual element. A widget implements whichever of these it
--  needs and the plate calls only the ones that exist, so adding an element
--  is adding a file and never touching this one:
--
--      Build(plate)       once, when the frame is created
--      Layout(plate, cfg) on a settings pass or a fresh plate
--      SetUnit(plate)     when a unit is assigned
--      Clear(plate)       when the unit goes away
--      Target(plate)      target, focus or mouseover changed
--      Events(cfg)        -> list of unit events this widget needs, or nil
--
--  Events is the important one: the event set is derived from the ACTIVE
--  CONFIGURATION, so a feature that is off does not register its events at
--  all. "Off" should mean silence, not a boolean check per event.
--------------------------------------------------------------------------------
ns.widgets = {}

function ns.Widget(def)
    assert(type(def) == "table" and type(def.name) == "string", "widget needs a name")
    ns.widgets[#ns.widgets + 1] = def
    return def
end

--- Dispatch to every widget that implements the method.
---
--- Each widget is guarded SEPARATELY. The obvious alternative -- one
--- ns.Safe around the whole sweep -- looks equivalent and is not: the first
--- widget that throws would skip every widget after it in the list. On the
--- Clear sweep that is a plate going back into the pool with an aura holder
--- still parented to it, which then shows the previous unit's dots on
--- whatever mob the recycled plate is handed to next. The guard is a pcall
--- per widget per call, which is nothing next to the work inside it.
local function ForEachWidget(method, ...)
    local list = ns.widgets
    for i = 1, #list do
        local w = list[i]
        local fn = w[method]
        if fn then ns.Safe(method .. ":" .. w.name, fn, ...) end
    end
end
ns.ForEachWidget = ForEachWidget

--------------------------------------------------------------------------------
--  Standing Blizzard's plate down
--
--  The doctrine, and every line of it is load bearing:
--
--   * SetAlpha(0), NEVER Hide(). Hiding the UnitFrame flips the plate's
--     contents to IsVisible() == false, which breaks click target selection
--     between overlapping plates in a pack. The frame must stay shown, and
--     stay where Blizzard put it.
--   * Reparent its children offscreen, discovered by walking GetChildren()
--     rather than from a list of names we would have to maintain. An
--     alpha-0 AurasFrame is still a mouse-enabled tooltip trap sitting over
--     every plate, so it has to move, not fade.
--   * UnregisterAllEvents on the UnitFrame and its cast bar. Blizzard
--     registers around 27 unit events and 20 globals per plate, and its
--     dirty flags arm a real OnUpdate on a frame nobody can see. Killing
--     that surface is the cheapest large win available to us.
--   * Put it all back on removal, so a recycled plate is clean and turning
--     the feature off leaves no trace.
--------------------------------------------------------------------------------
-- These are the game's, not ours, and they have to keep working. They cannot
-- simply be LEFT on the UnitFrame: alpha is inherited multiplicatively so an
-- alpha-0 parent hides them anyway, and WidgetContainer is anchored to
-- CastBarsContainer, which we park offscreen. So they move onto the base
-- plate instead, where they keep their own alpha and their own position.
local KEEP_CHILD = {
    WidgetContainer = true,     -- Blizzard's UI widgets belong to the game
    SoftTargetFrame = true,     -- soft target icon is the game's, not ours
}

-- No KEEP_EVENTS any more. We used to put PLAYER_TARGET_CHANGED and the two
-- soft target events back on their UnitFrame "for the soft target icon". The
-- icon is drawn by the DRIVER (NamePlateDriverMixin:UpdateSoftTargetIcon,
-- Blizzard_NamePlates.lua, forever branch), which has its own registrations.
-- All the UnitFrame did with PLAYER_TARGET_CHANGED was UpdateIsTarget, which
-- re-anchors WidgetContainer and calls UpdateHitTestArea -- pointing the
-- plate's hit test back at THEIR hidden health bar on every target change and
-- throwing ours away. So nothing is re-registered.

--- Every event registration in their subtree, not just the top frame. The
--- AurasFrame keeps LOSS_OF_CONTROL_* and the ClassificationFrame has its
--- own OnEvent; UnregisterAllEvents on the parent does not reach either.
--- The kept children (widgets) are skipped: those are the game's and have to
--- go on working. They re-register themselves the next time Blizzard's own
--- SetUnit runs on this frame, which is the next time the pool hands it out.
local function Silence(frame, keep, depth)
    depth = depth or 0
    if not frame or depth > 6 or keep[frame] then return end
    local okF, forbidden = pcall(frame.IsForbidden, frame)
    if okF and forbidden then return end
    if frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
    local ok, list = pcall(function() return { frame:GetChildren() } end)
    if ok then for _, c in ipairs(list) do Silence(c, keep, depth + 1) end end
end

local function Holder()
    if not hidden then
        hidden = CreateFrame("Frame", nil, UIParent)
        hidden:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
        hidden:SetSize(1, 1)
        hidden:Hide()
    end
    return hidden
end

local function StandDown(uf)
    if not uf or ns.blizState[uf] then return end
    local st = { children = {} }
    ns.blizState[uf] = st

    -- Alpha, with a guarded hook so their own code putting it back does not
    -- win. The guard stops our SetAlpha re-entering the hook.
    st.alpha = true
    pcall(uf.SetAlpha, uf, 0)
    if not alphaHooked[uf] then
        alphaHooked[uf] = true
        hooksecurefunc(uf, "SetAlpha", function(self2)
            local mine = ns.blizState[self2]
            if not (mine and mine.alpha) or mine.locked then return end
            mine.locked = true
            pcall(self2.SetAlpha, self2, 0)
            mine.locked = nil
        end)
    end

    local holder = Holder()
    if uf.GetChildren then
        local ok, list = pcall(function() return { uf:GetChildren() } end)
        if ok then
            for _, c in ipairs(list) do
                local key
                for k, v in pairs(uf) do if v == c then key = k break end end
                local locked = (c.IsForbidden and c:IsForbidden())
                    or (c.IsProtected and select(1, c:IsProtected()))
                if not locked and c.SetParent then
                    st.children[#st.children + 1] = { frame = c, parent = c:GetParent() }
                    if key and KEEP_CHILD[key] then
                        local base = uf:GetParent()
                        pcall(c.SetParent, c, base or holder)
                        pcall(c.SetAlpha, c, 1)
                        st.kept = st.kept or {}
                        st.kept[key] = c
                    else
                        pcall(c.SetParent, c, holder)
                    end
                end
            end
        end
    end

    -- GetChildren() returns FRAMES ONLY, so every FontString and Texture
    -- sitting directly on the UnitFrame is invisible to the walk above. The
    -- parent's alpha 0 covers most of them, but not one flagged
    -- ignoreParentAlpha -- selectionHighlight is exactly that
    -- (Blizzard_NamePlates.xml:298). Name them and quiet them.
    for _, key in ipairs({ "name", "selectionHighlight", "aggroFlash", "behindCameraIcon" }) do
        local r = uf[key]
        if type(r) == "table" and r.SetAlpha then
            st.regions = st.regions or {}
            st.regions[#st.regions + 1] = r
            pcall(r.SetAlpha, r, 0)
        end
    end

    -- Every registration in the subtree, the kept widgets excepted.
    local keepSet = {}
    for _, c in pairs(st.kept or {}) do keepSet[c] = true end
    Silence(uf, keepSet)

    -- Their dirty-flag OnUpdate (CompactUnitFrame_CheckNeedsUpdate arms it
    -- on the SetUnit that ran a moment ago). With every event gone nothing
    -- can re-arm it until Blizzard hands this frame a new unit.
    pcall(uf.SetScript, uf, "OnUpdate", nil)

    -- And the frame itself OFF the plate, reparented to a hidden holder,
    -- rather than alpha 0. At alpha 0 Blizzard's UnitFrame stays a live, laid out, pixel
    -- rounded (Blizzard_NamePlateUnitFrame.lua:88) child of the plate, and
    -- still the thing its hit test area hangs off. The reason to keep it
    -- there is that hiding it breaks click selection while the plate's hit
    -- test still points into it. Ours no longer does: Added
    -- hands the engine our own region on the add tick, and nothing of theirs is left listening to take it back.
    st.parent = uf:GetParent()
    pcall(uf.SetParent, uf, holder)
end

--- Put the widgets we kept somewhere sensible now their old anchors point
--- into a frame that is no longer on the plate. Blizzard's own positions,
--- re-expressed against our geometry: WidgetContainer under the bars
--- (UpdateIsTarget, Blizzard_NamePlateUnitFrame.lua:549-553), the soft target
--- icon 8 into the top of the plate (Blizzard_NamePlates.xml, SoftTargetFrame).
function ns.AnchorKept(f)
    local uf = f.blizUF
    local st = uf and ns.blizState[uf]
    local kept = st and st.kept
    if not kept or not f.plate then return end
    local st2 = ns.blizState[f.plate]
    local bounds = st2 and st2.bounds
    local w = kept.WidgetContainer
    if w then
        pcall(w.ClearAllPoints, w)
        if bounds then pcall(w.SetPoint, w, "TOP", bounds, "BOTTOM", 0, 0)
        else pcall(w.SetPoint, w, "TOP", f.plate, "CENTER", 0, 0) end
    end
    local t = kept.SoftTargetFrame
    if t then
        pcall(t.ClearAllPoints, t)
        pcall(t.SetPoint, t, "BOTTOM", f.plate, "TOP", 0, -8)
    end
end
ns.StandDown = StandDown

local function StandUp(uf)
    local st = uf and ns.blizState[uf]
    if not st then return end
    st.alpha = nil
    if st.parent then pcall(uf.SetParent, uf, st.parent) end
    for _, rec in ipairs(st.children) do
        if rec.frame and rec.parent then pcall(rec.frame.SetParent, rec.frame, rec.parent) end
    end
    -- Their original anchor (Blizzard_NamePlates.xml). WidgetContainer's is
    -- re-set by their own UpdateIsTarget on the next SetUnit.
    local t = st.kept and st.kept.SoftTargetFrame
    if t then
        pcall(t.ClearAllPoints, t)
        pcall(t.SetPoint, t, "BOTTOM", uf, "TOP", 0, -8)
    end
    for _, r in ipairs(st.regions or {}) do pcall(r.SetAlpha, r, 1) end
    pcall(uf.SetAlpha, uf, 1)
    ns.blizState[uf] = nil
end
ns.StandUp = StandUp

--------------------------------------------------------------------------------
--  Our plate
--------------------------------------------------------------------------------
local pool

local function ResetPlate(_, f)
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(UIParent)
    f.unit, f.plate, f.guid, f.blizUF, f._offY = nil, nil, nil, nil, nil
    f:UnregisterAllEvents()
    if ns.ForgetPlate then ns.ForgetPlate(f) end
end

--- postCreate, not a creator: CreateFramePool builds the frame itself and
--- hands it to us to decorate (Blizzard_SharedXMLBase/Pools.lua:670-678).
local function DecoratePlate(f)
    f:Hide()
    -- Batches the plate's draw layers: a nameplate is a dozen small regions
    -- that all move together, which is exactly what this is for.
    if f.SetFlattensRenderLayers then pcall(f.SetFlattensRenderLayers, f, true) end
    f:SetScript("OnEvent", function(self, event, ...)
        local h = ns.eventHandlers[event]
        if h then h(self, event, ...) end
    end)
    ForEachWidget("Build", f)
    ns.RoundLayout(f)
    return f
end

--- Per-plate event dispatch. Widgets put handlers here by event name; the
--- plate's OnEvent is a single table lookup.
ns.eventHandlers = {}

--- Lay the plate out, AT ITS FINAL SCALE.
---
--- The scale has to be set first, and this is not a tidiness argument. Every
--- snap in this module is computed as perfect / frame:GetEffectiveScale()
--- (EvermoreUI/Core/Pixel.lua:41), so a value snapped at scale 1 and then
--- scaled to 1.2 is no longer a whole number of physical pixels. Our plate is
--- 18 tall: at 1.2 that is 21.6 pixels, and the border strip snapped to one
--- pixel becomes 1.2 of one. Textures here are created with SetSnapToPixelGrid
--- off, deliberately, so the hardware does not round that away -- it filters
--- it, and the strip shimmers between one row and two as the plate slides
--- across the screen.
---
--- That has been true since the day target scaling went in. A black hairline
--- on a dark plate hid it; a white one on the target did not.
local function Layout(f)
    local cfg = M.db
    -- Overall scale first, target bump on top: one frame scale carrying
    -- every size on the plate. Doing it as a frame scale rather than by
    -- multiplying each stored number keeps the settings honest -- the width
    -- slider still says what the bar is at scale 1 -- and costs nothing,
    -- because this function snaps AFTER setting the scale.
    local scale = cfg.scale or 1
    if f.unit and cfg.targetScale ~= 1 then
        local isTarget, secret = ns.IsUnit(f.unit, "target")
        if not secret and isTarget then scale = scale * cfg.targetScale end
    end

    -- ONE scale, ours, and at the default it is 1 on every plate.
    --
    -- Our target plate used to be the only frame in the game carrying a
    -- SetScale of its own, so it was the only one whose geometry was computed
    -- in a different space from every other plate, and it behaved differently
    -- for exactly that reason. The better shape is to leave any target
    -- enlargement to the engine's own scale CVar and apply one SetScale of
    -- our own that is identical on every nameplate.
    --
    -- Handing it back also makes it survive restriction, which our version
    -- never could: the engine knows which unit is the target without us
    -- having to ask UnitIsUnit and get a secret boolean we cannot fold into a
    -- scale.
    if f:GetScale() ~= scale then f:SetScale(scale) end
    if f.SetCollapsesLayout then pcall(f.SetCollapsesLayout, f, true) end

    -- Where the plate sits over the mob. Re-asserted on every layout pass so
    -- a settings change moves the plates that are already up: see the long
    -- note in Added for why this offset has to exist at all.
    ns.PlacePlate(f)

    -- ONE BY ONE. The plate root is an anchor POINT, not a box.
    --
    -- This is the architectural difference, and everything else tonight was
    -- downstream of getting it wrong. The root gets a token size and
    -- everything hangs off its centre.
    --
    -- A point has one position, so one rounding decision, which every child
    -- centred on it inherits identically. A sized box has four edges that
    -- resolve and round independently, and its rounded width can differ from
    -- its nominal width as it slides. Ours was 196x26 with the border, the
    -- cast bar, the power strip, the aura rows, the raid marker, the quest
    -- text and the aggro glow all hanging off different edges of it, each
    -- rounding on its own. That is the content moving inside the plate, and
    -- no amount of choosing between rounding and not rounding could fix it,
    -- because the problem was how many things were being rounded separately.
    --
    -- The health bar now carries the real geometry and everything anchors to
    -- IT. See Health.lua.
    -- TWO PHYSICAL PIXELS, not one UI unit. In crisp every rect is rounded
    -- edge by edge, and 1 UI unit is not a whole number of pixels at any UI
    -- scale we ship (0.53 at 1440p: 1 unit = 1.875 px). So the rounded root
    -- was sometimes one pixel wide and sometimes two, its centre moved half a
    -- pixel as it did, and the health bar -- centred on that centre -- and
    -- every string on it went with it. The same fault as the host, one level
    -- down. An even pixel size keeps the rounded centre on a whole pixel
    -- wherever the plate is: left = round(c - 1), right = left + 2.
    local one = EV.Pixel:One(f)
    f:SetSize(one * 2, one * 2)
    ForEachWidget("Layout", f, cfg)
    -- Again after layout: the border containers and the cast icon frame are
    -- created lazily here, so the pass at build time never saw them. From the
    -- HOST, so the rect our box is centred on is rounded in the same pass and
    -- the same scale space as the box itself.
    ns.RoundLayout(f)
    ns.UpdateBounds(f)
    f._scale = scale
    f.styleGen = ns.styleGen
end
ns.Layout = Layout

--- Register only what the ACTIVE configuration needs, filtered to this unit
--- in the C layer so another unit's health change never enters Lua here.
local function RegisterFor(f, unit)
    local cfg = M.db
    local want, seen = {}, {}
    for _, w in ipairs(ns.widgets) do
        if w.Events then
            local list = w.Events(cfg)
            if list then
                for _, e in ipairs(list) do
                    if not seen[e] then seen[e] = true; want[#want + 1] = e end
                end
            end
        end
    end
    f:UnregisterAllEvents()
    for _, e in ipairs(want) do
        pcall(f.RegisterUnitEvent, f, e, unit)
    end
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--  Friendly plates, which are Blizzard's
--
--  With doFriendly off we do not draw these at all, so their height over the
--  unit is Blizzard's layout and there is no setting for it in the game. It is
--  high for a structural reason rather than a styling one: in name-only mode
--  the name anchors BOTTOMLEFT to the health bar container's TOPLEFT
--  (Blizzard_NamePlateUnitFrame.lua:741), and that container is stacked above
--  the cast bar container, which sits at the plate's bottom (:691-707). Both
--  bars are hidden on a name-only plate. Neither gives up its height. So the
--  name floats a whole bar stack above the unit with nothing underneath it.
--
--  We move the UnitFrame inside the plate rather than resizing anything.
--  C_NamePlate.SetNamePlateSize is the other lever and it is global -- one
--  size for every plate in the game, enemy and friendly alike (there is no
--  per-type setter: see NamePlateDocumentation.lua:46), which is the whole
--  reason this module has never called it.
--
--  Click targeting is unaffected. The UnitFrame carries disableMouse
--  (Blizzard_NamePlates.xml:95) and the clickable region is the PLATE's hit
--  test area, which on a name-only plate is cleared entirely
--  (Blizzard_NamePlateUnitFrame.lua:588-589) so the whole plate stays live.
--
--  Nothing to clean up on unload: AcquireUnitFrame SetAllPoints the frame
--  every time a plate takes a unit (Blizzard_NamePlateBase.lua:20), so the
--  next spawn puts it back by itself. We still undo it the moment the slider
--  returns to zero, for the plates already on screen.
--------------------------------------------------------------------------------
local nudged = setmetatable({}, { __mode = "k" })

local function NudgeFriendly(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit
                  and C_NamePlate.GetNamePlateForUnit(unit, false)
    local uf = plate and plate.UnitFrame
    if not uf then return end
    local off = M.db.friendlyVerticalOffset or 0
    if off == 0 then
        -- Only if we were the ones who moved it. Through the weak side table,
        -- never a field on their frame.
        if nudged[uf] then
            uf:ClearAllPoints()
            uf:SetAllPoints(plate)
            nudged[uf] = nil
        end
        return
    end
    uf:ClearAllPoints()
    uf:SetPoint("TOPLEFT", plate, "TOPLEFT", 0, off)
    uf:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", 0, off)
    nudged[uf] = true
end
ns.NudgeFriendly = NudgeFriendly

local function Wanted(unit)
    -- /evui npblizz: a session-only switch that leaves every NEW plate to
    -- Blizzard, untouched, so theirs can be compared with ours without
    -- turning the module off. Deliberately not saved.
    if ns.blizzardMode then return false end
    if not M.db.doFriendly then
        local ok, friend = pcall(UnitIsFriend, "player", unit)
        if ok and friend then return false end
    end
    return true
end

local function Added(unit)
    if not unit or ns.plates[unit] then return end
    local cfg = M.db
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit, false)
    if not plate then return end

    -- Decide BEFORE standing anything down. StandUp restores alpha and
    -- parents but it cannot put Blizzard's ~47 event registrations back, so
    -- a plate we stand down and then hand back is a plate frozen at whatever
    -- it displayed on the first frame. A plate we are not drawing is left
    -- completely alone.
    if not Wanted(unit) then
        if not ns.blizzardMode then ns.Safe("friendly", NudgeFriendly, unit) end
        return
    end

    StandDown(plate.UnitFrame)

    local f = pool:Acquire()
    f.unit, f.plate = unit, plate
    -- Remember THEIR frame: by the time NAME_PLATE_UNIT_REMOVED reaches us,
    -- Blizzard's own handler has already run ReleaseUnitFrame and set
    -- plate.UnitFrame to nil (Blizzard_NamePlateBase.lua:22-27), so looking
    -- it up again at removal finds nothing and the frame is never restored.
    f.blizUF = plate.UnitFrame
    -- type(), not `okG and guid or nil`. UnitGUID is
    -- SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:1241), and a
    -- throw here aborts Added AFTER StandDown has already suppressed
    -- Blizzard's plate: a nameplate with nothing drawn on it at all.
    local okG, guid = pcall(UnitGUID, unit)
    f.guid = (okG and not ns.IsSecret(guid) and type(guid) == "string") and guid or nil

    f:SetParent(plate)
    f:ClearAllPoints()
    -- Vertical offset: one CENTER to CENTER point with a Y offset.
    --
    -- It matters more for us than usual. C_NamePlate.SetNamePlateSize
    -- tells C++ how big a plate is, and C++ places it above the unit from
    -- that (Blizzard_NamePlates.lua:630-641). We never call it, deliberately,
    -- because it is global and would move every plate in the game including
    -- the friendly ones we leave alone. So the engine still positions plates
    -- for Blizzard's much shorter bar while we draw a taller one centred on
    -- it, and the taller ours gets the further its top sits above the mob.
    -- This is the knob that puts it back.
    --
    -- Applied in Layout, not here. Here it would only ever be read when a
    -- plate first appears, so moving the slider would leave every plate
    -- already on screen where it was until its mob despawned.
    f:SetFrameLevel((plate:GetFrameLevel() or 0) + 1)

    local st = ns.blizState[plate]
    if not st then st = {}; ns.blizState[plate] = st end
    st.ours = f
    WatchScale(plate, f)

    -- Click where you can SEE the bar. Blizzard derive the hit region from
    -- their own UnitFrame, which we have stood down, so resizing the plate
    -- would otherwise leave the clickable area somewhere other than the thing
    -- you are looking at. This has to happen on the tick the unit is assigned:
    -- the API says so outright ("Updates are normally blocked for tainted code
    -- during combat, except on the tick a unit is first assigned",
    -- FrameAPINamePlateDocumentation.lua:12), which is exactly here.
    if plate.SetAllHitTestPoints and plate.CanChangeHitTestPoints then
        local okC, can = pcall(plate.CanChangeHitTestPoints, plate)
        -- The BARS, not our root. The root is 1x1 by design (see Layout),
        -- so handing it over made the clickable area a single point.
        -- The clickable region is the same rect as the stacking bounds, so
        -- what you click is what the solver spaces.
        if okC and can then
            ns.PlacePlate(f)
            local b = ns.UpdateBounds(f)
            if b then pcall(plate.SetAllHitTestPoints, plate, b) end
        end
    end

    -- Always, not only when the style generation moved. A pooled frame comes
    -- back carrying the scale of whatever plate it was on last.
    Layout(f)
    ns.AnchorKept(f)
    RegisterFor(f, unit)

    ns.plates[unit] = f
    ns.active[f] = true
    f:Show()

    -- Health must paint now; everything else is imperceptible one frame late
    -- and moving it off the spawn tick is most of the cost of a pack pull.
    ForEachWidget("SetUnit", f)

    if not f._deferred then
        f._deferred = function()
            if not (f.unit and ns.plates[f.unit] == f) then return end
            ForEachWidget("Late", f)
        end
    end
    C_Timer.After(0, f._deferred)
end

local function Removed(unit)
    local f = unit and ns.plates[unit]
    ns.plates[unit] = nil
    if not f then return end
    rescale[f] = nil
    local st = f.plate and ns.blizState[f.plate]
    if st and st.ours == f then st.ours = nil end
    ns.ReleaseBounds(f.plate)
    StandUp(f.blizUF)
    f.blizUF = nil
    ns.active[f] = nil
    ForEachWidget("Clear", f)
    pool:Release(f)
end

--- A settings pass bumps one counter. Plates on screen relayout now; pooled
--- ones fix themselves on their next spawn, so there is nothing to sweep.
function M:Restyle()
    ns.styleGen = ns.styleGen + 1
    if ns.PinPlateScale then ns.Safe("cvars", ns.PinPlateScale) end
    for f in pairs(ns.active) do
        if f.unit then
            Layout(f)
            RegisterFor(f, f.unit)
            ForEachWidget("SetUnit", f)
        end
    end
    -- Turning friendly plates on or off has to reach the plates already on
    -- screen, and those are add/remove decisions rather than restyles.
    if not C_NamePlate.GetNamePlates then return end
    for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local u = (p.GetUnit and p:GetUnit()) or p.unitToken
        if u then
            local have, want = ns.plates[u] ~= nil, Wanted(u)
            if have and not want then ns.Safe("restyle-drop", Removed, u)
            elseif want and not have then ns.Safe("restyle-add", Added, u)
            elseif not want then ns.Safe("friendly", ns.NudgeFriendly, u) end
        end
    end
end

--------------------------------------------------------------------------------
--  Pinning the plate's scale
--
--  This is the answer to the jitter, and no amount of pixel rounding was ever
--  going to be.
--
--  Our plate is a CHILD of Blizzard's base nameplate, and C++ rescales that
--  base plate continuously as the mob's distance from you changes, between
--  nameplateMinScale and nameplateMaxScale. So our effective scale is a
--  moving number. Every snap in this module is computed as
--  perfect / GetEffectiveScale (EvermoreUI/Core/Pixel.lua:41), which means
--  every border thickness, every text position and every icon edge was being
--  rounded against a scale that had already changed by the time it drew. That
--  is not a rounding bug with a rounding fix. It is arithmetic against a
--  value that will not hold still, and it shows up exactly when the mob moves.
--
--  Blizzard's own Commentator
--  addon pins all three scale CVars to one value to stop plates resizing
--  (Blizzard_Commentator/Mainline:232-234). The reason carries straight
--  over: our plate is a child of the base nameplate, so Blizzard's scaling
--  shows through our own SetScale.
--
--  nameplateSelectedScale is the exception: it is not pinned, it is SET, from
--  the target scale setting. Growing the target is the engine's job and we
--  stopped doing it ourselves -- see the note in Layout.
--
--  These are account CVars and they outlive us, so the previous values are
--  kept and handed back the moment the option is turned off.
--------------------------------------------------------------------------------
--  Two more CVars belong here for the same reason, both about plates that
--  move for reasons other than the mob moving:
--
--   * nameplateShowOffscreen pins a plate to the edge of the screen once its
--     mob leaves view (Blizzard_SettingsDefinitions_Frame/Nameplates.lua:523
--     -525, "Offscreen NamePlates"). The plate then tracks the WINDOW.
--   * nameplateStackingTypes slides plates around each other so none overlap.
--     It is a bitfield, written per type through C_CVar.SetCVarBitfield with
--     Enum.NamePlateStackType (NamePlateConstantsDocumentation.lua:108-117),
--     not a plain SetCVar.
--------------------------------------------------------------------------------
--- Every engine scale lever, pinned to 1, so the plate under us never resizes
--- and our own single SetScale is the only scaling in play. We once had
--- three of these, which left the rest as ways for the engine to rescale a
--- plate we had declared constant.
---
--- nameplateSelectedScale is deliberately NOT here: that one carries the
--- target bump and is written from the setting.
local SCALE_CVARS = {
    -- overall, and the distance range
    "nameplateGlobalScale", "nameplateMaxScale", "nameplateMinScale",
    -- the base plate's own axes
    "NamePlateHorizontalScale", "NamePlateVerticalScale",
    -- the "larger nameplates" option, for mobs and for the player
    "nameplateLargerScale", "nameplatePlayerLargerScale",
    -- Their UnitFrame tells the engine a plate is "simplified" on SetUnit
    -- (C_NamePlateManager.SetNamePlateSimplified, UnitFrame.lua:378, "so it
    -- can scale it down"). That is the engine rescaling the frame we are a
    -- child of, per unit. Pinned like the rest.
    "nameplateSimplifiedScale",
}

--- Remember a CVar's value the FIRST time we take it over, and never again:
--- recording it twice would record our own value as the user's and there would
--- be nothing left to hand back.
local function Remember(backup, cv)
    if backup[cv] ~= nil then return end
    local ok, v = pcall(GetCVar, cv)
    if ok and v ~= nil then backup[cv] = v end
end

local function StackBit(which, on)
    if not (C_CVar and C_CVar.SetCVarBitfield) then return end
    if not (Enum and Enum.NamePlateStackType) then return end
    pcall(C_CVar.SetCVarBitfield, "nameplateStackingTypes", which, on and true or false)
end

local function SetPlateCVars()
    if InCombatLockdown() then return false end
    local db = M.db
    local backup = db.cvarBackup or {}
    db.cvarBackup = backup

    if db.pinPlateScale then
        -- Only the ones this client actually has. nppx reported
        -- GlobalScale=nil, so nameplateGlobalScale does not exist here and we
        -- were writing into the void for it. C_CVar.GetCVarInfo says which
        -- exist.
        for _, cv in ipairs(SCALE_CVARS) do
            if not C_CVar or not C_CVar.GetCVarInfo or C_CVar.GetCVarInfo(cv) then
                Remember(backup, cv)
                pcall(SetCVar, cv, 1)
            end
        end
    else
        for _, cv in ipairs(SCALE_CVARS) do
            if backup[cv] ~= nil then pcall(SetCVar, cv, backup[cv]); backup[cv] = nil end
        end
    end


    -- PINNED to 1, not set from the setting.
    --
    -- Handing the target bump to the engine made the engine rescale the plate
    -- under us on every target change, which is a size change on the frame we
    -- are anchored to, and because our plate is a child of the base
    -- nameplate, Blizzard's scaling shows straight through our own SetScale.
    -- Our own target scale defaults to 1, i.e. OFF, so out of the box no
    -- plate ever changes scale at all.
    Remember(backup, "nameplateSelectedScale")
    pcall(SetCVar, "nameplateSelectedScale", 1)

    ns.UpdatePlateSize()

    Remember(backup, "nameplateShowOffscreen")
    pcall(SetCVar, "nameplateShowOffscreen", db.offscreenPlates and 1 or 0)

    -- The bitfield is remembered whole, as the string it is, so turning the
    -- option off restores both bits at once rather than guessing at them.
    -- Guarded: it is not on every build of the Midnight API family, which is
    -- ours, so it may not exist here. nppx reports which.
    ns.probe.motionCVar = not (C_CVar and C_CVar.GetCVarInfo)
                          or (C_CVar.GetCVarInfo("nameplateMotionSpeed") ~= nil)
    if ns.probe.motionCVar then
        Remember(backup, "nameplateMotionSpeed")
        pcall(SetCVar, "nameplateMotionSpeed", db.plateMotionSpeed or 0.025)
    end

    -- Horizontal overlap only. nameplateOverlapV is deliberately NOT touched:
    -- it is the user's own vertical spacing preference and not ours to take.
    if db.stackPlates then
        Remember(backup, "nameplateOverlapH")
        pcall(SetCVar, "nameplateOverlapH", 1)
    end

    Remember(backup, "nameplateStackingTypes")
    if Enum and Enum.NamePlateStackType then
        StackBit(Enum.NamePlateStackType.Enemy, db.stackPlates)
        -- The friendly bit is only ours while we are the ones drawing friendly
        -- plates. Otherwise it is the user's setting and we leave it alone.
        if db.doFriendly then StackBit(Enum.NamePlateStackType.Friendly, db.stackPlates) end
    end
    return true
end

--- Hand everything back. Called when the module is switched off, so we do not
--- leave the user's game changed behind us.
function ns.ReleasePlateCVars()
    local backup = M.db.cvarBackup
    if not backup or InCombatLockdown() then return end
    for cv, v in pairs(backup) do pcall(SetCVar, cv, v) end
    M.db.cvarBackup = nil
end

--- Apply the current setting, deferring past combat if we have to. Some
--- nameplate CVars are refused in a lockdown and there is no point finding
--- out which ones the hard way.
local deferred = CreateFrame("Frame")
deferred:Hide()
deferred:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    ns.Safe("cvars", SetPlateCVars)
end)

function ns.PinPlateScale()
    if not SetPlateCVars() then
        deferred:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

--------------------------------------------------------------------------------
--  Module lifecycle
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--  Taking the driver's resize triggers away
--
--  NamePlateDriverFrame loses DISPLAY_SIZE_CHANGED and CVAR_UPDATE. We had
--  backed this out twice.
--
--  Both events route to UpdateNamePlateOptions (Blizzard_NamePlates.lua,
--  forever), which calls SetNamePlateSize with Blizzard's numbers, runs
--  ApplyFrameOptions on EVERY plate (which re-points each hit test at their
--  own health bar), and can do all of that in the middle of a pull, when we
--  are not allowed to put ours back.
--
--  The objection was the friendly plates we leave to Blizzard. Read against
--  the source it is smaller than it looked: UpdateNamePlateOptions computes
--  everything from CVars, not from the display, so DISPLAY_SIZE_CHANGED
--  changes nothing for them at all. What they lose is a live refresh when
--  one of the driver's four option CVars changes (nameplateSize,
--  nameplateStyle and the two class colour toggles): friendly plates pick
--  that up on the next /reload. Both references accept exactly that.
--
--  We deliberately do NOT call their UpdateNamePlateOptions ourselves to
--  make up for it. It writes the shared NamePlateSetupOptions tables, and a
--  table written from our code taints every later read of it, including
--  their UpdateHitTestArea on a friendly plate mid-combat, whose setter is a
--  hard error for tainted code. So on those events we only put OUR size and
--  OUR hit test regions back.
--
--  UpdateNamePlateSize is hooked rather than UpdateNamePlateOptions because
--  it is the one that actually calls SetNamePlateSize, and it has two more
--  callers that bypass Options: the debuff padding and aura scale CVar
--  callbacks (OnDebuffPaddingCVarChanged / OnAuraScaleCVarChanged).
--------------------------------------------------------------------------------
local DRIVER_EVENTS = { "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE" }
local driverTaken = false
local driverWatch = CreateFrame("Frame")
local driverPending = false

--- Our hit test regions back on every plate we draw, wherever the engine
--- allows it (always, out of combat).
function ns.ReclaimHitTest()
    for f in pairs(ns.active) do
        local plate = f.plate
        if plate and plate.SetAllHitTestPoints and plate.CanChangeHitTestPoints then
            local okC, can = pcall(plate.CanChangeHitTestPoints, plate)
            local st = ns.blizState[plate]
            if okC and can and st and st.bounds then
                pcall(plate.SetAllHitTestPoints, plate, st.bounds)
            end
        end
    end
end

local function RunDriverOptions()
    if InCombatLockdown() then
        driverPending = true
        driverWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    driverPending = false
    ns.Safe("platesize", ns.UpdatePlateSize)
    ns.Safe("hittest", ns.ReclaimHitTest)
end

driverWatch:SetScript("OnEvent", function(self, event, name)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if driverPending then RunDriverOptions() end
        return
    end
    if event == "CVAR_UPDATE" then
        -- Only the CVars their driver itself reacts to (optionCVars in
        -- NamePlateDriverMixin:OnLoad).
        local opts = NamePlateDriverFrame and NamePlateDriverFrame.optionCVars
        if not (opts and name and opts[name]) then return end
    end
    RunDriverOptions()
end)

function ns.TakeDriver()
    local d = NamePlateDriverFrame
    if not d or driverTaken then return end
    driverTaken = true
    for _, e in ipairs(DRIVER_EVENTS) do
        pcall(d.UnregisterEvent, d, e)
        driverWatch:RegisterEvent(e)
    end
    if d.UpdateNamePlateSize and not ns.sizeHooked then
        ns.sizeHooked = true
        hooksecurefunc(d, "UpdateNamePlateSize", function()
            if not driverTaken then return end
            ns.Safe("platesize", ns.UpdatePlateSize)
        end)
    end
end

function ns.ReleaseDriver()
    local d = NamePlateDriverFrame
    if not d or not driverTaken then return end
    driverTaken = false
    for _, e in ipairs(DRIVER_EVENTS) do
        driverWatch:UnregisterEvent(e)
        pcall(d.RegisterEvent, d, e)
    end
end

function M:OnEnable()
    if not self.db.enabled then return end
    -- One-off migration: an earlier build moved saved profiles to smooth.
    -- Put them back on crisp once; after that the setting is the user's.
    if not self.db.pxModel3 then
        self.db.pixelMode = "crisp"
        self.db.pxModel2 = true
        self.db.pxModel3 = true
    end
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        EV:Print(L["Nameplates: this client has no C_NamePlate API."])
        return
    end

    pool = CreateFramePool("Frame", UIParent, nil, ResetPlate, false, DecoratePlate)
    ns.pool = pool

    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, _, unit)
        ns.Safe("added", Added, unit)
    end)
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, _, unit)
        ns.Safe("removed", Removed, unit)
    end)

    -- Suppress BEFORE NAME_PLATE_UNIT_ADDED reaches any addon handler: this
    -- hook runs synchronously inside Blizzard's own add, so their initial
    -- layout pass never gets to perturb the plate.
    if NamePlateDriverFrame and NamePlateDriverFrame.OnNamePlateAdded then
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
            if not Wanted(unit) then return end
            local p = C_NamePlate.GetNamePlateForUnit(unit, false)
            if p then ns.Safe("standdown", StandDown, p.UnitFrame) end
        end)
    end

    ns.Safe("cvars", ns.PinPlateScale)
    ns.Safe("probe", ns.ReportProbe)
    ns.Safe("driver", ns.TakeDriver)

    ForEachWidget("Enable", self)

    -- /evui nppx  -- is the plate moving, and is it moving because we are
    -- relayouting it or because it sits between pixels? Sixty frames of the
    -- target plate's effective scale and screen position, which settles in one
    -- reading what several rounds of theory did not.
    EV:RegisterSlash("nppx", function()
        local f
        for u, p in pairs(ns.plates) do
            local isT, secret = ns.IsUnit(u, "target")
            if not secret and isT then f = p break end
        end
        if not f then EV:Print("Nameplates: target something we are drawing first."); return end

        local n, relayouts = 0, 0
        local esMin, esMax = math.huge, -math.huge
        local fx, fy = {}, {}
        local before = f.styleGen
        local w = CreateFrame("Frame")
        w:SetScript("OnUpdate", function(self)
            n = n + 1
            local okS, es = pcall(f.GetEffectiveScale, f)
            if okS and type(es) == "number" then
                if es < esMin then esMin = es end
                if es > esMax then esMax = es end
            end
            local okL, l = pcall(f.GetLeft, f)
            local okB, b = pcall(f.GetBottom, f)
            if okL and okB and type(l) == "number" and type(b) == "number" and okS and es and es > 0 then
                -- In PHYSICAL pixels, which is the only unit that matters here.
                local px = es / EV.Pixel:Perfect()
                fx[#fx + 1] = (l * px) % 1
                fy[#fy + 1] = (b * px) % 1
            end
            if f.styleGen ~= before then relayouts = relayouts + 1; before = f.styleGen end
            if n >= 60 then
                self:SetScript("OnUpdate", nil)
                local function spread(t)
                    if #t == 0 then return "n/a" end
                    local lo, hi = 1, 0
                    for _, v in ipairs(t) do
                        if v < lo then lo = v end
                        if v > hi then hi = v end
                    end
                    return ("%.2f..%.2f"):format(lo, hi)
                end
                EV:Print(("Nameplates pixels over %d frames:"):format(n))
                EV:Print(("  effective scale %.5f .. %.5f  (%s)")
                    :format(esMin, esMax, esMax - esMin > esMin * 0.0001 and "VARYING" or "steady"))
                if #fx == 0 then
                    EV:Print("  sub-pixel offset: UNREADABLE (geometry inside a nameplate")
                    EV:Print("    subtree does not report, which confirms design doc risk 3)")
                else
                    EV:Print(("  sub-pixel offset x %s   y %s"):format(spread(fx), spread(fy)))
                end
                EV:Print(("  relayouts triggered: %d"):format(relayouts))
                -- The other half of the question: SetSnapToPixelGrid is documented on
                -- TEXTURES. If a FontString does not carry it then our attempt
                -- to stop the text snapping did nothing at all, silently,
                -- because the helper guards on the method existing.
                -- Did the slug font objects actually resolve? Blizzard never
                -- declares a named <Font> with a direct font path, only via
                -- inherits, so the schema says our form is legal and nothing
                -- proves it until it runs. If this says false the text fell
                -- back to SetFont and is NOT slug.
                local fs = f.healthText
                local obj = fs and fs.GetFontObject and select(2, pcall(fs.GetFontObject, fs))
                local which
                for _, set in pairs(SLUG) do
                    for _, n in pairs(set) do
                        if obj ~= nil and obj == _G[n] then which = n break end
                    end
                    if which then break end
                end
                EV:Print(("  font in use: %s"):format(which or "NOT one of ours, so NOT slug"))
                EV:Print(("  configured face: %s"):format(tostring(EV.Media:GlobalFontName())))
                EV:Print(("  slug kept through sizing: %s")
                         :format(ns.slugKept == false and "NO (text will bounce)" or "yes"))
                local rs = ns.roundStats
                local pr = ns.probe
                EV:Print(("  can round layout: frame %s  fontstring %s")
                         :format(tostring(pr.frameRound and pr.frameRoundOK),
                                 tostring(pr.fontRound and pr.fontRoundOK)))
                EV:Print(("  can unsnap: texture %s  fontstring %s")
                         :format(tostring(pr.texSnap), tostring(pr.fontSnap and pr.fontSnapOK)))
                local byList = {}
                for kind, count in pairs(ns.roundStats.refusedBy) do
                    byList[#byList + 1] = ("%s x%d"):format(kind, count)
                end
                table.sort(byList)
                if #byList > 0 then
                    EV:Print(("  refused on: %s"):format(table.concat(byList, ", ")))
                end
                local db = M.db
                EV:Print(("  LIVE settings: pixelMode=%s vOffset=%s targetScale=%s scale=%s w=%s h=%s")
                         :format(tostring(db.pixelMode), tostring(db.verticalOffset),
                                 tostring(db.targetScale), tostring(db.scale),
                                 tostring(db.width), tostring(db.height)))
                if C_NamePlate and C_NamePlate.GetNamePlateSize then
                    local okZ, gw, gh = pcall(C_NamePlate.GetNamePlateSize)
                    EV:Print(("  plate size: asked %.0fx%.0f  engine says %s x %s  baseOffset %.1f")
                             :format(ns.sizeAsked.w, ns.sizeAsked.h,
                                     okZ and tostring(gw) or "?", okZ and tostring(gh) or "?",
                                     ns.baseOffset or 0))
                end
                local cv = {}
                for _, n in ipairs({ "nameplateMinScale", "nameplateMaxScale",
                                     "nameplateSelectedScale", "nameplateGlobalScale",
                                     "nameplateShowOffscreen" }) do
                    local okV, v = pcall(GetCVar, n)
                    cv[#cv + 1] = ("%s=%s"):format(n:gsub("nameplate", ""), okV and tostring(v) or "?")
                end
                EV:Print(("  cvars: %s"):format(table.concat(cv, " ")))
                local okM, mv = pcall(GetCVar, "nameplateMotionSpeed")
                EV:Print(("  engine motion smoothing: %s (stacking %s)")
                         :format(ns.probe.motionCVar == false and "CVAR ABSENT"
                                 or (okM and tostring(mv) or "?"),
                                 db.stackPlates and "on" or "OFF, so it does nothing"))
                -- "applied" counts CALLS, and in smooth mode every one of them
                -- sets rounding to FALSE. Say which, rather than reporting
                -- thousands of successful roundings on a plate that rounds
                -- nothing at all.
                EV:Print(("  rounding calls (%s): ok=%d  method missing=%d  refused=%d")
                    :format(M.db.pixelMode == "smooth" and "disabling" or "enabling",
                            rs.ok, rs.missing, rs.failed))
                -- Is rounding actually ON where it matters? SetRoundLayoutToNearestPixel
                -- is IsProtectedFunction, so a pcall that "succeeded" proves
                -- nothing. Read it back, per region, alongside the snap flag.
                local function flags(r)
                    if not r then return "absent" end
                    local okR, rv = pcall(function() return r:GetRoundLayoutToNearestPixel() end)
                    local okS, sv = pcall(function() return r:IsSnappingToPixelGrid() end)
                    local okP, pv = pcall(function() return r:GetParent():GetRoundLayoutToNearestPixel() end)
                    return ("round=%s snap=%s parentRound=%s"):format(
                        okR and tostring(rv) or "n/a", okS and tostring(sv) or "n/a", okP and tostring(pv) or "n/a")
                end
                EV:Print("  root:        " .. flags(f))
                EV:Print("  health bar:  " .. flags(f.health))
                EV:Print("  health fill: " .. flags(f.health and f.health:GetStatusBarTexture()))
                EV:Print("  health text: " .. flags(f.healthText))
                EV:Print("  name text:   " .. flags(f.nameText))
                EV:Print("  level text:  " .. flags(f.levelText))
                local okE, esF = pcall(f.GetEffectiveScale, f)
                EV:Print(("  eff scale %.5f  perfect %.5f  one px = %.4f UI")
                    :format(okE and esF or -1, EV.Pixel:Perfect(), EV.Pixel:One(f)))
                local bs = ns.boundsSize
                EV:Print(("  stacking bounds: %s  (%s)")
                    :format(bs and ("%.1f x %.1f"):format(bs.w, bs.h) or "never set",
                            f.plate and f.plate.SetStackingBoundsFrame and "engine supports it"
                                or "NO SetStackingBoundsFrame on this client"))
                EV:Print(("  plate scale: cfg %.2f  frame %.2f")
                    :format(ns.module.db.scale or 1, select(2, pcall(f.GetScale, f)) or -1))
                if fs and fs.GetFont then
                    local okF, path, h = pcall(fs.GetFont, fs)
                    if okF then EV:Print(("  rendering %s at %s"):format(tostring(path), tostring(h))) end
                end
                EV:Print("  scale VARYING means Blizzard is rescaling the plate as it moves.")
                EV:Print("  a sub-pixel spread near 0.00..1.00 means the plate sits between pixels.")
            end
        end)
        EV:Print("Nameplates: sampling for a second, keep moving.")
    end)

    -- /evui np  -- turns "I can't see my dot" into facts.
    -- /evui nptext <value>  -- live sub pixel nudge for bar text. Target a
    -- walking mob, try values, and keep the one where the text stops jumping.
    -- Without a value it steps through the sweep one value per call.
    local SWEEP = { 0, 0.1, 0.2, 0.3, 0.4, 0.5, -0.4, -0.3, -0.2, -0.1 }
    EV:RegisterSlash("nptext", function(rest)
        local v = tonumber(rest)
        if not v then
            local cur, idx = M.db.textPhase or 0, 1
            for i, s in ipairs(SWEEP) do
                if math.abs(s - cur) < 0.001 then idx = i % #SWEEP + 1 break end
            end
            v = SWEEP[idx]
        end
        if v > 0.5 then v = 0.5 elseif v < -0.5 then v = -0.5 end
        M.db.textPhase = v
        M:Restyle()
        EV:Print(("Nameplates: text phase %.2f px. Watch a walking mob; /evui nptext for the next step."):format(v))
    end)

    -- /evui npblizz  -- hand plates back to Blizzard for a side by side
    -- test. Plates already on screen are released, but their events cannot
    -- be put back until Blizzard gives them a new unit, so their health
    -- stays frozen; for a clean test use a plate that appears AFTER the
    -- switch (walk away and back). Run again to take plates back.
    EV:RegisterSlash("npblizz", function()
        ns.blizzardMode = not ns.blizzardMode
        if ns.blizzardMode then
            local list = {}
            for u in pairs(ns.plates) do list[#list + 1] = u end
            for _, u in ipairs(list) do ns.Safe("blizz-drop", Removed, u) end
            EV:Print("Nameplates: Blizzard's plates for now. Use a mob whose plate appears after this. /evui npblizz to switch back.")
        else
            if C_NamePlate.GetNamePlates then
                for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
                    local u = (p.GetUnit and p:GetUnit()) or p.unitToken
                    if u then ns.Safe("blizz-add", Added, u) end
                end
            end
            EV:Print("Nameplates: ours again.")
        end
    end)

    EV:RegisterSlash("nptextround", function()
        M.db.textRound = (M.db.textRound == false) and true or false
        M:Restyle()
        EV:Print(("Nameplates: text layout rounding %s."):format(M.db.textRound and "ON" or "OFF"))
    end)

    EV:RegisterSlash("np", function()
        local n = 0
        for _ in pairs(ns.plates) do n = n + 1 end
        EV:Print(("Nameplates: %d plate(s) up."):format(n))
        if ns.AuraReport then ns.Safe("np-report", ns.AuraReport) end
    end)

    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Restyle() end)

    -- Plates already on screen when we load.
    if C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates() or {}) do
            local u = (p.GetUnit and p:GetUnit()) or p.unitToken
            if u then ns.Safe("seed", Added, u) end
        end
    end
end

function M:OnProfileChanged() self:Restyle() end
function M:Refresh() self:Restyle() end
