if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Look.lua
--  How the cooldown icons look, and the three things they can tell you
--  beyond their cooldown:
--
--    Look       border thickness and colour, how far the icon is cropped,
--               how dark the cooldown swipe is.
--    Procs      when the game lights a spell up (Blizzard's proc alert on
--               the item: ActionButtonSpellAlertManager), ours shows in the
--               style you pick instead: a pulsing border, a solid border,
--               Blizzard's own glow sized to our square icons, or nothing.
--    Usable     reactive abilities that only become usable after something
--               happens (Overpower after a dodge, Revenge after a block,
--               Execute below 20%, Riposte after a parry, Counterattack...).
--               Forever keeps the classic rules, so these are "usable" states
--               rather than proc alerts; the icon glows while it's usable.
--               Seeded per class, and any cooldown can be switched on in its
--               inspector.
--    Refresh    the window in which re-casting a buff or debuff wastes
--               nothing. The client's own pandemic effect only fires when a
--               re-cast would carry time over, which Forever's auras mostly
--               don't, so we draw our own: the last N seconds, or the last N%
--               of the aura. The remaining time can be secret in combat, so
--               it never reaches our code as a number: the aura's duration
--               object evaluates a step curve C-side and the result goes
--               straight into SetAlpha.
--
--  Nothing is written onto Blizzard's frames: our glow frames are children
--  of the items, and every note lives in the module's weak state table.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local M = ns.module
local floor, max, min = math.floor, math.max, math.min
local issecret = issecretvalue or function() return false end

M.defaults.look = {
    border      = 1,          -- px; 0 = none
    borderColour = "border",  -- theme token, or "class"
    zoom        = 8,          -- percent cropped off each edge
    swipe       = 70,         -- cooldown swipe darkness, percent
    proc        = "pulse",    -- "pulse" | "border" | "blizzard" | "none"
    procColour  = "title",
    usableGlow  = true,       -- reactive abilities glow while usable
    refresh     = "percent",  -- "percent" | "seconds" | "blizzard" | "off"
    refreshPct  = 30,
    refreshSec  = 3,
    refreshColour = "warning",
}
-- Spells that glow while usable, by rank 1 spell ID, per class (seeded once)
-- plus your own: usable[CLASS] = { [spellID] = true | false }.
M.defaults.usable = {}
M.defaults.usableSeeded = {}

local USABLE_SEEDS = {
    WARRIOR = { 7384, 6572, 5308 },     -- Overpower, Revenge, Execute
    ROGUE   = { 14251 },                -- Riposte
    HUNTER  = { 19306, 1495 },          -- Counterattack, Mongoose Bite
    PALADIN = { 24275 },                -- Hammer of Wrath
}

local COLOURS = {
    { value = "border",       text = L["Theme border"] },
    { value = "borderStrong", text = L["Theme border, strong"] },
    { value = "accent",       text = L["Accent"] },
    { value = "title",        text = L["Gold"] },
    { value = "class",        text = L["Class colour"] },
    { value = "black",        text = L["Black"] },
}
ns.LOOK_COLOURS = COLOURS

local function Colour(token)
    if token == "class" then
        local _, class = UnitClass("player")
        local r, g, b = EV.Palette.ClassRGB(class)
        if r then return r, g, b, 1 end
        token = "accent"
    elseif token == "black" then
        return 0, 0, 0, 1
    end
    return T.RGBA(token)
end
ns.LookColour = Colour

local function Look() return M.db.look end

--------------------------------------------------------------------------------
--  Border, crop, swipe
--------------------------------------------------------------------------------
function ns.ApplyLook(f, s)
    local lk = Look()
    if s.edge then
        local size = lk.border or 1
        EV.Pixel:CreateBorder(s.edge, max(1, size), Colour(lk.borderColour))
        s.edge:SetShown(size > 0)
    end
    local z = (lk.zoom or 8) / 100
    if f.Icon and f.Icon.SetTexCoord then f.Icon:SetTexCoord(z, 1 - z, z, 1 - z) end
    local cd = f.Cooldown
    if cd and cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, (lk.swipe or 70) / 100) end
end

--------------------------------------------------------------------------------
--  Glows: one frame of ours per item, holding the proc glow, the usable glow
--  and the refresh highlight. Each is a hairline ring outside the icon.
--------------------------------------------------------------------------------
local function Ring(parent, level, inset)
    local r = CreateFrame("Frame", nil, parent)
    r:SetPoint("TOPLEFT", -inset, inset)
    r:SetPoint("BOTTOMRIGHT", inset, -inset)
    r:SetFrameLevel(level)
    r:EnableMouse(false)
    r:Hide()
    return r
end

