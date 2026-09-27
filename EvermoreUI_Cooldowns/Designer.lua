if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Designer.lua
--  The Cooldown Manager's surface for the designer: a grid, not a canvas.
--  Each of our bars is a row of the icons it shows, in order, with a tray
--  for the ones you've hidden. Drag an icon along its row to reorder it, to
--  the other cooldown row to move it there, or to the tray to hide it.
--
--  Everything written is our own arrangement (Cooldowns.lua, "Your
--  arrangement"), per class and spec. Which spells are tracked at all is
--  Blizzard's choice, in its Cooldown Manager settings; the button here opens
--  them.
--
--  Click a row for that bar's settings, a cooldown for its linked timer.
--  The settings themselves are in Settings.lua.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule and EvermoreUI.Designers) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local W = EV.UI
local M = ns.module

local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local issecret = issecretvalue or function() return false end

local ICON, GAP, PAD = 36, 6, 14
local HIDDEN = "hidden"

local grid                   -- our frame on the designer's stage
local rows = {}              -- row key -> row frame
local tiles = {}             -- pool of icon tiles
local dragging               -- { tile, item, from }
local DragUpdate, Drop       -- below
local Elements               -- below

local function Texture(f)
    local info = f.cooldownInfo
    if type(info) == "table" then
        for _, id in ipairs({ info.overrideSpellID, info.spellID }) do
            if type(id) == "number" and not issecret(id) and C_Spell and C_Spell.GetSpellTexture then
                local ok, tex = pcall(C_Spell.GetSpellTexture, id)
                if ok and tex and not issecret(tex) then return tex end
            end
        end
    end
    local icon = f.Icon and f.Icon.GetTexture and f.Icon:GetTexture()
    if icon and not issecret(icon) then return icon end
    return 134400
end

local function Name(f)
    if f.evLabel then return f.evLabel end
    local info = f.cooldownInfo
    if type(info) ~= "table" then return nil end
    return M.SpellName(info.overrideSpellID) or M.SpellName(info.spellID)
end

--- The spell a linked timer is kept against (plain, or nil).
local function SpellOf(f)
    local info = f.cooldownInfo
    local id = type(info) == "table" and info.spellID
    if type(id) == "number" and not issecret(id) then return id end
end

local function BarKey(key) return "bar:" .. key end
local function IconKey(id) return "spell:" .. id end

--- What picking this tile opens: a cooldown's own timer, or a buff's bar.
local function PickFor(item)
    if item.f.evCustom then return "custom:" .. item.f.evUID end
    if item.group == "cd" and SpellOf(item.f) then return IconKey(item.id) end
    return BarKey(item.native)
end

