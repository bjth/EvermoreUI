if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Info.lua
--  Laid over the map: the zone on a plate straddling the bottom edge (PvP
--  colours, day / night glyph, click for the world map), coordinates top
--  left, the clock top centre, and a difficulty badge top right while
--  you're in an instance.
--
--  Nothing here polls while idle: the clock wakes once a minute, and the
--  coordinates only update while you're moving (or the map changes).
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor = math.floor

local zone, zonePlate, clock, coords, badge, diel

local function Font(fs, size)
    fs:SetFont(T.FontPath(), size or M.db.fontSize, "")
    T.TextShadow(fs)
end

--------------------------------------------------------------------------------
--  Zone
--------------------------------------------------------------------------------
-- PvP status to theme colour.
local ZONE_TOKEN = {
    sanctuary = "rested", friendly = "success", hostile = "danger",
    contested = "warning", arena = "danger", combat = "danger",
}

local function UpdateZone()
    if not zone then return end
    zone:SetText(GetMinimapZoneText and GetMinimapZoneText() or "")
    local token = "text"
    if M.db.zoneColour and C_PvP and C_PvP.GetZonePVPInfo then
        local pvp = C_PvP.GetZonePVPInfo()
        token = ZONE_TOKEN[pvp or ""] or "text"
    end
    zone:SetTextColor(T.RGBA(token))
    if zonePlate then
        local w = (zone:GetStringWidth() or 0) + 20 + ((diel and diel:IsShown()) and 16 or 0)
        zonePlate:SetWidth(math.min(math.floor(w + 0.5), M.db.size - 16))
    end
end

local function ZoneTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
    local ok = false
    if Minimap_SetTooltip and C_PvP and C_PvP.GetZonePVPInfo then
        local pvpType, _, factionName = C_PvP.GetZonePVPInfo()
        ok = pcall(Minimap_SetTooltip, pvpType, factionName)
    end
    if not ok then GameTooltip:SetText(GetZoneText and GetZoneText() or "") end
    GameTooltip:AddLine(L["Click for the world map."], T.RGBA("textMuted"))
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
--  Clock: Blizzard's settings (local or realm time, 24 hour) from the
--  Time Manager, refreshed on the minute.
--------------------------------------------------------------------------------
local function TimeText()
    local useLocal = GetCVarBool and GetCVarBool("timeMgrUseLocalTime")
    local h, m
    if useLocal or not GetGameTime then
        local t = date("*t")
        h, m = t.hour, t.min
    else
        h, m = GetGameTime()
    end
    if GetCVarBool and GetCVarBool("timeMgrUseMilitaryTime") then
        return ("%02d:%02d"):format(h, m)
    end
    local suffix = h >= 12 and "pm" or "am"
    h = h % 12
    if h == 0 then h = 12 end
    return ("%d:%02d%s"):format(h, m, suffix)
end

local clockTimer
local function UpdateClock()
    if clockTimer then clockTimer:Cancel(); clockTimer = nil end
    if not (clock and M.db.clock) then return end
    clock:SetText(TimeText())
    -- Next minute boundary, plus a hair.
    local wait = 60 - (tonumber(date("%S")) or 0) + 0.05
    if C_Timer.NewTimer then clockTimer = C_Timer.NewTimer(wait, UpdateClock) end
end

local function ClockTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT", 0, -4)
    GameTooltip:SetText(TimeText(), T.RGBA("text"))
    if GameTime_GetGameTime and GameTime_GetLocalTime then
        GameTooltip:AddDoubleLine(L["Realm time"], GameTime_GetGameTime(true), T.RGBA("textMuted"))
        GameTooltip:AddDoubleLine(L["Local time"], GameTime_GetLocalTime(true), T.RGBA("textMuted"))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click: clock settings and alarm. Right-click: stopwatch."], T.RGBA("textMuted"))
    GameTooltip:Show()
end

local function ClockClick(_, button)
    if not (TimeManager_Toggle or Stopwatch_Toggle) and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_TimeManager")
    end
    if button == "RightButton" then
        if Stopwatch_Toggle then Stopwatch_Toggle() end
    elseif TimeManager_Toggle then
        TimeManager_Toggle()
    end
end

--------------------------------------------------------------------------------
--  Coordinates: only while moving, a few times a second.
--------------------------------------------------------------------------------
local lastX, lastY

--- Refresh the readout. Returns true when the position actually changed.
local function UpdateCoords()
    if not coords then return false end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if pos then x, y = pos:GetXY() end
    -- `not x` is a truthiness test, not a comparison, so it is safe on a
    -- secret. EV.IsSecret is not: see the note on it in Core/Init.lua.
    if not x or EV.IsSecret(x) or EV.IsSecret(y) then
        coords:SetText("")
        lastX, lastY = nil, nil
        return false
    end
    x, y = floor(x * 1000 + 0.5) / 10, floor(y * 1000 + 0.5) / 10
    if x == lastX and y == lastY then return false end
    lastX, lastY = x, y
    coords:SetFormattedText("%.1f, %.1f", x, y)
    return true
