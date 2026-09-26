if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Editor.lua
--  The bar editor on the Action Bars options page: a live copy of the bar
--  you picked, drawn from what the game has in its slots, that you edit in
--  place. Drag a spell from the book below (or from Blizzard's spellbook,
--  your bags or the macro window) onto a slot, drag slots to swap them,
--  right click to clear one, and click a slot then press a key to bind it.
--
--  Everything goes through the game's own cursor and action slots:
--  PickupAction / PlaceAction and C_SpellBook.PickupSpellBookItem, the same
--  calls Blizzard's buttons make when you drag on them. So the real bar
--  changes as you edit, there is no copy of your bars to fall out of step,
--  and the preview only ever shows what the slots hold. Moving actions is
--  out of combat only; the editor locks when combat starts.
--
--  Each preview slot maps to one real button, and the button's `action`
--  field is the slot it is showing now (page, form and stealth included).
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local W = EV.UI
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
-- The C_ActionBar spellings; the plain globals are only deprecation shims.
local AB = C_ActionBar or {}
local HasAction = AB.HasAction or HasAction
local GetActionTexture = AB.GetActionTexture or GetActionTexture

local E = {}
ns.Editor = E

local live = {}          -- editors currently built: editor -> true
local dragFrom           -- action slot a drag started from
local selected           -- slot frame waiting for a key

local function Locked() return InCombatLockdown() end

--------------------------------------------------------------------------------
--  Slots
--------------------------------------------------------------------------------
local function Deselect()
    local s = selected
    selected = nil
    if s then
        s:EnableKeyboard(false)
        T.SetBorderToken(s, "border")
        if s.editor then s.editor:Prompt() end
    end
end

local function Drop(slot)
    if Locked() then return end
    local action = slot.button and slot.button.action
    if type(action) ~= "number" then return end
    local from = dragFrom
    dragFrom = nil
    PlaceAction(action)
    -- A swap: what was here is on the cursor now; send it back to where the
    -- drag started, if that slot is empty.
    if from and from ~= action and GetCursorInfo() and not HasAction(from) then
        PlaceAction(from)
    end
end

