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
            b.rule:SetHeight(EV.Pixel:Line(b))
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
--------------------------------------------------------------------------------
--  The quest log's details page (QuestMapFrame.DetailsFrame, Mainline
--  QuestMapFrame.xml, 308 wide beside the map). Blizzard's pieces:
--
--    BackFrame         307x52 at the top: questlog-reward-top-frame (a brown
--                      plank) behind a 90x22 Back button at LEFT x=11 y=4.
--    ScrollFrame       the text, from y=-43.
--    RewardsFrame      in RewardsFrameContainer (clipped, 100 tall, 23 up from
--                      the bottom): questlog-reward-header-top, a tiled middle
--                      and a bottom, with "Rewards" in QuestFont_Huge at y=-22.
--    Abandon, Share, Track  105/103/105 x22 along the bottom edge, touching,
--                      with UI-Frame-BtnDivMiddle dividers hung off Share.
--
--  Ours: a header band with Back on it, the rewards panel as a band of ours
--  with its heading in the kit's title, and a footer with the three buttons
--  spaced evenly across it.
--------------------------------------------------------------------------------
-- TITLE_CANVAS_SPACER_FRAME_HEIGHT (Blizzard_WorldMap.lua: the map's top),
-- our title band plus its rule, and the tool bar's contents.
local MAP = { spacer = 67, top = (S.TITLE_BAND or 24) + 2, control = 30, gap = 6, search = 180, edge = 8 }

local QLOG = { foot = 26, pad = 8, gap = 6, button = 24, small = 22, back = 80 }

local function QuestLogDetails(k, bar)
    local qm = _G.QuestMapFrame
    local det = qm and qm.DetailsFrame
    if not det then return end
    if det.Bg then S.StripArt(det.Bg) end

    -- The page is 502 tall from the log's top; with the log now under the
    -- map's tool bar, that ran off the window's bottom. Its bottom is tied
    -- to the log's instead, and the text's 430 with it: from under the
    -- header to where Blizzard's own gap above the buttons began (29 up).
    local parent = det:GetParent()
    k:Anchors(det, { { "TOPRIGHT", parent, "TOPRIGHT", 0, -1 },
                     { "BOTTOMRIGHT", qm, "BOTTOMRIGHT", 0, 3 } })
    local text = det.ScrollFrame
    if text then
        k:Anchors(text, { { "TOPLEFT", det, "TOPLEFT", 5, -QLOG.pad },
                          { "BOTTOMLEFT", det, "BOTTOMLEFT", 5, 29 } })
        -- Its bar was hung 17 above the text and 27 below it
        -- (scrollBarTopY / scrollBarBottomY), for the header plank and the
        -- button row: into the map's tool bar and the footer. The text's
        -- own height now.
        local sb = text.ScrollBar
        if sb then
            local x = rawget(text, "scrollBarX") or 13
            k:Anchors(sb, { { "TOPLEFT", text, "TOPRIGHT", x, 0 },
                            { "BOTTOMLEFT", text, "BOTTOMRIGHT", x, 0 } })
        end
    end

    -- Reward buttons are made on demand (QuestInfo_GetRewardButton), after
    -- the window's walk: dress them each time a quest is displayed. The hook
    -- is on QuestInfo_Display, which callers reach by its global name.
    -- QuestInfo_ShowRewards is NOT: the QUEST_TEMPLATE_* tables hold the
    -- function itself, taken when QuestInfo.lua loaded, so a hook on the
    -- global never runs.
    k:Once(det, "rewardButtons", function()
        if type(QuestInfo_Display) == "function" then
            hooksecurefunc("QuestInfo_Display", function()
                -- The next frame: the buttons are laid out and shown by then.
                C_Timer.After(0, function()
                    for _, name in ipairs({ "MapQuestInfoRewardsFrame", "QuestInfoRewardsFrame" }) do
                        local fr = _G[name]
                        if fr then S.Walk(fr, 0) end
                    end
                end)
            end)
        end
    end)

    -- Back goes up onto the map's tool bar, where the log's settings button
    -- sits on the list (the list's search row is hidden with the list while a
    -- quest is open), so the page gets BackFrame's 52 pixels back.
    local back = det.BackFrame
    if back then
        k:Fade(back)
        local btn = back.BackButton
        if btn and bar then
            k:Size(btn, QLOG.back, MAP.control)
            k:Move(btn, "RIGHT", bar, "RIGHT", -MAP.gap, 0)
        end
    end
    local rc = det.RewardsFrameContainer
    local rf = rc and rc.RewardsFrame
    if rf then
        for _, key in ipairs({ "Top", "Background", "Bottom" }) do
            if rf[key] then S.StripArt(rf[key]) end
        end
        -- The panel rises over the end of the text as you scroll
        -- (AdjustRewardsFrameContainer), so it has to be opaque: the window's
        -- surface under the band's rail colour, the rule along its top.
        k:Fill(rc, T.LOOK.window.rest.fill)
        Band(rc, "rewards", "top", function(b) b:SetAllPoints(rc) end)
        if rf.Label then
            k:Label(rf.Label, "title", true)
            k:Move(rf.Label, "TOPLEFT", rf, "TOPLEFT", QLOG.pad, -QLOG.pad)
        end
    end

    local ab, sh, tr = det.AbandonButton, det.ShareButton, det.TrackButton
    if ab and sh and tr then
        local foot = Band(det, "foot", "top", function(b)
            -- Where Blizzard's buttons were: 2 below the page, up to the
            -- rewards panel 23 above it.
            b:SetPoint("BOTTOMLEFT", det, "BOTTOMLEFT", 0, -3)
            b:SetPoint("BOTTOMRIGHT", det, "BOTTOMRIGHT", 0, -3)
            b:SetHeight(QLOG.foot)
        end)
        -- The dividers hang off Share's sides.
        for _, r in ipairs(S.Regions(sh)) do
            if r.GetObjectType and r:GetObjectType() == "Texture" and not S.ours[r]
               and S.ArtIs(r, "ui%-frame%-btndiv") then
                S.StripArt(r)
            end
        end
        local w = (det:GetWidth() - 2 * QLOG.pad - 2 * QLOG.gap) / 3
        for i, b in ipairs({ ab, sh, tr }) do
            k:Size(b, w, QLOG.small)
            k:Move(b, "LEFT", foot, "LEFT", QLOG.pad + (i - 1) * (w + QLOG.gap), 0)
        end
    end
end


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
            -- On the tool bar, the control height, centred (see below).
            local inset = math.floor((MAP.spacer - MAP.top - 1 - MAP.control) / 2)
            k:Anchors(bar, {
                { "TOPLEFT",     sp, "TOPLEFT",     8, -(MAP.top + inset) },
                { "BOTTOMRIGHT", sp, "BOTTOMRIGHT", rightX, MAP.spacer - (MAP.top + inset + MAP.control) },
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

        -- The map's corner furniture, off its edges: the waypoint pin at the
        -- canvas's top left (Camelot: TOPLEFT +3 0, flush with the top), the
        -- quest log toggle at its bottom right (-2 +1), and the coordinates at
        -- its bottom left (+68 +2).
        local canvas = f.ScrollContainer
        if canvas then
            if f.WorldMapTrackingPinButton then
                k:Move(f.WorldMapTrackingPinButton, "TOPLEFT", canvas, "TOPLEFT", MAP.edge, -MAP.edge)
            end
            if toggle then k:Move(toggle, "BOTTOMRIGHT", canvas, "BOTTOMRIGHT", -MAP.edge, MAP.edge) end
        end
        -- The coordinates: two lines, each a label with no anchor of its own,
        -- so each sat centred in its 100px row and a longer player line began
        -- further left than the cursor line over it. Both from the left edge.
        for _, child in ipairs(S.Children(f)) do
            if child.CursorCoords and child.PlayerCoords then
                for _, row in ipairs({ child.CursorCoords, child.PlayerCoords }) do
                    if row.Label then
                        k:Move(row.Label, "LEFT", row, "LEFT", 0, 0)
                        row.Label:SetJustifyH("LEFT")
                    end
                end
                if canvas then k:Move(child, "BOTTOMLEFT", canvas, "BOTTOMLEFT", MAP.edge, MAP.edge) end
            end
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

        -- The row under the title sits on a tool bar, and everything on it is
        -- one height on one centre line: the nav bar and the tracking options
        -- button on the left, the quest log's search, count and settings on
        -- the right. Blizzard's numbers (Blizzard_WorldMap.lua):
        --   TITLE_CANVAS_SPACER_FRAME_HEIGHT 67, the map's top
        --   NavBar      TOPLEFT spacer +8 -25, BOTTOMRIGHT spacer -50 +9
        --   options     LEFT of the nav bar's right +10 -2 (Camelot)
        --   QuestMapFrame  TOPRIGHT -3 -25 (AttachQuestLog), so the log began
        --               above the map's top, inside the row; its search box
        --               hangs 7 over the list (BOTTOMLEFT on its TOPLEFT) and
        --               its settings button 25 over it.
        -- Ours: the bar from our title band to the map's top, its rule on the
        -- map's last pixel row; the log starts under it, level with the map,
        -- and its controls move up onto the bar.
        local bar
        if spacer then
            bar = Band(f, "toolbar", "bottom", function(b)
                b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -MAP.top)
                b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -MAP.top)
                b:SetHeight(MAP.spacer - MAP.top - 1)
            end)
        end
        local inset = math.floor((MAP.spacer - MAP.top - 1 - MAP.control) / 2)
        local nav = f.NavBar
        local opts = f.WorldMapTrackingOptionsButton
        if opts and nav then
            k:Size(opts, MAP.control, MAP.control)
            k:Move(opts, "LEFT", nav, "RIGHT", MAP.gap, 0)
        end

        local qm = _G.QuestMapFrame
        if qm and bar then
            k:Anchors(qm, { { "TOPRIGHT", bar, "BOTTOMRIGHT", -2, -1 },
                            { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3 } })
            local qf = qm.QuestsFrame
            local sf = qf and qf.ScrollFrame
            if sf then
                k:Anchors(sf, { { "TOPLEFT", qf, "TOPLEFT", 0, -MAP.gap },
                                { "BOTTOMRIGHT", qf, "BOTTOMRIGHT", 0, 0 } })
                local search, dd = sf.SearchBox, sf.SettingsDropdown
                if dd then
                    k:Size(dd, MAP.control, MAP.control)
                    k:Move(dd, "BOTTOMRIGHT", qm, "TOPRIGHT", -MAP.gap, inset + 1)
                    local dp = S.PainterFor(dd)
                    if S.D(dd).states then dp:States(T.LOOK.button) end
                end
                if search then
                    -- Two anchors, so the height is ours whatever the template
                    -- or its mixin sets (a Size alone was put back to 20).
                    k:Size(search, MAP.search, MAP.control)
                    k:Anchors(search, {
                        { "BOTTOMLEFT", qm, "TOPLEFT", MAP.gap, inset + 1 },
                        { "TOPLEFT",    qm, "TOPLEFT", MAP.gap, inset + 1 + MAP.control },
                    })
                    -- The count (QuestLogCount, shown by Camelot's
                    -- QuestMapFrameUtils): a 100x20 InputBoxVisual box hung off
                    -- the search box's top right, its text 5 in from the top
                    -- right. On the bar: the box between the search and the
                    -- settings, the count centred on the line, right-aligned.
                    local count, text = _G.QuestLogCount, _G.QuestLogQuestCount
                    if count then
                        k:Fade(count)
                        k:Anchors(count, {
                            { "TOPLEFT",     search, "TOPRIGHT", MAP.gap, 0 },
                            { "BOTTOMRIGHT", dd or search, dd and "BOTTOMLEFT" or "BOTTOMRIGHT", -MAP.gap, 0 },
                        })
                        if text then k:Move(text, "RIGHT", count, "RIGHT", 0, 0) end
                    end
                end
            end
        end
        QuestLogDetails(k, bar)
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
        local px = EV.Pixel:Line(host)
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
                line:SetHeight(EV.Pixel:Line(border))
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
    if not (d.iconBox and d.iconBox.Paint) then return end
    d.iconBox.Paint(tab.isSelected, tab.IsMouseOver and tab:IsMouseOver())
    -- The icon is anchored BOTTOM in the XML, and SetTabSelected adds a
    -- CENTER point on top of it every time. With both, the icon was pinned
    -- to the button's bottom and stretched up to its centre line: low in the
    -- tab, with a gap over it. One point, the centre of the square.
    local icon = tab.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
end

--- A school tab as a tab: a square of the button's height standing on the
--- tool bar's rule (S.TabFace, open at the bottom), one pixel over it so the
--- chosen school's tab runs into the page below it.
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
        local one = EV.Pixel:One(tab)
        box:SetWidth(TAB_H)
        box:SetPoint("TOP", tab, "TOP", 0, 0)
        box:SetPoint("BOTTOM", tab, "BOTTOM", 0, -one)
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box:EnableMouse(false)
        box.Paint = S.TabFace(box, "bottom", tab.Icon)
        d.iconBox = box
        T.Watch(box, function() IconTabState(tab) end)
        -- Pooled buttons: hooks go on once per button, state is re-read each time.
        k:After(tab, "SetTabSelected", function() IconTabState(tab) end)
        k:Hook(tab, "OnEnter", function() IconTabState(tab) end)
        k:Hook(tab, "OnLeave", function() IconTabState(tab) end)
    end
    -- The selection glow Blizzard shows on the chosen square tab.
    for _, key in ipairs({ "SquareBackground", "SquareBackgroundActive", "SquareBackgroundActiveGlow" }) do
        if tab[key] then S.Mute(tab[key]) end
    end
    -- The icon fills the box inside its edge and the black ring. Sized, not
    -- anchored: SetTabSelected re-anchors it CENTER on the button every time.
    local side = TAB_H - 2 * EV.Pixel:One(tab) * (1 + T.LOOK.windowTab.inset)
    k:Size(tab.Icon, side, side)
    S.Crop(tab.Icon)   -- the suite's crop, past the icon's own baked edge
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

--------------------------------------------------------------------------------
--  Talents: PlayerSpellsFrame.TalentsFrame (Camelot ClassTalentsFrame.xml and
--  .lua; the window is 1218x708 on this tab, the frame 1212x681 at BOTTOM y=4)
--
--  The trees are content and keep Blizzard's look: the talent buttons, their
--  rank badges and the arrows between them. The chrome round them:
--
--    Background        Talents-Background-c60, 701 tall from the frame's
--                      bottom; ClassBackground (the spec painting, y=-70 to
--                      y=+36 inside it) and its overlays, clouds and particles
--                      on top. All art: our window surface shows instead.
--    BackgroundBorder  Talents-inner-frame-c60 round ClassBackground, with the
--                      Talents-divider-* pieces on its top edge and between
--                      the trees. Ours: nothing round it, a hairline where
--                      each tree divider was.
--    TabSystem         Primary / Secondary (TabSystemButtonTemplate), standing
--                      on BackgroundBorder's top at x=70; SearchBox 4 above
--                      its top right, SearchOptionsDropdown beside it. Ours: a
--                      tool bar from our title band down to where the trees
--                      start, the tabs standing on its rule, the search, its
--                      options button and the unspent points on its right.
--    ClassCurrencyDisplay  "Unspent Talents" and a Talents-Square-Box-c60 with
--                      the number, at the tree area's top right. Ours: on the
--                      tool bar, the number in a well.
--    tree headers      ClassTalentTreeHeaderTemplate from treeHeaderPool, on
--                      every RefreshTreeHeaders: a round-masked icon in
--                      Talents-Main-Ring-c60, the points spent in a
--                      talents-main-ring-box-c60, a Talents-small-divider
--                      under. Ours: the suite's square icon, the name in gold,
--                      the points plain under the icon's corner.
--    ApplyButton       BOTTOM y=8 in the 36px under the trees, ResetButton and
--                      UndoButton (IconButtonTemplate, talents-button-*) 14 to
--                      its right. Ours: a footer across the window, Apply in
--                      its middle, the two icon buttons in our button box.
--    portrait          SetTalentPortrait puts the spec icon in the window's
--                      round portrait on this tab; the window part fades the
--                      portrait once, so it is faded again after each update.
--------------------------------------------------------------------------------
local TAL = { pad = 12, control = 30, gap = 8, footer = 40, button = 24, unspent = 30, unspentFont = 15 }

local TALENT_ART = { "Background", "ClassBackground", "OverlayBackgroundRight", "OverlayBackgroundMid",
                     "BackgroundBorder", "DividerHorizontalLeft", "DividerHorizontalRight",
                     "DividerVerticalLeft", "DividerVerticalRight" }

local function TreeHeader(h)
    if not S.Alive(h) then return end
    local d = S.D(h)
    if not d.dressed then
        d.dressed = true
        for _, key in ipairs({ "MainRing", "TextBackground", "Divider" }) do
            if h[key] then S.StripArt(h[key]) end
        end
        local icon = h.Icon
        if icon then
            for _, r in ipairs(S.Regions(h)) do
                if r.GetObjectType and r:GetObjectType() == "MaskTexture" and icon.RemoveMaskTexture then
                    pcall(icon.RemoveMaskTexture, icon, r)
                end
            end
            EV.Icons:Style(icon, { host = h })
        end
        local p = S.PainterFor(h)
        if h.Name then p:Label(h.Name, "title", true) end
        if h.Text then p:Label(h.Text, "text", true) end
    end
    -- The points spent, under the icon's bottom right corner, where the
    -- ring's box was (Setup never moves it; the XML anchors it to the box).
    if h.Text and h.Icon then
        h.Text:ClearAllPoints()
        h.Text:SetPoint("TOPRIGHT", h.Icon, "BOTTOMRIGHT", 0, -2)
    end
end

--- A text tab on a tool bar, the way the spellbook's school tabs are icon
--- tabs: panelTab's box goes, a window tab face (open at the bottom, a pixel
--- over the rule) takes its place, and the label is the tab Look's text.
local function TextTabState(tab)
    local d = S.D(tab)
    if not (d.textBox and d.textBox.Paint) then return end
    local on = tab.isSelected and true or false
    local hover = tab.IsMouseOver and tab:IsMouseOver() or false
    d.textBox.Paint(on, hover)
    local text = tab.Text
    if text then
        local okE, enabled = pcall(tab.IsEnabled, tab)
        local st = { on = on, hover = hover, disabled = okE and enabled == false }
        text:SetTextColor(T.C4(T.Resolve(T.LOOK.tab, st).text))
    end
