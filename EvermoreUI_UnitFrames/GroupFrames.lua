if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  GroupFrames.lua
--  Party and raid frames: the same frame as the player and target frames
--  (Frame.lua), laid out by the game's own secure group headers so they
--  sort, fill and follow roster changes in combat.
--
--  Forever has no secure snippets, and the header's usual way of sizing a
--  new frame (initialConfigFunction) is one. So every frame a header will
--  ever need is made up front, out of combat: the header is shown with a
--  negative startingIndex, which makes it create its full set of buttons at
--  once (5 for a party, 40 for a raid), and each is then sized and dressed
--  in plain Lua. In combat the header only moves, shows and hides frames it
--  already has, which it does from secure code.
--
--  A frame learns its unit from the header's "unit" attribute
--  (OnAttributeChanged), and events are routed by unit token to whichever
--  frames show it. On top of the shared frame, group frames carry a role,
--  leader and ready check icon, fade when out of range, and can show your
--  dispellable debuffs and your own buffs through engine aura containers,
--  whose filters keep working in restricted combat.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local UF = ns.Frame
local issecret = issecretvalue or function() return false end

local function Look(t)
    local base = {
        enabled = true, width = 200, height = 40, powerHeight = 6,
        portrait = "none", portraitSide = "left",
        healthColour = "class", healthText = "percent", powerText = "none",
        showName = true, showLevel = false, fontSize = 12, nameAlign = "LEFT",
        textStyle = "both", barShade = 0.75, texture = "Flat", bgAlpha = 0.85,
        borderSize = 1, innerShadow = true, healPrediction = true,
        aggroBorder = true, aggroAlpha = 0.35, aggroPad = 6,
        spacing = 6, rangeAlpha = 0.45,
        roleIcon = true, leaderIcon = true, readyCheck = true,
        debuffs = true, dispellableOnly = true, debuffSize = 18, debuffMax = 3,
        myBuffs = false, buffSize = 14, buffMax = 3,
        hideBlizzard = true,
    }
    for k, v in pairs(t) do base[k] = v end
    return base
end

local M = EV:NewModule("GroupFrames", {
    party = Look{ grow = "DOWN", showPlayer = true, sort = "index", raidStyle = false },
    raid  = Look{ width = 92, height = 42, powerHeight = 3, fontSize = 11, healthText = "none",
                  nameAlign = "CENTER", spacing = 3, layout = "columns", sort = "group",
                  roleIcon = true, leaderIcon = false, debuffSize = 14, debuffMax = 2 },
})
M.title = "Party & Raid"
M.description = "Party and raid frames in the style of the unit frames, with role, range, ready check and dispellable debuffs."
ns.group = M

local KINDS = { party = 5, raid = 40 }
local headers = {}      -- kind -> header
local children = {}     -- every dressed frame
local byUnit = {}       -- unit token -> { frame = true }
local hidden = CreateFrame("Frame")
hidden:Hide()
local pending = false

local function Cfg(f) return M.db[f.gkind] end

--------------------------------------------------------------------------------
--  Extra parts on a group frame
--------------------------------------------------------------------------------
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

local function Icon(f, size)
    local t = f.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    t:SetSize(size, size)
    t:Hide()
    return t
end

