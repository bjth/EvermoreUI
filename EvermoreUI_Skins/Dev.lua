if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Dev.lua
--  How the library gets extended. `/evui skin` on a window tells you what
--  the parts claimed and, more usefully, what art they did not: the loose
--  report lists every texture still on screen that no part and no ornate
--  pattern accounted for, with its atlas name. Adding coverage is then a
--  pattern in S.ORNATE or a new part, never a new window entry.
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S = ns.S
if not S then return end

local function Say(msg) print("|cffd4924eEvermoreUI|r " .. msg) end

--- The frame the mouse is over, walked up to something with a name.
local function Focus()
    local f = GetMouseFoci and GetMouseFoci()[1] or (GetMouseFocus and GetMouseFocus())
    while f and f ~= UIParent do
        if f.GetName and f:GetName() then return f end
        f = f.GetParent and f:GetParent()
    end
    return nil
end

--- Walk a frame and gather what we did and did not account for.
local function Audit(frame)
    local claimed, loose, textures = {}, {}, 0
    local function Visit(obj, depth)
        if depth > 8 or not S.Alive(obj) or S.ours[obj] then return end
        local part = S.claimed[obj]
        if part then claimed[part] = (claimed[part] or 0) + 1 end
        for _, r in ipairs(S.Regions(obj)) do
            if not S.ours[r] and r.GetObjectType and r:GetObjectType() == "Texture" then
                textures = textures + 1
                local shown = (not r.IsShown) or r:IsShown()
                local alpha = r.GetAlpha and r:GetAlpha() or 1
                if shown and alpha > 0.05 and not S.IsOrnate(r) then
                    local name = (r.GetAtlas and r:GetAtlas()) or (r.GetTexture and r:GetTexture())
                    -- A texture with no atlas and no path draws nothing.
                    -- There were 480 of those in one window, burying the
                    -- part of the report that matters.
                    if type(name) == "string" and name ~= "" then
                        loose[name] = (loose[name] or 0) + 1
                    end
                end
            end
        end
        for _, c in ipairs(S.Children(obj)) do Visit(c, depth + 1) end
    end
    Visit(frame, 0)
    return claimed, loose, textures
end

--------------------------------------------------------------------------------
--  /evui skin profile: what the walk costs. Each window's walk reports when it
--  finishes (how long in all, over how many slices, the longest slice, how
--  many objects it looked at and how many a part dressed), and the scroll
--  box row passes are summed once a second. Toggles.
--------------------------------------------------------------------------------
local function NameOf(obj)
    local ok, n = pcall(function() return obj:GetName() end)
    return ok and type(n) == "string" and n or tostring(obj)
end

function S.ReportWalk(w)
    Say(("walk |cffe3b464%s|r: %.1fms over %d slice(s), longest %.1fms; %d looked at, %d dressed%s"):format(
        NameOf(w.root), w.ms, w.slices, w.worst, w.nodes, w.dressed, w.again and ", going again" or ""))
    Say(("   parts %.1fms, decoration %.1fms, text %.1fms"):format(w.tParts or 0, w.tArt or 0, w.tText or 0))
end

local rowTicker
local function Profile()
    S.profiling = not S.profiling
    if rowTicker then rowTicker:Cancel(); rowTicker = nil end
    if S.profiling then
        S.rowCost.passes, S.rowCost.ms = 0, 0
        rowTicker = C_Timer.NewTicker(1, function()
            local c = S.rowCost
            if c.passes > 0 then
                Say(("rows: %d dressed, %.1fms"):format(c.passes, c.ms))
                c.passes, c.ms = 0, 0
            end
        end)
        Say(("skin profile |cff93b75con|r (budget %gms a frame). Open a window."):format(S.WALK_BUDGET_MS))
    else
        Say("skin profile |cffc0704aoff|r.")
    end
end

--------------------------------------------------------------------------------
--  /evui skin find <text>: the frames on screen showing that text, by path.
--  For a window with no name you know (a notice, a pane inside a pane), so it
--  can be dumped with /evui skin <path> or given a pack.
--------------------------------------------------------------------------------
local function PathOf(obj, depth)
    local name = obj.GetName and obj:GetName()
    if type(name) == "string" then return name end
    local parent = obj.GetParent and obj:GetParent()
    if not parent or (depth or 0) > 8 then return "?" end
    for k, v in pairs(parent) do
        if v == obj and type(k) == "string" then return PathOf(parent, (depth or 0) + 1) .. "." .. k end
    end
    return PathOf(parent, (depth or 0) + 1) .. ".?"
