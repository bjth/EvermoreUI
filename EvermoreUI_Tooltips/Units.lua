if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Units.lua
--  What goes on a unit tooltip: class-coloured name and health bar, titles
--  hidden, guild rank, who they're targeting, item level (inspected quietly
--  and cached), and spell/item IDs for addon work.
--
--  Identity comes from the tooltip's own data (data.guid), never the
--  "mouseover" token, which can lag a frame behind the cursor. Anything
--  secret is skipped. Blizzard refreshes unit tooltips while they're up, so
--  every added line is found and updated in place, never appended twice.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local issecret = ns.issecret

local shownGUID          -- who the game tooltip was last built for
local ilvlCache = {}     -- guid -> { ilvl, time }
local ILVL_TTL = 120
local pendingInspect
local lastTry = {}       -- guid -> time of our last inspect request
local userInspectUntil = 0

local LABEL = { r = 0.75, g = 0.78, b = 0.82 }
local PLAIN = { r = 0.9, g = 0.9, b = 0.9 }
local MUTED = { r = 0.6, g = 0.6, b = 0.6 }
local SELF  = { r = 1, g = 0.3, b = 0.3 }

--- The value itself, or nil when there is nothing usable (absent or secret).
local function Clean(v)
    if v ~= nil and not issecret(v) then return v end
end

local function ClassColour(class)
    class = Clean(class)
    if not class then return nil end
    local r, g, b = EvermoreUI.Palette.ClassRGB(class)
    if r then return { r = r, g = g, b = b } end
end

local function ReactionColour(unit)
    local reaction = Clean(UnitReaction(unit, "player"))
    return reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction] or nil
end

--- Find a left line containing `label` (plain text), secret lines skipped.
local function FindLine(tt, label, from)
    local name = tt:GetName()
    if not name then return end
    for i = from or 2, tt:NumLines() or 0 do
        local fs = _G[name .. "TextLeft" .. i]
        local text = fs and Clean(fs:GetText())
        if text and text:find(label, 1, true) then return i, fs end
    end
end

--- Add or update a "Label:  value" row. True when a line was added.
local function SetRow(tt, label, value, c)
    local name = tt:GetName()
    if not name then return false end
    c = c or { r = 1, g = 1, b = 1 }
    local i = FindLine(tt, label)
    if not i then
        tt:AddDoubleLine(label, value, LABEL.r, LABEL.g, LABEL.b, c.r, c.g, c.b)
        return true
    end
    local right = _G[name .. "TextRight" .. i]
    if right then
        right:SetText(value)
        right:SetTextColor(c.r, c.g, c.b)
    end
    return false
end

--------------------------------------------------------------------------------
--  Who is this tooltip about?
--
--  The GUID is the truth. A unit token is only a convenience for the APIs
--  that want one, and it is only kept when it resolves back to that same
--  GUID. Group frames are the awkward case: their tokens can read secret
--  while the GUID is clean, so we build our own from the roster.
--------------------------------------------------------------------------------
local function Roster()
    if IsInRaid and IsInRaid() then return "raid", GetNumGroupMembers() end
    return "party", GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
end

local function RosterToken(guid)
    if UnitGUID("player") == guid then return "player" end
    local prefix, count = Roster()
    for i = 1, count do
        local unit = prefix .. i
        if Clean(UnitGUID(unit)) == guid then return unit end
    end
end

local function EngineToken(guid)
    local unit = UnitTokenFromGUID and Clean(UnitTokenFromGUID(guid))
    if unit and UnitExists(unit) then return unit end
end

local function Identity(tt, data)
    local ok, _, shown = pcall(tt.GetUnit, tt)
    shown = ok and Clean(shown) or nil
    local tipGUID = shown and UnitExists(shown) and Clean(UnitGUID(shown)) or nil

    local guid = Clean(data and data.guid) or tipGUID
    if not guid then return nil, nil end
    if tipGUID == guid then return guid, shown end
    return guid, RosterToken(guid) or EngineToken(guid)
end

