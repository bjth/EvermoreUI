if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Bars.lua
--  Adoption, layout, visibility, fading and the Edit Mode lockout.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local issecret = issecretvalue or function() return false end

-- Our own reason bit for Blizzard's "showgrid" attribute (theirs are small
-- powers of two), so "show empty slots" survives their grid updates.
local GRID_BIT = 4096

local frames = {}          -- key -> our bar frame
local adopted = false
ns.frames = frames

-- Where unused buttons and Blizzard's emptied bar frames go.
local hidden = CreateFrame("Frame", "EvermoreUIActionBarsHidden", UIParent)
hidden:Hide()
ns.hidden = hidden

local DEFAULT_POS = {
    main   = { "BOTTOM", "BOTTOM", 0, 40 },
    bar2   = { "BOTTOM", "BOTTOM", 0, 84 },
    bar3   = { "BOTTOM", "BOTTOM", 0, 128 },
    bar4   = { "RIGHT", "RIGHT", -6, 0 },
    bar5   = { "RIGHT", "RIGHT", -50, 0 },
    bar6   = { "CENTER", "CENTER", 0, -120 },
    bar7   = { "CENTER", "CENTER", 0, -164 },
    bar8   = { "CENTER", "CENTER", 0, -208 },
    stance = { "BOTTOM", "BOTTOM", -220, 172 },
    pet    = { "BOTTOM", "BOTTOM", 220, 172 },
}

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------
local function Shell(def) return _G[def.shell] end

local function Buttons(def)
    local shell = Shell(def)
    local list = {}
    if shell and type(shell.actionButtons) == "table" and #shell.actionButtons > 0 then
        for i, b in ipairs(shell.actionButtons) do list[i] = b end
    else
        for i = 1, def.count do list[i] = _G[def.prefix .. i] end
    end
    return list
end
ns.Buttons = Buttons

local function MoverKey(key) return "AB_" .. key end

--------------------------------------------------------------------------------
--  Stance bar: it exists only while you have forms
--
--  Blizzard's StanceBar turns its grid on at load
--  (StanceBarMixin:OnLoad, SetShowGrid(true, ..._REASON_CVAR)), so all ten
--  buttons are always "shown", empty or not. That is harmless on Blizzard's
--  bar because the BAR hides itself when you have no forms:
--  StanceBarMixin:ShouldShow is numForms > 0, re-run by ActionBarController
--  on UPDATE_SHAPESHIFT_FORM(S) and UPDATE_SHAPESHIFT_USABLE. We moved the
--  buttons out of that bar, so its hiding no longer reaches them, and a mage
--  got ten empty wells.
--
--  So our stance bar follows the same count: hidden outright with no forms,
--  and laid out to exactly as many buttons as you have forms (the Buttons
--  setting becomes a cap). A druid learning a form grows the bar; nothing
--  else about it changes.
--------------------------------------------------------------------------------
local function NumForms(def)
    local ok, n = pcall(GetNumShapeshiftForms)
    if ok and type(n) == "number" and not issecret(n) then return n end
    -- Blizzard's own count, kept current by the same events.
    local shell = def and Shell(def)
    local c = shell and shell.numForms
    return (type(c) == "number" and not issecret(c)) and c or 0
end
ns.NumForms = NumForms

--- How many buttons a bar lays out right now.
local function ButtonCount(def, cfg)
    local n = max(1, min(def.count, cfg.buttons))
    if def.stance then n = min(n, NumForms(def)) end
    return n
end
ns.ButtonCount = ButtonCount

--- Blizzard's own "is this bar switched on" (its override reads the
--- setting, not the literal shown state).
local function BlizzardShown(shell)
    if not shell then return false end
    local ok, shown = pcall(shell.IsShown, shell)
    return ok and shown and true or false
end

