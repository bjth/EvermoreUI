if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Auras.lua
--  Your dots, with their timers, on the plate.
--
--  This file does NOT read auras. That is not a style choice, it is the
--  constraint: reading aura data in Lua throws while tainted in restricted
--  content, which we hit in this very project:
--
--      GetAuraDataByIndex(): Auras cannot be accessed when secret while
--      tainted by 'EvermoreUI_Objectives'
--
--  Restricted content is exactly where dot tracking matters, so the retail
--  approach (scan, filter in Lua, drive your own cooldown frames) is not
--  available to us at all.
--
--  Instead we use the engine aura container:
--
--      CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
--      container:AddAuraGroup(groupKey, filterString, options)
--      container:SetUnit(unitToken)
--
--  (Blizzard_AuraContainer/Blizzard_CustomAuraContainer.lua:286.) The engine
--  fetches, filters, sorts, lays out and DRIVES THE COOLDOWN SWIPES. Duration
--  and stack text are engine-provided font strings we only style. So the
--  timers cost us nothing and keep working when everything is secret.
--
--  THE RULE, and it is the most important line in this addon:
--  every predicate goes in the FILTER STRING, which the engine evaluates in
--  C. Never compare an aura field in Lua.
--
--  The corollary is subtle. Under secrecy a Lua compare against an
--  unreadable value fails in a direction: `x ~= true` is TRUE for every
--  unreadable aura, so a filter written that way shows everything or
--  nothing depending on polarity. Blizzard's own nameplate rule survives
--  secrecy only because it tests `== false`, which KEEPS unknowns rather
--  than dropping them. A filter that drops unknowns fails closed; one that
--  keeps them fails open. We use filter strings and sidestep the question.
--
--  A filter string ANDs its tokens and is fixed when the group is declared,
--  so configuration is expressed as SEVERAL PARALLEL ROWS.
--------------------------------------------------------------------------------
--  LAYOUT: why one container per row and not one container with three groups.
--
--  A CustomAuraContainer owns exactly ONE flow layout. Every enabled group
--  becomes a flow GROUP inside that single layout and the groups run one
--  after another along the same axis, with only groupSpacing and
--  forceNewLine to separate them (Blizzard_CustomAuraContainer.lua:675-754,
--  AnchorUtil.ApplyFlowLayout). There is no per-group anchor point and no
--  per-group growth direction.
--
--  The design puts the three rows in three different places
--  around the plate, growing in two different directions. That is not
--  expressible in one flow layout, so each row gets its own container in its
--  own holder, anchored independently. It costs nothing extra in frames:
--  AddAuraGroup pre-allocates one batch of ten per GROUP either way
--  (CustomAuraContainerConstants.FrameCreationBatchSize), so three groups in
--  one container and three containers of one group are the same thirty
--  buttons. A row switched off builds no container at all.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local floor, max = math.floor, math.max

--- Can this client make one? Asking for the MIXIN does not work: only the
--- XML of Blizzard_AuraContainer is loaded into the global environment, so
--- the templates are instantiable but the mixin tables are not visible from
--- addon code. Probe by building one, which is what EvermoreUI_Auras already
--- does (Container.lua:30-43). Load-on-demand: the addon may not be up yet.
local supported
local function Supported()
    if supported ~= nil then return supported end
    local ok = C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
    if not ok then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        ok = C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
    end
    local test
    if ok then ok, test = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate") end
    supported = (ok and test ~= nil and test.AddAuraGroup ~= nil) and true or false
    if test and test.Hide then test:Hide() end
    if EV.Caps then EV.Caps.auraContainer = supported end
    return supported
end

--- Call an engine method, and SAY SO when it does not work. The first cut of
--- this file used a bare pcall here, which meant that if, say,
--- SetFlowLayoutGrowthDirection ever asserted, the buff row would quietly
--- keep the engine default (Right/Down) against a BOTTOMRIGHT anchor and
--- march its icons across the health bar, with the diagnostic cheerfully
--- reporting the row as attached and healthy. Every failure in this file is
--- of that shape: nothing errors, nothing is missing, it just looks wrong.
--- So each method reports once, through ns.Safe, and then goes quiet.
--- Site names are memoised rather than concatenated per call: Try is on the
--- plate spawn path and a string built per engine call is garbage for nothing.
local site = setmetatable({}, { __index = function(t, k)
    local v = { call = "aura-call:" .. k, missing = "aura-missing:" .. k }
    rawset(t, k, v)
    return v
end })