local function Glows(f, s)
    if s.glow then return s.glow end
    local g = {}
    local level = f:GetFrameLevel() + 6
    g.proc = Ring(f, level + 2, 1)
    local pulse = g.proc:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.45)
    g.pulse = pulse
    g.usable = Ring(f, level + 1, 1)
    g.refresh = Ring(f, level, 0)
    -- The refresh highlight is always shown while an aura is tracked; its
    -- alpha (0 or 1, from the curve) decides whether you see it.
    g.refreshTint = g.refresh:CreateTexture(nil, "OVERLAY")
    g.refreshTint:SetAllPoints()
    g.refreshTint:SetBlendMode("ADD")
    s.glow = g
    return g
end

local function Paint(g)
    local lk = Look()
    local thick = max(2, (lk.border or 1) + 1)
    EV.Pixel:CreateBorder(g.proc, thick, Colour(lk.procColour))
    EV.Pixel:CreateBorder(g.usable, thick, Colour(lk.procColour))
    local r, gg, b = Colour(lk.refreshColour)
    EV.Pixel:CreateBorder(g.refresh, thick, r, gg, b, 1)
    g.refreshTint:SetColorTexture(r, gg, b, 0.18)
end

--------------------------------------------------------------------------------
--  Procs
--------------------------------------------------------------------------------
local procOn = setmetatable({}, { __mode = "k" })   -- item -> true while the game says so

--- Blizzard's alert frame on an item, if it has made one (read, never written).
local function BlizzardAlert(f)
    local a = f.SpellActivationAlert
    return type(a) == "table" and a.SetAlpha and a or nil
end

local function ShowProc(f)
    local s = ns.state[f]
    if not s then return end
    local g = Glows(f, s)
    local style = Look().proc
    local on = procOn[f] and true or false
    local alert = BlizzardAlert(f)
    if alert then
        if style == "blizzard" and on then
            -- Theirs, sized to our square icon (it's made once, at their size).
            local w, h = f:GetSize()
            alert:SetSize(w * 1.4, h * 1.4)
            alert:SetAlpha(1)
        else
            alert:SetAlpha(0)
        end
    end
    local ours = on and (style == "pulse" or style == "border")
    g.proc:SetShown(ours)
    if ours and style == "pulse" then g.pulse:Play() else g.pulse:Stop() end
end
ns.ShowProc = ShowProc

local procHooked = false
function ns.HookProcs()
    if procHooked or not ActionButtonSpellAlertManager then return end
    procHooked = true
    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, button)
        if ns.state[button] and M:IsEnabled() then procOn[button] = true; ShowProc(button) end
    end)
    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, button)
        if ns.state[button] and procOn[button] then procOn[button] = nil; ShowProc(button) end
    end)
end

--------------------------------------------------------------------------------
--  Usable (reactive abilities)
--------------------------------------------------------------------------------
local function UsableList()
    local _, class = UnitClass("player")
    local t = M.db.usable[class]
    if type(t) ~= "table" then t = {}; M.db.usable[class] = t end
    if not M.db.usableSeeded[class] then
        M.db.usableSeeded[class] = true
        for _, id in ipairs(USABLE_SEEDS[class] or {}) do if t[id] == nil then t[id] = true end end
    end
    return t
end

--- Names are what match: every rank of a spell counts.
local usableNames, namesAt = {}, nil
local function UsableNames()
    local list = UsableList()
    if namesAt == list and next(usableNames) then return usableNames end
    wipe(usableNames)
    for id, on in pairs(list) do
        local name = on and M.SpellName(id)
        if name then usableNames[name] = true end
    end
    namesAt = list
    return usableNames
end
function ns.UsableChanged() namesAt = nil end

--- Is this spell (by ID, any rank) set to glow while usable?
function ns.IsUsableGlow(spellID)
    local name = M.SpellName(spellID)
    return name and UsableNames()[name] or false
end

function ns.SetUsableGlow(spellID, on)
    local list = UsableList()
    local name = M.SpellName(spellID)
    -- One entry per spell: drop any other rank's.
    for id in pairs(list) do if M.SpellName(id) == name then list[id] = nil end end
    list[spellID] = on and true or false
    ns.UsableChanged()
    ns.UpdateUsable()
end

local function ItemSpellID(f)
    local info = f.cooldownInfo
    if type(info) == "table" then
        local id = info.overrideSpellID or info.spellID
        if type(id) == "number" and not issecret(id) then return id end
    end
end

local function Usable(id)
    if not (C_Spell and C_Spell.IsSpellUsable) then return false end
    local ok, usable = pcall(C_Spell.IsSpellUsable, id)
    if not ok or issecret(usable) then return false end
    if not usable then return false end
    -- On its own cooldown (not the global one): not yet.
    if C_Spell.GetSpellCooldown then
        local okC, cd = pcall(C_Spell.GetSpellCooldown, id)
        if okC and type(cd) == "table" and EV.Usable(cd.duration) and EV.Usable(cd.startTime)
           and cd.duration > 1.6 and cd.startTime + cd.duration - GetTime() > 0.1 then
            return false
        end
    end
    return true