--- What each row holds right now: bars in your order, then the hidden tray.
local function Contents()
    local out = {}
    local a = M:Arrangement(false)
    for _, def in ipairs(M.BARS) do
        local list = {}
        for _, f in ipairs(M.Members(def, true, true)) do
            local id = M.IdOf(f)
            if id then list[#list + 1] = { id = id, f = f, group = def.buff and "buff" or "cd", native = def.key } end
        end
        out[def.key] = list
    end
    local hidden = {}
    for _, def in ipairs(M.BARS) do
        for _, f in ipairs(M.Items(def, true)) do
            local id = M.IdOf(f)
            if id and a and a.hidden[id] then
                hidden[#hidden + 1] = { id = id, f = f, group = def.buff and "buff" or "cd", native = def.key }
            end
        end
    end
    for _, f in ipairs(ns.CustomFrames and ns.CustomFrames() or {}) do
        if a and a.hidden[f.evKey] then
            hidden[#hidden + 1] = { id = f.evKey, f = f, group = "cd", native = f.evHome }
        end
    end
    out[HIDDEN] = hidden
    return out
end

--------------------------------------------------------------------------------
--  Writing the arrangement
--------------------------------------------------------------------------------
--- Put item `it` into row `to` at position `index` (1-based among the others).
local function Move(it, to, index)
    local a = M:Arrangement(true)
    local now = Contents()
    if to == HIDDEN then
        a.hidden[it.id] = true
    else
        a.hidden[it.id] = nil
        -- Back on its own viewer's bar: forget the move rather than store it.
        if it.group == "cd" then a.bar[it.id] = (to ~= it.native) and to or nil end
        local list = {}
        for _, x in ipairs(now[to] or {}) do if x.id ~= it.id then list[#list + 1] = x.id end end
        index = max(1, min(index, #list + 1))
        table.insert(list, index, it.id)
        for i, id in ipairs(list) do a.order[id] = i end
    end
    EV.DesignerUI:Commit()
end

--------------------------------------------------------------------------------
--  Drawing
--------------------------------------------------------------------------------
local function PaintTile(t)
    local on = t.item and EV.DesignerUI:Selected() == PickFor(t.item) and t.item.group == "cd"
    T.SetBorderToken(t, (on or t:IsMouseOver()) and "accent" or "border")
end

local function Tile(i)
    local t = tiles[i]
    if t then return t end
    t = CreateFrame("Button", nil, grid)
    t:SetSize(ICON, ICON)
    t.back = t:CreateTexture(nil, "BACKGROUND")
    t.back:SetAllPoints()
    t.back:SetColorTexture(0, 0, 0, 1)
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOPLEFT", 1, -1)
    t.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    T.TokenBorder(t, "border")
    t:RegisterForClicks("AnyUp")
    t:SetScript("OnEnter", function(self)
        if dragging then return end
        T.SetBorderToken(self, "accent")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.name or L["Cooldown"], 1, 1, 1)
        if self.item.f.evCustom then
            GameTooltip:AddLine(self.item.f.evWhat or L["Your own icon"], 0.83, 0.57, 0.31)
        end
        GameTooltip:AddLine(self.item.group == "buff" and L["Drag along the row to reorder, or to the tray to hide it."]
            or L["Drag to reorder, to the other cooldown row to move it there, or to the tray to hide it. Click for its linked timer."],
            0.75, 0.78, 0.82, true)
        GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function(self) GameTooltip:Hide(); PaintTile(self) end)
    t:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        EV.DesignerUI:Select(PickFor(self.item))
        dragging = { tile = self, item = self.item, from = self.row }
        grid.ghost.icon:SetTexture(self.icon:GetTexture())
        grid.ghost:Show()
        self:SetAlpha(0.3)
        grid:SetScript("OnUpdate", function() DragUpdate() end)
    end)
    t:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and dragging then Drop() end
    end)
    tiles[i] = t
    return t
end

local function Row(key, label)
    local r = rows[key]
    if r then return r end
    r = CreateFrame("Frame", nil, grid)
    r.key = key
    -- Clicking the row itself (not an icon) picks its bar.
    r:EnableMouse(true)
    r:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" and key ~= HIDDEN then EV.DesignerUI:Select(BarKey(key)) end
    end)
    r.bg = T.Fill(r, "BACKGROUND", "surfaceSunk", 0.6)
    r.bg:SetAllPoints()
    T.TokenBorder(r, "border")
    r.label = T.Text(r, 12, "textMuted", true)
    r.label:SetPoint("BOTTOMLEFT", r, "TOPLEFT", 2, 4)
    r.label:SetText(label)
    r.empty = T.Text(r, 12, "textDisabled")
    r.empty:SetPoint("LEFT", PAD, 0)
    rows[key] = r
    return r
end

local function Build(stage)
    grid = CreateFrame("Frame", nil, stage)
    grid:SetAllPoints()
    grid:SetFrameLevel(stage:GetFrameLevel() + 5)
    grid.ghost = CreateFrame("Frame", nil, grid)
    grid.ghost:SetSize(ICON, ICON)
    grid.ghost:SetFrameLevel(grid:GetFrameLevel() + 50)
    grid.ghost.icon = grid.ghost:CreateTexture(nil, "OVERLAY")
    grid.ghost.icon:SetAllPoints()
    grid.ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    grid.ghost:SetAlpha(0.85)
    grid.ghost:Hide()
    -- Hidden mid-drag (combat, or the window closing): drop nothing. An
    -- OnUpdate left running would fire the drop wherever the cursor happened
    -- to be when the grid came back.
    grid:SetScript("OnHide", function()
        if dragging then
            dragging.tile:SetAlpha(1)
            dragging = nil
        end
        grid:SetScript("OnUpdate", nil)
        grid.ghost:Hide()
        grid.marker:Hide()
    end)
    grid.marker = grid:CreateTexture(nil, "OVERLAY", nil, 7)
    grid.marker:SetColorTexture(T.RGBA("accent", 1))
    grid.marker:SetSize(3, ICON + 8)
    grid.marker:Hide()

    grid.problem = T.Text(grid, 13, "warning")
    grid.problem:SetPoint("TOPLEFT", PAD, -PAD)
    grid.problem:SetPoint("RIGHT", -PAD, 0)
    grid.problem:SetJustifyH("LEFT")
    grid.problem:SetWordWrap(true)

    grid.blizz = W.Button(grid, L["Choose tracked spells"], 170, function()
        if CooldownViewerSettings and CooldownViewerSettings.TogglePanel then
            pcall(CooldownViewerSettings.TogglePanel, CooldownViewerSettings)
        else
            EV:Print(L["The game's Cooldown Manager settings aren't available."])
        end
    end)
    grid.blizz:SetPoint("BOTTOMLEFT", PAD, PAD)
    grid.reset = W.ConfirmButton(grid, L["Back to the game's order"], 190, function()
        local all = M.db.arrange
        all[M.SpecKey()] = nil
        EV.DesignerUI:Commit()
    end)
    grid.reset:SetPoint("LEFT", grid.blizz, "RIGHT", 8, 0)
    grid.add = W.Button(grid, L["Add your own"], 130, function() EV.DesignerUI:Select("yours") end)
    grid.add:SetPoint("LEFT", grid.reset, "RIGHT", 8, 0)

    -- The picked bar's row and the picked cooldown carry the accent.
    function grid.Paint(sel)
        for key, r in pairs(rows) do
            T.SetBorderToken(r, (key ~= HIDDEN and sel == BarKey(key)) and "accent" or "border")
        end
        for _, t in ipairs(tiles) do if t:IsShown() then PaintTile(t) end end
    end
end

--- Lay the rows and tiles out from the arrangement as it is now.
local function Draw()
    local contents = Contents()
    local width = max(grid:GetWidth() or 0, 300) - PAD * 2
    local per = max(1, floor((width - PAD * 2 + GAP) / (ICON + GAP)))
    local y = -PAD - 22
    local n = 0
    local problem = M.Problem and M.Problem(M.BARS[1])
    grid.problem:SetText(problem or "")
    if problem then y = y - 36 end

    local order = {}
    for _, def in ipairs(M.BARS) do order[#order + 1] = { key = def.key, label = def.label } end
    order[#order + 1] = { key = HIDDEN, label = L["Hidden from our bars"] }

    for _, o in ipairs(order) do
        local r = Row(o.key, o.label)
        local list = contents[o.key] or {}
        local lines = max(1, math.ceil(#list / per))
        local h = lines * ICON + (lines - 1) * GAP + PAD
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", grid, "TOPLEFT", PAD, y)
        r:SetSize(width, h)
        r.slots = {}
        r.empty:SetText(#list == 0 and (o.key == HIDDEN and L["Nothing hidden. Drag an icon here to hide it."]
            or L["Empty. Drag icons here."]) or "")
        for i, it in ipairs(list) do
            n = n + 1
            local t = Tile(n)
            t.item, t.row, t.name = it, o.key, Name(it.f)
            t.icon:SetTexture(Texture(it.f))
            t.icon:SetDesaturated(o.key == HIDDEN or (it.f.evCustom and not it.f.evActive) or false)
            local col, line = (i - 1) % per, floor((i - 1) / per)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", r, "TOPLEFT", PAD / 2 + col * (ICON + GAP), -PAD / 2 - line * (ICON + GAP))
            t:SetFrameLevel(r:GetFrameLevel() + 2)
            t:SetAlpha(1)
            t:Show()
            r.slots[i] = t
        end
        y = y - h - 30
    end
    for i = n + 1, #tiles do tiles[i]:Hide() end
    grid.Paint(EV.DesignerUI:Selected())
end

--------------------------------------------------------------------------------
--  Drag and drop
--------------------------------------------------------------------------------
local function CursorIn(frame)
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale()
    return x / s, y / s
end

local function Inside(r, x, y)
    local l, rt, t, b = r:GetLeft(), r:GetRight(), r:GetTop(), r:GetBottom()
    return l and x >= l and x <= rt and y <= t + 12 and y >= b - 12
end

--- Where a drop at (x, y) lands: row key and index, or nil.
local function Target(x, y, d)
    for key, r in pairs(rows) do
        if r:IsShown() and Inside(r, x, y) then
            local it = d.item
            -- Buffs stay in their row (or the tray); cooldowns can't go there.
            if key ~= HIDDEN then
                local def
                for _, d in ipairs(M.BARS) do if d.key == key then def = d end end
                if not def or (def.buff and it.group ~= "buff") or (not def.buff and it.group == "buff") then
                    return nil
                end
            end
            -- Before the first tile whose centre is past the cursor on this
            -- line, reading left to right, top to bottom.
            local index = #r.slots + 1
            for i, t in ipairs(r.slots) do
                if t ~= d.tile then
                    local tl, tr, tt, tb = t:GetLeft(), t:GetRight(), t:GetTop(), t:GetBottom()
                    if tl and y <= tt + GAP / 2 and y >= tb - GAP / 2 and x < (tl + tr) / 2 then
                        index = i
                        break
                    elseif tl and y > tt + GAP / 2 then
                        index = i
                        break
                    end
                end
            end
            return key, index, r
        end
    end
end

DragUpdate = function()
    if not dragging then return end
    if not IsMouseButtonDown("LeftButton") then Drop() return end
    local x, y = CursorIn(grid)
    grid.ghost:ClearAllPoints()
    grid.ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * grid:GetEffectiveScale() / UIParent:GetEffectiveScale(),
                        y * grid:GetEffectiveScale() / UIParent:GetEffectiveScale())
    local key, index, r = Target(x, y, dragging)
    if key and r then
        local t = r.slots[index]
        grid.marker:ClearAllPoints()
        if t then
            grid.marker:SetPoint("RIGHT", t, "LEFT", -1, 0)
        elseif r.slots[#r.slots] then
            grid.marker:SetPoint("LEFT", r.slots[#r.slots], "RIGHT", 1, 0)
        else
            grid.marker:SetPoint("LEFT", r, "LEFT", PAD / 2, 0)
        end
        grid.marker:Show()
    else
        grid.marker:Hide()
    end
end

Drop = function()
    grid:SetScript("OnUpdate", nil)
    grid.ghost:Hide()
    grid.marker:Hide()
    local d = dragging
    dragging = nil
    if not d then return end
    d.tile:SetAlpha(1)
    local x, y = CursorIn(grid)
    local key, index = Target(x, y, d)
    if not key then return end
    -- Dropping a tile on its own spot is not a change.
    if key == d.from then
        local r = rows[key]
        local cur
        for i, t in ipairs(r.slots) do if t == d.tile then cur = i end end
        if cur and (index == cur or index == cur + 1) then return end
        if cur and index > cur then index = index - 1 end
    end
    Move(d.item, key, index)
end

--------------------------------------------------------------------------------
--  Elements: each bar, the timer list, and each cooldown (picked on the grid)
--------------------------------------------------------------------------------
function Elements()
    local list = {}
    for _, def in ipairs(M.BARS) do
        list[#list + 1] = {
            key = BarKey(def.key), label = def.label,
            sub = L["Everything about this bar. Where it sits on screen is edit mode."],
            Options = function(p) ns.BarSettings(p, def) end,
            Reset = function() ns.ResetBar(def) end,
        }
    end
    local function Rebuild(commit) EV.DesignerUI:RebuildInspector(commit) end
    list[#list + 1] = {
        key = "mine", label = L["Your buffs"],
        sub = L["The buffs you name, in a bar of their own. Where it sits on screen is edit mode."],
        Options = function(p) ns.MyBuffSettings(p, Rebuild) end,
        Reset = function() ns.ResetBar(ns.MINE) end,
    }
    list[#list + 1] = {
        key = "yours", label = L["Your own icons"],
        sub = L["Add trinkets, items and spells to your cooldown bars."],
        Options = function(p) ns.CustomSettings(p, Rebuild) end,
    }
    list[#list + 1] = {
        key = "timers", label = L["Linked timers"],
        Options = function(p) ns.TimerList(p, Rebuild) end,
    }
    for _, f in ipairs(ns.CustomFrames and ns.CustomFrames() or {}) do
        local frame = f
        list[#list + 1] = {
            key = "custom:" .. f.evUID, label = f.evLabel or L["Your own icon"], unlisted = true,
            sub = L["Drag it on the grid to move it or hide it."],
            Options = function(p)
                ns.CustomIconSettings(p, frame, function()
                    EV.DesignerUI:Select(nil)
                    EV.DesignerUI:Commit()
                end)
            end,
        }
    end
    local contents = Contents()
    local seen = {}
    for _, items in pairs(contents) do
        for _, it in ipairs(items) do
            local spell = it.group == "cd" and SpellOf(it.f)
            local key = spell and IconKey(it.id)
            if key and not seen[key] then
                seen[key] = true
                list[#list + 1] = {
                    key = key, label = Name(it.f) or L["Cooldown"], unlisted = true,
                    sub = L["Drag it on the grid to move it. Its bar's settings are in the list."],
                    Options = function(p) ns.IconTimer(p, spell) end,
                }
            end
        end
    end
    return list
end

--------------------------------------------------------------------------------
--  The surface
--------------------------------------------------------------------------------
EV.Designers:Register{
    key = "cooldowns", title = L["Cooldowns"], module = "Cooldowns", kind = "grid",
    page = "cooldowns",
    help = L["Drag icons to reorder them, move a cooldown between the Essential and Utility bars, or drop one in the tray to hide it. The order is saved for your class and spec. Click a row for its bar's settings, or a cooldown for its linked timer. Add your own adds trinkets, items and spells; Your buffs is a bar of the buffs you name."],
    note = L["Which spells are tracked is the game's choice: Choose tracked spells opens its settings."],
    Tabs = function() return { { value = "spec", text = L["This spec"] } } end,
    BuildGrid = function(stage)
        if not grid then Build(stage) end
        grid:SetParent(stage)
        grid:SetAllPoints()
        grid:Show()
        Draw()
        -- Sizes settle a frame after showing; draw again with them.
        C_Timer.After(0, function() if grid:IsShown() then Draw() end end)
    end,
    HideGrid = function() if grid then grid:Hide() end end,
    Paint = function(sel) if grid and grid:IsShown() then grid.Paint(sel) end end,
    Elements = function() return Elements() end,
    -- An untouched spec has no entry, and a restore to that state removes
    -- it again rather than leaving an empty one in your settings.
    -- Each snapshot remembers whose it is, so switching spec with the window
    -- open can't pour one spec's arrangement into another.
    -- Bars and timers go back into the tables they came from: the
    -- inspector's rows hold those tables, not copies.
    Snapshot = function()
        local a = M:Arrangement(false)
        return { spec = M.SpecKey(), data = a and EV.CopyTable(a) or nil,
                 bars = EV.CopyTable(M.db.bars), timers = EV.CopyTable(M:Timers()),
                 custom = EV.CopyTable(M:CustomList()), mine = EV.CopyTable(M:MyBuffs()) }
    end,
    Restore = function(_, snap)
        if not snap then return end
        M.db.arrange[snap.spec or M.SpecKey()] = snap.data and EV.CopyTable(snap.data) or nil
        if snap.bars then
            for key, saved in pairs(snap.bars) do
                local db = M.db.bars[key]
                if db then
                    wipe(db)
                    for k, v in pairs(saved) do db[k] = type(v) == "table" and EV.CopyTable(v) or v end
                end
            end
        end
        for field, fn in pairs({ timers = "Timers", custom = "CustomList", mine = "MyBuffs" }) do
            if snap[field] then
                local list = M[fn](M)
                wipe(list)
                for i, t in ipairs(snap[field]) do list[i] = EV.CopyTable(t) end
            end
        end
        if ns.SyncCustom then ns.SyncCustom() end
        M:Refresh()
    end,
    Apply = function() M:Refresh() end,
}
