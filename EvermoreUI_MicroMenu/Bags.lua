if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Bags.lua
--  Blizzard's backpack, bag slots, reagent bag and key ring in an EvermoreUI
--  bar: cropped square icons on a sunk well, a 1px border that turns copper
--  while that bag is open, flat hover and pressed states, our font for the
--  free-slot count, and a chevron for Blizzard's expand toggle.
--
--  Blizzard re-sets the slot art in UpdateTextures (every bag change); that
--  is post-hooked. BagsBar:Layout still runs when bags are expanded or
--  collapsed; the buttons are pinned, so it can't move them.
--------------------------------------------------------------------------------
local _, ns = ...
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max = math.floor, math.max

local M = EV:NewModule("BagBar", {
    genesis      = false,
    size         = 30,       -- bag slots
    backpackSize = 38,
    spacing      = 4,
    padding      = 3,
    vertical     = false,
    grow         = "left",   -- which way the bags run from the backpack: left / right, or up / down when vertical
    panel        = false,    -- just the buttons, like retail
    toggle       = true,     -- collapse button beside the backpack
    collapsed    = false,    -- fallback when the client has no expandBagBar CVar
    freeSlots    = true,     -- free-slot count on the backpack
    countSize    = 11,
    fade         = false,
    fadeAlpha    = 0,
})
ns.bags = M
M.title = "Bag Bar"
M.description = "Blizzard's backpack and bag slots in an EvermoreUI bar, with a free-slot count."

local holder, fader
local dressed = setmetatable({}, { __mode = "k" })

