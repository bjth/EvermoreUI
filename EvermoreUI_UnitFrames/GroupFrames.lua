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

--  Where each part sits: text by a point on its bar plus an offset (as the
--  unit frames), icons centred on a point of the frame plus an offset, aura
--  rows by a point on the health bar with the row growing away from it. All
--  offsets are in frame units. The defaults are the layout these frames
--  always had.
local function Look(t)
    local base = {
        enabled = true, width = 200, height = 40, powerHeight = 6,
        portrait = "none", portraitSide = "left",
        healthColour = "class", healthText = "percent", powerText = "none",
        showName = true, showLevel = false, fontSize = 12, font = "",
        namePoint = "LEFT", nameX = 5, nameY = 0, nameWidth = 0,
        healthPoint = "RIGHT", healthX = -5, healthY = 0,
        textStyle = "both", barShade = 0.75, texture = "Flat", bgAlpha = 0.85,
        borderSize = 1, innerShadow = true, healPrediction = true,
        aggroBorder = true, aggroAlpha = 0.35, aggroPad = 6,
        spacing = 6, rangeAlpha = 0.45,
        roleIcon = true, roleIconPoint = "TOPLEFT", roleIconX = 9, roleIconY = -9, roleIconSize = 12,
        leaderIcon = true, leaderIconPoint = "TOPLEFT", leaderIconX = 9, leaderIconY = -1, leaderIconSize = 12,
        readyCheck = true, readyIconPoint = "CENTER", readyIconX = 0, readyIconY = 0, readyIconSize = 16,
        raidIconPoint = "TOP", raidIconX = 0, raidIconY = 0, raidIconSize = 18,
        debuffs = true, dispellableOnly = true, debuffSize = 18, debuffMax = 3,
        debuffPoint = "BOTTOMRIGHT", debuffX = -2, debuffY = 2, debuffGrow = "LEFT",
        myBuffs = false, buffSize = 14, buffMax = 3,
        buffPoint = "TOPRIGHT", buffX = -2, buffY = -2, buffGrow = "LEFT",
        hideBlizzard = true,
    }
    for k, v in pairs(t) do base[k] = v end
    return base
end

local M = EV:NewModule("GroupFrames", {
    party = Look{ grow = "DOWN", showPlayer = true, sort = "index", raidStyle = false },
    raid  = Look{ width = 92, height = 42, powerHeight = 3, fontSize = 11, healthText = "none",
                  namePoint = "CENTER", nameX = 0, nameY = 0, healthPoint = "CENTER", healthX = 0, healthY = -7,
                  spacing = 3, layout = "columns", sort = "group",
                  roleIcon = true, leaderIcon = false, debuffSize = 14, debuffMax = 2 },
})
M.title = "Party & Raid"
M.description = "Party and raid frames in the style of the unit frames, with role, range, ready check and dispellable debuffs."
ns.group = M

local KINDS = { party = 5, raid = 40 }
local headers = {}      -- kind -> header
local holders = {}      -- kind -> the frame edit mode moves (below)
local children = {}     -- every dressed frame
local byUnit = {}       -- unit token -> { frame = true }
local hidden = CreateFrame("Frame")
hidden:Hide()
local pending = false

local function Cfg(f) return M.db[f.gkind] end

--- Before the parts could be placed one by one, the name was either left
--- or centred (nameAlign, left for a party and centred for a raid unless
--- changed), and a centred name moved up to make room for the health text
--- under it. Once per profile, that becomes the matching positions.
local OLD_ALIGN = { party = "LEFT", raid = "CENTER" }
local function Migrate()
    for kind, c in pairs({ party = M.db.party, raid = M.db.raid }) do
        if not c.placed then
            local a = rawget(c, "nameAlign") or OLD_ALIGN[kind]
            if a == "CENTER" then
                c.namePoint, c.nameX, c.nameY = "CENTER", 0, c.healthText ~= "none" and 5 or 0
                c.healthPoint, c.healthX, c.healthY = "CENTER", 0, -7
            else
                c.namePoint, c.nameX, c.nameY = "LEFT", 5, 0
                c.healthPoint, c.healthX, c.healthY = "RIGHT", -5, 0
            end
            c.nameAlign = nil
            c.placed = true
        end
    end
