if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  SwingTimer.lua
--  The swing timer's bars: one per weapon, drawn from SwingEngine.lua.
--
--  We follow Blizzard's semantics (SwingTimerMixin): a row per swing type
--  that can swing (UnitAttackSpeed reports a speed for the slot; main hand
--  always), full when the swing lands, dimmed out of range, where nil is NOT
--  out of range. Our own frames; Blizzard's timer is only ever switched off
--  through its own CVar, showSwingTimer, and the value you had is put back
--  when ours is switched off.
--
--  Everything on a bar beyond the fill comes from layers (the contract is at
--  the end of SwingEngine.lua). The three built in here use nothing a class
--  layer couldn't:
--      gcd         the running global cooldown, shaded under the fill
--      latency     the end of the swing your latency makes too late to act in
--      autoattack  "Auto attack off" while you're in combat, in reach of
--                  something hostile, and not swinging at it
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min = math.floor, math.max, math.min
local E = ns.SwingEngine

local SW = EV:NewModule("SwingTimer", {
    enabled      = true,
    width        = 220,
    rowHeight    = 10,
    rowGap       = 3,
    showOffHand  = true,
    showRanged   = true,
    showText     = true,
    showLabel    = true,
    visibility   = "combat",   -- combat | always
    activeOnly   = true,       -- a bar only while that weapon is swinging
    hideBlizzard = true,       -- switch Blizzard's timer off (its CVar) while ours is on
    parryHaste   = true,       -- the parry rule, once your swings have proven it
    hasteRescale = true,       -- the mid-swing haste rule, likewise
    layers       = {},         -- layer key -> on / off; unset means the layer's default
})
SW.title = "Swing Timer"
SW.description = "A bar per weapon showing time to your next auto attack, dimmed when your target is out of reach."
ns.swing = SW

-- A client without C_SwingTimer: the module stays (its page says so), but
-- there is nothing to draw.
if not E then
    function SW:Refresh() end
    return
end

local ROWS = {
    { type = E.MAIN_HAND, key = "mh", tag = "MH", token = "accent" },
    { type = E.OFF_HAND,  key = "oh", tag = "OH", token = "xpEnd",  opt = "showOffHand" },
    { type = E.RANGED,    key = "r",  tag = "R",  token = "rested", opt = "showRanged" },
}

local holder, ticker
local rows, byType = {}, {}

--------------------------------------------------------------------------------
--  Which rows
--------------------------------------------------------------------------------
-- The last readable answer per swing type. UnitAttackSpeed can come back
-- secret in combat, and a secret can't be compared, so in combat we go on
-- what it said last time it could be read (and a swing is proof).
local canSwing = {}

local function CanSwing(swingType)
    if swingType == E.MAIN_HAND then return true end
    local ok, v = E.RawSpeed(swingType)
    -- A secret answer leaves the last plain one in place.
    if ok and not (issecretvalue and issecretvalue(v)) then
        canSwing[swingType] = type(v) == "number" and v > 0
    end
    return canSwing[swingType] or false
end

local function Allowed(def) return not def.opt or SW.db[def.opt] end
local function RowWanted(def) return Allowed(def) and CanSwing(def.type) end

-- How long a finished swing keeps its bar before it counts as stopped. The
-- next swing's PLAYER_SWING lands as the last one ends, so this covers the
-- gap between them, with room for latency jitter.
local GRACE = 0.9

local function Unlocked() return EV.Movers and EV.Movers.IsUnlocked and EV.Movers:IsUnlocked() end

--------------------------------------------------------------------------------
--  Layers
--------------------------------------------------------------------------------
local live = {}       -- layers switched on, in drawing order
local liveKey = {}

local function LayerOn(layer)
    local v = SW.db and SW.db.layers and SW.db.layers[layer.key]
    if v == nil then return layer.default ~= false end
    return v and true or false
end
SW.LayerOn = LayerOn

function SW:SetLayer(key, on)
    self.db.layers = self.db.layers or {}
    self.db.layers[key] = on and true or false
    self:Refresh()
