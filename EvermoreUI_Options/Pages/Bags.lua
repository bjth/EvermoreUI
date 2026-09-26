if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Bags: layout, and the sections (order, on/off, your own with rules).
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local W = EV.UI

local M = EV:GetModule("Bags", true)
if not M then return end
local ns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_Bags"]
local R = ns and ns.Rules

local TAB_GENERAL, TAB_SECTIONS = L["General"], L["Sections"]
local selected   -- key of your section being edited

local SORTS = {
    { value = "quality", text = L["Quality, best first"] },
    { value = "ilvl",    text = L["Item level, highest first"] },
    { value = "name",    text = L["Name"] },
    { value = "id",      text = L["Item ID"] },
}
local MATCH = {
    { value = "all", text = L["Every rule"] },
    { value = "any", text = L["Any rule"] },
}

local function Changed() M:Refresh(); EV.Options:Rebuild() end

--------------------------------------------------------------------------------
--  General
--------------------------------------------------------------------------------
local function General(p)
    local db = M.db
    local function G(k) return function() return db[k] end end
    local function S(k) return function(v) db[k] = v; M:Refresh() end end
    p:Section(L["Layout"])
    p:Dual({ type = "slider", text = L["Icons per row"], min = 6, max = 24, step = 1, get = G("columns"), set = S("columns") },
           { type = "slider", text = L["Icon size"], min = 24, max = 48, step = 1, get = G("size"), set = S("size") })
    p:Dual({ type = "slider", text = L["Spacing"], min = 0, max = 10, step = 1, get = G("spacing"), set = S("spacing") },
           { type = "button", text = L["Your bags"], label = L["Open"], width = 100, onClick = function() M:Open() end })
    p:Section(L["Items"])
    p:Dual({ type = "dropdown", text = L["Order within a section"], width = 200, values = SORTS, get = G("sort"), set = S("sort") },
           { type = "toggle", text = L["Item level on gear"], get = G("ilvl"), set = S("ilvl") })
    p:Note(L["Alt + click a bag on the bag bar to empty it into the others. Drop an item on a section's title in your bags to keep it in that section; click a title to fold it."], 0.7)
end

--------------------------------------------------------------------------------
--  Sections list
--------------------------------------------------------------------------------
local function Small(parent, width, onClick, chevron, text)
    local b = W.Button(parent, text or "", width, onClick)
    if chevron then
        local c = T.Chevron(b, 10)
        c:SetPoint("CENTER")
        c:Point(chevron)
    end
    return b
end

