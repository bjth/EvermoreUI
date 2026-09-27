if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Designer.lua
--  Place the parts of a frame by dragging them: the name, the health text,
--  icons, the cast bar, buff and debuff blocks. Edit mode places whole frames
--  on the screen; this places things inside one.
--
--  It edits SETTINGS, never live frames. The canvas holds a copy built by the
--  surface's own code (for unit frames, M:BuildPreview), every drag writes the
--  saved values and lays the copy out again, and the real frames are brought
--  into line when a change is committed. So what you see is the real layout
--  code running, and nothing the designer does can leave a frame in a state
--  its settings don't describe.
--
--  Mouse and keys follow edit mode:
--    click select, drag move (Alt: no snapping), corner grip resize
--    arrows nudge 1, Shift+arrows 10, Ctrl+Z undo, Esc deselect / close
--  Changes are live but held: Save keeps them, Discard puts them back.
--
--  SURFACE (registered through EV.Designers:Register, Core/Designers.lua)
--    key, title, module          module name gates it; page opens its options
--    kind = "canvas" | "grid"    grid surfaces draw themselves (BuildGrid)
--    Tabs() -> { { value, text }, ... }       e.g. the unit frames
--    Build(host, tab) -> preview frame        once per tab
--    Layout(preview, tab)                     from settings, with samples
--    Elements(tab, preview) -> { element, ... }
--    Snapshot(tab) -> table   Restore(tab, snap)   Apply(tab)
--    note                                      one line under the canvas
--    help                                      inspector text with nothing picked
--  A grid surface (kind = "grid") has no preview; it draws into the canvas
--  itself with BuildGrid(stage, tab), hides with HideGrid(), and calls
--  EV.DesignerUI:Commit() after each change it makes. Its elements have no
--  region: it picks them with EV.DesignerUI:Select(key), and Paint(selected)
--  lets it show which one is picked.
--
--  ELEMENT
--    key, label
--    region(preview) -> the region whose box is the element (nil: not shown)
--    shown() -> bool          off elements are listed but not drawn
--    move = "free" | "slot" | "nudge" | nil
--      free   a point on a parent plus an offset:
--               parent(preview) -> region, points = "three" | "nine",
--               anchor = "same" (element's own point, text) | "center" (icons)
--                        | "auto" (the facing edge when outside the parent)
--               get() -> point, x, y ; set(point, x, y, own)   frame units
--      slot   a side of the frame, picked by where you drop it:
--               slots = "sides" | "vertical" | "horizontal", aligned = bool
--               getSlot() -> side, align ; setSlot(side, align)
--      nudge  an offset dragged directly:
--               get() -> x, y ; set(x, y)   in PIXELS, or frame units
--               with units = "frame"
--    text = true              the box is the words at the justified edge
--    Nudge(dx, dy)            arrow keys, in the element's own units
--    getSize() -> w, h ; setSize(w, h)   frame units; gives it a grip
--    Options(p)               inspector rows, with the options page builder
--    sub                      the line under its name in the inspector
--    unlisted = true          picked on the canvas only, not in the list
--    fresh = true             rows drawn again each time it's picked
--    Reset()
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local W = EV.UI
local L = EV.L
local D = EV.Designers

local UI = {}
EV.DesignerUI = UI

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local win, canvas, stage, listPanel, inspector, surfaceTabs, unitTabs, hint, confirm
local surface, tab                -- what's open
local preview                     -- the copy on the canvas
local previews = {}               -- surface.key .. tab -> preview frame
local elements = {}               -- current element list
local handles = {}                -- element key -> handle
local selected                    -- element key
local drag
local zoom = 1
local snapshots = {}              -- tabKey -> settings as they were when first touched
local undo = {}
local lastState                   -- settings after the last commit, per tabKey
local inspectorCache = {}         -- tabKey .. element key -> { frame, builder }
local suspended = false
local quiet = false               -- our own inspector refreshes, not a user change
local pending                     -- an inspector commit waiting for the control to settle
local shownKey                    -- the inspector entry on show

local SNAP = 3                    -- snap distance, frame units
local OwnPoint                    -- below

local function TabKey() return surface and (surface.key .. ":" .. tostring(tab)) or "" end

local function Txt(parent, size, token, bold, justify)
    local fs = T.Text(parent, size, token, bold, justify)
    T.OnTheme(function() fs:SetTextColor(T.RGBA(token)) end)
    return fs
end

local function Element(key)
    for _, e in ipairs(elements) do if e.key == key then return e end end
end

local function Shown(e) return not e.shown or e.shown() end

--------------------------------------------------------------------------------
--  Undo, commit, save, discard
--------------------------------------------------------------------------------
local RefreshAll -- forward

--- Remember how this tab looked before its first change, for Discard.
local function Touch()
    -- lastState is how the tab stood before the change being committed
    -- (drags write settings as they go), so it is the one to keep.
    if not lastState then lastState = surface.Snapshot(tab) end
    local k = TabKey()
    if not snapshots[k] then
        snapshots[k] = { surface = surface, tab = tab, snap = lastState }
    end
end

--- A change has been made (drag ended, nudge, inspector): the state before
--- it goes on the undo stack, and the real frames are brought into line.
function UI:Commit()
    if not surface then return end
    Touch()
    undo[#undo + 1] = { surface = surface, tab = tab, snap = lastState }
    if #undo > 60 then table.remove(undo, 1) end
    lastState = surface.Snapshot(tab)
    surface.Apply(tab)
    if surface.kind == "grid" and surface.BuildGrid then surface.BuildGrid(stage, tab) end
    RefreshAll()
end

--- Lay the copy out again after settings changed, without committing.
local function Relayout()
    if preview and surface.Layout then surface.Layout(preview, tab) end
end

--- An inspector commit still waiting: do it now (before undo, save, discard).
local function Flush()
    if pending then
        pending = false
        UI:Commit()
    end
end

function UI:SchedulePaint()
    C_Timer.After(0, function() if win and win:IsShown() then UI:PaintHandles() end end)
end

function UI:Undo()
    Flush()
    local u = table.remove(undo)
    if not u then return end
    if u.surface ~= surface or u.tab ~= tab then
        -- Undo reaches back into another tab: go there first.
        self:Show(u.surface.key, u.tab)
    end
    u.surface.Restore(u.tab, u.snap)
    lastState = u.surface.Snapshot(u.tab)
    Relayout()
    if surface.kind == "grid" and surface.BuildGrid then surface.BuildGrid(stage, tab) end
    RefreshAll()
end

local function Dirty() return pending or next(snapshots) ~= nil end

function UI:Save()
    Flush()
    wipe(snapshots); wipe(undo)
    lastState = nil
    win:Hide()
end

function UI:Discard()
    Flush()
    for _, s in pairs(snapshots) do
        s.surface.Restore(s.tab, s.snap)
    end
    wipe(snapshots); wipe(undo)
    lastState = nil
    win:Hide()
end

--------------------------------------------------------------------------------
--  Geometry: boxes in the preview's own units
--------------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

--- Plain numbers only. A region whose size or place depends on a secret
--- value (a font string showing one, a bar fill) reports secret geometry,
--- and arithmetic on it throws; such a region just has no box.
local function Plain(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) ~= "number" or issecret(v) then return false end
    end
    return true
end

local function Box(r)
    if not r or not r.GetLeft then return nil end
    local l, rt, t, b = r:GetLeft(), r:GetRight(), r:GetTop(), r:GetBottom()
    if not Plain(l, rt, t, b) then return nil end
    -- Regions report in their own effective scale; bring them to the
    -- preview's so every box on the canvas is in one space.
    local k = (r.GetEffectiveScale and r:GetEffectiveScale() or 1) / preview:GetEffectiveScale()
    l, rt, t, b = l * k, rt * k, t * k, b * k
    return { l = l, r = rt, t = t, b = b, cx = (l + rt) / 2, cy = (t + b) / 2, w = rt - l, h = t - b, k = k }
end

--- A text's box is the words, not the font string: a name anchored across
--- the whole bar would otherwise be "in the middle" the moment you touched
--- it. The words sit at the string's justified edge.
local function TextBox(r)
    local b = Box(r)
    if not b then return nil end
    local sw = (r.GetUnboundedStringWidth and r:GetUnboundedStringWidth()) or (r.GetStringWidth and r:GetStringWidth())
    if not Plain(sw) or sw <= 0 then return b end
    local w = min(sw * b.k + 2, b.w)
    local j = r.GetJustifyH and r:GetJustifyH() or "LEFT"
    if j == "RIGHT" then b.l = b.r - w
    elseif j == "CENTER" then b.l, b.r = b.cx - w / 2, b.cx + w / 2
    else b.r = b.l + w end
    b.w, b.cx, b.j = w, (b.l + b.r) / 2, j
    return b
end

local function ElementBox(e, r) return e.text and TextBox(r) or Box(r) end

local function Cursor()
    local x, y = GetCursorPosition()
    local s = preview:GetEffectiveScale()
    return x / s, y / s
end

local H3 = { "LEFT", "", "RIGHT" }
local V3 = { "TOP", "", "BOTTOM" }

--- Which of the parent's points a box belongs to: thirds across (and down,
--- for nine points).
local function PickPoint(box, parent, nine)
    local fx = (box.cx - parent.l) / max(parent.w, 1)
    local hx = fx < 1 / 3 and 1 or (fx > 2 / 3 and 3 or 2)
    if not nine then return ({ "LEFT", "CENTER", "RIGHT" })[hx] end
    local fy = (parent.t - box.cy) / max(parent.h, 1)
    local vy = fy < 1 / 3 and 1 or (fy > 2 / 3 and 3 or 2)
    local p = V3[vy] .. H3[hx]
    return p == "" and "CENTER" or p
end

--- The coordinates of a named point on a box.
local function PointOf(box, point)
    local x, y = box.cx, box.cy
    if point:find("LEFT") then x = box.l elseif point:find("RIGHT") then x = box.r end
    if point:find("TOP") then y = box.t elseif point:find("BOTTOM") then y = box.b end
    return x, y
end

local function Round(v) return floor(v + 0.5) end

--- For anchor = "auto": the element's own point to pin by. Outside the
--- parent on a side, the facing edge (a mark left of the bar hangs by its
--- right edge); overlapping it, the same point as the parent's.
OwnPoint = function(box, parent, point)
    local h = point:find("LEFT") and "LEFT" or (point:find("RIGHT") and "RIGHT" or "")
    local v = point:find("TOP") and "TOP" or (point:find("BOTTOM") and "BOTTOM" or "")
    if box.r <= parent.l + 0.5 then h = "RIGHT" elseif box.l >= parent.r - 0.5 then h = "LEFT" end
    if box.b >= parent.t - 0.5 then v = "BOTTOM" elseif box.t <= parent.b + 0.5 then v = "TOP" end
    local p = v .. h
    return p == "" and "CENTER" or p
end

local function Snapped(v, targets)
    if IsAltKeyDown() then return v end
    for _, t in ipairs(targets) do
        if abs(v - t) <= SNAP then return t end
    end
    return v
end

--- Which side of the frame the cursor is on, and which end of it.
local function SideOf(cx, cy, fb, mode)
    local side
    if mode == "vertical" then
        side = cy >= fb.cy and "TOP" or "BOTTOM"
    elseif mode == "horizontal" then
        side = cx < fb.cx and "LEFT" or "RIGHT"
    else
        -- Outside the frame, the side you're past; inside, the nearest edge.
        local dx = cx < fb.l and (fb.l - cx) or (cx > fb.r and (cx - fb.r) or 0)
        local dy = cy > fb.t and (cy - fb.t) or (cy < fb.b and (fb.b - cy) or 0)
        if dx == 0 and dy == 0 then
            local d = { TOP = fb.t - cy, BOTTOM = cy - fb.b, LEFT = cx - fb.l, RIGHT = fb.r - cx }
            local best
            for k, v in pairs(d) do if not best or v < d[best] then best = k end end
            side = best
        elseif dx > dy then
            side = cx < fb.l and "LEFT" or "RIGHT"
        else
            side = cy > fb.t and "TOP" or "BOTTOM"
        end
    end
    local align = cx < fb.cx and "START" or "END"
    return side, align
end

--------------------------------------------------------------------------------
--  Dragging
--------------------------------------------------------------------------------
local function StartDrag(e, grip)
    local r = e.region and e.region(preview)
    local box = ElementBox(e, r)
    if not box then return end
    local cx, cy = Cursor()
    drag = { e = e, x0 = cx, y0 = cy, box = box, moved = false, grip = grip }
    if grip and e.getSize then
        drag.w0, drag.h0 = e.getSize()
    elseif e.move == "free" then
        drag.point, drag.ox, drag.oy = e.get()
    elseif e.move == "nudge" then
        drag.ox, drag.oy = e.get()
    end
    canvas:SetScript("OnUpdate", UI.DragUpdate)
end

function UI.DragUpdate()
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") then UI.EndDrag() return end
    local e = drag.e
    local cx, cy = Cursor()
    local dx, dy = cx - drag.x0, cy - drag.y0
    if not drag.moved then
        if abs(dx) < 2 and abs(dy) < 2 then return end
        drag.moved = true
    end

    if drag.grip then
        -- The top-left corner stays put; the size follows the cursor.
        e.setSize(max(Round(drag.w0 + dx), 4), max(Round(drag.h0 - dy), 2))
    elseif e.move == "free" then
        local parent = Box(e.parent(preview))
        if not parent then return end
        local b = drag.box
        local box = { l = b.l + dx, r = b.r + dx, t = b.t + dy, b = b.b + dy,
                      cx = b.cx + dx, cy = b.cy + dy, w = b.w, h = b.h }
        local point = PickPoint(box, parent, e.points == "nine")
        local px, py = PointOf(parent, point)
        local ex, ey, own
        if e.anchor == "same" then
            ex, ey = PointOf(box, point)
        elseif e.anchor == "auto" then
            own = OwnPoint(box, parent, point)
            ex, ey = PointOf(box, own)
        else
            ex, ey = box.cx, box.cy
        end
        local ox, oy = Round(ex - px), Round(ey - py)
        local tx, ty = { 0 }, { 0 }
        if e.snapX then for _, v in ipairs(e.snapX) do tx[#tx + 1] = v end end
        if e.snapY then for _, v in ipairs(e.snapY) do ty[#ty + 1] = v end end
        e.set(point, Snapped(ox, tx), Snapped(oy, ty), own)
    elseif e.move == "slot" then
        local fb = Box(preview)
        if not fb then return end
        local side, align = SideOf(cx, cy, fb, e.slots)
        local curSide, curAlign = e.getSlot()
        if side ~= curSide or (e.aligned and align ~= curAlign) then e.setSlot(side, align) end
    elseif e.move == "nudge" then
        -- Pixels unless the element says its offsets are frame units.
        local one = (e.units == "frame") and 1 or EV.Pixel:One(preview)
        local px, py = Round(dx / one), Round(dy / one)
        e.set(drag.ox + Snapped(px, { -drag.ox }), drag.oy + Snapped(py, { -drag.oy }))
    end
    Relayout()
    UI:PaintHandles()
end

function UI.EndDrag()
    canvas:SetScript("OnUpdate", nil)
    local moved = drag and drag.moved
    drag = nil
    if moved then UI:Commit() else RefreshAll() end
end

--------------------------------------------------------------------------------
--  Handles: an outline over each element on the canvas
--------------------------------------------------------------------------------
local function PaintHandle(h)
    local sel = selected == h.key
    local hover = h:IsMouseOver()
    h.fill:SetColorTexture(T.RGBA("accent", sel and 0.28 or (hover and 0.18 or 0.06)))
    if sel then T.SetBorderToken(h, "text") else T.SetBorderToken(h, "accent", hover and 1 or 0.55) end
    h.label:SetShown(sel or hover)
    if h.grip then h.grip:SetShown(sel) end
end

function UI:PaintHandles()
    for _, h in pairs(handles) do if h:IsShown() then PaintHandle(h) end end
end

local function Select(key)
    selected = key
    RefreshAll()
end

--- For grid surfaces, which pick their own elements.
function UI:Select(key) Select(key) end
function UI:Selected() return selected end

local function CreateHandle()
    local h = CreateFrame("Button", nil, stage)
    h:RegisterForClicks("AnyUp")
    h.fill = T.Fill(h, "BACKGROUND", "accent", 0.06)
    h.fill:SetAllPoints()
    T.TokenBorder(h, "accent", 0.55)
    h.label = Txt(h, 11, "text", true)
    h.label:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 0, 2)
    h.label:Hide()
    h:SetScript("OnEnter", function(self)
        PaintHandle(self)
        local e = Element(self.key)
        if e then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(e.label, 1, 1, 1)
            local how = e.move == "free" and L["Drag to place it. It sticks to the nearest edge or the middle."]
                or e.move == "slot" and L["Drag it to a side of the frame."]
                or e.move == "nudge" and L["Drag to move it."]
                or L["Click to change its settings."]
            GameTooltip:AddLine(how, 0.75, 0.78, 0.82, true)
            GameTooltip:Show()
        end
    end)
    h:SetScript("OnLeave", function(self) PaintHandle(self); GameTooltip:Hide() end)
    h:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local e = Element(self.key)
        if not e then return end
        if selected ~= self.key then Select(self.key) end
        if e.move then StartDrag(e) end
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and drag then UI.EndDrag() end
    end)

    local g = CreateFrame("Button", nil, h)
    g:SetSize(12, 12)
    g:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 4, -4)
    local dot = T.Fill(g, "OVERLAY", "text", 0.95)
    dot:SetAllPoints()
    T.TokenBorder(g, "accent", 1)
    g:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Drag to resize"], 1, 1, 1)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    g:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local e = Element(h.key)
        if e and e.getSize then StartDrag(e, true) end
    end)
    g:SetScript("OnMouseUp", function() if drag then UI.EndDrag() end end)
    g:Hide()
    h.grip = g
    return h
