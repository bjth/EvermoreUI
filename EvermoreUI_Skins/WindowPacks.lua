if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  WindowPacks.lua
--  The packs themselves. One block per window, opted in one at a time.
--
--  A window earns a pack only when the generic layer has been given its
--  chance and something is still wrong. Before adding one:
--
--    1. Open the window and run `/evui skin this`. It lists what the parts
--       claimed and every texture still drawing that nothing accounted for.
--    2. If the loose art is an ATLAS, add a pattern to S.ORNATE in Parts.lua
--       and every window in the game benefits.
--    3. If it is a FILE used by several windows, add it to S.ORNATE_FILES.
--    4. Only if it is that window's own art, or the fix needs a decision
--       about layout, write a pack here.
--
--  Reach for S.ORNATE and S.ORNATE_FILES first every time. A pattern in
--  those lists is worth ten packs, and a pack is a maintenance burden that
--  only that one window pays off.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S, T = ns.S, EV.Theme
if not S then return end

local P = S.Pack

--- A square button in our button look: its art faded (all of it, or all but
--- `keep`), our fill and edge, and a chevron pointing `dir` if it has one.
--- `on` says when it is on (default: Blizzard's isActive). Once per button.
--- Returns its data and a painter.
local function OverlayButton(k, b, dir, keep, on)
    if not S.Alive(b) then return end
    local d = S.D(b)
    local p = S.PainterFor(b)
    if d.overlay then return d, p end
    d.overlay = true
    S.claimed[b] = S.claimed[b] or "pack"
    S.Blank(b)
    p:Fade(nil, keep)
    local rest = T.LOOK.button.rest
    p:Fill(rest.fill)
    p:Border(rest.edge)
    local opts = { on = on or function() return b.isActive == true end }
    if dir then
        d.chev = S.Ours(T.Chevron(b, 5))
        d.chev:SetPoint("CENTER")
        d.chev:Point(dir)
        opts.chev = d.chev
    end
    p:States(T.LOOK.button, opts)
    return d, p
end

--------------------------------------------------------------------------------
--  Shared bits
--------------------------------------------------------------------------------

--- Blizzard's row separators are bare colour textures: no file, no atlas, so
--- nothing generic can recognise one. On a row that is otherwise stripped the
--- only texture left in that shape is the rule itself, so identify it that
--- way and give it our hairline colour instead of its own brown.
local function Rule(row)
    for _, r in ipairs(S.Regions(row)) do
        if not S.ours[r] and r.GetObjectType and r:GetObjectType() == "Texture"
           and r.SetColorTexture and not S.D(r).ruled then
            local okA, atlas = pcall(r.GetAtlas, r)
            local okT, tex = pcall(r.GetTexture, r)
            local bare = (not okA or atlas == nil or atlas == "")
                     and (not okT or tex == nil or tex == "")
            if bare then
                S.D(r).ruled = true
                local function Paint(self2) self2:SetColorTexture(T.RGBA("divider")) end
                Paint(r)
                T.Watch(r, Paint)
            end
        end
    end
end

--- A band of our own across a window: a strip in the rail colour with a
--- hairline on one side (`rule` = "top" or "bottom"), under everything the
--- window draws. The tool bars and footers packs lay out controls on, so that
--- a row of tabs or a pager sits ON something rather than in space. Created
--- once per host and key; `place` anchors it (it is only ever ours to move).
local BAND_FILL = { "surfaceSunk", a = 0.5 }    -- between the window and a well: the kit's rail

local function Band(host, key, rule, place)
    local d = S.D(host)
    d.bands = d.bands or {}
    local b = d.bands[key]
    if not b then
        b = S.Ours(CreateFrame("Frame", nil, host))
        b:EnableMouse(false)
        b:SetFrameLevel(host:GetFrameLevel())
        b.fill = S.Ours(b:CreateTexture(nil, "BACKGROUND", nil, -5))
        b.fill:SetAllPoints(b)
        b.rule = S.Ours(b:CreateTexture(nil, "BORDER", nil, -8))
        if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(b.rule) end
        if rule == "top" then
            b.rule:SetPoint("BOTTOMLEFT", b, "TOPLEFT")
            b.rule:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
        else
            b.rule:SetPoint("TOPLEFT", b, "BOTTOMLEFT")
            b.rule:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT")
        end
        local function Paint()
            b.fill:SetColorTexture(S.Colour(BAND_FILL))
            b.rule:SetColorTexture(S.Colour("border"))
            b.rule:SetHeight((EV.Pixel and EV.Pixel.One and EV.Pixel:One(b)) or 1)
        end
        Paint()
        T.Watch(b.fill, Paint)
        d.bands[key] = b
    end
    b:ClearAllPoints()
    place(b)
    return b
end

--------------------------------------------------------------------------------
--  MailFrame
--
--  What the generic layer cannot reach here, all confirmed against
--  Blizzard's XML rather than guessed:
--
--    * InboxFrameBg is Interface\MailFrame\UI-MailFrameBG, this window's own
--      sheet. It is not worth a global entry in S.ORNATE_FILES because no
--      other window uses it.
--    * The stationery backgrounds on the send pane are set in Lua, so they
--      carry no atlas and no file in the XML at all. Nothing but a pack can
--      know they are there.
--    * PrevPageButton and NextPageButton carry the spellbook's page art, so
--      the pageButton part has them.
--    * The attachment slots are a grid of 16 buttons whose slot art is
--      Blizzard's, and which we want as our own wells.
--    * The seven inbox rows are the reason an empty mailbox looked like
--      seven empty boxes. MailItemTemplate is a Frame that is ALWAYS shown:
--      InboxMixin:Update only hides $parentButton inside it (MailFrame.lua:430).
--      So with no mail the row still draws its whole BACKGROUND layer, which
--      is two Interface\MailFrame\MailItemBorder pieces (42x48 left, 263x48
--      right) and a 322x2 rule at Color r="0.33" g="0.16" b="0" a=".3"
--      (MailFrame.xml:14-35). On parchment that is the paper; on our surface
--      it is seven orange-edged boxes with nothing in them.
--
--      The border pieces go in S.ORNATE_FILES: that sheet is row chrome end
--      to end and nothing else uses it. The rule cannot go anywhere generic,
--      because it has no file and no atlas to match on -- it is a bare
--      colour. So the pack recolours it to our divider token, which is what
--      it was always for: a hairline between rows.
--------------------------------------------------------------------------------
P{
    name  = "MailFrame",
    addon = "Blizzard_MailFrame",
    apply = function(f, k)
        local inbox = f.InboxFrame or InboxFrame
        if inbox then
            k:Art(inbox, "Interface\\MailFrame\\UI-MailFrameBG")
        end

        -- Inbox rows. INBOXITEMS_TO_DISPLAY is 7; read it rather than assume.
        for i = 1, (_G.INBOXITEMS_TO_DISPLAY or 7) do
            local row = _G["MailItem" .. i]
            if row then Rule(row) end
        end

        local send = f.SendMail or SendMailFrame
        if send then
            -- Stationery: no atlas, no file in the XML. Fade by position.
            for _, name in ipairs({ "SendStationeryBackgroundLeft",
                                    "SendStationeryBackgroundRight" }) do
                local r = _G[name]
                if r then S.Mute(r) end
            end
            for i = 1, 16 do
                local slot = _G["SendMailAttachment" .. i]
                if slot then
                    S.Blank(slot)
                    k:Fade(slot)
                    k:Fill(slot, "surfaceSunk"):Border(slot, "border")
                end
            end
        end
    end,
}

--------------------------------------------------------------------------------
--  FriendsFrame
--
--  The one window the architecture doc has always used as its example, and
--  the one that shows the restraint: not a single SetPoint in it. Everything
--  here is paint.
--
--  Blizzard keeps the tab header, the battletag row and the status dropdown
--  in the band where the portrait was, which is exactly why we do not
--  reclaim that band. Leave the layout alone.
--------------------------------------------------------------------------------
P{
    name  = "FriendsFrame",
    addon = "Blizzard_FriendsFrame",
    apply = function(f, k)
        -- The battle.net portrait is art, not content.
        local icon = _G.FriendsFrameIcon
        if icon then S.Mute(icon) end

        local header = f.FriendsTabHeader
        if header then
            k:Fade(header)
            if header.BattlenetFrame then k:Fade(header.BattlenetFrame) end
        end

        -- The who-list column tabs are WhoFrame-ColumnTabs, a file sheet
        -- already in S.ORNATE_FILES, so the walk takes those down. What it
        -- cannot do is give the header row a surface, because nothing about
        -- those frames says "header".
        for _, name in ipairs({ "WhoFrameColumnHeader1", "WhoFrameColumnHeader2",
                                "WhoFrameColumnHeader3", "WhoFrameColumnHeader4" }) do
            local h = _G[name]
            if h then
                k:Fade(h)
                k:Fill(h, "surface2"):Border(h, "border")
                if h.GetFontString then
                    local fs = select(2, pcall(h.GetFontString, h))
                    if fs then k:Label(fs, "textMuted") end
                end
            end
        end

        local ignore = f.IgnoreListWindow
        if ignore then k:Panel(ignore, "surfaceSunk") end
    end,
}

--------------------------------------------------------------------------------
--  WorldMapFrame
--
--  Read out of Blizzard_WorldMap.xml and Blizzard_WorldMap.lua rather than
--  guessed. Two facts about this window matter:
--
--    * BorderFrame is declared frameStrata="HIGH" setAllPoints="true", so it
--      covers the entire window, canvas included.
--    * Blizzard_WorldMap.lua:28 does `self.BorderFrame.Bg:SetParent(self)`,
--      moving the background off that HIGH frame and onto WorldMapFrame,
--      where it draws behind the canvas.
--
--  `FillTarget` in Parts.lua now follows the Bg, so the generic layer paints
--  WorldMapFrame and not BorderFrame, and the map is visible with a real
--  background behind it. No pack needed for that any more, and the earlier
--  `NoFill` here was papering over the wrong fix: it removed the background
--  instead of moving it.
--
--  What is left is this window's own art.
--------------------------------------------------------------------------------
P{
    name  = "WorldMapFrame",
    addon = "Blizzard_WorldMap",
    apply = function(f, k)
        local border = f.BorderFrame
        if border then
            -- The inner tile strip under the title, and the dim overlay.
            if border.InsetBorderTop then S.Mute(border.InsetBorderTop) end
            if border.Underlay then S.Mute(border.Underlay) end
        end

        -- The blackout behind the maximised map is Blizzard's dimmer, not
        -- chrome: leave it working, take it to our own shade.
        local blackout = f.BlackoutFrame
        if blackout and blackout.Blackout then
            blackout.Blackout:SetColorTexture(T.RGBA("surfaceSunk", 0.85))
        end

        -- OverscrollBG is the tiled backing the canvas floats on
        -- (gamepad-mapquestlog-bgtile-2k plus four vignettes). It is this
        -- window's own art and no pattern would be worth sharing.
        local over = f.OverscrollBG
        if over then
            k:Fade(over)
            k:Fill(over, "surfaceSunk")
        end

        -- The nav bar's left inset tracks the PORTRAIT, not the content.
        -- Blizzard_WorldMap.lua:
        --     Minimize()  NavBar TOPLEFT ... 64, -25   + SetPortraitShown(true)
        --     Maximize()  NavBar TOPLEFT ...  8, -25   + SetPortraitShown(false)
        -- We hide the portrait in both states, so the 64 is a gap with
        -- nothing in it. Take the maximised inset in both cases, keeping the
        -- BOTTOMRIGHT anchor (Kit:Anchors, because Move would clear it and
        -- collapse the bar) and Blizzard's own NAVBAR_X_OFFSET rather than a
        -- number of ours.
        local spacer = f.TitleCanvasSpacerFrame
        local function SeatNavBar()
            local bar, sp = f.NavBar, spacer
            if not (bar and sp) then return end
            local rightX = (WorldMapConstants and WorldMapConstants.NAVBAR_X_OFFSET) or -4
            k:Anchors(bar, {
                { "TOPLEFT",     sp, "TOPLEFT",      8, -25 },
                { "BOTTOMRIGHT", sp, "BOTTOMRIGHT", rightX,  9 },
            })
        end
        SeatNavBar()

        -- Blizzard re-anchors it on every maximise and minimise, so re-seat
        -- after theirs rather than fighting it.
        if not S.D(f).navSeated then
            S.D(f).navSeated = true
            k:After(f, "Minimize", SeatNavBar)
            k:After(f, "Maximize", SeatNavBar)
        end

        -- The canvas, the nav bar, the floor dropdown and the tracking
        -- buttons are all added in Lua by AddOverlayFrames, so the first
        -- sweep can run before any of them exist. Re-dress on show.
        if f.ScrollContainer then k:Dress(f.ScrollContainer) end
        if f.NavBar then k:Dress(f.NavBar) end

        -- The quest log's open and close arrow at the canvas's bottom right
        -- (WorldMapSidePanelToggleTemplate): two buttons, one shown at a
        -- time, each QuestCollapse art on a corner shadow. Ours: a button
        -- with a chevron the way the panel will go.
        local toggle = f.SidePanelToggle
        if toggle then
            OverlayButton(k, toggle.OpenButton, "left")
            OverlayButton(k, toggle.CloseButton, "right")
        end

        -- The waypoint pin button (WorldMapTrackingPinButtonTemplate): a
        -- minimap-style gold ring round the pin. The pin is the content and
        -- stays; the ring, the backing and the glow go, and SetActive, which
        -- showed the glow, shows our "on" instead.
        local pin = f.WorldMapTrackingPinButton
        if pin then
            local d, p = OverlayButton(k, pin, nil, { pin.Icon, pin.IconOverlay })
            if p and not d.pinHooked then
                d.pinHooked = true
                k:After(pin, "SetActive", function() if d.Repaint then d.Repaint() end end)
            end
        end
    end,
}

--------------------------------------------------------------------------------
--  TaxiFrame: the flight map Forever actually uses
--  (Blizzard_UIPanels_Game/Shared/TaxiFrame.xml, BasicFrameTemplateWithInset).
--
--  The map is drawn INTO the template's InsetBg: TaxiFrame.lua does
--  SetTaxiMap(self.InsetBg). When the walk first meets that texture it still
--  holds UI-Background-Marble, so the inset part mutes it as chrome, and the
--  map Blizzard paints into it afterwards stays at alpha 0. The whole window
--  then showed the 3D world through it, with the flight nodes floating on
--  top. InsetBg is content here and is put back on every show.
--
--  The frame's own art (Bg, TitleBg, the corner and edge pieces) is faded by
--  the walk and nothing claims the frame, so it also gets our surface, a
--  title strip over where TitleBg was (y -1 to -21 in BasicFrameTemplate),
--  a border, and a hairline round the map.
--------------------------------------------------------------------------------
local TAXI_TITLE_H = 21

local function Hairlines(host, around, token)
    local e = {}
    for i = 1, 4 do
        e[i] = S.Ours(host:CreateTexture(nil, "BORDER", nil, 6))
        if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(e[i]) end
    end
    e[1]:SetPoint("BOTTOMLEFT", around, "TOPLEFT");     e[1]:SetPoint("BOTTOMRIGHT", around, "TOPRIGHT")
    e[2]:SetPoint("TOPLEFT", around, "BOTTOMLEFT");     e[2]:SetPoint("TOPRIGHT", around, "BOTTOMRIGHT")
    e[3]:SetPoint("TOPRIGHT", around, "TOPLEFT");       e[3]:SetPoint("BOTTOMRIGHT", around, "BOTTOMLEFT")
    e[4]:SetPoint("TOPLEFT", around, "TOPRIGHT");       e[4]:SetPoint("BOTTOMLEFT", around, "BOTTOMRIGHT")
    local function Paint()
        local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(host)) or 1
        e[1]:SetHeight(px); e[2]:SetHeight(px); e[3]:SetWidth(px); e[4]:SetWidth(px)
        for _, t in ipairs(e) do t:SetColorTexture(T.RGBA(token)) end
    end
    Paint()
    T.Watch(e[1]); e[1].Paint = Paint
    return e
