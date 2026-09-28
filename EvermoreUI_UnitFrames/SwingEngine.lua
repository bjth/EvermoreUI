if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  SwingEngine.lua
--  When each of your weapons will next swing, and what the bar should know
--  about it. No frames: SwingTimer.lua draws, and so can anything else that
--  registers a layer (see LAYERS at the end).
--
--  THE CLOCK. Addons lost the combat log in 12.0, so the old recipe (time
--  SWING_DAMAGE / SWING_MISSED) is gone. Forever ships the answer natively,
--  and Blizzard's own hidden timer (Blizzard_SwingTimer, AllowLoadGameType
--  camelot) is built on it:
--      PLAYER_SWING(swingDuration, swingType)        one per swing you make
--      C_SwingTimer.EnableRangeCheck(swingType, on)   opt in to range events
--      PLAYER_SWING_RANGE_UPDATE(type, inRange, checksRange)
--      C_SwingTimer.IsTargetWithinSwingRange(type)    nil = no check possible
--  A swing starts on PLAYER_SWING and lasts the length it announces. That is
--  all Blizzard's bar does, and it is where ours starts.
--
--  WHAT BLIZZARD'S BAR ALSO DOES. A weapon swap restarts the swing at the
--  new weapon's speed (ResetSwingTimerForEquippedWeapon on
--  WEAPON_SLOT_CHANGED). In combat the attack speed can be secret, so each
--  weapon's base speed is read from its tooltip and kept per item (bag
--  weapons are read out of combat, since swap macros pull from there), and
--  the haste on top is learned from real swings.
--
--  WHAT IT DOESN'T: two rules that can move a swing already running.
--      parry   you parry: the swing loses 40% of the weapon speed, but never
--              drops below 20% of it (and is never lengthened). Main hand.
--              Seen through UNIT_COMBAT("player", "PARRY").
--      haste   your attack speed changes: the rest of the swing scales.
--  Neither is documented for Forever's servers, so neither moves the bar on
--  faith. The accuracy guard: a rule that would move a swing always keeps
--  that move as a prediction; when the swing lands, its arrival shows which
--  was right, the rule or the plain length. Two confirmations in a row and
--  the rule moves the bar; one contradiction puts it back on Blizzard's
--  timing until it earns them again. Only telling swings count: one rule at
--  work, the two predictions far enough apart to tell apart, and nothing
--  that can hold a swing back (a cast with a cast time, a stun, a target
--  switch, leaving range, toggling auto attack). The record is account-wide
--  and starts over with each game build, since server rules move with
--  patches.
--
--  ALSO KEPT: whether auto attack is on (PLAYER_ENTER_COMBAT and
--  PLAYER_LEAVE_COMBAT are its toggle), the global cooldown from your own
--  casts, range per weapon, and your world latency.
--
--  Nothing secret is ever compared: every read goes through pcall and a
--  secrecy check, and a secret simply leaves the last plain answer in place.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not EvermoreUI then return end
local EV = EvermoreUI
local abs, floor, max, min = math.abs, math.floor, math.max, math.min
local issecret = issecretvalue or function() return false end

local SWING = Enum and Enum.PlayerSwingType
if not (C_SwingTimer and SWING) then return end

local E = {}
EV.Swing = E          -- public: class layers and other addons build on this
ns.SwingEngine = E

local MH, OH, RANGED = SWING.MainHand, SWING.OffHand, SWING.Ranged
E.MAIN_HAND, E.OFF_HAND, E.RANGED = MH, OH, RANGED
E.TYPES = { MH, OH, RANGED }

local SLOT = { [MH] = 16, [OH] = 17, [RANGED] = 18 }
local AUTO_ATTACK = 6603
local GCD_SPELL = 61304

--- A value that can be used: not secret. Anything else comes back nil.
local function Plain(v)
    if issecret(v) then return nil end
    return v
end

--- pcall that hands back only plain values (up to four).
local function Read(fn, ...)
    if not fn then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return Plain(a), Plain(b), Plain(c), Plain(d)