local function Try(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then
        ns.Safe(site[method].missing, error, "no such method on the aura container", 0)
        return false
    end
    return ns.Safe(site[method].call, fn, obj, ...)
end

--- The one call that is ALLOWED to fail: parking a container on a dead unit.
--- Not every build accepts the "none" token and the nil fallback is the point,
--- so a report here would be noise.
local function TryQuiet(obj, method, ...)
    local fn = obj and obj[method]
    if type(fn) ~= "function" then return false end
    return (pcall(fn, obj, ...))
end

--------------------------------------------------------------------------------
--  The rows
--
--  The arrangement: the debuff row is pinned to the BAR's left edge, above
--  it; crowd control sits OUTSIDE the bar entirely, clear to the right; buffs
--  mirror that on the left.
--
--  The flanking gap is our own. A gap measured as "the distance from the bar
--  to the edge of Blizzard's plate" leaves a visible hole on our 140-wide
--  bar, because Camelot's plate is a different size again.
--------------------------------------------------------------------------------
--  Measured off the reference screenshots, scaled to our 140-wide bar.
--  The debuff icons very nearly touch the bar: four pixels of clear space on
--  a 337px-wide plate, which is two of ours. They should not float.
--
--  The flanking gap is about five per cent of the bar width.
local GAP = 2                 -- between icons in a row
local FLANK = 7               -- between the bar and the side rows
local LIFT = 2                -- between the bar top and the debuff row

--- Icon geometry for a row, from the settings. Rectangular for the debuff
--- row (height 0.75 against a scale of 0.9), square for the
--- flanking rows (height 1).
local function IconSize(row, cfg)
    local w = max(floor(cfg.auraSize * row.scale + 0.5), 8)
    local h = row.wide and max(floor(w * (cfg.auraRatio or 0.75) + 0.5), 6) or w
    return w, h
end

local ROWS = {
    {
        -- The headline. HARMFUL plus the PLAYER token is what makes it "my
        -- dots", and it lives in the filter STRING so it survives secrecy.
        -- INCLUDE_NAME_PLATE_ONLY is Blizzard's own nameplate relevance flag.
        key     = "mine",
        filter  = "HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY",
        setting = "showAuras",
        count   = 6,
        scale   = 0.9,
        wide    = false,        -- square: the reference icons measure 37x40
        grow    = "RIGHT",
        sort    = "Expiration",
        -- Above the bar, left aligned with it, growing right and wrapping up.
        Place = function(h, f, cfg)
            h:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", 0, LIFT)
        end,
        -- Short of the full width when the quest count is on: that sits at
        -- the top right on this same line, and six dots at full width would
        -- run straight under it.
        Wrap = function(cfg, w) return cfg.width - (cfg.showQuest and 26 or 0) end,
    },
    {
        key     = "cc",
        filter  = "HARMFUL|CROWD_CONTROL",
        setting = "showCC",
        count   = 2,
        scale   = 1,
        wide    = false,
        grow    = "RIGHT",
        sort    = "Expiration",
        -- Off the right edge, vertically centred on the bar.
        Place = function(h, f, cfg, w, ih)
            h:SetPoint("BOTTOMLEFT", f.health, "RIGHT", FLANK, -ih / 2)
        end,
    },
    {
        key     = "buff",
        filter  = "HELPFUL|INCLUDE_NAME_PLATE_ONLY",
        -- INCLUDE_NAME_PLATE_ONLY does not mean "only nameplate-relevant
        -- auras". It WIDENS the set: "auras that are flagged as being
        -- nameplate-only will be included. When not set, nameplate-only auras
        -- will be filtered out" (AuraUtil.lua:279). On HARMFUL|PLAYER that is
        -- what we want, because PLAYER carries the restriction. On a bare
        -- HELPFUL it is every buff the mob has, and three slots sorted by
        -- expiry would fill with whatever happens to be ticking.
        --
        -- Blizzard narrow the same row in Lua, and their comment is the spec:
        -- "Avoid filling up the list of enemy unit buffs with information not
        -- relevant to the player" -- isStealable or IsSpellImportant
        -- (Blizzard_NamePlateAuras.lua:191-197). We cannot run that test in
        -- Lua here, but isStealable is one of the engine's own candidate
        -- filters (Blizzard_CustomAuraContainer.lua:123-134), evaluated in C
        -- like the filter string. Importance has no candidate filter, so this
        -- row is the purge list rather than Blizzard's union of the two.
        candidates = { isStealable = true },
        setting = "showBuffs",
        count   = 3,
        scale   = 0.85,
        wide    = false,
        grow    = "LEFT",
        sort    = "Expiration",
        Place = function(h, f, cfg, w, ih)
            -- The raid target marker lives off the left edge too, and it is
            -- only shown on marked units. Reserve its width unconditionally:
            -- a row that shifts sideways the moment somebody drops a skull on
            -- the mob is worse than a small gap when nobody has.
            h:SetPoint("BOTTOMRIGHT", f.health, "LEFT", -(FLANK + cfg.height + 6), -ih / 2)
        end,
    },
}

--------------------------------------------------------------------------------
--  The aura button
--
--  CustomAuraButtonTemplate carries NO ART. It is a bare host: you create the
--  icon, the cooldown and the text yourself in initializeFrame and then
--  REGISTER them with the button (SetIcon / SetDurationCooldown /
--  SetApplicationCount / SetDurationText). An initializer that only calls
--  SetSize leaves every button an invisible empty frame, which is consistent
--  with every symptom of "no icons": groups added, container enabled, right
--  unit, correct filters, nothing on screen.
--
--  ORDER MATTERS. Every Set* registration makes the engine run its aura
--  display update on the spot, and that update writes text into the font
--  strings it was handed. A font string with no font yet is a hard error
--  inside the engine. So build every region, style it, and register last.
--
--  So fonts go on BEFORE SetApplicationCount and SetDurationText, and the
--  pandemic texture is hidden BEFORE AddPandemicRegion, because registration
--  hands its Shown state to the engine as a secret aspect and we must not be
--  the ones touching it afterwards.
--
--  And clicks come off. Engine aura buttons are click-enabled by default, and
--  on a nameplate an icon that takes clicks sits between the cursor and the
--  plate's own click region, swallowing target switches, which is at its
--  worst in dense M+ pulls. initializeFrame is the only reliable place to
--  turn them off, because post-creation writes on the button are denied once
--  auras are secret -- which is combat, which is when it matters.
--------------------------------------------------------------------------------

--- Pandemic, for free. AddPandemicRegion hands a region's visibility to the
--- engine, which shows it inside the refresh window (Blizzard_CustomAuraButton
--- .lua:256-265). We cannot compute that ourselves at all: duration and expiry
--- are secret and arithmetic on them throws. This is the only way to show the
--- pandemic window on this client.
--- The engine's default duration formatter writes "16s". We want "16", so
--- we build our own numeric rule formatter: tenths below three seconds,
--- whole seconds up to a minute, minutes above that. No unit suffix at any point, because on a seventeen
--- pixel icon the "s" costs a digit and tells you nothing.
local durationFormatter
local function DurationFormatter()
    if durationFormatter ~= nil then return durationFormatter or nil end
    if type(C_StringUtil) ~= "table" or type(C_StringUtil.CreateNumericRuleFormatter) ~= "function" then
        durationFormatter = false
        return nil
    end
    local okF, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
    if not okF or not f then durationFormatter = false; return nil end
    local okB = pcall(f.SetBreakpoints, f, {
        { threshold = 0,  step = 0.1, format = "%.1f" },
        { threshold = 3,  step = 1,   format = "%d" },
        { threshold = 60, format = COOLDOWN_DURATION_MIN or "%dm",
          components = { { div = 60, step = 1 } } },
    })
    durationFormatter = okB and f or false
    return durationFormatter or nil
end

--- The coloured border. In the reference each debuff icon is ringed in its
--- dispel colour -- white-grey for something with no dispel type, red for the
--- one next to it -- and that is not something we could ever compute, because
--- the dispel type is secret like everything else about an aura.
---
--- AddDispelTypeTexture hands the whole question to the engine: it picks the
--- colour from the aura's dispel type C-side and applies it to a texture we
--- supply. PreserveAsset keeps our own flat white asset and only tints it,
--- which is what makes it a border rather than Blizzard's ring art, and
--- showAlways keeps it visible for auras that have no dispel type at all
--- (they take the "None" colour below) instead of blinking off.
local DISPEL_NONE = { r = 0.35, g = 0.35, b = 0.35 }

local function AddDispelBorder(b, edge)
    if type(b.AddDispelTypeTexture) ~= "function" then return false end
    local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    return (pcall(b.AddDispelTypeTexture, b, edge, {
        style = style and style.PreserveAsset or 3,
        showAlways = true,
        showWhenHarmful = true,
        showWhenHelpful = true,
        showWithoutDispelType = true,
        customDispelColorMap = { None = DISPEL_NONE },
    }))
end

local function AddPandemic(b, one)
    if type(b.AddPandemicRegion) ~= "function" then return end
    -- A STRIP along the bottom of the icon, not a ring around it. The ring
    -- version read as a permanent gold border and fought the dispel colour
    -- for the same two pixels; at this size there is only room for one thing
    -- to be a border, and that is the dispel type. ApplyPandemicDisplay only
    -- SetShown()s the region (Blizzard_CustomAuraButton.lua:760), so the strip
    -- appears exactly in the refresh window and is invisible the rest of the
    -- time.
    local strip = b:CreateTexture(nil, "OVERLAY", nil, 3)
    strip:SetColorTexture(1, 0.82, 0.1, 1)
    strip:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", one, one)
    strip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -one, one)
    strip:SetHeight(one * 2)
    strip:Hide()
    pcall(b.AddPandemicRegion, b, strip)
