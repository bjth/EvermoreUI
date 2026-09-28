if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Breakdown.lua
--  One source's spells, in a panel beside the window it was opened from:
--  a row per spell with its icon, name and amount (per second, share),
--  a red edge on avoidable or deadly hits. It follows its window's mode and
--  fight, and refreshes with it.
--
--  The game gives a breakdown for a GUID it can read from us. In combat a
--  source's GUID can be secret (yours never is), and then the panel says
--  the breakdown fills in when combat ends, which it does on its own.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
local M = ns.module
if not (EV and M) then return end
local L, T, U = EV.L, EV.Theme, EV.UI
local floor, max, min = math.floor, math.max, math.min

local B = { rows = {}, offset = 0 }
ns.Breakdown = B

local TITLE, ROW, WIDTH, HEIGHT = 22, 18, 280, 240

local function Build()
    local f = CreateFrame("Frame", "EvermoreUIMeterBreakdown", UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    U.Surface(f, "window", 0.95)

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE)
    bar.bg = T.Fill(bar, "BACKGROUND", "titleBar")
    bar.bg:SetAllPoints()
    bar.rule = bar:CreateTexture(nil, "BORDER")
    bar.rule:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    bar.rule:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
    f.bar = bar

    f.title = T.Text(bar, "small", "text", true)
    f.title:SetPoint("LEFT", bar, "LEFT", 6, 0)
    local close = U.CloseButton(bar, TITLE, function() B:Close() end)
    close:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    f.title:SetPoint("RIGHT", close, "LEFT", -6, 0)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    body:SetClipsChildren(true)
    f.body = body

    f.note = T.Text(body, "small", "textMuted", false, "CENTER")
    f.note:SetPoint("LEFT", body, "LEFT", 8, 0)
    f.note:SetPoint("RIGHT", body, "RIGHT", -8, 0)
    f.note:SetWordWrap(true)

    f:SetScript("OnMouseWheel", function(_, delta)
        local n = B.spells and #B.spells or 0
        B.offset = max(0, min(B.offset - delta, max(0, n - B:Visible())))
        B:Refresh()
    end)
    local function Paint()
        bar.bg:SetColorTexture(T.RGBA("titleBar"))
        bar.rule:SetColorTexture(T.RGBA("divider"))
        bar.rule:SetHeight(EV.Pixel:Line(bar))
    end
    Paint()
    T.Watch(f, Paint)
    tinsert(UISpecialFrames, "EvermoreUIMeterBreakdown")
    return f
end

function B:Visible()
    return max(0, floor(((self.frame.body:GetHeight() or 0) + 1) / (ROW + 1)))
end

