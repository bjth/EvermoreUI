if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  LootRolls.lua
--  Need, greed and pass in the EvermoreUI style: one row per item, stacked,
--  movable with /evui edit.
--
--  Our own rows rather than a skin, because which roll frame Forever uses
--  depends on its game family (the classic GroupLootFrame1-4 or retail's
--  GroupLootContainer), and both are built on the same few calls:
--      START_LOOT_ROLL(rollID, rollTime)      a roll opens
--      GetLootRollItemInfo / GetLootRollItemLink / GetLootRollTimeLeft
--      RollOnLoot(rollID, 0 pass | 1 need | 2 greed | 3 disenchant)
--      CANCEL_LOOT_ROLL(rollID)               it closed (rolled, timed out)
--  Blizzard's frames are hidden whenever they try to show. The bind on pickup
--  confirmation is still Blizzard's own dialog.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme

local M = EV:NewModule("LootRolls", {
    width = 320,
    height = 40,
    spacing = 6,
    growUp = true,
})
M.title = "Loot Rolls"
M.description = "Need, greed and pass rows in the EvermoreUI style, movable with /evui edit."
ns.lootRolls = M

local holder
local rows = {}          -- pool
local active = {}        -- rollID -> row

local ROLLS = {
    { key = "need",  roll = 1, tex = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",  label = NEED or "Need",
      nudge = -0.10 },
    { key = "greed", roll = 2, tex = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",  label = GREED or "Greed",
      nudge = -0.17, scale = 1.05 },
    { key = "de",    roll = 3, tex = "Interface\\Buttons\\UI-GroupLoot-DE-Up",    label = ROLL_DISENCHANT or "Disenchant" },
    { key = "pass",  roll = 0, tex = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",  label = PASS or "Pass",
      nudge = 0, scale = 0.88 },
}
-- The textures don't share a centre or a fill. Measured at 25px: the dice
-- art sits 2px above its square's centre, the coin 3.5px above and smaller,
-- the pass circle centred and larger. nudge moves each by a fraction of the
-- button size (negative is down) and scale evens the sizes, so every glyph
-- lands on the item icon's centre line.

