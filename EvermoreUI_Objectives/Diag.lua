if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Diag.lua
--  /evui objdiag: a snapshot of everything that decides whether the panel
--  can scroll (Blizzard's layout, our measurements, the scroll frame, what
--  the mouse is over and whether wheel events reach us). Printed to chat and
--  saved to EvermoreUIDB._dev.objectives so it can be read from the
--  SavedVariables file after a /reload.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI

local wheel = { count = 0 }
local seenFoci = {}   -- what the mouse was over while it was over the panel
local layouts = 0

local function Name(f)
    if not f then return "nil" end
    local ok, n = pcall(function() return f.GetDebugName and f:GetDebugName() or f:GetName() end)
    return (ok and n and n ~= "") and n or tostring(f)
end

local function R(v)
    if type(v) ~= "number" or ns.issecret(v) then return tostring(v) end
    return math.floor(v * 10 + 0.5) / 10
end

-- Watch the mouse over the panel, cheaply.
local watch = CreateFrame("Frame")
local acc = 0
-- Only while a diagnostic session is open (/evui objdiag arms it): it
-- builds strings, so it must not run all the time.
watch:Hide()
watch:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 then return end
    acc = 0
    local panel = ns.panel
    if not (panel and panel:IsVisible() and panel:IsMouseOver()) or not GetMouseFoci then return end
    local list = {}
    for i, f in ipairs(GetMouseFoci() or {}) do
        if i > 6 then break end
        local wheelOn = f.IsMouseWheelEnabled and f:IsMouseWheelEnabled()
        list[#list + 1] = Name(f) .. (wheelOn and " [wheel]" or "")
    end
    local key = table.concat(list, " > ")
    if key ~= "" then seenFoci[key] = (seenFoci[key] or 0) + 1 end
end)

function ns.DiagHook()
    local scroll = ns.scroll
    if scroll and not wheel.hooked then
        wheel.hooked = true
        scroll:HookScript("OnMouseWheel", function(_, delta)
            wheel.count = wheel.count + 1
            wheel.lastDelta = delta
            wheel.scrollAfter = R(scroll:GetScroll())
        end)
    end
    local layout = ns.Layout
    ns.Layout = function(...) layouts = layouts + 1; return layout(...) end
end

local function Snapshot()
    local t = ObjectiveTrackerFrame
    local s = ns.scroll
    local sf = s and s.scrollFrame
    local d = {
        time = date("%H:%M:%S"),
        settings = { width = M.db.width, height = M.db.height, fitContent = M.db.fitContent, collapsed = M.db.collapsed },
        layouts = layouts,
        measured = R(ns.ContentHeight and ns.ContentHeight()),
        panel = { w = R(ns.panel:GetWidth()), h = R(ns.panel:GetHeight()), shown = ns.panel:IsVisible(), alpha = R(ns.panel:GetAlpha()) },
        scroll = s and {
            shown = s:IsVisible(), h = R(s:GetHeight()), wheelEnabled = s:IsMouseWheelEnabled(),
            sfH = R(sf:GetHeight()), contentH = R(s.content:GetHeight()),
            range = R(s.content:GetHeight() - sf:GetHeight()), offset = R(sf:GetVerticalScroll()),
            nativeRange = R(sf:GetVerticalScrollRange()),
        },
        sheet = ns.sheet and { h = R(ns.sheet:GetHeight()), w = R(ns.sheet:GetWidth()) },
        wheel = { count = wheel.count, lastDelta = wheel.lastDelta, scrollAfter = wheel.scrollAfter },
        foci = {},
    }
    if t then
        local p1, rel = t:GetPoint(1)
        d.tracker = {
            parentIsSheet = t:GetParent() == ns.sheet, parent = Name(t:GetParent()),
            shown = t:IsShown(), visible = t:IsVisible(),
            h = R(t:GetHeight()), top = R(t:GetTop()), bottom = R(t:GetBottom()),
            points = t:GetNumPoints(), point1 = tostring(p1) .. " " .. Name(rel),
            ignoreFPM = t.ignoreFramePositionManager and true or false,
            clamped = t.IsClampedToScreen and t:IsClampedToScreen() or false,
            defaultPos = t.IsInDefaultPosition and t:IsInDefaultPosition() or "n/a",
            topPad = R(t.topModulePadding), collapsed = t.IsCollapsed and t:IsCollapsed() or "n/a",
            scale = R(t:GetEffectiveScale()), ourScale = R(ns.panel:GetEffectiveScale()),
        }
        d.modules = {}
        for i, m in ipairs(t.modules or {}) do
            d.modules[i] = {
                name = Name(m), shown = m:IsShown(), parentIsTracker = m:GetParent() == t,
                contents = R(m.GetContentsHeight and m:GetContentsHeight()),
                h = R(m:GetHeight()), bottom = R(m:GetBottom()),
                truncated = m.IsTruncated and m:IsTruncated() or false,
            }
        end
    end
    for k, n in pairs(seenFoci) do d.foci[#d.foci + 1] = n .. "x  " .. k end
    return d
end

local function Print(prefix, v, depth)
    depth = depth or 0
    if depth > 3 then return end
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            local x = v[k]
            if type(x) == "table" then
                Print(prefix .. tostring(k) .. ".", x, depth + 1)
            else
                EV:Print(prefix .. tostring(k) .. " = " .. tostring(x))
            end
        end
    end
end

EV:RegisterSlash("objdiag", function()
    if not ns.panel then EV:Print("Objectives isn't running.") return end
    watch:Show() -- start watching the mouse for the next snapshot
    local d = Snapshot()
    EvermoreUIDB._dev = type(EvermoreUIDB._dev) == "table" and EvermoreUIDB._dev or {}
    EvermoreUIDB._dev.objectives = d
    Print("", d)
    EV:Print("Saved. /reload so it's written to disk.")
end)
