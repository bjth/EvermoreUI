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

--------------------------------------------------------------------------------
--  Shared bits
--------------------------------------------------------------------------------

--- Blizzard's paging arrows are plain Buttons with file art in their state
--- textures and no template, so no fingerprint reaches them and they stay
--- as raised gold icons on a flat panel. Swap the art for one of our
--- chevrons and leave the button exactly where it is.
local function PageButton(k, btn, dir)
    if not (btn and btn.CreateTexture) then return end
    S.Blank(btn)
    k:Fade(btn)
    local d = S.D(btn)
    if not d.chev and T.Chevron then
        d.chev = S.Ours(T.Chevron(btn, 5))
        d.chev:SetPoint("CENTER")
        d.chev:Point(dir)
        local function Paint(self) self:SetColorLines(T.RGBA("textMuted")) end
        Paint(d.chev)
        T.Watch(d.chev)
        d.chev.Paint = Paint
        k:Hook(btn, "OnEnter", function() d.chev:SetColorLines(T.RGBA("text")) end)
        k:Hook(btn, "OnLeave", function() d.chev:SetColorLines(T.RGBA("textMuted")) end)
    end
    -- The label ("Prev"/"Next") is a loose FontString region rather than the
    -- button's designated font string, so GetFontString() does not find it.
    for _, r in ipairs(S.Regions(btn)) do
        if r.GetObjectType and r:GetObjectType() == "FontString" and not S.ours[r] then
            r:SetAlpha(0)
        end
    end
end


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
                T.Watch(r)
                r.Paint = Paint
            end
        end
    end
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
--    * PrevPageButton and NextPageButton are bare Buttons with file art.
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
            PageButton(k, _G.InboxPrevPageButton, "left")
            PageButton(k, _G.InboxNextPageButton, "right")
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
--  The school tabs are TabSystem tabs in square mode
--  (Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.lua): a 36x35 icon
--  centred on a button 44 wide (icon + 8) and 32 tall, masked by SquareMask
--  anchored 2px in from the top and right only. So the icon overhangs the
--  box panelTab draws on the button, and loses two pixels on two sides.
--
--  The button itself is left alone: it is a child of a layout frame, and
--  resizing it would mean asking Blizzard's layout to run from our code.
--  Instead the box moves to a square of the button's own height, centred,
--  and the icon shrinks to sit inside it.
--
--  The page art (the parchment) can be hidden with a Skins setting, off by
--  default. With it hidden the window's own surface shows through, and the
--  spell names are lifted to our text colour on every page turn.
--------------------------------------------------------------------------------
local TAB_H = 32                 -- TabSystemButtonTemplate's height
local TAB_ICON = TAB_H - 8       -- inside a 1px border with a 3px gap

local function IconTabState(tab)
    local d = S.D(tab)
    if not d.iconBox then return end
    local on = tab.isSelected
    d.iconBox.fill:SetColorTexture(T.RGBA(on and "surface2" or "surfaceSunk"))
    for _, e in ipairs(d.iconBox.edges) do e:SetColorTexture(T.RGBA(on and "accent" or "border")) end
    if tab.Icon then
        local hot = on or (tab.IsMouseOver and tab:IsMouseOver())
        tab.Icon:SetDesaturated(not hot)
        tab.Icon:SetAlpha(hot and 1 or 0.75)
    end
end