end
M.Migrate = Migrate

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

-- The leader icon is the one the single frames use (Frame.lua places it
-- from leaderIcon* and shows it in UF.UpdateIndicators).
local function Extras(f)
    f.role = Icon(f, 12)
    f.leaderIcon = Icon(f, 12)
    f.ready = Icon(f, 16)
    f.debuffHolder = AuraHolder(f)
    f.buffHolder = AuraHolder(f)
end

local POINTS = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
                 BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local function Point(v, fallback) return POINTS[v] and v or fallback end

--- The width of an aura row: every icon it may show, with the gap AuraBox uses.
local function RowWidth(size, n) return n * size + (n - 1) * 2 end
M.RowWidth = RowWidth

local function LayoutExtras(f, cfg)
    local function At(icon, parent, point, fallback, x, y, size)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", parent, Point(point, fallback), x or 0, y or 0)
    end
    At(f.role, f, cfg.roleIconPoint, "TOPLEFT", cfg.roleIconX, cfg.roleIconY, cfg.roleIconSize or 12)
    At(f.ready, f.health, cfg.readyIconPoint, "CENTER", cfg.readyIconX, cfg.readyIconY, cfg.readyIconSize or 16)
    -- Each aura row is a box as big as it can get, pinned by its own point
    -- to the same point of the health bar; the icons fill it from the end
    -- they grow away from.
    local function Row(holder, point, fallback, x, y, size, n)
        holder:ClearAllPoints()
        point = Point(point, fallback)
        holder:SetPoint(point, f.health, point, x or 0, y or 0)
        holder:SetSize(RowWidth(size, n), size)
    end
    Row(f.debuffHolder, cfg.debuffPoint, "BOTTOMRIGHT", cfg.debuffX, cfg.debuffY, cfg.debuffSize, cfg.debuffMax)
    Row(f.buffHolder, cfg.buffPoint, "TOPRIGHT", cfg.buffX, cfg.buffY, cfg.buffSize, cfg.buffMax)
end
M.LayoutExtras = LayoutExtras

--- Engine aura containers: your dispellable (or all) debuffs, your own buffs.
local function Auras(f, cfg)
    local C = ns.AuraBox
    if not C then return end
    C.Build(f.debuffHolder, cfg.debuffs and {
        unit = f.unit, filter = cfg.dispellableOnly and "HARMFUL|RAID" or "HARMFUL",
        size = cfg.debuffSize, max = cfg.debuffMax, dispel = true, grow = cfg.debuffGrow or "LEFT",
    } or nil)
    C.Build(f.buffHolder, cfg.myBuffs and {
        unit = f.unit, filter = "HELPFUL|PLAYER", size = cfg.buffSize, max = cfg.buffMax, grow = cfg.buffGrow or "LEFT",
    } or nil)
end

function M.UpdateRole(f, cfg)
    local role = cfg.roleIcon and UnitGroupRolesAssigned and UnitGroupRolesAssigned(f.unit)
    local atlas = role and ROLE_ATLAS[role]
    if atlas then f.role:SetAtlas(atlas); f.role:Show() else f.role:Hide() end
end

function M.UpdateLeader(f, cfg) UF.UpdateIndicators(f, cfg) end

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

--- The space a whole group takes: five (four without you) or a full raid.
local function FullSize(kind)
    local c = M.db[kind]
    local w, h, sp = c.width, c.height, c.spacing
    if kind == "party" then
        local n = c.showPlayer and 5 or 4
        local vertical = c.grow ~= "RIGHT" and c.grow ~= "LEFT"
        return vertical and w or (w * n + sp * (n - 1)), vertical and (h * n + sp * (n - 1)) or h
    end
    local cols, rows = 8, 5
    if c.layout == "rows" then cols, rows = rows, cols end
    return w * cols + sp * (cols - 1), h * rows + sp * (rows - 1)
end

--- The corner a group grows from, which the header is pinned by.
local function StartCorner(kind)
    if kind == "raid" then return "TOPLEFT" end
    local g = M.db.party.grow
    if g == "UP" then return "BOTTOMLEFT" elseif g == "LEFT" then return "TOPRIGHT" end
    return "TOPLEFT"
end

