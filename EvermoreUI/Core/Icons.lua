if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Icons.lua
--  One icon style for the whole suite, the way Masque gives one to a whole
--  interface: every icon we draw or skin goes through here, so a single set
--  of settings (General > Icons) decides how all of them look.
--
--    zoom          how much of the icon's baked-in edge is cropped off each
--                  side, in percent. Blizzard's icon art carries its own
--                  bevelled frame in the outer 6-8%; 8 is the crop ElvUI and
--                  our bags have always used.
--    border        our edge round the icon, in physical pixels; 0 for none
--    borderColour  a theme token, "class", or "black"
--
--  What an icon SAYS is not the style's business. An item's quality, a
--  debuff's dispel type, a reminder's "you're missing this", a spell that
--  isn't on your bars: those colour the edge through SetState, and the style
--  only decides the edge's width and its resting colour.
--
--  The API:
--
--    EV.Icons:Style(icon, opts) -> rec
--        icon   the texture holding the icon art
--        opts.host   the frame the icon lives in (default: the icon's parent)
--        opts.fit    true when we own the layout (our own buttons): the icon
--                    is anchored inside host, `border` pixels in, and the
--                    edge is drawn on host's own rect. Otherwise the icon is
--                    left where it is and the edge hugs it from outside, on a
--                    frame of ours (the case for Blizzard's buttons, which we
--                    must not move).
--        opts.well   a token for the ground behind the icon (fit only), for
--                    an empty slot; default none
--        opts.keepCoords  leave the texture coordinates alone (atlas icons,
--                    portraits)
--    EV.Icons:SetState(icon, spec)  an edge colour that means something (any
--                    Look colour spec, or r, g, b), or nil to rest
--    EV.Icons:Frame(icon)   the edge frame, for callers that hide it
--    EV.Icons:Refresh()     re-apply everything, after a settings change
--
--  Nothing is written onto the icon or its host; our records live in a weak
--  table here, and the edge frame is ours.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T = EV.Theme
local L = EV.L
local max, floor = math.max, math.floor

local I = {}
EV.Icons = I

I.DEFAULTS = {
    zoom = 8,
    border = 1,
    borderColour = "border",
}

--- The colours the edge can rest in: shared with anything that offers the
--- same choice (the cooldown designer).
I.COLOURS = {
    { value = "border",       text = L["Theme border"] },
    { value = "borderStrong", text = L["Theme border, strong"] },
    { value = "accent",       text = L["Accent"] },
    { value = "title",        text = L["Gold"] },
    { value = "class",        text = L["Class colour"] },
    { value = "black",        text = L["Black"] },
}

function I.Settings()
    local core = EV.DB and EV.dbReady and EV.DB:GetCore()
    if not core then return I.DEFAULTS end
    if type(core.icons) ~= "table" then core.icons = {} end
    EV.DB.Merge(core.icons, I.DEFAULTS)
    return core.icons
end

--- A colour choice as r, g, b, a.
function I.ColourOf(choice)
    if choice == "class" then
        local _, class = UnitClass("player")
        local r, g, b = EV.Palette and EV.Palette.ClassRGB and EV.Palette.ClassRGB(class)
        if r then return r, g, b, 1 end
        choice = "border"
    elseif choice == "black" then
        return 0, 0, 0, 1
    end
    return T.RGBA(choice or "border")
end

local recs = setmetatable({}, { __mode = "k" })   -- icon texture -> record

local function SpecRGBA(spec)
    if type(spec) == "table" and type(spec[1]) == "number" then
        return spec[1], spec[2], spec[3], spec[4] or 1
    end
    return T.C4(T.SpecRGBA(spec))
end

local function Paint(rec)
    local s = I.Settings()
    local frame = rec.frame
    if not frame then return end
    local show = (s.border or 0) > 0
    EV.Pixel:ShowEdges(frame, show)
    if not show then return end
    if rec.state then
        EV.Pixel:SetEdgeColor(frame, SpecRGBA(rec.state))
    else
        EV.Pixel:SetEdgeColor(frame, I.ColourOf(s.borderColour))
    end
end

local function Apply(rec)
    local icon, host, opts = rec.icon, rec.host, rec.opts
    local s = I.Settings()
    local z = (s.zoom or 8) / 100
    if not opts.keepCoords and icon.SetTexCoord then
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end
    local px = max(0, floor(s.border or 1))
    local one = EV.Pixel:One(host)
    local frame = rec.frame
    if not frame then
        frame = CreateFrame("Frame", nil, host)
        frame:EnableMouse(false)
        rec.frame = frame
        if opts.well then
            rec.well = EV.Pixel:Fill(host, "BACKGROUND", -6)
        end
    end
    frame:ClearAllPoints()
    if opts.fit then
        frame:SetAllPoints(host)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", host, "TOPLEFT", px * one, -px * one)
        icon:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -px * one, px * one)
    else
        frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -px * one, px * one)
        frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", px * one, -px * one)
    end
    EV.Pixel:Edges(frame, { size = max(1, px) })
    if rec.well then rec.well:SetColorTexture(T.C4(T.SpecRGBA(opts.well))) end
    Paint(rec)
end

--- Style an icon. Safe to call again on the same icon (a pooled button being
--- reused): the record is kept and only the options change.
function I:Style(icon, opts)
    if not (icon and icon.GetParent) then return end
    opts = opts or {}
    local rec = recs[icon]
    if not rec then
        local host = opts.host
        if not host then
            local ok, p = pcall(icon.GetParent, icon)
            host = ok and p or nil
        end
        if not (host and host.CreateTexture) then return end
        rec = { icon = icon, host = host }
        recs[icon] = rec
        T.Watch(icon, function() Paint(rec) end)
    end
    rec.opts = opts
    Apply(rec)
    return rec
end

function I:SetState(icon, spec, g, b, a)
    local rec = recs[icon]
    if not rec then return end
    if type(spec) == "number" then spec = { spec, g, b, a or 1 } end
    rec.state = spec
    Paint(rec)
end

function I:Frame(icon)
    local rec = recs[icon]
    return rec and rec.frame
end

function I:IsStyled(icon) return recs[icon] ~= nil end

--- The crop, as texture coordinates, for callers that set their own.
function I:Coords()
    local z = (I.Settings().zoom or 8) / 100
    return z, 1 - z, z, 1 - z
end

local listeners = {}
--- Called after every Refresh, for icons drawn outside Style (the cooldown
--- manager draws its own and follows the suite's style unless told not to).
function I:OnChange(fn) listeners[#listeners + 1] = fn end

function I:Refresh()
    for _, rec in pairs(recs) do Apply(rec) end
    for _, fn in ipairs(listeners) do pcall(fn) end
end
