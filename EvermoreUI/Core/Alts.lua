if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Alts.lua
--  What each of your characters is and carries, readable from any of them:
--  who they are, their gold, rested XP, professions, and a count of every
--  item in their bags, bank, mailbox and on their back. Plus the account
--  bank, which belongs to all of them.
--
--  Everything is a snapshot, taken when the game lets us look:
--    info, gold, rested, professions   at login, on change, at logout
--    bags and equipped                 whenever the bags settle
--    character bank, account bank      while you are at a banker
--    mail                              while the mailbox is open, and
--                                      what you send an alt, as you send it
--  Each part records when it was taken, so the window can say how old it is.
--
--  Stored in the account-wide per-character store (DB:AllChars()), keyed
--  "Name - Realm":
--    chars[key].info  = { name, realm, class, race, faction, level, seen,
--                         money, rested, xpMax, zone, guild, played,
--                         profs = { { name, icon, rank, max }, ... } }
--    chars[key].items = { bags = {}, equipped = {}, bank = {}, mail = {},
--                         at = { bags, bank, mail } }   [itemID] = count
--    chars[key].mail  = { count, money, expires }      expires: epoch seconds
--  and in the global store:
--    accountBank      = { items = {}, money, at }
--
--  Other features add their own per-character tables beside these (loot
--  luck keeps "lootStats") and read them across characters with List().
--
--  Settings (global, account-wide): alts = { track = true, scope = "faction" }
--  scope decides whose items count: "faction" your faction on any realm,
--  "realm" your realm and faction, "all" every character.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local A = {}
EV.Alts = A

local time = time
local NUM_BAGS = NUM_BAG_SLOTS or 4
local MAIL_ATTACH = ATTACHMENTS_MAX_RECEIVE or 16
local SEND_ATTACH = ATTACHMENTS_MAX_SEND or 12
local BT = Enum.BankType or { Character = 0, Account = 2 }

A.version = 0            -- bumped on every change, for anything that caches
local countCache = {}    -- itemID -> result of Counts(), for this version

local function Changed(what)
    A.version = A.version + 1
    wipe(countCache)
    EV:SendMessage("EV_ALTS_CHANGED", what)
end

--- Something outside changed what counts (the scope): drop cached counts.
function A:Invalidate(what) Changed(what or "settings") end

function A:Settings()
    local g = EV.DB:GetGlobal()
    if type(g.alts) ~= "table" then g.alts = {} end
    local s = g.alts
    if s.track == nil then s.track = true end
    if s.scope ~= "realm" and s.scope ~= "all" then s.scope = "faction" end
    if s.mailWarn == nil then s.mailWarn = 3 end   -- days; 0 = never
    return s
end

local function Tracking()
    return EV.DB and EV.dbReady and A:Settings().track
end

local function Ready() return EV.DB and EV.dbReady end

--------------------------------------------------------------------------------
--  Recording: who you are
--------------------------------------------------------------------------------
local function Info() return EV.DB:GetCharData("info") end

local function Items()
    local t = EV.DB:GetCharData("items")
    for _, k in ipairs({ "bags", "equipped", "bank", "mail", "at" }) do
        if type(t[k]) ~= "table" then t[k] = {} end
    end
    return t
end

