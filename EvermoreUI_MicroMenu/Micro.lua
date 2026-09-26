if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Micro.lua
--  Blizzard's micro buttons in an EvermoreUI bar, each drawn as a flat glyph
--  in a square cell: muted at rest, full text colour on hover, copper with
--  an accent bar when its panel is open. Blizzard's own art is faded by
--  vertex alpha (its code only ever changes SetAlpha on it), so its hover,
--  pushed and alert logic never brings it back.
--------------------------------------------------------------------------------
local _, ns = ...
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil

local M = EV:NewModule("MicroMenu", {
    genesis   = false,   -- first run: position copied from Blizzard's menu
    size      = 28,      -- cell width and height
    spacing   = 2,
    perRow    = 20,      -- buttons per row (per column when vertical)
    vertical  = false,
    grow      = "right", -- right / left, or down / up when vertical
    padding   = 3,       -- panel inset round the cells
    panel     = true,
    fade      = false,
    fadeAlpha = 0,
    petBattle = true,    -- hide during pet battles (Blizzard's pet battle UI has its own)
})
ns.micro = M
M.title = "Micro Menu"
M.description = "Blizzard's micro menu (character, spellbook, quests and the rest) as flat glyphs in an EvermoreUI bar."

-- Glyph per button; anything new falls back to Blizzard's icon, desaturated.
local GLYPH = {
    CharacterMicroButton    = "character",
    ProfessionMicroButton   = "professions",
    SpellbookMicroButton    = "spellbook",
    TalentMicroButton       = "talents",
    PlayerSpellsMicroButton = "talents",
    LegacyMicroButton       = "legacy",
    AchievementMicroButton  = "legacy",
    QuestLogMicroButton     = "questlog",
    HousingMicroButton      = "housing",
    GuildMicroButton        = "guild",
    LFDMicroButton          = "lfd",
    CollectionsMicroButton  = "collections",
    EJMicroButton           = "adventure",
    HelpMicroButton         = "help",
    StoreMicroButton        = "store",
    MainMenuMicroButton     = "menu",
}

-- Blizzard regions we fade. Alpha for the ones Blizzard only shows / hides;
-- vertex alpha for the ones it animates or re-alphas itself.
local FADE_ALPHA  = { "Background", "PushedBackground", "Shadow", "PushedShadow", "Portrait",
                      "Emblem", "HighlightEmblem", "MainMenuBarPerformanceBar" }
local FADE_VERTEX = { "FlashContent" }

local holder, fader
local buttons = {}           -- adopted, in Blizzard's order
local dressed = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
--  Look
--------------------------------------------------------------------------------
local function StateTextures(b)
    return b:GetNormalTexture(), b:GetPushedTexture(), b:GetDisabledTexture(), b:GetHighlightTexture()
end

local function Paint(b)
    local s = dressed[b]
    if not s then return end
    for _, t in ipairs({ StateTextures(b) }) do
        if t then t:SetVertexColor(1, 1, 1, 0) end
    end
    local open = b:GetButtonState() == "PUSHED"
    local hot = s.hover and b:IsEnabled()
    local token = open and "accent" or (hot and "text" or "textMuted")
    s.glyph:SetVertexColor(T.RGBA(token))
    s.glyph:SetDesaturated(s.fallback and not open or false)
    if open then
        s.cell:SetColorTexture(T.RGBA("surface2"))
    elseif hot then
        s.cell:SetColorTexture(T.RGBA("surface3"))
    else
        s.cell:SetColorTexture(T.RGBA("surface2", 0))
    end
    s.bar:SetShown(open)
    s.bar:SetColorTexture(T.RGBA("accent"))
    if b.FlashBorder then b.FlashBorder:SetColorTexture(T.RGBA("accent", 0.35)) end
end

local function Dress(b)
    if dressed[b] then return Paint(b) end
    local s = {}

    for _, k in ipairs(FADE_ALPHA) do
        local r = rawget(b, k)
        if type(r) == "table" and r.SetAlpha then r:SetAlpha(0) end
    end
    for _, k in ipairs(FADE_VERTEX) do
        local r = rawget(b, k)
        if type(r) == "table" and r.SetVertexColor then r:SetVertexColor(1, 1, 1, 0) end
    end

    -- Our cell, glyph and open-panel bar.
    s.cell = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    s.cell:SetPoint("TOPLEFT", 0, 0)
    s.cell:SetPoint("BOTTOMRIGHT", 0, 0)
    s.glyph = b:CreateTexture(nil, "ARTWORK", nil, 2)
    s.glyph:SetPoint("CENTER")
    local name = b:GetName()
    if name and GLYPH[name] then
        s.glyph:SetTexture(ns.GLYPH .. GLYPH[name] .. ".png")
    else
        s.fallback = true
        local atlas = b.textureName and ("UI-HUD-MicroMenu-" .. b.textureName .. "-Up")
        if atlas and C_Texture.GetAtlasInfo(atlas) then s.glyph:SetAtlas(atlas) else s.glyph:SetTexture(ns.GLYPH .. "menu.png") end
    end
    s.bar = b:CreateTexture(nil, "OVERLAY", nil, 2)
    s.bar:SetHeight(2)
    s.bar:SetPoint("BOTTOMLEFT", 3, 1)
    s.bar:SetPoint("BOTTOMRIGHT", -3, 1)

    -- Alerts: Blizzard's flash border pulses; ours is a copper wash.
    if b.FlashBorder then
        b.FlashBorder:ClearAllPoints()
        b.FlashBorder:SetAllPoints(b)
    end
    -- Notification pip (new guild invite, etc.) in the top-right corner.
    local note = b.NotificationOverlay
    if note then
        for _, r in ipairs({ note:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" then
                r:ClearAllPoints()
                r:SetPoint("TOPRIGHT", b, "TOPRIGHT", 2, 2)
                r:SetSize(12, 12)
            end
        end
    end

    b:HookScript("OnEnter", function(self) s.hover = true; Paint(self) end)
    b:HookScript("OnLeave", function(self) s.hover = false; Paint(self) end)
    b:HookScript("OnEnable", Paint)
    b:HookScript("OnDisable", Paint)
    -- Open / closed panel, and Blizzard re-setting its highlight atlas.
    for _, method in ipairs({ "SetPushed", "SetNormal" }) do
        if type(b[method]) == "function" then hooksecurefunc(b, method, Paint) end
    end
    hooksecurefunc(b, "SetButtonState", Paint)
    s.Paint = function() Paint(b) end
    dressed[b] = s
    T.Watch(s)
    Paint(b)
end

--------------------------------------------------------------------------------
--  Layout
--------------------------------------------------------------------------------
local function DoLayout()
    if not holder then return end
    local cfg = M.db
    local size, gap = cfg.size, cfg.spacing
    local pad = cfg.panel and cfg.padding or 0
    local shown = {}
    for _, b in ipairs(buttons) do
        if b:IsShown() then
            shown[#shown + 1] = b
        else
            -- Hidden ones still come with us. Left behind, they stay
            -- children of Blizzard's MicroMenu with a layoutIndex and no
            -- screen rect, and its own GetEdgeButton then compares two nil
            -- values whenever Edit Mode opens or closes.
            ns.Place(b, holder, pad, -pad, size, size)
        end
    end
    local n = max(#shown, 1)
    local per = max(1, min(n, cfg.perRow))
    local lines = ceil(n / per)
    local vertical = cfg.vertical
    local grow = ns.Grow(cfg, "right", "down")
    local cols, rows = per, lines
    if vertical then cols, rows = lines, per end
    holder:SetSize(cols * size + (cols - 1) * gap + pad * 2, rows * size + (rows - 1) * gap + pad * 2)
    for i, b in ipairs(shown) do
        local line, pos = floor((i - 1) / per), (i - 1) % per
        local r, c
        if vertical then
            c, r = line, pos
            if grow == "up" then r = rows - 1 - r end
        else
            r, c = line, pos
            if grow == "left" then c = cols - 1 - c end
        end
        ns.Place(b, holder, pad + c * (size + gap), -(pad + r * (size + gap)), size, size)
        Dress(b)
        local s = dressed[b]
        local g = floor(size * 0.62 + 0.5)
        s.glyph:SetSize(g, g)
    end
    holder:SetPanel(cfg.panel)
    EV.Movers:Apply("MicroMenu")
    if fader then fader.Update(true) end
end

-- The first button stays put on screen; the bar grows away from it.
local function Layout()
    local first
    for _, b in ipairs(buttons) do if b:IsShown() then first = b; break end end
    ns.Keep(holder, "MicroMenu", first, DoLayout)
end
ns.MicroLayout = Layout

-- A button showing or hiding (Blizzard's rules for the shop, help, etc.)
-- reflows the bar straight away, so nothing sits in a stale slot.
local busy = false
local function Reflow()
    if busy then return end
    busy = true
    ns.Safe("microlayout", Layout)
    busy = false
end

--------------------------------------------------------------------------------
--  Adoption
--------------------------------------------------------------------------------
local function Collect()
    local list = {}
    if MicroMenu then
        for _, c in ipairs({ MicroMenu:GetChildren() }) do
            if c.layoutIndex then list[#list + 1] = c end
        end
    end
    table.sort(list, function(a, b) return a.layoutIndex < b.layoutIndex end)
    return list
end

local function Genesis()
    if M.db.genesis then return end
    M.db.genesis = true
    local x, y = ns.CentreOf(MicroMenu)
    local core = EV.DB:GetCore()
    if x and not core.movers.MicroMenu then core.movers.MicroMenu = { "CENTER", "CENTER", x, y } end
end

local adopted = false
local function Adopt()
    if adopted or not MicroMenu then return end
    adopted = true
    buttons = Collect()
    Genesis()
    holder = ns.Holder("EvermoreUIMicroMenu")
    EV.Movers:Register(holder, "MicroMenu", L["Micro Menu"], { "BOTTOMRIGHT", "BOTTOMRIGHT", -6, 6 }, {
        group = L["Micro Menu & Bags"], page = "micromenu",
    })
    fader = ns.Fader(holder, function() return M.db end)
    for _, b in ipairs(buttons) do
        b:HookScript("OnShow", Reflow)
        b:HookScript("OnHide", Reflow)
        fader.Watch(b)
    end
    Layout()
    ns.Park(MicroMenuContainer)
end

--------------------------------------------------------------------------------
--  Visibility: step aside for pet battles, like Blizzard's menu does.
--------------------------------------------------------------------------------
local function UpdateShown()
    if not holder then return end
    local battle = C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle()
    holder:SetShown(not (M.db.petBattle and battle))
end

function M:Refresh()
    if not adopted then return end
    ns.Safe("microlayout", Layout)
    UpdateShown()
end

--------------------------------------------------------------------------------
--  Training badge: a count on the spellbook button when spells are ready to
--  train (EV_TRAINING_CHANGED from the QoL module's Training.lua). Drawn on our
--  own font string on the button; nothing of Blizzard's is changed.
--------------------------------------------------------------------------------
local badge
local function SpellbookButton()
    for _, name in ipairs({ "SpellbookMicroButton", "PlayerSpellsMicroButton" }) do
        local b = _G[name]
        if b and b:IsShown() then return b end
    end
    return _G.SpellbookMicroButton or _G.PlayerSpellsMicroButton
end

local function ShowBadge(count)
    local qol = EV:GetModule("QoL", true)
    local want = qol and qol.db and qol.db.trainingBadge and qol:IsEnabled()
    local b = SpellbookButton()
    if not b then return end
    if not badge then
        badge = CreateFrame("Frame", nil, b)
        badge:SetSize(16, 14)
        badge.bg = badge:CreateTexture(nil, "OVERLAY", nil, 6)
        badge.bg:SetAllPoints()
        badge.text = badge:CreateFontString(nil, "OVERLAY")
        badge.text:SetPoint("CENTER", 0, 0)
        T.Watch(badge)
        function badge:Paint()
            self.bg:SetColorTexture(T.RGBA("accent"))
            self.text:SetTextColor(T.RGBA("onAccent"))
        end
    end
    if badge:GetParent() ~= b then badge:SetParent(b) end
    badge:ClearAllPoints()
    badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 1, 1)
    badge:SetFrameLevel(b:GetFrameLevel() + 5)
    badge.text:SetFont(EV.Media:FetchBold(), 10, "")
    badge:Paint()
    count = tonumber(count) or 0
    if want and count > 0 then
        badge.text:SetText(count > 9 and "9+" or tostring(count))
        badge:SetWidth(math.max(14, badge.text:GetStringWidth() + 6))
        badge:Show()
    else
        badge:Hide()
    end
end

function M:OnEnable()
    ns.Safe("microadopt", Adopt)
    self:RegisterMessage("EV_TRAINING_CHANGED", function(_, _, count) ns.Safe("training badge", ShowBadge, count) end)
    UpdateShown()
    self:RegisterEvent("PET_BATTLE_OPENING_START", UpdateShown)
    self:RegisterEvent("PET_BATTLE_CLOSE", UpdateShown)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
end

function M:OnProfileChanged() self:Refresh() end
