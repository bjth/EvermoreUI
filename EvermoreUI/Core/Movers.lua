if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Movers.lua  (layout engine)
--  Where every EvermoreUI frame sits. The editor UI lives in EvermoreUI_Options
--  (EditMode.lua); this file only stores and applies layouts, so they work
--  with the options addon never loaded.
--
--  Per profile, in core:
--    movers[key]  = { "CENTER", "CENTER", x, y }     offset from screen centre
--    anchors[key] = { target, side, align, x, y }    glued to another element
--    matches[key] = { w = targetKey, h = targetKey } copy another's size
--
--  All values are in UIParent units and snapped to physical pixels on apply.
--  Anchored elements are placed in UIParent space (not SetPoint'd to the
--  target frame), so secure frames never hang off insecure ones.
--
--  EV.Movers:Register(frame, "XPBar", "XP Bar", { "BOTTOM", "BOTTOM", 0, 6 },
--      { setSize = fn(w, h), getSize = fn() -> w, h, page = "databars", tab = "Experience" })
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local Movers = {}
EV.Movers = Movers

local elements, order = {}, {}   -- key -> element; registration order
local pendingApply = {}
local floor, abs = math.floor, math.abs

local function Core() return EV.DB:GetCore() end
local function Ratio(frame) return frame:GetEffectiveScale() / UIParent:GetEffectiveScale() end

--------------------------------------------------------------------------------
--  Geometry (UIParent units)
--------------------------------------------------------------------------------
--- Absolute bounds of an element in UIParent units, or nil before layout.
function Movers:Bounds(key)
    local e = elements[key]
    local f = e and e.frame
    if not f then return nil end
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not l then return nil end
    local k = Ratio(f)
    l, r, t, b = l * k, r * k, t * k, b * k
    return { l = l, r = r, t = t, b = b, cx = (l + r) / 2, cy = (t + b) / 2, w = r - l, h = t - b }
end

--- Size in UIParent units.
function Movers:Size(key)
    local f = elements[key] and elements[key].frame
    if not f then return 0, 0 end
    local k = Ratio(f)
    return f:GetWidth() * k, f:GetHeight() * k
end

--------------------------------------------------------------------------------
--  Anchor maths
--  side: TOP | BOTTOM | LEFT | RIGHT (which side of the target we sit on)
--  align: START | CENTER | END along the target's edge
--         (START = left for TOP/BOTTOM, top for LEFT/RIGHT)
--------------------------------------------------------------------------------
local function AnchoredCenter(key, a)
    local tb = Movers:Bounds(a.target)
    if not tb then return nil end
    local w, h = Movers:Size(key)
    local cx, cy
    if a.side == "TOP" or a.side == "BOTTOM" then
        cy = (a.side == "TOP") and (tb.t + h / 2) or (tb.b - h / 2)
        if a.align == "START" then cx = tb.l + w / 2
        elseif a.align == "END" then cx = tb.r - w / 2
        else cx = tb.cx end
    else
        cx = (a.side == "LEFT") and (tb.l - w / 2) or (tb.r + w / 2)
        if a.align == "START" then cy = tb.t - h / 2
        elseif a.align == "END" then cy = tb.b + h / 2
        else cy = tb.cy end
    end
    local ux, uy = UIParent:GetCenter()
    return cx - ux + (a.x or 0), cy - uy + (a.y or 0)
end

--- The anchor offset that keeps an element exactly where it is now.
function Movers:OffsetForCurrentSpot(key)
    local a = Core().anchors[key]
    if not a then return end
    local saved = { target = a.target, side = a.side, align = a.align, x = 0, y = 0 }
    local bx, by = AnchoredCenter(key, saved)
    local b = self:Bounds(key)
    if not bx or not b then return 0, 0 end
    local ux, uy = UIParent:GetCenter()
    return (b.cx - ux) - bx, (b.cy - uy) - by
end

--------------------------------------------------------------------------------
--  Applying positions
--------------------------------------------------------------------------------
local depth = 0

--- Centre offset (UIParent units) the element should have, or nil when it
--- should use its raw default point.
local function Resolve(key)
    local core = Core()
    local a = core.anchors[key]
    if a and elements[a.target] then
        local x, y = AnchoredCenter(key, a)
        if x then return x, y end
    end
    local pos = core.movers[key]
    if pos and pos[1] == "CENTER" and pos[2] == "CENTER" then return pos[3], pos[4] end
    return nil
end