end

local function Find(text)
    local want, found = text:lower(), 0
    local f = EnumerateFrames and EnumerateFrames()
    while f and found < 12 do
        if not (f.IsForbidden and f:IsForbidden()) and f.IsVisible and f:IsVisible() then
            for _, r in ipairs(S.Regions(f)) do
                local ok, str = pcall(function() return r.GetText and r:GetText() end)
                if ok and type(str) == "string" and not (issecretvalue and issecretvalue(str))
                   and str:lower():find(want, 1, true) then
                    found = found + 1
                    local part = S.claimed[f]
                    Say(('%s: "%s"%s'):format(PathOf(f), str:sub(1, 40), part and ("  (" .. part .. ")") or ""))
                    break
                end
            end
        end
        f = EnumerateFrames(f)
    end
    if found == 0 then Say("Nothing on screen shows " .. text .. ".") end
end

EV:RegisterSlash("skin", function(rest)
    rest = (rest or ""):lower()

    if rest == "profile" then Profile(); return end
    local text = rest:match("^find%s+(.+)$")
    if text then Find(text); return end

    if rest == "" or rest == "parts" then
        Say(("%d parts registered:"):format(#S.parts))
        local names = {}
        for _, p in ipairs(S.parts) do names[#names + 1] = p.name end
        Say("  " .. table.concat(names, ", "))
        Say(("%d ornate atlas patterns, %d ornate file textures."):format(#S.ORNATE, #(S.ORNATE_FILES or {})))
        local pnames = {}
        for n in pairs(S.packs or {}) do pnames[#pnames + 1] = n end
        table.sort(pnames)
        Say(("%d window packs: %s"):format(#pnames, #pnames > 0 and table.concat(pnames, ", ") or "none"))
        Say("Point at a window and use |cffe3b464/evui skin this|r. Also |cffe3b464skin find <text>|r, |cffe3b464skin profile|r.")
        local broke = false
        for name, n in pairs(S.errors) do
            Say(("   |cffc0704apart %s threw %d time(s)|r"):format(name, n)); broke = true
        end
        if broke and S.lastError then Say("   last: " .. S.lastError) end
        local pbroke = false
        for name, n in pairs(S.packErrors or {}) do
            Say(("   |cffc0704apack %s threw %d time(s)|r"):format(name, n)); pbroke = true
        end
        if pbroke and S.lastPackError then Say("   last: " .. S.lastPackError) end
        return
    end

    local frame
    if rest == "this" or rest == "focus" then
        frame = Focus()
        if not frame then Say("Nothing under the mouse."); return end
    else
        frame = _G[rest] or _G[(rest:gsub("^%l", string.upper))]
        if not frame then Say("No frame called " .. rest .. "."); return end
    end

    local claimed, loose, textures = Audit(frame)
    local fname = frame:GetName() or "?"
    Say(("|cffe3b464%s|r: %d textures under it."):format(fname, textures))
    if S.packs and S.packs[fname] then
        Say("   |cff93b75chas a window pack.|r")
    end
    local any = false
    for part, n in pairs(claimed) do Say(("   %s x%d"):format(part, n)); any = true end
    if not any then Say("   nothing claimed. Is it reaching the walk at all?") end

    local list = {}
    for name, n in pairs(loose) do list[#list + 1] = { name, n } end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    if #list == 0 then
        Say("   no loose art.")
    else
        Say(("   |cffc0704a%d kinds of loose art|r (add a pattern to S.ORNATE or a part):"):format(#list))
        for i = 1, math.min(#list, 12) do
            Say(("      %s x%d"):format(list[i][1], list[i][2]))
        end
    end
end)

-- An instant way out. `/evui skin off` stops the module dead and puts
-- Blizzard's own look back on the next reload, without hunting through
-- the options for it.
EV:RegisterSlash("skinoff", function()
    local M = EV:GetModule("Skins", true)
    if not M then return end
    M.db.enabled = false
    Say("skins |cffc0704aoff|r. Reload to get Blizzard's look back: |cffe3b464/reload|r")
end)

EV:RegisterSlash("skinon", function()
    local M = EV:GetModule("Skins", true)
    if not M then return end
    M.db.enabled = true
    M:Refresh()
    Say("skins |cff93b75con|r.")
end)

-- Re-walk everything by hand, for when a window was built while we were
-- not looking.
EV:RegisterSlash("reskin", function()
    S.Sweep()
    local f = Focus()
    if f then S.Walk(f, 0) end
    Say("swept.")
end)
