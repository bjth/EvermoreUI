if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Install.lua
--  When setup runs. The setup window itself is in EvermoreUI_Options
--  (Install.lua there), which loads on demand; this file only decides when
--  to open it, so a finished account never loads the options addon at login.
--
--  Setup is account-wide (DB global `install`): once finished or skipped on
--  one character it doesn't come back on the next. Closing it part way
--  through leaves it pending, and it opens once more at the next login,
--  on the step you left.
--
--  /evui install (or /evui setup) opens it any time.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local function State()
    local g = EV.DB:GetGlobal()
    if type(g.install) ~= "table" then g.install = {} end
    return g.install
end
EV.InstallState = State

--- True until setup has been finished or skipped on this account.
function EV.InstallPending()
    if not (EV.DB and EV.dbReady) then return false end
    return not State().done
end

function EV:OpenInstaller(step)
    if InCombatLockdown() then
        self:Print(L["Setup is available out of combat."])
        return
    end
    if not C_AddOns.IsAddOnLoaded("EvermoreUI_Options") then
        local ok, reason = C_AddOns.LoadAddOn("EvermoreUI_Options")
        if not ok then self:Print(L["Couldn't load EvermoreUI_Options:"], tostring(reason)) return end
    end
    if self.Installer then self.Installer:Show(step) end
end

local waiting = false

local function Check()
    if not EV.InstallPending() then return end
    if InCombatLockdown() then waiting = true return end
    waiting = false
    EV:OpenInstaller()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Whether this account used EvermoreUI before setup existed, decided
        -- once, before What's New marks this version as seen.
        if EV.InstallPending() then
            local s = State()
            if s.returning == nil then s.returning = EV.DB:GetGlobal().lastSeenVersion ~= nil end
        end
        -- After the login burst, ahead of the What's New check (which stands
        -- aside while setup is pending).
        C_Timer.After(2.5, Check)
    elseif waiting then
        C_Timer.After(1, Check)
    end
end)

EV:RegisterSlash("install", function() EV:OpenInstaller(1) end)
EV:RegisterSlash("setup", function() EV:OpenInstaller(1) end)
