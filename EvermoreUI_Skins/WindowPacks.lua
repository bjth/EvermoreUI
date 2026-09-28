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
--  Icon picker pop-ups: IconSelectorPopupFrameTemplate (SharedXML), used by
--  MacroPopupFrame and GearManagerPopupFrame. A BG texture, a BorderBox
--  (SelectionFrameTemplate, frameLevel 50, setAllPoints) over everything, the
--  name field (IconSelectorEditBox, three UI-ClassTrainer-FilterBorder
--  pieces), the current icon (SelectedIconButton: a slot square, the icon as
--  its NormalTexture) and the grid (IconSelector, SelectorButtonTemplate
--  buttons, which selectorButton dresses) under the BorderBox.
--
--  The generic window part filled the BorderBox, the top of the stack, and
--  so covered the grid entirely. The BorderBox keeps no fill; the pop-up
--  itself carries the surface and the edge. They are children of their
--  windows, not windows, so the windows' packs call this.
--------------------------------------------------------------------------------
local function IconPopup(k, pop)
    if not S.Alive(pop) then return end
    local box = pop.BorderBox
    if box then
        k:NoFill(box)
        EV.Pixel:ShowEdges(box, false)
    end
    if pop.BG then S.StripArt(pop.BG) end
    k:Fill(pop, "surface0")
    k:Border(pop, "border")
    local edit = box and box.IconSelectorEditBox
    if edit then
        for _, key in ipairs({ "IconSelectorPopupNameLeft", "IconSelectorPopupNameMiddle", "IconSelectorPopupNameRight" }) do
            if edit[key] then S.StripArt(edit[key]) end
        end
        k:Fill(edit, "surfaceSunk")
        k:Border(edit, "borderStrong")
        if edit.SetTextInsets then edit:SetTextInsets(6, 6, 0, 0) end
        k:Size(edit, nil, 24)
    end
    -- A footer for Okay and Cancel (Blizzard: 78x22 at the bottom right on
    -- nothing), and the grid ending a gap above it rather than on its line.
    local foot = Band(pop, "footer", "top", function(b)
        b:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 1, 1)
        b:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -1, 1)
        b:SetHeight(36)
    end)
    local cancel, okay = box and box.CancelButton, box and box.OkayButton
    if cancel then
        k:Size(cancel, 96, 24)
        k:Move(cancel, "RIGHT", foot, "RIGHT", -7, 0)
    end
    if okay then
        k:Size(okay, 96, 24)
        if cancel then k:Move(okay, "RIGHT", cancel, "LEFT", -6, 0) end
    end
    local grid = pop.IconSelector
    if grid then
        k:Anchors(grid, {
            { "TOPLEFT",     pop,  "TOPLEFT",  21, -97 },
            { "BOTTOMRIGHT", foot, "TOPRIGHT", -10, 6 },
        })
    end

    local sel = box and box.SelectedIconArea and box.SelectedIconArea.SelectedIconButton
    if sel then
        k:Once(sel, "popupIcon", function()
            for _, r in ipairs(S.Regions(sel)) do
                if r ~= sel.Icon and r.GetObjectType and r:GetObjectType() == "Texture" and not S.ours[r] then
                    S.StripArt(r)
                end
            end
            if sel.Highlight then S.StripArt(sel.Highlight) end
            if sel.Icon then
                sel.Icon:ClearAllPoints()
                sel.Icon:SetAllPoints(sel)
                EV.Icons:Style(sel.Icon, { host = sel })
            end
        end)
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
--
--  Rebuilt to the window standard (28 Sep), from Blizzard_MailFrame's
--  MailFrame.xml / .lua:
--
--    Window        ButtonFrameTemplate; MailFrameTab_OnClick re-anchors the
--                  Inset's top per tab (-58 inbox, -80 send). The Inset goes
--                  invisible (no double border), so its moving is harmless.
--    Inbox         seven MailItemTemplate rows (305x45) from 13,-70, each a
--                  37px CheckButton icon on a gold (unread) or grey (read)
--                  UI-EmptySlot square, sender and subject beside it, the
--                  expiry at the top right; Prev / Next (32px page buttons)
--                  and Open All (120x24) at the bottom, the page text under
--                  Open All. InboxFrame:Update shows each row's button only
--                  while it holds a letter, and greys a read letter's text
--                  and icon itself.
--    Send          To / Subject / Postage at the top, the body in
--                  SendMailScrollFrame (296x257 at 8,-83), sixteen attachment
--                  slots, the money row (SendMailMoneyButton at BOTTOMLEFT
--                  15,37), and at the bottom your money in a ThinGoldEdge box
--                  on an inset and Send / Cancel (80x22) at the right.
--
--  Ours: inbox letters as edge-to-edge rows under the title (loot's rows),
--  with a rule and hover only while the row holds a letter, copper while it
--  is the open one, the slot square gone (the text and icon already say read
--  or unread); a footer band on each tab: Prev, the page, Open All beside
--  Next on the inbox; your money, Send and Cancel on send. The body keeps a
--  sunk well of its own.
--------------------------------------------------------------------------------
local MAIL = { row = 45, pad = 8, gap = 6, footer = 36, button = 24, short = 96, open = 120, invoice = 12 }

local function MailRowSync(row)
    local d = S.D(row)
    if not d.mailFill then return end
    local b = row.Button or _G[row:GetName() .. "Button"]
    local has = b and b:IsShown() or false
    local okC, checked = pcall(b.GetChecked, b)
    local st = { hover = has and b:IsMouseOver() or false, on = has and okC and checked or false }
    local r = T.Resolve(T.LOOK.listItem, st)
    d.mailFill:SetColorTexture(T.C4(r.fill))
    d.mailFill:SetShown(has)
    d.mailRule:SetShown(has and d.mailIndex ~= 1)
end

local function MailRow(row, i)
    if not S.Alive(row) then return end
    local d = S.D(row)
    d.mailIndex = i
    if d.mailFill then return end
    -- The row's own art: two MailItemBorder pieces and a bare brown rule.
    for _, r in ipairs(S.Regions(row)) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and not S.ours[r] then S.Mute(r) end
    end
    d.mailFill = S.Ours(EV.Pixel:Fill(row, "BACKGROUND", -7))
    d.mailRule = S.Ours(row:CreateTexture(nil, "BORDER", nil, 1))
    EV.Pixel.NoSnap(d.mailRule)
    d.mailRule:SetPoint("TOPLEFT"); d.mailRule:SetPoint("TOPRIGHT")
    local function Paint()
        d.mailRule:SetColorTexture(S.Colour("divider"))
        d.mailRule:SetHeight(EV.Pixel:Line(row))
        MailRowSync(row)
    end
    Paint()
    T.Watch(d.mailFill, Paint)
    local b = row.Button or _G[row:GetName() .. "Button"]
    if b then
        local slot = _G[row:GetName() .. "ButtonSlot"]
        if slot then S.StripArt(slot) end
        for _, get in ipairs({ "GetHighlightTexture", "GetCheckedTexture" }) do
            local ok, t = pcall(b[get], b)
            if ok and t then S.StripArt(t) end
        end
        local function Sync() MailRowSync(row) end
        b:HookScript("OnEnter", Sync)
        b:HookScript("OnLeave", Sync)
        b:HookScript("OnShow", Sync)
        b:HookScript("OnHide", Sync)
        hooksecurefunc(b, "SetChecked", Sync)
    end
end

local function MailFooter(host, f)
    return Band(host, "footer", "top", function(b)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        b:SetHeight(MAIL.footer)
    end)
end

P{
    name  = "MailFrame",
    addon = "Blizzard_MailFrame",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end

        -- Inbox.
        local inbox = f.InboxFrame or InboxFrame
        if inbox then
            k:Art(inbox, "Interface\\MailFrame\\UI-MailFrameBG")
            local rows = _G.INBOXITEMS_TO_DISPLAY or 7
            for i = 1, rows do
                local row = _G["MailItem" .. i]
                if row then
                    MailRow(row, i)
                    -- Inset from the window (Ben: full width felt forced
                    -- here, unlike loot's short list).
                    local y = -(top + MAIL.pad + (i - 1) * MAIL.row)
                    k:Anchors(row, {
                        { "TOPLEFT",  f, "TOPLEFT",  MAIL.pad, y },
                        { "TOPRIGHT", f, "TOPRIGHT", -MAIL.pad, y },
                    })
                    row:SetHeight(MAIL.row)
                    -- The letter opens from its 37px icon button only; its
                    -- click area runs the row's width (as the loot rows'
                    -- does), stopping short of the expiry text.
                    local b = row.Button or _G[row:GetName() .. "Button"]
                    local w = S.Num(f:GetWidth())
                    if b and w then
                        local rowW = w - 2 * MAIL.pad
                        b:SetHitRectInsets(0, -(rowW - 4 - 37 - 4 - 104), -4, -4)
                    end
                    MailRowSync(row)
                end
            end
            local foot = MailFooter(inbox, f)
            local prev, nxt, all = inbox.PrevPageButton, inbox.NextPageButton, inbox.OpenAllMail
            if prev then k:Move(prev, "LEFT", foot, "LEFT", MAIL.pad - 1, 0) end
            if nxt then k:Move(nxt, "RIGHT", foot, "RIGHT", -(MAIL.pad - 1), 0) end
            if all then
                k:Size(all, MAIL.open, MAIL.button)
                if nxt then k:Move(all, "RIGHT", nxt, "LEFT", -MAIL.gap, 0)
                else k:Move(all, "RIGHT", foot, "RIGHT", -MAIL.pad, 0) end
            end
            local page = _G.InboxCurrentPage
            if page and prev then
                k:Move(page, "LEFT", prev, "RIGHT", MAIL.gap, 0)
                page:SetJustifyH("LEFT")
            end
            k:After(inbox, "Update", function()
                for i = 1, rows do
                    local row = _G["MailItem" .. i]
                    if row then MailRowSync(row) end
                end
            end)
        end

        -- Send.
        local send = f.SendMail or SendMailFrame
        if send then
            k:Art(send, "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
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
            -- The body: its own sunk well, round the text and its scroll bar.
            local body = _G.SendMailScrollFrame
            if body then
                k:Once(send, "mailBody", function()
                    local well = S.Ours(CreateFrame("Frame", nil, send))
                    well:EnableMouse(false)
                    well:SetFrameLevel(math.max(0, body:GetFrameLevel() - 1))
                    well:SetPoint("TOPLEFT", body, "TOPLEFT", -2, 2)
                    well:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", -2, -2)
                    well:SetPoint("RIGHT", f, "RIGHT", -MAIL.pad, 0)
                    local fill = S.Ours(EV.Pixel:Fill(well, "BACKGROUND", -7))
                    EV.Pixel:Edges(well, { size = 1 })
                    local function Paint()
                        fill:SetColorTexture(S.Colour("surfaceSunk"))
                        EV.Pixel:SetEdgeColor(well, S.Colour("border"))
                    end
                    Paint()
                    T.Watch(fill, Paint)
                end)
            end
            local foot = MailFooter(send, f)
            for _, n in ipairs({ "SendMailMoneyInset", "SendMailMoneyBg" }) do
                if _G[n] then k:Mute(_G[n]) end
            end
            local money = _G.SendMailMoneyFrame
            if money then k:Move(money, "LEFT", foot, "LEFT", MAIL.pad, 0) end
            local cancel, go = _G.SendMailCancelButton, _G.SendMailMailButton
            if cancel then
                k:Size(cancel, MAIL.short, MAIL.button)
                k:Move(cancel, "RIGHT", foot, "RIGHT", -(MAIL.pad - 1), 0)
            end
            if go then
                k:Size(go, MAIL.short, MAIL.button)
                if cancel then k:Move(go, "RIGHT", cancel, "LEFT", -MAIL.gap, 0) end
            end
            -- The money row stood on the footer's line; a gap above it.
            local row = _G.SendMailMoneyButton
            if row then k:Move(row, "BOTTOMLEFT", send, "BOTTOMLEFT", 15, MAIL.footer + 1 + MAIL.gap) end
        end
    end,
}

--------------------------------------------------------------------------------
--  OpenMailFrame: reading a letter (same file). ButtonFrameTemplate beside
--  the mail window; From / Subject and Report Spam at the top; the letter in
--  OpenMailScrollFrame (8,-84) on stationery (OpenStationeryBackground*, set
--  per letter in Lua), or an auction invoice on the same stationery with its
--  sum line (UI-MailFrame-InvoiceLine); the attachments below it; Reply,
--  Delete and Close (82/82/80 x 22) at the bottom right.
--
--  OpenMailMixin:Update lays the bottom out from the window's bottom edge on
--  every letter: attachments from 31 up (28 + 3), the body shortened to
--  meet them. Our footer is 36, so after Update the attachments, their
--  label and the rule are lifted MAIL.lift and the body is shortened by the
--  same. Blizzard re-sets all of them from their base every time, so the
--  lift never accumulates.
--------------------------------------------------------------------------------
MAIL.lift = MAIL.footer + 1 + MAIL.gap - 31

P{
    name  = "OpenMailFrame",
    addon = "Blizzard_MailFrame",
    apply = function(f, k)
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end
        k:Art(f, "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
        for _, name in ipairs({ "OpenStationeryBackgroundLeft", "OpenStationeryBackgroundRight" }) do
            local r = _G[name]
            if r then S.Mute(r) end
        end
        -- The invoice's sum line: a file texture; a hairline where it was.
        local sum = _G.OpenMailArithmeticLine
        if sum then
            S.StripArt(sum)
            k:Once(sum, "mailSum", function()
                local line = S.Ours(sum:GetParent():CreateTexture(nil, "ARTWORK"))
                EV.Pixel.NoSnap(line)
                line:SetPoint("CENTER", sum, "CENTER", 0, 0)
                line:SetSize(200, 1)
                local function Paint()
                    line:SetColorTexture(S.Colour("divider"))
                    line:SetHeight(EV.Pixel:Line(line:GetParent()))
                end
                Paint()
                T.Watch(line, Paint)
            end)
        end

        -- The letter: a sunk well round the text and its scroll bar.
        local body = _G.OpenMailScrollFrame
        if body then
            k:Once(f, "mailBody", function()
                local well = S.Ours(CreateFrame("Frame", nil, f))
                well:EnableMouse(false)
                well:SetFrameLevel(math.max(0, body:GetFrameLevel() - 1))
                well:SetPoint("TOPLEFT", body, "TOPLEFT", -2, 2)
                well:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", -2, -2)
                well:SetPoint("RIGHT", f, "RIGHT", -MAIL.pad, 0)
                local fill = S.Ours(EV.Pixel:Fill(well, "BACKGROUND", -7))
                EV.Pixel:Edges(well, { size = 1 })
                local function Paint()
                    fill:SetColorTexture(S.Colour("surfaceSunk"))
                    EV.Pixel:SetEdgeColor(well, S.Colour("border"))
                end
                Paint()
                T.Watch(fill, Paint)
            end)
        end

        -- The footer: Reply, Delete, Close on the right.
        local foot = MailFooter(f, f)
        local close, del, reply = _G.OpenMailCancelButton, _G.OpenMailDeleteButton, _G.OpenMailReplyButton
        if close then
            k:Size(close, MAIL.short, MAIL.button)
            k:Move(close, "RIGHT", foot, "RIGHT", -(MAIL.pad - 1), 0)
        end
        if del then
            k:Size(del, MAIL.short, MAIL.button)
            if close then k:Move(del, "RIGHT", close, "LEFT", -MAIL.gap, 0) end
        end
        if reply then
            k:Size(reply, MAIL.short, MAIL.button)
            if del then k:Move(reply, "RIGHT", del, "LEFT", -MAIL.gap, 0) end
        end

        -- The invoice was laid out for the parchment's border: its text 30
        -- in and 35 down, the price column 27 from the right. Everything
        -- else in it hangs off these two, so moving them brings it all in.
        local invoice = _G.OpenMailInvoiceFrame
        if invoice then
            if _G.OpenMailInvoiceItemLabel then
                k:Move(_G.OpenMailInvoiceItemLabel, "TOPLEFT", invoice, "TOPLEFT", MAIL.invoice, -MAIL.invoice)
            end
            if _G.OpenMailInvoiceSalePrice then
                k:Move(_G.OpenMailInvoiceSalePrice, "TOPRIGHT", invoice, "TOPRIGHT", -MAIL.invoice, -(77 - 35 + MAIL.invoice))
            end
        end
        local order = _G.ConsortiumMailFrame
        if order and order.OpeningText then
            k:Move(order.OpeningText, "TOPLEFT", order, "TOPLEFT", MAIL.invoice, -MAIL.invoice)
        end

        -- Lift a region Blizzard hangs off the window's bottom, from its
        -- BASE: the position Blizzard last gave it, recorded straight after
        -- Blizzard's Update (`fresh`) or the first time we see it. Every pass
        -- sets base + lift, so any number of passes lands in the same place.
        -- (Comparing against the last lifted value instead let a rounding
        -- hair through and lifted the icons twice.) Update runs before the
        -- window is shown on the first letter, and so before this pack,
        -- which is why the pack runs a pass of its own too.
        local function Lift(region, fresh)
            if not (region and region.GetPoint) then return end
            local ok, pt, rel, rp, x, y = pcall(region.GetPoint, region, 1)
            if not (ok and pt and rel == f and rp == "BOTTOMLEFT") then return end
            local d = S.D(region)
            if fresh or d.mailBase == nil then d.mailBase = y or 0 end
            region:SetPoint(pt, rel, rp, x, d.mailBase + MAIL.lift)
        end

        -- `fresh`: straight after Blizzard's Update, which has just put
        -- everything back to its base, so everything is lifted.
        local function Layout(fresh)
            for _, b in ipairs(f.activeAttachmentButtons or {}) do Lift(b, fresh) end
            -- The label over the attachments: Blizzard left-aligns it and
            -- centres the icons; centred with them. Blizzard adds its
            -- TOPLEFT without clearing ours, so look for its point.
            local label = _G.OpenMailAttachmentText
            if label then
                for i = 1, (label:GetNumPoints() or 0) do
                    local ok, pt, rel, rp, _, y = pcall(label.GetPoint, label, i)
                    if ok and pt == "TOPLEFT" and rel == f and rp == "BOTTOMLEFT" then
                        label:ClearAllPoints()
                        label:SetPoint("TOP", f, "BOTTOM", 0, (y or 0) + MAIL.lift)
                        break
                    end
                end
            end
            if body then
                local d = S.D(body)
                local h = S.Num(body:GetHeight())
                if h and (fresh or d.mailBaseH == nil) then d.mailBaseH = h end
                if d.mailBaseH then
                    body:SetHeight(d.mailBaseH - MAIL.lift)
                    if _G.OpenMailScrollChildFrame then _G.OpenMailScrollChildFrame:SetHeight(d.mailBaseH - MAIL.lift) end
                end
            end
        end
        k:After(f, "Update", function() Layout(true) end)
        Layout(false)
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


--------------------------------------------------------------------------------
--  Talking to NPCs: QuestFrame and GossipFrame (Mainline QuestFrame.xml,
--  QuestFrameTemplates.xml and GossipFrame.xml, which this client loads).
--
--  The two are the same window. Blizzard's geometry:
--
--    Window            338x496, ButtonFrameTemplate: Inset TOPLEFT 4,-60,
--                      BOTTOMRIGHT -6,26, an edged box of its own inside the
--                      window's edge.
--    Lists             300 wide, 403 tall, at the window's TOPLEFT 5,-65
--                      (the quest frame's four QuestScrollFrameTemplates, scroll
--                      bar 9 to the right) or the greeting panel's 8,-65
--                      (gossip's WowScrollBoxList, MinimalScrollBar 6 to the
--                      right). The 65 is room for the 60px portrait, which we
--                      hide: it was the empty space above the text.
--    Buttons           22 tall at the window's bottom, y=4, x=6 from either
--                      side: Accept 77, Decline 78, Complete Quest 120,
--                      Continue 120, Cancel 78, Goodbye 78. Nothing under
--                      them, and their tops met the inset's border at 26.
--
--  None of it is re-anchored by Blizzard's Lua (only the rows inside the
--  lists), so it is seated once:
--
--    * a footer band the width of the window, the buttons on it, one height,
--      centred on it, one width per kind of button;
--    * no inner box (Ben: the double border wastes space): the inset keeps
--      its job as the content rect, from the title rule to the footer, with
--      its art, fill and edge gone;
--    * each list from the content's top to its bottom, TALK.pad in, its
--      width kept (the text inside is laid out to Blizzard's 300).
--------------------------------------------------------------------------------
local TALK = { footer = 36, button = 24, pad = 8, short = 96, long = 120, wide = 140, gutter = 21, text = 18 }

local function TalkWindow(f, k, lists, buttons)
    local foot = Band(f, "footer", "top", function(b)
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        b:SetHeight(TALK.footer)
    end)

    for name, how in pairs(buttons) do
        local b = type(name) == "table" and name or _G[name]
        if b then
            k:Size(b, TALK[how[2]], TALK.button)
            if how[1] == "left" then
                k:Move(b, "LEFT", foot, "LEFT", TALK.pad, 0)
            else
                k:Move(b, "RIGHT", foot, "RIGHT", -TALK.pad, 0)
            end
        end
    end

    local inset = f.Inset
    if not inset then return end
    k:Fade(inset)
    if inset.NineSlice then k:Fade(inset.NineSlice) end
    k:NoFill(inset)
    EV.Pixel:ShowEdges(inset, false)
    k:Anchors(inset, {
        { "TOPLEFT",     f,    "TOPLEFT",  1, -((S.TITLE_BAND or 24) + 2) },
        { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
    })
    -- The lists run to TALK.gutter from the right, not Blizzard's fixed 300:
    -- a scroll frame clips what it holds, and a row of two item cards (the
    -- quest's required items and rewards, 147 wide from x=7) ends at about
    -- 303, so the right-hand card lost its right edge. The text inside is
    -- still laid out to 300 by Blizzard; the scroll bar keeps its offset
    -- from the list's right (9, or 6 for gossip) and lands in the gutter.
    for _, list in ipairs(lists) do
        local l = type(list) == "table" and list or _G[list]
        if l then
            k:Anchors(l, {
                { "TOPLEFT",     inset, "TOPLEFT",     TALK.pad, -TALK.pad },
                { "BOTTOMRIGHT", inset, "BOTTOMRIGHT", -TALK.gutter, TALK.pad },
            })
        end
    end
end

-- name -> side, width
local QUEST_BUTTONS = {
    QuestFrameAcceptButton          = { "left",  "short" },
    QuestFrameDeclineButton         = { "right", "short" },
    QuestFrameCompleteQuestButton   = { "left",  "long" },
    QuestFrameCompleteButton        = { "left",  "long" },
    QuestFrameGoodbyeButton         = { "right", "short" },
    QuestFrameGreetingGoodbyeButton = { "right", "short" },
}
local QUEST_SCROLLS = { "QuestDetailScrollFrame", "QuestRewardScrollFrame",
                        "QuestProgressScrollFrame", "QuestGreetingScrollFrame" }

P{
    name  = "QuestFrame",
    apply = function(f, k)
        TalkWindow(f, k, QUEST_SCROLLS, QUEST_BUTTONS)
    end,
}

--------------------------------------------------------------------------------
--  PetitionFrame (a guild charter) and GuildRegistrarFrame (buying one), both
--  Mainline and both the talk window again, but with their text hung straight
--  off the window rather than in a scroll frame: the charter from
--  PetitionFrameCharterTitle at 12,-80, the registrar's pages from 20,-70 and
--  10,-10. Each draws the QuestBG-Parchment atlas as Bg (7,-62) and hangs a
--  MinimalScrollBar off it that "is for cosmetic purposes; it never scrolls"
--  (PetitionFrame.xml). Ben had a charter to test on 28 Sep; the registrar
--  follows the same rules from the source, untested.
--
--  Ours: the talk window's footer and no inner box; the parchment and the
--  cosmetic scroll bar gone; the text from under the title, TALK.text in.
--  The charter's Rename stretches between Request and Close with a gap each
--  side (Blizzard: -3 into Request, flush to Close).
--------------------------------------------------------------------------------
local function TalkText(k, f, region)
    if region then k:Move(region, "TOPLEFT", f, "TOPLEFT", TALK.text, -((S.TITLE_BAND or 24) + 2 + TALK.pad)) end
end

P{
    name  = "PetitionFrame",
    apply = function(f, k)
        if f.Bg then S.StripArt(f.Bg) end
        if f.ScrollBar then k:Mute(f.ScrollBar) end
        TalkWindow(f, k, {}, {
            PetitionFrameSignButton    = { "left",  "long" },
            PetitionFrameRequestButton = { "left",  "wide" },
            PetitionFrameCancelButton  = { "right", "short" },
        })
        TalkText(k, f, _G.PetitionFrameCharterTitle)
        local rename, req, close = _G.PetitionFrameRenameButton, _G.PetitionFrameRequestButton, _G.PetitionFrameCancelButton
        if rename and req and close then
            k:Anchors(rename, {
                { "LEFT",  req,   "RIGHT", TALK.pad - 2, 0 },
                { "RIGHT", close, "LEFT",  -(TALK.pad - 2), 0 },
            })
            rename:SetHeight(TALK.button)
        end
    end,
}

P{
    name  = "GuildRegistrarFrame",
    apply = function(f, k)
        if f.Bg then S.StripArt(f.Bg) end
        if f.ScrollBar then k:Mute(f.ScrollBar) end
        TalkWindow(f, k, {}, {
            GuildRegistrarFrameGoodbyeButton  = { "right", "short" },
            GuildRegistrarFrameCancelButton   = { "right", "short" },
            GuildRegistrarFramePurchaseButton = { "left",  "short" },
        })
        TalkText(k, f, _G.GuildRegistrarText)
        TalkText(k, f, _G.AvailableServicesText)
        TalkText(k, f, _G.GuildRegistrarPurchaseText)
    end,
}

P{
    name  = "GossipFrame",
    apply = function(f, k)
        local panel = f.GreetingPanel
        if not panel then return end
        local buttons = {}
        if panel.GoodbyeButton then buttons[panel.GoodbyeButton] = { "right", "short" } end
        TalkWindow(f, k, { panel.ScrollBox }, buttons)
    end,
}

--------------------------------------------------------------------------------
--  ClassTrainerFrame (Blizzard_TrainerUI, Mainline, plus the Camelot file,
--  which only turns categories on).
--
--  Blizzard's geometry:
--
--    Window            ButtonFrameTemplate; BG (the TrainerTextures sheet)
--                      stretched round the list, MoneyBg (UI-MoneyFrame-Border)
--                      at BOTTOMLEFT 5,-9 with the money frame on it.
--    Tool row          ClassTrainerStatusBar 130x18 at 64,-35 (trade skill
--                      trainers only), FilterDropdown at TOPRIGHT -13,-35,
--                      100 wide (OnLoad).
--    List              ScrollBox 302 wide at the Inset's TOPLEFT 5,-5, its
--                      MinimalScrollBar 5 to the right; with a trade skill
--                      step, skillStepButton (316x40) at the inset's top and
--                      the list in bottomInset under it. ClassTrainerFrame_
--                      Update clears and re-anchors the list and the Inset on
--                      every refresh, so both are seated again after it.
--    Train             MagicButtonTemplate at BOTTOMRIGHT; our Train all
--                      (EvermoreUI_QoL) hangs off its left at its height.
--
--  Ours: a tool bar under the title with the rank bar on the left and the
--  filter on the right, a footer with the money on the left and Train on the
--  right, no inner boxes (the double border again), the list between the
--  two with the scroll bar centred in a gutter. The rows are trainerRow.
--------------------------------------------------------------------------------
local TRAIN = { tool = 40, control = 30, pad = 8, gap = 6, footer = 36, button = 24,
                train = 96, gutter = 20, step = 40 }

P{
    name  = "ClassTrainerFrame",
    addon = "Blizzard_TrainerUI",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(TRAIN.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(TRAIN.footer)
        end)

        if f.BG then S.StripArt(f.BG) end
        if _G.ClassTrainerFrameMoneyBg then S.StripArt(_G.ClassTrainerFrameMoneyBg) end
        for _, inset in ipairs({ f.Inset, f.bottomInset }) do
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end

        -- The tool bar: rank on the left, filter on the right.
        if f.FilterDropdown then
            k:Size(f.FilterDropdown, nil, TRAIN.control)
            k:Move(f.FilterDropdown, "RIGHT", bar, "RIGHT", -(TRAIN.pad - 1), 0)
        end
        local rank = _G.ClassTrainerStatusBar
        if rank then k:Move(rank, "LEFT", bar, "LEFT", TRAIN.pad + 1, 0) end

        -- The footer: what you have on the left, Train on the right.
        local train = f.TrainButton or _G.ClassTrainerTrainButton
        if train then
            k:Size(train, TRAIN.train, TRAIN.button)
            k:Move(train, "RIGHT", foot, "RIGHT", -(TRAIN.pad - 1), 0)
        end
        for _, m in ipairs({ f.money, f.trainingPoints }) do
            k:Move(m, "LEFT", foot, "LEFT", TRAIN.pad + 1, 0)
        end

        -- The list, between the bars, after every refresh.
        local function SeatList()
            local box, sbar, step = f.ScrollBox, f.ScrollBar, f.skillStepButton
            if not box then return end
            local above, y = bar, -TRAIN.gap
            if step and step:IsShown() then
                k:Anchors(step, {
                    { "TOPLEFT",  bar, "BOTTOMLEFT",  TRAIN.pad - 1, -TRAIN.gap },
                    { "TOPRIGHT", bar, "BOTTOMRIGHT", -TRAIN.gutter, -TRAIN.gap },
                })
                step:SetHeight(TRAIN.step)
                above = step
            end
            k:Anchors(box, {
                { "TOPLEFT",     above, "BOTTOMLEFT", above == bar and TRAIN.pad - 1 or 0, y },
                { "BOTTOMRIGHT", foot,  "TOPRIGHT",   -TRAIN.gutter, TRAIN.gap },
            })
            if sbar then
                local w = S.Num(sbar:GetWidth()) or 8
                local x = math.floor((TRAIN.gutter - w) / 2 + 0.5)
                k:Anchors(sbar, {
                    { "TOPLEFT",    box, "TOPRIGHT",    x, 0 },
                    { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, 0 },
                })
            end
        end
        -- Every row we can see, in the state Blizzard has just set. The
        -- window's opening pick (OnShow: Update, then
        -- ClassTrainer_SelectNearestLearnableSkill -> ClassTrainer_SetSelection)
        -- all happens before our discovery sees the window, so the rows' own
        -- hooks can miss it: repaint after Blizzard's selection and refresh,
        -- and once more the frame after the window opens.
        local function Rows()
            local sync = S.TrainerRowSync
            if not sync then return end
            local box = f.ScrollBox
            if box and box.ForEachFrame then pcall(box.ForEachFrame, box, sync) end
            if f.skillStepButton then sync(f.skillStepButton) end
        end
        SeatList()
        Rows()
        k:Once(f, "trainerList", function()
            if type(_G.ClassTrainerFrame_Update) == "function" then
                hooksecurefunc("ClassTrainerFrame_Update", function() SeatList(); Rows() end)
            end
            if type(_G.ClassTrainer_SetSelection) == "function" then
                hooksecurefunc("ClassTrainer_SetSelection", Rows)
            end
            f:HookScript("OnShow", function() C_Timer.After(0, Rows) end)
        end)
    end,
}

--------------------------------------------------------------------------------
--  MerchantFrame (Mainline MerchantFrame.xml / .lua, which this client loads).
--
--  Blizzard's geometry:
--
--    Window            336x444, ButtonFrameTemplate. FilterDropdown at
--                      TOPRIGHT -11,-30 (hidden where the MerchantFilterDisabled
--                      game rule is on, as it is on Forever).
--    Items             MerchantItem1-12 (MerchantItemTemplate, 153x44): the
--                      UI-EmptySlot square (SlotTexture, 64x64 at -13,13) and
--                      the UI-Merchant-LabelSlots plate ($parentNameFrame)
--                      behind a 37px ItemButton at TOPLEFT. Two columns 12
--                      apart from TOPLEFT 11,-69; rows 8 apart on the merchant
--                      tab and 15 on buyback, re-set on every update.
--    Can't use/buy     UpdateMerchantInfo tints the icon, slot and plate red
--                      (vertex colours) when `not isPurchasable or (not
--                      isUsable and not heirloom)`, grey when out of stock.
--                      Can't afford only reds the price.
--    Bottom            MerchantFrameBottomLeftBorder (UI-Merchant-BotFrame)
--                      holding the repair, repair all, guild repair and sell
--                      junk buttons (36x36 on UI-EmptySlot, placed by
--                      UpdateRepairButtons) and MerchantBuyBackItem (115x37);
--                      the pager (32px page buttons, page text) above it;
--                      the money in a ThinGoldEdge box on an inset at the
--                      bottom right, extra currencies to its left (both placed
--                      by UpdateCurrencies).
--
--  Ours, re-seated after each of Blizzard's update functions:
--
--    * a tool bar under the title only while the filter is shown;
--    * the grid 12 in, 6 apart both ways, on both tabs;
--    * each item a tile card with our empty well where the slot art was, the
--      icon in its own colours (Blizzard's tint undone), and the card's edge
--      red for what you can't use or can't buy (Blizzard's test, and the
--      price you can't pay), dimmed for out of stock and empty slots;
--    * an actions band over the footer: the repair and junk buttons on the
--      left in our icon style, the last item sold as a card on the right;
--      the pager on the band's top;
--    * the footer: money on the right (on the left when extra currencies
--      take the right), no gold box, no insets, no inner box.
--------------------------------------------------------------------------------
local MERCH = { pad = 12, gap = 6, tool = 40, control = 30, footer = 36, actions = 52,
                button = 36, icon = 4, buyback = 140, pager = 32, pair = 2 }
local MERCH_ACTIONS = { "MerchantRepairItemButton", "MerchantRepairAllButton",
                        "MerchantGuildBankRepairButton", "MerchantSellAllJunkButton" }
local MERCH_HIDE = { "MerchantMoneyInset", "MerchantMoneyBg",
                     "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" }

local function MerchIcon(b)
    return b and (rawget(b, "Icon") or rawget(b, "icon") or b.icon)
end

--- One item's card: state is "ok", "no" (can't use or buy), "out" (out of
--- stock) or "empty".
local function MerchantCardSync(item)
    local d = S.D(item)
    if not d.merchFill then return end
    local b = item.ItemButton
    local st = { hover = b and b:IsShown() and b:IsMouseOver() or false,
                 disabled = d.merchState == "empty" or d.merchState == "out" }
    local r = T.Resolve(T.LOOK.tile, st)
    d.merchFill:SetColorTexture(T.C4(r.fill))
    T.SetEdge(item, d.merchState == "no" and { S.Colour("danger") } or r.edge)
end

local function MerchantCard(item)
    if not S.Alive(item) then return end
    local d = S.D(item)
    if d.merchFill then return end
    local name = item:GetName()
    S.StripArt(item.SlotTexture or (name and _G[name .. "SlotTexture"]))
    local plate = name and _G[name .. "NameFrame"]
    if plate then S.StripArt(plate) end
    d.merchFill = S.Ours(EV.Pixel:Fill(item, "BACKGROUND", -7))
    EV.Pixel:Edges(item, { size = 1 })
    local b = item.ItemButton
    if b then
        -- The empty slot, ours: a well where the button sits, under it, so it
        -- shows only when the button is hidden or has nothing in it.
        b:ClearAllPoints()
        b:SetPoint("LEFT", item, "LEFT", MERCH.icon, 0)
        S.Well(item, b, 1)
        b:HookScript("OnEnter", function() MerchantCardSync(item) end)
        b:HookScript("OnLeave", function() MerchantCardSync(item) end)
    end
    T.Watch(d.merchFill, function() MerchantCardSync(item) end)
end

--- The name and the price as one group, centred on the card: the name ends
--- MERCH.pair above the middle, the price starts MERCH.pair below it; with no
--- price the name is centred alone.
---
--- Blizzard hangs the price (and UpdateMerchantInfo the alternative currency,
--- on every update) from the name plate's BOTTOMLEFT: +2,+31 on the grid,
--- +0,+25 on the buyback item. The plate is invisible now but still the
--- anchor, so it is placed where those offsets put the price's top on the
--- line below the middle, from the price's own height.
local function MerchantText(item)
    local name = item:GetName()
    if not name then return end
    local x = MERCH.icon + 37 + 6
    local back = item == _G.MerchantBuyBackItem
    local lift, nudge = back and 25 or 31, back and 0 or 2
    local money, alt = _G[name .. "MoneyFrame"], _G[name .. "AltCurrencyFrame"]
    local priced = (money and money:IsShown()) or (alt and alt:IsShown())
    local plate = _G[name .. "NameFrame"]
    local h = S.Num(money and money:GetHeight()) or 13
    local mid = (S.Num(item:GetHeight()) or 44) / 2
    if plate then
        plate:ClearAllPoints()
        plate:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", x - nudge, (mid - MERCH.pair - h) - lift)
    end
    local label = item.Name or _G[name .. "Name"]
    if label then
        label:ClearAllPoints()
        label:SetWordWrap(false)
        label:SetHeight(14)
        if priced then
            label:SetPoint("BOTTOMLEFT", item, "LEFT", x, MERCH.pair)
            label:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            label:SetJustifyV("BOTTOM")
        else
            label:SetPoint("LEFT", item, "LEFT", x, 0)
            label:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            label:SetJustifyV("MIDDLE")
        end
    end
end

local function SetMerchantState(item, state)
    MerchantCard(item)
    S.D(item).merchState = state
    MerchantText(item)
    local icon = MerchIcon(item.ItemButton)
    if icon and icon.SetVertexColor and state ~= "empty" then
        -- Blizzard's red (or grey) tint on the art goes: the card says it.
        local v = state == "out" and 0.5 or 1
        icon:SetVertexColor(v, v, v)
    end
    MerchantCardSync(item)
end

local function MerchantStates()
    local money = GetMoney() or 0
    if MerchantFrame.selectedTab == 1 then
        local per = MERCHANT_ITEMS_PER_PAGE or 10
        local count = GetMerchantNumItems() or 0
        for i = 1, per do
            local item = _G["MerchantItem" .. i]
            local index = ((MerchantFrame.page or 1) - 1) * per + i
            local state = "empty"
            local ok, info = false, nil
            if index <= count and C_MerchantFrame and C_MerchantFrame.GetItemInfo then
                ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
            end
            if ok and type(info) == "table" then
                local id = GetMerchantItemID and GetMerchantItemID(index)
                local heir = id and C_Heirloom and C_Heirloom.IsItemHeirloom(id)
                local red = not info.isPurchasable or (not info.isUsable and not heir)
                local okA, afford = pcall(CanAffordMerchantItem, index)
                if red or (okA and afford == false) then state = "no"
                elseif info.numAvailable == 0 then state = "out"
                else state = "ok" end
            end
            if item then SetMerchantState(item, state) end
        end
        -- The last thing sold, on the actions band.
        local last = GetNumBuybackItems and GetNumBuybackItems() or 0
        local state = "empty"
        if last > 0 then
            local name, _, price, _, _, usable = GetBuybackItemInfo(last)
            if name then state = (not usable or (price or 0) > money) and "no" or "ok" end
        end
        if _G.MerchantBuyBackItem then SetMerchantState(_G.MerchantBuyBackItem, state) end
    else
        for i = 1, BUYBACK_ITEMS_PER_PAGE or 12 do
            local item = _G["MerchantItem" .. i]
            local name, _, price, _, _, usable = GetBuybackItemInfo(i)
            local state = "empty"
            if name then state = (not usable or (price or 0) > money) and "no" or "ok" end
            if item then SetMerchantState(item, state) end
        end
    end
end

--- A repair or junk button in our icon style: the slot and Blizzard's
--- pushed and highlight art cleared, the icon ours, its edge lifting under
--- the mouse. Blizzard's desaturate-when-unavailable stays.
local function MerchantActionButton(b)
    if not S.Alive(b) then return end
    local d = S.D(b)
    if d.merchAction then return end
    d.merchAction = true
    local icon = b.Icon
    for _, r in ipairs(S.Regions(b)) do
        if r ~= icon and r.GetObjectType and r:GetObjectType() == "Texture" and not S.ours[r] then
            S.StripArt(r)
        end
    end
    for _, get in ipairs({ "GetPushedTexture", "GetHighlightTexture", "GetNormalTexture" }) do
        local ok, t = pcall(b[get], b)
        if ok and t then S.StripArt(t) end
    end
    if not icon then return end
    icon:ClearAllPoints()
    icon:SetAllPoints(b)
    EV.Icons:Style(icon, { host = b })
    local function Sync()
        if b:IsMouseOver() then
            local e = T.Resolve(T.LOOK.slot, { hover = true }).edge
            EV.Icons:SetState(icon, e[1], e[2], e[3], e[4])
        else
            EV.Icons:SetState(icon, nil)
        end
    end
    b:HookScript("OnEnter", Sync)
    b:HookScript("OnLeave", Sync)
end

P{
    name  = "MerchantFrame",
    apply = function(f, k)
        local title = (S.TITLE_BAND or 24) + 2
        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -title)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -title)
            b:SetHeight(MERCH.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(MERCH.footer)
        end)
        local acts = Band(f, "actions", "top", function(b)
            b:SetPoint("BOTTOMLEFT", foot, "TOPLEFT", 0, 1)
            b:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT", 0, 1)
            b:SetHeight(MERCH.actions)
        end)

        -- Chrome that goes.
        for _, n in ipairs({ "BuybackBG", "MerchantFrameBottomLeftBorder" }) do
            if _G[n] then S.StripArt(_G[n]) end
        end
        for _, n in ipairs(MERCH_HIDE) do
            if _G[n] then k:Mute(_G[n]) end
        end
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end
        for _, n in ipairs(MERCH_ACTIONS) do MerchantActionButton(_G[n]) end

        local function SeatGrid()
            local dd = f.FilterDropdown
            local tool = dd and dd:IsShown()
            bar:SetShown(tool and true or false)
            if tool then
                k:Size(dd, nil, MERCH.control)
                k:Move(dd, "RIGHT", bar, "RIGHT", -(MERCH.pad - 1), 0)
            end
            local top = title + (tool and MERCH.tool or 0) + MERCH.gap
            local per = (MerchantFrame.selectedTab == 1) and (MERCHANT_ITEMS_PER_PAGE or 10) or (BUYBACK_ITEMS_PER_PAGE or 12)
            for i = 1, math.max(per, 12) do
                local item = _G["MerchantItem" .. i]
                if item then
                    MerchantCard(item)
                    item:ClearAllPoints()
                    if i == 1 then
                        item:SetPoint("TOPLEFT", f, "TOPLEFT", MERCH.pad, -top)
                    elseif i % 2 == 0 then
                        item:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 1)], "TOPRIGHT", MERCH.gap, 0)
                    else
                        item:SetPoint("TOPLEFT", _G["MerchantItem" .. (i - 2)], "BOTTOMLEFT", 0, -MERCH.gap)
                    end
                end
            end
            -- The actions band and the pager are the merchant tab's.
            local merchant = MerchantFrame.selectedTab == 1
            acts:SetShown(merchant)
            local back = _G.MerchantBuyBackItem
            if back then
                MerchantCard(back)
                back:SetSize(MERCH.buyback, 44)
                back:ClearAllPoints()
                back:SetPoint("RIGHT", acts, "RIGHT", -(MERCH.pad - 1), 0)
            end
            local prev, nxt, page = _G.MerchantPrevPageButton, _G.MerchantNextPageButton, _G.MerchantPageText
            if prev then prev:ClearAllPoints(); prev:SetPoint("BOTTOMLEFT", acts, "TOPLEFT", MERCH.pad - 1, MERCH.gap) end
            if nxt then nxt:ClearAllPoints(); nxt:SetPoint("BOTTOMRIGHT", acts, "TOPRIGHT", -(MERCH.pad - 1), MERCH.gap) end
            if page then page:ClearAllPoints(); page:SetPoint("CENTER", acts, "TOP", 0, MERCH.gap + MERCH.pager / 2) end
        end

        -- Each button on the band by its own offset, never on another
        -- button: UpdateRepairButtons adds points without clearing them
        -- (Repair Item RIGHT on Repair All's LEFT, Sell Junk on Repair All),
        -- and a chain of ours running the other way made a loop the client
        -- refuses ("Cannot anchor to a region dependent on it").
        local function SeatActions()
            local x = MERCH.pad - 1
            for _, n in ipairs(MERCH_ACTIONS) do
                local b = _G[n]
                if b and b:IsShown() then
                    MerchantActionButton(b)
                    b:SetSize(MERCH.button, MERCH.button)
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", acts, "LEFT", x, 0)
                    x = x + MERCH.button + MERCH.gap
                end
            end
        end

        local function SeatMoney()
            local money = _G.MerchantMoneyFrame
            local tokens = _G.MerchantExtraCurrencyInset and _G.MerchantExtraCurrencyInset:IsShown()
            if money then
                money:ClearAllPoints()
                if tokens then
                    money:SetPoint("LEFT", foot, "LEFT", MERCH.pad, 0)
                else
                    money:SetPoint("RIGHT", foot, "RIGHT", -(MERCH.pad - 4), 0)
                end
            end
            local first = _G.MerchantToken1
            if tokens and first then
                first:ClearAllPoints()
                first:SetPoint("RIGHT", foot, "RIGHT", -(MERCH.pad - 4), 0)
            end
            for _, n in ipairs(MERCH_HIDE) do
                if _G[n] then _G[n]:SetAlpha(0) end
            end
        end

        local function All()
            SeatGrid()
            SeatActions()
            SeatMoney()
            MerchantStates()
        end
        All()
        k:Once(f, "merchantLayout", function()
            for _, fn in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
                if type(_G[fn]) == "function" then
                    hooksecurefunc(fn, function() SeatGrid(); SeatActions(); MerchantStates() end)
                end
            end
            if type(_G.MerchantFrame_UpdateRepairButtons) == "function" then
                hooksecurefunc("MerchantFrame_UpdateRepairButtons", SeatActions)
            end
            if type(_G.MerchantFrame_UpdateCurrencies) == "function" then
                hooksecurefunc("MerchantFrame_UpdateCurrencies", SeatMoney)
            end
        end)
    end,
}

--------------------------------------------------------------------------------
--  LootFrame (Mainline LootFrame.xml, ScrollingFlatPanel.xml/.lua).
--
--  Blizzard's geometry: a ScrollingFlatPanelTemplate 220 wide (+16 while its
--  scroll bar shows), ScrollBox at TOPLEFT 4,-22 and BOTTOM 0,4, a linear view
--  padded 6 all round with 2 between 46px rows, and a height Resize works out
--  on every open as rows + gaps + 26 + 20, capped at 290. Shown through
--  ShowUIPanel only when loot isn't under the mouse, so Discover takes it by
--  name. The rows are the lootRow part.
--
--  Ours (Ben: a row per item, no borders, no padding): the view's padding and
--  gaps taken to nothing, the list from our title rule to the window's bottom
--  edge and side to side (less a gutter for the scroll bar while it shows),
--  and the height, after Blizzard's Resize, exactly the title and the rows.
--------------------------------------------------------------------------------
local LOOT = { row = 46, gutter = 16 }

P{
    name  = "LootFrame",
    apply = function(f, k)
        local box, bar = f.ScrollBox, f.ScrollBar
        if not box then return end
        if f.Bg then k:Strip(f.Bg, 1) end
        for _, get in ipairs({ "GetUpperShadowTexture", "GetLowerShadowTexture" }) do
            local ok, t = pcall(box[get], box)
            if ok and t then S.StripArt(t) end
        end
        local top = (S.TITLE_BAND or 24) + 2

        local function Seat()
            local gutter = (bar and bar:IsShown()) and LOOT.gutter or 0
            k:Anchors(box, {
                { "TOPLEFT",     f, "TOPLEFT",     1, -top },
                { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -(1 + gutter), 1 },
            })
            if bar and gutter > 0 then
                local w = S.Num(bar:GetWidth()) or 8
                local x = -(1 + gutter) + math.floor((gutter - w) / 2 + 0.5)
                k:Anchors(bar, {
                    { "TOPLEFT",    f, "TOPRIGHT",    x, -(top + 4) },
                    { "BOTTOMLEFT", f, "BOTTOMRIGHT", x, 5 },
                })
            end
            if f.isInEditMode then return end
            local okN, n = pcall(box.GetDataProviderSize, box)
            if okN and type(n) == "number" and n > 0 then
                f:SetHeight(math.min(top + n * LOOT.row + 1, f.panelMaxHeight or 290))
            end
        end

        k:Once(f, "lootView", function()
            local okV, view = pcall(box.GetView, box)
            if okV and view and view.SetPadding then pcall(view.SetPadding, view, 0, 0, 0, 0, 0) end
            if type(f.Resize) == "function" then hooksecurefunc(f, "Resize", Seat) end
        end)
        Seat()
    end,
}

--------------------------------------------------------------------------------
--  TimeManagerFrame: the clock (Blizzard_TimeManager, Mainline), from the
--  minimap's time. 220x240 ButtonFrameTemplate, shown with a bare Show by
--  TimeManager_Toggle, so Discover takes it by name. Its portrait is a globe
--  (TimeManagerGlobe) with the time on it (TimeManagerFrameTicker, set every
--  update), and its title a loose font string at TOP x=15 to clear the globe.
--  TimeManagerStopwatchFrame (160x60 at TOPRIGHT 10,-12) holds "Show
--  Stopwatch" and a 28px pocket-watch check; the alarm block starts at
--  12,-65 and the Enabled check sits at the frame's LEFT 12,-45.
--
--  Ours: the time in the title bar's left, as level and class are on the
--  character window; the title through the window's own title; the
--  stopwatch toggle on a tool bar under the title, an icon in our style,
--  copper while the stopwatch is shown; the alarm block 6 under the bar,
--  which keeps it clear of the Enabled check as Blizzard's was.
--------------------------------------------------------------------------------
local CLOCK = { tool = 36, pad = 8, gap = 6 }

P{
    name  = "TimeManagerFrame",
    addon = "Blizzard_TimeManager",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end
        if _G.TimeManagerGlobe then S.StripArt(_G.TimeManagerGlobe) end

        -- The title: Blizzard's loose one goes, the window's own takes it.
        for _, r in ipairs(S.Regions(f)) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r ~= _G.TimeManagerFrameTicker then
                local ok, t = pcall(r.GetText, r)
                if ok and t == _G.TIMEMANAGER_TITLE then r:SetAlpha(0) end
            end
        end
        if f.SetTitle and _G.TIMEMANAGER_TITLE then f:SetTitle(_G.TIMEMANAGER_TITLE) end

        -- The time, in the title bar on the left.
        local ticker = _G.TimeManagerFrameTicker
        if ticker then
            k:Move(ticker, "LEFT", f, "TOPLEFT", CLOCK.pad + 2, -((S.TITLE_BAND or 24) / 2 + 1))
            ticker:SetJustifyH("LEFT")
            k:Label(ticker, "text", true)
        end

        -- The stopwatch toggle on a tool bar.
        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(CLOCK.tool)
        end)
        local sw, check = _G.TimeManagerStopwatchFrame, _G.TimeManagerStopwatchCheck
        if sw then
            -- The check is 17 in from this frame's right; its right lands
            -- CLOCK.pad in from ours, on the bar's middle.
            k:Move(sw, "RIGHT", bar, "RIGHT", 17 - CLOCK.pad, 0)
        end
        if check then
            k:Once(check, "clockCheck", function()
                for _, get in ipairs({ "GetHighlightTexture", "GetCheckedTexture" }) do
                    local ok, t = pcall(check[get], check)
                    if ok and t then S.StripArt(t) end
                end
                local okN, icon = pcall(check.GetNormalTexture, check)
                if not (okN and icon) then return end
                icon:ClearAllPoints()
                icon:SetAllPoints(check)
                EV.Icons:Style(icon, { host = check })
                local function Sync()
                    local okC, on = pcall(check.GetChecked, check)
                    local st = { on = okC and on or false, hover = check:IsMouseOver() or false }
                    if st.on or st.hover then
                        local e = T.Resolve(T.LOOK.slot, st).edge
                        EV.Icons:SetState(icon, e[1], e[2], e[3], e[4])
                    else
                        EV.Icons:SetState(icon, nil)
                    end
                end
                check:HookScript("OnEnter", Sync)
                check:HookScript("OnLeave", Sync)
                check:HookScript("OnClick", Sync)
                hooksecurefunc(check, "SetChecked", Sync)
                Sync()
            end)
        end

        local alarm = f.AlarmTimeFrame or _G.TimeManagerAlarmTimeFrame
        if alarm then k:Move(alarm, "TOPLEFT", f, "TOPLEFT", 12, -(top + CLOCK.tool + CLOCK.gap)) end
    end,
}

