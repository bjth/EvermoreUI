if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Tooltips.lua
--  The look: every Blizzard tooltip (and right-click menus, and the aura
--  tooltip on our buff bars) gets the EvermoreUI panel colour, a 1px border,
--  our font, and a slim health bar tucked inside the bottom edge. Item
--  tooltips take their quality colour on the border.
--
--  Taint rules: visual only. We never Show/Hide/SetParent a Blizzard tooltip
--  (one pcall'd re-Show after changing fonts, so it re-measures), never write
--  fields on it (state lives in a side table), and only post-hook. Menu
--  skinning is collected in a hook and applied from our own timer.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L

local M = EV:NewModule("Tooltips", {
    skin          = true,
    bgAlpha       = 0.95,
    qualityBorder = true,
    font          = "",        -- "" follows General > Font
    outline       = "NONE",
    titleSize     = 14,
    bodySize      = 12,
    healthBar     = true,
    barHeight     = 4,
    -- units
    classColours  = true,
    hideTitles    = true,
    guildRank     = false,
    targetLine    = true,
    itemLevel     = true,
    showIds       = false,
    -- position
    anchor        = "fixed",   -- fixed | cursor | blizzard
    cursorPos     = "right",   -- where the tip sits relative to the cursor
    cursorX       = 12,
    cursorY       = 0,
    -- menus
    menus         = true,
    compareGap    = 3,         -- px between a tooltip and its comparisons
})
ns.module = M
M.title = "Tooltips"
M.description = "Tooltips and right-click menus in the EvermoreUI style, with class colours, item level, quality borders and a movable or cursor anchor."

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

local state = setmetatable({}, { __mode = "k" })
local function D(f)
    local d = state[f]
    if not d then d = {}; state[f] = d end
    return d
end
ns.D = D

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------
function ns.FontPath() return EV.Media:Fetch("font", M.db.font) end
function ns.FontFlags()
    local o = M.db.outline
    return (o == "OUTLINE" or o == "THICKOUTLINE") and o or ""
end

-- A tooltip anchored to a forbidden widget restricts calls on it without
-- IsForbidden saying so; a pcall'd read is the only safe probe.
local function Usable(tt)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) then return false end
    local ok, w = pcall(tt.GetWidth, tt)
    return ok and not issecret(w)
end
ns.Usable = Usable

local BORDER_DEFAULT = EV.Theme.C.border

local function PaintBorder(tt)
    local d = state[tt]
    if not (d and d.edge) then return end
    local c = (M.db.qualityBorder and d.quality) or BORDER_DEFAULT
    EV.Pixel:CreateBorder(d.edge, 1, c[1], c[2], c[3], c[4] or 1)
end

--------------------------------------------------------------------------------
--  Skin one tooltip
--------------------------------------------------------------------------------
local function Skin(tt)
    if not M.db.skin or not Usable(tt) then return end
    -- Embedded tooltips (rewards inside a quest tooltip) sit inside another
    -- one; a second panel there looks nested.
    if tt.IsEmbedded == true then return end
    local d = D(tt)
    if not d.bg then
        -- Our fill at the very back of the tooltip, our border on a child
        -- frame above its text.
        local fill = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
        EV.Pixel.NoSnap(fill)
        fill:SetAllPoints(tt)
        local edge = CreateFrame("Frame", nil, tt)
        edge:EnableMouse(false)
        edge:SetAllPoints(tt)
        d.bg, d.edge = fill, edge
    end
    if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
    local bg = EV.Theme.C.surface1 -- raised: tooltips and menus, like our own
    d.bg:SetColorTexture(bg[1], bg[2], bg[3], M.db.bgAlpha)
    d.bg:Show()
    local ok, lvl = pcall(tt.GetFrameLevel, tt)
    if ok and lvl then d.edge:SetFrameLevel(lvl + 4) end
    d.edge:Show()
    PaintBorder(tt)
end
ns.Skin = Skin

