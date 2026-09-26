if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Alts.lua
--  Who your characters are, for anything that compares them: name, realm,
--  class, race, faction, level and when you last played them. Written each
--  time a character logs in or levels, into the account-wide per-character
--  store (DB:GetCharData("info")), so every character's record is readable
--  from any other.
--
--  This is the base of the alt data: features add their own per-character
--  tables beside "info" (loot luck does, as "lootStats") and read them back
--  across characters with EV.Alts:List().
--------------------------------------------------------------------------------
local EV = EvermoreUI
local A = {}
EV.Alts = A

local function Record()
    if not (EV.DB and EV.dbReady) then return end
    local info = EV.DB:GetCharData("info")
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    local faction = UnitFactionGroup("player")
    info.name = UnitName("player")
    info.realm = GetRealmName()
    info.class = class
    info.race = race
    info.faction = faction
    info.level = UnitLevel("player")
    info.seen = time()
end
A.Record = Record

--- Every known character: { key, info, data }, optionally filtered.
--- opts.faction = "same" keeps your own faction; opts.realm = "same" your realm.
function A:List(opts)
    opts = opts or {}
    local me = EV.DB.charKey
    local myFaction = UnitFactionGroup("player")
    local myRealm = GetRealmName()
    local out = {}
    for key, data in pairs(EV.DB:AllChars()) do
        local info = type(data) == "table" and data.info
        if type(info) == "table" and info.name then
            local ok = true
            if opts.faction == "same" and info.faction and info.faction ~= myFaction then ok = false end
            if opts.realm == "same" and info.realm ~= myRealm then ok = false end
            if ok then out[#out + 1] = { key = key, info = info, data = data, me = key == me } end
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        return (a.info.name or "") < (b.info.name or "")
    end)
    return out
end

--- "|cffRRGGBBName|r" in the character's class colour.
function A:Coloured(info)
    local r, g, b = EV.Palette.ClassRGB(info and info.class)
    local name = info and info.name or "?"
    if not r then return name end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, name)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event)
    -- PLAYER_LEVEL_UP carries the new level before UnitLevel catches up.
    if event == "PLAYER_LEVEL_UP" then C_Timer.After(1, Record) else Record() end
end)
