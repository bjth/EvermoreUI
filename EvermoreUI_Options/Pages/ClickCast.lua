if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Click Casting: spells and actions on modifier clicks over our unit frames.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("UnitFrames", true)
if not M then return end
local ns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_UnitFrames"]
if not ns or not ns.ApplyClickCast then return end

local function DB() return M.db.clickCast end
local function Apply() if M:IsEnabled() then ns.ApplyClickCast() end end

local draft = { mod = "shift", button = 1, kind = "spell", value = "" }

local function TextOf(list, v)
    for _, e in ipairs(list) do if e.value == v then return e.text end end
    return tostring(v)
end

local function Describe(c)
    local what = TextOf(ns.CLICK_KINDS, c.kind)
    if c.kind == "spell" or c.kind == "macro" then what = what .. ": " .. (c.value or "") end
    local combo = c.mod == "" and TextOf(ns.CLICK_BUTTONS, c.button)
        or (TextOf(ns.CLICK_MODS, c.mod) .. " + " .. TextOf(ns.CLICK_BUTTONS, c.button))
    return combo .. " = " .. what
end

EV.Options:RegisterPage{
    key = "clickcast", title = L["Click Casting"], group = "Combat", module = "UnitFrames",
    description = L["Cast on a unit by clicking its frame with a modifier held: Shift + left click on your target frame to heal it, say. Works in combat."],
    build = function(p)
        p:Section(L["Click casting"])
        p:Dual({ type = "toggle", text = L["Use these bindings"],
                 get = function() return DB().enabled end,
                 set = function(v) DB().enabled = v; Apply() end },
               ns.HasBlizzardClickBinding() and { type = "button", text = L["Blizzard's click casting"], label = L["Open"], width = 100,
                 tooltip = L["The game has its own click casting window too. Its bindings work on these frames as well, and win if both bind the same click."],
                 onClick = function() EV.Options:Toggle(); pcall(ToggleClickBindingFrame) end } or nil)
        p:Note(L["Applies to EvermoreUI's player, target, target of target, focus, pet, party and raid frames. Without a binding, left click targets and right click opens the menu, as usual. Bindings change out of combat; they are applied as soon as you leave it."], 0.7)

        p:Section(L["Your bindings"])
        if #DB().binds == 0 then p:Note(L["None yet."], 0.6) end
        for i, c in ipairs(DB().binds) do
            p:Row{ type = "button", text = Describe(c), label = L["Remove"], width = 90,
                   onClick = function()
                       table.remove(DB().binds, i)
                       Apply()
                       EV.Options:Rebuild()
                   end }
        end

        p:Section(L["Add one"])
        local function DG(k) return function() return draft[k] end end
        local function DS(k) return function(v) draft[k] = v; EV.Options:RefreshCurrent() end end
        p:Dual({ type = "dropdown", text = L["Modifier"], width = 130, values = ns.CLICK_MODS, get = DG("mod"), set = DS("mod") },
               { type = "dropdown", text = L["Click"], width = 150, values = ns.CLICK_BUTTONS, get = DG("button"), set = DS("button") })
        p:Dual({ type = "dropdown", text = L["Does"], width = 150, values = ns.CLICK_KINDS, get = DG("kind"), set = DS("kind") },
               { type = "input", text = L["Name"], width = 180, placeholder = L["Spell or macro name"],
                 get = DG("value"), set = function(v) draft.value = v end,
                 disabled = function() return not (draft.kind == "spell" or draft.kind == "macro") end })
        p:Row{ type = "button", text = L["Add this binding"], label = L["Add"], width = 90,
               onClick = function()
                   local c = { mod = draft.mod, button = draft.button, kind = draft.kind, value = draft.value }
                   if not ns.ValidClick(c) then
                       EV:Print(L["That binding needs a spell or macro name."])
                       return
                   end
                   local binds = DB().binds
                   for i = #binds, 1, -1 do
                       if binds[i].mod == c.mod and binds[i].button == c.button then table.remove(binds, i) end
                   end
                   binds[#binds + 1] = c
                   draft.value = ""
                   Apply()
                   EV.Options:Rebuild()
               end }
    end,
    onReset = function()
        local d = DB()
        d.enabled = true
        wipe(d.binds)
        Apply()
    end,
}