end

local function TextTab(k, tab)
    if not S.Alive(tab) then return end
    local d = S.D(tab)
    if d.fill then d.fill:SetAlpha(0) end
    d.edgeless = true
    EV.Pixel:ShowEdges(tab, false)
    if not d.textBox then
        local box = CreateFrame("Frame", nil, tab)
        S.Ours(box)
        box:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, -EV.Pixel:One(tab))
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box:EnableMouse(false)
        box.Paint = S.TabFace(box, "bottom")
        local bd = S.D(box)
        if bd.tabInset then bd.tabInset:Hide() end
        d.textBox = box
        T.Watch(box, function() TextTabState(tab) end)
        k:After(tab, "SetTabSelected", function() TextTabState(tab) end)
        k:After(tab, "SetEnabled", function() TextTabState(tab) end)
        k:Hook(tab, "OnEnter", function() TextTabState(tab) end)
        k:Hook(tab, "OnLeave", function() TextTabState(tab) end)
    end
    TextTabState(tab)
end

local function Talents(f, k)
    local tf = f.TalentsFrame
    if not tf then return end
    local top = (S.TITLE_BAND or 24) + 2

    for _, key in ipairs(TALENT_ART) do
        if tf[key] then S.StripArt(tf[key]) end
    end
    k:Fade(tf)

    -- The window's portrait comes back on this tab.
    if f.PortraitContainer then
        k:Fade(f.PortraitContainer)
        k:Once(f, "talentPortrait", function()
            k:After(f, "UpdatePortrait", function() k:Fade(f.PortraitContainer) end)
        end)
    end

    local art = tf.ClassBackground
    if not art then return end

    -- The tool bar: our title band down to where the trees start.
    local bar = Band(tf, "toolbar", "bottom", function(b)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
        b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
        b:SetPoint("BOTTOM", art, "TOP", 0, 0)
    end)
    local ts = tf.TabSystem
    if ts then
        k:Move(ts, "BOTTOMLEFT", bar, "BOTTOMLEFT", TAL.pad, 0)
        for _, tab in ipairs(ts.tabs or {}) do TextTab(k, tab) end
    end
    local dd, search = tf.SearchOptionsDropdown, tf.SearchBox
    local rightmost = bar
    if dd then
        k:Size(dd, TAL.control, TAL.control)
        k:Move(dd, "RIGHT", bar, "RIGHT", -TAL.pad, 0)
        OverlayButton(k, dd, "down", nil, function()
            return type(dd.IsMenuOpen) == "function" and dd:IsMenuOpen() or false
        end)
        rightmost = dd
    end
    if search then
        k:Size(search, 220, TAL.control)
        if rightmost == bar then
            k:Move(search, "RIGHT", bar, "RIGHT", -TAL.pad, 0)
        else
            k:Move(search, "RIGHT", rightmost, "LEFT", -TAL.gap, 0)
        end
    end
    local cur = tf.ClassCurrencyDisplay
    if cur then
        if cur.Border then S.StripArt(cur.Border) end
        k:Move(cur, "RIGHT", search or bar, search and "LEFT" or "RIGHT", -(TAL.gap * 2), 0)
        local box = cur.CurrentAmountContainer
        if box then
            k:Size(box, TAL.unspent + 10, TAL.unspent)
            S.Well(box, box, -1)
            local amount = box.CurrencyAmount
            if amount then
                -- Game32Font in the art's 48px box; body size in our well.
                k:Label(amount, false, true)
                local path = T.FontBoldPath and T.FontBoldPath()
                if path then pcall(amount.SetFont, amount, path, TAL.unspentFont, "") end
                -- SetAmount colours it on every change: green with points to
                -- spend, grey with none. Ours, meaning the same.
                local function Colour()
                    local n = tonumber(amount:GetText() or "") or 0
                    amount:SetTextColor(S.Colour(n > 0 and "success" or "textMuted"))
                end
                Colour()
                k:Once(cur, "amountColour", function()
                    k:After(cur, "SetAmount", Colour)
                    T.Watch(amount, Colour)
                end)
            end
        end
        if cur.UnspentLabel then
            k:Label(cur.UnspentLabel, "textMuted")
            if box then
                cur.UnspentLabel:ClearAllPoints()
                cur.UnspentLabel:SetPoint("RIGHT", box, "LEFT", -TAL.gap, 0)
            end
        end
    end

    -- A hairline where each tree divider was.
    for _, key in ipairs({ "DividerVerticalLeft", "DividerVerticalRight" }) do
        local div = tf[key]
        if div then
            k:Once(div, "rule", function()
                local rule = S.Ours(tf:CreateTexture(nil, "BORDER"))
                EV.Pixel.NoSnap(rule)
                rule:SetPoint("TOP", div, "TOP", 0, 0)
                rule:SetPoint("BOTTOM", div, "BOTTOM", 0, 0)
                local function Paint()
                    rule:SetColorTexture(S.Colour("border"))
                    rule:SetWidth(EV.Pixel:Line(tf))
                end
                Paint()
                T.Watch(rule, Paint)
            end)
        end
    end

    -- The footer: Apply in its middle, reset and undo beside it.
    local foot = Band(tf, "footer", "top", function(b)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        b:SetPoint("TOP", art, "BOTTOM", 0, 0)
    end)
    local apply = tf.ApplyButton
    if apply then
        k:Size(apply, nil, TAL.button)
        k:Move(apply, "CENTER", foot, "CENTER", 0, 0)
        if apply.YellowGlow then k:Fade(apply.YellowGlow) end
    end
    for _, key in ipairs({ "ResetButton", "UndoButton" }) do
        local b = tf[key]
        if b then
            k:Size(b, TAL.button, TAL.button)
            local _, p = OverlayButton(k, b, nil, { b.Icon })
            if p and b.Icon then p:States(T.LOOK.button, { glyph = b.Icon }) end
        end
    end
    if tf.InspectCopyButton and foot then k:Move(tf.InspectCopyButton, "CENTER", foot, "CENTER", 0, 0) end

    -- Tree headers are pooled and re-laid on every refresh.
    local function Headers()
        for _, h in ipairs(tf.treeHeaders or {}) do TreeHeader(h) end
    end
    Headers()
    k:Once(tf, "treeHeaders", function() k:After(tf, "RefreshTreeHeaders", Headers) end)
