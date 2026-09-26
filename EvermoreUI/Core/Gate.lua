--------------------------------------------------------------------------------
--  Gate.lua
--  First file in the suite. Feature-detects the client and records what it
--  finds in EvermoreUI.Caps. Never gates on build or interface number: Forever
--  reports 16001 while running the retail codebase, so "build >= 100000"
--  style checks pick the wrong path.
--
--  If a hard requirement is missing, EV_BLOCKED is set and line 1 of every
--  other suite file returns immediately. No DB is touched in that case.
--  Fail-open: anything we can't read is treated as present.
--------------------------------------------------------------------------------

EvermoreUI = EvermoreUI or {}
local EV = EvermoreUI

local version, build, date, iface = GetBuildInfo()

local caps = {
    -- identity
    version      = version,
    build        = build,
    buildDate    = date,
    interface    = iface,
    projectID    = WOW_PROJECT_ID,
    isMainline   = (WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE),

    -- API surface (static checks; runtime probes live in Probes.lua)
    secrets           = C_Secrets ~= nil,
    restrictedActions = C_RestrictedActions ~= nil,
    editMode          = C_EditMode ~= nil,
    cooldownViewer    = C_CooldownViewer ~= nil,
    unitAuras         = C_UnitAuras ~= nil,
    spellNS           = C_Spell ~= nil,
    itemNS            = C_Item ~= nil,
    specAPI           = type(GetSpecialization) == "function",
    wrapScriptAPI     = type(SecureHandlerWrapScript) == "function",
    pixelUtil         = PixelUtil ~= nil,

    -- runtime probes, filled later (nil = not yet run)
    secureSnippets = nil,
    svLoaded       = nil,
}
EV.Caps = caps

-- Hard requirements. Keep this list short: everything else degrades per module.
local missing = {}
if not C_Timer then missing[#missing + 1] = "C_Timer" end
if not C_AddOns then missing[#missing + 1] = "C_AddOns" end
if type(CreateFrame) ~= "function" then missing[#missing + 1] = "CreateFrame" end

if #missing > 0 then
    EV_BLOCKED = true
    caps.blockedBy = table.concat(missing, ", ")
    local f = CreateFrame and CreateFrame("Frame")
    if f then
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            print("|cffd4924eEvermoreUI|r: disabled, this client is missing " .. caps.blockedBy .. ". Your settings have not been touched.")
        end)
    end
end
