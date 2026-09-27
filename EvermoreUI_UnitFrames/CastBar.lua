if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  CastBar.lua
--  Cast bars for the player, target, focus and pet frames.
--
--  Retiring Blizzard's TargetFrame and FocusFrame takes their spell bars with
--  them (TargetFrameSpellBar and FocusFrameSpellBar are children), so without
--  these the target's cast, the one you interrupt, is simply not on screen.
--
--  Each bar either hangs under its frame (attached: the frame's width unless
--  you set one, and it hides with the frame) or stands on its own where you
--  put it in edit mode (detached). Edit mode moves a proxy frame of the same
--  size, never the bar: Movers re-applies an element's position whenever its
--  size changes, which would fight an attached bar's anchors.
--
--  The cast path follows the nameplates' (EvermoreUI_Nameplates/Cast.lua) and
--  its rules for secret values, which are written out there at length:
--   * fill from a duration object where the client offers one, and pass
--     anything that may be secret straight to a setter, never to arithmetic
--   * type() checks, never truthiness, on anything UnitCasting* returned
--   * stop handlers tear down from cached state and never re-read cast info
--   * uninterruptible is folded into the colour C-side
--  On top of that the unit frames' bars add a spark on the fill's edge,
--  latency on your own casts, and a short red "Interrupted" when a cast is
--  cut off, which is the feedback that tells you your kick landed.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local V = ns.Values
local PAL = EV.Palette

local CB = {}
ns.CastBar = CB

--- Units the game sends cast events for. Target of target has none (nor
--- UNIT_AURA), so it can't have a live cast bar.
CB.LIVE = { player = true, target = true, focus = true, pet = true }

local max, min = math.max, math.min

-- Suite palette, rewritten in place from the Colours page.
local CAST        = PAL.CAST.cast
local CHANNEL     = PAL.CAST.channel
local SHIELDED    = PAL.CAST.shielded
local INTERRUPTED = PAL.CAST.interrupted

local HOLD = 0.6            -- how long "Interrupted" stays up, seconds
local bars = {}             -- unit token -> bar holder
local sentAt                -- GetTime() of your last UNIT_SPELLCAST_SENT

local function IsSecret(v) return V.IsSecret(v) end
local function Plain(v) return type(v) == "number" and not IsSecret(v) end

local function Cfg(h)
    local M = ns.module
    local c = M and M.db and M.db[h.key]
    return c, c and c.castbar
end

--------------------------------------------------------------------------------
--  Fill
--------------------------------------------------------------------------------
local function WriteTimer(h, rem, total)
    local timer = h.timer
    if not timer:IsShown() then return end
    if h.showTotal and type(total) ~= "nil" then
        pcall(timer.SetFormattedText, timer, "%.1f / %.1f", rem, total)
    else
        pcall(timer.SetFormattedText, timer, "%.1f", rem)
    end
end

local function Fill(bar)
    local h = bar.holder
    local dur = h._duration
    if type(dur) ~= "nil" then
        local get = h._channel and dur.GetRemainingDuration or dur.GetElapsedDuration
        if get then
            local ok, v = pcall(get, dur)
            if ok and type(v) ~= "nil" then
                pcall(bar.SetValue, bar, v)
                if dur.GetRemainingDuration then
                    local okR, rem = pcall(dur.GetRemainingDuration, dur)
                    if okR and type(rem) ~= "nil" then WriteTimer(h, rem, h._totalV) end
                end
                return
            end
        end
    end
    local total, endAt = h._total, h._endAt
    if Plain(total) and Plain(endAt) and total > 0 then
        local left = endAt - GetTime()
        if left < 0 then left = 0 end
        bar:SetValue(h._channel and left or (total - left))
        WriteTimer(h, left, total)
    end
end

--- The "Interrupted" hold: counts down, then hides.
local function Holding(bar, elapsed)
    local h = bar.holder
    h._hold = (h._hold or 0) - elapsed
    if h._hold <= 0 then
        h._hold = nil
        bar:SetScript("OnUpdate", nil)
        if h.preview then CB.Preview(h, true) else h:Hide() end
    end