end

P{
    name  = "PlayerSpellsFrame",
    addon = "Blizzard_PlayerSpells",
    apply = function(f, k)
        Talents(f, k)
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
            -- Standing on the bar's rule, the first box `pad` in (the button
            -- is wider than its box).
            k:Move(tabs, "BOTTOMLEFT", bar, "BOTTOMLEFT", BOOK.pad - (TAB_W - TAB_H) / 2, 0)
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
                        g:SetWidth(EV.Pixel:Line(v2))
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

-- The right pane's tab row: the header band's height, the tabs' height, the
-- first tab in from the pane's edge and the gap between tabs.
local SIDEBAR = { band = 34, tab = 28, pad = 8, gap = 2, textPad = 12 }
local SIDEBAR_LABELS = { [1] = "CHARACTER", [2] = "EQUIPMENT_MANAGER", [3] = "PET" }

--- One of the pane's tabs as a text tab: its icon, frame and checked art go,
--- a window tab face (open at the bottom) and a label take their place, on
--- while Blizzard has it checked.
local function SidebarTab(k, tab, id)
    if not S.Alive(tab) then return end
    local d = S.D(tab)
    if not d.textTab then
        d.textTab = true
        S.Blank(tab)
        S.PainterFor(tab):Fade()
        if tab.Icon then tab.Icon:SetAlpha(0) end
        local box = S.Ours(CreateFrame("Frame", nil, tab))
        box:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, -EV.Pixel:One(tab))
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box:EnableMouse(false)
        box.Paint = S.TabFace(box, "bottom")
        local bd = S.D(box)
        if bd.tabInset then bd.tabInset:Hide() end
        local label = S.Ours(tab:CreateFontString(nil, "OVERLAY"))
        local path = T.FontBoldPath and T.FontBoldPath() or T.FontPath()
        if path then label:SetFont(path, 12, "") end
        label:SetPoint("CENTER", tab, "CENTER", 0, 0)
        local key = SIDEBAR_LABELS[id]
        local text = (key and type(_G[key]) == "string" and _G[key])
            or (PAPERDOLL_SIDEBARS and PAPERDOLL_SIDEBARS[id] and PAPERDOLL_SIDEBARS[id].name) or ""
        label:SetText(text)
        d.label = label
        local function Sync()
            local okC, on = pcall(tab.GetChecked, tab)
            local okE, enabled = pcall(tab.IsEnabled, tab)
            local st = { on = okC and on or false, hover = tab:IsMouseOver() or false,
                         disabled = okE and enabled == false }
            tab:SetAlpha(1)   -- Blizzard fades a disabled tab to half; ours says it in the label
            box.Paint(st.on, st.hover)
            label:SetTextColor(T.C4(T.Resolve(T.LOOK.tab, st).text))
        end
        d.Sync = Sync
        T.Watch(box, Sync)
        k:After(tab, "SetChecked", Sync)
        k:After(tab, "Enable", Sync)
        k:After(tab, "Disable", Sync)
        k:Hook(tab, "OnEnter", Sync)
        k:Hook(tab, "OnLeave", Sync)
    end
    k:Size(tab, math.floor(d.label:GetStringWidth() + 2 * SIDEBAR.textPad + 0.5), SIDEBAR.tab)
    d.Sync()