function Movers:Apply(key)
    local e = elements[key]
    if not e then return end
    local f = e.frame
    if f:IsProtected() and InCombatLockdown() then pendingApply[key] = true; return end

    -- Passive elements (Blizzard frames like chat) stay where Blizzard puts
    -- them until the user actually moves them.
    if e.passive and not Core().movers[key] and not Core().anchors[key] then return end

    local k = Ratio(f)
    local x, y = Resolve(key)
    f:ClearAllPoints()
    if x then
        local w, h = self:Size(key)
        local ux, uy = UIParent:GetCenter()
        -- Snap the absolute centre, then convert back to an offset, so edges
        -- land on physical pixels whatever the frame's size.
        local ax = EV.Pixel:SnapCenter(UIParent, ux + x, w) - ux
        local ay = EV.Pixel:SnapCenter(UIParent, uy + y, h) - uy
        f:SetPoint("CENTER", UIParent, "CENTER", ax / k, ay / k)
    else
        local d = e.default
        f:SetPoint(d[1], UIParent, d[2], EV.Pixel:Snap(UIParent, d[3]) / k, EV.Pixel:Snap(UIParent, d[4]) / k)
    end

    -- Anything glued to this follows it.
    depth = depth + 1
    if depth < 20 then
        for child, a in pairs(Core().anchors) do
            if a.target == key and elements[child] then self:Apply(child) end
        end
    end
    depth = depth - 1
    EV:SendMessage("EV_LAYOUT_CHANGED", key)
end

function Movers:ApplyAll()
    for _, key in ipairs(order) do self:Apply(key) end
end

--------------------------------------------------------------------------------
--  Size matching
--------------------------------------------------------------------------------
function Movers:ApplyMatches(targetKey)
    for key, m in pairs(Core().matches) do
        local e = elements[key]
        if e and e.setSize and (m.w == targetKey or m.h == targetKey) and elements[targetKey] then
            local tw, th = self:Size(targetKey)
            local k = Ratio(e.frame)
            e.setSize(m.w == targetKey and tw / k or nil, m.h == targetKey and th / k or nil)
        end
    end
end

function Movers:GetMatch(key) return Core().matches[key] end

function Movers:SetMatch(key, dim, target)
    local m = Core().matches[key] or {}
    m[dim] = target
    if not m.w and not m.h then Core().matches[key] = nil else Core().matches[key] = m end
    if target then self:ApplyMatches(target) end
end

