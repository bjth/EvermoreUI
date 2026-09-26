if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  LootLuck.lua
--  The Loot Luck window: your characters side by side, luckiest first.
--  Numbers from LootStats.lua; names and classes from EV.Alts. /evui luck.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme

local window, scroll, lines = nil, nil, {}
local onlyFaction = false

local COLS = {
    { key = "name",   title = L["Character"], w = 150, justify = "LEFT" },
    { key = "won",    title = L["Won"],       w = 70 },
    { key = "rate",   title = L["Win rate"],  w = 70 },
    { key = "need",   title = L["Need"],      w = 70 },
    { key = "greed",  title = L["Greed"],     w = 70 },
    { key = "passed", title = L["Passed"],    w = 60 },
    { key = "avg",    title = L["Avg roll"],  w = 70 },
    { key = "best",   title = L["Best win"],  w = 170, justify = "LEFT" },
}

local function Quality(q)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    local name = _G["ITEM_QUALITY" .. tostring(q) .. "_DESC"] or tostring(q)
    if c then return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name) end
    return name
end

local function Tip(row)
    local s = row.stats
    GameTooltip:SetOwner(row.frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(EV.Alts:Coloured(row.entry.info))
    local qs = {}
    local function seen(t) for q in pairs(t or {}) do qs[q] = true end end
    for _, k in ipairs({ "need", "greed", "de" }) do seen(s[k] and s[k].won); seen(s[k] and s[k].lost) end
    seen(s.pass)
    local order = {}
    for q in pairs(qs) do order[#order + 1] = q end
    table.sort(order, function(a, b) return a > b end)
    for _, q in ipairs(order) do
        local function wl(k) return ("%d-%d"):format((s[k].won[q] or 0), (s[k].lost[q] or 0)) end
        GameTooltip:AddDoubleLine(Quality(q),
            ("%s %s   %s %s   %s %d"):format(L["need"], wl("need"), L["greed"], wl("greed"), L["passed"], s.pass[q] or 0),
            1, 1, 1, 0.85, 0.85, 0.85)
    end
    local sum = row.sum
    if (sum.hundreds or 0) > 0 then
        GameTooltip:AddLine((L["Rolled a 100 %d times."]):format(sum.hundreds), 0.9, 0.8, 0.4)
    end
    GameTooltip:AddLine(L["Won and lost counts are need and greed rolls; wins against losses make the win rate."], 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function Line(i)
    local f = lines[i]
    if f then return f end
    f = CreateFrame("Frame", nil, scroll.content)
    f:SetHeight(24)
    f:EnableMouse(true)
    f.bg = T.Fill(f, "BACKGROUND", "surfaceSunk", (i % 2 == 1) and 0.25 or 0.5)
    f.bg:SetAllPoints()
    f.cells = {}
    local x = 8
    for c, col in ipairs(COLS) do
        local fs = T.Text(f, "body", "text")
        fs:SetPoint("LEFT", f, "LEFT", x, 0)
        fs:SetWidth(col.w - 6)
        fs:SetJustifyH(col.justify or "CENTER")
        fs:SetWordWrap(false)
        f.cells[c] = fs
        x = x + col.w
    end
    f:SetScript("OnEnter", function(self) if self.row then Tip(self.row) end end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lines[i] = f
    return f
end

local function Pct(v) return v and ("%d%%"):format(math.floor(v * 100 + 0.5)) or "-" end

local function Fill()
    local board = ns.lootStats.Board()
    local myFaction = UnitFactionGroup("player")
    local rows = {}
    for _, r in ipairs(board) do
        if not onlyFaction or r.entry.info.faction == myFaction then rows[#rows + 1] = r end
    end
    local width = scroll.content:GetWidth()
    for i, r in ipairs(rows) do
        local f = Line(i)
        r.frame = f
        f.row = r
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
        f:SetWidth(width)
        local s = r.sum
        local best = s.best and s.best.link or "-"
        local vals = {
            ("%d. %s"):format(i, EV.Alts:Coloured(r.entry.info)),
            ("%d / %d"):format(s.won, s.rolled),
            Pct(s.rate),
            ("%d-%d"):format(s.needWon, s.needLost),
            ("%d-%d"):format(s.greedWon + s.deWon, s.greedLost + s.deLost),
            tostring(s.passed),
            s.avg and ("%.1f"):format(s.avg) or "-",
            best,
        }
        for c, v in ipairs(vals) do f.cells[c]:SetText(v) end
        f:Show()
    end
    for i = #rows + 1, #lines do lines[i]:Hide(); lines[i].row = nil end
    scroll:SetContentHeight(#rows * 24 + 4)

    local top = rows[1]
    if top and top.sum.rate then
        window.banner:SetText((L["Luckiest: %s, winning %s of their rolls."]):format(EV.Alts:Coloured(top.entry.info), Pct(top.sum.rate)))
    elseif #rows > 0 then
        window.banner:SetText(L["Nobody has won or lost a roll yet. Get rolling."])
    else
        window.banner:SetText(L["No loot rolls recorded yet. Every character you play from now on joins the board after their first roll."])
    end
end

local function Build()
    if window then return window end
    local W = EV.UI
    local width = 0
    for _, c in ipairs(COLS) do width = width + c.w end
    window = W.Window("EvermoreUILootLuck", { title = L["Loot Luck"], width = width + 40, height = 440 })
    window:SetPoint("CENTER")
    local body = window.body

    window.banner = T.Text(body, "label", "title", true)
    window.banner:SetPoint("TOPLEFT", 14, -12)
    window.banner:SetPoint("RIGHT", -14, 0)
    window.banner:SetWordWrap(true)

    local header = CreateFrame("Frame", nil, body)
    header:SetPoint("TOPLEFT", 12, -44)
    header:SetPoint("RIGHT", -12, 0)
    header:SetHeight(20)
    local x = 8
    for _, col in ipairs(COLS) do
        local fs = T.Text(header, "caption", "textDisabled", true)
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(col.w - 6)
        fs:SetJustifyH(col.justify or "CENTER")
        fs:SetText(col.title:upper())
        x = x + col.w
    end

    scroll = W.Scroll(body)
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 52)

    local cb = W.Checkbox(body, L["Only this faction"], function() return onlyFaction end,
        function(v) onlyFaction = v and true or false; Fill() end)
    cb:SetPoint("BOTTOMLEFT", 14, 18)
    local reset = W.ConfirmButton(body, L["Reset this character"], 170, function()
        wipe(EV.DB:GetCharData("lootStats"))
        Fill()
    end)
    reset:SetPoint("BOTTOMRIGHT", -12, 12)

    window:HookScript("OnShow", function() C_Timer.After(0, Fill) end)
    return window
end

function ns.ShowLuck()
    Build()
    if window:IsShown() then Fill() else window:Show() end
end
