if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Probes.lua
--  Runtime capability checks that need the world loaded. Results land in
--  EvermoreUI.Caps and are printed by /evui caps.
--
--  secureSnippets: can we compile restricted snippets (Execute, WrapScript)?
--  Confirmed 18 Sep 2026: the Forever beta can't (loadstring_untainted is
--  nil), which rules out custom action bars and state drivers for now.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local caps = EV.Caps

-- Secure snippets are compiled by the C function loadstring_untainted, which
-- RestrictedExecution.lua captures at load. If the client doesn't provide it,
-- every Execute/WrapScript/_onstate-* fails. Checking the global directly is
-- silent: actually running a snippet reports its error to BugSack through the
-- attribute handler, where pcall can't catch it.
local function ProbeSecureSnippets()
    if type(loadstring_untainted) == "function" then return true end
    return false, "loadstring_untainted missing"
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    caps.secureSnippets, caps.secureSnippetsError = ProbeSecureSnippets()
end)

--- Rerun the probes on demand (/evui caps).
function EV:RunProbes()
    caps.secureSnippets, caps.secureSnippetsError = ProbeSecureSnippets()
end

local function YesNo(v)
    if v == nil then return "|cffaaaaaa?|r" end
    return v and "|cff55ff55yes|r" or "|cffff5555no|r"
end

function EV:PrintCaps()
    self:RunProbes()
    local c = caps
    self:Print(("v%s  client %s (%s)  interface %s  mainline %s"):format(
        self.version, tostring(c.version), tostring(c.build), tostring(c.interface), YesNo(c.isMainline)))
    print(("  C_Secrets %s   C_RestrictedActions %s   Edit Mode %s   Cooldown Viewer %s"):format(
        YesNo(c.secrets), YesNo(c.restrictedActions), YesNo(c.editMode), YesNo(c.cooldownViewer)))
    print(("  C_UnitAuras %s   C_Spell %s   C_Item %s   GetSpecialization %s   PixelUtil %s"):format(
        YesNo(c.unitAuras), YesNo(c.spellNS), YesNo(c.itemNS), YesNo(c.specAPI), YesNo(c.pixelUtil)))
    print(("  Aura containers %s"):format(YesNo(c.auraContainer)))
    local X = self.Experimental
    if X then
        local active = X:Active()
        print(("  Experimental %s%s"):format(YesNo(X:IsEnabled()),
            #active > 0 and ("  (" .. table.concat(active, ", ") .. ")") or ""))
    end
    print(("  Secure snippets %s%s"):format(
        YesNo(c.secureSnippets), c.secureSnippetsError and ("  (" .. c.secureSnippetsError .. ")") or ""))

    local db = self.DB
    local sv
    if db.previousWrite then
        sv = ("|cff55ff55loaded|r, last written %s (%d sessions)"):format(
            date("%Y-%m-%d %H:%M", db.previousWrite), db.writeCount or 0)
    elseif c.svLoaded then
        sv = "|cffffcc00table loaded but no write stamp yet|r"
    else
        sv = "|cffaaaaaanone yet|r (first session)"
    end
    print("  SavedVariables " .. sv)
end
