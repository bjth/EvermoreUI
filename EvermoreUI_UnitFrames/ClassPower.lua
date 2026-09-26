if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  ClassPower.lua
--  Combo points and totems, on the player frame.
--
--  Both lived on frames we retire: combo points on TargetFrame (ComboFrame)
--  or PlayerFrame's class power bar, depending on the client's lineage, and
--  a shaman's totems on PlayerFrame (TotemFrame). Hiding those frames hid
--  these with them.
--
--  COMBO POINTS. One pip per point, each a StatusBar whose range is one
--  point wide: pip i runs from i-1 to i, and every pip is handed the same
--  count. The bar clamps, so pip i is full exactly when you have at least i
--  points. That means the count can be secret and still draw, because it
--  only ever goes to SetValue: nothing here compares or adds it. Shown for
--  rogues, and for druids while their power is energy (Cat Form).
--
--  TOTEMS. A button per totem slot (GetTotemInfo), with its icon, a swipe
--  and the time left, and Blizzard's own secure "destroytotem" action on
--  right click, the same one TotemFrame uses. The buttons are secure, so
--  they are made and shown out of combat; an empty slot is faded to nothing
--  rather than hidden, because a totem goes down mid-fight when Show would
--  be refused.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local V = ns.Values

local CP = {}
ns.ClassPower = CP

local max = math.max
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_TOTEMS = MAX_TOTEMS or 4

local function IsSecret(v) return V.IsSecret(v) end
local function Frame() return ns.frames and ns.frames.player end
local function Cfg() local M = ns.module; return M and M.db and M.db.player end

local _, CLASS = UnitClass("player")

--------------------------------------------------------------------------------
--  Combo points
--------------------------------------------------------------------------------
local combo            -- holder with .pips
local comboMax = 5

local function Points() return EV.ComboPoints() end
local function WantsCombo() return EV.WantsComboPoints() end

local function BuildCombo(f)
    if combo then return combo end
    combo = CreateFrame("Frame", "EvermoreUI_ComboPoints", f)
    combo.pips = {}
    combo:Hide()
    return combo
end

local function Pip(i)
    local p = combo.pips[i]
    if p then return p end
    p = CreateFrame("StatusBar", nil, combo)
    p:SetStatusBarTexture(WHITE)
    p:SetMinMaxValues(i - 1, i)
    p:SetValue(0)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    EV.Pixel.NoSnap(p.bg)
    combo.pips[i] = p
    return p
end

