if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  WhatsNew.lua
--  After an update, the first login shows what changed: every release
--  newer than the one you last saw, up to the one you are running. The
--  notes are CHANGELOG.md, turned into Core/Changelog.lua at release time
--  (tools/changelog/build.py), so the window and the CurseForge page say the
--  same thing. /evui new opens it any time.
--
--  The version you last saw is account-wide (DB global), so a new
--  character does not see it again. A development copy (version "dev") never
--  pops up on its own.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme

local WN = {}
EV.WhatsNew = WN

local MAX_RELEASES = 3
local max = math.max

--- "v0.10.0-beta2" -> { 0, 10, 0 }, or nil for "dev".
local function Parts(v)
    if type(v) ~= "string" then return nil end
    local a, b, c = v:match("(%d+)%.(%d+)%.?(%d*)")
    if not a then return nil end
    return { tonumber(a), tonumber(b), tonumber(c) or 0 }
end

--- -1, 0 or 1, comparing two version strings. Unknown sorts first.
function WN.Compare(x, y)
    local a, b = Parts(x), Parts(y)
    if not a or not b then return (a and 1) or (b and -1) or 0 end
    for i = 1, 3 do
        if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
    end
    return 0
end

local function Current()
    local p = Parts(EV.version)
    return p and ("%d.%d.%d"):format(p[1], p[2], p[3]) or nil
end

local function Settings()
    local g = EV.DB and EV.dbReady and EV.DB:GetGlobal()
    return g or {}
end

--- Releases to show: newer than `since` and no newer than what is running.
--- With no `since`, the latest few.
function WN.Entries(since)
    local cur = Current()
    local out = {}
    for _, r in ipairs(EV.CHANGELOG or {}) do
        local notAhead = not cur or WN.Compare(r.version, cur) <= 0
        local unseen = not since or WN.Compare(r.version, since) > 0
        if notAhead and unseen then out[#out + 1] = r end
        if #out >= MAX_RELEASES then break end
    end
    return out
end

--------------------------------------------------------------------------------
--  Rendering
--------------------------------------------------------------------------------
--- The changelog's **bold** and `code`, as colour codes.
local function Inline(s)
    local title, accent = T.Hex("title"), T.Hex("accent")
    s = s:gsub("%*%*(.-)%*%*", "|cff" .. title .. "%1|r")
    s = s:gsub("`(.-)`", "|cff" .. accent .. "%1|r")
    return s
end

local window, scroll, pool

local function Clear()
    for _, r in ipairs(pool) do r:Hide() end
    pool.used = 0
end

local function Text(size, token, bold)
    pool.used = pool.used + 1
    local fs = pool[pool.used]
    if not fs then
        fs = scroll.content:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        pool[pool.used] = fs
    end
    fs:SetFont(bold and T.FontBoldPath() or T.FontPath(), size, "")
    T.TextShadow(fs)
    fs:SetTextColor(T.RGBA(token))
    fs:ClearAllPoints()
    fs:Show()
    return fs
end

local function Fill(list)
    Clear()
    local width = max(scroll.content:GetWidth(), 300) - 24
    local y = -8
    local function place(fs, x, gapAfter, w)
        fs:SetWidth(w or (width - x))
        fs:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 12 + x, y)
        y = y - (fs:GetStringHeight() or 14) - (gapAfter or 6)
    end
    if #list == 0 then
        local fs = Text(T.SIZE.body, "textMuted")
        fs:SetText(L["No release notes in this build."])
        place(fs, 0)
    end
    for n, r in ipairs(list) do
        if n > 1 then y = y - 14 end
        local h = Text(T.SIZE.heading, "title", true)
        h:SetText((L["What's new in %s"]):format(r.version))
        place(h, 0, 8)
        for _, p in ipairs(r.intro or {}) do
            local fs = Text(T.SIZE.body, "text")
            fs:SetText(Inline(p))
            place(fs, 0, 10)
        end
        for _, sec in ipairs(r.sections or {}) do
            if sec.title and sec.title ~= "" then
                y = y - 4
                local st = Text(T.SIZE.caption, "textDisabled", true)
                st:SetText(sec.title:upper())
                place(st, 0, 6)
            end
            for _, item in ipairs(sec.items or {}) do
                local dot = Text(T.SIZE.body, "accent", true)
                dot:SetText("\226\128\162")   -- a bullet
                dot:SetWidth(12)
                dot:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 14, y)
                local fs = Text(T.SIZE.body, "text")
                fs:SetText(Inline(item))
                place(fs, 16, 6)
            end
        end
    end
    scroll:SetContentHeight(-y + 10)
    scroll:ScrollTo(0)
end

local function Build()
    if window then return window end
    local W = EV.UI
    window = W.Window("EvermoreUIWhatsNew", { title = "EvermoreUI", width = 560, height = 520 })
    window:SetPoint("CENTER")
    local foot = 48
    scroll = W.Scroll(window.body)
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -4, foot)
    pool = { used = 0 }

    local done = W.Button(window.body, L["Got it"], 110, function() window:Hide() end, "accent")
    done:SetPoint("BOTTOMRIGHT", -12, 12)
    local opts = W.Button(window.body, L["Open options"], 130, function()
        window:Hide()
        EV:OpenOptions()
    end)
    opts:SetPoint("RIGHT", done, "LEFT", -8, 0)
    local issues = T.Text(window.body, "small", "textMuted")
    issues:SetPoint("BOTTOMLEFT", 14, 20)
    issues:SetPoint("RIGHT", opts, "LEFT", -10, 0)
    issues:SetWordWrap(false)
    issues:SetText(L["Found a problem? /evui bug"])

    window:HookScript("OnShow", function() C_Timer.After(0, function() Fill(window.list or {}) end) end)
    return window
end

--- Open the window. With no argument, the latest few releases.
function WN.Show(list)
    if InCombatLockdown() then
        WN.pending = list or true
        return
    end
    Build()
    window.list = type(list) == "table" and list or WN.Entries(nil)
    window:SetTitle(("EvermoreUI %s"):format(Current() or EV.version or ""))
    if window:IsShown() then Fill(window.list) else window:Show() end
end

--------------------------------------------------------------------------------
--  After an update
--------------------------------------------------------------------------------
local function Check()
    local cur = Current()
    if not cur then return end            -- a development copy
    local g = Settings()
    if g.lastSeenVersion == cur then return end
    local since = g.lastSeenVersion
    g.lastSeenVersion = cur
    if g.whatsNew == false then return end
    -- A first install sees only the release it installed, not the history.
    local list = WN.Entries(since)
    if not since then
        list = WN.Entries(nil)
        for i = #list, 2, -1 do list[i] = nil end
    end
    if #list > 0 then WN.Show(list) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Let the login chat, the tutorial popups and loading settle first.
        C_Timer.After(4, Check)
    elseif WN.pending then
        local list = WN.pending
        WN.pending = nil
        WN.Show(type(list) == "table" and list or nil)
    end
end)

EV:RegisterSlash("new", function() WN.Show() end)
EV:RegisterSlash("changelog", function() WN.Show() end)
