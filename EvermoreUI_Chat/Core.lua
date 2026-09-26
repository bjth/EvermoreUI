if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Core.lua
--  Chat module definition, settings and the helpers every chat file shares.
--
--  How EvermoreUI chat works (four layers, one file each):
--    Chat.lua    our panels, the edit box, Blizzard chrome, position, fade
--    Engine.lua  the display plane: our own message frames draw every line
--    Tabs.lua    tab faces drawn over Blizzard's invisible, clickable tabs
--    Sidebar.lua the icon strip beside the main window
--  Blizzard's chat frames keep running untouched as the secure data plane:
--  they format every message, own every hyperlink click, every tab click and
--  menu, and every temporary whisper window. We only draw.
--
--  Taint rules (every file follows these, do not relax):
--    * never write fields onto Blizzard frames or tables; our state lives in
--      the CFD side table keyed by frame
--    * never hooksecurefunc an FCF_* function, and never call dock or window
--      management functions (FCFDock_SelectWindow and friends)
--    * never HookScript a Blizzard chat frame's OnShow/OnHide/OnEvent/
--      OnSizeChanged, or any edit box script that runs inside chat-state
--      changes; EventRegistry callbacks are the safe substitute
--    * never hooksecurefunc SetAlpha on Blizzard frames; re-assert instead
--    * never parent our frames to Blizzard chat widgets, never reparent theirs
--    * position our panels numerically from Blizzard rects, deferred a tick
--    * secret strings pass through whole: no concat, compare, find or length
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end -- stale-parent guard
local EV = EvermoreUI
EV._ModuleNS[ADDON_NAME] = ns

local M = EV:NewModule("Chat", {
    -- Panel
    bgAlpha        = 0.72,
    border         = true,
    dividers       = true,
    tabsInPanel    = true,
    -- Text
    font           = "",        -- "" follows General > Font
    outline        = "NONE",
    shadow         = true,
    overrideSize   = false,
    fontSize       = 14,
    -- Input
    inputOnTop     = false,
    editHeight     = 24,
    editFontSize   = 0,        -- 0 = same as the window
    recall         = true,     -- plain Up/Down recalls what you sent
    -- Idle fade
    idleFade       = true,
    idleDelay      = 15,
    idleStrength   = 40,       -- percent faded
    scrollBar      = "always", -- always | scrolled | never
    -- Messages
    timestamps     = "%H:%M ",
    stampAll       = false,
    shortChannels  = true,
    classNames     = true,     -- class colours for names inside messages
    urls           = true,
    linkTooltips   = true,
    whisperSound   = "none",
    history        = 100,      -- lines kept per window through a reload (0 = off)
    -- Tabs
    tabHeight      = 24,
    tabFontSize    = 12,
    tabPadding     = 12,
    tabSpacing     = 1,
    tabUnderline   = true,
    tabActiveText  = "white",  -- white | accent | class
    tabBgAlpha     = 0.35,
    tabActiveBgAlpha = 0.65,
    -- Sidebar
    sidebar        = "always", -- always | mouseover | never
    sidebarRight   = false,
    sidebarWidth   = 34,
    iconFriends    = true,
    iconGuild      = true,
    iconCopy       = true,
    iconChannels   = true,
    iconSettings   = true,
    iconScroll     = true,
    -- Main window size (UI units), captured the first time we see it
    size           = false,
})
ns.module = M
M.title = "Chat"
M.description = "A clean chat panel with its own text, tabs and sidebar, idle fade, timestamps, short channel names, clickable links and copy."

ns.issecret = issecretvalue or function() return false end
local issecret = ns.issecret

--------------------------------------------------------------------------------
--  Side table: everything we know about a Blizzard frame lives here.
--------------------------------------------------------------------------------
local cfd = setmetatable({}, { __mode = "k" })
function ns.CFD(f)
    local d = cfd[f]
    if not d then d = {}; cfd[f] = d end
    return d
end

function ns.DB() return M.db end

--------------------------------------------------------------------------------
--  Colours and sizes
--------------------------------------------------------------------------------
-- Theme tokens (EvermoreUI/Core/Theme.lua). These are the live token
-- tables, updated in place when the theme changes.
ns.BG      = EV.Theme.C.surface0
ns.DIVIDER = EV.Theme.C.divider
ns.BORDER  = EV.Theme.C.border

--- n physical pixels in UIParent units.
function ns.Px(n) return EV.Pixel:One(UIParent) * n end

--- Round a UIParent-unit value to whole physical pixels.
function ns.Snap(v)
    local one = EV.Pixel:One(UIParent)
    return math.floor(v / one + 0.5) * one
end

function ns.Accent()
    local r, g, b = EV.Theme.RGBA("accent")
    return r, g, b
end

function ns.ClassColour()
    local _, class = UnitClass("player")
    local r, g, b = EvermoreUI.Palette.ClassRGB(class)
    if r then return r, g, b end
    return 1, 1, 1
end

--------------------------------------------------------------------------------
--  Fonts
--------------------------------------------------------------------------------
function ns.FontPath() return EV.Media:Fetch("font", M.db.font) end

function ns.FontFlags()
    local o = M.db.outline
    if o == "OUTLINE" or o == "THICKOUTLINE" then return o end
    return ""
end

--- The text size for a window: ours if overridden, else Blizzard's saved
--- per-window size (right-click tab > Font Size).
function ns.FontSize(id)
    if M.db.overrideSize then return M.db.fontSize end
    local get = FCF_GetChatWindowInfo or GetChatWindowInfo
    if id and id > 0 and get then
        local ok, _, size = pcall(get, id)
        if ok and type(size) == "number" and not issecret(size) and size > 0 then return size end
    end
    return 14
