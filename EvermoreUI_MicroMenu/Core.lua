if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  EvermoreUI Micro Menu & Bags
--
--  Same idea as the action bars: Blizzard's own buttons are adopted into
--  EvermoreUI bars, laid out and dressed by us, and Blizzard's containers
--  (MicroMenuContainer, BagsBar) are parked under a hidden frame so Edit
--  Mode has nothing of theirs left to show. Blizzard keeps all the
--  behaviour: clicks, keybinds, tooltips, alerts, pushed states for open
--  panels, bag expansion and free-slot counts.
--
--  Blizzard still re-anchors some of these buttons (BagsBar:Layout runs from
--  an EventRegistry callback we can't hook). Each adopted button is pinned:
--  a post-hook on its SetPoint / SetSize puts it straight back in our slot,
--  so there's never a frame with it in the wrong place.
--
--  Files: Core (shared helpers), Micro (micro menu), Bags (bag bar).
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns
local T = EV.Theme
local min, max = math.min, math.max

ns.GLYPH = T.MEDIA .. "micro_"

-- Where Blizzard's emptied containers go.
local hidden = CreateFrame("Frame", "EvermoreUIMicroHidden", UIParent)
hidden:Hide()
ns.hidden = hidden

--------------------------------------------------------------------------------
--  Combat queue. Nothing here is protected on Forever today, but if a
--  button ever turns protected we wait rather than cause "action blocked".
--------------------------------------------------------------------------------
local queue = {}
local qf = CreateFrame("Frame")
qf:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    local list = queue
    queue = {}
    for _, f in pairs(list) do
        xpcall(f, geterrorhandler())
    end
end)
function ns.Safe(key, fn, frame)
    if not (InCombatLockdown() and (not frame or (frame.IsProtected and frame:IsProtected()))) then
        return fn()
    end
    queue[key] = fn
    qf:RegisterEvent("PLAYER_REGEN_ENABLED")
end

--- Retire a Blizzard container we've emptied: invisible and click-through,
--- but still parented and shown. Hiding it (or parking it under a hidden
--- frame) leaves its children without a screen rect, and Blizzard's own
--- Edit Mode code measures them: "attempt to compare two nil values" in
--- MicroMenuContainer when Edit Mode opens or closes.

--- Retire a Blizzard Edit Mode system: no highlight, no selection, so it
--- stops appearing in Blizzard's Edit Mode at all. Blizzard's own systems
--- use defaultHideSelection for this; the hook covers anything that
--- highlights it anyway.
local function RetireFromEditMode(frame)
    if type(frame.HighlightSystem) ~= "function" then return end
    frame.defaultHideSelection = true
    hooksecurefunc(frame, "HighlightSystem", function(f)
        if f.ClearHighlight then f:ClearHighlight() end
    end)
    if frame.isHighlighted and frame.ClearHighlight then frame:ClearHighlight() end
end

local retired = setmetatable({}, { __mode = "k" })
function ns.Park(frame)
    if not frame or retired[frame] then return end
    retired[frame] = true
    ns.Safe("park" .. tostring(frame), function()
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        if frame.EnableMouseWheel then frame:EnableMouseWheel(false) end
        RetireFromEditMode(frame)
    end, frame)
end

--------------------------------------------------------------------------------
--  Pinning: our slot for each adopted button, restored whenever Blizzard
--  moves or resizes it.
--------------------------------------------------------------------------------
local slots = setmetatable({}, { __mode = "k" })   -- button -> { holder, x, y, w, h }
local seating = false

local function Seat(b)
    local s = slots[b]
    if not s or seating then return end
    if InCombatLockdown() and b:IsProtected() then
        ns.Safe("seat" .. tostring(b), function() Seat(b) end)
        return
    end
    seating = true
    if b:GetParent() ~= s.holder then b:SetParent(s.holder) end
    -- Blizzard's buttons keep the strata / level they had in its menu; make
    -- sure they sit above our panel, not under it.
    local strata = s.holder:GetFrameStrata()
    if b:GetFrameStrata() ~= strata then b:SetFrameStrata(strata) end
    local lvl = s.holder:GetFrameLevel() + 2
    if b:GetFrameLevel() < lvl then b:SetFrameLevel(lvl) end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", s.holder, "TOPLEFT", s.x, s.y)
    b:SetSize(s.w, s.h)
    seating = false
end