end

local handlePool = {}

local function SyncHandles()
    for _, h in pairs(handles) do h:Hide() end
    wipe(handles)
    local i = 0
    -- Bigger elements first, so small ones sit on top and stay grabbable.
    local list = {}
    for _, e in ipairs(elements) do
        local r = Shown(e) and e.region and e.region(preview)
        local box = r and r.IsShown and r:IsShown() and ElementBox(e, r)
        if box and box.w > 0 and box.h > 0 then list[#list + 1] = { e = e, r = r, box = box, area = box.w * box.h } end
    end
    table.sort(list, function(a, b) return a.area > b.area end)
    for _, it in ipairs(list) do
        i = i + 1
        local h = handlePool[i] or CreateHandle()
        handlePool[i] = h
        h.key = it.e.key
        h.label:SetText(it.e.label)
        h:ClearAllPoints()
        if it.e.text and it.box.j then
            -- Over the words: pinned at the justified edge, as wide as they are.
            local j = it.box.j == "RIGHT" and "RIGHT" or (it.box.j == "CENTER" and "" or "LEFT")
            local ratio = preview:GetEffectiveScale() / h:GetEffectiveScale()
            h:SetPoint("TOP" .. j, it.r, "TOP" .. j)
            h:SetPoint("BOTTOM" .. j, it.r, "BOTTOM" .. j)
            h:SetWidth(it.box.w * ratio)
        else
            h:SetAllPoints(it.r)
        end
        h:SetFrameLevel(stage:GetFrameLevel() + 20 + i)
        h.grip:SetFrameLevel(h:GetFrameLevel() + 1)
        h.hasGrip = it.e.getSize ~= nil
        h:Show()
        handles[it.e.key] = h
    end
    for j = i + 1, #handlePool do handlePool[j]:Hide() end
    for _, h in pairs(handles) do
        PaintHandle(h)
        if not h.hasGrip then h.grip:Hide() end
    end
end

--------------------------------------------------------------------------------
--  Element list (left) and inspector (right)
--------------------------------------------------------------------------------
local listButtons = {}

local function SyncList()
    local y = -8
    local i = 0
    for _, e in ipairs(elements) do
      if not e.unlisted then
        i = i + 1
        local b = listButtons[i]
        if not b then
            b = CreateFrame("Button", nil, listPanel.content)
            b:SetHeight(24)
            b.bg = T.Fill(b, "BACKGROUND", "accent", 0)
            b.bg:SetAllPoints()
            b.text = Txt(b, 12, "text")
            b.text:SetPoint("LEFT", 10, 0)
            b.text:SetPoint("RIGHT", -6, 0)
            b.text:SetJustifyH("LEFT")
            b:SetScript("OnClick", function(self) Select(self.key) end)
            b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(T.C4(T.Resolve(T.LOOK.listItem, { hover = true, on = selected == self.key }).fill)) end)
            b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(T.C4(T.Resolve(T.LOOK.listItem, { on = selected == self.key }).fill)) end)
            listButtons[i] = b
        end
        b.key = e.key
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4, y)
        b:SetPoint("RIGHT", listPanel.content, "RIGHT", -4, 0)
        local on = Shown(e)
        b.text:SetText(on and e.label or (e.label .. "  |cff808080" .. L["off"] .. "|r"))
        b.text:SetTextColor(T.RGBA(on and "text" or "textMuted"))
        b.bg:SetColorTexture(T.C4(T.Resolve(T.LOOK.listItem, { on = selected == e.key }).fill))
        b:Show()
        y = y - 26
      end
    end
    for j = i + 1, #listButtons do listButtons[j]:Hide() end
    listPanel:SetContentHeight(-y + 8)
