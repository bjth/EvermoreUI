--------------------------------------------------------------------------------
--  tools/survey/coverage.lua
--  Which part claims each of Blizzard's templates, measured with the real
--  fingerprints. It loads EvermoreUI_Skins/Core.lua and Parts.lua in a stub
--  environment, builds a stand-in object for every template from the shapes
--  the survey resolved, and runs S.Matches over each one in registration
--  order, first match wins, exactly as S.Dress does in game.
--
--  There is no second copy of any fingerprint here. If a part's fingerprint
--  goes stale after a client patch, this says so the first time it runs.
--
--  The survey runs it for you (tools/survey/survey.py), through lupa or a
--  lua5.1 on the PATH. By hand, from the repo root, with a shapes file the
--  survey wrote with --shapes:
--
--      lua5.1 tools/survey/coverage.lua shapes.lua            summary
--      lua5.1 tools/survey/coverage.lua shapes.lua all        every template
--      lua5.1 tools/survey/coverage.lua shapes.lua tsv        for the survey
--
--  What a stand-in object can and cannot tell you:
--    * It has the object type, the parentKey children, the $parent-named
--      globals, the art on every region (atlas or file), the button art
--      slots and the frame's KeyValues, all with inheritance applied.
--    * It has no mixin methods and nothing a script adds at runtime. A part
--      that fingerprints on those (navCrumb, which asks who its parent is)
--      cannot be measured here; those are listed under RUNTIME below and
--      reported as such rather than as dead.
--    * File art is compared the way the client compares it: by an opaque
--      file id, never by reading the path back. An atlas pattern cannot
--      match a file texture here any more than it can in game.
--    * A template instance is assumed to be named, so its $parent regions
--      are reachable through S.Sub. An anonymous instance would not be.
--------------------------------------------------------------------------------

-- Parts that recognise an object by something only a live frame has, and the
-- templates they claim in game. Counted as covered and named in the report,
-- so the claim stays visible and gets checked in game with /evui skin this.
local RUNTIME = {
    navCrumb = { why = "matches on its parent being a nav bar, which only exists at runtime",
                 claims = { "NavButtonTemplate" } },
    -- <ItemButton> inherits the intrinsic "ItemButton" (Blizzard_ItemButton,
    -- intrinsic="true"), which declares IconBorder, icon and Count. The survey
    -- does not model intrinsics, so no stand-in carries an IconBorder.
    itemButton = { why = "its IconBorder comes from the ItemButton intrinsic, which the survey does not model",
                   claims = { "PaperDollItemSlotButtonTemplate", "InspectPaperDollItemSlotButtonTemplate",
                              "ContainerFrameItemButtonTemplate", "BankItemButtonTemplate",
                              "CamelotBankItemButtonTemplate", "GuildBankItemButtonTemplate",
                              "EquipmentFlyoutButtonTemplate", "OpenMailAttachment",
                              "ProfessionsButtonTemplate", "ProfessionsGearSlotTemplate" } },
    -- The header's banner atlas is chosen in Init (Options_CategoryHeader_<n>),
    -- so the template carries no atlas for the survey to read.
    settingsHeader = { why = "its banner atlas is set in Init, not declared in the template",
                       claims = { "SettingsCategoryListHeaderTemplate" } },
}