local function IconTab(k, tab)
    if not (S.Alive(tab) and tab.tabIcon and tab.Icon) then return end
    local d = S.D(tab)
    -- panelTab painted the whole 44px rect; that box goes, ours replaces it.
    if d.fill then d.fill:SetAlpha(0) end
    if d.edges then for _, e in ipairs(d.edges) do e:SetAlpha(0) end end
    if not d.iconBox then
        local box = CreateFrame("Frame", nil, tab)
        S.ours[box] = true
        box:SetSize(TAB_H, TAB_H)
        box:SetPoint("CENTER")
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box.fill = box:CreateTexture(nil, "BACKGROUND")
        box.fill:SetAllPoints()
        box.edges = {}
        for i = 1, 4 do
            local e = box:CreateTexture(nil, "BORDER")
            if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(e) end
            box.edges[i] = e
        end
        local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(box)) or 1
        box.edges[1]:SetPoint("TOPLEFT");    box.edges[1]:SetPoint("TOPRIGHT");    box.edges[1]:SetHeight(px)
        box.edges[2]:SetPoint("BOTTOMLEFT"); box.edges[2]:SetPoint("BOTTOMRIGHT"); box.edges[2]:SetHeight(px)
        box.edges[3]:SetPoint("TOPLEFT");    box.edges[3]:SetPoint("BOTTOMLEFT");  box.edges[3]:SetWidth(px)
        box.edges[4]:SetPoint("TOPRIGHT");   box.edges[4]:SetPoint("BOTTOMRIGHT"); box.edges[4]:SetWidth(px)
        d.iconBox = box
        T.Watch(box.fill); box.fill.Paint = function() IconTabState(tab) end
        -- Pooled buttons: hooks go on once per button, state is re-read each time.
        k:After(tab, "SetTabSelected", function() IconTabState(tab) end)
        k:Hook(tab, "OnEnter", function() IconTabState(tab) end)
        k:Hook(tab, "OnLeave", function() IconTabState(tab) end)
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

-- Each spell has a Backplate (atlas spellbook-item-backplate) at 25% that
-- goes to 100% on hover (SpellBookItemMixin, defaultBackplateAlpha /
-- hoverBackplateAlpha). "backplate" is in S.ORNATE, so the walk mutes it to
-- 0, and OnIconLeave then put it back to Blizzard's 25% rather than our 0:
-- every spell you had hovered kept a smudge. It is a hover glow now: full on
-- hover (Blizzard's OnIconEnter), nothing at rest (our post-hook on leave).
-- Blizzard only ever changes its alpha, never its colour, so the tint is
-- ours: darkened into the stone while the parchment is hidden.
local BACKPLATE_DARK = { 0.42, 0.36, 0.30 }

local function LiftPage(paged, hide)
    if not (paged and paged.GetFrames) then return end
    local ok, frames = pcall(paged.GetFrames, paged)
    if not ok or type(frames) ~= "table" then return end
    for _, fr in ipairs(frames) do
        S.LiftText(fr)
        if fr.TextContainer then S.LiftText(fr.TextContainer) end
        local bp = fr.Backplate
        if bp and bp.SetVertexColor then
            if hide then bp:SetVertexColor(BACKPLATE_DARK[1], BACKPLATE_DARK[2], BACKPLATE_DARK[3])
            else bp:SetVertexColor(1, 1, 1) end
            local d = S.D(fr)
            if not d.backplateHooked and type(fr.OnIconLeave) == "function" then
                d.backplateHooked = true
                hooksecurefunc(fr, "OnIconLeave", function(self2)
                    if self2.Backplate then self2.Backplate:SetAlpha(0) end
                end)
            end
            -- Pooled frames can arrive carrying the last spell's leave alpha.
            if not (fr.IsMouseOver and fr:IsMouseOver()) then bp:SetAlpha(0) end
        end
    end
end
local function HidingPages()
    return S.module and S.module.db and S.module.db.hideSpellbookPages and true or false
end

P{
    name  = "PlayerSpellsFrame",
    addon = "Blizzard_PlayerSpells",
    apply = function(f, k)
        local book = f.SpellBookFrame
        if not book then return end

        local tabs = book.CategoryTabSystem
        if tabs then
            if tabs.tabs then for _, tab in ipairs(tabs.tabs) do IconTab(k, tab) end end
            local d = S.D(tabs)
            if not d.iconTabsHooked then
                d.iconTabsHooked = true
                -- Tabs are rebuilt from a pool whenever the spell list changes.
                k:After(tabs, "AddTab", function(self2, _, _)
                    local t = self2.tabs and self2.tabs[#self2.tabs]
                    if t then IconTab(k, t) end
                end)
            end
        end

        local hide = S.module and S.module.db and S.module.db.hideSpellbookPages
        for _, key in ipairs(PAGE_ART) do
            local r = book[key]
            if r and r.SetAlpha then r:SetAlpha(hide and 0 or 1) end
        end

        local paged = book.PagedSpellsFrame
        if paged then
            local d = S.D(paged)
            if not d.liftHooked then
                d.liftHooked = true
                k:After(paged, "DisplayViewsForCurrentPage", function(self2) LiftPage(self2, HidingPages()) end)
            end
            LiftPage(paged, hide)
        end
    end,
}
