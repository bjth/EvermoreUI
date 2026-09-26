if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  EditMode.lua
--  The layout editor. Data lives in the core (Core/Movers.lua); this is the UI.
--
--  Mouse
--    click              select            ctrl-click   add/remove from selection
--    drag               move (selection moves together; anchored frames follow)
--    shift + drag       lock to one axis  alt + drag   no snapping
--    right-click        select + settings shift + right-click  hide this handle
--  Keys
--    arrows             nudge 1 pixel     shift + arrows  10 pixels
--    ctrl + z           undo              esc   clear selection / leave
--
--  Snapping: edges and centres of other frames, the screen centre lines, and
--  the grid when it's showing. Guides show what you snapped to.
--  Changes are live but held: Save keeps them, Discard puts everything back.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local W = EV.UI
local L = EV.L
-- Theme helpers: every colour here is a token, kept in step with the
-- contrast setting.
local function PanelBg(f, alpha)
    local bg = T.Fill(f, "BACKGROUND", "surface0", alpha or 0.97)
    bg:SetAllPoints()
    T.TokenBorder(f, "border")
    T.OnTheme(function()
        bg:SetColorTexture(T.RGBA("surface0", alpha or 0.97))
        T.SetBorderToken(f, "border")
    end)
    return bg
end
local function Txt(parent, size, token, bold, justify)
    local fs = T.Text(parent, size, token, bold, justify)
    T.OnTheme(function() fs:SetTextColor(T.RGBA(token)) end)
    return fs
end
local Movers = EV.Movers

local EM = {}
EV.EditMode = EM

local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local root, dim, gridFrame, guideX, guideY, topBar, inspector, confirm
local handles = {}           -- key -> handle
local selected, selOrder = {}, {}
local active, suspended = false, false
local snapshot, dirty = nil, false
local undo = {}
local drag                   -- live drag state
local pick                   -- { kind = "anchor"|"w"|"h", key = }
local hiddenHandles = {}
local reopenOptions = false

local SNAP_PX = 8            -- snap distance, physical pixels
local GRID_PX = 32           -- grid spacing, physical pixels

local function Settings()
    local core = EV.DB:GetCore()
    core.editMode = core.editMode or {}
    EV.DB.Merge(core.editMode, { grid = "dim", snap = true, coords = false, dim = true })
    return core.editMode
end

local function One() return EV.Pixel:One(UIParent) end