end

--------------------------------------------------------------------------------
--  Start, stop, interrupted
--------------------------------------------------------------------------------
local function Stop(h, quiet)
    if not h then return end
    local bar = h.bar
    if h._hold then return end          -- let "Interrupted" finish
    -- A real end of cast remembers when, so an INTERRUPTED that lands just
    -- after the STOP still shows. A reset (new target) does not.
    if h.casting and not quiet then h.stoppedAt = GetTime() end
    h.casting = false
    bar:SetScript("OnUpdate", nil)
    h._duration, h._total, h._endAt, h._channel, h._totalV = nil, nil, nil, nil, nil
    h.timer:SetText("")
    h.text:SetText("")
    h.safe:Hide()
    if h.preview then CB.Preview(h, true) else h:Hide() end
end
CB.Stop = Stop

local function Interrupted(h, label)
    if not h or not (h.casting or (h.stoppedAt and GetTime() - h.stoppedAt < 0.15)) then return end
    local bar = h.bar
    h.casting = false
    h._duration, h._total, h._endAt = nil, nil, nil
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarColor(INTERRUPTED[1], INTERRUPTED[2], INTERRUPTED[3], 1)
    h.safe:Hide()
    h.timer:SetText("")
    h.text:SetText(label)
    h._hold = HOLD
    bar:SetScript("OnUpdate", Holding)
    h:Show()
end

local function Start(h, channel, isUpdate)
    local unit = h.unit
    if h.isPreview or not CB.LIVE[h.key] then return end
    local cfg, cc = Cfg(h)
    if not (cfg and cc and cc.enabled and cfg.enabled) then return end

    local ok, name, texture, startAt, endAt, notInterruptible, castID
    local _   -- the skipped returns; a bare _ would write the global, which taints
    if channel then
        if type(UnitChannelInfo) ~= "function" then return end
        ok, name, _, texture, startAt, endAt, _, notInterruptible = pcall(UnitChannelInfo, unit)
    else
        if type(UnitCastingInfo) ~= "function" then return end
        ok, name, _, texture, startAt, endAt, _, castID, notInterruptible = pcall(UnitCastingInfo, unit)
    end
    if not ok or type(name) == "nil" then Stop(h) return end

    local bar = h.bar
    h._hold = nil
    h._channel = channel and true or false
    -- Which cast this is, so a FAILED or INTERRUPTED for some other spell
    -- (pressing a key mid-cast fails that spell, not this one) is ignored.
    -- Plain strings only; a channel has none.
    h.castID = (type(castID) == "string" and not IsSecret(castID)) and castID or nil
    h._duration, h._total, h._endAt, h._totalV = nil, nil, nil, nil

    local durFn = channel and UnitChannelDuration or UnitCastingDuration
    if type(durFn) == "function" then
        local okD, dur = pcall(durFn, unit)
        if okD and type(dur) ~= "nil" then
            h._duration = dur
            local okT, total = pcall(dur.GetTotalDuration, dur)
            local maxV = 1
            if okT and type(total) ~= "nil" then maxV = total; h._totalV = total end
            pcall(bar.SetMinMaxValues, bar, 0, maxV)
        end
    end
    if type(h._duration) == "nil" and Plain(startAt) and Plain(endAt) then
        h._total = (endAt - startAt) / 1000
        h._endAt = endAt / 1000
        h._totalV = h._total
        bar:SetMinMaxValues(0, h._total)
    end

    if h.icon then
        h.icon:SetTexture(texture)
    end
    pcall(h.text.SetFormattedText, h.text, "%s", name)

    local base = channel and CHANNEL or CAST
    -- Clients whose UnitCastingInfo predates the flag put the spell ID in
    -- that slot; a number is not an answer.
    if type(notInterruptible) == "number" then notInterruptible = nil end
    bar:SetStatusBarColor(base[1], base[2], base[3], 1)
    if type(notInterruptible) ~= "nil" and C_CurveUtil
       and type(C_CurveUtil.EvaluateColorValueFromBoolean) == "function" then
        local okR, r = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, notInterruptible, SHIELDED[1], base[1])
        local okG, g = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, notInterruptible, SHIELDED[2], base[2])
        local okB, b = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, notInterruptible, SHIELDED[3], base[3])
        if okR and okG and okB then pcall(bar.SetStatusBarColor, bar, r, g, b, 1) end
    elseif not IsSecret(notInterruptible) and notInterruptible == true then
        bar:SetStatusBarColor(SHIELDED[1], SHIELDED[2], SHIELDED[3], 1)
    end

    -- Latency, your own casts only: the time from pressing the key
    -- (UNIT_SPELLCAST_SENT) to the server starting the cast, drawn as a
    -- shaded block at the end of the bar. Anything released inside it is
    -- already too late to cancel. Only with a readable total, since the
    -- width is a division.
    -- A repaint of a running cast (pushback, interruptibility) keeps the
    -- block it has; only a new cast measures again.
    if isUpdate then
        -- leave h.safe as it is
    elseif unit == "player" then
        h.safe:Hide()
    end
    if not isUpdate and unit == "player" and cc.latency and not channel and sentAt then
        local total = Plain(h._totalV) and h._totalV or nil
        local lag = GetTime() - sentAt
        if total and total > 0 and lag > 0 and lag < 2 then
            local w = bar:GetWidth()
            if w and w > 0 then
                h.safe:SetWidth(max(min(lag / total, 1) * w, EV.Pixel:One(bar)))
                h.safe:Show()
            end
        end
    end
    if unit == "player" and not isUpdate then sentAt = nil end

    h.casting = true
    bar:SetScript("OnUpdate", Fill)
    Fill(bar)
    h:Show()
