if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Designer.lua
--  The nameplates' surface for the designer (EvermoreUI_Options/Designer.lua
--  has the contract). The copy is a plate built by the same widgets as every
--  real one (Core.lua, BuildPreviewPlate), with samples in it.
--
--  What moves freely: the raid mark, the quest count and the three aura rows,
--  each stored as { own, rel, x, y } on the health bar (cfg.raidMarkPos,
--  cfg.questPos, cfg.auraPos[row]). Until you move one it has no setting and
--  keeps the measured placement its widget has always used, so the plate you
--  know is unchanged by default. What hangs below the bar moves up and down:
--  the mana strip and the cast bar by their gaps, combo points by their edge.
--
--  A move that reaches further above or below the bar grows the plate's box
--  (Core.lua, Extent), which the engine positions plates by; that's pushed
--  on each commit, out of combat, which is the only time the designer runs.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule and EvermoreUI.Designers) then return end
local EV = EvermoreUI
local L = EV.L
local M = ns.module
local max, min, floor = math.max, math.min, math.floor

local function Round(v) return floor(v + 0.5) end
local function C() return M.db end

local SLOT_SIDE = {
    { value = "none", text = L["Nothing"] }, { value = "levelname", text = L["Level and name"] },
    { value = "name", text = L["Name"] }, { value = "level", text = L["Level"] },
    { value = "health", text = L["Health"] },
}
local SLOT_CENTRE = {
    { value = "none", text = L["Nothing"] }, { value = "name", text = L["Name"] },
    { value = "level", text = L["Level"] }, { value = "health", text = L["Health"] },
}