end

function ns.UpdateUsable()
    local on = Look().usableGlow and M:IsEnabled()
    local names = on and UsableNames() or nil
    for f, s in pairs(ns.state) do
        if not (s.def and s.def.buff) then
            local lit = false
            if names then
                local id = ItemSpellID(f)
                local name = id and M.SpellName(id)
                lit = name and names[name] and Usable(id) or false
            end
            if lit or s.glow then
                local g = Glows(f, s)
                g.usable:SetShown(lit and true or false)
            end
        end
    end
end

--------------------------------------------------------------------------------
--  Refresh window
--------------------------------------------------------------------------------
local curve, curveKey

--- A step curve: 1 inside the window, 0 outside it. x is seconds remaining
--- or the fraction remaining, whichever the mode uses.
local function Curve()
    local lk = Look()
    local edge = lk.refresh == "seconds" and (lk.refreshSec or 3) or (lk.refreshPct or 30) / 100
    local key = lk.refresh .. ":" .. edge
    if curve and curveKey == key then return curve end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateCurve)
    if not (ok and c) then return nil end
    local step = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if step then pcall(c.SetType, c, step) end
    pcall(c.AddPoint, c, 0, 1)
    pcall(c.AddPoint, c, edge, 1)
    pcall(c.AddPoint, c, edge + 0.0001, 0)
    pcall(c.AddPoint, c, lk.refresh == "seconds" and 100000 or 1, 0)
    curve, curveKey = c, key
    return c
end
function ns.RefreshCurveChanged() curve = nil end

--- The aura an item is showing: unit and instance, both plain, or nil.
local function AuraOf(f)
    local id, unit = f.auraInstanceID, f.auraDataUnit
    if type(id) ~= "number" or issecret(id) or type(unit) ~= "string" then return nil end
    return unit, id
end

local function UpdateRefresh(f, s)
    local lk = Look()
    local mode = lk.refresh
    local alert = f.PandemicIcon
    if type(alert) == "table" and alert.SetAlpha then
        -- Blizzard's own pandemic effect: kept (and squared up) only in its mode.
        if mode == "blizzard" then
            alert:ClearAllPoints()
            alert:SetAllPoints(f)
            alert:SetAlpha(1)
        else
            alert:SetAlpha(0)
        end
    end
    if mode ~= "percent" and mode ~= "seconds" then
        if s.glow then s.glow.refresh:Hide() end
        return false
    end
    local unit, id = AuraOf(f)
    if not unit then
        if s.glow then s.glow.refresh:Hide() end
        return false
    end
    local c = Curve()
    if not (c and C_UnitAuras and C_UnitAuras.GetAuraDuration) then return false end
    local ok, dur = pcall(C_UnitAuras.GetAuraDuration, unit, id)
    if not (ok and dur) then
        if s.glow then s.glow.refresh:Hide() end
        return false
    end
    local fn = mode == "seconds" and dur.EvaluateRemainingDuration or dur.EvaluateRemainingPercent
    if not fn then return false end
    local okE, v = pcall(fn, dur, c)
    if not okE or type(v) == "nil" then return false end
    local g = Glows(f, s)
    g.refresh:Show()
    -- v may be secret: straight into the setter, never compared.
    pcall(g.refresh.SetAlpha, g.refresh, v)
    return true
end

ns.UpdateRefresh = UpdateRefresh

local ticker
function ns.StartRefreshTicker()
    if ticker then return end
    ticker = CreateFrame("Frame")
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        if not M:IsEnabled() then return end
        for f, s in pairs(ns.state) do
            if f:IsShown() and f:IsVisible() then pcall(UpdateRefresh, f, s) end
        end
    end)
end

--------------------------------------------------------------------------------
--  All of it, for one item and for everything
--------------------------------------------------------------------------------
function ns.LookItem(f, s)
    ns.ApplyLook(f, s)
    if s.glow then Paint(s.glow) else Paint(Glows(f, s)) end
    ShowProc(f)
end

function ns.LookAll()
    ns.RefreshCurveChanged()
    ns.UsableChanged()
    for f, s in pairs(ns.state) do pcall(ns.LookItem, f, s) end
    ns.UpdateUsable()
end

function ns.EnableLook()
    ns.HookProcs()
    ns.StartRefreshTicker()
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "SPELL_UPDATE_USABLE", "SPELL_UPDATE_COOLDOWN", "PLAYER_TARGET_CHANGED",
                         "UNIT_HEALTH", "PLAYER_REGEN_ENABLED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    local queued = false
    ev:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_HEALTH" and unit ~= "target" then return end
        if queued then return end
        queued = true
        C_Timer.After(0.05, function() queued = false; ns.UpdateUsable() end)
    end)
end