function CP.LayoutCombo()
    local f, cfg = Frame(), Cfg()
    if not (f and cfg) then return end
    local c = cfg.classPower
    BuildCombo(f)
    if not (c and c.enabled and cfg.enabled) or not EV.HasComboClass() then
        combo:Hide()
        return
    end
    local one = EV.Pixel:One(f)
    local n = comboMax
    local w = (c.width and c.width > 0) and c.width or cfg.width
    local h = max(c.height or 8, 2)
    local gap = one * (c.spacing or 2)
    local bpx = cfg.borderSize or 1
    local bc = ns.Frame.RGB(cfg.borderColour, { 0, 0, 0 })
    local bg = ns.Frame.RGB(cfg.bgColour, { 0.031, 0.031, 0.031 })
    local col = ns.Frame.RGB(c.colour, { 1, 0.86, 0.1 })
    local tex = EV.Media:Fetch("statusbar", cfg.texture)

    EV.Pixel:SetSize(combo, w, h)
    combo:ClearAllPoints()
    local x, y = one * (c.x or 0), one * (c.y or 0)
    -- Past anything else claiming that side: an attached cast bar below,
    -- and the frame's own buffs or debuffs if you've put them there.
    local UA = ns.UnitAuras
    if c.side == "BOTTOM" then
        local below = (UA and (UA.BottomClearance(f, cfg) + UA.Claimed(f, cfg, "BOTTOM")) or 0) + one * 3
        combo:SetPoint("TOP", f, "BOTTOM", x, y - below)
    else
        local above = (UA and UA.Claimed(f, cfg, "TOP") or 0) + one * 3
        combo:SetPoint("BOTTOM", f, "TOP", x, y + above)
    end
    combo:SetFrameLevel(f:GetFrameLevel() + 6)

    local pw = (w - gap * (n - 1)) / n
    for i = 1, max(n, #combo.pips) do
        local p = Pip(i)
        if i <= n then
            p:SetStatusBarTexture(tex)
            p:SetStatusBarColor(col[1], col[2], col[3], 1)
            p.bg:SetColorTexture(bg[1], bg[2], bg[3], 0.85)
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", combo, "TOPLEFT", (i - 1) * (pw + gap), 0)
            EV.Pixel:SetSize(p, pw, h)
            -- Decoupled: a border on the bar itself would sit under its own
            -- fill (Pixel.lua), and a lit pip would lose its edge.
            if bpx > 0 then EV.Pixel:CreateBorder(p, math.min(bpx, 2), bc[1], bc[2], bc[3], 1, true)
            else EV.Pixel:CreateBorder(p, 1, 0, 0, 0, 0, true) end
            p:Show()
        else
            p:Hide()
        end
    end
    CP.UpdateCombo()
end

function CP.UpdateCombo()
    local cfg = Cfg()
    if not combo or not cfg then return end
    local c = cfg.classPower
    if not (c and c.enabled and cfg.enabled) or not WantsCombo() then combo:Hide() return end
    local v, m = Points()
    if m and m ~= comboMax and m <= 10 then
        -- The holder and pips are plain frames, so this is fine in combat.
        comboMax = m
        CP.LayoutCombo()
        return
    end
    if type(v) == "nil" then combo:Hide() return end
    for i = 1, comboMax do
        local p = combo.pips[i]
        if p then pcall(p.SetValue, p, v) end
    end
    -- Out of combat with nothing to spend, it can step aside. Only when the
    -- count can be read; otherwise it stays up.
    if c.hideEmpty and not IsSecret(v) and v == 0 and not UnitAffectingCombat("player") then
        combo:Hide()
    else
        combo:Show()
    end
end

--------------------------------------------------------------------------------
--  Totems
--------------------------------------------------------------------------------
local totems           -- holder with .buttons

local function TotemButton(slot)
    local b = CreateFrame("Button", "EvermoreUI_Totem" .. slot, totems, "SecureActionButtonTemplate")
    b.slot = slot
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type2", "destroytotem")
    b:SetAttribute("totem-slot", slot)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetDrawEdge(false)
    b.cd:SetReverse(true)
    b:SetScript("OnEnter", function(self)
        -- Our own plain flag: after a secret fold the alpha itself may be
        -- secret, and comparing it would throw.
        if self.empty then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if GameTooltip.SetTotem then pcall(GameTooltip.SetTotem, GameTooltip, self.slot) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetAlpha(0)
    b.empty = true
    return b
end

function CP.LayoutTotems()
    local f, cfg = Frame(), Cfg()
    if not (f and cfg) or CLASS ~= "SHAMAN" then return end
    if InCombatLockdown() then return end
    local t = cfg.totems
    if not totems then
        totems = CreateFrame("Frame", "EvermoreUI_Totems", f)
        totems.buttons = {}
        for slot = 1, MAX_TOTEMS do totems.buttons[slot] = TotemButton(slot) end
    end
    if not (t and t.enabled and cfg.enabled) then
        totems:Hide()
        return
    end
    local one = EV.Pixel:One(f)
    local size, gap = max(t.size or 24, 10), one * (t.spacing or 3)
    local n = MAX_TOTEMS
    EV.Pixel:SetSize(totems, n * size + (n - 1) * gap, size)
    totems:ClearAllPoints()
    local x, y = one * (t.x or 0), one * (t.y or 0)
    local UA = ns.UnitAuras
    if t.side == "TOP" then
        local above = (UA and UA.Claimed(f, cfg, "TOP") or 0) + one * 3
        totems:SetPoint(t.align == "END" and "BOTTOMRIGHT" or "BOTTOMLEFT", f,
                        t.align == "END" and "TOPRIGHT" or "TOPLEFT", x, y + above)
    else
        local below = (UA and (UA.BottomClearance(f, cfg) + UA.Claimed(f, cfg, "BOTTOM")) or 0) + one * 3
        totems:SetPoint(t.align == "END" and "TOPRIGHT" or "TOPLEFT", f,
                        t.align == "END" and "BOTTOMRIGHT" or "BOTTOMLEFT", x, y - below)
    end
    totems:SetFrameLevel(f:GetFrameLevel() + 6)
    local bpx = math.min(cfg.borderSize or 1, 2)
    for slot, b in ipairs(totems.buttons) do
        b:ClearAllPoints()
        b:SetPoint("LEFT", totems, "LEFT", (slot - 1) * (size + gap), 0)
        EV.Pixel:SetSize(b, size, size)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("TOPLEFT", one * bpx, -one * bpx)
        b.icon:SetPoint("BOTTOMRIGHT", -one * bpx, one * bpx)
        b.cd:SetAllPoints(b.icon)
        b.cd:SetHideCountdownNumbers(t.showTimer == false)
        b:Show()
    end
    totems:Show()
    CP.UpdateTotems()
end

function CP.UpdateTotems()
    if not totems or not totems:IsShown() then return end
    local calm = not InCombatLockdown()
    for slot, b in ipairs(totems.buttons) do
        local ok, have, name, start, duration, icon = pcall(GetTotemInfo, slot)
        if not ok or type(have) == "nil" then
            b.empty = true
            b:SetAlpha(0)
        elseif IsSecret(have) then
            -- Can't tell: fold the answer into the alpha and keep the button
            -- live for its tooltip and right click.
            b.empty = false
            pcall(b.SetAlphaFromBoolean, b, have, 1, 0)
            pcall(b.icon.SetTexture, b.icon, icon)
            pcall(b.cd.SetCooldown, b.cd, start, duration)
        elseif have and type(name) == "string" and name ~= "" then
            b.empty = false
            b.icon:SetTexture(icon)
            pcall(b.cd.SetCooldown, b.cd, start, duration)
            b:SetAlpha(1)
        else
            b.empty = true
            b.cd:Clear()
            b:SetAlpha(0)
        end
        -- An empty slot shouldn't swallow clicks meant for the world under
        -- it. Mouse on a secure button is out of combat only; in combat an
        -- empty one stays clickable (right click on nothing does nothing).
        if calm then b:EnableMouse(not b.empty) end
    end
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
local totemsPending = false

function CP.Refresh()
    -- Combo points are plain frames and can be laid out any time; totems
    -- are secure buttons and wait for combat to end.
    CP.LayoutCombo()
    if InCombatLockdown() then
        totemsPending = true
        CP.UpdateTotems()
    else
        totemsPending = false
        CP.LayoutTotems()
    end
end

function CP.Enable(M)
    local ev = CreateFrame("Frame")
    for _, e in ipairs(EV.COMBO_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
    for _, e in ipairs({ "PLAYER_TOTEM_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        pcall(ev.RegisterEvent, ev, e)
    end
    ev:SetScript("OnEvent", function(_, event, unit, token)
        if not M:IsEnabled() then return end
        if event == "PLAYER_TOTEM_UPDATE" then CP.UpdateTotems() return end
        if event == "PLAYER_ENTERING_WORLD" then CP.Refresh() return end
        if event == "PLAYER_REGEN_ENABLED" then
            if totemsPending then totemsPending = false; CP.LayoutTotems() else CP.UpdateTotems() end
        end
        if not EV.IsComboEvent(event, unit, token) then return end
        CP.UpdateCombo()
    end)
    CP.Refresh()
end
