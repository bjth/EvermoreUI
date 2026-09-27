if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Parts.lua
--  One part per Blizzard template. The fingerprints are taken from their
--  own XML (exported with /console ExportInterfaceFiles code), not from
--  guesswork, and the counts below are how many places in that XML
--  inherit the template, so the order is roughly the order of value.
--
--  The counts are camelot's, from tools/survey/manifests/camelot.json,
--  checked 21 Sep 2026. They were previously quoted about 1.5x too high
--  (retail mainline figures, most likely). Re-run the survey after a
--  client patch rather than trusting these.
--
--  Order matters: the first part that matches claims the object, so the
--  specific ones come before the general. A close button also has
--  Left/Middle/Right/Text, so it has to be tried before a panel button.
--
--  To extend this file: add a part. Nothing else changes, and every
--  window Blizzard builds from that template is covered at once.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S, T = ns.S, EV.Theme
if not S then return end

local R = S.Register
-- What every control looks like is in EvermoreUI/Core/Looks.lua, shared with
-- our own widgets. Parts read their geometry and colours from there.
local LOOK = T.LOOK

--- A scroll arrow (or any small chevron that lights on hover), through
--- T.LOOK.scrollStep. `step` is the button it lives on, for the hover hooks;
--- nil for a chevron that is only ever at rest.
function S.StepperLook(step, sd)
    if not sd.chev then return end
    local st = sd
    local function Paint() sd.chev:SetColorLines(T.C4(T.Resolve(LOOK.scrollStep, st).glyph)) end
    Paint()
    T.Watch(sd.chev, Paint)
    if step and step.HookScript then
        step:HookScript("OnEnter", function() st.hover = true; Paint() end)
        step:HookScript("OnLeave", function() st.hover = false; Paint() end)
    end
end

--- The one icon treatment, used by every part that shows an icon: the
--- suite's icon style (EvermoreUI/Core/Icons.lua, General > Icons), the same
--- crop and edge as every icon we draw ourselves. Blizzard's icon stays where
--- Blizzard put it; the edge hugs it from outside, on a frame of ours, which
--- this returns (hide it to hide the edge). An edge colour that means
--- something (quality, hover) goes through EV.Icons:SetState on the icon.
function S.IconWell(icon)
    if not (icon and icon.SetTexCoord and icon.GetParent) then return end
    local rec = EV.Icons:Style(icon)
    if rec and rec.frame then S.Ours(rec.frame) end
    return rec and rec.frame
end

--- The suite's crop, for icons whose coordinates Blizzard sets again later.
function S.Crop(icon)
    if icon and icon.SetTexCoord then icon:SetTexCoord(EV.Icons:Coords()) end
end

--- A scroll thumb through T.LOOK.scrollbar: `tex` is what we colour,
--- `hoverOn` the frame whose mouse-over and press count (the thumb itself on
--- a modern bar, the whole Slider on a legacy one).
function S.ThumbLook(hoverOn, tex)
    local st = {}
    local function Paint() tex:SetColorTexture(T.C4(T.Resolve(LOOK.scrollbar, st).thumb)) end
    Paint()
    T.Watch(tex, Paint)
    if hoverOn and hoverOn.HookScript then
        hoverOn:HookScript("OnEnter", function() st.hover = true; Paint() end)
        hoverOn:HookScript("OnLeave", function() st.hover = false; Paint() end)
        hoverOn:HookScript("OnMouseDown", function() st.dragging = true; Paint() end)
        hoverOn:HookScript("OnMouseUp", function() st.dragging = false; Paint() end)
    end
end

--- The separator between two crumbs.
---
--- Blizzard gives every NavButtonTemplate an arrowUp/arrowDown pair anchored
--- LEFT-to-RIGHT, so it sits just outside that button's right edge and
--- divides it from the NEXT crumb. They are the same separator in two
--- pressed states, and nothing in Blizzard's code ever hides one.
---
--- Hanging our chevron on that texture inherited both of its faults:
---   * the home button is declared inline in NavBarTemplate, has no arrows at
---     all, and so got no separator after it ("World" ran straight into
---     "Kalimdor")
---   * the last crumb has one like any other, so we drew a trailing chevron
---     after the final zone
---
--- A separator belongs BETWEEN two crumbs, which makes it the strip's
--- business rather than the button's. NavBar_CheckLength already works out
--- which buttons are shown and anchors them left to right; we mirror that
--- pass and give a chevron to every shown crumb except the last.
---
--- Position is the midpoint of the gap the eye actually sees, between where
--- this crumb stops drawing and where the next crumb's label starts.
---
--- Anchoring it a fixed distance into the following button looked right for
--- the zone crumbs and too wide after "World", because the two shapes inset
--- their labels differently:
---
---   home    ButtonText LEFT x="10" AND RIGHT x="-30", width
---           min(128, stringwidth + 50). It reserves 30px on the right for a
---           menu arrow it does not have, and xoffset = -15 claws back only
---           half of it.
---   crumb   ButtonText LEFT x="20", no right anchor, auto-sized, and its
---           MenuArrowButton sits at RIGHT x="-2", hard against the edge.
---
--- For "World" that put the chevron 35px after the label and 10px before the
--- next one. The zone crumbs came out even by luck. Measuring the gap fixes
--- home and leaves the crumbs where they already were.
local NAV_SEP_CLEAR = 4

--- Where this crumb stops drawing, measured from its own left edge.
local function ContentEnd(b)
    local w = S.Num(b.GetWidth and b:GetWidth()) or 0
    local crumb = rawget(b, "arrowUp") ~= nil
    local menu = rawget(b, "MenuArrowButton")
    if S.Alive(menu) and menu.IsShown and menu:IsShown() then
        return w - 2                      -- MenuArrowButton is anchored RIGHT x="-2"
    end
    local fs = rawget(b, "text")
    if type(fs) == "table" and fs.GetStringWidth then
        local ok, sw = pcall(fs.GetStringWidth, fs)
        sw = ok and S.Num(sw) or nil
        if sw then
            local inset = crumb and 20 or 10
            -- home's label is two-point anchored, so it truncates at w-30.
            local limit = crumb and w or (w - 30)
            return math.min(inset + sw, limit)
        end
    end
    return w                              -- the overflow button, which has no label
end

--- Where the following crumb's label begins, in this crumb's coordinates.
local function NextLabelStart(b, after)
    local w = S.Num(b.GetWidth and b:GetWidth()) or 0
    local gap = S.Num(rawget(b, "xoffset")) or 0   -- negative: the crumbs overlap
    local inset = (after and rawget(after, "arrowUp") ~= nil) and 20 or 10
    return w + gap + inset
end

local function Separator(b)
    local d = S.D(b)
    if d.sep or not T.Chevron then return d.sep end
    if not b.CreateTexture then return nil end
    d.sep = S.Ours(T.Chevron(b, LOOK.scrollStep.chevron))
    d.sep:Point("right")
    S.StepperLook(nil, { chev = d.sep })
    return d.sep
end

--- Lay the separators out across one bar. Idempotent: it recomputes from
--- what is shown rather than remembering anything.
function S.NavSeparators(bar)
    if not S.Alive(bar) then return end
    local list = rawget(bar, "navList")
    if type(list) ~= "table" then return end

    -- The overflow button, when the strip has collapsed, sits ahead of the
    -- first visible crumb: NavBar_CheckLength anchors that crumb to its RIGHT.
    local shown = {}
    local overflow = rawget(bar, "overflow")
    if S.Alive(overflow) and overflow:IsShown() then shown[#shown + 1] = overflow end
    for i = 1, #list do
        local b = list[i]
        if S.Alive(b) and b:IsShown() then shown[#shown + 1] = b end
    end

    for i = 1, #shown do
        local b, after = shown[i], shown[i + 1]
        local sep = Separator(b)
        if sep then
            if after then
                local ends = ContentEnd(b)
                local mid = (ends + NextLabelStart(b, after)) / 2
                -- The overflow button overlaps the crumb after it by 18, so
                -- the midpoint can land before its own content. Never draw
                -- the chevron back over the thing it follows.
                if mid < ends + NAV_SEP_CLEAR then mid = ends + NAV_SEP_CLEAR end
                sep:ClearAllPoints()
                sep:SetPoint("CENTER", b, "LEFT", mid, 0)
                sep:Show()
            else
                sep:Hide()
            end
        end
    end
end

--- Blizzard pools nav bar buttons. NavBar_AddButton pulls one off
--- freeButtons or builds a new one, and every add, reset and click ends in
--- NavBar_CheckLength. A button created after our sweep would otherwise keep
--- Blizzard's art until the window was next shown, which on the world map
--- means every time you change zone.
---
--- Post-hooking that one function catches all of it, and is also the right
--- moment to re-lay the separators, because it is exactly when Blizzard has
--- finished deciding which crumbs are visible. S.Dress skips anything already
--- claimed, so re-walking an unchanged bar costs almost nothing.
local navHooked = false
--------------------------------------------------------------------------------
--  Panel tabs bounce their own text
--
--  Blizzard moves a tab's label when it is selected. Both functions set the
--  same point with different offsets
--  (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua:598-632):
--
--      DeselectTab:  tab.Text:SetPoint("CENTER", tab, "CENTER", 0,  2)
--      SelectTab:    tab.Text:SetPoint("CENTER", tab, "CENTER", 0, -3)
--
--  That is a five pixel jump, and it exists because their selected tab art
--  sits lower in the rect than their unselected art. Take the art away and
--  draw both states on the rect, as we do, and the offset has nothing left to
--  compensate for: the label just hops when you click it.
--
--  Blizzard re-applies it on every select, so a one-off re-seat in the part
--  would last until the first click. Post-hook both functions instead, the
--  same shape as S.HookNavBar. The re-seat goes through Painter:Reseat, so it
--  is still the guarded path: same object, same point name, offsets only.
--------------------------------------------------------------------------------
local tabsHooked = false
function S.HookPanelTabs()
    if tabsHooked then return end
    if type(_G.PanelTemplates_SelectTab) ~= "function"
       or type(_G.PanelTemplates_DeselectTab) ~= "function" then return end
    tabsHooked = true
    local function Settle(tab)
        if not S.Alive(tab) then return end
        local d = S.D(tab)
        if d.Seat then d.Seat() end
        if d.Sync then d.Sync() end
    end
    hooksecurefunc("PanelTemplates_SelectTab", Settle)
    hooksecurefunc("PanelTemplates_DeselectTab", Settle)
    -- A greyed-out tab takes the deselected offset down the same path
    -- (SharedUIPanelTemplates.lua:640-652) but is reached from
    -- PanelTemplates_UpdateTabs rather than from either of the above.
    if type(_G.PanelTemplates_SetDisabledTabState) == "function" then
        hooksecurefunc("PanelTemplates_SetDisabledTabState", Settle)
    end
end

function S.HookNavBar()
    if navHooked or type(_G.NavBar_CheckLength) ~= "function" then return end
    navHooked = true
    hooksecurefunc("NavBar_CheckLength", function(bar)
        if not S.Alive(bar) then return end
        S.Walk(bar, 0)
        S.NavSeparators(bar)
    end)
end

--------------------------------------------------------------------------------
--  Ornate chrome we always take down, wherever it turns up.
--
--  This is the one curated list in the library. It is checked against
--  every texture the walk meets, so a pattern added here covers every
--  window at once. `/evui skin loose` lists the art in a window that no
--  pattern and no part accounted for, which is how the list grows.
--------------------------------------------------------------------------------
-- These are ATLAS patterns only, and that is a hard limit rather than a
-- choice. In this client `GetTexture()` on a texture declared in XML with
-- `file="Interface\\Common\\bluemenu-main"` does not return that path: it
-- returns the string "FileData ID 123456". So no pattern here can match a
-- texture PATH by string; file art is handled by S.ArtIsFile below.
--
-- Atlas names do come back as names, so atlas chrome can be matched here.
-- File-texture chrome (the blue communities panel, the GuildFrame sheet)
-- cannot be matched by name at all, and has to be handled by recognising
-- the FRAME it sits on. That is why every other skin does it that way.
S.ORNATE = {
    "%-nineslice", "nineslice%-",
    "%-border", "border%-", "%-corner", "%-edge",
    "%-shadow", "%-divider", "divider%-",
    "%-background", "%-bg$", "widebackground", "backplate",
    "%-banner", "toptilestreaks",
    "uiframe%-", "ui%-frame%-",
    "%-ring%-", "ring%-blue", "ring%-gold",
    "minimal%-scrollbar", "scrollbar%-",
    "common%-dropdown", "common%-search%-border",
    "%-textholder", "checkbox%-minimal",
    "questlog%-frame", "guildfinder%-card", "communities%-",
    -- Quest and book parchment. QuestBG-Parchment and its four accessibility
    -- variants are the sheet behind every quest detail, petition, guild
    -- registrar and item-text page (QuestTextContrast.lua:17-23).
    "questbg%-", "questdetailsbackgrounds",
    "groupfinder%-waitdot", "spinner_",
    "shadowoverlay%-", "charactercreate%-ring",
    -- The character window's own art (Camelot CharacterFrame.xml and
    -- PaperDollFrame.xml): the stat header banners, the frame round every
    -- equipment slot, the stone backdrop, the dividers and scroll line, the
    -- item level plate, the sidebar tabs' frame; the stat pane's inside
    -- border; the side tabs down a window's edge (LargeSideTabButtonTemplate,
    -- whose selected and hover states the sideTab part follows).
    "ui%-character%-info%-title", "ui%-character%-info%-gearslot",
    "ui%-character%-info%-stat%-stonebg", "ui%-character%-info%-scrollline",
    "ui%-character%-info%-itemlevel%-bounce", "ui%-character%-info%-stattab",
    "common%-insideframe", "common%-framedivider", "common%-sidetab",
    -- The settings panel's inner frame, its page divider and its expandable
    -- section bars (the settingsExpand part draws those).
    "options_innerframe", "options_horizontaldivider", "options_listexpand",
}

--------------------------------------------------------------------------------
--  File chrome. Matching against the STRING GetTexture() returns never
--  works, because it is never the path. S.ArtIsFile resolves a path through a scratch texture of our own and
--  compares what the client gives back for both sides, so the path never has
--  to be parsed and the list works.
--
--  The survey counts how often each file is used on a decorative layer;
--  these are the heavy ones. Curate as carefully as the atlas list above:
--  a file here mutes EVERY texture drawn from that sheet. Deliberately NOT
--  here, and do not add them: Interface\TargetingFrame\UI-StatusBar (bar
--  fills are content), UI-Durability-Icons, WhiteIconFrame, UI-EmptySlot
--  (icons and item slots), and anything under Interface\Glues (login screen)
--  or Interface\Tooltips (EvermoreUI_Tooltips owns those).
--------------------------------------------------------------------------------
S.ORNATE_FILES = {
    -- window and panel tiles
    "Interface\\FrameGeneral\\UI-Background-Rock",
    "Interface\\FrameGeneral\\UI-Background-Marble",
    "Interface\\DialogFrame\\UI-DialogBox-Background",
    "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    "Interface\\DialogFrame\\UI-DialogBox-Border",
    -- control borders
    "Interface\\Common\\Common-Input-Border",
    "Interface\\Common\\UI-Goldborder",
    "Interface\\Buttons\\UI-Button-Borders",
    "Interface\\Buttons\\UI-Silver-Button-Up",
    -- per-window sheets that are chrome end to end
    "Interface\\MailFrame\\MailItemBorder",
    "Interface\\GuildFrame\\GuildFrame",
    "Interface\\GuildBankFrame\\Corners",
    "Interface\\TutorialFrame\\UI-TUTORIAL-FRAME",
    "Interface\\AchievementFrame\\UI-Achievement-Header",
    "Interface\\AchievementFrame\\UI-Achievement-ProgressBar-Border",
    "Interface\\Calendar\\CalendarBackground",
    "Interface\\FriendsFrame\\WhoFrame-ColumnTabs",
    "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar",
    "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder",
    -- the equipment flyout's backing and the ring it puts round its slot
    "Interface\\PaperDollInfoFrame\\UI-GearManager-Flyout",
    "Interface\\PaperDollInfoFrame\\UI-GearManager-ItemButton-Highlight",
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar",
    "Interface\\SpellBook\\SpellBook-SkillLineTab",
    "Interface\\Store\\Store-Main",
}

--- Is this region decoration, by the two lists above?
---
--- The same answer S.ArtIs and S.ArtIsFile would give pattern by pattern,
--- read once. That loop asked the client for the region's atlas and texture
--- twice per pattern, 118 pcalled calls and 37 lowercased copies for every
--- texture the walk passed, and the walk passes every texture on every
--- object each time a window opens: most of the 40 to 100ms a re-walk of the
--- character window cost, with nothing left to dress.
---
--- The verdict is kept per piece of art (atlas and texture together), not
--- per region, so a pooled texture that comes back holding different art is
--- judged afresh. The lists never change after load.
local verdicts = {}    -- atlas .. "\0" .. texture -> true / false
local fileIds          -- the resolved ids of S.ORNATE_FILES, as a set

