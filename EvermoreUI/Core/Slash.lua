if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Slash.lua
--  /evui            open options (loads EvermoreUI_Options on demand)
--  /evui caps       client capability report
--  /evui edit       toggle edit mode (also /evui unlock, /evui lock)
--  /evui profile    list profiles, or /evui profile <name> to switch/create
--  /evui modules    list modules and their state
--  /evui copy       copy the selected chat window
--  /evui bug        bug report to copy into an issue (also /evui report)
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

function EV:OpenOptions()
    if not C_AddOns.IsAddOnLoaded("EvermoreUI_Options") then
        local loaded, reason = C_AddOns.LoadAddOn("EvermoreUI_Options")
        if not loaded then
            self:Print(L["Couldn't load EvermoreUI_Options:"], tostring(reason))
            return
        end
    end
    if self.Options and self.Options.Toggle then
        self.Options:Toggle()
    end
end

-- Blizzard's addon compartment (the minimap's addons button) lists us from
-- the TOC; clicking the entry opens the options.
function EvermoreUI_OnAddonCompartmentClick() EV:OpenOptions() end

local handlers = {}

--- Modules add their own /evui commands (e.g. debugging aids).
function EV:RegisterSlash(cmd, fn) handlers[cmd:lower()] = fn end

handlers.caps = function() EV:PrintCaps() end
handlers.edit = function() EV.Movers:Toggle() end
handlers.unlock = handlers.edit
handlers.move = handlers.edit
handlers.lock = function() EV.Movers:Lock() end

handlers.copy = function()
    local chat = EV:GetModule("Chat", true)
    if chat and chat:IsEnabled() then chat:CopyMain() else EV:Print(L["The chat module isn't loaded."]) end
end

handlers.bug = function() EV.Report:Show() end
handlers.report = handlers.bug

handlers.profile = function(rest)
    if rest == "" then
        EV:Print(L["Active profile:"], EV:Colour(EV.DB:GetProfileName()))
        print("  " .. table.concat(EV.DB:ListProfiles(), ", "))
        return
    end
    EV.DB:SetProfile(rest)
    EV:Print(L["Switched to profile"], EV:Colour(rest))
end

-- Profile strings: the same text the options page copies out and takes in.
handlers.export = function()
    local str, err = EV.DB:ExportProfile()
    if not str then EV:Print(L["Couldn't export:"], tostring(err)); return end
    if EV.UI and EV.UI.ShowCopyText then
        EV.UI.ShowCopyText(L["Export profile"] .. " - " .. EV.DB:GetProfileName(), str,
            L["Select all is done for you. Ctrl+C to copy."])
    else
        EV:Print(str)
    end
end

handlers.import = function(rest)
    if rest ~= "" then
        local ok, info = EV.DB:ImportProfile(rest)
        EV:Print(ok and (L["Imported profile"] .. " " .. EV:Colour(tostring(info or ""))) or (L["Couldn't import:"] .. " " .. tostring(info)))
        return
    end
    if not (EV.UI and EV.UI.ShowPasteText) then EV:Print(L["Paste the string after the command."]); return end
    EV.UI.ShowPasteText(L["Import profile"],
        L["Paste a profile string. It replaces the settings in your active profile."], L["Import"],
        function(text)
            local ok, info = EV.DB:ImportProfile(text)
            if not ok then return info end
            EV:Print(L["Imported profile"], EV:Colour(tostring(info or "")))
        end)
end

handlers.modules = function()
    EV:Print(L["Modules:"])
    for _, mod in EV:IterateModules() do
        local state = mod:IsEnabled() and "|cff55ff55on|r"
            or (mod:IsWanted() and "|cffffcc00loaded, not enabled|r" or "|cffff5555off|r")
        print(("  %s  %s"):format(mod.name, state))
    end
end

handlers.help = function()
    EV:Print("/evui, /evui caps, /evui edit, /evui lock, /evui copy, /evui profile [name], /evui modules, /evui bug, /evui export, /evui import, /evui auras [target]")
end

SLASH_EVERMOREUI1 = "/evui"
SLASH_EVERMOREUI2 = "/evermore"
SlashCmdList.EVERMOREUI = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" then
        EV:OpenOptions()
    elseif handlers[cmd] then
        handlers[cmd](rest or "")
    else
        handlers.help()
    end
end
