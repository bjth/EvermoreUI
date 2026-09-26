if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Experimental.lua
--  Experimental features ship as their own load-on-demand addons, marked in
--  their TOC:
--
--    ## LoadOnDemand: 1
--    ## X-Evermore-Experimental: 1
--    ## X-Evermore-Label: Action Bars
--    ## X-Evermore-Risk: One line on what could go wrong.
--
--  Nothing of theirs loads unless experimental features are switched on
--  (account-wide) AND that feature is switched on (also account-wide). Both
--  are checked once, as EvermoreUI loads, so changes take effect after a
--  reload. A feature that's off costs nothing and touches nothing.
--
--  Both switches are plain booleans; unset means off.
--
--  Promoting a feature: drop the X-Evermore-Experimental line and the
--  LoadOnDemand line from its TOC. Its settings carry on as they were.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local X = {}
EV.Experimental = X

X.list = {}     -- discovered features, in addon-list order
X.byAddon = {}

function X:Settings()
    local g = EV.DB:GetGlobal()
    if type(g.experimental) ~= "table" then g.experimental = {} end
    local s = g.experimental
    if type(s.modules) ~= "table" then s.modules = {} end
    return s
end

function X:IsEnabled() return self:Settings().enabled == true end

function X:SetEnabled(on) self:Settings().enabled = on and true or false end

function X:IsFeatureOn(addon) return self:Settings().modules[addon] == true end

function X:SetFeature(addon, on) self:Settings().modules[addon] = on and true or false end
--- Will this feature be loaded (both switches on)?
function X:Wanted(addon) return self:IsEnabled() and self:IsFeatureOn(addon) end

local function Meta(name, key)
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, name, key)
    return ok and v or nil
end

function X:Discover()
    wipe(self.list); wipe(self.byAddon)
    if not (C_AddOns and C_AddOns.GetNumAddOns) then return self.list end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, notes = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and name:find("^EvermoreUI_") and Meta(name, "X-Evermore-Experimental") then
            local label = Meta(name, "X-Evermore-Label")
            if not label and type(title) == "string" then label = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
            local entry = {
                addon = name,
                label = label or name,
                notes = notes,
                risk = Meta(name, "X-Evermore-Risk"),
                loaded = C_AddOns.IsAddOnLoaded(name) and true or false,
            }
            self.list[#self.list + 1] = entry
            self.byAddon[name] = entry
        end
    end
    return self.list
end

--- Load every feature that's switched on. Called once, as EvermoreUI loads.
function X:LoadWanted()
    self:Discover()
    for _, e in ipairs(self.list) do
        if self:Wanted(e.addon) and not e.loaded then
            local ok, reason = C_AddOns.LoadAddOn(e.addon)
            e.loaded = ok and true or false
            e.error = (not ok) and tostring(reason) or nil
        end
    end
end

--- Load one feature straight away, for this session (no reload). Used by
--- the options page's "Try it now".
function X:LoadNow(addon)
    local e = self.byAddon[addon]
    if not e or e.loaded then return e and e.loaded end
    local ok, reason = C_AddOns.LoadAddOn(addon)
    e.loaded = ok and true or false
    e.error = (not ok) and tostring(reason) or nil
    return e.loaded, e.error
end

--- Features currently running, for /evui caps.
function X:Active()
    local out = {}
    for _, e in ipairs(self.list) do if e.loaded then out[#out + 1] = e.label end end
    return out
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= EV.name or not EV.dbReady then return end
    self:UnregisterAllEvents()
    local ok, err = pcall(X.LoadWanted, X)
    if not ok then geterrorhandler()("EvermoreUI experimental loader: " .. tostring(err)) end
end)
