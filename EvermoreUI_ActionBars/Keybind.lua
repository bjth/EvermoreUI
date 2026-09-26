if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Keybind.lua
--  Keybind mode: hover a button, press a key. Escape clears the button.
--  Mouse buttons 3-5 and the wheel bind too; left and right click do not,
--  so you can still move the window.
--
--  Every button of ours is one of Blizzard's, so each already has a binding
--  command: ACTIONBUTTON1, MULTIACTIONBAR1BUTTON1 and so on (the button's
--  bindingAction, set in its UpdateHotkeys), SHAPESHIFTBUTTONn for the
--  stance bar and BONUSACTIONBUTTONn for the pet bar. Binding them is the
--  plain SetBinding / SaveBindings any key binding window uses, so the keys
--  also show in Blizzard's Key Bindings, and work with EvermoreUI switched
--  off. Out of combat only; entering combat leaves the mode.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local W = EV.UI

local KB = {}
ns.Keybind = KB

local overlays = {}      -- button -> overlay
local active = false
local hovered
local window

-- Keys that only ever modify another key, plus the client's "no idea".
local IGNORE = { UNKNOWN = true }
for _, mod in ipairs({ "ALT", "CTRL", "SHIFT", "META" }) do
    IGNORE["L" .. mod], IGNORE["R" .. mod] = true, true
end
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

--- The binding command for one of our buttons.
function KB.Command(b)
    local def = b.evBar and ns.BY_KEY[b.evBar]
    if def and def.stance then return "SHAPESHIFTBUTTON" .. (b.evIndex or b:GetID()) end
    if def and def.pet then return "BONUSACTIONBUTTON" .. (b.evIndex or b:GetID()) end
    if b.bindingAction then return b.bindingAction end
    if b.commandName then return b.commandName end
    local name = b:GetName()
    return name and ("CLICK " .. name .. ":LeftButton") or nil
end

local function Keys(cmd)
    if not cmd then return {} end
    return { GetBindingKey(cmd) }
end

-- Held modifiers, in the order WoW writes them in a binding ("ALT-CTRL-X").
local HELD = {
    { "ALT", function() return IsAltKeyDown() end },
    { "CTRL", function() return IsControlKeyDown() end },
    { "SHIFT", function() return IsShiftKeyDown() end },
    { "META", function() return IsMetaKeyDown and IsMetaKeyDown() end },
}