--------------------------------------------------------------------------------
--  Target row
--------------------------------------------------------------------------------
local function IdentityHidden(unit)
    local ask = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
    if not ask then return false end
    local hidden = ask(unit)
    return issecret(hidden) or hidden == true
end

--- What the row should say about `unit`'s target. A third return of true
--- means "only update a row that is already there": nothing to announce.
local function Targeting(tu)
    if not UnitExists(tu) then return "-", MUTED, true end
    if UnitIsUnit(tu, "player") then return L["You"], SELF end
    local name = Clean(UnitName(tu))
    if not name then return nil end
    local colour
    if UnitIsPlayer(tu) then
        colour = ClassColour(select(2, UnitClass(tu)))
    else
        colour = ReactionColour(tu)
    end
    return name, colour or PLAIN
end

local function TargetRow(tt, unit)
    if not (unit and M.db.targetLine) then return end
    local tu = unit .. "target"
    if IdentityHidden(tu) then return end
    local label = L["Target:"]
    local text, colour, updateOnly = Targeting(tu)
    if not text or (updateOnly and not FindLine(tt, label)) then return end
    SetRow(tt, label, text, colour)
end

--------------------------------------------------------------------------------
--  Item level: our own from the character sheet, everyone else's from a
--  quiet inspect, remembered for a couple of minutes.
--------------------------------------------------------------------------------
local function Cached(guid)
    local entry = ilvlCache[guid]
    if entry and GetTime() - entry.time < ILVL_TTL then return entry.ilvl end
end

--- Read an inspected unit's level into the cache. Returns it when there was one.
local function Store(guid, unit)
    local read = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel
    local v = read and Clean(read(unit))
    if not v or v <= 0 then return nil end
    v = math.floor(v)
    ilvlCache[guid] = { ilvl = v, time = GetTime() }
    return v
end

--- Only ever one request in flight, once per person per TTL, never in
--- combat, and never on top of an inspect the player opened themselves.
local function MayInspect(guid, unit)
    local now = GetTime()
    if guid == pendingInspect or now <= userInspectUntil then return false end
    if now - (lastTry[guid] or -math.huge) <= ILVL_TTL then return false end
    if InCombatLockdown() or (InspectFrame and InspectFrame:IsShown()) then return false end
    return (CanInspect and NotifyInspect and CanInspect(unit)) and true or false
end

local function ItemLevelFor(guid, unit)
    if unit and UnitIsUnit(unit, "player") then
        local equipped = select(2, GetAverageItemLevel())
        return (equipped and equipped > 0) and math.floor(equipped) or nil
    end
    local v = Cached(guid)
    if v or not unit then return v end
    v = Store(guid, unit)
    if not v and MayInspect(guid, unit) then
        pendingInspect, lastTry[guid] = guid, GetTime()
        ns.inspectFrame:RegisterEvent("INSPECT_READY")
        NotifyInspect(unit)
    end
    return v
end

local function ItemLevelRow(tt, guid, unit)
    if not M.db.itemLevel then return end
    local v = ItemLevelFor(guid, unit)
    if v then SetRow(tt, L["Item level:"], v) end
end

--------------------------------------------------------------------------------
--  The unit tooltip
--------------------------------------------------------------------------------
--- Class, name and realm for a player; nil for anything else.
local function PlayerInfo(guid, unit)
    if GetPlayerInfoByGUID then
        local _, class, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
        if Clean(class) then return class, name, realm end
    end
    if unit and UnitIsPlayer(unit) then
        local class = Clean(select(2, UnitClass(unit)))
        if class then return class, UnitName(unit) end
    end
end

--- Line 1 without the title, but only when it really carries one.
local function DropTitle(line1, unit, name, realm)
    name = Clean(name)
    if not name then return end
    realm = Clean(realm)
    local plain = (realm and realm ~= "") and (name .. "-" .. realm) or name
    local shown = Clean(line1:GetText())
    if not shown or shown == plain then return end
    if unit then
        local titled = UnitPVPName and Clean(UnitPVPName(unit))
        if not titled or titled == name then return end
    end
    line1:SetText(plain)
end