end

local function SyncLayers()
    local on = SW:IsEnabled() and SW.db.enabled
    wipe(live)
    local want = {}
    for _, layer in ipairs(E:Layers()) do
        if on and LayerOn(layer) then
            live[#live + 1] = layer
            want[layer.key] = layer
        end
    end
    for key, layer in pairs(liveKey) do
        if not want[key] then
            liveKey[key] = nil
            if layer.OnDisable then pcall(layer.OnDisable, layer) end
        end
    end
    for key, layer in pairs(want) do
        if not liveKey[key] then
            liveKey[key] = layer
            if layer.OnEnable then pcall(layer.OnEnable, layer) end
        end
    end
end

-- A layer wants this row on screen even while that weapon isn't swinging.
local function Kept(r, now)
    for i = 1, #live do
        local layer = live[i]
        if layer.Keep then
            local ok, keep = pcall(layer.Keep, layer, r.def.type, now)
            if ok and keep then return true end
        end
    end
    return false
end

--- Whether a row is on screen: it can swing, and (with activeOnly) it is
--- swinging now or a layer keeps it. A priest shooting a wand gets the
--- ranged bar alone.
local function RowShown(r, now)
    if not Allowed(r.def) then return false end
    if SW.db.activeOnly and not Unlocked() then
        return (r.active or Kept(r, now)) and true or false
    end
    return RowWanted(r.def) or Kept(r, now)
end

--------------------------------------------------------------------------------
--  The row a layer draws on. Reset every frame; the pools below hold its
--  textures.
--------------------------------------------------------------------------------
local Row = {}
Row.__index = Row

function Row:At(time)
    if not self.swinging then return nil end
    return E:FractionAt(self.type, time)
end
function Row:Colour(r, g, b) self.cr, self.cg, self.cb = r, g, b end
function Row:Token(token) self.cr, self.cg, self.cb = T.RGBA(token) end
function Row:Text(text, token) self.text, self.textToken = text, token end
function Row:Label(text) self.label = text end
function Row:Dim(alpha) self.dim = min(self.dim or 1, alpha) end

local function Push(list, n, a, b, c, d)
    local e = list[n]
    if not e then e = {}; list[n] = e end
    e[1], e[2], e[3], e[4] = a, b, c, d
end
function Row:Underlay(from, to, token, alpha)
    self.nUnder = self.nUnder + 1
    Push(self.under, self.nUnder, from, to, token, alpha)
end
function Row:Zone(from, to, token, alpha)
    self.nZone = self.nZone + 1
    Push(self.zone, self.nZone, from, to, token, alpha)
end
function Row:Marker(at, token, width)
    self.nMark = self.nMark + 1
    Push(self.mark, self.nMark, at, token, width)
end

local function Reset(ctx, r, now)
    local t = r.def.type
    local sw = E:Get(t)
    ctx.type, ctx.now = t, now
    ctx.swinging = E:IsSwinging(t, now)
    ctx.progress = ctx.swinging and E:Progress(t, now) or nil
    ctx.remaining = ctx.swinging and E:Remaining(t, now) or 0
    ctx.duration = ctx.swinging and (sw.ends - sw.start) or 0
    ctx.ends = ctx.swinging and sw.ends or nil
    ctx.inRange = E:InRange(t)
    ctx.cr, ctx.cg, ctx.cb = T.RGBA(r.def.token)
    ctx.text, ctx.textToken, ctx.label, ctx.dim = nil, nil, nil, nil
    ctx.nUnder, ctx.nZone, ctx.nMark = 0, 0, 0
end

--------------------------------------------------------------------------------
--  Frames
--------------------------------------------------------------------------------
local function BuildRow(def)
    local r = CreateFrame("Frame", nil, holder)
    r.def = def
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bar = CreateFrame("StatusBar", nil, r)
    EV.Pixel:Bar(r.bar)
    r.bar:SetAllPoints()
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(0)
    -- Over the fill: zones, markers, the spark and the text.
    r.over = CreateFrame("Frame", nil, r)
    r.over:SetAllPoints()
    r.over:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.spark = r.over:CreateTexture(nil, "OVERLAY", nil, 2)
    r.spark:SetWidth(2)
    r.spark:SetBlendMode("ADD")
    r.spark:Hide()
    r.time = r.over:CreateFontString(nil, "OVERLAY")
    r.time:SetPoint("RIGHT", r, "RIGHT", -3, 0)
    r.label = r.over:CreateFontString(nil, "OVERLAY")
    r.label:SetPoint("LEFT", r, "LEFT", 3, 0)
    EV.Pixel:CreateBorder(r, 1, 0, 0, 0, 1)
    r.pools = { under = {}, zone = {}, mark = {} }
    r.ctx = setmetatable({ under = {}, zone = {}, mark = {} }, Row)
    r.outOfRange = false
    return r
end

local function Tex(r, pool, i)
    local list = r.pools[pool]
    local t = list[i]
    if not t then
        if pool == "under" then
            t = r:CreateTexture(nil, "ARTWORK")          -- under the bar's fill (a child frame)
        else
            t = r.over:CreateTexture(nil, "OVERLAY", nil, pool == "mark" and 1 or 0)
        end
        list[i] = t
    end
    return t
end

local function HideFrom(list, n)
    for i = n + 1, #list do list[i]:Hide() end
end

local function PaintRow(r)
    local db = SW.db
    local font = EV.Media:Fetch("font")
    local size = max(8, min(14, db.rowHeight))
    r.bg:SetColorTexture(T.RGBA("surfaceSunk", 0.85))   -- content colour: the track under the timer
    r.bar:SetStatusBarTexture(EV.Media:Fetch("statusbar", "Flat"))
    local cr, cg, cb = T.RGBA(r.def.token)
    r.bar:SetStatusBarColor(cr, cg, cb, 1)
    r.spark:SetColorTexture(1, 1, 1, 0.9)
    r.spark:SetHeight(db.rowHeight)
    for _, fs in ipairs({ r.time, r.label }) do
        fs:SetFont(font, size, "OUTLINE")
        fs:SetTextColor(T.RGBA("text"))
    end
    r.label:SetText(db.showLabel and r.def.tag or "")
end

-- A band from `from` to `to` (fractions of the bar), clipped to the bar.
local function Band(r, tex, from, to, token, alpha)
    from, to = max(0, from or 0), min(1, to or 0)
    if to <= from then tex:Hide(); return end
    local w = r:GetWidth()
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", r, "TOPLEFT", from * w, 0)
    tex:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", from * w, 0)
    tex:SetWidth(max(1, (to - from) * w))
    local cr, cg, cb = T.RGBA(token or "text")
    tex:SetColorTexture(cr, cg, cb, alpha or 0.4)
    tex:Show()
end

local function DrawRow(r, now)
    local ctx = r.ctx
    Reset(ctx, r, now)
    for i = 1, #live do
        local layer = live[i]
        if layer.Decorate then
            local ok, err = pcall(layer.Decorate, layer, ctx)
            if not ok and EV.debug then EV:Print("swing layer " .. layer.key .. ": " .. tostring(err)) end
        end
    end

    local p = ctx.progress
    r.bar:SetValue(p or 0)
    r.bar:SetStatusBarColor(ctx.cr, ctx.cg, ctx.cb, 1)
    if p then
        r.spark:ClearAllPoints()
        r.spark:SetPoint("CENTER", r.bar, "LEFT", r:GetWidth() * p, 0)
        r.spark:Show()
    else
        r.spark:Hide()
    end

    if ctx.text then
        r.time:SetText(ctx.text)
        r.time:SetTextColor(T.RGBA(ctx.textToken or "text"))
        r.time:Show()
    else
        r.time:SetTextColor(T.RGBA("text"))
        r.time:SetShown(SW.db.showText)
        if ctx.swinging and SW.db.showText then
            r.time:SetFormattedText("%.1f", ctx.remaining)
        else
            r.time:SetText("")
        end
    end
    r.label:SetText(ctx.label or (SW.db.showLabel and r.def.tag) or "")

    for i = 1, ctx.nUnder do
        local e = ctx.under[i]
        Band(r, Tex(r, "under", i), e[1], e[2], e[3], e[4])
    end
    HideFrom(r.pools.under, ctx.nUnder)
    for i = 1, ctx.nZone do
        local e = ctx.zone[i]
        Band(r, Tex(r, "zone", i), e[1], e[2], e[3], e[4])
    end
    HideFrom(r.pools.zone, ctx.nZone)
    local w = r:GetWidth()
    local shown = 0
    for i = 1, ctx.nMark do
        local e = ctx.mark[i]
        if e[1] and e[1] >= 0 and e[1] <= 1 then
            shown = shown + 1
            local tex = Tex(r, "mark", shown)
            local mw = e[3] or 2
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", r, "TOPLEFT", e[1] * w - mw / 2, 0)
            tex:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", e[1] * w - mw / 2, 0)
            tex:SetWidth(mw)
            tex:SetColorTexture(T.RGBA(e[2] or "text"))
            tex:Show()
        end
    end
    HideFrom(r.pools.mark, shown)

    r:SetAlpha((r.outOfRange and 0.4 or 1) * (ctx.dim or 1))
end

local function DrawAll(now)
    now = now or GetTime()
    for _, r in ipairs(rows) do
        if r:IsShown() then DrawRow(r, now) end
    end
end

--------------------------------------------------------------------------------
--  Layout and visibility
--------------------------------------------------------------------------------
local function AnyLive()
    for _, r in ipairs(rows) do if r:IsShown() and r.active then return true end end
    return false
end

local function AnyKept(now)
    for _, r in ipairs(rows) do if r:IsShown() and Kept(r, now) then return true end end
    return false
end

local function UpdateVisibility()
    if not holder then return end
    local want
    if not SW:IsEnabled() or not SW.db.enabled then
        want = false
    elseif Unlocked() or SW.db.visibility == "always" then
        want = true
    else
        want = E.inCombat or AnyLive() or AnyKept(GetTime())
    end
    holder:SetShown(want and true or false)
end

local function Layout()
    if not holder then return end
    local db = SW.db
    local now = GetTime()
    local y = 0
    for _, r in ipairs(rows) do
        r:ClearAllPoints()
        if RowShown(r, now) then
            r:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -y)
            r:SetSize(db.width, db.rowHeight)
            r:Show()
            PaintRow(r)
            y = y + db.rowHeight + db.rowGap
        else
            r:Hide()
        end
    end
    holder:SetSize(db.width, max(db.rowHeight, y - db.rowGap))
    EV.Movers:Apply("SwingTimer")
    DrawAll(now)
    UpdateVisibility()