--------------------------------------------------------------------------------
--  AddonList (Blizzard_AddOnList). 600x550 ButtonFrameTemplate. The
--  character Dropdown at TOPLEFT 12,-30, "Load out of date" (ForceLoad) at
--  TOP -80,-27, SearchBox 160x22 at TOPRIGHT -10,-31; the Performance block
--  (header, CPU figures, an Options_HorizontalDivider) at TOP -65, 25 in from
--  each side, collapsing when hidden (collapsesLayout); the list under it,
--  7 in, BOTTOMRIGHT -34,28; Enable All / Disable All (120x22) at the bottom
--  left and Okay / Cancel (80x22) at the bottom right, on nothing. The rows'
--  highlight is UI-QuestTitleHighlight, so talkRow already dresses them.
--
--  Ours: a tool bar with the dropdown, the check and the search on it, 30
--  tall; no inner box; the Performance block and the list 12 in, the
--  divider a hairline; a footer with the four buttons, 24 tall; the list's
--  scroll bar centred in a 20px gutter.
--------------------------------------------------------------------------------
local ADDONS = { tool = 40, control = 30, pad = 12, gap = 6, footer = 36, button = 24,
                 all = 120, short = 96, gutter = 20, search = 200, drop = 180 }

P{
    name  = "AddonList",
    addon = "Blizzard_AddOnList",
    apply = function(f, k)
        local A = ADDONS
        local top = (S.TITLE_BAND or 24) + 2
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end
        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(A.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(A.footer)
        end)

        if f.Dropdown then
            k:Size(f.Dropdown, A.drop, A.control)
            k:Move(f.Dropdown, "LEFT", bar, "LEFT", A.pad - 1, 0)
        end
        if f.ForceLoad then k:Move(f.ForceLoad, "CENTER", bar, "CENTER", -80, 0) end
        if f.SearchBox then
            k:Size(f.SearchBox, A.search, A.control)
            k:Move(f.SearchBox, "RIGHT", bar, "RIGHT", -(A.pad - 1), 0)
        end

        local perf = f.Performance
        if perf then
            k:Anchors(perf, {
                { "TOPLEFT",  bar, "BOTTOMLEFT",  A.pad - 1, 0 },
                { "TOPRIGHT", bar, "BOTTOMRIGHT", -(A.pad - 1), 0 },
            })
            local div = perf.Divider
            if div then
                S.StripArt(div)
                k:Once(perf, "addonsRule", function()
                    local rule = S.Ours(perf:CreateTexture(nil, "ARTWORK"))
                    EV.Pixel.NoSnap(rule)
                    rule:SetPoint("LEFT", div, "LEFT"); rule:SetPoint("RIGHT", div, "RIGHT")
                    rule:SetPoint("BOTTOM", perf, "BOTTOM", 0, 5)
                    local function Paint()
                        rule:SetColorTexture(S.Colour("divider"))
                        rule:SetHeight(EV.Pixel:Line(perf))
                    end
                    Paint()
                    T.Watch(rule, Paint)
                end)
            end
        end

        local box, sbar = f.ScrollBox, f.ScrollBar
        if box then
            k:Anchors(box, {
                { "TOP",         perf or bar, "BOTTOM",     0, -(perf and 0 or A.gap) },
                { "LEFT",        f,           "LEFT",       A.pad - 1, 0 },
                { "BOTTOMRIGHT", foot,        "TOPRIGHT",   -A.gutter, A.gap },
            })
            if sbar then
                local w = S.Num(sbar:GetWidth()) or 8
                local x = math.floor((A.gutter - w) / 2 + 0.5)
                k:Anchors(sbar, {
                    { "TOPLEFT",    box, "TOPRIGHT",    x, 0 },
                    { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, 0 },
                })
            end
        end

        local en, dis, ok, cancel = f.EnableAllButton, f.DisableAllButton, f.OkayButton, f.CancelButton
        if en then k:Size(en, A.all, A.button); k:Move(en, "LEFT", foot, "LEFT", A.pad - 4, 0) end
        if dis then k:Size(dis, A.all, A.button); if en then k:Move(dis, "LEFT", en, "RIGHT", A.gap, 0) end end
        if cancel then k:Size(cancel, A.short, A.button); k:Move(cancel, "RIGHT", foot, "RIGHT", -(A.pad - 4), 0) end
        if ok then k:Size(ok, A.short, A.button); if cancel then k:Move(ok, "RIGHT", cancel, "LEFT", -A.gap, 0) end end
    end,
}

