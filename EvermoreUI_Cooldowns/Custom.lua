if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Custom.lua
--  What Blizzard's Cooldown Manager doesn't track, added by you.
--
--  Your own icons, in the cooldown bars:
--    slot    an equipped trinket (13 or 14), shown while it has a Use
--    item    anything with a cooldown in your bags: potions, Healthstones,
--            engineering gear. Greyed when you have none, with a count.
--    spell   a spell of yours the game doesn't list, shown once known
--  Each is a frame of ours with an icon, a Cooldown and a count, keyed
--  "c:<uid>" (evKey), so Cooldowns.lua sorts, moves and hides it with your
--  arrangement like any of Blizzard's items. The list is per class; where
--  each sits is per spec, like the rest of the arrangement.
--
--  Cooldowns are handed straight to the Cooldown frame: a spell's through its
--  duration object where the client has one, otherwise start and duration.
--  Those can be secret in combat, and a setter takes a secret value where
--  Lua can't compare one, so nothing here reads them.
--
--  Your own bars: as many as you like, each a buff bar (the buffs you name,
--  drawn by the engine's aura container) or an icon bar (placed like the
--  game's cooldown bars). See "Your own bars" below.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme
local M = ns.module
local floor, max, min = math.floor, math.max, math.min
local issecret = issecretvalue or function() return false end

local TRINKETS = { [13] = L["Top trinket"], [14] = L["Bottom trinket"] }
ns.TRINKETS = TRINKETS

local function Plain(v) return v ~= nil and not issecret(v) end

--------------------------------------------------------------------------------
--  Lists
--------------------------------------------------------------------------------
local function ClassList(field)
    local _, class = UnitClass("player")
    class = class or "?"
    local all = M.db[field]
    if type(all[class]) ~= "table" then all[class] = {} end
    return all[class]
end

function M:CustomList() return ClassList("custom") end

local seq = 0
local function NewUID()
    seq = seq + 1
    return ("%d%03d"):format(time() % 100000000, seq % 1000)
end

--- Add an icon: kind "slot" | "item" | "spell", its id, and the bar.
function M:AddCustom(kind, id, bar)
    if type(id) ~= "number" then return nil end
    local list = self:CustomList()
    for _, e in ipairs(list) do if e.kind == kind and e.id == id then return e end end
    local e = { uid = NewUID(), kind = kind, id = id, bar = bar or "essential" }
    list[#list + 1] = e
    ns.SyncCustom()
    return e
end

function M:RemoveCustom(uid)
    local list = self:CustomList()
    for i, e in ipairs(list) do
        if e.uid == uid then
            table.remove(list, i)
            local a = self:Arrangement(false)
            if a then
                local key = "c:" .. uid
                a.order[key], a.bar[key], a.hidden[key] = nil, nil, nil
            end
            break
        end
    end
    ns.SyncCustom()
end

--------------------------------------------------------------------------------
--  Reading the game (every call guarded; nothing secret is compared)
--------------------------------------------------------------------------------
local function SpellName(id) return M.SpellName(id) end

--- A spell ID from what you typed: an ID, a link, or a name you know.
function M.ResolveSpell(text)
    if type(text) == "number" then return text end
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    local id = tonumber(text) or tonumber(text:match("spell:(%d+)"))
    if id then return id end
    local ok, info = pcall(C_Spell.GetSpellInfo, text)
    if ok and type(info) == "table" and Plain(info.spellID) then return info.spellID end
end

--- An item ID from an ID, a link, or the name of something you carry.
function M.ResolveItem(text)
    if type(text) == "number" then return text end
    if type(text) ~= "string" then return nil end
    text = strtrim(text)
    local id = tonumber(text) or tonumber(text:match("item:(%d+)"))
    if id then return id end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, iid = pcall(C_Item.GetItemInfoInstant, text)
        if ok and type(iid) == "number" then return iid end
    end
end

local function Known(id)
    if type(IsPlayerSpell) == "function" then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and v then return true end
    end
    local name = SpellName(id)
    if not name then return false end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    return ok and type(info) == "table"
end

local function ItemUse(itemID)
    if not (C_Item and C_Item.GetItemSpell) then return true end
    local ok, name = pcall(C_Item.GetItemSpell, itemID)
    return ok and name ~= nil
end

local function ItemCount(itemID)
    if not (C_Item and C_Item.GetItemCount) then return nil end
    local ok, n = pcall(C_Item.GetItemCount, itemID, false, true)
    if ok and type(n) == "number" and not issecret(n) then return n end
end

--- What an entry shows now: active, texture, label, spell name (for keybind,
--- rank and linked timer text), count text, greyed.
local function Describe(e)
    if e.kind == "slot" then
        local item = GetInventoryItemID("player", e.id)
        local tex = GetInventoryItemTexture("player", e.id)
        local name = item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
        return {
            active = item ~= nil and ItemUse(item),
            tex = tex or 136528,
            label = (name or TRINKETS[e.id] or "?"),
            what = TRINKETS[e.id],
        }
    elseif e.kind == "item" then
        local n = ItemCount(e.id)
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)
        local tex = C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)
        return {
            active = true, tex = tex or 134400, label = name or ("#" .. e.id), what = L["Item"],
            count = n and n > 1 and tostring(n) or nil, grey = n == 0,
        }
    else
        local name = SpellName(e.id)
        local tex
        if C_Spell.GetSpellTexture then
            local ok, t = pcall(C_Spell.GetSpellTexture, e.id)
            tex = ok and Plain(t) and t or nil
        end
        return {
            active = Known(e.id), tex = tex or 134400, label = name or ("#" .. e.id), what = L["Spell"],
            spell = name,
        }
    end
