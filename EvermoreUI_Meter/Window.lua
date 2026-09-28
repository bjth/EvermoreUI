if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Window.lua
--  A meter window: a title bar (the mode, the fight, how long it lasted, a
--  menu) over rows, one per source, in the game's order.
--
--    [ Damage Done · Current            1:42  v ]
--    [ 1. Name                 12.4K (1.1K)     ]  <- a bar in the class
--    [ 2. Name                  9.8K (902)      ]     colour on a sunk track
--
--  Click the mode for the mode menu, the fight for the fight menu, the
--  chevron for report / reset / settings. Click a row for its breakdown;
--  right-click one for the mode menu. The mouse wheel scrolls. Size and
--  place come from the suite's edit mode (EV.Movers) and the options page.
--
--  Rows are a small pool, reused on every refresh; nothing is created per
--  update. Secret values go straight into the widgets (see Meter.lua).
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
local M = ns.module
if not (EV and M) then return end
local L, T, U = EV.L, EV.Theme, EV.UI
local floor, max, min = math.floor, math.max, math.min

local TITLE = 22       -- the title bar
local ICON_GAP = 4     -- between the icon and the name

local Window = {}
Window.__index = Window

local CLASS_ICON = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

--------------------------------------------------------------------------------
--  Building
--------------------------------------------------------------------------------
local function TitleButton(parent, token)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(TITLE)
    b.text = T.Text(b, "small", token, token == "text")
    b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(T.RGBA("accent")) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(T.RGBA(self.token)) end)
    b.token = token
    function b:SetLabel(s)
        self.text:SetText(s or "")
        self:SetWidth(max(8, self.text:GetStringWidth()))
    end
    return b
end

function ns.CreateWindow(i)
    local w = setmetatable({ index = i, rows = {}, offset = 0, dirty = true }, Window)
    w.db = M.db.windows[i]

    local f = CreateFrame("Frame", "EvermoreUIMeter" .. i, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:Hide()
    w.frame = f
    -- The window Look, its fill at the window's own opacity setting.
    f.bg, w.paintSurface = U.Surface(f, "window", function() return w.db.opacity or 0.9 end)

    -- The title bar.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE)
    bar.bg = T.Fill(bar, "BACKGROUND", "titleBar")
    bar.bg:SetAllPoints()
    bar.rule = bar:CreateTexture(nil, "BORDER")
    bar.rule:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    bar.rule:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
    w.bar = bar

    w.modeButton = TitleButton(bar, "text")
    w.modeButton:SetPoint("LEFT", bar, "LEFT", 6, 0)
    w.modeButton:SetScript("OnClick", function(self) w:ModeMenu(self) end)

    w.dot = T.Text(bar, "small", "textMuted")
    w.dot:SetPoint("LEFT", w.modeButton, "RIGHT", 4, 0)
    w.dot:SetText("·")

    w.fightButton = TitleButton(bar, "textMuted")
    w.fightButton:SetPoint("LEFT", w.dot, "RIGHT", 4, 0)
    w.fightButton:SetScript("OnClick", function(self) w:FightMenu(self) end)

    w.menuButton = U.IconButton(bar, { size = TITLE - 4, glyph = "chevron", tooltip = L["Report, reset and settings"] },
        function(self) w:MainMenu(self) end)
    w.menuButton:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

    w.clock = T.Text(bar, "small", "textMuted", false, "RIGHT")
    w.clock:SetPoint("RIGHT", w.menuButton, "LEFT", -6, 0)

    -- The rows' area; rows past its bottom are clipped.
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    body:SetClipsChildren(true)
    w.body = body

    w.empty = T.Text(body, "small", "textMuted", false, "CENTER")
    w.empty:SetPoint("LEFT", body, "LEFT", 8, 0)
    w.empty:SetPoint("RIGHT", body, "RIGHT", -8, 0)
    w.empty:SetWordWrap(true)

    f:SetScript("OnMouseWheel", function(_, delta) w:Scroll(delta) end)
    f:SetScript("OnShow", function() w.dirty = true end)
    f:SetScript("OnSizeChanged", function() w.dirty = true end)

    T.Watch(f, function() w:Paint() end)

    EV.Movers:Register(f, "Meter" .. i, L["Damage Meter"] .. " " .. i,
        { "BOTTOMRIGHT", "BOTTOMRIGHT", -20 - (i - 1) * 250, 260 }, {
            group = L["Damage Meter"], page = "meter",
            getSize = function() return w.db.width, w.db.height end,
            setSize = function(width, height)
                if width then w.db.width = floor(width + 0.5) end
                if height then w.db.height = floor(height + 0.5) end
                w:Apply()
            end,
            isDisabled = function() return not w:Wanted() end,
        })
    return w
