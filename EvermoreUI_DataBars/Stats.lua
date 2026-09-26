if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Stats.lua
--  Two small readouts: framerate and latency. Each is its own movable
--  element with a tooltip.
--
--    [ FPS 144 ]      [ MS 42 / 87 ]
--
--  Latency shows home (realm: chat, auction house, mail), world (combat
--  and other players) or both. Values are coloured by how healthy they are,
--  using the theme's success / warning / danger colours.
--
--  FPS tooltip: now, the last minute's average and low, and memory use
--  (EvermoreUI and the heaviest addons; refreshed on hover, never in
--  combat). MS tooltip: home and world with what each covers, plus
--  bandwidth.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EV = EvermoreUI
local M = ns.module
if not M then return end
local L = EV.L
local T = EV.Theme
local floor, max, min = math.floor, math.max, math.min

M.defaults.fps = {
    enabled    = true,
    showLabel  = true,
    colourize  = true,
    background = true,
    fontSize   = 13,
    interval   = 1,      -- seconds between updates; 0 = only while hovered
    good       = 60,     -- at or above: good
    ok         = 30,     -- at or above: ok, below: poor
}
M.defaults.latency = {
    enabled    = true,
    mode       = "both",  -- "home", "world" or "both"
    showLabel  = true,
    colourize  = true,
    background = true,
    fontSize   = 13,
    interval   = 5,      -- the client itself only refreshes latency every 30s
    good       = 100,    -- below: good
    ok         = 200,    -- below: ok, at or above: poor
}
M.defaults.durability = {
    enabled    = true,
    showLabel  = true,
    colourize  = true,
    background = true,
    fontSize   = 13,
    interval   = 0,      -- event driven (UPDATE_INVENTORY_DURABILITY); 0 = hover refresh only
    good       = 50,     -- at or above: good
    ok         = 25,     -- at or above: ok, below: poor
}
M.description = "Experience bar with quest and rested segments, XP/hour and session stats, plus framerate, latency and durability readouts."

local frames = {}
local samples, sampleAt = {}, 0 -- framerate, one a second, last 60