local function FileIds()
    if fileIds then return fileIds end
    local set = {}
    for _, path in ipairs(S.ORNATE_FILES) do
        local id = S.TexID(path)
        if id then set[id] = true end
    end
    fileIds = set
    return set
end

local function IsOrnate(region)
    if type(region) ~= "table" then return false end
    local atlas, tex
    if region.GetAtlas then
        local ok, a = pcall(region.GetAtlas, region)
        if ok and type(a) == "string" and a ~= "" then atlas = a end
    end
    if region.GetTexture then
        local ok, t = pcall(region.GetTexture, region)
        if ok and t ~= nil and t ~= "" then tex = t end
    end
    if not atlas and tex == nil then return false end
    local key = (atlas or "") .. "\0" .. tostring(tex)
    local hit = verdicts[key]
    if hit ~= nil then return hit end
    local yes = false
    local la = atlas and atlas:lower()
    local lt = type(tex) == "string" and tex:lower() or nil
    for _, pattern in ipairs(S.ORNATE) do
        if (la and la:find(pattern)) or (lt and lt:find(pattern)) then yes = true; break end
    end
    -- A file only counts on a region with no atlas: dozens of atlases share
    -- one sheet, as S.ArtIsFile explains.
    if not yes and not atlas and tex ~= nil and FileIds()[tex] then yes = true end
    verdicts[key] = yes
    return yes
end
S.IsOrnate = IsOrnate

--------------------------------------------------------------------------------
--  0. Backdrop input      an EditBox that borrows the tooltip's backdrop
--      (TooltipBackdropTemplate): the static pop-ups' text field
--      (StaticPopupTemplate's EditBox, AutoCompleteEditBoxTemplate plus
--      TooltipBackdropTemplate). The tooltip part below claims anything with a
--      tooltip layout and stops, so the pop-up's field was left with no box at
--      all. Claimed first, as an input.
--------------------------------------------------------------------------------
R{
    name = "backdropInput",
    type = "EditBox",
    layout = { "TooltipDefaultLayout", "TooltipMixedLayout" },
    paint = function(e, p)
        p:Fade()
        p:FadeSlice()
        p:Fill("surfaceSunk")
        p:Border("borderStrong")
        -- The pop-up's field is user-scaled (UserScaledFrameTemplate) and
        -- centred, so its edges land on part pixels, and an unsnapped
        -- one-pixel line there can round away: the right edge did. These are
        -- still, so the renderer's snapping is only a gain.
        local rec = EV.Pixel:EdgesOf(e)
        for _, t in ipairs(rec and rec.edges or {}) do
            EV.Pixel.KeepSnap(t, true)
            if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(true) end
            if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
        end
        p:States(LOOK.input, { label = e })
        if e.Instructions then p:Label(e.Instructions, LOOK.input.rest.placeholder) end
        p:TextPad(LOOK.input.pad, LOOK.input.pad)
    end,
}

--------------------------------------------------------------------------------
--  0a. Tooltips           layoutType Tooltip*, 48 templates
--      CLAIMED AND LEFT ALONE, on purpose. EvermoreUI_Tooltips already skins
--      GameTooltip, the shopping tooltips, ItemRefTooltip and the shared
--      backdrop, including fading their NineSlice. Before this part existed
--      the `window` fingerprint (NineSlice, nothing else) claimed every one
--      of them as a window and painted surface0 over the top, so two of our
--      own addons were drawing the same frames. `stop` also halts the walk
--      here, so nothing inside a tooltip is dressed either.
--------------------------------------------------------------------------------
R{
    name = "tooltip",
    layout = { "TooltipDefaultLayout", "TooltipMixedLayout", "TooltipGluesLayout",
               "ChatBubble" },
    stop = true,
    paint = function() end,
}

--------------------------------------------------------------------------------
--  0b. Slider             UISliderTemplate and friends
--      Also claimed before `window` could have it. A slider has a NineSlice
--      (its track is one), so the old fingerprint painted sliders as windows:
--      a flat surface0 box with a border where a groove should be.
--------------------------------------------------------------------------------
R{
    name = "slider",
    type = "Slider",
    -- `type = "Slider"` alone is NOT a fingerprint, and Register is right to
    -- refuse it. Classic implements scroll bars as Sliders too: 11 of this
    -- client's 18 Slider templates are scroll bars (UIPanelScrollBarTemplate,
    -- the Hybrid family, MinimalScrollBarTemplate). Painting those as a
    -- slider groove would be exactly the mistake the CheckButton part made.
    --
    -- The split is clean and comes from Blizzard's own XML: a real slider
    -- attaches its thumb as `Thumb`, a scroll bar as `ThumbTexture` or
    -- `thumbTexture`, and never both. The legacy scroll bars are picked up
    -- by scrollBarLegacy below.
    keys = { "Thumb" },
    paint = function(sl, p)
        p:Fade()
        p:FadeSlice()
        local groove = LOOK.slider.groove
        p:Fill(groove.fill)
        p:Border(groove.edge)
        local thumb = sl.GetThumbTexture and select(2, pcall(sl.GetThumbTexture, sl))
        if thumb and thumb.SetColorTexture then
            if thumb.SetAtlas then pcall(thumb.SetAtlas, thumb, nil) end
            local function Paint(t) t:SetColorTexture(T.C4(T.Resolve(LOOK.slider).thumb)) end
            Paint(thumb)
            T.Watch(thumb, Paint)
        end
    end,
}

--------------------------------------------------------------------------------
--  1. Close button        UIPanelCloseButton, 48 inherits (+27 NoScripts)
--     keys: Left/Middle/Right/Text + corners; normal atlas RedButton-Exit
--     Tried first, because it shares Left/Middle/Right/Text with a panel
--     button and would otherwise be claimed as one.
--------------------------------------------------------------------------------
R{
    name = "closeButton",
    type = "Button",
    art  = { normal = "redbutton%-exit" },
    paint = function(b, p)
        p:Fade()
        S.Blank(b)
        p:Fill("surface2")
        p:Glyph("close", LOOK.close.glyphSize, "textMuted")
        p:States(LOOK.close)
    end,
}

--------------------------------------------------------------------------------
--  1b. Maximise and minimise. Same RedButton art family as the close
--      button, different atlas, so it needs its own fingerprint or it
--      stays a red block next to our flat X.
--------------------------------------------------------------------------------
R{
    name = "maxMin",
    type = "Button",
    -- The patterns here were wrong and matched NOTHING in this client, which
    -- is why the world map kept a red Blizzard expand button on an otherwise
    -- skinned window. MaximizeMinimizeButtonFrameTemplate uses the atlases
    -- RedButton-Expand and RedButton-Condense; the minicondense/maximize/
    -- minimize names are from a different client. Checked against the
    -- manifest, not guessed, and the others are kept as fallbacks.
    test = function(b)
        if type(b.GetNormalTexture) ~= "function" then return false end
        local ok, t = pcall(b.GetNormalTexture, b)
        if not (ok and t) then return false end
        return S.ArtIs(t, "redbutton%-expand") or S.ArtIs(t, "condense")
            or S.ArtIs(t, "uitools%-icon%-%a-size")
            or S.ArtIs(t, "%-maximize") or S.ArtIs(t, "%-minimize")
    end,
    paint = function(b, p)
        p:Fade()
        S.Blank(b)
        p:Fill("surface2")
        -- Our own maximise/minimise glyphs, which have been sitting unused
        -- in Media since they were drawn. This used to build the icon out of
        -- two chevron.png textures rotated onto a diagonal, which is
        -- rebuilding a control we only needed to re-skin.
        local ok, t = pcall(b.GetNormalTexture, b)
        local shrink = ok and t and (S.ArtIs(t, "condense") or S.ArtIs(t, "%-minimize"))
        local d = S.D(b)
        if not d.icon then
            d.icon = S.Ours(b:CreateTexture(nil, "OVERLAY", nil, 7))
            d.icon:SetPoint("CENTER")
            d.icon:SetSize(10, 10)
        end
        d.icon:SetTexture(S.MEDIA .. (shrink and "minimise" or "maximise") .. ".png")
        p:States(LOOK.buttonGhost, { glyph = d.icon })
    end,
}

--------------------------------------------------------------------------------
--  1c. Reset button       UIResetButtonTemplate: the red disc with a yellow X
--     Shown on a filter button while any filter is off its default (the map's
--     filter button, the auction house, the collections). A small box of ours
--     with the close glyph in copper, red under the mouse (LOOK.reset). The
--     button is 23px square; the box is drawn inside it, centred, at the
--     Look's size, so the hit area stays Blizzard's.
--------------------------------------------------------------------------------
R{
    name = "resetButton",
    type = "Button",
    art  = { normal = "auctionhouse%-ui%-filter%-redx" },
    paint = function(b, p)
        local RL = LOOK.reset
        S.Blank(b)
        p:Fade()
        local d = S.D(b)
        if not d.box then
            d.box = S.Ours(CreateFrame("Frame", nil, b))
            d.box:SetSize(RL.box, RL.box)
            d.box:SetPoint("CENTER")
            d.box:EnableMouse(false)
        end
        -- Over whatever it sits on (the filter button's corner): a badge.
        local okP, par = pcall(b.GetParent, b)
        if okP and par and par.GetFrameLevel then b:SetFrameLevel(par:GetFrameLevel() + 5) end
        p:Fill(RL.rest.fill, nil, nil, d.box)
        p:Border(RL.rest.edge, nil, d.box)
        p:Glyph("close", RL.glyphSize, RL.rest.glyph)
        -- The glyph lives on the box, over its solid fill: on the button it
        -- sat under the box (a child frame draws over its parent), and the
        -- reset showed as an empty square.
        local glyph = S.D(b).glyph
        if glyph and glyph:GetParent() ~= d.box then
            glyph:SetParent(d.box)
            glyph:SetDrawLayer("OVERLAY", 7)
            glyph:ClearAllPoints()
            glyph:SetPoint("CENTER", d.box, "CENTER")
        end
        local boxFill = S.D(d.box).fill
        p:States(RL, { edgesOn = d.box, after = function(r)
            if boxFill and r.fill then boxFill:SetColorTexture(T.C4(r.fill)) end
        end })
    end,
}

--------------------------------------------------------------------------------
--  1d. Page button        the spellbook-style previous and next page arrows
--     PagingControlsPrev/NextPageButtonTemplate (Blizzard_PagedContent: the
--     spellbook, collections, housing) and every older window that reuses the
--     same art on a bare Button (mail, merchant, the pet stable). A 32x32
--     button whose Normal/Pushed/Disabled textures are the gold
--     UI-SpellbookIcon-PrevPage / -NextPage files, with UI-Common-MouseHilight
--     over them. Only the file says what it is, so that is the print.
--
--     Ours is the button Look in a box of LOOK.pager.box, centred in
--     Blizzard's 32px hit area (the paging layout frames measure the button,
--     so the button keeps its size), with our chevron. Disabled at the first
--     and last page comes from Blizzard's own SetEnabled.
--------------------------------------------------------------------------------
local PAGE_FILES = {
    prev = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    next = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
}

local function PageDir(b)
    local ok, n = pcall(b.GetNormalTexture, b)
    if not (ok and n) then return nil end
    if S.ArtIsFile(n, PAGE_FILES.prev) then return "left" end
    if S.ArtIsFile(n, PAGE_FILES.next) then return "right" end
    return nil
end

R{
    name = "pageButton",
    type = "Button",
    test = function(b)
        -- The character window's pane toggle wears the same art, swapped in
        -- Lua as the pane folds (CharacterFrame.lua, SetRightPaneCollapsed);
        -- its pack draws it, pointing whichever way the pane will go.
        local cf = _G.CharacterFrame
        if cf and b == rawget(cf, "RightPaneToggleButton") then return false end
        return type(b.GetNormalTexture) == "function" and PageDir(b) ~= nil
    end,
    paint = function(b, p)
        local dir = PageDir(b)
        local PL = LOOK.pager
        S.Blank(b)
        p:Fade()
        -- A label some windows hang on the button ("Prev"/"Next" on the mail
        -- inbox) is a loose FontString, not the button's own: the chevron says it.
        for _, r in ipairs(S.Regions(b)) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and not S.ours[r] then r:SetAlpha(0) end
        end
        local d = S.D(b)
        if not d.box then
            d.box = S.Ours(CreateFrame("Frame", nil, b))
            d.box:SetPoint("CENTER")
            d.box:EnableMouse(false)
            d.chev = S.Ours(T.Chevron(d.box, PL.chevron))
            d.chev:SetPoint("CENTER")
        end
        local side = math.min(PL.box, math.floor(S.Num(b:GetWidth()) or PL.box),
                                      math.floor(S.Num(b:GetHeight()) or PL.box))
        d.box:SetSize(side, side)
        d.chev:Point(dir or "right")
        p:Fill(LOOK.button.rest.fill, nil, nil, d.box)
        p:Border(LOOK.button.rest.edge, nil, d.box)
        local boxFill = S.D(d.box).fill
        p:States(LOOK.button, { edgesOn = d.box, chev = d.chev, after = function(r)
            if boxFill and r.fill then boxFill:SetColorTexture(T.C4(r.fill)) end
        end })
    end,
}