end

local function InitButton(b, w, h, fontSize)
    pcall(b.SetSize, b, w, h)

    -- ONE PHYSICAL PIXEL, not one layout unit. Every inset below used to be a
    -- literal 1, which is a unit of the virtual 768-tall screen: at 1440p that
    -- is nearly two physical pixels, and at 4K nearly three. The icon borders
    -- were the wrong thickness on every display but 1080p, and inconsistent
    -- with the plate's own border right beside them.
    --
    -- Measured against UIParent, deliberately, and not against the button.
    -- At this moment the button's parent chain runs holder -> UIParent,
    -- because BuildHolder parents the holder there and AddAuraGroup creates
    -- the whole batch before anything is attached to a plate. Asking the
    -- button gives the same answer today and stops being the same answer the
    -- moment the holder is reparented into a scaled plate. initializeFrame
    -- runs once per button ever, so there is no correcting it later: the
    -- honest thing is to name the space the number is in.
    local one = EV.Pixel:One(UIParent)

    -- Input off first, while we still certainly have write access. Clicks
    -- AND motion: AuraButtonPrivateMixin has OnEnter_Intrinsic /
    -- OnLeave_Intrinsic that show and hide the aura tooltip
    -- (Blizzard_AuraButton.lua:80-88), so a dot icon left mouse-aware pops a
    -- tooltip that then chases the mob around the screen.
    pcall(b.SetMouseClickEnabled, b, false)
    pcall(b.SetMouseMotionEnabled, b, false)

    -- The frame behind the icon, which the icon is inset into. One texture
    -- instead of four hairlines: at this size four pixel-snapped strips per
    -- icon is a lot of geometry for a border nobody measures. Flat white so
    -- the engine can tint it to the dispel colour; if it will not take it we
    -- fall back to black and it is simply a black border.
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(b)
    edge:SetColorTexture(1, 1, 1, 1)
    edge:SetVertexColor(DISPEL_NONE.r, DISPEL_NONE.g, DISPEL_NONE.b, 1)


    local icon = b:CreateTexture(nil, "ARTWORK")
    -- Snapping off at creation, here rather than only in the layout walk: the
    -- engine creates these buttons in batches of ten at container build time
    -- and the walk runs on layout, so a button minted afterwards would keep
    -- the renderer's per region rounding and crawl against the row beside it.
    -- ns.SnapOff covers the font strings on the carrier below as well.
    ns.SnapOff(edge)
    ns.SnapOff(icon)
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", one, -one)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -one, one)
    -- A wide icon has to be cropped harder on the vertical to stay square in
    -- appearance, otherwise the art squashes. Trim to the ratio we are drawing.
    local inset = 0.08
    local dw, dh = max(w - 2, 1), max(h - 2, 1)
    local vInset = (dh < dw) and (0.5 - (0.5 - inset) * (dh / dw)) or inset
    icon:SetTexCoord(inset, 1 - inset, vInset, 1 - vInset)

    -- CooldownFrameTemplate supplies the swipe art; a bare Cooldown draws no
    -- swipe at all, which would cost us the dot timer this module exists for.
    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", b, "TOPLEFT", one, -one)
    cd:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -one, one)
    cd:SetHideCountdownNumbers(true)
    cd:SetDrawEdge(false)
    cd:SetSwipeColor(0, 0, 0, 0.6)
    cd:SetReverse(true)

    -- Text rides its own carrier above the swipe so the cooldown cannot
    -- cover it. Mouse off for the same reason as the button.
    local carrier = CreateFrame("Frame", nil, b)
    carrier:SetAllPoints(b)
    carrier:SetFrameLevel(cd:GetFrameLevel() + 1)
    carrier:EnableMouse(false)

    -- A FontString with no font assigned hard-errors inside the engine the
    -- moment UpdateAuraDisplay SetText()s it, and Media:Fetch can legitimately
    -- return nil if LibSharedMedia has not registered yet. Never hand the
    -- engine a nil font.
    local stack = carrier:CreateFontString(nil, "OVERLAY")
    ns.SetText(stack, max(fontSize - 2, 7), true)
    stack:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", one, -one)
    stack:SetTextColor(1, 1, 1, 1)

    -- Centred on the icon, not below it. Below would put the number between
    -- the row and the health bar, which is the one place on this layout with
    -- no room at all.
    local dur = carrier:CreateFontString(nil, "OVERLAY")
    ns.SetText(dur, fontSize, true)
    dur:SetPoint("CENTER", b, "CENTER", 0, 0)
    dur:SetTextColor(1, 1, 1, 1)
    ns.SnapOff(stack)
    ns.SnapOff(dur)

    if not AddDispelBorder(b, edge) then
        edge:SetVertexColor(0, 0, 0, 1)
    end
    AddPandemic(b, one)

    -- Registration last, and only now that the fonts are set. Reported, not
    -- swallowed: a failure here is an icon that renders as an empty box, and
    -- every other signal -- group added, container enabled, right unit --
    -- still says the row is fine.
    Try(b, "SetIcon", icon)
    Try(b, "SetDurationCooldown", cd)
    Try(b, "SetApplicationCount", stack, {})
    Try(b, "SetDurationText", dur, { textFormatter = DurationFormatter() })
