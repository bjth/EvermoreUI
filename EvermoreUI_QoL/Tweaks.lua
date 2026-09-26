if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Tweaks.lua
--  Small fixes, each off until chosen, each fully undone when switched off.
--
--  Easy delete     Destroying a good item asks you to type DELETE
--                  (StaticPopupDialogs.DELETE_GOOD_ITEM, hasEditBox). We type
--                  it for you: the edit box's own OnTextChanged enables YES,
--                  exactly as if you had, so the click is still yours.
--  Max camera      cameraDistanceMaxZoomFactor to 2.0, the top of Blizzard's
--                  own slider on Forever (Camelot/ControlsOverrides.lua). Your
--                  previous value is kept and put back.
--  Quieter errors  Blizzard's own per-type switch,
--                  UIErrorsFrame:SetMessageTypeEnabled, for the red lines that
--                  repeat while you mash a key ("Ability is not ready yet",
--                  "Not enough energy", "Out of range"). Real errors still show.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI

local function DB() return ns.module and ns.module.db end

--------------------------------------------------------------------------------
--  Easy delete
--------------------------------------------------------------------------------
local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }
local deleteHooked = false

local function FillDelete(which)
    local db = DB()
    if not (db and db.easyDelete and DELETE_POPUPS[which]) then return end
    local word = DELETE_ITEM_CONFIRM_STRING
    if type(word) ~= "string" or word == "" then return end
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
    local box = dialog and dialog.GetEditBox and dialog:GetEditBox()
    if box then box:SetText(word) end
end

local function HookDelete()
    if deleteHooked or type(StaticPopup_Show) ~= "function" then return end
    deleteHooked = true
    hooksecurefunc("StaticPopup_Show", function(which)
        ns.Safe("easy delete", FillDelete, which)
    end)
end

--------------------------------------------------------------------------------
--  Max camera distance
--------------------------------------------------------------------------------
local CAMERA_CVAR, CAMERA_MAX = "cameraDistanceMaxZoomFactor", "2.0"

local function ApplyCamera()
    local db = DB()
    if not db then return end
    local g = EV.DB:GetGlobal()
    if db.maxCamera then
        if g.cameraBefore == nil then
            local ok, v = pcall(GetCVar, CAMERA_CVAR)
            g.cameraBefore = ok and v or false
        end
        pcall(SetCVar, CAMERA_CVAR, CAMERA_MAX)
    elseif g.cameraBefore ~= nil then
        if g.cameraBefore then pcall(SetCVar, CAMERA_CVAR, g.cameraBefore) end
        g.cameraBefore = nil
    end
end

--------------------------------------------------------------------------------
--  Quieter errors
--------------------------------------------------------------------------------
local QUIET = {
    "LE_GAME_ERR_ABILITY_COOLDOWN", "LE_GAME_ERR_SPELL_COOLDOWN", "LE_GAME_ERR_ITEM_COOLDOWN",
    "LE_GAME_ERR_OUT_OF_ENERGY", "LE_GAME_ERR_OUT_OF_RAGE", "LE_GAME_ERR_OUT_OF_MANA",
    "LE_GAME_ERR_OUT_OF_FOCUS", "LE_GAME_ERR_OUT_OF_RANGE", "LE_GAME_ERR_SPELL_OUT_OF_RANGE",
    "LE_GAME_ERR_NO_ATTACK_TARGET", "LE_GAME_ERR_GENERIC_NO_TARGET", "LE_GAME_ERR_INVALID_ATTACK_TARGET",
    "LE_GAME_ERR_BADATTACKFACING", "LE_GAME_ERR_BADATTACKPOS",
}
local quietApplied = false

local function ApplyErrors()
    local db = DB()
    local f = UIErrorsFrame
    if not (db and f and f.SetMessageTypeEnabled) then return end
    local want = db.quietErrors and true or false
    if want == quietApplied then return end
    quietApplied = want
    for _, name in ipairs(QUIET) do
        local t = _G[name]
        if t ~= nil then pcall(f.SetMessageTypeEnabled, f, t, not want) end
    end
end

--------------------------------------------------------------------------------
function ns.ApplyTweaks()
    HookDelete()
    ApplyCamera()
    ApplyErrors()
end

function ns.EnableTweaks(M)
    ns.ApplyTweaks()
end