--------------------------------------------------------------------------------
--  Helpers
--------------------------------------------------------------------------------
local function Hex(token)
    local r, g, b = T.RGBA(token)
    return ("%02x%02x%02x"):format(floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

local function Colour(text, token, on)
    if not on then return text end
    return "|cff" .. Hex(token) .. text .. "|r"
end

local function FpsToken(v, cfg)
    if v >= cfg.good then return "success" elseif v >= cfg.ok then return "warning" end
    return "danger"
end

local function MsToken(v, cfg)
    if v < cfg.good then return "success" elseif v < cfg.ok then return "warning" end
    return "danger"
end

local function DurToken(v, cfg)
    if v >= cfg.good then return "success" elseif v >= cfg.ok then return "warning" end
    return "danger"
end

local function NetStats()
    if not GetNetStats then return 0, 0, 0, 0 end
    local bIn, bOut, home, world = GetNetStats()
    return bIn or 0, bOut or 0, home or 0, world or 0
end

--------------------------------------------------------------------------------
--  Frames
--------------------------------------------------------------------------------
local function Create(key, name)
    local f = CreateFrame("Button", name, UIParent)
    f:SetFrameStrata("LOW")
    f:SetSize(80, 22)
    f:EnableMouse(true)
    f.bg = T.Fill(f, "BACKGROUND", "surface0", 0.85)
    f.bg:SetAllPoints()
    T.TokenBorder(f, "border")
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER", 0, 0)
    T.TextShadow(f.text)
    f.key = key
    function f:Paint()
        self.bg:SetColorTexture(T.RGBA("surface0", 0.85))
        T.SetBorderToken(self, "border")
        M:UpdateStats()
    end
    T.Watch(f)
    f:SetScript("OnEnter", function(self)
        M:UpdateStats(self.key)
        M:ShowStatsTooltip(self)
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

-- Width fitted to the widest value this element can show, so the box
-- doesn't twitch as numbers change.
local function Fit(f, widest)
    f.text:SetText(widest)
    local w = f.text:GetStringWidth() or 60
    local h = f.text:GetStringHeight() or 12
    EV.Pixel:SetSize(f, floor(w + 18), floor(h + 10))
end

--------------------------------------------------------------------------------
--  Update
--------------------------------------------------------------------------------
-- One framerate sample a second for the tooltip's average and low. Taken
-- whatever the update interval, so the numbers are there when you hover.
local function Sample()
    local now = GetTime()
    if now - sampleAt < 1 then return end
    sampleAt = now
    table.insert(samples, GetFramerate and GetFramerate() or 0)
    if #samples > 60 then table.remove(samples, 1) end
end

--- Redraw the readouts: both, or just one ("fps" / "latency").
function M:UpdateStats(which)
    local fps, lat, dur = frames.fps, frames.latency, frames.durability
    if which == "latency" then fps, dur = nil, nil
    elseif which == "fps" then lat, dur = nil, nil
    elseif which == "durability" then fps, lat = nil, nil end
    if dur and dur:IsShown() then
        local cfg = self.db.durability
        local d = EV:ReadDurability()
        local v = floor(d.lowest + 0.5)
        local label = cfg.showLabel and (Colour(L["Gear"], "textMuted", true) .. " ") or ""
        dur.text:SetText(label .. Colour(v .. "%", DurToken(v, cfg), cfg.colourize))
    end
    Sample()
    local rate = GetFramerate and GetFramerate() or 0
    if fps and fps:IsShown() then
        local cfg = self.db.fps
        local v = floor(rate + 0.5)
        local label = cfg.showLabel and (Colour(L["FPS"], "textMuted", true) .. " ") or ""
        fps.text:SetText(label .. Colour(tostring(v), FpsToken(v, cfg), cfg.colourize))
    end
    if lat and lat:IsShown() then
        local cfg = self.db.latency
        local _, _, home, world = NetStats()
        local value
        if cfg.mode == "home" then
            value = Colour(tostring(home), MsToken(home, cfg), cfg.colourize)
        elseif cfg.mode == "world" then
            value = Colour(tostring(world), MsToken(world, cfg), cfg.colourize)
        else
            value = Colour(tostring(home), MsToken(home, cfg), cfg.colourize) .. Colour(" / ", "textMuted", true)
                .. Colour(tostring(world), MsToken(world, cfg), cfg.colourize)
        end
        local labelText = cfg.mode == "home" and L["Home"] or cfg.mode == "world" and L["World"] or L["MS"]
        local label = cfg.showLabel and (Colour(labelText, "textMuted", true) .. " ") or ""
        lat.text:SetText(label .. value .. (cfg.showLabel and "" or Colour(" ms", "textMuted", true)))
    end
end

--------------------------------------------------------------------------------
--  Tooltips
--------------------------------------------------------------------------------
local memCache, memAt = nil, 0

local function MemoryReport()
    if InCombatLockdown() then return nil, L["Memory use is hidden in combat."] end
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage and C_AddOns and C_AddOns.GetNumAddOns) then return nil end
    if memCache and GetTime() - memAt < 10 then return memCache end
    UpdateAddOnMemoryUsage()
    local list, ours, total = {}, 0, 0
    for i = 1, C_AddOns.GetNumAddOns() do
        if C_AddOns.IsAddOnLoaded(i) then
            local name, title = C_AddOns.GetAddOnInfo(i)
            local kb = GetAddOnMemoryUsage(i) or 0
            total = total + kb
            if name and name:find("^EvermoreUI") then
                ours = ours + kb
            else
                list[#list + 1] = { title = title or name, kb = kb }
            end
        end
    end
    table.sort(list, function(a, b) return a.kb > b.kb end)
    memCache = { ours = ours, total = total, top = list }
    memAt = GetTime()
    return memCache
end

local function Mem(kb)
    if kb >= 1024 then return ("%.1f MB"):format(kb / 1024) end
    return ("%d KB"):format(floor(kb + 0.5))
end

function M:ShowStatsTooltip(owner)
    local tt = GameTooltip
    tt:SetOwner(owner, "ANCHOR_BOTTOM", 0, -6)
    local tr, tg, tb = T.RGBA("text")
    local mr, mg, mb = T.RGBA("textMuted")
    local ar, ag, ab = T.RGBA("accent")
    local function Row(left, right, token)
        local r, g, b = T.RGBA(token or "text")
        tt:AddDoubleLine(left, right, mr, mg, mb, r, g, b)
    end
    if owner.key == "durability" then
        local cfg = self.db.durability
        local d = EV:ReadDurability()
        tt:AddLine(L["Durability"], ar, ag, ab)
        Row(L["Worst item"], d.worstSlot and ("%s  %d%%"):format(EV:SlotName(d.worstSlot), floor(d.lowest + 0.5)) or "100%",
            DurToken(d.lowest, cfg))
        if d.broken > 0 then Row(L["Broken"], tostring(d.broken), "danger") end
        if d.damaged > 0 then
            local money = EV.FormatMoney and EV:FormatMoney(d.cost) or tostring(d.cost)
            Row(d.known and L["Repair cost"] or L["Repair cost, at least"], money)
        else
            tt:AddLine(L["Nothing needs repairing."], mr, mg, mb, true)
        end
        tt:Show()
        return
    end
    if owner.key == "fps" then
        local cfg = self.db.fps
        local now = GetFramerate and GetFramerate() or 0
        local sum, low = 0, math.huge
        for _, v in ipairs(samples) do sum = sum + v; low = min(low, v) end
        local avg = #samples > 0 and sum / #samples or now
        if low == math.huge then low = now end
        tt:AddLine(L["Framerate"], ar, ag, ab)
        Row(L["Now"], ("%d fps"):format(floor(now + 0.5)), FpsToken(now, cfg))
        Row(L["Average, last minute"], ("%d fps"):format(floor(avg + 0.5)), FpsToken(avg, cfg))
        Row(L["Lowest, last minute"], ("%d fps"):format(floor(low + 0.5)), FpsToken(low, cfg))
        local mem, why = MemoryReport()
        if mem then
            tt:AddLine(" ")
            tt:AddLine(L["Memory"], ar, ag, ab)
            Row(L["EvermoreUI"], Mem(mem.ours))
            for i = 1, min(5, #mem.top) do Row(mem.top[i].title, Mem(mem.top[i].kb)) end
            Row(L["All addons"], Mem(mem.total))
        elseif why then
            tt:AddLine(" ")
            tt:AddLine(why, mr, mg, mb, true)
        end
    else
        local cfg = self.db.latency
        local bIn, bOut, home, world = NetStats()
        tt:AddLine(L["Latency"], ar, ag, ab)
        Row(L["Home"], ("%d ms"):format(home), MsToken(home, cfg))
        tt:AddLine(L["Your connection to the realm: chat, mail, the auction house."], mr, mg, mb, true)
        Row(L["World"], ("%d ms"):format(world), MsToken(world, cfg))
        tt:AddLine(L["Your connection to the game world: combat, abilities, other players."], mr, mg, mb, true)
        tt:AddLine(" ")
        tt:AddLine(L["Bandwidth"], ar, ag, ab)
        Row(L["Download"], ("%.1f KB/s"):format(bIn))
        Row(L["Upload"], ("%.1f KB/s"):format(bOut))
        tt:AddLine(" ")
        tt:AddLine(L["The client refreshes latency every 30 seconds."], mr, mg, mb, true)
    end
    tt:Show()
end

--------------------------------------------------------------------------------
--  Settings and lifecycle (called from DataBars.lua)
--------------------------------------------------------------------------------
function ns.ApplyStats()
    local font = EV.Media:Fetch("font")
    for key, f in pairs(frames) do
        local cfg = M.db[key]
        f.text:SetFont(font, cfg.fontSize, "")
        f.bg:SetShown(cfg.background)
        if f.evBorder then
            for _, e in ipairs(f.evBorder.edges) do e:SetShown(cfg.background) end
        end
        local shown = cfg.enabled or (EV.Movers:IsUnlocked())
        f:SetShown(shown)
        if key == "fps" then
            Fit(f, (cfg.showLabel and (L["FPS"] .. " ") or "") .. "000")
        elseif key == "durability" then
            Fit(f, (cfg.showLabel and (L["Gear"] .. " ") or "") .. "100%")
        else
            local label = cfg.showLabel and ((cfg.mode == "home" and L["Home"] or cfg.mode == "world" and L["World"] or L["MS"]) .. " ") or ""
            Fit(f, label .. (cfg.mode == "both" and "000 / 000" or "000") .. (cfg.showLabel and "" or " ms"))
        end
        EV.Movers:Apply(key == "fps" and "FPS" or key == "durability" and "Durability" or "Latency")
    end
    M:UpdateStats()
end

function ns.EnableStats()
    frames.fps = Create("fps", "EvermoreUIFPS")
    frames.latency = Create("latency", "EvermoreUILatency")
    frames.durability = Create("durability", "EvermoreUIDurability")
    ns.statFrames = frames
    EV.Movers:Register(frames.durability, "Durability", L["Durability"], { "TOP", "TOP", 144, -6 }, {
        group = L["Data Bars"], page = "databars",
        isDisabled = function() return not M.db.durability.enabled end,
    })
    local durEvents = CreateFrame("Frame")
    durEvents:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    durEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    durEvents:RegisterEvent("MERCHANT_CLOSED")
    durEvents:SetScript("OnEvent", function() M:UpdateStats("durability") end)
    EV.Movers:Register(frames.fps, "FPS", L["Framerate"], { "TOP", "TOP", -48, -6 }, {
        group = L["Data Bars"], page = "databars",
        isDisabled = function() return not M.db.fps.enabled end,
    })
    EV.Movers:Register(frames.latency, "Latency", L["Latency"], { "TOP", "TOP", 48, -6 }, {
        group = L["Data Bars"], page = "databars",
        isDisabled = function() return not M.db.latency.enabled end,
    })
    -- Each readout updates on its own interval; 0 means only while the
    -- mouse is over it. Hovered readouts (and their tooltips) always tick
    -- once a second.
    local acc, last = 0, {}
    local ticker = CreateFrame("Frame")
    ns.statsTicker = ticker
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        Sample()
        local now = GetTime()
        for key, f in pairs(frames) do
            if f:IsShown() then
                local hovered = f:IsMouseOver()
                local interval = tonumber(M.db[key].interval) or 1
                local due = hovered and 1 or interval
                if (hovered or interval > 0) and now - (last[key] or 0) >= due then
                    last[key] = now
                    M:UpdateStats(key)
                    if hovered and GameTooltip:IsOwned(f) then M:ShowStatsTooltip(f) end
                end
            end
        end
    end)
    ns.ApplyStats()
end