end

local function Tick()
    local now = GetTime()
    local going, relayout = false, false
    for _, r in ipairs(rows) do
        if r.active then
            local sw = E:Get(r.def.type)
            if not E:IsSwinging(r.def.type, now) and now >= (sw.ends or 0) + GRACE then
                -- No new swing followed the last: this weapon has stopped.
                r.active = false
                relayout = true
            else
                going = true
            end
        end
    end
    if relayout then Layout() else DrawAll(now) end
    if not going then
        ticker:Hide()
        UpdateVisibility()
    end
end

local function SetRowRange(r, value)
    local out = value == false
    if r.outOfRange == out then return end
    r.outOfRange = out
    if r:IsShown() then DrawRow(r, GetTime()) end
end

--------------------------------------------------------------------------------
--  Blizzard's timer, off through its own CVar while ours is on
--------------------------------------------------------------------------------
local CVAR = "showSwingTimer"
local function BlizzardTimer(ours)
    local g = EV.DB:GetGlobal()
    if ours and SW.db.hideBlizzard then
        if g.swingCVarBefore == nil then
            local ok, v = pcall(GetCVar, CVAR)
            g.swingCVarBefore = ok and v or false
        end
        pcall(SetCVar, CVAR, "0")
    elseif g.swingCVarBefore ~= nil then
        if g.swingCVarBefore then pcall(SetCVar, CVAR, g.swingCVarBefore) end
        g.swingCVarBefore = nil
    end
