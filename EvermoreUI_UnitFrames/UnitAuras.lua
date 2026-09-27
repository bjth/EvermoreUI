if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UnitAuras.lua
--  Buffs and debuffs on the single unit frames.
--
--  The Cooldown Manager shows the spells you chose to track; this is the
--  rest of what's on a unit: other people's debuffs on your target (who has
--  Sunder or a curse up, whether it's already sheeped), buffs to Purge or
--  Tranquilize, and a friend's buffs before you rebuff them. Blizzard showed
--  these on TargetFrame, which we retire, so without this they're gone.
--
--  Drawn by the engine's aura containers (Core/AuraContainer.lua), so the
--  filter runs in the game's secure code and keeps working in restricted
--  combat, where reading a unit's auras from Lua does not. The cost of that
--  is that we never learn how many icons there are, so rows cannot push
--  other things along: when buffs and debuffs share a side, the second
--  block starts past the space the first could fill at most.
--
--  cfg.buffs / cfg.debuffs = {
--      enabled, size, spacing, perRow, max,
--      side = "TOP" | "BOTTOM" | "LEFT" | "RIGHT",  -- which side of the frame
--      align = "START" | "END",   -- start at the left (or top) end, or the right
--      x, y,                      -- nudge, pixels
--      onlyMine, showTimer, timerSize, showSwipe, sort = "default" | "time",
--  }
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local UA = {}
ns.UnitAuras = UA

-- Units the game sends UNIT_AURA for; target of target isn't one.
local LIVE_UNITS = { player = true, target = true, focus = true, pet = true }

local max = math.max

local function Holder(f, name)
    local h = CreateFrame("Frame", nil, f)
    h:SetFrameLevel(f:GetFrameLevel() + 6)
    h:SetSize(1, 1)
    h.kind = name
    return h
end

function UA.Build(f)
    if f.auraHolders then return end
    f.auraHolders = { debuffs = Holder(f, "debuffs"), buffs = Holder(f, "buffs") }
end

--- The container settings for one block: the saved settings plus the
--- growth the side and alignment imply.
local function Shape(a)
    local side, align = a.side or "TOP", a.align or "START"
    local growX, growY
    if side == "LEFT" then growX, growY = "LEFT", "DOWN"
    elseif side == "RIGHT" then growX, growY = "RIGHT", "DOWN"
    else
        growX = (align == "END") and "LEFT" or "RIGHT"
        growY = (side == "BOTTOM") and "DOWN" or "UP"
    end
    return {
        size = max(a.size or 24, 8), spacing = a.spacing or 2,
        perRow = max(a.perRow or 8, 1), max = max(a.max or 16, 1),
        growX = growX, growY = growY,
        showSwipe = a.showSwipe ~= false, showTimer = a.showTimer ~= false,
        timerSize = a.timerSize or 10,
    }
end

--- How far below the frame's bottom edge something hung under it starts,
--- in UI units: past an attached cast bar, which owns that space whether or
--- not it's casting right now.
function UA.BottomClearance(f, cfg)
    local cc = cfg.castbar
    if cc and cc.enabled and (not cc.detached or f.isPreview) and ns.CastBar.LIVE[f.key] then
        return EV.Pixel:One(f) * (cc.gap or 4) + max(cc.height or 18, 4)
    end
    return 0
end

--- How much of one side (TOP or BOTTOM) this frame's buffs and debuffs
--- claim, in UI units, so other things hung on that side (combo points,
--- totems) start past them. Their full possible height, since the real
--- count isn't readable in combat.
function UA.Claimed(f, cfg, side)
    local total = 0
    local C = EV.AuraContainer
    if not (C and LIVE_UNITS[f.key]) then return 0 end
    for _, kind in ipairs({ "debuffs", "buffs" }) do
        local a = cfg[kind]
        if a and a.enabled and (a.side or "TOP") == side then
            local _, ht = C.BoxSize(Shape(a))
            total = total + ht + EV.Pixel:One(f) * 4
        end
    end
    return total
end

--- Where the holder's corner goes on the frame, for a side and alignment.
--- extra pushes it further out (the space another block has claimed), in
--- UI units like the sizes; the gap and your nudge are pixels.
local function Place(h, f, cfg, a, shape, extra)
    local one = EV.Pixel:One(f)
    local C = EV.AuraContainer
    local w, ht = C.BoxSize(shape)
    EV.Pixel:SetSize(h, w, ht)
    local side, align = a.side or "TOP", a.align or "START"
    local gap = one * 2 + (extra or 0)
    local x, y = one * (a.x or 0), one * (a.y or 0)
    h:ClearAllPoints()
    if side == "TOP" then
        local p = (align == "END") and "RIGHT" or "LEFT"
        h:SetPoint("BOTTOM" .. p, f, "TOP" .. p, x, y + gap)
    elseif side == "BOTTOM" then
        local p = (align == "END") and "RIGHT" or "LEFT"
        gap = gap + UA.BottomClearance(f, cfg)
        h:SetPoint("TOP" .. p, f, "BOTTOM" .. p, x, y - gap)
    elseif side == "LEFT" then
        h:SetPoint("TOPRIGHT", f, "TOPLEFT", x - gap, y)
    else
        h:SetPoint("TOPLEFT", f, "TOPRIGHT", x + gap, y)
    end
end

local FILTER = { buffs = "HELPFUL", debuffs = "HARMFUL" }
local LIVE = LIVE_UNITS

--- Out of combat: containers are made, not moved, when settings change.
function UA.Layout(f, cfg)
    if not f.auraHolders then return end
    local C = EV.AuraContainer
    local claimed = { TOP = 0, BOTTOM = 0, LEFT = 0, RIGHT = 0 }
    -- Debuffs first: on a target they're the ones you're reading.
    for _, kind in ipairs({ "debuffs", "buffs" }) do
        local h, a = f.auraHolders[kind], cfg[kind]
        if a and a.enabled and cfg.enabled and LIVE[f.key] and C and (f.isPreview or C.Supported()) then
            local shape = Shape(a)
            local side = a.side or "TOP"
            Place(h, f, cfg, a, shape, claimed[side])
            local w, ht = C.BoxSize(shape)
            claimed[side] = claimed[side] + ((side == "TOP" or side == "BOTTOM") and ht or w)
                            + EV.Pixel:One(f) * 4
            if f.isPreview then
                UA.Placeholders(h, shape, kind)
            else
                C.Build(h, shape, {
                    unit = f.unit,
                    filter = FILTER[kind] .. (a.onlyMine and "|PLAYER" or ""),
                    cancel = (kind == "buffs" and f.unit == "player") or nil,
                    tooltip = true,
                    tooltipAnchor = "ANCHOR_BOTTOMRIGHT",
                    dispel = kind == "debuffs" or nil,
                    sort = a.sort,
                })
            end
            h:Show()
        else
            if C then C.Hide(h) end
            h:Hide()
        end
    end
end

--------------------------------------------------------------------------------
--  Designer preview: sample icons filling the block's whole box, laid out
--  the way the engine grows them, so what you place is the space it claims.
--------------------------------------------------------------------------------
local SAMPLE = {
    debuffs = { 136207, 135817, 132337, 136118, 136139, 135849, 132092, 136188 },
    buffs   = { 135987, 136078, 135932, 132333, 135938, 136090, 135926, 132341 },
}

function UA.Placeholders(h, shape, kind)
    h.samples = h.samples or {}
    local one = EV.Pixel:One(h)
    local size, gap, perRow, n = shape.size, shape.spacing, shape.perRow, shape.max
    local left = shape.growX == "LEFT"
    local up = shape.growY == "UP"
    for i = 1, math.max(n, #h.samples) do
        local s = h.samples[i]
        if i <= n then
            if not s then
                s = CreateFrame("Frame", nil, h)
                s.icon = s:CreateTexture(nil, "ARTWORK")
                s.icon:SetTexCoord(EV.Icons:Coords())
                s.back = s:CreateTexture(nil, "BACKGROUND")
                s.back:SetAllPoints()
                h.samples[i] = s
            end
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local x = col * (size + gap)
            local y = row * (size + gap)
            s:ClearAllPoints()
            s:SetSize(size, size)
            s:SetPoint((up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT"), h,
                       (up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT"),
                       left and -x or x, up and y or -y)
            s.icon:ClearAllPoints()
            s.icon:SetPoint("TOPLEFT", one, -one)
            s.icon:SetPoint("BOTTOMRIGHT", -one, one)
            local list = SAMPLE[kind] or SAMPLE.buffs
            s.icon:SetTexture(list[(i - 1) % #list + 1])
            if kind == "debuffs" then s.back:SetColorTexture(0.8, 0.1, 0.1, 1) else s.back:SetColorTexture(0, 0, 0, 1) end
            -- Later icons fade: the box is room for the most you could have,
            -- not what you'll usually see.
            s:SetAlpha(i <= perRow and 1 or 0.45)
            s:Show()
        elseif s then
            s:Hide()
        end
    end
end

--- The token now points at someone else: re-read.
function UA.Update(f)
    if not f.auraHolders then return end
    local C = EV.AuraContainer
    if not C then return end
    C.UpdateAll(f.auraHolders.debuffs)
    C.UpdateAll(f.auraHolders.buffs)
end