--------------------------------------------------------------------------------
--  Undo
--------------------------------------------------------------------------------
local function PushUndo()
    undo[#undo + 1] = Movers:Snapshot()
    if #undo > 40 then table.remove(undo, 1) end
    dirty = true
end

local lastNudgePush = 0
local function PushUndoThrottled()
    local now = GetTime()
    if now - lastNudgePush > 0.8 then PushUndo() end
    lastNudgePush = now
end

--------------------------------------------------------------------------------
--  Selection helpers
--------------------------------------------------------------------------------
local RefreshAll -- forward

local function Visible(key)
    local e = Movers:Get(key)
    if not e then return false end
    if hiddenHandles[key] then return false end
    if e.isDisabled and e.isDisabled() then return false end
    return true
end

local function ClearSelection()
    wipe(selected); wipe(selOrder)
end

local function Select(key, additive)
    if not additive then ClearSelection() end
    if selected[key] then
        if additive then
            selected[key] = nil
            for i, k in ipairs(selOrder) do if k == key then table.remove(selOrder, i) break end end
        end
    else
        selected[key] = true
        selOrder[#selOrder + 1] = key
    end
end

local function Depth(key)
    local d, cur = 0, Movers:GetAnchor(key)
    while cur and d < 50 do d = d + 1; cur = Movers:GetAnchor(cur.target) end
    return d
end

-- Selection ordered so anchor targets move before the things glued to them.
local function SelectionByDepth()
    local list = {}
    for _, k in ipairs(selOrder) do list[#list + 1] = k end
    table.sort(list, function(a, b) return Depth(a) < Depth(b) end)
    return list
end

local function MoveSelectionBy(dx, dy)
    for _, k in ipairs(SelectionByDepth()) do
        -- A frame glued to another selected frame already moved with it.
        local a = Movers:GetAnchor(k)
        if not (a and selected[a.target]) then
            local x, y = Movers:GetOffset(k)
            Movers:SetOffset(k, x + dx, y + dy)
        end
    end
end

--------------------------------------------------------------------------------
--  Grid and guides
--------------------------------------------------------------------------------
local function BuildGrid()
    gridFrame.lines = gridFrame.lines or {}
    for _, l in ipairs(gridFrame.lines) do l:Hide() end
    local mode = Settings().grid
    if mode == "off" then return end
    local one = One()
    local step = GRID_PX * one
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local alpha = mode == "bright" and 0.16 or 0.07
    local n = 0
    local function Line(vertical, off, centre)
        n = n + 1
        local t = gridFrame.lines[n] or gridFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
        gridFrame.lines[n] = t
        EV.Pixel.NoSnap(t)
        if centre then t:SetColorTexture(T.RGBA("accent", 0.55)) else t:SetColorTexture(T.RGBA("text", alpha)) end
        t:ClearAllPoints()
        if vertical then t:SetSize(one, h); t:SetPoint("CENTER", gridFrame, "CENTER", off, 0)
        else t:SetSize(w, one); t:SetPoint("CENTER", gridFrame, "CENTER", 0, off) end
        t:Show()
    end
    Line(true, 0, true); Line(false, 0, true)
    for off = step, w / 2, step do Line(true, off); Line(true, -off) end
    for off = step, h / 2, step do Line(false, off); Line(false, -off) end
end

local function ShowGuide(tex, vertical, pos)
    if not pos then tex:Hide(); return end
    tex:ClearAllPoints()
    local one = One()
    if vertical then
        tex:SetSize(one, UIParent:GetHeight())
        tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos, UIParent:GetHeight() / 2)
    else
        tex:SetSize(UIParent:GetWidth(), one)
        tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", UIParent:GetWidth() / 2, pos)
    end
    tex:Show()
end

--------------------------------------------------------------------------------
--  Snapping
--------------------------------------------------------------------------------
-- Bounds of `key` if its centre were at offset (x, y) from screen centre.
local function BoundsAt(key, x, y)
    local w, h = Movers:Size(key)
    local ux, uy = UIParent:GetCenter()
    local cx, cy = ux + x, uy + y
    return { l = cx - w / 2, r = cx + w / 2, cx = cx, t = cy + h / 2, b = cy - h / 2, cy = cy }
end

local XS, YS = { "l", "cx", "r" }, { "t", "cy", "b" }

-- Returns correction dx, dy and the guide positions they snapped to.
local function Snap(key, x, y)
    if not Settings().snap or IsAltKeyDown() then return 0, 0 end
    local me = BoundsAt(key, x, y)
    local thresh = SNAP_PX * One()
    local bestX, bestY, gx, gy

    local function Try(axis, mine, theirs)
        local d = theirs - mine
        if abs(d) > thresh then return end
        if axis == "x" then
            if not bestX or abs(d) < abs(bestX) then bestX, gx = d, theirs end
        else
            if not bestY or abs(d) < abs(bestY) then bestY, gy = d, theirs end
        end
    end

    -- Screen centre lines
    local ux, uy = UIParent:GetCenter()
    Try("x", me.cx, ux)
    Try("y", me.cy, uy)

    -- Other frames (not selected, not glued to the selection)
    local excluded = {}
    for k in pairs(selected) do excluded[k] = true; Movers:Descendants(k, excluded) end
    for k, h in pairs(handles) do
        if not excluded[k] and h:IsShown() then
            local ob = Movers:Bounds(k)
            if ob then
                for _, a in ipairs(XS) do for _, b in ipairs(XS) do Try("x", me[a], ob[b]) end end
                for _, a in ipairs(YS) do for _, b in ipairs(YS) do Try("y", me[a], ob[b]) end end
            end
        end
    end

    -- Grid, for any axis nothing else claimed
    if Settings().grid ~= "off" then
        local step = GRID_PX * One()
        if not bestX then
            for _, a in ipairs(XS) do
                local line = ux + floor((me[a] - ux) / step + 0.5) * step
                Try("x", me[a], line)
            end
        end
        if not bestY then
            for _, a in ipairs(YS) do
                local line = uy + floor((me[a] - uy) / step + 0.5) * step
                Try("y", me[a], line)
            end
        end
    end

    ShowGuide(guideX, true, gx)
    ShowGuide(guideY, false, gy)
    return bestX or 0, bestY or 0
end

--------------------------------------------------------------------------------
--  Handles (the overlay on each frame)
--------------------------------------------------------------------------------
local function PaintHandle(h)
    local key = h.key
    local sel = selected[key]
    local hover = h:IsMouseOver()
    local anchored = Movers:GetAnchor(key) ~= nil
    local isPickTarget = pick and pick.key ~= key

    h.fill:SetColorTexture(T.RGBA("accent", sel and 0.32 or (hover and 0.22 or 0.13)))
    h.backing:SetColorTexture(T.RGBA("surfaceSunk", 0.55))
    if sel then T.SetBorderToken(h, "text")
    elseif isPickTarget and hover then T.SetBorderToken(h, "warning")
    else T.SetBorderToken(h, "accent", hover and 1 or 0.75) end

    h.label:SetTextColor(T.RGBA("text", sel and 1 or 0.85))
    h.sub:SetTextColor(T.RGBA("textMuted"))
    h.coords:SetTextColor(T.RGBA("textMuted"))
    local a = Movers:GetAnchor(key)
    if a then
        local te = Movers:Get(a.target)
        h.sub:SetText(L["anchored to"] .. " " .. (te and te.label or a.target))
        h.sub:Show()
    else
        h.sub:Hide()
    end
    local showCoords = Settings().coords or sel or hover
    if showCoords then
        local px, py = Movers:GetOffsetPx(key)
        h.coords:SetText(("%d, %d"):format(px, py))
        h.coords:Show()
    else
        h.coords:Hide()
    end
    h.label:SetShown(h:GetHeight() >= 14)
    if anchored then h.label:SetTextColor(T.RGBA("warning", sel and 1 or 0.9)) end
end

local function PaintHandles()
    for _, h in pairs(handles) do if h:IsShown() then PaintHandle(h) end end
end

local function StartDrag(h)
    local wasDirty = dirty
    PushUndo()
    local cx, cy = GetCursorPosition()
    local es = UIParent:GetEffectiveScale()
    drag = { key = h.key, x0 = cx / es, y0 = cy / es, moved = false, start = {}, wasDirty = wasDirty }
    for _, k in ipairs(selOrder) do
        local x, y = Movers:GetOffset(k)
        drag.start[k] = { x = x, y = y }
    end
    root:SetScript("OnUpdate", EM.DragUpdate)
end

function EM.DragUpdate()
    if not drag then return end
    local cx, cy = GetCursorPosition()
    local es = UIParent:GetEffectiveScale()
    local dx, dy = cx / es - drag.x0, cy / es - drag.y0
    if not drag.moved then
        if abs(dx) < 3 * One() and abs(dy) < 3 * One() then return end
        drag.moved = true
        drag.axis = IsShiftKeyDown() and ((abs(dx) >= abs(dy)) and "x" or "y") or nil
    end
    if drag.axis == "x" then dy = 0 elseif drag.axis == "y" then dx = 0 end

    local s = drag.start[drag.key]
    local sx, sy = Snap(drag.key, s.x + dx, s.y + dy)
    if drag.axis == "x" then sy = 0 elseif drag.axis == "y" then sx = 0 end
    dx, dy = dx + sx, dy + sy

    for _, k in ipairs(SelectionByDepth()) do
        local a = Movers:GetAnchor(k)
        if not (a and selected[a.target]) then
            local st = drag.start[k]
            Movers:SetOffset(k, st.x + dx, st.y + dy)
        end
    end
    PaintHandles()
    EM:RefreshInspector()
end

local function EndDrag()
    root:SetScript("OnUpdate", nil)
    guideX:Hide(); guideY:Hide()
    if drag and not drag.moved then  -- a click, not a move
        table.remove(undo)
        dirty = drag.wasDirty
    end
    drag = nil
    RefreshAll()
end

local function FinishPick(targetKey)
    local p = pick
    pick = nil
    if not p or p.key == targetKey then RefreshAll(); return end
    PushUndo()
    if p.kind == "anchor" then
        local a = Movers:GetAnchor(p.key)
        if not Movers:SetAnchor(p.key, targetKey, a and a.side or "BOTTOM", a and a.align or "CENTER") then
            EV:Print(L["Can't anchor there: it would make a loop."])
        end
    else
        Movers:SetMatch(p.key, p.kind, targetKey)
    end
    RefreshAll()
end

local function CreateHandle(key)
    local e = Movers:Get(key)
    local h = CreateFrame("Button", nil, root)
    h.key = key
    h:SetAllPoints(e.frame)
    h:RegisterForClicks("AnyUp")
    h.fill = T.Fill(h, "BACKGROUND", "accent", 0.13)
    h.fill:SetAllPoints()
    h.backing = T.Fill(h, "BACKGROUND", "surfaceSunk", 0.55, -1)
    h.backing:SetAllPoints()
    T.TokenBorder(h, "accent", 0.75)

    h.label = T.Text(h, 13, "text", true, "CENTER")
    h.label:SetPoint("CENTER", 0, 0)
    h.label:SetText(e.label)
    h.sub = T.Text(h, 10, "textMuted", false, "CENTER")
    h.sub:SetPoint("TOP", h.label, "BOTTOM", 0, -1)
    h.coords = T.Text(h, 10, "textMuted")
    h.coords:SetPoint("TOPLEFT", 3, -2)

    h:SetScript("OnEnter", function(self)
        PaintHandle(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(e.label, 1, 1, 1)
        if e.group then GameTooltip:AddLine(e.group, 0.6, 0.6, 0.6) end
        GameTooltip:AddLine(L["Drag to move. Right-click for settings."], 0.75, 0.78, 0.82, true)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function(self) PaintHandle(self); GameTooltip:Hide() end)
    h:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if pick then FinishPick(self.key); return end
        if IsControlKeyDown() then
            Select(self.key, true)
            if not selected[self.key] then RefreshAll(); return end
        elseif not selected[self.key] then
            Select(self.key)
        end
        RefreshAll()
        StartDrag(self)
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and drag then EndDrag() end
    end)
    h:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        if IsShiftKeyDown() then
            hiddenHandles[self.key] = true
            selected[self.key] = nil
            for i, k in ipairs(selOrder) do if k == self.key then table.remove(selOrder, i) break end end
            EV:Print(L["Handle hidden until you leave edit mode:"], e.label)
        else
            Select(self.key)
            EM.inspectorOpen = true
        end
        RefreshAll()
    end)
    -- Resizable elements get a corner grip: drag it and the top-left corner
    -- stays put while the size follows the cursor, pixel-snapped.
    if e.setSize then
        local g = CreateFrame("Button", nil, h)
        g:SetSize(14, 14)
        g:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -2, 2)
        g:SetFrameLevel(h:GetFrameLevel() + 3)
        for i = 1, 3 do
            for j = 1, i do
                local dot = T.Fill(g, "OVERLAY", "accent", 0.9)
                dot:SetSize(2, 2)
                dot:SetPoint("BOTTOMRIGHT", g, "BOTTOMRIGHT", -(j - 1) * 4, (i - j) * 4)
            end
        end
        g:SetAlpha(0.7)
        g:SetScript("OnEnter", function(self)
            self:SetAlpha(1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Drag to resize"], 1, 1, 1)
            GameTooltip:Show()
        end)
        g:SetScript("OnLeave", function(self) self:SetAlpha(0.7); GameTooltip:Hide() end)
        g:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            local b = Movers:Bounds(key)
            if not b then return end
            PushUndo()
            Select(key)
            local s = UIParent:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local start = { x = cx / s, y = cy / s, l = b.l, t = b.t, w = b.w, h = b.h }
            self:SetScript("OnUpdate", function(grip)
                if not IsMouseButtonDown("LeftButton") then
                    grip:SetScript("OnUpdate", nil)
                    RefreshAll()
                    return
                end
                local x, y = GetCursorPosition()
                x, y = x / s, y / s
                local one = EV.Pixel:One(UIParent)
                local w = math.max(one * 8, start.w + (x - start.x))
                local hh = math.max(one * 8, start.h + (start.y - y))
                w, hh = math.floor(w / one + 0.5) * one, math.floor(hh / one + 0.5) * one
                e.setSize(w, hh)
                -- The element may clamp; keep the corner by its real size.
                local rw, rh = Movers:Size(key)
                local ux, uy = UIParent:GetCenter()
                Movers:SetOffset(key, start.l + rw / 2 - ux, start.t - rh / 2 - uy)
                PaintHandles()
                EM:RefreshInspector()
            end)
        end)
        g:SetScript("OnMouseUp", function(self)
            self:SetScript("OnUpdate", nil)
            RefreshAll()
        end)
        h.grip = g
    end
    handles[key] = h
    return h
