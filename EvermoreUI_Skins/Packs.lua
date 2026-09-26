if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Packs.lua
--  The per-window layer: the thing the generic walk cannot do.
--
--  The walk in Core.lua matches by FINGERPRINT. It is very good at Blizzard's
--  templates, and it is structurally incapable of two things:
--
--    1. Chrome that is neither a template nor a named atlas: a window that
--       hangs one big art sheet onto itself, a pane assembled in Lua, a
--       border drawn from four loose corner textures. Nothing about it says
--       what it is. Only knowing the window tells you.
--    2. Anything that needs a decision. Whether this particular button row
--       should be evened up, whether that inset should lose 4px, whether the
--       gap Blizzard left is a gap or a band with a dropdown parked in it.
--
--  So: a pack is written against ONE named window, by a person who opened it
--  and looked. That is what buys it the right to move things.
--
--  THE RULE, restated precisely, because getting it wrong is what caused
--  every layout bug this suite has had:
--
--      Nothing that matches by GUESS may move anything.
--      A pack, which matches by NAME, may.
--
--  It is enforced by which object you are handed, not by discipline. A part's
--  paint gets a Painter, which has no SetPoint, no SetSize and no SetParent.
--  A pack's apply gets a Kit, which has all of the Painter's verbs plus
--  Move, Size and Anchor. There is no way to move a frame from inside a part,
--  and no way to write a pack that applies to windows in general.
--
--  The split is deliberate: the generic engine only ever positions its own
--  shells, and anything that moves Blizzard's frames is written by hand, one
--  named window at a time.
--
--  A pack looks like this:
--
--      S.Pack{
--          name  = "FriendsFrame",
--          addon = "Blizzard_FriendsFrame",   -- optional, load-on-demand
--          apply = function(f, k)
--              k:Strip(f.Inset)               -- loose file chrome
--              k:Panel(f.ListPane, "surfaceSunk")
--              k:Move(f.Tab1, "TOPLEFT", f, "BOTTOMLEFT", 8, -2)
--          end,
--      }
--------------------------------------------------------------------------------
local ADDON, ns = ...
local EV = EvermoreUI
if not EV then return end
local S, T = ns.S, EV.Theme
if not S then return end

local packs = {}
S.packs = packs

--------------------------------------------------------------------------------
--  The Kit
--
--  Everything here takes the object as its first argument, because a pack
--  works across a whole window rather than on one claimed object.
--------------------------------------------------------------------------------
local Kit = {}
Kit.__index = Kit

local function Alive(o) return S.Alive(o) end

--- Is it unsafe to move this right now? Protected frames cannot be moved in
--- combat, and trying taints. Queued work runs at PLAYER_REGEN_ENABLED.
local queued = {}
local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function()
    local todo = queued
    queued = {}
    for _, fn in ipairs(todo) do pcall(fn) end
end)

local function Locked(obj)
    if not InCombatLockdown() then return false end
    if type(obj) ~= "table" or not obj.IsProtected then return false end
    local ok, prot = pcall(obj.IsProtected, obj)
    return ok and prot
end

