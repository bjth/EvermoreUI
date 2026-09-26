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
--  Window
--------------------------------------------------------------------------------
local win, content
local holders, buttons, headers = {}, {}, {}
local PAD, TOP, FOOT, HEAD = 10, 44, 30, 20

local function Holder(bag)
    local h = holders[bag]
    if h then return h end
    h = CreateFrame("Frame", nil, content)
    h:SetAllPoints(content)
    h:SetID(bag)
    holders[bag] = h
    return h
end

local function Skin(b)
    if b.evSkinned then return end
    b.evSkinned = true
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local icon = b.icon or b.Icon
    if icon then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    local well = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    well:SetAllPoints()
    well:SetColorTexture(T.RGBA("surfaceSunk", 0.9))
    b.evWell = well
    local edge = CreateFrame("Frame", nil, b)
    edge:SetAllPoints()
    edge:EnableMouse(false)
    T.TokenBorder(edge, "border")
    b.evEdge = edge
end

local function Button(bag, slot)
    buttons[bag] = buttons[bag] or {}
    local b = buttons[bag][slot]
    if b then return b end
    b = CreateFrame("ItemButton", nil, Holder(bag), "ContainerFrameItemButtonTemplate")
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
    if q and q > 1 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        T.SetBorderColor(b.evEdge, c.r, c.g, c.b, 1)
    else
        T.SetBorderToken(b.evEdge, "border")
    end
end