end

--------------------------------------------------------------------------------
--  Settings
--------------------------------------------------------------------------------
function Window:Wanted()
    return M:IsEnabled() and self.index <= (M.db.count or 1)
end

function Window:Paint()
    if self.paintSurface then self.paintSurface() end
    self.bar.bg:SetColorTexture(T.RGBA("titleBar"))
    self.bar.rule:SetColorTexture(T.RGBA("divider"))
    self.bar.rule:SetHeight(EV.Pixel:Line(self.bar))
end

function Window:Apply()
    self.db = M.db.windows[self.index]
    local f = self.frame
    f:SetSize(self.db.width, self.db.height)
    self.texture = EV.Media:Fetch("statusbar", self.db.texture ~= "" and self.db.texture or nil)
    for _, row in ipairs(self.rows) do self:StyleRow(row) end
    self:Paint()
    EV.Movers:Apply("Meter" .. self.index)
    local show = self:Wanted() and (not M.db.hidden or EV.Movers:IsUnlocked())
    f:SetShown(show)
    if not show and ns.Breakdown and ns.Breakdown.win == self then ns.Breakdown:Close() end
    self.dirty = true
end

--------------------------------------------------------------------------------
--  Rows
--------------------------------------------------------------------------------
function Window:StyleRow(row)
    local h, size = self.db.barHeight, self.db.textSize
    row:SetHeight(h)
    row.bar:SetStatusBarTexture(self.texture)
    local font = T.FontPath()
    row.name:SetFont(font, size, "")
    row.value:SetFont(font, size, "")
    row.icon:SetSize(h, h)
    row.track:SetColorTexture(T.RGBA("surfaceSunk", 0.6)) -- content colour: the track under a value
end

