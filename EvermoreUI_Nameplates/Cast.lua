if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Cast.lua
--  The cast bar, and the only legitimate OnUpdate in this addon.
--
--  Two decisions worth stating:
--
--  1. ONE GLOBAL DISPATCHER, not per-plate registrations. There are eight
--     cast events; registering them per plate against forty plates is 320
--     registrations, and the payload's first return is the unit token, so a
--     single global frame plus an O(1) lookup in ns.plates does the same job
--     with eight. This is the single biggest structural saving available on
--     the cast path.
--
--  2. The fill OnUpdate is INSTALLED ON CAST START AND REMOVED ON CAST STOP.
--     A bar that is not filling has no script attached. Nothing polls to ask
--     whether a cast is happening.
--
--  Secret values: UnitCastingInfo's times are secret in restricted content
--  and cannot be used in arithmetic, so the fill is driven from a duration
--  object where the client offers one. And the stop handlers DELIBERATELY DO
--  NOT re-read cast info: under restriction the API can hand back a secret
--  non-nil tuple for the cast that just ended, the ended branch never runs,
--  and the bar sticks on screen forever. Tear down from cached state.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local T = EV.Theme

local casting = {}      -- our plate -> true, so ticks iterate the 1-3 casting
                        -- plates rather than every plate in the scene

-- Cast colours live in the suite palette (Core/Palette.lua, P.CAST), which
-- rewrites these tables in place when you pick your own on the Colours page.
local CAST        = EV.Palette.CAST.cast
local CHANNEL     = EV.Palette.CAST.channel
local SHIELDED    = EV.Palette.CAST.shielded

--------------------------------------------------------------------------------
--  Fill
--------------------------------------------------------------------------------
local function Fill(bar)
    local dur = bar._duration
    -- type(), never truthiness: UnitCastingDuration is SecretReturns, so the
    -- duration object itself is a secret value in restricted content and
    -- `if dur then` throws. This runs in an OnUpdate with no pcall around
    -- it, so it would throw every frame of every cast.
    if type(dur) ~= "nil" then
        -- A cast fills as it progresses, a channel drains. Ask the duration
        -- object for the value that already points the right way rather
        -- than subtracting one from the other: the values are secret in
        -- restricted content and arithmetic on a secret throws.
        local get = bar._channel and dur.GetRemainingDuration or dur.GetElapsedDuration
        if get then
            local ok, v = pcall(get, dur)
            if ok and type(v) ~= "nil" then
                pcall(bar.SetValue, bar, v)     -- may be secret; setter only
                if bar.timer:IsShown() and dur.GetRemainingDuration then
                    local okR, rem = pcall(dur.GetRemainingDuration, dur)
                    -- SetFormattedText takes a secret; %.1f on one does not,
                    -- so it goes to the setter and nowhere else.
                    if okR and type(rem) ~= "nil" then
                        pcall(bar.timer.SetFormattedText, bar.timer, "%.1f", rem)
                    end
                end
                return
            end
        end
    end
    -- Plain fallback for a client without duration objects. Cached plain
    -- numbers only; cast info is never re-read here.
    local total, endAt = bar._total, bar._endAt
    if type(total) == "number" and type(endAt) == "number" and total > 0 then
        local left = endAt - GetTime()
        if left < 0 then left = 0 end
        bar:SetValue(bar._channel and left or (total - left))
        if bar.timer:IsShown() then bar.timer:SetFormattedText("%.1f", left) end
    end
end

local function Stop(f)
    local bar = f.cast
    if not bar then return end
    casting[f] = nil
    bar:SetScript("OnUpdate", nil)
    bar._duration, bar._total, bar._endAt, bar._channel = nil, nil, nil, nil
    if bar.timer then bar.timer:SetText("") end
    if bar.target then bar.target:SetText("") end
    -- The icon frame hangs off the PLATE, not off the bar, so hiding the bar
    -- no longer takes it with it. Forget this and every mob you ever saw cast
    -- keeps a spell icon floating beside it.
    if bar.iconFrame then bar.iconFrame:Hide() end
    bar:Hide()
end
ns.StopCast = Stop