end

P{
    name  = "TaxiFrame",
    apply = function(f, k)
        -- The map. Content, never chrome.
        if f.InsetBg then f.InsetBg:SetAlpha(1) end

        k:Fill(f, "surface0")
        k:Border(f, "borderStrong")

        local d = S.D(f)
        if not d.taxiDressed then
            d.taxiDressed = true
            local strip = S.Ours(f:CreateTexture(nil, "BACKGROUND", nil, 1))
            strip:SetPoint("TOPLEFT"); strip:SetPoint("TOPRIGHT")
            strip:SetHeight(TAXI_TITLE_H)
            local function Paint() strip:SetColorTexture(T.RGBA("titleBar")) end
            Paint()
            T.Watch(strip); strip.Paint = Paint
            if f.InsetBg then Hairlines(f, f.InsetBg, "border") end
        end
    end,
}

--------------------------------------------------------------------------------
--  FlightMapFrame (Blizzard_FlightMap).
--
--  Built like the world map: a map canvas the full size of the window, with
--  BorderFrame (PortraitFrameTemplate, frameStrata HIGH, setAllPoints) laid
--  over it as chrome, and Bg moved off it onto the canvas
--  (FlightMapMixin:OnLoad: BorderFrame.Bg:SetParent(self)). There is no
--  background of its own: the map IS the window, and the frame it had was
--  the NineSlice and the AdventureMap_TopBorder strip, which covered the top
--  22px of map for the title.
--
--  The generic window part fades all of that, fills behind the canvas where
--  nothing can be seen, and draws a hairline that vanishes against terrain.
--  So: our own title strip over the top of the map, a divider under it, and
--  a border strong enough to read against a map.
--------------------------------------------------------------------------------
local FLIGHT_TITLE_H = 22     -- where Blizzard's TopBorder started (y -22)

