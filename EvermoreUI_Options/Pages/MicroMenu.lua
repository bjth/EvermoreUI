if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Micro Menu and Bag Bar. Each page only registers if its module is loaded.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local function Controls(M)
    local function Get(key) return function() return M.db[key] end end
    local function Set(key)
        return function(v)
            M.db[key] = v
            if M:IsEnabled() then M:Refresh() end
        end
    end
    local C = {}
    function C.Toggle(key, text, tooltip, disabled)
        return { type = "toggle", text = text, tooltip = tooltip, get = Get(key), set = Set(key), disabled = disabled }
    end
    function C.Slider(key, text, lo, hi, step, tooltip, disabled)
        return { type = "slider", text = text, min = lo, max = hi, step = step or 1, tooltip = tooltip,
                 get = Get(key), set = Set(key), disabled = disabled }
    end
    function C.Fade(p)
        p:Section(L["Fade"])
        p:Dual(C.Toggle("fade", L["Fade out"], L["Fades the bar while your mouse isn't over it."]),
               { type = "slider", text = L["Faded opacity"], min = 0, max = 100, step = 5, fmt = function(v) return v .. "%" end,
                 get = function() return math.floor(M.db.fadeAlpha * 100 + 0.5) end,
                 set = function(v) M.db.fadeAlpha = v / 100; if M:IsEnabled() then M:Refresh() end end,
                 disabled = function() return not M.db.fade end })
    end
    function C.Reset(key)
        return { type = "button", text = L["Position"], label = L["Reset"], width = 100,
                 onClick = function() EV.Movers:Reset(key) end }
    end
    -- Orientation and the directions that go with it. Switching orientation
    -- picks that orientation's default direction.
    function C.Orientation(hDefault, vDefault)
        return { type = "dropdown", text = L["Orientation"], width = 150,
                 values = { { value = "h", text = L["Horizontal"] }, { value = "v", text = L["Vertical"] } },
                 get = function() return M.db.vertical and "v" or "h" end,
                 set = function(v)
                     M.db.vertical = v == "v"
                     M.db.grow = M.db.vertical and vDefault or hDefault
                     if M:IsEnabled() then M:Refresh() end
                 end }
    end
    function C.Grow(text, labels)
        return { type = "dropdown", text = text, width = 150,
                 values = function()
                     local keys = M.db.vertical and { "up", "down" } or { "left", "right" }
                     return { { value = keys[1], text = labels[keys[1]] }, { value = keys[2], text = labels[keys[2]] } }
                 end,
                 get = function() return M.db.grow end,
                 set = function(v) M.db.grow = v; if M:IsEnabled() then M:Refresh() end end }
    end
    function C.OnReset()
        local keep = M.db.genesis
        wipe(M.db)
        EV.DB.Merge(M.db, M.defaults)
        M.db.genesis = keep
        if M:IsEnabled() then M:Refresh() end
    end
    return C
end

local Micro = EV:GetModule("MicroMenu", true)
if Micro then
    local C = Controls(Micro)
    local function NoPanel() return not Micro.db.panel end
    EV.Options:RegisterPage{
        key = "micromenu", title = L["Micro Menu"], group = "Interface", module = "MicroMenu",
        description = L["Blizzard's micro menu as flat glyphs in an EvermoreUI bar. Move it with /evui edit."],
        build = function(p)
            p:Section(L["Layout"])
            p:Dual(C.Slider("size", L["Button size"], 18, 48),
                   C.Slider("spacing", L["Spacing"], 0, 12))
            p:Dual(C.Orientation("right", "down"),
                   C.Grow(L["Grow"], { left = L["Left"], right = L["Right"], up = L["Up"], down = L["Down"] }))
            p:Dual(C.Slider("perRow", L["Buttons per line"], 1, 20, 1, L["Buttons in each row, or each column when vertical, before it wraps."]),
                   C.Reset("MicroMenu"))
            p:Section(L["Panel"])
            p:Dual(C.Toggle("panel", L["Show panel"], L["A background and border behind the buttons."]),
                   C.Slider("padding", L["Padding"], 0, 12, 1, nil, NoPanel))
            p:Section(L["Visibility"])
            p:Row(C.Toggle("petBattle", L["Hide in pet battles"], L["Blizzard's pet battle screen has its own menu."]))
            C.Fade(p)
        end,
        onReset = C.OnReset,
    }
end

local Bags = EV:GetModule("BagBar", true)
if Bags then
    local C = Controls(Bags)
    local function NoPanel() return not Bags.db.panel end
    EV.Options:RegisterPage{
        key = "bagbar", title = L["Bag Bar"], group = "Interface", module = "BagBar",
        description = L["Your backpack, bags, reagent bag and key ring in an EvermoreUI bar. Move it with /evui edit."],
        build = function(p)
            p:Section(L["Layout"])
            p:Dual(C.Slider("backpackSize", L["Backpack size"], 20, 56),
                   C.Slider("size", L["Bag size"], 18, 48))
            p:Dual(C.Orientation("left", "up"),
                   C.Grow(L["Bags run"], { left = L["Left of the backpack"], right = L["Right of the backpack"],
                                           up = L["Above the backpack"], down = L["Below the backpack"] }))
            p:Row(C.Slider("spacing", L["Spacing"], 0, 12))
            p:Dual(C.Toggle("toggle", L["Collapse button"], L["An arrow beside the backpack that folds the other bags away, like retail. Holding a bag opens them so you can drop it in."]),
                   C.Reset("BagBar"))
            p:Section(L["Free slots"])
            p:Dual(C.Toggle("freeSlots", L["Show free slots"], L["How many empty slots you have across all your bags, on the backpack."]),
                   C.Slider("countSize", L["Font size"], 8, 18, 1, nil, function() return not Bags.db.freeSlots end))
            p:Section(L["Panel"])
            p:Dual(C.Toggle("panel", L["Show panel"], L["A background and border behind the buttons."]),
                   C.Slider("padding", L["Padding"], 0, 12, 1, nil, NoPanel))
            C.Fade(p)
        end,
        onReset = C.OnReset,
    }
end