end
E.Read, E.Plain = Read, Plain

--------------------------------------------------------------------------------
--  State
--------------------------------------------------------------------------------
-- One per swing type. `baseEnds` is Blizzard's view of the swing (its start
-- plus the length PLAYER_SWING announced); `ends` and `duration` are what
-- the bar shows, and differ from it only through a rule the guard trusts.
local function NewSwing()
    return { start = nil, duration = 0, ends = 0, baseEnds = 0, speed = nil, count = 0 }
end

E.swings = { [MH] = NewSwing(), [OH] = NewSwing(), [RANGED] = NewSwing() }
E.inRange = {}                    -- type -> true / false / nil (no check possible)
E.attacking = false               -- auto attack toggled on
E.inCombat = false
E.gcd = { start = 0, duration = 0, ends = 0 }
E.lag = 0                         -- world latency, seconds
E.weaponBase = {}                 -- item id -> base speed from its tooltip
E.weaponID = {}                   -- type -> equipped item id
E.haste = {}                      -- type -> actual speed / base speed

local running = false
local opts = function() return nil end   -- settings table, from Configure

--- Where the engine reads its switches: parryHaste, hasteRescale.
function E:Configure(getter) opts = getter end

local function Opt(key, default)
    local db = opts()
    if not db or db[key] == nil then return default end
    return db[key]
end

--------------------------------------------------------------------------------
--  Callbacks
--  E:On(event, fn) -> fn(event, ...). Events:
--    swing(type, duration)      a swing began (the last one landed)
--    moved(type)                a running swing was moved (rule, swap)
--    parry()                    you parried
--    cast(spellID, gcd)         you cast something (gcd in seconds, 0 = none)
--    attack(on)                 auto attack switched on or off
--    combat(on)                 entered or left combat
--    range(type, inRange)       range for a weapon changed
--    rule(rule, confirmed)      the accuracy guard judged a swing
--    target()                   your target changed
--  Listeners are called through pcall: one that errors can't stop the rest.
--------------------------------------------------------------------------------
local listeners = {}

