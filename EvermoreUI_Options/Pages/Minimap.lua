if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Minimap. Only registers if the module is loaded.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("Minimap", true)
if not M then return end

local function Get(key) return function() return M.db[key] end end
local function Set(key)
    return function(v)
        M.db[key] = v
        if M:IsEnabled() then M:Refresh() end
    end
end
local function Toggle(key, text, tooltip, disabled)
    return { type = "toggle", text = text, tooltip = tooltip, get = Get(key), set = Set(key), disabled = disabled }
end

EV.Options:RegisterPage{
    key = "minimap", title = L["Minimap"], group = "Interface", module = "Minimap",
    description = L["A square minimap with the zone, clock, coordinates and buttons laid over it. Move it with /evui edit."],
    build = function(p)
        p:Section(L["Map"])
        p:Dual({ type = "slider", text = L["Size"], min = 120, max = 360, step = 2, get = Get("size"), set = Set("size") },
               { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                 onClick = function() EV.Movers:Reset("Minimap") end })
        p:Dual(Toggle("wheelZoom", L["Mouse wheel zooms"], L["Scroll anywhere on the map to zoom in and out."]),
               { type = "slider", text = L["Zoom back out after"], min = 0, max = 60, step = 5,
                 fmt = function(v) return v == 0 and L["Never"] or (v .. "s") end,
                 tooltip = L["After zooming, return to the widest view after this many seconds."],
                 get = Get("autoZoom"), set = Set("autoZoom") })
        p:Row(Toggle("difficulty", L["Instance badge"], L["Group size and difficulty (5, 10H, 25M...) in the map's corner while you're in an instance."]))

        p:Section(L["On the map"])
        p:Dual(Toggle("zone", L["Zone name"], L["On a plate across the bottom edge. Click it for the world map."]),
               Toggle("zoneColour", L["Colour by PvP status"], L["Sanctuary, friendly, contested and hostile zones each get their colour."],
                      function() return not M.db.zone end))
        p:Dual(Toggle("diel", L["Day and night"], L["A sun or moon on the zone plate for Forever's day and night cycle."],
                      function() return not M.db.zone end),
               Toggle("coords", L["Coordinates"], L["Top left. Only updates while you're moving."]))
        p:Dual(Toggle("clock", L["Clock"], L["Top centre. Uses the Time Manager's settings for local or realm time and 24-hour format."]),
               Toggle("buttons", L["Buttons"], L["Tracking, calendar, mail, crafting orders and addons, down the right edge."]))
        p:Row({ type = "slider", text = L["Font size"], min = 9, max = 18, step = 1, get = Get("fontSize"), set = Set("fontSize") })

        p:Section(L["Addon buttons"])
        p:Dual(Toggle("group", L["Group addon buttons"], L["Gathers other addons' minimap buttons into one pop-out behind the dotted button on the map. Turning it off takes a reload to put them back on the map."],
                      nil),
               { type = "slider", text = L["Buttons per row"], min = 2, max = 10, step = 1,
                 get = Get("groupColumns"), set = Set("groupColumns"), disabled = function() return not M.db.group end })
    end,
    onReset = function()
        wipe(M.db)
        EV.DB.Merge(M.db, M.defaults)
        if M:IsEnabled() then M:Refresh() end
    end,
}
