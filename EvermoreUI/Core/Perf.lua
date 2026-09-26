if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Perf.lua
--  /evui perf [seconds]: how fast each EvermoreUI addon makes garbage.
--  Samples every addon's memory once a second for the window (default 20s)
--  and adds up the growth between samples, so a garbage collection in the
--  middle doesn't hide anything. Steady growth with nothing happening means
--  something is allocating on a timer. CPU is included when the game's
--  script profiler is on (/console scriptProfile 1, then /reload).
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local running = false

local function Ours()
    local list = {}
    if not (C_AddOns and C_AddOns.GetNumAddOns) then return list end
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if name and name:find("^EvermoreUI") and C_AddOns.IsAddOnLoaded(i) then
            list[#list + 1] = { name = name, grown = 0 }
        end
    end
    return list
end

local function Run(seconds)
    if running then EV:Print(L["A perf run is already going."]) return end
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then EV:Print(L["This client can't report addon memory."]) return end
    seconds = math.max(5, math.min(tonumber(seconds) or 20, 120))
    local list = Ours()
    local profiling = GetCVarBool and GetCVarBool("scriptProfile")
    if profiling and ResetCPUUsage then ResetCPUUsage() end
    UpdateAddOnMemoryUsage()
    for _, a in ipairs(list) do a.last = GetAddOnMemoryUsage(a.name) or 0; a.start = a.last end
    running = true
    EV:Print(("%s %ds..."):format(L["Measuring for"], seconds))
    local ticks = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        ticks = ticks + 1
        UpdateAddOnMemoryUsage()
        for _, a in ipairs(list) do
            local now = GetAddOnMemoryUsage(a.name) or 0
            if now > a.last then a.grown = a.grown + (now - a.last) end
            a.last = now
        end
        if ticks < seconds then return end
        ticker:Cancel()
        running = false
        table.sort(list, function(x, y) return x.grown > y.grown end)
        EV:Print(L["Garbage made per second (and memory now):"])
        for _, a in ipairs(list) do
            local line = ("  %s: %.2f KB/s  (%.0f KB)"):format(a.name, a.grown / seconds, a.last)
            if profiling and GetAddOnCPUUsage then
                UpdateAddOnCPUUsage()
                line = line .. ("  CPU %.1f ms/s"):format((GetAddOnCPUUsage(a.name) or 0) / seconds)
            end
            print(line)
        end
        if not profiling then EV:Print(L["For CPU too: /console scriptProfile 1, /reload, run it again (turn it off after, it slows the game)."]) end
    end)
end

EV:RegisterSlash("perf", function(arg) Run(arg) end)
