if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Experimental: the account-wide switch and one switch per feature.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local X = EV.Experimental
if not X then return end
-- Only worth a sidebar entry while there is something experimental installed.
X:Discover()
if #X.list == 0 then return end

EV.Options:RegisterPage{
    key = "experimental", title = L["Experimental"], group = "Experimental",
    description = L["Features still being built. Everything here is off unless you turn it on, for every character on this account. Changes apply after a reload."],
    build = function(p)
        X:Discover()
        p:Banner(L["Experimental features are unfinished. They may misbehave or clash with Blizzard's UI."])
        p:Section(L["Experimental features"])
        p:Row{ type = "toggle", text = L["Enable experimental features"],
               tooltip = L["The master switch. While it's off, no experimental feature loads, whatever its own switch says."],
               get = function() return X:IsEnabled() end,
               set = function(v) X:SetEnabled(v); EV.Options:MarkReloadNeeded() end }

        p:Section(L["Features"])
        if #X.list == 0 then
            p:Note(L["No experimental features are installed. Check they're ticked in the AddOns list."])
            return
        end
        for _, e in ipairs(X.list) do
            local tip = e.notes or ""
            if e.risk then tip = tip .. (tip ~= "" and "\n\n" or "") .. L["Risk:"] .. " " .. e.risk end
            p:Row{ type = "toggle", text = e.label, tooltip = tip,
                   disabled = function() return not X:IsEnabled() end,
                   get = function() return X:IsFeatureOn(e.addon) end,
                   set = function(v) X:SetFeature(e.addon, v); EV.Options:MarkReloadNeeded() end }
            if not e.loaded then
                p:Row{ type = "button", text = L["Try it now"], label = L["Load"], width = 100,
                       tooltip = L["Loads this feature straight away, for this session only. Nothing to reload."],
                       disabled = function() return not X:IsEnabled() or e.loaded end,
                       onClick = function()
                           X:LoadNow(e.addon)
                           if e.error then EV:Print(L["Couldn't load:"] .. " " .. e.error) end
                           EV.Options:Rebuild()
                       end }
            end
            local status
            if e.loaded then status = L["Running."]
            elseif e.error then status = L["Couldn't load:"] .. " " .. e.error
            elseif X:Wanted(e.addon) then status = L["Loads after a reload."]
            else status = L["Off."] end
            p:Note(status, 0.6)
        end
    end,
}