--------------------------------------------------------------------------------
--  2. Bottom tab          PanelTabButtonTemplate, 19 inherits
--     keys: Left/Middle/Right + LeftActive/MiddleActive/RightActive
--------------------------------------------------------------------------------
R{
    name = "panelTab",
    type = "Button",
    keys = { "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive" },
    paint = function(tab, p)
        -- TabSystem tabs (the spellbook's school tabs, TabSystemButtonArtTemplate
        -- in Blizzard_SharedXML/Shared/TabSystem) carry their content in `Icon`,
        -- textured from Lua by TabSystemButtonMixin:Init. The sweep would mute
        -- it and leave an empty box, so it is kept.
        p:Fade(nil, { tab.Icon })
        p:FadeKeys("LeftActive", "MiddleActive", "RightActive",
                   "LeftHighlight", "MiddleHighlight", "RightHighlight",
                   "LeftDisabled", "MiddleDisabled", "RightDisabled")
        p:Fill("surface1")
        p:Border("border")
        p:Label(tab.Text, "textMuted")
        local d = S.D(tab)

        -- Undo Blizzard's selected/deselected label offset. See S.HookPanelTabs.
        local function Seat()
            if tab.Text then p:Reseat(tab.Text, { { "CENTER", 0, 0 } }) end
        end
        d.Seat = Seat

        local function Sync()
            -- PanelTemplates keeps the answer on the PARENT:
            -- PanelTemplates_SetTab does frame.selectedTab = id
            -- (SharedUIPanelTemplates.lua:439). tab.isDisabled marks a greyed
            -- tab, which is neither selected nor ordinary. Enabled state is
            -- deliberately LAST: the selected tab is Disable()d, but so is a
            -- greyed one, so reading it first would light up dead tabs.
            local on, off
            if tab.isDisabled then
                off = true
            else
                local par = tab.GetParent and tab:GetParent()
                if par then
                    if par.selectedTab ~= nil and type(tab.GetID) == "function" then
                        local ok, id = pcall(tab.GetID, tab)
                        if ok then on = (par.selectedTab == id) end
                    end
                    if on == nil and par.selectedTabID ~= nil and tab.tabID ~= nil then
                        on = par.selectedTabID == tab.tabID
                    end
                end
                if on == nil then on = tab.isSelected end
                if on == nil and type(tab.GetChecked) == "function" then
                    local okc, c = pcall(tab.GetChecked, tab); on = okc and c or nil
                end
                if on == nil and type(tab.IsEnabled) == "function" then
                    local oke, enabled = pcall(tab.IsEnabled, tab)
                    if oke then on = not enabled end
                end
            end
            d.on, d.disabled = on and true or false, off and true or false
            local r = T.Resolve(LOOK.tab, d)
            if d.fill then d.fill:SetColorTexture(T.C4(r.fill)) end
            -- A pack that draws its own box in the tab (the spellbook's
            -- school tabs) sets `edgeless`, and the tab's border stays down.
            if r.edge and not d.edgeless then T.SetEdge(tab, r.edge) end
            if tab.Text then tab.Text:SetTextColor(T.C4(r.text)) end
        end
        d.Sync = Sync
        S.HookPanelTabs()
        p:Hook("OnEnter", function() d.hover = true; Sync() end)
        p:Hook("OnLeave", function() d.hover = false; Sync() end)
        S.Own(Sync, tab, tab.Text)
        p:Hook("OnShow", function() Seat(); Sync() end)
        p:Hook("OnClick", function() C_Timer.After(0, function() Seat(); Sync() end) end)
        Seat()
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  3. Stretch button      UIMenuButtonStretchTemplate, 18 inherits
--------------------------------------------------------------------------------
R{
    name = "stretchButton",
    type = "Button",
    keys = { "TopLeft", "TopMiddle", "TopRight", "MiddleLeft", "MiddleMiddle",
             "MiddleRight", "BottomLeft", "BottomMiddle", "BottomRight" },
    paint = function(b, p)
        p:Fade()
        p:Fill("surface2")
        p:Border("borderStrong")
        p:Label(b.Text)
        p:States(LOOK.button, { label = b.Text })
    end,
}

--------------------------------------------------------------------------------
--  4. Panel button        UIPanelButtonTemplate, 284 inherits
--     The single biggest win in the game's UI.
--------------------------------------------------------------------------------
R{
    name = "panelButton",
    type = "Button",
    keys = { "Left", "Middle", "Right", "Text" },
    paint = function(b, p)
        p:Fade()
        p:Fill("surface2")
        p:Border("borderStrong")
        p:Label(b.Text)
        p:States(LOOK.button, { label = b.Text })
    end,
}

--------------------------------------------------------------------------------
--  4c. Three-slice button ThreeSliceButtonTemplate, 35 templates: the big red buttons
--     The game menu's, and BigRedThreeSliceButtonTemplate's whole family
--     (SharedButtonTemplate and its sizes, the gold-red ones, talents, end of
--     match). Left, Center and Right, no Middle, so panelButton never saw
--     them, and their art is set from Lua (ThreeSliceButtonMixin:UpdateButton,
--     "128-RedButton-Left" and so on) on show, enable, disable and every
--     press. That only swaps the atlas; the alpha we set stays, so the art
--     stays down.
--
--     Fingerprinted on atlasName, the KeyValue every one of them carries:
--     UpdateButton builds its atlas names from it, so Blizzard keeps it.
--     The gold-red kit is their primary button, and it gets ours.
--------------------------------------------------------------------------------
R{
    name = "threeSlice",
    type = "Button",
    keys = { "Left", "Center", "Right" },
    test = function(b) return type(b.atlasName) == "string" end,
    paint = function(b, p)
        S.Blank(b)          -- the highlight atlas InitButton sets
        p:Fade()
        local look = b.atlasName:lower():find("goldred", 1, true) and LOOK.buttonPrimary or LOOK.button
        local r = look.rest
        p:Fill(r.fill ~= "none" and r.fill or "surface2")
        p:Border(r.edge ~= "none" and r.edge or "borderStrong")
        local fs = b.GetFontString and b:GetFontString()
        p:Label(fs)
        p:States(look, { label = fs })
    end,
}

--------------------------------------------------------------------------------
--  4b. Radio button       UIRadioButtonTemplate
--      A radio button is a CheckButton whose art is a FILE
--      (Interface\Buttons\UI-RadioButton), so it was invisible to the old
--      atlas-only fingerprint. It needs its own part rather than being folded
--      into the check box: a radio drawn as a square tick box tells the user
--      they can pick several when they can pick one. Registered first so the
--      check box cannot claim it.
--------------------------------------------------------------------------------
R{
    name = "radioButton",
    type = "CheckButton",
    file = { normal = "Interface\\Buttons\\UI-RadioButton" },
    paint = function(b, p)
        S.Blank(b)
        p:Fade()
        local d = S.D(b)
        -- Same reasoning as checkButton: the rect is the hit area. A radio
        -- ring is drawn at the check box's size so a column of mixed
        -- controls lines up.
        local RL = LOOK.radio
        local RING = RL.ring
        if not d.ring then
            d.ringFill = S.Ours(b:CreateTexture(nil, "BORDER"))
            d.ringFill:SetTexture(T.MEDIA .. "circle.png")
            d.ringFill:SetPoint("CENTER")
            d.ring = S.Ours(b:CreateTexture(nil, "ARTWORK"))
            d.ring:SetTexture(T.MEDIA .. "ring.png")
            d.ring:SetPoint("CENTER")
            d.dot = S.Ours(b:CreateTexture(nil, "OVERLAY"))
            d.dot:SetTexture(T.MEDIA .. "circle.png")
            d.dot:SetPoint("CENTER")
        end
        local side = math.min(RING, math.floor(S.Num(b:GetWidth()) or RING),
                                    math.floor(S.Num(b:GetHeight()) or RING))
        if side < 8 then side = 8 end
        d.ring:SetSize(side, side)
        d.ringFill:SetSize(side - 2, side - 2)
        local dot = math.max(math.floor(side * RL.dot / RL.ring + 0.5), 3)
        d.dot:SetSize(dot, dot)
        local function Sync()
            local on = type(b.GetChecked) == "function" and select(2, pcall(b.GetChecked, b)) or false
            d.on = on and true or false
            local r = T.Resolve(RL, d)
            d.ring:SetVertexColor(T.C4(r.ring))
            d.ringFill:SetVertexColor(T.C4(r.fill))
            if r.dot then d.dot:SetVertexColor(T.C4(r.dot)) end
            d.dot:SetShown(d.on)
        end
        d.Sync = Sync
        p:After("SetChecked", Sync)
        p:Hook("OnClick", Sync)
        p:Hook("OnShow", Sync)
        p:Hook("OnEnter", function() d.hover = true; Sync() end)
        p:Hook("OnLeave", function() d.hover = false; Sync() end)
        p:Label(b.Text)
        S.Own(Sync, d.ring)
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  5. Check button        UICheckButtonTemplate, 28 inherits
--------------------------------------------------------------------------------
R{
    name = "checkButton",
    type = "CheckButton",
    -- Only a real check box. Blizzard uses CheckButton for an enormous
    -- amount that is not one: quest log tracking rows, community role
    -- icons, action buttons. Matching the type alone blanked all of
    -- their icons and drew a tick box in place of each. So: the normal
    -- texture has to be the check box atlas, and nothing else counts.
    -- The atlas patterns alone matched nothing on the templates that
    -- matter. UICheckButtonTemplate, which is 28 of the inherits, draws
    -- Interface\\Buttons\\UI-CheckBox-Up: a FILE, not an atlas, so no
    -- name pattern could ever see it. Both are checked now.
    artOrFile = {
        normal = {
            atlas = { "checkbox%-minimal", "checkbox%-?%d*$", "common%-checkbox" },
            files = { "Interface\\Buttons\\UI-CheckBox-Up" },
        },
    },
    -- A check button's rect is its HIT AREA, not its box. UICheckButtonTemplate
    -- is 32x32 and the auction house's Buyout Mode button is 36x36
    -- (Blizzard_AuctionHouseItemSellFrame.xml:7), while UI-CheckBox-Up draws a
    -- visible box of about 20 inside all that transparent padding. Painting
    -- the rect gave a 36px orange slab. So the box is our own house size,
    -- centred in whatever rect Blizzard gave it -- BOX 16 with a 12 tick, the
    -- same numbers as U.Checkbox in EvermoreUI/UI/Toggles.lua, so a skinned
    -- check box and one of our own read as the same control.
    paint = function(b, p)
        S.Blank(b)
        p:Fade()
        local d = S.D(b)
        local CL = LOOK.checkbox
        local BOX = CL.box
        if not d.boxFrame then
            -- A frame rather than a bare texture, so the border has corners
            -- to anchor to that are the box's and not the button's.
            d.boxFrame = S.Ours(CreateFrame("Frame", nil, b))
            d.boxFrame:SetPoint("CENTER")
            d.box = S.Ours(d.boxFrame:CreateTexture(nil, "ARTWORK"))
            d.box:SetAllPoints(d.boxFrame)
            d.tick = S.Ours(d.boxFrame:CreateTexture(nil, "OVERLAY"))
            d.tick:SetTexture(T.MEDIA .. "check.png")
            d.tick:SetPoint("CENTER")
        end
        -- Never wider than the button, for the few that are genuinely small.
        local side = math.min(BOX, math.floor(S.Num(b:GetWidth()) or BOX),
                                   math.floor(S.Num(b:GetHeight()) or BOX))
        if side < 8 then side = 8 end
        d.boxFrame:SetSize(side, side)
        d.tick:SetSize(side - (CL.box - CL.tick), side - (CL.box - CL.tick))
        p:Border("borderStrong", nil, d.boxFrame)
        local function Sync()
            local on = type(b.GetChecked) == "function" and select(2, pcall(b.GetChecked, b)) or false
            d.on = on and true or false
            local r = T.Resolve(CL, d)
            d.box:SetColorTexture(T.C4(r.fill))
            T.SetEdge(d.boxFrame, r.edge)
            if r.glyph then d.tick:SetVertexColor(T.C4(r.glyph)) end
            d.tick:SetShown(d.on)
        end
        d.Sync = Sync
        p:After("SetChecked", Sync)
        p:Hook("OnClick", Sync)
        p:Hook("OnShow", Sync)
        p:Hook("OnEnter", function() d.hover = true; Sync() end)
        p:Hook("OnLeave", function() d.hover = false; Sync() end)
        p:Label(b.Text)
        S.Own(Sync, d.box, d.boxFrame)
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  6. Dropdown            WowStyle1DropdownTemplate, 76 inherits
--------------------------------------------------------------------------------
R{
    name = "dropdown",
    keys = { "Arrow", "Background", "Text" },
    paint = function(dd, p)
        p:Fade()
        S.Mute(dd.Arrow)
        S.Mute(dd.Background)
        p:Fill("surface2")
        p:Border("borderStrong")
        p:Label(dd.Text)
        local d = S.D(dd)
        if not d.chev and T.Chevron then
            -- T.Chevron hands back a frame holding two rotated lines, so
            -- it is pointed with its own Point(), not SetRotation.
            d.chev = S.Ours(T.Chevron(dd, LOOK.dropdown.chevron))
            d.chev:SetPoint("RIGHT", dd, "RIGHT", -6, 0)
            d.chev:Point("down")
        end
        -- Open is Blizzard's own state (DropdownButtonMixin:IsMenuOpen), and
        -- it tells us when it changes through OnMenuOpened / OnMenuClosed.
        p:States(LOOK.dropdown, {
            label = dd.Text, chev = d.chev,
            on = function() return type(dd.IsMenuOpen) == "function" and dd:IsMenuOpen() end,
        })
        p:After("OnMenuOpened", function() if d.Repaint then d.Repaint() end end)
        p:After("OnMenuClosed", function() if d.Repaint then d.Repaint() end end)
    end,
}

--------------------------------------------------------------------------------
--  6b. Icon dropdown      a DropdownButton that is only an icon
--     UIPanelArrowDropdownButtonTemplate, UIPanelIconDropdownButtonTemplate
--     (the quest log's settings cog) and the world map's filter button
--     (WorldMapTrackingOptionsButtonTemplate). Two of them draw their icon
--     from common-dropdown-a-button, which S.ORNATE rightly takes down on a
--     real dropdown, where it is the arrow the dropdown part replaces, and
--     wrongly took off these, where it is the whole button: the map's filter
--     button was invisible, its red reset X floating on its own.
--
--     An arrow becomes our chevron. Any other icon keeps its shape, in our
--     text colours. A button big enough to be a button (the map's, 32px) is
--     drawn as one; a small one is a ghost that boxes on hover.
--------------------------------------------------------------------------------
R{
    name = "iconDropdown",
    -- No type: the XML says <DropdownButton>, but in game the object is a
    -- plain Button (the map's filter button reported "Button" and went
    -- unclaimed with type = "DropdownButton", though the survey's stand-ins,
    -- built from the tag, matched). The icon and its atlas are the print.
    keys = { "Icon" },
    artOrFile = { Icon = { atlas = { "common%-dropdown%-a%-button", "questlog%-icon%-setting" } } },
    paint = function(b, p)
        local d = S.D(b)
        local arrow = S.ArtIs(b.Icon, "common%-dropdown%-a%-button")
        local big = (S.Num(b:GetWidth()) or 0) >= 24
        local look = big and LOOK.button or LOOK.buttonGhost
        S.Blank(b)
        p:Fill("surface2")
        p:Border("borderStrong")
        if arrow then
            p:Fade()
            if not d.chev then
                d.chev = S.Ours(T.Chevron(b, big and 5 or 4))
                d.chev:SetPoint("CENTER")
                d.chev:Point("down")
            end
            p:States(look, { chev = d.chev })
        else
            p:Fade(nil, { b.Icon })
            if b.Icon.SetDesaturated then b.Icon:SetDesaturated(true) end
            p:States(look, { glyph = b.Icon })
        end
    end,
}

--------------------------------------------------------------------------------
--  7. Search box          SearchBoxTemplate, 23 inherits
--
--     Blizzard's numbers, from InputBoxTemplates.xml:
--         searchIcon   10x10, LEFT x="1" y="-1"
--         clearButton  17x17, RIGHT x="-3"
--         Instructions TOPLEFT x="16" / BOTTOMRIGHT x="-20"
--         TextInsets   left 16, right 20
--
--     Every one of those offsets is measured from the frame RECT, while the
--     art they were tuned against sits 5px OUTSIDE it (InputBoxVisualTemplate
--     anchors Left at LEFT x="-5"). Against Blizzard's border the icon reads
--     6px in. Against our 1px border on the rect it reads 1px in, hard up to
--     the line, with the placeholder crowding it.
--
--     So the furniture is re-seated for our border: 6px of clear space, then
--     the 10px icon, then 5px, then the text. Through Painter:Reseat, which
--     can only move a region of this control, to this control, on the edge
--     Blizzard already used. See the note on it in Core.lua.
--------------------------------------------------------------------------------
local SEARCH_PAD   = LOOK.input.pad   -- clear space inside our border
local SEARCH_ICON  = 10   -- Blizzard's icon size
local SEARCH_GAP   = 5    -- icon to text
local SEARCH_TEXT  = SEARCH_PAD + SEARCH_ICON + SEARCH_GAP   -- 21
local SEARCH_RIGHT = 24   -- clears the 17px clear button and its inset glyph

R{
    name = "searchBox",
    type = "EditBox",
    keys = { "searchIcon", "clearButton" },
    paint = function(e, p)
        p:Fade()
        p:Fill("surfaceSunk")
        p:Border("borderStrong")
        p:Label(nil, false)
        -- The glass follows the Look like ours: the edge's colour while
        -- focused, the glyph's otherwise.
        local glass = e.searchIcon
        p:States(LOOK.input, { label = e, after = function(r)
            if glass then glass:SetVertexColor(T.C4(S.D(e).focus and r.edge or r.glyph)) end
        end })

        -- The magnifying glass is content, not chrome: recolour, never hide.
        if e.searchIcon then
            S.D(e.searchIcon).muted = nil
            e.searchIcon:SetAlpha(1)
            p:Reseat(e.searchIcon, { { "LEFT", SEARCH_PAD, 0 } })
        end

        -- The clear button's own art is Blizzard's little x; keep it, move it
        -- off our border and mute it to match.
        if e.clearButton then
            local icon = e.clearButton.Icon
            if icon then
                icon:SetVertexColor(T.C4(T.Resolve(LOOK.input).glyph))
                S.D(icon).muted = nil
                icon:SetAlpha(1)
            end
            p:Reseat(e.clearButton, { { "RIGHT", -SEARCH_PAD, 0 } })
        end

        -- The placeholder is a two-point FontString, so both corners move or
        -- it loses its width.
        if e.Instructions then
            p:Label(e.Instructions, LOOK.input.rest.placeholder)
            p:Reseat(e.Instructions, { { "TOPLEFT", SEARCH_TEXT, 0 },
                                       { "BOTTOMRIGHT", -SEARCH_RIGHT, 0 } })
        end

        -- And the typed text, which is laid out by insets rather than anchors.
        p:TextPad(SEARCH_TEXT, SEARCH_RIGHT)
    end,
}

--------------------------------------------------------------------------------
--  8. Input boxes         MoneyFrameEditBoxTemplate, then InputBoxTemplate
--                         (31 inherits, +2 Instructions)
--------------------------------------------------------------------------------
-- The coin is 13x13 on one template and 12x14 on the other. Right inset has
-- to clear our padding, the coin and a gap, or the digits run under it.
local COIN       = 14                                 -- the larger of 13 and 14
local COIN_LEFT  = SEARCH_PAD                         -- 6
local COIN_RIGHT = SEARCH_PAD + COIN + SEARCH_GAP     -- 25

--------------------------------------------------------------------------------
--  Money input boxes
--
--  Three edit boxes for gold, silver and copper, each carrying its own coin
--  icon. inputBox reached them first and opened with a blanket p:Fade(),
--  which mutes EVERY texture on the box: the border pieces we meant, and the
--  coin we did not. That is why the auction house buyout row read as three
--  empty boxes with nothing to say which was which. The widths are fine, and
--  are Blizzard's -- 190 wide split 77/49/49 with 6px gaps, gold taking the
--  remainder (Blizzard_MoneyFrame/Shared/MoneyInputFrame.xml:41-71).
--
--  There are TWO money box templates and they share nothing but the idea:
--
--    MoneyFrameEditBoxTemplate  coinAtlas  region "texture"  13x13 RIGHT -4
--      Mainline/MoneyInputFrame.xml, used by mail and trade.
--    LargeMoneyInputBoxTemplate iconAtlas  region "Icon"     12x14 RIGHT -10
--      Shared/MoneyInputFrame.xml, used by the auction house through
--      LargeMoneyInputFrameTemplate.
--
--  The first pass at this part fingerprinted coinAtlas only, read out of the
--  Mainline file, and so matched everything except the window it was written
--  for. Both are handled now.
--
--  Icon and Text are mutually exclusive: LargeMoneyInputBoxMixin:OnLoad hides
--  the Icon in colourblind mode and puts a g/s/c letter in Text instead. Seat
--  both, show neither by force.
--------------------------------------------------------------------------------
R{
    name = "moneyBox",
    type = "EditBox",
    test = function(e)
        return type(rawget(e, "iconAtlas")) == "string"
            or type(rawget(e, "coinAtlas")) == "string"
    end,
    paint = function(e, p)
        for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
            local r = S.Sub(e, suffix)
            if r and r.GetObjectType and r:GetObjectType() == "Texture" then S.Mute(r) end
        end
        p:Fill("surfaceSunk")
        p:Border("borderStrong")
        p:States(LOOK.input, { label = e })

        local function Keep(r)
            if type(r) ~= "table" or not r.SetAlpha then return end
            r:SetAlpha(1)
            S.D(r).muted = nil
            p:Reseat(r, { { "RIGHT", -COIN_LEFT, 0 } })
        end
        Keep(rawget(e, "Icon"))        -- LargeMoneyInputBoxTemplate
        Keep(rawget(e, "texture"))     -- MoneyFrameEditBoxTemplate

        for _, key in ipairs({ "Text", "label" }) do
            local fs = rawget(e, key)
            if type(fs) == "table" and fs.SetTextColor then
                p:Label(fs, "textMuted")
                p:Reseat(fs, { { "RIGHT", -COIN_LEFT, 0 } })
            end
        end

        p:TextPad(COIN_LEFT, COIN_RIGHT)
    end,
}

R{
    name = "inputBox",
    type = "EditBox",
    -- Both attachment styles. The parentKey form (e.Left) covers the modern
    -- templates; the global form (_G[name .. "Left"]) covers the older ones,
    -- which is most of the edit boxes in the mail, trade and guild windows.
    test = function(e)
        return S.Sub(e, "Left") ~= nil or S.Sub(e, "LeftTex") ~= nil
            or S.Sub(e, "MiddleTex") ~= nil
    end,
    paint = function(e, p)
        p:Fade()
        for _, suffix in ipairs({ "Left", "Middle", "Right", "LeftTex", "MiddleTex", "RightTex",
                                  "TopLeftTex", "TopTex", "TopRightTex",
                                  "BottomLeftTex", "BottomTex", "BottomRightTex" }) do
            local r = S.Sub(e, suffix)
            if r then
                if r.GetObjectType and r:GetObjectType() == "Texture" then S.Mute(r) else p:Fade(r) end
            end
        end
        p:Fill("surfaceSunk")
        p:Border("borderStrong")
        p:States(LOOK.input, { label = e })
        if e.Instructions then p:Label(e.Instructions, LOOK.input.rest.placeholder) end
        -- Same reasoning as the search box, without an icon to clear: their
        -- art was 5px outside the rect, ours is on it, so text that looked
        -- inset now sits on the line. TextPad only ever raises an inset, so a
        -- box that deliberately set a wider one keeps it.
        p:TextPad(SEARCH_PAD, SEARCH_PAD)
    end,
}

--------------------------------------------------------------------------------
--  9. Scroll bar          MinimalScrollBar, 107 inherits
--------------------------------------------------------------------------------
R{
    name = "scrollBar",
    keys = { "Track" },
    -- Begin, End and Middle sit on the Track and the Thumb inside it.
    -- Back and Forward are the steppers, which is what left
    -- minimal-scrollbar-arrow-top and -bottom on screen.
    test = function(bar)
        return type(bar.Track) == "table"
            and (type(bar.Track.Thumb) == "table" or type(bar.Back) == "table" or type(bar.Forward) == "table")
    end,
    paint = function(bar, p)
        p:Fade()
        -- The steppers used to be blanked and faded outright, which left two
        -- invisible but still clickable buttons at the ends of every scroll
        -- bar in the game. We are skinning a control, not deleting it: the
        -- arrow becomes one of our chevrons in our colours.
        for _, k in ipairs({ "Back", "Forward" }) do
            local step = bar[k]
            if type(step) == "table" then
                S.Blank(step)
                p:Fade(step)
                if type(step.Texture) == "table" then S.Mute(step.Texture) end
                local sd = S.D(step)
                if not sd.chev and T.Chevron and step.CreateTexture then
                    sd.chev = S.Ours(T.Chevron(step, LOOK.scrollStep.chevron))
                    sd.chev:SetPoint("CENTER")
                    sd.chev:Point(k == "Back" and "up" or "down")
                    S.StepperLook(step, sd)
                end
            end
        end
        local track = bar.Track
        p:Fade(track)
        for _, k in ipairs({ "Begin", "End", "Middle" }) do S.Mute(track[k]) end
        local d = S.D(bar)
        if not d.trackFill and track.CreateTexture then
            d.trackFill = S.Ours(track:CreateTexture(nil, "BACKGROUND"))
            d.trackFill:SetAllPoints(track)
        end
        if d.trackFill then
            local function Paint(t) t:SetColorTexture(T.C4(T.Resolve(LOOK.scrollbar).track)) end
            Paint(d.trackFill)
            T.Watch(d.trackFill, Paint)
        end
        local thumb = track.Thumb
        if thumb then
            for _, r in ipairs(S.Regions(thumb)) do S.Mute(r) end
            local td = S.D(thumb)
            if not td.fill and thumb.CreateTexture then
                td.fill = S.Ours(thumb:CreateTexture(nil, "ARTWORK"))
                td.fill:SetAllPoints(thumb)
            end
            -- The thumb is redrawn from its own texture keys on hover; ours
            -- follows it through the scroll bar Look.
            if td.fill then S.ThumbLook(thumb, td.fill) end
        end
    end,
}

--------------------------------------------------------------------------------
--  9c. Navigation bar    NavBarTemplate
--      The breadcrumb strip across the top of the world map, and the same
--      template in the encounter journal and character select.
--
--      Drawn ENTIRELY from file textures with TexCoords into two sheets,
--      Interface\HelpFrame\CS_HelpTextures and _Tile, plus a set of
--      UI-Frame-Inner* strips along its own edges. No atlas anywhere and no
--      distinguishing art, so the fingerprint is structural: overlay +
--      overflow + home is NavBarTemplate and nothing else.
--------------------------------------------------------------------------------
R{
    name = "navBar",
    keys = { "overlay", "overflow", "home" },
    paint = function(bar, p)
        p:Fade()                                   -- the tile strip
        p:FadeKeys("InsetBorderBottomLeft", "InsetBorderBottomRight",
                   "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight")
        if type(bar.overlay) == "table" then p:Fade(bar.overlay) end
        p:Surface("raised")
        S.HookNavBar()
        S.NavSeparators(bar)
    end,
}

--------------------------------------------------------------------------------
--  9d. Navigation crumb
--
--      Three different shapes wear this hat, which is what the first attempt
--      got wrong. Only the middle crumbs come from NavButtonTemplate:
--
--        home      declared INLINE in NavBarTemplate, with its own art
--                  (CS_HelpTextures plus a ShadowOverlay-Left) and no
--                  arrowUp/arrowDown at all. NavBar_Initialize is handed it
--                  as `self.home`, so it never goes near NavButtonTemplate.
--        overflow  likewise inline, a 44x30 DropdownButton, no text.
--        crumbs    CreateFrame("BUTTON", name, self, "NavButtonTemplate"),
--                  pooled through navList/freeButtons.
--
--      A fingerprint keyed on NavButtonTemplate's parentKeys therefore
--      claimed the crumbs and missed the home button, which is why "World"
--      kept a brown Blizzard tile while the zone crumbs went flat.
--
--      So the fingerprint is "I am a button belonging to a nav bar", which
--      is exact, covers all three, and cannot reach anything else.
--------------------------------------------------------------------------------
R{
    name = "navCrumb",
    type = "Button",
    test = function(b)
        if type(b.GetParent) ~= "function" then return false end
        local ok, bar = pcall(b.GetParent, b)
        if not (ok and type(bar) == "table") then return false end
        return type(rawget(bar, "overflow")) == "table"
           and type(rawget(bar, "home")) == "table"
           and type(rawget(bar, "overlay")) == "table"
    end,
    paint = function(b, p)
        S.Blank(b)
        p:Fade()
        -- selected is re-Shown by NavBar_CheckLength for the active crumb.
        -- Muting is alpha based, so a later Show leaves it invisible and we
        -- do not have to fight the rebuild.
        p:FadeKeys("arrowUp", "arrowDown", "selected")

        -- The home button's shadow sits on a $parent-named region with no
        -- parentKey, reachable only as the global.
        local shadow = S.Sub(b, "Left")
        if shadow then S.Mute(shadow) end

        p:Fill("surface1")
        p:Label(b.text, "textMuted")
        p:States(LOOK.buttonGhost, { label = b.text })

        -- No separator is drawn here. It belongs between two crumbs, so
        -- S.NavSeparators lays them out across the strip instead; see the
        -- note on it above.

        -- The drop-down arrow a crumb grows when it has children, and the
        -- overflow button's own arrow.
        local menu = b.MenuArrowButton
        if type(menu) == "table" then
            S.Blank(menu)
            p:Fade(menu)
            if type(menu.Art) == "table" then S.Mute(menu.Art) end
        end
        local arrowOn = (type(menu) == "table") and menu or
                        ((type(b.text) ~= "table") and b or nil)
        if arrowOn and not S.D(arrowOn).chev and T.Chevron then
            local cd = S.D(arrowOn)
            cd.chev = S.Ours(T.Chevron(arrowOn, 4))
            cd.chev:SetPoint("CENTER")
            cd.chev:Point("down")
            S.StepperLook(nil, cd)
        end
    end,
}

--------------------------------------------------------------------------------
--  9e. List header        ListHeaderVisualTemplate: the quest log's zone headers
--     A brown bar (common-button-list-collapseExpand) with a gold +/- at the
--     right. Ours: a flat bar, the title in gold, lighter under the mouse,
--     and our chevron for the +/-, down while open, right while collapsed.
--
--     Blizzard recolours the title on every enter and leave
--     (ListHeaderVisualMixin:CheckHighlightTitle) and swaps the +/- atlas and
--     the highlight in CollapseButtonMixin:UpdateCollapsedState, so ours are
--     put back after each, not fought.
--------------------------------------------------------------------------------
R{
    name = "listHeader",
    type = "Button",
    keys = { "CollapseButton" },
    art  = { normal = "common%-button%-list%-collapseexpand" },
    paint = function(h, p)
        S.Blank(h)
        p:Fade()
        p:Fill("surface2")
        p:Border("border")
        local title = h.ButtonText or h.Text
        if title then p:Label(title, false, true) end
        local d = S.D(h)
        local function Over()
            local fn = h.IsMouseMotionFocus or h.IsMouseOver
            local ok, v = pcall(fn, h)
            return ok and v and true or false
        end
        local function Sync(_, over)
            if type(over) ~= "boolean" then over = Over() end
            if d.fill then d.fill:SetColorTexture(S.Colour(over and "surface3" or "surface2")) end
            if title then title:SetTextColor(S.Colour(over and "text" or "title")) end
        end
        p:After("CheckHighlightTitle", Sync)
        p:Hook("OnEnter", function() Sync(nil, true) end)
        p:Hook("OnLeave", function() Sync(nil, false) end)
        S.Own(Sync, h, title)
        Sync()

        local c = h.CollapseButton
        if S.Alive(c) then
            S.claimed[c] = "listHeader"
            local cp, cd = S.PainterFor(c), S.D(c)
            if not cd.chev then
                cd.chev = S.Ours(T.Chevron(c, 5))
                cd.chev:SetPoint("CENTER")
            end
            local function Turn()
                S.Blank(c)          -- UpdateCollapsedState sets the highlight atlas again
                cp:Fade()
                cd.chev:Point(c.collapsed and "right" or "down")
                cd.chev:SetColorLines(S.Colour("textMuted"))
            end
            cp:After("UpdateCollapsedState", Turn)
            T.Watch(cd.chev, Turn)
            Turn()
        end
    end,
}

--------------------------------------------------------------------------------
--  9f. Quest track box    QuestLogTrackCheckboxTemplate: the quest log's ticks
--     A Frame, not a CheckButton, so the check button part never saw it: a
--     ticksquare atlas behind a yellow CheckMark that Blizzard shows and
--     hides for tracked and untracked (QuestMapFrame.lua,
--     Checkbox.CheckMark:SetShown(isTracked)). Drawn as our checkbox
--     (LOOK.checkbox): copper with a dark tick while tracked. Their mark stays
--     where it is, out of sight, and still says which it is.
--------------------------------------------------------------------------------
R{
    name = "questTrack",
    keys = { "CheckMark" },
    art  = { CheckMark = "questlog%-icon%-checkmark" },
    paint = function(f, p)
        local CL = LOOK.checkbox
        p:Fade()
        p:Fill(CL.rest.fill)
        p:Border(CL.rest.edge)
        local d = S.D(f)
        if not d.tick then
            d.tick = S.Ours(f:CreateTexture(nil, "OVERLAY", nil, 7))
            d.tick:SetTexture(T.MEDIA .. "check.png")
            d.tick:SetPoint("CENTER")
            d.tick:SetSize(10, 10)
        end
        local mark = f.CheckMark
        local function Sync()
            d.on = mark:IsShown() and true or false
            local r = T.Resolve(CL, d)
            if d.fill then d.fill:SetColorTexture(T.C4(r.fill)) end
            T.SetEdge(f, r.edge)
            if r.glyph then d.tick:SetVertexColor(T.C4(r.glyph)) end
            d.tick:SetShown(d.on)
        end
        for _, m in ipairs({ "SetShown", "Show", "Hide" }) do pcall(hooksecurefunc, mark, m, Sync) end
        S.Own(Sync, f)
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  9g. Item button        anything built on ItemButtonTemplate
--     The paper doll's slots, inspect, loot, the merchant, mail, quest
--     rewards. Blizzard's slot frame (the normal texture, and the paper
--     doll's BorderFrame) goes; the icon gets S.IconWell; the well is the
--     slot Look. Quality is Blizzard's to decide and ours to show:
--     SetItemButtonBorder shows IconBorder for a quality and hides it for
--     none, SetItemButtonBorderVertexColor colours it (ItemButtonTemplate.lua,
--     SetItemButtonQuality_Base). IconBorder stays out of sight, and its
--     colour and visibility become our edge. Common (white) keeps the plain
--     edge, as our bags do.
--------------------------------------------------------------------------------
-- The ItemButton intrinsic declares `icon`; some templates add their own
-- `Icon` over it and draw into that one instead (ProfessionsButtonTemplate:
-- "Substitution for the icon in ItemButton"), leaving `icon` empty. Styling
-- `icon` there left every reagent slot's real icon uncropped. When a template
-- carries both, `Icon` is the one it draws.
local function ItemIcon(b)
    local I, i = rawget(b, "Icon"), rawget(b, "icon")
    if type(I) == "table" and I.SetTexCoord then return I end
    return i or b.Icon or b.icon or S.Sub(b, "IconTexture")
end

R{
    name = "itemButton",
    keys = { "IconBorder" },
    test = function(b) local i = ItemIcon(b); return type(i) == "table" and i.SetTexCoord ~= nil end,
    paint = function(b, p)
        local icon, ib = ItemIcon(b), b.IconBorder
        S.Blank(b)
        S.Mute(ib)
        if S.Alive(b.BorderFrame) then S.PainterFor(b.BorderFrame):Fade() end
        p:Fill(LOOK.slot.rest.fill)
        -- A round mask (CircularGiantItemButtonTemplate's CircleMask, the
        -- professions output) would cut our square icon to a disc.
        for _, key in ipairs({ "CircleMask", "IconMask" }) do
            local m = rawget(b, key)
            if m and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, m) end
        end
        local well = S.IconWell(icon)
        if not well then return end
        local d = S.D(b)
        local function Sync()
            local shown = ib.IsShown and ib:IsShown()
            local r, g, bl = ib:GetVertexColor()
            r, g, bl = S.Num(r), S.Num(g), S.Num(bl)
            if shown and r and not (r > 0.95 and g > 0.95 and bl > 0.95) and not d.hover then
                EV.Icons:SetState(icon, r, g, bl, 1)
            elseif d.hover then
                local e = T.Resolve(LOOK.slot, d).edge
                EV.Icons:SetState(icon, e[1], e[2], e[3], e[4])
            else
                EV.Icons:SetState(icon, nil)
            end
        end
        S.Own(Sync, well)
        for _, m in ipairs({ "SetVertexColor", "Show", "Hide", "SetShown" }) do
            if type(ib[m]) == "function" then pcall(hooksecurefunc, ib, m, Sync) end
        end
        p:Hook("OnEnter", function() d.hover = true; Sync() end)
        p:Hook("OnLeave", function() d.hover = false; Sync() end)
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  9h. Spellbook item     SpellBookItemTemplate: one spell in the spellbook
--     (Blizzard_PlayerSpells/SpellBook/Blizzard_SpellBookItem.xml).
--
--     A 40px icon button at the item's LEFT with its text 50px in, and nothing
--     behind either but a soft Backplate glow. On our flat surface that is an
--     icon floating next to a line of text. Ours is the kit's tile: a card of
--     our own round the whole item (8px of margin to the icon's left, the
--     grid's own 10-15px gaps between cards), lighter under the mouse, dimmed
--     for a spell not learned yet, and a step quieter for a passive.
--
--     Blizzard picks the icon art per spell (UpdateArtSet: square for actives,
--     round for passives) and the frames are pooled, so one frame is active on
--     this page and passive on the next. So ours is re-applied after every
--     UpdateVisuals: an active spell gets S.IconWell with the mask off so the
--     crop is square; a passive keeps Blizzard's round mask and gets our ring.
--
--     Two looping animations are taken out at the source, their textures
--     cleared (the atlases are only ever set in XML, so it stays cleared):
--       ActionBarHighlight  spellbook-item-unassigned-glow, pulsing forever on
--                           every spell that is on none of your bars
--       BorderSheen         talents-sheen-node, a sweep across every icon
--     The first carries information, so it becomes a static copper mark in
--     the card's corner, shown from the same actionBarStatus Blizzard reads.
--------------------------------------------------------------------------------
local TILE_PAD  = 8     -- card edge to the icon, on the left
local TILE_TEXT = 6     -- text to the card's right edge
local TILE_MARK = 5     -- the "not on your bars" mark

--- Take a texture's art away for good. Muting by alpha is not enough for a
--- spell's hover art: Blizzard's own hover and leave handlers set those alphas
--- (OnIconEnter lifts the Backplate to 1; OnIconLeave puts it back to 0.25 and
--- the icon highlight to 0.35), so a muted texture came back on the first
--- hover and stayed after it. The art itself is cleared instead, and cleared
--- again whenever Blizzard sets new art (UpdateVisuals re-sets the highlight
--- and the border atlas for every spell), so any alpha it picks shows nothing.
local stripped = setmetatable({}, { __mode = "k" })
local function StripArt(t)
    if not (t and t.SetTexture) or stripped[t] then return end
    stripped[t] = true
    local busy
    local function Clear(self)
        if busy then return end
        busy = true
        pcall(self.SetTexture, self, nil)
        busy = false
    end
    Clear(t)
    pcall(hooksecurefunc, t, "SetAtlas", Clear)
    pcall(hooksecurefunc, t, "SetTexture", Clear)
end

local function Passive(item)
    local ok, v = pcall(function() return item.spellBookItemInfo and item.spellBookItemInfo.isPassive end)
    return ok and v == true
end

local function MissingFromBars(item)
    local ok, v = pcall(function()
        return item.actionBarStatus ~= nil and ActionButtonUtil and ActionButtonUtil.ActionBarActionStatus
            and item.actionBarStatus == ActionButtonUtil.ActionBarActionStatus.MissingFromAllBars
    end)
    return ok and v and true or false
end

R{
    name = "spellItem",
    keys = { "Backplate", "TextContainer", "Button" },
    art  = { Backplate = "spellbook%-item%-backplate" },
    paint = function(item, p)
        local btn = item.Button
        local icon = S.Alive(btn) and btn.Icon
        if not (icon and icon.SetTexCoord) then return end
        local d, bd = S.D(item), S.D(btn)
        local well = S.IconWell(icon)
        if not well then return end

        -- The two loops, cleared for good.
        for _, key in ipairs({ "ActionBarHighlight", "BorderSheen" }) do
            local t = btn[key]
            if t and t.SetTexture then pcall(t.SetTexture, t, nil); t:SetAlpha(0) end
        end

        if not d.tile then
            d.tile = S.Ours(CreateFrame("Frame", nil, item))
            d.tile:SetPoint("TOPLEFT", item, "TOPLEFT", -TILE_PAD, 0)
            d.tile:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
            d.tile:SetFrameLevel(item:GetFrameLevel())
            d.tile:EnableMouse(false)
            d.mark = S.Ours(d.tile:CreateTexture(nil, "ARTWORK"))
            d.mark:SetSize(TILE_MARK, TILE_MARK)
            d.mark:SetPoint("TOPRIGHT", d.tile, "TOPRIGHT", -4, -4)
        end
        if not bd.ring then
            bd.ring = S.Ours(btn:CreateTexture(nil, "OVERLAY", nil, 6))
            bd.ring:SetTexture(T.MEDIA .. "ring.png")
            bd.ring:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
            bd.ring:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
        end
        p:Fill(LOOK.tile.rest.fill, nil, nil, d.tile)
        p:Border("border", nil, d.tile)

        -- Text: our face, body and muted; clear of the card's right edge.
        p:Label(item.Name, "text")
        p:Label(item.SubName, "textMuted")
        p:Label(item.RequiredLevel, "textMuted")
        if item.TextContainer then
            p:Reseat(item.TextContainer, { { "LEFT", 50, -1 }, { "RIGHT", -TILE_TEXT, -1 } })
        end

        local tileFill = S.D(d.tile).fill
        local function Sync()
            local passive = Passive(item)
            d.disabled = item.isUnlearned == true
            local r = T.Resolve(passive and LOOK.tileQuiet or LOOK.tile, d)
            if tileFill and r.fill then tileFill:SetColorTexture(T.C4(r.fill)) end
            if r.edge then T.SetEdge(d.tile, r.edge) end
            if r.mark then d.mark:SetColorTexture(T.C4(r.mark)) end
            d.mark:SetShown(MissingFromBars(item) and not d.disabled)
        end

        -- Blizzard's frame, shadow, hover glow, trainer art and backplate:
        -- the card and our edge do all of their jobs.
        StripArt(item.Backplate)
        for _, key in ipairs({ "Border", "BorderShadow", "IconHighlight", "TrainableShadow", "TrainableBackplate" }) do
            StripArt(btn[key])
        end

        local function Apply()
            if Passive(item) then
                if bd.unmasked and btn.IconMask then pcall(icon.AddMaskTexture, icon, btn.IconMask) end
                bd.unmasked = false
                icon:SetTexCoord(0, 1, 0, 1)
                well:Hide()
                bd.ring:Show()
            else
                if not bd.unmasked and btn.IconMask then pcall(icon.RemoveMaskTexture, icon, btn.IconMask) end
                bd.unmasked = true
                S.Crop(icon)
                well:Show()
                bd.ring:Hide()
            end
            bd.ring:SetVertexColor(S.Colour("borderStrong"))
            Sync()
        end
        p:After("UpdateArtSet", Apply)
        p:After("UpdateVisuals", Apply)
        p:After("UpdateActionBarAnim", Sync)
        p:After("OnIconEnter", function() d.hover = true; Sync() end)
        p:After("OnIconLeave", function() d.hover = false; Sync() end)
        S.Own(Sync, d.tile)
        T.Watch(bd.ring, Apply)
        Apply()
    end,
}

--------------------------------------------------------------------------------
--  9h2. Spellbook header  SpellBookHeaderTemplate: the school's name over its
--     spells. A parchment backplate and a gold scroll divider (both art),
--     the name in SystemFont_Huge2. Ours: the name in our bold body colour
--     and a plain rule under it, from the name's left edge to the frame's
--     right, which the grid stretches to the column (autoExpandHeaders).
--------------------------------------------------------------------------------
R{
    name = "spellHeader",
    keys = { "Backplate", "Text", "Border" },
    art  = { Backplate = "spellbook%-list%-backplate" },
    paint = function(f, p)
        S.Mute(f.Backplate)
        S.Mute(f.Border)
        p:Label(f.Text, "text", true)
        local d = S.D(f)
        if not d.rule then
            d.rule = S.Ours(f:CreateTexture(nil, "BORDER"))
            d.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -TILE_PAD, 6)
            d.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 6)
            if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(d.rule) end
            local function Paint()
                d.rule:SetColorTexture(S.Colour("border"))
                d.rule:SetHeight((EV.Pixel and EV.Pixel.One and EV.Pixel:One(f)) or 1)
            end
            Paint()
            T.Watch(d.rule, Paint)
        end
    end,
}

--------------------------------------------------------------------------------
--  9i. Stat header        CharacterStatFrameCategoryTemplate and the side
--     pane's CharacterFrameSidePaneCategoryTemplate: a brown banner
--     (UI-Character-Info-Title) stretched over the whole 40px frame
--     (CharacterFrame.xml), the name centred on it.
--
--     A box that size over every group of four stats is most of what made
--     the stat pane read as slabs. Ours is LOOK.section: no box at all, the
--     name in gold between two hairlines that run out to the pane's edges.
--     Blizzard's own centring of the name is kept; the rules follow it.
--------------------------------------------------------------------------------
R{
    name = "statHeader",
    keys = { "Background" },
    art  = { Background = "ui%-character%-info%-title" },
    test = function(f) return type(f.Title or f.Label) == "table" end,
    paint = function(f, p)
        p:Fade()
        local title = f.Title or f.Label
        local SL = LOOK.section
        p:Label(title, SL.rest.text, true)
        local d = S.D(f)
        if not d.rules then
            local function Rule()
                local t = S.Ours(f:CreateTexture(nil, "BORDER"))
                if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(t) end
                return t
            end
            d.rules = { Rule(), Rule() }
            local l, r = d.rules[1], d.rules[2]
            l:SetPoint("LEFT", f, "LEFT", SL.pad, 0)
            l:SetPoint("RIGHT", title, "LEFT", -SL.gap, 0)
            r:SetPoint("LEFT", title, "RIGHT", SL.gap, 0)
            r:SetPoint("RIGHT", f, "RIGHT", -SL.pad, 0)
            -- On the name's own centre line, not the frame's: Blizzard sets
            -- the name 1px high (CENTER y=1).
            local function Paint()
                local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(f)) or 1
                for _, t in ipairs(d.rules) do
                    t:SetHeight(px)
                    t:SetColorTexture(T.C4(T.Resolve(SL).rule))
                end
            end
            Paint()
            T.Watch(l, Paint)
        end
    end,
}

--------------------------------------------------------------------------------
--  9i1. Collapsible list headers and their parts, shared by the character
--     window's Reputation, Skills, Currency and Statistics tabs (Camelot
--     ReputationFrame.xml, SkillsFrame.xml, Blizzard_TokenUI.xml,
--     StatisticsFrame.xml), which are built from the same four pieces:
--
--       <X>HeaderTemplate     a Button: an unkeyed common-button-list-
--                             collapseExpand bar, StateIcon (plus / minus,
--                             set in Initialize) at the right, Name
--       ToggleCollapseButton  on a sub-header: campaign_headericon_closed /
--                             _open, re-set through GetNormalTexture():SetAtlas
--       BackgroundHighlight   on every entry: three soft charactercreate
--                             line-mouseover pieces Blizzard tints (white, or
--                             red at war) and fades (hover 0.1, selected 0.2)
--       ColoredProgressBarTemplate  a rounded, masked bar
--
--     Ours: the kit's group header (like listHeader, the quest log's), a
--     chevron for every open/closed control, a flat highlight (copper for the
--     selected row), and a flat bar in a well.
--------------------------------------------------------------------------------
R{
    name = "collapseHeader",
    type = "Button",
    keys = { "StateIcon", "Name" },
    test = function(h)
        for _, r in ipairs(S.Regions(h)) do
            if S.ArtIs(r, "common%-button%-list%-collapseexpand") then return true end
        end
        return false
    end,
    paint = function(h, p)
        p:Fade()
        S.Mute(h.StateIcon)
        p:Fill("surface2")
        p:Border("border")
        p:Label(h.Name, false, true)
        local d = S.D(h)
        if not d.chev then
            d.chev = S.Ours(T.Chevron(h, 4))
            d.chev:SetPoint("RIGHT", h, "RIGHT", -10, 0)
        end
        local function Collapsed()
            return S.ArtIs(h.StateIcon, "list%-plus")
        end
        local function Sync()
            local over = h.IsMouseOver and h:IsMouseOver()
            if d.fill then d.fill:SetColorTexture(S.Colour(over and "surface3" or "surface2")) end
            h.Name:SetTextColor(S.Colour(over and "text" or "title"))
            d.chev:Point(Collapsed() and "right" or "down")
            d.chev:SetColorLines(S.Colour(over and "text" or "textMuted"))
        end
        pcall(hooksecurefunc, h.StateIcon, "SetAtlas", function(t) t:SetAlpha(0); Sync() end)
        p:Hook("OnEnter", Sync)
        p:Hook("OnLeave", Sync)
        p:Hook("OnShow", Sync)
        S.Own(Sync, h, h.Name)
        Sync()
    end,
}

R{
    name = "headerToggle",
    type = "Button",
    art  = { normal = "campaign_headericon" },
    paint = function(b, p)
        local d = S.D(b)
        -- Faded, never blanked: Blizzard re-sets the art through
        -- GetNormalTexture():SetAtlas, which needs the texture to be there.
        local function Hide()
            for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
                local ok, t = pcall(b[g], b)
                if ok and t and t.SetAlpha then t:SetAlpha(0) end
            end
        end
        if not d.chev then
            d.chev = S.Ours(T.Chevron(b, 4))
            d.chev:SetPoint("CENTER")
        end
        local function Sync()
            Hide()
            local ok, n = pcall(b.GetNormalTexture, b)
            local open = ok and n and S.ArtIs(n, "_open")
            d.chev:Point(open and "down" or "right")
            local over = b.IsMouseOver and b:IsMouseOver()
            d.chev:SetColorLines(S.Colour(over and "text" or "textMuted"))
        end
        local ok, n = pcall(b.GetNormalTexture, b)
        if ok and n then pcall(hooksecurefunc, n, "SetAtlas", Sync) end
        p:Hook("OnEnter", Sync)
        p:Hook("OnLeave", Sync)
        T.Watch(d.chev, Sync)
        Sync()
    end,
}

local FLAT = "Interface\\Buttons\\WHITE8X8"

R{
    name = "rowHighlight",
    keys = { "Left", "Right", "Middle", "TextureRegions" },
    art  = { Middle = "linemouseover" },
    paint = function(f, p)
        for _, r in ipairs(f.TextureRegions) do
            if r.SetTexture then r:SetTexture(FLAT) end
        end
        -- Blizzard tints the pieces (white, or red for a faction at war) and
        -- sets the frame's alpha; the selected row, not at war, is copper.
        local okP, content = pcall(f.GetParent, f)
        local entry = okP and content and content.GetParent and content:GetParent()
        if entry and type(entry.RefreshBackgroundHighlightColor) == "function" then
            local function Tint(e)
                local okS, sel = pcall(e.IsSelected, e)
                local okW, war = pcall(function() return e.IsAtWar and e:IsAtWar() end)
                if okS and sel and not (okW and war) then
                    for _, r in ipairs(f.TextureRegions) do r:SetVertexColor(S.Colour("accent")) end
                end
            end
            pcall(hooksecurefunc, entry, "RefreshBackgroundHighlightColor", Tint)
        end
    end,
}

R{
    name = "statBar",
    keys = { "Fill", "Mask", "Text" },
    art  = { Fill = "common%-stat%-bar" },
    paint = function(f, p)
        local fill = f.Fill
        if fill.RemoveMaskTexture then pcall(fill.RemoveMaskTexture, fill, f.Mask) end
        -- Blizzard colours a bar two ways: a coloured atlas
        -- (SetFillTextureByColorType: red, green, blue, white) or white with a
        -- vertex colour (reputation's standing colour). Ours is flat either way,
        -- the colour kept.
        --
        -- The two meet on the skills bars: a blue atlas, then
        -- UpdateBarColor(WHITE_FONT_COLOR) as a vertex colour, so on the flat
        -- texture the white won and every bar went white. A white vertex
        -- colour means "the atlas's own colour", and is read as that.
        local TOKENS = { red = "danger", green = "success", blue = "rested" }
        local kind, busy
        local function Tint(t)
            if TOKENS[kind] then
                busy = true
                t:SetVertexColor(S.Colour(TOKENS[kind]))
                busy = false
            end
        end
        local function Flat(t, atlas)
            atlas = type(atlas) == "string" and atlas:lower() or ""
            kind = atlas:match("common%-stat%-bar%-(%a+)")
            t:SetTexture(FLAT)
            Tint(t)
        end
        local ok, atlas = pcall(fill.GetAtlas, fill)
        Flat(fill, ok and atlas)
        pcall(hooksecurefunc, fill, "SetAtlas", Flat)
        pcall(hooksecurefunc, fill, "SetVertexColor", function(t, r, g, b)
            if busy then return end
            r, g, b = S.Num(r), S.Num(g), S.Num(b)
            if r and g and b and r > 0.99 and g > 0.99 and b > 0.99 then Tint(t) end
        end)

        local d = S.D(f)
        if not d.track then
            local h = S.Num(fill:GetHeight()) or 15
            d.track = S.Ours(f:CreateTexture(nil, "BACKGROUND", nil, 1))
            d.track:SetPoint("LEFT", f, "LEFT", 0, 0)
            d.track:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            d.track:SetHeight(h)
            d.edges = {}
            for i = 1, 4 do
                local e = S.Ours(f:CreateTexture(nil, "ARTWORK", nil, -8))
                if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(e) end
                d.edges[i] = e
            end
            local e, tr = d.edges, d.track
            e[1]:SetPoint("BOTTOMLEFT", tr, "TOPLEFT");   e[1]:SetPoint("BOTTOMRIGHT", tr, "TOPRIGHT")
            e[2]:SetPoint("TOPLEFT", tr, "BOTTOMLEFT");   e[2]:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
            e[3]:SetPoint("TOPRIGHT", tr, "TOPLEFT");     e[3]:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
            e[4]:SetPoint("TOPLEFT", tr, "TOPRIGHT");     e[4]:SetPoint("BOTTOMLEFT", tr, "BOTTOMRIGHT")
            local function Paint()
                local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(f)) or 1
                e[1]:SetHeight(px); e[2]:SetHeight(px); e[3]:SetWidth(px); e[4]:SetWidth(px)
                tr:SetColorTexture(S.Colour("surfaceSunk"))
                for _, t in ipairs(e) do t:SetColorTexture(S.Colour("border")) end
            end
            Paint()
            T.Watch(tr, Paint)
        end
        p:Label(f.Text, "text")
    end,
}

R{
    name = "sidePane",
    keys = { "Title", "Subtitle", "Divider", "Description", "Content", "Footer" },
    paint = function(f, p)
        -- The title's colour is Blizzard's (SetPaneTitleColor: a faction's
        -- standing, a skill's), so only our face.
        p:Label(f.Title, false, true)
        p:Label(f.Subtitle, false)
        local div = f.Divider
        if div and div.SetColorTexture then
            local function Paint()
                div:SetColorTexture(S.Colour("border"))
                div:SetHeight((EV.Pixel and EV.Pixel.One and EV.Pixel:One(f)) or 1)
            end
            Paint()
            T.Watch(div, Paint)
            S.D(div).muted = nil
            div:SetAlpha(1)
        end
    end,
}

--------------------------------------------------------------------------------
--  9p. Professions pieces (Blizzard_ProfessionsTemplates)
--
--     rankBar        ProfessionsRankBarTemplate: the skill bar across the top
--                    of the professions window. A per-profession flipbook fill
--                    (Skillbar_Fill_Flipbook_<kit>, set in Update) masked to the
--                    skill (the Mask's WIDTH is the progress, GetMaskWidth), a
--                    flare, a bevelled background and frame. Ours: the mask
--                    kept (it is the progress), the fill flat copper, the flare,
--                    background and frame cleared, a sunk well of ours round
--                    the fill's rect.
--     filterDropdown WowStyle1FilterDropdownTemplate (Classic): a Background
--                    atlas (common-dropdown-classic-b-button, in S.ORNATE) and
--                    a Text, no Arrow, so the dropdown part never saw it and
--                    "Filter" floated as bare gold text. Ours: our dropdown.
--     recipeRow      ProfessionsRecipeListRecipeTemplate: the gold
--                    Professions_Recipe_Active / _Hover line art cleared; the
--                    listItem Look, on while Blizzard shows SelectedOverlay.
--                    The label keeps Blizzard's colour: it is the recipe's
--                    difficulty (orange, yellow, green, grey).
--     skillBarLegacy ProfessionsStatusBarArtTemplate: a category's skill bar,
--                    UI-Character-Skills-Bar in its BarBorder (in
--                    S.ORNATE_FILES). Flat, in a well.
--------------------------------------------------------------------------------
local function Well(host, around, sub)
    local d = S.D(host)
    if d.well then return d.well end
    local w = { track = S.Ours(host:CreateTexture(nil, "BACKGROUND", nil, sub or 1)), edges = {} }
    w.track:SetAllPoints(around)
    for i = 1, 4 do
        local e = S.Ours(host:CreateTexture(nil, "ARTWORK", nil, -8))
        if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(e) end
        w.edges[i] = e
    end
    local e, tr = w.edges, w.track
    e[1]:SetPoint("BOTTOMLEFT", tr, "TOPLEFT");   e[1]:SetPoint("BOTTOMRIGHT", tr, "TOPRIGHT")
    e[2]:SetPoint("TOPLEFT", tr, "BOTTOMLEFT");   e[2]:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    e[3]:SetPoint("TOPRIGHT", tr, "TOPLEFT");     e[3]:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    e[4]:SetPoint("TOPLEFT", tr, "TOPRIGHT");     e[4]:SetPoint("BOTTOMLEFT", tr, "BOTTOMRIGHT")
    local function Paint()
        local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(host)) or 1
        e[1]:SetHeight(px); e[2]:SetHeight(px); e[3]:SetWidth(px); e[4]:SetWidth(px)
        tr:SetColorTexture(S.Colour("surfaceSunk"))
        for _, t in ipairs(e) do t:SetColorTexture(S.Colour("border")) end
    end
    Paint()
    T.Watch(tr, Paint)
    d.well = w
    return w
end
S.Well = Well

R{
    name = "rankBar",
    keys = { "Background", "Fill", "Flare", "Mask", "Border", "Rank" },
    paint = function(f, p)
        StripArt(f.Background)
        StripArt(f.Border)
        StripArt(f.Flare)
        local fill = f.Fill
        local busy
        local function Flat(t)
            if busy then return end
            busy = true
            t:SetTexture(FLAT)
            -- The deep end of our copper, not the accent: the rank reads in
            -- white across it, and on the bright accent it did not.
            t:SetVertexColor(S.Colour("xp"))
            busy = false
        end
        Flat(fill)
        pcall(hooksecurefunc, fill, "SetAtlas", Flat)
        T.Watch(fill, Flat)
        Well(f, fill, 1)
        local text = f.Rank and f.Rank.Text
        if text then
            p:Label(text, "text", true)
            -- Blizzard's font was outlined (Number12FontOutline); ours is not,
            -- so a shadow keeps it off the fill.
            text:SetShadowColor(0, 0, 0, 1)
            text:SetShadowOffset(1, -1)
        end
    end,
}

R{
    name = "filterDropdown",
    keys = { "ResetButton", "Background", "Text" },
    without = { "Arrow" },
    paint = function(dd, p)
        p:Fade()
        StripArt(dd.Background)
        p:Fill("surface2")
        p:Border("borderStrong")
        p:Label(dd.Text)
        local d = S.D(dd)
        if not d.chev and T.Chevron then
            d.chev = S.Ours(T.Chevron(dd, LOOK.dropdown.chevron))
            d.chev:SetPoint("RIGHT", dd, "RIGHT", -6, 0)
            d.chev:Point("down")
        end
        p:States(LOOK.dropdown, {
            label = dd.Text, chev = d.chev,
            on = function() return type(dd.IsMenuOpen) == "function" and dd:IsMenuOpen() end,
        })
        p:After("OnMenuOpened", function() if d.Repaint then d.Repaint() end end)
        p:After("OnMenuClosed", function() if d.Repaint then d.Repaint() end end)
    end,
}

R{
    name = "recipeRow",
    type = "Button",
    keys = { "SkillUps", "LockedIcon", "SelectedOverlay", "HighlightOverlay", "Label" },
    paint = function(b, p)
        StripArt(b.SelectedOverlay)
        StripArt(b.HighlightOverlay)
        p:Fill("surface2", 0)
        p:Label(b.Label, false)
        if b.Count then p:Label(b.Count, false) end
        local sel, d = b.SelectedOverlay, S.D(b)
        p:States(LOOK.listItem, { on = function() return sel:IsShown() end })
        for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
            pcall(hooksecurefunc, sel, m, function() if d.Repaint then d.Repaint() end end)
        end
    end,
}

R{
    name = "skillBarLegacy",
    type = "StatusBar",
    keys = { "BorderLeft", "BorderRight", "BorderMid", "Rank" },
    paint = function(bar, p)
        StripArt(bar.BorderLeft); StripArt(bar.BorderRight); StripArt(bar.BorderMid)
        local ok, tex = pcall(bar.GetStatusBarTexture, bar)
        if ok and tex then tex:SetTexture(FLAT) end
        Well(bar, bar, -1)
        if bar.Rank then p:Label(bar.Rank, "text") end
    end,
}

--------------------------------------------------------------------------------
--  9q. Professions overview (Blizzard_ProfessionsBook, Camelot templates)
--
--     professionCard  PrimaryProfessionTemplate / SecondaryProfessionTemplate:
--                     a card whose Background atlas (Profession-overview-Card,
--                     -Card-<name> once learned, set in Lua) carries the
--                     parchment, an illustration and a gold frame, with
--                     transparent margins the layout relies on: the cards are
--                     anchored overlapping (secondaries x=-6, primaries y=+5).
--                     Ours: the art cleared for good, and the kit's tile inset
--                     into that margin, so neighbours keep an even gap.
--     professionSpell ProfessionButtonTemplate: the ability icons on a card,
--                     framed by Profession-square-frame (IconTextureOverlay,
--                     set on every update). Ours: the suite's icon style, lit
--                     under the mouse.
--     unlearnButton   the red crossmark beside a primary's bar: a small box of
--                     ours with the close glyph, in the danger Look.
--------------------------------------------------------------------------------
local CARD_INSET = 6

R{
    name = "professionCard",
    keys = { "Background", "ProfessionName", "missingHeader", "missingText", "StatusBar" },
    paint = function(f, p)
        StripArt(f.Background)
        local d = S.D(f)
        if not d.card then
            d.card = S.Ours(CreateFrame("Frame", nil, f))
            d.card:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_INSET, -CARD_INSET)
            d.card:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
            d.card:SetFrameLevel(f:GetFrameLevel())
            d.card:EnableMouse(false)
        end
        p:Fill(LOOK.tile.rest.fill, nil, nil, d.card)
        p:Border("border", nil, d.card)
        p:Label(f.ProfessionName, "title", true)
        p:Label(f.missingHeader, "title", true)
        p:Label(f.missingText, "textMuted")
        if f.specialization then p:Label(f.specialization, "textMuted") end
    end,
}

R{
    name = "professionSpell",
    type = "CheckButton",
    keys = { "IconTexture", "IconTextureOverlay", "spellString" },
    paint = function(b, p)
        StripArt(b.IconTextureOverlay)
        if b.highlightTexture then StripArt(b.highlightTexture) end
        S.Blank(b)
        local icon = b.IconTexture
        S.IconWell(icon)
        p:Label(b.spellString, "text")
        if b.subSpellString then p:Label(b.subSpellString, "textMuted") end
        local d = S.D(b)
        local function Sync()
            if d.hover then
                local e = T.Resolve(LOOK.slot, d).edge
                EV.Icons:SetState(icon, e[1], e[2], e[3], e[4])
            else
                EV.Icons:SetState(icon, nil)
            end
        end
        p:Hook("OnEnter", function() d.hover = true; Sync() end)
        p:Hook("OnLeave", function() d.hover = false; Sync() end)
    end,
}

R{
    name = "unlearnButton",
    type = "Button",
    keys = { "Icon", "Overlay" },
    art  = { Icon = "crossmark" },
    paint = function(b, p)
        StripArt(b.Icon)
        StripArt(b.Overlay)
        S.Blank(b)
        -- The skill bar beside it is frameStrata HIGH (the book's template), so
        -- at the button's own strata the bar's well covered its left edge.
        b:SetFrameStrata("HIGH")
        local okP, par = pcall(b.GetParent, b)
        local bar = okP and par and rawget(par, "StatusBar")
        if bar and bar.GetFrameLevel then b:SetFrameLevel(bar:GetFrameLevel() + 5) end
        p:Fill(LOOK.buttonDanger.rest.fill)
        p:Border(LOOK.buttonDanger.rest.edge)
        p:Glyph("close", LOOK.close.glyphSize, "danger")
        p:States(LOOK.buttonDanger)
    end,
}

--------------------------------------------------------------------------------
--  9i2. Popout button     EquipmentFlyoutPopoutButtonTemplate: the tab beside
--     an equipment slot that opens the list of what else fits it
--     (Blizzard_FrameXML/Camelot/EquipmentFlyout.lua). A 20x43 gold pull
--     tab, or 43x20 under the weapons. Blizzard re-sets its atlases, size and
--     rotation in EquipmentFlyoutPopoutButton_RefreshVisualState on show,
--     enter, leave, press and click, so ours is re-applied after that.
--
--     Ours is LOOK.popout: a slim box in the button Look, centred in
--     Blizzard's rect (the hit area stays theirs), with a chevron the way
--     the list opens; on (copper) while it is open (flyoutLocked).
--------------------------------------------------------------------------------
local popouts = setmetatable({}, { __mode = "k" })
local popoutHooked

local function PopoutDir(b)
    local ok, par = pcall(b.GetParent, b)
    par = ok and par or nil
    local dir = (par and rawget(par, "flyoutDirection")) or rawget(b, "flyoutDirection")
    if not dir and par and rawget(par, "verticalFlyout") then dir = "UP" end
    dir = type(dir) == "string" and dir:lower() or "right"
    return dir
end

local function PopoutSync(b)
    local d = popouts[b]
    if not d then return end
    for _, g in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local ok, t = pcall(b[g], b)
        if ok and t and t.SetAlpha then t:SetAlpha(0) end
    end
    local PL = LOOK.popout
    local dir = PopoutDir(b)
    local vertical = dir == "up" or dir == "down"
    d.box:SetSize(vertical and PL.long or PL.short, vertical and PL.short or PL.long)
    d.chev:Point(dir)
    if d.Repaint then d.Repaint() end
end

R{
    name = "popoutButton",
    type = "Button",
    art  = { normal = "ui%-character%-info%-button%-pull" },
    paint = function(b, p)
        local d = S.D(b)
        if not d.box then
            d.box = S.Ours(CreateFrame("Frame", nil, b))
            d.box:SetPoint("CENTER")
            d.box:EnableMouse(false)
            d.chev = S.Ours(T.Chevron(d.box, LOOK.popout.chevron))
            d.chev:SetPoint("CENTER")
        end
        p:Fill(LOOK.button.rest.fill, nil, nil, d.box)
        p:Border(LOOK.button.rest.edge, nil, d.box)
        local boxFill = S.D(d.box).fill
        p:States(LOOK.button, { edgesOn = d.box, chev = d.chev,
            on = function() return rawget(b, "flyoutLocked") == true end,
            after = function(r) if boxFill and r.fill then boxFill:SetColorTexture(T.C4(r.fill)) end end })
        popouts[b] = d
        if not popoutHooked and type(_G.EquipmentFlyoutPopoutButton_RefreshVisualState) == "function" then
            popoutHooked = true
            hooksecurefunc("EquipmentFlyoutPopoutButton_RefreshVisualState", PopoutSync)
        end
        PopoutSync(b)
    end,
}

--------------------------------------------------------------------------------
--  9i3. Tertiary button   PaperDollTertiaryButtonTemplate: the equipment
--     manager's New Set. A common-button-tertiary state atlas (re-set on
--     every state change by PaperDollTertiaryButtonMixin:OnButtonStateChanged,
--     the texture kept, so our alpha holds), a green GameFontGreen label and
--     a green plus. Ours: our button, the label in its text colour, the plus
--     kept and drawn in copper.
--------------------------------------------------------------------------------
R{
    name = "tertiaryButton",
    type = "Button",
    keys = { "StateTexture" },
    art  = { StateTexture = "common%-button%-tertiary" },
    paint = function(b, p)
        S.Blank(b)
        S.Mute(b.StateTexture)
        local label, plus
        for _, r in ipairs(S.Regions(b)) do
            local ot = r.GetObjectType and r:GetObjectType()
            if ot == "FontString" and not label then label = r
            elseif ot == "Texture" and S.ArtIs(r, "icon%-add") then plus = r end
        end
        p:Fill(LOOK.button.rest.fill)
        p:Border(LOOK.button.rest.edge)
        if plus then
            plus:SetDesaturated(true)
            plus:SetSize(12, 12)
        end
        if label then p:Label(label) end
        p:States(LOOK.button, { label = label, after = function(r)
            if plus then plus:SetVertexColor(S.Colour(S.D(b).disabled and "textDisabled" or "accent")) end
        end })
    end,
}

--------------------------------------------------------------------------------
--  9i4. Title row         PlayerTitleButtonTemplate: a title in the
--     character window's titles list. Char-Stat file art top, middle and
--     bottom, a gold UI-CheckBox-Check on the one you wear, the FriendsFrame
--     highlight bars for selected and hover. Ours: the listItem Look, on for
--     the worn title (Blizzard shows SelectedBar for it), the tick in copper.
--     Blizzard's alternate-row Stripe (a flat colour it sets itself) stays.
--------------------------------------------------------------------------------
R{
    name = "titleRow",
    type = "Button",
    keys = { "BgTop", "BgBottom", "BgMiddle", "Stripe", "Check", "SelectedBar" },
    paint = function(b, p)
        S.Blank(b)
        S.Mute(b.BgTop); S.Mute(b.BgBottom); S.Mute(b.BgMiddle); S.Mute(b.SelectedBar)
        local check = b.Check
        check:SetDesaturated(true)
        check:SetVertexColor(S.Colour("accent"))
        p:Fill("surface2", 0)
        local label = b.text or (b.GetFontString and b:GetFontString())
        if label then p:Label(label) end
        local d = S.D(b)
        p:States(LOOK.listItem, { label = label, on = function() return b.SelectedBar:IsShown() end })
        for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
            pcall(hooksecurefunc, b.SelectedBar, m, function() if d.Repaint then d.Repaint() end end)
        end
    end,
}

--------------------------------------------------------------------------------
--  9i5. Gear set          GearSetButtonTemplate: an equipment set in the
--     equipment manager. An OutfitCard atlas from the icon rightwards, with
--     -Hover and -Selected versions Blizzard shows and hides
--     (PaperDollEquipmentManagerPane_Update), an ornate frame round the icon
--     and a ring round the spec icon. Ours is the kit's tile across the whole
--     row, the icon in our well, on while the set is selected and lit while
--     Blizzard's hover bar is up. The tick for the set you wear is kept, in
--     copper; the edit and delete buttons are Blizzard's own small icons.
--------------------------------------------------------------------------------
R{
    name = "gearSet",
    type = "Button",
    keys = { "HighlightBar", "SelectedBar", "Check", "icon", "SpecRing" },
    paint = function(b, p)
        p:Fade(nil, { b.icon, b.SpecIcon, b.Check })
        S.Blank(b)
        b.Check:SetDesaturated(true)
        b.Check:SetVertexColor(S.Colour("accent"))
        p:Fill(LOOK.tile.rest.fill)
        p:Border("border")
        S.IconWell(b.icon)
        if b.text then p:Label(b.text) end
        local d = S.D(b)
        p:States(LOOK.tile, { on = function() return b.SelectedBar:IsShown() end })
        for _, bar in ipairs({ b.SelectedBar, b.HighlightBar }) do
            for _, m in ipairs({ "Show", "Hide", "SetShown" }) do
                pcall(hooksecurefunc, bar, m, function()
                    d.hover = b.HighlightBar:IsShown() or nil
                    if d.Repaint then d.Repaint() end
                end)
            end
        end
    end,
}

--------------------------------------------------------------------------------
--  9o. Model control      ModelSceneControlButtonTemplate: the zoom, turn and
--     reset buttons over a model (the character window, inspect, the dressing
--     room). 32px buttons with a 4px HitRectInset, laid out with
--     buttonHorizontalPadding -6 (ModelSceneControlFrame.xml), so the visible
--     button is the middle 24 and neighbours overlap by 6. Painting the whole
--     rect stacked them into one strip. Ours is a box the size of the hit
--     area, centred, in our button Look, the icon kept and tinted to its
--     glyph colour.
--------------------------------------------------------------------------------
local MODEL_BOX = 24

R{
    name = "modelControl",
    type = "Button",
    keys = { "Icon" },
    art  = { normal = "common%-button%-square%-gray" },
    paint = function(b, p)
        S.Blank(b)
        p:Fade(nil, { b.Icon })
        local d = S.D(b)
        if not d.box then
            d.box = S.Ours(CreateFrame("Frame", nil, b))
            d.box:SetSize(MODEL_BOX, MODEL_BOX)
            d.box:SetPoint("CENTER")
            d.box:EnableMouse(false)
            d.box:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
        end
        p:Fill(LOOK.button.rest.fill, nil, nil, d.box)
        p:Border(LOOK.button.rest.edge, nil, d.box)
        if b.Icon.SetDesaturated then b.Icon:SetDesaturated(true) end
        local boxFill = S.D(d.box).fill
        p:States(LOOK.button, { glyph = b.Icon, edgesOn = d.box, after = function(r)
            if boxFill and r.fill then boxFill:SetColorTexture(T.C4(r.fill)) end
        end })
    end,
}

--------------------------------------------------------------------------------
--  9j. Stat row           CharacterStatFrameTemplate and the scroll box's
--     stat elements: a Line-Bounce background Blizzard shows on every other
--     row. It becomes our faint stripe (the same texture, a flat colour of
--     ours, so Blizzard's own alternation still decides which rows have it);
--     the label muted, the value in body text.
--------------------------------------------------------------------------------
R{
    name = "statRow",
    keys = { "Background", "Value" },
    art  = { Background = "ui%-character%-info%-line%-bounce" },
    paint = function(f, p)
        local bg = f.Background
        local function Paint() bg:SetColorTexture(S.Colour({ "surfaceSunk", a = 0.45 })) end
        Paint()
        T.Watch(bg, Paint)
        if f.Label then p:Label(f.Label, "textMuted") end
        p:Label(f.Value, "text")
    end,
}

--------------------------------------------------------------------------------
--  9k. Side tab           LargeSideTabButtonTemplate: the big tabs down a
--     window's edge (the character window's, the quest log's). Blizzard
--     shows SelectedTexture for the chosen one (SidePanelTabButtonMixin:
--     SetChecked); its art is in S.ORNATE, so it is out of sight and says
--     which tab is on. Ours: an icon well in the slot Look, the icon kept
--     (with Blizzard's mask), copper when selected.
--------------------------------------------------------------------------------
--- A tab's face, through LOOK.windowTab. A tab reads as a tab when the chosen
--- one is part of what it opens: the window's own surface, no edge on the
--- side that meets the window (and one pixel over the window's border, which
--- the caller arranges by where it puts the tab), and a copper bar on the far
--- side. The others are sunk, edged all round, their icons dimmed.
---
--- `open` is the side facing the window: "left" for tabs down a window's
--- right edge, "bottom" for tabs along a tool bar. Returns Paint(on, hover).
local EDGE_OF = { top = 1, bottom = 2, left = 3, right = 4 }
local FAR_SIDE = { left = "right", right = "left", bottom = "top", top = "bottom" }
function S.TabFace(f, open, icon)
    local d = S.D(f)
    local TL = LOOK.windowTab
    if not d.tabFill then
        d.tabFill = S.Ours(EV.Pixel:Fill(f, "BACKGROUND", -7))
        EV.Pixel:Edges(f)
        -- The icon sits in a black ring inside the edge (LOOK.windowTab.inset),
        -- so the art has a frame of its own whatever the tab's state.
        local one = EV.Pixel:One(f)
        d.tabInset = S.Ours(f:CreateTexture(nil, "BACKGROUND", nil, -6))
        d.tabInset:SetPoint("TOPLEFT", f, "TOPLEFT", one, -one)
        d.tabInset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -one, one)
        d.tabInset:SetColorTexture(0, 0, 0, 1)
        d.tabBar = S.Ours(f:CreateTexture(nil, "BORDER", nil, 6))
        local far = FAR_SIDE[open] or "right"
        if far == "right" or far == "left" then
            d.tabBar:SetPoint("TOP" .. far:upper(), f, "TOP" .. far:upper())
            d.tabBar:SetPoint("BOTTOM" .. far:upper(), f, "BOTTOM" .. far:upper())
            d.tabBar:SetWidth(TL.bar)
        else
            d.tabBar:SetPoint(far:upper() .. "LEFT", f, far:upper() .. "LEFT")
            d.tabBar:SetPoint(far:upper() .. "RIGHT", f, far:upper() .. "RIGHT")
            d.tabBar:SetHeight(TL.bar)
        end
    end
    local st = {}
    local function Paint(on, hover)
        st.on, st.hover = on and true or false, hover and true or false
        local r = T.Resolve(TL, st)
        d.tabFill:SetColorTexture(T.C4(r.fill))
        T.SetEdge(f, r.edge)
        local rec = EV.Pixel:EdgesOf(f)
        local openEdge = rec and rec.edges[EDGE_OF[open] or 3]
        if openEdge then openEdge:SetShown(not st.on) end
        d.tabBar:SetColorTexture(T.C4(r.bar))
        if icon and r.icon then
            icon:SetDesaturated(not (st.on or st.hover))
            icon:SetAlpha(r.icon[4] or 1)
        end
    end
    d.TabPaint = Paint
    return Paint
end

R{
    name = "sideTab",
    keys = { "Background", "Icon", "SelectedTexture" },
    art  = { Background = "common%-sidetab" },
    paint = function(t, p)
        p:Fade(nil, { t.Icon })
        local sel, icon, d = t.SelectedTexture, t.Icon, S.D(t)
        -- These tabs hang off a window's right edge (the character window's,
        -- the quest log's), so their open side is the left.
        local Paint = S.TabFace(t, "left", icon)
        local function Sync() Paint(sel:IsShown(), d.hover) end
        -- The tab-shaped mask (common-sidetab-mask) cut the icon to Blizzard's
        -- tab outline; in a square tab it is a square icon. The side tab icons
        -- (INV_SideTab_*) are painted for that mask, with a dark vignette in
        -- their corners, so they are cropped a step harder than the suite's
        -- crop, after Blizzard's UpdateIconInterior sets its own on every
        -- SetChecked.
        if t.Mask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, t.Mask) end
        local function Crop()
            if rawget(t, "fillToInterior") then
                local z = math.max(select(1, EV.Icons:Coords()), 0.12)
                icon:SetTexCoord(z, 1 - z, z, 1 - z)
            end
        end
        Crop()
        p:After("SetChecked", function() Crop(); Sync() end)
        p:Hook("OnEnter", function() d.hover = true; Sync() end)
        p:Hook("OnLeave", function() d.hover = false; Sync() end)
        S.Own(Sync, t)
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  9l. Settings category  SettingsCategoryListButtonTemplate: a row in the
--     settings panel's category list. Blizzard shows its Texture as
--     Options_List_Active when selected, Options_List_Hover under the mouse,
--     and hides it otherwise, resetting the label's font object each time
--     (SettingsCategoryListButtonMixin:UpdateStateInternal); the +/- is the
--     Toggle, re-textured in SetExpanded. Ours: the listItem Look read from
--     that state, top-level categories bold in body text and the rest muted,
--     and our chevron for the toggle. Both re-applied after Blizzard's.
--------------------------------------------------------------------------------
R{
    name = "settingsCategory",
    type = "Button",
    keys = { "Toggle", "Texture", "Label" },
    paint = function(b, p)
        S.Mute(b.Texture)
        p:Fill("surface2", 0)
        local d = S.D(b)
        local t, cd = b.Toggle, S.D(b.Toggle)
        if S.Alive(t) and not cd.chev then
            cd.chev = S.Ours(T.Chevron(t, 4))
            cd.chev:SetPoint("CENTER")
        end
        local function Category()
            local ok, c = pcall(function() return b:GetElementData().data.category end)
            return ok and c or nil
        end
        local function Sync()
            local tex = b.Texture
            local shown = tex:IsShown()
            local atlas = shown and tex:GetAtlas() or ""
            atlas = type(atlas) == "string" and atlas or ""
            d.on = shown and atlas:find("Active", 1, true) ~= nil
            d.hover = shown and atlas:find("Hover", 1, true) ~= nil
            local r = T.Resolve(LOOK.listItem, d)
            if d.fill and r.fill then d.fill:SetColorTexture(T.C4(r.fill)) end
            local cat = Category()
            local top = cat and cat.HasParentCategory and not cat:HasParentCategory()
            if r.text then
                if top and not d.on and not d.hover then b.Label:SetTextColor(S.Colour("text"))
                else b.Label:SetTextColor(T.C4(r.text)) end
            end
            if cd.chev then
                S.Blank(t)
                local ok, open = pcall(function() return cat and cat:IsExpanded() end)
                cd.chev:Point(ok and open and "down" or "right")
                cd.chev:SetColorLines(S.Colour("textMuted"))
            end
        end
        p:After("UpdateStateInternal", Sync)
        p:After("SetExpanded", Sync)
        S.Own(Sync, b, b.Label)
        Sync()
    end,
}

--------------------------------------------------------------------------------
--  9m. Settings header    SettingsCategoryListHeaderTemplate: the banner over
--     a group of categories (Options_CategoryHeader_<n>, set in Init, so the
--     survey cannot see it: coverage lists it as runtime-matched). Ours: the
--     label in gold on the panel, our divider under it.
--------------------------------------------------------------------------------
R{
    name = "settingsHeader",
    keys = { "Background", "Label" },
    test = function(f) return S.ArtIs(f.Background, "options_categoryheader") end,
    paint = function(f, p)
        S.Mute(f.Background)
        p:Label(f.Label, "title", true)
        local d = S.D(f)
        if not d.rule and f.CreateTexture then
            d.rule = S.Ours(f:CreateTexture(nil, "BORDER"))
            d.rule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 2)
            d.rule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 2)
            d.rule:SetHeight(1)
            local function Paint() d.rule:SetColorTexture(S.Colour("divider")) end
            Paint()
            T.Watch(d.rule, Paint)
        end
    end,
}

--------------------------------------------------------------------------------
--  9n. Settings section   the button of SettingsExpandableSectionTemplate: a
--     three-piece Options_ListExpand bar. Ours: a flat bar, our edge, its
--     title in gold.
--------------------------------------------------------------------------------
R{
    name = "settingsExpand",
    type = "Button",
    keys = { "Left", "Right", "Text" },
    art  = { Left = "options_listexpand_left" },
    paint = function(b, p)
        p:Fade()
        p:Fill("surface2")
        p:Border("border")
        p:Label(b.Text, "title", true)
    end,
}

--------------------------------------------------------------------------------
--  9b. Legacy scroll bar  Slider-based, 10 templates
--      MinimalScrollBar (the modern one, an EventFrame with a Track) is part
--      9. Everything older is a Slider with ScrollUpButton/ScrollDownButton
--      and a ThumbTexture, and nothing claimed any of it: the Track
--      fingerprint cannot see them and the slider part must not have them.
--      Found by running the fingerprints over the manifest, not in game.
--------------------------------------------------------------------------------
R{
    name = "scrollBarLegacy",
    type = "Slider",
    without = { "Thumb" },
    test = function(bar)
        return type(S.Sub(bar, "ThumbTexture")) == "table"
            or type(rawget(bar, "thumbTexture")) == "table"
            or type(bar.ScrollUpButton) == "table"
    end,
    paint = function(bar, p)
        p:Fade()
        p:FadeSlice()
        p:FadeKeys("Top", "Middle", "Bottom", "Background", "BG", "Border",
                   "trackBG", "ScrollUpBorder", "ScrollDownBorder")
        p:Fill("surface2")
        local track = S.D(bar).fill
        if track then
            local function Paint(t) t:SetColorTexture(T.C4(T.Resolve(LOOK.scrollbar).track)) end
            Paint(track)
            T.Watch(track, Paint)
        end

        -- The steppers keep working and keep their hit area; only the gold
        -- arrow art goes, replaced by one of our chevrons.
        for key, dir in pairs({ ScrollUpButton = "up", ScrollDownButton = "down",
                                UpButton = "up", DownButton = "down" }) do
            local step = bar[key]
            if type(step) == "table" then
                S.Blank(step)
                p:Fade(step)
                local sd = S.D(step)
                if not sd.chev and T.Chevron then
                    sd.chev = S.Ours(T.Chevron(step, LOOK.scrollStep.chevron))
                    sd.chev:SetPoint("CENTER")
                    sd.chev:Point(dir)
                    S.StepperLook(step, sd)
                end
            end
        end

        -- A Slider's thumb is its ThumbTexture, so we recolour it in place
        -- rather than drawing over it: it is the object the client moves.
        local thumb = S.Sub(bar, "ThumbTexture") or rawget(bar, "thumbTexture")
        if not thumb and bar.GetThumbTexture then
            local ok, t = pcall(bar.GetThumbTexture, bar)
            if ok then thumb = t end
        end
        if thumb and thumb.SetColorTexture then
            if thumb.SetAtlas then pcall(thumb.SetAtlas, thumb, nil) end
            -- A Slider's hover is the whole bar's.
            S.ThumbLook(bar, thumb)
        end
    end,
}

--------------------------------------------------------------------------------
-- 10. Inset               InsetFrameTemplate, 49 inherits; by layoutType, 19 templates
--
--     This part matched NOTHING until 21 Sep. Its fingerprint was
--     art = { Bg = "ui%-background%-marble" }, and InsetFrameTemplate's Bg is
--     Interface\FrameGeneral\UI-Background-Marble, a FILE. GetTexture()
--     never returns that path, so the pattern could not fire, and every inset
--     in the game fell through to `window` and was painted surface0: the same
--     colour as the window containing it. That is why skinned windows read as
--     flat, with no interior depth at all.
--
--     Blizzard already names it for us. NineSliceUtil reads frame.layoutType
--     to choose the slice art, so an inset says "InsetFrameTemplate" and says
--     it through inheritance, on every one of the 49 sites. No art guessing.
--------------------------------------------------------------------------------
R{
    name = "inset",
    layout = "InsetFrameTemplate",
    paint = function(f, p)
        p:Fade()
        p:FadeSlice()
        p:Surface("inset")
    end,
}

--------------------------------------------------------------------------------
-- 11. Dialog border       DialogBorderTemplate, 44 inherits; by layoutType, 5 templates
--     Dead for the same reason as the inset: its Bg is
--     Interface\DialogFrame\UI-DialogBox-Background, a file.
--------------------------------------------------------------------------------
--
--     A dialog that stands on its own (the game menu, a pop-up) is a window,
--     and is drawn as ours are (EvermoreUI/UI/Containers.lua, U.Window): the
--     window surface, its edge, and the soft shadow that lets the edge read
--     against the world. One inside another window is a box, and stays raised.
--------------------------------------------------------------------------------
local function TopLevel(f)
    local ok, parent = pcall(f.GetParent, f)
    if not (ok and parent) then return false end
    local ok2, grand = pcall(parent.GetParent, parent)
    return ok2 and (grand == UIParent or grand == nil)
end
S.TopLevel = TopLevel

--- Our soft shadow round a frame of Blizzard's: frames of our own, below it.
function S.Shadow(f, size)
    local d = S.D(f)
    if d.shadow or not (T.Shadow and f.GetFrameLevel) then return end
    d.shadow = S.Ours(T.Shadow(f, size or 12))
end

R{
    name = "dialogBorder",
    layout = "Dialog",
    paint = function(f, p)
        p:Fade()
        p:FadeSlice()
        if TopLevel(f) then
            p:Surface("window")
            S.Shadow(f)
        else
            p:Surface("raised")
        end
    end,
}

--------------------------------------------------------------------------------
--  Game dialog           StaticPopupTemplate (Blizzard_StaticPopup_Game): the
--      confirmations (unlearn, delete, sell, invite). A BG frame of two atlases
--      Blizzard sets in OnLoad (GameDialogBackgroundTop, the diamond border, and
--      UI-DialogBox-Background-Dark), both in S.ORNATE, and nothing else, so
--      once they were down the dialog was a shadowless see-through box.
--      Ours: a window, with its shadow.
--
--  Dialog button         StaticPopupButtonTemplate: file art
--      (UI-DialogBox-Button-Up/-Down/-Disabled/-Highlight) and a Flash glow
--      for PulseAnim. Ours: the button Look, the first button (the one that
--      does the thing) primary.
--------------------------------------------------------------------------------
R{
    name = "gameDialog",
    keys = { "BG", "ButtonContainer", "CoverFrame", "EditBox" },
    paint = function(f, p)
        -- The alert icon and the progress bar are content.
        p:Fade(nil, { f.AlertIcon, f.ProgressBarFill, f.ProgressBarBorder })
        p:FadeSlice()
        if S.Alive(f.BG) then S.PainterFor(f.BG):Fade() end
        p:Surface("window")
        if TopLevel(f) then S.Shadow(f) end
        if f.Text then p:Label(f.Text, "text") end
        if f.SubText then p:Label(f.SubText, "textMuted") end
    end,
}

R{
    name = "dialogButton",
    type = "Button",
    file = { normal = "Interface\\Buttons\\UI-DialogBox-Button-Up" },
    paint = function(b, p)
        S.Blank(b)
        p:Fade()
        if b.Flash then StripArt(b.Flash) end
        local primary = b.GetID and b:GetID() == 1
        local look = primary and LOOK.buttonPrimary or LOOK.button
        local r = look.rest
        p:Fill(r.fill ~= "none" and r.fill or "surface2")
        p:Border(r.edge ~= "none" and r.edge or "borderStrong")
        local fs = b.Text or (b.GetFontString and b:GetFontString())
        p:Label(fs)
        p:States(look, { label = fs })
    end,
}


--------------------------------------------------------------------------------
-- 11b. Dialog header      DialogHeaderTemplate, 17 inherits: the metal banner over a dialog
--     Its title becomes our title bar: the banner art goes, a strip in the
--     title bar colour runs across the top of the dialog under it, with the
--     divider rule below, and the title sits centred in it in gold. The
--     strip is ours, drawn on the header and anchored to the dialog it
--     crowns; nothing of Blizzard's moves except the title, re-seated within
--     its own header (Painter:Reseat), because the banner hung 11px above
--     the dialog (DialogTemplates.xml, Anchor TOP y="11") and the title with
--     it.
--
--     Fingerprinted on headerTextPadding, the KeyValue UpdateWidth reads.
--------------------------------------------------------------------------------
local TITLE_BAR = 32      -- as U.Window's

R{
    name = "dialogHeader",
    keys = { "LeftBG", "RightBG", "CenterBG", "Text" },
    -- Present, not typed: the survey keeps every KeyValue as a string.
    test = function(h) return h.headerTextPadding ~= nil end,
    paint = function(h, p)
        p:Fade()
        p:Label(h.Text, "title", true)
        local ok, win = pcall(h.GetParent, h)
        if not (ok and S.Alive(win) and h.CreateTexture) then return end
        -- How far the header stands above the dialog: its own anchor, 11px
        -- in the template, read from the frames when they have been laid out.
        local lift = 11
        local ht, wt = S.Num(h.GetTop and h:GetTop()), S.Num(win.GetTop and win:GetTop())
        if ht and wt then lift = ht - wt end
        local tall = S.Num(h.Text.GetStringHeight and h.Text:GetStringHeight()) or 14
        p:Reseat(h.Text, { { "TOP", 0, -(lift + 1 + TITLE_BAR / 2 - tall / 2) } })
        local d = S.D(h)
        if not d.bar then
            d.bar = S.Ours(h:CreateTexture(nil, "BACKGROUND", nil, -8))
            d.bar:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -1)
            d.bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -1, -1)
            d.bar:SetHeight(TITLE_BAR)
            d.rule = S.Ours(h:CreateTexture(nil, "BORDER"))
            d.rule:SetPoint("TOPLEFT", d.bar, "BOTTOMLEFT")
            d.rule:SetPoint("TOPRIGHT", d.bar, "BOTTOMRIGHT")
            d.rule:SetHeight(1)
            local function Paint()
                local r = T.Resolve(LOOK.window)
                d.bar:SetColorTexture(T.C4(r.titleBar))
                d.rule:SetColorTexture(T.C4(r.divider))
            end
            Paint()
            T.Watch(d.bar, Paint)
        end
    end,
}

