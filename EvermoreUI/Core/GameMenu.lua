if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  GameMenu.lua
--  An "EvermoreUI" button in the Escape menu that opens our options, and
--  optionally (General > Look, off by default) an "EvermoreUI Edit Mode"
--  button under it that unlocks our movers. They sit
--  in Blizzard's first group, straight after Shop (or Options when there's
--  no Shop), with a small gap above it; the rest of the menu follows as
--  normal.
--
--  The menu rebuilds its buttons from a pool every time it opens
--  (GameMenuFrameMixin:InitButtons), then lays them out in layoutIndex
--  order. We post-hook InitButtons, add ours through the menu's own
--  AddButton, and give it a layoutIndex halfway between the anchor and the
--  next button, so Blizzard's own layout puts it in place. Nothing is
--  re-anchored by hand. The gap is a topPadding, which Blizzard's AddButton
--  resets on every pooled button, so nothing lingers when the pool reuses it.
--
--  Closing uses the menu's own Hide (what its Close button does), not the
--  UI panel functions.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local function Setting(key, default)
    local core = EV.dbReady and EV.DB:GetCore()
    if not core or core[key] == nil then return default end
    return core[key]
end

local function OnClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    GameMenuFrame:Hide()
    EV:OpenOptions()
end

local function OnEditClick()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    GameMenuFrame:Hide()
    EV.Movers:Unlock()
end

--- The button ours follows: Shop if it's there, otherwise Options.
local function Anchor(menu)
    local shop, options
    for _, b in ipairs(menu.buttons or {}) do
        local text = b.GetText and b:GetText()
        if text == BLIZZARD_STORE then shop = b elseif text == GAMEMENU_OPTIONS then options = b end
    end
    return shop or options
end

local function AddButton(menu)
    if type(menu.AddButton) ~= "function" then return end
    local showMain = Setting("gameMenuButton", true) ~= false
    local showEdit = Setting("gameMenuEditButton", false) == true
    if not (showMain or showEdit) then return end
    local anchor = Anchor(menu)
    local after = anchor and anchor.layoutIndex
    if type(after) ~= "number" then after = 0 end
    local brand = "|cff" .. EV.Theme.Hex("accent") .. "Evermore|r|cff" .. EV.Theme.Hex("text") .. "UI|r"
    -- Both slot in between the anchor and the next Blizzard button, in order.
    local gap = 12
    if showMain then
        local ok, btn = pcall(menu.AddButton, menu, brand, OnClick)
        if ok and btn then
            btn.layoutIndex = after + 0.4
            btn.topPadding = gap
            gap = nil
        end
    end
    if showEdit then
        local ok, btn = pcall(menu.AddButton, menu, brand .. " " .. L["Edit Mode"], OnEditClick)
        if ok and btn then
            btn.layoutIndex = after + 0.6
            btn.topPadding = gap
        end
    end
end

local hooked = false
local function Hook()
    if hooked or not (GameMenuFrame and GameMenuFrame.InitButtons) then return end
    hooked = true
    hooksecurefunc(GameMenuFrame, "InitButtons", AddButton)
end

Hook()
if not hooked then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        Hook()
        if hooked then self:UnregisterAllEvents() end
    end)
end