local HEALTH_TEXT = {
    { value = "none", text = L["None"] }, { value = "percent", text = L["87%"] },
    { value = "current", text = L["12.3k"] }, { value = "curpercent", text = L["12.3k  87%"] },
}
local HEALTH_COLOURS = {
    { value = "reaction", text = L["Reaction"] }, { value = "class", text = L["Class (players)"] },
}
local TEXT_STYLE = {
    { value = "both", text = L["Outline and shadow"] }, { value = "shadow", text = L["Shadow only"] },
    { value = "outline", text = L["Outline only"] },
}
local POWER_MODE = {
    { value = "mana", text = L["Only units with mana"] }, { value = "any", text = L["Any resource"] },
}
local function Textures()
    local list = {}
    for _, name in ipairs(EV.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
    return list
end

local function Controls()
    local X = {}
    local function Get(k) return function() return C()[k] end end
    local function Set(k) return function(v) C()[k] = v end end
    function X.T(k, text, tip) return { type = "toggle", text = text, tooltip = tip, get = Get(k), set = Set(k) } end
    function X.S(k, text, lo, hi, step, tip)
        return { type = "slider", text = text, min = lo, max = hi, step = step or 1, tooltip = tip, get = Get(k), set = Set(k) }
    end
    function X.D(k, text, values, width, tip)
        return { type = "dropdown", text = text, values = values, width = width or 150, tooltip = tip, get = Get(k), set = Set(k) }
    end
    function X.C(k, text, default)
        return {
            type = "colour", text = text,
            get = function() local c = C()[k] or default; return c[1], c[2], c[3] end,
            set = function(r, g, b) C()[k] = { r, g, b } end,
            reset = function() C()[k] = { default[1], default[2], default[3] } end,
            isCustom = function()
                local c = C()[k]
                if type(c) ~= "table" then return false end
                for i = 1, 3 do if math.abs((c[i] or 0) - default[i]) > 0.002 then return true end end
                return false
            end,
        }
    end
    return X
end

--- A freely placed element, stored as { own, rel, x, y }. `fallback` is
--- where it sits until moved, in the same shape, for nudging and the
--- inspector's numbers.
local function Free(key, label, region, getPos, setPos, fallback, shown, size, options)
    local e = {
        key = key, label = label, region = region, shown = shown,
        move = "free", points = "nine", anchor = "auto",
        parent = function(pf) return pf.health end,
        get = function()
            local p = getPos() or fallback()
            return p.rel, p.x, p.y
        end,
        set = function(rel, x, y, own)
            setPos({ own = own or rel, rel = rel, x = max(-300, min(300, x)), y = max(-150, min(150, y)) })
        end,
        Nudge = function(dx, dy)
            local p = getPos() or fallback()
            setPos({ own = p.own, rel = p.rel, x = (p.x or 0) + dx, y = (p.y or 0) + dy })
        end,
        Reset = function() setPos(nil) end,
        Options = options,
    }
    if size then e.getSize, e.setSize = size.get, size.set end
    return e
end

local function Elements()
    local list = {}
    local function Add(e) list[#list + 1] = e end
    local cfg = C()

    Add{
        key = "plate", label = L["Health bar"],
        region = function(pf) return pf.health end,
        getSize = function() return C().width, C().height end,
        -- Even sizes only: the plate is centred on Blizzard's, and an odd
        -- width puts its edges on half pixels (Core.lua, width).
        setSize = function(w, h)
            C().width = max(60, min(320, Round(w / 2) * 2))
            C().height = max(8, min(48, Round(h / 2) * 2))
        end,
        Reset = function() C().width, C().height = 196, 26 end,
        Options = function(p)
            ns.Settings(p, { sections = {
                [L["Plate"]] = { scale = true, targetScale = true, width = true, height = true, texture = true,
                                 healthColour = true, barShade = true, typeColour = true, typeInInstancesOnly = true },
                [L["Text"]] = true,
            } })
            p:Note(L["Width and height move in steps of two: the plate is centred on the game's, and an odd size puts its edges on half pixels."])
        end,
    }

    Add(Free("raidMark", L["Raid mark"], function(pf) return pf.raidMark end,
        function() return C().raidMarkPos end,
        function(v) C().raidMarkPos = v end,
        function() return { own = "RIGHT", rel = "LEFT", x = -4, y = 0 } end,
        nil,
        {
            get = function()
                local s = (C().raidMarkSize or 0) > 0 and C().raidMarkSize or (C().height + 4)
                return s, s
            end,
            set = function(w, h) C().raidMarkSize = max(8, min(64, Round(max(w, h)))) end,
        },
        function(p)
            local X = Controls()
            p:Row(X.S("raidMarkSize", L["Size"], 0, 64, 1, L["0 is the bar's height plus four."]))
        end))

    local quest = Free("quest", L["Quest count"], function(pf) return pf.questText end,
        function() return C().questPos end,
        function(v) C().questPos = v end,
        function() return { own = "BOTTOMRIGHT", rel = "TOPRIGHT", x = 0, y = 3 } end,
        function() return C().showQuest end, nil,
        function(p) ns.Settings(p, { sections = { [L["Text"]] = { showQuest = true, fontSize = true } } }) end)
    quest.text = true
    Add(quest)

    local ROWS = ns.AURA_ROWS or {}
    local LABEL = { mine = L["Your dots"], cc = L["Crowd control"], buff = L["Enemy buffs"] }
    for _, row in ipairs(ROWS) do
        local key = row.key
        local function Fallback()
            local _, ih = ns.AuraIconSize(row, C())
            if key == "mine" then return { own = "BOTTOMLEFT", rel = "TOPLEFT", x = 0, y = ns.AURA_LIFT } end
            if key == "cc" then return { own = "BOTTOMLEFT", rel = "RIGHT", x = ns.AURA_FLANK, y = -ih / 2 } end
            return { own = "BOTTOMRIGHT", rel = "LEFT", x = -(ns.AURA_FLANK + C().height + 6), y = -ih / 2 }
        end
        Add(Free("aura_" .. key, LABEL[key] or key,
            function(pf) return pf.pvRows and pf.pvRows[key] end,
            function() return C().auraPos and C().auraPos[key] end,
            function(v) C().auraPos = C().auraPos or {}; C().auraPos[key] = v end,
            Fallback,
            function() return C()[row.setting] end, nil,
            function(p) ns.Settings(p, { sections = { [L["Auras"]] = true } }) end))
    end

    Add{
        key = "power", label = L["Mana strip"],
        region = function(pf) return pf.power end,
        shown = function() return C().showPower and (C().powerHeight or 0) > 0 end,
        move = "nudge", units = "frame",
        get = function() return 0, -(C().powerGap or 0) end,
        set = function(_, y) C().powerGap = max(0, min(10, -y)) end,
        Nudge = function(_, dy) C().powerGap = max(0, min(10, (C().powerGap or 0) - dy)) end,
        getSize = function() return C().width, C().powerHeight end,
        setSize = function(_, h) C().powerHeight = max(2, min(16, Round(h))) end,
        Reset = function() C().powerGap, C().powerHeight = 0, 8 end,
        Options = function(p)
            ns.Settings(p, { sections = { [L["Power"]] = true } })
            p:Note(L["Shown with a sample of mana here; on real plates only units with the resource have it."])
        end,
    }

    Add{
        key = "cast", label = L["Cast bar"],
        region = function(pf) return pf.cast end,
        shown = function() return C().showCast and (C().castHeight or 0) > 0 end,
        move = "nudge", units = "frame",
        get = function() return 0, -(C().castGap or 0) end,
        set = function(_, y) C().castGap = max(0, min(10, -y)) end,
        Nudge = function(_, dy) C().castGap = max(0, min(10, (C().castGap or 0) - dy)) end,
        getSize = function() return C().width, C().castHeight end,
        setSize = function(_, h) C().castHeight = max(4, min(20, Round(h))) end,
        Reset = function() C().castGap, C().castHeight = 0, 14 end,
        Options = function(p)
            ns.Settings(p, { sections = { [L["Cast bar"]] = true } })
        end,
    }

    if EV.HasComboClass and EV.HasComboClass() then
        Add{
            key = "combo", label = L["Combo points"],
            region = function(pf) return pf.combo end,
            shown = function() return C().comboPoints end,
            move = "slot", slots = "vertical",
            getSlot = function() return C().comboSpot == "top" and "TOP" or "BOTTOM" end,
            setSlot = function(side) C().comboSpot = side == "TOP" and "top" or "bottom" end,
            Nudge = function(_, dy) C().comboY = (C().comboY or 0) + dy end,
            getSize = function()
                local n = 5
                local c = C()
                return n * c.comboWidth + (n - 1) * c.comboSpacing, c.comboHeight
            end,
            setSize = function(w, h)
                local c = C()
                c.comboWidth = max(4, min(30, Round((w - 4 * c.comboSpacing) / 5)))
                c.comboHeight = max(2, min(16, Round(h)))
            end,
            Reset = function()
                local c = C()
                c.comboWidth, c.comboHeight, c.comboSpacing, c.comboSpot, c.comboY = 12, 6, 2, "top", 0
            end,
            Options = function(p)
                ns.Settings(p, { sections = { [L["Combo points"]] = true } })
            end,
        }
    end
    -- Not a part of the plate you can point at: how plates behave. Listed,
    -- not drawn.
    Add{
        key = "behaviour", label = L["Plate behaviour"],
        Options = function(p)
            ns.Settings(p, { sections = {
                [L["Plate"]] = { offscreenPlates = true, stackPlates = true, plateMotionSpeed = true, pixelMode = true,
                                 pinPlateScale = true, verticalOffset = true, friendlyVerticalOffset = true,
                                 doFriendly = true },
                [L["Aggro"]] = true, [L["Threat"]] = true, [L["Target"]] = true, [L["Execute range"]] = true,
            } })
        end,
    }
    return list
end

EV.Designers:Register{
    key = "nameplates", title = L["Nameplates"], module = "Nameplates", kind = "canvas",
    page = "nameplates",
    note = L["A plate like every real one, with samples. Moving a part further out makes room on every plate."],
    Tabs = function() return { { value = "enemy", text = L["Enemy plate"] } } end,
    Build = function(host) return ns.BuildPreviewPlate(host) end,
    Layout = function(pf) ns.LayoutPreviewPlate(pf) end,
    Elements = function() return Elements() end,
    Snapshot = function() return EV.CopyTable(M.db) end,
    Restore = function(_, snap)
        local c = M.db
        wipe(c)
        for k, v in pairs(EV.CopyTable(snap)) do c[k] = v end
        if M:IsEnabled() then M:Restyle(); ns.Safe("platesize", ns.UpdatePlateSize) end
    end,
    Apply = function()
        if M:IsEnabled() then M:Restyle(); ns.Safe("platesize", ns.UpdatePlateSize) end
    end,
}