end

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
            -- LeftPaneHost starts 20 down; our title band and its rule end
            -- TITLE_BAND + 2 down.
            local under = -((S.TITLE_BAND or 20) + 2 - 20)
            k:Anchors(scene, { { "TOPLEFT", left, "TOPLEFT", 1, under },
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
                b:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -((S.TITLE_BAND or 20) + 2 - 20))
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
                seam:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -((S.TITLE_BAND or 20) + 2 - 20))
                seam:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 0, 1)
                local function Paint()
                    seam:SetColorTexture(S.Colour("border"))
                    seam:SetWidth(EV.Pixel:Line(right))
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

        -- The pane's tabs (PaperDollSidebarTab1-3: stats, equipment sets,
        -- pet; 42px icon squares in UI-Character-Info-StatTab frames, in a
        -- 233x85 holder under the pane's stone). Text tabs, as the talent
        -- window's Primary and Secondary, standing on the header band's rule,
        -- which is now only as tall as they are: the stone (and every pane
        -- anchored under it) comes up to meet them.
        if right and stone then
            k:Size(stone, nil, (S.TITLE_BAND or 20) + 2 - 20 + SIDEBAR.band)
            local band = S.D(right).bands and S.D(right).bands.header
            local prev
            for i = 1, 3 do
                local tab = _G["PaperDollSidebarTab" .. i]
                if tab and band then
                    SidebarTab(k, tab, i)
                    if tab:IsShown() then
                        if prev then
                            k:Move(tab, "BOTTOMLEFT", prev, "BOTTOMRIGHT", SIDEBAR.gap, 0)
                        else
                            k:Move(tab, "BOTTOMLEFT", band, "BOTTOMLEFT", SIDEBAR.pad, 0)
                        end
                        prev = tab
                    end
                end
            end
        end
        -- "Level N Class" in the title bar, as the inspect window has it.
        local level = _G.CharacterLevelText
        if level and S.TitleInfo then S.TitleInfo(k, f, level) end

        local toggle = f.RightPaneToggleButton
        if toggle then
            local function Collapsed()
                if type(f.IsRightPaneCollapsed) ~= "function" then return false end
                local ok, v = pcall(f.IsRightPaneCollapsed, f)
                return ok and v and true or false
            end
            -- Clear of the taller title band: Blizzard has it 6 into the pane.
            if left then k:Move(toggle, "TOPRIGHT", left, "TOPRIGHT", -6, -((S.TITLE_BAND or 20) - 20 + 8)) end
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