local function Later(fn)
    queued[#queued + 1] = fn
end

--------------------------------------------------------------------------------
--  Painting. Same vocabulary as the Painter, addressed by object.
--------------------------------------------------------------------------------

--- Run the generic walk over a subtree. For panes Blizzard builds late.
function Kit:Dress(obj)
    if Alive(obj) then S.Walk(obj, 0) end
    return self
end

--- Fade every texture on an object (not its children).
function Kit:Fade(obj)
    if not Alive(obj) then return self end
    for _, r in ipairs(S.Regions(obj)) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then S.Mute(r) end
    end
    return self
end

--- Fade every texture under an object, to a depth. This is the blunt tool for
--- a window that hangs one art sheet across several frames.
function Kit:Strip(obj, depth)
    depth = depth or 4
    local function Visit(o, d)
        if d > depth or not Alive(o) or S.ours[o] then return end
        self:Fade(o)
        for _, c in ipairs(S.Children(o)) do Visit(c, d + 1) end
    end
    Visit(obj, 0)
    return self
end

--- Fade only the textures drawn from these files, anywhere under the object.
--- The precise tool: takes a window's own art sheet down and leaves its
--- icons, portraits and bar fills alone.
function Kit:Art(obj, ...)
    local paths = { ... }
    local function Visit(o, d)
        if d > 6 or not Alive(o) or S.ours[o] then return end
        for _, r in ipairs(S.Regions(o)) do
            if r.GetObjectType and r:GetObjectType() == "Texture" and not S.ours[r] then
                for _, path in ipairs(paths) do
                    if S.ArtIsFile(r, path) then S.Mute(r) break end
                end
            end
        end
        for _, c in ipairs(S.Children(o)) do Visit(c, d + 1) end
    end
    Visit(obj, 0)
    return self
end

--- Our flat surface behind an object's own drawing.
function Kit:Fill(obj, token, alpha, sub)
    if not (Alive(obj) and obj.CreateTexture) then return self end
    local d = S.D(obj)
    if not d.packFill then
        d.packFill = S.Ours(obj:CreateTexture(nil, "BACKGROUND", nil, sub or -7))
        d.packFill:SetAllPoints(obj)
    end
    d.packFillToken, d.packFillAlpha = token, alpha
    local function Paint(self2) self2:SetColorTexture(T.RGBA(d.packFillToken, d.packFillAlpha)) end
    Paint(d.packFill)
    T.Watch(d.packFill)
    d.packFill.Paint = Paint
    return self
end

--- One physical pixel of border on four textures of our own.
function Kit:Border(obj, token, alpha)
    if not (Alive(obj) and obj.CreateTexture) then return self end
    local d = S.D(obj)
    if not d.packEdges then
        local e = {}
        for i = 1, 4 do
            e[i] = S.Ours(obj:CreateTexture(nil, "BORDER", nil, 7))
            -- See the note in Painter:Border: a hairline that is not exempt
            -- from texel snapping is not reliably a hairline.
            if EV.Pixel and EV.Pixel.NoSnap then EV.Pixel.NoSnap(e[i]) end
        end
        e[1]:SetPoint("TOPLEFT");    e[1]:SetPoint("TOPRIGHT")
        e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT")
        e[3]:SetPoint("TOPLEFT");    e[3]:SetPoint("BOTTOMLEFT")
        e[4]:SetPoint("TOPRIGHT");   e[4]:SetPoint("BOTTOMRIGHT")
        d.packEdges = e
    end
    do
        local px = (EV.Pixel and EV.Pixel.One and EV.Pixel:One(obj)) or 1
        local e = d.packEdges
        e[1]:SetHeight(px); e[2]:SetHeight(px)
        e[3]:SetWidth(px);  e[4]:SetWidth(px)
    end
    d.packEdgeToken, d.packEdgeAlpha = token or "border", alpha
    local function Paint()
        for _, t in ipairs(d.packEdges) do t:SetColorTexture(T.RGBA(d.packEdgeToken, d.packEdgeAlpha)) end
    end
    Paint()
    T.Watch(d.packEdges[1])
    d.packEdges[1].Paint = Paint
    return self
end

--- Fade, fill and border in one: the common case for a pane.
function Kit:Panel(obj, token, alpha)
    if not Alive(obj) then return self end
    self:Fade(obj)
    if obj.NineSlice then
        for _, k in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner",
                             "BottomRightCorner", "TopEdge", "BottomEdge",
                             "LeftEdge", "RightEdge", "Center" }) do
            local r = obj.NineSlice[k]
            if type(r) == "table" then S.Mute(r) end
        end
        self:Fade(obj.NineSlice)
    end
    self:Fill(obj, token or "surface1", alpha)
    self:Border(obj, "border")
    return self
end

--- A font string takes our face and a token colour. Size stays Blizzard's.
function Kit:Label(fs, token, bold)
    if not (fs and fs.GetFont and fs.SetFont) then return self end
    local ok, _, size = pcall(fs.GetFont, fs)
    if not ok then return self end
    size = S.Num(size) or 12
    local path = bold and T.FontBoldPath() or T.FontPath()
    if path then pcall(fs.SetFont, fs, path, size, "") end
    if token ~= false then
        local d = S.D(fs)
        d.token = token or "text"
        fs:SetTextColor(T.RGBA(d.token))
        T.Watch(fs)
        fs.Paint = function(self2) self2:SetTextColor(T.RGBA(S.D(self2).token)) end
    end
    return self
