if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  DataBars.lua
--  Experience bar in the style of Luxthos' Simple Experience Bar (our own code).
--  Framerate and latency readouts live in Stats.lua.
--
--  [ Level 15        12581 / 14400   ||||||sage|teal|        87.4% (92.1%) ]
--        Completed Quests: 4.7%  -  Rested Experience: 6.4%
--        Level Time: 1h 12m  -  XP/Hour: 18.4k  -  Level In: 23m
--        Session: 45m (34,210 XP)  -  Played: 3d 4h
--
--  Fill segments, left to right: XP (copper to wheat gradient), completed
--  quests (sage), rested (dusky teal). Optional faint layer for every quest
--  in the log. The session survives /reload unless told otherwise.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L

local M = EV:NewModule("DataBars", {
    xp = {
        enabled        = true,
        width          = 530,
        height         = 30,
        texture        = "Flat",
        fontSize       = 15,
        -- text lines
        showBarText    = true,    -- level, numbers and percentage inside the bar
        showQuestLine  = true,    -- "Completed Quests: x% - Rested Experience: y%"
        showRateLine   = true,    -- level time, XP/hour, time to level
        showSessionLine = true,   -- session time and XP
        showPlayed     = true,    -- /played total, on the session line
        -- bar layers
        showQuestLog   = false,   -- faint layer for incomplete quests too
        -- behaviour
        resetSessionOnReload = false,
        hideBlizzardBar = false,
        showAtMax      = false,
        animations     = true,
    },
})
ns.module = M
M.title = "Data Bars"
M.description = "Experience bar with completed-quest and rested segments, XP/hour, time to level and session stats."

local bar
local floor, max, min = math.floor, math.max, math.min

