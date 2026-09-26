if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Engine.lua
--  The display plane. Each Blizzard chat window keeps receiving and
--  formatting its messages as normal, but its text is made invisible and a
--  ScrollingMessageFrame of ours draws the same lines on our panel.
--
--    * each line arrives through a hooksecurefunc post-hook on the window's AddMessage,
--      the last step of Blizzard's pipeline; its wrapper reads as secure, so
--      Blizzard's own whisper handling after AddMessage stays secure
--    * Blizzard's invisible text keeps its hyperlink hit-zones: our text is
--      laid over it in the same font, same rect and same scroll offset, so
--      every link click still runs through Blizzard's own scripts
--    * Blizzard's view is the scroll authority; its scroll methods are
--      post-hooked to copy the offset into ours
--    * transforms that change a line's width (short channel names, stamping
--      every line) write the final text back into Blizzard's stored entry,
--      so both surfaces lay out the same text and the hit-zones stay under
--      the letters you see; they stand down entirely in restricted content
--    * the combat log is the exception: while its tab is open Blizzard draws
--      it (its filter machinery is not ours to rebuild)
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local CFD, issecret = ns.CFD, ns.issecret
local max, min, floor = math.max, math.min, math.floor

local E = {}
ns.Engine = E

local wins = {}            -- chat frame -> { cf, smf, track, thumb }
E.wins = wins
-- Hidden parent for the few Blizzard pieces we take off screen for good.
local parking = CreateFrame("Frame")
parking:Hide()

local protectedNow = false -- restricted content: transforms off
local tailObservers = {}

--------------------------------------------------------------------------------
--  History through a reload
--
--  Each permanent window's last `history` lines are kept in this character's
--  saved data, as the exact text we displayed, and put back when the window
--  comes under the engine after a reload or login. They go back in through
--  the window's own AddMessage, so Blizzard's copy holds them too and every
--  link in them is still clickable.
--
--  Never kept: secret lines (restricted content hands us those, and they
--  cannot be compared, stored or written), temporary whisper windows, and
--  the combat log. Replayed lines are not recorded a second time.
--------------------------------------------------------------------------------
local replaying = false
local replayed = {}        -- window id -> true once this session

local function HistoryStore()
    return EV.DB:GetCharData("chatHistory")
end

local function Keeps(cf)
    return not cf.isTemporary and not ns.IsCombatLog(cf) and type(cf.GetID) == "function" and cf:GetID() > 0
end