local function AuraHolder(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetFrameLevel(f:GetFrameLevel() + 6)
    h:SetSize(1, 1)
    return h
end

local function Extras(f)
    f.role = Icon(f, 12)
    f.leader = Icon(f, 12)
    f.ready = Icon(f, 16)
    f.debuffHolder = AuraHolder(f)
    f.buffHolder = AuraHolder(f)
end

local function LayoutExtras(f, cfg)
    local b = EV.Pixel:One(f) * (cfg.borderSize or 1)
    f.role:ClearAllPoints()
    f.role:SetPoint("TOPLEFT", f, "TOPLEFT", b + 2, -b - 2)
    f.leader:ClearAllPoints()
    f.leader:SetPoint("BOTTOMLEFT", f.role, "TOPLEFT", 0, -4)
    f.ready:ClearAllPoints()
    f.ready:SetPoint("CENTER", f.health, "CENTER", 0, 0)
    f.debuffHolder:ClearAllPoints()
    f.debuffHolder:SetPoint("BOTTOMRIGHT", f.health, "BOTTOMRIGHT", -2, 2)
    f.buffHolder:ClearAllPoints()
    f.buffHolder:SetPoint("TOPRIGHT", f.health, "TOPRIGHT", -2, -2)
    if cfg.nameAlign == "CENTER" then
        f.nameText:ClearAllPoints()
        f.nameText:SetPoint("CENTER", f.health, "CENTER", 0, cfg.healthText ~= "none" and 5 or 0)
        f.nameText:SetWidth(cfg.width - 8)
        f.nameText:SetJustifyH("CENTER")
        f.healthText:ClearAllPoints()
        f.healthText:SetPoint("TOP", f.nameText, "BOTTOM", 0, -1)
    else
        f.nameText:SetJustifyH("LEFT")
    end
end

--- Engine aura containers: your dispellable (or all) debuffs, your own buffs.
local function Auras(f, cfg)
    local C = ns.AuraBox
    if not C then return end
    C.Build(f.debuffHolder, cfg.debuffs and {
        unit = f.unit, filter = cfg.dispellableOnly and "HARMFUL|RAID" or "HARMFUL",
        size = cfg.debuffSize, max = cfg.debuffMax, dispel = true, grow = "LEFT",
    } or nil)
    C.Build(f.buffHolder, cfg.myBuffs and {
        unit = f.unit, filter = "HELPFUL|PLAYER", size = cfg.buffSize, max = cfg.buffMax, grow = "LEFT",
    } or nil)
end

function M.UpdateRole(f, cfg)
    local role = cfg.roleIcon and UnitGroupRolesAssigned and UnitGroupRolesAssigned(f.unit)
    local atlas = role and ROLE_ATLAS[role]
    if atlas then f.role:SetAtlas(atlas); f.role:Show() else f.role:Hide() end
end

function M.UpdateLeader(f, cfg)
    local tex
    if cfg.leaderIcon then
        if UnitIsGroupLeader(f.unit) then tex = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
        elseif UnitIsGroupAssistant and UnitIsGroupAssistant(f.unit) then tex = "Interface\\GroupFrame\\UI-Group-AssistantIcon" end
    end
    if tex then f.leader:SetTexture(tex); f.leader:Show() else f.leader:Hide() end
end

local READY = {
    ready = READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting = READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local readyActive = false

function M.UpdateReady(f, cfg)
    if not (cfg.readyCheck and readyActive) then f.ready:Hide(); return end
    local ok, status = pcall(GetReadyCheckStatus, f.unit)
    local tex = ok and READY[status]
    if tex then f.ready:SetTexture(tex); f.ready:Show() else f.ready:Hide() end
end

--- Out of range fades the frame. UnitInRange can come back secret; the
--- frame then fades through SetAlphaFromBoolean without us reading it.
function M.UpdateRange(f, cfg)
    local unit = f.unit
    if not unit or UnitIsUnit(unit, "player") then f:SetAlpha(1); return end
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if not ok then return end
    if issecret(inRange) or issecret(checked) then
        if f.SetAlphaFromBoolean then pcall(f.SetAlphaFromBoolean, f, inRange, 1, cfg.rangeAlpha) end
        return
    end
    if checked and not inRange then f:SetAlpha(cfg.rangeAlpha) else f:SetAlpha(1) end
end

local function UpdateAll(f)
    if not f.unit or not UnitExists(f.unit) then return end
    local cfg = Cfg(f)
    UF.UpdateAll(f, cfg)
    M.UpdateRole(f, cfg)
    M.UpdateLeader(f, cfg)
    M.UpdateReady(f, cfg)
    M.UpdateRange(f, cfg)
end
M.UpdateFrame = UpdateAll

--------------------------------------------------------------------------------
--  Units
--------------------------------------------------------------------------------
local function SetUnit(f, unit)
    if f.unit == unit then return end
    if f.unit and byUnit[f.unit] then byUnit[f.unit][f] = nil end
    f.unit = unit
    if unit then
        byUnit[unit] = byUnit[unit] or {}
        byUnit[unit][f] = true
    end
    -- The containers follow the unit even in combat: a roster change
    -- mid-fight hands this frame someone else, and SetUnit on an existing
    -- container is all that takes.
    Auras(f, Cfg(f))
    if unit and f:IsVisible() then UpdateAll(f) end
end

local function ForUnit(unit, fn)
    local set = byUnit[unit]
    if not set then return end
    for f in pairs(set) do
        if f.unit == unit and f:IsVisible() then fn(f, Cfg(f)) end
    end
end

local function ForAll(fn)
    for _, f in ipairs(children) do
        if f.unit and f:IsVisible() then fn(f, Cfg(f)) end
    end
end

--------------------------------------------------------------------------------
--  Headers
--------------------------------------------------------------------------------
local function Dress(f, kind)
    if f.gkind then return end
    UF.Dress(f, "group", nil)
    f.gkind = kind
    f:SetFrameStrata("LOW")
    Extras(f)
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[f] = true
    f:HookScript("OnAttributeChanged", function(self, name, value)
        if name == "unit" then SetUnit(self, value) end
    end)
    f:HookScript("OnShow", function(self) if self.unit then UpdateAll(self) end end)
    children[#children + 1] = f
    SetUnit(f, f:GetAttribute("unit"))
end

local function Visibility(kind)
    local db = M.db
    if not db[kind].enabled then return "hide" end
    if kind == "party" then
        if db.party.raidStyle then return "hide" end
        return "[group:raid] hide; [group:party] show; hide"
    end
    if db.party.raidStyle then return "[group:raid] show; [group:party] show; hide" end
    return "[group:raid] show; hide"
end

local GROW = {
    DOWN  = { point = "TOP",    x = 0,  y = -1 },
    UP    = { point = "BOTTOM", x = 0,  y = 1 },
    RIGHT = { point = "LEFT",   x = 1,  y = 0 },
    LEFT  = { point = "RIGHT",  x = -1, y = 0 },
}

local function Configure(kind)
    local h = headers[kind]
    local c = M.db[kind]
    local party = kind == "party"
    h:SetAttribute("_ignore", "attributeChanges")
    -- The raid header also shows a party when "use the raid frames in a
    -- party" is on, and then yourself if the party frames would have.
    local raidStyle = M.db.party.raidStyle
    h:SetAttribute("showPlayer", (party and c.showPlayer) or (not party and raidStyle and M.db.party.showPlayer) or false)
    h:SetAttribute("showParty", party or M.db.party.raidStyle)
    h:SetAttribute("showRaid", not party)
    h:SetAttribute("showSolo", false)
    if party then
        local g = GROW[c.grow] or GROW.DOWN
        h:SetAttribute("point", g.point)
        h:SetAttribute("xOffset", g.x * c.spacing)
        h:SetAttribute("yOffset", g.y * c.spacing)
        h:SetAttribute("maxColumns", 1)
        h:SetAttribute("unitsPerColumn", 5)
        h:SetAttribute("groupBy", c.sort == "role" and "ASSIGNEDROLE" or nil)
        h:SetAttribute("groupingOrder", c.sort == "role" and "TANK,HEALER,DAMAGER,NONE" or nil)
        h:SetAttribute("sortMethod", c.sort == "name" and "NAME" or "INDEX")
    else
        local cols = c.layout ~= "rows"
        h:SetAttribute("point", cols and "TOP" or "LEFT")
        h:SetAttribute("xOffset", cols and 0 or c.spacing)
        h:SetAttribute("yOffset", cols and -c.spacing or 0)
        h:SetAttribute("columnSpacing", c.spacing)
        h:SetAttribute("columnAnchorPoint", cols and "LEFT" or "TOP")
        h:SetAttribute("unitsPerColumn", 5)
        h:SetAttribute("maxColumns", 8)
        if c.sort == "role" then
            h:SetAttribute("groupBy", "ASSIGNEDROLE")
            h:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
        elseif c.sort == "class" then
            h:SetAttribute("groupBy", "CLASS")
            h:SetAttribute("groupingOrder", "WARRIOR,PALADIN,PRIEST,DRUID,SHAMAN,ROGUE,MAGE,WARLOCK,HUNTER")
        else
            h:SetAttribute("groupBy", "GROUP")
            h:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
        end
        h:SetAttribute("sortMethod", "INDEX")
    end
    h:SetAttribute("_ignore", nil)
end

--- Size and dress every frame the header has.
local function LayoutChildren(kind)
    local h = headers[kind]
    local c = M.db[kind]
    local i = 1
    while h[i] do
        local f = h[i]
        Dress(f, kind)
        UF.Layout(f, c)
        LayoutExtras(f, c)
        Auras(f, c)
        if f.unit then UpdateAll(f) end
        i = i + 1
    end
end

--- Make the header create every button it will ever need, now.
local function Spawn(kind)
    local h = headers[kind]
    local n = KINDS[kind]
    if h[n] then return end
    UnregisterStateDriver(h, "visibility")
    h:Show()
    h:SetAttribute("startingIndex", -n + 1)
    h:SetAttribute("startingIndex", 1)
    h:Hide()
end

local function Header(kind)
    if headers[kind] then return headers[kind] end
    local h = CreateFrame("Frame", "EvermoreUI_" .. kind .. "Header", UIParent, "SecureGroupHeaderTemplate")
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetFrameStrata("LOW")
    headers[kind] = h
    local c = M.db[kind]
    local sizeFor = function()
        local cc = M.db[kind]
        if kind == "party" then
            local vertical = cc.grow == "DOWN" or cc.grow == "UP"
            return vertical and cc.width or (cc.width * 5 + cc.spacing * 4),
                   vertical and (cc.height * 5 + cc.spacing * 4) or cc.height
        end
        return cc.width * 8 + cc.spacing * 7, cc.height * 5 + cc.spacing * 4
    end
    EV.Movers:Register(h, "GF_" .. kind, kind == "party" and L["Party"] or L["Raid"],
        kind == "party" and { "TOPLEFT", "TOPLEFT", 20, -240 } or { "TOPLEFT", "TOPLEFT", 20, -240 }, {
        group = L["Unit Frames"], page = "groupframes", tab = kind == "party" and L["Party"] or L["Raid"],
        getSize = sizeFor,
        isDisabled = function() return not (M:IsEnabled() and M.db[kind].enabled) end,
    })
    return h
end

--------------------------------------------------------------------------------
--  Blizzard's party and raid frames
--------------------------------------------------------------------------------
local function Retire(f)
    if not f or f.evRetired then return end
    f.evRetired = true
    if f.UnregisterAllEvents then pcall(f.UnregisterAllEvents, f) end
    pcall(f.Hide, f)
    pcall(f.SetParent, f, hidden)
end

local function RetireBlizzard()
    if M.db.party.enabled and M.db.party.hideBlizzard then
        Retire(PartyFrame)
        Retire(CompactPartyFrame)
        for i = 1, 4 do Retire(_G["PartyMemberFrame" .. i]) end
    end
    if M.db.raid.enabled and M.db.raid.hideBlizzard then
        Retire(CompactRaidFrameContainer)
        Retire(CompactRaidFrameManager)
    end
end

--------------------------------------------------------------------------------
--  Preview: stand-in frames for placing and sizing while you're on your own.
--  Plain frames drawn with the same parts, laid out the way the header lays
--  out the real ones, and anchored to the header so they move with it.
--------------------------------------------------------------------------------
M.preview = { party = false, raid = false }
local fakes = { party = {}, raid = {} }
local SAMPLE = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "PALADIN", "SHAMAN", "WARLOCK" }
local SAMPLE_ROLE = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }

local function Fake(kind, i)
    local f = fakes[kind][i]
    if f then return f end
    f = CreateFrame("Button", nil, UIParent)
    UF.Dress(f, "preview", nil)
    Extras(f)
    f:EnableMouse(false)
    f:SetFrameStrata("LOW")
    fakes[kind][i] = f
    return f
end

local function Place(kind, f, i, c)
    local h = headers[kind]
    local col, row = 0, i - 1
    local w, hh, sp = c.width, c.height, c.spacing
    f:ClearAllPoints()
    if kind == "party" then
        local g = c.grow or "DOWN"
        if g == "DOWN" then f:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -row * (hh + sp))
        elseif g == "UP" then f:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, row * (hh + sp))
        elseif g == "RIGHT" then f:SetPoint("TOPLEFT", h, "TOPLEFT", row * (w + sp), 0)
        else f:SetPoint("TOPRIGHT", h, "TOPRIGHT", -row * (w + sp), 0) end
        return
    end
    col, row = math.floor((i - 1) / 5), (i - 1) % 5
    if c.layout == "rows" then col, row = row, col end
    f:SetPoint("TOPLEFT", h, "TOPLEFT", col * (w + sp), -row * (hh + sp))