function E:On(event, fn)
    listeners[event] = listeners[event] or {}
    local list = listeners[event]
    list[#list + 1] = fn
end

function E:Off(event, fn)
    local list = listeners[event]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
end

local function Fire(event, ...)
    local list = listeners[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok and EV.debug then EV:Print("swing listener (" .. event .. "): " .. tostring(err)) end
    end
end
E.Fire = Fire

--------------------------------------------------------------------------------
--  Queries
--------------------------------------------------------------------------------
--- The swing record for a type (read only, please).
function E:Get(swingType) return self.swings[swingType] end

--- Whether that weapon's swing is under way (or only just landed).
function E:IsSwinging(swingType, now)
    local sw = self.swings[swingType]
    return sw and sw.start ~= nil and (now or GetTime()) < sw.ends or false
end

--- Seconds to the next swing, 0 when none is due.
function E:Remaining(swingType, now)
    local sw = self.swings[swingType]
    if not (sw and sw.start) then return 0 end
    return max(0, sw.ends - (now or GetTime()))
end

--- 0..1 through the running swing, nil when none is running.
function E:Progress(swingType, now)
    local sw = self.swings[swingType]
    if not (sw and sw.start) or sw.duration <= 0 then return nil end
    return min(1, max(0, ((now or GetTime()) - sw.start) / (sw.ends - sw.start)))
end

--- Where a moment falls along the running swing, 0..1 (unclamped), nil when
--- no swing is running.
function E:FractionAt(swingType, at)
    local sw = self.swings[swingType]
    if not (sw and sw.start) then return nil end
    local len = sw.ends - sw.start
    if len <= 0 then return nil end
    return (at - sw.start) / len
end

--- true / false, or nil when no check is possible (no target, say). nil is
--- NOT out of range.
function E:InRange(swingType) return self.inRange[swingType] end

--- Seconds of global cooldown left, 0 when free.
function E:GCDRemaining(now) return max(0, self.gcd.ends - (now or GetTime())) end

--------------------------------------------------------------------------------
--  Accuracy guard
--------------------------------------------------------------------------------
local CONFIRMATIONS = 2
local MIN_GAP = 0.25     -- seconds between the two predictions for a swing to be telling
local MAX_TOL = 0.12     -- how close the landing must be to a prediction (network jitter)
E.CONFIRMATIONS = CONFIRMATIONS
E.RULES = { "parry", "haste" }

local spareBook = {}     -- until the saved variables are up
local function Book()
    local g = EV.DB and EV.DB.GetGlobal and EV.DB:GetGlobal()
    if not g then return spareBook end
    local version, build = Read(GetBuildInfo)
    local key = tostring(version or "?") .. " " .. tostring(build or "?")
    if type(g.swingRules) ~= "table" or g.swingRules.build ~= key then
        g.swingRules = { build = key }
    end
    return g.swingRules
end

function E:Ledger(rule)
    local book = Book()
    local r = book[rule]
    if type(r) ~= "table" then
        r = { streak = 0, yes = 0, no = 0 }
        book[rule] = r
    end
    return r
end

function E:Trusted(rule)
    return self:Ledger(rule).streak >= CONFIRMATIONS
end

local function Record(rule, confirmed)
    local r = E:Ledger(rule)
    if confirmed then
        r.yes = r.yes + 1
        r.streak = min(r.streak + 1, 99)
    else
        r.no = r.no + 1
        r.streak = 0
    end
    r.last = confirmed
    Fire("rule", rule, confirmed)
end

--- "in use", "testing" or "not in use", with the counts behind it.
function E:RuleState(rule)
    local r = self:Ledger(rule)
    if r.streak >= CONFIRMATIONS then return "in use", r end
    if r.last == false then return "not in use", r end
    return "testing", r
end

--- Something that can hold a swing back happened: the running swing (of
--- one type, or all) proves nothing.
function E:Disturb(swingType)
    if swingType then
        self.swings[swingType].disturbed = true
    else
        for _, sw in pairs(self.swings) do sw.disturbed = true end
    end
end

-- A rule moves a running swing: move(ends, duration, now) returns the moved
-- end and length. The prediction always follows; the bar only once trusted.
local function ApplyRule(swingType, rule, move)
    local sw = E.swings[swingType]
    if not sw.start then return end
    local now = GetTime()
    if now >= sw.ends then return end
    sw.shadow = sw.shadow or {}
    sw.shadow[rule] = (move(sw.shadow[rule] or sw.baseEnds, sw.duration, now))
    if E:Trusted(rule) then
        sw.ends, sw.duration = move(sw.ends, sw.duration, now)
        Fire("moved", swingType)
    end
end

-- The swing that was running landed at `now`, and the next lasts
-- `nextLength`: which prediction was right?
local function Judge(sw, now, nextLength)
    if sw.disturbed or not sw.shadow or not sw.start then return end
    -- The speed changed while secret: harmless only if the next swing is as long.
    if sw.speedHidden and not (sw.speed and abs(nextLength - sw.speed) < 0.004) then return end
    local rule, predicted = next(sw.shadow)
    if next(sw.shadow, rule) ~= nil then return end   -- two rules at work: no telling them apart
    local gap = abs(predicted - sw.baseEnds)
    if gap < MIN_GAP then return end
    local tol = min(MAX_TOL, gap / 3)
    if abs(now - predicted) <= tol then
        Record(rule, true)
    elseif abs(now - sw.baseEnds) <= tol then
        Record(rule, false)
    end
end

--------------------------------------------------------------------------------
--  Weapon speeds
--------------------------------------------------------------------------------
--- ok, speed for a type, exactly as the game gave it (it may be secret).
--- Ranged: UnitAttackSpeed's third return where the client has one, else
--- UnitRangedDamage's speed.
function E.RawSpeed(swingType)
    local ok, mh, oh, ranged = pcall(UnitAttackSpeed, "player")
    if swingType == MH then return ok, mh end
    if swingType == OH then return ok, oh end
    if ok and ranged ~= nil then return ok, ranged end
    local ok2, speed = pcall(UnitRangedDamage, "player")
    return ok2, speed
end

-- Readable attack speed per type, or nil (secret, or no such weapon).
local function ReadSpeed(swingType)
    local ok, v = E.RawSpeed(swingType)
    v = ok and Plain(v) or nil
    return type(v) == "number" and v > 0 and v or nil
end
E.ReadSpeed = ReadSpeed

local speedPattern
local function TooltipSpeed(data)
    if type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
    if not speedPattern then
        local label = (type(SPEED) == "string" and SPEED ~= "") and SPEED or "Speed"
        speedPattern = label:gsub("%p", "%%%0") .. "%s*(%d+[%.,]%d+)"
    end
    for _, line in ipairs(data.lines) do
        if type(line) == "table" then
            for _, key in ipairs({ "rightText", "leftText" }) do
                local text = Plain(line[key])
                local n = type(text) == "string" and text:match(speedPattern)
                n = n and tonumber((n:gsub(",", ".")))
                if n and n > 0 then return n end
            end
        end
    end
    return nil
end

local function EquippedID(swingType)
    local id = Read(GetInventoryItemID, "player", SLOT[swingType])
    return type(id) == "number" and id or nil
end

local function BaseSpeed(swingType, id)
    if not id then return nil end
    if E.weaponBase[id] then return E.weaponBase[id] end
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local s = TooltipSpeed(Read(C_TooltipInfo.GetInventoryItem, "player", SLOT[swingType]))
    if s then E.weaponBase[id] = s end
    return s
end

-- A real speed is known (readable, or a swing's own length): note the haste
-- on top of the weapon's base speed.
local function NoteSpeed(swingType, speed)
    local base = BaseSpeed(swingType, E.weaponID[swingType])
    if base and type(speed) == "number" and speed > 0 then E.haste[swingType] = speed / base end
end

local WEAPON_EQUIP = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

--- Out of combat: the base speed of every weapon in your bags.
function E:ScanWeapons()
    for _, t in ipairs(self.TYPES) do
        self.weaponID[t] = EquippedID(t)
        BaseSpeed(t, self.weaponID[t])
    end
    if self.inCombat or not (C_Container and C_TooltipInfo and C_TooltipInfo.GetBagItem and C_Item) then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = Read(C_Container.GetContainerNumSlots, bag) or 0
        for slot = 1, slots do
            local id = Read(C_Container.GetContainerItemID, bag, slot)
            if type(id) == "number" and not self.weaponBase[id] then
                local _, _, _, equip = Read(C_Item.GetItemInfoInstant, id)
                if equip and WEAPON_EQUIP[equip] then
                    local s = TooltipSpeed(Read(C_TooltipInfo.GetBagItem, bag, slot))
                    if s then self.weaponBase[id] = s end
                end
            end
        end
    end
end

-- The speed a freshly equipped weapon swings at: readable, or base x haste.
local function SpeedAfterSwap(swingType)
    local speed = ReadSpeed(swingType)
    if speed then NoteSpeed(swingType, speed); return speed, true end
    local base = BaseSpeed(swingType, E.weaponID[swingType])
    if base then return base * (E.haste[swingType] or 1), false end
    return nil, false
end

--------------------------------------------------------------------------------
--  Handlers
--------------------------------------------------------------------------------
local function OnSwing(dur, swingType)
    swingType = Plain(swingType)
    local sw = swingType and E.swings[swingType]
    if not sw then return end
    local estimated = false
    dur = Plain(dur)
    if type(dur) ~= "number" or dur <= 0 then
        -- PLAYER_SWING is documented as never secret. Should that change,
        -- keep time with the last known length (and never judge it).
        dur, estimated = sw.speed, true
    end
    if type(dur) ~= "number" or dur <= 0 then return end
    local now = GetTime()
    Judge(sw, now, dur)
    sw.start, sw.duration, sw.ends, sw.baseEnds = now, dur, now + dur, now + dur
    if not estimated then sw.speed = dur; NoteSpeed(swingType, dur) end
    sw.shadow, sw.disturbed, sw.speedHidden = nil, estimated, nil
    sw.count = sw.count + 1
    E:UpdateLag()
    Fire("swing", swingType, dur)
end

local function OnParry()
    if not Opt("parryHaste", true) then E:Disturb(MH); return end
    local sw = E.swings[MH]
    local speed = sw.speed or sw.duration
    if not speed or speed <= 0 then return end
    ApplyRule(MH, "parry", function(ends, duration, now)
        local remaining = ends - now
        if remaining <= 0 then return ends, duration end
        local left = max(remaining - 0.4 * speed, 0.2 * speed)
        if left < remaining then return now + left, duration end
        return ends, duration
    end)
    Fire("parry")
end

local function OnAttackSpeed()
    for _, t in ipairs({ MH, OH }) do
        local sw = E.swings[t]
        local new = ReadSpeed(t)
        if not new then
            if sw.start then sw.speedHidden = true end   -- judged by the next swing's length
        else
            if sw.speed and abs(new - sw.speed) >= 0.004 and sw.start then
                if not Opt("hasteRescale", true) then
                    E:Disturb(t)
                else
                    local factor = new / sw.speed
                    ApplyRule(t, "haste", function(ends, duration, now)
                        if ends <= now then return ends, duration end
                        return now + (ends - now) * factor, duration * factor
                    end)
                end
            end
            sw.speed = new
            NoteSpeed(t, new)
        end
    end
end

-- Equipment changed: any weapon slot that now holds a different item
-- restarts its swing at the new weapon's speed, as the game does.
local function OnWeapons()
    local now = GetTime()
    for _, t in ipairs(E.TYPES) do
        local id = EquippedID(t)
        if id ~= E.weaponID[t] then
            E.weaponID[t] = id
            local sw = E.swings[t]
            sw.disturbed = true
            local speed, known = SpeedAfterSwap(t)
            if id and sw.start and now < sw.ends + 1 then
                local length = speed or sw.speed
                if length and length > 0 then
                    sw.start, sw.duration, sw.ends, sw.baseEnds = now, length, now + length, now + length
                    sw.shadow = nil
                    sw.speed = length
                    sw.speedHidden = not known or nil
                    Fire("moved", t)
                end
            elseif speed then
                sw.speed = speed
            end
        end
    end
end

-- Global cooldown a spell starts, seconds (0 = none or unknown), cached.
local gcdOf = {}
local function GCDOf(spellID)
    if gcdOf[spellID] == nil then
        local gcd = 0
        if spellID ~= AUTO_ATTACK then
            local _, gcdMS = Read(GetSpellBaseCooldown, spellID)
            if type(gcdMS) == "number" and gcdMS > 0 then gcd = gcdMS / 1000 end
        end
        gcdOf[spellID] = gcd
    end
    return gcdOf[spellID]
end

local function OnCast(spellID)
    spellID = Plain(spellID)
    if type(spellID) ~= "number" then return end
    local gcd = GCDOf(spellID)
    if gcd > 0 then
        local now = GetTime()
        E.gcd.start, E.gcd.duration, E.gcd.ends = now, gcd, now + gcd
    end
    Fire("cast", spellID, gcd)
end

-- The game's own GCD refines the estimate whenever it is readable.
local function OnCooldowns()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local ok, info = pcall(C_Spell.GetSpellCooldown, GCD_SPELL)
    if not ok or type(info) ~= "table" or issecret(info) then return end
    local start, dur = Plain(info.startTime), Plain(info.duration)
    if type(start) == "number" and type(dur) == "number" and dur > 0 and dur <= 1.5 then
        E.gcd.start, E.gcd.duration, E.gcd.ends = start, dur, start + dur
    end
end

local function SetRange(swingType, value)
    if E.inRange[swingType] == value then return end
    E.inRange[swingType] = value
    if value == false then E:Disturb(swingType) end
    Fire("range", swingType, value)
end

function E:PollRange()
    for _, t in ipairs(self.TYPES) do
        local v = Read(C_SwingTimer.IsTargetWithinSwingRange, t)
        if v == nil then SetRange(t, nil) else SetRange(t, v and true or false) end
    end
end

function E:UpdateLag()
    local _, _, _, world = Read(GetNetStats)
    self.lag = max(0, (tonumber(world) or 0) / 1000)
end

local function ReadAttacking()
    local on
    if C_Spell and C_Spell.IsCurrentSpell then on = Read(C_Spell.IsCurrentSpell, AUTO_ATTACK)
    elseif IsCurrentSpell then on = Read(IsCurrentSpell, AUTO_ATTACK) end
    return on and true or false
end

local function SetAttacking(on)
    E:Disturb()
    if E.attacking == on then return end
    E.attacking = on
    Fire("attack", on)
end

--------------------------------------------------------------------------------
--  Range checks. Blizzard's bar switches the check off whenever its own
--  timer is hidden (from its CVar callback, whose timing we don't control),
--  so ours is armed again after anything that can do that, and once more a
--  moment later, after Blizzard's handlers have run.
--------------------------------------------------------------------------------
local armed = {}

--- wanted(type) -> bool. Arms the check for each wanted type.
function E:ArmRange(wanted)
    self.rangeWanted = wanted
    for _, t in ipairs(self.TYPES) do
        local want = wanted(t) and true or false
        if want then
            pcall(C_SwingTimer.EnableRangeCheck, t, true)
            armed[t] = true
        elseif armed[t] then
            pcall(C_SwingTimer.EnableRangeCheck, t, false)
            armed[t] = nil
        end
    end
    self:PollRange()
end

--- Switches off only what we switched on, so Blizzard's own bar keeps its.
function E:DisarmRange()
    self.rangeWanted = nil
    for t in pairs(armed) do pcall(C_SwingTimer.EnableRangeCheck, t, false) end
    wipe(armed)
end

local function Rearm()
    if not E.rangeWanted then return end
    E:ArmRange(E.rangeWanted)
    C_Timer.After(0.2, function() if E.rangeWanted then E:ArmRange(E.rangeWanted) end end)
end
E.Rearm = Rearm

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local scanPending = false

local function ScanSoon()
    if scanPending then return end
    scanPending = true
    C_Timer.After(1, function()
        scanPending = false
        if not E.inCombat then E:ScanWeapons() end
    end)
end

local EVENTS = {
    PLAYER_SWING = function(dur, swingType) OnSwing(dur, swingType) end,
    UNIT_COMBAT = function(unit, action)
        if unit == "player" and Plain(action) == "PARRY" then OnParry() end
    end,
    UNIT_ATTACK_SPEED = function(unit) if unit == "player" then OnAttackSpeed() end end,
    UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID) if unit == "player" then OnCast(spellID) end end,
    UNIT_SPELLCAST_START = function(unit) if unit == "player" then E:Disturb() end end,
    UNIT_SPELLCAST_CHANNEL_START = function(unit) if unit == "player" then E:Disturb() end end,
    LOSS_OF_CONTROL_ADDED = function() E:Disturb() end,
    SPELL_UPDATE_COOLDOWN = OnCooldowns,
    PLAYER_SWING_RANGE_UPDATE = function(swingType, inRange, checks)
        swingType, inRange, checks = Plain(swingType), Plain(inRange), Plain(checks)
        if swingType == nil or not E.swings[swingType] then return end
        if checks then SetRange(swingType, inRange and true or false) else SetRange(swingType, nil) end
    end,
    PLAYER_TARGET_CHANGED = function()
        E:Disturb()
        E:PollRange()
        Fire("target")
    end,
    PLAYER_ENTER_COMBAT = function() SetAttacking(true) end,
    PLAYER_LEAVE_COMBAT = function() SetAttacking(false) end,
    PLAYER_REGEN_DISABLED = function() E.inCombat = true; Fire("combat", true) end,
    PLAYER_REGEN_ENABLED = function() E.inCombat = false; Fire("combat", false); ScanSoon() end,
    PLAYER_DEAD = function() E:Disturb() end,
    WEAPON_SLOT_CHANGED = function() OnWeapons(); Rearm() end,
    PLAYER_EQUIPMENT_CHANGED = function() OnWeapons() end,
    BAG_UPDATE_DELAYED = function() ScanSoon() end,
    CVAR_UPDATE = function(name)
        name = Plain(name)
        if type(name) == "string" and name:lower() == "showswingtimer" then Rearm() end
    end,
    EDIT_MODE_LAYOUTS_UPDATED = function() Rearm() end,
    PLAYER_ENTERING_WORLD = function()
        E:Disturb()
        E.inCombat = (Read(UnitAffectingCombat, "player")) and true or false
        E.attacking = ReadAttacking()
        E:UpdateLag()
        E:ScanWeapons()
        Rearm()
    end,
}

frame:SetScript("OnEvent", function(_, event, ...)
    local h = EVENTS[event]
    if h then h(...) end
end)

--- Starts listening. Safe to call more than once.
function E:Start()
    if running then return end
    running = true
    for event in pairs(EVENTS) do
        if event:find("^UNIT_") then
            pcall(frame.RegisterUnitEvent, frame, event, "player")
        else
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    self.inCombat = (Read(UnitAffectingCombat, "player")) and true or false
    self.attacking = ReadAttacking()
    self:UpdateLag()
    self:ScanWeapons()
end

function E:Stop()
    if not running then return end
    running = false
    frame:UnregisterAllEvents()
    self:DisarmRange()
end

function E:IsRunning() return running end

--------------------------------------------------------------------------------
--  LAYERS
--  Everything drawn on the swing bar beyond the fill is a layer, the
--  built-in ones included (SwingTimer.lua). A class layer (seal twisting,
--  on-next-swing attacks, a mage's wand) is one more:
--
--    EvermoreUI.Swing:RegisterLayer("warrior-queue", {
--        title       = "Heroic Strike queued",   -- its switch in the options
--        description = "...",                     -- the switch's tooltip
--        class       = "WARRIOR",                 -- optional: only this class
--        IsAvailable = function(layer) end,       -- optional, further gating
--        default     = true,                      -- on until switched off
--        order       = 50,                        -- later draws over earlier
--        Keep        = function(layer, swingType, now) end, -- keep a row on screen
--        Decorate    = function(layer, row) end,  -- each frame, per shown row
--        OnEnable    = function(layer) end,       -- switched on (or at start)
--        OnDisable   = function(layer) end,
--    })
--
--  Decorate gets a `row`, reset every frame, carrying the facts:
--    row.type, row.now, row.swinging, row.progress (0..1 or nil),
--    row.remaining, row.duration, row.ends, row.inRange
--    row:At(time)             where a moment falls on the bar (0..1, unclamped)
--  and the ways to draw, all in fractions of the bar's width:
--    row:Colour(r, g, b) / row:Token(themeToken)    the fill's colour
--    row:Underlay(from, to, token, alpha)           a band under the fill
--    row:Zone(from, to, token, alpha)               a band over the fill
--    row:Marker(at, token, width)                   a thin vertical line
--    row:Text(text, token)                          replaces the time left
--    row:Label(text)                                replaces MH / OH / R
--    row:Dim(alpha)                                 fades the whole row
--  A layer needing the engine's events subscribes with E:On in OnEnable.
--------------------------------------------------------------------------------
E.layers = {}

function E:RegisterLayer(key, layer)
    assert(type(key) == "string" and type(layer) == "table", "RegisterLayer(key, layer)")
    layer.key = key
    layer.order = layer.order or 50
    self.layers[key] = layer
    Fire("layers")
end

--- Layers that apply to this character, in drawing order.
function E:Layers()
    local _, class = UnitClass("player")
    local list = {}
    for _, layer in pairs(self.layers) do
        local ok = (not layer.class or layer.class == class)
        if ok and layer.IsAvailable then
            local fine, res = pcall(layer.IsAvailable, layer)
            ok = fine and res and true or false
        end
        if ok then list[#list + 1] = layer end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)
    return list
end