end

--------------------------------------------------------------------------------
--  The ticker only runs while the player is moving, so it needs to know when
--  they have stopped. `GetUnitSpeed("player")` answers that, except when the
--  client makes the speed a secret number, under the same restrictions that
--  make the map position one. ANY comparison against a secret throws, so
--  `(GetUnitSpeed("player") or 0) == 0` threw 162 times in a few minutes,
--  once per poll, because this runs from an OnUpdate.
--
--  Where we are allowed to read the speed we still do, because it stops the
--  ticker the instant the player halts. Where we are not, we fall back on the
--  one thing we can still see: if the coordinates have not changed for a few
--  consecutive polls, the player is standing still.
--
--  That fallback also covers a client with no GetUnitSpeed at all, where the
--  old line could never be true and the ticker ran for the whole session.
--------------------------------------------------------------------------------
local STILL_POLLS = 3          -- 3 x 0.2s of no movement
local moveFrame = CreateFrame("Frame")
local acc, still = 0, 0
moveFrame:Hide()
moveFrame:SetScript("OnUpdate", function(self, dt)
    acc = acc + dt
    if acc < 0.2 then return end
    acc = 0
    local moved = UpdateCoords()

    local speed = GetUnitSpeed and GetUnitSpeed("player")
    if EV.Usable(speed) then
        if speed == 0 and not IsFalling() then self:Hide() end
        return
    end

    still = moved and 0 or (still + 1)
    if still >= STILL_POLLS and not IsFalling() then self:Hide() end
end)
local function Moving()
    if coords and M.db.coords then
        still = 0
        moveFrame:Show()
    end
end

--------------------------------------------------------------------------------
--  Difficulty badge: "5", "10H", "25", "40" and so on, top-right of the map.
--------------------------------------------------------------------------------
local HEROIC = { [2] = true, [5] = true, [6] = true, [11] = true, [15] = true, [174] = true, [193] = true }
local MYTHIC = { [8] = true, [16] = true, [23] = true }

local function UpdateBadge()
    if not badge then return end
    local _, kind, diffID, _, maxPlayers = GetInstanceInfo()
    if not M.db.difficulty or kind == "none" or not kind or (kind ~= "party" and kind ~= "raid" and kind ~= "scenario") then
        badge:Hide()
        return
    end
    local mark = (MYTHIC[diffID] and "M") or (HEROIC[diffID] and "H") or ""
    local size = (maxPlayers and maxPlayers > 0) and tostring(maxPlayers) or ""
    badge.text:SetText(size .. mark)
    badge.text:SetTextColor(T.RGBA(mark ~= "" and "accent" or "text"))
    badge:SetWidth((badge.text:GetStringWidth() or 0) + 10)
    badge.diffID = diffID
    badge:Show()
end

--------------------------------------------------------------------------------
--  Day and night: Forever's day / night cycle, as a sun or moon at the left
--  of the zone plate (amber by day, dusky teal by night).
--------------------------------------------------------------------------------
local function IsDay()
    if C_DateAndTime and C_DateAndTime.IsDayTime then
        local ok, day = pcall(C_DateAndTime.IsDayTime)
        if ok and day ~= nil then return day and true or false end
    end
    return nil
end

local function UpdateDiel(isDay)
    if not diel then return end
    if isDay == nil then isDay = IsDay() end
    local on = M.db.zone and M.db.diel and isDay ~= nil
    diel:SetShown(on)
    if not on then return end
    diel.day = isDay
    diel.glyph:SetTexture(ns.GLYPH .. (isDay and "map_sun" or "map_moon") .. ".png")
    diel.glyph:SetVertexColor(T.RGBA(isDay and "warning" or "rested"))
end

