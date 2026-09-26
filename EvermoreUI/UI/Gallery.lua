if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Gallery.lua
--  /evui widgets: every control in one window, in every state, with a
--  contrast switch. The place to check a change to the library or theme.
--  /evui theme [standard|high]: switch contrast; /evui theme audit: check the
--  palette against its contrast promises.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local U = EV.UI
local L = EV.L

local gallery

local function Build()
    local w = U.Window("EvermoreUIWidgetGallery", { title = L["EvermoreUI widgets"], width = 720, height = 560 })
    local scroll = U.Scroll(w.body)
    scroll:SetPoint("TOPLEFT", 16, -12)
    scroll:SetPoint("BOTTOMRIGHT", -8, 12)
    local c = scroll.content
    local y = 0
    local state = { toggle = true, check = true, check2 = false, radio = "b", slider = 40, stepper = 3,
                    drop = "two", tab = "one", r = 0.31, g = 0.77, b = 0.97, a = 1 }

    local function Row(label, h)
        local fs = U.Label(c, label, "textMuted", "small")
        fs:SetPoint("TOPLEFT", 0, -y - 6)
        local anchor = CreateFrame("Frame", nil, c)
        anchor:SetPoint("TOPLEFT", 150, -y)
        anchor:SetSize(1, h or U.HEIGHT)
        y = y + (h or U.HEIGHT) + 14
        return anchor
    end
    local function Section(text)
        local s = U.Section(c, text)
        s:SetPoint("TOPLEFT", 0, -y)
        s:SetPoint("RIGHT", c, "RIGHT", -8, 0)
        y = y + 40
    end

    Section(L["Theme"])
    local a = Row(L["Contrast"], 18)
    U.RadioGroup(c, { { value = "standard", text = L["Standard"] }, { value = "high", text = L["High contrast"] } },
        function() return T.mode end, function(v) T.SetContrast(v) end, { direction = "horizontal" }):SetPoint("LEFT", a, "LEFT")

    Section(L["Buttons"])
    a = Row(L["Styles"])
    local prev
    for _, s in ipairs({ { "primary", L["Primary"] }, { nil, L["Secondary"] }, { "ghost", L["Ghost"] }, { "danger", L["Danger"] } }) do
        local b = U.Button(c, s[2], 110, nil, s[1])
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 8, 0) else b:SetPoint("LEFT", a, "LEFT") end
        prev = b
    end
    a = Row(L["States"])
    local dis = U.Button(c, L["Disabled"], 110)
    dis:SetPoint("LEFT", a, "LEFT")
    dis:SetDisabled(true)
    local ic = U.Button(c, L["With icon"], 130)
    ic:SetIcon(134400)
    ic:SetPoint("LEFT", dis, "RIGHT", 8, 0)
    local conf = U.ConfirmButton(c, L["Confirm"], 130, function() EV:Print(L["Confirmed"]) end)
    conf:SetPoint("LEFT", ic, "RIGHT", 8, 0)
    a = Row(L["Icon buttons"])
    prev = nil
    for i, g in ipairs({ "close", "search", "check" }) do
        local b = U.IconButton(c, { glyph = g, size = 26, style = i == 2 and "secondary" or "ghost", tooltip = g })
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT", a, "LEFT") end
        prev = b
    end
    local tog = U.IconButton(c, { texture = 136048, size = 26, style = "secondary", toggle = true, tooltip = L["Toggle"] })
    tog:SetScript("OnClick", function(self) self:SetSelected(not self:IsSelected()) end)
    tog:SetPoint("LEFT", prev, "RIGHT", 6, 0)

    Section(L["Choices"])
    a = Row(L["Toggle"], 20)
    U.Toggle(c, function() return state.toggle end, function(v) state.toggle = v end):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Checkbox"], 18)
    local cb = U.Checkbox(c, L["Show something"], function() return state.check end, function(v) state.check = v end)
    cb:SetPoint("LEFT", a, "LEFT")
    U.Checkbox(c, L["Unchecked"], function() return state.check2 end, function(v) state.check2 = v end):SetPoint("LEFT", cb, "RIGHT", 24, 0)
    a = Row(L["Radio"], 18)
    U.RadioGroup(c, { { value = "a", text = "Alpha" }, { value = "b", text = "Bravo" }, { value = "c", text = "Charlie" } },
        function() return state.radio end, function(v) state.radio = v end, { direction = "horizontal" }):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Dropdown"])
    local long = { { header = L["Short"] }, { value = "one", text = "One" }, { value = "two", text = "Two" },
                   { value = "three", text = "Three (disabled)", disabled = true }, { separator = true }, { header = L["Many"] } }
    for i = 1, 20 do long[#long + 1] = { value = "n" .. i, text = "Option " .. i } end
    U.Dropdown(c, 200, long, function() return state.drop end, function(v) state.drop = v end):SetPoint("LEFT", a, "LEFT")

    Section(L["Numbers and text"])
    a = Row(L["Slider"], 22)
    U.Slider(c, 0, 100, 1, function() return state.slider end, function(v) state.slider = v end, nil, 280):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Stepper"])
    U.Stepper(c, 0, 10, 1, function() return state.stepper end, function(v) state.stepper = v end):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Input"])
    U.Input(c, 220, L["Type and press Enter"], function(t) EV:Print(t) end):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Search"])
    U.SearchBox(c, 220, function() end):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Colour"], 22)
    U.ColorSwatch(c, function() return state.r, state.g, state.b, state.a end,
        function(r, g, b, al) state.r, state.g, state.b, state.a = r, g, b, al end, true):SetPoint("LEFT", a, "LEFT")

    Section(L["Containers"])
    a = Row(L["Tabs"], 32)
    U.Tabs(c, { { value = "one", text = "General" }, { value = "two", text = "Appearance" }, { value = "three", text = "Advanced" } },
        function() return state.tab end, function(v) state.tab = v end):SetPoint("LEFT", a, "LEFT")
    a = Row(L["Panel"], 70)
    local p = U.Panel(c)
    p:SetPoint("TOPLEFT", a, "TOPLEFT")
    p:SetSize(380, 70)
    local t1 = U.Label(p, L["Body text on a raised panel"], "text")
    t1:SetPoint("TOPLEFT", 12, -12)
    local t2 = U.Label(p, L["Muted text for descriptions and hints"], "textMuted", "small")
    t2:SetPoint("TOPLEFT", t1, "BOTTOMLEFT", 0, -6)
    local t3 = U.Label(p, L["Heading colour"], "title", "small", true)
    t3:SetPoint("TOPLEFT", t2, "BOTTOMLEFT", 0, -6)

    scroll:SetContentHeight(y + 10)
    return w
end

EV:RegisterSlash("widgets", function()
    gallery = gallery or Build()
    gallery:SetShown(not gallery:IsShown())
end)

EV:RegisterSlash("theme", function(rest)
    rest = (rest or ""):lower()
    if rest == "standard" or rest == "high" then
        T.SetContrast(rest)
        EV:Print(L["Contrast:"], rest)
    elseif rest == "audit" then
        for _, mode in ipairs({ "standard", "high" }) do
            local fails = T.Audit(mode)
            EV:Print(mode, #fails == 0 and "|cff55ff55" .. L["all contrast checks pass"] .. "|r" or table.concat(fails, "; "))
        end
    else
        EV:Print(L["Contrast:"], T.mode, " (/evui theme standard | high | audit)")
    end
end)