--------------------------------------------------------------------------------
--  MacroFrame (Blizzard_MacroUI). 338x424 ButtonFrameTemplate; its title a
--  loose font string (CREATE_MACROS) at TOP -5; General / Character tabs
--  (PanelTopTabButtonTemplate) at TOPLEFT 51,-28 beside the portrait; the
--  macro grid (MacroSelector, 319x146) at 12,-66; a trainer bar at -210;
--  the selected macro on a UI-EmptySlot at 5,-218 with Change Name/Icon
--  (170x22) and Save / Cancel (80x22) beside it; the commands in a
--  TooltipBackdrop box (322x95 at 6,-289), the character count at BOTTOM
--  -15,30; Delete / New / Exit (80x22) at the bottom, on nothing.
--
--  Ours: the window's own title; the tabs on a tool bar under it; the grid
--  6 under the bar; the slots (selectorButton) as our wells; the bar and
--  slot art gone; the commands in a sunk well, 6 clear of a footer, with the
--  character count on the label's line at the well's right; Delete left and
--  New / Exit right on the footer; every button 24 tall.
--------------------------------------------------------------------------------
local MACRO = { tool = 36, pad = 8, gap = 6, footer = 36, button = 24, short = 96,
                box = 295, rise = 4, label = 12 }

P{
    name  = "MacroFrame",
    addon = "Blizzard_MacroUI",
    apply = function(f, k)
        local M = MACRO
        local top = (S.TITLE_BAND or 24) + 2
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end
        -- The title: Blizzard's loose one goes, the window's own takes it.
        for _, r in ipairs(S.Regions(f)) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                local ok, t = pcall(r.GetText, r)
                if ok and t == _G.CREATE_MACROS then r:SetAlpha(0) end
            end
        end
        if f.SetTitle and _G.CREATE_MACROS then f:SetTitle(_G.CREATE_MACROS) end
        k:Art(f, "Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
        if _G.MacroFrameSelectedMacroBackground then S.StripArt(_G.MacroFrameSelectedMacroBackground) end

        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(M.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(M.footer)
        end)

        -- The tabs stand on the bar's rule; the second follows the first.
        local tab1 = _G.MacroFrameTab1
        if tab1 then k:Move(tab1, "BOTTOMLEFT", bar, "BOTTOMLEFT", M.pad, 0) end

        local grid = f.MacroSelector
        if grid then k:Move(grid, "TOPLEFT", f, "TOPLEFT", 12, -(top + M.tool + M.gap)) end

        -- The commands: a sunk well, ending M.gap above the footer.
        local box = _G.MacroFrameTextBackground
        if box then
            if box.NineSlice then k:Fade(box.NineSlice) end
            k:Fade(box)
            k:Fill(box, "surfaceSunk")
            k:Border(box, "border")
            k:Anchors(box, {
                { "TOPLEFT",     f,    "TOPLEFT",  6, -M.box },
                { "BOTTOMRIGHT", foot, "TOPRIGHT", -(338 - 328), M.gap },
            })
            -- The character count on the label's line, straight after the
            -- label: at the line's right end it sat under Cancel.
            -- The text scrolls inside the well, following it down.
            local scroll = _G.MacroFrameScrollFrame
            if scroll then
                k:Anchors(scroll, {
                    { "TOPLEFT",     box, "TOPLEFT",     10, -6 },
                    { "BOTTOMRIGHT", box, "BOTTOMRIGHT", -26, 6 },
                })
            end
            local count, label = _G.MacroFrameCharLimitText, _G.MacroFrameEnterMacroText
            -- The label sits on the well rather than on the stripped slot
            -- art, so the buttons above can be placed clear of it.
            if label then k:Move(label, "BOTTOMLEFT", box, "TOPLEFT", 2, M.rise) end
            if count and label then
                k:Move(count, "LEFT", label, "RIGHT", M.pad, 0)
                count:SetJustifyH("LEFT")
                -- Blizzard fixes its height at 10, shorter than our font,
                -- which truncates the end of the line. Let it size itself.
                count:SetHeight(0)
                count:SetWordWrap(false)
                k:Label(count, "textMuted")
            end
        end

        -- Save over Cancel on the right, M.gap apart (Blizzard: 15), and
        -- Change Name/Icon beside them on their middle line, the selected
        -- macro's slot to its left on the same line.
        local save, cancel, edit = _G.MacroSaveButton, _G.MacroCancelButton, _G.MacroEditButton
        if cancel then
            k:Size(cancel, M.short, M.button)
            -- Cancel's foot M.gap clear of the label line above the well.
            if box then k:Move(cancel, "BOTTOMRIGHT", box, "TOPRIGHT", 0, M.rise + M.label + M.gap) end
        end
        if save then
            k:Size(save, M.short, M.button)
            if cancel then k:Move(save, "BOTTOM", cancel, "TOP", 0, M.gap) end
        end
        if edit then
            k:Size(edit, 160, M.button)
            if save then k:Move(edit, "RIGHT", save, "BOTTOMLEFT", -M.pad, -M.gap / 2) end
            local slot = f.SelectedMacroButton or _G.MacroFrameSelectedMacroButton
            if slot then k:Move(slot, "RIGHT", edit, "LEFT", -M.pad, 0) end
        end
        IconPopup(k, _G.MacroPopupFrame)
        local del, new, exit = _G.MacroDeleteButton, _G.MacroNewButton, _G.MacroExitButton
        if del then k:Size(del, M.short, M.button); k:Move(del, "LEFT", foot, "LEFT", M.pad - 1, 0) end
        if exit then k:Size(exit, M.short, M.button); k:Move(exit, "RIGHT", foot, "RIGHT", -(M.pad - 1), 0) end
        if new then k:Size(new, M.short, M.button); if exit then k:Move(new, "RIGHT", exit, "LEFT", -M.gap, 0) end end
    end,
}

--------------------------------------------------------------------------------
--  CalendarFrame (Blizzard_Calendar, Mainline). A plain 659x624 frame whose
--  whole look is loose texture sheets on the frame itself: CalendarFrame_*
--  edges (a 46px top, 12 and 10 px sides, a 9px bottom), a CalendarBackground
--  banner per weekday, the month and year plates, the selected weekday's
--  glow. Six rows of seven 91px day buttons hang from the first weekday
--  banner (CalendarFrame_InitDay), each on a random tile of CalendarBackground
--  (its NormalTexture) with an ADD highlight Blizzard locks for the selected
--  day, a DarkFrame of CalendarShadows over other months' days, and
--  CalendarTodayFrame (an animated glow) re-parented onto today.
--  CalendarFrame_UpdateDay(index, day, monthOffset, isSelected, _, isToday,
--  ...) runs for every cell on every update.
--
--  Ours: the window surface and edge; the top as a band with the month and
--  its arrows centred and the filter and close on the right; the weekday
--  names on a band; each day a flat cell on a frame of ours under its
--  content, and a grid of hairlines on a layer above it (Ben: a border
--  round each square); other months dimmed, hover lighter, the selected
--  day the tile Look's on, today edged in copper on that upper layer. Holiday art and event
--  text stay: they are content. The grid is centred (Blizzard: 12 in on
--  the left, 10 on the right).
--------------------------------------------------------------------------------
local CAL = { top = 46, pad = 8, filter = 30 }
local calState = setmetatable({}, { __mode = "k" })   -- day button -> { other, selected, today, hover }

local function CalCell(b)
    local st = calState[b]
    local cell = st and st.cell
    if not cell then return end
    local r = T.Resolve(T.LOOK.tile, { on = st.selected, hover = st.hover, disabled = st.other })
    cell.fill:SetColorTexture(T.C4(r.fill))
    -- Today and the selected day: an edge inside the grid lines, on the
    -- layer above the day's art, so a holiday's picture can't cover it.
    if st.today then
        T.SetEdge(st.mark, { S.Colour("accent") })
    elseif st.selected then
        T.SetEdge(st.mark, r.edge)
    else
        T.SetEdge(st.mark, nil)
    end
end

--- The grid: each cell draws its right and bottom line, the first column its
--- left one too (the top is the weekday band's rule), on a mouse-transparent
--- layer above the day's content, so full-cell holiday art can't hide it.
local function CalGrid(b, st)
    local name = b:GetName() or ""
    local index = tonumber(name:match("(%d+)$")) or 0
    local over = S.Ours(CreateFrame("Frame", nil, b))
    over:EnableMouse(false)
    over:SetAllPoints(b)
    over:SetFrameLevel(b:GetFrameLevel() + 8)
    local lines = {}
    local function Line(a1, a2, vertical)
        local t = S.Ours(over:CreateTexture(nil, "OVERLAY", nil, 6))
        EV.Pixel.NoSnap(t)
        t:SetPoint(a1); t:SetPoint(a2)
        lines[#lines + 1] = { t, vertical }
    end
    Line("TOPRIGHT", "BOTTOMRIGHT", true)
    Line("BOTTOMLEFT", "BOTTOMRIGHT", false)
    if index % 7 == 1 then Line("TOPLEFT", "BOTTOMLEFT", true) end
    local function Paint()
        local px = EV.Pixel:Line(over)
        for _, l in ipairs(lines) do
            l[1]:SetColorTexture(S.Colour("border"))
            if l[2] then l[1]:SetWidth(px) else l[1]:SetHeight(px) end
        end
    end
    Paint()
    T.Watch(lines[1][1], Paint)
    -- The mark for today and the selected day, a pixel inside the lines.
    local mark = S.Ours(CreateFrame("Frame", nil, over))
    mark:EnableMouse(false)
    local one = EV.Pixel:One(b)
    mark:SetPoint("TOPLEFT", over, "TOPLEFT", index % 7 == 1 and one or 0, 0)
    mark:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -one, one)
    EV.Pixel:Edges(mark, { size = 1 })
    st.mark = mark
end

local function CalDay(b)
    if not S.Alive(b) or calState[b] then return end
    local st = {}
    calState[b] = st
    local okN, n = pcall(b.GetNormalTexture, b)
    if okN and n then S.StripArt(n) end
    local okH, h = pcall(b.GetHighlightTexture, b)
    if okH and h then S.StripArt(h) end
    local name = b:GetName()
    local dark = name and _G[name .. "DarkFrame"]
    if dark then
        for _, r in ipairs(S.Regions(dark)) do S.StripArt(r) end
    end
    local cell = S.Ours(CreateFrame("Frame", nil, b))
    cell:EnableMouse(false)
    cell:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    cell:SetAllPoints(b)
    cell.fill = S.Ours(EV.Pixel:Fill(cell, "BACKGROUND", -7))
    st.cell = cell
    CalGrid(b, st)
    b:HookScript("OnEnter", function() st.hover = true; CalCell(b) end)
    b:HookScript("OnLeave", function() st.hover = false; CalCell(b) end)
    T.Watch(cell.fill, function() CalCell(b) end)
    CalCell(b)
end

--------------------------------------------------------------------------------
--  The calendar's read-only side panels: CalendarViewHolidayFrame and
--  CalendarViewRaidFrame. Each is a DialogBorderDarkTemplate with a
--  DialogHeaderTemplate plate standing over its top edge, a ScrollingFont of
--  fixed size for the description and, on the holiday one, the holiday's
--  ornate INFO sheet at 40% behind the text. Blizzard hangs them from the
--  calendar's top right, 24 down, at a fixed 320 or 150 tall.
--
--  Ours: our window with its title band, the name on the band, the close
--  in its corner, the ornament gone, the text inset by the pad, and the
--  panel as tall as its text (up to Blizzard's height, past which the text
--  scrolls as before). It sits a gap clear of the calendar, level with its
--  top.
--------------------------------------------------------------------------------
local CALSIDE = { gap = 6, pad = 16, min = 60 }

local function CalSide(name, closeName)
    P{
        name  = name,
        addon = "Blizzard_Calendar",
        apply = function(f, k)
            local W = T.LOOK.window.rest
            if f.Border then k:Mute(f.Border) end
            if f.Texture then k:Mute(f.Texture) end
            k:Fill(f, W.fill)
            k:Border(f, W.edge)
            local cal = _G.CalendarFrame
            if cal then k:Move(f, "TOPLEFT", cal, "TOPRIGHT", CALSIDE.gap, 0) end

            -- The title band the calendar itself wears, so the two read as
            -- one window and its panel.
            local top = S.TITLE_BAND or 24
            local band = Band(f, "title", "bottom", function(b)
                b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
                b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
                b:SetHeight(top)
            end)
            -- Blizzard's plate is 39 tall against our 24, and the generic
            -- layer dresses it as a pane: its fill and edge hung below the
            -- band and read as a taller bar. Hide the plate outright and put
            -- the name on the band; Setup still sets its text there.
            local header = f.Header
            if header and band then
                k:Mute(header)
                local name = header.Text
                if name then
                    if name:GetParent() ~= band then name:SetParent(band) end
                    k:Move(name, "CENTER", band, "CENTER", 0, 0)
                    k:Label(name, W.title, true)
                end
            end
            local close = _G[closeName]
            if close then
                k:Size(close, top, top)
                k:Move(close, "TOPRIGHT", f, "TOPRIGHT", -1, -1)
            end

            local sf = f.ScrollingFont
            if not sf then return end
            top = top + 1
            k:Anchors(sf, {
                { "TOPLEFT",     f, "TOPLEFT",     CALSIDE.pad, -(top + CALSIDE.pad) },
                { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -CALSIDE.pad, CALSIDE.pad },
            })
            local fs = sf.GetFontString and sf:GetFontString()
            if fs then k:Label(fs, "text") end
            -- Blizzard's height is the most the panel grows to.
            local d = S.D(f)
            d.calMax = d.calMax or f:GetHeight()
            local function Fit()
                local str = sf.GetFontString and sf:GetFontString()
                local h = str and S.Num(str:GetStringHeight())
                if not h then return end
                h = math.max(CALSIDE.min, math.min(d.calMax, top + 2 * CALSIDE.pad + math.ceil(h)))
                if math.abs(f:GetHeight() - h) > 0.5 then k:Size(f, nil, h) end
            end
            Fit()
            k:After(sf, "SetText", function() Fit() end)
        end,
    }
end
CalSide("CalendarViewHolidayFrame", "CalendarViewHolidayCloseButton")
CalSide("CalendarViewRaidFrame", "CalendarViewRaidCloseButton")

P{
    name  = "CalendarFrame",
    addon = "Blizzard_Calendar",
    apply = function(f, k)
        -- The frame's own sheets: edges, banners, plates, the weekday glow.
        k:Fade(f)
        k:Fill(f, "surface0")
        k:Border(f, "border")
        local today = _G.CalendarTodayFrame
        if today then
            for _, r in ipairs(S.Regions(today)) do S.StripArt(r) end
        end

        -- The top: a band the height Blizzard gave it, the month centred.
        Band(f, "title", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
            b:SetHeight(CAL.top - 1)
        end)
        local close = _G.CalendarCloseButton
        if close then k:Move(close, "TOPRIGHT", f, "TOPRIGHT", -1, -1) end
        local filter = f.FilterButton
        if filter then
            k:Size(filter, nil, CAL.filter)
            k:Move(filter, "RIGHT", f, "TOPRIGHT", -((S.TITLE_BAND or 24) + CAL.pad), -CAL.top / 2)
        end

        -- The grid hangs from the left side piece: centre it.
        local side = _G.CalendarFrameLeftTopTexture
        if side then k:Move(side, "TOPLEFT", f, "TOPLEFT", -1, -CAL.top) end
        local w1, w7 = _G.CalendarWeekday1Background, _G.CalendarWeekday7Background
        if w1 and w7 then
            Band(f, "weekdays", "bottom", function(b)
                b:SetPoint("TOPLEFT", w1, "TOPLEFT")
                b:SetPoint("BOTTOMRIGHT", w7, "BOTTOMRIGHT", -1, 0)
            end)
        end

        for i = 1, 42 do CalDay(_G["CalendarDayButton" .. i]) end
        -- The side panels are the calendar's children, shown with a bare
        -- Show: adopt them so their own packs run on every opening.
        if S.Take then
            S.Take("CalendarViewHolidayFrame")
            S.Take("CalendarViewRaidFrame")
        end

        -- The grid runs to within a pixel or two of the bottom edge, while
        -- the sides get about ten. Grow the frame by the difference so the
        -- bottom margin matches the sides, measured rather than assumed.
        local function Fit()
            local d1, d42 = _G.CalendarDayButton1, _G.CalendarDayButton42
            if not (d1 and d42) then return end
            local l, fl = d1:GetLeft(), f:GetLeft()
            local b, fb = d42:GetBottom(), f:GetBottom()
            if not (l and fl and b and fb) then return end
            local want = (l - fl) - (b - fb)
            if math.abs(want) > 0.5 then k:Size(f, nil, f:GetHeight() + want) end
        end
        Fit()
        k:Hook(f, "OnShow", function() C_Timer.After(0, Fit) end, "calendarFit")

        k:Once(f, "calendarDays", function()
            if type(_G.CalendarFrame_UpdateDay) == "function" then
                hooksecurefunc("CalendarFrame_UpdateDay", function(index, _, monthOffset, isSelected, _, isToday)
                    local b = _G["CalendarDayButton" .. tostring(index)]
                    if not b then return end
                    CalDay(b)
                    local st = calState[b]
                    st.other = monthOffset ~= 0
                    st.selected = isSelected and true or false
                    st.today = isToday and true or false
                    CalCell(b)
                end)
            end
            if type(_G.CalendarFrame_SetSelectedDay) == "function" then
                hooksecurefunc("CalendarFrame_SetSelectedDay", function(dayButton)
                    for b, st in pairs(calState) do
                        st.selected = (b == dayButton)
                        CalCell(b)
                    end
                end)
            end
        end)
    end,
}

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
--  the walk and nothing claims the frame, so it also gets our window surface
--  and edge, our title bar with the name centred and the close in its
--  corner, and the map from under the title rule to the border.
--------------------------------------------------------------------------------
P{
    name  = "TaxiFrame",
    apply = function(f, k)
        -- The map. Content, never chrome.
        if f.InsetBg then f.InsetBg:SetAlpha(1) end

        local W = T.LOOK.window.rest
        k:Fill(f, W.fill)
        k:Border(f, W.edge)

        -- Our title bar, the name centred on it and the close flush in its
        -- corner, as every other window; the map from under its rule to our
        -- border (Blizzard: 4 in, 24 down, 6 from the right, 4 up).
        S.TitleBar(f, S.PainterFor(f))
        local band = S.D(f).titleBar
        local title = f.TitleText or (f.TitleContainer and f.TitleContainer.TitleText)
        if title and band then
            k:Anchors(title, { { "CENTER", band, "CENTER", 0, 0 } })
            k:Label(title, W.title, true)
        end
        local close = f.CloseButton
        if close then
            k:Size(close, S.TITLE_BAND or 24, S.TITLE_BAND or 24)
            k:Move(close, "TOPRIGHT", f, "TOPRIGHT", -1, -1)
        end
        if f.InsetBg then
            k:Anchors(f.InsetBg, {
                { "TOPLEFT",     f, "TOPLEFT",     1, -((S.TITLE_BAND or 24) + 2) },
                { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1 },
            })
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
--  BattlefieldMapFrame: the zone map (Blizzard_BattlefieldMap, Mainline, which
--  this client loads; Classic's extra CloseButtonBorder is covered too).
--
--  Blizzard's geometry, from Blizzard_BattlefieldMap.xml:
--
--    BattlefieldMapTab    64x32 on UIParent, strata LOW: ChatFrameTab
--                         Left/Middle/Right, a tab highlight, the label 5
--                         below centre. Alpha 0 until the cursor rests on the
--                         map (then 0.75); drag and right-click menu are its.
--    BattlefieldMapFrame  300x200, TOPLEFT on the tab's BOTTOMLEFT 0,-5.
--      ScrollContainer    the canvas: TOPLEFT 0,+2, BOTTOMRIGHT -2,+3, so it
--                         stands 2 above the frame and 2-3 in from its right
--                         and bottom. Its top is the tab's bottom -3.
--      BorderFrame        strata HIGH, setAllPoints, over the map: eight
--                         battlefieldminimap-border-* pieces hanging 7-13
--                         outside it, and the close button at TOPRIGHT 2,6.
--                         RefreshAlpha sets its alpha to 1 - opacity.
--
--  Ours: the eight pieces go and no edge replaces them; the map sits on our
--  sunk backdrop, cut to the CANVAS (not the frame, which it does not fill),
--  which follows the opacity setting as the border frame does. The close
--  button is flush inside the canvas's top right corner as on our windows,
--  and the tab a window tab standing on the map's top edge, label centred.
--
--  The opacity setting opens OpacityFrame (Blizzard_ColorPickerFrame), which
--  has its own pack below.
--
--  The frame is in neither UIPanelWindows nor UISpecialFrames (Toggle shows
--  it with a bare Show), so Discover.lua takes it by name.
--------------------------------------------------------------------------------
local ZONE = {
    tab   = 20,    -- the tab face's height, a chat tab's
    below = 3,     -- tab bottom to canvas top: the frame's -5 and the canvas's +2
}
local ZONE_ART = { "TopLeft", "TopRight", "BottomLeft", "BottomRight",
                   "Top", "Bottom", "Left", "Right", "CloseButtonBorder" }

local function ZoneTab(k)
    local tab = _G.BattlefieldMapTab
    if not S.Alive(tab) then return end
    k:Once(tab, "zoneTab", function()
        S.claimed[tab] = S.claimed[tab] or "pack"
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            if tab[key] then S.StripArt(tab[key]) end
        end
        local okH, hl = pcall(tab.GetHighlightTexture, tab)
        if okH and hl then S.StripArt(hl) end

        -- The face: the tab's width, ZONE.tab tall, its bottom on the
        -- canvas's top edge line (one pixel above the canvas), open there.
        local one = EV.Pixel:One(tab)
        local face = S.Ours(CreateFrame("Frame", nil, tab))
        face:EnableMouse(false)
        face:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        face:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, one - ZONE.below)
        face:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, one - ZONE.below)
        face:SetHeight(ZONE.tab)
        face.Paint = S.TabFace(face, "bottom")
        local fd = S.D(face)
        if fd.tabInset then fd.tabInset:Hide() end

        local text = tab.Text
        if text then
            text:ClearAllPoints()
            text:SetPoint("CENTER", face, "CENTER", 0, 0)
            k:Label(text, false, true)
        end
        -- Always the map's own tab, so always on; hover lifts it.
        local function Sync()
            local st = { on = true, hover = tab:IsMouseOver() or false }
            face.Paint(st.on, st.hover)
            if text then text:SetTextColor(T.C4(T.Resolve(T.LOOK.tab, st).text)) end
        end
        T.Watch(face, Sync)
        k:Hook(tab, "OnEnter", Sync)
        k:Hook(tab, "OnLeave", Sync)
        Sync()
    end)
end

P{
    name  = "BattlefieldMapFrame",
    addon = "Blizzard_BattlefieldMap",
    apply = function(f, k)
        local border, canvas = f.BorderFrame, f.ScrollContainer
        if not (border and canvas) then return end

        -- BorderFrame lies over the map and the frame is wider than the
        -- canvas: a generic fill on either would cover map or show a strip.
        k:NoFill(border)
        k:NoFill(f)
        for _, key in ipairs(ZONE_ART) do
            if border[key] then S.StripArt(border[key]) end
        end

        k:Once(f, "zoneMap", function()
            local back = S.Ours(f:CreateTexture(nil, "BACKGROUND", nil, -7))
            back:SetAllPoints(canvas)
            local function Paint() back:SetColorTexture(T.RGBA("surfaceSunk")) end
            Paint()
            T.Watch(back, Paint)
            -- The opacity option (right-click the tab) fades the map and the
            -- border frame; the backing follows the border frame.
            local function Alpha() back:SetAlpha(border:GetAlpha()) end
            Alpha()
            k:After(f, "RefreshAlpha", Alpha)
        end)

        local close = border.CloseButton
        if close then k:Move(close, "TOPRIGHT", canvas, "TOPRIGHT", 0, 0) end

        ZoneTab(k)
    end,
}

--------------------------------------------------------------------------------
--  OpacityFrame (Blizzard_ColorPickerFrame): the little opacity pop-up the
--  zone map, chat and colour picker open. 80x180, BackdropTemplate with
--  BACKDROP_DIALOG_32_32, the title "$parentText" at TOP -15, and
--  OpacityFrameSlider: a 16x128 vertical slider on BACKDROP_SLIDER_8_8 with a
--  white "+" above and "-" below in GameFontNormalHuge. Shown with a bare
--  Show, so Discover.lua takes it by name.
--
--  The backdrop is cleared (Blizzard sets it once, from backdropInfo, and
--  never again) and the frame drawn as our pop-ups are: the window surface,
--  its edge and shadow. The slider is the slider part's, by its thumb file.
--------------------------------------------------------------------------------
P{
    name  = "OpacityFrame",
    addon = "Blizzard_ColorPickerFrame",
    apply = function(f, k)
        k:Once(f, "opacityDialog", function()
            if f.ClearBackdrop then pcall(f.ClearBackdrop, f) else k:Fade(f) end
            S.PainterFor(f):Surface("window")
            S.Shadow(f)
        end)
        local title = _G.OpacityFrameText
        if title then k:Label(title, T.LOOK.window.rest.title, true) end
        local sl = _G.OpacityFrameSlider
        if sl then
            k:Dress(sl)
            for _, r in ipairs(S.Regions(sl)) do
                if r.GetObjectType and r:GetObjectType() == "FontString" then k:Label(r, "text") end
            end
        end
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
-- The side pane's lists: the equipment manager's own inset (ScrollBox TOPLEFT
-- 5,-8, BOTTOMRIGHT x=-20), given to the stats lists too.
local SIDE_LIST = { left = 5, top = 8, gutter = 20 }
local SIDEBAR_LABELS ={ [1] = "CHARACTER", [2] = "EQUIPMENT_MANAGER", [3] = "PET" }

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
        --
        -- Blizzard undoes both on every switch of pane, after this pack has
        -- run (Camelot PaperDollFrame.lua):
        --   PaperDollFrame_SetSidebar       StoneBg:SetAtlas(..., true), which
        --                                   puts the stone back to its atlas
        --                                   height and drops the pane under it
        --   PaperDollFrame_UpdateSidebarTabLayout
        --                                   clears all three tabs and centres
        --                                   them on PaperDollSidebarTabs
        -- so both are seated again straight after Blizzard's.
        if right and stone then
            local function SeatStone()
                stone:SetHeight((S.TITLE_BAND or 20) + 2 - 20 + SIDEBAR.band)
            end
            local function SeatTabs()
                local band = S.D(right).bands and S.D(right).bands.header
                if not band then return end
                local prev
                for i = 1, 3 do
                    local tab = _G["PaperDollSidebarTab" .. i]
                    if tab then
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
            k:Size(stone, nil, (S.TITLE_BAND or 20) + 2 - 20 + SIDEBAR.band)
            SeatTabs()
            k:After(stone, "SetAtlas", SeatStone)
            k:Once(right, "sidebarLayout", function()
                if type(_G.PaperDollFrame_UpdateSidebarTabLayout) == "function" then
                    hooksecurefunc("PaperDollFrame_UpdateSidebarTabLayout", SeatTabs)
                end
            end)
        end

        -- The side pane's lists, all on the equipment manager's geometry.
        -- Blizzard insets them differently: the sets list 5 in, 8 down and a
        -- 20px gutter (PaperDollFrame.xml), the stats and pet stats lists 10
        -- in, 8 down, a 30px gutter and 30 off the bottom
        -- (CharacterStatsPaneScrollBoxTemplate), with each scroll bar hung
        -- INSIDE its gutter's edge (-5 and +5) and 12 below the rows' top.
        -- One inset for all three, the scroll bar centred in the gutter, top
        -- and bottom with the rows; the stats lists end as far off the
        -- bottom as they start off the top. The sets list keeps its bottom,
        -- which makes room for its buttons.
        local function PaneList(pane, bottom)
            local box, bar = pane and pane.ScrollBox, pane and pane.ScrollBar
            if not (box and bar) then return end
            if bottom then
                k:Anchors(box, {
                    { "TOPLEFT",     pane, "TOPLEFT",     SIDE_LIST.left, -SIDE_LIST.top },
                    { "BOTTOMRIGHT", pane, "BOTTOMRIGHT", -SIDE_LIST.gutter, bottom },
                })
            end
            local w = S.Num(bar:GetWidth()) or 8
            local x = math.floor((SIDE_LIST.gutter - w) / 2 + 0.5)
            k:Anchors(bar, {
                { "TOPLEFT",    box, "TOPRIGHT",    x, 0 },
                { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, 0 },
            })
        end
        PaneList(_G.PaperDollFrame and PaperDollFrame.EquipmentManagerPane)
        PaneList(_G.CharacterStatsPaneScrollBox, SIDE_LIST.top)
        PaneList(_G.CharacterStatsPanePetScrollBox, SIDE_LIST.top)
        -- The equipment set icon picker: the same pop-up as the macros'.
        IconPopup(k, _G.GearManagerPopupFrame)

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

--------------------------------------------------------------------------------
--  AutoCompleteBox (Blizzard_AutoComplete): the name list under a whisper,
--  invite or mail recipient as you type. A TooltipBackdropTemplate box with
--  up to five 120x14 AutoCompleteButtonTemplate rows (text 15 in, the
--  UIPanelButtonHighlightTexture sheen, the chosen one held with
--  LockHighlight) from 10 down, and "Press Tab" 15 in and 10 up from the
--  bottom. AutoComplete_UpdateResults sizes it every keystroke: rows * row
--  height + 35 tall, the widest name + 30 wide.
--
--  Ours: the menu Look (the list a dropdown opens). Rows run edge to edge
--  from under the top border, 22 tall, the text 10 in; the chosen row is the
--  list item's on (a copper wash), hover its hover. "Press Tab" sits on a
--  footer band. The height is set again after Blizzard's, to the rows plus
--  that band. Shown with a bare Show, so Discover.lua takes it by name.
--------------------------------------------------------------------------------
local AC = { row = 22, text = 10, foot = 22, max = 5 }

local acState = setmetatable({}, { __mode = "k" })

local function ACPaint(b)
    local st = acState[b]
    if not st then return end
    local L = T.LOOK.listItem
    local fill
    if st.on then fill = L.on.fill
    elseif st.hover then fill = L.hover.fill end
    if fill then
        st.fill:SetColorTexture(S.Colour(fill))
        st.fill:Show()
    else
        st.fill:Hide()
    end
end

local function ACRow(k, b)
    if not S.Alive(b) then return end
    local h = b.GetHighlightTexture and b:GetHighlightTexture()
    if h then S.StripArt(h) end
    local fs = b.GetFontString and b:GetFontString()
    if fs then k:Move(fs, "LEFT", b, "LEFT", AC.text, 0) end
    k:Size(b, nil, AC.row)
    if acState[b] then return end
    local st = { on = false, hover = false }
    st.fill = S.Ours(b:CreateTexture(nil, "BACKGROUND", nil, -6))
    st.fill:SetAllPoints(b)
    acState[b] = st
    T.Watch(st.fill, function() ACPaint(b) end)
    hooksecurefunc(b, "LockHighlight", function() st.on = true; ACPaint(b) end)
    hooksecurefunc(b, "UnlockHighlight", function() st.on = false; ACPaint(b) end)
    b:HookScript("OnEnter", function() st.hover = true; ACPaint(b) end)
    b:HookScript("OnLeave", function() st.hover = false; ACPaint(b) end)
    ACPaint(b)
end

local function ACHeight(f)
    local n = 0
    for i = 1, AC.max do
        local b = _G["AutoCompleteButton" .. i]
        if b and b:IsShown() then n = n + 1 end
    end
    if n > 0 then f:SetHeight(n * AC.row + 2 + AC.foot) end
end

P{
    name  = "AutoCompleteBox",
    apply = function(f, k)
        local slice = f.NineSlice
        if slice then
            S.PainterFor(slice):FadeSlice(slice)
            k:NoFill(slice)
            EV.Pixel:ShowEdges(slice, false)
        end
        local M = T.LOOK.menu.rest
        k:Fill(f, M.fill)
        k:Border(f, M.edge)

        local prev
        for i = 1, AC.max do
            local b = _G["AutoCompleteButton" .. i]
            if b then
                ACRow(k, b)
                if prev then
                    k:Anchors(b, { { "TOPLEFT", prev, "BOTTOMLEFT" }, { "TOPRIGHT", prev, "BOTTOMRIGHT" } })
                else
                    k:Anchors(b, { { "TOPLEFT", f, "TOPLEFT", 1, -1 }, { "TOPRIGHT", f, "TOPRIGHT", -1, -1 } })
                end
                prev = b
            end
        end

        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(AC.foot - 1)
        end)
        local tip = _G.AutoCompleteInstructions
        if tip then
            k:Move(tip, "LEFT", foot, "LEFT", AC.text - 1, 0)
            -- Blizzard greys it with an inline colour code, which no text
            -- colour overrides; set it plain so the muted token shows.
            if _G.PRESS_TAB then tip:SetText(_G.PRESS_TAB) end
            k:Label(tip, "textMuted")
        end

        k:Once(f, "autoCompleteHeight", function()
            if type(_G.AutoComplete_UpdateResults) == "function" then
                hooksecurefunc("AutoComplete_UpdateResults", function(self) ACHeight(self) end)
            end
        end)
        ACHeight(f)
    end,
}

--------------------------------------------------------------------------------
--  AuctionHouseFrame (Blizzard_AuctionHouseUI, Shared + Mainline family, which
--  Camelot loads). An 800x538 PortraitFrameTemplate with three display modes
--  (AuctionHouseFrameDisplayMode), each a set of sub-frames SetDisplayMode
--  shows:
--
--    Buy       SearchBar (618x40 at TOPRIGHT -12,-29: favourites, search box,
--              filter, Search), CategoriesList (168 wide under it, an
--              InsetFrameTemplate nine-slice, parchment Background, a
--              ScrollBox of AuctionCategoryButtonTemplate rows) and
--              BrowseResultsFrame (an item list to the right). Picking a
--              result swaps the results for ItemBuyFrame or
--              CommoditiesBuyFrame (a Back button, an item card, the offers
--              list, bid and buyout at the bottom).
--    Sell      ItemSellFrame / CommoditiesSellFrame (363 wide, a
--              VerticalLayoutFrame of aligned controls on a parchment, a
--              "Create Auction" tab of three atlases over its top edge) with
--              ItemSellList / CommoditiesSellList beside it.
--    Auctions  AuctionsFrame: Auctions / Bids top tabs, a summary list on the
--              left, the auctions or bids table, Cancel Auction (or bid and
--              buyout) hanging 22 below the frame.
--
--  Every table is an AuctionHouseItemListTemplate: a background texture and
--  nine-slice, a 19px HeaderContainer, a ScrollBox under it and a
--  MinimalScrollBar beside the right edge, and a RefreshFrame (the count and a
--  refresh button) pushed up by per-list offsets to sit on the row above.
--  The money is a ThinGoldEdge box on an inset under the bottom-left corner.
--  The mode tabs hang below the window, as Blizzard's bottom tabs do.
--
--  Ours: a 40px tool bar under the title in every mode (the search in Buy,
--  the "Create Auction" heading in Sell, the Auctions / Bids tabs in
--  Auctions; the refresh on its right where the mode has one) and a footer
--  band (money left, the mode's action buttons right). Between them nothing
--  is boxed: the lists sit straight on the window, split by hairlines. Tables
--  have a header band, rows (ahLine), and the scroll bar centred in a gutter
--  of their own. Item cards are tile cards.
--------------------------------------------------------------------------------
local AH = { tool = 40, control = 30, pad = 8, gap = 6, footer = 36, button = 24,
             side = 168, sell = 363, gutter = 20, head = 23, headH = 19,
             short = 96, long = 120, wide = 140, back = 96, card = 72 }

-- An AuctionHouseBackgroundTemplate (or any inset nine-slice) left as a plain
-- rect: no picture, box, fill or edge.
local function AHFlat(k, frame)
    if not S.Alive(frame) then return end
    if frame.Background then S.StripArt(frame.Background) end
    local ns = frame.NineSlice
    if ns then
        S.PainterFor(ns):FadeSlice(ns)
        k:NoFill(ns)
        EV.Pixel:ShowEdges(ns, false)
    end
    k:NoFill(frame)
    EV.Pixel:ShowEdges(frame, false)
end

-- A hairline of ours down one side of a frame, to split two panes.
local function AHSeam(host, side)
    local d = S.D(host)
    local key = "ahSeam" .. side
    if d[key] then return d[key] end
    local t = S.Ours(host:CreateTexture(nil, "BORDER", nil, 2))
    EV.Pixel.NoSnap(t)
    local x = side == "RIGHT" and 0 or 0
    t:SetPoint("TOP" .. side, host, "TOP" .. side, x, 0)
    t:SetPoint("BOTTOM" .. side, host, "BOTTOM" .. side, x, 0)
    local function Paint()
        t:SetColorTexture(S.Colour("divider"))
        t:SetWidth(EV.Pixel:Line(host))
    end
    Paint()
    T.Watch(t, Paint)
    d[key] = t
    return t
end

-- The refresh control: the button a tool bar control, its gold icon in our
-- text colour, the count beside it muted.
local function AHRefresh(k, rf, point, rel, relPoint, x, y)
    if not S.Alive(rf) then return end
    k:Move(rf, point, rel, relPoint, x, y)
    local b = rf.RefreshButton
    if b then
        k:Size(b, AH.control, AH.control)
        local icon = b.Icon
        if icon and icon.SetDesaturated then
            icon:SetDesaturated(true)
            icon:SetVertexColor(T.RGBA("text"))
        end
    end
    if rf.TotalQuantity then k:Label(rf.TotalQuantity, "textMuted") end
end

-- An item list: a header band across the top, the rows under it to the
-- gutter, the scroll bar centred in the gutter.
local function AHList(k, list)
    if not S.Alive(list) then return end
    AHFlat(k, list)
    local head = Band(list, "head", "bottom", function(b)
        b:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        b:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
        b:SetHeight(AH.head)
    end)
    local hc = list.HeaderContainer
    if hc then
        k:Anchors(hc, {
            { "TOPLEFT",  head, "TOPLEFT",  AH.pad - 4, -math.floor((AH.head - AH.headH) / 2) },
            { "TOPRIGHT", head, "TOPRIGHT", -AH.gutter, -math.floor((AH.head - AH.headH) / 2) },
        })
    end
    local box, bar = list.ScrollBox, list.ScrollBar
    if box then
        k:Anchors(box, {
            { "TOPLEFT",     head, "BOTTOMLEFT", 0, -1 },
            { "BOTTOMRIGHT", list, "BOTTOMRIGHT", -AH.gutter, 0 },
        })
        if bar then
            local w = S.Num(bar:GetWidth()) or 8
            local x = math.floor((AH.gutter - w) / 2 + 0.5)
            k:Anchors(bar, {
                { "TOPLEFT",    box, "TOPRIGHT",    x, -AH.gap },
                { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, AH.gap },
            })
        end
    end
    if list.ResultsText then k:Label(list.ResultsText, "textMuted") end
    -- A list builds its header buttons when its layout is first set, which
    -- for the sell and auctions tables is after the window's walk: dress
    -- them each time Blizzard lays the columns out.
    k:After(list, "UpdateTableBuilderLayout", function(self)
        local h = self.HeaderContainer
        if h then S.Walk(h, 0) end
    end)
    if hc then S.Walk(hc, 0) end
end

-- A side list (categories, the auctions summary): rows from the top edge to
-- the gutter, the scroll bar centred in it, a hairline down the right.
local function AHSideList(k, list)
    if not S.Alive(list) then return end
    AHFlat(k, list)
    AHSeam(list, "RIGHT")
    local box, bar = list.ScrollBox, list.ScrollBar
    -- A little room above the first row and in from the left, the same as
    -- the gap between two category headers (their boxes stand 2 in from
    -- their rows). No spacing between rows, so the tree rails run unbroken.
    local view = box and box.GetView and box:GetView()
    if view and view.SetPadding and not S.D(list).ahPad then
        S.D(list).ahPad = true
        view:SetPadding(AH.gap - 4, AH.gap - 4, AH.gap - 2, 0, 0)
        -- The list may already hold its rows; lay them out again.
        if box.FullUpdate then pcall(box.FullUpdate, box, true) end
    end
    if box then
        k:Anchors(box, {
            { "TOPLEFT",     list, "TOPLEFT",     0, 0 },
            { "BOTTOMRIGHT", list, "BOTTOMRIGHT", -AH.gutter, 0 },
        })
        if bar then
            local w = S.Num(bar:GetWidth()) or 8
            local x = math.floor((AH.gutter - w) / 2 + 0.5)
            k:Anchors(bar, {
                { "TOPLEFT",    box, "TOPRIGHT",    x, -AH.gap },
                { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, AH.gap },
            })
        end
    end
end

-- An item card: the tile Look, the header frame art and the empty slot art
-- gone (the item button's well shows instead).
local function AHCard(k, disp)
    if not S.Alive(disp) then return end
    AHFlat(k, disp)
    ClearAtlas(disp, "auctionhouse%-itemheaderframe")
    local tile = T.LOOK.tile.rest
    k:Fill(disp, tile.fill)
    k:Border(disp, tile.edge)
    local ib = disp.ItemButton
    if ib and ib.EmptyBackground then S.StripArt(ib.EmptyBackground) end
end

-- The mode tabs (PanelTabButtonTemplate) hang
-- under the window: window tab faces open on their top, the chosen one the
-- window's own surface running up into it, a copper bar along its foot.
-- PanelTemplates keeps the choice on the window (selectedTab indexes Tabs).
local AH_TAB = { h = 28, gap = 2 }

local function AHTabState(f, tab)
    local d = S.D(tab)
    if not (d.textBox and d.textBox.Paint) then return end
    local on = false
    if f.selectedTab then
        if type(f.Tabs) == "table" and f.Tabs[f.selectedTab] == tab then on = true
        elseif tab.GetID and tab:GetID() ~= 0 and tab:GetID() == f.selectedTab then on = true end
    end
    local hover = tab.IsMouseOver and tab:IsMouseOver() or false
    d.textBox.Paint(on, hover)
    local text = tab.Text
    if text then
        text:SetTextColor(T.C4(T.Resolve(T.LOOK.tab, { on = on, hover = hover }).text))
        text:ClearAllPoints()
        text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
end

local function AHTab(k, f, tab)
    if not S.Alive(tab) then return end
    local d = S.D(tab)
    k:Fade(tab)
    if d.fill then d.fill:SetAlpha(0) end
    d.edgeless = true
    EV.Pixel:ShowEdges(tab, false)
    k:Size(tab, nil, AH_TAB.h)
    if not d.textBox then
        local box = S.Ours(CreateFrame("Frame", nil, tab))
        local one = EV.Pixel:One(tab)
        box:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, one)
        box:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box:EnableMouse(false)
        box.Paint = S.TabFace(box, "top")
        local bd = S.D(box)
        if bd.tabInset then bd.tabInset:Hide() end
        d.textBox = box
        T.Watch(box, function() AHTabState(f, tab) end)
        k:Hook(tab, "OnEnter", function() AHTabState(f, tab) end)
        k:Hook(tab, "OnLeave", function() AHTabState(f, tab) end)
    end
    AHTabState(f, tab)
end

-- A button sized to our footer kinds.
local function AHButton(k, b, w)
    if b then k:Size(b, w, AH.button) end
end

P{
    name  = "AuctionHouseFrame",
    addon = "Blizzard_AuctionHouseUI",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        local under = -(top + AH.tool)

        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(AH.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(AH.footer)
        end)

        -- The money: on the footer, left, out of its gold box and inset.
        if f.MoneyFrameInset then k:Mute(f.MoneyFrameInset) end
        local mb = f.MoneyFrameBorder
        if mb then
            k:Fade(mb)
            k:NoFill(mb)
            EV.Pixel:ShowEdges(mb, false)
            local money = mb.MoneyFrame
            if money then
                if money.SetResizeToFit and not S.D(money).fit then
                    S.D(money).fit = true
                    money:SetResizeToFit(true)
                    if money.UpdateWidth then pcall(money.UpdateWidth, money) end
                end
                k:Move(money, "LEFT", foot, "LEFT", AH.pad, 0)
            end
        end

        -- The mode tabs, flush under the window's bottom edge.
        local tabs = type(f.Tabs) == "table" and f.Tabs or {}
        local prev
        for _, tab in ipairs(tabs) do
            AHTab(k, f, tab)
            if prev then
                k:Move(tab, "TOPLEFT", prev, "TOPRIGHT", AH_TAB.gap, 0)
            else
                k:Move(tab, "TOPLEFT", f, "BOTTOMLEFT", AH.pad, 0)
            end
            prev = tab
        end
        k:Once(f, "ahTabs", function()
            local function All()
                for _, tab in ipairs(type(f.Tabs) == "table" and f.Tabs or {}) do AHTabState(f, tab) end
            end
            if type(_G.PanelTemplates_SetTab) == "function" then
                hooksecurefunc("PanelTemplates_SetTab", function(frame) if frame == f then All() end end)
            end
            for _, fn in ipairs({ "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab" }) do
                if type(_G[fn]) == "function" then
                    hooksecurefunc(fn, function(tab)
                        if tab and tab.GetParent and tab:GetParent() == f then AHTabState(f, tab) end
                    end)
                end
            end
        end)

        ------------------------------------------------------------ Buy
        local sb = f.SearchBar
        if sb then
            k:Anchors(sb, {
                { "TOPLEFT",     bar, "TOPLEFT",     AH.pad, 0 },
                { "BOTTOMRIGHT", bar, "BOTTOMRIGHT", -AH.pad, 0 },
            })
            local fav, box, filter, go = sb.FavoritesSearchButton, sb.SearchBox, sb.FilterButton, sb.SearchButton
            if fav then
                k:Size(fav, AH.control, AH.control)
                k:Move(fav, "LEFT", sb, "LEFT", 0, 0)
            end
            if go then
                k:Size(go, AH.long, AH.control)
                k:Move(go, "RIGHT", sb, "RIGHT", 0, 0)
            end
            if filter then
                k:Size(filter, nil, AH.control)
                if go then k:Move(filter, "RIGHT", go, "LEFT", -AH.gap, 0) end
            end
            if box and fav and filter then
                k:Anchors(box, {
                    { "LEFT",  fav,    "RIGHT", AH.gap + 4, 0 },
                    { "RIGHT", filter, "LEFT",  -AH.gap, 0 },
                })
                k:Size(box, nil, AH.control)
            end
        end

        local cats = f.CategoriesList
        if cats then
            k:Anchors(cats, {
                { "TOPLEFT",    f,    "TOPLEFT",    1, under },
                { "BOTTOMLEFT", foot, "TOPLEFT",    0, 0 },
            })
            k:Size(cats, AH.side, nil)
            AHSideList(k, cats)
        end

        local results = f.BrowseResultsFrame
        if results and cats then
            k:Anchors(results, {
                { "TOPLEFT",     cats, "TOPRIGHT", 0, 0 },
                { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
            })
            local list = results.ItemList
            if list then
                k:Anchors(list, { { "TOPLEFT", results, "TOPLEFT" }, { "BOTTOMRIGHT", results, "BOTTOMRIGHT" } })
                AHList(k, list)
            end
        end

        -- A picked item or commodity: Back and the refresh on the pane's
        -- first line, the card, the offers.
        for _, key in ipairs({ "ItemBuyFrame", "CommoditiesBuyFrame" }) do
            local pane = f[key]
            if pane and cats then
                k:Anchors(pane, {
                    { "TOPLEFT",     cats, "TOPRIGHT", 0, 0 },
                    { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
                })
                local back = pane.BackButton
                if back then
                    k:Size(back, AH.back, AH.button)
                    k:Move(back, "TOPLEFT", pane, "TOPLEFT", AH.pad, -AH.gap)
                end
            end
        end
        local ib = f.ItemBuyFrame
        if ib then
            local back = ib.BackButton
            local disp = ib.ItemDisplay
            if disp and back then
                AHCard(k, disp)
                k:Anchors(disp, {
                    { "TOPLEFT",  back, "BOTTOMLEFT", 0, -AH.gap },
                    { "TOPRIGHT", ib,   "TOPRIGHT",   -AH.pad, 0 },
                })
                k:Size(disp, nil, AH.card)
            end
            -- Bid and buyout on the footer, right.
            local buyout, bid = ib.BuyoutFrame, ib.BidFrame
            if buyout then
                k:Move(buyout, "RIGHT", foot, "RIGHT", -AH.pad, 0)
                AHButton(k, buyout.BuyoutButton, AH.long)
            end
            if bid and buyout then
                k:Move(bid, "RIGHT", buyout, "LEFT", -AH.pad * 2, 0)
                AHButton(k, bid.BidButton, AH.long)
            end
            local list = ib.ItemList
            if list and disp then
                k:Anchors(list, {
                    { "TOPLEFT",     disp, "BOTTOMLEFT", -AH.pad, -AH.gap },
                    { "BOTTOMRIGHT", ib,   "BOTTOMRIGHT", 0, 0 },
                })
                AHList(k, list)
                if back then AHRefresh(k, list.RefreshFrame, "RIGHT", ib, "TOPRIGHT", -AH.pad, -(AH.gap + AH.button / 2)) end
            end
        end
        local cb = f.CommoditiesBuyFrame
        if cb then
            local back, show, list = cb.BackButton, cb.BuyDisplay, cb.ItemList
            if show and back then
                AHFlat(k, show)
                AHSeam(show, "RIGHT")
                k:Anchors(show, {
                    { "TOPLEFT",    back, "BOTTOMLEFT", -AH.pad, -AH.gap },
                    { "BOTTOMLEFT", cb,   "BOTTOMLEFT", 0, 0 },
                })
                AHCard(k, show.ItemDisplay)
                AHButton(k, show.BuyButton, nil)
            end
            if list and show then
                k:Anchors(list, {
                    { "TOPLEFT",     show, "TOPRIGHT",   0, 0 },
                    { "BOTTOMRIGHT", cb,   "BOTTOMRIGHT", 0, 0 },
                })
                AHList(k, list)
                AHRefresh(k, list.RefreshFrame, "RIGHT", cb, "TOPRIGHT", -AH.pad, -(AH.gap + AH.button / 2))
            end
        end

        ------------------------------------------------------------ Sell
        -- The form on the left, its list on the right, one hairline between.
        local isf, isl = f.ItemSellFrame, f.ItemSellList
        if isf then
            k:Anchors(isf, {
                { "TOPLEFT",    f,    "TOPLEFT", 1, under },
                { "BOTTOMLEFT", foot, "TOPLEFT", 0, 0 },
            })
            k:Size(isf, AH.sell, nil)
        end
        if isl and isf then
            k:Anchors(isl, {
                { "TOPLEFT",     isf,  "TOPRIGHT", 0, 0 },
                { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
            })
        end
        for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
            local sf = f[key]
            if sf then
                AHFlat(k, sf)
                AHSeam(sf, "RIGHT")
                for _, t in ipairs({ "CreateAuctionTabLeft", "CreateAuctionTabMiddle", "CreateAuctionTabRight" }) do
                    if sf[t] then S.StripArt(sf[t]) end
                end
                -- "Create Auction" is the mode's heading, on the tool bar.
                if sf.CreateAuctionLabel then
                    k:Move(sf.CreateAuctionLabel, "LEFT", bar, "LEFT", AH.pad + 4, 0)
                    k:Label(sf.CreateAuctionLabel, "text", true)
                end
                AHCard(k, sf.ItemDisplay)
                AHButton(k, sf.PostButton, nil)
                local q = sf.QuantityInput
                if q and q.MaxButton then AHButton(k, q.MaxButton, nil) end
            end
        end
        for _, key in ipairs({ "ItemSellList", "CommoditiesSellList" }) do
            local list = f[key]
            if list then
                AHList(k, list)
                AHRefresh(k, list.RefreshFrame, "RIGHT", bar, "RIGHT", -AH.pad, 0)
            end
        end

        ------------------------------------------------------------ Auctions
        local af = f.AuctionsFrame
        if af then
            k:Anchors(af, {
                { "TOPLEFT",     f,    "TOPLEFT",  1, under },
                { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
            })
            -- Auctions / Bids stand on the tool bar's rule.
            local t1 = af.AuctionsTab
            if t1 then k:Move(t1, "BOTTOMLEFT", bar, "BOTTOMLEFT", AH.pad, 0) end
            if af.BidsTab and t1 then k:Move(af.BidsTab, "LEFT", t1, "RIGHT", 2, 0) end

            local cancel = af.CancelAuctionButton
            if cancel then
                k:Size(cancel, AH.wide, AH.button)
                k:Move(cancel, "RIGHT", foot, "RIGHT", -AH.pad, 0)
            end
            local buyout, bid = af.BuyoutFrame, af.BidFrame
            if buyout and cancel then
                k:Move(buyout, "RIGHT", cancel, "RIGHT", 0, 0)
                AHButton(k, buyout.BuyoutButton, AH.long)
            end
            if bid and buyout then
                k:Move(bid, "RIGHT", buyout, "LEFT", -AH.pad * 2, 0)
                AHButton(k, bid.BidButton, AH.long)
            end

            local sum = af.SummaryList
            if sum then
                k:Anchors(sum, {
                    { "TOPLEFT",    af, "TOPLEFT",    0, 0 },
                    { "BOTTOMLEFT", af, "BOTTOMLEFT", 0, 0 },
                })
                k:Size(sum, AH.side, nil)
                AHSideList(k, sum)
            end
            local all = af.AllAuctionsList
            if all and sum then
                k:Anchors(all, {
                    { "TOPLEFT",     sum, "TOPRIGHT",    0, 0 },
                    { "BOTTOMRIGHT", af,  "BOTTOMRIGHT", 0, 0 },
                })
            end
            local disp = af.ItemDisplay
            if disp and sum then
                AHCard(k, disp)
                k:Anchors(disp, {
                    { "TOPLEFT",  sum, "TOPRIGHT", AH.pad, -AH.gap },
                    { "TOPRIGHT", af,  "TOPRIGHT", -AH.pad, -AH.gap },
                })
                k:Size(disp, nil, AH.card)
            end
            local il = af.ItemList
            if il and disp and sum then
                k:Anchors(il, {
                    { "TOPLEFT",     disp, "BOTTOMLEFT", -AH.pad, -AH.gap },
                    { "BOTTOMRIGHT", af,   "BOTTOMRIGHT", 0, 0 },
                })
            end
            for _, key in ipairs({ "AllAuctionsList", "BidsList", "ItemList", "CommoditiesList" }) do
                local list = af[key]
                if list then
                    AHList(k, list)
                    AHRefresh(k, list.RefreshFrame, "RIGHT", bar, "RIGHT", -AH.pad, 0)
                end
            end
        end

        ------------------------------------------------------------ Dialogs
        local dlg = f.BuyDialog
        if dlg then
            if dlg.Border then k:Mute(dlg.Border) end
            k:Fill(dlg, T.LOOK.window.rest.fill)
            k:Border(dlg, T.LOOK.window.rest.edge)
        end
    end,
}

--------------------------------------------------------------------------------
--  ChatConfigFrame (Blizzard_ChatFrame, Mainline ChatConfigFrame.xml / .lua,
--  which Camelot loads). A 745x605 dialog: DialogBorderTemplate and a
--  DialogHeaderTemplate title; the chat windows as ChatWindowTab buttons
--  (pooled by ChatTabManager, re-acquired on every show, the choice shown by
--  FCFTab_UpdateColors) over ChatConfigCategoryFrame, a TooltipBackdrop box
--  12 in holding ConfigCategoryButtonTemplate rows (16 tall, a blue-tinted
--  UI-Listbox-Highlight2 locked on the open one by ChatConfigCategory_OnClick);
--  ChatConfigBackgroundFrame, another box, to its right, the open panel on it.
--  Each panel's lists are built on show by ChatConfig_CreateCheckboxes /
--  _CreateTieredCheckboxes / _CreateColorSwatches into a box with a header
--  (ChatConfigBoxWithHeaderTemplate): one TooltipBorderBackdrop row per entry,
--  a 24px UI-CheckBox check and label, a colour swatch, and on the channel
--  rows a UI-GroupLoot-Pass leave button. Defaults / Reset Positions (or the
--  combat log's or text to speech's defaults) and Okay sit on the bottom
--  edge, 11 in and 12 up.
--
--  Ours: a tool bar under the title with the chat window tabs standing on its
--  rule as window tab faces; a footer with the defaults left and Okay right;
--  the category list flat as list items, a hairline between it and the
--  panel; each list a sunk well, its rows unboxed with a hairline under each;
--  the leave button our close glyph. Lists built after the walk are dressed
--  as Blizzard builds them.
--------------------------------------------------------------------------------
-- list: the widest list's box (Blizzard's 550 rows plus the 8 it pads a
-- box by), which sets the window's width; head: room above a box for its
-- heading; inset: a box's own padding round its rows (4).
local CFG = { tool = 40, footer = 36, button = 24, pad = 8, gap = 6, side = 136,
              row = 22, tab = 28, short = 96, text = 10, list = 558, head = 26, inset = 4,
              filters = 85 }

local cfgBoxes = setmetatable({}, { __mode = "k" })

local function CfgTabState(tab)
    local d = S.D(tab)
    if not (d.textBox and d.textBox.Paint) then return end
    local on = d.cfgOn and true or false
    local hover = tab.IsMouseOver and tab:IsMouseOver() or false
    d.textBox.Paint(on, hover)
    local text = tab.Text
    if text then
        text:SetTextColor(T.C4(T.Resolve(T.LOOK.tab, { on = on, hover = hover }).text))
        text:ClearAllPoints()
        text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end
end

local function CfgTab(k, tab)
    if not S.Alive(tab) then return end
    local d = S.D(tab)
    k:Fade(tab)
    if d.fill then d.fill:SetAlpha(0) end
    d.edgeless = true
    EV.Pixel:ShowEdges(tab, false)
    k:Size(tab, nil, CFG.tab)
    if not d.textBox then
        local box = S.Ours(CreateFrame("Frame", nil, tab))
        box:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, -EV.Pixel:One(tab))
        box:SetFrameLevel(math.max(0, tab:GetFrameLevel() - 1))
        box:EnableMouse(false)
        box.Paint = S.TabFace(box, "bottom")
        local bd = S.D(box)
        if bd.tabInset then bd.tabInset:Hide() end
        d.textBox = box
        T.Watch(box, function() CfgTabState(tab) end)
        tab:HookScript("OnEnter", function() CfgTabState(tab) end)
        tab:HookScript("OnLeave", function() CfgTabState(tab) end)
    end
    CfgTabState(tab)
end

-- A category row: a list item, copper while its panel is open (Blizzard's
-- LockHighlight), its blue highlight art gone.
local function CfgCategory(b, keepHeight)
    if not S.Alive(b) then return end
    local d = S.D(b)
    local hi = b.Highlight or (b.GetHighlightTexture and b:GetHighlightTexture())
    if hi then S.StripArt(hi) end
    if not keepHeight then b:SetHeight(CFG.row) end
    local text = b.NormalText
    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", b, "LEFT", CFG.text, 0)
    end
    local p = S.PainterFor(b)
    p:Fill("surface2")
    if not d.cfgHooked then
        d.cfgHooked = true
        local function Sync() if d.Repaint then d.Repaint() end end
        hooksecurefunc(b, "LockHighlight", function() d.cfgOn = true; Sync() end)
        hooksecurefunc(b, "UnlockHighlight", function() d.cfgOn = false; Sync() end)
    end
    p:States(T.LOOK.listItem, { on = function() return d.cfgOn end })
end

-- A backdrop box (TooltipBackdropTemplate and its border-only sibling) left
-- as a plain rect: its nine-slice faded, no fill, no edge.
local function CfgFlat(k, box)
    if not S.Alive(box) then return end
    local ns = box.NineSlice
    if ns then
        S.PainterFor(ns):FadeSlice(ns)
        k:NoFill(ns)
        EV.Pixel:ShowEdges(ns, false)
    end
    k:NoFill(box)
    EV.Pixel:ShowEdges(box, false)
end

-- A list Blizzard has just built: the box plain, each row unboxed with
-- a hairline under it, the leave buttons our close glyph, and the whole
-- thing walked so its check boxes and swatches are dressed.
local function CfgList(k, box)
    if not S.Alive(box) then return end
    CfgFlat(k, box)
    cfgBoxes[box] = true
    local title = box.header or _G[(box:GetName() or "") .. "Title"]
    if title then
        k:Label(title, "title", true)
        -- Over the rows' first column, not the box's padded edge: the
        -- check box's left side (a row 4 in, its check 5 in, the drawn box
        -- 4 inside that), or a swatch row's label (7 in).
        local x = box.checkBoxTable and (CFG.inset + 5 + 4) or (CFG.inset + 7)
        k:Move(title, "BOTTOMLEFT", box, "TOPLEFT", x, 2)
    end
    for _, row in ipairs(S.Children(box)) do
        if row.CheckButton or row.ColorSwatch or (row.GetName and row:GetName() and row:GetName():find("Swatch%d+$")) then
            CfgFlat(k, row)
            local d = S.D(row)
            if not d.cfgRule then
                d.cfgRule = S.Ours(row:CreateTexture(nil, "BORDER", nil, 1))
                EV.Pixel.NoSnap(d.cfgRule)
                d.cfgRule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 0)
                d.cfgRule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 0)
                local function Paint()
                    d.cfgRule:SetColorTexture(S.Colour("divider"))
                    d.cfgRule:SetHeight(EV.Pixel:Line(row))
                end
                Paint()
                T.Watch(d.cfgRule, Paint)
            end
            local leave = rawget(row, "CloseChannel")
            if leave and not S.D(leave).cfgLeave then
                S.D(leave).cfgLeave = true
                S.claimed[leave] = S.claimed[leave] or "pack"
                local lp = S.PainterFor(leave)
                lp:Fade()
                S.Blank(leave)
                lp:Fill("surface2")
                lp:Glyph("close", 8, "textMuted")
                lp:States(T.LOOK.close)
                k:Size(leave, 16, 16)
            end
        end
    end
    S.Walk(box, 0)
end

--------------------------------------------------------------------------------
--  The combat log's five pages, laid out on one grid. Blizzard places each
--  with its own offsets (x 10, 11, 13, 15, 25, 27 from four different
--  frames, one page hung from the bottom); ours all hang from the panel's
--  top-left under the tab rule: the first control 30 down, headings 2 above
--  what they head, a check box's drawn square 17 in (its button 13), the
--  second column half the page across, sub-options 20 in under their
--  parent, columns of sub-options 110 apart, labels 4 clear of their box.
--------------------------------------------------------------------------------
local CC = { x = 13, top = 30, col = 285, sub = 20, subCol = 110, label = 4, block = 28, gap = 26 }

-- A check button's label, 4 clear of it and on its centre line (Blizzard
-- sets 0 or -2 across and 2 up).
local function CfgCheckLabel(cb)
    if not (cb and cb.GetName) then return end
    local fs = cb.Text or _G[(cb:GetName() or "") .. "Text"]
    if fs and fs.SetPoint then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", cb, "RIGHT", CC.label, 0)
    end
end

-- A heading in the title colour, 2 above what it heads, over its glyph.
local function CfgHeading(k, fs, over, x)
    if not fs then return end
    k:Label(fs, "title", true)
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOMLEFT", over, "TOPLEFT", x or 0, 2)
end

-- A bordered row box of Blizzard's (ChatConfigBorderBoxTemplate) as one of
-- our rows: unboxed, a hairline under it.
local function CfgRowBox(k, row)
    if not S.Alive(row) then return end
    CfgFlat(k, row)
    local d = S.D(row)
    if d.cfgRule then return end
    d.cfgRule = S.Ours(row:CreateTexture(nil, "BORDER", nil, 1))
    EV.Pixel.NoSnap(d.cfgRule)
    d.cfgRule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 0)
    d.cfgRule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 0)
    local function Paint()
        d.cfgRule:SetColorTexture(S.Colour("divider"))
        d.cfgRule:SetHeight(EV.Pixel:Line(row))
    end
    Paint()
    T.Watch(d.cfgRule, Paint)
