if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Discover.lua
--  Finding Blizzard's windows without keeping a list of them.
--
--  Blizzard already keeps that list, in two tables the client maintains
--  itself: UIPanelWindows (every frame their panel system opens) and
--  UISpecialFrames (every frame Escape closes). Between those and a hook
--  on ShowUIPanel, every window the game opens comes past us, including
--  load-on-demand ones that do not exist at login. Nothing here names a
--  window, so a window Blizzard adds tomorrow is covered today.
--
--  Third-party frames are not swept: we only follow Blizzard's own
--  registries. An addon that reparents itself into a Blizzard window is
--  still skinned, which is the same behaviour as every other skin.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S = ns.S
if not S then return end

local seen = setmetatable({}, { __mode = "k" })

--- Our own windows sit in UISpecialFrames too, so that Escape closes them,
--- and the sweep found them there. They are drawn by our widgets through the
--- Looks already, so walking them is at best wasted and at worst wrong: the
--- dark-text lift took a primary button's label (onAccent, dark on copper)
--- for parchment text, painted it white and pinned it with SetFixedColor,
--- until a hover repainted it. Everything of ours is named EvermoreUI*.
--- The widget gallery walks its Blizzard samples itself, with S.Walk.
local function Mine(frame)
    local ok, name = pcall(frame.GetName, frame)
    return ok and type(name) == "string" and name:find("^EvermoreUI") ~= nil
end

local function Take(frame)
    if type(frame) == "string" then frame = _G[frame] end
    if not S.Alive(frame) or seen[frame] or S.ours[frame] or Mine(frame) then return end
    seen[frame] = true
    S.Adopt(frame)
    -- Scroll boxes recycle rows; follow them so new rows are dressed.
    local function Follow(f, depth)
        if depth > 6 or not S.Alive(f) then return end
        if type(f.ScrollBox) == "table" then S.FollowScrollBox(f.ScrollBox) end
        if f.GetChildren then
            for _, c in ipairs(S.Children(f)) do Follow(c, depth + 1) end
        end
    end
    Follow(frame, 0)
end
S.Take = Take

--- Everything Blizzard's own registries know about.
local function Sweep()
    if type(UIPanelWindows) == "table" then
        for name in pairs(UIPanelWindows) do Take(name) end
    end
    if type(UISpecialFrames) == "table" then
        for _, name in ipairs(UISpecialFrames) do Take(name) end
    end
    -- Static pop-ups and the game menu are children of UIParent rather
    -- than panels, and they are Blizzard's by name.
    for i = 1, 4 do Take("StaticPopup" .. i) end
    Take("GameMenuFrame")
    Take("DropDownList1")
    Take("DropDownList2")
    -- The zone map toggles itself with a bare Show and is in neither table.
    Take("BattlefieldMapFrame")
    Take("OpacityFrame")
    -- Loot under the mouse shows the loot window with a bare Show.
    Take("LootFrame")
    -- The clock toggles itself with a bare Show.
    Take("TimeManagerFrame")
    -- Name completion under a whisper or recipient box, a bare Show.
    Take("AutoCompleteBox")
end
S.Sweep = Sweep

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        S.ApplyFonts()
        if S.ApplyMaterials then S.ApplyMaterials() end
        Sweep()
        -- A second pass once the login rush has settled: some panels
        -- build themselves on their first OnShow.
        C_Timer.After(2, Sweep)
    else
        -- A load-on-demand addon has just brought its windows in. It may
        -- also have brought the material tables and QuestTextContrast with
        -- them, so take those again too; both calls are idempotent.
        C_Timer.After(0, function()
            if S.ApplyMaterials then S.ApplyMaterials() end
            Sweep()
        end)
    end
end)

-- Anything opened through Blizzard's panel system, the moment it opens.
if type(ShowUIPanel) == "function" then
    hooksecurefunc("ShowUIPanel", function(frame) Take(frame) end)
end
if type(StaticPopup_Show) == "function" then
    hooksecurefunc("StaticPopup_Show", function() C_Timer.After(0, Sweep) end)
end