--------------------------------------------------------------------------------
-- 12, 13, 14. Panels, in three grades.
--
--     There used to be ONE part here, fingerprinted on keys = { "NineSlice" }
--     and nothing else, registered last. Because a nineslice is how Blizzard
--     draws any bordered box at all, it claimed 106 templates across 398
--     inherit sites: every tooltip, every inset, sliders, the chat config
--     boxes, the auction house panels, the collections backgrounds. All of
--     them were painted surface0 with a border and given a window title.
--     A slider drawn as a window. An inset the same colour as its parent.
--     That single over-broad fingerprint was most of the "hodge podge".
--
--     Split by how sure we are what the frame is:
--       window       Blizzard says it is a window (layoutType)
--       panel        it is not labelled, but it has window furniture
--       ninesliceBox anything else with a nineslice: a bordered box, so it
--                    gets a raised surface and a border, and NO title
--
--     Tooltips, sliders, insets and dialogs never reach these: they are
--     claimed by their own parts above.
--------------------------------------------------------------------------------

--- WHERE does Blizzard draw this window's background?
---
--- Normally `frame.Bg` is a texture on the frame itself and the answer is
--- the frame. But a frame can be chrome drawn OVER content, and Blizzard's
--- own answer in that case is to move the background somewhere lower.
--- Blizzard_WorldMap.lua, line 28:
---
---     self.BorderFrame.Bg:SetParent(self);
---
--- WorldMapFrame.BorderFrame inherits PortraitFrameTemplateMinimizable, so
--- every fingerprint reads it as an ordinary window, and it is declared
--- frameStrata="HIGH" setAllPoints="true". Painting an opaque fill on it
--- covered the map, the nav bar, the zone crumbs and every overlay button.
--- Blizzard reparents the Bg down to WorldMapFrame, where it draws behind
--- the canvas.
---
--- So we follow the Bg. In the ordinary case it leads back to the frame; on
--- the map it leads to WorldMapFrame. One rule, no special case, and it is
--- Blizzard telling us the answer rather than us guessing.
---
--- The first attempt at this simply skipped the fill when Blizzard had
--- hidden the Bg. That was wrong in the other direction: the map then had no
--- background at all.
local function FillTarget(f)
    local bg = f.Bg
    if type(bg) ~= "table" or not bg.GetParent then return f end
    local ok, parent = pcall(bg.GetParent, bg)
    if ok and type(parent) == "table" and S.Alive(parent) then return parent end
    return f
