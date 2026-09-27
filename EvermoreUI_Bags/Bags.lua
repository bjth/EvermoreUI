if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Bags.lua
--  All your bags in one EvermoreUI window, split into sections by category:
--  new items, gear sets, equipment, consumables, quest items, gathering
--  (herbs, ore, leather, cloth), trade goods and the rest, junk last.
--  Replaces Blizzard's bag windows, which are closed whenever they open.
--
--  The item buttons are Blizzard's own ContainerFrameItemButtonTemplate, so
--  clicking, using, splitting, selling and dragging are Blizzard's code and
--  keep working in combat. Each bag gets a holder frame whose ID is the bag
--  (the button's GetBagID falls back to its parent's ID) and each button's ID
--  is its slot; both are set with SetID, so the values come from the game
--  and nothing we write is read back by those clicks.
--
--  The bank gets a window of its own in the same style (see "The bank
--  window" below).
--
--  Opening and closing follows Blizzard's own calls: OpenAllBags,
--  ToggleAllBags, ToggleBackpack and friends are post-hooked. Whatever they
--  did to Blizzard's windows, ours opens or closes to match and theirs is
--  hidden again.
--
--  Sections. Where an item goes, first that fits:
--    1. a section you dropped that item on (drag an item onto a section's
--       title in the bags to put it there)
--    2. your own sections, in the order they're shown, by their rules
--       (Rules.lua)
--    3. the built-in sections, in match order (junk and quest before
--       equipment, and so on)
--    4. Everything else
--  Any section can be switched off; its items fall through to the next that
--  fits (Herbs off: herbs go to Trade goods). Sections are drawn in the
--  order set on the options page, and can be folded by clicking the title.
--  Empty space shows as one slot per kind of bag, with a count, so there's
--  always somewhere to drop an item.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local IC = Enum.ItemClass or {}
local CONSUMABLE, CONTAINER, WEAPON, GEM, ARMOR = IC.Consumable or 0, IC.Container or 1, IC.Weapon or 2, IC.Gem or 3, IC.Armor or 4
local REAGENT, PROJECTILE, TRADEGOODS, RECIPE = IC.Reagent or 5, IC.Projectile or 6, IC.Tradegoods or 7, IC.Recipe or 9
local QUIVER, QUEST, KEY = IC.Quiver or 11, IC.Questitem or 12, IC.Key or 13
-- Trade goods subclasses.
local CLOTH, LEATHER, METAL, HERB = 5, 6, 7, 9

--------------------------------------------------------------------------------
--  Categories
--------------------------------------------------------------------------------
-- key, label, display order, test(item). Match order is the list order.
local CATEGORIES = {
    { key = "new",        label = L["New"],           order = 1,  test = function(i) return i.new end },
    { key = "junk",       label = L["Junk"],          order = 99, test = function(i) return i.quality == 0 and not i.noValue end },
    { key = "quest",      label = L["Quest items"],   order = 5,  test = function(i) return i.class == QUEST or i.quest end },
    { key = "sets",       label = L["Gear sets"],     order = 2,  test = function(i) return i.inSet end },
    { key = "equipment",  label = L["Equipment"],     order = 3,  test = function(i) return i.class == WEAPON or i.class == ARMOR end },
    { key = "consumable", label = L["Consumables"],   order = 4,  test = function(i) return i.class == CONSUMABLE end },
    { key = "herbs",      label = L["Herbs"],         order = 10, gather = true, test = function(i) return i.class == TRADEGOODS and i.sub == HERB end },
    { key = "ore",        label = L["Ore & stone"],   order = 11, gather = true, test = function(i) return i.class == TRADEGOODS and i.sub == METAL end },
    { key = "leather",    label = L["Leather"],       order = 12, gather = true, test = function(i) return i.class == TRADEGOODS and i.sub == LEATHER end },
    { key = "cloth",      label = L["Cloth"],         order = 13, gather = true, test = function(i) return i.class == TRADEGOODS and i.sub == CLOTH end },
    { key = "tradegoods", label = L["Trade goods"],   order = 14, test = function(i) return i.class == TRADEGOODS or i.class == GEM end },
    { key = "reagents",   label = L["Reagents"],      order = 15, test = function(i) return i.class == REAGENT end },
    { key = "ammo",       label = L["Ammo"],          order = 16, test = function(i) return i.class == PROJECTILE or i.class == QUIVER end },
    { key = "recipes",    label = L["Recipes"],       order = 17, test = function(i) return i.class == RECIPE end },
    { key = "bags",       label = L["Bags"],          order = 18, test = function(i) return i.class == CONTAINER end },
    { key = "keys",       label = L["Keys"],          order = 19, test = function(i) return i.class == KEY end },
}
local OTHER = { key = "other", label = L["Everything else"], order = 90 }

local function CategoryDefaults()
    local t = {}
    for _, c in ipairs(CATEGORIES) do t[c.key] = true end
    return t
end

local M = EV:NewModule("Bags", {
    columns    = 10,
    size       = 36,
    spacing    = 4,
    categories = CategoryDefaults(),   -- [key] = on (built-in sections)
    custom     = {},                   -- your sections: { key, name, on, match, rules, items }
    assign     = {},                   -- [itemID] = section key, dropped there by hand
    order      = {},                   -- section keys, top to bottom
    collapsed  = {},                   -- [key] = true
    sort       = "quality",            -- within a section: quality, name, ilvl, id
    ilvl       = true,                 -- item level on gear
    searchHide = true,                 -- searching hides what doesn't match (off: dims it)
    point      = { "BOTTOMRIGHT", -60, 110 },
})
M.title = "Bags"
M.description = "All your bags in one window, split into sections by category. Replaces Blizzard's bag windows."
M.CATEGORIES = CATEGORIES
ns.module = M

--------------------------------------------------------------------------------
--  Reading the bags
--------------------------------------------------------------------------------
local function BagList()
    local list = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
        if ok and n and n > 0 then list[#list + 1] = bag end
    end
    return list
end

local function BagFamily(bag)
    if bag == (NUM_BAG_SLOTS or 4) + 1 then return "reagent" end
    local ok, _, fam = pcall(C_Container.GetContainerNumFreeSlots, bag)
    return (ok and fam and fam ~= 0) and ("f" .. fam) or "normal"
end

local function Read(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return nil end
    local i = {
        bag = bag, slot = slot, id = info.itemID, icon = info.iconFileID, count = info.stackCount,
        locked = info.isLocked, quality = info.quality, readable = info.isReadable, link = info.hyperlink,
        filtered = false, noValue = info.hasNoValue, bound = info.isBound,
    }
    local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(info.itemID)
    i.class, i.sub = class, sub
    local okN, isNew = pcall(C_NewItems.IsNewItem, bag, slot)
    i.new = okN and isNew or false
    local okQ, q = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if okQ and q then i.quest, i.questID, i.questActive = q.isQuestItem, q.questID, q.isActive end
    if C_Container.GetContainerItemEquipmentSetInfo then
        local okS, inSet = pcall(C_Container.GetContainerItemEquipmentSetInfo, bag, slot)
        i.inSet = okS and inSet or false
    end
    return i
end

local Rules = ns.Rules

local builtinByKey = {}
for _, c in ipairs(CATEGORIES) do builtinByKey[c.key] = c end
builtinByKey.other = OTHER

--- Every section, top to bottom: { key, label, builtin = cat | custom = sec }.
--- The saved order is kept; sections it doesn't know yet join where they
--- belong (yours at the top, built-ins by their usual place).
function M.All()
    local db = M.db
    local out, seen = {}, {}
    local customByKey = {}
    for _, sec in ipairs(db.custom) do customByKey[sec.key] = sec end
    local function Add(key)
        if seen[key] then return end
        local b, c = builtinByKey[key], customByKey[key]
        if not (b or c) then return end
        seen[key] = true
        out[#out + 1] = { key = key, label = c and c.name or b.label, builtin = b, custom = c }
    end
    -- New sections of yours (not in the saved order yet) go at the top.
    local known = {}
    for _, key in ipairs(db.order) do known[key] = true end
    for _, sec in ipairs(db.custom) do if not known[sec.key] then Add(sec.key) end end
    for _, key in ipairs(db.order) do Add(key) end
    local builtins = {}
    for _, c in ipairs(CATEGORIES) do builtins[#builtins + 1] = c end
    builtins[#builtins + 1] = OTHER
    table.sort(builtins, function(x, y) return x.order < y.order end)
    for _, c in ipairs(builtins) do Add(c.key) end
    return out
end

--- Save the current top-to-bottom order (after a move in the options).
function M.SetOrder(list)
    local keys = {}
    for i, e in ipairs(list) do keys[i] = e.key end
    M.db.order = keys
end

function M.IsOn(key)
    local db = M.db
    if builtinByKey[key] then return key == "other" or db.categories[key] ~= false end
    for _, sec in ipairs(db.custom) do if sec.key == key then return sec.on ~= false end end
    return false
end

function M.NewSection(name)
    local db = M.db
    -- Unique within the saved setup (and across imports): time, then a count
    -- until nothing has the key already.
    local key, n = nil, #db.custom
    repeat
        n = n + 1
        key = ("c%d_%d"):format(time(), n)
        local taken = false
        for _, sec in ipairs(db.custom) do if sec.key == key then taken = true; break end end
    until not taken
    local sec = { key = key, name = name or L["New section"], on = true, match = "all", rules = {}, items = {} }
    db.custom[#db.custom + 1] = sec
    return sec
end

function M.DeleteSection(key)
    local db = M.db
    for n, sec in ipairs(db.custom) do
        if sec.key == key then table.remove(db.custom, n); break end
    end
    for id, k in pairs(db.assign) do if k == key then db.assign[id] = nil end end
end

--- Put an item in a section by hand (or take it out again with key = nil).
function M.Assign(itemID, key)
    if type(itemID) ~= "number" then return end
    M.db.assign[itemID] = key
end

local function CategoryOf(i, all)
    local db = M.db
    local byHand = db.assign[i.id]
    if byHand and M.IsOn(byHand) then
        for _, e in ipairs(all) do if e.key == byHand then return e end end
    end
    for _, e in ipairs(all) do
        if e.custom and e.custom.on ~= false and Rules.Matches(e.custom, i) then return e end
    end
    for _, c in ipairs(CATEGORIES) do
        if db.categories[c.key] ~= false and c.test(i) then
            for _, e in ipairs(all) do if e.key == c.key then return e end end
        end
    end
    for _, e in ipairs(all) do if e.key == "other" then return e end end
end

local SORTS = {
    quality = function(a, b)
        local qa, qb = a.i.quality or 0, b.i.quality or 0
        if qa ~= qb then return qa > qb end
        if a.i.id ~= b.i.id then return a.i.id < b.i.id end
        return (a.i.count or 1) > (b.i.count or 1)
    end,
    name = function(a, b)
        local na = C_Item.GetItemNameByID(a.i.id) or ""
        local nb = C_Item.GetItemNameByID(b.i.id) or ""
        if na ~= nb then return na < nb end
        return (a.i.count or 1) > (b.i.count or 1)
    end,
    ilvl = function(a, b)
        local la, lb = Rules.ItemLevel(a.i), Rules.ItemLevel(b.i)
        if la ~= lb then return la > lb end
        if a.i.id ~= b.i.id then return a.i.id < b.i.id end
        return (a.i.count or 1) > (b.i.count or 1)
    end,
    id = function(a, b)
        if a.i.id ~= b.i.id then return a.i.id < b.i.id end
        return (a.i.count or 1) > (b.i.count or 1)
    end,
}
M.SORTS = SORTS


--------------------------------------------------------------------------------
--  Views: the bags window and the bank window share everything below. A view
--  knows which bags it shows; buttons are kept per bag, so a bag's buttons
--  live in whichever view holds that bag.
--------------------------------------------------------------------------------
local holders, buttons = {}, {}
local PAD, TOP, FOOT, HEAD = 10, 44, 30, 20

local function Holder(view, bag)
    local h = holders[bag]
    if h then return h end
    h = CreateFrame("Frame", nil, view.content)
    h:SetAllPoints(view.content)
    h:SetID(bag)
    holders[bag] = h
    return h
end

local skinned = setmetatable({}, { __mode = "k" })   -- item button -> its icon

--- The suite's icon style (EV.Icons, General > Icons) on a slot: its crop and
--- edge, and the slot's well behind it for an empty one.
local function Skin(b)
    if skinned[b] then return end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local icon = b.icon or b.Icon
    if not icon then return end
    EV.Icons:Style(icon, { host = b, fit = true, well = T.LOOK.slot.rest.fill })
    skinned[b] = icon
end

local function Button(view, bag, slot)
    buttons[bag] = buttons[bag] or {}
    local b = buttons[bag][slot]
    if b then return b end
    b = CreateFrame("ItemButton", nil, Holder(view, bag), "ContainerFrameItemButtonTemplate")
    b:SetID(slot)
    Skin(b)
    buttons[bag][slot] = b
    return b
end

local function Paint(b, i)
    local texture = i and i.icon
    ClearItemButtonOverlay(b)
    b:SetHasItem(texture)
    b:SetItemButtonTexture(texture)
    SetItemButtonQuality(b, i and i.quality, i and i.link, false, i and i.bound)
    SetItemButtonCount(b, i and i.count)
    SetItemButtonDesaturated(b, i and i.locked)
    b:UpdateExtended()
    b:UpdateQuestItem(i and i.quest, i and i.questID, i and i.questActive)
    b:UpdateNewItem(i and i.quality)
    b:UpdateJunkItem(i and i.quality, i and i.noValue)
    b:UpdateCooldown(texture)
    b:SetReadable(i and i.readable)
    b:CheckUpdateTooltip(GameTooltip:GetOwner())
    b:SetMatchesSearch(not (i and i.filtered))
    -- Quality edge on our border (Blizzard's IconBorder stays for its own art).
    local q = i and i.quality
    local icon = skinned[b]
    if icon then
        if q and q > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
            local c = ITEM_QUALITY_COLORS[q]
            EV.Icons:SetState(icon, c.r, c.g, c.b, 1)   -- content colour
        else
            EV.Icons:SetState(icon, nil)
        end
    end
end

--- A section title. Click folds the section; dropping an item on it puts
--- that item in this section from now on (the item goes back where it was).
local function Header(view, n)
    local h = view.headers[n]
    if h then return h end
    h = CreateFrame("Button", nil, view.content)
    h:SetHeight(HEAD - 2)
    h.text = T.Text(h, "small", "textMuted", true)
    h.text:SetPoint("LEFT", 0, 0)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    local function Drop(self)
        local kind, itemID = GetCursorInfo()
        if kind ~= "item" or not self.key then return false end
        M.Assign(itemID, self.key)
        ClearCursor()
        M:Refresh()
        return true
    end
    h:SetScript("OnReceiveDrag", Drop)
    h:SetScript("OnClick", function(self)
        if Drop(self) or not self.key then return end
        M.db.collapsed[self.key] = not M.db.collapsed[self.key] or nil
        M:Refresh()
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.label or "")
        GameTooltip:AddLine(L["Click to fold or unfold."], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Drop an item here to keep it in this section."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.headers[n] = h
    return h
end

local ilvlText = setmetatable({}, { __mode = "k" })
local function ItemLevelText(b, i, size)
    local t = ilvlText[b]
    local lvl = M.db.ilvl and i and (i.class == WEAPON or i.class == ARMOR) and (i.quality or 0) >= 2
        and Rules.ItemLevel(i) or 0
    if lvl <= 1 then
        if t then t:Hide() end
        return
    end
    if not t then
        t = b:CreateFontString(nil, "OVERLAY")
        t:SetPoint("TOPLEFT", 2, -2)
        ilvlText[b] = t
    end
    t:SetFont(EV.Media:Fetch("font"), max(9, floor(size * 0.3)), "OUTLINE")
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[i.quality]
    if c then t:SetTextColor(c.r, c.g, c.b) else t:SetTextColor(1, 1, 1) end
    t:SetText(lvl)
    t:Show()
end

local freeText = setmetatable({}, { __mode = "k" })
local labelOf = setmetatable({}, { __mode = "k" })   -- button -> its section's name, for in: searches

local View = {}
View.__index = View

--- Read the view's bags, sort into sections, lay out. Called on bag events
--- and when the window opens or settings change.
function View:Build()
    local win = self.win
    if not (win and win:IsShown()) then return end
    local db = M.db
    local size, gap, cols = db.size, db.spacing, max(4, db.columns)
    local content = self.content
    local query = self.query

    local all = M.All()
    local position = {}
    for n, e in ipairs(all) do position[e.key] = n end
    local sections, byKey = {}, {}
    local empties, freeCount = {}, {}
    local bags = self.bags()
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local i = Read(bag, slot)
            local b = Button(self, bag, slot)
            if i then
                local c = CategoryOf(i, all)
                labelOf[b] = c.label
                if query then i.filtered = not Rules.SearchMatches(query, i, c.label) end
                if not (i.filtered and db.searchHide) then
                    local s = byKey[c.key]
                    if not s then
                        s = { cat = c, items = {} }
                        byKey[c.key] = s
                        sections[#sections + 1] = s
                    end
                    s.items[#s.items + 1] = { b = b, i = i }
                end
            else
                local fam = BagFamily(bag)
                freeCount[fam] = (freeCount[fam] or 0) + 1
                if not empties[fam] then empties[fam] = b end
                Paint(b, nil)
                ItemLevelText(b, nil, size)
            end
        end
    end
    table.sort(sections, function(a, b) return (position[a.cat.key] or 999) < (position[b.cat.key] or 999) end)
    local sorter = SORTS[db.sort] or SORTS.quality
    for _, s in ipairs(sections) do table.sort(s.items, sorter) end

    -- Lay out.
    local y = 0
    local width = cols * size + (cols - 1) * gap
    local shown = {}
    local headers = self.headers
    for n, s in ipairs(sections) do
        local h = Header(self, n)
        local folded = db.collapsed[s.cat.key] and not query
        h.key, h.label = s.cat.key, s.cat.label
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        h:SetWidth(width)
        h.text:SetText((folded and "+ " or "") .. s.cat.label .. "  |cff808080" .. #s.items .. "|r")
        h:Show()
        y = y + HEAD
        if not folded then
            for k, e in ipairs(s.items) do
                local r, c = floor((k - 1) / cols), (k - 1) % cols
                local b = e.b
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", content, "TOPLEFT", c * (size + gap), -(y + r * (size + gap)))
                Paint(b, e.i)
                ItemLevelText(b, e.i, size)
                b:Show()
                shown[b] = true
            end
            y = y + ceil(#s.items / cols) * (size + gap)
        end
        y = y + 6
    end
    for n = #sections + 1, #headers do headers[n]:Hide() end

    -- One empty slot per kind of bag, with how many there are.
    local famOrder = { "normal", "reagent" }
    for fam in pairs(empties) do if fam ~= "normal" and fam ~= "reagent" then famOrder[#famOrder + 1] = fam end end
    local k, total = 0, 0
    for _, fam in ipairs(famOrder) do
        local b = empties[fam]
        if b then
            k = k + 1
            b:SetSize(size, size)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", (k - 1) * (size + gap), -y)
            b:Show()
            shown[b] = true
            local t = freeText[b]
            if not t then
                t = b:CreateFontString(nil, "OVERLAY")
                t:SetPoint("CENTER")
                freeText[b] = t
            end
            t:SetFont(EV.Media:Fetch("font"), max(10, floor(size * 0.34)), "OUTLINE")
            t:SetText(freeCount[fam])
            t:SetTextColor(T.RGBA(fam == "normal" and "text" or "textMuted"))
            t:Show()
            total = total + (fam == "normal" and freeCount[fam] or 0)
        end
    end
    if k > 0 then y = y + size + gap end

    -- Everything of this view's bags that isn't laid out goes out of sight,
    -- and so does anything left over from bags it no longer shows.
    local mine = {}
    for _, bag in ipairs(bags) do mine[bag] = true end
    for bag, list in pairs(buttons) do
        local here = holders[bag] and holders[bag]:GetParent() == content
        if mine[bag] or here then
            for _, b in pairs(list) do
                if not (mine[bag] and shown[b]) then b:Hide() end
                if freeText[b] and (not shown[b] or b:HasItem()) then freeText[b]:Hide() end
            end
        end
    end

    local h = max(size, y)
    content:SetSize(width, h)
    win:SetSize(max(width + PAD * 2, self.minWidth or 0), TOP + h + FOOT + (self.extraTop or 0))
    if win.money then win.money:SetText(EV:FormatMoney(GetMoney())) end
    win.free:SetText((L["%d free"]):format(total))
end

--- Only the looks (lock, cooldown), for events that don't move items.
function View:Repaint()
    if not (self.win and self.win:IsShown()) then return end
    for _, bag in ipairs(self.bags()) do
        for slot, b in pairs(buttons[bag] or {}) do
            if b:IsShown() then
                local i = Read(bag, slot)
                if i then
                    if self.query then i.filtered = not Rules.SearchMatches(self.query, i, labelOf[b]) end
                    Paint(b, i)
                end
            end
        end
    end
end

-- Positions: a corner of the window as an offset from the same corner of
-- the screen, so the window grows away from where it's pinned.
local function SavePoint(view)
    local win = view.win
    local corner = view.corner
    local k = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y
    if corner == "BOTTOMRIGHT" then
        x, y = win:GetRight(), win:GetBottom()
        if not (x and y) then return end
        x, y = x * k - UIParent:GetWidth(), y * k
    else
        x, y = win:GetLeft(), win:GetTop()
        if not (x and y) then return end
        x, y = x * k, y * k - UIParent:GetHeight()
    end
    M.db[view.pointKey] = { corner, floor(x + 0.5), floor(y + 0.5) }
end

local function PlaceWindow(view)
    local p = M.db[view.pointKey] or {}
    local d = view.defaultPoint
    view.win:ClearAllPoints()
    view.win:SetPoint(view.corner, UIParent, view.corner, p[2] or d[1], p[3] or d[2])
end

local function NewView(key, opts)
    local view = setmetatable({ key = key, headers = {} }, View)
    for k, v in pairs(opts) do view[k] = v end
    return view
end

local function BuildWindow(view)
    if view.win then return end
    local W = EV.UI
    local win = W.Window(view.frameName, { width = 440, height = 300, title = view.title, strata = "MEDIUM" })
    view.win = win
    win.titleBar:HookScript("OnDragStop", function() SavePoint(view); PlaceWindow(view) end)

    local content = CreateFrame("Frame", nil, win.body)
    content:SetPoint("TOPLEFT", win.body, "TOPLEFT", PAD, -(TOP - 32) - (view.extraTop or 0))
    view.content = content

    local search = W.SearchBox(win.titleBar, 150, function(text)
        view.query = Rules.ParseSearch(text)
        view:Build()
    end, L["Search"])
    search:SetHeight(20)
    search:SetPoint("RIGHT", win.closeButton or win.titleBar, win.closeButton and "LEFT" or "RIGHT", -8, 0)
    search:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Search"])
        for _, line in ipairs(Rules.SEARCH_HELP) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    win.search = search

    if view.sort then
        local sort = W.Button(win.titleBar, L["Sort"], 56, function()
            if InCombatLockdown() then return end
            view.sort()
        end)
        sort:SetHeight(20)
        sort:SetPoint("RIGHT", search, "LEFT", -6, 0)
        win.sort = sort
    end

    if view.money then
        win.money = T.Text(win.body, "body", "text")
        win.money:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", -PAD, 9)
    end
    win.free = T.Text(win.body, "small", "textMuted")
    win.free:SetPoint("BOTTOMLEFT", win.body, "BOTTOMLEFT", PAD, 10)

    if view.decorate then view.decorate(view, win) end

    win:HookScript("OnShow", function()
        PlaceWindow(view)
        view:Build()
    end)
    win:HookScript("OnHide", function()
        view.query = nil
        search:SetText("")
        if view.onHide then view.onHide(view) end
    end)
    PlaceWindow(view)
end

--------------------------------------------------------------------------------
--  The bags window
--------------------------------------------------------------------------------
local bagsView = NewView("bags", {
    frameName = "EvermoreUIBags", title = L["Bags"], bags = BagList,
    corner = "BOTTOMRIGHT", pointKey = "point", defaultPoint = { -60, 110 },
    money = true,
    sort = C_Container.SortBags and function() pcall(C_Container.SortBags) end or nil,
    onHide = function()
        if C_NewItems and C_NewItems.ClearAll then pcall(C_NewItems.ClearAll) end
    end,
})

--------------------------------------------------------------------------------
--  The bank window
--
--  Forever's bank is the modern one: tabs you buy, each a container of its
--  own (C_Bank.FetchPurchasedBankTabData), for your character and, where the
--  game allows, your account. Blizzard's BankFrame has to stay shown while
--  you're at the bank (hiding it ends the visit: its OnHide calls
--  C_Bank.CloseBankFrame), so it is made invisible and moved off screen
--  instead, and brought back by the "Blizzard's bank" button.
--  Right-clicking an item in your bags puts it in the bank Blizzard's frame
--  has selected, so choosing Character or Account in ours switches that one
--  too. Buying a tab uses Blizzard's own purchase button template.
--------------------------------------------------------------------------------
local BT = Enum.BankType or { Character = 0, Account = 2 }
local bankType = BT.Character
local atBank = false
local showBlizzardBank = false

local function BankBags()
    local list = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabData then
        local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, bankType)
        if ok and type(tabs) == "table" then
            for _, t in ipairs(tabs) do
                local id = t.ID or t.bankTabID
                if id and (C_Container.GetContainerNumSlots(id) or 0) > 0 then list[#list + 1] = id end
            end
        end
        return list
    end
    -- An older bank: the bank itself and its bag slots.
    if BANK_CONTAINER and (C_Container.GetContainerNumSlots(BANK_CONTAINER) or 0) > 0 then list[#list + 1] = BANK_CONTAINER end
    for bag = (NUM_BAG_SLOTS or 4) + 2, (NUM_BAG_SLOTS or 4) + 1 + (NUM_BANKBAGSLOTS or 7) do
        if (C_Container.GetContainerNumSlots(bag) or 0) > 0 then list[#list + 1] = bag end
    end
    return list
end

local function CanView(t)
    if not (C_Bank and C_Bank.CanViewBank) then return t == BT.Character end
    local ok, can = pcall(C_Bank.CanViewBank, t)
    return ok and can or false
end

local function Supports(fn, t)
    if not (C_Bank and C_Bank[fn]) then return false end
    local ok, yes = pcall(C_Bank[fn], t)
    return ok and yes or false
end

--- Make Blizzard's bank frame (out of sight) look at the same bank as ours,
--- so right-clicking an item in your bags puts it there. The base SetTab is
--- used rather than the frame's own, which would also try to buy a free tab.
local function FollowInBlizzard(t)
    local f = BankFrame
    if not (f and f:IsShown() and f.BankPanel and BankFrameBaseMixin and BankFrameBaseMixin.SetTab) then return end
    if f.GetActiveBankType and f:GetActiveBankType() == t then return end
    local id = (t == BT.Account) and f.accountBankTabID or f.characterBankTabID
    if id then pcall(BankFrameBaseMixin.SetTab, f, id) end
end

local function Gold(copper)
    return EV:FormatMoney(tonumber(copper) or 0)
end

local bankView
bankView = NewView("bank", {
    frameName = "EvermoreUIBank", title = L["Bank"], bags = BankBags,
    corner = "TOPLEFT", pointKey = "bankPoint", defaultPoint = { 40, -110 },
    extraTop = 30, minWidth = 460,
    sort = function()
        if bankType == BT.Account and C_Container.SortAccountBankBags then
            pcall(C_Container.SortAccountBankBags)
        elseif C_Container.SortBankBags then
            pcall(C_Container.SortBankBags)
        end
    end,
    decorate = function(view, win)
        local W = EV.UI
        local function Pick(t)
            bankType = t
            FollowInBlizzard(t)
            view:Paint()
            view:Build()
        end
        local mineBtn = W.Button(win.body, L["Character"], 100, function() Pick(BT.Character) end)
        mineBtn:SetHeight(22)
        mineBtn:SetPoint("TOPLEFT", win.body, "TOPLEFT", PAD, -8)
        local acct = W.Button(win.body, L["Account"], 100, function() Pick(BT.Account) end)
        acct:SetHeight(22)
        acct:SetPoint("LEFT", mineBtn, "RIGHT", 6, 0)

        local function Tip(b, title, text)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(title)
                GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local blizz = W.Button(win.body, L["Blizzard's bank"], 110, function()
            showBlizzardBank = not showBlizzardBank
            M.ApplyBankFrame()
        end)
        blizz:SetHeight(22)
        blizz:SetPoint("TOPRIGHT", win.body, "TOPRIGHT", -PAD, -8)
        Tip(blizz, L["Blizzard's bank"], L["Shows or hides the game's own bank window."])

        -- Buying a tab goes through Blizzard's own purchase button template
        -- (made for addons: the bank type comes from an attribute), so the
        -- purchase runs in Blizzard's code and its confirmation.
        local buy
        local ok, made = pcall(CreateFrame, "Button", nil, win.body, "BankPanelPurchaseButtonScriptTemplate")
        if ok and made then
            buy = made
            buy:SetSize(96, 22)
            buy.bg = EV.UI.Surface(buy, "control")
            EV.UI.SurfaceEdge(buy.bg, "accent")
            buy.label = T.Text(buy, "small", "text", true)
            buy.label:SetPoint("CENTER")
            buy.label:SetText(L["Buy a tab"])
            buy:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            local hl = buy:GetHighlightTexture()
            if hl then hl:SetVertexColor(1, 1, 1, 0.08) end
            buy:SetPoint("RIGHT", blizz, "LEFT", -6, 0)
            buy:HookScript("OnEnter", function(self)
                local data = C_Bank.FetchNextPurchasableBankTabData and C_Bank.FetchNextPurchasableBankTabData(bankType)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["Buy a bank tab"])
                if data and data.tabCost then GameTooltip:AddLine(Gold(data.tabCost), 1, 1, 1) end
                GameTooltip:Show()
            end)
            buy:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end

        local deposit = W.Button(win.body, L["Deposit all"], 96, function()
            if C_Bank and C_Bank.AutoDepositItemsIntoBank then pcall(C_Bank.AutoDepositItemsIntoBank, bankType) end
        end)
        deposit:SetHeight(22)
        deposit:SetPoint("RIGHT", buy or blizz, "LEFT", -6, 0)
        Tip(deposit, L["Deposit all"], L["Puts everything this bank takes from your bags into it, as the game's own deposit button does."])

        -- Money kept in the bank (the account bank holds gold).
        local money = T.Text(win.body, "small", "text")
        money:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", -PAD - 150, 10)
        local function AskGold(title, onGold)
            EV.UI.AskNumber{ title = title, text = L["How much gold?"], value = 0, min = 0, max = 9999999,
                             onSave = function(n) if n > 0 then onGold(n * 10000) end end }
        end
        local put = W.Button(win.body, L["Deposit"], 70, function()
            AskGold(L["Deposit gold"], function(c) pcall(C_Bank.DepositMoney, bankType, c) end)
        end)
        put:SetHeight(20)
        put:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", -PAD - 76, 6)
        local take = W.Button(win.body, L["Withdraw"], 70, function()
            AskGold(L["Withdraw gold"], function(c) pcall(C_Bank.WithdrawMoney, bankType, c) end)
        end)
        take:SetHeight(20)
        take:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", -PAD, 6)

        view.tabs = { [BT.Character] = mineBtn, [BT.Account] = acct }
        function view:Paint()
            for t, b in pairs(self.tabs) do
                b:SetShown(t == BT.Character or CanView(t))
                b:SetStyle(t == bankType and "primary" or "secondary")
            end
            deposit:SetShown(Supports("DoesBankTypeSupportAutoDeposit", bankType))
            if buy then
                buy:SetAttribute("overrideBankType", bankType)
                buy:SetShown(not InCombatLockdown() and Supports("CanPurchaseBankTab", bankType))
            end
            local moneyOK = Supports("DoesBankTypeSupportMoneyTransfer", bankType)
            put:SetShown(moneyOK and Supports("CanDepositMoney", bankType))
            take:SetShown(moneyOK and Supports("CanWithdrawMoney", bankType))
            money:SetShown(moneyOK)
            if moneyOK and C_Bank.FetchDepositedMoney then
                local okM, amount = pcall(C_Bank.FetchDepositedMoney, bankType)
                money:SetText(okM and Gold(amount) or "")
            end
        end
    end,
    onHide = function()
        -- Closing ours ends the visit, as closing Blizzard's would.
        if atBank and C_Bank and C_Bank.CloseBankFrame then pcall(C_Bank.CloseBankFrame) end
    end,
})

--- Blizzard's bank window: invisible and off screen while ours is in use,
--- but still shown, so the visit stays open.
function M.ApplyBankFrame()
    local f = BankFrame
    if not (f and f:IsShown()) then return end
    if M:IsEnabled() and not showBlizzardBank then
        f:SetAlpha(0)
        if not (InCombatLockdown() and f:IsProtected()) then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -5000, 5000)
        end
    else
        f:SetAlpha(1)
        if not (InCombatLockdown() and f:IsProtected()) and UpdateUIPanelPositions then
            pcall(UpdateUIPanelPositions, f)
        end
    end
end

--------------------------------------------------------------------------------
--  Opening and closing, and taking over from Blizzard's bags
--------------------------------------------------------------------------------
local function IsOurBag(id)
    return type(id) ~= "number" or (id >= 0 and id <= (NUM_BAG_SLOTS or 4) + 1)
end

local function BlizzardFrames()
    local list = {}
    if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
    for n = 1, NUM_CONTAINER_FRAMES or 13 do
        local f = _G["ContainerFrame" .. n]
        if f then list[#list + 1] = f end
    end
    return list
end

local function HideBlizzard()
    for _, f in ipairs(BlizzardFrames()) do
        if f:IsShown() then
            if IsOurBag(f.GetBagID and f:GetBagID()) then f:Hide() end
        end
    end
end

local function Show(view, on)
    if not M:IsEnabled() then return end
    BuildWindow(view)
    view.win:SetShown(on)
end

function M:Toggle() Show(bagsView, not (bagsView.win and bagsView.win:IsShown())) end
function M:Open() Show(bagsView, true) end
function M:Close() if bagsView.win then bagsView.win:Hide() end end

-- After each of Blizzard's calls: follow what it meant, hide its windows.
-- The calls nest (ToggleAllBags opens the bags through OpenBag and
-- OpenBackpack), and post-hooks fire innermost first, so acting on each one
-- would open ours and then toggle it straight shut. Instead each call just
-- records itself; the outermost call's hook runs last, so the last one
-- recorded is what was meant, and it is carried out once, a frame later.
local want
local function Resolve()
    local kind = want
    want = nil
    if not (kind and M:IsEnabled()) then return end
    if kind == "toggle" then M:Toggle()
    elseif kind == "open" then M:Open()
    elseif kind == "close" then M:Close() end
    HideBlizzard()
end

local function After(kind, perBag)
    return function(id)
        if not M:IsEnabled() then return end
        -- ToggleBag / OpenBag for a bank bag: not ours.
        if perBag and not IsOurBag(id) then return end
        if not want then C_Timer.After(0, Resolve) end
        want = kind
    end
end

local HOOKS = {
    ToggleAllBags = "toggle", ToggleBackpack = "toggle", ToggleBag = "toggle",
    OpenAllBags = "open", OpenBackpack = "open", OpenBag = "open",
    CloseAllBags = "close", CloseBackpack = "close",
}
local PER_BAG = { ToggleBag = true, OpenBag = true }

function M:OnEnable()
    for name, kind in pairs(HOOKS) do
        if type(_G[name]) == "function" then hooksecurefunc(name, After(kind, PER_BAG[name])) end
    end
    -- Blizzard's bag windows never stay open; the calls above decide ours.
    for _, f in ipairs(BlizzardFrames()) do
        f:HookScript("OnShow", function(self)
            if not M:IsEnabled() then return end
            if IsOurBag(self.GetBagID and self:GetBagID()) then self:Hide() end
        end)
    end

    -- The bank.
    if BankFrame then
        BankFrame:HookScript("OnShow", function() M.ApplyBankFrame() end)
        if type(ShowUIPanel) == "function" then hooksecurefunc("ShowUIPanel", function() M.ApplyBankFrame() end) end
        if type(UpdateUIPanelPositions) == "function" then
            hooksecurefunc("UpdateUIPanelPositions", function() if not showBlizzardBank then M.ApplyBankFrame() end end)
        end
    end
    local win = EV:GetModule("Windows", true)
    if win and win.skip then win.skip.BankFrame = true end
    self:RegisterEvent("BANKFRAME_OPENED", function()
        atBank = true
        showBlizzardBank = false
        bankType = BT.Character
        Show(bankView, true)
        if bankView.Paint then bankView:Paint() end
        M.ApplyBankFrame()
    end)
    local function BankTop() if bankView.win and bankView.win:IsShown() and bankView.Paint then bankView:Paint() end end
    self:RegisterEvent("ACCOUNT_MONEY", BankTop)
    self:RegisterEvent("BANK_TABS_CHANGED", function() BankTop(); M:Refresh() end)
    self:RegisterEvent("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", function() M:Refresh() end)
    self:RegisterEvent("BANKFRAME_CLOSED", function()
        atBank = false
        if bankView.win then bankView.win:Hide() end
    end)

    local queued = false
    local function Rebuild()
        if queued then return end
        queued = true
        C_Timer.After(0.05, function() queued = false; M:Refresh() end)
    end
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "BAG_NEW_ITEMS_UPDATED", "EQUIPMENT_SETS_CHANGED", "QUEST_ACCEPTED",
                         "PLAYERBANKSLOTS_CHANGED", "BANK_TAB_SETTINGS_UPDATED" }) do
        self:RegisterEvent(e, Rebuild)
    end
    local function Repaint() bagsView:Repaint(); bankView:Repaint() end
    self:RegisterEvent("ITEM_LOCK_CHANGED", Repaint)
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", Repaint)
    self:RegisterEvent("PLAYER_MONEY", function()
        if bagsView.win and bagsView.win:IsShown() then bagsView.win.money:SetText(EV:FormatMoney(GetMoney())) end
    end)
end

function M:Refresh()
    bagsView:Build()
    bankView:Build()
end
