if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Modules: switch whole modules on or off for this profile.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

EV.Options:RegisterPage{
    key = "modules", title = L["Modules"], group = "General",
    description = L["Switch whole modules on or off. Changes apply after a reload."],
    build = function(p)
        p:Section(L["Modules"])
        local any = false
        for _, mod in EV:IterateModules() do
            if not mod.internal and not mod.experimental then
                any = true
                local name = mod.name
                p:Row{ type = "toggle", text = mod.title or name, tooltip = mod.description,
                       get = function() return not EV.DB:GetCore().disabled[name] end,
                       set = function(on)
                           EV.DB:GetCore().disabled[name] = (not on) or nil
                           EV.Options:MarkReloadNeeded()
                       end }
            end
        end
        if not any then p:Note(L["No modules loaded. Check they're ticked in the AddOns list."]) end
    end,
}