end

--------------------------------------------------------------------------------
--  Holders
--
--  THE THING THAT MATTERS: a container is never created inside a nameplate.
--
--  A nameplate is a restricted, aspect-bearing subtree. Engine aura buttons
--  created in there do not render, and aspects cannot be conferred after
--  creation, so building the container with the plate as its parent gives
--  you a container that reports success and shows nothing.
--
--  So each container lives inside a HOLDER frame built under a neutral
--  parent, and attaching to a plate reparents the HOLDER, never the
--  container.
--
--  Detaching parks the container on a dead unit rather than tearing it down:
--  SetUnit("none"), falling back to SetUnit(nil) because not every build
--  accepts the string (TryQuiet, above).
--------------------------------------------------------------------------------
--  POOLING, and why it is keyed on the icon size rather than on a settings
--  generation.
--
--  The obvious scheme -- stamp each holder with ns.styleGen and throw away
--  anything older -- leaks, permanently. AddAuraGroup calls
--  frameProvider:CreateFrameBatch() up front and the batch size is a flat 10
--  regardless of maxFrameCount (CustomAuraContainerConstants
--  .FrameCreationBatchSize), so every holder owns ten aura buttons, each with
--  three textures, a Cooldown, a carrier frame and two font strings. WoW
--  frames cannot be destroyed. Restyle() bumps ns.styleGen and runs on every
--  options change, so one drag of the icon-size slider across twenty plates
--  would strand sixty containers and six hundred buttons, and the next drag
--  would do it again.
--
--  What actually cannot be changed after the fact is narrower than that. The
--  filter string is a constant per row. maxFrameCount, the group's layout and
--  the flow's line size all have setters. The ONE immutable is the pixel size
--  the buttons were built at, because that is baked in initializeFrame and
--  initializeFrame runs once per button, ever.
--
--  So the pool is keyed on exactly that, and everything else is re-applied on
--  the way out. Holders are then reused across every settings change that
--  does not resize the icons, and a user who goes 20 -> 24 -> 20 gets the
--  original holders back rather than a third set.
local free = {}
local function PoolKey(row, w, h) return ("%s|%d|%d"):format(row.key, w, h) end