P{
    name  = "FlightMapFrame",
    addon = "Blizzard_FlightMap",
    apply = function(f, k)
        local border = f.BorderFrame
        if not border then return end
        if border.TopBorder then S.Mute(border.TopBorder) end
        if border.Underlay then S.Mute(border.Underlay) end

        local d = S.D(border)
        if not d.flightTitle then
            local strip = S.Ours(border:CreateTexture(nil, "BACKGROUND", nil, 1))
            strip:SetPoint("TOPLEFT"); strip:SetPoint("TOPRIGHT")
            strip:SetHeight(FLIGHT_TITLE_H)
            local line = S.Ours(border:CreateTexture(nil, "BORDER", nil, 6))
            if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(line) end
            line:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
            line:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
            local function Paint()
                strip:SetColorTexture(T.RGBA("titleBar", 0.96))
                line:SetColorTexture(T.RGBA("borderStrong"))
                line:SetHeight((EV.Pixel and EV.Pixel.One and EV.Pixel:One(border)) or 1)
            end
            Paint()
            T.Watch(strip); strip.Paint = Paint
            d.flightTitle = strip
        end
        k:Border(border, "borderStrong")
    end,
}

--------------------------------------------------------------------------------
--  PlayerSpellsFrame: the spellbook (Blizzard_PlayerSpells/Camelot/SpellBook).
--
--  Blizzard's geometry, from Blizzard_PlayerSpellsFrame.xml,
--  Blizzard_SpellBookFrame.xml and Camelot's Blizzard_SpellBookTemplates.xml:
--
--    PlayerSpellsFrame     720 tall with the book open (spellBookHeight)
--    SpellBookFrame        702 tall, BOTTOMLEFT y=4: its top is 14 below ours
--    CategoryTabSystem     TOPLEFT x=70 y=-26 of the book
--    SettingsDropdown      15x16 arrow, TOPRIGHT x=-30 y=-27
--    SearchBox             300x30, RIGHT of the dropdown's LEFT x=-5 y=4
--    PagedSpellsFrame      from y=-50 of the book to its bottom
--      View1 / View2       680x590, TOPLEFT x=85 / TOPRIGHT x=-50, y=-45
--      PagingControls      BOTTOMRIGHT x=-75 y=40, 32px arrows and a label
--
--  So the tabs, the search box and a 15px arrow sat at three different
--  heights on the bare surface, with nothing behind them, and the pager
--  floated in the bottom corner. Ours, in the kit's structure:
--
--    a tool bar      under the title bar down to where the spells start
--                    (14 + 50 - the title band and its rule = 42px): the
--                    school tabs on its left, the filter button (30px, our
--                    button) and the search box (30px) on its right, all on
--                    its centre line
--    the page        the grid pulled up under the tool bar, and centred: the
--                    same margin both sides, and a rule between the two
--                    pages when the book is open wide
--    a footer        40px along the bottom holding the pager on its right
--
--  The school tabs are TabSystem tabs in square mode
--  (Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.lua): a 36px icon
--  centred on a 44x32 button. The button is left alone (a layout frame owns
--  it); the box is a square of its height, centred, the icon inside it.
--
--  The page art (the parchment) can be hidden with a Skins setting.
--------------------------------------------------------------------------------
local TAB_H = 32                 -- TabSystemButtonTemplate's height
local TAB_ICON = TAB_H - 8       -- inside a 1px border with a 3px gap
local TAB_W = 44                 -- the square-mode button: icon + 8