end

local function RangeWanted(swingType)
    local r = byType[swingType]
    return r and RowWanted(r.def) or false
end

--------------------------------------------------------------------------------
--  Built-in layers
--------------------------------------------------------------------------------
E:RegisterLayer("gcd", {
    title = L["Global cooldown"],
    description = L["Shades the part of the swing your global cooldown still covers, so you can see whether there's time for another ability before the swing lands."],
    default = true,
    order = 10,
    Decorate = function(_, row)
        if not row.swinging then return end
        local ends = E.gcd.ends
        if ends <= row.now then return end
        row:Underlay(0, row:At(ends), "textMuted", 0.35)
    end,
})

E:RegisterLayer("latency", {
    title = L["Latency"],
    description = L["Tints the end of each swing by your latency: anything you press in that stretch reaches the server after the swing has gone."],
    default = false,
    order = 20,
    Decorate = function(_, row)
        if not row.swinging or E.lag <= 0 or row.duration <= 0 then return end
        row:Zone(1 - E.lag / row.duration, 1, "danger", 0.4)
    end,
})

do
    local function Hostile()
        local exists = E.Read(UnitExists, "target")
        if not exists then return false end
        local can = E.Read(UnitCanAttack, "player", "target")
        local dead = E.Read(UnitIsDead, "target")
        return can and not dead and true or false
    end

    local function Warn()
        return E.inCombat and not E.attacking and E:InRange(E.MAIN_HAND) == true
            and not E:IsSwinging(E.RANGED) and Hostile()
    end

    local function Changed() SW:Relayout() end
    local EVENTS = { "attack", "combat", "range", "target" }

    E:RegisterLayer("autoattack", {
        title = L["Auto attack off"],
        description = L["Says so on the main hand bar when you're in combat, within reach of something hostile, and not attacking it."],
        default = true,
        order = 90,
        Keep = function(_, swingType) return swingType == E.MAIN_HAND and Warn() end,
        Decorate = function(_, row)
            if row.type ~= E.MAIN_HAND or not Warn() then return end
            row:Zone(0, 1, "warning", 0.18)
            row:Text(L["Auto attack off"], "warning")
        end,
        OnEnable = function() for _, ev in ipairs(EVENTS) do E:On(ev, Changed) end end,
        OnDisable = function() for _, ev in ipairs(EVENTS) do E:Off(ev, Changed) end end,
    })
