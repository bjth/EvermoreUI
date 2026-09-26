if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Reminders: the list editor. Reorder, add, remove, switch off, and edit
--  each reminder: which buffs satisfy it, what a click does, and where it
--  applies. Lists are per class.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local W = EV.UI

local M = EV:GetModule("Reminders", true)
if not M then return end

local selected   -- uid of the reminder being edited

local KINDS = {
    { value = "buff",   text = L["A buff"] },
    { value = "weapon", text = L["A weapon enchant"] },
}
local HANDS = {
    { value = "main", text = L["Main hand"] },
    { value = "off",  text = L["Off hand"] },
}
local WHERE = {
    { value = "always",   text = L["Everywhere"] },
    { value = "instance", text = L["Dungeons and raids"] },
    { value = "group",    text = L["In a group"] },
}

local function TextOf(list, v)
    for _, e in ipairs(list) do if e.value == v then return e.text end end
    return ""
end

local function Changed() M:Refresh(); EV.Options:Rebuild() end

--- "Arcane Intellect (1459), Frost Armor" <-> { 1459, "Frost Armor" }
local function SpellsText(spells)
    local parts = {}
    for _, s in ipairs(spells or {}) do
        if type(s) == "number" then
            local n = M.SpellName(s)
            parts[#parts + 1] = n and ("%s (%d)"):format(n, s) or tostring(s)
        else
            parts[#parts + 1] = s
        end
    end
    return table.concat(parts, ", ")
end

local function ParseSpells(text)
    local out = {}
    for part in (text or ""):gmatch("[^,]+") do
        part = strtrim(part)
        local id = tonumber(part:match("%((%d+)%)%s*$")) or tonumber(part)
        if id then out[#out + 1] = id elseif part ~= "" then out[#out + 1] = part end
    end
    return out
end

local function Summary(e)
    local bits = {}
    if e.kind == "weapon" then
        bits[#bits + 1] = TextOf(HANDS, e.hand or "main")
    else
        local n = #(e.spells or {})
        bits[#bits + 1] = n == 1 and SpellsText(e.spells) or (L["any of %d"]):format(n)
    end
    if e.where ~= "always" then bits[#bits + 1] = TextOf(WHERE, e.where) end
    if e.item then bits[#bits + 1] = L["click uses an item"] end
    return table.concat(bits, "  -  ")
end

--------------------------------------------------------------------------------
--  One line of the list
--------------------------------------------------------------------------------
local function SmallButton(parent, width, onClick, chevron, text)
    local b = W.Button(parent, text or "", width, onClick)
    if chevron then
        local c = T.Chevron(b, 10)
        c:SetPoint("CENTER")
        c:Point(chevron)
    end
    return b
end

local function Line(p, e, index, count)
    local width = p.width - 40
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(width, 34)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(M.EntryIcon(e))
    icon:SetDesaturated(not e.on)

    local edit = SmallButton(f, 60, function()
        selected = (selected ~= e.uid) and e.uid or nil
        EV.Options:Rebuild()
    end, nil, selected == e.uid and L["Close"] or L["Edit"])
    edit:SetPoint("RIGHT", 0, 0)
    local down = SmallButton(f, 28, function() M.Move(e.uid, 1); EV.Options:Rebuild() end, "down")
    down:SetPoint("RIGHT", edit, "LEFT", -6, 0)
    local up = SmallButton(f, 28, function() M.Move(e.uid, -1); EV.Options:Rebuild() end, "up")
    up:SetPoint("RIGHT", down, "LEFT", -4, 0)
    if index == 1 then up:SetDisabled(true) end
    if index == count then down:SetDisabled(true) end
    local on = W.Toggle(f, function() return e.on end, function(v) e.on = v and true or false; Changed() end)
    on:SetPoint("RIGHT", up, "LEFT", -12, 0)

    local name = T.Text(f, "body", e.on and "text" or "textMuted")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
    name:SetPoint("RIGHT", on, "LEFT", -10, 0)
    name:SetWordWrap(false)
    name:SetText(e.label or "?")
    local sub = T.Text(f, "caption", "textMuted")
    sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, -1)
    sub:SetPoint("RIGHT", on, "LEFT", -10, 0)
    sub:SetWordWrap(false)
    sub:SetText(Summary(e))
    p:Row{ type = "custom", height = 42, build = function() return f end }
end

--------------------------------------------------------------------------------
--  Editing one reminder
--------------------------------------------------------------------------------
local function Editor(p, e)
    p:Section((L["Editing: %s"]):format(e.label or ""))
    local function G(k) return function() return e[k] end end
    local function S(k) return function(v) e[k] = v; Changed() end end
    p:Dual({ type = "input", text = L["Name"], width = 200, get = G("label"),
             set = function(v) e.label = (v ~= "" and v) or e.label; Changed() end },
           { type = "dropdown", text = L["Remind about"], width = 170, values = KINDS,
             get = function() return e.kind or "buff" end, set = S("kind") })
    if e.kind == "weapon" then
        p:Dual({ type = "dropdown", text = L["Hand"], width = 140, values = HANDS,
                 get = function() return e.hand or "main" end, set = S("hand") }, nil)
    else
        p:Row{ type = "input", text = L["Buffs that count"], width = 320,
               placeholder = L["Spell names or IDs, separated by commas"],
               tooltip = L["Any one of these on you satisfies the reminder. Names match every rank; IDs are shown with their names."],
               get = function() return SpellsText(e.spells) end,
               set = function(v) e.spells = ParseSpells(v); Changed() end }
        p:Dual({ type = "toggle", text = L["Only once I know the spell"],
                 tooltip = L["For class buffs: hidden until you've learned one of the spells. Leave off for food, flasks and elixirs."],
                 get = function() return e.known and true or false end, set = S("known") },
               { type = "toggle", text = L["Only when I carry something for it"],
                 tooltip = L["Hidden unless your bags hold its item, or a consumable that gives one of these buffs (food that makes you Well Fed). Clicking uses it."],
                 get = function() return e.needItem and true or false end, set = S("needItem") })
    end
    p:Dual({ type = "input", text = L["Click uses"], width = 200,
             placeholder = L["Item name or ID (optional)"],
             tooltip = e.kind == "weapon" and L["The poison, oil or stone to put on that hand when you click the reminder."]
                 or L["An item to use when you click the reminder, like a flask or your favourite food. Empty: clicking casts the buff."],
             get = function()
                 local id = M.ItemID(e.item)
                 local name = id and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
                 return name or (e.item and tostring(e.item)) or ""
             end,
             set = function(v)
                 if v == "" then e.item = nil else e.item = M.ItemID(v) or v end
                 Changed()
             end },
           { type = "dropdown", text = L["Where"], width = 170, values = WHERE,
             get = function() return e.where or "always" end, set = S("where") })
    p:Row{ type = "button", text = L["Remove this reminder"], label = L["Remove"], width = 100, confirm = true,
           onClick = function() M.Remove(e.uid); selected = nil; Changed() end }
end

--------------------------------------------------------------------------------
--  The page
--------------------------------------------------------------------------------
EV.Options:RegisterPage{
    key = "reminders", title = L["Reminders"], group = "Combat", module = "Reminders",
    description = L["Icons in the middle of the screen for what you should have up and don't. Click one to cast or use it. Hidden in combat."],
    build = function(p)
        local list = M.List()
        p:Section((L["Your list (%s)"]):format(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[M.CLASS] or M.CLASS))
        p:Note(L["Shown in this order. Each class keeps its own list."], 0.7)
        if #list == 0 then p:Note(L["Nothing on the list."], 0.6) end
        for i, e in ipairs(list) do
            Line(p, e, i, #list)
            if selected == e.uid then Editor(p, e); p:Section(L["More reminders"]) end
        end

        p:Section(L["Add"])
        p:Dual({ type = "button", text = L["A new reminder"], label = L["New"], width = 100,
                 onClick = function()
                     local e = M.Add({ label = L["New reminder"], kind = "buff", spells = {}, known = false })
                     selected = e.uid
                     EV.Options:Rebuild()
                 end },
               { type = "button", text = L["Put the list back as it started"], label = L["Reset"], width = 100, confirm = true,
                 onClick = function() M.ResetList(); selected = nil; EV.Options:Rebuild() end })
        local current = M.CurrentBuffs()
        if #current > 0 then
            p:Note(L["Buffs on you now. Add one to be reminded when it's missing:"], 0.7)
            for _, b in ipairs(current) do
                p:Row{ type = "button", text = ("|T%s:16:16:0:0:64:64:5:59:5:59|t  %s"):format(tostring(b.icon or 134400), b.name),
                       label = L["Add"], width = 80,
                       onClick = function()
                           local e = M.Add({ label = b.name, kind = "buff", spells = { b.spellID or b.name }, known = false })
                           selected = e.uid
                           EV.Options:Rebuild()
                       end }
            end
        end

        p:Section(L["When"])
        local function Get(k) return function() return M.db[k] end end
        local function Set(k) return function(v) M.db[k] = v; M:Refresh() end end
        p:Dual({ type = "toggle", text = L["Also when about to run out"],
                 tooltip = L["Shows a buff that is still up but running low, so you can top it up before a pull."],
                 get = Get("expiring"), set = Set("expiring") },
               { type = "slider", text = L["Running low at"], min = 10, max = 600, step = 10,
                 fmt = function(v) return v .. "s" end, get = Get("expiringAt"), set = Set("expiringAt"),
                 disabled = function() return not M.db.expiring end })

        p:Section(L["Look"])
        p:Dual({ type = "slider", text = L["Icon size"], min = 20, max = 64, step = 1,
                 get = Get("size"), set = Set("size") },
               { type = "toggle", text = L["Names under the icons"], get = Get("showNames"), set = Set("showNames") })
        p:Dual({ type = "slider", text = L["Spacing"], min = 0, max = 20, step = 1,
                 get = Get("spacing"), set = Set("spacing") },
               { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                 onClick = function() EV.Movers:Reset("Reminders") end })
    end,
    onReset = function()
        local lists = M.db.lists
        wipe(M.db)
        EV.DB.Merge(M.db, M.defaults)
        M.db.lists = lists          -- the lists have their own reset button
        if M:IsEnabled() then M:Refresh() end
    end,
}