end

local function SyncInspector()
    for _, c in pairs(inspectorCache) do c.frame:Hide() end
    local e = selected and Element(selected)
    if not e then
        shownKey = nil
        inspector.title:SetText(surface and surface.title or "")
        inspector.sub:SetText(surface and surface.help or L["Pick something on the frame, or from the list."])
        inspector.reset:Hide()
        inspector.scroll:SetContentHeight(1)
        return
    end
    inspector.title:SetText(e.label)
    inspector.sub:SetText(e.sub or e.move == "free" and L["Drag it, or set it exactly below."]
        or e.move == "slot" and L["Drag it to a side of the frame, then nudge with the arrow keys."]
        or e.move == "nudge" and L["Drag it, or nudge with the arrow keys."] or "")
    inspector.reset:SetShown(e.Reset ~= nil)
    local ck = TabKey() .. ":" .. e.key
    local c = inspectorCache[ck]
    -- fresh: rows that read the game (buffs on you now) are drawn again
    -- each time the element is picked, not kept from last time.
    if c and e.fresh and shownKey ~= ck then
        c.frame:Hide()
        inspectorCache[ck] = nil
        c = nil
    end
    shownKey = ck
    if not c then
        -- The page builder puts its rows T.PAD in from the left, which suits
        -- the options window and not this narrow column: the host is pulled
        -- left so rows start 8 in, and the rows are as wide as the column
        -- less the scroll bar's room (kept whether or not it shows).
        local T_PAD = (EV.Theme and EV.Theme.PAD) or 32
        local width = max((inspector:GetWidth() or 420) - 30, 200)
        local f = CreateFrame("Frame", nil, inspector.scroll.content)
        f:SetPoint("TOPLEFT", inspector.scroll.content, "TOPLEFT", 8 - T_PAD, 0)
        f:SetWidth(width + T_PAD)
        -- The builder calls this after a control changes AND at the end of
        -- every Refresh, including ours; only the first is an edit.
        -- A slider fires on every step of a drag. The copy follows each step;
        -- the commit (an undo step, and the real frames) waits until the
        -- control has been still for a moment, so one drag is one undo.
        local b = EV.Options_NewBuilder(f, width, function()
            if quiet then return end
            Relayout()
            UI:SchedulePaint()
            if pending then return end
            pending = true
            C_Timer.After(0.35, function()
                if not pending then return end
                pending = false
                UI:Commit()
            end)
        end)
        -- Sliders and dropdowns sized for the column, so labels keep room.
        local row = b.Row
        b.Row = function(self, cfg)
            if cfg and cfg.type == "slider" and not cfg.width then cfg.width = 150 end
            if cfg and cfg.type == "dropdown" then cfg.width = min(cfg.width or 150, 160) end
            return row(self, cfg)
        end
        if e.Options then e.Options(b) end
        quiet = true
        b:Refresh()
        quiet = false
        f:SetHeight(b:Height())
        c = { frame = f, builder = b }
        inspectorCache[ck] = c
    end
    quiet = true
    c.builder:Refresh()
    quiet = false
    c.frame:Show()
    inspector.scroll:SetContentHeight(c.frame:GetHeight())