end

--- Hide without hiding: alpha 0, never Hide(), because Blizzard's own code
--- and Edit Mode both measure frames that are shown.
function Kit:Mute(obj)
    if Alive(obj) and obj.SetAlpha then obj:SetAlpha(0) end
    return self
end

--- Undo the generic layer's background on one frame, and stop it coming
--- back on the next OnShow re-walk. For a frame that is chrome drawn OVER
--- content: filling it hides whatever is beneath.
function Kit:NoFill(obj)
    if not Alive(obj) then return self end
    local d = S.D(obj)
    d.wantsFill = false
    if d.fill and d.fill.SetAlpha then d.fill:SetAlpha(0) end
    if d.packFill and d.packFill.SetAlpha then d.packFill:SetAlpha(0) end
    return self
end

function Kit:Hook(obj, script, fn)
    if Alive(obj) and obj.HookScript then obj:HookScript(script, fn) end
    return self
end

function Kit:After(obj, method, fn)
    if Alive(obj) and type(obj[method]) == "function" then
        pcall(hooksecurefunc, obj, method, fn)
    end
    return self
end

--------------------------------------------------------------------------------
--  Movement. ONLY available here.
--
--  Every mover is idempotent: the original anchors are kept the first time,
--  and a re-run sets absolute values rather than nudging again. Packs re-run
--  on OnShow, so a relative adjustment would walk the frame off the screen
--  over a session.
--------------------------------------------------------------------------------

