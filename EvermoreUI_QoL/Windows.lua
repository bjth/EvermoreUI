if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Windows.lua
--  Drag Blizzard's windows (character, spellbook, merchant, quest log...) by
--  their title bar, and they open where you left them.
--
--  How:
--    * A thin handle of our own sits over each window's title bar (left of
--      the close button) and starts StartMoving on the window underneath.
--      Blizzard's frames get no scripts replaced; only SetMovable,
--      SetClampedToScreen and the move itself.
--    * Blizzard's panel manager puts windows back in their left / centre /
--      right slots whenever a panel opens or closes (ShowUIPanel,
--      UpdateUIPanelPositions). Both are post-hooked, as is each window's
--      OnShow, and a saved window is put back where you left it.
--    * Positions are saved per profile as the window's top left in UIParent
--      units. SetUserPlaced(false) after a move keeps the client's own
--      layout cache out of it.
--    * Windows that are protected can't be moved or placed in combat; those
--      wait for combat to end.
--    * Windows from load-on-demand addons are picked up as they load.
--  The world map is left alone: it has its own sizes and maximise.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local floor, max = math.floor, math.max

local M = EV:NewModule("Windows", {
    remember  = true,    -- keep positions between sessions
    positions = {},      -- [frame name] = { x, y } top left, UIParent units
})
M.title = "Windows"
M.description = "Drag Blizzard's windows by their title bar; they open where you left them."
ns.windows = M

local NAMES = {
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "ProfessionsBookFrame", "QuestLogFrame",
    "QuestFrame", "GossipFrame", "MerchantFrame", "ClassTrainerFrame", "TaxiFrame", "FlightMapFrame",
    "MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame", "AuctionHouseFrame", "TradeFrame",
    "FriendsFrame", "CommunitiesFrame", "GuildRegistrarFrame", "PetitionFrame", "TabardFrame",
    "PVEFrame", "LFGParentFrame", "RaidParentFrame", "PVPUIFrame", "InspectFrame", "DressUpFrame",
    "AchievementFrame", "CollectionsJournal", "EncounterJournal", "CalendarFrame", "MacroFrame",
    "AddonList", "ChannelFrame", "HelpFrame", "ItemTextFrame", "ItemSocketingFrame", "ItemUpgradeFrame",
    "ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "PetStableFrame", "TimeManagerFrame",
    "TokenFrame", "BlackMarketFrame", "BarberShopFrame", "LootFrame", "GenericTraitFrame",
    "ClickBindingFrame", "ChatConfigFrame", "SettingsPanel", "GameMenuFrame",
}

local hooked = {}    -- window -> handle
local session = {}   -- positions for this session when "remember" is off
local pending = false

local function Store()
    return M.db.remember and M.db.positions or session
end

local function CanTouch(f)
    return not (InCombatLockdown() and f:IsProtected())
end

local function Place(f)
    local name = f:GetName()
    local p = name and Store()[name]
    if not (p and f:IsShown()) then return end
    if not CanTouch(f) then pending = true; return end
    local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1] * k, p[2] * k)
end

local function PlaceAll()
    if not M:IsEnabled() then return end
    for f in pairs(hooked) do Place(f) end
end

local function Save(f)
    local name = f:GetName()
    local left, top = f:GetLeft(), f:GetTop()
    if not (name and left and top) then return end
    local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    Store()[name] = { floor(left * k + 0.5), floor(top * k + 0.5) }
end

local function Handle(f)
    local h = CreateFrame("Frame", nil, f)
    local title = f.TitleContainer
    h:SetPoint("TOPLEFT", f, "TOPLEFT", title and 0 or 4, 0)
    -- Clear of the close button, and the maximise button where there is one.
    local maxi = f.MaximizeMinimizeButton or f.MaxMinButtonFrame
    h:SetPoint("TOPRIGHT", f, "TOPRIGHT", maxi and -56 or -28, 0)
    h:SetHeight(title and max(18, title:GetHeight() or 22) or 22)
    h:SetFrameLevel(f:GetFrameLevel() + 20)
    h:EnableMouse(true)
    h:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not M:IsEnabled() or not CanTouch(f) then return end
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:StartMoving()
        h.moving = true
    end)
    h:SetScript("OnMouseUp", function()
        if not h.moving then return end
        h.moving = false
        f:StopMovingOrSizing()
        if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
        Save(f)
    end)
    h:SetScript("OnHide", function()
        if h.moving then
            h.moving = false
            f:StopMovingOrSizing()
            Save(f)
        end
    end)
    return h
end

local function Hook(name)
    local f = _G[name]
    if not (f and type(f) == "table" and f.GetObjectType and f.StartMoving) or hooked[f] then return end
    hooked[f] = Handle(f)
    f:HookScript("OnShow", function(self) if M:IsEnabled() then Place(self) end end)
end

local function HookAll()
    for _, name in ipairs(NAMES) do Hook(name) end
end

--- Forget saved positions; windows go back to Blizzard's slots next time
--- they open.
function M:ResetAll()
    wipe(self.db.positions)
    wipe(session)
    if UpdateUIPanelPositions and not InCombatLockdown() then pcall(UpdateUIPanelPositions) end
end

function M:OnEnable()
    HookAll()
    self:RegisterEvent("ADDON_LOADED", function() HookAll() end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        if pending then pending = false; PlaceAll() end
    end)
    if type(ShowUIPanel) == "function" then hooksecurefunc("ShowUIPanel", PlaceAll) end
    if type(UpdateUIPanelPositions) == "function" then hooksecurefunc("UpdateUIPanelPositions", PlaceAll) end
end