--- A section title. Click folds the section; dropping an item on it puts
--- that item in this section from now on (the item goes back where it was).
local function Header(n)
    local h = headers[n]
    if h then return h end
    h = CreateFrame("Button", nil, content)
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
        M:Build()
        return true
    end
    h:SetScript("OnReceiveDrag", Drop)
    h:SetScript("OnClick", function(self)
        if Drop(self) or not self.key then return end
        M.db.collapsed[self.key] = not M.db.collapsed[self.key] or nil
        M:Build()
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.label or "")
        GameTooltip:AddLine(L["Click to fold or unfold."], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Drop an item here to keep it in this section."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    headers[n] = h
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

local freeText = {}
local labelOf = setmetatable({}, { __mode = "k" })   -- button -> its section's name, for in: searches

--- Read every bag, sort into sections, lay out. Called on BAG_UPDATE_DELAYED
--- and when the window opens or settings change.
function M:Build()
    if not (win and win:IsShown()) then return end
    local db = self.db
    local size, gap, cols = db.size, db.spacing, max(4, db.columns)

    local all = M.All()
    local position = {}
    for n, e in ipairs(all) do position[e.key] = n end
    local sections, byKey = {}, {}
    local empties, freeCount = {}, {}
    local used = {}
    for _, bag in ipairs(BagList()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local i = Read(bag, slot)
            local b = Button(bag, slot)
            used[b] = true
            if i then
                local c = CategoryOf(i, all)
                labelOf[b] = c.label
                if M.query then i.filtered = not Rules.SearchMatches(M.query, i, c.label) end
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
    for n, s in ipairs(sections) do
        local h = Header(n)
        local folded = db.collapsed[s.cat.key] and not M.query
        h.key, h.label = s.cat.key, s.cat.label
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        h:SetWidth(width)
        h.text:SetText((folded and "+ " or "") .. s.cat.label .. "  |cff808080" .. #s.items .. "|r")
        h:Show()
        y = y + HEAD
        for k, e in ipairs(folded and {} or s.items) do
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
        if not folded then y = y + ceil(#s.items / cols) * (size + gap) end
        y = y + 6
    end
    for n = #sections + 1, #headers do headers[n]:Hide() end

    -- One empty slot per kind of bag, with how many there are.
    local famOrder = { "normal", "reagent" }
    for fam in pairs(empties) do if fam ~= "normal" and fam ~= "reagent" then famOrder[#famOrder + 1] = fam end end
    local k = 0
    local total = 0
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
    -- Free-slot numbers only belong on the slots showing them.
    for b, t in pairs(freeText) do if not shown[b] or b:HasItem() then t:Hide() end end

    for _, list in pairs(buttons) do
        for _, b in pairs(list) do
            if not shown[b] then b:Hide() end
        end
    end

    content:SetSize(width, max(size, y))
    win:SetSize(width + PAD * 2, TOP + max(size, y) + FOOT)
    win.money:SetText(EV:FormatMoney(GetMoney()))
    win.free:SetText((L["%d free"]):format(total))
end

--- Only the looks (lock, cooldown, search), for events that don't move items.
function M:Repaint()
    if not (win and win:IsShown()) then return end
    for bag, list in pairs(buttons) do
        for slot, b in pairs(list) do
            if b:IsShown() then
                local i = Read(bag, slot)
                if i then
                    if M.query then i.filtered = not Rules.SearchMatches(M.query, i, labelOf[b]) end
                    Paint(b, i)
                end
            end
        end
    end
end

local function SavePoint()
    local right, bottom = win:GetRight(), win:GetBottom()
    if not (right and bottom) then return end
    local k = win:GetEffectiveScale() / UIParent:GetEffectiveScale()
    M.db.point = { "BOTTOMRIGHT", floor(right * k - UIParent:GetWidth() + 0.5), floor(bottom * k + 0.5) }
end

local function PlaceWindow()
    local p = M.db.point or {}
    win:ClearAllPoints()
    win:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", p[2] or -60, p[3] or 110)
end

local function BuildWindow()
    if win then return end
    local W = EV.UI
    win = W.Window("EvermoreUIBags", { width = 440, height = 300, title = L["Bags"], strata = "MEDIUM" })
    win.titleBar:HookScript("OnDragStop", function() SavePoint(); PlaceWindow() end)

    content = CreateFrame("Frame", nil, win.body)
    content:SetPoint("TOPLEFT", win.body, "TOPLEFT", PAD, -(TOP - 32))

    local search = W.SearchBox(win.titleBar, 160, function(text)
        M.query = Rules.ParseSearch(text)
        M:Build()
    end, L["Search"])
    search:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Search"])
        for _, line in ipairs(Rules.SEARCH_HELP) do GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    search:HookScript("OnLeave", function() GameTooltip:Hide() end)
    search:SetHeight(20)
    search:SetPoint("RIGHT", win.closeButton or win.titleBar, win.closeButton and "LEFT" or "RIGHT", -8, 0)
    win.search = search

    if C_Container.SortBags then
        local sort = W.Button(win.titleBar, L["Sort"], 56, function()
            if InCombatLockdown() then return end
            pcall(C_Container.SortBags)
        end)
        sort:SetHeight(20)
        sort:SetPoint("RIGHT", search, "LEFT", -6, 0)
        win.sort = sort
    end

    win.money = T.Text(win.body, "body", "text")
    win.money:SetPoint("BOTTOMRIGHT", win.body, "BOTTOMRIGHT", -PAD, 9)
    win.free = T.Text(win.body, "small", "textMuted")
    win.free:SetPoint("BOTTOMLEFT", win.body, "BOTTOMLEFT", PAD, 10)

    win:HookScript("OnShow", function()
        PlaceWindow()
        M:Build()
    end)
    win:HookScript("OnHide", function()
        M.query = nil
        search:SetText("")
        if C_NewItems and C_NewItems.ClearAll and M.db.clearNew ~= false then pcall(C_NewItems.ClearAll) end
    end)
    PlaceWindow()
end

--------------------------------------------------------------------------------
--  Taking over from Blizzard's bags
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

local function Show(on)
    if not M:IsEnabled() then return end
    BuildWindow()
    win:SetShown(on)
end

function M:Toggle() Show(not (win and win:IsShown())) end
function M:Open() Show(true) end
function M:Close() if win then win:Hide() end end

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

    local queued = false
    local function Rebuild()
        if queued then return end
        queued = true
        C_Timer.After(0.05, function() queued = false; M:Build() end)
    end
    self:RegisterEvent("BAG_UPDATE_DELAYED", Rebuild)
    self:RegisterEvent("BAG_NEW_ITEMS_UPDATED", Rebuild)
    self:RegisterEvent("EQUIPMENT_SETS_CHANGED", Rebuild)
    self:RegisterEvent("QUEST_ACCEPTED", Rebuild)
    self:RegisterEvent("ITEM_LOCK_CHANGED", function() M:Repaint() end)
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() M:Repaint() end)
    self:RegisterEvent("PLAYER_MONEY", function() if win and win:IsShown() then win.money:SetText(EV:FormatMoney(GetMoney())) end end)
end

function M:Refresh()
    if win and win:IsShown() then self:Build() end
end