-- Edit mode moves a holder, not the header. The header sizes itself to the
-- frames it shows (almost nothing when you're on your own, so it couldn't
-- be seen or grabbed), and pinned by its centre it would slide about as
-- people joined. The holder is always the full group's size, and the header
-- hangs from its starting corner, so the first frame never moves.
-- The holder carries protected frames, so it is only moved out of combat
-- (secure = true in Movers).
local function Header(kind)
    if headers[kind] then return headers[kind] end
    local holder = CreateFrame("Frame", "EvermoreUI_" .. kind .. "Holder", UIParent)
    holder:SetSize(FullSize(kind))
    holders[kind] = holder
    local h = CreateFrame("Frame", "EvermoreUI_" .. kind .. "Header", UIParent, "SecureGroupHeaderTemplate")
    h:SetAttribute("template", "SecureUnitButtonTemplate")
    h:SetAttribute("templateType", "Button")
    h:SetFrameStrata("LOW")
    headers[kind] = h
    EV.Movers:Register(holder, "GF_" .. kind, kind == "party" and L["Party"] or L["Raid"],
        { "TOPLEFT", "TOPLEFT", 20, -240 }, {
        group = L["Unit Frames"], page = "groupframes", designer = "groupframes", designerTab = kind,
        secure = true,
        isDisabled = function() return not (M:IsEnabled() and M.db[kind].enabled) end,
    })
    return h
end

--- Size the holder and pin the header to it. Out of combat.
local function Pin(kind)
    local holder, h = holders[kind], headers[kind]
    EV.Pixel:SetSize(holder, FullSize(kind))
    local corner = StartCorner(kind)
    h:ClearAllPoints()
    h:SetPoint(corner, holder, corner, 0, 0)
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
local SAMPLE_ICONS = { 136207, 135940, 136085, 135953, 136096, 135987 }

--- A plain frame with a group frame's parts, for stand-ins and the designer.
--- It is never offered to click casting and never takes the mouse.
local function Stand(parent)
    local f = CreateFrame("Button", nil, parent or UIParent)
    UF.Dress(f, "preview", nil, true)
    Extras(f)
    f:EnableMouse(false)
    return f
end
M.Stand = Stand