end

--------------------------------------------------------------------------------
--  Frames
--------------------------------------------------------------------------------
local frames = {}      -- uid -> frame
local order = {}       -- frames in list order

local function NewFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(36, 36)
    f:EnableMouse(false)
    f:Hide()
    f.back = f:CreateTexture(nil, "BACKGROUND")
    f.back:SetAllPoints()
    f.back:SetColorTexture(0, 0, 0, 1)
    f.Icon = f:CreateTexture(nil, "ARTWORK")
    f.Icon:SetAllPoints()
    f.Cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.Cooldown:SetAllPoints()
    f.Cooldown:SetDrawEdge(false)
    f.Cooldown:SetHideCountdownNumbers(false)
    -- Same shape as Blizzard's items, so Cooldowns.lua styles both alike.
    f.ChargeCount = CreateFrame("Frame", nil, f)
    f.ChargeCount:SetAllPoints()
    f.ChargeCount:SetFrameLevel(f:GetFrameLevel() + 5)
    f.ChargeCount.Current = f.ChargeCount:CreateFontString(nil, "OVERLAY")
    f.ChargeCount.Current:SetFont(EV.Media:Fetch("font"), 10, "OUTLINE")
    f.ChargeCount.Current:SetPoint("BOTTOMRIGHT", -2, 2)
    -- Parts Blizzard's items have and ours don't, named so nothing looks.
    f.Applications, f.DebuffBorder, f.CooldownFlash, f.OutOfRange = false, false, false, false
    f.evCustom = true
    return f
end

