if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Presets.lua
--  Looking up what is on a unit, for /evui auras.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end

function ns.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    return "#" .. tostring(id)
end

--------------------------------------------------------------------------------
--  What is on a unit right now, with spell IDs
--
--  For /evui auras, which lists them. Hovering an aura does not get you
--  there: the engine's aura buttons show their tooltip on
--  AuraButtonTooltip, a restricted tooltip of Blizzard's own
--  (Blizzard_AuraContainerUtil.lua, GetDefaultTooltip), not GameTooltip, so
--  the Tooltips module's "Spell ID" line never reaches it.
--
--  GetAuraDataByIndex is SecretWhenUnitAuraRestricted, so in restricted
--  content (combat in an instance) the fields come back secret. Those are
--  skipped, never compared, and the caller is told how many were hidden.
--------------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

--- { { id =, name =, icon = }, ... } for the unit's buffs or debuffs, one row
--- per spell ID, plus how many auras were unreadable.
function ns.CurrentAuras(unit, harmful)
    local out, seen, hidden = {}, {}, 0
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return out, hidden end
    local filter = harmful and "HARMFUL" or "HELPFUL"
    for i = 1, 80 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok or type(a) ~= "table" then break end
        local id, name, icon = a.spellId, a.name, a.icon
        if issecret(id) or issecret(name) or type(id) ~= "number" then
            hidden = hidden + 1
        elseif not seen[id] then
            seen[id] = true
            -- Cast by you? nil when the game won't say.
            local mine = a.isFromPlayerOrPlayerPet
            if issecret(mine) or type(mine) ~= "boolean" then mine = nil end
            local dur = a.duration
            if issecret(dur) or type(dur) ~= "number" then dur = nil end
            out[#out + 1] = { id = id, name = (type(name) == "string" and name) or ns.SpellName(id),
                              icon = (not issecret(icon)) and icon or nil, mine = mine, duration = dur }
        end
    end
    table.sort(out, function(x, y) return x.name < y.name end)
    return out, hidden
end