-- Colours are theme tokens (EvermoreUI/Core/Theme.lua): the data colours
-- xp, xpEnd, quest and rested, plus the usual surfaces and text. High
-- contrast brightens them all; the bar repaints when the theme changes.
local TH = EV.Theme
local function Hex(token, s)
    local r, g, b = TH.RGBA(token)
    return ("|cff%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)) .. s .. "|r"
end

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

local function AtMaxLevel()
    if IsPlayerAtEffectiveMaxLevel then return IsPlayerAtEffectiveMaxLevel() end
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    return false
end

local function Short(n)
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
    return EV.FormatNumber(n)
end

local function Duration(sec)
    if not sec or sec ~= sec or sec == math.huge or sec < 0 then return "?" end
    sec = floor(sec + 0.5)
    local d, h, m = floor(sec / 86400), floor((sec % 86400) / 3600), floor((sec % 3600) / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return ("%ds"):format(sec)
end

local function SEP() return Hex("textMuted", "  -  ") end

--------------------------------------------------------------------------------
--  Quest XP (debounced: QUEST_LOG_UPDATE fires in bursts)
--------------------------------------------------------------------------------
local quest = { ready = 0, readyCount = 0, log = 0, logCount = 0 }

local function ScanQuests()
    quest.ready, quest.readyCount, quest.log, quest.logCount = 0, 0, 0, 0
    local QL = C_QuestLog
    if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo and GetQuestLogRewardXP) then return end
    for i = 1, QL.GetNumQuestLogEntries() do
        local info = QL.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID then
            local xp = GetQuestLogRewardXP(info.questID) or 0
            if xp > 0 then
                quest.log, quest.logCount = quest.log + xp, quest.logCount + 1
                local done = (QL.ReadyForTurnIn and QL.ReadyForTurnIn(info.questID))
                    or (QL.IsComplete and QL.IsComplete(info.questID))
                if done then
                    quest.ready, quest.readyCount = quest.ready + xp, quest.readyCount + 1
                end
            end
        end
    end
end

local questScanPending = false
function M:QueueQuestScan()
    if questScanPending then return end
    questScanPending = true
    C_Timer.After(0.25, function()
        questScanPending = false
        ScanQuests()
        self:UpdateXP()
    end)
end

--------------------------------------------------------------------------------
--  Session and rate. Stored per character outside profiles so a /reload keeps
--  the session going. Timestamps use time() so they survive the reload.
--------------------------------------------------------------------------------
local WINDOW = 20 * 60
local session          -- { start, xp, samples = { {t, xp}, ... } }
local last = {}        -- cur, max, level from the previous update

local function StartSession(keep)
    session = EV.DB:GetCharData("DataBarsSession")
    if not keep or not session.start then
        session.start, session.xp, session.samples = time(), 0, {}
    end
    session.samples = session.samples or {}
    session.xp = session.xp or 0
end

local function RecordGain(amount)
    local s = session.samples
    s[#s + 1] = { t = time(), xp = amount }
    session.xp = session.xp + amount
end

--- XP per hour over the last WINDOW seconds (or since the session began).
local function XPPerHour()
    if not session then return nil end
    local now = time()
    local cutoff = now - WINDOW
    local s = session.samples
    while s[1] and s[1].t < cutoff do table.remove(s, 1) end
    local total = 0
    for i = 1, #s do total = total + s[i].xp end
    local span = min(WINDOW, now - session.start)
    if span < 60 or total <= 0 then return nil end
    return total / span * 3600
end

--------------------------------------------------------------------------------
--  /played, fetched quietly: Blizzard prints the reply to chat, so we swap the
--  printer out for the one request we make and restore it straight after.
--------------------------------------------------------------------------------
local played = { total = nil, level = nil, at = nil }
local quietRequest = false

local function RequestPlayedQuietly()
    if type(RequestTimePlayed) ~= "function" then return end
    if type(ChatFrame_DisplayTimePlayed) == "function" then
        if not M._origDisplayPlayed then M._origDisplayPlayed = ChatFrame_DisplayTimePlayed end
        ChatFrame_DisplayTimePlayed = function() end
        quietRequest = true
    end
    RequestTimePlayed()
end

local function RestorePlayedPrinter()
    if quietRequest and M._origDisplayPlayed then
        ChatFrame_DisplayTimePlayed = M._origDisplayPlayed
    end
    quietRequest = false
end

--------------------------------------------------------------------------------
--  Frame
--------------------------------------------------------------------------------
local function Layer(parent, level)
    local sb = CreateFrame("StatusBar", nil, parent)
    sb:SetAllPoints()
    sb:SetFrameLevel(level)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    return sb
end

local function Font(parent, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH(justify or "CENTER")
    TH.TextShadow(fs)
    return fs
end

local function CreateBar()
    local f = CreateFrame("Frame", "EvermoreUIXPBar", UIParent)
    f:SetFrameStrata("LOW")
    f:EnableMouse(true)
    -- Our panel look: a sunk well with the theme's border.
    f.bg = TH.Fill(f, "BACKGROUND", "surfaceSunk", 0.9, -8)
    f.bg:SetAllPoints()
    TH.TokenBorder(f, "border")

    -- Back to front. Each layer's value is cumulative, so they read as
    -- consecutive segments: XP | quests | rested.
    local base = f:GetFrameLevel()
    f.questLog = Layer(f, base + 1)
    f.rested   = Layer(f, base + 2)
    f.quests   = Layer(f, base + 3)
    f.xp       = Layer(f, base + 4)

    local top = CreateFrame("Frame", nil, f)
    top:SetAllPoints()
    top:SetFrameLevel(base + 6)
    f.top = top

    f.level = Font(top, "LEFT")
    f.level:SetPoint("LEFT", 8, 0)
    f.numbers = Font(top, "CENTER")
    f.numbers:SetPoint("CENTER", 0, 0)
    f.pct = Font(top, "RIGHT")
    f.pct:SetPoint("RIGHT", -8, 0)

    -- Text lines under the bar
    f.lines = {}
    for i = 1, 3 do
        local fs = Font(f, "CENTER")
        f.lines[i] = fs
    end

    -- Gain flash over the XP just earned
    local flash = top:CreateTexture(nil, "OVERLAY", nil, -1)
    flash:SetColorTexture(1, 1, 1, 1)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    local fa = flash:CreateAnimationGroup()
    local fade = fa:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.7); fade:SetToAlpha(0); fade:SetDuration(0.9); fade:SetSmoothing("OUT")
    fa:SetScript("OnFinished", function() flash:SetAlpha(0) end)
    f.flash, f.flashAnim = flash, fa

    -- Level-up: the bar flashes and "Level N" rises above it
    local lvlFlash = top:CreateTexture(nil, "OVERLAY", nil, -2)
    lvlFlash:SetAllPoints(f)
    lvlFlash:SetColorTexture(1, 1, 1, 1)
    lvlFlash:SetBlendMode("ADD")
    lvlFlash:SetAlpha(0)
    local la = lvlFlash:CreateAnimationGroup()
    local l1 = la:CreateAnimation("Alpha")
    l1:SetFromAlpha(0.6); l1:SetToAlpha(0); l1:SetDuration(1.2); l1:SetSmoothing("OUT")
    la:SetScript("OnFinished", function() lvlFlash:SetAlpha(0) end)
    f.levelFlashAnim = la

    local pop = Font(top, "CENTER")
    pop:SetPoint("BOTTOM", f, "TOP", 0, 8)
    pop:SetAlpha(0)
    local pa = pop:CreateAnimationGroup()
    local p1 = pa:CreateAnimation("Alpha")
    p1:SetFromAlpha(0); p1:SetToAlpha(1); p1:SetDuration(0.25); p1:SetOrder(1)
    local p2 = pa:CreateAnimation("Translation")
    p2:SetOffset(0, 12); p2:SetDuration(0.25); p2:SetOrder(1); p2:SetSmoothing("OUT")
    local p3 = pa:CreateAnimation("Alpha")
    p3:SetFromAlpha(1); p3:SetToAlpha(0); p3:SetDuration(0.8); p3:SetStartDelay(1.8); p3:SetOrder(2)
    pa:SetScript("OnFinished", function() pop:SetAlpha(0) end)
    f.pop, f.popAnim = pop, pa

    f:SetScript("OnEnter", function(self) M:ShowTooltip(self) end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function f:Paint()
        M:ApplySettings()
        M:UpdateXP()
    end
    TH.Watch(f)

    return f
end

--------------------------------------------------------------------------------
--  Update
--------------------------------------------------------------------------------
local function PlaceFlash(fromFrac, toFrac)
    if toFrac <= fromFrac then return end
    local w = bar:GetWidth()
    bar.flash:ClearAllPoints()
    bar.flash:SetPoint("TOPLEFT", bar, "TOPLEFT", w * fromFrac, 0)
    bar.flash:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", w * fromFrac, 0)
    bar.flash:SetWidth(max(w * (toFrac - fromFrac), 1))
    bar.flashAnim:Stop()
    bar.flashAnim:Play()
end

local function SetLines(texts)
    local prev = bar
    local n = 0
    for i, fs in ipairs(bar.lines) do
        local t = texts[i]
        if t and t ~= "" then
            n = n + 1
            fs:ClearAllPoints()
            fs:SetPoint("TOP", prev, "BOTTOM", 0, prev == bar and -4 or -2)
            fs:SetText(t)
            fs:Show()
            prev = fs
        else
            fs:Hide()
        end
    end
end

function M:UpdateXP()
    if not bar then return end
    local cfg = self.db.xp
    if not cfg.enabled or (not cfg.showAtMax and AtMaxLevel()) then
        bar:Hide()
        return
    end
    bar:Show()

    local cur, maxXP = UnitXP("player"), UnitXPMax("player")
    local level = UnitLevel("player")
    local rested = GetXPExhaustion() or 0

    -- Status bars accept secret values; our arithmetic and text do not.
    if IsSecret(cur) or IsSecret(maxXP) then
        bar.xp:SetMinMaxValues(0, maxXP)
        bar.xp:SetValue(cur)
        for _, l in ipairs({ bar.rested, bar.quests, bar.questLog }) do l:SetValue(0) end
        bar.numbers:SetText(""); bar.pct:SetText("")
        SetLines({})
        return
    end
    if not maxXP or maxXP <= 0 then maxXP = 1 end

    -- UnitXP can reset before UnitLevel catches up on a level-up, so a drop in
    -- XP at the same level is treated as the rollover, and the later level
    -- change isn't counted twice.
    if last.cur and session then
        local gained, sameLevel = 0, false
        if level > last.level then
            gained = last.rolled and (cur - last.cur) or ((last.max - last.cur) + cur)
            last.rolled = false
        elseif cur >= last.cur then
            gained, sameLevel = cur - last.cur, true
        else
            gained = (last.max - last.cur) + cur
            last.rolled = true
        end
        if gained > 0 then
            RecordGain(gained)
            if cfg.animations and sameLevel then PlaceFlash(last.cur / maxXP, cur / maxXP) end
        end
    end
    last.cur, last.max, last.level = cur, maxXP, level

    -- Segments
    for _, l in ipairs({ bar.xp, bar.rested, bar.quests, bar.questLog }) do
        l:SetMinMaxValues(0, maxXP)
    end
    local afterQuests = min(cur + quest.ready, maxXP)
    bar.xp:SetValue(cur)
    bar.quests:SetValue(afterQuests)
    bar.rested:SetValue(min(afterQuests + rested, maxXP))
    bar.questLog:SetValue(cfg.showQuestLog and min(cur + quest.log, maxXP) or 0)

    -- In-bar text
    local pct = cur / maxXP * 100
    local withQuests = afterQuests / maxXP * 100
    bar.level:SetText(("%s %d"):format(L["Level"], level))
    bar.numbers:SetText(("%d / %d"):format(cur, maxXP))
    if quest.ready > 0 then
        bar.pct:SetText(("%.1f%% (%.1f%%)"):format(pct, withQuests))
    else
        bar.pct:SetText(("%.1f%%"):format(pct))
    end

    -- Lines under the bar
    local lines = {}
    if cfg.showQuestLine then
        lines[#lines + 1] = ("%s: %s%s%s: %s"):format(
            L["Completed Quests"], Hex("quest", ("%.1f%%"):format(quest.ready / maxXP * 100)), SEP(),
            L["Rested Experience"], Hex("rested", ("%.1f%%"):format(rested / maxXP * 100)))
    end
    if cfg.showRateLine then
        local parts = {}
        if played.level and played.at then
            parts[#parts + 1] = ("%s: %s"):format(L["Level Time"], Duration(played.level + (time() - played.at)))
        end
        local perHour = XPPerHour()
        parts[#parts + 1] = ("%s: %s"):format(L["XP/Hour"], perHour and Short(perHour) or "-")
        if perHour then
            parts[#parts + 1] = ("%s: %s"):format(L["Level In"], Duration((maxXP - cur) / perHour * 3600))
        end
        lines[#lines + 1] = table.concat(parts, SEP())
    end
    if cfg.showSessionLine and session then
        local parts = { ("%s: %s (%s XP)"):format(L["Session"], Duration(time() - session.start),
            EV.FormatNumber(session.xp)) }
        if cfg.showPlayed and played.total and played.at then
            parts[#parts + 1] = ("%s: %s"):format(L["Played"], Duration(played.total + (time() - played.at)))
        end
        lines[#lines + 1] = table.concat(parts, SEP())
    end
    SetLines(lines)
end

function M:OnLevelUp(level)
    if played.at then played.level, played.at = 0, time() end
    if not bar or not self.db.xp.animations then return end
    bar.levelFlashAnim:Stop(); bar.levelFlashAnim:Play()
    bar.pop:SetText(("%s %d"):format(L["Level"], level))
    bar.popAnim:Stop(); bar.popAnim:Play()
end

--------------------------------------------------------------------------------
--  Tooltip
--------------------------------------------------------------------------------
function M:ShowTooltip(owner)
    local cur, maxXP = UnitXP("player"), UnitXPMax("player")
    if IsSecret(cur) or IsSecret(maxXP) or not maxXP or maxXP <= 0 then return end
    local rested = GetXPExhaustion() or 0
    local tt = GameTooltip
    local function Row(left, right, token)
        local r, g, b = TH.RGBA(token)
        tt:AddDoubleLine(left, right, r, g, b, r, g, b)
    end
    tt:SetOwner(owner, "ANCHOR_TOP", 0, 8)
    tt:AddLine(("%s %d"):format(L["Level"], UnitLevel("player")), TH.RGBA("title"))
    Row(L["Current"], ("%s / %s  (%.1f%%)"):format(EV.FormatNumber(cur), EV.FormatNumber(maxXP), cur / maxXP * 100), "text")
    Row(L["Remaining"], EV.FormatNumber(maxXP - cur), "text")
    Row(("%s (%d)"):format(L["Completed Quests"], quest.readyCount), EV.FormatNumber(quest.ready), "quest")
    Row(("%s (%d)"):format(L["All quests in log"], quest.logCount), EV.FormatNumber(quest.log), "textMuted")
    Row(L["Rested Experience"], EV.FormatNumber(rested), "rested")
    if cur + quest.ready >= maxXP then
        tt:AddLine(" ")
        tt:AddLine(L["Handing in your completed quests levels you up."], TH.RGBA("quest"))
    end
    tt:Show()
end

--------------------------------------------------------------------------------
--  Blizzard's own XP bar
--------------------------------------------------------------------------------
-- Every name Blizzard has used for the XP bar: retail's status tracking
-- containers, then the older Classic-era frames, in case Forever uses those.
local BLIZZARD_BARS = {
    "MainStatusTrackingBarContainer",
    "StatusTrackingBarManager",
    "MainMenuExpBar",
    "MainMenuBarExpBar",
}
local hookedBars = {}

-- Faded rather than hidden: some of these are Edit Mode frames, and hiding
-- them outright can upset Edit Mode's layout. Mouse is switched off too so
-- the invisible bar doesn't eat clicks or show tooltips.
local function ApplyToBar(b, hide)
    b:SetAlpha(hide and 0 or 1)
    if b.EnableMouse and not InCombatLockdown() then b:EnableMouse(not hide) end
end

function M:ApplyBlizzardBar()
    local hide = self.db.xp.enabled and self.db.xp.hideBlizzardBar
    for _, name in ipairs(BLIZZARD_BARS) do
        local b = _G[name]
        if b and b.SetAlpha then
            ApplyToBar(b, hide)
            -- Blizzard re-shows and re-fades these itself; put ours back after.
            if not hookedBars[b] then
                hookedBars[b] = true
                b:HookScript("OnShow", function(frame)
                    ApplyToBar(frame, M.db.xp.enabled and M.db.xp.hideBlizzardBar)
                end)
                hooksecurefunc(b, "SetAlpha", function(frame, a)
                    if a ~= 0 and M.db.xp.enabled and M.db.xp.hideBlizzardBar then frame:SetAlpha(0) end
                end)
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Settings
--------------------------------------------------------------------------------
function M:ApplySettings()
    if not bar then return end
    local cfg = self.db.xp
    EV.Pixel:SetSize(bar, cfg.width, cfg.height)

    -- Colour after texture: SetStatusBarTexture replaces the texture and drops
    -- any vertex colour or gradient set before it.
    local tex = EV.Media:Fetch("statusbar", cfg.texture)
    bar.xp:SetStatusBarTexture(tex)
    local xpTex = bar.xp:GetStatusBarTexture()
    if xpTex and xpTex.SetGradient and CreateColor then
        bar.xp:SetStatusBarColor(1, 1, 1, 1)
        xpTex:SetGradient("HORIZONTAL", CreateColor(TH.RGBA("xp")), CreateColor(TH.RGBA("xpEnd")))
    else
        bar.xp:SetStatusBarColor(TH.RGBA("xp"))
    end
    bar.quests:SetStatusBarTexture(tex);   bar.quests:SetStatusBarColor(TH.RGBA("quest"))
    bar.rested:SetStatusBarTexture(tex);   bar.rested:SetStatusBarColor(TH.RGBA("rested", 0.75))
    bar.questLog:SetStatusBarTexture(tex); bar.questLog:SetStatusBarColor(TH.RGBA("quest", 0.3))
    bar.bg:SetColorTexture(TH.RGBA("surfaceSunk", 0.9))
    TH.SetBorderToken(bar, "border")

    local font = EV.Media:Fetch("font")
    local size = cfg.fontSize
    for _, fs in ipairs({ bar.level, bar.numbers, bar.pct }) do
        fs:SetFont(font, size, "")
        TH.TextShadow(fs)
        fs:SetTextColor(TH.RGBA("text"))
        fs:SetShown(cfg.showBarText)
    end
    for _, fs in ipairs(bar.lines) do
        fs:SetFont(font, size - 1, "")
        TH.TextShadow(fs)
        fs:SetTextColor(TH.RGBA("text"))
    end
    bar.pop:SetFont(font, size + 8, "OUTLINE")
    bar.pop:SetTextColor(TH.RGBA("xpEnd"))

    self:ApplyBlizzardBar()
    EV.Movers:Apply("XPBar")
end

--- Called by options after any setting change.
function M:Refresh()
    self:ApplySettings()
    if ns.ApplyStats then ns.ApplyStats() end
    ScanQuests()
    self:UpdateXP()
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
    bar = CreateBar()
    ns.bar = bar
    EV.Movers:Register(bar, "XPBar", L["XP Bar"], { "BOTTOM", "BOTTOM", 0, 60 }, {
        group = L["Data Bars"], page = "databars",
        getSize = function() return self.db.xp.width, self.db.xp.height end,
        setSize = function(w, h)
            if w then self.db.xp.width = w end
            if h then self.db.xp.height = h end
            self:ApplySettings()
        end,
        isDisabled = function() return not self.db.xp.enabled end,
    })

    local update = function() self:UpdateXP() end
    local quests = function() self:QueueQuestScan() end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isLogin, isReload)
        if not session or isLogin or isReload then
            StartSession(not isLogin and not (isReload and self.db.xp.resetSessionOnReload))
        end
        if isLogin or isReload or not played.at then RequestPlayedQuietly() end
        ScanQuests()
        self:ApplyBlizzardBar()
        self:UpdateXP()
    end)
    self:RegisterEvent("TIME_PLAYED_MSG", function(_, _, total, thisLevel)
        played.total, played.level, played.at = total, thisLevel, time()
        C_Timer.After(0, RestorePlayedPrinter)
        self:UpdateXP()
    end)
    self:RegisterEvent("PLAYER_XP_UPDATE", update)
    self:RegisterEvent("UPDATE_EXHAUSTION", update)
    self:RegisterEvent("DISABLE_XP_GAIN", update)
    self:RegisterEvent("ENABLE_XP_GAIN", update)
    self:RegisterEvent("PLAYER_LEVEL_UP", function(_, _, level)
        self:OnLevelUp(tonumber(level) or UnitLevel("player"))
        self:UpdateXP()
    end)
    self:RegisterEvent("QUEST_LOG_UPDATE", quests)
    self:RegisterEvent("QUEST_ACCEPTED", quests)
    self:RegisterEvent("QUEST_REMOVED", quests)
    self:RegisterEvent("QUEST_TURNED_IN", quests)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:ApplySettings(); ns.ApplyStats() end)
    self:RegisterMessage("EV_UNLOCK", function() bar:Show(); ns.ApplyStats() end)
    self:RegisterMessage("EV_LOCK", function() update(); ns.ApplyStats() end)
    ns.EnableStats()

    -- Keep the clocks on the text lines ticking.
    C_Timer.NewTicker(5, update)

    self:Refresh()
end

function M:OnProfileChanged()
    self:Refresh()
end