local function Quality(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local Layout

local function Close(row)
    if not row then return end
    if row.rollID then active[row.rollID] = nil end
    row.rollID, row.test = nil, nil
    row:SetScript("OnUpdate", nil)
    row:Hide()
    Layout()
end

local function RollButton(row, def)
    local b = CreateFrame("Button", nil, row)
    b:SetNormalTexture(def.tex)
    b:SetHighlightTexture(def.tex:gsub("%-Up$", "-Highlight"), "ADD")
    b:SetPushedTexture(def.tex:gsub("%-Up$", "-Down"))
    b.def = def
    b:SetScript("OnClick", function(self)
        local r = self:GetParent()
        if r.test then Close(r); return end
        if r.rollID then
            pcall(RollOnLoot, r.rollID, def.roll)
            Close(r)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(def.label)
        if self.reason then GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

local function NewRow()
    local r = CreateFrame("Frame", nil, holder)
    r.bg = T.Fill(r, "BACKGROUND", "surface1", 0.95)
    r.bg:SetAllPoints()
    T.TokenBorder(r, "border")

    r.item = CreateFrame("Button", nil, r)
    r.item.icon = r.item:CreateTexture(nil, "ARTWORK")
    r.item.icon:SetPoint("TOPLEFT", 1, -1)
    r.item.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    r.item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    T.TokenBorder(r.item, "border")
    r.item.count = r.item:CreateFontString(nil, "OVERLAY")
    r.item.count:SetPoint("BOTTOMRIGHT", -2, 2)
    r.item:SetScript("OnEnter", function(self)
        local row = self:GetParent()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if row.rollID then
            pcall(GameTooltip.SetLootRollItem, GameTooltip, row.rollID)
        elseif row.link then
            GameTooltip:SetHyperlink(row.link)
        end
        GameTooltip:Show()
    end)
    r.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.item:SetScript("OnClick", function(self)
        local link = self:GetParent().link
        if link then HandleModifiedItemClick(link) end
    end)

    r.name = T.Text(r, "body", "text")
    r.name:SetWordWrap(false)
    r.bind = T.Text(r, "caption", "warning", true)

    r.timer = CreateFrame("StatusBar", nil, r)
    r.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    r.timer:SetPoint("BOTTOMLEFT", 1, 1)
    r.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    r.timer:SetHeight(3)

    r.buttons = {}
    for i, def in ipairs(ROLLS) do r.buttons[i] = RollButton(r, def) end
    return r
end

local function Row()
    for _, r in ipairs(rows) do
        if not r:IsShown() and not r.rollID then return r end
    end
    local r = NewRow()
    rows[#rows + 1] = r
    return r
end

--- Row layout: icon on the left, roll buttons on the right (hidden ones
--- skipped so there is no gap), name and bind text stacked between them and
--- centred as a block, and the timer as a thin line along the bottom edge.
local TIMER_H = 2

local function Style(r)
    local db = M.db
    local h = db.height
    r:SetSize(db.width, h)
    local inner = h - 6 - TIMER_H
    r.item:SetSize(inner, inner)
    r.item:ClearAllPoints()
    r.item:SetPoint("TOPLEFT", 3, -3)

    local bs = math.floor(inner * 0.8)
    local x, prev = -6, nil
    for i = #r.buttons, 1, -1 do
        local b = r.buttons[i]
        b:ClearAllPoints()
        if b:IsShown() then
            local w = math.floor(bs * (b.def.scale or 1) + 0.5)
            b:SetSize(w, w)
            -- TIMER_H / 2 up from the row's centre is the item icon's centre.
            b:SetPoint("RIGHT", r, "RIGHT", x,
                       TIMER_H / 2 + math.floor(bs * (b.def.nudge or 0) + 0.5))
            x = x - w - 6
            prev = b
        end
    end

    local hasBind = (r.bind:GetText() or "") ~= ""
    r.name:ClearAllPoints()
    r.bind:ClearAllPoints()
    if hasBind then
        r.name:SetPoint("BOTTOMLEFT", r.item, "RIGHT", 8, 1)
        r.bind:SetPoint("TOPLEFT", r.item, "RIGHT", 8, -2)
        r.bind:SetPoint("RIGHT", prev or r, prev and "LEFT" or "RIGHT", -8, 0)
    else
        r.name:SetPoint("LEFT", r.item, "RIGHT", 8, 0)
    end
    r.name:SetPoint("RIGHT", prev or r, prev and "LEFT" or "RIGHT", -8, 0)
    r.name:SetJustifyH("LEFT")
    r.bind:SetJustifyH("LEFT")
    r.bind:SetWordWrap(false)

    r.timer:ClearAllPoints()
    r.timer:SetPoint("BOTTOMLEFT", 1, 1)
    r.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    r.timer:SetHeight(TIMER_H)
    r.item.count:SetFont(EV.Media:Fetch("font"), 11, "OUTLINE")
    r.timer:SetStatusBarColor(T.RGBA("accent", 0.9))
end

function Layout()
    if not holder then return end
    local db = M.db
    local shown = {}
    for _, r in ipairs(rows) do if r:IsShown() then shown[#shown + 1] = r end end
    table.sort(shown, function(a, b) return (a.order or 0) < (b.order or 0) end)
    for i, r in ipairs(shown) do
        r:ClearAllPoints()
        local off = (i - 1) * (db.height + db.spacing)
        if db.growUp then r:SetPoint("BOTTOM", holder, "BOTTOM", 0, off)
        else r:SetPoint("TOP", holder, "TOP", 0, -off) end
    end
end

local order = 0
local function Fill(r, info)
    Style(r)
    order = order + 1
    r.order = order
    r.link = info.link
    r.item.icon:SetTexture(info.texture)
    r.item.count:SetText((info.count or 1) > 1 and info.count or "")
    r.name:SetText(info.name or "")
    r.name:SetTextColor(Quality(info.quality))
    T.SetBorderToken(r.item, "border")
    r.bind:SetText(info.bop and (ITEM_BIND_ON_PICKUP or L["Binds when picked up"]) or "")
    local can = { need = info.canNeed, greed = info.canGreed, de = info.canDE, pass = true }
    local why = { need = info.reasonNeed, greed = info.reasonGreed, de = info.reasonDE }
    for _, b in ipairs(r.buttons) do
        local k = b.def.key
        if k == "de" and not info.canDE and not info.reasonDE then
            b:Hide()
        else
            b:Show()
            b:SetEnabled(can[k] ~= false)
            b:GetNormalTexture():SetDesaturated(can[k] == false)
            local reason = why[k]
            b.reason = (can[k] == false and reason) and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason] or nil
        end
    end
    Style(r)   -- again, now DE may be hidden
    local total = math.max(info.time or 1, 1)
    r.timer:SetMinMaxValues(0, total)
    r:SetScript("OnUpdate", function(self)
        local left
        if self.rollID then
            local ok, t = pcall(GetLootRollTimeLeft, self.rollID)
            left = ok and t or 0
        else
            left = math.max(0, (self.testEnd or 0) - GetTime() * 1000)
            if left <= 0 then Close(self) return end
        end
        self.timer:SetValue(left)
    end)
    r:Show()
    Layout()
end

local function Start(rollID, rollTime)
    if not holder then return end
    local ok, texture, name, count, quality, bop, canNeed, canGreed, canDE, rNeed, rGreed, rDE = pcall(GetLootRollItemInfo, rollID)
    if not ok or not name then return end
    local r = active[rollID] or Row()
    r.rollID = rollID
    active[rollID] = r
    local okL, link = pcall(GetLootRollItemLink, rollID)
    Fill(r, {
        texture = texture, name = name, count = count, quality = quality, bop = bop,
        canNeed = canNeed, canGreed = canGreed, canDE = canDE,
        reasonNeed = rNeed, reasonGreed = rGreed, reasonDE = rDE,
        link = okL and link or nil, time = rollTime,
    })
end

--- A pretend roll for placing the rows: a Hearthstone, twenty seconds.
function M:Test()
    if not holder then return end
    local id = 6948
    local name, link, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(id)
    local r = Row()
    r.test = true
    r.testEnd = GetTime() * 1000 + 20000
    Fill(r, { texture = texture or 134414, name = name or "Hearthstone", quality = quality or 1,
              link = link, canNeed = true, canGreed = true, canDE = false, bop = true, time = 20000 })
end

--------------------------------------------------------------------------------
--  Blizzard's own rows step aside
--------------------------------------------------------------------------------
local function Silence(f)
    if f and not f.evSilenced then
        f.evSilenced = true
        f:HookScript("OnShow", function(self) if M:IsEnabled() then self:Hide() end end)
        if f:IsShown() then f:Hide() end
    end
end

local function SilenceBlizzard()
    Silence(GroupLootContainer)
    for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do Silence(_G["GroupLootFrame" .. i]) end
end

function M:OnEnable()
    holder = holder or CreateFrame("Frame", "EvermoreUILootRolls", UIParent)
    holder:SetSize(self.db.width, self.db.height)
    holder:SetFrameStrata("HIGH")
    EV.Movers:Register(holder, "LootRolls", L["Loot Rolls"], { "BOTTOM", "BOTTOM", 0, 280 }, {
        group = L["Interface"], page = "group",
        isDisabled = function() return not M:IsEnabled() end,
    })
    EV.Movers:Apply("LootRolls")
    SilenceBlizzard()
    self:RegisterEvent("START_LOOT_ROLL", function(_, _, rollID, rollTime) Start(rollID, rollTime) end)
    self:RegisterEvent("CANCEL_LOOT_ROLL", function(_, _, rollID) Close(active[rollID]) end)
    self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS", function() for _, r in pairs(active) do Close(r) end end)
    -- Frames that load late (the retail container is created on demand).
    self:RegisterEvent("PLAYER_ENTERING_WORLD", SilenceBlizzard)
end

function M:Refresh()
    if not holder then return end
    holder:SetSize(self.db.width, self.db.height)
    for _, r in ipairs(rows) do if r:IsShown() then Style(r) end end
    Layout()
end