ns.auraDiag = { built = 0, attached = 0, groups = {}, failures = {} }

--- Where the flow layout starts, and which way it runs. Elements anchor to
--- the CONTAINER's anchor point with computed offsets, and the container
--- resizes itself as the row fills (FlowLayoutMixin:OnLayoutComplete), so the
--- container must be pinned by the same corner the flow starts from or the
--- whole row slides about as auras come and go.
---
--- The numeric fallbacks are not decoration. AnchorUtil.FlowDirection is
--- { Left = -1, Right = 1, Up = 1, Down = -1 } (AnchorUtil.lua:471), so the
--- lazy `FD and FD[dir] or 1` substitutes RIGHT for LEFT and sends the buff
--- row the wrong way -- a bug introduced by the defensive path itself.
local FLOW = {
    RIGHT = { point = "BOTTOMLEFT",  h = "Right", v = "Up", hFallback =  1, vFallback = 1 },
    LEFT  = { point = "BOTTOMRIGHT", h = "Left",  v = "Up", hFallback = -1, vFallback = 1 },
}

local function BuildHolder(row, cfg, w, h)
    local holder = CreateFrame("Frame", nil, UIParent)
    holder:SetSize(1, 1)
    holder:Hide()

    local ok, c = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end

    local flow = FLOW[row.grow] or FLOW.RIGHT
    c:SetPoint(flow.point, holder, flow.point, 0, 0)
    c:SetSize(1, 1)

    local FD = AnchorUtil and AnchorUtil.FlowDirection
    Try(c, "SetFlowLayoutAnchorPoint", flow.point)
    Try(c, "SetFlowLayoutGrowthDirection",
        (FD and FD[flow.h]) or flow.hFallback,
        (FD and FD[flow.v]) or flow.vFallback)
    Try(c, "SetFlowLayoutPadding", 0, 0, 0, 0)
    if AnchorUtil and AnchorUtil.FlowLayoutAxis then
        Try(c, "SetFlowLayoutAxis", AnchorUtil.FlowLayoutAxis.Horizontal)
    end
    local SM, SD = AuraContainerSortMethod, AuraContainerSortDirection
    local fontSize = max(floor(h * 0.62 + 0.5), 8)
    local okG, err = pcall(c.AddAuraGroup, c, row.key, row.filter, {
        maxFrameCount = row.count,
        sortMethod = (SM and SM[row.sort]) or 0,
        sortDirection = SD and SD.Normal or 0,
        candidateFilters = row.candidates,
        -- Through ns.Safe, not a bare call. The provider invokes this with
        -- securecallfunction (Blizzard_AuraContainerFrameProviders.lua:79),
        -- which routes a throw to the error handler instead of back to us, so
        -- AddAuraGroup would still return success with ten half-built buttons
        -- behind it and the diagnostic would call the row healthy.
        initializeFrame = function(b) ns.Safe("aura-init", InitButton, b, w, h, fontSize) end,
        layout = {
            elementWidth = w, elementHeight = h,
            elementSpacing = GAP, lineSpacing = GAP,
        },
    })
    if not okG then
        ns.auraDiag.failures[row.key] = tostring(err)
        geterrorhandler()(("EvermoreUI Nameplates: aura group '%s' rejected: %s")
            :format(row.key, tostring(err)))
        holder:Hide()
        return nil
    end
    -- A row that failed once and now builds is not a failing row any more.
    ns.auraDiag.failures[row.key] = nil
    ns.auraDiag.groups[row.key] = (ns.auraDiag.groups[row.key] or 0) + 1

    holder.container = c
    holder.poolKey = PoolKey(row, w, h)
    holder.iconW, holder.iconH = w, h
    holder.count = row.count          -- AddAuraGroup has already set this one
    ns.auraDiag.built = ns.auraDiag.built + 1
    return holder