--------------------------------------------------------------------------------
--  Genesis: the first time, copy what Blizzard's layout had.
--------------------------------------------------------------------------------
local function Genesis()
    if M.db.genesis then return end
    local ux, uy = UIParent:GetCenter()
    for _, def in ipairs(ns.BARS) do
        local cfg = ns.Bar(def.key)
        local shell = Shell(def)
        if shell then
            if not def.small then cfg.enabled = BlizzardShown(shell) end
            local rows = tonumber(shell.numRows) or 1
            local shown = tonumber(shell.numButtonsShowable) or def.count
            -- The stance bar's showable count is just the forms you have on
            -- the day, so copying it capped the bar there for good. Its
            -- Buttons setting is a cap now; start it at the full ten.
            if def.stance then shown = def.count end
            cfg.buttons = max(1, min(def.count, shown))
            if shell.isHorizontal == false then
                cfg.perRow = rows
            else
                cfg.perRow = max(1, ceil(cfg.buttons / max(rows, 1)))
            end
            local cx, cy = shell:GetCenter()
            if cfg.enabled and cx and ux and not issecret(cx) then
                local k = shell:GetEffectiveScale() / UIParent:GetEffectiveScale()
                EV.DB:GetCore().movers[MoverKey(def.key)] = { "CENTER", "CENTER", cx * k - ux, cy * k - uy }
            end
        end
    end
    M.db.genesis = true
end

--------------------------------------------------------------------------------
--  Our bar frames
--------------------------------------------------------------------------------
local function VisibilityCondition(def, cfg)
    if not cfg.enabled then return "hide" end
    if def.stance and NumForms(def) == 0 then return "hide" end
    -- Our bars step aside for pet battles and skinned vehicles, like Blizzard's.
    local base = "[petbattle][vehicleui] hide; "
    if def.pet then base = base .. "[nopet] hide; " end
    local v = cfg.visibility
    if v == "hidden" then return "hide" end
    if v == "combat" then return base .. "[combat] show; hide" end
    if v == "nocombat" then return base .. "[combat] hide; show" end
    if v == "custom" and type(cfg.custom) == "string" and cfg.custom:find("%S") then
        return base .. cfg.custom
    end
    return base .. "show"
end
ns.VisibilityCondition = VisibilityCondition