--- Sample icons filling an aura row, so it can be seen and placed.
local function SampleRow(holder, on, size, n, grow, dispel)
    holder.samples = holder.samples or {}
    for i = 1, math.max(n, #holder.samples) do
        local t = holder.samples[i]
        if i <= n and on then
            if not t then
                t = CreateFrame("Frame", nil, holder)
                t.back = t:CreateTexture(nil, "BACKGROUND")
                t.back:SetAllPoints()
                t.icon = t:CreateTexture(nil, "ARTWORK")
                t.icon:SetTexCoord(EV.Icons:Coords())
                holder.samples[i] = t
            end
            local one = EV.Pixel:One(holder)
            t:SetSize(size, size)
            t:ClearAllPoints()
            local edge = grow == "RIGHT" and "LEFT" or "RIGHT"
            t:SetPoint(edge, holder, edge, (grow == "RIGHT" and 1 or -1) * (i - 1) * (size + 2), 0)
            if dispel then t.back:SetColorTexture(0.6, 0.2, 0.8, 1) else t.back:SetColorTexture(0, 0, 0, 1) end
            t.icon:ClearAllPoints()
            t.icon:SetPoint("TOPLEFT", one, -one)
            t.icon:SetPoint("BOTTOMRIGHT", -one, one)
            t.icon:SetTexture(SAMPLE_ICONS[(i - 1) % #SAMPLE_ICONS + 1])
            t:Show()
        elseif t then
            t:Hide()
        end
    end
end

--- Dress a stand-in with made-up values: the i-th member of a group.
--- `first` also shows the parts that only some members have (leader, a
--- ready check answer, a raid mark), so each can be seen.
local function Sample(f, kind, i, c, first)
    f.gkind = kind
    UF.Layout(f, c)
    LayoutExtras(f, c)
    local class = SAMPLE[(i - 1) % #SAMPLE + 1]
    local r, g, b = EV.Palette.ClassRGB(class)
    local k = c.barShade or 0.75
    local hp = 100 - ((i * 37) % 60)
    f.health:SetMinMaxValues(0, 100)
    f.health:SetValue(hp)
    if c.healthColour == "green" then f.health:SetStatusBarColor(0.2 * k, 0.8 * k, 0.2 * k, 1)
    elseif c.healthColour == "dark" then f.health:SetStatusBarColor(0.16, 0.16, 0.16, 1)
    else f.health:SetStatusBarColor((r or 0.5) * k, (g or 0.5) * k, (b or 0.5) * k, 1) end
    -- The empty part, as the real frames colour it (they do it from the unit).
    if c.healthColour == "dark" then
        f.health.bg:SetVertexColor((r or 0.5) * k, (g or 0.5) * k, (b or 0.5) * k, 0.55)
    else
        f.health.bg:SetVertexColor(UF.HealthBG(c))
    end
    f.power:SetMinMaxValues(0, 100)
    f.power:SetValue(70)
    f.power:SetStatusBarColor(0.18 * k, 0.45 * k, 1 * k, 1)
    f.nameText:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class) .. " " .. i)
    local texts = { percent = hp .. "%", deficit = "-" .. (100 - hp) * 30, current = (hp * 30 / 1000) .. "k" }
    f.healthText:SetText(texts[c.healthText] or "")
    f.healthText:SetShown(c.healthText ~= "none")
    f.powerText:SetText("")
    f.statusText:Hide()
    local role = c.roleIcon and ROLE_ATLAS[SAMPLE_ROLE[(i - 1) % 5 + 1]]
    if role then f.role:SetAtlas(role); f.role:Show() else f.role:Hide() end
    if first and c.leaderIcon then
        f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        f.leaderIcon:Show()
    else
        f.leaderIcon:Hide()
    end
    if first and c.readyCheck then f.ready:SetTexture(READY.ready); f.ready:Show() else f.ready:Hide() end
    if first and f.raidIcon then
        if SetRaidTargetIconTexture then SetRaidTargetIconTexture(f.raidIcon, 1) end
        f.raidIcon:Show()
    elseif f.raidIcon then
        f.raidIcon:Hide()
    end
    SampleRow(f.debuffHolder, c.debuffs, c.debuffSize, i == 1 and c.debuffMax or math.min(c.debuffMax, 1),
              c.debuffGrow, c.dispellableOnly)
    SampleRow(f.buffHolder, c.myBuffs, c.buffSize, c.buffMax, c.buffGrow)
    f:SetAlpha(1)
    f:Show()
end

--- Where the i-th frame sits relative to `anchor`, the way the header lays
--- the real ones out.
local function Place(kind, f, i, c, anchor)
    local col, row = 0, i - 1
    local w, hh, sp = c.width, c.height, c.spacing
    f:ClearAllPoints()
    if kind == "party" then
        local g = c.grow or "DOWN"
        if g == "DOWN" then f:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -row * (hh + sp))
        elseif g == "UP" then f:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, row * (hh + sp))
        elseif g == "RIGHT" then f:SetPoint("TOPLEFT", anchor, "TOPLEFT", row * (w + sp), 0)
        else f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -row * (w + sp), 0) end
        return
    end
    col, row = math.floor((i - 1) / 5), (i - 1) % 5
    if c.layout == "rows" then col, row = row, col end
    f:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (w + sp), -row * (hh + sp))
end

--- The size of `n` frames laid out that way.
local function Extent(kind, c, n)
    local w, h, sp = c.width, c.height, c.spacing
    if kind == "party" then
        local vertical = c.grow ~= "RIGHT" and c.grow ~= "LEFT"
        return vertical and w or (w * n + sp * (n - 1)), vertical and (h * n + sp * (n - 1)) or h
    end
    local cols, rows = math.ceil(n / 5), math.min(n, 5)
    if c.layout == "rows" then cols, rows = rows, cols end
    return w * cols + sp * (cols - 1), h * rows + sp * (rows - 1)
end
M.Extent = Extent

--- How many frames a sample group shows: a party is four without you.
local function SampleCount(kind, full)
    if kind == "party" and not M.db.party.showPlayer then return full - 1 end
    return full
end