local function Record(cf, text, r, g, b)
    local keep = M.db.history or 0
    if replaying or keep <= 0 or not Keeps(cf) then return end
    if issecret(text) or type(text) ~= "string" or text == "" then return end
    if issecret(r) or issecret(g) or issecret(b) then r, g, b = nil, nil, nil end
    local store = HistoryStore()
    local id = tostring(cf:GetID())
    local list = store[id]
    if type(list) ~= "table" then list = {}; store[id] = list end
    list[#list + 1] = { text, r, g, b }
    -- Trim in batches, not per line: table.remove(list, 1) is a full shift.
    if #list > keep + 25 then
        local keepFrom = #list - keep + 1
        local out = {}
        for i = keepFrom, #list do out[#out + 1] = list[i] end
        store[id] = out
    end
end

local function Replay(cf)
    if not Keeps(cf) then return end
    local id = tostring(cf:GetID())
    if replayed[id] then return end
    replayed[id] = true
    local keep = M.db.history or 0
    local store = HistoryStore()
    local list = store[id]
    if keep <= 0 then store[id] = nil; return end
    if type(list) ~= "table" or #list == 0 then return end
    local from = math.max(1, #list - keep + 1)
    replaying = true
    for i = from, #list do
        local e = list[i]
        if type(e) == "table" and type(e[1]) == "string" then
            pcall(cf.AddMessage, cf, e[1], e[2], e[3], e[4])
        end
    end
    local r, g, b = 0.5, 0.5, 0.5
    if EV.Theme and EV.Theme.RGBA then r, g, b = EV.Theme.RGBA("textDisabled") end
    pcall(cf.AddMessage, cf, EV.L["Earlier messages, restored from your last session"], r, g, b)
    replaying = false
end
E.ClearHistory = function() wipe(HistoryStore()) end

function E.AddTailObserver(fn) tailObservers[#tailObservers + 1] = fn end

--------------------------------------------------------------------------------
--  Hiding Blizzard's text and scroll bar (alpha and mouse only)
--------------------------------------------------------------------------------
local function BarMouse(bar, on)
    local track = type(bar.Track) == "table" and bar.Track or nil
    for _, f in ipairs({ bar, track, track and type(track.Thumb) == "table" and track.Thumb or nil }) do
        if type(f) ~= "table" then
            -- nothing
        elseif f.SetMouseClickEnabled then
            f:SetMouseClickEnabled(on)
            f:SetMouseMotionEnabled(on)
        elseif f.EnableMouse then
            f:EnableMouse(on)
        end
    end
end

local STEPPERS = { "Back", "Forward" }

local function Suppress(cf)
    local d = CFD(cf)
    if d.suppressed then return end
    d.suppressed = true
    if cf.FontStringContainer then cf.FontStringContainer:SetAlpha(0) end
    local bar = cf.ScrollBar
    if not bar then return end
    BarMouse(bar, false)
    if bar.Track then bar.Track:SetAlpha(0) end
    -- The stepper arrows are the one thing we re-home: nothing of
    -- Blizzard's touches them after creation.
    for _, key in ipairs(STEPPERS) do
        local arrow = bar[key]
        if arrow and arrow:GetParent() ~= parking then arrow:SetParent(parking) end
    end
end

--------------------------------------------------------------------------------
--  Scroll bar: the shared EvermoreUI one (EvermoreUI/UI/ScrollBar.lua).
--  Chat scrolls from the bottom (offset 0 is the newest line). The chat
--  setting picks when it shows: always, only while scrolled back, never.
--------------------------------------------------------------------------------
local function UpdateBar(w)
    local offset = w.smf:GetScrollOffset()
    for _, fn in ipairs(E.scrollListeners or {}) do fn(w.cf, offset > 0) end
    local bar = w.bar
    local mode = M.db.scrollBar
    bar.mode = (mode == "always" and "auto") or mode
    if not w.smf:IsShown() then bar:Hide() return end
    bar:Update()
end

local function MirrorToBlizzard(w)
    if w.cf.SetScrollOffset then w.cf:SetScrollOffset(w.smf:GetScrollOffset()) end
end

local function BuildBar(w)
    local smf = w.smf
    local bar = EV.UI.ScrollBar(smf:GetParent(), {
        range = function() return smf:GetMaxScrollRange() end,
        offset = function() return smf:GetScrollOffset() end,
        visible = function() return smf:GetNumVisibleLines() end,
        set = function(v)
            smf:SetScrollOffset(floor(v + 0.5))
            MirrorToBlizzard(w)
        end,
        fromBottom = true,
        step = 3,
    })
    bar:SetPoint("TOPLEFT", smf, "TOPRIGHT", ns.Px(3), 0)
    bar:SetPoint("BOTTOMLEFT", smf, "BOTTOMRIGHT", ns.Px(3), 0)
    bar:SetFrameLevel(smf:GetFrameLevel() + 2)
    w.bar = bar
    w.track = bar -- older name, kept for anything that re-homes it
end

--------------------------------------------------------------------------------
--  Transforms (our display copy, plus the write-back that keeps Blizzard's
--  invisible layout identical)
--------------------------------------------------------------------------------
local shortChannels, classNames, stampAll, stampFmt = false, false, false, nil

-- Group chats by their usual one or two letter shorthand.
local SHORT_TYPES = {
    GUILD = "G", OFFICER = "O",
    PARTY = "P", PARTY_LEADER = "PL", PARTY_GUIDE = "PG",
    RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
    INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
    BATTLEGROUND = "BG", BATTLEGROUND_LEADER = "BL",
}

-- |Hchannel:<target>|h[<label>]|h  ->  |Hchannel:<target>|h[<short>]|h
-- Numbered world channels show their number ("[2]"), group chats a letter.
local function ShortenChannels(text)
    return (text:gsub("|Hchannel:([^|]+)|h%[([^%]|]*)%]|h", function(target, label)
        local short = SHORT_TYPES[target:upper()]
        if not short then
            short = target:match("^[Cc][Hh][Aa][Nn][Nn][Ee][Ll]:(%d+)$") or label:match("^(%d+)%.")
        end
        if not short then return nil end
        return "|Hchannel:" .. target .. "|h[" .. short .. "]|h"
    end))
end
E.ShortenChannels = ShortenChannels

-- Class colours for names typed inside messages: current group only.
local roster = {}   -- lower-case name -> "ffrrggbb"
local NAME_EVENTS = {}
for _, kind in ipairs({ "SAY", "YELL", "GUILD", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
                        "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }) do
    NAME_EVENTS["CHAT_MSG_" .. kind] = true
end

local function AddToRoster(unit)
    if not UnitExists(unit) then return end
    local name = UnitName(unit)
    if issecret(name) or type(name) ~= "string" or name == "" then return end
    local _, class = UnitClass(unit)
    if issecret(class) or not class then return end
    local r, g, b = EvermoreUI.Palette.ClassRGB(class)
    if not r then return end
    roster[name:lower()] = ("ff%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

local function RebuildRoster()
    wipe(roster)
    if IsInRaid and IsInRaid() then
        for i = 1, GetNumGroupMembers() do AddToRoster("raid" .. i) end
    else
        AddToRoster("player")
        for i = 1, 4 do AddToRoster("party" .. i) end
    end
end

local rosterFrame = CreateFrame("Frame")
rosterFrame:SetScript("OnEvent", ns.Deferred(RebuildRoster))

-- Where the escape sequence starting at `at` (the "|") ends. Every kind we
-- do not know is two characters long.
--   |cAARRGGBB  fixed width      |cnNAME:  named colour, up to the colon
--   |H...|h[label]|h             a link, taken whole with its label
--   |T...|t  |A...|a  |K...|k   texture, atlas and protected-name blocks
local PAIRED = { T = "|t", A = "|a", K = "|k" }

local function EscapeEnd(text, at, kind)
    if kind == "c" then
        if text:sub(at + 2, at + 2) ~= "n" then return at + 9 end
        return text:find(":", at + 3, true) or at + 2
    end
    if kind == "H" then
        local mid = text:find("|h", at + 2, true)
        if not mid then return at + 1 end
        local close = text:find("|h", mid + 2, true)
        return close and close + 1 or mid + 1
    end
    local closer = PAIRED[kind]
    if closer then
        local close = text:find(closer, at + 2, true)
        return close and close + 1 or at + 1
    end
    return at + 1
end

-- Split a line into escape sequences (left alone, links whole with their
-- label) and plain text (where names get coloured).
local function ColourNames(text)
    if next(roster) == nil then return text end
    local out, n, pos, len = {}, 0, 1, #text
    local depth = 0 -- inside someone else's colour code: leave it be
    local function plain(s)
        n = n + 1
        if depth > 0 then out[n] = s; return end
        out[n] = (s:gsub("[%w\128-\255]+", function(word)
            local hex = roster[word:lower()]
            if hex then return "|c" .. hex .. word .. "|r" end
        end))
    end
    while pos <= len do
        local bar = text:find("|", pos, true)
        if bar ~= pos then plain(text:sub(pos, (bar or len + 1) - 1)) end
        if not bar then break end
        local kind = text:sub(bar + 1, bar + 1)
        local last = EscapeEnd(text, bar, kind)
        if kind == "c" then
            depth = depth + 1
        elseif kind == "r" and depth > 0 then
            depth = depth - 1
        end
        n = n + 1
        out[n] = text:sub(bar, last)
        pos = last + 1
    end
    return table.concat(out)
end
E.ColourNames = ColourNames

local function HasStamp(msg)
    return msg:find("^%[?%d%d?:%d%d") ~= nil
end

--- Prefix the time, for "stamp every line". `when` is the line's arrival in
--- server time when we know it (a rebuild), otherwise now.
local function Stamp(msg, when)
    if not stampAll or protectedNow or HasStamp(msg) then return msg end
    local ok, prefix = pcall(date, stampFmt, when and floor(when))
    if not ok or type(prefix) ~= "string" or prefix == "" then return msg end
    return prefix .. msg
end

local function Display(msg, event)
    if issecret(msg) or type(msg) ~= "string" then return msg end
    if shortChannels and not protectedNow and msg:find("|Hchannel:", 1, true) then
        msg = ShortenChannels(msg)
    end
    if classNames and event and not issecret(event) and NAME_EVENTS[event] then
        msg = ColourNames(msg)
    end
    return msg
end

-- Write the display form back into Blizzard's newest stored entry (or a
-- given one) so its invisible layout matches ours. Secrets never compared.
local function WriteBack(entry, original, display)
    if not entry or issecret(original) or type(display) ~= "string" or display == original then return end
    local stored = entry.message
    if type(stored) == "string" and not issecret(stored) and stored == original then
        entry.message = display
    end
end

--- The text we draw for one line, written back into Blizzard's stored entry
--- when it differs so both surfaces lay out the same string.
local function Prepare(msg, event, entry, when)
    if issecret(msg) or type(msg) ~= "string" then return msg end
    local shown = Stamp(Display(msg, event), when)
    if shown ~= msg then WriteBack(entry, msg, shown) end
    return shown
end

--- Blizzard's line store for a window, when this client exposes it.
local function Store(cf)
    local hb = cf.historyBuffer
    if hb and hb.GetEntryAtIndex and hb.GetNumElements then return hb end
end

--- A stored entry's arrival in server time. Entries are stamped in the
--- GetTime() clock, so shift by the difference between the two clocks.
local function Arrival(entry, clockOffset)
    local t = entry and entry.timestamp
    if type(t) == "number" then return t + clockOffset end
end

--- The timestamp format the player picked in Blizzard's own chat settings,
--- or nil for none.
local function GameStampFormat()
    local get = ChatFrameUtil and ChatFrameUtil.GetTimestampFormat
    if not get then return nil end
    local ok, fmt = pcall(get)
    if not ok or type(fmt) ~= "string" or fmt == "" or fmt == "none" then return nil end
    return fmt
end

local ROSTER_EVENTS = { "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE" }

function E.SetTransforms(db)
    shortChannels = not not db.shortChannels
    classNames = not not db.classNames

    local choice = db.timestamps
    stampFmt = (choice == "blizzard" and GameStampFormat())
        or (choice ~= "none" and choice ~= "blizzard" and choice)
        or nil
    stampAll = (db.stampAll and stampFmt) and true or false

    rosterFrame:UnregisterAllEvents()
    wipe(roster)
    if not classNames then return end
    for _, event in ipairs(ROSTER_EVENTS) do rosterFrame:RegisterEvent(event) end
    RebuildRoster()
end

--------------------------------------------------------------------------------
--  Hooking Blizzard's window
--------------------------------------------------------------------------------
local RebuildSoon -- forward

local function UpdateProtected()
    local now = ns.Restricted()
    if now == protectedNow then return end
    protectedNow = now
    E.RebuildAllSoon()
end

-- Runs after Blizzard's AddMessage. Signature matches the hook: the window,
-- then AddMessage's own arguments.
local function OnLine(cf, msg, r, g, b, typeID, accessID, lineTypeID, event, eventArgs)
    UpdateProtected()
    local store = Store(cf)
    local display = Prepare(msg, event, store and store:GetEntryAtIndex(1))
    Record(cf, display, r, g, b)
    local w = wins[cf]
    if w then
        local ours = w.smf
        ours:AddMessage(display, r, g, b, typeID, type(eventArgs) == "table" and eventArgs[11] or nil, event)
        if ours:GetNumMessages() > cf:GetNumMessages() then
            -- We hold more lines than Blizzard does, so its buffer was emptied
            -- under us (a reused whisper window, another addon's Clear).
            RebuildSoon(cf)
        else
            -- Both frames nudge a scrolled-back view by a line when one
            -- arrives. Take Blizzard's result so the two cannot drift.
            ours:SetScrollOffset(cf:GetScrollOffset())
        end
    end
    for i = 1, #tailObservers do tailObservers[i](cf, event) end
end

-- Every way Blizzard's view can move. SetScrollOffset matters most: its own
-- wheel handler and scroll bar set the offset directly.
local SCROLL_METHODS = {
    "SetScrollOffset", "ScrollToBottom", "ScrollToTop",
    "ScrollDown", "ScrollUp", "PageDown", "PageUp",
}

--- Follow Blizzard's view (post-hook on every scroll method above).
local function FollowScroll(cf)
    local w = wins[cf]
    if not w then return end
    local offset = cf:GetScrollOffset()
    if issecret(offset) or offset == w.smf:GetScrollOffset() then return end
    w.smf:SetScrollOffset(offset)
end

-- Plain wheel: three lines. Ctrl: a page. Shift: all the way.
local function WheelStep(cf)
    if IsShiftKeyDown() then return "ScrollToTop", "ScrollToBottom", 1 end
    if IsControlKeyDown() and cf.PageUp then return "PageUp", "PageDown", 1 end
    return "ScrollUp", "ScrollDown", 3
end

local function OnWheel(cf, delta)
    local towardsOld, towardsNew, times = WheelStep(cf)
    local step = cf[delta > 0 and towardsOld or towardsNew]
    for _ = 1, times do step(cf) end
end

-- A window Blizzard hasn't opened yet is left alone: opening one copies
-- lines in with a loop that an AddMessage hook would taint.
local function PermanentOpen(cf)
    if not FCF_IsChatWindowIndexActive then return cf.isDocked or cf:IsShown() end
    local index = cf:GetID()
    return index > 0 and FCF_IsChatWindowIndexActive(index) and true or false
end

local function IsOpen(cf)
    if not cf.isTemporary then return PermanentOpen(cf) end
    return cf.inUse == true -- a pooled whisper window, only once handed out
end

local function Hook(cf)
    local d = CFD(cf)
    if d.hooked or not IsOpen(cf) then return false end
    d.hooked = true
    hooksecurefunc(cf, "AddMessage", OnLine)
    for _, method in ipairs(SCROLL_METHODS) do
        local exists = type(cf[method]) == "function"
        if exists then hooksecurefunc(cf, method, FollowScroll) end
    end
    -- Only take the wheel if Blizzard hasn't wired one; either way the
    -- window must receive it.
    if not cf:GetScript("OnMouseWheel") then cf:SetScript("OnMouseWheel", OnWheel) end
    cf:EnableMouseWheel(true)
    return true
end

--------------------------------------------------------------------------------
--  Windows
--------------------------------------------------------------------------------
local function Layout(w)
    local cf, smf = w.cf, w.smf
    local area = cf.FontStringContainer or cf
    local extra = CFD(cf).inputTopExtra or 0
    smf:ClearAllPoints()
    smf:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -extra)
    smf:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)
end
function E.Layout(cf) if wins[cf] then Layout(wins[cf]) end end

function E.ApplyFont(cf)
    local w = wins[cf]
    if w then ns.ApplyFont(w.smf, cf:GetID()) end
end

local function Create(cf, host)
    local smf = CreateFrame("ScrollingMessageFrame", nil, host)
    smf:SetFrameLevel(host:GetFrameLevel() + 4)
    -- No mouse at all: clicks and links belong to Blizzard's frame beneath.
    smf:EnableMouse(false)
    smf:EnableMouseWheel(false)
    -- Same line capacity and wrapping as the window it copies (wrapped lines
    -- must break where Blizzard's do, or link zones drift), and no fading.
    smf:SetMaxLines(cf.GetMaxLines and cf:GetMaxLines() or 128)
    smf:SetJustifyH("LEFT")
    smf:SetIndentedWordWrap(true)
    smf:SetFading(false)
    if smf.SetScrollAllowed then smf:SetScrollAllowed(true) end
    local w = { cf = cf, smf = smf }
    wins[cf] = w
    BuildBar(w)
    if smf.SetOnScrollChangedCallback then smf:SetOnScrollChangedCallback(function() UpdateBar(w) end) end
    if smf.AddOnDisplayRefreshedCallback then smf:AddOnDisplayRefreshedCallback(function() UpdateBar(w) end) end
    Layout(w)
    ns.ApplyFont(smf, cf:GetID())
    return w
end

--- Move a window's text onto a different panel (docking and undocking).
function E.SetHost(cf, host)
    local w = wins[cf]
    if not (w and host) or w.smf:GetParent() == host then return end
    w.smf:SetParent(host)
    w.smf:SetFrameLevel(host:GetFrameLevel() + 4)
    w.track:SetParent(host)
    w.track:SetFrameLevel(host:GetFrameLevel() + 6)
end

-- Rebuild our copy from Blizzard's buffer (install, reused windows, censor
-- and report rewrites). Converges the write-back for lines that arrived
-- while transforms were standing down.
local function Rebuild(cf)
    local w = wins[cf]
    if not w then return end
    local smf = w.smf
    smf:Clear()
    local store = Store(cf)
    local count = cf:GetNumMessages()
    local newest = store and store:GetNumElements()
    local clockOffset = time() - GetTime()
    for i = 1, count do
        local msg, r, g, b, typeID, _, _, event, eventArgs = cf:GetMessageInfo(i)
        if msg ~= nil then
            -- The store counts from the newest line, GetMessageInfo from the oldest.
            local entry = store and store:GetEntryAtIndex(newest - i + 1)
            local display = Prepare(msg, event, entry, Arrival(entry, clockOffset))
            smf:AddMessage(display, r, g, b, typeID, type(eventArgs) == "table" and eventArgs[11] or nil, event)
        end
    end
    -- Blizzard's view is the scroll authority: keep whatever it's showing.
    smf:SetScrollOffset(math.min(cf:GetScrollOffset() or 0, smf:GetMaxScrollRange()))
    UpdateBar(w)
end
E.Rebuild = Rebuild

local soon = {}
RebuildSoon = function(cf)
    if soon[cf] then return end
    soon[cf] = true
    C_Timer.After(0, function() soon[cf] = nil; Rebuild(cf) end)
end

E.RebuildAllSoon = ns.Deferred(function()
    for cf in pairs(wins) do
        if not (E.hostingCombatLog and ns.IsCombatLog(cf)) then Rebuild(cf) end
    end
end)

--- Bring one window under the engine. Only ever called from our own
--- deferred passes, never from inside Blizzard's code.
function E.Adopt(cf, host)
    if not host then return end
    Suppress(cf)
    local w = wins[cf]
    if not w then
        Create(cf, host)
        Hook(cf)
        Rebuild(cf)
        Replay(cf)
        return
    end
    E.SetHost(cf, host)
    if Hook(cf) and w.smf:GetNumMessages() == 0 then Rebuild(cf); return end
    if cf:GetNumMessages() < w.smf:GetNumMessages() then Rebuild(cf) end
end

--- Our text shows exactly when Blizzard's window does. Cheap: run it often.
function E.SyncShown()
    for cf, w in pairs(wins) do
        local want = cf:IsShown() and not (E.hostingCombatLog and ns.IsCombatLog(cf))
        if w.smf:IsShown() ~= want then
            w.smf:SetShown(want)
        end
        UpdateBar(w)
    end
end

--- While the combat log's tab is open, Blizzard draws it.
function E.UpdateCombatLog()
    local cf2 = ChatFrame2
    if not (cf2 and ns.IsCombatLog(cf2)) then return end
    -- Docked: while its tab is the open one. Undocked: whenever it's shown.
    local host
    if cf2.isDocked then host = ns.Selected() == cf2 else host = cf2:IsShown() and true or false end
    if host == (E.hostingCombatLog or false) then return end
    E.hostingCombatLog = host
    if cf2.FontStringContainer then cf2.FontStringContainer:SetAlpha(host and 1 or 0) end
    local bar = cf2.ScrollBar
    if bar then
        if bar.Track then bar.Track:SetAlpha(host and 1 or 0) end
        BarMouse(bar, host)
    end
    -- Refilters refill Blizzard's log without AddMessage, so always resync.
    if wins[cf2] and not host then Rebuild(cf2) end
    E.SyncShown()
end

function E.ApplyFonts()
    for cf in pairs(wins) do E.ApplyFont(cf) end
end

function E.LayoutAll()
    for _, w in pairs(wins) do Layout(w); UpdateBar(w) end
end

function E.ScrollToBottom(cf)
    cf = cf or ChatFrame1
    if cf and cf.ScrollToBottom then cf:ScrollToBottom() end
end

function E.IsScrolledBack(cf)
    local w = wins[cf]
    return w and w.smf:GetScrollOffset() > 0 or false
end

--- Lines for Copy Chat, oldest first (secrets included; the caller skips them).
function E.Lines(cf)
    local out, w = {}, wins[cf]
    local src = (w and not (E.hostingCombatLog and ns.IsCombatLog(cf))) and w.smf or cf
    if not (src and src.GetNumMessages) then return out end
    for i = 1, src:GetNumMessages() do out[#out + 1] = (src:GetMessageInfo(i)) end
    return out
end

--------------------------------------------------------------------------------
--  Mirrors of Blizzard-side changes, on our own event frame
--------------------------------------------------------------------------------
local mirror = CreateFrame("Frame")
mirror:RegisterEvent("UPDATE_CHAT_COLOR")
mirror:RegisterEvent("PLAYER_REPORT_SUBMITTED")
mirror:RegisterEvent("CAUTIONARY_CHAT_MESSAGE")
mirror:RegisterEvent("PLAYER_ENTERING_WORLD")
mirror:SetScript("OnEvent", function(_, event, chatType, r, g, b)
    if event == "UPDATE_CHAT_COLOR" then
        if type(chatType) ~= "string" or issecret(chatType) then return end
        local function recolour(key)
            local info = ChatTypeInfo and ChatTypeInfo[key:upper()]
            if not (info and info.id) then return end
            for _, w in pairs(wins) do
                if w.smf.AdjustMessageColors then
                    w.smf:AdjustMessageColors(function(_, _, _, _, id)
                        if id == info.id then return true, r, g, b end
                        return false
                    end)
                end
            end
        end
        recolour(chatType)
        if chatType:upper() == "WHISPER" then recolour("REPLY") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateProtected()
    else
        E.RebuildAllSoon()
    end
end)