local function CreateBar(def)
    local f = CreateFrame("Frame", "EvermoreUIActionBar_" .. def.key, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(100, 40)
    f.def = def
    if f.SetRolesets then pcall(f.SetRolesets, f, "actionBars") end -- follow Blizzard's UI modes (spectating)
    frames[def.key] = f
    EV.Movers:Register(f, MoverKey(def.key), def.label, DEFAULT_POS[def.key], {
        group = L["Action Bars"], page = "actionbars",
        -- A class with no forms has no stance bar to place.
        isDisabled = function()
            return not ns.Bar(def.key).enabled or (def.stance and NumForms(def) == 0)
        end,
    })
    return f
end

local function FlyoutDirection(f, cfg)
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return "UP" end
    if cfg.perRow == 1 and cfg.buttons > 1 then
        return cx > ux and "LEFT" or "RIGHT"
    end
    return cy > uy and "DOWN" or "UP"
end

--- Lay one bar out (out of combat only).
local function Layout(def)
    local f = frames[def.key]
    if not f then return end
    local cfg = ns.Bar(def.key)
    local n = ButtonCount(def, cfg)
    if def.stance then f.evForms = n end
    -- Zero forms: every button goes under the hidden parent below and the
    -- state driver hides the frame. Size it as one slot so the mover and
    -- flyout maths still have something to measure.
    local laidOut = n
    n = max(n, 1)
    local per = max(1, min(n, cfg.perRow))
    local size, gap = cfg.size, cfg.spacing
    local cols = per
    local rows = ceil(n / per)
    f:SetScale(ns.ValidScale(cfg.scale))
    f:SetSize(cols * size + (cols - 1) * gap, rows * size + (rows - 1) * gap)
    local dir = FlyoutDirection(f, cfg)
    -- Growth: which corner the first button sits in, and which way the rest
    -- run from it.
    local left, up = cfg.growH == "LEFT", cfg.growV == "UP"
    local corner = (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT")
    local sx, sy = left and -1 or 1, up and 1 or -1
    for i, b in ipairs(Buttons(def)) do
        b.evBar, b.evIndex = def.key, i
        if i <= laidOut then
            b:SetParent(f)
            b:ClearAllPoints()
            local r, c = floor((i - 1) / per), (i - 1) % per
            b:SetPoint(corner, f, corner, sx * c * (size + gap), sy * r * (size + gap))
            b:SetSize(size, size)
            b:SetAttribute("flyoutDirection", dir)
            -- Empty slots: our own bit in Blizzard's showgrid attribute.
            local grid = b:GetAttribute("showgrid") or 0
            if cfg.showEmpty then
                b:SetAttribute("showgrid", bit.bor(grid, GRID_BIT))
                b:Show()
            elseif bit.band(grid, GRID_BIT) ~= 0 then
                b:SetAttribute("showgrid", bit.band(grid, bit.bnot(GRID_BIT)))
                if not def.small and b.HasAction and not b:HasAction() then b:Hide() end
            end
            ns.SkinButton(b)
        else
            b:SetParent(hidden)
        end
    end
    RegisterStateDriver(f, "visibility", VisibilityCondition(def, cfg))
    if ns.ApplyPaging then ns.ApplyPaging(def) end
    if ns.ApplyActions then ns.ApplyActions(def) end
    EV.Movers:Apply(MoverKey(def.key))
end
ns.Layout = Layout

function ns.ValidScale(v)
    if type(v) == "number" and v >= 0.5 and v <= 2 then return v end
    return 1
end

--- Blizzard re-decides which buttons show when its grid changes (dragging
--- a spell, for instance). Its choice uses its own bar settings, which no
--- longer apply; put ours back.
local function Reassert(def)
    if InCombatLockdown() or def.small then return end
    local cfg = ns.Bar(def.key)
    local n = min(def.count, cfg.buttons)
    for i, b in ipairs(Buttons(def)) do
        if i <= n and b.HasAction then
            local grid = b:GetAttribute("showgrid") or 0
            if b:HasAction() or grid ~= 0 or cfg.showEmpty then b:Show() end
        end
    end
end

--------------------------------------------------------------------------------
--  Fading
--------------------------------------------------------------------------------
local fader = CreateFrame("Frame")
fader:Hide()   -- shown by OnEnable, so a switched-off module costs nothing
local current = {}   -- key -> alpha now
local function Hot(f)
    if f:IsMouseOver(2, -2, -2, 2) then return true end
    local fly = SpellFlyout
    if fly and fly:IsShown() and fly.GetParent and fly:GetParent() and fly:GetParent():GetParent() == f then return true end
    if GetCursorInfo() then return true end -- dragging something to a slot
    return false
end
local acc = 0
fader:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.05 then return end
    local step = acc
    acc = 0
    local combat = InCombatLockdown() or UnitAffectingCombat("player")
    -- Linked bars: the mouse over any bar in a group wakes the whole group.
    local groupHot = {}
    for key, f in pairs(frames) do
        local g = ns.Bar(key).fadeGroup
        if type(g) == "number" and g > 0 and f:IsShown() and Hot(f) then groupHot[g] = true end
    end
    for key, f in pairs(frames) do
        local cfg = ns.Bar(key)
        local full = (type(cfg.alpha) == "number" and cfg.alpha >= 0 and cfg.alpha <= 1) and cfg.alpha or 1
        local target = full
        local hot = Hot(f) or (cfg.fadeGroup and groupHot[cfg.fadeGroup])
        if cfg.fade and f:IsShown() and not (combat and not cfg.fadeInCombat) and not hot then
            target = min(cfg.fadeAlpha, full)
        end
        local a = current[key] or 1
        if a ~= target then
            local speed = step * 6
            if a < target then a = min(target, a + speed) else a = max(target, a - speed) end
            current[key] = a
            f:SetAlpha(a)
        end
    end
end)

--------------------------------------------------------------------------------
--  Blizzard's own bars: emptied, parked, and kept out of Edit Mode
--------------------------------------------------------------------------------
local function Park(def)
    local shell = Shell(def)
    if shell and shell:GetParent() ~= hidden then shell:SetParent(hidden) end
end

-- The vehicle exit button lives inside Blizzard's main bar; it comes with us.
local function AdoptVehicleButton()
    local b = MainMenuBarVehicleLeaveButton
    if not b or ns.vehicleButton then return end
    b:SetParent(UIParent)
    ns.vehicleButton = b
    EV.Movers:Register(b, "AB_vehicle", L["Vehicle Exit"], { "BOTTOM", "BOTTOM", 260, 40 }, {
        group = L["Action Bars"], page = "actionbars",
    })
    -- Edit Mode re-anchors it as one of its systems; put ours back after.
    if type(b.ApplySystemAnchor) == "function" then
        hooksecurefunc(b, "ApplySystemAnchor", function()
            ns.Safe("vehicle", function() EV.Movers:Apply("AB_vehicle") end)
        end)
    end
end

local noted = false
local function EditModeNote()
    if noted or not M.db.editModeNote then return end
    noted = true
    EV:Print(L["Action bars are handled by EvermoreUI: move them with /evui edit."])
end

--------------------------------------------------------------------------------
--  Adopt everything (once, out of combat)
--------------------------------------------------------------------------------
function ns.Adopt()
    if adopted then return end
    adopted = true
    Genesis()
    for _, def in ipairs(ns.BARS) do
        if Shell(def) then
            CreateBar(def)
            Layout(def)
            Park(def)
            local shell = Shell(def)
            if type(shell.UpdateShownButtons) == "function" then
                hooksecurefunc(shell, "UpdateShownButtons", function() Reassert(def) end)
            end
        end
    end
    AdoptVehicleButton()
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnShow", EditModeNote)
        -- Leaving Edit Mode can re-set button art; dress them again.
        EditModeManagerFrame:HookScript("OnHide", function() ns.Safe("restyle", ns.RestyleButtons) end)
    end
end

function M:Refresh()
    if not adopted then return end
    ns.Safe("layout", function()
        for _, def in ipairs(ns.BARS) do
            if frames[def.key] then Layout(def) end
        end
    end)
    ns.RestyleButtons()
    -- The options' copy of the bar follows its settings straight away, even
    -- when the real bar has to wait for combat to end.
    if ns.Editor then ns.Editor.RelayoutAll() end
end

--- Stance bar: re-lay it when the number of forms changes. The same events
--- Blizzard's ActionBarController uses to re-run StanceBar:Update; they also
--- fire on every shift, so only a change in the count does any work.
local function FormsChanged()
    local def = ns.BY_KEY.stance
    local f = def and frames.stance
    if not f then return end
    local n = ButtonCount(def, ns.Bar("stance"))
    if f.evForms == n then return end
    ns.Safe("layout:stance", function() Layout(def) end)
end

--- One time: undo the cap genesis used to copy onto the stance bar (see
--- Genesis). A single horizontal row stays a row at the new width.
local function MigrateStanceCap()
    if M.db.stanceCapFixed then return end
    local def, cfg = ns.BY_KEY.stance, ns.Bar("stance")
    if def and cfg and M.db.genesis then
        if cfg.perRow >= cfg.buttons then cfg.perRow = def.count end
        cfg.buttons = def.count
    end
    M.db.stanceCapFixed = true
end

function M:OnEnable()
    fader:Show()
    if ns.EnableCounts then ns.EnableCounts() end
    MigrateStanceCap()
    ns.Safe("adopt", ns.Adopt)
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", FormsChanged)
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", FormsChanged)
    self:RegisterMessage("EV_PIXEL_CHANGED", function() self:Refresh() end)
    -- Positions settle after login; lay out once more then.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Refresh() end)
end

function M:OnProfileChanged() self:Refresh() end
