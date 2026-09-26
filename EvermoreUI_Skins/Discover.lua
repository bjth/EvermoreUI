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

local function Take(frame)
    if type(frame) == "string" then frame = _G[frame] end
    if not S.Alive(frame) or seen[frame] or S.ours[frame] then return end
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