--- Our font on every line from `from` on (line 1 is the title).
local function SetIfDifferent(fs, path, size, flags)
    local p, s, f = fs:GetFont()
    if p == path and s and math.abs(s - size) < 0.01 and (f or "") == flags then return false end
    fs:SetFont(path, size, flags)
    return true
end

--- Returns true when any line changed (the tooltip then needs re-measuring).
local function Fonts(tt, from)
    if not M.db.skin or not Usable(tt) then return false end
    local ok, prefix = pcall(tt.GetName, tt)
    if not (ok and prefix) then return false end
    local path, flags = ns.FontPath(), ns.FontFlags()
    local db = M.db
    local last = (tt.NumLines and tt:NumLines()) or 30
    local changed = false
    local line = from or 1
    while line <= last do
        local cells = { _G[prefix .. "TextLeft" .. line], _G[prefix .. "TextRight" .. line] }
        if not cells[1] then break end
        for side, fs in pairs(cells) do
            -- The title is line 1's left cell; everything else is body text.
            local size = (line == 1 and side == 1) and db.titleSize or db.bodySize
            if SetIfDifferent(fs, path, size, flags) then changed = true end
        end
        line = line + 1
    end
    return changed
end
ns.Fonts = Fonts

local relaying = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local COMPARE = {}
ns.COMPARE = COMPARE
local function OnShow(tt)
    Skin(tt)
    Fonts(tt)
    if COMPARE[tt] and ns.SpaceComparisons then ns.SpaceComparisons() end
    -- Show again so it re-measures with our fonts. Optional polish, so
    -- pcall'd: a tooltip showing restricted content may refuse it.
    if M.db.skin and not relaying[tt] then
        relaying[tt] = true
        pcall(tt.Show, tt)
        relaying[tt] = nil
    end
end

