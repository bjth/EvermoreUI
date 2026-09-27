if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Install.lua
--  First-run setup: a short walk through the choices that change what the
--  interface looks like on day one, one step at a time, each of them the
--  same setting the options pages hold. Nothing is applied behind your back:
--  a step shows the current value, and changing it changes the setting there
--  and then, exactly as the options page would. The one step that moves
--  frames (Layout) waits for a button, and can be undone.
--
--  Core decides when to open it (EvermoreUI/Core/Install.lua). Where you are
--  is kept in the account-wide install state, so a reload part way through
--  comes back to the same step.
--
--  Steps, in order:
--    welcome     what EvermoreUI is, set up now or keep the defaults
--    characters  one setup for every character or one of its own; import
--    look        contrast, font, scale
--    modules     which parts of the interface are ours
--    layout      a starting layout for your role (tank, healer, damage)
--    everyday    vendor, loot, quest and training conveniences
--    done        what happens next, and where feedback goes
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local W = EV.UI

local I = {}
EV.Installer = I

local WIDTH, HEIGHT = 840, 600
local RAIL_W = 210
local FOOT_H = 58
local HEAD_H = 78
local DISCORD = "https://discord.evermoreui.com"

local window, rail, head, scroll, footer
local railButtons = {}
local pages = {}          -- step key -> { frame, builder }
local current = 1
local reloadNeeded = false

local function State() return EV.InstallState() end

local function Module(name)
    local m = EV:GetModule(name, true)
    return m and m.db and m or nil
end

local function ModuleWanted(name)
    return not EV.DB:GetCore().disabled[name]
end

local function NeedReload()
    reloadNeeded = true
    if I.PaintFooter then I.PaintFooter() end
end

--------------------------------------------------------------------------------
--  Layouts for a role
--
--  Offsets and anchors in edit mode's own terms (EV.Movers), so the result
--  is an ordinary layout you carry on adjusting in /evui edit. A layout
--  resets the frames it names first, then places them; anything it doesn't
--  name stays where you put it.
--------------------------------------------------------------------------------
local LAYOUT_KEYS = {
    "GF_party", "GF_raid", "UF_player", "UF_target",
    "CD_essential", "CD_utility", "CD_buffs",
}

--- The highest action bar in use, for anything that sits on top of the bars.
local function TopActionBar()
    local MV = EV.Movers
    for _, key in ipairs({ "AB_bar3", "AB_bar2", "AB_main" }) do
        local e = MV:Get(key)
        if e and not (e.isDisabled and e.isDisabled()) and e.frame:IsShown() then return key end
    end
end

local function Glue(key, target, side, align, x, y)
    local MV = EV.Movers
    if not (MV:Get(key) and MV:Get(target)) then return false end
    if not MV:SetAnchor(key, target, side, align) then return false end
    local a = MV:GetAnchor(key)
    if a then a.x, a.y = x or 0, y or 0 end
    MV:Apply(key)
    return true
end

local LAYOUTS = {
    damage = {
        text = L["Damage"],
        icon = "roleicon-tiny-dps",
        blurb = L["Your unit frames either side of the middle of the screen, cooldowns under your character, and party and raid frames on the left, out of the way."],
        tankMode = "auto",
    },
    tank = {
        text = L["Tank"],
        icon = "roleicon-tiny-tank",
        blurb = L["The damage layout, with nameplates always in tank colours: green while you hold a mob, and loud the moment something turns away from you."],
        tankMode = "tank",
    },
    healer = {
        text = L["Healer"],
        icon = "roleicon-tiny-healer",
        blurb = L["Party and raid frames in the middle, sitting on your action bars, with your cooldowns stacked above them and your unit frames either side, so everything you watch is in one place."],
        tankMode = "auto",
        place = function()
            local bars = TopActionBar()
            for _, kind in ipairs({ "GF_raid", "GF_party" }) do
                if not (bars and Glue(kind, bars, "TOP", "CENTER", 0, 14)) then
                    EV.Movers:SetOffset(kind, 0, -150)
                end
            end
            -- Cooldowns stacked above the raid frames: essential, then utility, then buffs.
            Glue("CD_essential", "GF_raid", "TOP", "CENTER", 0, 10)
            Glue("CD_utility", "CD_essential", "TOP", "CENTER", 0, 4)
            Glue("CD_buffs", "CD_utility", "TOP", "CENTER", 0, 4)
            Glue("UF_player", "GF_raid", "LEFT", "END", -18, 0)
            Glue("UF_target", "GF_raid", "RIGHT", "END", 18, 0)
        end,
    },
}
local LAYOUT_ORDER = { "damage", "tank", "healer" }