--------------------------------------------------------------------------------
--  ProfessionsFrame (Blizzard_Professions, Camelot ProfessionsFrame.xml and
--  Blizzard_ProfessionsCrafting.xml, Camelot overrides in
--  Blizzard_ProfessionsCrafting.lua)
--
--  The pieces are parts (rankBar, filterDropdown, recipeRow, skillBarLegacy,
--  the list headers, reagent item buttons, side tabs). The layout, from
--  Blizzard's numbers:
--
--    RankBar           TOPLEFT x=110 y=-40 (SetRankBarAnchors, re-run on every
--                      profession): on a tool bar band from our title bar down
--                      to where the recipe list starts (y=-72), centred on it.
--    RecipeList        TOPLEFT x=5 y=-72 to the bottom, 304 wide (OverrideArt):
--                      its Professions-background-summarylist art and inset
--                      nine-slice go, and it ends on the footer.
--      SearchBox       20 tall next to a 22px filter; both 24, one line.
--    SchematicForm     beside the list, 484 tall, an inset (the inset part
--                      boxes it). No box on either side: one hairline between
--                      the two, the way the spellbook's pages meet.
--    Create controls   Create All, the count spinner and Create on a footer
--                      the width of the window, grouped on its right.
--    Side tabs         ProfessionsOverviewTab at TOPRIGHT y=-60 with seven
--                      profession tabs chained under it; the character
--                      window's tabs, sized and set flush the same way.
--
--  Two things are built after the window's first walk and are dressed when
--  they appear: the profession tabs (RefreshRightTabs shows them) and
--  everything in the schematic for a recipe (its reagent slots, the track
--  check box: Init runs per recipe).
--------------------------------------------------------------------------------
local PROF = { list = 72, pad = 8, control = 24, gap = 6, footer = 36 }