function B:Row(n)
    local row = self.rows[n]
    if row then return row end
    local body = self.frame.body
    row = CreateFrame("Frame", nil, body)
    row:SetHeight(ROW)
    row.track = T.Fill(row, "BACKGROUND", "surfaceSunk", 0.6) -- content colour: the track under a value
    row.track:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW, ROW)
    row.icon:SetPoint("LEFT")
    row.icon:SetTexCoord(EV.Icons:Coords())
    row.flag = T.Fill(row, "OVERLAY", "danger")
    row.flag:SetPoint("TOPLEFT"); row.flag:SetPoint("BOTTOMLEFT"); row.flag:SetWidth(2)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
    row.bar:SetMinMaxValues(0, 1)
    local text = CreateFrame("Frame", nil, row)
    text:SetAllPoints(row.bar)
    text:SetFrameLevel(row.bar:GetFrameLevel() + 2)
    row.name = T.Text(text, "small", "text")
    row.name:SetPoint("LEFT", text, "LEFT", 4, 0)
    row.value = T.Text(text, "small", "text", false, "RIGHT")
    row.value:SetPoint("RIGHT", text, "RIGHT", -4, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    self.rows[n] = row
    return row
end

--- Open the breakdown of `src` from window `win`, beside it.
function B:Open(win, src)
    self.frame = self.frame or Build()
    self.win, self.src, self.offset = win, src, 0
    local f = self.frame
    f:ClearAllPoints()
    local right = (win.frame:GetRight() or 0) + WIDTH < (UIParent:GetRight() or 0)
    if right then
        f:SetPoint("TOPLEFT", win.frame, "TOPRIGHT", 6, 0)
    else
        f:SetPoint("TOPRIGHT", win.frame, "TOPLEFT", -6, 0)
    end
    local ok = pcall(f.title.SetText, f.title, ns.Name(src.name))
    if not ok then f.title:SetText(L["Breakdown"]) end
    local r, g, b = EV.Palette.ClassRGB(src.classFilename)
    if r then f.title:SetTextColor(r, g, b) else f.title:SetTextColor(T.RGBA("text")) end
    f:Show()
    self.dirty = true
    self:Tick()
end

function B:Close()
    if self.frame then self.frame:Hide() end
    self.win, self.src = nil, nil
end

function B:MarkDirty()
    if self.frame and self.frame:IsShown() then self.dirty = true end
end

function B:Tick()
    if self.dirty and self.frame and self.frame:IsShown() then
        self.dirty = false
        self:Refresh()
    end
end

-- The source again, fresh from its window's current data, so the panel
-- follows it as the fight goes on. Matched by GUID when readable.
local function Current(win, src)
    local guid = src.sourceGUID
    if not EV.Usable(guid) then return src end
    for _, s in ipairs(win.data or {}) do
        if EV.Usable(s.sourceGUID) and s.sourceGUID == guid then return s end
    end
    return src
end

function B:Refresh()
    local win, f = self.win, self.frame
    if not (win and f) then return end
    self.src = Current(win, self.src)
    local source, reason = ns.Source(win, self.src)
    local spells = source and source.combatSpells or {}

    -- Out of combat the amounts are readable: biggest first.
    local readable = true
    for _, s in ipairs(spells) do
        if not EV.Usable(s.totalAmount) then readable = false; break end
    end
    if readable and #spells > 1 then
        table.sort(spells, function(a, b) return a.totalAmount > b.totalAmount end)
    end
    self.spells = spells

    local total = source and source.totalAmount
    local maxAmount = source and source.maxAmount
    local mode = win.db.mode
    local visible = self:Visible()
    self.offset = max(0, min(self.offset, max(0, #spells - visible)))
    local texture = win.texture
    local cr, cg, cb = EV.Palette.ClassRGB(self.src.classFilename)
    if not cr then cr, cg, cb = T.RGBA("accent") end

    for slot = 1, visible do
        local spell = spells[self.offset + slot]
        local row = self.rows[slot]
        if spell then
            row = self:Row(slot)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.body, "TOPLEFT", 0, -(slot - 1) * (ROW + 1))
            row:SetPoint("TOPRIGHT", f.body, "TOPRIGHT", 0, -(slot - 1) * (ROW + 1))
            row.bar:SetStatusBarTexture(texture)
            row.bar:SetStatusBarColor(cr, cg, cb, 0.7)
            local amount = spell.totalAmount
            pcall(row.bar.SetMinMaxValues, row.bar, 0, type(maxAmount) == "nil" and 1 or maxAmount)
            pcall(row.bar.SetValue, row.bar, type(amount) == "nil" and 0 or amount)

            local id = spell.spellID
            local icon = EV.Usable(id) and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
            row.icon:SetTexture(icon or 134400)
            local name = EV.Usable(id) and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if not name and EV.Usable(spell.creatureName) and spell.creatureName ~= "" then name = spell.creatureName end
            row.name:SetText(name or L["Unknown"])

            local deadly = EV.Usable(spell.isDeadly) and spell.isDeadly
            local avoidable = EV.Usable(spell.isAvoidable) and spell.isAvoidable
            row.flag:SetShown((deadly or avoidable) and true or false)

            local main, paren = spell.totalAmount, spell.amountPerSecond
            if ns.PER_SECOND_FIRST[mode] then main, paren = spell.amountPerSecond, spell.totalAmount end
            if ns.NO_PER_SECOND[mode] then paren = nil end
            ns.SetValueText(row.value, main, paren, ns.Share(spell.totalAmount, total))
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    for slot = visible + 1, #self.rows do self.rows[slot]:Hide() end

    if not source then
        f.note:SetText(reason or "")
    elseif #spells == 0 then
        f.note:SetText(L["Nothing to show for this one yet."])
    else
        f.note:SetText("")
    end
end