local function SlotTip(s)
    local action = s.button and s.button.action
    GameTooltip:SetOwner(s, "ANCHOR_TOP")
    if type(action) == "number" and HasAction(action) then
        pcall(GameTooltip.SetAction, GameTooltip, action)
    else
        GameTooltip:SetText(L["Empty"])
    end
    GameTooltip:AddLine(L["Drag to move. Right click to clear. Click, then press a key to bind."], 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

local function NewSlot(editor)
    local s = CreateFrame("Button", nil, editor)
    s.editor = editor
    s.well = T.Fill(s, "BACKGROUND", "surfaceSunk", 0.9)
    s.well:SetAllPoints()
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1)
    s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.key = s:CreateFontString(nil, "OVERLAY")
    s.key:SetPoint("TOPRIGHT", -2, -3)
    s.key:SetJustifyH("RIGHT")
    s.num = s:CreateFontString(nil, "OVERLAY")
    s.num:SetPoint("BOTTOMLEFT", 3, 3)
    T.TokenBorder(s, "border")
    local hl = s:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(s.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)

    s:RegisterForDrag("LeftButton")
    s:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp", "Button4Up", "Button5Up")
    s:SetScript("OnDragStart", function(self)
        if Locked() then return end
        local a = self.button and self.button.action
        if type(a) == "number" and HasAction(a) then
            Deselect()
            PickupAction(a)
            dragFrom = a
        end
    end)
    s:SetScript("OnReceiveDrag", function(self) Drop(self) end)
    s:SetScript("OnClick", function(self, btn)
        if Locked() then return end
        local key = ns.Keybind.MOUSE[btn]
        if selected == self and key then
            ns.Keybind.Apply(self.button, key)
            return
        end
        if btn == "LeftButton" then
            if GetCursorInfo() then
                Deselect()
                Drop(self)
            elseif selected == self then
                Deselect()
            else
                Deselect()
                selected = self
                -- Keys are only listened for while the pointer is on the
                -- selected slot (OnEnter / OnLeave below), so a slot left
                -- selected can't catch keys you meant for something else.
                self:EnableKeyboard(self:IsMouseOver())
                T.SetBorderToken(self, "accent")
                editor:Prompt(self)
            end
        elseif btn == "RightButton" then
            if GetCursorInfo() then
                ClearCursor()
                dragFrom = nil
            else
                local a = self.button and self.button.action
                if type(a) == "number" and HasAction(a) then
                    PickupAction(a)
                    ClearCursor()
                end
            end
        end
    end)
    s:SetScript("OnKeyDown", function(self, key)
        if ns.Keybind.IGNORE[key] then return end
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        ns.Keybind.Apply(self.button, key)
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        if selected == self then
            ns.Keybind.Apply(self.button, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
        end
    end)
    s:EnableMouseWheel(true)
    s:SetScript("OnEnter", function(self)
        if selected == self and not Locked() then self:EnableKeyboard(true) end
        SlotTip(self)
    end)
    s:SetScript("OnLeave", function(self)
        self:EnableKeyboard(false)
        GameTooltip:Hide()
    end)
    return s
end

local function PaintSlot(s)
    local b = s.button
    local a = b and b.action
    local tex = type(a) == "number" and GetActionTexture(a) or nil
    s.icon:SetTexture(tex)
    s.icon:SetShown(tex ~= nil)
    local font = EV.Media:Fetch("font")
    local fs = max(9, floor(s:GetWidth() * 0.28))
    s.key:SetFont(font, fs, "OUTLINE")
    s.num:SetFont(font, max(8, fs - 2), "OUTLINE")
    s.key:SetText(b and ns.HotkeyText(b) or "")
    s.num:SetText(s.index)
    s.num:SetTextColor(T.RGBA("textMuted", tex and 0 or 0.8))
    s:SetAlpha(Locked() and 0.5 or 1)
end

--------------------------------------------------------------------------------
--  The bar
--------------------------------------------------------------------------------
--- A live, editable copy of one bar, drawn to the bar's own proportions:
--- buttons per row, button size, spacing and growth, scaled down to fit.
--- The box keeps the height it was built with (so the options page doesn't
--- jump while you drag a slider); the copy scales to fit inside it.
local PROMPT_H = 22

function E.Bar(parent, width, key)
    local def = ns.BY_KEY[key]
    local editor = CreateFrame("Frame", nil, parent)
    editor.key, editor.slots = key, {}

    -- Room for what the bar needs now at up to full size, and at least
    -- enough that a bar turned tall later still reads.
    local cfg = ns.Bar(key)
    local n = max(1, ns.ButtonCount(def, cfg))
    local per = max(1, min(n, cfg.perRow))
    local rows = ceil(n / per)
    local realW = per * cfg.size + (per - 1) * cfg.spacing
    local realH = rows * cfg.size + (rows - 1) * cfg.spacing
    local k = min(1, width / realW)
    local boxH = min(260, max(110, floor(realH * k + 0.5)))
    editor:SetSize(width, boxH + PROMPT_H + 6)
    editor.boxW, editor.boxH = width, boxH

    local prompt = T.Text(editor, "small", "textMuted")
    prompt:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, -(boxH + 8))
    prompt:SetPoint("RIGHT", editor, "RIGHT", 0, 0)
    prompt:SetJustifyH("CENTER")
    prompt:SetWordWrap(false)
    function editor:Prompt(slot)
        if Locked() then
            prompt:SetText(L["Out of combat only."])
        elseif slot then
            prompt:SetText((L["With the pointer on button %d, press a key to bind it. Escape clears it; click it again to stop."]):format(slot.index))
        else
            prompt:SetText(L["Drag spells on from the book below, your bags or the macro window."])
        end
    end

    --- Lay the copy out from the bar's settings as they are now.
    function editor:Relayout()
        local c = ns.Bar(self.key)
        local buttons = ns.Buttons(def)
        local count = max(1, ns.ButtonCount(def, c))
        local cols = max(1, min(count, c.perRow))
        local lines = ceil(count / cols)
        local rw = cols * c.size + (cols - 1) * c.spacing
        local rh = lines * c.size + (lines - 1) * c.spacing
        local f = min(1, self.boxW / rw, self.boxH / rh)
        local size, gap = max(8, floor(c.size * f)), floor(c.spacing * f + 0.5)
        local w = cols * size + (cols - 1) * gap
        local h = lines * size + (lines - 1) * gap
        local ox, oy = floor((self.boxW - w) / 2), floor((self.boxH - h) / 2)
        local left, up = c.growH == "LEFT", c.growV == "UP"
        for i = 1, count do
            local s = self.slots[i]
            if not s then
                s = NewSlot(self)
                self.slots[i] = s
            end
            s.index, s.button = i, buttons[i]
            s:SetSize(size, size)
            local r, col = floor((i - 1) / cols), (i - 1) % cols
            if left then col = cols - 1 - col end
            if up then r = lines - 1 - r end
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", self, "TOPLEFT", ox + col * (size + gap), -oy - r * (size + gap))
            s:Show()
        end
        for i = count + 1, #self.slots do
            local s = self.slots[i]
            if selected == s then Deselect() end
            s:Hide()
        end
        self.count = count
        self:Refresh()
    end

    function editor:Refresh()
        for i = 1, self.count or 0 do PaintSlot(self.slots[i]) end
        if selected and selected.editor ~= self then return end
        self:Prompt(selected)
    end
    editor:SetScript("OnShow", function(self) live[self] = true; self:Relayout() end)
    editor:SetScript("OnHide", function(self)
        live[self] = nil
        if selected and selected.editor == self then Deselect() end
    end)
    live[editor] = true
    editor:Relayout()
    return editor