end
S.FillTarget = FillTarget

--------------------------------------------------------------------------------
--  The title bar of a portrait window
--
--  PortraitFrameTemplate and ButtonFrameTemplate (thirty of the windows a
--  player opens: mail, merchant, quests, friends, the spellbook...) keep their
--  title in a TitleContainer 20px tall at y -1, and their background starts at
--  y -21 (SharedUIPanelTemplates.xml). That band is the title bar already, so
--  ours is drawn into it, in the window Look's title bar colour with the
--  divider under it, as U.Window's and the game menu's are. Nothing of
--  Blizzard's moves for it.
--
--  The title is centred in the container, and the container runs from x 58
--  (room for the portrait, which we hide) to -24, so the text sat 17px right
--  of the window's centre. It is re-seated within its own container, widened
--  on the left by the difference, which puts its centre on the window's.
--  Blizzard re-anchors the container itself (TitledPanelMixin:SetTitleOffsets,
--  ButtonFrameTemplate_HidePortrait and _ShowPortrait: 58/-24 or 0/0), so the
--  offsets are read from its anchors each time, after any of those and on
--  show, never assumed.
--------------------------------------------------------------------------------
-- The height of the close and maximise buttons (UIPanelCloseButtonNoScripts
-- and MaximizeMinimizeButtonFrameTemplate are both 24x24), so they sit flush
-- in the band rather than hanging over it. It was 20, which left Blizzard's
-- 24px buttons poking out below the title bar on every window.
local TITLE_BAND = 24
S.TITLE_BAND = TITLE_BAND   -- packs lay bands under it