-- Lines added after the tooltip is already up (the "if you replace this
-- item" block on comparisons, late item level) arrive with Blizzard's font;
-- the tooltip resizes when they do, so catch them there.
local function OnSizeChanged(tt)
    if relaying[tt] or not M.db.skin then return end
    if Fonts(tt) then
        relaying[tt] = true
        pcall(tt.Show, tt)
        relaying[tt] = nil
    end
end

local function Hook(tt)
    if not tt or hooked[tt] or (tt.IsForbidden and tt:IsForbidden()) then return end
    hooked[tt] = true
    tt:HookScript("OnShow", OnShow)
    tt:HookScript("OnSizeChanged", OnSizeChanged)
    if ns.SkinHeader then ns.SkinHeader(tt) end
    if tt.HasScript and tt:HasScript("OnTooltipCleared") then
        tt:HookScript("OnTooltipCleared", function(self)
            local d = state[self]
            if d and d.quality then d.quality = nil; PaintBorder(self) end
        end)
    end
end
ns.Hook = Hook

-- Every tooltip we dress, by global name. Some only exist on some clients or
-- once their addon has loaded, so the list is resolved each time it is used.
local TOOLTIP_NAMES = {
    -- the main one and its item comparisons
    "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    -- clicked links and their comparisons
    "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
    -- smaller Blizzard ones
    "EmbeddedItemTooltip", "FriendsTooltip", "GameSmallHeaderTooltip",
    "NamePlateTooltip", "QuickKeybindTooltip", "ReputationParagonTooltip",
    "SettingsTooltip", "WarCampaignTooltip",
    -- the minimap button library many addons share
    "LibDBIconTooltip",
}

local function Tooltips()
    local list = {}
    for _, name in ipairs(TOOLTIP_NAMES) do
        local tt = _G[name]
        if tt then list[#list + 1] = tt end
    end
    local quests = QuestScrollFrame
    if quests then
        for _, key in ipairs({ "CampaignTooltip", "StoryTooltip" }) do
            if quests[key] then list[#list + 1] = quests[key] end
        end
    end
    return list
end

--------------------------------------------------------------------------------
--  Comparison tooltips: the "Equipped" tab above them becomes a tab of our
--  panel (same colour, border on three sides, the tooltip's top edge closes
--  it), and joined tooltips get a small gap so two borders never double up.
--------------------------------------------------------------------------------
function ns.SkinHeader(tt)
    local h = tt and tt.CompareHeader
    if type(h) ~= "table" or not h.GetRegions or (h.IsForbidden and h:IsForbidden()) then return end
    local d = D(h)
    if not d.bg then
        d.bg = h:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetAllPoints()
        EV.Pixel.NoSnap(d.bg)
        d.ours = { [d.bg] = true }
        d.edge = CreateFrame("Frame", nil, h)
        d.edge:SetAllPoints()
        d.edge:EnableMouse(false)
    end
    local on = M.db.skin
    for _, r in ipairs({ h:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and not d.ours[r] then r:SetAlpha(on and 0 or 1) end
    end
    local bg = EV.Theme.C.surface1 -- raised: tooltips and menus, like our own
    d.bg:SetColorTexture(bg[1], bg[2], bg[3], M.db.bgAlpha)
    d.bg:SetShown(on)
    local border = EV.Pixel:CreateBorder(d.edge, 1, unpack(EV.Theme.C.border))
    border.edges[2]:Hide() -- bottom: the tooltip's own top border closes the tab
    d.edge:SetShown(on)
    local label = h.Label or h.Text
    if on and label and label.SetFont then
        label:SetFont(ns.FontPath(), M.db.bodySize, ns.FontFlags())
        label:SetTextColor(EV.Theme.RGBA("textMuted"))
    end
end

-- Blizzard keeps re-anchoring comparison tooltips flush against the main
-- one (it refreshes them every frame while they're up), so moving them just
-- starts a fight. Instead the gap is drawn: a joined tooltip pulls its own
-- panel and border (ours) in by the gap on the side it touches. Nothing of
-- Blizzard's is moved.
local function JoinedSide(tt)
    local n = tt:GetNumPoints()
    for i = 1, n or 0 do
        local p, rel, rp = tt:GetPoint(i)
        if issecret(p) or issecret(rp) or issecret(rel) then return nil end
        if rel and rel ~= UIParent and rp then
            if p:find("LEFT") and rp:find("RIGHT") then return "LEFT" end
            if p:find("RIGHT") and rp:find("LEFT") then return "RIGHT" end
        end
    end
end

local function Inset(frame, d, l, r)
    for _, f in ipairs({ d.bg, d.edge }) do
        if f then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", frame, "TOPLEFT", l, 0)
            f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -r, 0)
        end
    end
end

local function Gap(tt)
    if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
    local d = state[tt]
    if not (d and d.bg) then return end
    local side = M.db.skin and M.db.compareGap > 0 and JoinedSide(tt) or nil
    local gap = side and EV.Pixel:One(tt) * M.db.compareGap or 0
    local key = (side or "none") .. gap
    if d.gapKey == key then return end
    d.gapKey = key
    local l, r = side == "LEFT" and gap or 0, side == "RIGHT" and gap or 0
    Inset(tt, d, l, r)
    -- The Equipped tab sits on the tooltip's left; keep it on the panel.
    local h = tt.CompareHeader
    local hd = h and state[h]
    if hd and hd.bg then Inset(h, hd, l, 0) end
end

local function SpaceComparisons()
    for tt in pairs(ns.COMPARE or {}) do Gap(tt) end
end
ns.SpaceComparisons = SpaceComparisons

--------------------------------------------------------------------------------
--  Item quality on the border
--------------------------------------------------------------------------------
local function QualityColour(q)
    if not q or issecret(q) then return nil end
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if r then return { r, g, b, 1 } end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and { c.r, c.g, c.b, 1 } or nil
end

local function OnItem(tt, data)
    -- Item data lands before the first OnShow, so the state may be new; Skin
    -- paints whatever we record here.
    if not (M.db.skin and M.db.qualityBorder) or not hooked[tt] or not Usable(tt) then return end
    D(tt)
    local q
    local id = data and data.id
    if id and not issecret(id) and C_Item and C_Item.GetItemQualityByID then
        q = C_Item.GetItemQualityByID(id)
    end
    if not q and tt.GetItem then
        local ok, _, link = pcall(tt.GetItem, tt)
        if ok and link and not issecret(link) and C_Item and C_Item.GetItemQualityByID then
            q = C_Item.GetItemQualityByID(link)
        end
    end
    -- Common and poor items keep the plain border.
    if q and not issecret(q) and q >= 2 then
        state[tt].quality = QualityColour(q)
    else
        state[tt].quality = nil
    end
    PaintBorder(tt)
end

--------------------------------------------------------------------------------
--  Health bar: slim, flat, inside the bottom edge
--------------------------------------------------------------------------------
local function StyleBar()
    local bar = GameTooltipStatusBar
    if not bar then return end
    local d = D(bar)
    bar:SetAlpha(M.db.healthBar and 1 or 0)
    if not M.db.skin then return end
    bar:SetStatusBarTexture(EV.Media:Fetch("statusbar", "Flat"))
    if not d.bg then
        d.bg = bar:CreateTexture(nil, "BACKGROUND")
        d.bg:SetAllPoints()
        d.bg:SetColorTexture(EV.Theme.RGBA("surfaceSunk", 0.8))
    end
    local one = EV.Pixel:One(GameTooltip)
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", GameTooltip, "BOTTOMLEFT", one, one)
    bar:SetPoint("BOTTOMRIGHT", GameTooltip, "BOTTOMRIGHT", -one, one)
    bar:SetHeight(EV.Pixel:Snap(GameTooltip, M.db.barHeight))
    bar:SetAlpha(M.db.healthBar and 1 or 0)
end
ns.StyleBar = StyleBar

--------------------------------------------------------------------------------
--  The aura tooltip every aura container button uses (engine-owned; styled
--  through the entry points Blizzard exposes for it)
--------------------------------------------------------------------------------
local function SyncAuraTooltip()
    local inb = _G.AuraContainerInbound
    if not inb then return end
    if M.db.skin and inb.SetTooltipBackdrop and CreateColor then
        local bg, bd = EV.Theme.C.surface1, EV.Theme.C.border
        pcall(inb.SetTooltipBackdrop, {
            backdropInfo = {
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            },
            centerColor = CreateColor(bg[1], bg[2], bg[3], M.db.bgAlpha),
            borderColor = CreateColor(bd[1], bd[2], bd[3], bd[4]),
        })
    elseif inb.ResetTooltipStyle then
        pcall(inb.ResetTooltipStyle)
    end
end

--------------------------------------------------------------------------------
--  Right-click menus. Blizzard styles every menu level through the style
--  mixin's Generate, copied onto each menu frame at open; a post-hook there
--  sees root menus and flyouts alike. We only collect in the hook and skin
--  from our own timer, and only recolour the regions the menu already has
--  (open menus refuse new textures).
--------------------------------------------------------------------------------
local menuOwned = setmetatable({}, { __mode = "k" })

local function SkinMenu(frame)
    if not (M.db.menus and frame) or (frame.IsForbidden and frame:IsForbidden()) then return end
    local bg = EV.Theme.C.surface1 -- raised: tooltips and menus, like our own
    local one = EV.Pixel:One(frame)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") and not menuOwned[r] then
            r:SetColorTexture(bg[1], bg[2], bg[3], 1)
            r:SetAlpha(M.db.bgAlpha)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", frame, "TOPLEFT", one, -one)
            r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -one, one)
        end
    end
    local d = D(frame)
    if not d.edge then
        local ok, edge = pcall(CreateFrame, "Frame", nil, frame)
        if not ok then return end
        d.edge = edge
        edge:SetAllPoints()
        edge:EnableMouse(false)
    end
    local ok, lvl = pcall(frame.GetFrameLevel, frame)
    if ok and lvl then d.edge:SetFrameLevel(lvl + 4) end
    EV.Pixel:CreateBorder(d.edge, 1, unpack(EV.Theme.C.border))
    d.edge:Show()
end

local pending, armed = {}, false
local function Flush()
    armed = false
    for i = #pending, 1, -1 do
        local f = pending[i]
        pending[i] = nil
        pcall(SkinMenu, f)
    end
end
local function Collect(frame)
    pending[#pending + 1] = frame
    if not armed then armed = true; C_Timer.After(0, Flush) end
end

--------------------------------------------------------------------------------
--  Menu rows: dividers, submenu arrows, checkboxes, radios and the hover
--  highlight, in our look. Blizzard builds each row through MenuVariants
--  (looked up on every call, and again whenever a row refreshes, say after
--  you tick a box), so a post-hook on each dresses every row as it's made.
--  Rows are built from pooled textures that Blizzard resets to defaults
--  when a row is released, and rows may not create textures of their own,
--  so we restyle Blizzard's textures in place.
--------------------------------------------------------------------------------
local UI_MEDIA = "Interface\\AddOns\\EvermoreUI\\Media\\UI\\"
local TH = EV.Theme

local function Glyph(tex, name, size, token)
    if not (tex and tex.SetTexture) then return end
    tex:SetTexture(UI_MEDIA .. name .. ".png")
    tex:SetTexCoord(0, 1, 0, 1)
    if size then tex:SetSize(size, size) end
    tex:SetVertexColor(TH.RGBA(token))
end

local function StyleSelection(frame, radio)
    local t1, t2 = frame.leftTexture1, frame.leftTexture2
    if not t1 then return end
    local selected = t2 ~= nil
    if radio then
        Glyph(t1, selected and "circle" or "ring", 14, selected and "accent" or "borderStrong")
        if t2 then
            Glyph(t2, "circle", 6, "onAccent")
            t2:ClearAllPoints()
            t2:SetPoint("CENTER", t1, "CENTER")
        end
    else
        Glyph(t1, selected and "boxfill" or "box", 14, selected and "accent" or "borderStrong")
        if t2 then
            Glyph(t2, "check", 12, "onAccent")
            t2:ClearAllPoints()
            t2:SetPoint("CENTER", t1, "CENTER")
        end
    end
end

local function StyleMenuRows()
    local V = _G.MenuVariants
    if type(V) ~= "table" then return end
    local function post(name, fn)
        if type(V[name]) == "function" then
            hooksecurefunc(V, name, function(...)
                if M.db.menus then pcall(fn, ...) end
            end)
        end
    end
    post("CreateCheckbox", function(_, frame) StyleSelection(frame, false) end)
    post("CreateRadio", function(_, frame) StyleSelection(frame, true) end)
    post("CreateSubmenuArrow", function(frame)
        local a = frame and frame.arrow
        Glyph(a, "chevron", 10, "textMuted")
    end)
    post("CreateHighlight", function(frame)
        local h = frame and frame.highlight
        if h and h.SetColorTexture then
            h:SetBlendMode("BLEND")
            h:SetColorTexture(TH.RGBA("surface3", 1))
        end
    end)
    -- A divider row holds just the one texture: a 1px line in the theme's
    -- divider colour, like ours.
    post("CreateDivider", function(frame)
        if not frame then return end
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.IsObjectType and r:IsObjectType("Texture") then
                local h = r:GetHeight()
                if h and not (issecretvalue and issecretvalue(h)) and h >= 8 then
                    r:SetColorTexture(TH.RGBA("divider"))
                    r:SetHeight(EV.Pixel:One(frame))
                end
            end
        end
    end)
end

local menusHooked = false
local function HookMenus()
    if menusHooked then return end
    menusHooked = true
    StyleMenuRows()
    local any = false
    for _, mixin in ipairs({ _G.MenuStyle1Mixin, _G.MenuStyle2Mixin }) do
        if type(mixin) == "table" and type(mixin.Generate) == "function" then
            hooksecurefunc(mixin, "Generate", Collect)
            any = true
        end
    end
    -- Older menus: skin the open root a few ticks after it opens.
    if not any and Menu and Menu.GetManager then
        local mgr = Menu.GetManager()
        local function later()
            for _, t in ipairs({ 0, 0.05, 0.15 }) do
                C_Timer.After(t, function()
                    local open = mgr.GetOpenMenu and mgr:GetOpenMenu()
                    if open then pcall(SkinMenu, open) end
                end)
            end
        end
        if mgr and mgr.OpenMenu then hooksecurefunc(mgr, "OpenMenu", later) end
        if mgr and mgr.OpenContextMenu then hooksecurefunc(mgr, "OpenContextMenu", later) end
    end
end

--------------------------------------------------------------------------------
--  Refresh and lifecycle
--------------------------------------------------------------------------------
function M:Refresh()
    if not self:IsEnabled() then return end
    for _, tt in ipairs(Tooltips()) do
        if tt then
            Hook(tt)
            if state[tt] and state[tt].bg then
                local on = self.db.skin
                state[tt].bg:SetShown(on)
                state[tt].edge:SetShown(on)
                if tt.NineSlice then tt.NineSlice:SetAlpha(on and 0 or 1) end
                if on then Skin(tt) end
            end
        end
    end
    for _, tt in ipairs(Tooltips()) do if tt then ns.SkinHeader(tt) end end
    StyleBar()
    SyncAuraTooltip()
    if ns.ApplyAnchor then ns.ApplyAnchor() end
end

function M:OnEnable()
    for _, tt in ipairs({ ShoppingTooltip1, ShoppingTooltip2, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 }) do
        if tt then COMPARE[tt] = true end
    end
    for _, tt in ipairs(Tooltips()) do if tt then Hook(tt) end end

    -- Blizzard re-applies its backdrop on some tooltips (and from secure code,
    -- e.g. the cast bar), so re-skin a tick later rather than inside it.
    if SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
            if hooked[tt] or state[tt] then C_Timer.After(0, function() Skin(tt) end) end
        end)
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
    end
    if ns.EnablePrice then ns.EnablePrice() end

    -- The bar is re-shown by Blizzard per unit; keep it hidden when it's off.
    if GameTooltipStatusBar then
        hooksecurefunc(GameTooltipStatusBar, "Show", function(bar)
            if not M.db.healthBar then bar:SetAlpha(0) end
        end)
    end

    -- Re-check the join whenever Blizzard re-anchors a comparison tooltip.
    for tt in pairs(COMPARE) do
        hooksecurefunc(tt, "SetPoint", Gap)
    end

    EV:RegisterSlash("tipdebug", function()
        for _, tt in ipairs({ GameTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
            if tt then
                EV:Print(tt:GetName(), tt:IsShown() and "shown" or "hidden")
                for i = 1, tt:GetNumPoints() or 0 do
                    local pt, rel, rp, x, y = tt:GetPoint(i)
                    print("   ", tostring(pt), rel and rel.GetName and rel:GetName() or tostring(rel), tostring(rp), tostring(x), tostring(y))
                end
            end
        end
    end)

    HookMenus()
    if ns.InitUnits then ns.InitUnits() end
    if ns.InitAnchor then ns.InitAnchor() end
    self:RegisterMessage("EV_PIXEL_CHANGED", function() StyleBar() end)
    -- Late-loading tooltips (Blizzard addons load on demand).
    self:RegisterEvent("ADDON_LOADED", function()
        for _, tt in ipairs(Tooltips()) do if tt then Hook(tt) end end
    end)
    self:Refresh()
end

function M:OnProfileChanged()
    if ns.SeedAnchor then ns.SeedAnchor() end
    self:Refresh()
end