end

-- Message Types' tiered lists: a check per type with its sub-types in two
-- columns under it. The containers are positioned by the caller.
local function CfgTiered(frame, columns)
    if not (frame and frame.checkBoxTable) then return end
    local base = frame:GetName() .. "Checkbox"
    for i = 1, #frame.checkBoxTable do
        local cb = _G[base .. i]
        if cb then
            CfgCheckLabel(cb)
            local fs = cb.Text or _G[base .. i .. "Text"]
            if fs and not columns then
                local path, size = fs:GetFont()
                if path then fs:SetFont(T.FontBoldPath and T.FontBoldPath() or path, size, "") end
            end
            -- The misc list's columns: every other box beside its pair.
            if columns and i % columns == 0 then
                cb:ClearAllPoints()
                cb:SetPoint("TOPLEFT", _G[base .. (i - 1)], "TOPLEFT", CC.subCol, 0)
            end
            local k2 = 1
            while _G[base .. i .. "_" .. k2] do
                local sub = _G[base .. i .. "_" .. k2]
                CfgCheckLabel(sub)
                sub:ClearAllPoints()
                if k2 == 1 then
                    sub:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", CC.sub, 0)
                elseif k2 % 2 == 0 then
                    sub:SetPoint("TOPLEFT", _G[base .. i .. "_" .. (k2 - 1)], "TOPLEFT", CC.subCol, 0)
                else
                    sub:SetPoint("TOPLEFT", _G[base .. i .. "_" .. (k2 - 2)], "BOTTOMLEFT", 0, 0)
                end
                k2 = k2 + 1
            end
        end
    end