P{
    name  = "ProfessionsFrame",
    addon = "Blizzard_Professions",
    apply = function(f, k)
        local page = f.CraftingPage
        local top = (S.TITLE_BAND or 20) + 2

        -- Side tabs: the character window's treatment.
        local over = f.ProfessionsOverviewTab
        if over then
            k:Move(over, "TOPLEFT", f, "TOPRIGHT", T.LOOK.sideTab.gap, -(top + 6))
            S.Walk(over, 0)
            ModeTab(k, over)
        end
        local function Tabs()
            for _, tab in ipairs(f.rightProfessionTabs or {}) do
                if S.Alive(tab) then
                    S.Walk(tab, 0)
                    ModeTab(k, tab)
                end
            end
        end
        Tabs()
        k:After(f, "RefreshRightTabs", Tabs)

        -- The overview (the book page) fills its cards in Lua as it is shown.
        local book = f.BookPage
        if book then
            -- Unlearn sits LEFT of the bar's RIGHT, 1 across and 4 down; the
            -- bar's fill (and our well round it) is 3 down, so it read a pixel
            -- low. Centred on the fill, the well's height, a 2px gap.
            local function Unlearn()
                local content = book.ProfessionsContentFrame
                for _, key in ipairs({ "PrimaryProfession1", "PrimaryProfession2" }) do
                    local card = content and content[key]
                    local btn, bar = card and card.UnlearnButton, card and card.StatusBar
                    if btn and bar and bar.Fill then
                        local one = EV.Pixel:One(bar)
                        k:Size(btn, nil, bar.Fill:GetHeight() + 2 * one)
                        k:Move(btn, "LEFT", bar.Fill, "RIGHT", one + 2, 0)
                    end
                end
            end
            k:Hook(book, "OnShow", function(self2)
                C_Timer.After(0, function()
                    if self2:IsShown() then S.Walk(self2, 0); Unlearn() end
                end)
            end)
            Unlearn()
        end

        if not page then return end

        -- The tool bar, holding the skill bar.
        local bar = Band(page, "toolbar", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(PROF.list - top - 2)
        end)
        local rank = page.RankBar
        if rank then
            local function Seat() k:Move(rank, "CENTER", bar, "CENTER", 0, 3) end
            Seat()
            k:After(page, "SetRankBarAnchors", Seat)

            -- A small addition of ours: the overview's Unlearn cross, beside
            -- the skill bar on the profession's own page too. It opens
            -- Blizzard's own UNLEARN_SKILL dialog (type the word to confirm),
            -- exactly as the overview's button does
            -- (Blizzard_ProfessionsBook/Camelot, FormatProfession), and only
            -- for a primary profession, which is all the overview offers it for.
            k:Once(rank, "unlearn", function()
                local b = S.Ours(CreateFrame("Button", nil, rank))
                b:SetFrameStrata("HIGH")
                b:SetFrameLevel(rank:GetFrameLevel() + 5)
                local p = S.PainterFor(b)
                p:Fill(T.LOOK.buttonDanger.rest.fill)
                p:Border(T.LOOK.buttonDanger.rest.edge)
                p:Glyph("close", T.LOOK.close.glyphSize, "danger")
                p:States(T.LOOK.buttonDanger)
                b:SetScript("OnEnter", function(self2)
                    GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
                    GameTooltip:SetText(UNLEARN_SKILL_TOOLTIP or UNLEARN or "Unlearn")
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                S.D(rank).unlearn = b
            end)
            local unlearn = S.D(rank).unlearn
            local function Primary()
                local ok, info = pcall(Professions.GetProfessionInfo)
                if not (ok and info) then return end
                local line = info.parentProfessionID or info.professionID
                local p1, p2 = GetProfessions()
                for _, idx in ipairs({ p1, p2 }) do
                    if idx then
                        local name, _, _, _, _, _, skillLine = GetProfessionInfo(idx)
                        if skillLine == line then return name, skillLine end
                    end
                end
            end
            local function Unlearn()
                if not unlearn then return end
                local fill = rank.Fill
                local one = EV.Pixel:One(rank)
                local h = (fill and fill:GetHeight() or 18) + 2 * one
                unlearn:SetSize(h, h)
                unlearn:ClearAllPoints()
                unlearn:SetPoint("LEFT", fill or rank, "RIGHT", one + 2, 0)
                local name, line = Primary()
                unlearn:SetShown(name ~= nil and rank:IsShown())
                -- Blizzard's chat link button hangs off the bar's right end
                -- (LEFT of RankBar.RIGHT, x=-2), exactly where the cross now
                -- is: it moves along to stand after it, the same size.
                local link = page.LinkButton
                if link then
                    k:Size(link, h, h)
                    if unlearn:IsShown() then
                        k:Move(link, "LEFT", unlearn, "RIGHT", PROF.gap, 0)
                    else
                        k:Move(link, "LEFT", fill or rank, "RIGHT", one + 2, 0)
                    end
                end
                unlearn:SetScript("OnClick", function()
                    local popup = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
                        and "UNLEARN_SKILL_GAMEPAD" or "UNLEARN_SKILL"
                    StaticPopup_Show(popup, name, nil, line)
                end)
            end
            Unlearn()
            k:After(page, "Refresh", Unlearn)
        end

        -- The chat link button: a tertiary square (common-button-tertiary-
        -- square-*, swapped per state in OnButtonStateChanged) round a
        -- chat-link glyph. Ours: the button Look, the glyph kept and
        -- coloured by state like our own glyphs.
        local link = page.LinkButton
        if link then
            k:Once(link, "look", function()
                if link.Background then S.StripArt(link.Background) end
                local p = S.PainterFor(link)
                p:Fill(T.LOOK.button.rest.fill)
                p:Border(T.LOOK.button.rest.edge)
                if link.Icon and link.Icon.SetDesaturated then link.Icon:SetDesaturated(true) end
                p:States(T.LOOK.button, { glyph = link.Icon })
                k:After(link, "OnButtonStateChanged", function()
                    local d = S.D(link)
                    if d.Repaint then d.Repaint() end
                end)
            end)
        end

        -- The results log (only opened on its own with a controller, on
        -- Forever): its cards are the itemCard part; the scroll box's
        -- shadows are the loot card's gradient.
        local log = page.CraftingOutputLog
        local box = log and log.ScrollBox
        if box then
            for _, get in ipairs({ "GetUpperShadowTexture", "GetLowerShadowTexture" }) do
                local ok, t = pcall(box[get], box)
                if ok and t then S.StripArt(t) end
            end
        end

        -- The footer, the whole width of the window, like the spellbook's.
        local foot = Band(page, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(PROF.footer)
        end)

        -- The recipe list and the schematic sit straight on the window, with
        -- one hairline between them: no box round either (Ben: two nested
        -- borders read cramped). The list runs from the tool bar down to the
        -- footer; the schematic is Blizzard's fixed 484 tall, which ends on
        -- the footer's line.
        local list = page.RecipeList
        local form = page.SchematicForm
        if form then
            k:NoFill(form)
            EV.Pixel:ShowEdges(form, false)
            if form.NineSlice then k:Fade(form.NineSlice) end
        end
        if list then
            if list.BackgroundNineSlice then k:Fade(list.BackgroundNineSlice) end
            k:Fade(list)
            k:Anchors(list, { { "TOPLEFT", page, "TOPLEFT", 5, -PROF.list },
                              { "BOTTOMLEFT", foot, "TOPLEFT", 4, 0 } })
            k:Once(list, "divider", function()
                local rule = S.Ours(page:CreateTexture(nil, "BORDER"))
                if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(rule) end
                rule:SetPoint("TOPLEFT", list, "TOPRIGHT", 1, 0)
                rule:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 1, 0)
                local function Paint()
                    rule:SetColorTexture(S.Colour("border"))
                    rule:SetWidth(EV.Pixel:Line(page))
                end
                Paint()
                T.Watch(rule, Paint)
            end)
            local filter, search = list.FilterDropdown, list.SearchBox
            if filter then
                k:Size(filter, nil, PROF.control)
                k:Move(filter, "TOPRIGHT", list, "TOPRIGHT", -PROF.pad, -PROF.pad)
            end
            if search and filter then
                k:Size(search, nil, PROF.control)
                k:Anchors(search, { { "TOPLEFT", list, "TOPLEFT", PROF.pad, -PROF.pad },
                                    { "RIGHT", filter, "LEFT", -PROF.gap, 0 } })
            end
        end

        -- Create All, the count and Create, on the footer.
        if form then

            -- One group on the footer's right, the way Blizzard reads it:
            -- [Create All] [<] [count] [>] [Create], an even gap between each.
            -- Camelot pinned Create All and the count to fixed offsets from the
            -- page's corner (SetControlAnchors) and Create to another
            -- (Refresh, every recipe), which spread them across the footer.
            -- The arrows hang off the count box (NumericInputSpinnerTemplate:
            -- Decrement 6 left of it, Increment on its right), 23 wide.
            local count, create, all = page.CreateMultipleInputBox, page.CreateButton, page.CreateAllButton
            if count and count.SetJustifyH then count:SetJustifyH("CENTER") end
            local function Controls()
                if not (count and create and all) then return end
                local g, h = PROF.gap + 2, 22
                local arrow = h
                k:Size(create, nil, h)
                k:Size(all, nil, h)
                k:Size(count, nil, h)
                -- The arrows are 23x22 in the template; square, and the height
                -- of everything else on the line. The template puts Decrement
                -- 6 off the box and Increment flush against it, so the box sat
                -- off centre between them: both 6 off.
                local inc, dec = count.IncrementButton, count.DecrementButton
                if inc then k:Size(inc, arrow, h); k:Move(inc, "LEFT", count, "RIGHT", 6, 0) end
                if dec then k:Size(dec, arrow, h); k:Move(dec, "RIGHT", count, "LEFT", -6, 0) end
                k:Move(create, "RIGHT", foot, "RIGHT", -PROF.pad, 0)
                k:Move(count, "RIGHT", create, "LEFT", -(6 + arrow + g), 0)
                k:Move(all, "RIGHT", count, "LEFT", -(6 + arrow + g), 0)
            end
            Controls()
            k:After(page, "SetControlAnchors", Controls)
            k:After(page, "Refresh", Controls)
            -- A recipe's slots and controls are built and shown per recipe.
            k:After(form, "Init", function()
                C_Timer.After(0, function() if form:IsShown() then S.Walk(form, 0) end end)
            end)
        end
    end,
}