local function Summary(e)
    if e.builtin then return L["Built in"] end
    local sec = e.custom
    local n, hand = #(sec.rules or {}), 0
    for _, k in pairs(M.db.assign) do if k == sec.key then hand = hand + 1 end end
    local parts = {}
    parts[#parts + 1] = n == 1 and L["1 rule"] or (L["%d rules"]):format(n)
    if hand > 0 then parts[#parts + 1] = hand == 1 and L["1 item by hand"] or (L["%d items by hand"]):format(hand) end
    return table.concat(parts, ", ")
end

local function Line(p, list, index)
    local e = list[index]
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(p.width - 40, 34)
    local on = M.IsOn(e.key)

    local right
    if e.custom then
        right = Small(f, 60, function()
            selected = (selected ~= e.key) and e.key or nil
            EV.Options:Rebuild()
        end, nil, selected == e.key and L["Close"] or L["Edit"])
    else
        right = CreateFrame("Frame", nil, f)
        right:SetSize(60, 1)
    end
    right:SetPoint("RIGHT", 0, 0)
    local down = Small(f, 28, function()
        list[index], list[index + 1] = list[index + 1], list[index]
        M.SetOrder(list); Changed()
    end, "down")
    down:SetPoint("RIGHT", right, "LEFT", -6, 0)
    local up = Small(f, 28, function()
        list[index], list[index - 1] = list[index - 1], list[index]
        M.SetOrder(list); Changed()
    end, "up")
    up:SetPoint("RIGHT", down, "LEFT", -4, 0)
    if index == 1 then up:SetDisabled(true) end
    if index == #list then down:SetDisabled(true) end

    local toggle
    if e.key ~= "other" then
        toggle = W.Toggle(f, function() return M.IsOn(e.key) end, function(v)
            if e.custom then e.custom.on = v and true or false else M.db.categories[e.key] = v and true or false end
            Changed()
        end)
        toggle:SetPoint("RIGHT", up, "LEFT", -12, 0)
    end
    local anchor = toggle or up

    local name = T.Text(f, "body", on and "text" or "textMuted")
    name:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
    name:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
    name:SetWordWrap(false)
    name:SetText(e.label)
    local sub = T.Text(f, "caption", "textMuted")
    sub:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 2)
    sub:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
    sub:SetWordWrap(false)
    sub:SetText(Summary(e))
    p:Row{ type = "custom", height = 42, build = function() return f end }
end

--------------------------------------------------------------------------------
--  Editing one of your sections
--------------------------------------------------------------------------------
local function ValueControl(r)
    local function Set(v) r.value = v; R.Changed(r); M:Refresh() end
    local get = function() return r.value end
    if r.kind == "type" then
        return { type = "dropdown", text = L["Is"], width = 240, values = R.Types(), get = get, set = Set }
    elseif r.kind == "quality" then
        return { type = "dropdown", text = L["Quality"], width = 160, values = R.Qualities(), get = get, set = Set }
    elseif r.kind == "slot" then
        return { type = "dropdown", text = L["Slot"], width = 180, values = R.Slots(), get = get, set = Set }
    elseif r.kind == "bound" then
        return { type = "dropdown", text = L["Soulbound"], width = 100, values = R.BOUND, get = get, set = Set }
    elseif r.kind == "ilvl" then
        return { type = "slider", text = L["Item level"], min = 1, max = 100, step = 1,
                 get = function() return tonumber(r.value) or 1 end, set = Set }
    elseif r.kind == "set" or r.kind == "novalue" then
        return nil
    end
    local placeholder = (r.kind == "ids" and L["Item IDs, separated by commas"]) or L["Text to look for"]
    return { type = "input", text = L["Value"], width = 220, placeholder = placeholder,
             get = function() return r.value and tostring(r.value) or "" end, set = Set }
end

local function Editor(p, sec)
    p:Section((L["Editing: %s"]):format(sec.name or ""))
    p:Dual({ type = "input", text = L["Name"], width = 200, get = function() return sec.name end,
             set = function(v) if v ~= "" then sec.name = v end; Changed() end },
           { type = "dropdown", text = L["Items must match"], width = 150, values = MATCH,
             get = function() return sec.match or "all" end, set = function(v) sec.match = v; M:Refresh() end })

    sec.rules = sec.rules or {}
    for n, r in ipairs(sec.rules) do
        local hasOp = r.kind == "quality" or r.kind == "ilvl"
        p:Dual({ type = "dropdown", text = (L["Rule %d"]):format(n), width = 180, values = R.KINDS,
                 get = function() return r.kind end,
                 set = function(v)
                     local fresh = R.New(v)
                     for k in pairs(r) do r[k] = nil end
                     for k, x in pairs(fresh) do r[k] = x end
                     R.Changed(r); Changed()
                 end },
               { type = "button", text = "", label = L["Remove"], width = 90,
                 onClick = function() table.remove(sec.rules, n); Changed() end })
        local value = ValueControl(r)
        if hasOp or value then
            p:Dual(hasOp and { type = "dropdown", text = L["Compare"], width = 120, values = R.OPS,
                               get = function() return r.op or "atleast" end,
                               set = function(v) r.op = v; M:Refresh() end } or value,
                   hasOp and value or nil)
        end
    end
    p:Row{ type = "dropdown", text = L["Add a rule"], width = 200, values = R.KINDS,
           get = function() return nil end,
           set = function(kind) sec.rules[#sec.rules + 1] = R.New(kind); Changed() end }

    -- Items dropped on this section's title.
    local hand = {}
    for id, key in pairs(M.db.assign) do if key == sec.key then hand[#hand + 1] = id end end
    table.sort(hand)
    if #hand > 0 then
        p:Section(L["Put here by hand"])
        for _, id in ipairs(hand) do
            local name = C_Item.GetItemNameByID(id) or ("#" .. id)
            local icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or 134400
            p:Row{ type = "button", text = ("|T%s:16:16:0:0:64:64:5:59:5:59|t  %s"):format(tostring(icon), name),
                   label = L["Remove"], width = 90,
                   onClick = function() M.Assign(id, nil); Changed() end }
        end
    end

    p:Row{ type = "button", text = L["Delete this section"], label = L["Delete"], width = 100, confirm = true,
           onClick = function() M.DeleteSection(sec.key); selected = nil; Changed() end }
end

local function Sections(p)
    if not R then return end
    p:Section(L["Sections"])
    p:Note(L["Top to bottom as they appear in your bags. An item goes in the first section that fits: one you dropped it on, then your own sections in this order, then the built-in ones. Switch a section off and its items fall through to the next that fits."], 0.7)
    local list = M.All()
    for n = 1, #list do Line(p, list, n) end
    p:Dual({ type = "button", text = L["A section of your own"], label = L["New"], width = 100,
             onClick = function()
                 local sec = M.NewSection(L["New section"])
                 selected = sec.key
                 Changed()
             end },
           { type = "button", text = L["Order and on/off"], label = L["Reset"], width = 100, confirm = true,
             onClick = function()
                 wipe(M.db.order)
                 for k in pairs(M.db.categories) do M.db.categories[k] = true end
                 Changed()
             end })
    if selected then
        for _, sec in ipairs(M.db.custom) do
            if sec.key == selected then Editor(p, sec) end
        end
    end
end

EV.Options:RegisterPage{
    key = "bags", title = L["Bags"], group = "Interface", module = "Bags",
    description = L["All your bags in one window, split into sections by category. Replaces Blizzard's bag windows."],
    tabs = { TAB_GENERAL, TAB_SECTIONS },
    build = function(p, tab)
        if tab == TAB_SECTIONS then Sections(p) else General(p) end
    end,
    onReset = function(tab)
        if tab == TAB_SECTIONS then return end
        for _, k in ipairs({ "columns", "size", "spacing", "sort", "ilvl" }) do M.db[k] = M.defaults[k] end
        M:Refresh()
    end,
}
