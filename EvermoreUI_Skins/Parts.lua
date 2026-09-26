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
    d.sep = S.Ours(T.Chevron(b, 4))
    d.sep:Point("right")
    local function Paint(self) self:SetColorLines(T.RGBA("textMuted")) end
    Paint(d.sep)
    T.Watch(d.sep)
    d.sep.Paint = Paint
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
    "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar",
    "Interface\\SpellBook\\SpellBook-SkillLineTab",
    "Interface\\Store\\Store-Main",
}

local function IsOrnate(region)
    for _, pattern in ipairs(S.ORNATE) do
        if S.ArtIs(region, pattern) then return true end
    end
    for _, path in ipairs(S.ORNATE_FILES) do
        if S.ArtIsFile(region, path) then return true end
    end
    return false
end
S.IsOrnate = IsOrnate

--------------------------------------------------------------------------------
--  0a. Tooltips           layoutType Tooltip*, 46 templates
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
        p:Fill("surfaceSunk")
        p:Border("border")
        local thumb = sl.GetThumbTexture and select(2, pcall(sl.GetThumbTexture, sl))
        if thumb and thumb.SetColorTexture then
            if thumb.SetAtlas then pcall(thumb.SetAtlas, thumb, nil) end
            thumb:SetColorTexture(T.RGBA("accent"))
            S.D(thumb).token = "accent"
            T.Watch(thumb)
            thumb.Paint = function(self) self:SetColorTexture(T.RGBA("accent")) end
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
        p:Fill("surface2", 0)
        p:Glyph("close", 10, "textMuted")
        p:States{ hover = "danger", pressed = "danger" }
        local d = S.D(b)
        p:Hook("OnEnter", function() if d.glyph then d.glyph:SetVertexColor(T.RGBA("onAccent")) end end)
        p:Hook("OnLeave", function() if d.glyph then d.glyph:SetVertexColor(T.RGBA("textMuted")) end end)
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
        p:Fill("surface2", 0)
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
        local function Tint(token) d.icon:SetVertexColor(T.RGBA(token)) end
        d.Tint = Tint
        Tint("textMuted")
        T.Watch(d.icon)
        d.icon.Paint = function() Tint("textMuted") end
        p:States{ hover = "surface3", pressed = "surfaceSunk" }
        p:Hook("OnEnter", function() Tint("text") end)
        p:Hook("OnLeave", function() Tint("textMuted") end)
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
            if d.fill then d.fill:SetColorTexture(T.RGBA(on and "surface2" or "surface1")) end
            if tab.Text then
                tab.Text:SetTextColor(T.RGBA(off and "textDisabled" or (on and "title" or "textMuted")))
            end
        end
        d.Sync = Sync
        S.HookPanelTabs()
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
        p:States{ hover = "surface3", pressed = "surfaceSunk", disabled = "surface1" }
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
        p:States{ hover = "surface3", pressed = "surfaceSunk", disabled = "surface1" }
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
        local RING = 16
        if not d.ring then
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
        d.dot:SetSize(math.max(math.floor(side * 0.42), 3), math.max(math.floor(side * 0.42), 3))
        local function Sync()
            local on = type(b.GetChecked) == "function" and select(2, pcall(b.GetChecked, b)) or false
            d.ring:SetVertexColor(T.RGBA(on and "accent" or "borderStrong"))
            d.dot:SetVertexColor(T.RGBA("accent"))
            d.dot:SetShown(on and true or false)
        end
        d.Sync = Sync
        p:After("SetChecked", Sync)
        p:Hook("OnClick", Sync)
        p:Hook("OnShow", Sync)
        p:Label(b.Text)
        T.Watch(d.ring); d.ring.Paint = Sync
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
        local BOX = 16
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
        d.tick:SetSize(side - 4, side - 4)
        local function Sync()
            local on = type(b.GetChecked) == "function" and select(2, pcall(b.GetChecked, b)) or false
            d.box:SetColorTexture(T.RGBA(on and "accent" or "surfaceSunk"))
            d.tick:SetVertexColor(T.RGBA("onAccent"))
            d.tick:SetShown(on and true or false)
        end
        d.Sync = Sync
        p:After("SetChecked", Sync)
        p:Hook("OnClick", Sync)
        p:Hook("OnShow", Sync)
        p:Border("borderStrong", nil, d.boxFrame)
        p:Label(b.Text)
        T.Watch(d.box); d.box.Paint = Sync
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
            d.chev = S.Ours(T.Chevron(dd, 5))
            d.chev:SetPoint("RIGHT", dd, "RIGHT", -6, 0)
            d.chev:Point("down")
            d.chev:SetColorLines(T.RGBA("textMuted"))
            T.Watch(d.chev)
            d.chev.Paint = function(self) self:SetColorLines(T.RGBA("textMuted")) end
        end
        p:States{ hover = "surface3", disabled = "surface1" }
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
local SEARCH_PAD   = 6    -- clear space inside our border
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
        e:SetTextColor(T.RGBA("text"))

        -- The magnifying glass is content, not chrome: recolour, never hide.
        if e.searchIcon then
            e.searchIcon:SetVertexColor(T.RGBA("textMuted"))
            S.D(e.searchIcon).muted = nil
            e.searchIcon:SetAlpha(1)
            p:Reseat(e.searchIcon, { { "LEFT", SEARCH_PAD, 0 } })
        end

        -- The clear button's own art is Blizzard's little x; keep it, move it
        -- off our border and mute it to match.
        if e.clearButton then
            local icon = e.clearButton.Icon
            if icon then
                icon:SetVertexColor(T.RGBA("textMuted"))
                S.D(icon).muted = nil
                icon:SetAlpha(1)
            end
            p:Reseat(e.clearButton, { { "RIGHT", -SEARCH_PAD, 0 } })
        end

        -- The placeholder is a two-point FontString, so both corners move or
        -- it loses its width.
        if e.Instructions then
            p:Label(e.Instructions, "textDisabled")
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
        e:SetTextColor(T.RGBA("text"))

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
        e:SetTextColor(T.RGBA("text"))
        if e.Instructions then p:Label(e.Instructions, "textDisabled") end
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
                    sd.chev = S.Ours(T.Chevron(step, 4))
                    sd.chev:SetPoint("CENTER")
                    sd.chev:Point(k == "Back" and "up" or "down")
                    local function Paint(self) self:SetColorLines(T.RGBA("textMuted")) end
                    Paint(sd.chev)
                    T.Watch(sd.chev)
                    sd.chev.Paint = Paint
                    if step.HookScript then
                        step:HookScript("OnEnter", function() sd.chev:SetColorLines(T.RGBA("text")) end)
                        step:HookScript("OnLeave", function() sd.chev:SetColorLines(T.RGBA("textMuted")) end)
                    end
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
            d.trackFill:SetColorTexture(T.RGBA("surfaceSunk"))
            T.Watch(d.trackFill)
            d.trackFill.Paint = function(self) self:SetColorTexture(T.RGBA("surfaceSunk")) end
        end
        local thumb = track.Thumb
        if thumb then
            for _, r in ipairs(S.Regions(thumb)) do S.Mute(r) end
            local td = S.D(thumb)
            if not td.fill and thumb.CreateTexture then
                td.fill = S.Ours(thumb:CreateTexture(nil, "ARTWORK"))
                td.fill:SetAllPoints(thumb)
            end
            if td.fill then
                td.fill:SetColorTexture(T.RGBA("surface3"))
                T.Watch(td.fill)
                td.fill.Paint = function(self) self:SetColorTexture(T.RGBA("surface3")) end
            end
            -- The thumb is redrawn from its own texture keys on hover.
            if thumb.HookScript then
                thumb:HookScript("OnEnter", function() if td.fill then td.fill:SetColorTexture(T.RGBA("accent")) end end)
                thumb:HookScript("OnLeave", function() if td.fill then td.fill:SetColorTexture(T.RGBA("surface3")) end end)
            end
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
        p:Fill("surface1")
        p:Border("border")
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

        p:Fill("surface1", 0)
        p:Label(b.text, "textMuted")
        p:States{ hover = "surface3", pressed = "surfaceSunk" }

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
            local function Paint(self) self:SetColorLines(T.RGBA("textMuted")) end
            Paint(cd.chev)
            T.Watch(cd.chev)
            cd.chev.Paint = Paint
        end
    end,
}