end

--- The picked element's rows changed shape (a list grew or shrank): draw
--- them again. commit records the change when no control has.
function UI:RebuildInspector(commit)
    C_Timer.After(0, function()
        if not (win and win:IsShown()) then return end
        local ck = TabKey() .. ":" .. tostring(selected)
        local c = inspectorCache[ck]
        if c then c.frame:Hide(); inspectorCache[ck] = nil end
        if commit then UI:Commit() else SyncInspector() end
    end)
end

--------------------------------------------------------------------------------
--  Tabs and the canvas
--------------------------------------------------------------------------------
local function SurfaceTabs()
    local list = {}
    for _, s in ipairs(D:List()) do list[#list + 1] = { value = s.key, text = s.title } end
    return list
end

local tabsBySurface = {}

--- One row of tabs per surface, made once and kept.
local function BuildUnitTabs()
    if unitTabs then unitTabs:Hide() end
    unitTabs = nil
    if not (surface and surface.Tabs) then return end
    unitTabs = tabsBySurface[surface.key]
    if not unitTabs then
        local key = surface.key
        unitTabs = W.Tabs(win.body, surface.Tabs(), function() return tab end, function(v) UI:Show(key, v) end,
                          { height = 28 })
        unitTabs:SetPoint("TOPLEFT", win.body, "TOPLEFT", 196, -44)
        tabsBySurface[key] = unitTabs
    end
    unitTabs:Show()
    unitTabs:Refresh()
end

--- The zoom lives on a holder the copy sits in, not on the copy: a surface's
--- own layout may set the copy's scale (a nameplate does), and it must not
--- undo the zoom or be undone by it.
local function Place()
    if not preview then return end
    stage.zoom:SetScale(zoom)
    preview:ClearAllPoints()
    -- Centred, a little high: most of what hangs off a frame hangs below it.
    preview:SetPoint("CENTER", stage.zoom, "CENTER", 0, 30 / zoom)
end

function RefreshAll()
    if not win or not win:IsShown() then return end
    elements = (surface and surface.Elements and surface.Elements(tab, preview)) or {}
    if selected and not Element(selected) then selected = nil end
    if preview then
        SyncHandles()
    else
        for _, h in pairs(handles) do h:Hide() end
        wipe(handles)
    end
    SyncList()
    SyncInspector()
    if surface and surface.kind == "grid" and surface.Paint then surface.Paint(selected) end
    win.undo:SetDisabled(#undo == 0)
    win.discard:SetDisabled(not Dirty())
    hint:SetText(surface and surface.note or "")
end
UI.RefreshAll = function() RefreshAll() end

--- Show one surface and tab in the window.
function UI:Show(key, which)
    local s = D:Get(key)
    if not s then return end
    if drag then UI.EndDrag() end
    local changed = s ~= surface
    surface = s
    local list = s.Tabs and s.Tabs() or {}
    if which == nil or which == "" then
        which = (changed or tab == nil) and (list[1] and list[1].value) or tab
    end
    tab = which
    lastState = nil
    if preview then preview:Hide() end
    local pk = TabKey()
    if s.kind == "grid" then
        preview = nil
        if s.BuildGrid then s.BuildGrid(stage, tab) end
    else
        if s.HideGrid then s.HideGrid() end
        for _, other in pairs(D.surfaces) do
            if other ~= s and other.HideGrid then other.HideGrid() end
        end
        preview = previews[pk]
        if not preview then
            preview = s.Build(stage.zoom, tab)
            previews[pk] = preview
        end
        preview:SetParent(stage.zoom)
        preview:SetFrameLevel(stage:GetFrameLevel() + 2)
        Place()
        s.Layout(preview, tab)
        preview:Show()
    end
    if changed then BuildUnitTabs() elseif unitTabs then unitTabs:Refresh() end
    surfaceTabs:Refresh()
    selected = nil
    lastState = s.Snapshot and s.Snapshot(tab) or nil
    RefreshAll()
    -- Handles hang off regions laid out this frame; place them once the
    -- layout has settled.
    C_Timer.After(0, function() if win:IsShown() then RefreshAll() end end)
end

--------------------------------------------------------------------------------
--  Keyboard
--------------------------------------------------------------------------------
local ARROWS = { LEFT = { -1, 0 }, RIGHT = { 1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 } }

local function OnKeyDown(self, key)
    local handled = false
    if key == "ESCAPE" then
        handled = true
        if confirm:IsShown() then confirm:Hide()
        elseif selected then Select(nil)
        else UI:RequestClose() end
    elseif ARROWS[key] and selected and not GetCurrentKeyBoardFocus() then
        local e = Element(selected)
        if e and e.Nudge then
            handled = true
            local step = IsShiftKeyDown() and 10 or 1
            e.Nudge(ARROWS[key][1] * step, ARROWS[key][2] * step)
            Relayout()
            UI:Commit()
        end
    elseif key == "Z" and IsControlKeyDown() and not GetCurrentKeyBoardFocus() then
        handled = true
        UI:Undo()
    end
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not handled) end
end

--------------------------------------------------------------------------------
--  Window
--------------------------------------------------------------------------------
local function BuildConfirm()
    local f = CreateFrame("Frame", nil, win)
    f:SetSize(380, 150)
    f:SetPoint("CENTER")
    f:SetFrameLevel(win:GetFrameLevel() + 200)
    f:EnableMouse(true)
    W.Surface(f, "raised", 1)
    T.Shadow(f, 10)
    local t = Txt(f, 17, "text", true)
    t:SetPoint("TOPLEFT", 20, -18)
    t:SetText(L["Keep your changes?"])
    local d = Txt(f, 13, "textMuted")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    d:SetText(L["You changed the layout in the designer."])
    local save = W.Button(f, L["Save"], 100, function() f:Hide(); UI:Save() end, "accent")
    save:SetPoint("BOTTOMRIGHT", -16, 16)
    local discard = W.Button(f, L["Discard"], 100, function() f:Hide(); UI:Discard() end)
    discard:SetPoint("RIGHT", save, "LEFT", -8, 0)
    local back = W.Button(f, L["Keep editing"], 110, function() f:Hide() end, "ghost")
    back:SetPoint("RIGHT", discard, "LEFT", -8, 0)
    f:Hide()
    return f
end

function UI:RequestClose()
    if Dirty() then confirm:Show() else self:Save() end
end

local function Build()
    win = W.Window("EvermoreUIDesigner", { width = 1240, height = 740, title = L["Designer"],
                                           strata = "DIALOG", escape = false })
    win:SetFrameStrata("DIALOG")
    win.closeButton:SetScript("OnClick", function() UI:RequestClose() end)
    win:EnableKeyboard(true)
    win:SetScript("OnKeyDown", OnKeyDown)
    win:SetPropagateKeyboardInput(true)
    local body = win.body

    surfaceTabs = W.Tabs(body, SurfaceTabs(), function() return surface and surface.key end,
                         function(v) UI:Show(v) end, { height = 34 })
    surfaceTabs:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -6)

    -- Left: the element list.
    local left = CreateFrame("Frame", nil, body)
    left:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -84)
    left:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 52)
    left:SetWidth(176)
    W.Surface(left, "inset", 0.5, { edge = false })
    local lt = Txt(left, 11, "textDisabled", true)
    lt:SetPoint("BOTTOMLEFT", left, "TOPLEFT", 2, 6)
    lt:SetText(L["PARTS"])
    listPanel = W.Scroll(left)
    listPanel:SetAllPoints()

    -- Right: the inspector.
    inspector = CreateFrame("Frame", nil, body)
    inspector:SetPoint("TOPRIGHT", body, "TOPRIGHT", -12, -84)
    inspector:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 52)
    inspector:SetWidth(420)
    W.Surface(inspector, "inset", 0.5, { edge = false })
    inspector.title = Txt(inspector, 16, "text", true)
    inspector.title:SetPoint("TOPLEFT", 14, -12)
    inspector.title:SetPoint("RIGHT", -90, 0)
    inspector.title:SetJustifyH("LEFT")
    inspector.sub = Txt(inspector, 12, "textMuted")
    inspector.sub:SetPoint("TOPLEFT", inspector.title, "BOTTOMLEFT", 0, -4)
    inspector.sub:SetPoint("RIGHT", -14, 0)
    inspector.sub:SetJustifyH("LEFT")
    inspector.sub:SetWordWrap(true)
    inspector.reset = W.ConfirmButton(inspector, L["Reset"], 72, function()
        local e = selected and Element(selected)
        if e and e.Reset then
            Touch()
            e.Reset()
            Relayout()
            UI:Commit()
        end
    end)
    inspector.reset:SetPoint("TOPRIGHT", -10, -8)
    inspector.scroll = W.Scroll(inspector, { reserve = true })
    inspector.scroll:SetPoint("TOPLEFT", 0, -56)
    inspector.scroll:SetPoint("BOTTOMRIGHT", 0, 4)

    -- Middle: the canvas.
    canvas = CreateFrame("Frame", nil, body)
    canvas:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    -- Shorter than the side columns: the canvas's own two lines of help sit
    -- under it, clear of the buttons along the bottom.
    canvas:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMLEFT", -12, 40)
    canvas:SetClipsChildren(true)
    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Select(nil) end
    end)
    local cbg = T.Solid(canvas, "BACKGROUND", 0.06, 0.07, 0.08, 1)   -- the canvas: a neutral stage, not a surface
    cbg:SetAllPoints()
    -- Its edge is an inset's; its fill is the stage above, so the surface's
    -- own fill is clear.
    W.Surface(canvas, "inset", 0)
    -- A faint dot grid, so empty space reads as a canvas rather than a hole.
    for gx = 1, 30 do
        for gy = 1, 20 do
            local d = canvas:CreateTexture(nil, "BACKGROUND", nil, 1)
            d:SetColorTexture(1, 1, 1, 0.05)
            d:SetSize(2, 2)
            d:SetPoint("TOPLEFT", canvas, "TOPLEFT", gx * 32, -gy * 32)
        end
    end
    stage = CreateFrame("Frame", nil, canvas)
    stage:SetAllPoints()
    stage:SetFrameLevel(canvas:GetFrameLevel() + 2)
    stage.zoom = CreateFrame("Frame", nil, stage)
    stage.zoom:SetSize(2, 2)
    stage.zoom:SetPoint("CENTER")
    stage.zoom:SetFrameLevel(stage:GetFrameLevel() + 1)

    hint = Txt(body, 12, "textMuted")
    hint:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 2, -6)
    hint:SetPoint("RIGHT", canvas, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)

    local keys = Txt(body, 11, "textDisabled")
    keys:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    keys:SetPoint("RIGHT", canvas, "RIGHT", 0, 0)
    keys:SetJustifyH("LEFT")
    keys:SetWordWrap(false)
    keys:SetText(L["Drag to move, Alt: no snapping, arrows nudge (Shift: 10), Ctrl+Z undo, Esc deselect"])

    -- Bottom right: the actions.
    local save = W.Button(body, L["Save & close"], 130, function() UI:Save() end, "accent")
    save:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 12)
    win.discard = W.Button(body, L["Discard"], 96, function() UI:Discard() end)
    win.discard:SetPoint("RIGHT", save, "LEFT", -8, 0)
    win.undo = W.Button(body, L["Undo"], 72, function() UI:Undo() end)
    win.undo:SetPoint("RIGHT", win.discard, "LEFT", -8, 0)
    local zoomBtn
    zoomBtn = W.Button(body, L["Zoom"] .. ": 1x", 96, function()
        zoom = zoom == 1 and 1.5 or (zoom == 1.5 and 2 or 1)
        zoomBtn:SetText(L["Zoom"] .. ": " .. zoom .. "x")
        Place()
        -- Pixel-snapped sizes were worked out at the old scale.
        Relayout()
        C_Timer.After(0, RefreshAll)
    end, "ghost")
    zoomBtn:SetPoint("RIGHT", win.undo, "LEFT", -16, 0)
    zoomBtn:SetTooltip(L["Zoom"], L["Bigger to grab small things. Borders stay one screen pixel thick at any zoom, so 1x is the one that looks exactly like the real frame."])
    local opts = W.Button(body, L["All settings"], 110, function()
        if surface and surface.page then
            -- Kept, as edit mode keeps them on its way to the options: the
            -- two must not both be editing the same settings.
            local page, pageTab = surface.page, surface.PageTab and surface.PageTab(tab)
            UI:Save()
            EV:OpenOptions()
            if EV.Options.ShowPage then EV.Options:ShowPage(page, pageTab) end
        end
    end, "ghost")
    opts:SetPoint("RIGHT", zoomBtn, "LEFT", -8, 0)

    confirm = BuildConfirm()
    win:SetScript("OnHide", function()
        if drag then UI.EndDrag() end
        GameTooltip:Hide()
    end)
    win:SetScript("OnShow", function()
        -- A grid surface draws from live state; bring it up to date.
        if surface and surface.kind == "grid" and surface.BuildGrid then surface.BuildGrid(stage, tab) end
    end)