local undo   -- edit mode snapshot from before the last layout was applied

local function ApplyLayout(role)
    local def = LAYOUTS[role]
    if not def or InCombatLockdown() then return end
    local MV = EV.Movers
    local np = Module("Nameplates")
    undo = { snap = MV:Snapshot(), role = State().role, tankMode = np and np.db.tankMode }
    for _, key in ipairs(LAYOUT_KEYS) do
        if MV:Get(key) then MV:Reset(key) end
    end
    if def.place then def.place() end
    if np then
        np.db.tankMode = def.tankMode
        if np:IsEnabled() and np.Refresh then np:Refresh() end
    end
    State().role = role
end

local function UndoLayout()
    if not undo or InCombatLockdown() then return end
    EV.Movers:Restore(undo.snap)
    State().role = undo.role
    local np = Module("Nameplates")
    if np and undo.tankMode then
        np.db.tankMode = undo.tankMode
        if np:IsEnabled() and np.Refresh then np:Refresh() end
    end
    undo = nil
end

--------------------------------------------------------------------------------
--  Steps
--------------------------------------------------------------------------------
local STEPS = {}

STEPS[#STEPS + 1] = { key = "welcome", title = L["Welcome"],
    heading = L["Welcome to EvermoreUI"],
    sub = L["A complete interface for World of Warcraft: Forever. A few quick choices and you're ready to play."],
    build = function(p)
        if State().returning then
            p:Banner(L["You've used EvermoreUI before, so your settings are all still here. Every step shows what you have now, and nothing changes unless you change it."])
        end
        p:Note(L["EvermoreUI replaces most of the game's interface: unit frames, nameplates, action bars, cooldowns, bags, chat, the minimap and more, drawn in one style and set up for how Forever plays."])
        p:Note(L["This takes about a minute. Every choice here is also in the options (/evui), and you can run this again any time with /evui install."])
        p:Section(L["Not now?"])
        p:Row{ type = "button", text = L["Keep the defaults and start playing"], label = L["Skip setup"], width = 150,
               tooltip = L["Everything stays as it is. Setup won't open by itself again."],
               onClick = function() I.Finish(true) end }
    end }

STEPS[#STEPS + 1] = { key = "characters", title = L["Characters"],
    heading = L["Your characters"],
    sub = L["Whether this character shares its setup with your others. Choose this first: it decides where the rest of your choices are saved."],
    build = function(p)
        local DB = EV.DB
        local own = DB.charKey
        p:Section(L["Settings"])
        p:Row{ type = "dropdown", text = L["This character uses"], width = 250,
               tooltip = L["Shared: every character on the shared profile looks the same, and a change on one is a change on all. Just this character: a profile of its own, starting as a copy of the shared one."],
               values = {
                   { value = "shared", text = L["The shared setup"] },
                   { value = "own",    text = L["A setup of its own"] },
               },
               get = function() return DB:GetProfileName() == own and "own" or "shared" end,
               set = function(v)
                   local from = DB:GetProfileName()
                   if v == "own" then
                       DB:SetProfile(own)
                       if from ~= own then DB:CopyProfile(from) end
                   else
                       DB:SetProfile("Default")
                   end
                   I.RebuildPages()
               end }
        p:Note((L["Active profile: %s. Profiles are all in /evui under General > Profiles."]):format(EV:Colour(DB:GetProfileName())), 0.7)

        p:Section(L["Bring a setup with you"])
        p:Row{ type = "button", text = L["Paste a profile string"], label = L["Import"], width = 150,
               tooltip = L["A string from /evui export, yours from another account or one a friend shared. It replaces the settings in your active profile."],
               onClick = function()
                   W.ShowPasteText(L["Import profile"],
                       L["Paste a profile string. It replaces the settings in your active profile."], L["Import"],
                       function(text)
                           local ok, info = DB:ImportProfile(text)
                           if not ok then return info end
                           EV:Print(L["Imported profile"], EV:Colour(tostring(info or "")))
                           NeedReload()
                           I.RebuildPages()
                       end)
               end }

        if EV.Alts then
            local A = EV.Alts
            p:Section(L["Your other characters"])
            p:Row{ type = "toggle", text = L["Remember what my characters carry"],
                   tooltip = L["Each character's gold, bags, bank and mail, recorded as you play it: item tooltips then say who has how many, and /evui alts shows them all side by side."],
                   get = function() return A:Settings().track end,
                   set = function(v) A:Settings().track = v; A:Invalidate("settings") end }
            p:Row{ type = "dropdown", text = L["Whose characters count"], width = 250,
                   values = {
                       { value = "faction", text = L["My faction, any realm"] },
                       { value = "realm",   text = L["My realm and faction"] },
                       { value = "all",     text = L["Every character"] },
                   },
                   disabled = function() return not A:Settings().track end,
                   get = function() return A:Settings().scope end,
                   set = function(v) A:Settings().scope = v; A:Invalidate("scope") end }
            local known = #A:List()
            if known > 1 then
                p:Note((L["EvermoreUI knows %d of your characters on this account. Each one you log in on joins them."]):format(known), 0.7)
            else
                p:Note(L["Each character you log in on joins the list. A bank is known once you've visited a banker."], 0.7)
            end
        end
    end }