local function BagButtons()
    local list = {}
    if MainMenuBarBagManager and MainMenuBarBagManager.EnumerateBagButtons then
        for _, b in MainMenuBarBagManager:EnumerateBagButtons() do list[#list + 1] = b end
    end
    if #list == 0 then
        for _, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
                              "CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }) do
            if _G[n] then list[#list + 1] = _G[n] end
        end
    end
    return list
end

--------------------------------------------------------------------------------
--  Look
--------------------------------------------------------------------------------
local function IsOpen(b)
    local t = b.SlotHighlightTexture
    return t and t:IsShown()
end

local function States(b)
    local s = dressed[b]
    if not s then return end
    local icon = b.icon or b.Icon
    local nt = b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    local pt = b:GetPushedTexture()
    if pt then
        pt:SetColorTexture(T.RGBA("surfaceSunk", 0.5))
        pt:ClearAllPoints(); pt:SetAllPoints(icon)
    end
    local hl = b:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(T.RGBA("text", 0.15))
        hl:SetBlendMode("BLEND")
        hl:SetAlpha(1)
        hl:ClearAllPoints(); hl:SetAllPoints(icon)
    end
    local sh = b.SlotHighlightTexture
    if sh then
        sh:SetColorTexture(T.RGBA("accent", 0.14))
        sh:ClearAllPoints(); sh:SetAllPoints(icon)
    end
    if b.IconBorder then b.IconBorder:SetAlpha(0) end
    T.SetBorderToken(s.edge, IsOpen(b) and "accent" or "border")
end

local function Texts(b)
    local c = b.Count
    if not (c and c.SetFont) then return end
    local cfg = M.db
    c:SetFont(EV.Media:Fetch("font"), cfg.countSize, "OUTLINE")
    c:ClearAllPoints()
    if b == MainMenuBarBackpackButton then
        c:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
        c:SetTextColor(T.RGBA("text"))
        c:SetAlpha(cfg.freeSlots and 1 or 0)
    else
        c:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
    end
end

local function Dress(b)
    if dressed[b] then States(b); Texts(b); return end
    local s = {}
    dressed[b] = s
    local icon = b.icon or b.Icon
    if icon then
        if b.SquareMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, b.SquareMask) end
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    end
    s.well = T.Fill(b, "BACKGROUND", "surfaceSunk", 0.9, -8)
    s.well:SetAllPoints(b)
    local edge = CreateFrame("Frame", nil, b)
    edge:SetAllPoints(b)
    edge:SetFrameLevel(b:GetFrameLevel() + 2)
    edge:EnableMouse(false)
    T.TokenBorder(edge, "border")
    s.edge = edge
    -- Blizzard fits these to its 45px art; fit them to our icon.
    for _, k in ipairs({ "searchOverlay", "ItemContextOverlay", "IconOverlay", "IconOverlay2" }) do
        local t = b[k]
        if t and t.ClearAllPoints and icon then t:ClearAllPoints(); t:SetAllPoints(icon) end
    end
    if type(b.UpdateTextures) == "function" then
        hooksecurefunc(b, "UpdateTextures", States)
    end
    -- Bag opened / closed: Blizzard shows its slot highlight.
    local sh = b.SlotHighlightTexture
    if sh then
        local function Open() States(b) end
        hooksecurefunc(sh, "Show", Open)
        hooksecurefunc(sh, "Hide", Open)
        hooksecurefunc(sh, "SetShown", Open)
    end
    s.Paint = function()
        s.well:SetColorTexture(T.RGBA("surfaceSunk", 0.9))
        States(b); Texts(b)
    end
    T.Watch(s)
    States(b)
    Texts(b)
end

--------------------------------------------------------------------------------
--  Collapse toggle. Forever hides Blizzard's own (hideExpandToggle), so this
--  is ours: a chevron beside the backpack, like retail. The state lives in
--  Blizzard's expandBagBar CVar (client settings persist even when
--  SavedVariables don't), and Blizzard's manager still opens the bar while
--  you're holding a bag, so you can drop it into a slot.
--------------------------------------------------------------------------------
local toggle
local function HasCVar()
    return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("expandBagBar") ~= nil
end
local function Expanded()
    local mgr = MainMenuBarBagManager
    if HasCVar() and mgr and mgr.ShouldBarExpand then return mgr:ShouldBarExpand() and true or false end
    return not M.db.collapsed
end
local function SetExpanded(on)
    if HasCVar() then SetCVar("expandBagBar", on and "1" or "0") end
    M.db.collapsed = not on
end

local function PaintToggle()
    if not toggle then return end
    -- Points the way the bags will go on the next click: out along the bar
    -- when they're folded away, back towards the backpack when they're out.
    local grow = ns.Grow(M.db, "left", "up")
    local back = ({ left = "right", right = "left", up = "down", down = "up" })[grow]
    toggle.chevron:Point(Expanded() and back or grow)
    toggle.chevron:SetColorLines(T.RGBA(toggle.hot and "text" or "textMuted"))
    toggle.bg:SetColorTexture(T.RGBA("surface3", toggle.hot and 0.6 or 0))
end

local Layout
local function MakeToggle()
    if toggle then return toggle end
    toggle = CreateFrame("Button", "EvermoreUIBagBarToggle", holder)
    toggle:RegisterForClicks("LeftButtonUp")
    toggle.bg = toggle:CreateTexture(nil, "BACKGROUND")
    toggle.bg:SetAllPoints()
    toggle.chevron = T.Chevron(toggle, 4, 1)
    toggle.chevron:SetPoint("CENTER")
    toggle:SetScript("OnClick", function()
        SetExpanded(not Expanded())
        ns.Safe("baglayout", Layout)
    end)
    toggle:SetScript("OnEnter", function(self)
        self.hot = true
        PaintToggle()
        T.ShowTooltip(self, Expanded() and L["Hide bags"] or L["Show bags"])
    end)
    toggle:SetScript("OnLeave", function(self)
        self.hot = false
        PaintToggle()
        T.HideTooltip()
    end)
    T.OnTheme(PaintToggle)
    if fader then fader.Watch(toggle) end
    return toggle
end

--------------------------------------------------------------------------------
--  Layout: backpack at the near edge, then the toggle, then the bags.
--  Collapsed bags are parked with Blizzard's containers, so nothing of
--  Blizzard's can show them again behind our back.
--------------------------------------------------------------------------------
local laying = false
local function DoLayout()
    if not holder or laying then return end
    laying = true
    local cfg = M.db
    local size, bp, gap = cfg.size, cfg.backpackSize, cfg.spacing
    local pad = cfg.panel and cfg.padding or 0
    local vertical = cfg.vertical
    local grow = ns.Grow(cfg, "left", "up")
    local thick = max(size, bp)          -- across the bar

    -- Each entry: button, length along the bar, depth across it.
    local open = Expanded()
    local row = {}
    for i, b in ipairs(BagButtons()) do
        if i == 1 or b == MainMenuBarBackpackButton then
            row[#row + 1] = { b, bp, bp }
            if cfg.toggle then row[#row + 1] = { MakeToggle(), 12, size, toggle = true } end
        elseif b:IsShown() and (open or not cfg.toggle) then
            row[#row + 1] = { b, size, size }
        else
            ns.Unplace(b, ns.hidden)
        end
    end
    if toggle then toggle:SetShown(cfg.toggle and true or false) end

    -- The bar is always as long as it is with every bag out, so folding the
    -- bags away never moves the backpack (the mover anchors the centre).
    local function Span(list)
        local n = pad * 2
        for i, e in ipairs(list) do n = n + e[2] + (i > 1 and gap or 0) end
        return n
    end
    local used = Span(row)
    local full = row
    if cfg.toggle and not open then
        full = { row[1], row[2] }
        for i, b in ipairs(BagButtons()) do
            if i > 1 and b ~= MainMenuBarBackpackButton and b:IsShown() then full[#full + 1] = { b, size, size } end
        end
    end
    local length = max(Span(full), 1)
    if vertical then holder:SetSize(thick + pad * 2, length) else holder:SetSize(length, thick + pad * 2) end

    -- Backpack at the near edge; "left" / "up" start from the far end.
    local reverse = grow == "left" or grow == "up"
    -- The panel (if on) covers just the buttons showing.
    local from, to = reverse and (length - used) or 0, reverse and length or used
    for _, r in ipairs({ holder.bg, holder.edge }) do
        r:ClearAllPoints()
        if vertical then
            r:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -from)
            r:SetPoint("BOTTOMRIGHT", holder, "TOPRIGHT", 0, -to)
        else
            r:SetPoint("TOPLEFT", holder, "TOPLEFT", from, 0)
            r:SetPoint("BOTTOMRIGHT", holder, "BOTTOMLEFT", to, 0)
        end
    end
    local at = pad
    for i, e in ipairs(row) do
        local b, along, across = e[1], e[2], e[3]
        if i > 1 then at = at + gap end
        local a = reverse and (length - at - along) or at
        local c = pad + (thick - across) / 2
        if vertical then
            ns.Place(b, holder, floor(c + 0.5), -floor(a + 0.5), across, along)
        else
            ns.Place(b, holder, floor(a + 0.5), -floor(c + 0.5), along, across)
        end
        if not e.toggle then Dress(b) end
        at = at + along
    end
    holder:SetPanel(cfg.panel)
    PaintToggle()
    EV.Movers:Apply("BagBar")
    if fader then fader.Update(true) end
    laying = false
end

-- The backpack stays where it is on screen whatever the settings do.
function Layout()
    ns.Keep(holder, "BagBar", MainMenuBarBackpackButton, DoLayout)
end

local function Reflow() ns.Safe("baglayout", Layout) end

--------------------------------------------------------------------------------
--  Adoption
--------------------------------------------------------------------------------
local function Genesis()
    if M.db.genesis then return end
    M.db.genesis = true
    local x, y = ns.CentreOf(BagsBar)
    local core = EV.DB:GetCore()
    if x and not core.movers.BagBar then core.movers.BagBar = { "CENTER", "CENTER", x, y } end
end

local adopted = false
local function Adopt()
    if adopted or not BagsBar or not MainMenuBarBackpackButton then return end
    if C_GameRules and Enum.GameRule and Enum.GameRule.BagsUIDisabled
        and C_GameRules.IsGameRuleActive(Enum.GameRule.BagsUIDisabled) then return end
    adopted = true
    Genesis()
    holder = ns.Holder("EvermoreUIBagBar")
    holder.acceptsCursor = true
    EV.Movers:Register(holder, "BagBar", L["Bag Bar"], { "BOTTOMRIGHT", "BOTTOMRIGHT", -6, 44 }, {
        group = L["Micro Menu & Bags"], page = "bagbar",
    })
    fader = ns.Fader(holder, function() return M.db end)
    -- The bar keeps the space of the folded bags; don't let that empty
    -- space eat clicks. Hover still works through the buttons.
    holder:EnableMouse(false)
    for _, b in ipairs(BagButtons()) do
        b:HookScript("OnShow", Reflow)
        b:HookScript("OnHide", Reflow)
        fader.Watch(b)
    end
    Layout()
    ns.Park(BagsBar)
    -- Blizzard's manager changed its mind (the CVar, or you picked up a bag).
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("MainMenuBarManager.OnExpandChanged", function() ns.Safe("baglayout", Layout) end, M)
    end
end

function M:Refresh()
    if not adopted then return end
    ns.Safe("baglayout", Layout)
end

function M:OnEnable()
    ns.Safe("bagadopt", Adopt)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
    -- Dragging an item or bag: a faded bar comes back so you can drop it.
    self:RegisterEvent("CURSOR_CHANGED", function() if fader then fader.Update() end end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
end

function M:OnProfileChanged() self:Refresh() end
