if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Combo.lua
--  Combo points, read once for every surface that draws them: the player
--  frame's pips (EvermoreUI_UnitFrames/ClassPower.lua) and the ones on your
--  target's nameplate (EvermoreUI_Nameplates/Combo.lua).
--
--  The count may be secret. It is only ever handed to StatusBar:SetValue on
--  pips whose range is one point wide (pip i runs from i-1 to i), so the
--  bar's own clamping lights exactly the pips you have and nothing here has
--  to compare or add it.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local issecret = issecretvalue or function() return false end

local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
local ENERGY = Enum and Enum.PowerType and Enum.PowerType.Energy or 3

local _, CLASS = UnitClass("player")

--- Classes that ever have combo points.
function EV.HasComboClass() return CLASS == "ROGUE" or CLASS == "DRUID" end

--- Current points, and the maximum when it can be read (else nil). The
--- count may be secret; the maximum is only returned when it's plain.
--- Newer clients keep points on the player (UnitPower), classic ones on
--- the target (GetComboPoints); whichever answers is used.
function EV.ComboPoints()
    local ok, v = pcall(UnitPower, "player", COMBO)
    local okM, m = pcall(UnitPowerMax, "player", COMBO)
    if ok and okM and type(v) ~= "nil" and type(m) == "number" and (issecret(m) or m > 0) then
        return v, (not issecret(m)) and m or nil
    end
    if type(GetComboPoints) == "function" then
        local okC, c = pcall(GetComboPoints, "player", "target")
        if okC and type(c) ~= "nil" then return c, nil end
    end
    return nil
end

--- Should combo points show right now: always for a rogue, for a druid
--- while their power is energy (Cat Form). A power type we can't read
--- counts as yes.
function EV.WantsComboPoints()
    if CLASS == "ROGUE" then return true end
    if CLASS == "DRUID" then
        local ok, pType = pcall(UnitPowerType, "player")
        if not ok or issecret(pType) then return true end
        return pType == ENERGY
    end
    return false
end

--- The events that can change either answer. Callers register them on
--- their own frames (pcall: not every client knows every one).
EV.COMBO_EVENTS = {
    "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "PLAYER_TARGET_CHANGED", "UPDATE_SHAPESHIFT_FORM", "UNIT_COMBO_POINTS",
    "PLAYER_ENTERING_WORLD",
}

--- Does this event matter for combo points? unit and token are the event's
--- first two arguments.
function EV.IsComboEvent(event, unit, token)
    if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
        return unit == "player" and (token == nil or token == "COMBO_POINTS")
    elseif event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        return unit == "player"
    end
    return true
end