local function ReadProfessions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local out = {}
    local list = { GetProfessions() }
    for i = 1, 5 do
        local idx = list[i]
        if idx then
            local ok, name, icon, rank, max = pcall(GetProfessionInfo, idx)
            if ok and name then out[#out + 1] = { name = name, icon = icon, rank = rank, max = max } end
        end
    end
    return out
end

local function Record()
    if not Ready() then return end
    local info = Info()
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    info.name = UnitName("player")
    info.realm = GetRealmName()
    info.class = class
    info.race = race
    info.faction = UnitFactionGroup("player")
    info.level = UnitLevel("player")
    info.seen = time()
    if not Tracking() then return end
    info.money = GetMoney and GetMoney() or info.money
    info.rested = GetXPExhaustion and GetXPExhaustion() or 0
    info.xpMax = UnitXPMax and UnitXPMax("player") or info.xpMax
    info.zone = GetRealZoneText and GetRealZoneText() or info.zone
    info.guild = GetGuildInfo and GetGuildInfo("player") or nil
    local profs = ReadProfessions()
    if profs then info.profs = profs end
end
A.Record = Record

--------------------------------------------------------------------------------
--  Recording: what you carry
--------------------------------------------------------------------------------
local function Add(t, id, n)
    if id and n and n > 0 then t[id] = (t[id] or 0) + n end
end

local function ReadContainer(bag, into)
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
    if not (ok and slots and slots > 0) then return end
    for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID then Add(into, info.itemID, info.stackCount or 1) end
    end
end

local function ScanBags()
    if not Tracking() then return end
    local items = Items()
    local bags = {}
    for bag = 0, NUM_BAGS + 1 do ReadContainer(bag, bags) end   -- + 1: the reagent bag
    items.bags = bags
    local worn = {}
    for slot = 1, 19 do
        local id = GetInventoryItemID("player", slot)
        if id then Add(worn, id, 1) end
    end
    items.equipped = worn
    items.at.bags = time()
    Changed("bags")
end

local atBank = false

local function TabIDs(bankType)
    if not (C_Bank and C_Bank.FetchPurchasedBankTabIDs) then return nil end
    if C_Bank.CanViewBank then
        local ok, can = pcall(C_Bank.CanViewBank, bankType)
        if ok and not can then return nil end
    end
    local ok, ids = pcall(C_Bank.FetchPurchasedBankTabIDs, bankType)
    return ok and type(ids) == "table" and ids or nil
end

local function ScanBank()
    if not (atBank and Tracking()) then return end
    local items = Items()
    local bank = {}
    local ids = TabIDs(BT.Character)
    if ids and #ids > 0 then
        for _, bag in ipairs(ids) do ReadContainer(bag, bank) end
    else
        -- An older bank: the bank itself and its bag slots.
        if BANK_CONTAINER then ReadContainer(BANK_CONTAINER, bank) end
        for bag = NUM_BAGS + 2, NUM_BAGS + 1 + (NUM_BANKBAGSLOTS or 7) do ReadContainer(bag, bank) end
    end
    items.bank = bank
    items.at.bank = time()

    local acct = TabIDs(BT.Account)
    if acct then
        local g = EV.DB:GetGlobal()
        local store = { items = {}, at = time() }
        for _, bag in ipairs(acct) do ReadContainer(bag, store.items) end
        if C_Bank.FetchDepositedMoney then
            local ok, money = pcall(C_Bank.FetchDepositedMoney, BT.Account)
            if ok and EV.Usable(money) then store.money = money end
        end
        g.accountBank = store
    end
    Changed("bank")
end

--- The mailbox as it is now: what's attached, the gold in it, and when the
--- first letter runs out.
local function ScanMail()
    if not (Tracking() and GetInboxNumItems) then return end
    local items = Items()
    local mail = {}
    local count, money, expires = 0, 0, nil
    local n = GetInboxNumItems() or 0
    for i = 1, n do
        local _, _, _, _, m, cod, days, has = GetInboxHeaderInfo(i)
        count = count + 1
        if m and m > 0 then money = money + m end
        if days then
            local at = time() + math.floor(days * 86400)
            if not expires or at < expires then expires = at end
        end
        if has and (not cod or cod == 0) then
            for a = 1, MAIL_ATTACH do
                local _, id, _, qty = GetInboxItem(i, a)
                if id then Add(mail, id, qty or 1) end
            end
        end
    end
    items.mail = mail
    items.at.mail = time()
    local m = EV.DB:GetCharData("mail")
    m.count, m.money, m.expires = count, money, expires
    Changed("mail")
end

--------------------------------------------------------------------------------
--  Mail you send to your own characters: it lands in their mailbox as far as
--  we're concerned, so their counts are right before they ever log in.
--------------------------------------------------------------------------------
local outgoing

local function KeyForName(name)
    if not name or name == "" then return nil end
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    short = short or name
    realm = realm or GetRealmName()
    local want = short:lower()
    for key, data in pairs(EV.DB:AllChars()) do
        local info = type(data) == "table" and data.info
        if info and info.name and info.name:lower() == want
           and (info.realm or ""):gsub("%s", "") == realm:gsub("%s", "") then
            return key
        end
    end
end

local function OnSendMail(recipient)
    outgoing = nil
    if not Tracking() then return end
    local key = KeyForName(recipient)
    if not key or key == EV.DB.charKey then return end
    local list = {}
    for a = 1, SEND_ATTACH do
        local _, id, _, qty = GetSendMailItem(a)
        if id then list[#list + 1] = { id, qty or 1 } end
    end
    local money = GetSendMailMoney and GetSendMailMoney() or 0
    if #list > 0 or money > 0 then outgoing = { key = key, items = list, money = money } end
end

local function OnMailSent()
    local o = outgoing
    outgoing = nil
    if not o then return end
    local data = EV.DB:AllChars()[o.key]
    if type(data) ~= "table" then return end
    data.items = type(data.items) == "table" and data.items or {}
    data.items.mail = type(data.items.mail) == "table" and data.items.mail or {}
    for _, it in ipairs(o.items) do Add(data.items.mail, it[1], it[2]) end
    data.mail = type(data.mail) == "table" and data.mail or {}
    data.mail.count = (data.mail.count or 0) + 1
    data.mail.money = (data.mail.money or 0) + (o.money or 0)
    -- Mail between your own characters keeps for 30 days.
    local at = time() + 30 * 86400
    if not data.mail.expires or at < data.mail.expires then data.mail.expires = at end
    Changed("mail")
end

--------------------------------------------------------------------------------
--  Reading
--------------------------------------------------------------------------------
--- Every known character: { key, info, data, me }, optionally filtered.
--- opts.faction = "same" keeps your own faction; opts.realm = "same" your
--- realm; opts.scope = "faction" | "realm" | "all" does both from a setting.
function A:List(opts)
    opts = opts or {}
    local me = EV.DB.charKey
    local myFaction = UnitFactionGroup("player")
    local myRealm = GetRealmName()
    local faction, realm = opts.faction, opts.realm
    if opts.scope == "faction" then faction = "same"
    elseif opts.scope == "realm" then faction, realm = "same", "same" end
    local out = {}
    for key, data in pairs(EV.DB:AllChars()) do
        local info = type(data) == "table" and data.info
        if type(info) == "table" and info.name then
            local ok = true
            if faction == "same" and info.faction and info.faction ~= myFaction then ok = false end
            if realm == "same" and info.realm ~= myRealm then ok = false end
            if ok then out[#out + 1] = { key = key, info = info, data = data, me = key == me } end
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if (a.info.level or 0) ~= (b.info.level or 0) then return (a.info.level or 0) > (b.info.level or 0) end
        return (a.info.name or "") < (b.info.name or "")
    end)
    return out
end

local PLACES = { "bags", "bank", "mail", "equipped" }
A.PLACES = PLACES

--- How many of an item each character has, and where.
--- Returns { total, account = n, chars = { { entry, total, bags, bank, mail, equipped }, ... } }
--- using the scope setting. Cached until anything changes.
function A:Counts(itemID)
    if not (itemID and Ready()) then return nil end
    local hit = countCache[itemID]
    if hit then return hit end
    local res = { total = 0, account = 0, chars = {} }
    for _, e in ipairs(self:List({ scope = self:Settings().scope })) do
        local items = e.data.items
        if type(items) == "table" then
            local row, sum = { entry = e }, 0
            for _, place in ipairs(PLACES) do
                local n = type(items[place]) == "table" and items[place][itemID] or 0
                if n > 0 then row[place] = n; sum = sum + n end
            end
            if sum > 0 then
                row.total = sum
                res.total = res.total + sum
                res.chars[#res.chars + 1] = row
            end
        end
    end
    local ab = EV.DB:GetGlobal().accountBank
    if type(ab) == "table" and type(ab.items) == "table" then
        res.account = ab.items[itemID] or 0
        res.total = res.total + res.account
    end
    countCache[itemID] = res
    return res
end

--- Gold across characters in scope, plus the account bank's.
function A:Money()
    local list = self:List({ scope = self:Settings().scope })
    local total = 0
    for _, e in ipairs(list) do total = total + (e.info.money or 0) end
    local ab = EV.DB:GetGlobal().accountBank
    local bank = type(ab) == "table" and ab.money or 0
    return total + bank, list, bank
end

--- Every item ID anyone has, for searching.
function A:AllItemIDs()
    local seen = {}
    for _, e in ipairs(self:List({ scope = self:Settings().scope })) do
        local items = e.data.items
        if type(items) == "table" then
            for _, place in ipairs(PLACES) do
                if type(items[place]) == "table" then
                    for id in pairs(items[place]) do seen[id] = true end
                end
            end
        end
    end
    local ab = EV.DB:GetGlobal().accountBank
    if type(ab) == "table" and type(ab.items) == "table" then
        for id in pairs(ab.items) do seen[id] = true end
    end
    return seen
end

function A:AccountBank()
    local ab = EV.DB:GetGlobal().accountBank
    return type(ab) == "table" and ab or nil
end

--- Forget a character (not the one you're on).
function A:Forget(key)
    local ok = EV.DB:ForgetChar(key)
    if ok then Changed("forget") end
    return ok
end

--- "|cffRRGGBBName|r" in the character's class colour.
function A:Coloured(info)
    local r, g, b = EV.Palette.ClassRGB(info and info.class)
    local name = info and info.name or "?"
    if not r then return name end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, name)
end

--- "3 days ago", "2 hours ago", "just now".
function A.Ago(t)
    if not t then return L["never"] end
    local d = time() - t
    if d < 90 then return L["just now"] end
    if d < 5400 then return (L["%d minutes ago"]):format(math.floor(d / 60 + 0.5)) end
    if d < 129600 then return (L["%d hours ago"]):format(math.floor(d / 3600 + 0.5)) end
    return (L["%d days ago"]):format(math.floor(d / 86400 + 0.5))
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local pending = {}
local function Soon(what, fn, delay)
    if pending[what] then return end
    pending[what] = true
    C_Timer.After(delay or 0.4, function()
        pending[what] = nil
        fn()
    end)
end

--- Mail about to run out on any of your characters: one line at login.
local function MailWarning()
    local s = A:Settings()
    if not s.track or (s.mailWarn or 0) <= 0 then return end
    local soon = time() + s.mailWarn * 86400
    for _, e in ipairs(A:List()) do
        local m = e.data.mail
        if type(m) == "table" and m.expires and (m.count or 0) > 0 and m.expires < soon then
            local days = math.max(0, math.floor((m.expires - time()) / 86400))
            EV:Print((L["Mail on %s runs out in %d |4day:days;."]):format(A:Coloured(e.info), days))
        end
    end
end

local ev = CreateFrame("Frame")
local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
for _, e in ipairs({
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "PLAYER_UPDATE_RESTING",
    "UPDATE_EXHAUSTION", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED", "TIME_PLAYED_MSG",
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
    "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED",
    "MAIL_INBOX_UPDATE", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
}) do Reg(e) end

ev:SetScript("OnEvent", function(_, event, a1, a2)
    if not Ready() then return end
    if event == "PLAYER_LOGIN" then
        Record()
        C_Timer.After(2, ScanBags)
        C_Timer.After(8, MailWarning)
    elseif event == "PLAYER_LOGOUT" then
        Record()
    elseif event == "PLAYER_LEVEL_UP" then
        -- PLAYER_LEVEL_UP carries the new level before UnitLevel catches up.
        C_Timer.After(1, Record)
    elseif event == "TIME_PLAYED_MSG" then
        if Tracking() then Info().played = a1; Info().playedAt = time() end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        Soon("bags", ScanBags)
        if atBank then Soon("bank", ScanBank) end
    elseif event == "BANKFRAME_OPENED" then
        atBank = true
        Soon("bank", ScanBank, 0.5)
    elseif event == "BANKFRAME_CLOSED" then
        if atBank then ScanBank() end
        atBank = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED"
        or event == "BANK_TABS_CHANGED" then
        if atBank then Soon("bank", ScanBank) end
    elseif event == "MAIL_INBOX_UPDATE" then
        Soon("mail", ScanMail)
    elseif event == "MAIL_SEND_SUCCESS" then
        OnMailSent()
    elseif event == "MAIL_FAILED" then
        outgoing = nil
    else
        Soon("info", function() Record(); Changed("info") end, 1)
    end
end)

-- Read straight after SendMail is called: the attachments stay in the send
-- slots until the server confirms (MAIL_SEND_SUCCESS), and only count once
-- it has.
if SendMail then hooksecurefunc("SendMail", function(recipient) pcall(OnSendMail, recipient) end) end