end

-- The example lines at the top of Colors and Formatting, as a block under
-- its heading.
local function CfgExample(k, page, prefix)
    local s1, s2, title = _G[prefix .. "ExampleString1"], _G[prefix .. "ExampleString2"], _G[prefix .. "ExampleTitle"]
    if not s1 then return end
    s1:ClearAllPoints()
    s1:SetPoint("TOPLEFT", page, "TOPLEFT", CC.x + 4, -CC.top)
    if title then CfgHeading(k, title, s1, 0) end
    return s2 or s1
end

local function CfgCombatPages(k, cbg)
    if not cbg then return end
    -- Every page from the panel's top-left.
    for _, name in ipairs({ "CombatConfigMessageSources", "CombatConfigMessageTypes", "CombatConfigColors",
                            "CombatConfigFormatting", "CombatConfigSettings" }) do
        local page = _G[name]
        if page then k:Move(page, "TOPLEFT", cbg, "TOPLEFT", 0, 0) end
    end

    -- Message Sources: two lists side by side.
    local src = _G.CombatConfigMessageSources
    local by, to = _G.CombatConfigMessageSourcesDoneBy, _G.CombatConfigMessageSourcesDoneTo
    if src and by then k:Move(by, "TOPLEFT", src, "TOPLEFT", CC.x - 5 - CFG.inset, -CC.top) end
    if src and to then k:Move(to, "TOPLEFT", src, "TOPLEFT", CC.x - 5 - CFG.inset + CC.col, -CC.top) end
    for _, box in ipairs({ by, to }) do
        if box and box.checkBoxTable then
            for i = 1, #box.checkBoxTable do
                local row = _G[box:GetName() .. "Checkbox" .. i]
                if row and row.CheckButton then CfgCheckLabel(row.CheckButton) end
            end
        end
    end

    -- Message Types: two columns of tiered lists, the misc list under the
    -- right one.
    local types = _G.CombatConfigMessageTypes
    local left, right, misc = _G.CombatConfigMessageTypesLeft, _G.CombatConfigMessageTypesRight, _G.CombatConfigMessageTypesMisc
    if types and left then k:Move(left, "TOPLEFT", types, "TOPLEFT", CC.x - 4, -(CC.top - 4)) end
    if types and right then k:Move(right, "TOPLEFT", types, "TOPLEFT", CC.x - 4 + CC.col, -(CC.top - 4)) end
    if misc and right then
        -- Under the right list's last row, not under Blizzard's estimate of
        -- its height (which counts 24 a row and 0.6 of one per sub-type).
        local base = right:GetName() .. "Checkbox"
        local n = right.checkBoxTable and #right.checkBoxTable or 0
        local lastMain = _G[base .. n]
        local below, dx = lastMain, -4
        if lastMain then
            local m = 0
            while _G[base .. n .. "_" .. (m + 1)] do m = m + 1 end
            if m > 0 then
                below = _G[base .. n .. "_" .. (m % 2 == 1 and m or m - 1)]
                dx = -(4 + CC.sub)
            end
        end
        if below then
            k:Move(misc, "TOPLEFT", below, "BOTTOMLEFT", dx, -CC.gap)
        else
            k:Move(misc, "TOPLEFT", right, "BOTTOMLEFT", 0, -CC.gap)
        end
        for _, r in ipairs(S.Regions(misc)) do
            if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == _G.MISCELLANEOUS then
                -- Over the small boxes' drawn squares (a 20 button, 16 box).
                CfgHeading(k, r, misc, 4 + 2)
            end
        end
    end
    CfgTiered(left)
    CfgTiered(right)
    CfgTiered(misc, 2)

    -- Colors: the example, then unit colours and highlighting on the left,
    -- the colourise options on the right.
    local colors = _G.CombatConfigColors
    if colors then
        CfgExample(k, colors, "CombatConfigColors")
        local unit = _G.CombatConfigColorsUnitColors
        local listTop = CC.top + CC.block + CC.gap + 12
        if unit then k:Move(unit, "TOPLEFT", colors, "TOPLEFT", CC.x - 5 - CFG.inset + 2, -listTop) end
        local hl = _G.CombatConfigColorsHighlighting
        if hl and unit then
            CfgFlat(k, hl)
            -- Its checks sit 6 in and draw their square 4 inside that: one
            -- pixel further in than the colour list, to land on 17.
            k:Move(hl, "TOPLEFT", unit, "BOTTOMLEFT", 1, -CC.gap)
            local line, ability = _G.CombatConfigColorsHighlightingLine, _G.CombatConfigColorsHighlightingAbility
            local dmg, school = _G.CombatConfigColorsHighlightingDamage, _G.CombatConfigColorsHighlightingSchool
            for _, cb in ipairs({ line, ability, dmg, school }) do CfgCheckLabel(cb) end
            if ability and line then ability:ClearAllPoints(); ability:SetPoint("TOPLEFT", line, "TOPLEFT", CC.subCol, 0) end
            if school and dmg then school:ClearAllPoints(); school:SetPoint("TOPLEFT", dmg, "TOPLEFT", CC.subCol, 0) end
            if dmg and line then dmg:ClearAllPoints(); dmg:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0) end
            CfgHeading(k, _G.CombatConfigColorsHighlightingTitle, hl, 6 + 4)
        end
        local cz = _G.CombatConfigColorsColorize
        if cz then
            k:Move(cz, "TOPLEFT", colors, "TOPLEFT", CC.x - 7 + CC.col, -listTop)
            for _, key in ipairs({ "UnitName", "SpellNames", "DamageNumber", "DamageSchool", "EntireLine" }) do
                local row = _G["CombatConfigColorsColorize" .. key]
                if row then
                    CfgRowBox(k, row)
                    CfgCheckLabel(_G["CombatConfigColorsColorize" .. key .. "Check"])
                    CfgCheckLabel(_G["CombatConfigColorsColorize" .. key .. "SchoolColoring"])
                end
            end
            local first = _G.CombatConfigColorsColorizeUnitName
            if first then
                for _, r in ipairs(S.Regions(first)) do
                    if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == _G.COLORIZE then
                        CfgHeading(k, r, first, 7 + 4)
                    end
                end
            end
        end
    end

    -- Formatting: the example, then the options as one indented list.
    local fmt = _G.CombatConfigFormatting
    if fmt then
        local last = CfgExample(k, fmt, "CombatConfigFormatting")
        local ts = _G.CombatConfigFormattingShowTimeStamp
        if ts and last then
            ts:ClearAllPoints()
            ts:SetPoint("TOPLEFT", last, "BOTTOMLEFT", -4, -CC.gap)
        end
        for _, key in ipairs({ "ShowTimeStamp", "ShowBraces", "UnitNames", "SpellNames", "ItemNames", "FullText" }) do
            CfgCheckLabel(_G["CombatConfigFormatting" .. key])
        end
        local braces, unit = _G.CombatConfigFormattingShowBraces, _G.CombatConfigFormattingUnitNames
        if braces and ts then braces:ClearAllPoints(); braces:SetPoint("TOPLEFT", ts, "BOTTOMLEFT", 0, -CFG.gap) end
        if unit and braces then unit:ClearAllPoints(); unit:SetPoint("TOPLEFT", braces, "BOTTOMLEFT", CC.sub, 0) end
        local spell, item = _G.CombatConfigFormattingSpellNames, _G.CombatConfigFormattingItemNames
        if spell and unit then spell:ClearAllPoints(); spell:SetPoint("TOPLEFT", unit, "BOTTOMLEFT", 0, 0) end
        if item and spell then item:ClearAllPoints(); item:SetPoint("TOPLEFT", spell, "BOTTOMLEFT", 0, 0) end
        local full = _G.CombatConfigFormattingFullText
        if full and item then full:ClearAllPoints(); full:SetPoint("TOPLEFT", item, "BOTTOMLEFT", -CC.sub, -CFG.gap) end
    end

    -- Settings: the filter's name and Save on one line, the quick button
    -- and where it shows under it.
    local set = _G.CombatConfigSettings
    if set then
        local name, save = _G.CombatConfigSettingsNameEditBox, _G.CombatConfigSettingsSaveButton
        if name then
            k:Size(name, 200, CFG.button)
            k:Move(name, "TOPLEFT", set, "TOPLEFT", CC.x + 4, -CC.top)
            for _, r in ipairs(S.Regions(name)) do
                if r.GetObjectType and r:GetObjectType() == "FontString" and r:GetText() == _G.FILTER_NAME then
                    CfgHeading(k, r, name, 0)
                end
            end
        end
        if save and name then
            k:Size(save, CFG.short, CFG.button)
            k:Move(save, "LEFT", name, "RIGHT", CFG.gap, 0)
        end
        local quick = _G.CombatConfigSettingsShowQuickButton
        if quick and name then
            CfgCheckLabel(quick)
            quick:ClearAllPoints()
            quick:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -4, -CC.gap + 6)
        end
        local solo, party, raid = _G.CombatConfigSettingsSolo, _G.CombatConfigSettingsParty, _G.CombatConfigSettingsRaid
        for _, cb in ipairs({ solo, party, raid }) do CfgCheckLabel(cb) end
        if solo and quick then solo:ClearAllPoints(); solo:SetPoint("TOPLEFT", quick, "BOTTOMLEFT", CC.sub, 0) end
        if party and solo then party:ClearAllPoints(); party:SetPoint("TOPLEFT", solo, "TOPLEFT", CC.subCol, 0) end
        if raid and party then raid:ClearAllPoints(); raid:SetPoint("TOPLEFT", party, "TOPLEFT", CC.subCol, 0) end
    end