--- Remember where Blizzard had it, once.
local function Remember(obj)
    local d = S.D(obj)
    if d.packOrigin then return d.packOrigin end
    local pts = {}
    local n = (obj.GetNumPoints and obj:GetNumPoints()) or 0
    for i = 1, n do
        local a, rel, rp, x, y = obj:GetPoint(i)
        if not a then break end
        pts[#pts + 1] = { a, rel, rp, x or 0, y or 0 }
    end
    -- `local w, h = obj.GetSize and obj:GetSize()` would NOT work here: the
    -- `and` truncates the call to a single value, so h would always be nil.
    local w, h
    if obj.GetSize then
        local ok, gw, gh = pcall(obj.GetSize, obj)
        if ok then w, h = gw, gh end
    end
    d.packOrigin = { points = pts, w = S.Num(w), h = S.Num(h) }
    return d.packOrigin
end
S.Remember = Remember

--- Put an object somewhere. Clears its anchors and sets exactly one.
function Kit:Move(obj, point, rel, relPoint, x, y)
    if not Alive(obj) or not obj.SetPoint then return self end
    if Locked(obj) then
        Later(function() self:Move(obj, point, rel, relPoint, x, y) end)
        return self
    end
    Remember(obj)
    obj:ClearAllPoints()
    obj:SetPoint(point, rel or obj:GetParent(), relPoint or point, x or 0, y or 0)
    return self
end

--- Set SEVERAL anchors at once, replacing whatever was there.
---
--- Move sets one point, which is wrong for anything Blizzard stretches
--- between two corners: the world map's nav bar is anchored TOPLEFT and
--- BOTTOMRIGHT to the title spacer, so clearing it down to a single point
--- collapses it to its minimum width.
---
--- Each entry is { point, relativeTo, relativePoint, x, y }.
function Kit:Anchors(obj, points)
    if not Alive(obj) or not obj.SetPoint then return self end
    if type(points) ~= "table" or #points == 0 then return self end
    if Locked(obj) then
        Later(function() self:Anchors(obj, points) end)
        return self
    end
    Remember(obj)
    obj:ClearAllPoints()
    for _, pt in ipairs(points) do
        pcall(obj.SetPoint, obj, pt[1], pt[2] or obj:GetParent(), pt[3] or pt[1], pt[4] or 0, pt[5] or 0)
    end
    return self
end

--- Nudge an object from where Blizzard put it. Measured from the REMEMBERED
--- anchors, so running it twice does not move it twice.
function Kit:Nudge(obj, dx, dy)
    if not Alive(obj) or not obj.SetPoint then return self end
    if Locked(obj) then
        Later(function() self:Nudge(obj, dx, dy) end)
        return self
    end
    local origin = Remember(obj)
    if #origin.points == 0 then return self end
    obj:ClearAllPoints()
    for _, pt in ipairs(origin.points) do
        obj:SetPoint(pt[1], pt[2], pt[3], pt[4] + (dx or 0), pt[5] + (dy or 0))
    end
    return self
end

--- Set a size, remembering the original.
function Kit:Size(obj, w, h)
    if not Alive(obj) or not obj.SetSize then return self end
    if Locked(obj) then
        Later(function() self:Size(obj, w, h) end)
        return self
    end
    local origin = Remember(obj)
    obj:SetSize(w or origin.w or obj:GetWidth(), h or origin.h or obj:GetHeight())
    return self
end

--- Put everything back where Blizzard had it. For `/evui skin packoff`.
function Kit:Restore(obj)
    local d = S.D(obj)
    local origin = d.packOrigin
    if not (origin and Alive(obj)) then return self end
    if Locked(obj) then return self end
    if #origin.points > 0 and obj.SetPoint then
        obj:ClearAllPoints()
        for _, pt in ipairs(origin.points) do obj:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
    end
    if origin.w and origin.h and obj.SetSize then obj:SetSize(origin.w, origin.h) end
    return self
end

--- Space a row of objects evenly across a width. The one layout helper worth
--- sharing, because a bottom button row is the commonest hand fix there is,
--- and doing it by eye per pack gets it subtly wrong every time.
function Kit:Row(objs, parent, gap, inset, bottom)
    gap, inset, bottom = gap or 8, inset or 8, bottom or 8
    if not Alive(parent) then return self end
    local live = {}
    for _, o in ipairs(objs) do if Alive(o) then live[#live + 1] = o end end
    if #live == 0 then return self end
    if Locked(parent) then
        Later(function() self:Row(objs, parent, gap, inset, bottom) end)
        return self
    end
    local total = S.Num(parent:GetWidth())
    if not total then return self end
    local each = (total - inset * 2 - gap * (#live - 1)) / #live
    if each < 1 then return self end
    for i, o in ipairs(live) do
        Remember(o)
        o:ClearAllPoints()
        o:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT",
                   inset + (i - 1) * (each + gap), bottom)
        if o.SetWidth then o:SetWidth(each) end
    end
    return self
end

--------------------------------------------------------------------------------
--  Registration and dispatch
--------------------------------------------------------------------------------
function S.Pack(pack)
    assert(type(pack) == "table" and pack.name and pack.apply,
        "a pack needs a name and an apply")
    local names = type(pack.name) == "table" and pack.name or { pack.name }
    for _, n in ipairs(names) do
        assert(not packs[n], ("two packs claim %s"):format(n))
        packs[n] = pack
    end
    pack.frames = names
    return pack
end

S.packErrors = {}

--- Run the pack for a frame, if there is one. Called after the walk has
--- dressed it, and again whenever it is shown.
function S.ApplyPack(frame)
    if not S.Alive(frame) then return end
    if S.module and S.module.db and S.module.db.enabled == false then return end
    local name = frame.GetName and frame:GetName()
    if not name then return end
    local pack = packs[name]
    if not pack then return end
    if S.module and S.module.db and S.module.db.packs
        and S.module.db.packs[name] == false then return end
    local k = setmetatable({ frame = frame, pack = pack }, Kit)
    local ok, err = pcall(pack.apply, frame, k)
    if not ok then
        S.packErrors[name] = (S.packErrors[name] or 0) + 1
        S.lastPackError = ("%s: %s"):format(name, tostring(err))
        geterrorhandler()(("EvermoreUI Skins pack (%s): %s"):format(name, tostring(err)))
    end
    return pack
end

--- A kit not tied to a registered pack, for the dev commands.
function S.NewKit(frame)
    return setmetatable({ frame = frame }, Kit)
end

S.Kit = Kit