local function ContainerOffsets(tc)
    local left, right = 58, 24
    local ok, n = pcall(tc.GetNumPoints, tc)
    for i = 1, (ok and S.Num(n) or 0) do
        local okP, pt, _, _, x = pcall(tc.GetPoint, tc, i)
        x = okP and S.Num(x)
        if x then
            if pt == "TOPLEFT" or pt == "LEFT" then left = x
            elseif pt == "TOPRIGHT" or pt == "RIGHT" then right = -x end
        end
    end
    return left, right
end

local titled = setmetatable({}, { __mode = "k" })   -- window -> its re-centre

local function TitleBar(f, p, tc, title)
    local d = S.D(f)
    if not d.titleBar and f.CreateTexture then
        d.titleBar = S.Ours(f:CreateTexture(nil, "BACKGROUND", nil, -6))
        d.titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        d.titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        d.titleBar:SetHeight(TITLE_BAND)
        d.titleRule = S.Ours(f:CreateTexture(nil, "BORDER", nil, -8))
        d.titleRule:SetPoint("TOPLEFT", d.titleBar, "BOTTOMLEFT")
        d.titleRule:SetPoint("TOPRIGHT", d.titleBar, "BOTTOMRIGHT")
        d.titleRule:SetHeight(1)
        local function Paint()
            local r = T.Resolve(LOOK.window)
            d.titleBar:SetColorTexture(T.C4(r.titleBar))
            d.titleRule:SetColorTexture(T.C4(r.divider))
        end
        Paint()
        T.Watch(d.titleBar, Paint)
    end
    if not (title and title.GetParent and title:GetParent() == tc) then return end
    local tp = S.PainterFor(tc)
    local function Centre()
        local left, right = ContainerOffsets(tc)
        tp:Reseat(title, { { "TOP", 0, -(5 + (TITLE_BAND - 20) / 2) }, { "LEFT", -(left - right), 0 }, { "RIGHT", 0, 0 } })
    end
    titled[f] = Centre
    Centre()
    p:Hook("OnShow", Centre)
    p:After("SetTitleOffsets", Centre)
