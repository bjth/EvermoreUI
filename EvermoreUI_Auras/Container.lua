if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Container.lua
--  Thin wrapper over Blizzard's AuraContainer engine (12.1+).
--
--  The engine does the filtering, sorting, layout, timers and stacks in C,
--  so secret aura values never reach our Lua and everything keeps working in
--  combat. We only style each button once, in initializeFrame, and hand the
--  engine our regions to drive (SetIcon, SetDurationCooldown, ...).
--
--  Rules learned the hard way (and from how others use it):
--   * set the unit LAST, after the groups exist, or UNIT_AURA never registers
--   * button size is ours to set, once, in initializeFrame; after that the
--     engine locks the button while auras are secret, so any change of size
--     or filter means building a fresh container (out of combat)
--   * never anchor our frames to engine buttons; anchor to our own holder
--   * an empty includeSpellIDs list means "no filter": never build a
--     container meant to show a few spells with an empty list
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local C = {}
ns.Container = C

--------------------------------------------------------------------------------
--  Support probe
--------------------------------------------------------------------------------
function C.Supported()
    if C.supported ~= nil then return C.supported end
    local ok = C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
    if not ok then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        ok = C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
    end
    local test
    if ok then ok, test = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate") end
    C.supported = (ok and test ~= nil and test.AddAuraGroup ~= nil) and true or false
    if test and test.Hide then test:Hide() end
    EV.Caps.auraContainer = C.supported
    return C.supported
end

--------------------------------------------------------------------------------
--  Layout helpers
--------------------------------------------------------------------------------
--- Corner the icons flow from, e.g. grow left + down => TOPRIGHT.
function C.AnchorPoint(cfg)
    return (cfg.growY == "UP" and "BOTTOM" or "TOP") .. (cfg.growX == "LEFT" and "RIGHT" or "LEFT")
end

--- Size of the box the icons can fill (our holder; the engine's own size is
--- secret while auras are, so we never read it).
function C.BoxSize(cfg)
    local cols = math.max(1, math.min(cfg.perRow, cfg.max))
    local rows = math.max(1, math.ceil(cfg.max / cfg.perRow))
    return cols * cfg.size + (cols - 1) * cfg.spacing, rows * cfg.size + (rows - 1) * cfg.spacing
end

local timerFonts = {}
local function TimerFont(size)
    local name = "EvermoreUIAuraTimer" .. size
    if not timerFonts[name] then
        local f = CreateFont(name)
        f:SetFont(EV.Media:Fetch("font"), size, "OUTLINE")
        timerFonts[name] = f
    end
    return name
end

local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

--------------------------------------------------------------------------------
--  Button styling (runs once per engine button)
--------------------------------------------------------------------------------
local function InitButton(b, cfg, spec)
    local size = cfg.size
    b:SetSize(size, size)
    local one = EV.Pixel:One(b)

    -- A sunk backing doubles as a 1px border around the icon.
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(EV.Theme.RGBA("surfaceSunk", 1))

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", one, -one)
    icon:SetPoint("BOTTOMRIGHT", -one, one)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Try(b, "SetIcon", icon)

    -- Debuff border tinted by dispel type (the engine colours it).
    if spec.dispel then
        local tint = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        tint:SetAllPoints()
        tint:SetColorTexture(1, 1, 1, 1)
        local E = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        if not Try(b, "AddDispelTypeTexture", tint, { style = E and E.PreserveAsset, showWhenHarmful = true, showWhenHelpful = false }) then
            local EB = Enum and Enum.CustomAuraButtonBorderStyle
            if not Try(b, "SetAuraBorder", tint, EB and EB.Color) then tint:Hide() end
        end
    end

    if cfg.showSwipe or cfg.showTimer then
        local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:SetDrawEdge(false)
        cd:SetReverse(true)
        cd:SetDrawSwipe(cfg.showSwipe and true or false)
        cd:SetHideCountdownNumbers(not cfg.showTimer)
        if cfg.showTimer then Try(cd, "SetCountdownFont", TimerFont(cfg.timerSize)) end
        Try(b, "SetDurationCooldown", cd)
    end

    -- Stack count, bottom right, above the swipe.
    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(b:GetFrameLevel() + 5)
    local stacks = overlay:CreateFontString(nil, "OVERLAY")
    stacks:SetFont(EV.Media:Fetch("font"), math.max(math.floor(size * 0.36), 9), "OUTLINE")
    stacks:SetPoint("BOTTOMRIGHT", -1, 2)
    stacks:SetJustifyH("RIGHT")
    Try(b, "SetApplicationCount", stacks, {})

    if spec.cancel then
        Try(b, "SetCancelAuraButtons", "RightButtonUp")
    else
        Try(b, "SetMouseClickEnabled", false)
    end
    if spec.tooltip then
        Try(b, "SetTooltipAnchorPoint", "ANCHOR_BOTTOMLEFT")
    else
        Try(b, "SetMouseMotionEnabled", false)
    end