end

P{
    name  = "ChatConfigFrame",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        local under = -(top + CFG.tool)

        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(CFG.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(CFG.footer)
        end)

        -- The chat windows' tabs on the tool bar's rule.
        local mgr = f.ChatTabManager
        if mgr then
            k:Move(mgr, "BOTTOMLEFT", bar, "BOTTOMLEFT", CFG.pad, -1)
            local function Tabs()
                if not (mgr.tabPool and mgr.tabPool.EnumerateActive) then return end
                -- The pool hands its tabs back in no particular order; lay
                -- them out by chat window number, as Blizzard's chain does.
                local list = {}
                for tab in mgr.tabPool:EnumerateActive() do list[#list + 1] = tab end
                table.sort(list, function(a, b) return (a:GetID() or 0) < (b:GetID() or 0) end)
                local prev
                for _, tab in ipairs(list) do
                    CfgTab(k, tab)
                    tab:ClearAllPoints()
                    if prev then
                        tab:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                    else
                        tab:SetPoint("BOTTOMLEFT", mgr, "TOPLEFT", 0, 0)
                    end
                    prev = tab
                end
            end
            Tabs()
            k:After(mgr, "UpdateTabDisplay", Tabs)
            k:Once(f, "cfgTabColours", function()
                if type(_G.FCFTab_UpdateColors) == "function" then
                    hooksecurefunc("FCFTab_UpdateColors", function(tab, selected)
                        if tab and tab.GetParent and tab:GetParent() == mgr then
                            S.D(tab).cfgOn = selected and true or false
                            CfgTabState(tab)
                        end
                    end)
                end
            end)
        end

        -- The categories, flat down the left.
        local cats = _G.ChatConfigCategoryFrame
        if cats then
            CfgFlat(k, cats)
            AHSeam(cats, "RIGHT")
            k:Anchors(cats, {
                { "TOPLEFT",     f,    "TOPLEFT", 1, under },
                { "BOTTOMRIGHT", foot, "TOPLEFT", CFG.side, 0 },
            })
            for i = 1, 7 do
                local b = _G["ChatConfigCategoryFrameButton" .. i]
                if b then CfgCategory(b) end
            end
            for _, i in ipairs({ 1, 5 }) do
                local b = _G["ChatConfigCategoryFrameButton" .. i]
                if b then
                    k:Anchors(b, {
                        { "TOPLEFT",  cats, "TOPLEFT",  CFG.gap - 2, -CFG.gap },
                        { "TOPRIGHT", cats, "TOPRIGHT", -CFG.gap, -CFG.gap },
                    })
                end
            end
        end

        -- The panel's ground, and the combat log's, to the right of it.
        for _, name in ipairs({ "ChatConfigBackgroundFrame", "ChatConfigCombatSettings" }) do
            local bg = _G[name]
            if bg and cats then
                CfgFlat(k, bg)
                k:Anchors(bg, {
                    { "TOPLEFT",     cats, "TOPRIGHT", 0, 0 },
                    { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
                })
            end
        end

        -- The footer: defaults left, Okay right.
        local def, redock = f.DefaultButton, f.RedockButton
        for _, b in ipairs({ def, redock, _G.CombatLogDefaultButton, _G.TextToSpeechDefaultButton,
                             _G.ChatConfigFrameOkayButton, _G.ChatConfigFrameCancelButton }) do
            if b then k:Size(b, nil, CFG.button) end
        end
        if def then k:Move(def, "LEFT", foot, "LEFT", CFG.pad, 0) end
        if redock and def then k:Move(redock, "LEFT", def, "RIGHT", CFG.gap, 0) end
        for _, b in ipairs({ _G.CombatLogDefaultButton, _G.TextToSpeechDefaultButton }) do
            if b then k:Move(b, "LEFT", foot, "LEFT", CFG.pad, 0) end
        end
        local okay, cancel = _G.ChatConfigFrameOkayButton, _G.ChatConfigFrameCancelButton
        if okay then
            k:Size(okay, CFG.short, CFG.button)
            k:Move(okay, "RIGHT", foot, "RIGHT", -CFG.pad, 0)
        end
        if cancel and okay then
            k:Size(cancel, CFG.short, CFG.button)
            k:Move(cancel, "RIGHT", okay, "LEFT", -CFG.gap, 0)
        end

        ------------------------------------------------------------ Combat log
        -- Its page is the filter list (85 tall), a row under it of the
        -- move arrows and Copy / Add / Delete, then five tabs standing on
        -- the panel, which Blizzard pushes 135 down on show. Ours: the list
        -- flat with list-item rows, the row's buttons ours at 24, the tabs
        -- window tab faces on a hairline across the page.
        local cs = _G.ChatConfigCombatSettings
        local filters = cs and cs.Filters
        local cbg = _G.ChatConfigBackgroundFrame
        local tabTop = CFG.gap + CFG.filters + CFG.gap + CFG.button + CFG.gap + CFG.tab
        if filters then
            CfgFlat(k, filters)
            k:Anchors(filters, {
                { "TOPLEFT",     cs, "TOPLEFT",  CFG.pad - CFG.inset, -CFG.gap },
                { "BOTTOMRIGHT", cs, "TOPRIGHT", -CFG.pad, -(CFG.gap + CFG.filters) },
            })
            local del = _G.ChatConfigCombatSettingsFiltersDeleteButton
            local add = _G.ChatConfigCombatSettingsFiltersAddFilterButton
            local copy = _G.ChatConfigCombatSettingsFiltersCopyFilterButton
            if del then
                k:Size(del, CFG.short, CFG.button)
                k:Move(del, "TOPRIGHT", filters, "BOTTOMRIGHT", 0, -CFG.gap)
            end
            if add and del then
                k:Size(add, CFG.short, CFG.button)
                k:Move(add, "RIGHT", del, "LEFT", -CFG.gap, 0)
            end
            if copy and add then
                k:Size(copy, CFG.short, CFG.button)
                k:Move(copy, "RIGHT", add, "LEFT", -CFG.gap, 0)
            end
            local up, down = _G.ChatConfigMoveFilterUpButton, _G.ChatConfigMoveFilterDownButton
            for _, pair in ipairs({ { up, "up" }, { down, "down" } }) do
                local b = pair[1]
                if b then
                    OverlayButton(k, b, pair[2])
                    k:Size(b, CFG.button, CFG.button)
                    b:SetHitRectInsets(0, 0, 0, 0)
                end
            end
            if up then k:Move(up, "TOPLEFT", filters, "BOTTOMLEFT", CFG.inset, -CFG.gap) end
            if down and up then k:Move(down, "LEFT", up, "RIGHT", CFG.gap, 0) end
        end
        if cs then
            -- The page's rule the tabs stand on.
            local d = S.D(cs)
            if not d.cfgRule then
                d.cfgRule = S.Ours(cs:CreateTexture(nil, "BORDER", nil, 1))
                EV.Pixel.NoSnap(d.cfgRule)
                d.cfgRule:SetPoint("TOPLEFT", cs, "TOPLEFT", 0, -tabTop)
                d.cfgRule:SetPoint("TOPRIGHT", cs, "TOPRIGHT", 0, -tabTop)
                local function Paint()
                    d.cfgRule:SetColorTexture(S.Colour("divider"))
                    d.cfgRule:SetHeight(EV.Pixel:Line(cs))
                end
                Paint()
                T.Watch(d.cfgRule, Paint)
            end
        end
        -- The chosen tab is the one whose page is showing; Blizzard says so
        -- only through the pages' visibility and the labels' colour.
        local function CombatTabs()
            local prev
            for i, info in ipairs(_G.COMBAT_CONFIG_TABS or {}) do
                local tab = _G["CombatConfigTab" .. i]
                if tab then
                    CfgTab(k, tab)
                    tab:SetAlpha(1)
                    local page = info.frame and _G[info.frame]
                    S.D(tab).cfgOn = page and page:IsShown() and true or false
                    CfgTabState(tab)
                    tab:ClearAllPoints()
                    if prev then
                        tab:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", 2, 0)
                    elseif cs then
                        tab:SetPoint("BOTTOMLEFT", cs, "TOPLEFT", CFG.pad, -tabTop)
                    end
                    prev = tab
                end
            end
        end
        CombatTabs()
        -- Blizzard moves the panel down for the combat page on every show
        -- and back on hide; ours is the same, from our own top.
        local function Ground(combat)
            if cbg and cats then
                k:Anchors(cbg, {
                    { "TOPLEFT",     cats, "TOPRIGHT", 0, combat and -tabTop or 0 },
                    { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
                })
            end
        end
        Ground(cs and cs:IsShown())
        k:Once(f, "cfgCombat", function()
            -- The XML binds OnShow / OnHide to the functions themselves at
            -- load, so a hook on the globals never runs: follow the frame.
            if cs then
                cs:HookScript("OnShow", function()
                    Ground(true); CombatTabs()
                    C_Timer.After(0, function() if S.D(f).cfgFit then S.D(f).cfgFit() end end)
                end)
                cs:HookScript("OnHide", function() Ground(false) end)
            end
            if type(_G.ChatConfig_UpdateCombatTabs) == "function" then
                hooksecurefunc("ChatConfig_UpdateCombatTabs", function()
                    CombatTabs()
                    C_Timer.After(0, function() if S.D(f).cfgFit then S.D(f).cfgFit() end end)
                end)
            end
            if type(_G.ChatConfigCombat_InitButton) == "function" then
                hooksecurefunc("ChatConfigCombat_InitButton", function(b) CfgCategory(b, true) end)
            end
        end)

        CfgCombatPages(k, cbg)

        -- As wide as the widest list with a pad each side of it.
        k:Size(f, 1 + CFG.side + CFG.pad - CFG.inset + CFG.list + CFG.pad + 1, nil)

        -- The first box of each page a pad in from the categories' hairline
        -- (its rows start at the box's inset), its heading above it.
        for _, name in ipairs({ "ChatConfigChatSettingsLeft", "ChatConfigChannelSettingsLeft",
                                "ChatConfigOtherSettingsCombat", "ChatConfigTextToSpeechChannelSettingsLeft",
                                "CombatConfigMessageSourcesDoneBy" }) do
            local box = _G[name]
            if box then k:Move(box, "TOPLEFT", box:GetParent(), "TOPLEFT", CFG.pad - CFG.inset, -CFG.head) end
        end

        -- Tall enough for the longest list we have seen: never cut a list
        -- off at the footer. Grows only, so the window doesn't jump about
        -- between pages.
        -- The combat pages' controls hang off each other rather than
        -- filling their containers, so on those pages measure the controls.
        local function Lowest(frame, depth, low)
            if depth > 4 or not frame:IsVisible() then return low end
            local b = S.Num(frame:GetBottom())
            if b and frame:GetObjectType() == "CheckButton" and (not low or b < low) then low = b end
            for _, c in ipairs(S.Children(frame)) do low = Lowest(c, depth + 1, low) end
            return low
        end
        local function Fit()
            local low
            for box in pairs(cfgBoxes) do
                if box:IsVisible() then
                    local b = S.Num(box:GetBottom())
                    if b and (not low or b < low) then low = b end
                end
            end
            for _, name in ipairs({ "CombatConfigMessageSources", "CombatConfigMessageTypes", "CombatConfigColors",
                                    "CombatConfigFormatting", "CombatConfigSettings" }) do
                local page = _G[name]
                if page and page:IsVisible() then low = Lowest(page, 0, low) end
            end
            local ft = S.Num(foot:GetTop())
            if not (low and ft) then return end
            local need = (ft + CFG.pad) - low
            if need > 0.5 then k:Size(f, nil, f:GetHeight() + need) end
        end
        S.D(f).cfgFit = Fit

        -- Lists, as Blizzard builds them.
        k:Once(f, "cfgLists", function()
            for _, fn in ipairs({ "ChatConfig_CreateCheckboxes", "ChatConfig_CreateTieredCheckboxes",
                                  "ChatConfig_CreateColorSwatches" }) do
                if type(_G[fn]) == "function" then
                    hooksecurefunc(fn, function(box)
                        CfgList(k, box)
                        C_Timer.After(0, function() if S.D(f).cfgFit then S.D(f).cfgFit() end end)
                    end)
                end
            end
            if type(_G.ChatConfigCategory_OnClick) == "function" then
                hooksecurefunc("ChatConfigCategory_OnClick", function()
                    C_Timer.After(0, function() if S.D(f).cfgFit then S.D(f).cfgFit() end end)
                end)
            end
        end)
        C_Timer.After(0, Fit)
        for _, name in ipairs({ "ChatConfigChatSettingsLeft", "ChatConfigChannelSettingsLeft",
                                "ChatConfigOtherSettingsCombat", "ChatConfigOtherSettingsPVP",
                                "ChatConfigOtherSettingsAdditionalColors", "ChatConfigOtherSettingsSystem",
                                "ChatConfigOtherSettingsCreature", "ChatConfigTextToSpeechChannelSettingsLeft",
                                "CombatConfigMessageSourcesDoneBy", "CombatConfigMessageSourcesDoneTo",
                                "CombatConfigColorsUnitColors" }) do
            local box = _G[name]
            if box and box.checkBoxTable or (box and box.swatchTable) then CfgList(k, box) end
        end
    end,
}

--------------------------------------------------------------------------------
--  FriendsFrame (Blizzard_FriendsFrame, Camelot FriendsFrame.xml / .lua), the
--  Contacts window. A 385x424 ButtonFrameTemplate: under the title
--  FriendsTabHeader holds the status dropdown, the Battle.net tag
--  (BattlenetFrame, 190x29, 26 under the title) with ContactsMenuButton (a
--  32px square with a gold arrow) beside it, and a TabSystem (Friends,
--  Recent Allies) at 18,-60. The lists sit in the Inset: FriendsListFrame's
--  ScrollBox from 8,-87, RecentAlliesFrame.List 3 inside the Inset. Add
--  Friend and Send Message are 134x21 on the bottom corners; the Contacts /
--  Raid tabs hang below. The ignore list is a second ButtonFrameTemplate
--  window beside it.
--
--  Ours: a tool bar under the title (status left, tag centred, the menu
--  button right, all 30); the Friends / Recent Allies tabs standing on a rule
--  under it; the lists straight on the window from that rule to a footer,
--  scroll bar centred in a gutter; Add Friend and Send Message on the
--  footer. Rows, dividers, status dots and invite buttons are the contacts
--  parts'.
--------------------------------------------------------------------------------
local FR = { tool = 40, control = 30, pad = 8, gap = 6, tabs = 24, footer = 36, button = 24,
             wide = 140, gutter = 20 }

--------------------------------------------------------------------------------
--  The Raid tab (Blizzard_RaidFrame Mainline RaidFrame.xml, and
--  Blizzard_RaidUI, loaded on demand in a raid): RaidFrame is re-parented
--  into the contacts window (ClaimRaidFrame) and fills it. Its controls:
--  the All Assist check at 58,-23, the role counts centred 25 down, Raid
--  Info at the top right, Convert to Raid 5 up from the bottom right. In a
--  raid, eight RaidGroup frames (162x80, a UI-RaidFrame-GroupOutline
--  picture, a "Group N" label above) each hold five slots and the members
--  as secure RaidGroupButtons (UI-RaidFrame-GroupButton art); sixteen
--  RaidClassButtons count classes down the right on SpellBook-SkillLineTab
--  plates. RaidInfoFrame, the saved instances, opens beside the window.
--
--  Ours, written from the source (the tab can't be seen outside a raid):
--  the controls on the window's tool bar and footer, each group a sunk well
--  with its label as a heading, members as rows (surface, lighter on hover),
--  empty slots clear with their text muted, the class plates gone and the
--  class icons in our icon style; the saved instances panel as our window.
--  Nothing here moves a secure button.
--------------------------------------------------------------------------------
local raidDressed = setmetatable({}, { __mode = "k" })

local function FrRaidInfo(k)
    local rf = _G.RaidInfoFrame
    if not rf or raidDressed[rf] then return end
    raidDressed[rf] = true
    local W = T.LOOK.window.rest
    if rf.Border then k:Mute(rf.Border) end
    k:Fill(rf, W.fill)
    k:Border(rf, W.edge)
    for _, n in ipairs({ "RaidInfoDetailHeader", "RaidInfoDetailFooter" }) do
        if _G[n] then S.StripArt(_G[n]) end
    end
    k:Art(rf, "Interface\\FriendsFrame\\WhoFrame-ColumnTabs")
    local band = Band(rf, "title", "bottom", function(b)
        b:SetPoint("TOPLEFT", rf, "TOPLEFT", 1, -1)
        b:SetPoint("TOPRIGHT", rf, "TOPRIGHT", -1, -1)
        b:SetHeight(S.TITLE_BAND or 24)
    end)
    local header = rf.Header
    if header then
        k:Mute(header)
        local name = header.Text
        if name then
            if name:GetParent() ~= band then name:SetParent(band) end
            k:Move(name, "CENTER", band, "CENTER", 0, 0)
            k:Label(name, W.title, true)
        end
    end
    local close = _G.RaidInfoCloseButton
    if close then
        k:Size(close, S.TITLE_BAND or 24, S.TITLE_BAND or 24)
        k:Move(close, "TOPRIGHT", rf, "TOPRIGHT", -1, -1)
    end
    for _, n in ipairs({ "RaidInfoInstanceLabel", "RaidInfoIDLabel" }) do
        local l = _G[n]
        if l and l.text then k:Label(l.text, "textMuted") end
    end
    for _, n in ipairs({ "RaidInfoExtendButton", "RaidInfoCancelButton" }) do
        if _G[n] then k:Size(_G[n], nil, FR.button) end
    end
    local owner = rf:GetParent()
    if owner then k:Move(rf, "TOPLEFT", owner, "TOPRIGHT", FR.gap, 0) end
end

local function FrRaid(k, f, bar, foot)
    local raid = _G.RaidFrame
    if not raid then return end
    -- Controls onto the window's bars while the window holds the raid page.
    if raid:GetParent() == f then
        local assist = _G.RaidFrameAllAssistCheckButton
        if assist then k:Move(assist, "LEFT", bar, "LEFT", FR.pad, 0) end
        if raid.RoleCount then k:Move(raid.RoleCount, "CENTER", bar, "CENTER", 0, 0) end
        local info = _G.RaidFrameRaidInfoButton
        if info then
            k:Size(info, 96, FR.control)
            k:Move(info, "RIGHT", bar, "RIGHT", -FR.pad, 0)
        end
        local convert = _G.RaidFrameConvertToRaidButton
        if convert then
            k:Size(convert, FR.wide, FR.button)
            k:Move(convert, "RIGHT", foot, "RIGHT", -FR.pad, 0)
        end
    end
    FrRaidInfo(k)

    -- The groups, once Blizzard_RaidUI has built them.
    for g = 1, 8 do
        local group = _G["RaidGroup" .. g]
        if group and not raidDressed[group] then
            raidDressed[group] = true
            for _, r in ipairs(S.Regions(group)) do
                if S.ArtIsFile(r, "Interface\\RaidFrame\\UI-RaidFrame-GroupOutline") then S.StripArt(r) end
            end
            local gp = S.PainterFor(group)
            gp:Fill("surfaceSunk")
            gp:Border("border")
            local label = _G["RaidGroup" .. g .. "Label"]
            local fs = label and label.GetFontString and label:GetFontString()
            if fs then k:Label(fs, "title", true) end
            for s = 1, 5 do
                local slot = _G["RaidGroup" .. g .. "Slot" .. s]
                if slot then
                    local h = slot.GetHighlightTexture and slot:GetHighlightTexture()
                    if h then S.StripArt(h) end
                    for _, r in ipairs(S.Regions(slot)) do
                        if r.GetObjectType and r:GetObjectType() == "FontString" then k:Label(r, "textDisabled") end
                    end
                end
            end
        end
    end
    local ROW = { rest = { fill = "surface2" }, hover = { fill = "surface3" } }
    for i = 1, 40 do
        local b = _G["RaidGroupButton" .. i]
        if b and not raidDressed[b] then
            raidDressed[b] = true
            for _, g in ipairs({ "GetNormalTexture", "GetHighlightTexture" }) do
                local t = b[g] and b[g](b)
                if t then S.StripArt(t) end
            end
            local p = S.PainterFor(b)
            p:Fill("surface2")
            p:States(ROW)
        end
    end
    for i = 1, 16 do
        local b = _G["RaidClassButton" .. i]
        if b and not raidDressed[b] then
            raidDressed[b] = true
            for _, r in ipairs(S.Regions(b)) do
                if S.ArtIsFile(r, "Interface\\SpellBook\\SpellBook-SkillLineTab") then S.StripArt(r) end
            end
            local h = b.GetHighlightTexture and b:GetHighlightTexture()
            if h then S.StripArt(h) end
            local icon = _G["RaidClassButton" .. i .. "IconTexture"]
            if icon then EV.Icons:Style(icon, { host = b, keepCoords = true }) end
        end
    end
end

P{
    name  = "FriendsFrame",
    addon = "Blizzard_FriendsFrame",
    apply = function(f, k)
        local top = (S.TITLE_BAND or 24) + 2
        if _G.FriendsFrameIcon then S.Mute(_G.FriendsFrameIcon) end

        -- No box round the lists: the Inset is only their rect.
        local inset = f.Inset
        if inset then
            k:Fade(inset)
            if inset.NineSlice then k:Fade(inset.NineSlice) end
            k:NoFill(inset)
            EV.Pixel:ShowEdges(inset, false)
        end

        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -top)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -top)
            b:SetHeight(FR.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(FR.footer)
        end)

        -- The tool bar: status, tag, menu.
        local header = f.FriendsTabHeader
        local bn = header and header.BattlenetFrame
        local status = header and header.StatusDropdown
        if status then
            k:Size(status, nil, FR.control)
            k:Move(status, "LEFT", bar, "LEFT", FR.pad, 0)
            -- Blizzard shows the status as a 16px icon in the text, sat on
            -- the baseline. Ours: the status dot, centred in the room left
            -- of the chevron.
            local d = S.D(status)
            local text = status.Text
            if text and not d.dot then
                local dot = S.Ours(status:CreateTexture(nil, "OVERLAY", nil, 3))
                dot:SetTexture(T.MEDIA .. "circle.png")
                dot:SetSize(8, 8)
                dot:SetPoint("CENTER", status, "LEFT", 16, 0)
                d.dot = dot
                local function Sync()
                    local token = S.StatusToken and S.StatusToken(header.bnStatus) or nil
                    text:SetAlpha(token and 0 or 1)
                    dot:SetShown(token ~= nil)
                    if token then dot:SetVertexColor(S.Colour(token)) end
                end
                hooksecurefunc(text, "SetText", Sync)
                T.Watch(dot, Sync)
                Sync()
            end
        end
        if bn then
            k:Fade(bn)
            k:Move(bn, "CENTER", bar, "CENTER", 0, 0)
            local menu = bn.ContactsMenuButton
            if menu then
                -- Our button with our chevron, not Blizzard's gold arrow.
                OverlayButton(k, menu, "down")
                k:Size(menu, FR.control, FR.control)
                k:Move(menu, "RIGHT", bar, "RIGHT", -FR.pad, 0)
            end
            -- Click the tag to copy it.
            local d = S.D(bn)
            if bn.Tag and not d.copy then
                local b = S.Ours(CreateFrame("Button", nil, bn))
                b:SetAllPoints(bn.Tag)
                b:SetScript("OnClick", function()
                    local _, tag = BNGetInfo()
                    if tag and EV.UI and EV.UI.ShowCopyText then
                        EV.UI.ShowCopyText(EV.L["BattleTag"], tag, EV.L["Send it to anyone who wants to add you."])
                    end
                end)
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:SetText(EV.L["Click to copy your BattleTag"], 1, 1, 1)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", GameTooltip_Hide)
                d.copy = b
            end
            if bn.BroadcastFrame then
                local bf = bn.BroadcastFrame
                if bf.Border then k:Mute(bf.Border) end
                k:Fill(bf, T.LOOK.window.rest.fill)
                k:Border(bf, T.LOOK.window.rest.edge)
            end
        end

        -- Friends / Recent Allies on a rule under the tool bar.
        local ts = header and header.TabSystem
        local listTop = top + FR.tool + FR.gap + FR.tabs
        if ts then
            k:Move(ts, "BOTTOMLEFT", f, "TOPLEFT", FR.pad, -listTop)
            for _, tab in ipairs(ts.tabs or {}) do TextTab(k, tab) end
            local d = S.D(f)
            if not d.frRule then
                d.frRule = S.Ours(f:CreateTexture(nil, "BORDER", nil, 1))
                EV.Pixel.NoSnap(d.frRule)
                d.frRule:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -listTop)
                d.frRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -listTop)
                local function Paint()
                    d.frRule:SetColorTexture(S.Colour("border"))
                    d.frRule:SetHeight(EV.Pixel:Line(f))
                end
                Paint()
                T.Watch(d.frRule, Paint)
                -- Rule and tabs only where the tabs are: the Raid page has none.
                local function Sync() d.frRule:SetShown(header:IsShown()) end
                header:HookScript("OnShow", Sync)
                header:HookScript("OnHide", Sync)
                Sync()
            end
        end

        -- The lists, from the rule to the footer, their bars in a gutter.
        local function Gutter(box, sbar)
            if not (box and sbar) then return end
            local w = S.Num(sbar:GetWidth()) or 8
            local x = math.floor((FR.gutter - w) / 2 + 0.5)
            k:Anchors(sbar, {
                { "TOPLEFT",    box, "TOPRIGHT",    x, -FR.gap },
                { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, FR.gap },
            })
        end
        local fl = _G.FriendsListFrame
        if fl and fl.ScrollBox then
            k:Anchors(fl.ScrollBox, {
                { "TOPLEFT",     f,    "TOPLEFT",  1, -(listTop + 1) },
                { "BOTTOMRIGHT", foot, "TOPRIGHT", -FR.gutter, 0 },
            })
            Gutter(fl.ScrollBox, fl.ScrollBar)
        end
        local ra = _G.RecentAlliesFrame
        local list = ra and ra.List
        if list then
            k:Anchors(list, {
                { "TOPLEFT",     f,    "TOPLEFT",  1, -(listTop + 1) },
                { "BOTTOMRIGHT", foot, "TOPRIGHT", 0, 0 },
            })
            if list.ScrollBox then
                k:Anchors(list.ScrollBox, {
                    { "TOPLEFT",     list, "TOPLEFT",     0, 0 },
                    { "BOTTOMRIGHT", list, "BOTTOMRIGHT", -FR.gutter, 0 },
                })
                Gutter(list.ScrollBox, list.ScrollBar)
            end
        end

        -- The footer.
        local add, msg = _G.FriendsFrameAddFriendButton, _G.FriendsFrameSendMessageButton
        if add then
            k:Size(add, FR.wide, FR.button)
            k:Move(add, "LEFT", foot, "LEFT", FR.pad, 0)
        end
        if msg then
            k:Size(msg, FR.wide, FR.button)
            k:Move(msg, "RIGHT", foot, "RIGHT", -FR.pad, 0)
        end

        local ignore = f.IgnoreListWindow
        if ignore then k:Panel(ignore, "surfaceSunk") end

        -- Contacts / Raid (/ Quick Join) as window tab faces under the
        -- window, laid out over whichever are showing.
        local function Tabs()
            local prev
            for _, name in ipairs({ "FriendsFrameTab1", "FriendsFrameTab3", "FriendsFrameTab4" }) do
                local tab = _G[name]
                if tab then
                    AHTab(k, f, tab)
                    if tab:IsShown() then
                        tab:ClearAllPoints()
                        if prev then
                            tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", AH_TAB.gap, 0)
                        else
                            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", FR.pad, 0)
                        end
                        prev = tab
                    end
                end
            end
        end
        Tabs()
        k:Once(f, "frTabs", function()
            if type(_G.PanelTemplates_SetTab) == "function" then
                hooksecurefunc("PanelTemplates_SetTab", function(frame)
                    if frame == f then
                        for _, name in ipairs({ "FriendsFrameTab1", "FriendsFrameTab3", "FriendsFrameTab4" }) do
                            if _G[name] then AHTabState(f, _G[name]) end
                        end
                    end
                end)
            end
            if type(_G.FriendsFrame_UpdateQuickJoinTab) == "function" then
                hooksecurefunc("FriendsFrame_UpdateQuickJoinTab", Tabs)
            end
            local raid = _G.RaidFrame
            if raid then
                raid:HookScript("OnShow", function()
                    C_Timer.After(0, function() FrRaid(k, f, bar, foot) end)
                end)
            end
        end)
        if _G.RaidFrame and _G.RaidFrame:IsShown() then FrRaid(k, f, bar, foot) end
    end,
}

--------------------------------------------------------------------------------
--  AddFriendFrame and BattleNetInviteFrame (Blizzard_AddFriend). Dialogs,
--  shown with a bare Show, that size themselves (ResizeLayoutFrame, user
--  scaled): a DialogBorderTemplate, a close button hung on the top-right
--  corner, the yellow info button, and AddFriendButtonTemplate buttons on
--  UI-DialogBox-Button art (which the dialogButton part dresses once the
--  walk reaches them). Their own layout is left alone: it sizes the frame.
--
--  Ours: the window's surface and edge in place of the border, the close
--  our size in the corner, the button that goes ahead in the primary Look,
--  the info button in our muted text colour.
--------------------------------------------------------------------------------
local function DialogPrimary(b)
    if not S.Alive(b) then return end
    local fs = b.Text or (b.GetFontString and b:GetFontString())
    S.PainterFor(b):States(T.LOOK.buttonPrimary, { label = fs })
end

local function FriendDialog(f, k)
    local W = T.LOOK.window.rest
    if f.Border then k:Mute(f.Border) end
    k:Fill(f, W.fill)
    k:Border(f, W.edge)
    local close = f.CloseButton
    if close then
        k:Size(close, S.TITLE_BAND or 24, S.TITLE_BAND or 24)
        k:Move(close, "TOPRIGHT", f, "TOPRIGHT", -1, -1)
    end
end

P{
    name  = "AddFriendFrame",
    apply = function(f, k)
        FriendDialog(f, k)
        local entry, info = f.EntryFrame, f.InfoFrame
        local box = entry and entry.EditBoxContainer
        DialogPrimary((box and box.AcceptButton) or (entry and entry.AcceptButton) or _G.AddFriendEntryFrameAcceptButton)
        if info then DialogPrimary(info.OkayButton) end
        local ib = _G.AddFriendEntryFrameInfoButton
        local t = ib and ib.GetNormalTexture and ib:GetNormalTexture()
        if t and t.SetDesaturated then
            t:SetDesaturated(true)
            t:SetVertexColor(T.RGBA("textMuted"))
        end
    end,
}

P{
    name  = "BattleNetInviteFrame",
    apply = function(f, k)
        FriendDialog(f, k)
        DialogPrimary(f.SendButton)
    end,
}

--------------------------------------------------------------------------------
--  FriendsFriendsFrame (Blizzard_FriendsFrame Mainline FriendsFriendsFrame.xml):
--  "Friends of <name>". A user-scaled dialog: DialogBorderTemplate, the title
--  left-aligned 26 in and 20 down, the Everyone / Mutual dropdown under it,
--  the list in a TooltipBackdrop box 24 in from each side, Send Request and
--  Close 30 in and 24 up.
--
--  Ours: our window with the title centred on a title bar, the dropdown on a
--  tool bar, the list straight on the window between the bars with its
--  scroll bar in a gutter, Send Request (primary) and Close on a footer.
--------------------------------------------------------------------------------
local FOF = { tool = 40, control = 30, pad = 8, footer = 36, button = 24, long = 120, gutter = 20, gap = 6 }

P{
    name  = "FriendsFriendsFrame",
    apply = function(f, k)
        local W = T.LOOK.window.rest
        if f.Border then k:Mute(f.Border) end
        k:Fill(f, W.fill)
        k:Border(f, W.edge)
        local TB = S.TITLE_BAND or 24

        local title = Band(f, "title", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
            b:SetHeight(TB)
        end)
        if f.Title then
            k:Anchors(f.Title, {
                { "LEFT",  title, "LEFT",  FOF.pad, 0 },
                { "RIGHT", title, "RIGHT", -FOF.pad, 0 },
            })
            f.Title:SetJustifyH("CENTER")
            k:Label(f.Title, W.title, true)
        end
        local bar = Band(f, "tool", "bottom", function(b)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -(TB + 2))
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -(TB + 2))
            b:SetHeight(FOF.tool)
        end)
        local foot = Band(f, "footer", "top", function(b)
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
            b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
            b:SetHeight(FOF.footer)
        end)

        local dd = f.FriendsDropdown
        if dd then
            k:Size(dd, nil, FOF.control)
            k:Move(dd, "LEFT", bar, "LEFT", FOF.pad, 0)
        end

        local border = f.ScrollFrameBorder
        if border then
            CfgFlat(k, border)
            k:Anchors(border, {
                { "TOPLEFT",     bar,  "BOTTOMLEFT", 0, -1 },
                { "BOTTOMRIGHT", foot, "TOPRIGHT",   0, 0 },
            })
            local box, sbar = f.ScrollBox, f.ScrollBar
            if box then
                k:Anchors(box, {
                    { "TOPLEFT",     border, "TOPLEFT",     0, 0 },
                    { "BOTTOMRIGHT", border, "BOTTOMRIGHT", -FOF.gutter, 0 },
                })
                if sbar then
                    local w = S.Num(sbar:GetWidth()) or 8
                    local x = math.floor((FOF.gutter - w) / 2 + 0.5)
                    k:Anchors(sbar, {
                        { "TOPLEFT",    box, "TOPRIGHT",    x, -FOF.gap },
                        { "BOTTOMLEFT", box, "BOTTOMRIGHT", x, FOF.gap },
                    })
                end
            end
        end

        local send, close = f.SendRequestButton, f.CloseButton
        if send then
            k:Size(send, FOF.long, FOF.button)
            k:Move(send, "LEFT", foot, "LEFT", FOF.pad, 0)
            DialogPrimary(send)
        end
        if close then
            k:Size(close, FOF.long, FOF.button)
            k:Move(close, "RIGHT", foot, "RIGHT", -FOF.pad, 0)
        end
    end,
}