local function Modified(key)
    local parts = {}
    for _, mod in ipairs(HELD) do
        if mod[2]() then parts[#parts + 1] = mod[1] end
    end
    parts[#parts + 1] = key
    return table.concat(parts, "-")
end

local function Save()
    local set = (M.db.behaviour.bindPerCharacter and 2) or 1
    pcall(SaveBindings, set)
end

local function Tip(o)
    local b = o.button
    GameTooltip:SetOwner(o, "ANCHOR_TOP")
    local cmd = KB.Command(b)
    GameTooltip:SetText(_G["BINDING_NAME_" .. (cmd or "")] or cmd or "?")
    local keys = Keys(cmd)
    if #keys == 0 then
        GameTooltip:AddLine(L["Not bound. Press a key."], 0.7, 0.7, 0.7)
    else
        for _, k in ipairs(keys) do GameTooltip:AddLine(GetBindingText(k), 1, 1, 1) end
        GameTooltip:AddLine(L["Escape clears."], 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

--- Bind a key (with the modifiers held now) to one of our buttons, or
--- clear its keys on Escape. Shared with the options' bar editor.
function KB.Apply(b, key)
    if InCombatLockdown() or not b then return end
    local cmd = KB.Command(b)
    if not cmd then return end
    if key == "ESCAPE" then
        for _, k in ipairs(Keys(cmd)) do SetBinding(k) end
        Save()
        EV:Print(L["Cleared"], _G["BINDING_NAME_" .. cmd] or cmd)
    else
        local combo = Modified(key)
        -- Say what the key did before, so taking it from something else
        -- (P from the spellbook, say) is never silent.
        local before = GetBindingAction(combo)
        SetBinding(combo, cmd)
        Save()
        if before and before ~= "" and before ~= cmd then
            EV:Print(GetBindingText(combo), "->", _G["BINDING_NAME_" .. cmd] or cmd,
                ("(%s %s)"):format(L["was"], _G["BINDING_NAME_" .. before] or before))
        else
            EV:Print(GetBindingText(combo), "->", _G["BINDING_NAME_" .. cmd] or cmd)
        end
    end
end

KB.IGNORE, KB.MOUSE = IGNORE, MOUSE

local function Bind(o, key)
    if InCombatLockdown() then return KB.Stop() end
    KB.Apply(o.button, key)
    Tip(o)
end

local function Overlay(b)
    local o = overlays[b]
    if o then return o end
    o = CreateFrame("Button", nil, b)
    o:SetAllPoints(b)
    o:SetFrameLevel(b:GetFrameLevel() + 20)
    o:RegisterForClicks("AnyUp")
    o.fill = T.Fill(o, "OVERLAY", "accent", 0.18)
    o.fill:SetAllPoints()
    o.button = b
    o:SetScript("OnEnter", function(self)
        hovered = self
        self.fill:SetColorTexture(T.RGBA("accent", 0.5))
        self:EnableKeyboard(true)
        Tip(self)
    end)
    o:SetScript("OnLeave", function(self)
        if hovered == self then hovered = nil end
        self.fill:SetColorTexture(T.RGBA("accent", 0.18))
        self:EnableKeyboard(false)
        GameTooltip:Hide()
    end)
    o:SetScript("OnKeyDown", function(self, key)
        if IGNORE[key] then return end
        -- Keys pressed here are ours; nothing else should act on them.
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        Bind(self, key)
    end)
    o:SetScript("OnMouseDown", function(self, button)
        local key = MOUSE[button]
        if key then Bind(self, key) end
    end)
    o:SetScript("OnMouseWheel", function(self, delta)
        Bind(self, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)
    o:EnableMouseWheel(true)
    o:Hide()
    overlays[b] = o
    return o
end

local function Window()
    if window then return window end
    window = W.Window("EvermoreUIKeybindWindow", { title = L["Keybind mode"], width = 340, height = 150, escape = false })
    window:SetPoint("TOP", UIParent, "TOP", 0, -120)
    window.closeButton:SetScript("OnClick", function() KB.Stop() end)
    local text = T.Text(window.body, "body", "textMuted")
    text:SetWordWrap(true)
    text:SetWidth(316)
    text:SetPoint("TOPLEFT", 12, -10)
    text:SetText(L["Hover a button and press a key. Escape clears it. Mouse buttons and the wheel work too."])
    local cb = W.Checkbox(window.body, L["Save for this character only"],
        function() return M.db.behaviour.bindPerCharacter end,
        function(v) M.db.behaviour.bindPerCharacter = v and true or false; Save() end)
    cb:SetPoint("TOPLEFT", 12, -56)
    local done = W.Button(window.body, L["Done"], 100, function() KB.Stop() end, "accent")
    done:SetPoint("BOTTOMRIGHT", -10, 10)
    return window
end

function KB.Start()
    if active then return end
    if InCombatLockdown() then
        EV:Print(L["Keybind mode is available out of combat."])
        return
    end
    active = true
    for _, def in ipairs(ns.BARS) do
        local f = ns.frames[def.key]
        if f and f:IsShown() then
            for _, b in ipairs(ns.Buttons(def)) do
                if b:GetParent() == f and b:IsShown() then Overlay(b):Show() end
            end
        end
    end
    Window():Show()
end

function KB.Stop()
    if not active then return end
    active = false
    for _, o in pairs(overlays) do
        o:EnableKeyboard(false)
        o:Hide()
    end
    hovered = nil
    GameTooltip:Hide()
    if window then window:Hide() end
end

function KB.Toggle()
    if active then KB.Stop() else KB.Start() end
end

function KB.IsActive() return active end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function() KB.Stop() end)

EV:RegisterSlash("kb", function() if M:IsEnabled() then KB.Toggle() end end)
EV:RegisterSlash("bind", function() if M:IsEnabled() then KB.Toggle() end end)