--- " [Rank]" after the guild line, once.
local function AddRank(tt, unit)
    local guild, rank = GetGuildInfo(unit)
    guild, rank = Clean(guild), Clean(rank)
    if not (guild and rank) then return end
    local _, fs = FindLine(tt, guild)
    local text = fs and Clean(fs:GetText())
    if not text then return end
    local suffix = " |cff9a9aa8[" .. rank .. "]|r"
    if text:sub(-#suffix) ~= suffix then fs:SetText(text .. suffix) end
end

local function PaintBar(c)
    if GameTooltipStatusBar and c then GameTooltipStatusBar:SetStatusBarColor(c.r, c.g, c.b) end
end

local function OnUnit(tt, data)
    if tt ~= GameTooltip or not ns.Usable(tt) then return end
    local first = (tt:NumLines() or 0) + 1
    local guid, unit = Identity(tt, data)
    shownGUID = guid
    if not guid then return end

    -- The bar keeps whatever colour it was last given, so reset it to
    -- Blizzard's green before deciding anything.
    PaintBar({ r = 0, g = 1, b = 0 })
    local class, name, realm = PlayerInfo(guid, unit)
    local line1 = GameTooltipTextLeft1

    if class and line1 then
        if M.db.hideTitles then DropTitle(line1, unit, name, realm) end
        local c = M.db.classColours and ClassColour(class)
        if c then
            line1:SetTextColor(c.r, c.g, c.b)
            PaintBar(c)
        end
        if unit and M.db.guildRank then AddRank(tt, unit) end
        ItemLevelRow(tt, guid, unit)
    elseif unit and M.db.classColours then
        PaintBar(ReactionColour(unit))
    end
    TargetRow(tt, unit)
    ns.Fonts(tt, first)
end

--------------------------------------------------------------------------------
--  IDs (for addon work)
--------------------------------------------------------------------------------
local function IdRow(label)
    return function(tt, data)
        if not M.db.showIds or not ns.Usable(tt) then return end
        local id = data and data.id
        if not id or issecret(id) then return end
        local before = tt:NumLines() or 0
        if SetRow(tt, label, tostring(id), MUTED) then ns.Fonts(tt, before + 1) end
    end
end

--------------------------------------------------------------------------------
--  Init
--------------------------------------------------------------------------------
function ns.InitUnits()
    ns.inspectFrame = CreateFrame("Frame")
    ns.inspectFrame:SetScript("OnEvent", function(self, _, guid)
        self:UnregisterEvent("INSPECT_READY")
        pendingInspect = nil
        guid = Clean(guid)
        if not guid then return end
        local unit = EngineToken(guid)
        if unit then Store(guid, unit) end
        -- Late answer: only worth a line if the tooltip is still about them.
        local entry = ilvlCache[guid]
        if not (entry and M.db.itemLevel and shownGUID == guid) then return end
        if not (ns.Usable(GameTooltip) and GameTooltip:IsShown()) then return end
        local first = (GameTooltip:NumLines() or 0) + 1
        if SetRow(GameTooltip, L["Item level:"], entry.ilvl) then
            ns.Fonts(GameTooltip, first)
            pcall(GameTooltip.Show, GameTooltip) -- re-measure; optional
        end
    end)
    if InspectUnit then hooksecurefunc("InspectUnit", function() userInspectUntil = GetTime() + 2 end) end
    GameTooltip:HookScript("OnHide", function() shownGUID = nil end)
    GameTooltip:HookScript("OnTooltipCleared", function() shownGUID = nil end)

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        local T = Enum.TooltipDataType
        TooltipDataProcessor.AddTooltipPostCall(T.Unit, OnUnit)
        TooltipDataProcessor.AddTooltipPostCall(T.Spell, IdRow(L["Spell ID:"]))
        TooltipDataProcessor.AddTooltipPostCall(T.Item, IdRow(L["Item ID:"]))
        if T.UnitAura then TooltipDataProcessor.AddTooltipPostCall(T.UnitAura, IdRow(L["Spell ID:"])) end
    else
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) OnUnit(tt, nil) end)
    end
end
