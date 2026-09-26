if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Report.lua
--  /evui bug: everything a bug report needs, in a copy box, with the issue
--  tracker's address. Players paste it; we stop asking "which version?".
--
--  What it collects, all read-only:
--    * suite version, client build and interface, locale, screen and scale
--    * class and level (plenty of our UI is class- or level-specific)
--    * every module and whether it's on, the active profile
--    * other addons loaded (conflicts are the usual culprit)
--    * our recent Lua errors: from BugGrabber when it's installed, otherwise
--      from Blizzard's error frame, filtered to EvermoreUI
--    * blocked or forbidden actions blamed on us this session (taint), which
--      Blizzard only reports through an event, so we listen from load
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local R = {}
EV.Report = R

local MAX_ERRORS, MAX_BLOCKED, MAX_ADDONS = 5, 10, 60

--- Modules add their own diagnostics to the report rather than printing them
--- to players' chat: fn() returns a line (or nil for nothing to say).
R.extras = {}
function R:AddLine(fn) if type(fn) == "function" then self.extras[#self.extras + 1] = fn end end

local function Meta(key)
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, EV.name, key)
    return ok and v or nil
end

function R:IssuesURL() return Meta("X-Issues") or "https://github.com/bjth/EvermoreUI/issues" end

--------------------------------------------------------------------------------
--  Blocked actions (taint). Blizzard names the addon it blames.
--------------------------------------------------------------------------------
local blocked = {}
local watch = CreateFrame("Frame")
watch:RegisterEvent("ADDON_ACTION_BLOCKED")
watch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watch:SetScript("OnEvent", function(_, event, addon, func)
    if type(addon) ~= "string" or not addon:find("^EvermoreUI") then return end
    local line = ("%s %s: %s (%s)"):format(date("%H:%M:%S"),
        event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked", tostring(func), addon)
    for _, b in ipairs(blocked) do if b.line == line:sub(10) then b.count = b.count + 1 return end end
    table.insert(blocked, { line = line:sub(10), first = line, count = 1 })
    if #blocked > MAX_BLOCKED then table.remove(blocked, 1) end
end)

--------------------------------------------------------------------------------
--  Recent errors mentioning us
--------------------------------------------------------------------------------
local function Ours(msg, stack)
    return (type(msg) == "string" and msg:find("EvermoreUI", 1, true))
        or (type(stack) == "string" and stack:find("EvermoreUI", 1, true))
end

local function FirstLines(s, n)
    if type(s) ~= "string" then return "" end
    local out = {}
    for line in s:gmatch("[^\n]+") do
        out[#out + 1] = "    " .. line
        if #out >= n then break end
    end
    return table.concat(out, "\n")
end

--------------------------------------------------------------------------------
--  Our own catch: with Lua errors hidden and no BugSack, the game keeps no
--  readable record, so the report had nothing to show. The error handler is
--  wrapped once to remember errors that mention EvermoreUI (message, first
--  stack lines, how many times), then passes every error on unchanged.
--------------------------------------------------------------------------------
local caught, caughtIndex = {}, {}
do
    local previous = geterrorhandler and geterrorhandler()
    if type(previous) == "function" and seterrorhandler then
        seterrorhandler(function(msg, ...)
            -- Errors from the game's own calls ("Font not set") don't name a
            -- file, so the stack is checked as well as the message.
            local okS, stack = pcall(debugstack, 2)
            stack = okS and type(stack) == "string" and stack or ""
            if type(msg) == "string" and (msg:find("EvermoreUI", 1, true) or stack:find("EvermoreUI", 1, true)) then
                local e = caughtIndex[msg]
                if e then
                    e.count = e.count + 1
                else
                    e = { msg = msg, stack = stack, count = 1 }
                    caughtIndex[msg] = e
                    caught[#caught + 1] = e
                    if #caught > 30 then caughtIndex[table.remove(caught, 1).msg] = nil end
                end
            end
            return previous(msg, ...)
        end)
    end
end

local function RecentErrors()
    local found = {}
    -- BugGrabber (BugSack's backend): newest last.
    local bg = _G.BugGrabber
    if type(bg) == "table" and type(bg.GetDB) == "function" then
        local ok, db = pcall(bg.GetDB, bg)
        if ok and type(db) == "table" then
            for i = #db, 1, -1 do
                local e = db[i]
                if type(e) == "table" and Ours(e.message, e.stack) then
                    found[#found + 1] = { msg = e.message, stack = e.stack, count = e.counter or 1 }
                    if #found >= MAX_ERRORS then break end
                end
            end
            return found, "BugGrabber"
        end
    end
    -- Blizzard's error frame keeps what it has shown this session.
    local sef = _G.ScriptErrorsFrame
    if type(sef) == "table" and type(sef.order) == "table" and type(sef.messages) == "table" then
        for i = #sef.order, 1, -1 do
            local msg = sef.order[i]
            local count = type(sef.count) == "table" and sef.count[i] or 1
            local body = sef.messages[i]
            if Ours(msg, body) then
                found[#found + 1] = { msg = msg, stack = body, count = count }
                if #found >= MAX_ERRORS then break end
            end
        end
        if #found > 0 then return found, "Blizzard error frame" end
    end
    -- Ours, newest first.
    for i = #caught, 1, -1 do
        found[#found + 1] = caught[i]
        if #found >= MAX_ERRORS then break end
    end
    if #found > 0 or #caught == 0 then return found, "EvermoreUI" end
    return found, nil
end

--------------------------------------------------------------------------------
--  The report
--------------------------------------------------------------------------------
function R:Build()
    local c, out = EV.Caps, {}
    local function Add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

    Add("EvermoreUI %s", tostring(EV.version))
    Add("Client %s (%s), interface %s, %s", tostring(c.version), tostring(c.build), tostring(c.interface), GetLocale())
    local w, h = GetPhysicalScreenSize()
    Add("Screen %sx%s, UI scale %.2f", tostring(w), tostring(h), UIParent:GetEffectiveScale())
    local _, class = UnitClass("player")
    Add("Character: level %s %s", tostring(UnitLevel("player")), tostring(class))
    Add("Profile: %s", EV.DB:GetProfileName())

    local on, off = {}, {}
    for _, mod in EV:IterateModules() do
        if not mod.internal then
            if mod:IsEnabled() then on[#on + 1] = mod.name else off[#off + 1] = mod.name end
        end
    end
    Add("Modules on: %s", #on > 0 and table.concat(on, ", ") or "none")
    Add("Modules off: %s", #off > 0 and table.concat(off, ", ") or "none")

    local others = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(i)
        if type(name) == "string" and not name:find("^EvermoreUI") and C_AddOns.IsAddOnLoaded(name) then
            others[#others + 1] = name
        end
    end
    table.sort(others)
    local extra = #others - MAX_ADDONS
    if extra > 0 then for _ = 1, extra do table.remove(others) end end
    Add("Other addons (%d): %s%s", #others + math.max(extra, 0),
        #others > 0 and table.concat(others, ", ") or "none", extra > 0 and (", +" .. extra .. " more") or "")

    for _, fn in ipairs(self.extras) do
        local ok, line = pcall(fn)
        if ok and type(line) == "string" and line ~= "" then Add("%s", line) end
    end

    local errs, from = RecentErrors()
    Add("")
    if not from then
        Add("Errors: couldn't read any (turn on /console scriptErrors 1, or install BugSack)")
    elseif #errs == 0 then
        Add("Errors: none from EvermoreUI (%s)", from)
    else
        Add("Errors from EvermoreUI, newest first (%s):", from)
        for i, e in ipairs(errs) do
            Add("%d. [x%s] %s", i, tostring(e.count), (FirstLines(e.msg, 1):gsub("^%s+", "")))
            local stack = FirstLines(e.stack, 4)
            if stack ~= "" then Add(stack) end
        end
    end

    if #blocked > 0 then
        Add("")
        Add("Blocked actions this session:")
        for _, b in ipairs(blocked) do Add("  %s%s", b.first, b.count > 1 and (" x" .. b.count) or "") end
    end
    return table.concat(out, "\n")
end

function R:Show()
    local text = self:Build()
    local hint = L["Ctrl+C, then paste it into a new issue at"] .. " " .. self:IssuesURL()
    if EV.UI and EV.UI.ShowCopyText then
        EV.UI.ShowCopyText(L["Bug report"], text, hint)
    else
        print(text)
    end
    EV:Print(L["Report issues at"], self:IssuesURL())
end