--------------------------------------------------------------------------------
--  Build and layout
--------------------------------------------------------------------------------
function ns.AdoptInfo()
    local f = ns.frame
    local o = f.overlay

    -- Zone plate, straddling the bottom edge.
    zonePlate = ns.Plate(o, 0.95)
    zonePlate:SetHeight(18)
    zonePlate:SetPoint("BOTTOM", f, "BOTTOM", 0, -7)
    local zb = CreateFrame("Button", nil, zonePlate)
    zb:SetAllPoints()
    zb:RegisterForClicks("LeftButtonUp")
    zb:SetScript("OnClick", function() if ToggleWorldMap then ToggleWorldMap() end end)
    zb:SetScript("OnEnter", ZoneTooltip)
    zb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    zone = zb:CreateFontString(nil, "OVERLAY")
    zone:SetWordWrap(false)
    zone:SetJustifyH("CENTER")

    diel = CreateFrame("Frame", nil, zonePlate)
    diel:SetSize(14, 14)
    diel:SetPoint("LEFT", 5, 0)
    diel:SetFrameLevel(zb:GetFrameLevel() + 1)
    diel:EnableMouse(true)
    diel.glyph = diel:CreateTexture(nil, "OVERLAY")
    diel.glyph:SetSize(12, 12)
    diel.glyph:SetPoint("CENTER")
    diel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(self.day and L["Daytime"] or L["Night-time"], T.RGBA(self.day and "warning" or "rested"))
        GameTooltip:AddLine(L["Forever's day and night cycle."], T.RGBA("textMuted"))
        GameTooltip:Show()
    end)
    diel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    diel:Hide()

    -- Coordinates, top left; the clock, top centre. Shadowed text over the map.
    coords = o:CreateFontString(nil, "OVERLAY")
    coords:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -5)
    coords:SetJustifyH("LEFT")

    local cb = CreateFrame("Button", nil, o)
    cb:SetSize(60, 16)
    cb:SetPoint("TOP", f, "TOP", 0, -3)
    cb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    clock = cb:CreateFontString(nil, "OVERLAY")
    clock:SetPoint("CENTER")
    cb:SetScript("OnClick", ClockClick)
    cb:SetScript("OnEnter", function(self) clock:SetTextColor(T.RGBA("accent")); ClockTooltip(self) end)
    cb:SetScript("OnLeave", function() clock:SetTextColor(T.RGBA("text")); GameTooltip:Hide() end)
    ns.clockButton = cb

    -- Difficulty badge, top right.
    badge = ns.Plate(o, 0.9)
    badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    badge:SetHeight(16)
    badge.text = badge:CreateFontString(nil, "OVERLAY")
    badge.text:SetPoint("CENTER", 0, 0)
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        local name = GetDifficultyInfo and self.diffID and GetDifficultyInfo(self.diffID)
        GameTooltip:SetText(name or L["Instance"], T.RGBA("text"))
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge:Hide()
    ns.badge = badge

    -- Fonts before any text: the theme callback below sets text straight away.
    Font(zone, M.db.fontSize)
    Font(coords, M.db.fontSize - 1)
    Font(clock, M.db.fontSize)
    Font(badge.text, M.db.fontSize - 2)

    T.OnTheme(function()
        clock:SetTextColor(T.RGBA("text"))
        coords:SetTextColor(T.RGBA("text"))
        UpdateZone()
        UpdateBadge()
        UpdateDiel()
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD",
                         "PLAYER_DIFFICULTY_CHANGED", "UPDATE_INSTANCE_INFO", "GROUP_ROSTER_UPDATE",
                         "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "CVAR_UPDATE", "DIEL_CYCLE_CHANGED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, e, arg)
        if e == "PLAYER_STARTED_MOVING" then return Moving() end
        if e == "PLAYER_STOPPED_MOVING" then return UpdateCoords() end
        if e == "DIEL_CYCLE_CHANGED" then UpdateDiel(arg); return UpdateZone() end
        if e == "CVAR_UPDATE" then
            if arg == "timeMgrUseMilitaryTime" or arg == "timeMgrUseLocalTime" then UpdateClock() end
            return
        end
        UpdateZone()
        UpdateBadge()
        UpdateCoords()
    end)
end

function ns.LayoutInfo()
    if not zone then return end
    local cfg = M.db
    Font(zone, cfg.fontSize)
    Font(coords, cfg.fontSize - 1)
    Font(clock, cfg.fontSize)
    Font(badge.text, cfg.fontSize - 2)
    badge:SetHeight(cfg.fontSize + 4)
    zonePlate:SetHeight(cfg.fontSize + 7)
    zonePlate:SetShown(cfg.zone)
    coords:SetShown(cfg.coords)
    ns.clockButton:SetShown(cfg.clock)
    ns.RefreshInfo()
end

function ns.RefreshInfo()
    UpdateDiel()
    -- The day / night glyph takes the plate's left; the name sits to its right.
    zone:ClearAllPoints()
    if diel:IsShown() then
        zone:SetPoint("LEFT", diel, "RIGHT", 3, 0)
        zone:SetPoint("RIGHT", zonePlate, "RIGHT", -8, 0)
    else
        zone:SetPoint("LEFT", zonePlate, "LEFT", 8, 0)
        zone:SetPoint("RIGHT", zonePlate, "RIGHT", -8, 0)
    end
    UpdateZone()
    UpdateClock()
    UpdateCoords()
    UpdateBadge()
end