--- The cooldown on one of ours, straight into its Cooldown frame.
local function UpdateCooldown(f, e)
    local cd = f.Cooldown
    if not f.evActive then cd:Clear(); return end
    if e.kind == "spell" then
        -- Duration objects carry secret timings safely where the client has
        -- them; otherwise start and duration go straight in.
        local set = false
        if C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
            local ok, obj = pcall(C_Spell.GetSpellCooldownDuration, e.id)
            set = ok and obj ~= nil and pcall(cd.SetCooldownFromDurationObject, cd, obj) or false
        end
        if not set then
            local ok, info = pcall(C_Spell.GetSpellCooldown, e.id)
            if ok and type(info) == "table" then
                -- The global cooldown isn't this spell's; skip it when we can tell.
                if Plain(info.isOnGCD) and info.isOnGCD == true then
                    cd:Clear()
                elseif not pcall(cd.SetCooldown, cd, info.startTime, info.duration, info.modRate) then
                    cd:Clear()
                end
            else
                cd:Clear()
            end
        end
        local okC, ch = pcall(C_Spell.GetSpellCharges, e.id)
        local text = f.ChargeCount.Current
        -- Passed through as is: a charge count can be secret too.
        if not (okC and type(ch) == "table" and pcall(text.SetText, text, ch.currentCharges)) then
            text:SetText("")
        end
        return
    end
    local ok, start, dur
    if e.kind == "slot" then
        ok, start, dur = pcall(GetInventoryItemCooldown, "player", e.id)
    else
        local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        if fn then ok, start, dur = pcall(fn, e.id) end
    end
    if not (ok and pcall(cd.SetCooldown, cd, start, dur)) then cd:Clear() end
end