local BOOK = {
    top      = 14,               -- 720 - 702 - 4: the book's top below the window's
    spells   = 50,               -- PagedSpellsFrame's y in the book
    footer   = 40,
    pad      = 12,               -- band edge to its first and last control
    control  = 30,               -- the filter button and the search box
    gap      = 6,                -- search box to filter button
    viewW    = 680,              -- PagedSpellsView templates
    viewTop  = 12,               -- tool bar to the first heading
    pageW    = 806,              -- minimizedWidth: one page of the book
}
BOOK.bar = BOOK.top + BOOK.spells - (S.TITLE_BAND or 20) - 2
-- Centre a view on its page, counting the spell cards' 8px overhang on the left.
BOOK.viewX = math.floor((BOOK.pageW - BOOK.viewW + 8) / 2)

local function IconTabState(tab)
    local d = S.D(tab)
    if not d.iconBox then return end
    local on = tab.isSelected
    local hover = tab.IsMouseOver and tab:IsMouseOver()
    local r = T.Resolve(T.LOOK.slot, { on = on, hover = hover })
    d.iconBox.fill:SetColorTexture(T.C4(r.fill))
    T.SetEdge(d.iconBox, r.edge)
    if tab.Icon then
        local hot = on or hover
        tab.Icon:SetDesaturated(not hot)
        tab.Icon:SetAlpha(hot and 1 or 0.7)
    end