end

--------------------------------------------------------------------------------
--  Build
--  spec = { unit, filter, include = {[id]=true}, exclude = {...},
--           cancel, tooltip, dispel, sort = "time" | "default", maxDuration }
--------------------------------------------------------------------------------
local SIG_FIELDS = { "size", "spacing", "perRow", "max", "growX", "growY",
                     "showSwipe", "showTimer", "timerSize" }

local function IdList(map)
    if not map then return "" end
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = tostring(id) end
    table.sort(ids)
    return table.concat(ids, ",")
end

--- Everything that forces a new container, as one string.
local function Signature(cfg, spec)
    local parts = {}
    for _, f in ipairs(SIG_FIELDS) do parts[#parts + 1] = tostring(cfg[f]) end
    for _, f in ipairs({ "unit", "filter", "cancel", "tooltip", "dispel", "sort", "maxDuration" }) do
        parts[#parts + 1] = tostring(spec[f])
    end
    parts[#parts + 1] = IdList(spec.include)
    parts[#parts + 1] = IdList(spec.exclude)
    return table.concat(parts, "|")
end

function C.Build(holder, cfg, spec)
    -- Engine containers pre-create their buttons and can't be destroyed, so
    -- only make a new one when something that matters actually changed.
    local sig = Signature(cfg, spec)
    if holder.container and holder.sig == sig then
        holder.container:Show()
        return true
    end
    holder.sig = sig
    if holder.container then
        holder.container:Hide()
        holder.container = nil
    end
    if not C.Supported() then return false end

    local c = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    local anchor = C.AnchorPoint(cfg)
    c:SetPoint(anchor, holder, anchor, 0, 0)
    c:SetSize(1, 1)

    local FD = AnchorUtil and AnchorUtil.FlowDirection
    local h = cfg.growX == "LEFT" and (FD and FD.Left or -1) or (FD and FD.Right or 1)
    local v = cfg.growY == "UP" and (FD and FD.Up or 1) or (FD and FD.Down or -1)
    local line = cfg.perRow * cfg.size + (cfg.perRow - 1) * cfg.spacing
    local _ = Try(c, "SetFlowLayoutAnchorPoint", anchor) or Try(c, "SetAuraLayoutAnchorPoint", anchor)
    _ = Try(c, "SetFlowLayoutGrowthDirection", h, v) or Try(c, "SetAuraLayoutGrowthDirection", h, v)
    _ = Try(c, "SetFlowLayoutPadding", 0, 0, 0, 0) or Try(c, "SetAuraLayoutPadding", 0, 0, 0, 0)
    _ = Try(c, "SetFlowLayoutMaximumLineSize", line) or Try(c, "SetAuraLayoutRowWidth", line)
    if AnchorUtil and AnchorUtil.FlowLayoutAxis then Try(c, "SetFlowLayoutAxis", AnchorUtil.FlowLayoutAxis.Horizontal) end

    local cand = {}
    if spec.include then cand.includeSpellIDs = spec.include end
    if spec.exclude and next(spec.exclude) then cand.excludeSpellIDs = spec.exclude end
    -- Evaluated by Blizzard's secure code like the filter string, so it holds
    -- in restricted combat (DoesAuraPassCandidateFilters). Hides permanent
    -- auras as a side effect.
    if spec.maxDuration then cand.maxDuration = spec.maxDuration end

    local SM, SD = AuraContainerSortMethod, AuraContainerSortDirection
    local sortMethod = SM and (spec.sort == "time" and SM.Expiration or SM.Default) or 0
    local ok, err = pcall(c.AddAuraGroup, c, "main", spec.filter, {
        maxFrameCount = cfg.max,
        sortMethod = sortMethod,
        sortDirection = SD and SD.Normal or 0,
        candidateFilters = cand,
        initializeFrame = function(b) InitButton(b, cfg, spec) end,
        layout = {
            elementWidth = cfg.size, elementHeight = cfg.size,
            elementSpacing = cfg.spacing, lineSpacing = cfg.spacing,
        },
    })
    if not ok then
        geterrorhandler()("EvermoreUI Auras: AddAuraGroup failed: " .. tostring(err))
        c:Hide()
        return false
    end

    -- Unit last.
    Try(c, "SetUnit", spec.unit)
    Try(c, "UpdateAllAuras")
    holder.container = c
    return true
end