STEPS[#STEPS + 1] = { key = "look", title = L["Look"],
    heading = L["How it looks"],
    sub = L["Contrast, font and size, for every EvermoreUI window and the Blizzard windows it skins."],
    build = function(p)
        local Px = EV.Pixel
        p:Section(L["Look"])
        p:Row{ type = "dropdown", text = L["Contrast"], width = 180,
               values = { { value = "standard", text = L["Standard"] }, { value = "high", text = L["High contrast"] } },
               tooltip = L["High contrast brightens borders and text and deepens panels. Both meet WCAG AA contrast."],
               get = function() return T.mode end,
               set = function(v) T.SetContrast(v) end }
        p:Row{ type = "dropdown", text = L["Font"], width = 200,
               values = function() return EV.Media:FontValues(false) end,
               tooltip = L["The font for every EvermoreUI addon. Blizzard's text changes straight away; ours finishes changing after a reload."],
               get = function() return EV.Media:GlobalFontName() end,
               set = function(v) EV.Fonts:SetGlobal(v); NeedReload() end }
        p:Row{ type = "toggle", text = L["Use it in Blizzard's interface too"],
               tooltip = L["Swaps Blizzard's plain text font for ours: quest text, menus and windows. Decorative fonts are left alone."],
               disabled = function() return not EV.Fonts:Supported() end,
               get = function() return EV.DB:GetCore().blizzardFonts ~= false end,
               set = function(v) EV.Fonts:SetBlizzard(v) end }

        p:Section(L["Size"])
        p:Row{ type = "toggle", text = L["Pixel-perfect scale"],
               tooltip = L["One UI unit is exactly one screen pixel, so borders and edges line up. Turning this off hands scaling back to Blizzard after a reload."],
               get = function() return Px.ScaleSettings().managed end,
               set = function(v)
                   Px.ScaleSettings().managed = v
                   if v then Px:ApplyScale() else NeedReload() end
               end }
        p:Row{ type = "slider", text = L["UI size"], min = 100, max = 200, step = 5,
               fmt = function(v) return v .. "%" end,
               tooltip = L["Everything bigger while staying pixel-perfect. Try it now: the change is live."],
               disabled = function() return not Px.ScaleSettings().managed end,
               get = function() return math.floor((Px.ScaleSettings().size or 1) * 100 + 0.5) end,
               set = function(v) Px.ScaleSettings().size = v / 100; Px:ApplyScale() end }
    end }

-- Which options group each module belongs to, as the sidebar has them.
local GROUPS = {
    { key = "Combat", title = L["Combat"],
      mods = { "UnitFrames", "SwingTimer", "GroupFrames", "Nameplates", "ActionBars", "Cooldowns", "Auras", "Reminders" } },
    { key = "Interface", title = L["Interface"],
      mods = { "Minimap", "Objectives", "DataBars", "MicroMenu", "BagBar", "Bags", "Characters", "LootRolls", "ReadyCheck", "LootStats" } },
    { key = "Chat", title = L["Chat & Tooltips"], mods = { "Chat", "Tooltips" } },
}