end

local function SyncHandles()
    -- Smaller frames sit above bigger ones so they're always grabbable.
    local list = {}
    for _, key in ipairs(Movers:Keys()) do
        if not handles[key] then CreateHandle(key) end
        local h = handles[key]
        h:SetShown(Visible(key))
        if h:IsShown() then list[#list + 1] = key end
    end
    table.sort(list, function(a, b)
        local aw, ah = Movers:Size(a); local bw, bh = Movers:Size(b)
        return aw * ah > bw * bh
    end)
    for i, key in ipairs(list) do handles[key]:SetFrameLevel(root:GetFrameLevel() + 5 + i) end
end

--------------------------------------------------------------------------------
--  Inspector
--------------------------------------------------------------------------------
local SIDE_LIST = {
    { value = "TOP", text = L["Above"] }, { value = "BOTTOM", text = L["Below"] },
    { value = "LEFT", text = L["Left of"] }, { value = "RIGHT", text = L["Right of"] },
}
local function AlignList(side)
    if side == "LEFT" or side == "RIGHT" then
        return { { value = "START", text = L["Top edges"] }, { value = "CENTER", text = L["Middles"] },
                 { value = "END", text = L["Bottom edges"] } }
    end
    return { { value = "START", text = L["Left edges"] }, { value = "CENTER", text = L["Centres"] },
             { value = "END", text = L["Right edges"] } }
end

local function Primary() return selOrder[#selOrder] end

local function ElementList(exclude, includeNone, noneText, resizableOnly)
    local list = {}
    if includeNone then list[1] = { value = false, text = noneText or L["None"] } end
    for _, k in ipairs(Movers:Keys()) do
        local e = Movers:Get(k)
        if not exclude[k] and not (e.isDisabled and e.isDisabled()) then
            list[#list + 1] = { value = k, text = e.label .. (e.group and ("  |cff808080" .. e.group .. "|r") or "") }
        end
    end
    return list
end

local function NumberBox(parent, label, width, onCommit)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(width, 44)
    local l = Txt(holder, 11, "textDisabled", true)
    l:SetPoint("TOPLEFT", 0, 0)
    l:SetText(label)
    local box = W.Input(holder, width, "", function(text)
        local n = tonumber(text)
        if n then onCommit(n) end
        RefreshAll()
    end)
    box:SetPoint("BOTTOMLEFT", 0, 0)
    box:SetJustifyH("CENTER")
    holder.box = box
    function holder:SetValue(v)
        if not box:HasFocus() then box:SetText(v and tostring(v) or "") end
    end
    return holder
end

local function Label(parent, text)
    local fs = Txt(parent, 11, "textDisabled", true)
    fs:SetText(text:upper())
    return fs
end

local function BuildInspector()
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(300, 560)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -96)
    f:SetFrameLevel(root:GetFrameLevel() + 300)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    PanelBg(f)
    T.Shadow(f, 8)

    f.title = Txt(f, 18, "text", true)
    f.title:SetPoint("TOPLEFT", 18, -16)
    f.title:SetPoint("RIGHT", -18, 0)
    f.subtitle = Txt(f, 12, "textMuted")
    f.subtitle:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)

    -- Single selection controls
    local single = CreateFrame("Frame", nil, f)
    single:SetPoint("TOPLEFT", 18, -62)
    single:SetPoint("BOTTOMRIGHT", -18, 14)
    f.single = single

    local posL = Label(single, L["Position (pixels from centre)"])
    posL:SetPoint("TOPLEFT", 0, 0)
    f.x = NumberBox(single, "X", 124, function(n) PushUndo(); local _, y = Movers:GetOffsetPx(Primary()); Movers:SetOffsetPx(Primary(), n, y) end)
    f.x:SetPoint("TOPLEFT", 0, -16)
    f.y = NumberBox(single, "Y", 124, function(n) PushUndo(); local x = Movers:GetOffsetPx(Primary()); Movers:SetOffsetPx(Primary(), x, n) end)
    f.y:SetPoint("TOPLEFT", 140, -16)

    f.centreH = W.Button(single, L["Centre horizontally"], 124, function()
        PushUndo(); local _, y = Movers:GetOffset(Primary()); Movers:SetOffset(Primary(), 0, y); RefreshAll()
    end)
    f.centreH:SetPoint("TOPLEFT", 0, -70)
    f.centreV = W.Button(single, L["Centre vertically"], 124, function()
        PushUndo(); local x = Movers:GetOffset(Primary()); Movers:SetOffset(Primary(), x, 0); RefreshAll()
    end)
    f.centreV:SetPoint("TOPLEFT", 140, -70)

    local sizeL = Label(single, L["Size (pixels)"])
    sizeL:SetPoint("TOPLEFT", 0, -114)
    f.sizeLabel = sizeL
    local function SetSizePx(wpx, hpx)
        local e = Movers:Get(Primary())
        if not e or not e.setSize then return end
        PushUndo()
        e.setSize(wpx and EV.Pixel:FromPixels(wpx), hpx and EV.Pixel:FromPixels(hpx))
    end
    f.w = NumberBox(single, "W", 124, function(n) SetSizePx(n, nil) end)
    f.w:SetPoint("TOPLEFT", 0, -130)
    f.h = NumberBox(single, "H", 124, function(n) SetSizePx(nil, n) end)
    f.h:SetPoint("TOPLEFT", 140, -130)

    local anchorL = Label(single, L["Anchor"])
    anchorL:SetPoint("TOPLEFT", 0, -186)
    f.anchorTarget = W.Dropdown(single, 208, function()
        local key = Primary()
        if not key then return {} end
        local ex = { [key] = true }
        Movers:Descendants(key, ex)
        return ElementList(ex, true, L["Not anchored"])
    end, function()
        local a = Primary() and Movers:GetAnchor(Primary()); return a and a.target or false
    end, function(v)
        PushUndo()
        if v then
            local a = Movers:GetAnchor(Primary())
            Movers:SetAnchor(Primary(), v, a and a.side or "BOTTOM", a and a.align or "CENTER")
        else
            Movers:ClearAnchor(Primary())
        end
        RefreshAll()
    end)
    f.anchorTarget:SetPoint("TOPLEFT", 0, -204)
    f.anchorPick = W.Button(single, L["Pick"], 56, function()
        pick = { kind = "anchor", key = Primary() }
        EV:Print(L["Click the frame to anchor to. Esc cancels."])
        RefreshAll()
    end)
    f.anchorPick:SetPoint("LEFT", f.anchorTarget, "RIGHT", 8, 0)

    local function AnchorSet(field)
        return function(v)
            local a = Primary() and Movers:GetAnchor(Primary())
            if not a then return end
            PushUndo()
            Movers:SetAnchor(Primary(), a.target, field == "side" and v or a.side, field == "align" and v or a.align)
            RefreshAll()
        end
    end
    f.anchorSide = W.Dropdown(single, 124, SIDE_LIST,
        function() local a = Primary() and Movers:GetAnchor(Primary()); return a and a.side or "BOTTOM" end, AnchorSet("side"))
    f.anchorSide:SetPoint("TOPLEFT", 0, -240)
    f.anchorAlign = W.Dropdown(single, 124, function()
            local a = Primary() and Movers:GetAnchor(Primary()); return AlignList(a and a.side or "BOTTOM")
        end,
        function() local a = Primary() and Movers:GetAnchor(Primary()); return a and a.align or "CENTER" end, AnchorSet("align"))
    f.anchorAlign:SetPoint("TOPLEFT", 140, -240)
    f.anchorHint = Txt(single, 11, "textDisabled")
    f.anchorHint:SetPoint("TOPLEFT", 0, -274)
    f.anchorHint:SetWidth(264)
    f.anchorHint:SetWordWrap(true)
    f.anchorHint:SetText(L["Anchored frames follow their target. Drag or nudge to set the gap."])

    local matchL = Label(single, L["Match size of"])
    matchL:SetPoint("TOPLEFT", 0, -312)
    f.matchLabel = matchL
    local function MatchDD(dim)
        return W.Dropdown(single, 124, function()
            local key = Primary()
            if not key then return {} end
            local ex = { [key] = true }
            -- no loops: skip anything already matching us on this dimension
            for k, m in pairs(EV.DB:GetCore().matches) do if m[dim] == key then ex[k] = true end end
            return ElementList(ex, true, dim == "w" and L["Own width"] or L["Own height"])
        end, function()
            local m = Primary() and Movers:GetMatch(Primary()); return m and m[dim] or false
        end, function(v)
            PushUndo(); Movers:SetMatch(Primary(), dim, v or nil); RefreshAll()
        end)
    end
    f.matchW = MatchDD("w"); f.matchW:SetPoint("TOPLEFT", 0, -330)
    f.matchH = MatchDD("h"); f.matchH:SetPoint("TOPLEFT", 140, -330)

    f.reset = W.ConfirmButton(single, L["Reset"], 124, function()
        PushUndo()
        local key = Primary()
        Movers:Reset(key)
        Movers:SetMatch(key, "w", nil); Movers:SetMatch(key, "h", nil)
        RefreshAll()
    end)
    f.reset:SetPoint("TOPLEFT", 0, -380)
    f.settings = W.Button(single, L["Frame settings"], 124, function()
        local e = Movers:Get(Primary())
        if e and e.page then
            EM:Exit(true)
            EV:OpenOptions()
            if EV.Options.ShowPage then EV.Options:ShowPage(e.page, e.tab) end
        end
    end)
    f.settings:SetPoint("TOPLEFT", 140, -380)

    -- Multi selection controls
    local multi = CreateFrame("Frame", nil, f)
    multi:SetPoint("TOPLEFT", 18, -62)
    multi:SetPoint("BOTTOMRIGHT", -18, 14)
    f.multi = multi
    local alignL = Label(multi, L["Align to the last one picked"])
    alignL:SetPoint("TOPLEFT", 0, 0)

    local function AlignEdge(edge)
        return function()
            local ref = Movers:Bounds(Primary())
            if not ref then return end
            PushUndo()
            local ux, uy = UIParent:GetCenter()
            for _, k in ipairs(SelectionByDepth()) do
                if k ~= Primary() then
                    local b = Movers:Bounds(k)
                    local x, y = Movers:GetOffset(k)
                    if b then
                        if edge == "l" then x = x + (ref.l - b.l)
                        elseif edge == "cx" then x = x + (ref.cx - b.cx)
                        elseif edge == "r" then x = x + (ref.r - b.r)
                        elseif edge == "t" then y = y + (ref.t - b.t)
                        elseif edge == "cy" then y = y + (ref.cy - b.cy)
                        elseif edge == "b" then y = y + (ref.b - b.b) end
                        Movers:SetOffset(k, x, y)
                    end
                end
            end
            RefreshAll()
        end
    end
    local aligns = {
        { L["Lefts"], "l" }, { L["Centres"], "cx" }, { L["Rights"], "r" },
        { L["Tops"], "t" }, { L["Middles"], "cy" }, { L["Bottoms"], "b" },
    }
    for i, a in ipairs(aligns) do
        local b = W.Button(multi, a[1], 82, AlignEdge(a[2]))
        b:SetPoint("TOPLEFT", ((i - 1) % 3) * 91, -18 - floor((i - 1) / 3) * 38)
    end

    local distL = Label(multi, L["Spread evenly"])
    distL:SetPoint("TOPLEFT", 0, -106)
    local function Distribute(axis)
        return function()
            if #selOrder < 3 then EV:Print(L["Pick at least three frames to spread."]); return end
            PushUndo()
            local list = {}
            for _, k in ipairs(selOrder) do local b = Movers:Bounds(k); if b then list[#list + 1] = { k = k, b = b } end end
            local lo, hi = axis == "x" and "l" or "b", axis == "x" and "r" or "t"
            table.sort(list, function(p, q) return p.b[lo] < q.b[lo] end)
            local total = 0
            for _, it in ipairs(list) do total = total + (it.b[hi] - it.b[lo]) end
            local span = list[#list].b[hi] - list[1].b[lo]
            local gap = (span - total) / (#list - 1)
            local cursor = list[1].b[hi]
            for i = 2, #list - 1 do
                local it = list[i]
                local x, y = Movers:GetOffset(it.k)
                local shift = (cursor + gap) - it.b[lo]
                if axis == "x" then x = x + shift else y = y + shift end
                Movers:SetOffset(it.k, x, y)
                cursor = cursor + gap + (it.b[hi] - it.b[lo])
            end
            RefreshAll()
        end
    end
    W.Button(multi, L["Horizontally"], 124, Distribute("x")):SetPoint("TOPLEFT", 0, -124)
    W.Button(multi, L["Vertically"], 124, Distribute("y")):SetPoint("TOPLEFT", 140, -124)

    local grpL = Label(multi, L["Group"])
    grpL:SetPoint("TOPLEFT", 0, -168)
    W.Button(multi, L["Centre horizontally"], 264, function()
        local l, r
        for _, k in ipairs(selOrder) do
            local b = Movers:Bounds(k)
            if b then l = l and min(l, b.l) or b.l; r = r and max(r, b.r) or b.r end
        end
        if not l then return end
        PushUndo()
        local ux = UIParent:GetCenter()
        MoveSelectionBy(ux - (l + r) / 2, 0)
        RefreshAll()
    end):SetPoint("TOPLEFT", 0, -186)
    local hint = Txt(multi, 11, "textDisabled")
    hint:SetPoint("TOPLEFT", 0, -226)
    hint:SetWidth(264)
    hint:SetWordWrap(true)
    hint:SetText(L["Drag or use the arrow keys to move the whole selection. Ctrl-click a frame to add or remove it."])

    return f
end

function EM:RefreshInspector()
    if not inspector then return end
    local n = #selOrder
    if n == 0 then inspector:Hide(); return end
    inspector:Show()
    if n > 1 then
        inspector.title:SetText(("%d %s"):format(n, L["frames selected"]))
        inspector.subtitle:SetText(L["Moving together"])
        inspector.single:Hide(); inspector.multi:Show()
        inspector:SetHeight(330)
        return
    end
    inspector.single:Show(); inspector.multi:Hide()
    local key = Primary()
    local e = Movers:Get(key)
    inspector.title:SetText(e.label)
    inspector.subtitle:SetText(e.group or "")
    local px, py = Movers:GetOffsetPx(key)
    inspector.x:SetValue(px); inspector.y:SetValue(py)

    local resizable = e.setSize ~= nil
    local w, h = Movers:Size(key)
    inspector.w:SetValue(EV.Pixel:ToPixels(w)); inspector.h:SetValue(EV.Pixel:ToPixels(h))
    for _, c in ipairs({ inspector.w, inspector.h }) do c.box:SetDisabled(not resizable) end
    inspector.matchW:SetDisabled(not resizable); inspector.matchH:SetDisabled(not resizable)

    local a = Movers:GetAnchor(key)
    inspector.anchorTarget:Refresh()
    inspector.anchorSide:Refresh(); inspector.anchorAlign:Refresh()
    inspector.anchorSide:SetDisabled(not a); inspector.anchorAlign:SetDisabled(not a)
    inspector.matchW:Refresh(); inspector.matchH:Refresh()
    inspector.settings:SetDisabled(not e.page)
    inspector:SetHeight(440)
end

--------------------------------------------------------------------------------
--  Top bar
--------------------------------------------------------------------------------
local function BuildTopBar()
    local bar = CreateFrame("Frame", nil, root)
    bar:SetSize(900, 52)
    bar:SetPoint("TOP", UIParent, "TOP", 0, -16)
    bar:SetFrameLevel(root:GetFrameLevel() + 300)
    bar:EnableMouse(true)
    PanelBg(bar)
    T.Shadow(bar, 8)
    local accent = T.Fill(bar, "ARTWORK", "accent")
    T.OnTheme(function() accent:SetColorTexture(T.RGBA("accent")) end)
    accent:SetPoint("TOPLEFT"); accent:SetPoint("TOPRIGHT"); accent:SetHeight(2)

    local title = Txt(bar, 17, "text", true)
    title:SetPoint("LEFT", 18, 0)
    title:SetText(L["Edit Mode"])

    local x = 150
    local function Toggle(label, get, cycle)
        local b = W.Button(bar, "", 110, function(self)
            cycle(); self:SetText(label .. ": " .. get()); EM:ApplyViewSettings()
        end, "ghost")
        b:SetPoint("LEFT", x, 0)
        b:SetText(label .. ": " .. get())
        x = x + 116
        return b
    end
    local s = Settings
    local GRID_NEXT = { off = "dim", dim = "bright", bright = "off" }
    local NAMES = { off = L["Off"], dim = L["Dim"], bright = L["Bright"] }
    bar.grid = Toggle(L["Grid"], function() return NAMES[s().grid] end, function() s().grid = GRID_NEXT[s().grid] end)
    bar.snap = Toggle(L["Snap"], function() return s().snap and L["On"] or L["Off"] end, function() s().snap = not s().snap end)
    bar.coords = Toggle(L["Coords"], function() return s().coords and L["On"] or L["Off"] end, function() s().coords = not s().coords end)
    bar.dim = Toggle(L["Dim"], function() return s().dim and L["On"] or L["Off"] end, function() s().dim = not s().dim end)

    local save = W.Button(bar, L["Save & Exit"], 120, function() EM:Save() end, "accent")
    save:SetPoint("RIGHT", -12, 0)
    local discard = W.Button(bar, L["Discard"], 96, function() EM:Discard() end)
    discard:SetPoint("RIGHT", save, "LEFT", -8, 0)
    local undoBtn = W.Button(bar, L["Undo"], 72, function() EM:Undo() end)
    undoBtn:SetPoint("RIGHT", discard, "LEFT", -8, 0)
    bar.undo = undoBtn

    local help = Txt(root, 12, "textMuted", false, "CENTER")
    help:SetPoint("TOP", bar, "BOTTOM", 0, -8)
    help:SetText(L["Click to select, Ctrl-click to add  -  Drag to move (Shift: one axis, Alt: no snap)  -  Arrows nudge 1px, Shift 10px  -  Right-click for settings  -  Ctrl+Z undo"])
    return bar
end

--------------------------------------------------------------------------------
--  Save / discard / confirm
--------------------------------------------------------------------------------
local function BuildConfirm()
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(380, 150)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameLevel(root:GetFrameLevel() + 400)
    f:EnableMouse(true)
    PanelBg(f)
    T.Shadow(f, 10)
    local t = Txt(f, 17, "text", true)
    t:SetPoint("TOPLEFT", 20, -18)
    t:SetText(L["Keep your layout changes?"])
    local d = Txt(f, 13, "textMuted")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
    d:SetText(L["You moved or resized frames in this session."])
    local save = W.Button(f, L["Save"], 100, function() f:Hide(); EM:Save() end, "accent")
    save:SetPoint("BOTTOMRIGHT", -16, 16)
    local discard = W.Button(f, L["Discard"], 100, function() f:Hide(); EM:Discard() end)
    discard:SetPoint("RIGHT", save, "LEFT", -8, 0)
    local back = W.Button(f, L["Keep editing"], 110, function() f:Hide() end, "ghost")
    back:SetPoint("RIGHT", discard, "LEFT", -8, 0)
    f:Hide()
    return f
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
        elseif pick then pick = nil; RefreshAll()
        elseif #selOrder > 0 then ClearSelection(); RefreshAll()
        else EM:RequestExit() end
    elseif ARROWS[key] and #selOrder > 0 and not GetCurrentKeyBoardFocus() then
        handled = true
        local step = (IsShiftKeyDown() and 10 or 1) * One()
        PushUndoThrottled()
        MoveSelectionBy(ARROWS[key][1] * step, ARROWS[key][2] * step)
        RefreshAll()
    elseif key == "Z" and IsControlKeyDown() and not GetCurrentKeyBoardFocus() then
        handled = true
        EM:Undo()
    end
    if not InCombatLockdown() then self:SetPropagateKeyboardInput(not handled) end
end

--------------------------------------------------------------------------------
--  Build / enter / exit
--------------------------------------------------------------------------------
function RefreshAll()
    SyncHandles()
    PaintHandles()
    EM:RefreshInspector()
    if topBar then topBar.undo:SetDisabled(#undo == 0) end
end
EM.RefreshAll = function() RefreshAll() end

function EM:ApplyViewSettings()
    dim:SetShown(Settings().dim)
    BuildGrid()
    RefreshAll()
end

local function Build()
    root = CreateFrame("Frame", "EvermoreUIEditMode", UIParent)
    root:SetAllPoints()
    root:SetFrameStrata("DIALOG")
    root:EnableMouse(true)
    root:EnableKeyboard(true)
    root:SetScript("OnKeyDown", OnKeyDown)
    root:SetPropagateKeyboardInput(true)
    root:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and not pick and not IsControlKeyDown() then ClearSelection(); RefreshAll() end
    end)
    root:Hide()

    -- A plain black scrim over the game world (not a theme surface).
    dim = T.Solid(root, "BACKGROUND", 0, 0, 0, 0.35, -8)
    dim:SetAllPoints()
    gridFrame = CreateFrame("Frame", nil, root)
    gridFrame:SetAllPoints()
    -- Guides sit above the handles.
    local guideHost = CreateFrame("Frame", nil, root)
    guideHost:SetAllPoints()
    guideHost:SetFrameLevel(root:GetFrameLevel() + 250)
    guideX = T.Fill(guideHost, "OVERLAY", "accent", 0.9, 7); guideX:Hide()
    guideY = T.Fill(guideHost, "OVERLAY", "accent", 0.9, 7); guideY:Hide()
    T.OnTheme(function()
        guideX:SetColorTexture(T.RGBA("accent", 0.9))
        guideY:SetColorTexture(T.RGBA("accent", 0.9))
    end)

    topBar = BuildTopBar()
    inspector = BuildInspector()
    confirm = BuildConfirm()

    EV.Core_EditModeBuilt = true
end

function EM:IsActive() return active end

function EM:Enter()
    if InCombatLockdown() then EV:Print(L["Edit mode is available out of combat."]); return end
    if active then return end
    if not root then Build() end
    active, suspended = true, false
    snapshot, dirty = Movers:Snapshot(), false
    wipe(undo); wipe(hiddenHandles); ClearSelection(); pick = nil
    local opt = EV.Options and EV.Options.Frame and EV.Options:Frame()
    reopenOptions = opt and opt:IsShown() or false
    if opt then opt:Hide() end
    root:Show()
    EV:SendMessage("EV_UNLOCK")
    self:ApplyViewSettings()
end

function EM:Exit(noReopen)
    if not active then return end
    active = false
    root:Hide()
    if confirm then confirm:Hide() end
    GameTooltip:Hide()
    ClearSelection(); pick = nil; drag = nil
    root:SetScript("OnUpdate", nil)
    EV:SendMessage("EV_LOCK")
    if reopenOptions and not noReopen then
        reopenOptions = false
        EV:OpenOptions()
    end
end

function EM:Save()
    snapshot, dirty = nil, false
    EV:Print(L["Layout saved."])
    self:Exit()
end

function EM:Discard()
    if snapshot then Movers:Restore(snapshot) end
    snapshot, dirty = nil, false
    self:Exit()
end

function EM:RequestExit()
    if dirty then confirm:Show() else self:Save() end
end

function EM:Undo()
    local snap = table.remove(undo)
    if not snap then return end
    Movers:Restore(snap)
    RefreshAll()
end

-- Combat: step aside, keep the session, come back after.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if not active then return end
    if event == "PLAYER_REGEN_DISABLED" then
        suspended = true
        drag = nil
        root:SetScript("OnUpdate", nil)
        root:Hide()
        EV:Print(L["Edit mode paused for combat."])
    elseif suspended then
        suspended = false
        root:Show()
        RefreshAll()
    end
end)

-- Keep handles current when frames register or the scale changes.
local listener = EV:NewModule("EditMode")
listener.internal = true
listener:RegisterMessage("EV_MOVER_REGISTERED", function() if active and not drag then RefreshAll() end end)
listener:RegisterMessage("EV_PIXEL_CHANGED", function() if active then BuildGrid(); RefreshAll() end end)