local function Start(f, channel)
    local bar = f.cast
    local unit = f.unit
    if not (bar and unit) then return end
    local cfg = ns.module.db
    if not cfg.showCast or cfg.castHeight <= 0 then return end

    -- The two APIs do NOT share a return order. UnitCastingInfo has castID
    -- at 7 and notInterruptible at 8; UnitChannelInfo has notInterruptible
    -- at 7 and spellID at 8 (UnitDocumentation.lua:840-851, 882-893).
    -- Reading them with one destructure paints every channel as shielded,
    -- because a spellID is a truthy number.
    local ok, name, texture, startAt, endAt, notInterruptible
    if channel then
        if type(UnitChannelInfo) ~= "function" then return end
        ok, name, _, texture, startAt, endAt, _, notInterruptible = pcall(UnitChannelInfo, unit)
    else
        if type(UnitCastingInfo) ~= "function" then return end
        ok, name, _, texture, startAt, endAt, _, _, notInterruptible = pcall(UnitCastingInfo, unit)
    end
    if not ok or type(name) == "nil" then Stop(f) return end

    bar._channel = channel and true or false
    bar._duration, bar._total, bar._endAt = nil, nil, nil

    -- Preferred: a duration object, which is the secret-safe path.
    local durFn = channel and UnitChannelDuration or UnitCastingDuration
    if type(durFn) == "function" then
        local okD, dur = pcall(durFn, unit)
        if okD and type(dur) ~= "nil" then
            bar._duration = dur
            -- Hoisted out of the call: an `x and total or 1` argument is
            -- evaluated BEFORE pcall is entered, so a secret total would
            -- throw past the guard that is supposed to catch it.
            local okT, total = pcall(dur.GetTotalDuration, dur)
            local maxV = 1
            if okT and type(total) ~= "nil" then maxV = total end
            pcall(bar.SetMinMaxValues, bar, 0, maxV)
        end
    end
    -- type(), not truthiness. UnitCastingDuration is SecretReturns = true
    -- (UnitDocumentation.lua:811), so bar._duration is itself a secret in
    -- restricted content and `if not bar._duration` throws -- which is the
    -- rule this file states in its own header and then broke here. Fill gets
    -- it right; Start did not, and the cost was every cast bar in a dungeon.
    --
    -- The plain fallback also has to be guarded properly. startTimeMs and
    -- endTimeMs are NOT marked NeverSecret in UnitCastingInfo's documentation
    -- (UnitDocumentation.lua:828-851) the way isTradeskill and castBarID are,
    -- and type() of a secret number is "number", so the old guard proved
    -- nothing before doing arithmetic on them.
    if type(bar._duration) == "nil"
       and not ns.IsSecret(startAt) and not ns.IsSecret(endAt)
       and type(startAt) == "number" and type(endAt) == "number" then
        bar._total = (endAt - startAt) / 1000
        bar._endAt = endAt / 1000
        bar:SetMinMaxValues(0, bar._total)
    end

    if bar.icon then
        bar.icon:SetTexture(texture)
        bar.iconFrame:SetShown(type(texture) ~= "nil")
    end
    if bar.text then pcall(bar.text.SetFormattedText, bar.text, "%s", name) end

    -- Uninterruptible is a boolean that may be secret. Fold it into the
    -- colour C-side rather than branching on it.
    local base = channel and CHANNEL or CAST
    if type(notInterruptible) ~= "nil" and C_CurveUtil
       and type(C_CurveUtil.EvaluateColorValueFromBoolean) == "function" then
        local okR, r = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, notInterruptible, SHIELDED[1], base[1])
        local okG, g = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, notInterruptible, SHIELDED[2], base[2])
        local okB, b = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, notInterruptible, SHIELDED[3], base[3])
        if okR and okG and okB then pcall(bar.SetStatusBarColor, bar, r, g, b, 1) end
    else
        bar:SetStatusBarColor(base[1], base[2], base[3], 1)
    end

    -- Cast target, class coloured, on the bar's right.
    if bar.target:IsShown() then
        local tUnit = unit .. "target"
        local okT, tName = pcall(UnitName, tUnit)
        if okT and type(tName) ~= "nil" then
            local okC, _, class = pcall(UnitClass, tUnit)
            local r, g, b = EV.Palette.ClassRGB(okC and class or nil)
            if r then bar.target:SetTextColor(r, g, b) else bar.target:SetTextColor(1, 1, 1) end
            pcall(bar.target.SetFormattedText, bar.target, "%s", tName)
        else
            bar.target:SetText("")
        end
    end

    casting[f] = true
    bar:SetScript("OnUpdate", Fill)
    Fill(bar)
    bar:Show()
end