--------------------------------------------------------------------------------
--  9b. Legacy scroll bar  Slider-based, 11 templates
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
        p:Fill("surfaceSunk")

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
                    sd.chev = S.Ours(T.Chevron(step, 4))
                    sd.chev:SetPoint("CENTER")
                    sd.chev:Point(dir)
                    local function Paint(self) self:SetColorLines(T.RGBA("textMuted")) end
                    Paint(sd.chev)
                    T.Watch(sd.chev)
                    sd.chev.Paint = Paint
                    if step.HookScript then
                        step:HookScript("OnEnter", function() sd.chev:SetColorLines(T.RGBA("text")) end)
                        step:HookScript("OnLeave", function() sd.chev:SetColorLines(T.RGBA("textMuted")) end)
                    end
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
            thumb:SetColorTexture(T.RGBA("surface3"))
            local function Paint(self) self:SetColorTexture(T.RGBA("surface3")) end
            T.Watch(thumb)
            thumb.Paint = Paint
            if bar.HookScript then
                bar:HookScript("OnEnter", function() thumb:SetColorTexture(T.RGBA("accent")) end)
                bar:HookScript("OnLeave", function() thumb:SetColorTexture(T.RGBA("surface3")) end)
            end
        end
    end,
}

--------------------------------------------------------------------------------
-- 10. Inset               layoutType "InsetFrameTemplate", 19 templates / 49 inherits
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
        p:Fill("surfaceSunk")
        p:Border("border")
    end,
}

--------------------------------------------------------------------------------
-- 11. Dialog border       layoutType "Dialog", 5 templates / 44 inherits
--     Dead for the same reason as the inset: its Bg is
--     Interface\DialogFrame\UI-DialogBox-Background, a file.
--------------------------------------------------------------------------------
R{
    name = "dialogBorder",
    layout = "Dialog",
    paint = function(f, p)
        p:Fade()
        p:FadeSlice()
        p:Fill("surface1")
        p:Border("border")
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

--- Shared by window and panel. Their treatment is the same; only our
--- confidence about what the frame is differs.
local function PaintWindow(f, p)
    p:Fade()
    p:FadeSlice()
    p:FadeKeys("Bg", "TopTileStreaks", "PortraitContainer", "portrait", "Center")
    if type(f.PortraitContainer) == "table" then p:Fade(f.PortraitContainer) end
    p:Fill("surface0", nil, nil, FillTarget(f))
    p:Border("border")
    local title = (type(f.TitleContainer) == "table" and f.TitleContainer.TitleText) or f.TitleText
    if title then p:Label(title, "title") end
    if type(f.TitleContainer) == "table" then p:Fade(f.TitleContainer) end
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

-- 12. Window: Blizzard's own label. 30 templates.
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
        p:Fill("surface1", nil, nil, FillTarget(f))
        p:Border("border")
    end,
}