end

local function IconTab(k, tab)
    if not (S.Alive(tab) and tab.tabIcon and tab.Icon) then return end
    local d = S.D(tab)
    -- panelTab painted the whole 44px rect; that box goes, ours replaces it.
    if d.fill then d.fill:SetAlpha(0) end
    d.edgeless = true     -- panelTab's Sync leaves the border down from now on
    EV.Pixel:ShowEdges(tab, false)
    if not d.iconBox then
        local box = CreateFrame("Frame", nil, tab)
        S.ours[box] = true
        box:SetSize(TAB_H, TAB_H)
        box:SetPoint("CENTER")
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box.fill = EV.Pixel:Fill(box, "BACKGROUND")
        EV.Pixel:Edges(box)
        d.iconBox = box
        T.Watch(box.fill, function() IconTabState(tab) end)
        -- Pooled buttons: hooks go on once per button, state is re-read each time.
        k:After(tab, "SetTabSelected", function() IconTabState(tab) end)
        k:Hook(tab, "OnEnter", function() IconTabState(tab) end)
        k:Hook(tab, "OnLeave", function() IconTabState(tab) end)
    end
    -- The selection glow Blizzard shows on the chosen square tab.
    for _, key in ipairs({ "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }) do
        if tab[key] then S.Mute(tab[key]) end
    end
    k:Size(tab.Icon, TAB_ICON, TAB_ICON)
    tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- the icon's own baked edge
    if tab.IconMask then
        k:Anchors(tab.IconMask, { { "TOPLEFT", tab.Icon, "TOPLEFT", 0, 0 },
                                  { "BOTTOMRIGHT", tab.Icon, "BOTTOMRIGHT", 0, 0 } })
    end
    IconTabState(tab)
end

local PAGE_ART = { "BookBGLeft", "BookBGRight", "BookBGHalved", "BookCornerFlipbook", "Bookmark" }

local function HidingPages()
    return S.module and S.module.db and S.module.db.hideSpellbookPages and true or false
end

--- Every frame on the page: walked (pooled frames come and go with the page),
--- and any text still dark from the parchment lifted.
local function DressPage(k, paged)
    if not (paged and paged.GetFrames) then return end
    local ok, frames = pcall(paged.GetFrames, paged)
    if not ok or type(frames) ~= "table" then return end
    for _, fr in ipairs(frames) do
        k:Dress(fr)
        S.LiftText(fr)
        if fr.TextContainer then S.LiftText(fr.TextContainer) end
        if fr.Backplate then fr.Backplate:SetAlpha(0) end
    end
end

P{
    name  = "PlayerSpellsFrame",
    addon = "Blizzard_PlayerSpells",
    apply = function(f, k)
        local book = f.SpellBookFrame
        if not book then return end

        -- The tool bar, the whole width of the window, under our title bar.
        local bar = Band(book, "toolbar", "bottom", function(b)
            local y = -((S.TITLE_BAND or 20) + 2)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, y)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, y)
            b:SetHeight(BOOK.bar)
        end)

        local tabs = book.CategoryTabSystem
        if tabs then
            -- The first box sits `pad` in: the button is wider than its box.
            k:Move(tabs, "LEFT", bar, "LEFT", BOOK.pad - (TAB_W - TAB_H) / 2, 0)
            if tabs.tabs then for _, tab in ipairs(tabs.tabs) do IconTab(k, tab) end end
            k:Once(tabs, "iconTabs", function()
                -- Tabs are rebuilt from a pool whenever the spell list changes.
                k:After(tabs, "AddTab", function(self2)
                    local t = self2.tabs and self2.tabs[#self2.tabs]
                    if t then IconTab(k, t) end
                end)
            end)
        end

        -- The filter: Blizzard's 15x16 arrow becomes a button the height of
        -- the search box, on the bar's right. iconDropdown drew it as a
        -- ghost at its old size; it is the button Look at this one.
        local dd = book.SettingsDropdown
        if dd then
            k:Size(dd, BOOK.control, BOOK.control)
            k:Move(dd, "RIGHT", bar, "RIGHT", -BOOK.pad, 0)
            local dp = S.PainterFor(dd)
            if S.D(dd).states then dp:States(T.LOOK.button) end
        end

        local search = book.SearchBox
        if search and dd then
            k:Size(search, nil, BOOK.control)
            k:Move(search, "RIGHT", dd, "LEFT", -BOOK.gap, 0)
        end

        -- The page art, by setting.
        local hide = HidingPages()
        for _, key in ipairs(PAGE_ART) do
            local r = book[key]
            if r and r.SetAlpha then r:SetAlpha(hide and 0 or 1) end
        end

        local paged = book.PagedSpellsFrame
        if paged then
            local v1, v2 = paged.View1, paged.View2
            if v1 then k:Move(v1, "TOPLEFT", paged, "TOPLEFT", BOOK.viewX, -BOOK.viewTop) end
            if v2 then
                k:Move(v2, "TOPRIGHT", paged, "TOPRIGHT", -(BOOK.viewX - 8), -BOOK.viewTop)
                -- The gutter between the two pages, drawn on the right-hand
                -- view so it is there exactly when that page is.
                k:Once(v2, "gutter", function()
                    local g = S.Ours(v2:CreateTexture(nil, "BACKGROUND"))
                    if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(g) end
                    -- View2's left edge is viewX past the middle of the book.
                    local x = -BOOK.viewX
                    g:SetPoint("TOPRIGHT", v2, "TOPLEFT", x, 0)
                    g:SetPoint("BOTTOMRIGHT", v2, "BOTTOMLEFT", x, 0)
                    local function Paint()
                        g:SetColorTexture(S.Colour("border"))
                        g:SetWidth((EV.Pixel and EV.Pixel.One and EV.Pixel:One(v2)) or 1)
                    end
                    Paint()
                    T.Watch(g, Paint)
                end)
            end

            local foot = Band(book, "footer", "top", function(b)
                b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
                b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
                b:SetHeight(BOOK.footer)
            end)
            local pager = paged.PagingControls
            if pager then
                -- The arrow's box is inset in its 32px button.
                local inset = (32 - T.LOOK.pager.box) / 2
                k:Move(pager, "RIGHT", foot, "RIGHT", -(BOOK.pad - inset), 0)
                if pager.PageText then k:Label(pager.PageText, "textMuted") end
            end

            k:Once(paged, "dressPages", function()
                k:After(paged, "DisplayViewsForCurrentPage", function(self2) DressPage(k, self2) end)
            end)
            DressPage(k, paged)
        end
    end,
}

--------------------------------------------------------------------------------
--  CharacterFrame (Camelot CharacterFrame.xml, PaperDollFrame.xml)
--
--  The equipment slots, the stat headers and rows, the popout tabs, the
--  title and set rows, New Set and the side tabs' look are parts; the
--  window's own art is in S.ORNATE. This is the layout, all measured from
--  Blizzard's XML:
--
--    LeftPaneHost        398 wide from y=-20, the model and the slots
--      CharacterModelScene   fills it, with the race backdrop (four
--                            BACKGROUND textures and an overlay) on its own
--                            edges. On our window those edges are our border
--                            and title rule, so the backdrop drew over both:
--                            the "background outside the frame". Ours sits it
--                            one pixel inside the border and under the rule.
--    RightPaneHost       233 wide beside it
--      StoneBg               the top of the pane (the stats, titles and sets
--                            buttons and "Level N Class"); in S.ORNATE, which
--                            left those floating. Ours is a band where it was,
--                            shown exactly when Blizzard shows the stone
--                            (UpdateRightPaneHeader: the Character tab only).
--      common-framedivider   the seam between the panes; a hairline of ours.
--    ModeTabs            64x384 off the window's right edge from y=-30; six
--                        LargeSideTabButtonTemplate tabs sized from their art
--                        (about 60x55) with a 50px icon, chained 2px apart by
--                        UpdateTabLayout. Ours are LOOK.sideTab squares, the
--                        chain kept, `gap` off the window.
--    EquipmentManagerPane  NewSet 180x34 at BOTTOM y=50 over Equip and Save,
--                        99x28 at x=-50 and x=50: touching. Ours: the two
--                        with a gap, New Set spanning both at their height.
--    PaperDollSidebarTab1-3  the stats / titles / sets buttons: our button,
--                        on while checked.
--    RightPaneToggleButton   the gold arrow that folds the stat pane: our
--                        button with a chevron as Blizzard's pointed (left
--                        while open), turned after SetRightPaneCollapsed.
--------------------------------------------------------------------------------
local SET_BUTTON = { w = 97, h = 28, gap = 4, bottom = 20, above = 6 }

