if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Window Skins.
--
--  There is no list of windows here, because the module does not keep
--  one. It recognises Blizzard's own templates, so what you can switch
--  on and off is the parts: turn off "panelButton" and every button in
--  every window goes back to Blizzard's, in one go.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Skins", true)
if not M then return end
local ns = EV._ModuleNS["EvermoreUI_Skins"]

local function Reload() EV.Options:MarkReloadNeeded() end
local function Off() return not M.db.enabled end

local function PartToggle(part)
    if not part then return nil end
    return { type = "toggle", text = part.name, disabled = Off,
             get = function() return M.db.parts[part.name] ~= false end,
             set = function(v)
                 if v then M.db.parts[part.name] = nil else M.db.parts[part.name] = false end
                 -- Switching one on applies now; switching one off puts
                 -- Blizzard's art back, which needs a reload.
                 if v then M:Refresh() else Reload() end
             end }
end

EV.Options:RegisterPage{
    key = "skins", title = L["Window Skins"], group = "Extras", module = "Skins",
    description = L["Blizzard's own windows in the EvermoreUI palette. Their layout is never touched: we hide their art, draw ours in its place and restyle their text."],
    build = function(p)
        p:Section(L["Look"])
        p:Dual({ type = "toggle", text = L["Skin Blizzard windows"],
                 tooltip = L["Turning this off needs a reload to bring Blizzard's look back."],
                 get = function() return M.db.enabled end,
                 set = function(v) M.db.enabled = v; if v then M:Refresh() else Reload() end end },
               { type = "toggle", text = L["Restyle Blizzard's fonts"], disabled = Off,
                 tooltip = L["Their shared font objects carry almost every label in the game, so this takes the gold out of windows nothing else touches."],
                 get = function() return M.db.fonts end,
                 set = function(v) M.db.fonts = v; if v then M:Refresh() else Reload() end end })
        p:Dual({ type = "toggle", text = L["Hide the spellbook's parchment"], disabled = Off,
                 tooltip = L["Takes the scroll background out of the spellbook so its pages sit on our surface. Off by default."],
                 get = function() return M.db.hideSpellbookPages end,
                 set = function(v)
                     M.db.hideSpellbookPages = v
                     local S = ns and ns.S
                     if S and S.ApplyPack and _G.PlayerSpellsFrame then S.ApplyPack(_G.PlayerSpellsFrame) end
                 end }, nil)
        p:Note(L["Point at a window and type /evui skin this to see what was recognised in it, and what art is still loose."], 0.6)

        p:Section(L["Damage meter"])
        p:Dual({ type = "toggle", text = L["Skin the damage meter"], disabled = Off,
                 tooltip = L["Forever's built-in damage meter in our style: title bar, surface, flat bars and our font. Its own settings (class colours, bar height, text size, opacity) keep working. Turning this off needs a reload."],
                 get = function() return M.db.damageMeter end,
                 set = function(v)
                     M.db.damageMeter = v
                     if v then if ns.RefreshDamageMeter then ns.RefreshDamageMeter() end else Reload() end
                 end },
               { type = "dropdown", text = L["Bar texture"], width = 150,
                 disabled = function() return Off() or not M.db.damageMeter end,
                 values = function()
                     local list = { { value = "", text = L["Same as the suite"] } }
                     for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
                     return list
                 end,
                 get = function() return M.db.dmTexture end,
                 set = function(v) M.db.dmTexture = v; if ns.RefreshDamageMeter then ns.RefreshDamageMeter() end end })
        p:Dual({ type = "toggle", text = L["Outline the bar text"],
                 disabled = function() return Off() or not M.db.damageMeter end,
                 tooltip = L["An outline instead of a shadow, for bars in bright class colours."],
                 get = function() return M.db.dmOutline end,
                 set = function(v) M.db.dmOutline = v; if ns.RefreshDamageMeter then ns.RefreshDamageMeter() end end }, nil)

        p:Section(L["Parts"])
        p:Note(L["Each part is one of Blizzard's templates. Switching one off affects every window that uses it."], 0.6)
        local list = (ns and ns.S and ns.S.parts) or {}
        for i = 1, #list, 2 do
            p:Dual(PartToggle(list[i]), PartToggle(list[i + 1]))
        end
    end,
}