end

--- Is this unit casting right now? Start the bar if so, stop it if not.
local function Check(h)
    if not h or h.isPreview or not CB.LIVE[h.key] then return end
    h._hold = nil
    local bar = h.bar
    bar:SetScript("OnUpdate", nil)
    if type(UnitCastingInfo) == "function" then
        local ok, name = pcall(UnitCastingInfo, h.unit)
        if ok and type(name) ~= "nil" then Start(h, false) return end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, name = pcall(UnitChannelInfo, h.unit)
        if ok and type(name) ~= "nil" then Start(h, true) return end
    end
    h.stoppedAt = nil
    Stop(h, true)
end
CB.Check = Check

--------------------------------------------------------------------------------
--  Build and layout
--------------------------------------------------------------------------------
--- preview: the designer's copy. No global names, not in the event map,
--- and always laid out under its frame (a detached bar's spot is edit
--- mode's business, not the designer's).
function CB.Build(f, preview)
    if f.castbar then return f.castbar end
    local h = CreateFrame("Frame", (not preview) and ("EvermoreUI_" .. f.key .. "CastBar") or nil, f)
    h.key, h.unit, h.frame, h.isPreview = f.key, f.unit, f, preview and true or nil
    h:Hide()
    h.bg = h:CreateTexture(nil, "BACKGROUND", nil, -8)
    h.bg:SetAllPoints()
    EV.Pixel.NoSnap(h.bg)

    h.bar = CreateFrame("StatusBar", nil, h)
    EV.Pixel:Bar(h.bar)
    h.bar.holder = h
    h.bar:SetMinMaxValues(0, 1)
    h.bar:SetValue(0)

    -- The spark rides the fill's right edge, so the client moves it.
    h.spark = h.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    h.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    h.spark:SetBlendMode("ADD")

    -- Latency block: at the end of the bar, over the fill.
    h.safe = h.bar:CreateTexture(nil, "OVERLAY", nil, 0)
    h.safe:SetColorTexture(1, 0.1, 0.1, 0.45)
    h.safe:Hide()

    h.iconFrame = CreateFrame("Frame", nil, h)
    h.icon = h.iconFrame:CreateTexture(nil, "ARTWORK")
    h.icon:SetAllPoints()
    h.icon:SetTexCoord(EV.Icons:Coords())
    h.iconEdge = h:CreateTexture(nil, "BORDER")
    EV.Pixel.NoSnap(h.iconEdge)

    h.over = CreateFrame("Frame", nil, h)
    h.over:SetAllPoints()
    h.over:SetFrameLevel(h.bar:GetFrameLevel() + 3)
    h.text = h.over:CreateFontString(nil, "OVERLAY")
    h.text:SetJustifyH("LEFT")
    h.text:SetWordWrap(false)
    h.timer = h.over:CreateFontString(nil, "OVERLAY")
    h.timer:SetJustifyH("RIGHT")
    -- A font straight away, not first in Layout: a bar that's off never gets
    -- laid out, but Stop still clears its text, and SetText on a font string
    -- with no font throws (target of target's bar is off from the start).
    EV.Fonts:StyleText(h.text, 11, "both", true)
    EV.Fonts:StyleText(h.timer, 11, "both", true)

    -- What edit mode moves when the bar is detached.
    if not preview then
        h.proxy = CreateFrame("Frame", "EvermoreUI_" .. f.key .. "CastBarMover", UIParent)
        h.proxy:SetSize(1, 1)
    end

    f.castbar = h
    if not preview then bars[f.unit] = h end
    return h
end

--- Out of combat (the attached bar is parented to a protected frame).
function CB.Layout(f, cfg)
    local h = f.castbar
    if not h then return end
    local cc = cfg.castbar
    if not (cc and cc.enabled and cfg.enabled and CB.LIVE[f.key]) then
        h._hold = nil
        h.preview = false
        Stop(h, true)
        h:Hide()
        return
    end
    local one = EV.Pixel:One(f)
    local w = (cc.width and cc.width > 0) and cc.width or cfg.width
    local ht = max(cc.height or 18, 4)
    if h.proxy then EV.Pixel:SetSize(h.proxy, w, ht) end

    h:ClearAllPoints()
    if cc.detached and not h.isPreview then
        h:SetParent(UIParent)
        h:SetAllPoints(h.proxy)
    else
        h:SetParent(f)
        local gap = one * (cc.gap or 4)
        if cc.width and cc.width > 0 then
            EV.Pixel:SetSize(h, w, ht)
            h:SetPoint("TOP", f, "BOTTOM", one * (cc.x or 0), -gap)
        else
            h:SetPoint("TOPLEFT", f, "BOTTOMLEFT", one * (cc.x or 0), -gap)
            h:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", one * (cc.x or 0), -gap)
            h:SetHeight(EV.Pixel:Snap(h, ht))
        end
    end
    -- The designer's copy keeps its window's strata; MEDIUM would put it
    -- under the canvas.
    if not h.isPreview then h:SetFrameStrata("MEDIUM") end
    h:SetFrameLevel(max(f:GetFrameLevel(), 2) + 8)
    h.over:SetFrameLevel(h.bar:GetFrameLevel() + 3)

    -- Same border, background and texture as the frame it belongs to.
    local bpx = cfg.borderSize or 1
    local bc = ns.Frame.RGB(cfg.borderColour, { 0, 0, 0 })
    local b = one * bpx
    if bpx > 0 then EV.Pixel:CreateBorder(h, bpx, bc[1], bc[2], bc[3], 1)
    else EV.Pixel:CreateBorder(h, 1, 0, 0, 0, 0) end
    local bg = ns.Frame.RGB(cfg.bgColour, { 0.031, 0.031, 0.031 })
    h.bg:SetColorTexture(bg[1], bg[2], bg[3], cfg.bgAlpha or 0.85)
    local tex = EV.Media:Fetch("statusbar", (cc.texture and cc.texture ~= "") and cc.texture or cfg.texture)
    h.bar:SetStatusBarTexture(tex)

    -- Icon: a square inside the border on the chosen side, then a hairline.
    local inner = max(ht - b * 2, 1)
    local iw = 0
    h.iconFrame:ClearAllPoints()
    h.iconEdge:ClearAllPoints()
    if cc.icon ~= false then
        iw = inner + one
        h.iconFrame:SetSize(inner, inner)
        if cc.iconSide == "RIGHT" then
            h.iconFrame:SetPoint("TOPRIGHT", h, "TOPRIGHT", -b, -b)
            h.iconEdge:SetPoint("TOPRIGHT", h.iconFrame, "TOPLEFT", 0, 0)
            h.iconEdge:SetPoint("BOTTOMRIGHT", h.iconFrame, "BOTTOMLEFT", 0, 0)
        else
            h.iconFrame:SetPoint("TOPLEFT", h, "TOPLEFT", b, -b)
            h.iconEdge:SetPoint("TOPLEFT", h.iconFrame, "TOPRIGHT", 0, 0)
            h.iconEdge:SetPoint("BOTTOMLEFT", h.iconFrame, "BOTTOMRIGHT", 0, 0)
        end
        h.iconEdge:SetWidth(one)
        h.iconEdge:SetColorTexture(bc[1], bc[2], bc[3], 1)
        h.iconEdge:Show()
        h.iconFrame:Show()
    else
        h.iconEdge:Hide()
        h.iconFrame:Hide()
    end
    local left = (cc.icon ~= false and cc.iconSide ~= "RIGHT") and iw or 0
    local right = (cc.icon ~= false and cc.iconSide == "RIGHT") and iw or 0
    h.bar:ClearAllPoints()
    h.bar:SetPoint("TOPLEFT", h, "TOPLEFT", b + left, -b)
    h.bar:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -b - right, b)

    local fill = h.bar:GetStatusBarTexture()
    h.spark:ClearAllPoints()
    if fill and cc.spark ~= false then
        h.spark:SetSize(max(inner * 0.6, 6), inner * 2.2)
        h.spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
        h.spark:Show()
    else
        h.spark:Hide()
    end
    h.safe:ClearAllPoints()
    h.safe:SetPoint("TOPRIGHT", h.bar, "TOPRIGHT", 0, 0)
    h.safe:SetPoint("BOTTOMRIGHT", h.bar, "BOTTOMRIGHT", 0, 0)

    local size = cc.fontSize or max((cfg.fontSize or 13) - 2, 8)
    EV.Fonts:StyleText(h.text, size, cfg.textStyle, true, cfg.font)
    EV.Fonts:StyleText(h.timer, size, cfg.textStyle, true, cfg.font)
    h.text:SetTextColor(1, 1, 1)
    h.timer:SetTextColor(1, 1, 1)
    h.timer:ClearAllPoints()
    h.timer:SetPoint("RIGHT", h.bar, "RIGHT", -4, 0)
    h.text:ClearAllPoints()
    h.text:SetPoint("LEFT", h.bar, "LEFT", 4, 0)
    if cc.showTime ~= false then
        h.text:SetPoint("RIGHT", h.timer, "LEFT", -4, 0)
    else
        h.text:SetPoint("RIGHT", h.bar, "RIGHT", -4, 0)
    end
    h.text:SetShown(cc.showName ~= false)
    h.timer:SetShown(cc.showTime ~= false)
    h.showTotal = cc.timeFormat == "both"

    if h.preview then CB.Preview(h, true) end