end

--- Everything a reused holder has to be told again, because these are the
--- settings that CAN change under a holder we are handing back out.
local function Refresh(h, row, cfg, w)
    local c = h.container
    local wrap = row.Wrap and row.Wrap(cfg, w) or nil
    if h.wrap ~= wrap then
        h.wrap = wrap
        -- Only the row above the bar wraps; the flanking rows are single line
        -- and would look broken stacked.
        Try(c, "SetFlowLayoutMaximumLineSize", wrap)
    end
    if h.count ~= row.count then
        h.count = row.count
        Try(c, "SetAuraGroupMaxFrameCount", row.key, row.count)
    end
end

local function Acquire(row, cfg, w, h)
    local key = PoolKey(row, w, h)
    local pool = free[key]
    if pool and #pool > 0 then
        local holder = table.remove(pool)
        Refresh(holder, row, cfg, w)
        return holder
    end
    local holder = BuildHolder(row, cfg, w, h)
    if holder then Refresh(holder, row, cfg, w) end
    return holder
end

local function Park(h)
    local c = h.container
    if c then
        Try(c, "SetEnabled", false)
        -- The one call allowed to fail quietly: see TryQuiet.
        if not TryQuiet(c, "SetUnit", "none") then TryQuiet(c, "SetUnit", nil) end
    end
    h:ClearAllPoints()
    h:SetParent(UIParent)
    h:Hide()
    if c and h.poolKey then
        local pool = free[h.poolKey]
        if not pool then pool = {}; free[h.poolKey] = pool end
        pool[#pool + 1] = h
    end
end

local function Detach(f)
    local rows = f.auraRows
    if not rows then return end
    for key, h in pairs(rows) do
        rows[key] = nil
        Park(h)
    end
end

--- Attach every enabled row to the plate and park the rest. Split out of
--- Late because Restyle() does NOT call Late: it runs Layout and SetUnit, so
--- a settings change would otherwise retire every row and leave the plates on
--- screen bare until each one respawned.
local function Attach(f)
    local cfg = ns.module.db
    if not (f.unit and Supported()) then return end

    local rows = f.auraRows
    for _, row in ipairs(ROWS) do
        if cfg[row.setting] then
            rows = rows or {}
            local w, ih = IconSize(row, cfg)
            local h = rows[row.key]
            -- A holder built at a different icon size cannot be resized: the
            -- buttons were sized in initializeFrame, which runs once per
            -- button ever. Park it (its pool keeps it for if the user goes
            -- back) and take one of the right size.
            if h and (h.iconW ~= w or h.iconH ~= ih) then
                rows[row.key] = nil
                Park(h)
                h = nil
            end
            if not h then
                h = Acquire(row, cfg, w, ih)
                if h then rows[row.key] = h end
            else
                Refresh(h, row, cfg, w)
            end
            if h then
                -- Reparent the HOLDER. Never the container.
                h:SetParent(f)
                h:ClearAllPoints()
                row.Place(h, f, cfg, h.iconW, h.iconH)
                h:Show()
                -- Rounded HERE, not by Layout. Layout's pass runs before this
                -- one: the holders are created in Attach, which arrives from
                -- Late a frame later, so the aura rows were the only subtree
                -- on the plate that never got native pixel rounding -- and
                -- they hang off its edges, where it shows most.
                ns.RoundLayout(h)

                local c = h.container
                Try(c, "SetUnit", f.unit)
                Try(c, "SetEnabled", true)
                Try(c, "UpdateAllAuras")
                ns.auraDiag.attached = ns.auraDiag.attached + 1
            end
        elseif rows and rows[row.key] then
            local h = rows[row.key]
            rows[row.key] = nil
            Park(h)
        end
    end
    f.auraRows = rows
end

ns.Widget{
    name = "auras",

    -- Nothing at Build: the container's parent must not be the plate at
    -- creation time, so there is nothing to make until we know the unit.
    -- A plate already on screen is being restyled, and Late will not come
    -- round again for it, so the re-attach has to happen here. A plate
    -- mid-spawn is not in ns.active yet (Core.lua sets it after Layout runs),
    -- and that one waits for Late so the container build stays off the spawn
    -- tick, which is most of the cost of a pack pull. Attach itself decides
    -- what to keep, resize or park.
    Layout = function(f, cfg)
        if ns.active[f] then Attach(f) end
    end,

    -- No Events: each container registers UNIT_AURA itself and refreshes
    -- itself, which is the whole reason for using one.
    Late = Attach,

    Clear = function(f) Detach(f) end,

    Enable = function(M)
        if not Supported() then
            EV:Print(EV.L["Nameplates: this client has no aura containers, so tracked dots are off."])
            return
        end
    end,
}

--------------------------------------------------------------------------------
--  Counting buttons without reading them
--
--  An engine aura button's IsShown() is a SECRET BOOLEAN. Boolean-testing one
--  throws, and it is also why every "shown=0" in the reports before this was
--  meaningless: a pooled button that was never filled returns a plain false,
--  and a button carrying an actual aura returns a secret. So a SECRET result
--  is the positive one. Count the three states apart and never branch on the
--  value itself.
--------------------------------------------------------------------------------
local function CountStates(c, key, owned)
    local plainOff, plainOn, secret = 0, 0, 0
    for i = 1, owned do
        local okF, b = pcall(c.GetAuraGroupFrame, c, key, i)
        if okF and type(b) == "table" then
            local okS, vis = pcall(b.IsShown, b)
            if okS then
                if EV.IsSecret(vis) then secret = secret + 1
                elseif vis == true then plainOn = plainOn + 1
                else plainOff = plainOff + 1 end
            end
        end
    end
    return plainOn, secret, plainOff
end

--------------------------------------------------------------------------------
--  Diagnostic
--
--  "I can't see my dot" is not something anyone should have to debug from a
--  screenshot. This turns it into facts in one line.
--------------------------------------------------------------------------------
function ns.AuraReport()
    local d = ns.auraDiag
    EV:Print(("Nameplates auras: supported=%s built=%d attaches=%d")
        :format(tostring(Supported()), d.built, d.attached))
    for _, row in ipairs(ROWS) do
        local err = d.failures[row.key]
        EV:Print(("  row %-5s built=%d%s"):format(row.key, d.groups[row.key] or 0,
            err and ("  REJECTED: " .. err) or ""))
    end

    local unit
    for u in pairs(ns.plates) do
        local isT, secret = ns.IsUnit(u, "target")
        if not secret and isT then unit = u break end
    end
    if not unit then EV:Print("  no plate for your target"); return end
    local f = ns.plates[unit]
    local rows = f and f.auraRows
    if not rows then EV:Print("  target plate has no rows attached"); return end

    -- GetAuraGroupFrameCount reports OWNED frames (the pool the provider
    -- pre-created), not visible ones (Blizzard_CustomAuraContainer.lua:348),
    -- so it says nothing about whether anything matched. Count the states.
    --
    -- Every read here is protected, the state counting included: an aura
    -- button's IsShown() is secret, EV.IsSecret is the only safe thing to do
    -- with it, and a diagnostic that throws is worse than no diagnostic
    -- because it looks like an answer.
    for _, row in ipairs(ROWS) do
        local h = rows[row.key]
        if not h then
            EV:Print(("  row %-5s not attached"):format(row.key))
        else
            local c = h.container
            local okC, owned = pcall(c.GetAuraGroupFrameCount, c, row.key)
            owned = okC and owned or 0
            local okS, on, secret, off = pcall(CountStates, c, row.key, owned)
            if not okS then
                EV:Print(("  row %-5s icon=%.0fx%.0f owned=%d  count failed: %s")
                    :format(row.key, h.iconW or 0, h.iconH or 0, owned, tostring(on)))
            else
                EV:Print(("  row %-5s icon=%.0fx%.0f owned=%d visible=%d secret=%d empty=%d")
                    :format(row.key, h.iconW or 0, h.iconH or 0, owned, on, secret, off))
            end
        end
    end
    EV:Print("  secret > 0 means real auras are behind those buttons.")
end