end

function UI:Open(key, which)
    if InCombatLockdown() then EV:Print(L["The designer is available out of combat."]) return end
    if not win then Build() end
    local list = D:List()
    if #list == 0 then EV:Print(L["Nothing to design: the modules that use the designer are switched off."]) return end
    local ok = {}
    for _, s in ipairs(list) do ok[s.key] = true end
    if key and not ok[key] then
        EV:Print(L["That part of the UI is switched off, so there's nothing of it to design."])
        key = nil
    end
    if not key then key = (surface and ok[surface.key] and surface.key) or list[1].key end
    win:Show()
    win:Raise()
    self:Show(key, which)
end

-- Edit mode (the Position section's Open button, or /evui edit) places whole
-- frames on the screen; the two don't share the screen. Keep what's been done
-- here and step out of its way.
local listener = EV:NewModule("Designer")
listener.internal = true
listener:RegisterMessage("EV_UNLOCK", function()
    if win and win:IsShown() then UI:Save() end
end)

-- Combat: step aside and keep the session.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if win and win:IsShown() then
            suspended = true
            if drag then UI.EndDrag() end
            win:Hide()
            EV:Print(L["Designer paused for combat."])
        end
    elseif suspended then
        suspended = false
        win:Show()
        if surface then UI:Show(surface.key, tab) end
    end
end)