local function Main(shapesPath, root, mode, emit)
    root = root or "."
    emit = emit or print

    ----------------------------------------------------------------------------
    --  A stub world, just enough for Core.lua and Parts.lua to load.
    ----------------------------------------------------------------------------
    local function Stub()
        return setmetatable({}, { __index = function() return function() end end })
    end
    EV_BLOCKED = nil
    wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
    hooksecurefunc = function() end
    CreateFrame = function() return Stub() end
    UIParent = Stub()
    GameTooltip = Stub()
    geterrorhandler = function() return function(e) emit("error\t" .. tostring(e)) end end

    local modules = {}
    EvermoreUI = {
        _ModuleNS = {},
        Media = { Fetch = function() return "" end, FetchBold = function() return "" end },
        Pixel = Stub(),
        NewModule = function(_, name) local m = { name = name }; modules[name] = m; return m end,
    }
    local function Load(path, addon, ns)
        local f, err = loadfile(root .. "/" .. path)
        if not f then error(err, 0) end
        f(addon, ns)
    end
    Load("EvermoreUI/Core/Theme.lua", "EvermoreUI", {})
    Load("EvermoreUI/Core/Looks.lua", "EvermoreUI", {})
    local ns = {}
    Load("EvermoreUI_Skins/Core.lua", "EvermoreUI_Skins", ns)
    Load("EvermoreUI_Skins/Parts.lua", "EvermoreUI_Skins", ns)
    local S = ns.S
    assert(S and S.parts and S.Matches, "EvermoreUI_Skins did not load: no S.parts")

    ----------------------------------------------------------------------------
    --  File art as the client sees it: an id, the same for the same file.
    ----------------------------------------------------------------------------
    local ids, nextId = {}, 100000
    local function Norm(path)
        return (path:lower():gsub("/", "\\"):gsub("%.blp$", ""):gsub("%.tga$", ""):gsub("%.png$", ""))
    end
    local function FileID(key)
        local id = ids[key]
        if not id then nextId = nextId + 1; id = "FileData ID " .. nextId; ids[key] = id end
        return id
    end
    S.TexID = function(path) return FileID("file:" .. Norm(path)) end

    local data = dofile(shapesPath)
    local PARENT, TEXTURE, FONT = data.parent, data.texture, data.font

    ----------------------------------------------------------------------------
    --  Stand-in objects.
    ----------------------------------------------------------------------------
    local info = setmetatable({}, { __mode = "k" })
    local Obj = {}
    local Class = { __index = Obj }

    local function Kind(t)
        if TEXTURE[t] then return "Texture" end
        if FONT[t] then return "FontString" end
        return t
    end
    function Obj:GetObjectType() return Kind(info[self].t) end
    function Obj:IsObjectType(want)
        local t, n = Kind(info[self].t), 0
        while t and n < 12 do
            if t == want then return true end
            t = PARENT[t]; n = n + 1
        end
        return false
    end
    function Obj:GetName() return info[self].name end
    function Obj:GetParent() return info[self].parent end
    function Obj:GetAtlas() return info[self].a end
    function Obj:GetTexture()
        local i = info[self]
        if i.a then return FileID("atlas:" .. i.a:lower()) end
        if i.f then return FileID("file:" .. Norm(i.f)) end
        return nil
    end
    local function Slot(role)
        return function(self) return info[self].slots[role] end
    end
    Obj.GetNormalTexture = Slot("NormalTexture")
    Obj.GetPushedTexture = Slot("PushedTexture")
    Obj.GetHighlightTexture = Slot("HighlightTexture")
    Obj.GetDisabledTexture = Slot("DisabledTexture")
    Obj.GetCheckedTexture = Slot("CheckedTexture")
    Obj.GetThumbTexture = Slot("ThumbTexture")
    Obj.GetFontString = Slot("ButtonText")

    local made = {}
    local function Build(o, name, parent)
        local obj = setmetatable({}, Class)
        info[obj] = { t = o.t, a = o.a, f = o.f, name = name, parent = parent, slots = {}, kids = {} }
        -- KeyValues become plain fields on the frame, as the client sets them.
        for k, v in pairs(o.kv or {}) do rawset(obj, k, v) end
        for _, c in ipairs(o.ch or {}) do
            local cname
            if c.n then
                if c.n:find("^%$parent") then
                    cname = name and (name .. c.n:sub(8))
                elseif not c.n:find("%$") then
                    cname = c.n
                end
            end
            local child = Build(c, cname, obj)
            info[obj].kids[#info[obj].kids + 1] = child
            if c.k and not c.k:find("[%.%$]") then rawset(obj, c.k, child) end
            if c.role then info[obj].slots[c.role] = child end
            if cname then _G[cname] = child; made[#made + 1] = cname end
        end
        return obj
    end
    local function Clear()
        for i = #made, 1, -1 do _G[made[i]] = nil; made[i] = nil end
    end

    ----------------------------------------------------------------------------
    --  The measurement.
    --
    --  Three passes over the same objects:
    --    templates  each template's own root, the headline number. `sites` is
    --               how many places inherit the template.
    --    inside     frames a template declares inside itself (the gold box in
    --               the money input frame, the steppers on a scroll bar). The
    --               walk dresses those too, and a part written for them, such
    --               as moneyBox, claims no template root at all. Only the
    --               template's OWN declarations are walked; what it inherits
    --               is measured on the template it came from.
    --    frames     Blizzard's named frames, the instances the player sees,
    --               every object in each one.
    ----------------------------------------------------------------------------
    local order = {}
    for i, part in ipairs(S.parts) do order[i] = part.name end

    local errors = {}
    local function First(obj, where)
        local hits = {}
        for _, part in ipairs(S.parts) do
            local ok, res = pcall(S.Matches, part, obj)
            if not ok then
                errors[#errors + 1] = ("%s on %s: %s"):format(part.name, where, tostring(res))
            elseif res then
                hits[#hits + 1] = part.name
            end
        end
        return hits[1], hits
    end
    local function RuntimeClaim(name)
        for pname, r in pairs(RUNTIME) do
            for _, t in ipairs(r.claims) do
                if t == name then return pname end
            end
        end
    end
    local function IsFrame(o) return not TEXTURE[o.t] and not FONT[o.t] end

    --- Walk the stand-in `obj` built from shape `o`, calling fn on every frame
    --- below the root, keyed or not. `ownOnly` stops at children the shape
    --- inherited.
    local function Descend(obj, o, ownOnly, fn)
        local kids = info[obj].kids
        for i, c in ipairs(o.ch or {}) do
            local child = kids[i]
            if child and IsFrame(c) and (c.own or not ownOnly) then
                fn(child, c)
                Descend(child, c, ownOnly, fn)
            end
        end
    end

    local rows, byPart = {}, {}
    local function Tally(pname, field, n)
        local b = byPart[pname]
        if not b then b = { templates = 0, sites = 0, inside = 0, insideSites = 0, frames = 0 }; byPart[pname] = b end
        b[field] = b[field] + n
    end
    local insideRows = {}
    for i, tpl in ipairs(data.templates) do
        local obj = Build(tpl.obj, "EVCoverage" .. i)
        local claim, hits = First(obj, tpl.name)
        claim = claim or RuntimeClaim(tpl.name)
        rows[#rows + 1] = { name = tpl.name, count = tpl.count, part = claim, hits = hits }
        if claim then Tally(claim, "templates", 1); Tally(claim, "sites", tpl.count) end
        -- A claimed root that stops the walk (tooltips) hides its children in
        -- game too, so they are not counted.
        local stop = false
        for _, part in ipairs(S.parts) do
            if part.name == claim and part.stop then stop = true end
        end
        if not stop then
            Descend(obj, tpl.obj, true, function(child, c)
                local cp = First(child, tpl.name .. "." .. (c.k or "?"))
                if cp then
                    Tally(cp, "inside", 1); Tally(cp, "insideSites", tpl.count)
                    insideRows[#insideRows + 1] = { tpl.name, c.k or "?", cp, tpl.count }
                end
            end)
        end
        Clear()
    end

    local frameRows, frameObjects = {}, 0
    for i, fr in ipairs(data.frames or {}) do
        local obj = Build(fr.obj, fr.name)
        local claim = First(obj, fr.name)
        frameObjects = frameObjects + 1
        if claim then Tally(claim, "frames", 1) end
        frameRows[#frameRows + 1] = { fr.name, claim }
        local stop = false
        for _, part in ipairs(S.parts) do
            if part.name == claim and part.stop then stop = true end
        end
        if not stop then
            Descend(obj, fr.obj, false, function(child, c)
                frameObjects = frameObjects + 1
                local cp = First(child, fr.name .. "." .. (c.k or "?"))
                if cp then Tally(cp, "frames", 1) end
            end)
        end
        Clear()
    end

    ----------------------------------------------------------------------------
    --  Output.
    ----------------------------------------------------------------------------
    if mode == "tsv" then
        for _, n in ipairs(order) do
            emit("part\t" .. n .. (RUNTIME[n] and ("\truntime\t" .. RUNTIME[n].why) or ""))
        end
        for _, r in ipairs(rows) do
            emit(("row\t%s\t%d\t%s\t%s"):format(r.name, r.count, r.part or "", table.concat(r.hits, ">")))
        end
        for _, r in ipairs(insideRows) do
            emit(("inside\t%s\t%s\t%s\t%d"):format(r[1], r[2], r[3], r[4]))
        end
        for _, r in ipairs(frameRows) do
            emit(("frame\t%s\t%s"):format(r[1], r[2] or ""))
        end
        for n, b in pairs(byPart) do
            emit(("objects\t%s\t%d"):format(n, b.frames))
        end
        emit("frameobjects\t" .. frameObjects)
        for _, e in ipairs(errors) do emit("error\t" .. e) end
        return #errors
    end

    local claimed, claimedSites, open, openSites = 0, 0, {}, 0
    for _, r in ipairs(rows) do
        if r.part then
            claimed = claimed + 1; claimedSites = claimedSites + r.count
        else
            open[#open + 1] = r; openSites = openSites + r.count
        end
    end
    local function ByCount(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end
    table.sort(open, ByCount)

    if mode == "all" then
        local sorted = {}
        for i, r in ipairs(rows) do sorted[i] = r end
        table.sort(sorted, ByCount)
        emit(("%-52s %5s  %s"):format("template", "sites", "part"))
        for _, r in ipairs(sorted) do
            emit(("%-52s %5d  %s"):format(r.name, r.count, r.part or "-"))
        end
        emit("")
    end

    emit(("%-16s %9s %6s %7s %6s %7s"):format("part", "templates", "sites", "inside", "sites", "objects"))
    local totals = { templates = 0, sites = 0, inside = 0, insideSites = 0, frames = 0 }
    for _, n in ipairs(order) do
        local b = byPart[n] or { templates = 0, sites = 0, inside = 0, insideSites = 0, frames = 0 }
        for k in pairs(totals) do totals[k] = totals[k] + b[k] end
        local note = ""
        if RUNTIME[n] then note = "  runtime: " .. RUNTIME[n].why
        elseif b.templates + b.inside + b.frames == 0 then note = "  MATCHES NOTHING" end
        emit(("%-16s %9d %6d %7d %6d %7d%s"):format(n, b.templates, b.sites, b.inside, b.insideSites, b.frames, note))
    end
    emit(("%-16s %9d %6d %7d %6d %7d"):format("claimed", totals.templates, totals.sites,
        totals.inside, totals.insideSites, totals.frames))
    emit(("%-16s %9d %6d %14s %7d"):format("unclaimed", #open, openSites, "", frameObjects - totals.frames))
    emit("")
    emit("templates: the template's own root. inside: frames a template declares")
    emit("within itself. sites: weighted by how many places inherit the template.")
    emit("objects: frames in Blizzard's named windows, every level.")
    emit("")
    emit("Unclaimed, most inherited first (the backlog for new parts):")
    for i = 1, math.min(#open, 40) do
        if open[i].count == 0 then break end
        emit(("  %-50s %5d"):format(open[i].name, open[i].count))
    end
    for _, e in ipairs(errors) do emit("ERROR " .. e) end
    return #errors
end

if arg and arg[1] then
    local bad = Main(arg[1], arg[3] or ".", arg[2] or "summary")
    os.exit(bad == 0 and 0 or 1)
end
return Main