end

--------------------------------------------------------------------------------
--  Edit mode preview: a half-filled bar so you can see what you're placing
--------------------------------------------------------------------------------
function CB.Preview(h, on)
    local cfg, cc = Cfg(h)
    on = on and cfg and cc and cfg.enabled and cc.enabled and CB.LIVE[h.key]
    h.preview = on and true or false
    if on then
        if h.casting or h._hold then return end
        local bar = h.bar
        bar:SetScript("OnUpdate", nil)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0.6)
        bar:SetStatusBarColor(CAST[1], CAST[2], CAST[3], 1)
        h.icon:SetTexture(134400)   -- the question-mark icon
        h.text:SetText(L["Cast bar"])
        h.timer:SetText(h.showTotal and "1.2 / 3.0" or "1.2")
        h:Show()
    elseif not h.casting and not h._hold then
        h:Hide()
    end
end

--------------------------------------------------------------------------------
--  Blizzard's own player and pet cast bars
--------------------------------------------------------------------------------
local retired = {}
local function Retire(name)
    local b = _G[name]
    if not b or retired[name] then return end
    retired[name] = true
    if b.SetUnit then pcall(b.SetUnit, b, nil)
    elseif CastingBarFrame_SetUnit then pcall(CastingBarFrame_SetUnit, b, nil) end
    -- Without its unit and events nothing drives it, so it stays down. No
    -- OnShow hook forcing it hidden: that would run our code inside every
    -- Blizzard path that shows it, which is how taint spreads.
    if b.UnregisterAllEvents then b:UnregisterAllEvents() end
    b:Hide()