end

function ns.RefreshPreview()
    for kind, n in pairs({ party = 5, raid = 25 }) do
        local on = M.preview[kind] and M:IsEnabled() and M.db[kind].enabled and headers[kind] ~= nil
        local c = M.db[kind]
        for i = 1, n do
            if on then
                local f = Fake(kind, i)
                f.gkind = kind
                UF.Layout(f, c)
                LayoutExtras(f, c)
                Place(kind, f, i, c)
                local class = SAMPLE[(i - 1) % #SAMPLE + 1]
                local r, g, b = EV.Palette.ClassRGB(class)
                local k = c.barShade or 0.75
                f.health:SetMinMaxValues(0, 100)
                f.health:SetValue(100 - ((i * 37) % 60))
                f.health:SetStatusBarColor((r or 0.5) * k, (g or 0.5) * k, (b or 0.5) * k, 1)
                f.power:SetMinMaxValues(0, 100)
                f.power:SetValue(70)
                f.power:SetStatusBarColor(0.18 * k, 0.45 * k, 1 * k, 1)
                f.nameText:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class) .. " " .. i)
                f.healthText:SetText(c.healthText ~= "none" and ((100 - ((i * 37) % 60)) .. "%") or "")
                f.statusText:Hide()
                local role = c.roleIcon and ROLE_ATLAS[SAMPLE_ROLE[(i - 1) % 5 + 1]]
                if role then f.role:SetAtlas(role); f.role:Show() else f.role:Hide() end
                f:Show()
            elseif fakes[kind][i] then
                fakes[kind][i]:Hide()
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Applying settings
--------------------------------------------------------------------------------
function M:Apply()
    if InCombatLockdown() then pending = true; return end
    pending = false
    for kind in pairs(KINDS) do
        local h = Header(kind)
        Configure(kind)
        Spawn(kind)
        LayoutChildren(kind)
        RegisterStateDriver(h, "visibility", Visibility(kind))
        EV.Movers:Apply("GF_" .. kind)
    end
    if ns.ApplyClickCast then ns.ApplyClickCast() end
    if ns.RefreshPreview then ns.RefreshPreview() end
