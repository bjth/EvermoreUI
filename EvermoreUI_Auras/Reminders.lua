if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Reminders.lua
--  Icons in the middle of the screen for what you should have up and don't,
--  from a list you edit: order, add, remove, switch off. Out of combat only;
--  the whole row hides the moment combat starts.
--
--  Each class has its own list (a mage's armours are no use to a warrior),
--  kept in the profile under lists[CLASS] and seeded from DEFAULTS below the
--  first time that class is seen. An entry is one of two kinds:
--
--    buff    shown while none of its auras is on you. Auras are spell IDs
--            or names and match by name, so any rank counts. "Only if known"
--            hides it until you know one of the spells (class buffs);
--            leave it off for consumables. Click casts the buff, or uses the
--            entry's item if it has one (a flask, an elixir, food).
--    weapon  shown while the chosen hand has no temporary enchant (poison,
--            oil, sharpening stone, shaman imbue). With an item set, click
--            applies it to that hand (the item, then target-slot 16 or 17).
--
--  "Where" limits an entry to dungeons and raids, or to being in a group.
--  "Only when I carry something for it" (needItem) hides a buff reminder
--  unless your bags hold a consumable that gives it: the entry's own item if
--  it has one, otherwise any consumable whose tooltip names one of its buffs
--  ("...you will become well fed..."). Clicking uses the one found.
--
--  The buttons are secure action buttons set up out of combat, in a row
--  hidden by a state driver ([combat] hide), so nothing here touches a
--  protected frame in combat. Your own buffs are read out of combat, and a
--  secret name is skipped rather than compared.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local issecret = issecretvalue or function() return false end

local M = EV:NewModule("Reminders", {
    enabled    = true,
    size       = 36,
    spacing    = 6,
    showNames  = true,
    expiring   = true,      -- also remind when a buff is about to run out
    expiringAt = 60,        -- seconds
    lists      = {},        -- [CLASS] = { entry, ... } in display order
})
M.title = "Reminders"
M.description = "Icons for the buffs, weapon poisons and food you're missing, from a list you edit. Click one to cast it."
ns.reminders = M

local _, myClass = UnitClass("player")

--------------------------------------------------------------------------------
--  Starting lists. Spell IDs are rank 1 (names are read from the client).
--------------------------------------------------------------------------------
local WELL_FED = 19705
local FOOD = { label = "Well Fed", kind = "buff", spells = { WELL_FED }, where = "instance", known = false,
               needItem = true }

local DEFAULTS = {
    MAGE = {
        { label = "Arcane Intellect", kind = "buff", spells = { 1459 }, known = true },
        { label = "Armour", kind = "buff", spells = { 6117, 7302, 168 }, known = true },
    },
    PRIEST = {
        { label = "Power Word: Fortitude", kind = "buff", spells = { 1243 }, known = true },
        { label = "Inner Fire", kind = "buff", spells = { 588 }, known = true },
    },
    DRUID = {
        { label = "Mark of the Wild", kind = "buff", spells = { 1126 }, known = true },
    },
    WARLOCK = {
        { label = "Armour", kind = "buff", spells = { 706, 687 }, known = true },
    },
    PALADIN = {
        { label = "Aura", kind = "buff", spells = { 465, 7294, 19746, 19876, 19888, 19891, 20218 }, known = true },
        { label = "Blessing", kind = "buff", spells = { 19740, 19742, 20217, 1038, 20911, 19977 }, known = true },
    },
    HUNTER = {
        { label = "Aspect", kind = "buff", spells = { 13165, 13163, 5118, 13159, 20043, 13161 }, known = true },
        { label = "Trueshot Aura", kind = "buff", spells = { 19506 }, known = true },
    },
    SHAMAN = {
        { label = "Lightning Shield", kind = "buff", spells = { 324 }, known = true },
        { label = "Weapon imbue", kind = "weapon", hand = "main" },
    },
    ROGUE = {
        { label = "Main hand poison", kind = "weapon", hand = "main" },
        { label = "Off hand poison", kind = "weapon", hand = "off" },
    },
}

local uidSeq = 0
local function NewUID()
    uidSeq = uidSeq + 1
    return ("%d.%d"):format(time(), uidSeq)
end

local function Copy(e)
    local c = {}
    for k, v in pairs(e) do
        if type(v) == "table" then local t = {}; for i, x in ipairs(v) do t[i] = x end; c[k] = t else c[k] = v end
    end
    return c
end

function M.DefaultList(class)
    local out = {}
    for _, e in ipairs(DEFAULTS[class] or {}) do out[#out + 1] = Copy(e) end
    out[#out + 1] = Copy(FOOD)
    for _, e in ipairs(out) do e.uid = NewUID(); e.on = true; e.where = e.where or "always" end
    return out
end

--- This class's list, seeded on first use. Settings from before the list
--- existed (the old off-switches) are carried over once.
function M.List()
    local db = M.db
    db.lists = type(db.lists) == "table" and db.lists or {}
    local list = db.lists[myClass]
    if type(list) ~= "table" then
        list = M.DefaultList(myClass)
        local off = type(db.off) == "table" and db.off or {}
        for _, e in ipairs(list) do
            local old = (e.kind == "weapon" and "weapon") or (e.spells and e.spells[1] == WELL_FED and "food") or nil
            if (old and off[old]) or (old == "food" and db.food == false) or (old == "weapon" and db.weapons == false)
               or (e.known and db.classBuffs == false) then
                e.on = false
            end
        end
        db.lists[myClass] = list
        db.off, db.food, db.weapons, db.classBuffs = nil, nil, nil, nil
    end
    -- Lists made before needItem existed: Well Fed only when you have food.
    if not db.needItemSeeded then
        db.needItemSeeded = true
        for _, e in ipairs(list) do
            if e.needItem == nil and e.spells and e.spells[1] == WELL_FED then e.needItem = true end
        end
    end
    return list
end

--------------------------------------------------------------------------------
--  Looking things up
--------------------------------------------------------------------------------
local function SpellName(s)
    if type(s) == "string" then return s end
    local ok, n = pcall(C_Spell.GetSpellName, s)
    return ok and type(n) == "string" and n or nil
end
M.SpellName = SpellName

local function Known(name)
    if not name then return false end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    return ok and info ~= nil
end

local function SpellIcon(s)
    local ok, info = pcall(C_Spell.GetSpellInfo, s)
    return ok and info and info.iconID or nil
end

local function ItemID(item)
    if type(item) == "number" then return item end
    if type(item) ~= "string" then return nil end
    local id = tonumber(item) or tonumber(item:match("item:(%d+)"))
    if not id and C_Item and C_Item.GetItemInfoInstant then id = C_Item.GetItemInfoInstant(item) end
    return id
end
M.ItemID = ItemID

local function ItemIcon(item)
    local id = ItemID(item)
    return id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil
end

local function HaveItem(item)
    local id = ItemID(item)
    return id and C_Item.GetItemCount(id) > 0
end

--- A consumable in your bags whose tooltip names one of these buffs (food
--- that makes you Well Fed, say). Tooltip reads are cached per item.
local gives = {}   -- itemID -> lower-case tooltip text, once it has loaded
local function TooltipText(bag, slot, id)
    local t = gives[id]
    if t then return t end
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" or #data.lines < 2 then return nil end
    local parts = {}
    for _, line in ipairs(data.lines) do
        local txt = line.leftText
        if type(txt) == "string" and not issecret(txt) then parts[#parts + 1] = txt:lower() end
    end
    t = table.concat(parts, "\n")
    gives[id] = t
    return t
end

local CONSUMABLE = Enum.ItemClass and Enum.ItemClass.Consumable or 0

local function ItemFor(names)
    if #names == 0 or not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and select(6, C_Item.GetItemInfoInstant(id)) == CONSUMABLE then
                local text = TooltipText(bag, slot, id)
                if text then
                    for _, n in ipairs(names) do
                        if text:find(n, 1, true) then return id end
                    end
                end
            end
        end
    end
end

--- The icon for an entry, for the row and the editor.
function M.EntryIcon(e)
    if e.item then local i = ItemIcon(e.item); if i then return i end end
    if e.kind == "weapon" then
        return GetInventoryItemTexture("player", e.hand == "off" and 17 or 16) or 135343
    end
    for _, s in ipairs(e.spells or {}) do
        local i = SpellIcon(s)
        if i then return i end
    end
    return 134400
end

--- Your buffs now: name -> seconds left (0 for no end).
local function Buffs()
    local out = {}
    local now = GetTime()
    for i = 1, 60 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        local name = a.name
        if type(name) == "string" and not issecret(name) then
            local exp = a.expirationTime
            local left = 0
            if type(exp) == "number" and not issecret(exp) and exp > 0 then left = exp - now end
            out[name] = left
        end
    end
    return out
end

--- Buffs on you now, for the editor's quick add: { name, spellID, icon }.
function M.CurrentBuffs()
    local out = {}
    for i = 1, 60 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if type(a.name) == "string" and not issecret(a.name) and not issecret(a.spellId) then
            out[#out + 1] = { name = a.name, spellID = a.spellId, icon = a.icon }
        end
    end
    return out
end

local function WhereOK(where)
    if where == "instance" then
        local inside, kind = IsInInstance()
        return inside and (kind == "party" or kind == "raid")
    elseif where == "group" then
        return IsInGroup()
    end
    return true
end

local lastUsed = {}   -- uid -> spell name last seen up

--- The reminders that apply right now, in list order.
local function Missing()
    local db = M.db
    local out = {}
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") or IsMounted() then return out end
    local buffs = Buffs()
    local soon = db.expiring and db.expiringAt or 0
    local okW, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)

    for _, e in ipairs(M.List()) do
        if e.on and WhereOK(e.where) then
            if e.kind == "weapon" then
                local slot = e.hand == "off" and 17 or 16
                local equipped = GetInventoryItemID("player", slot)
                local isWeapon = equipped and select(6, C_Item.GetItemInfoInstant(equipped)) == (Enum.ItemClass and Enum.ItemClass.Weapon or 2)
                local has = (slot == 16) and hasMain or hasOff
                if okW and isWeapon and not has then
                    out[#out + 1] = { entry = e, label = e.label, icon = M.EntryIcon(e),
                                      item = (e.item and HaveItem(e.item)) and e.item or nil, slot = slot }
                end
            else
                local known, have, first = false, false, nil
                for _, s in ipairs(e.spells or {}) do
                    local name = SpellName(s)
                    if name then
                        if Known(name) then known = true; first = first or name end
                        local left = buffs[name]
                        if left and (left == 0 or left > soon) then have = true; lastUsed[e.uid] = name end
                    end
                end
                if not have and (known or not e.known) then
                    local item = (e.item and HaveItem(e.item)) and e.item or nil
                    if e.needItem and not item then
                        local names = {}
                        for _, s in ipairs(e.spells or {}) do
                            local n = SpellName(s)
                            if n then names[#names + 1] = n:lower() end
                        end
                        item = not e.item and ItemFor(names) or nil
                    end
                    if item or not e.needItem then
                        local cast = not item and not e.item and (lastUsed[e.uid] or first) or nil
                        out[#out + 1] = { entry = e, label = e.label, icon = item and ItemIcon(item) or M.EntryIcon(e),
                                          cast = cast, item = item }
                    end
                end
            end
        end
    end
    return out
end
M.Missing = Missing

--------------------------------------------------------------------------------
--  The row
--------------------------------------------------------------------------------
local row
local buttons = {}

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    -- Both halves of the click: SecureActionButton_OnClick acts on the down
    -- press when ActionButtonUseKeyDown is on (the game's default) and on the
    -- release when it is off, and ignores the other. Registering only one
    -- makes the button do nothing for half of all players.
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.well = T.Fill(b, "BACKGROUND", "surfaceSunk", 0.9)
    b.well:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    T.TokenBorder(b, "warning")
    b.label = T.Text(b, "small", "text")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.label:SetWordWrap(false)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", function(self)
        local r = self.rem
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(r and r.label or "")
        if r and r.item then
            GameTooltip:AddLine(r.slot and L["Click to apply it."] or L["Click to use it."], 0.7, 0.7, 0.7)
        elseif r and r.cast then
            GameTooltip:AddLine(L["Click to cast it."], 0.7, 0.7, 0.7)
        elseif r and r.slot then
            GameTooltip:AddLine(L["Nothing on this weapon."], 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end

local ATTRS = { "type", "spell", "item", "unit", "target-slot" }

local function Layout(list)
    local db = M.db
    local size, gap = db.size, db.spacing
    local n = #list
    row:SetSize(math.max(1, n * size + math.max(0, n - 1) * gap), size)
    for i, r in ipairs(list) do
        local b = Button(i)
        b.rem = r
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
        b.icon:SetTexture(r.icon)
        b.label:SetShown(db.showNames)
        b.label:SetText(r.label or "")
        b.label:SetWidth(size + 30)
        for _, a in ipairs(ATTRS) do b:SetAttribute(a, nil) end
        if r.item then
            local id = ItemID(r.item)
            b:SetAttribute("type", "item")
            b:SetAttribute("item", id and ("item:" .. id) or r.item)
            if r.slot then b:SetAttribute("target-slot", r.slot) end
        elseif r.cast then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", r.cast)
            b:SetAttribute("unit", "player")
        end
        b:Show()
    end
    for i = n + 1, #buttons do buttons[i]:Hide() end
end

local function Update()
    if not (row and M:IsEnabled()) then return end
    -- Secure buttons: only rearranged out of combat. In combat the row is
    -- hidden by its state driver anyway.
    if InCombatLockdown() then return end
    Layout(Missing())
end
M.Update = Update

local function Build()
    if row then return end
    row = CreateFrame("Frame", "EvermoreUIReminders", UIParent)
    row:SetSize(36, 36)
    row:SetFrameStrata("MEDIUM")
    EV.Movers:Register(row, "Reminders", L["Reminders"], { "CENTER", "CENTER", 0, 170 }, {
        group = L["Buffs & Debuffs"], page = "reminders",
        isDisabled = function() return not M:IsEnabled() end,
    })
end

local ticker
function M:OnEnable()
    Build()
    RegisterStateDriver(row, "visibility", "[combat][petbattle] hide; show")
    for _, e in ipairs({ "UNIT_AURA", "PLAYER_REGEN_ENABLED", "UNIT_INVENTORY_CHANGED", "PLAYER_ENTERING_WORLD",
                         "SPELLS_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_UNGHOST", "PLAYER_ALIVE",
                         "PLAYER_MOUNT_DISPLAY_CHANGED", "PLAYER_CONTROL_GAINED", "GROUP_ROSTER_UPDATE",
                         "BAG_UPDATE_DELAYED" }) do
        pcall(self.RegisterEvent, self, e, function(_, _, unit)
            if (e == "UNIT_AURA" or e == "UNIT_INVENTORY_CHANGED") and unit ~= "player" then return end
            Update()
        end)
    end
    -- Buffs running low and poisons wearing off have no event of their own.
    ticker = ticker or C_Timer.NewTicker(5, function() if M:IsEnabled() and not InCombatLockdown() then Update() end end)
    EV.Movers:Apply("Reminders")
    Update()
end

function M:Refresh() Update() end
function M:OnProfileChanged() Update() end

--------------------------------------------------------------------------------
--  Editing, for the options page
--------------------------------------------------------------------------------
function M.Add(e)
    local list = M.List()
    e.uid = NewUID()
    e.on = e.on ~= false
    e.where = e.where or "always"
    e.kind = e.kind or "buff"
    list[#list + 1] = e
    Update()
    return e
end

function M.Remove(uid)
    local list = M.List()
    for i, e in ipairs(list) do
        if e.uid == uid then table.remove(list, i); break end
    end
    Update()
end

function M.Move(uid, delta)
    local list = M.List()
    for i, e in ipairs(list) do
        if e.uid == uid then
            local j = i + delta
            if j >= 1 and j <= #list then list[i], list[j] = list[j], list[i] end
            break
        end
    end
    Update()
end

function M.Find(uid)
    for _, e in ipairs(M.List()) do if e.uid == uid then return e end end
end

function M.ResetList()
    M.db.lists[myClass] = M.DefaultList(myClass)
    Update()
end

M.CLASS = myClass
