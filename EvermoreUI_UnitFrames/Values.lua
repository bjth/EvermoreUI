if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Values.lua
--  Health and power text that copes with Midnight-style secret values.
--
--  When a value is readable we format it ourselves. When it's secret we can't
--  do arithmetic or build strings from it, but the client can still display
--  it: FontString:SetFormattedText and the *Percent APIs accept secrets. Every
--  secret path runs inside pcall, so the worst case is blank text, never an
--  error.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local V = {}
ns.Values = V

local floor = math.floor

-- Comparing a secret (even with nil) can error, so test with type() and
-- issecretvalue() only.
local function IsSecret(v) return issecretvalue ~= nil and type(v) ~= "nil" and issecretvalue(v) end
V.IsSecret = IsSecret

--- 12345 -> "12.3k", 1234567 -> "1.23m"
function V.Short(n)
    if n >= 1e9 then return ("%.2fb"):format(n / 1e9) end
    if n >= 1e6 then return ("%.2fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
    return tostring(floor(n + 0.5))
end

-- Percent (0-100) from the client's own API, secret or not.
local function ApiPercent(kind, unit)
    local fn = kind == "health" and UnitHealthPercent or UnitPowerPercent
    if type(fn) ~= "function" then return nil end
    local curve = CurveConstants and CurveConstants.ScaleTo100
    local ok, v
    if kind == "health" then
        ok, v = pcall(fn, unit, true, curve)
    else
        ok, v = pcall(fn, unit, nil, true, curve)
    end
    if not ok or type(v) == "nil" then return nil end
    if curve then return v end
    -- Unscaled (0-1). Only scale it if we're allowed to do arithmetic on it.
    if IsSecret(v) then return nil end
    return v * 100
end

local function SetSafe(fs, fmt, ...)
    local ok = pcall(fs.SetFormattedText, fs, fmt, ...)
    if not ok then fs:SetText("") end
end

local function SecretShort(v)
    if type(AbbreviateNumbers) == "function" then
        local ok, s = pcall(AbbreviateNumbers, v)
        if ok then return s end
    end
    return v
end

--- Write a value in the chosen style.
--- mode: none | percent | current | curmax | curpercent | deficit
function V.Write(fs, mode, kind, unit, cur, max)
    if mode == "none" then fs:SetText(""); return end

    if not IsSecret(cur) and not IsSecret(max) then
        cur, max = cur or 0, max or 0
        local pct = max > 0 and cur / max * 100 or 0
        if mode == "percent" then
            fs:SetFormattedText("%d%%", floor(pct + 0.5))
        elseif mode == "current" then
            fs:SetText(V.Short(cur))
        elseif mode == "curmax" then
            fs:SetFormattedText("%s / %s", V.Short(cur), V.Short(max))
        elseif mode == "curpercent" then
            fs:SetFormattedText("%s  |cffb0b0b0%d%%|r", V.Short(cur), floor(pct + 0.5))
        elseif mode == "deficit" then
            local d = max - cur
            if d > 0 then fs:SetFormattedText("|cffff7070-%s|r", V.Short(d)) else fs:SetText("") end
        end
        return
    end

    -- Secret: let the client render it.
    if mode == "percent" or mode == "deficit" then
        local p = ApiPercent(kind, unit)
        if type(p) ~= "nil" then
            SetSafe(fs, "%.0f%%", p)
        else
            fs:SetText("")
        end
    elseif mode == "current" then
        SetSafe(fs, "%s", SecretShort(cur))
    elseif mode == "curmax" then
        SetSafe(fs, "%s / %s", SecretShort(cur), SecretShort(max))
    elseif mode == "curpercent" then
        local p = ApiPercent(kind, unit)
        if type(p) ~= "nil" then
            SetSafe(fs, "%s  |cffb0b0b0%.0f%%|r", SecretShort(cur), p)
        else
            SetSafe(fs, "%s", SecretShort(cur))
        end
    end
end