--- Put b at (x, y) inside holder at w x h, and keep it there.
function ns.Place(b, holder, x, y, w, h)
    local s = slots[b]
    if not s then
        s = {}
        slots[b] = s
        hooksecurefunc(b, "SetPoint", Seat)
        hooksecurefunc(b, "SetSize", Seat)
    end
    s.holder, s.x, s.y, s.w, s.h = holder, x, y, w, h
    Seat(b)
end

--- Run a relayout without moving one button on screen (the backpack, or a
--- bar's first button): wherever the change puts it inside the resized bar,
--- the bar's mover shifts by the difference. So switching orientation,
--- direction or sizes grows the bar away from that button instead of round
--- its centre.
local function Centre(b)
    local s = slots[b]
    if not s then return end
    local w, h = s.holder:GetWidth(), s.holder:GetHeight()
    return s.x + s.w / 2 - w / 2, h / 2 + s.y - s.h / 2, s.holder
end
function ns.Keep(holder, key, b, relayout)
    local bx, by, was = nil, nil, nil
    if b then bx, by, was = Centre(b) end
    relayout()
    if not (bx and was == holder) then return end
    local ax, ay, now = Centre(b)
    if not ax or now ~= holder then return end
    local dx, dy = bx - ax, by - ay
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return end
    local k = holder:GetScale()
    local ox, oy = EV.Movers:GetOffset(key)
    EV.Movers:SetOffset(key, ox + dx * k, oy + dy * k)
end

--- Stop pinning (button parked with a hidden parent).
function ns.Unplace(b, parent)
    slots[b] = nil
    if parent and b:GetParent() ~= parent then b:SetParent(parent) end
end

--------------------------------------------------------------------------------
--  Holder: our bar frame with an optional panel behind the buttons.
--------------------------------------------------------------------------------
function ns.Holder(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)
    f:SetSize(40, 40)
    f.bg = T.Fill(f, "BACKGROUND", "surface1", 0.92, -8)
    f.bg:SetAllPoints()
    f.edge = CreateFrame("Frame", nil, f)
    f.edge:SetAllPoints()
    f.edge:EnableMouse(false)
    T.TokenBorder(f.edge, "border")
    function f:SetPanel(on)
        self.bg:SetShown(on)
        self.edge:SetShown(on)
    end
    f.Paint = function()
        f.bg:SetColorTexture(T.RGBA("surface1", 0.92))
        T.SetBorderToken(f.edge, "border")
    end
    T.Watch(f)
    return f
end

--------------------------------------------------------------------------------
--  Mouseover fade. Event driven (enter / leave on the bar and its buttons),
--  with a short OnUpdate only while an alpha change is running.
--------------------------------------------------------------------------------
function ns.Fader(holder, cfgFn)
    local fader = CreateFrame("Frame", nil, holder)
    fader:Hide()
    local target, alpha = 1, 1
    fader:SetScript("OnUpdate", function(self, dt)
        local step = dt * 6
        if alpha < target then alpha = min(target, alpha + step) else alpha = max(target, alpha - step) end
        holder:SetAlpha(alpha)
        if alpha == target then self:Hide() end
    end)
    local function Want()
        local cfg = cfgFn()
        if not cfg.fade then return 1 end
        if holder:IsMouseOver(2, -2, -2, 2) then return 1 end
        if GetCursorInfo() and holder.acceptsCursor then return 1 end
        return cfg.fadeAlpha
    end
    local api = {}
    function api.Update(instant)
        target = Want()
        if instant then
            alpha = target
            holder:SetAlpha(alpha)
            fader:Hide()
        elseif alpha ~= target then
            fader:Show()
        end
    end
    local pending = false
    local function Later()
        if pending then return end
        pending = true
        C_Timer.After(0.1, function() pending = false; api.Update() end)
    end
    function api.Watch(frame)
        frame:HookScript("OnEnter", function() api.Update() end)
        frame:HookScript("OnLeave", Later)
    end
    holder:EnableMouse(true)
    api.Watch(holder)
    return api
end

--- Grow direction, valid for the orientation: horizontal bars grow left or
--- right, vertical ones up or down.
function ns.Grow(cfg, hDefault, vDefault)
    local g = cfg.grow
    if cfg.vertical then
        return (g == "up" or g == "down") and g or vDefault
    end
    return (g == "left" or g == "right") and g or hDefault
end

--- Screen centre of a Blizzard frame as a mover offset, for the first run.
function ns.CentreOf(frame)
    if not (frame and frame.GetCenter) then return end
    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return end
    if issecretvalue and (issecretvalue(cx) or issecretvalue(cy)) then return end
    local k = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * k - ux, cy * k - uy
end
