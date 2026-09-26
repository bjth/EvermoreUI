if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  AuraBox.lua
--  Small engine aura containers for the party and raid frames: a row of
--  icons for one unit and one filter ("HARMFUL|RAID" is the debuffs you can
--  dispel, "HELPFUL|PLAYER" the buffs you cast). The engine draws them and
--  applies the filter in its own secure code, so they keep working in
--  restricted combat, where reading a friendly unit's debuffs from Lua does
--  not. Same approach as the Auras module's containers (Container.lua there),
--  cut down to what a group frame needs.
--
--  spec = { unit, filter, size, max, dispel, grow = "LEFT" | "RIGHT" }
--  Build(holder, nil) hides the holder's container.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local B = {}
ns.AuraBox = B

local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

local supported
function B.Supported()
    if supported ~= nil then return supported end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, test = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    supported = (ok and test ~= nil and test.AddAuraGroup ~= nil) and true or false
    if test and test.Hide then test:Hide() end
    return supported
end

local function InitButton(b, spec)
    b:SetSize(spec.size, spec.size)
    local one = EV.Pixel:One(b)
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 1)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", one, -one)
    icon:SetPoint("BOTTOMRIGHT", -one, one)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    Try(b, "SetIcon", icon)
    if spec.dispel then
        local tint = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        tint:SetAllPoints()
        tint:SetColorTexture(1, 1, 1, 1)
        local E = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        if not Try(b, "AddDispelTypeTexture", tint, { style = E and E.PreserveAsset, showWhenHarmful = true, showWhenHelpful = false }) then
            tint:Hide()
        end
    end
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(false)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    Try(b, "SetDurationCooldown", cd)
    local stacks = b:CreateFontString(nil, "OVERLAY")
    stacks:SetFont(EV.Media:Fetch("font"), math.max(math.floor(spec.size * 0.5), 8), "OUTLINE")
    stacks:SetPoint("BOTTOMRIGHT", 1, 0)
    Try(b, "SetApplicationCount", stacks, {})
    Try(b, "SetMouseClickEnabled", false)
    Try(b, "SetTooltipAnchorPoint", "ANCHOR_BOTTOMRIGHT")
end

local function Signature(spec)
    return table.concat({ spec.filter, spec.size, spec.max, tostring(spec.dispel), spec.grow or "LEFT" }, "|")
end

function B.Build(holder, spec)
    if not spec then
        if holder.box then holder.box:Hide() end
        return
    end
    local sig = Signature(spec)
    if holder.box and holder.sig == sig then
        if holder.unit ~= spec.unit then
            holder.unit = spec.unit
            if spec.unit then Try(holder.box, "SetUnit", spec.unit); Try(holder.box, "UpdateAllAuras") end
        end
        holder.box:SetShown(spec.unit ~= nil)
        return
    end
    if holder.box then holder.box:Hide(); holder.box = nil end
    if not B.Supported() then return end
    holder.sig, holder.unit = sig, spec.unit

    local c = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    local left = spec.grow ~= "RIGHT"
    local anchor = left and "BOTTOMRIGHT" or "BOTTOMLEFT"
    c:SetPoint(anchor, holder, anchor, 0, 0)
    c:SetSize(1, 1)
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    local h = left and (FD and FD.Left or -1) or (FD and FD.Right or 1)
    local v = FD and FD.Up or 1
    local gap = 2
    local line = spec.max * spec.size + (spec.max - 1) * gap
    local _ = Try(c, "SetFlowLayoutAnchorPoint", anchor) or Try(c, "SetAuraLayoutAnchorPoint", anchor)
    _ = Try(c, "SetFlowLayoutGrowthDirection", h, v) or Try(c, "SetAuraLayoutGrowthDirection", h, v)
    _ = Try(c, "SetFlowLayoutPadding", 0, 0, 0, 0) or Try(c, "SetAuraLayoutPadding", 0, 0, 0, 0)
    _ = Try(c, "SetFlowLayoutMaximumLineSize", line) or Try(c, "SetAuraLayoutRowWidth", line)
    if AnchorUtil and AnchorUtil.FlowLayoutAxis then Try(c, "SetFlowLayoutAxis", AnchorUtil.FlowLayoutAxis.Horizontal) end

    local SM, SD = AuraContainerSortMethod, AuraContainerSortDirection
    local ok = pcall(c.AddAuraGroup, c, "main", spec.filter, {
        maxFrameCount = spec.max,
        sortMethod = SM and SM.Default or 0,
        sortDirection = SD and SD.Normal or 0,
        candidateFilters = {},
        initializeFrame = function(b) InitButton(b, spec) end,
        layout = { elementWidth = spec.size, elementHeight = spec.size, elementSpacing = gap, lineSpacing = gap },
    })
    if not ok then c:Hide(); return end
    if spec.unit then Try(c, "SetUnit", spec.unit); Try(c, "UpdateAllAuras") end
    c:SetShown(spec.unit ~= nil)
    holder.box = c
end
