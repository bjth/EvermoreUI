if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Characters.lua
--  Your characters in one window (/evui alts):
--
--    Characters   who they are, their gold, rested XP, professions and when
--                 you last played them, with the total gold at the foot.
--                 Hover one for its zone, time played, mail and how fresh
--                 each snapshot is. Forget a character you've deleted.
--    Inventory    any character's bags, bank or mail, or the account bank,
--                 as they were when last seen: browse them from anywhere.
--    Find         type part of an item's name: every character holding it,
--                 and where. Hovering a result shows the item's tooltip,
--                 counts and all.
--
--  The data is EV.Alts (EvermoreUI/Core/Alts.lua): snapshots taken as you
--  play each character. Characters you haven't logged in since installing
--  EvermoreUI aren't known yet, and a bank is only known once you've
--  visited it.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local floor, max, min = math.floor, math.max, math.min

local M = EV:NewModule("Characters", {})
M.title = "Characters"
M.description = "Your characters side by side: gold, rested XP, professions, and a search for any item across their bags, banks and mail. /evui alts"
ns.characters = M

local A        -- EV.Alts, once the core has it
local window, tabs, pages = nil, nil, {}
local tab = "chars"
local ROW = 26

local function Gold(copper)
    copper = copper or 0
    -- Whole gold once there's any: copper and silver are noise in a list.
    if copper >= 10000 then copper = floor(copper / 10000) * 10000 end
    return EV:FormatMoney(copper)
end

local function Muted(s) return "|cff" .. T.Hex("textMuted") .. s .. "|r" end

--------------------------------------------------------------------------------
--  Characters tab
--------------------------------------------------------------------------------
local COLS = {
    { key = "name",  title = L["Character"],   w = 190, justify = "LEFT" },
    { key = "gold",  title = L["Gold"],        w = 120, justify = "RIGHT" },
    { key = "rest",  title = L["Rested"],      w = 80 },
    { key = "profs", title = L["Professions"], w = 190, justify = "LEFT" },
    { key = "seen",  title = L["Last played"], w = 110 },
    { key = "x",     title = "",               w = 76 },
}
local function Width(cols) local w = 0 for _, c in ipairs(cols) do w = w + c.w end return w end

local function Rested(info)
    local cap = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
    if (info.level or 0) >= cap then return Muted("-") end
    if not (info.rested and info.xpMax and info.xpMax > 0) then return Muted("?") end
    local pct = floor(info.rested / info.xpMax * 100 + 0.5)
    local token = pct >= 150 and "success" or pct > 0 and "text" or "textMuted"
    return "|cff" .. T.Hex(token) .. pct .. "%|r"
end

local function Profs(info)
    local out = {}
    for _, p in ipairs(info.profs or {}) do
        out[#out + 1] = ("|T%s:14:14:0:0:64:64:5:59:5:59|t %d"):format(tostring(p.icon or 134400), p.rank or 0)
    end
    return #out > 0 and table.concat(out, "   ") or Muted("-")
end

local function Tip(owner, e)
    local info, data = e.info, e.data
    local tt = GameTooltip
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    tt:SetText(A:Coloured(info))
    local mr, mg, mb = T.RGBA("textMuted")
    local tr, tg, tb = T.RGBA("text")
    local function Row(l, r) tt:AddDoubleLine(l, r, mr, mg, mb, tr, tg, tb) end
    local cls = info.class and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[info.class]) or info.class
    Row(L["Level"], ("%d %s"):format(info.level or 0, cls or ""))
    if info.realm then Row(L["Realm"], info.realm .. (info.faction and ("  " .. info.faction) or "")) end
    if info.zone then Row(L["Last seen in"], info.zone) end
    if info.guild then Row(L["Guild"], info.guild) end
    Row(L["Time played"], info.played and SecondsToTime(info.played) or Muted(L["type /played on them"]))
    for _, p in ipairs(info.profs or {}) do
        Row(("|T%s:14|t %s"):format(tostring(p.icon or 134400), p.name), ("%d / %d"):format(p.rank or 0, p.max or 0))
    end
    tt:AddLine(" ")
    local at = type(data.items) == "table" and data.items.at or {}
    Row(L["Bags"], A.Ago(at.bags))
    Row(L["Bank"], at.bank and A.Ago(at.bank) or Muted(L["visit a banker to record it"]))
    local m = type(data.mail) == "table" and data.mail or nil
    if m and (m.count or 0) > 0 then
        local left = m.expires and max(0, floor((m.expires - time()) / 86400)) or nil
        Row(L["Mail"], (L["%d |4letter:letters;"]):format(m.count)
            .. (left and ("  " .. (L["first runs out in %d |4day:days;"]):format(left)) or ""))
        if (m.money or 0) > 0 then Row(L["Gold in the mail"], Gold(m.money)) end
    else
        Row(L["Mail"], at.mail and L["empty"] or Muted(L["open the mailbox to record it"]))
    end
    tt:Show()