--------------------------------------------------------------------------------
--  SettingsPanel (Blizzard_Settings_Shared: Blizzard_SettingsPanel.xml,
--  Blizzard_SettingsList.xml, Mainline SettingsFrameTemplate)
--
--  The rows, sections, sliders and category list are parts. The window,
--  from Blizzard's numbers:
--
--    NineSlice.Text    the title, TOP y=-5 on the nine-slice: centred on our
--                      title band.
--    ClosePanelButton  flush in the band's corner, as on every window.
--    Options_InnerFrame an OVERLAY atlas at x=17 y=-64 framing the list and
--                      the page: cleared.
--    GameTab/AddOnsTab MinimalTabTemplate at x=32 y=-27, only while an addon
--                      has a category; SearchBox 350x22 over the page's top
--                      right. Both on a tool bar under the title.
--    CategoryList      x=18 y=-76, 199 wide, to 46 above the bottom: from the
--                      tool bar down to the footer, a hairline on its right.
--    Container         anchored to the list, so it follows it.
--    SettingsList.Header  a page's title, Defaults, and Options_HorizontalDivider
--                      under them: our rule instead.
--    Close/Apply       96x22 at the bottom right; OutputText (the key binding
--                      prompt) at BOTTOM y=24. On a footer across the window.
--------------------------------------------------------------------------------
local SET = { tool = 40, footer = 40, pad = 10, gap = 8, control = 24, search = 260 }

local function ClearAtlas(obj, pattern)
    for _, r in ipairs(S.Regions(obj)) do
        if not S.ours[r] and r.GetObjectType and r:GetObjectType() == "Texture" and S.ArtIs(r, pattern) then
            S.StripArt(r)
        end
    end
end

P{
    name  = "SettingsPanel",
    apply = function(f, k)
        local TB = S.TITLE_BAND or 24
        local top = TB + 2
        ClearAtlas(f, "options_innerframe")
        -- The window is painted here, on the panel itself. The generic parts
        -- would put it on SettingsFrameTemplate's NineSlice (the window part,
        -- by its layout) and on Bg (a frame at level 0), and the nine-slice,
        -- a child at the panel's own level, would then cover every band and
        -- rule drawn on the panel. So neither keeps a fill or an edge.
        local host = f
        local W = T.LOOK.window.rest
        local slice = f.NineSlice
        if slice then
            S.PainterFor(slice):FadeSlice(slice)
            k:NoFill(slice)
            EV.Pixel:ShowEdges(slice, false)
        end
        if f.Bg then k:Fade(f.Bg); k:NoFill(f.Bg) end
        k:Fill(f, W.fill)
        k:Border(f, W.edge)
        S.Shadow(f)

        -- The title band, with the title and the close button on it.
        S.TitleBar(host, S.PainterFor(host))
        local band = S.D(host).titleBar
        local title = f.NineSlice and f.NineSlice.Text
        if title and band then
            k:Anchors(title, { { "CENTER", band, "CENTER", 0, 0 } })
            k:Label(title, W.title, true)
        end
        local close = f.ClosePanelButton
        if close then k:Move(close, "TOPRIGHT", f, "TOPRIGHT", -1, -1) end

        -- The tool bar: the Game / AddOns tabs standing on its rule, the
        -- search box on its right.
        local tool = Band(host, "toolbar", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(SET.tool)
        end)
        local search = f.SearchBox
        if search then
            k:Size(search, SET.search, SET.control)
            k:Move(search, "RIGHT", tool, "RIGHT", -SET.pad, 0)
        end
        if f.GameTab then
            k:Size(f.GameTab, nil, SET.tool - SET.gap)
            k:Move(f.GameTab, "BOTTOMLEFT", tool, "BOTTOMLEFT", SET.pad, 0)
        end
        if f.AddOnsTab then k:Size(f.AddOnsTab, nil, SET.tool - SET.gap) end

        -- The footer: Close and Apply on its right, the binding prompt in
        -- its middle.
        local foot = Band(host, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(SET.footer)
        end)
        local done, apply = f.CloseButton, f.ApplyButton
        if done then
            k:Size(done, nil, SET.control)
            k:Move(done, "RIGHT", foot, "RIGHT", -SET.pad, 0)
        end
        if apply and done then
            k:Size(apply, nil, SET.control)
            k:Move(apply, "RIGHT", done, "LEFT", -SET.gap, 0)
        end
        if f.OutputText then k:Move(f.OutputText, "CENTER", foot, "CENTER", 0, 0) end

        -- The category list, from the tool bar to the footer, and one line
        -- between it and the page.
        local list = f.CategoryList
        if list then
            local y = top + SET.tool + 1 + SET.gap
            k:Anchors(list, { { "TOPLEFT", f, "TOPLEFT", SET.pad, -y },
                              { "BOTTOMLEFT", foot, "TOPLEFT", SET.pad - 1, SET.gap } })
            k:Once(list, "divider", function()
                local rule = S.Ours(host:CreateTexture(nil, "BORDER"))
                EV.Pixel.NoSnap(rule)
                rule:SetPoint("TOPLEFT", list, "TOPRIGHT", SET.gap, SET.gap)
                rule:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", SET.gap, -SET.gap)
                local function Paint()
                    rule:SetColorTexture(S.Colour("border"))
                    rule:SetWidth(EV.Pixel:Line(f))
                end
                Paint()
                T.Watch(rule, Paint)
            end)
        end

        -- A page's header: its title and Defaults over our rule.
        local header = f.Container and f.Container.SettingsList and f.Container.SettingsList.Header
        if header then
            ClearAtlas(header, "options_horizontaldivider")
            if header.Title then k:Label(header.Title, "text", true) end
            k:Once(header, "rule", function()
                local rule = S.Ours(header:CreateTexture(nil, "BORDER"))
                EV.Pixel.NoSnap(rule)
                rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
                rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -SET.pad, 0)
                local function Paint()
                    rule:SetColorTexture(S.Colour("border"))
                    rule:SetHeight(EV.Pixel:Line(header))
                end
                Paint()
                T.Watch(rule, Paint)
            end)
            if header.DefaultsButton then k:Size(header.DefaultsButton, nil, SET.control) end
        end
    end,
}