end

--------------------------------------------------------------------------------
--  /evui swing: what each bar thinks is going on, for bug reports.
--------------------------------------------------------------------------------
EV:RegisterSlash("swing", function()
    if not holder then EV:Print(L["The swing timer isn't running on this client."]); return end
    local blizz = GetCVar and GetCVar(CVAR)
    EV:Print(("activeOnly=%s  visibility=%s  showSwingTimer(Blizzard)=%s  holder shown=%s"):format(
        tostring(SW.db.activeOnly), tostring(SW.db.visibility), tostring(blizz), tostring(holder:IsShown())))
    EV:Print(("in combat=%s  auto attack=%s  latency=%dms  gcd left=%.2fs"):format(
        tostring(E.inCombat), tostring(E.attacking), floor(E.lag * 1000 + 0.5), E:GCDRemaining()))
    local now = GetTime()
    for _, r in ipairs(rows) do
        local sw = E:Get(r.def.type)
        EV:Print(("%s: wanted=%s shown=%s active=%s swinging=%s range=%s speed=%s last %s"):format(
            r.def.tag, tostring(RowWanted(r.def)), tostring(r:IsShown()), tostring(r.active and true or false),
            tostring(E:IsSwinging(r.def.type, now)), tostring(E:InRange(r.def.type)),
            sw.speed and ("%.2f"):format(sw.speed) or "?",
            sw.start and ("%.1fs ago (%.2fs)"):format(now - sw.start, sw.duration) or "never"))
    end
    for _, rule in ipairs(E.RULES) do
        local state, rec = E:RuleState(rule)
        EV:Print(("rule %s: %s (streak %d, confirmed %d, contradicted %d)"):format(
            rule, state, rec.streak, rec.yes, rec.no))
    end
    local names = {}
    for _, layer in ipairs(live) do names[#names + 1] = layer.key end
    EV:Print("layers: " .. (#names > 0 and table.concat(names, ", ") or "none"))
end)

--------------------------------------------------------------------------------
--  Module
--------------------------------------------------------------------------------
--- Re-evaluates which rows show (a layer's Keep may have changed).
function SW:Relayout()
    if holder then Layout() end
end

function SW:Refresh()
    if not holder then return end
    local on = self:IsEnabled() and self.db.enabled
    SyncLayers()
    if on then
        BlizzardTimer(true)
        E:ArmRange(RangeWanted)
        E.Rearm()
    else
        -- Ours off first, so Blizzard's callback re-arms its own checks after.
        E:DisarmRange()
        BlizzardTimer(false)
    end
    for _, r in ipairs(rows) do
        r.outOfRange = E:InRange(r.def.type) == false
    end
    Layout()
end

function SW:OnEnable()
    E:Configure(function() return self.db end)
    holder = CreateFrame("Frame", "EvermoreUISwingTimer", UIParent)
    holder:SetFrameStrata("MEDIUM")
    holder:SetSize(self.db.width, self.db.rowHeight)
    ticker = CreateFrame("Frame", nil, holder)
    ticker:Hide()
    ticker:SetScript("OnUpdate", Tick)
    for _, def in ipairs(ROWS) do
        local r = BuildRow(def)
        rows[#rows + 1] = r
        byType[def.type] = r
        -- Fonts now: a bar that stays hidden still has its text set, and a
        -- font string with no font errors.
        PaintRow(r)
    end
    EV.Movers:Register(holder, "SwingTimer", L["Swing Timer"], { "CENTER", "CENTER", 0, -170 }, {
        group = L["Unit Frames"], page = "swingtimer",
        getSize = function() return self.db.width, holder:GetHeight() end,
        setSize = function(w) if w then self.db.width = floor(w + 0.5); self:Refresh() end end,   -- height follows the rows
        isDisabled = function() return not (self:IsEnabled() and self.db.enabled) end,
    })

    E:On("swing", function(_, swingType)
        local r = byType[swingType]
        if not (r and Allowed(r.def)) then return end
        if swingType ~= E.MAIN_HAND then canSwing[swingType] = true end
        local wasActive = r.active
        r.active = true
        if not wasActive then Layout() end
        ticker:Show()
        UpdateVisibility()
    end)
    E:On("moved", function() if holder:IsShown() then ticker:Show() end end)
    E:On("range", function(_, swingType, value)
        local r = byType[swingType]
        if r then SetRowRange(r, value) end
    end)
    E:On("combat", UpdateVisibility)
    E:On("layers", function() self:Refresh() end)
    E:Start()

    self:RegisterEvent("UNIT_ATTACK_SPEED", function(_, _, unit) if unit == "player" then Layout() end end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() self:Refresh() end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
    -- Moving it shows every bar it can have, so you can see its full size.
    self:RegisterMessage("EV_UNLOCK", Layout)
    self:RegisterMessage("EV_LOCK", Layout)
    self:RegisterMessage("EV_THEME_CHANGED", function() self:Refresh() end)
    self:RegisterMessage("EV_FONT_CHANGED", function() self:Refresh() end)
    self:Refresh()
end

function SW:OnProfileChanged() self:Refresh() end
