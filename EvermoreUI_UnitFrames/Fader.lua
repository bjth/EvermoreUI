if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Fader.lua
--  Fade the player and pet frames away when there is nothing to watch, and
--  bring them back the moment there is: in combat, with a target, while
--  casting, when hurt or low on power, or under the mouse.
--
--  Only alpha changes, which is allowed on a protected frame in combat, so
--  the frame keeps working (clicks, click casting) while faded.
--
--  Health and power are read only when they can be: a secret value counts
--  as "show", which errs on the side of the frame being there. They are
--  mostly secret in combat, where the combat rule shows the frame anyway.
--
--  cfg.fader = { enabled, alpha, combat, target, casting, health, power,
--                mouseover }
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local V = ns.Values

local FD = {}
ns.Fader = FD

local SPEED = 5            -- alpha per second: a quarter second end to end
local faded = {}           -- key -> frame, the frames with a fader on

local function Readable(v) return type(v) == "number" and not V.IsSecret(v) end

--- Is anything asking for this frame to be seen?
local function Wanted(f, c)
    local unit = f.unit
    if c.combat and UnitAffectingCombat("player") then return true end
    if c.target and UnitExists("target") then return true end
    if c.casting then
        local h = f.castbar
        if h and (h.casting or h._hold) then return true end
        local ok, name = pcall(UnitCastingInfo, unit)
        if ok and type(name) ~= "nil" then return true end
        ok, name = pcall(UnitChannelInfo, unit)
        if ok and type(name) ~= "nil" then return true end
    end
    if c.health and UnitExists(unit) then
        local cur, mx = UnitHealth(unit), UnitHealthMax(unit)
        if not (Readable(cur) and Readable(mx)) then return true end
        if cur < mx then return true end
    end
    if c.power and UnitExists(unit) then
        local ok, pType = pcall(UnitPowerType, unit)
        if ok and Readable(pType) then
            local cur, mx = UnitPower(unit, pType), UnitPowerMax(unit, pType)
            if not (Readable(cur) and Readable(mx)) then return true end
            -- Rage and runic power drain to empty at rest, so "not full"
            -- would never let them fade: for those, anything above 0 counts.
            local drains = pType == 1 or pType == 6
            if drains then
                if cur > 0 then return true end
            elseif cur < mx then
                return true
            end
        end
    end
    if c.mouseover and f:IsMouseOver() then return true end
    return false
end

local function Step(f, elapsed)
    local goal = f.evFadeGoal or 1
    local a = f:GetAlpha()
    if math.abs(a - goal) < 0.01 then
        f:SetAlpha(goal)
        f.evFader:SetScript("OnUpdate", nil)
        return
    end
    local d = SPEED * elapsed
    if a < goal then a = math.min(a + d, goal) else a = math.max(a - d, goal) end
    f:SetAlpha(a)
end

function FD.Update(f)
    local M = ns.module
    local cfg = M and M.db and M.db[f.key]
    local c = cfg and cfg.fader
    if not (c and c.enabled and cfg.enabled) then
        if f.evFadeGoal then
            f.evFadeGoal = nil
            if f.evFader then f.evFader:SetScript("OnUpdate", nil) end
            f:SetAlpha(1)
        end
        return
    end
    local goal = Wanted(f, c) and 1 or (c.alpha or 0)
    if EV.Movers and EV.Movers:IsUnlocked() then goal = 1 end
    if goal == f.evFadeGoal and math.abs(f:GetAlpha() - goal) < 0.01 then return end
    f.evFadeGoal = goal
    if not f.evFader then f.evFader = CreateFrame("Frame", nil, UIParent) end
    f.evFader:SetScript("OnUpdate", function(_, e) Step(f, e) end)
end

function FD.Attach(f)
    if f.evFaderHooked then return end
    f.evFaderHooked = true
    faded[f.key] = f
    f:HookScript("OnEnter", function(self) FD.Update(self) end)
    f:HookScript("OnLeave", function(self) FD.Update(self) end)
end

function FD.UpdateAll()
    for _, f in pairs(faded) do FD.Update(f) end
end

function FD.Enable(M)
    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED",
                         "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
                         "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED",
                         "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
                         "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event, unit)
        if not M:IsEnabled() then return end
        if unit and unit ~= "player" and unit ~= "pet" and event ~= "UNIT_PET" then return end
        -- The "Interrupted" hold outlives the event; look again after it.
        if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_STOP"
           or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            C_Timer.After(0.7, FD.UpdateAll)
        end
        FD.UpdateAll()
    end)
end