--------------------------------------------------------------------------------
--  "Level N Class" in the title bar, left of the name. Blizzard draws it in the
--  window (the character window's PaperDollLevelInfo over the stat pane, the
--  inspect window's InspectLevelText under the title) and sets it with
--  SetFormattedText, the class name in its class colour. Ours is a copy on the
--  title band, kept in step with Blizzard's through hooks on that font string,
--  which itself is faded. Present whatever pane is open.
--------------------------------------------------------------------------------
local function TitleInfo(k, f, fs)
    if not (fs and fs.GetText) then return end
    local d = S.D(f)
    local band = d.titleBar
    if not band then return end
    if not d.titleInfo then
        local tc = type(f.TitleContainer) == "table" and f.TitleContainer or f
        local label = S.Ours(tc:CreateFontString(nil, "OVERLAY"))
        local path = T.FontPath and T.FontPath()
        if path then label:SetFont(path, 11, "") end
        label:SetPoint("LEFT", band, "LEFT", 8, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        d.titleInfo = label
        local function Copy()
            local ok, text = pcall(fs.GetText, fs)
            label:SetText(ok and text or "")
            label:SetTextColor(S.Colour("textMuted"))
        end
        Copy()
        T.Watch(label, Copy)
        pcall(hooksecurefunc, fs, "SetFormattedText", Copy)
        pcall(hooksecurefunc, fs, "SetText", Copy)
    end
    fs:SetAlpha(0)
end
S.TitleInfo = TitleInfo

--------------------------------------------------------------------------------
--  InspectFrame (Blizzard_InspectUI, Camelot InspectUI.xml and
--  InspectPaperDollFrame.xml; ButtonFrameTemplate, 338x424, so the window part
--  gives it our title band). Laid out as the character window is: three
--  columns (the left slots, the model, the right slots) and three rows (the
--  title, the slots and model, the weapons).
--
--    InspectFrameInset ButtonFrameTemplate's inset, 4,-60 to -6,26: the slots
--                      hang off its corners. Its box goes; it moves up under
--                      our title band.
--    InspectModelFrame 231x320 at 52,-66, with Char-Corner / Char-Inner
--                      border pieces round it and a race backdrop in four
--                      BackgroundTop/Bot textures (set per inspect). All art:
--                      the model stands on the window, level with the slots.
--    LevelTextWrapper  "Level N Class" at TOP y=-27: into the title bar.
--    InspectTalents    102x20 at TOP y=-39 (ViewButton in its place out of
--                      range): on the weapons row, after the ranged slot.
--    ModeTabs          the character window's side tabs.
--------------------------------------------------------------------------------
local INSPECT = { lift = 30, gap = 4, button = 24, buttonW = 80, modelX = 48 }
local INSPECT_ART = { "BorderTopLeft", "BorderTopRight", "BorderBottomLeft", "BorderBottomRight",
                      "BorderLeft", "BorderRight", "BorderTop", "BorderBottom", "BorderBottom2",
                      "BackgroundTopLeft", "BackgroundTopRight", "BackgroundBotLeft",
                      "BackgroundBotRight", "BackgroundOverlay" }

P{
    name  = "InspectFrame",
    addon = "Blizzard_InspectUI",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        local pdf = _G.InspectPaperDollFrame
        local model = _G.InspectModelFrame
        local inset = f.Inset or _G.InspectFrameInset

        local tabs = f.ModeTabs
        if tabs then
            k:Move(tabs, "TOPLEFT", f, "TOPRIGHT", T.LOOK.sideTab.gap, -(top + 6))
            for _, tab in ipairs(tabs.Tabs or {}) do
                S.Walk(tab, 0)
                ModeTab(k, tab)
            end
        end

        TitleInfo(k, f, _G.InspectLevelText)

        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
            -- Up under the title band. The window keeps Blizzard's height:
            -- the weapons row is on the frame's bottom (BOTTOMLEFT +116 +16),
            -- so a shorter window brought it up level with the columns' last
            -- slots, and the right column ran into the talents button.
            k:Anchors(inset, { { "TOPLEFT", f, "TOPLEFT", 4, -(60 - INSPECT.lift) },
                               { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 26 } })
        end
        if model then
            for _, key in ipairs(INSPECT_ART) do
                local t = _G["InspectModelFrame" .. key]
                if t then S.StripArt(t) end
            end
            if inset then k:Move(model, "TOPLEFT", inset, "TOPLEFT", INSPECT.modelX, -2) end
        end

        local ranged = _G.InspectRangedSlot
        for _, key in ipairs({ "InspectTalents", "ViewButton" }) do
            local b = pdf and pdf[key]
            if b and ranged then
                k:Size(b, INSPECT.buttonW, INSPECT.button)
                k:Move(b, "LEFT", ranged, "RIGHT", INSPECT.gap * 3, 0)
            end
        end
    end,
}
