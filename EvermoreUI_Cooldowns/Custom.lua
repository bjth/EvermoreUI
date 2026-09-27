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
--  Your buffs: a fourth bar of the buffs you name, drawn by the engine's aura
--  container (EV.AuraContainer), which filters in its own secure code and so
--  keeps working in combat. It matches by spell ID, and every rank of a buff
--  has its own, so each name brings in every rank in your spellbook plus any
--  rank seen on you (remembered in the entry's `seen`).
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
function M:MyBuffs() return ClassList("myBuffs") end

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
--  Your buffs
--------------------------------------------------------------------------------
local MINE = { key = "mine", label = L["Your buffs"], buff = true, own = true,
               pos = { "CENTER", "CENTER", 0, -100 } }
ns.MINE = MINE
local mine          -- the bar's frame (edit mode moves it)
local inside        -- the container's holder, inside the bar

function M.AddMyBuff(text)
    if type(text) ~= "string" and type(text) ~= "number" then return nil end
    local spell = tonumber(text) or (type(text) == "string" and tonumber(text:match("spell:(%d+)")))
    if not spell then
        spell = strtrim(tostring(text))
        if spell == "" then return nil end
    end
    local list = M:MyBuffs()
    local name = type(spell) == "number" and SpellName(spell) or spell
    for _, e in ipairs(list) do
        local en = type(e.spell) == "number" and SpellName(e.spell) or e.spell
        if en and name and en:lower() == name:lower() then return e end
    end
    local e = { spell = spell, seen = {} }
    list[#list + 1] = e
    return e
end

function M.RemoveMyBuff(i)
    table.remove(M:MyBuffs(), i)
end

function M.MyBuffName(e)
    if type(e.spell) == "number" then return SpellName(e.spell) or ("#" .. e.spell) end
    return e.spell
end

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

--- The spell IDs the bar lets through, as a set, and how many buffs that is.
local function MineIDs()
    local ids, n = {}, 0
    for _, e in ipairs(M:MyBuffs()) do
        n = n + 1
        if type(e.spell) == "number" then ids[e.spell] = true end
        local name = M.MyBuffName(e)
        if name then
            BookIDs(name, ids)
            local ok, info = pcall(C_Spell.GetSpellInfo, name)
            if ok and type(info) == "table" and Plain(info.spellID) then ids[info.spellID] = true end
        end
        for id in pairs(e.seen or {}) do ids[id] = true end
    end
    return ids, n
end

--- Out of combat, note the rank IDs of your named buffs that are on you.
local function Learn()
    if InCombatLockdown() then return false end
    local list = M:MyBuffs()
    if #list == 0 then return false end
    local byName = {}
    for _, e in ipairs(list) do
        local name = M.MyBuffName(e)
        if name then byName[name:lower()] = e end
    end
    local learnt = false
    for i = 1, 40 do
        local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not a then break end
        if Plain(a.name) and Plain(a.spellId) then
            local e = byName[a.name:lower()]
            if e then
                e.seen = e.seen or {}
                if not e.seen[a.spellId] then e.seen[a.spellId] = true; learnt = true end
            end
        end
    end
    return learnt
end

function ns.LayoutMine()
    if not mine then return end
    local db = M.db.bars.mine
    local ids, n = MineIDs()
    local C = EV.AuraContainer
    if not (M:IsEnabled() and db.enabled and n > 0 and next(ids) and C and C.Supported()) then
        mine:SetSize(40, 20)
        if inside then C.Hide(inside) end
        mine:SetAlpha(0)
        return
    end
    local cfg = {
        size = db.size, spacing = db.spacing, perRow = max(1, db.perRow), max = min(n, 16),
        growX = db.grow == "LEFT" and "LEFT" or "RIGHT", growY = db.rows == "UP" and "UP" or "DOWN",
        showSwipe = true, showTimer = true, timerSize = max(9, floor(db.size * 0.36 + 0.5)),
    }
    local w, h = C.BoxSize(cfg)
    EV.Pixel:SetSize(mine, w, h)
    inside:SetAllPoints(mine)
    -- A container only changes shape out of combat; in combat the one
    -- already built carries on.
    if not (InCombatLockdown() and inside.container) then
        C.Build(inside, cfg, { unit = "player", filter = "HELPFUL", include = ids })
    end
    local alpha = M.Opacity(db)
    mine:SetAlpha(alpha or 0)
end

--------------------------------------------------------------------------------
--  Wiring
--------------------------------------------------------------------------------
function ns.EnableCustom()
    if not mine then
        mine = CreateFrame("Frame", "EvermoreUICooldowns_mine", UIParent)
        mine:SetSize(40, 20)
        inside = CreateFrame("Frame", nil, mine)
        inside:SetAllPoints()
        EV.Movers:Register(mine, "CD_mine", MINE.label, MINE.pos, {
            group = L["Combat"], page = "cooldowns", designer = "cooldowns",
            isDisabled = function()
                return not (M:IsEnabled() and M.db.bars.mine.enabled and #M:MyBuffs() > 0)
            end,
        })
    end
    ns.SyncCustom()
    if ns.customEvents then return end   -- enabled again: already listening
    ns.customEvents = true

    -- Our own event frame: the module keeps one handler per event, and
    -- Cooldowns.lua already has SPELLS_CHANGED and PLAYER_ENTERING_WORLD.
    local queued = false
    local function Resync()
        if queued then return end
        queued = true
        C_Timer.After(0.2, function() queued = false; if M:IsEnabled() then ns.SyncCustom() end end)
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
            -- A new rank of a named buff seen on you joins the bar's filter.
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
