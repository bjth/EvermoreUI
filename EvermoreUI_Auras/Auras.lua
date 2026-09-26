if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Auras.lua
--  Movable player buffs and debuffs, drawn by the engine's aura containers so
--  they keep working in combat. Tracking particular auras in your HUD is the
--  Cooldowns module's job, on top of the game's Cooldown Manager.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local L = EV.L
local C = ns.Container

local DEFAULTS = {
    buffs = {
        enabled = true, hideBlizzard = true, size = 32, spacing = 4, perRow = 12, max = 36,
        growX = "LEFT", growY = "DOWN", showSwipe = true, showTimer = true, timerSize = 11,
        cancel = true, tooltip = true, sort = "default",
    },
    debuffs = {
        enabled = true, hideBlizzard = true, size = 40, spacing = 4, perRow = 8, max = 16,
        growX = "LEFT", growY = "DOWN", showSwipe = true, showTimer = true, timerSize = 12,
        tooltip = true, sort = "default",
    },
}

local M = EV:NewModule("Auras", DEFAULTS)
ns.module = M
M.title = "Buffs & Debuffs"
M.description = "Movable buffs and debuffs."

local holders = {}      -- key -> holder frame
local pending = false   -- rebuild waiting for combat to end

--------------------------------------------------------------------------------
--  Holders (what edit mode moves)
--------------------------------------------------------------------------------
local function Holder(key, label, default, group)
    local h = holders[key]
    if h then return h end
    h = CreateFrame("Frame", "EvermoreUI_" .. key, UIParent)
    h:SetSize(40, 40)
    holders[key] = h
    EV.Movers:Register(h, key, label, default, {
        group = L["Buffs & Debuffs"], page = "auras", tab = group,
        isDisabled = function() return not h:IsShown() end,
    })
    return h
end

local function SizeHolder(h, cfg)
    local w, hh = C.BoxSize(cfg)
    EV.Pixel:SetSize(h, w, hh)
end

--------------------------------------------------------------------------------
--  Building
--------------------------------------------------------------------------------
function M:BuildBuffs()
    local cfg = self.db.buffs
    local h = Holder("AURA_buffs", L["Buffs"], { "TOPRIGHT", "TOPRIGHT", -236, -16 }, L["Buffs"])
    if not cfg.enabled then h:Hide(); if h.container then h.container:Hide() end; return end
    h:Show()
    SizeHolder(h, cfg)
    C.Build(h, cfg, {
        unit = "player", filter = "HELPFUL",
        cancel = cfg.cancel, tooltip = cfg.tooltip, sort = cfg.sort,
    })
end

function M:BuildDebuffs()
    local cfg = self.db.debuffs
    local h = Holder("AURA_debuffs", L["Debuffs"], { "TOPRIGHT", "TOPRIGHT", -236, -140 }, L["Debuffs"])
    if not cfg.enabled then h:Hide(); if h.container then h.container:Hide() end; return end
    h:Show()
    SizeHolder(h, cfg)
    C.Build(h, cfg, {
        unit = "player", filter = "HARMFUL",
        dispel = true, tooltip = cfg.tooltip, sort = cfg.sort,
    })
end

--- Rebuild everything (containers can't change size or filter in place).
function M:Rebuild()
    if not self:IsEnabled() then return end
    if InCombatLockdown() then pending = true; return end
    if not C.Supported() then return end
    self:BuildBuffs()
    self:BuildDebuffs()
    self:ApplyBlizzard()
    EV.Movers:ApplyAll()
end
M.Refresh = M.Rebuild

--------------------------------------------------------------------------------
--  Blizzard's buff frames
--------------------------------------------------------------------------------
local hooked = {}
local function Suppress(frame, want)
    if not frame then return end
    if not hooked[frame] then
        hooked[frame] = true
        hooksecurefunc(frame, "Show", function(f) if f.evSuppressed then f:Hide() end end)
    end
    frame.evSuppressed = want
    if want then frame:Hide() end
end

function M:ApplyBlizzard()
    local b, d = self.db.buffs, self.db.debuffs
    Suppress(_G.BuffFrame, b.enabled and b.hideBlizzard)
    Suppress(_G.DebuffFrame, d.enabled and d.hideBlizzard)
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
    if not C.Supported() then
        EV:Print(L["Auras: this client has no Blizzard aura containers, so EvermoreUI is leaving buffs to Blizzard."])
        return
    end
    -- Trackers moved to the Cooldowns module; drop what they saved.
    self.db.classes = nil
    if self.db.buffs then self.db.buffs.excludeTracked = nil end

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pending then pending = false; self:Rebuild() end
    end)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Rebuild() end)
    self:Rebuild()
end

function M:OnProfileChanged()
    if not C.Supported() then return end
    self.db.classes = nil
    self:Rebuild()
end

--------------------------------------------------------------------------------
--  /evui auras [target|focus|pet]
--  Lists the unit's buffs and debuffs with spell IDs.
--------------------------------------------------------------------------------
EV:RegisterSlash("auras", function(rest)
    local unit = strtrim(rest or ""):lower()
    if unit == "" then unit = "player" end
    if not UnitExists(unit) then EV:Print(L["No such unit:"], unit); return end
    for _, harmful in ipairs({ false, true }) do
        local list, hidden = ns.CurrentAuras(unit, harmful)
        EV:Print(("%s on %s: %d"):format(harmful and L["Debuffs"] or L["Buffs"], unit, #list))
        for _, a in ipairs(list) do
            local icon = a.icon and ("|T" .. a.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ""
            local who = a.mine == true and L["yours"] or a.mine == false and L["not yours"] or "?"
            if a.duration then who = who .. ", " .. (a.duration > 0 and (math.floor(a.duration + 0.5) .. "s") or L["permanent"]) end
            EV:Print(("   %s%s  |cffffd100%d|r  |cff808080%s|r"):format(icon, a.name, a.id, who))
        end
        if hidden > 0 then
            EV:Print(("   |cff808080" .. L["%d more the game is hiding right now (combat in an instance). Try again out of combat."] .. "|r"):format(hidden))
        end
    end
end)