function ns.RefreshPreview()
    for kind, n in pairs({ party = 5, raid = 25 }) do
        local on = M.preview[kind] and M:IsEnabled() and M.db[kind].enabled and holders[kind] ~= nil
        local c = M.db[kind]
        local shown = SampleCount(kind, n)
        for i = 1, n do
            if on and i <= shown then
                local f = fakes[kind][i]
                if not f then
                    f = Stand(UIParent)
                    f:SetFrameStrata("LOW")
                    fakes[kind][i] = f
                end
                Sample(f, kind, i, c, i == 1)
                Place(kind, f, i, c, holders[kind])
            elseif fakes[kind][i] then
                fakes[kind][i]:Hide()
            end
        end
    end
end

--------------------------------------------------------------------------------
--  The designer's copy: a party of five or three raid groups, in a holder
--  sized to them. The first frame is the one whose parts are picked.
--------------------------------------------------------------------------------
local DESIGN_COUNT = { party = 5, raid = 15 }

function M:BuildDesignerPreview(kind, host)
    local pv = CreateFrame("Frame", nil, host)
    pv.kind = kind
    pv.frames = {}
    for i = 1, DESIGN_COUNT[kind] do pv.frames[i] = Stand(pv) end
    return pv
end

function M:LayoutDesignerPreview(pv)
    local kind = pv.kind
    local c = M.db[kind]
    local n = SampleCount(kind, #pv.frames)
    local w, h = Extent(kind, c, n)
    pv:SetSize(w, h)
    for i, f in ipairs(pv.frames) do
        if i <= n then
            f:SetFrameLevel(pv:GetFrameLevel() + 2)
            Sample(f, kind, i, c, i == 1)
            Place(kind, f, i, c, pv)
        else
            f:Hide()
        end
    end
    pv.first = pv.frames[1]
end

--------------------------------------------------------------------------------
--  Applying settings
--------------------------------------------------------------------------------
function M:Apply()
    if EV:Locked() then pending = true; return end
    -- Loading after a reload in combat: set up now so the group shows, and
    -- once more when combat ends in case any of it didn't take.
    pending = InCombatLockdown()
    for kind in pairs(KINDS) do
        local h = Header(kind)
        Configure(kind)
        Pin(kind)
        Spawn(kind)
        LayoutChildren(kind)
        RegisterStateDriver(h, "visibility", Visibility(kind))
        EV.Movers:Apply("GF_" .. kind)
    end
    if ns.ApplyClickCast then ns.ApplyClickCast() end
    if ns.RefreshPreview then ns.RefreshPreview() end
end

--- One report line per header: what the game has done with it, for when a
--- group doesn't show. Read-only; safe in combat.
local function Diagnose()
    local out = {}
    for _, kind in ipairs({ "party", "raid" }) do
        local h = headers[kind]
        if h then
            local shown, first = 0, nil
            local i = 1
            while h[i] do
                if h[i]:IsShown() then shown = shown + 1 end
                if not first and h[i]:GetAttribute("unit") then first = h[i] end
                i = i + 1
            end
            local line = ("%s: header %s/%s state %s, %d of %d shown"):format(kind,
                h:IsShown() and "shown" or "hidden", h:IsVisible() and "visible" or "not visible",
                tostring(h:GetAttribute("state-visibility")), shown, i - 1)
            if first then
                line = line .. (" first %s %s alpha %.2f size %dx%d points %d"):format(
                    tostring(first:GetAttribute("unit")), first:IsShown() and "shown" or "hidden",
                    first:GetAlpha(), first:GetWidth(), first:GetHeight(), first:GetNumPoints())
            end
            out[#out + 1] = line
        end
    end
    out[#out + 1] = ("group %s raid %s combat %s pending %s"):format(tostring(IsInGroup()),
        tostring(IsInRaid()), tostring(InCombatLockdown()), tostring(pending))
    return "Group frames: " .. table.concat(out, "; ")
end

function M:Refresh() self:Apply() end
function M:OnProfileChanged() Migrate(); self:Apply() end

function M.Children() return children end

function M:OnEnable()
    if EV.Report and EV.Report.AddLine and not M.inReport then
        M.inReport = true
        EV.Report:AddLine(function() local ok, line = pcall(Diagnose); return ok and line or nil end)
    end
    Migrate()
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