end

-- The portrait toggles are global functions, taking the window.
local portraitHooked = false
local function HookPortraitToggles()
    if portraitHooked then return end
    portraitHooked = true
    for _, fn in ipairs({ "ButtonFrameTemplate_HidePortrait", "ButtonFrameTemplate_ShowPortrait" }) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function(win) local c = titled[win]; if c then c() end end)
        end
    end
end

--- Shared by window and panel. Their treatment is the same; only our
--- confidence about what the frame is differs.
--- A window of its own (not a panel inside another): its parent is UIParent,
--- or it is chrome covering one that is (the world map's BorderFrame).
local function WindowTop(f)
    local ok, parent = pcall(f.GetParent, f)
    if not (ok and parent) then return false end
    if parent == UIParent then return true end
    local ok2, grand = pcall(parent.GetParent, parent)
    return ok2 and grand == UIParent
end

local function PaintWindow(f, p)
    if WindowTop(f) then S.Shadow(f) end
    p:Fade()
    p:FadeSlice()
    p:FadeKeys("Bg", "TopTileStreaks", "PortraitContainer", "portrait", "Center")
    if type(f.PortraitContainer) == "table" then p:Fade(f.PortraitContainer) end
    local W = LOOK.window.rest
    p:Fill(W.fill, nil, nil, FillTarget(f))
    p:Border(W.edge)
    local title = (type(f.TitleContainer) == "table" and f.TitleContainer.TitleText) or f.TitleText
    if title then p:Label(title, W.title, true) end
    if type(f.TitleContainer) == "table" then
        p:Fade(f.TitleContainer)
        HookPortraitToggles()
        TitleBar(f, p, f.TitleContainer, title)
        -- The close button, flush in the band's corner inside our border.
        -- Blizzard anchors it TOPRIGHT x=-2 y=1 (Camelot's
        -- UIPanelCloseButtonDefaultAnchorsMixin), a pixel above the window;
        -- the maximise button hangs off its left, so it follows.
        local close = rawget(f, "CloseButton")
        if type(close) == "table" and close.GetPoint then
            local ok, pt, rel = pcall(close.GetPoint, close, 1)
            if ok and pt == "TOPRIGHT" and (rel == f or rel == nil) then
                p:Reseat(close, { { "TOPRIGHT", -1, -1 } })
            end
        end
    end
end

--- Does this frame carry the furniture a window has?
local FURNITURE = { "TitleContainer", "TitleText", "PortraitContainer", "portrait",
                    "CloseButton", "Inset", "TitleBg" }
local function HasFurniture(f)
    for _, k in ipairs(FURNITURE) do
        if type(f[k]) == "table" then return true end
    end
    return false
end

-- 12. Window: Blizzard's own label. 34 templates.
R{
    name = "window",
    layout = { "PortraitFrameTemplate", "PortraitFrameTemplateMinimizable",
               "ButtonFrameTemplateNoPortrait", "HeldBagLayout",
               "SimplePanelTemplate", "SelectionFrameTemplate" },
    paint = PaintWindow,
}

-- 13. Panel: unlabelled, but it looks and behaves like a window.
R{
    name = "panel",
    keys = { "NineSlice" },
    test = HasFurniture,
    paint = PaintWindow,
}

-- 14. Nineslice box: a bordered container and nothing more. Raised surface,
--     a border, and deliberately no title: there is no title to find, and
--     labelling a random FontString as one is how the old part put gold text
--     in places that had none.
R{
    name = "ninesliceBox",
    keys = { "NineSlice" },
    paint = function(f, p)
        p:Fade()
        p:FadeSlice()
        p:FadeKeys("Bg", "Background", "Center")
        p:Surface("raised", nil, nil, FillTarget(f))
    end,
}