STEPS[#STEPS + 1] = { key = "modules", title = L["Modules"],
    heading = L["What EvermoreUI takes over"],
    sub = L["Each part is its own module. Switch off any you'd rather leave to Blizzard or another addon; its frames come back after a reload."],
    build = function(p)
        local placed = {}
        local function Row(mod)
            local name = mod.name
            placed[name] = true
            p:Row{ type = "toggle", text = L[mod.title or name], tooltip = mod.description and L[mod.description],
                   get = function() return ModuleWanted(name) end,
                   set = function(on)
                       EV.DB:GetCore().disabled[name] = (not on) or nil
                       NeedReload()
                   end }
        end
        for _, g in ipairs(GROUPS) do
            local any = false
            for _, name in ipairs(g.mods) do
                local mod = EV:GetModule(name, true)
                if mod and not mod.internal and not mod.experimental then
                    if not any then p:Section(g.title); any = true end
                    Row(mod)
                end
            end
        end
        local rest = {}
        for _, mod in EV:IterateModules() do
            if not placed[mod.name] and not mod.internal and not mod.experimental then rest[#rest + 1] = mod end
        end
        if #rest > 0 then
            p:Section(L["Extras"])
            for _, mod in ipairs(rest) do Row(mod) end
        end
    end }

STEPS[#STEPS + 1] = { key = "layout", title = L["Layout"],
    heading = L["A layout for how you play"],
    sub = L["A starting point for where things sit. Nothing moves until you press Use this layout, and Undo puts everything back."],
    build = function(p)
        I.layoutPick = I.layoutPick or State().role or "damage"
        local pick = I.layoutPick
        p:Section(L["Your role"])
        local cells = {}
        for _, role in ipairs(LAYOUT_ORDER) do
            local def = LAYOUTS[role]
            cells[#cells + 1] = p:Row{ type = "custom", text = "|A:" .. def.icon .. ":16:16|a  " .. def.text,
                   tooltip = def.blurb,
                   build = function(host)
                       return W.RadioGroup(host, { { value = role, text = "" } },
                           function() return pick end,
                           function(v) I.layoutPick = v; I.RebuildPages() end)
                   end }
        end
        p:Spacer(4)
        p:Note(LAYOUTS[pick].blurb)
        p:Row{ type = "button", text = L["Place my frames for this role"], label = L["Use this layout"], width = 150, style = "accent",
               tooltip = L["Resets the party and raid frames, player and target frames and cooldown bars, then places them for this role. Everything else stays where it is."],
               onClick = function() ApplyLayout(pick); I.RefreshPage() end }
        p:Row{ type = "button", text = L["Put them back where they were"], label = L["Undo"], width = 150,
               disabled = function() return undo == nil end,
               onClick = function() UndoLayout(); I.RefreshPage() end }
        p:Row{ type = "button", text = L["Fine-tune by dragging"], label = L["Edit mode"], width = 150,
               tooltip = L["Setup closes and edit mode opens. /evui install brings you back here."],
               onClick = function() I.Hide(); EV.Movers:Unlock() end }
        if pick == "healer" and Module("GroupFrames") then
            p:Section(L["Healing"])
            p:Row{ type = "button", text = L["Click casting on your party and raid frames"], label = L["Set it up"], width = 150,
                   tooltip = L["Shift + left click to cast a heal on whoever you click, and the like. Opens the Click Casting page."],
                   onClick = function()
                       I.Hide()
                       EV:OpenOptions()
                       if EV.Options.ShowPage then EV.Options:ShowPage("clickcast") end
                   end }
        end
    end }

STEPS[#STEPS + 1] = { key = "everyday", title = L["Everyday"],
    heading = L["The little things"],
    sub = L["Conveniences for vendors, loot, quests and trainers. All of them are off or on as you like; hold Shift at an NPC to skip them once."],
    build = function(p)
        local q = Module("QoL")
        if q then
            local db = q.db
            local function T2(key, text, tip)
                p:Row{ type = "toggle", text = text, tooltip = tip,
                       get = function() return db[key] end,
                       set = function(v) db[key] = v; if q.Refresh then q:Refresh() end end }
            end
            p:Section(L["Vendors"])
            T2("autoRepair", L["Repair automatically"], L["At any vendor who can repair, using guild funds first where you're allowed."])
            T2("autoSellJunk", L["Sell grey items"], L["Every grey item in your bags, sold when you open a vendor."])
            p:Section(L["Loot and quests"])
            T2("fastLoot", L["Faster looting"], L["Takes everything the moment the loot window opens."])
            T2("autoAccept", L["Accept quests"], L["Accepts a quest as soon as its text opens."])
            T2("autoTurnIn", L["Hand in quests"], L["Completes a quest when there's no reward to choose."])
            p:Section(L["Levelling"])
            T2("trainingNotify", L["Tell me when there's something to train"], L["A chat line when you level and your trainer has something new for you."])
            T2("trainAllButton", L["Train All button"], L["On the class trainer: buys everything you can afford in one go."])
            T2("durabilityWarn", L["Warn me when my gear is wearing out"], L["A warning in chat when your gear drops low, and again if something breaks."])
        end
        local s = Module("Skins")
        if s then
            p:Section(L["Windows"])
            p:Row{ type = "toggle", text = L["Skin Blizzard's windows to match"],
                   tooltip = L["The game's own windows in the EvermoreUI palette: character, spellbook, quest log, professions and the rest. Turning it off needs a reload."],
                   get = function() return s.db.enabled end,
                   set = function(v) s.db.enabled = v; if v then s:Refresh() else NeedReload() end end }
            if s.db.damageMeter ~= nil then
                local sns = EV._ModuleNS["EvermoreUI_Skins"]
                p:Row{ type = "toggle", text = L["Skin the damage meter too"],
                       tooltip = L["Forever's built-in damage meter to match: our title bar, surface, flat bars and font. Its own settings keep working."],
                       disabled = function() return not s.db.enabled end,
                       get = function() return s.db.damageMeter end,
                       set = function(v)
                           s.db.damageMeter = v
                           if v then if sns and sns.RefreshDamageMeter then sns.RefreshDamageMeter() end else NeedReload() end
                       end }
            end
        end
        if not (q or s) then p:Note(L["Quality of Life and Window Skins are switched off, so there's nothing to set here."]) end
    end }

STEPS[#STEPS + 1] = { key = "done", title = L["Done"],
    heading = L["You're all set"],
    sub = L["A few things worth knowing before you go."],
    build = function(p)
        if reloadNeeded then
            p:Banner(L["Some of your choices take effect after a reload. Finish reloads for you."])
        end
        p:Section(L["Getting around"])
        p:Row{ type = "button", text = L["Everything else: /evui"], label = L["Open options"], width = 150,
               onClick = function() I.Finish(false, true); EV:OpenOptions() end }
        p:Row{ type = "button", text = L["Move and resize anything: /evui edit"], label = L["Edit mode"], width = 150,
               onClick = function() I.Finish(false, true); EV.Movers:Unlock() end }
        if EV.Designers and #EV.Designers:List() > 0 then
            p:Row{ type = "button", text = L["Unit frames, nameplates and cooldowns: /evui design"], label = L["Designer"], width = 150,
                   onClick = function() I.Finish(false, true); EV.Designers:Open() end }
        end
        p:Section(L["Tell us how it went"])
        p:Note(L["EvermoreUI is built for Forever, with Forever players. If anything in setup was confusing, missing or wrong, we want to hear it: it shapes what gets built next."])
        p:Row{ type = "button", text = L["Our Discord: ideas, help and feedback"], label = L["Copy link"], width = 150,
               onClick = function()
                   W.ShowCopyText(L["EvermoreUI Discord"], DISCORD, L["Paste it into your browser. Setup feedback goes in #ideas."])
               end }
        p:Row{ type = "button", text = L["Something broken? /evui bug"], label = L["Bug report"], width = 150,
               onClick = function() EV.Report:Show() end }
        p:Row{ type = "button", text = L["What changed in this version: /evui new"], label = L["What's new"], width = 150,
               onClick = function() I.Finish(false, true); EV.WhatsNew.Show() end }
    end }

I.STEPS = STEPS

--------------------------------------------------------------------------------
--  Window
--------------------------------------------------------------------------------
local function ContentWidth() return WIDTH - 2 - RAIL_W - 14 end

local function PaintRail()
    for i, b in ipairs(railButtons) do
        local sel = i == current
        b.bar:SetShown(sel)
        b.bar:SetColorTexture(T.RGBA("accent"))
        b.hl:SetShown(sel or b.hover)
        b.hl:SetColorTexture(T.C4(T.Resolve(T.LOOK.listItem, { hover = b.hover and not sel, on = sel }).fill))
        local passed = i < current and not sel
        b.num:SetShown(not passed)
        b.num:SetTextColor(T.RGBA(sel and "accent" or "textDisabled"))
        b.tick:SetShown(passed)
        b.tick:SetVertexColor(T.RGBA("success"))
        b.text:SetTextColor(T.RGBA(sel and "text" or (i < current and "textMuted" or "textDisabled")))
    end
end

local function BuildRail()
    rail = CreateFrame("Frame", nil, window.body)
    rail:SetPoint("TOPLEFT")
    rail:SetPoint("BOTTOMLEFT")
    rail:SetWidth(RAIL_W)
    rail.bg = W.Surface(rail, "raised", nil, { edge = false })
    local edge = T.Fill(rail, "BORDER", "divider")
    edge:SetPoint("TOPRIGHT"); edge:SetPoint("BOTTOMRIGHT"); edge:SetWidth(1)

    local logo = rail:CreateTexture(nil, "ARTWORK")
    logo:SetSize(40, 40)
    logo:SetPoint("TOPLEFT", 18, -18)
    logo:SetTexture("Interface\\AddOns\\EvermoreUI\\Media\\UI\\evermore.png")
    local name = T.Text(rail, "title", "title", true)
    name:SetPoint("LEFT", logo, "RIGHT", 10, 6)
    name:SetText("EvermoreUI")
    local ver = T.Text(rail, "small", "textMuted")
    ver:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    ver:SetText(EV.version or "")

    local y = -84
    for i, step in ipairs(STEPS) do
        local b = CreateFrame("Button", nil, rail)
        b:SetPoint("TOPLEFT", 0, y)
        b:SetPoint("TOPRIGHT", -1, y)
        b:SetHeight(36)
        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetAllPoints()
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
        b.num = T.Text(b, "body", "textDisabled", true, "CENTER")
        b.num:SetWidth(22)
        b.num:SetPoint("LEFT", 16, 0)
        b.num:SetText(tostring(i))
        b.tick = W.Glyph(b, "check", 12, "ARTWORK")
        b.tick:SetPoint("CENTER", b.num, "CENTER")
        b.text = T.Text(b, "label", "text")
        b.text:SetPoint("LEFT", b.num, "RIGHT", 8, 0)
        b.text:SetText(step.title)
        b:SetScript("OnEnter", function() b.hover = true; PaintRail() end)
        b:SetScript("OnLeave", function() b.hover = false; PaintRail() end)
        b:SetScript("OnClick", function() I.Go(i) end)
        railButtons[i] = b
        y = y - 36
    end
end

local function BuildHead()
    head = CreateFrame("Frame", nil, window.body)
    head:SetPoint("TOPLEFT", RAIL_W, 0)
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_H)
    head.title = T.Text(head, "heading", "title", true)
    head.title:SetPoint("TOPLEFT", T.PAD, -20)
    head.sub = T.Text(head, "body", "textMuted")
    head.sub:SetPoint("TOPLEFT", head.title, "BOTTOMLEFT", 0, -6)
    head.sub:SetPoint("RIGHT", -T.PAD, 0)
    head.sub:SetJustifyH("LEFT")
    head.sub:SetWordWrap(true)
    local rule = T.Fill(head, "BORDER", "divider")
    rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
    head.rule = rule