function Window:Row(n)
    local row = self.rows[n]
    if row then return row end
    row = CreateFrame("Button", nil, self.body)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT")
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(0)
    local text = CreateFrame("Frame", nil, row)
    text:SetAllPoints(row.bar)
    text:SetFrameLevel(row.bar:GetFrameLevel() + 2)
    row.name = T.Text(text, "small", "text")
    row.name:SetPoint("LEFT", text, "LEFT", 4, 0)
    row.value = T.Text(text, "small", "text", false, "RIGHT")
    row.value:SetPoint("RIGHT", text, "RIGHT", -4, 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row:SetScript("OnEnter", function(r) self:RowTooltip(r) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(r, button)
        if button == "RightButton" then
            self:ModeMenu(self.modeButton)
        elseif r.src and ns.Breakdown then
            ns.Breakdown:Open(self, r.src)
        end
    end)
    self.rows[n] = row
    self:StyleRow(row)
    return row
end

function Window:SetRow(row, src, rank)
    local db, mode = self.db, self.db.mode
    row.src = src

    -- The icon: the spec's, or the class's; none for enemy sources.
    local iconShown = false
    if db.icons and not ns.NO_ICON[mode] then
        local spec = src.specIconID
        if EV.Usable(spec) and spec and spec ~= 0 then
            row.icon:SetTexture(spec)
            row.icon:SetTexCoord(EV.Icons:Coords())
            iconShown = true
        elseif EV.Usable(src.classFilename) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[src.classFilename] then
            local c = CLASS_ICON_TCOORDS[src.classFilename]
            row.icon:SetTexture(CLASS_ICON)
            row.icon:SetTexCoord(c[1], c[2], c[3], c[4])
            iconShown = true
        end
    end
    row.icon:SetShown(iconShown)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("TOPRIGHT", row, "TOPRIGHT")
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT")
    row.bar:SetPoint("LEFT", row, "LEFT", iconShown and (db.barHeight + ICON_GAP) or 0, 0)

    -- The bar: the game's own maximum and amount, straight in.
    -- Nil checks by type(): these can be secret, and `x or y` tests them.
    local top, amount = self.max, src.totalAmount
    pcall(row.bar.SetMinMaxValues, row.bar, 0, type(top) == "nil" and 1 or top)
    pcall(row.bar.SetValue, row.bar, type(amount) == "nil" and 0 or amount)
    local r, g, b
    if db.classColours then r, g, b = EV.Palette.ClassRGB(src.classFilename) end
    if not r then
        local enemy = ns.TYPE.EnemyDamageTaken == mode
        r, g, b = T.RGBA(enemy and "danger" or "accent")
    end
    row.bar:SetStatusBarColor(r, g, b, 0.85)

    -- Rank and name.
    local name = ns.Name(src.name)
    local ok
    if db.rank then ok = pcall(row.name.SetFormattedText, row.name, "%d. %s", rank, name)
    else ok = pcall(row.name.SetText, row.name, name) end
    if not ok then pcall(row.name.SetText, row.name, name) end

    -- The value: the main number, the other in brackets, the share once
    -- it can be worked out.
    local total, perSecond = src.totalAmount, src.amountPerSecond
    local main, paren = total, perSecond
    if ns.PER_SECOND_FIRST[mode] then main, paren = perSecond, total end
    if ns.NO_PER_SECOND[mode] then paren = nil end
    local pct
    if db.numbers == "minimal" then paren = nil
    elseif db.numbers == "complete" then pct = ns.Share(total, self.total) end
    ns.SetValueText(row.value, main, paren, pct)
end

function Window:RowTooltip(row)
    local src = row.src
    if not src then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    pcall(GameTooltip.AddLine, GameTooltip, ns.Name(src.name), 1, 1, 1)
    pcall(GameTooltip.AddDoubleLine, GameTooltip, ns.TypeName(self.db.mode), ns.Short(src.totalAmount), 0.8, 0.8, 0.8, 1, 1, 1)
    if not ns.NO_PER_SECOND[self.db.mode] then
        pcall(GameTooltip.AddDoubleLine, GameTooltip, L["Per second"], ns.Short(src.amountPerSecond), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    local pct = ns.Share(src.totalAmount, self.total)
    if pct then GameTooltip:AddDoubleLine(L["Share"], pct .. "%", 0.8, 0.8, 0.8, 1, 1, 1) end
    GameTooltip:AddLine(L["Click for a breakdown. Right-click to change what this window shows."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
--  Refresh: the session into the rows
--------------------------------------------------------------------------------
function Window:Visible()
    local h, gap = self.db.barHeight, self.db.spacing
    local height = self.body:GetHeight() or 0
    return max(0, floor((height + gap) / (h + gap)))
end

function Window:Scroll(delta)
    local n = self.data and #self.data or 0
    self.offset = max(0, min(self.offset - delta, max(0, n - self:Visible())))
    self:Refresh()
end

local function FightLabel(win)
    if win.sessionID then
        for _, s in ipairs(ns.Fights()) do
            if s.sessionID == win.sessionID then
                return EV.Usable(s.name) and s.name ~= "" and s.name or L["Fight"] .. " " .. win.sessionID
            end
        end
        return L["Fight"] .. " " .. win.sessionID
    end
    return win.db.session == "overall" and L["Overall"] or L["Current"]
end

function Window:Refresh()
    if not self.frame:IsShown() then return end
    self.modeButton:SetLabel(ns.TypeName(self.db.mode))
    self.fightButton:SetLabel(FightLabel(self))

    local available, reason = ns.Available()
    local s = available and ns.Session(self) or nil
    local sources = s and s.combatSources or {}
    self.data, self.max, self.total = sources, s and s.maxAmount, s and s.totalAmount
    self.clock:SetText(s and ns.Clock(s.durationSeconds) or "")

    local n = #sources
    local visible = self:Visible()
    self.offset = max(0, min(self.offset, max(0, n - visible)))

    -- Your own row stays in view where the mode keeps you: pinned to the
    -- edge you've scrolled it past.
    local mine
    if self.db.showSelf and ns.KEEP_SELF[self.db.mode] then
        for i, src in ipairs(sources) do
            if src.isLocalPlayer then mine = i; break end
        end
    end

    local h, gap = self.db.barHeight, self.db.spacing
    for slot = 1, visible do
        local index = self.offset + slot
        if mine and slot == visible and mine > self.offset + visible then index = mine end
        if mine and slot == 1 and self.offset > 0 and mine <= self.offset then index = mine end
        local src = sources[index]
        if src then
            local row = self:Row(slot)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", self.body, "TOPLEFT", 0, -(slot - 1) * (h + gap))
            row:SetPoint("TOPRIGHT", self.body, "TOPRIGHT", 0, -(slot - 1) * (h + gap))
            self:SetRow(row, src, index)
            row:Show()
        elseif self.rows[slot] then
            self.rows[slot]:Hide()
            self.rows[slot].src = nil
        end
    end
    for slot = visible + 1, #self.rows do
        self.rows[slot]:Hide()
        self.rows[slot].src = nil
    end

    if not available then
        self.empty:SetText(reason or L["The game's meter isn't available here."])
    elseif n == 0 then
        self.empty:SetText(L["Nothing yet. Pull something."])
    else
        self.empty:SetText("")
    end
end

--------------------------------------------------------------------------------
--  Menus (the suite's shared menu, EV.UI.GetMenu)
--------------------------------------------------------------------------------
function Window:ModeMenu(owner)
    local list = {}
    for _, cat in ipairs(ns.CATEGORIES) do
        list[#list + 1] = { header = cat.name }
        for _, t in ipairs(cat.types) do
            if t then list[#list + 1] = { value = t, text = ns.TypeName(t) } end
        end
    end
    U.GetMenu():Open(owner, list, self.db.mode, function(v)
        self.db.mode = v
        self.offset = 0
        self.dirty = true
        if ns.Breakdown then ns.Breakdown:Close() end
    end)
end

function Window:FightMenu(owner)
    local list = {
        { value = "current", text = L["Current fight"] },
        { value = "overall", text = L["Overall"] },
    }
    local fights = ns.Fights()
    if #fights > 0 then
        list[#list + 1] = { header = L["Earlier fights"] }
        for _, s in ipairs(fights) do
            local name = EV.Usable(s.name) and s.name ~= "" and s.name or (L["Fight"] .. " " .. s.sessionID)
            local clock = ns.Clock(s.durationSeconds)
            list[#list + 1] = { value = "id:" .. s.sessionID, text = clock and (name .. "  " .. clock) or name }
        end
    end
    local current = self.sessionID and ("id:" .. self.sessionID) or self.db.session
    U.GetMenu():Open(owner, list, current, function(v)
        local id = type(v) == "string" and tonumber(v:match("^id:(%d+)$"))
        if id then
            self.sessionID = id
        else
            self.sessionID = nil
            self.db.session = v
        end
        self.offset = 0
        self.dirty = true
        if ns.Breakdown then ns.Breakdown:Close() end
    end)
end

StaticPopupDialogs["EVERMOREUI_METER_RESET"] = {
    text = L["Clear every fight from the damage meter?"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then C_DamageMeter.ResetAllCombatSessions() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Window:MainMenu(owner)
    local list = { { header = L["Report to"] } }
    for _, c in ipairs(ns.REPORT_CHANNELS or {}) do
        list[#list + 1] = { value = "report:" .. c.value, text = c.text }
    end
    list[#list + 1] = { separator = true }
    list[#list + 1] = { value = "reset", text = L["Reset all fights"] }
    list[#list + 1] = { value = "settings", text = L["Settings"] }
    U.GetMenu():Open(owner, list, nil, function(v)
        local channel = type(v) == "string" and v:match("^report:(.+)$")
        if channel then
            if ns.Report then ns.Report(self, channel) end
        elseif v == "reset" then
            StaticPopup_Show("EVERMOREUI_METER_RESET")
        elseif v == "settings" then
            local open = EV.Options and EV.Options.Frame and EV.Options:Frame()
            if not (open and open:IsShown()) then EV:OpenOptions() end
            if EV.Options and EV.Options.ShowPage then EV.Options:ShowPage("meter") end
        end
    end)
end