end

local function CharLine(page, i)
    local f = page.lines[i]
    if f then return f end
    f = CreateFrame("Frame", nil, page.scroll.content)
    f:SetHeight(ROW)
    f:EnableMouse(true)
    f.bg = T.Fill(f, "BACKGROUND", "surfaceSunk", (i % 2 == 1) and 0.25 or 0.5)
    f.bg:SetAllPoints()
    f.cells = {}
    local x = 8
    for c, col in ipairs(COLS) do
        if col.key ~= "x" then
            local fs = T.Text(f, "body", "text")
            fs:SetPoint("LEFT", f, "LEFT", x, 0)
            fs:SetWidth(col.w - 10)
            fs:SetJustifyH(col.justify or "CENTER")
            fs:SetWordWrap(false)
            f.cells[c] = fs
        end
        x = x + col.w
    end
    f.forget = EV.UI.ConfirmButton(f, L["Forget"], 70, function()
        if f.entry and A:Forget(f.entry.key) then M:Fill() end
    end, L["Sure?"])
    f.forget:SetPoint("RIGHT", -4, 0)
    f.forget:SetHeight(20)
    f.forget:SetTooltip(L["Forget this character"], L["For a character you've deleted or moved. Everything recorded about it goes; logging in on it records it again."])
    f:SetScript("OnEnter", function(self) if self.entry then Tip(self, self.entry) end end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.lines[i] = f
    return f
end

local function FillChars(page)
    local total, list, bank = A:Money()
    for i, e in ipairs(list) do
        local f = CharLine(page, i)
        f.entry = e
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        f:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)
        local info = e.info
        f.cells[1]:SetText(("%s  %s"):format(A:Coloured(info), Muted(tostring(info.level or "?"))))
        f.cells[2]:SetText(info.money and Gold(info.money) or Muted("?"))
        f.cells[3]:SetText(Rested(info))
        f.cells[4]:SetText(Profs(info))
        f.cells[5]:SetText(e.me and ("|cff" .. T.Hex("success") .. L["now"] .. "|r") or A.Ago(info.seen))
        f.forget:SetShown(not e.me)
        f:Show()
    end
    for i = #list + 1, #page.lines do page.lines[i]:Hide(); page.lines[i].entry = nil end
    page.scroll:SetContentHeight(#list * ROW + 4)
    local foot = (L["Total: %s across %d |4character:characters;"]):format(Gold(total), #list)
    if bank and bank > 0 then foot = foot .. Muted("  " .. (L["(%s of it in the account bank)"]):format(Gold(bank))) end
    page.footText = foot
end

--------------------------------------------------------------------------------
--  Find tab
--------------------------------------------------------------------------------
local names = {}        -- itemID -> { name, quality, icon } once the client knows it
local waiting = {}      -- itemID -> true while asked for
local query = ""

local function ItemData(id)
    local d = names[id]
    if d then return d end
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
    if name then
        d = { name = name, lower = name:lower(), quality = quality, icon = icon }
        names[id] = d
        return d
    end
    if not waiting[id] and C_Item.RequestLoadItemDataByID then
        waiting[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end

local function Where(c)
    local parts = {}
    for _, row in ipairs(c.chars) do
        parts[#parts + 1] = ("%s %d"):format(A:Coloured(row.entry.info), row.total)
    end
    if c.account > 0 then parts[#parts + 1] = Muted(L["Account bank"]) .. " " .. c.account end
    return table.concat(parts, ",  ")
end

local function FindLine(page, i)
    local f = page.lines[i]
    if f then return f end
    f = CreateFrame("Frame", nil, page.scroll.content)
    f:SetHeight(ROW)
    f:EnableMouse(true)
    f.bg = T.Fill(f, "BACKGROUND", "surfaceSunk", (i % 2 == 1) and 0.25 or 0.5)
    f.bg:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(20, 20)
    f.icon:SetPoint("LEFT", 8, 0)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.name = T.Text(f, "body", "text")
    f.name:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
    f.name:SetWidth(240)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.count = T.Text(f, "body", "text", true)
    f.count:SetPoint("LEFT", f.name, "RIGHT", 6, 0)
    f.count:SetWidth(50)
    f.count:SetJustifyH("RIGHT")
    f.where = T.Text(f, "body", "text")
    f.where:SetPoint("LEFT", f.count, "RIGHT", 16, 0)
    f.where:SetPoint("RIGHT", -8, 0)
    f.where:SetJustifyH("LEFT")
    f.where:SetWordWrap(false)
    f:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.lines[i] = f
    return f
end

local MAX_RESULTS = 200

local function FillFind(page)
    local q = query:lower()
    local rows, unknown = {}, 0
    if q ~= "" then
        for id in pairs(A:AllItemIDs()) do
            local d = ItemData(id)
            if not d then
                unknown = unknown + 1
            elseif d.lower:find(q, 1, true) then
                local c = A:Counts(id)
                if c and c.total > 0 then rows[#rows + 1] = { id = id, d = d, c = c } end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.c.total ~= b.c.total then return a.c.total > b.c.total end
        return a.d.name < b.d.name
    end)
    local shown = min(#rows, MAX_RESULTS)
    for i = 1, shown do
        local r = rows[i]
        local f = FindLine(page, i)
        f.id = r.id
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        f:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW)
        f.icon:SetTexture(r.d.icon or 134400)
        local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[r.d.quality or 1]
        f.name:SetText(qc and qc.hex and (qc.hex .. r.d.name .. "|r") or r.d.name)
        f.count:SetText(tostring(r.c.total))
        f.where:SetText(Where(r.c))
        f:Show()
    end
    for i = shown + 1, #page.lines do page.lines[i]:Hide(); page.lines[i].id = nil end
    page.scroll:SetContentHeight(shown * ROW + 4)
    if q == "" then
        page.footText = Muted(L["Type part of an item's name to see which of your characters has it."])
    elseif #rows == 0 then
        page.footText = (unknown > 0 and Muted(L["Nothing yet. Some item names are still loading; results fill in as they arrive."])
            or Muted(L["None of your characters has anything by that name."]))
    else
        local s = (L["%d |4item:items;"]):format(#rows)
        if #rows > MAX_RESULTS then s = s .. Muted("  " .. (L["(the first %d shown)"]):format(MAX_RESULTS)) end
        page.footText = s
    end
end

--------------------------------------------------------------------------------
--  Inventory tab: one character's bags, bank or mail (or the account bank)
--  from the last snapshot, as a grid of icons with counts.
--------------------------------------------------------------------------------
local ICON, GAP = 36, 4
local invChar, invPlace = nil, "bags"

local PLACE_NAMES = {
    { value = "bags",     text = L["Bags"] },
    { value = "bank",     text = L["Bank"] },
    { value = "mail",     text = L["Mail"] },
    { value = "equipped", text = L["Equipped"] },
    { value = "account",  text = L["Account bank"] },
}

local function InvButton(page, i)
    local b = page.lines[i]
    if b then return b end
    b = CreateFrame("Button", nil, page.scroll.content)
    b:SetSize(ICON, ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    T.TokenBorder(b, "border")
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(EV.Media:Fetch("font"), 12, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self)
        -- Shift-click links it in chat, as a bag slot would.
        if self.id and IsModifiedClick("CHATLINK") then
            local _, link = C_Item.GetItemInfo(self.id)
            if link then ChatEdit_InsertLink(link) end
        end
    end)
    page.lines[i] = b
    return b
end

local function InvSource()
    if invPlace == "account" then
        local ab = A:AccountBank()
        return ab and ab.items, ab and ab.at
    end
    local data = invChar and EV.DB:AllChars()[invChar]
    local items = type(data) == "table" and data.items
    if type(items) ~= "table" then return nil end
    return items[invPlace], type(items.at) == "table" and items.at[invPlace == "equipped" and "bags" or invPlace]
end

local function FillInv(page)
    if not invChar then invChar = EV.DB.charKey end
    page.who:Refresh()
    page.where:Refresh()
    page.who:SetDisabled(invPlace == "account")
    local src, at = InvSource()
    local list = {}
    for id, n in pairs(src or {}) do
        local d = ItemData(id)
        list[#list + 1] = { id = id, n = n, q = d and d.quality or 1, name = d and d.name or "" }
    end
    table.sort(list, function(a, b)
        if a.q ~= b.q then return a.q > b.q end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    local per = max(1, floor((page.scroll:GetWidth() - 16 + GAP) / (ICON + GAP)))
    for i, it in ipairs(list) do
        local b = InvButton(page, i)
        b.id = it.id
        local col, row = (i - 1) % per, floor((i - 1) / per)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", col * (ICON + GAP), -row * (ICON + GAP))
        b.icon:SetTexture(C_Item.GetItemIconByID(it.id) or 134400)
        b.count:SetText(it.n > 1 and tostring(it.n) or "")
        local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[it.q]
        if qc and it.q >= 2 then T.SetBorderColor(b, qc.r, qc.g, qc.b, 1) else T.SetBorderToken(b, "border") end
        b:Show()
    end
    for i = #list + 1, #page.lines do page.lines[i]:Hide(); page.lines[i].id = nil end
    local rows = math.ceil(#list / per)
    page.scroll:SetContentHeight(rows * (ICON + GAP) + 4)
    if not src then
        page.footText = Muted(invPlace == "bank" and L["Not seen yet: visit a banker on that character."]
            or invPlace == "mail" and L["Not seen yet: open the mailbox on that character."]
            or invPlace == "account" and L["Not seen yet: visit a banker."]
            or L["Not seen yet: log in on that character."])
    else
        page.footText = (L["%d different |4item:items;"]):format(#list) .. Muted("  " .. (L["as of %s"]):format(A.Ago(at)))
    end
end

--------------------------------------------------------------------------------
--  Window
--------------------------------------------------------------------------------
local function Page(parent, top)
    local p = CreateFrame("Frame", nil, parent)
    p:SetPoint("TOPLEFT", 12, top)
    p:SetPoint("BOTTOMRIGHT", -12, 44)
    p.lines = {}
    return p
end

local function Header(page, cols)
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(20)
    local x = 8
    for _, col in ipairs(cols) do
        local fs = T.Text(header, "caption", "textDisabled", true)
        fs:SetPoint("LEFT", header, "LEFT", x, 0)
        fs:SetWidth(col.w - 10)
        fs:SetJustifyH(col.justify or "CENTER")
        fs:SetText(col.title:upper())
        x = x + col.w
    end
    return header
end

function M:Fill()
    if not (window and window:IsShown()) then return end
    for key, p in pairs(pages) do p:SetShown(key == tab) end
    if tab == "chars" then FillChars(pages.chars)
    elseif tab == "inv" then FillInv(pages.inv)
    else FillFind(pages.find) end
    window.foot:SetText(pages[tab].footText or "")
end

local function Build()
    if window then return window end
    local W = EV.UI
    window = W.Window("EvermoreUICharacters", { title = L["Characters"], width = Width(COLS) + 44, height = 480 })
    window:SetPoint("CENTER")
    local body = window.body

    tabs = W.Tabs(body, {
        { value = "chars", text = L["Characters"] },
        { value = "inv",   text = L["Inventory"] },
        { value = "find",  text = L["Find an item"] },
    }, function() return tab end, function(v)
        tab = v
        M:Fill()
        if v == "find" and pages.find.search then pages.find.search:SetFocus() end
    end)
    tabs:SetPoint("TOPLEFT", 12, -6)

    local scope = W.Dropdown(body, 190, {
        { value = "faction", text = L["My faction"] },
        { value = "realm",   text = L["My realm and faction"] },
        { value = "all",     text = L["Every character"] },
    }, function() return A:Settings().scope end, function(v) A:Settings().scope = v; A:Invalidate("scope") end)
    scope:SetPoint("TOPRIGHT", -12, -8)
    scope:SetTooltip(L["Whose characters count"], L["Here, in item tooltips and in the gold readout."])

    -- Characters
    local chars = Page(body, -48)
    Header(chars, COLS)
    chars.scroll = W.Scroll(chars)
    chars.scroll:SetPoint("TOPLEFT", 0, -24)
    chars.scroll:SetPoint("BOTTOMRIGHT")
    pages.chars = chars

    -- Inventory
    local inv = Page(body, -48)
    inv.who = W.Dropdown(inv, 220, function()
        local out = {}
        for _, e in ipairs(A:List({ scope = A:Settings().scope })) do
            out[#out + 1] = { value = e.key, text = A:Coloured(e.info) }
        end
        return out
    end, function() return invChar end, function(v) invChar = v; M:Fill() end)
    inv.who:SetPoint("TOPLEFT", 0, 0)
    inv.where = W.Dropdown(inv, 160, PLACE_NAMES, function() return invPlace end, function(v) invPlace = v; M:Fill() end)
    inv.where:SetPoint("LEFT", inv.who, "RIGHT", 8, 0)
    inv.scroll = W.Scroll(inv)
    inv.scroll:SetPoint("TOPLEFT", 0, -38)
    inv.scroll:SetPoint("BOTTOMRIGHT")
    pages.inv = inv

    -- Find
    local find = Page(body, -48)
    find.search = W.SearchBox(find, 300, function(text) query = text or ""; M:Fill() end, L["Item name"])
    find.search:SetPoint("TOPLEFT", 0, 0)
    find.scroll = W.Scroll(find)
    find.scroll:SetPoint("TOPLEFT", 0, -38)
    find.scroll:SetPoint("BOTTOMRIGHT")
    pages.find = find

    window.foot = T.Text(body, "body", "text")
    window.foot:SetPoint("BOTTOMLEFT", 16, 16)
    window.foot:SetPoint("RIGHT", -16, 0)
    window.foot:SetJustifyH("LEFT")
    window.foot:SetWordWrap(false)

    window:HookScript("OnShow", function() C_Timer.After(0, function() M:Fill() end) end)
    return window
end

function M:Show(which)
    if not A then return end
    Build()
    if which then tab = which; tabs:Refresh() end
    if window:IsShown() then self:Fill() else window:Show() end
end

function M:Toggle()
    if window and window:IsShown() then window:Hide() else self:Show() end
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
function M:OnEnable()
    A = EV.Alts
    self:RegisterMessage("EV_ALTS_CHANGED", function() M:Fill() end)
    -- Item names arriving for a search in progress: redraw once they settle.
    local again = false
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, _, id)
        if id then waiting[id] = nil end
        if tab == "chars" or (tab == "find" and query == "") or again then return end
        again = true
        C_Timer.After(0.3, function() again = false; M:Fill() end)
    end)
end

EV:RegisterSlash("alts", function() if M:IsEnabled() then M:Toggle() else EV:Print(L["The Characters module is switched off."]) end end)
EV:RegisterSlash("chars", function() if M:IsEnabled() then M:Toggle() else EV:Print(L["The Characters module is switched off."]) end end)