end

local function BuildFooter()
    footer = CreateFrame("Frame", nil, window.body)
    footer:SetPoint("BOTTOMLEFT", RAIL_W, 0)
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(FOOT_H)
    local rule = T.Fill(footer, "BORDER", "divider")
    rule:SetPoint("TOPLEFT"); rule:SetPoint("TOPRIGHT"); rule:SetHeight(1)

    footer.next = W.Button(footer, L["Next"], 130, function()
        if current >= #STEPS then I.Finish() else I.Go(current + 1) end
    end, "accent")
    footer.next:SetPoint("RIGHT", -16, 0)
    footer.back = W.Button(footer, L["Back"], 100, function() I.Go(current - 1) end)
    footer.back:SetPoint("RIGHT", footer.next, "LEFT", -8, 0)
    footer.step = T.Text(footer, "small", "textMuted")
    footer.step:SetPoint("LEFT", 16, 0)
end

function I.PaintFooter()
    if not footer then return end
    footer.back:SetDisabled(current <= 1)
    if current >= #STEPS then
        footer.next:SetText(reloadNeeded and L["Finish and reload"] or L["Finish"])
    else
        footer.next:SetText(L["Next"])
    end
    footer.step:SetText((L["Step %d of %d"]):format(current, #STEPS))
end

local function Build()
    if window then return end
    window = W.Window("EvermoreUIInstaller", { title = L["EvermoreUI setup"], width = WIDTH, height = HEIGHT })
    window:SetPoint("CENTER")
    BuildRail()
    BuildHead()
    BuildFooter()
    scroll = W.Scroll(window.body)
    scroll:SetPoint("TOPLEFT", RAIL_W, -HEAD_H - 1)
    scroll:SetPoint("BOTTOMRIGHT", -4, FOOT_H + 1)
    -- Closed part way through: it stays pending and comes back next login.
    window:HookScript("OnHide", function()
        T.HideTooltip()
        if EV.InstallPending() and not I.finishing then
            EV:Print(L["Setup will pick up where you left off next time you log in, or type /evui install."])
        end
    end)
end

local function PageFor(i)
    local step = STEPS[i]
    local entry = pages[step.key]
    if entry then return entry end
    local frame = CreateFrame("Frame", nil, scroll.content)
    frame:SetPoint("TOPLEFT")
    local w = ContentWidth()
    frame:SetWidth(w)
    local p = EV.Options_NewBuilder(frame, w - T.PAD * 2)
    step.build(p)
    frame:SetHeight(p:Height())
    entry = { frame = frame, builder = p }
    pages[step.key] = entry
    return entry
end

function I.RefreshPage()
    local entry = pages[STEPS[current].key]
    if entry then entry.builder:Refresh() end
end

--- Drop built pages, e.g. after a profile change: every value may be new.
function I.RebuildPages()
    for _, e in pairs(pages) do e.frame:Hide() end
    wipe(pages)
    if window and window:IsShown() then I.Go(current) end
end

function I.Go(i)
    i = math.max(1, math.min(#STEPS, i or 1))
    current = i
    State().step = i
    for _, e in pairs(pages) do e.frame:Hide() end
    local entry = PageFor(i)
    entry.frame:Show()
    entry.builder:Refresh()
    local step = STEPS[i]
    head.title:SetText(step.heading or step.title)
    head.sub:SetText(step.sub or "")
    scroll:SetContentHeight(entry.frame:GetHeight())
    scroll:ScrollTo(0)
    PaintRail()
    I.PaintFooter()
end

function I:Show(step)
    if InCombatLockdown() then return end
    I.layoutPick = nil
    Build()
    I.finishing = false
    -- A built page holds the values it was built with; start fresh each time.
    for _, e in pairs(pages) do e.frame:Hide() end
    wipe(pages)
    window:Show()
    I.Go(step or State().step or 1)
end

function I.Hide() if window then window:Hide() end end

--- Mark setup as finished and close. skip: without going through it.
--- stay: going on to something else (options, edit mode), so no reload yet.
function I.Finish(skip, stay)
    local s = State()
    s.done = EV.version or "dev"
    s.at = time()
    s.skipped = skip and true or nil
    s.step = nil
    I.finishing = true
    if window then window:Hide() end
    I.finishing = false
    if reloadNeeded and not skip and not stay then
        ReloadUI()
    elseif reloadNeeded then
        EV:Print(L["Some changes take effect after a reload: /reload"])
    end
end

-- Setup isn't a thing to have open mid-fight.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function() if window and window:IsShown() then window:Hide() end end)
