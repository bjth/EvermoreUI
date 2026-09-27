--------------------------------------------------------------------------------
--  tools/skins/walk_test.lua
--  The skins walk and the pack layer, tested outside the game under Lua 5.1,
--  the Lua the client runs. Run from the repo root:
--
--      lua5.1 tools/skins/walk_test.lua
--
--  tools/check.py runs it when lua5.1 is on the PATH. Exits non-zero on any
--  failure.
--
--  What it pins down, because none of it shows up until a big window opens:
--    * a window's walk keeps to its time budget, a slice at a time, and a
--      small one is done before its OnShow returns
--    * walks queued while hidden share one budget a frame, and the one the
--      player opens goes first
--    * asking again mid-walk goes over the window once more, not twice at once
--    * a part's paint that walks synchronously never yields: Lua 5.1 cannot
--      yield across a pcall, and doing so is an error, not a slowdown
--    * a part that asks for its own window again, or a frame that dies
--      mid-walk, does not break the walk
--    * scroll box rows get one pass after a rebuild, none on a scroll
--    * a window is walked once per opening
--    * IsOrnate gives the answers the old per-pattern loop did, in two calls
--    * pack hooks go on once however often the pack runs; S.Window's paths
--      and its refusal of unknown fields; the dev commands
--------------------------------------------------------------------------------
EV_BLOCKED = false
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local failures, passes = 0, 0
local function ok(cond, what)
    if cond then passes = passes + 1 else failures = failures + 1; print("FAIL: " .. what) end
end

--------------------------------------------------------------------------------
--  A clock the tests control. Every object the walk looks at costs a little.
--------------------------------------------------------------------------------
local clock = 0
function debugprofilestop() return clock end
local COST_LOOK, COST_DRESS = 0.005, 0.01

--------------------------------------------------------------------------------
--  Timers and hooks, as the client does them.
--------------------------------------------------------------------------------
local timers = {}
C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTicker = function(_, fn) return { Cancel = function() end, fn = fn } end,
}
local function Flush()
    local run = timers
    timers = {}
    for _, fn in ipairs(run) do fn() end
end

function hooksecurefunc(obj, method, fn)
    if type(obj) == "string" then obj, method, fn = _G, obj, method end
    local orig = obj[method]
    if type(orig) ~= "function" then return end   -- Theme.lua hooks things this world lacks
    obj[method] = function(...)
        local r = { orig(...) }
        fn(...)
        return unpack(r)
    end
end