end

function ns.ApplyShadow(obj)
    if not obj or not obj.SetShadowOffset then return end
    if M.db.shadow and M.db.outline == "NONE" then
        obj:SetShadowOffset(1, -1)
        obj:SetShadowColor(0, 0, 0, 0.85)
    else
        obj:SetShadowOffset(0, 0)
        obj:SetShadowColor(0, 0, 0, 0)
    end
end

-- Font families (12.1): one font per alphabet, so Chinese and Korean text in
-- chat still renders when the chosen font only covers Latin and Cyrillic.
-- Our text and Blizzard's invisible text must use the same object so both
-- lay out identically. Falls back to a plain file when unavailable.
local families = {}
local CJK = {
    korean = "Fonts\\2002.ttf",
    simplifiedchinese = "Fonts\\ARKai_T.ttf",
    traditionalchinese = "Fonts\\blei00d.TTF",
}
local CLIENT_ALPHABET = ({ koKR = "korean", zhCN = "simplifiedchinese", zhTW = "traditionalchinese" })[GetLocale and GetLocale() or ""]

function ns.FontFamily(id, path, size, flags)
    if not CreateFontFamily then return nil end
    local fam = families[id]
    if fam == false then return nil end
    local function height(alphabet)
        if CJK[alphabet] and alphabet ~= CLIENT_ALPHABET then return size + 2 end
        return size
    end
    local function file(alphabet)
        if CJK[alphabet] and alphabet ~= CLIENT_ALPHABET then return CJK[alphabet] end
        return path
    end
    if not fam then
        local members = {}
        for _, a in ipairs({ "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }) do
            members[#members + 1] = { alphabet = a, file = file(a), height = height(a), flags = flags }
        end
        local ok, created = pcall(CreateFontFamily, "EvermoreUIChatFont" .. id, members)
        if not ok or not created then families[id] = false; return nil end
        families[id] = created
        return created
    end
    local ok = pcall(function()
        for _, a in ipairs({ "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }) do
            local member = fam:GetFontObjectForAlphabet(a)
            if member then
                member:SetFont(file(a), height(a), flags)
                member:SetSpacing(a == "korean" and 3 or 0)
            end
        end
    end)
    return ok and fam or nil
end

--- Put the chat font on a text object (ours or Blizzard's) for window `id`.
function ns.ApplyFont(obj, id, size)
    local path, flags = ns.FontPath(), ns.FontFlags()
    size = size or ns.FontSize(id)
    local fam = ns.FontFamily(id, path, size, flags)
    if fam and obj.SetFontObject then
        obj:SetFontObject(fam)
    else
        obj:SetFont(path, size, flags)
    end
    ns.ApplyShadow(obj)
end

--------------------------------------------------------------------------------
--  Chat frames
--------------------------------------------------------------------------------
--- Every chat frame Blizzard has made, temporary whisper windows included.
-- Every chat window, built once and rebuilt only when the set can have
-- changed (Blizzard's CHAT_FRAMES list grows when a whisper window opens).
-- Callers only iterate it: it's called from 10 Hz watchers, so it must not
-- allocate on each call.
local frameNames = {}
for i = 1, 20 do frameNames[i] = "ChatFrame" .. i end
local frameList, frameSeen = {}, {}
local builtFor = -1
function ns.ChatFramesDirty() builtFor = -1 end
function ns.ChatFrames()
    local n = type(CHAT_FRAMES) == "table" and #CHAT_FRAMES or 0
    if n == builtFor then return frameList end
    builtFor = n
    wipe(frameList); wipe(frameSeen)
    for i = 1, 20 do
        local f = _G[frameNames[i]]
        if f and not frameSeen[f] and f.AddMessage then frameSeen[f] = true; frameList[#frameList + 1] = f end
    end
    if n > 0 then
        for _, name in ipairs(CHAT_FRAMES) do
            local f = _G[name]
            if f and not frameSeen[f] and f.AddMessage then frameSeen[f] = true; frameList[#frameList + 1] = f end
        end
    end
    return frameList
end

function ns.Selected()
    return GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
end

function ns.IsCombatLog(cf)
    if IsCombatLog then
        local ok, r = pcall(IsCombatLog, cf)
        if ok then return r and true or false end
    end
    return cf == ChatFrame2
end

function ns.EditBoxOf(cf)
    local name = cf:GetName()
    return name and _G[name .. "EditBox"]
end

local tabOf = setmetatable({}, { __mode = "k" })
function ns.TabOf(cf)
    local tab = tabOf[cf]
    if tab then return tab end
    local name = cf:GetName()
    tab = name and _G[name .. "Tab"]
    if tab then tabOf[cf] = tab end
    return tab
end

--- Permanent windows are 1-10; 11+ are pooled temporary whisper windows,
--- which never get script hooks (their secure code handles secret names).
function ns.IsPermanent(f)
    local name = f and f.GetName and f:GetName()
    local i = name and tonumber(name:match("^ChatFrame(%d+)"))
    return i ~= nil and i <= 10
end

--- Chat messaging lockdown and friends: every width-changing transform
--- stands down while this is true.
function ns.Restricted()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and not issecret(r) and r then return true end
    end
    if C_CVar and C_CVar.GetCVarBool then
        local ok, r = pcall(C_CVar.GetCVarBool, "addonChatRestrictionsForced")
        if ok and r then return true end
    end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, r = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and r then return true end
    end
    return false
end

--- Coalesce a function to at most once per frame.
function ns.Deferred(fn)
    local queued = false
    return function()
        if queued then return end
        queued = true
        C_Timer.After(0, function() queued = false; fn() end)
    end
end