--------------------------------------------------------------------------------
--  The widget
--------------------------------------------------------------------------------
ns.Widget{
    name = "cast",

    Build = function(f)
        local bar = CreateFrame("StatusBar", nil, f)
        bar:Hide()
        bar:SetMinMaxValues(0, 1)
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        EV.Pixel.NoSnap(bar.bg)
        -- The spell icon is its own frame, not a texture on the cast bar,
        -- because in the reference it is anchored to the PLATE and spans both
        -- bars: a texture parented to a 9px cast bar cannot be 27px tall
        -- without the bar's own draw order fighting it.
        bar.iconFrame = CreateFrame("Frame", nil, f)
        bar.iconFrame:EnableMouse(false)
        bar.iconFrame:Hide()
        bar.iconEdge = bar.iconFrame:CreateTexture(nil, "BACKGROUND")
        bar.iconEdge:SetAllPoints(bar.iconFrame)
        bar.iconEdge:SetColorTexture(0, 0, 0, 1)
        bar.icon = bar.iconFrame:CreateTexture(nil, "ARTWORK")
        -- One physical pixel of border, not one layout unit: see the same
        -- note in Auras.lua's InitButton.
        local one = EV.Pixel:One(f)
        bar.icon:SetPoint("TOPLEFT", bar.iconFrame, "TOPLEFT", one, -one)
        bar.icon:SetPoint("BOTTOMRIGHT", bar.iconFrame, "BOTTOMRIGHT", -one, one)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Spell name below left, remaining time below right, cast target on
        -- the bar itself at the right. All three ride an overlay so the bar
        -- fill can never cover them.
        bar.over = CreateFrame("Frame", nil, bar)
        bar.over:SetAllPoints()
        bar.over:SetFrameLevel(bar:GetFrameLevel() + 2)
        bar.text = bar.over:CreateFontString(nil, "OVERLAY")
        bar.text:SetJustifyH("LEFT")
        bar.text:SetWordWrap(false)
        bar.timer = bar.over:CreateFontString(nil, "OVERLAY")
        bar.timer:SetJustifyH("RIGHT")
        bar.target = bar.over:CreateFontString(nil, "OVERLAY")
        bar.target:SetJustifyH("RIGHT")
        bar.target:SetWordWrap(false)
        f.cast = bar
    end,

    Layout = function(f, cfg)
        local bar, one = f.cast, EV.Pixel:One(f)
        local on = cfg.showCast and cfg.castHeight > 0
        bar:ClearAllPoints()
        -- Only torn down when the feature itself is off. Tearing down on
        -- every layout pass would blank a live cast whenever a setting
        -- changed, and the bar heals itself on the next unit assignment.
        if not on then Stop(f); return end
        -- BELOW the plate, not inside it. A cast bar that takes its height
        -- out of the health bar leaves a sliver of health and an empty box
        -- whenever nothing is casting.
        -- Anchored to the POWER strip rather than to the plate, and to a
        -- frame rather than to a number. The power bar only exists for units
        -- that have the resource, so its height is decided per unit, and a
        -- cast bar positioned by arithmetic would leave a six pixel hole
        -- under every wolf. Anchoring to the frame means the hole closes
        -- itself: with no power bar the strip collapses to nothing and its
        -- bottom edge IS the plate's.
        local anchor = f.power or f.health
        bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -cfg.castGap)
        bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -cfg.castGap)
        bar:SetHeight(cfg.castHeight)
        -- Its own hairline. With castGap at 0 the two bars touch, and the
        -- reference's three pixels of black between the fills are exactly
        -- this: the health bar's bottom edge and the cast bar's top edge
        -- sitting against each other.
        -- Decoupled, like the health bar's: this rides the same plate and
        -- scales with it. Every layout rather than once behind a flag, so the
        -- colour and thickness are re-asserted after a relayout.
        EV.Pixel:CreateBorder(bar, 1, 0, 0, 0, 1, true)

        local tex = EV.Media:Fetch("statusbar", cfg.texture)
        bar:SetStatusBarTexture(tex)
        bar.bg:SetTexture(tex)
        bar.bg:SetVertexColor(T.RGBA("surfaceSunk", 0.9))

        -- Left of the PLATE, top aligned with it, as tall as the health bar
        -- and the cast bar together. In the reference it measures 59px square
        -- against a 44px health bar and a 22px cast bar, two pixels clear of
        -- the bar's left edge. It is the first thing you see when something
        -- starts casting, which is the point.
        local iconSize = cfg.height + cfg.castHeight
        bar.iconFrame:ClearAllPoints()
        bar.iconFrame:SetPoint("TOPRIGHT", f.health, "TOPLEFT", -one * 2, 0)
        EV.Pixel:SetSize(bar.iconFrame, iconSize, iconSize)
        bar.iconFrame:SetFrameLevel((f:GetFrameLevel() or 1) + 2)

        -- Spell name TOPLEFT below the cast bar, time left TOPRIGHT
        -- beside it, cast target on the bar's right at a smaller scale.
        local small = math.max(cfg.fontSize - 1, 8)
        local tiny  = math.max(cfg.fontSize - 3, 7)
        ns.SetText(bar.text, small, true)
        ns.SetText(bar.timer, small, true)
        ns.SetText(bar.target, tiny, true)
        for _, fs in ipairs({ bar.text, bar.timer, bar.target }) do
            fs:SetTextColor(1, 1, 1)
        end

        bar.text:ClearAllPoints()
        bar.text:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
        bar.timer:ClearAllPoints()
        bar.timer:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -1)
        bar.text:SetPoint("RIGHT", bar.timer, "LEFT", -4, 0)
        bar.target:ClearAllPoints()
        bar.target:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

        bar.text:SetShown(cfg.showCastText)
        bar.timer:SetShown(cfg.showCastText)
        bar.target:SetShown(cfg.showCastTarget)
    end,

    --- Hidden when the plate changes UNIT, not on every SetUnit sweep.
    ---
    --- Plates are pooled, so a frame acquired for a new mob may still be
    --- carrying the bar from whatever the last one was casting, and the pool's
    --- resetter does not hide children.
    ---
    --- But SetUnit is a SWEEP, not a unit change. UNIT_NAME_UPDATE and
    --- UNIT_LEVEL both run it (Extras.lua), and so does every options change
    --- via Restyle. Tearing down unconditionally meant a mob that levelled or
    --- renamed itself mid-cast, or any settings tweak during a pull, blanked
    --- the cast bar until the next cast event. Which is the exact failure the
    --- Layout path above is written to avoid.
    SetUnit = function(f)
        if f.cast and f.cast._unit ~= f.unit then
            f.cast._unit = f.unit
            Stop(f)
        end
    end,

    -- Deliberately no Events: the cast events are global, below.
    Late = function(f)
        if not ns.module.db.showCast then return end
        -- A plate that spawned mid-cast should show it.
        if type(UnitCastingInfo) == "function" then
            local ok, name = pcall(UnitCastingInfo, f.unit)
            if ok and type(name) ~= "nil" then Start(f, false) return end
        end
        if type(UnitChannelInfo) == "function" then
            local ok, name = pcall(UnitChannelInfo, f.unit)
            if ok and type(name) ~= "nil" then Start(f, true) end
        end
    end,

    Clear = function(f)
        -- On release, not in Stop: SetUnit sets _unit and then calls Stop, so
        -- clearing it there would make every SetUnit sweep tear the bar down
        -- again, which is the bug this key exists to prevent.
        if f.cast then f.cast._unit = nil end
        Stop(f)
    end,

    --------------------------------------------------------------------------
    --  One global dispatcher for the whole cast family.
    --------------------------------------------------------------------------
    Enable = function(M)
        local function plate(unit) return unit and ns.plates[unit] or nil end

        -- Empowered casts come through the channel API, so they map onto the
        -- channel branch rather than needing a third code path.
        local START   = {
            UNIT_SPELLCAST_START = false,
            UNIT_SPELLCAST_CHANNEL_START = true,
            UNIT_SPELLCAST_EMPOWER_START = true,
        }
        local UPDATE  = {
            UNIT_SPELLCAST_DELAYED = false,
            UNIT_SPELLCAST_CHANNEL_UPDATE = true,
            UNIT_SPELLCAST_EMPOWER_UPDATE = true,
            -- Interruptibility can flip mid-cast; re-running Start repaints
            -- the bar without disturbing the fill.
            UNIT_SPELLCAST_INTERRUPTIBLE = false,
            UNIT_SPELLCAST_NOT_INTERRUPTIBLE = false,
        }
        local STOP    = {
            UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
            UNIT_SPELLCAST_EMPOWER_STOP = true,
            UNIT_SPELLCAST_FAILED = true, UNIT_SPELLCAST_INTERRUPTED = true,
        }

        for event, channel in pairs(START) do
            M:RegisterEvent(event, function(_, _, unit)
                local f = plate(unit)
                if f then ns.Safe("cast-start", Start, f, channel) end
            end)
        end
        for event, channel in pairs(UPDATE) do
            M:RegisterEvent(event, function(_, _, unit)
                local f = plate(unit)
                -- Repaint only a bar that is already up: an interruptibility
                -- event for a unit we are not tracking is not a cast start.
                if f and casting[f] then
                    ns.Safe("cast-update", Start, f, f.cast and f.cast._channel or channel)
                end
            end)
        end
        for event in pairs(STOP) do
            -- Note: no re-read of cast info here, on purpose. See the header.
            M:RegisterEvent(event, function(_, _, unit)
                local f = plate(unit)
                if f then ns.Safe("cast-stop", Stop, f) end
            end)
        end
    end,
}