local errors = {}
function geterrorhandler() return function(e) errors[#errors + 1] = tostring(e) end end
function InCombatLockdown() return false end

--------------------------------------------------------------------------------
--  Frames: a tree with names, keys, visibility and scripts.
--------------------------------------------------------------------------------
local Frame = {}
local FrameMT = { __index = Frame }
local all = {}

local function New(name, parent, key)
    local f = setmetatable({ _children = {}, _regions = {}, _shown = true, _scripts = {}, _hooks = {} }, FrameMT)
    f._name = name
    if parent then
        f._parent = parent
        parent._children[#parent._children + 1] = f
        if key then parent[key] = f end
    end
    if name then _G[name] = f end
    all[#all + 1] = f
    return f
end
function Frame:GetObjectType() return "Frame" end
function Frame:IsObjectType(t) return t == "Frame" end
function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:IsForbidden()
    clock = clock + COST_LOOK
    return self._dead == true
end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetRegions() return unpack(self._regions) end
function Frame:IsShown() return self._shown end
function Frame:IsVisible()
    local f = self
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:SetScript(s, fn) self._scripts[s] = fn end
function Frame:HookScript(s, fn)
    self._hooks[s] = self._hooks[s] or {}
    table.insert(self._hooks[s], fn)
end
function Frame:RegisterEvent() end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:CreateTexture()
    return { SetColorTexture = function() end, SetAlpha = function() end, GetObjectType = function() return "Texture" end }
end
local function Open(f)
    f._shown = true
    for _, fn in ipairs(f._hooks.OnShow or {}) do fn(f) end
end

function CreateFrame() return New(nil, nil) end
UIParent = New("UIParent")
GameTooltip = New("GameTooltip")

-- A texture region.
local function Tex(parent, key)
    local t = { _alpha = 1 }
    function t:GetObjectType() return "Texture" end
    function t:SetAlpha(a) self._alpha = a end
    function t:SetAtlas() end
    function t:SetTexture() end
    function t:IsForbidden() return false end
    parent._regions[#parent._regions + 1] = t
    if key then parent[key] = t end
    return t
end

-- A window: `panels` panels of `buttons` buttons each.
local function Window(name, panels, buttons)
    local w = New(name, UIParent)
    for p = 1, panels do
        local panel = New(nil, w, "Panel" .. p)
        for b = 1, buttons do
            local btn = New(nil, panel)
            btn.IsButton = {}
        end
    end
    return w
end

local function Count(root)
    local n, dressed = 0, 0
    local function V(f)
        if f.IsButton then n = n + 1; if f._dressed then dressed = dressed + 1 end end
        for _, c in ipairs(f._children) do V(c) end
    end
    V(root)
    return n, dressed
end

--------------------------------------------------------------------------------
--  The addon, loaded as the client would.
--------------------------------------------------------------------------------
local slashes = {}
EvermoreUI = {
    _ModuleNS = {},
    Media = { Fetch = function() return "" end, FetchBold = function() return "" end },
    NewModule = function(_, name) return { name = name } end,
    RegisterSlash = function(_, name, fn) slashes[name] = fn end,
}
local function Load(path, addon, ns)
    local f = assert(loadfile(path))
    f(addon, ns)
end
Load("EvermoreUI/Core/Theme.lua", "EvermoreUI", {})
Load("EvermoreUI/Core/Looks.lua", "EvermoreUI", {})

-- Hairlines and fills, enough for a pack's Panel.
local function FakeTex() return { SetColorTexture = function() end, SetAlpha = function() end,
                                  SetVertexColor = function() end, GetObjectType = function() return "Texture" end } end
EvermoreUI.Pixel = {
    Fill = function() return FakeTex() end,
    Edges = function() return { FakeTex(), FakeTex(), FakeTex(), FakeTex() } end,
    EdgesOf = function() return nil end,
    SetEdgeColor = function() end,
    ResnapAll = function() end,
}

local ns = {}
Load("EvermoreUI_Skins/Core.lua", "EvermoreUI_Skins", ns)
Load("EvermoreUI_Skins/Packs.lua", "EvermoreUI_Skins", ns)
local printed = {}
local realPrint = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " ") end
Load("EvermoreUI_Skins/Dev.lua", "EvermoreUI_Skins", ns)
print = realPrint
local S = ns.S

-- One part: anything with IsButton. Dressing it costs time, as matching does.
local nestTarget, reenterRoot
S.Register{
    name = "testButton",
    keys = { "IsButton" },
    paint = function(b)
        clock = clock + COST_DRESS
        b._dressed = (b._dressed or 0) + 1
        -- A paint that walks something synchronously, past the deadline.
        if b.Nest and nestTarget then S.Walk(nestTarget, 0) end
        -- A paint that asks for its own window again.
        if b.Reenter and reenterRoot then S.Rewalk(reenterRoot) end
    end,
}

local BUDGET = S.WALK_BUDGET_MS
local EPS = COST_DRESS + COST_LOOK * 2
local runner = S.walkRunner

-- One drawn frame: the runner's OnUpdate, if it is shown.
local function Tick()
    if runner._shown and runner._scripts.OnUpdate then
        local t0 = clock
        runner._scripts.OnUpdate(runner, 0.016)
        return clock - t0
    end
    return 0
end
local function Drain(max)
    local frames = 0
    while runner._shown and frames < (max or 1000) do Tick(); frames = frames + 1 end
    return frames
end

--------------------------------------------------------------------------------
--  1. A small window on screen is dressed before OnShow returns.
--------------------------------------------------------------------------------
do
    local w = Window("SmallWindow", 2, 5)
    local after = 0
    S.Rewalk(w, function() after = after + 1 end)
    local n, dressed = Count(w)
    ok(dressed == n, "small window dressed at once")
    ok(after == 1, "small window: after ran once")
    ok(not S.Walking(w), "small window: no walk left over")
    ok(not runner._shown, "small window: runner idle")
end

--------------------------------------------------------------------------------
--  2. A big window keeps to the budget, a slice a frame, and finishes.
--------------------------------------------------------------------------------
do
    local w = Window("BigWindow", 40, 50)
    local after, worst = 0, 0
    local t0 = clock
    S.Rewalk(w, function() after = after + 1 end)
    local first = clock - t0
    ok(first <= BUDGET + EPS, ("big window: first slice %.2fms within budget"):format(first))
    ok(S.Walking(w), "big window: still walking after the first slice")
    local _, part = Count(w)
    ok(part > 0, "big window: first slice dressed something")
    local frames = 0
    while runner._shown and frames < 1000 do
        local spent = Tick()
        if spent > worst then worst = spent end
        frames = frames + 1
    end
    local n, dressed = Count(w)
    ok(dressed == n, ("big window: all %d dressed (got %d)"):format(n, dressed))
    ok(frames > 1, "big window: took more than one frame")
    ok(worst <= BUDGET + EPS, ("big window: worst frame %.2fms within budget"):format(worst))
    ok(after == 1, "big window: after ran once")
    local twice = false
    for _, f in ipairs(all) do if f._dressed and f._dressed > 1 then twice = true end end
    ok(not twice, "big window: nothing dressed twice")
end

--------------------------------------------------------------------------------
--  3. Hidden windows queue and share one budget a frame; opening one puts it
--     first and starts it now, without a second pass it does not need.
--------------------------------------------------------------------------------
do
    local a = Window("HiddenA", 30, 50); a:Hide()
    local b = Window("HiddenB", 30, 50); b:Hide()
    local afterA, afterB = 0, 0
    S.Rewalk(a, function() afterA = afterA + 1 end)
    S.Rewalk(b, function() afterB = afterB + 1 end)
    ok(#S.walkQueue == 2, "hidden windows: both queued")
    ok(S.walkQueue[1].nodes == 0 and S.walkQueue[2].nodes == 0, "hidden windows: nothing walked on request")
    local spent = Tick()
    ok(spent <= BUDGET + EPS, ("hidden windows: one frame %.2fms within one budget"):format(spent))
    ok(S.walkQueue[1] and S.walkQueue[1].root == a, "hidden windows: first come first")
    -- B has not started. Opening it puts it first and starts it now.
    local startedB = S.walkQueue[2].nodes
    ok(startedB == 0, "hidden windows: B not started yet")
    b:Show()
    local t1 = clock
    S.Rewalk(b, function() afterB = afterB + 1 end)
    ok(clock > t1, "opened window: started at once")
    ok(S.walkQueue[1] and S.walkQueue[1].root == b, "opened window: now first")
    ok(S.walkQueue[1].again ~= true, "opened window: no second pass for a walk that had not started")
    Drain()
    local nA, dA = Count(a)
    local nB, dB = Count(b)
    ok(dA == nA and dB == nB, "hidden windows: both finished")
    ok(afterA == 1 and afterB == 1, ("hidden windows: after once each (A %d, B %d)"):format(afterA, afterB))
end

--------------------------------------------------------------------------------
--  4. Asked again mid-walk: noted, and one more full pass after.
--------------------------------------------------------------------------------
do
    local w = Window("AgainWindow", 40, 50)
    local after = 0
    local function A() after = after + 1 end
    S.Rewalk(w, A)
    ok(S.Walking(w), "again: walking")
    S.Rewalk(w, A)
    S.Rewalk(w, A)
    ok(#S.walkQueue == 1, "again: still one walk")
    -- Something built after the walk passed it.
    local late = New(nil, w.Panel1); late.IsButton = {}
    Drain()
    ok(late._dressed == 1, "again: the late part was dressed by the second pass")
    ok(after == 2, ("again: after ran twice, once per pass (got %d)"):format(after))
end

--------------------------------------------------------------------------------
--  5. A paint that walks synchronously, past the deadline, never yields.
--------------------------------------------------------------------------------
do
    local before = #errors
    nestTarget = Window("NestTarget", 20, 50); nestTarget:Hide()
    local w = Window("NestWindow", 10, 50)
    -- Deep in the window, so the deadline has passed when the paint runs.
    local deep = New(nil, w.Panel9); deep.IsButton = {}; deep.Nest = true
    S.Rewalk(w)
    Drain()
    ok(#errors == before, "nested walk: no error (" .. tostring(errors[#errors]) .. ")")
    local n, d = Count(nestTarget)
    ok(d == n, "nested walk: the nested subtree was dressed whole")
    ok(not next(S.errors), "nested walk: no part errors")
    nestTarget = nil
end

--------------------------------------------------------------------------------
--  6. A paint that asks for its own window again; a frame that dies mid-walk.
--------------------------------------------------------------------------------
do
    local before = #errors
    local w = Window("ReenterWindow", 30, 50)
    reenterRoot = w
    local r = New(nil, w.Panel1); r.IsButton = {}; r.Reenter = true
    local after = 0
    S.Rewalk(w, function() after = after + 1 end)
    Drain()
    ok(#errors == before, "re-entry: no error (" .. tostring(errors[#errors]) .. ")")
    ok(after >= 1, "re-entry: finished")
    reenterRoot = nil

    local d = Window("DyingWindow", 40, 50)
    S.Rewalk(d)
    d.Panel40._dead = true
    for _, c in ipairs(d.Panel40._children) do c._dead = true end
    Drain()
    ok(#errors == before, "dying frame: no error")
    ok(not S.Walking(d), "dying frame: walk finished")
end

--------------------------------------------------------------------------------
--  7. Adopt: walk, pack after, and on show once, with no second pass queued.
--------------------------------------------------------------------------------
do
    local w = Window("AdoptWindow", 2, 3)
    local packs = 0
    S.Pack{ name = "AdoptWindow", apply = function() packs = packs + 1 end }
    timers = {}
    S.Adopt(w)
    ok(packs == 1, "adopt: pack ran after the walk")
    Open(w)
    ok(packs == 2, "adopt: pack ran on show")
    ok(#timers == 0, "adopt: no second pass queued for the frame after")
    -- A big window opened: one walk, not a second on top of it.
    local big = Window("AdoptBig", 40, 50)
    big:Hide()
    S.Adopt(big)
    Drain()
    Open(big)
    Flush(); Drain()
    ok(not S.Walking(big), "adopt: big window walked once and done")
end

--------------------------------------------------------------------------------
--  8. Scroll box rows: dressed on init; one pass after a rebuild, however many
--     rebuilds; none on a scroll.
--------------------------------------------------------------------------------
do
    ScrollUtil = { AddInitializedFrameCallback = function(box, cb) box._init = cb end }
    local box = New("TestBox", UIParent)
    local rows = {}
    for i = 1, 8 do
        local row = New(nil, box); row.IsButton = {}; rows[i] = row
    end
    function box:ForEachFrame(fn) for _, r in ipairs(rows) do fn(r) end end
    function box:FullUpdateInternal() end
    function box:Update() end
    S.FollowScrollBox(box)
    local all8 = true
    for _, r in ipairs(rows) do if r._dressed ~= 1 then all8 = false end end
    ok(all8, "rows: dressed when followed")
    ok(type(box._init) == "function", "rows: init callback registered")
    -- A row initialised later.
    local new = New(nil, box); new.IsButton = {}
    box._init(nil, new)
    ok(new._dressed == 1, "rows: a new row dressed on init")
    -- A child a rebuild adds to a row after its init.
    local extra = New(nil, rows[1]); extra.IsButton = {}
    timers = {}
    for _ = 1, 5 do box:Update() end
    ok(#timers == 0, "rows: no pass on scroll updates")
    for _ = 1, 5 do box:FullUpdateInternal() end
    ok(#timers == 1, ("rows: one pass for five rebuilds (got %d)"):format(#timers))
    Flush()
    ok(extra._dressed == 1, "rows: the late child dressed by the pass")
    box:FullUpdateInternal()
    ok(#timers == 1, "rows: a later rebuild queues again")
    Flush()
    S.FollowScrollBox(box)
    ok(true, "rows: following twice is harmless")
end

--------------------------------------------------------------------------------
--  9. Packs: hooks once however often apply runs; keys; Find; S.Window.
--------------------------------------------------------------------------------
do
    local f = New("PackFrame", UIParent)
    local inset = New(nil, f, "Inset")
    local bg = Tex(inset, "Bg")
    f.Refresh = function() end
    local enter, refreshed = 0, 0
    S.Pack{ name = "PackFrame", apply = function(frame, k)
        k:Hook(frame, "OnEnter", function() enter = enter + 1 end)
        k:After(frame, "Refresh", function() refreshed = refreshed + 1 end)
        k:Hook(frame, "OnEnter", function() enter = enter + 10 end, "second")
        k:Once(frame, "made", function(o) o._made = (o._made or 0) + 1 end)
    end }
    for _ = 1, 4 do S.ApplyPack(f) end
    for _, fn in ipairs(f._hooks.OnEnter or {}) do fn(f) end
    f:Refresh()
    ok(enter == 11, ("pack hooks: one of each key after four runs (got %d)"):format(enter))
    ok(refreshed == 1, ("pack hooks: method hooked once (got %d)"):format(refreshed))
    ok(f._made == 1, "pack hooks: Once ran once")

    local k = S.NewKit(f)
    ok(k:Find(".Inset.Bg") == bg, "find: relative path")
    ok(k:Find("PackFrame.Inset") == inset, "find: global path")
    ok(k:Find(".Nope.Bg") == nil, "find: missing step is nil")
    ok(k:Find("NoSuchGlobal.X") == nil, "find: missing global is nil")
    ok(k:Find(inset) == inset, "find: a table comes straight back")

    local bad = pcall(S.Window, { name = "Typo", panel = {} })
    ok(not bad, "S.Window: an unknown field is refused")

    local g = New("DescribedFrame", UIParent)
    local gi = New(nil, g, "Inset")
    local gbg = Tex(gi, "Bg")
    local pane = New(nil, g, "Pane")
    local late = New(nil, pane); late.IsButton = {}
    local order = {}
    S.Window{
        name   = "DescribedFrame",
        mute   = { ".Inset.Bg", ".Missing.Piece" },
        panels = { [".Pane"] = "surfaceSunk" },
        dress  = { ".Pane" },
        apply  = function() order[#order + 1] = "apply" end,
    }
    S.ApplyPack(g)
    ok(gbg._alpha == 0, "S.Window: mute hid the texture")
    ok(late._dressed == 1, "S.Window: dress walked the pane")
    ok(order[1] == "apply", "S.Window: apply ran")
    ok(not S.lastPackError or not S.lastPackError:find("DescribedFrame"), "S.Window: a missing path is skipped, not an error")
end

--------------------------------------------------------------------------------
--  10. Dev commands.
--------------------------------------------------------------------------------
do
    local out = {}
    print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
    slashes.skin("profile")
    ok(S.profiling == true, "profile: on")
    local w = Window("ProfiledWindow", 2, 3)
    S.Rewalk(w)
    local reported = false
    for _, line in ipairs(out) do if line:find("walk", 1, true) and line:find("ProfiledWindow", 1, true) then reported = true end end
    ok(reported, "profile: a finished walk is reported")
    slashes.skin("profile")
    ok(not S.profiling, "profile: off")

    local holder = New("FindHolder", UIParent)
    local label = New(nil, holder, "Label")
    label._regions[1] = { GetText = function() return "Hello There" end, GetObjectType = function() return "FontString" end }
    local list, i = { holder, label }, 0
    EnumerateFrames = function(prev)
        if prev == nil then i = 1 else i = i + 1 end
        return list[i]
    end
    out = {}
    slashes.skin("find hello")
    ok(out[1] and out[1]:find("FindHolder.Label", 1, true), "find: path of the frame showing the text (" .. tostring(out[1]) .. ")")
    out = {}
    slashes.skin("find nothing like it")
    ok(out[1] and out[1]:find("Nothing on screen", 1, true), "find: says when nothing matches")
    print = realPrint
end

--------------------------------------------------------------------------------
--  11. IsOrnate: the same verdicts as the pattern-by-pattern loop it replaced,
--      far fewer calls, and a pooled texture given new art judged afresh.
--------------------------------------------------------------------------------
do
    local ns2 = {}
    Load("EvermoreUI_Skins/Core.lua", "EvermoreUI_Skins", ns2)
    Load("EvermoreUI_Skins/Parts.lua", "EvermoreUI_Skins", ns2)
    local S2 = ns2.S
    -- File art as the client hands it back: an opaque id per file.
    S2.TexID = function(path) return "FileData ID " .. path:lower() end
    local function Old(region)
        for _, pattern in ipairs(S2.ORNATE) do if S2.ArtIs(region, pattern) then return true end end
        for _, path in ipairs(S2.ORNATE_FILES) do if S2.ArtIsFile(region, path) then return true end end
        return false
    end
    local calls = 0
    local function Region(atlas, tex)
        return {
            GetAtlas = function() calls = calls + 1; return atlas end,
            GetTexture = function() calls = calls + 1; return tex end,
        }
    end
    local atlases = { nil, "", "UI-Frame-Metal-CornerTopLeft", "common-dropdown-a-button", "QuestBG-Parchment",
                      "ui-hud-actionbar-iconframe", "Professions-Icon-Quality", "communities-list-row" }
    local texes = { nil, "", 132089, "Interface\\Icons\\INV_Misc_Bag_08",
                    "Interface\\Common\\Some-Border-Piece", "FileData ID 424242" }
    for _, path in ipairs(S2.ORNATE_FILES) do texes[#texes + 1] = S2.TexID(path) end
    local same, n, disagree = true, 0, nil
    for ai = 0, #atlases do
        for ti = 0, #texes do
            local r = Region(atlases[ai], texes[ti])
            local want = Old(r)
            for _ = 1, 2 do     -- the second time is from the cache
                if S2.IsOrnate(r) ~= want then same = false; disagree = tostring(atlases[ai]) .. " / " .. tostring(texes[ti]) end
            end
            n = n + 1
        end
    end
    ok(same, ("IsOrnate: same verdicts as before on %d combinations (%s)"):format(n, tostring(disagree)))
    local r = Region("UI-Frame-Metal-CornerTopLeft", nil)
    calls = 0; Old(r); local oldCalls = calls
    calls = 0; S2.IsOrnate(r); local newCalls = calls
    ok(newCalls <= 2, ("IsOrnate: %d calls a region, was %d"):format(newCalls, oldCalls))
    -- Pooled: the same region, new art.
    local atlas = "UI-Frame-Metal-CornerTopLeft"
    local pooled = { GetAtlas = function() return atlas end, GetTexture = function() return nil end }
    ok(S2.IsOrnate(pooled) == true, "IsOrnate: decoration while it holds a corner")
    atlas = "ui-hud-actionbar-iconframe"
    ok(S2.IsOrnate(pooled) == false, "IsOrnate: judged afresh when it holds something else")
end

ok(#errors == 0, "no errors raised: " .. tostring(errors[1]))
print(("skins walk test: %d passed, %d failed"):format(passes, failures))
os.exit(failures == 0 and 0 or 1)