--- Bring the frames in line with the list and the game.
function ns.SyncCustom()
    local list = M:CustomList()
    local keep = {}
    wipe(order)
    for i, e in ipairs(list) do
        local f = frames[e.uid] or NewFrame()
        frames[e.uid] = f
        keep[e.uid] = true
        local d = Describe(e)
        f.evKey, f.evUID, f.evEntry = "c:" .. e.uid, e.uid, e
        f.evHome = e.bar or "essential"
        f.evActive = d.active and true or false
        f.evLabel, f.evWhat = d.label, d.what
        f.evSpellName = d.spell
        f.layoutIndex = 1000 + i
        f.Icon:SetTexture(d.tex)
        f.Icon:SetDesaturated(d.grey and true or false)
        if e.kind ~= "spell" then f.ChargeCount.Current:SetText(d.count or "") end
        UpdateCooldown(f, e)
        order[#order + 1] = f
    end
    for uid, f in pairs(frames) do
        if not keep[uid] then
            f:Hide()
            M.Park(f)
            frames[uid] = nil
        end
    end
    if M:IsEnabled() then M:LayoutAll() end
end

function ns.CustomFrames() return order end

local function UpdateAllCooldowns()
    for _, f in ipairs(order) do
        if f.evEntry then UpdateCooldown(f, f.evEntry) end
    end
end

local function UpdateCounts()
    for _, f in ipairs(order) do
        local e = f.evEntry
        if e and e.kind == "item" then
            local n = ItemCount(e.id)
            f.ChargeCount.Current:SetText(n and n > 1 and tostring(n) or "")
            f.Icon:SetDesaturated(n == 0)
        end
    end
end

--------------------------------------------------------------------------------
--  Your own bars
--
--  As many as you like, per class, each with a name:
--    buffs   the buffs you name, drawn by an engine aura container, one
--            group per buff so your order holds (the engine only sorts
--            within a group). Every rank counts.
--    icons   placed by Cooldowns.lua like the game's two cooldown bars, and
--            able to hold anything they can: your own icons, and any of
--            Blizzard's cooldowns dragged across.
--  A bar's settings are M.db.bars["u:<id>"], made with the bar and removed
--  with it; its place on screen is edit mode's ("CD_u:<id>").
--------------------------------------------------------------------------------
function M:UserBars() return ClassList("userBars") end

local function NewDefaults(kind)
    if kind == "buffs" then return M.BarDefaults(32, 8, "RIGHT", "UP", false) end
    return M.BarDefaults(36, 8, "CENTER", "DOWN", true)
end
ns.NewDefaults = NewDefaults

local defs, defByKey = {}, {}
local known = {}          -- keys of bars of ours we've made holders for

local function PosFor(i) return { "CENTER", "CENTER", 0, -60 - (i - 1) * 46 } end

--- Defs for this class's bars, rebuilt from the list.
local function Defs()
    wipe(defs); wipe(defByKey)
    for i, b in ipairs(M:UserBars()) do
        local d = { key = "u:" .. b.id, label = b.name or L["Bar"], buff = b.kind == "buffs",
                    own = true, user = b, pos = PosFor(i) }
        defs[#defs + 1] = d
        defByKey[d.key] = d
    end
    return defs
end
function ns.UserDefs() return defs end
function ns.UserDef(key) return defByKey[key] end

--- Make a bar: kind "buffs" or "icons", and a name.
function M:NewBar(kind, name)
    local list = self:UserBars()
    local b = { id = NewUID(), kind = kind == "buffs" and "buffs" or "icons",
                name = (name and strtrim(name) ~= "" and strtrim(name))
                    or (kind == "buffs" and L["Buffs"] or L["Icons"]) .. " " .. (#list + 1),
                buffs = {} }
    list[#list + 1] = b
    self.db.bars["u:" .. b.id] = NewDefaults(b.kind)
    ns.SyncUserBars()
    return b
end

function M:RenameBar(b, name)
    name = name and strtrim(name) or ""
    if name == "" then return end
    b.name = name
    ns.SyncUserBars()
end

--- Delete a bar. Whatever was on it goes back where it came from.
function M:DeleteBar(b)
    local list = self:UserBars()
    for i, x in ipairs(list) do if x == b then table.remove(list, i) break end end
    local key = "u:" .. b.id
    self.db.bars[key] = nil
    for _, e in ipairs(self:CustomList()) do if e.bar == key then e.bar = "essential" end end
    for _, a in pairs(self.db.arrange) do
        if type(a) == "table" and type(a.bar) == "table" then
            for id, to in pairs(a.bar) do if to == key then a.bar[id] = nil end end
        end
    end
    ns.SyncUserBars()
end

function M.BuffName(e)
    if type(e.spell) == "number" then return SpellName(e.spell) or ("#" .. e.spell) end
    return e.spell
end
M.MyBuffName = M.BuffName

--- Name a buff for a buff bar: a spell ID, a link or a name.
function M.AddBarBuff(b, text)
    if type(text) ~= "string" and type(text) ~= "number" then return nil end
    local spell = tonumber(text) or (type(text) == "string" and tonumber(text:match("spell:(%d+)")))
    if not spell then
        spell = strtrim(tostring(text))
        if spell == "" then return nil end
    end
    b.buffs = b.buffs or {}
    local name = type(spell) == "number" and SpellName(spell) or spell
    for _, e in ipairs(b.buffs) do
        local en = M.BuffName(e)
        if en and name and en:lower() == name:lower() then return e end
    end
    local e = { spell = spell, seen = {} }
    b.buffs[#b.buffs + 1] = e
    return e
end

function M.RemoveBarBuff(b, i) table.remove(b.buffs, i) end

--- Every spell ID in your spellbook with this name (each rank has its own).
local function BookIDs(name, into)
    if not (name and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local okN, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not okN or type(lines) ~= "number" then return end
    local want = name:lower()
    for i = 1, lines do
        local okL, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
        if okL and type(line) == "table" and line.itemIndexOffset and line.numSpellBookItems then
            for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local ok, item = pcall(C_SpellBook.GetSpellBookItemInfo, j, bank)
                if ok and type(item) == "table" and Plain(item.name) and item.name:lower() == want then
                    local id = item.spellID or item.actionID
                    if Plain(id) then into[id] = true end
                end
            end
        end
    end
end

--- The spell IDs of each named buff on a bar, in its order.
local function Groups(b)
    local groups = {}
    for _, e in ipairs(b.buffs or {}) do
        local ids = {}
        if type(e.spell) == "number" then ids[e.spell] = true end
        local name = M.BuffName(e)
        if name then
            BookIDs(name, ids)
            local ok, info = pcall(C_Spell.GetSpellInfo, name)
            if ok and type(info) == "table" and Plain(info.spellID) then ids[info.spellID] = true end
        end
        for id in pairs(e.seen or {}) do ids[id] = true end
        if next(ids) then groups[#groups + 1] = ids end
    end
    return groups
end

--- Out of combat, note the rank IDs of named buffs that are on you.
local function Learn()
    if InCombatLockdown() then return false end
    local byName = {}
    for _, b in ipairs(M:UserBars()) do
        for _, e in ipairs(b.buffs or {}) do
            local name = M.BuffName(e)
            if name then
                byName[name:lower()] = byName[name:lower()] or {}
                table.insert(byName[name:lower()], e)
            end
        end
    end
    if not next(byName) then return false end
    local learnt = false
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if Plain(a.name) and Plain(a.spellId) then
            for _, e in ipairs(byName[a.name:lower()] or {}) do
                e.seen = e.seen or {}
                if not e.seen[a.spellId] then e.seen[a.spellId] = true; learnt = true end
            end
        end
    end
    return learnt
end

local function LayoutBuffBar(def)
    local holder = M.Holder(def)
    holder.inside = holder.inside or CreateFrame("Frame", nil, holder)
    local inside = holder.inside
    local db = M.db.bars[def.key]
    local groups = Groups(def.user)
    local n = #groups
    local C = EV.AuraContainer
    if not (db and M:IsEnabled() and db.enabled and n > 0 and C and C.Supported()) then
        holder:SetSize(max(db and db.size or 32, 20), max(db and db.size or 32, 20))
        C.Hide(inside)
        holder:SetAlpha(0)
        return
    end
    local cfg = {
        size = db.size, spacing = db.spacing, perRow = max(1, db.perRow), max = min(n, 16),
        growX = db.grow == "LEFT" and "LEFT" or "RIGHT", growY = db.rows == "UP" and "UP" or "DOWN",
        showSwipe = true, showTimer = true, timerSize = max(9, floor(db.size * 0.36 + 0.5)),
    }
    EV.Pixel:SetSize(holder, C.BoxSize(cfg))
    inside:SetAllPoints(holder)
    -- A container only changes shape out of combat; in combat the one
    -- already built carries on.
    if not (InCombatLockdown() and inside.container) then
        C.Build(inside, cfg, { unit = "player", filter = "HELPFUL", groups = groups })
    end
    holder:SetAlpha(M.Opacity(db) or 0)
end

function ns.LayoutMine()
    for _, d in ipairs(defs) do
        if d.buff then LayoutBuffBar(d) end
    end
end

--- Holders for this class's bars, and none for bars that have gone.
function ns.SyncUserBars()
    Defs()
    local now = {}
    for _, d in ipairs(defs) do
        now[d.key] = true
        known[d.key] = true
        if not M.db.bars[d.key] then M.db.bars[d.key] = NewDefaults(d.user.kind) end
        local holder = M.Holder(d)
        local e = EV.Movers:Get("CD_" .. d.key)
        if e then e.label = d.label end
        if holder.inside and not d.buff then EV.AuraContainer.Hide(holder.inside) end
    end
    for key in pairs(known) do
        if not now[key] then
            known[key] = nil
            M.DropHolder(key)
        end
    end
    if M:IsEnabled() then M:LayoutAll() end
end

--- The one Your buffs bar of before becomes a buff bar of yours, keeping its
--- settings and its place on screen.
local function MoveOldBuffs()
    local _, class = UnitClass("player")
    local old = class and M.db.myBuffs[class]
    if type(old) ~= "table" or #old == 0 then return end
    local b = M:NewBar("buffs", L["Your buffs"])
    b.buffs = old
    M.db.myBuffs[class] = nil
    local was = rawget(M.db.bars, "mine")
    if type(was) == "table" then
        for k, v in pairs(was) do M.db.bars["u:" .. b.id][k] = v end
        M.db.bars.mine = nil
    end
    local core = EV.DB and EV.DB:GetCore()
    if core and core.movers and core.movers.CD_mine then
        core.movers["CD_u:" .. b.id] = core.movers.CD_mine
        core.movers.CD_mine = nil
    end
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
function ns.EnableCustom()
    MoveOldBuffs()
    ns.SyncUserBars()
    ns.SyncCustom()
    if ns.customEvents then return end   -- enabled again: already listening
    ns.customEvents = true

    -- Our own event frame: the module keeps one handler per event, and
    -- Cooldowns.lua already has SPELLS_CHANGED and PLAYER_ENTERING_WORLD.
    local queued = false
    local function Resync()
        if queued then return end
        queued = true
        C_Timer.After(0.2, function()
            queued = false
            if M:IsEnabled() then ns.SyncUserBars(); ns.SyncCustom() end
        end)
    end
    local COOLDOWN = { SPELL_UPDATE_COOLDOWN = true, SPELL_UPDATE_CHARGES = true,
                       BAG_UPDATE_COOLDOWN = true, ACTIONBAR_UPDATE_COOLDOWN = true }
    local RESYNC = { PLAYER_EQUIPMENT_CHANGED = true, GET_ITEM_INFO_RECEIVED = true, SPELLS_CHANGED = true,
                     LEARNED_SPELL_IN_TAB = true, PLAYER_ENTERING_WORLD = true }
    local lastLearn = 0
    local ev = CreateFrame("Frame")
    for e in pairs(COOLDOWN) do pcall(ev.RegisterEvent, ev, e) end
    for e in pairs(RESYNC) do pcall(ev.RegisterEvent, ev, e) end
    pcall(ev.RegisterEvent, ev, "BAG_UPDATE_DELAYED")
    pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
    ev:SetScript("OnEvent", function(_, event)
        if not M:IsEnabled() then return end
        if COOLDOWN[event] then
            UpdateAllCooldowns()
        elseif RESYNC[event] then
            Resync()
        elseif event == "BAG_UPDATE_DELAYED" then
            UpdateCounts()
        elseif event == "UNIT_AURA" then
            -- A new rank of a named buff seen on you joins its bar's filter.
            local now = GetTime()
            if now - lastLearn < 1 then return end
            lastLearn = now
            if Learn() then ns.LayoutMine() end
        end
    end)
end

--------------------------------------------------------------------------------
--  /evui cdprobe <spell or item>: what the cooldown calls return here, and
--  whether it's secret. For checking a client before relying on a call.
--------------------------------------------------------------------------------
local function Show(v)
    if v == nil then return "nil" end
    if issecret(v) then return "|cffff8040secret|r" end
    return tostring(v)
end

EV:RegisterSlash("cdprobe", function(rest)
    rest = strtrim(rest or "")
    local spell = M.ResolveSpell(rest)
    local item = M.ResolveItem(rest)
    EV:Print(("cdprobe %s  combat %s"):format(rest, tostring(InCombatLockdown())))
    if spell then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spell)
        if ok and type(info) == "table" then
            EV:Print(("  spell %d cooldown: start %s duration %s gcd %s"):format(spell, Show(info.startTime),
                Show(info.duration), Show(info.isOnGCD)))
        else
            EV:Print(("  spell %d cooldown: %s"):format(spell, tostring(info)))
        end
        EV:Print(("  duration object API: %s"):format(tostring(C_Spell.GetSpellCooldownDuration ~= nil)))
    end
    if item then
        local fn = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
        local ok, s, d, en = pcall(fn, item)
        EV:Print(("  item %d cooldown: start %s duration %s enabled %s count %s"):format(item, Show(ok and s),
            Show(ok and d), Show(ok and en), Show(ItemCount(item))))
    end
    for slot in pairs(TRINKETS) do
        local ok, s, d = pcall(GetInventoryItemCooldown, "player", slot)
        EV:Print(("  trinket %d: item %s start %s duration %s"):format(slot,
            tostring(GetInventoryItemID("player", slot)), Show(ok and s), Show(ok and d)))
    end
end)