end

function M:Refresh() self:Apply() end
function M:OnProfileChanged() self:Apply() end

function M.Children() return children end

function M:OnEnable()
    RetireBlizzard()
    self:Apply()

    local function Health(_, _, unit) ForUnit(unit, UF.UpdateHealth) end
    local function Power(_, _, unit) ForUnit(unit, UF.UpdatePower) end
    local function Name(_, _, unit) ForUnit(unit, UF.UpdateName) end
    local function Whole(_, _, unit) ForUnit(unit, function(f) UpdateAll(f) end) end
    local function Everyone() ForAll(function(f) UpdateAll(f) end) end
    self:RegisterEvent("UNIT_HEALTH", Health)
    self:RegisterEvent("UNIT_MAXHEALTH", Health)
    self:RegisterEvent("UNIT_HEAL_PREDICTION", Health)
    self:RegisterEvent("UNIT_POWER_UPDATE", Power)
    self:RegisterEvent("UNIT_MAXPOWER", Power)
    self:RegisterEvent("UNIT_DISPLAYPOWER", Power)
    self:RegisterEvent("UNIT_NAME_UPDATE", Name)
    self:RegisterEvent("UNIT_CONNECTION", Whole)
    self:RegisterEvent("UNIT_FLAGS", Whole)
    self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", function(_, _, unit) ForUnit(unit, UF.UpdateAggro) end)
    self:RegisterEvent("RAID_TARGET_UPDATE", function() ForAll(function(f) UF.UpdateRaidIcon(f) end) end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", Everyone)
    self:RegisterEvent("PARTY_LEADER_CHANGED", function() ForAll(M.UpdateLeader) end)
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", function() ForAll(M.UpdateRole) end)
    self:RegisterEvent("READY_CHECK", function() readyActive = true; ForAll(M.UpdateReady) end)
    self:RegisterEvent("READY_CHECK_CONFIRM", function(_, _, unit) ForUnit(unit, M.UpdateReady) end)
    self:RegisterEvent("READY_CHECK_FINISHED", function()
        ForAll(M.UpdateReady)
        -- Leave the answers up for a moment, as Blizzard's frames do.
        C_Timer.After(6, function() readyActive = false; ForAll(M.UpdateReady) end)
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pending then self:Apply() end
        ForAll(UF.UpdateAggro)
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", Everyone)
    self:RegisterMessage("EV_PALETTE_CHANGED", function() self:Apply() end)
    self:RegisterMessage("EV_FONT_CHANGED", function() self:Apply() end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Apply() end)

    -- Range has no event; four times a second across what is shown.
    C_Timer.NewTicker(0.25, function() if M:IsEnabled() then ForAll(M.UpdateRange) end end)
end