local function ModeTab(k, tab)
    local SL = T.LOOK.sideTab
    k:Size(tab, SL.box, SL.box)
    local icon = tab.Icon
    if not icon then return end
    local function Seat(pressed)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", tab, "CENTER", pressed and 1 or 0, pressed and -1 or 0)
        icon:SetSize(SL.icon, SL.icon)
    end
    Seat(false)
    -- Blizzard re-sizes the icon to its interior (50) on every SetChecked and
    -- re-anchors it off centre on every press.
    k:After(tab, "SetChecked", function() Seat(false) end)
    k:Hook(tab, "OnMouseDown", function() Seat(true) end)
    k:Hook(tab, "OnMouseUp", function() Seat(false) end)
end

P{
    name  = "CharacterFrame",
    apply = function(f, k)
        -- The model and its backdrop, inside our border and under the title rule.
        local left, scene = f.LeftPaneHost, _G.CharacterModelScene
        if left and scene then
            k:Anchors(scene, { { "TOPLEFT", left, "TOPLEFT", 1, -2 },
                               { "BOTTOMRIGHT", left, "BOTTOMRIGHT", -1, 1 } })
            -- The zoom and turn buttons are hidden until the model is set up,
            -- after the window's walk; dress them when they appear.
            local cf = scene.ControlFrame
            if cf then
                k:Dress(cf)
                k:Hook(cf, "OnShow", function(self2) S.Walk(self2, 0) end)
            end
        end

        -- The top of the right pane: a band where the stone was.
        local right = f.RightPaneHost
        local stone = right and right.StoneBg
        if right and stone then
            local band = Band(right, "header", "bottom", function(b)
                b:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -2)
                b:SetPoint("BOTTOMRIGHT", stone, "BOTTOMRIGHT", -1, 0)
            end)
            -- PaperDollLevelInfo is declared frameLevel="5", absolute, so on a
            -- raised window it can sit under the band; keep it over.
            local info = _G.PaperDollLevelInfo
            if info and info:GetFrameLevel() <= band:GetFrameLevel() then
                info:SetFrameLevel(band:GetFrameLevel() + 2)
            end
            local function Sync() band:SetShown(stone:IsShown()) end
            Sync()
            for _, m in ipairs({ "Show", "Hide", "SetShown" }) do k:After(stone, m, Sync) end

            -- The seam between the panes.
            k:Once(right, "seam", function()
                local seam = S.Ours(right:CreateTexture(nil, "BORDER", nil, 7))
                if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(seam) end
                seam:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -2)
                seam:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 1)
                local function Paint()
                    seam:SetColorTexture(S.Colour("border"))
                    seam:SetWidth((EV.Pixel and EV.Pixel.One and EV.Pixel:One(right)) or 1)
                end
                Paint()
                T.Watch(seam, Paint)
            end)
        end

        -- The mode tabs down the right edge.
        local tabs = f.ModeTabs
        if tabs then
            k:Move(tabs, "TOPLEFT", f, "TOPRIGHT", T.LOOK.sideTab.gap, -((S.TITLE_BAND or 20) + 8))
            for _, tab in ipairs(tabs.Tabs or {}) do ModeTab(k, tab) end
        end

        -- The equipment manager's buttons.
        local em = _G.PaperDollFrame and PaperDollFrame.EquipmentManagerPane
        if em then
            local SB = SET_BUTTON
            local half = (SB.w + SB.gap) / 2
            if em.EquipSet then
                k:Size(em.EquipSet, SB.w, SB.h)
                k:Move(em.EquipSet, "BOTTOM", em, "BOTTOM", -half, SB.bottom)
            end
            if em.SaveSet then
                k:Size(em.SaveSet, SB.w, SB.h)
                k:Move(em.SaveSet, "BOTTOM", em, "BOTTOM", half, SB.bottom)
            end
            if em.NewSet then
                k:Size(em.NewSet, SB.w * 2 + SB.gap, SB.h)
                k:Move(em.NewSet, "BOTTOM", em, "BOTTOM", 0, SB.bottom + SB.h + SB.above)
            end
        end

        -- The equipment flyout: the list of what else fits a slot. Its own
        -- frame on UIParent, filled in by EquipmentFlyout_UpdateItems, which
        -- adds item buttons and backing pieces as it needs them. The backing
        -- (UI-GearManager-Flyout) is in S.ORNATE_FILES; ours is a panel on the
        -- button frame Blizzard sizes to the buttons, and a walk for the new
        -- buttons and the page arrows.
        local flyout = _G.EquipmentFlyoutFrame
        if flyout and type(_G.EquipmentFlyout_UpdateItems) == "function" then
            k:Once(flyout, "flyoutHook", function()
                hooksecurefunc("EquipmentFlyout_UpdateItems", function()
                    local bf = flyout.buttonFrame
                    if bf then k:Panel(bf, "surface1") end
                    local nav = flyout.NavigationFrame
                    if nav then k:Panel(nav, "surface1") end
                    S.Walk(flyout, 0)
                end)
            end)
        end

        for i = 1, 3 do
            local tab = _G["PaperDollSidebarTab" .. i]
            if tab then
                local d = OverlayButton(k, tab, nil, { tab.Icon }, function()
                    local ok, on = pcall(tab.GetChecked, tab)
                    return ok and on and true or false
                end)
                if d then
                    k:After(tab, "SetChecked", function() if d.Repaint then d.Repaint() end end)
                end
            end
        end
        local level = _G.CharacterLevelText
        if level then k:Label(level, "title", true) end

        local toggle = f.RightPaneToggleButton
        if toggle then
            local function Collapsed()
                if type(f.IsRightPaneCollapsed) ~= "function" then return false end
                local ok, v = pcall(f.IsRightPaneCollapsed, f)
                return ok and v and true or false
            end
            -- Blizzard's arrow points left while the pane is open.
            local d = OverlayButton(k, toggle, Collapsed() and "right" or "left")
            if d and d.chev then
                local function Turn() d.chev:Point(Collapsed() and "right" or "left") end
                Turn()
                k:After(f, "SetRightPaneCollapsed", Turn)
            end
        end
    end,
}