end

--- The bar settings changed (options, edit mode, forms): redraw the copies.
function E.RelayoutAll()
    for f in pairs(live) do
        if f.Relayout and f:IsVisible() then f:Relayout() end
    end
end

--------------------------------------------------------------------------------
--  The book: your spells and macros, to drag onto a slot
--------------------------------------------------------------------------------
local BANK = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
local IT = Enum.SpellBookItemType or {}

local function LevelLearned(j)
    if not C_SpellBook.GetSpellBookItemLevelLearned then return nil end
    local ok, lvl = pcall(C_SpellBook.GetSpellBookItemLevelLearned, j, BANK)
    return ok and type(lvl) == "number" and lvl or nil
end

--- Known spells first, in book order, then the ones still to learn by the
--- level they arrive at. Unlearnt spells can't be picked up, so they show
--- greyed with their level and do nothing on click.
local function Spells()
    local out, future = {}, {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if line and not line.shouldHide and not line.offSpecID then
            for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local ok, item = pcall(C_SpellBook.GetSpellBookItemInfo, j, BANK)
                if ok and item and not item.isPassive and not item.isOffSpec then
                    local tip = function() pcall(GameTooltip.SetSpellBookItem, GameTooltip, j, BANK) end
                    if item.itemType == IT.Spell or item.itemType == IT.Flyout then
                        out[#out + 1] = {
                            name = item.name, sub = item.subName, icon = item.iconID, line = line.name,
                            tip = tip,
                            pickup = function() C_SpellBook.PickupSpellBookItem(j, BANK) end,
                        }
                    elseif IT.FutureSpell and item.itemType == IT.FutureSpell then
                        future[#future + 1] = {
                            name = item.name, sub = item.subName, icon = item.iconID, line = line.name,
                            tip = tip, future = true, level = LevelLearned(j), order = j,
                        }
                    end
                end
            end
        end
    end
    table.sort(future, function(a, b)
        if (a.level or 999) ~= (b.level or 999) then return (a.level or 999) < (b.level or 999) end
        return a.order < b.order
    end)
    for _, e in ipairs(future) do out[#out + 1] = e end
    return out
end

local function Macros()
    local out = {}
    if type(GetNumMacros) ~= "function" then return out end
    local general, char = GetNumMacros()
    local function add(i)
        local name, icon = GetMacroInfo(i)
        if name then
            out[#out + 1] = {
                name = name, icon = icon,
                tip = function() GameTooltip:SetText(name) end,
                pickup = function() PickupMacro(i) end,
            }
        end
    end
    for i = 1, general or 0 do add(i) end
    local base = MAX_ACCOUNT_MACROS or 120
    for i = 1, char or 0 do add(base + i) end
    return out
end

local SOURCES = {
    { value = "spells", text = L["Spells"] },
    { value = "macros", text = L["Macros"] },
}

--- The spell and macro grid, with a search box.
function E.Book(parent, width)
    local book = CreateFrame("Frame", nil, parent)
    local ICON, GAP = 34, 4
    local per = max(1, floor((width + GAP) / (ICON + GAP)))
    local state = { source = "spells", filter = "" }
    local pool = {}

    local src = W.Dropdown(book, 130, SOURCES,
        function() return state.source end,
        function(v) state.source = v; book:Fill() end)
    src:SetPoint("TOPLEFT", 0, 0)
    local search = W.SearchBox(book, min(220, width - 150), function(text)
        state.filter = (text or ""):lower()
        book:Fill()
    end, L["Find a spell"])
    search:SetPoint("LEFT", src, "RIGHT", 10, 0)

    local grid = CreateFrame("Frame", nil, book)
    grid:SetPoint("TOPLEFT", 0, -(W.HEIGHT + 10))
    grid:SetWidth(width)

    local function Icon(i)
        local b = pool[i]
        if b then return b end
        b = CreateFrame("Button", nil, grid)
        b:SetSize(ICON, ICON)
        b.well = T.Fill(b, "BACKGROUND", "surfaceSunk", 0.9)
        b.well:SetAllPoints()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        T.TokenBorder(b, "border")
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b.icon)
        hl:SetColorTexture(1, 1, 1, 0.15)
        b:RegisterForDrag("LeftButton")
        local function pick(self)
            if Locked() or not self.entry or not self.entry.pickup then return end
            Deselect()
            dragFrom = nil
            self.entry.pickup()
        end
        b:SetScript("OnDragStart", pick)
        b:SetScript("OnClick", pick)
        b:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            self.entry.tip()
            if not self.entry.pickup then
                GameTooltip:AddLine(L["Not learnt yet."], 0.7, 0.7, 0.7, true)
            else
                GameTooltip:AddLine(L["Drag onto a slot, or click it and then click a slot."], 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pool[i] = b
        return b
    end

    local all
    function book:Fill()
        all = state.source == "macros" and Macros() or Spells()
        local shown = 0
        for _, e in ipairs(all) do
            local hay = ((e.name or "") .. " " .. (e.sub or "") .. " " .. (e.line or "")):lower()
            if state.filter == "" or hay:find(state.filter, 1, true) then
                shown = shown + 1
                local b = Icon(shown)
                b.entry = e
                b.icon:SetTexture(e.icon)
                b.icon:SetDesaturated(e.future or false)
                b.icon:SetAlpha(e.future and 0.55 or 1)
                if not b.level then
                    b.level = T.Text(b, "small", "text")
                    b.level:SetPoint("BOTTOMRIGHT", -2, 2)
                end
                b.level:SetText(e.future and e.level and tostring(e.level) or "")
                b:ClearAllPoints()
                local r, c = floor((shown - 1) / per), (shown - 1) % per
                b:SetPoint("TOPLEFT", grid, "TOPLEFT", c * (ICON + GAP), -r * (ICON + GAP))
                b:Show()
            end
        end
        for i = shown + 1, #pool do pool[i]:Hide(); pool[i].entry = nil end
        if not self.empty then
            self.empty = T.Text(grid, "body", "textMuted")
            self.empty:SetPoint("TOPLEFT", 2, -4)
        end
        self.empty:SetText(shown == 0 and L["Nothing matches."] or "")
    end

    -- Height is set for the whole list so the page doesn't jump while you
    -- search; the spell list only changes when you learn something.
    local count = max(#Spells(), #Macros(), 1)
    local rows = ceil(count / per)
    local gridH = rows * (ICON + GAP)
    grid:SetHeight(gridH)
    book:SetSize(width, W.HEIGHT + 10 + gridH)
    book:SetScript("OnShow", function(self) live[self] = true; self:Fill() end)
    book:SetScript("OnHide", function(self) live[self] = nil end)
    function book:Refresh() self:Fill() end
    live[book] = true
    book:Fill()
    return book
end

--------------------------------------------------------------------------------
--  Keeping the copies current
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "ACTIONBAR_PAGE_CHANGED",
                     "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "CURSOR_CHANGED",
                     "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED",
                     "UPDATE_MACROS" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local queued
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then Deselect() end
    if event == "CURSOR_CHANGED" then
        if not GetCursorInfo() then dragFrom = nil end
        return
    end
    if not next(live) or queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = false
        for f in pairs(live) do
            if f:IsVisible() and f.Refresh then f:Refresh() end
        end
    end)
end)
