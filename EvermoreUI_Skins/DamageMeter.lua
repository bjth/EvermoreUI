if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  DamageMeter.lua
--  Blizzard's built-in damage meter (Blizzard_DamageMeter) in our style.
--  Forever has it built in, so it is the meter most players will use; it
--  should look like the rest of the interface rather than the one window in
--  retail art.
--
--  What it covers, for each session window (DamageMeterSessionWindow1-3)
--  and its breakdown (the source window a bar opens):
--    * the header strip and the window background become our title bar
--      and surface, with a hairline border. The background still follows
--      Blizzard's own opacity setting (it sets the alpha, we mirror it).
--    * the bars: our statusbar texture, a sunk track behind the fill, our
--      font on the name and value, a bordered icon. Class colours, bar
--      height, spacing, text size and the rest stay Blizzard's settings,
--      set in its own settings menu, and keep working.
--    * the dropdowns, the minimise button and the scroll bars go through
--      the generic parts, as they would in any other window.
--
--  It is not in UIPanelWindows or UISpecialFrames, so Discover never meets
--  it: the windows are taken here, at login and whenever Blizzard sets one
--  up (DamageMeter:SetupSessionWindow). Bars are pooled by the scroll box
--  and dressed as they're acquired.
--
--  Nothing is moved or resized. Nothing is written onto Blizzard's frames:
--  our textures and flags live in S.D's weak table.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S, T = ns.S, EV.Theme
if not S then return end
local M = S.module

M.defaults.damageMeter = true      -- skin the built-in damage meter
M.defaults.dmTexture = ""          -- bar texture; "" follows the suite's statusbar
M.defaults.dmOutline = false       -- outline the bar text rather than a shadow

local function On()
    return M.db and M.db.enabled ~= false and M.db.damageMeter ~= false
end

local function BarTexture()
    local name = M.db.dmTexture
    if name == "" then name = nil end
    return EV.Media:Fetch("statusbar", name)
end

--------------------------------------------------------------------------------
--  Bars
--------------------------------------------------------------------------------
local function EntryFonts(entry)
    local sb = entry.StatusBar
    if not sb then return end
    local font = T.FontPath()
    local flags = M.db.dmOutline and "OUTLINE" or ""
    for _, fs in ipairs({ sb.Name, sb.Value }) do
        if fs and fs.SetFont then
            pcall(fs.SetFont, fs, font, 12, flags)
            T.TextShadow(fs, not M.db.dmOutline)
        end
    end
end

local function EntryLook(entry)
    local d = S.D(entry)
    local sb = entry.StatusBar
    if not (sb and d.dmTrack) then return end
    -- Blizzard's bar shadow and its edge: gone, whatever style is picked.
    for _, r in ipairs(entry.BackgroundRegions or {}) do S.Mute(r) end
    local path = BarTexture()
    if d.dmTex ~= path then
        d.dmTex = path
        sb:SetStatusBarTexture(path)
        -- The colour lives on the texture; put Blizzard's back on ours.
        local c = entry.statusBarColor
        local tex = sb:GetStatusBarTexture()
        if c and c.GetRGB and tex then tex:SetVertexColor(c:GetRGB()) end
    end
    d.dmTrack:SetColorTexture(T.RGBA("surfaceSunk", 0.7))
    if entry.Icon and entry.Icon.Icon then entry.Icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
end

local function Entry(entry)
    if not (S.Alive(entry) and entry.StatusBar) then return end
    local d = S.D(entry)
    if not d.dm then
        d.dm = true
        S.claimed[entry] = "damageMeter"
        local sb = entry.StatusBar
        d.dmTrack = S.Ours(sb:CreateTexture(nil, "BACKGROUND", nil, -8))
        d.dmTrack:SetAllPoints(sb)
        if entry.Icon then S.NewKit(entry):Border(entry.Icon, "border") end
        -- Style, background and text size are all Blizzard's settings; each
        -- puts its own art or font back, so follow them.
        for _, method in ipairs({ "UpdateStyle", "UpdateBackground" }) do
            if type(entry[method]) == "function" then
                hooksecurefunc(entry, method, function(self) if On() then EntryLook(self) end end)
            end
        end
        if type(entry.SetTextScale) == "function" then
            hooksecurefunc(entry, "SetTextScale", function(self) if On() then EntryFonts(self) end end)
        end
        T.Watch(d.dmTrack)
        d.dmTrack.Paint = function() EntryLook(entry) end
    end
    EntryLook(entry)
    EntryFonts(entry)
end

local function FollowBars(box)
    if not (S.Alive(box) and ScrollUtil and ScrollUtil.AddAcquiredFrameCallback) then return end
    local d = S.D(box)
    if d.dmFollowed then return end
    d.dmFollowed = true
    ScrollUtil.AddAcquiredFrameCallback(box, function(_, entry) if On() then Entry(entry) end end, nil, false)
    if box.ForEachFrame then pcall(box.ForEachFrame, box, function(entry) Entry(entry) end) end
end