end

function CB.RetireBlizzard(unit)
    if unit == "player" then
        Retire("PlayerCastingBarFrame")
        Retire("CastingBarFrame")
    elseif unit == "pet" then
        Retire("PetCastingBarFrame")
    end
end

--------------------------------------------------------------------------------
--  Events: one dispatcher for every bar
--------------------------------------------------------------------------------
function CB.Enable(M)
    local ev = CreateFrame("Frame")
    local function Reg(e) pcall(ev.RegisterEvent, ev, e) end

    local START = {
        UNIT_SPELLCAST_START = false,
        UNIT_SPELLCAST_CHANNEL_START = true,
        UNIT_SPELLCAST_EMPOWER_START = true,
    }
    local UPDATE = {
        UNIT_SPELLCAST_DELAYED = false,
        UNIT_SPELLCAST_CHANNEL_UPDATE = true,
        UNIT_SPELLCAST_EMPOWER_UPDATE = true,
        UNIT_SPELLCAST_INTERRUPTIBLE = false,
        UNIT_SPELLCAST_NOT_INTERRUPTIBLE = false,
    }
    local STOP = {
        UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
        UNIT_SPELLCAST_EMPOWER_STOP = true,
    }
    for e in pairs(START) do Reg(e) end
    for e in pairs(UPDATE) do Reg(e) end
    for e in pairs(STOP) do Reg(e) end
    Reg("UNIT_SPELLCAST_INTERRUPTED")
    Reg("UNIT_SPELLCAST_FAILED")
    Reg("UNIT_SPELLCAST_SENT")
    Reg("PLAYER_TARGET_CHANGED")
    Reg("PLAYER_FOCUS_CHANGED")
    Reg("UNIT_PET")

    ev:SetScript("OnEvent", function(_, event, unit, token)
        if not M:IsEnabled() then return end
        if event == "UNIT_SPELLCAST_SENT" then
            if unit == "player" then sentAt = GetTime() end
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then Check(bars.target) return end
        if event == "PLAYER_FOCUS_CHANGED" then Check(bars.focus) return end
        if event == "UNIT_PET" then
            if unit == "player" then Check(bars.pet) end
            return
        end
        local h = unit and bars[unit]
        if not h then return end
        if START[event] ~= nil then
            Start(h, START[event])
        elseif UPDATE[event] ~= nil then
            if h.casting then Start(h, h._channel or UPDATE[event], true) end
        elseif STOP[event] then
            Stop(h)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
            -- Only for the cast the bar is showing. Pressing another spell
            -- mid-cast sends FAILED for that spell while this one carries
            -- on, and FAILED also fires for casts that never started (not
            -- ready, out of range). So FAILED needs the cast ID to match;
            -- INTERRUPTED is taken without one (channels have none).
            local id = token
            local same = h.castID and type(id) == "string" and not IsSecret(id) and id == h.castID
            if event == "UNIT_SPELLCAST_INTERRUPTED" then
                if same or not h.castID or type(id) ~= "string" then Interrupted(h, L["Interrupted"]) end
            elseif h.casting and same then
                Interrupted(h, L["Failed"])
            end
        end
    end)

end

--- Edit mode opened or closed (UnitFrames.lua routes the message here:
--- a module keeps one handler per message).
function CB.PreviewAll(on)
    for _, h in pairs(bars) do CB.Preview(h, on) end
end

function CB.Bars() return bars end