--------------------------------------------------------------------------------
--  Registration
--------------------------------------------------------------------------------
function Movers:Register(frame, key, label, default, opts)
    local e = { key = key, frame = frame, label = label or key,
                default = default or { "CENTER", "CENTER", 0, 0 } }
    if opts then for k, v in pairs(opts) do e[k] = v end end
    if not elements[key] then order[#order + 1] = key end
    elements[key] = e

    frame:HookScript("OnSizeChanged", function()
        -- Centre-anchored, so a resize grows both ways; re-snap and carry
        -- anything glued or size-matched to us along.
        Movers:Apply(key)
        Movers:ApplyMatches(key)
    end)
    self:Apply(key)
    EV:SendMessage("EV_MOVER_REGISTERED", key)
end

--- Forget an element (e.g. a deleted aura tracker). Its saved layout goes too.
function Movers:Unregister(key)
    if not elements[key] then return end
    elements[key] = nil
    for i, k in ipairs(order) do if k == key then table.remove(order, i) break end end
    local core = Core()
    core.movers[key], core.anchors[key], core.matches[key] = nil, nil, nil
    for child, a in pairs(core.anchors) do
        if a.target == key then self:ClearAnchor(child) end
    end
    EV:SendMessage("EV_MOVER_REGISTERED", key)
end

function Movers:Get(key) return elements[key] end
function Movers:Keys() return order end
function Movers:IsResizable(key) return elements[key] and elements[key].setSize ~= nil end

--------------------------------------------------------------------------------
--  Position API (used by the editor and options pages)
--------------------------------------------------------------------------------
--- Current centre offset from the screen centre, UIParent units.
function Movers:GetOffset(key)
    local b = self:Bounds(key)
    if not b then
        local x, y = Resolve(key)
        return x or 0, y or 0
    end
    local ux, uy = UIParent:GetCenter()
    return b.cx - ux, b.cy - uy
end

--- Place by centre offset. Anchored elements keep their anchor and take the
--- move as a new anchor offset.
function Movers:SetOffset(key, x, y)
    if not elements[key] then return end
    local core = Core()
    local a = core.anchors[key]
    if a and elements[a.target] then
        local bx, by = AnchoredCenter(key, { target = a.target, side = a.side, align = a.align, x = 0, y = 0 })
        if bx then a.x, a.y = x - bx, y - by end
    else
        core.movers[key] = { "CENTER", "CENTER", x, y }
    end
    self:Apply(key)
end

function Movers:GetOffsetPx(key)
    local x, y = self:GetOffset(key)
    return EV.Pixel:ToPixels(x), EV.Pixel:ToPixels(y)
end

function Movers:SetOffsetPx(key, px, py)
    self:SetOffset(key, EV.Pixel:FromPixels(px), EV.Pixel:FromPixels(py))
end

function Movers:Reset(key)
    local core = Core()
    core.movers[key], core.anchors[key] = nil, nil
    local e = elements[key]
    if e and e.onReset then e.onReset() end
    self:Apply(key)
end

--------------------------------------------------------------------------------
--  Anchors
--------------------------------------------------------------------------------
function Movers:GetAnchor(key) return Core().anchors[key] end

--- True if target (or anything it hangs off) is key: anchoring would loop.
function Movers:WouldCycle(key, target)
    local seen = 0
    local cur = target
    while cur and seen < 50 do
        if cur == key then return true end
        local a = Core().anchors[cur]
        cur = a and a.target
        seen = seen + 1
    end
    return false
end

function Movers:SetAnchor(key, target, side, align, keepSpot)
    if not target then return self:ClearAnchor(key) end
    if not elements[key] or not elements[target] or self:WouldCycle(key, target) then return false end
    local core = Core()
    core.anchors[key] = { target = target, side = side or "BOTTOM", align = align or "CENTER", x = 0, y = 0 }
    if keepSpot then
        local x, y = self:OffsetForCurrentSpot(key)
        core.anchors[key].x, core.anchors[key].y = x or 0, y or 0
    end
    self:Apply(key)
    return true
end

function Movers:ClearAnchor(key)
    local core = Core()
    if not core.anchors[key] then return end
    local x, y = self:GetOffset(key)
    core.anchors[key] = nil
    core.movers[key] = { "CENTER", "CENTER", x, y }
    self:Apply(key)
end

--- Keys anchored (directly or through a chain) to key.
function Movers:Descendants(key, out)
    out = out or {}
    for child, a in pairs(Core().anchors) do
        if a.target == key and not out[child] then
            out[child] = true
            self:Descendants(child, out)
        end
    end
    return out
end

--------------------------------------------------------------------------------
--  Snapshots (edit mode save / discard)
--------------------------------------------------------------------------------
function Movers:Snapshot()
    local core = Core()
    local sizes = {}
    for key, e in pairs(elements) do
        if e.getSize then sizes[key] = { e.getSize() } end
    end
    return {
        movers  = EV.CopyTable(core.movers),
        anchors = EV.CopyTable(core.anchors),
        matches = EV.CopyTable(core.matches),
        sizes   = sizes,
    }
end

function Movers:Restore(snap)
    local core = Core()
    wipe(core.movers);  for k, v in pairs(snap.movers)  do core.movers[k]  = v end
    wipe(core.anchors); for k, v in pairs(snap.anchors) do core.anchors[k] = v end
    wipe(core.matches); for k, v in pairs(snap.matches) do core.matches[k] = v end
    for key, s in pairs(snap.sizes) do
        local e = elements[key]
        if e and e.setSize then e.setSize(s[1], s[2]) end
    end
    self:ApplyAll()
end

--------------------------------------------------------------------------------
--  Edit mode entry (the editor itself loads on demand)
--------------------------------------------------------------------------------
function Movers:Unlock()
    if InCombatLockdown() then EV:Print(L["Edit mode is available out of combat."]); return end
    if not C_AddOns.IsAddOnLoaded("EvermoreUI_Options") then
        local ok, reason = C_AddOns.LoadAddOn("EvermoreUI_Options")
        if not ok then EV:Print(L["Couldn't load EvermoreUI_Options:"], tostring(reason)); return end
    end
    if EV.EditMode then EV.EditMode:Enter() end
end

function Movers:Lock()
    if EV.EditMode and EV.EditMode:IsActive() then EV.EditMode:Exit() end
end

function Movers:Toggle()
    if EV.EditMode and EV.EditMode:IsActive() then self:Lock() else self:Unlock() end
end

function Movers:IsUnlocked() return EV.EditMode ~= nil and EV.EditMode:IsActive() end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    for key in pairs(pendingApply) do
        pendingApply[key] = nil
        Movers:Apply(key)
    end
end)