--------------------------------------------------------------------------------
--  Windows
--------------------------------------------------------------------------------
local function Panel(k, frame, theirs, alphaFrom, below)
    -- Our surface under everything, their art muted. Blizzard drives the
    -- opacity by setting its background's alpha; ours copies it.
    local d = S.D(frame)
    if not d.dmFill then
        d.dmFill = S.Ours(frame:CreateTexture(nil, "BACKGROUND", nil, -8))
        -- Under a header, start below it: the two share a frame level, and
        -- two frames' backgrounds at one level have no reliable order.
        if below then
            d.dmFill:SetPoint("TOPLEFT", below, "BOTTOMLEFT")
            d.dmFill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
        else
            d.dmFill:SetAllPoints(frame)
        end
        T.Watch(d.dmFill)
        d.dmFill.Paint = function(self2) self2:SetColorTexture(T.RGBA("surface0")) end
    end
    d.dmFill:SetColorTexture(T.RGBA("surface0"))
    local a = 1
    if alphaFrom then
        local ok, v = pcall(alphaFrom)
        a = ok and S.Num(v) or 1
    end
    d.dmFill:SetAlpha(a)
    if theirs then S.Mute(theirs) end
    k:Border(frame, "border")
end

local function Source(win)
    local src = win.MinimizeContainer and win.MinimizeContainer.SourceWindow
    if not S.Alive(src) then return end
    local k = S.NewKit(src)
    Panel(k, src, src.Background, function() return src.GetBackgroundAlpha and src:GetBackgroundAlpha() end)
    local d = S.D(src)
    if not d.dm then
        d.dm = true
        if type(src.SetBackgroundAlpha) == "function" then
            hooksecurefunc(src, "SetBackgroundAlpha", function() if On() then Source(win) end end)
        end
        if src.ScrollBar then S.Walk(src.ScrollBar, 0) end
        if src.CloseButton then S.Walk(src.CloseButton, 0) end
        FollowBars(src.ScrollBox)
    end
end

local function Window(win)
    if not (On() and S.Alive(win)) then return end
    local k = S.NewKit(win)
    local box = win.MinimizeContainer

    -- The header: their strip out, our title bar in, with a hairline under it.
    local d = S.D(win)
    if win.Header then
        S.Mute(win.Header)
        if not d.dmHead then
            d.dmHead = S.Ours(win:CreateTexture(nil, "BACKGROUND", nil, -7))
            d.dmHead:SetAllPoints(win.Header)
            d.dmRule = S.Ours(win:CreateTexture(nil, "BORDER", nil, 6))
            d.dmRule:SetPoint("BOTTOMLEFT", win.Header, "BOTTOMLEFT")
            d.dmRule:SetPoint("BOTTOMRIGHT", win.Header, "BOTTOMRIGHT")
            d.dmRule:SetHeight(1)
            if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(d.dmRule) end
            T.Watch(d.dmHead)
            d.dmHead.Paint = function()
                d.dmHead:SetColorTexture(T.RGBA("titleBar"))
                d.dmRule:SetColorTexture(T.RGBA("divider"))
            end
        end
        d.dmHead.Paint()
    end

    if box then
        Panel(k, box, box.Background, function() return win.GetBackgroundAlpha and win:GetBackgroundAlpha() end, win.Header)
    end

    -- Header text: the timer, the meter type and the session name.
    k:Label(win.SessionTimer, "textMuted", true)
    if win.DamageMeterTypeDropdown then k:Label(win.DamageMeterTypeDropdown.TypeName, "title", true) end
    if win.SessionDropdown then k:Label(win.SessionDropdown.SessionName, "text", true) end
    if box and box.NotActive then k:Label(box.NotActive, "textMuted") end

    if not d.dm then
        d.dm = true
        -- The generic parts for the controls; the bars are ours alone.
        for _, c in ipairs({ win.DamageMeterTypeDropdown, win.SessionDropdown, win.SettingsDropdown,
                             win.MinimizeButton, box and box.ScrollBar }) do
            if c then S.Walk(c, 0) end
        end
        if type(win.UpdateBackground) == "function" then
            hooksecurefunc(win, "UpdateBackground", function(self) if On() then Window(self) end end)
        end
        if box then
            FollowBars(box.ScrollBox)
            if box.LocalPlayerEntry then Entry(box.LocalPlayerEntry) end
        end
    end
    Source(win)
end
ns.SkinDamageMeterWindow = Window

--- Every session window Blizzard has made so far.
local function All()
    for i = 1, 3 do
        local w = _G["DamageMeterSessionWindow" .. i]
        if w then Window(w) end
    end
end

local Hook

--- Re-dress everything after a setting changes (texture, outline).
function ns.RefreshDamageMeter()
    if not On() then return end
    Hook()
    All()
    for i = 1, 3 do
        local w = _G["DamageMeterSessionWindow" .. i]
        local box = w and w.MinimizeContainer
        if box and box.ScrollBox and box.ScrollBox.ForEachFrame then
            pcall(box.ScrollBox.ForEachFrame, box.ScrollBox, function(e) Entry(e) end)
        end
        local src = box and box.SourceWindow
        if src and src.ScrollBox and src.ScrollBox.ForEachFrame then
            pcall(src.ScrollBox.ForEachFrame, src.ScrollBox, function(e) Entry(e) end)
        end
    end
end

local hooked = false
function Hook()
    if hooked or not DamageMeter then return end
    hooked = true
    if type(DamageMeter.SetupSessionWindow) == "function" then
        hooksecurefunc(DamageMeter, "SetupSessionWindow", function(_, _, windowData)
            local w = windowData and windowData.sessionWindow
            if w then C_Timer.After(0, function() Window(w) end) end
        end)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name ~= "Blizzard_DamageMeter" then return end
    if not On() then return end
    Hook()
    C_Timer.After(0, All)
end)
