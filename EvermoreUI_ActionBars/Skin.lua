if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Skin.lua
--  The button look: square cropped icon on a sunk well, a 1px theme border,
--  flat hover / pressed / checked states, and our fonts for the keybind,
--  charge count and macro name.
--
--  Blizzard's art is faded by alpha, never hidden or replaced, so its own
--  code (which re-sets atlases now and then) never fights us: an atlas swap
--  keeps the alpha. The three state textures are recoloured in place; the
--  only Blizzard code that resets them (UpdateButtonArt) is post-hooked.
--  Blizzard keeps tinting the icon for range and usability, and keeps its
--  proc glow, cooldown swipes and highlight marks.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end
local EV = EvermoreUI
local T = EV.Theme

local skinned = setmetatable({}, { __mode = "k" }) -- button -> our bits

local ART = { "NormalTexture", "SlotArt", "SlotBackground", "FloatingBG" }
local FIT = { "Flash", "SpellHighlightTexture", "NewActionTexture", "Border", "QuickKeybindHighlightTexture" }

local function Icon(b) return b.icon or b.Icon end

local function States(b)
    local icon = Icon(b)
    local hl = b.GetHighlightTexture and b:GetHighlightTexture()
    if hl then
        hl:SetColorTexture(EV.Theme.RGBA("text", 0.15))
        hl:ClearAllPoints(); hl:SetAllPoints(icon)
    end
    local pt = b.GetPushedTexture and b:GetPushedTexture()
    if pt then
        pt:SetColorTexture(EV.Theme.RGBA("surfaceSunk", 0.5))
        pt:ClearAllPoints(); pt:SetAllPoints(icon)
    end
    local ct = b.GetCheckedTexture and b:GetCheckedTexture()
    if ct then
        local r, g, bl = T.RGBA("accent")
        ct:SetColorTexture(r, g, bl, 0.3)
        ct:ClearAllPoints(); ct:SetAllPoints(icon)
    end
    -- Overlays Blizzard sizes for its 45px button: fit them to our icon.
    for _, k in ipairs(FIT) do
        local t = b[k]
        if t and t.ClearAllPoints and icon then
            t:ClearAllPoints()
            t:SetAllPoints(icon)
        end
    end
    for _, k in ipairs(ART) do
        local t = b[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
end

-- Per bar switches sit on top of the Buttons tab's: both must be on.
local function BarText(b, key)
    local bar = b.evBar and M.db.bars[b.evBar]
    return not bar or bar[key] ~= false
end

local function Texts(b)
    local cfg = M.db.text
    local font = EV.Media:Fetch("font")
    local hk, count, name = b.HotKey, b.Count, b.Name
    if hk and hk.SetFont then
        hk:SetFont(font, cfg.hotkeySize, "OUTLINE")
        hk:ClearAllPoints()
        hk:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -3)
        hk:SetJustifyH("RIGHT")
        hk:SetAlpha((cfg.hotkey and BarText(b, "showHotkey")) and 1 or 0)
    end
    if count and count.SetFont then
        count:SetFont(font, cfg.countSize, "OUTLINE")
        count:ClearAllPoints()
        count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 3)
        count:SetAlpha((cfg.count and BarText(b, "showCount")) and 1 or 0)
    end
    if name and name.SetFont then
        name:SetFont(font, cfg.macroSize, "OUTLINE")
        name:ClearAllPoints()
        name:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 3)
        name:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 3)
        name:SetAlpha((cfg.macro and BarText(b, "showMacro")) and 1 or 0)
    end
end

--------------------------------------------------------------------------------
--  Reagent and ammo counts
--
--  Blizzard's count comes from the engine, C_ActionBar.GetActionDisplayCount
--  (ActionButton.lua, UpdateCount), and we never touch it. Where it leaves
--  the count EMPTY we lay our own number over the same corner:
--    * a spell that uses a reagent: GetActionCount(action), the classic call
--      that returns how many casts your reagents cover
--    * a ranged attack that fires ammunition: the ammo in your ammo slot
--    * Throw: the thrown weapon's stack
--  Our text is our own font string; Blizzard's Count is only read.
--------------------------------------------------------------------------------
local AMMO_SPELLS = { [75] = true, [2480] = true, [7918] = true, [7919] = true }   -- Auto Shot, Shoot Bow/Gun/Crossbow
local THROW_SPELLS = { [2764] = true }
local AMMO_SLOT = INVSLOT_AMMO or 0
local RANGED_SLOT = INVSLOT_RANGED or 18
local issecret = issecretvalue or function() return false end

local function Num(v) return type(v) == "number" and not issecret(v) and v or nil end

-- C_ActionBar spellings first: the plain globals are deprecation shims
-- (Blizzard_DeprecatedActionBar) that go away with the next expansion.
local AB = C_ActionBar or {}
local IsItemActionFn = AB.IsItemAction or IsItemAction
local UseCountFn = AB.GetActionUseCount or GetActionCount

local function ExtraCount(b)
    local action = b.action
    if type(action) ~= "number" then return nil end
    local okI, isItem = pcall(IsItemActionFn, action)
    if okI and isItem then return nil end
    local okT, kind, id = pcall(GetActionInfo, action)
    if okT and kind == "spell" and Num(id) then
        if AMMO_SPELLS[id] then
            local ok, n = pcall(GetInventoryItemCount, "player", AMMO_SLOT)
            n = ok and Num(n)
            if n and n > 0 then return n end
        elseif THROW_SPELLS[id] then
            local ok, n = pcall(GetInventoryItemCount, "player", RANGED_SLOT)
            n = ok and Num(n)
            if n and n > 1 then return n end
        end
    end
    if type(UseCountFn) == "function" then
        local ok, n = pcall(UseCountFn, action)
        n = ok and Num(n)
        if n and n > 0 then return n end
    end
    return nil
end

local function FillCount(b)
    local s = skinned[b]
    if not s then return end
    local cfg = M.db.text
    local blizz = b.Count and b.Count.GetText and b.Count:GetText()
    local n
    -- A secret count is never compared (comparison throws); it is left to Blizzard.
    if cfg.count and cfg.reagents and BarText(b, "showCount") and not issecret(blizz) and (blizz == nil or blizz == "") then
        n = ExtraCount(b)
    end
    if not s.extra then
        s.extra = b:CreateFontString(nil, "OVERLAY")
        s.extra:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 3)
        s.extra:SetJustifyH("RIGHT")
    end
    s.extra:SetFont(EV.Media:Fetch("font"), cfg.countSize, "OUTLINE")
    if n then
        s.extra:SetText(n > 999 and "999+" or tostring(n))
        s.extra:Show()
    else
        s.extra:Hide()
    end
end
ns.FillCount = FillCount

local countEvents = CreateFrame("Frame")
countEvents:SetScript("OnEvent", function()
    for b in pairs(skinned) do FillCount(b) end
end)
function ns.EnableCounts()
    countEvents:RegisterEvent("BAG_UPDATE_DELAYED")
    countEvents:RegisterEvent("UNIT_INVENTORY_CHANGED")
    countEvents:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    countEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
end

--------------------------------------------------------------------------------
--  Short keybind text
--
--  Blizzard writes GetBindingText(key, 1) into HotKey (UpdateHotkeys). We
--  post-hook it and write our own from the raw key: modifiers as single
--  letters, mouse buttons as M4, the wheel as WU / WD, the number pad as N.
--  The range dot (RANGE_INDICATOR, shown when nothing is bound) is left be.
--------------------------------------------------------------------------------
local ShortKey = EV.ShortKey

local function BindingFor(b)
    if b.bindingAction then return GetBindingKey(b.bindingAction) end
    if b.commandName then return GetBindingKey(b.commandName) end
    local name = b.GetName and b:GetName()
    if name then return GetBindingKey("CLICK " .. name .. ":LeftButton") end
end
ns.BindingFor = BindingFor

--- The keybind text we would show for a button (short or Blizzard's).
function ns.HotkeyText(b)
    local key = BindingFor(b)
    if not key then return "" end
    if M.db.text.shortKeys then return ShortKey(key) or "" end
    return GetBindingText(key, 1) or key
end

local function Hotkey(b)
    local hk = b.HotKey
    if not (hk and M.db.text.shortKeys) then return end
    local text = hk:GetText()
    if issecret(text) or text == RANGE_INDICATOR or text == nil or text == "" then return end
    local key = BindingFor(b)
    local short = ShortKey(key)
    if short then hk:SetText(short) end
end

--------------------------------------------------------------------------------
--  Range tint and equipped edge
--
--  Blizzard only reddens the keybind when you are out of range
--  (ActionButton_UpdateRangeIndicator). We keep that and also tint the
--  icon, which is what people look at. Blizzard's own usability tint
--  (UpdateUsable: blue for no mana, grey for unusable) resets the icon's
--  colour, so we re-apply ours after it. Equipped items get our border in
--  the success colour instead of Blizzard's green glow, which sat oddly on
--  the cropped icon.
--------------------------------------------------------------------------------
local RANGE = { 0.85, 0.25, 0.25 }

local function Tint(b)
    local s = skinned[b]
    local icon = Icon(b)
    if not (s and icon) then return end
    if s.oor and M.db.look.rangeTint then
        icon:SetVertexColor(RANGE[1], RANGE[2], RANGE[3])
    end
end

local function OnRange(b, checksRange, inRange)
    local s = skinned[b]
    if not s then return end
    local was = s.oor
    if issecret(checksRange) or issecret(inRange) then
        s.oor = false
    else
        s.oor = (checksRange and inRange == false) and true or false
    end
    if s.oor then
        Tint(b)
    elseif was and b.UpdateUsable then
        pcall(b.UpdateUsable, b)   -- Blizzard puts its own colour back
    end
end
if type(ActionButton_UpdateRangeIndicator) == "function" then
    hooksecurefunc("ActionButton_UpdateRangeIndicator", OnRange)
end

local function Equipped(b)
    local s = skinned[b]
    if not (s and s.edge) then return end
    local on = false
    if M.db.look.equipped and type(b.action) == "number" and C_ActionBar and C_ActionBar.IsEquippedAction then
        local ok, eq = pcall(C_ActionBar.IsEquippedAction, b.action)
        on = ok and eq == true
    end
    if b.Border then b.Border:SetAlpha(0) end
    T.SetBorderToken(s.edge, on and "success" or "border")
end

--------------------------------------------------------------------------------
--  Spell rank
--
--  Classic spells come in ranks, and the rank is the spell's subtext
--  (C_Spell.GetSpellSubtext: "Rank 3"). A macro shows the rank of the spell
--  it would cast (GetMacroSpell). Subtext can be empty until the spell's
--  data has loaded; SPELL_TEXT_UPDATE redraws when it arrives. The number is
--  pulled out of the text so it reads the same in any language.
--------------------------------------------------------------------------------
local RANK_JUSTIFY = {
    TOPLEFT = "LEFT", LEFT = "LEFT", BOTTOMLEFT = "LEFT",
    TOP = "CENTER", CENTER = "CENTER", BOTTOM = "CENTER",
    TOPRIGHT = "RIGHT", RIGHT = "RIGHT", BOTTOMRIGHT = "RIGHT",
}

local function RankOf(action)
    if type(action) ~= "number" then return nil end
    local ok, kind, id = pcall(GetActionInfo, action)
    if not ok then return nil end
    local spellID
    if kind == "spell" then
        spellID = id
    elseif kind == "macro" and type(GetMacroSpell) == "function" then
        local okM, sid = pcall(GetMacroSpell, id)
        spellID = okM and sid or nil
    end
    if type(spellID) ~= "number" or issecret(spellID) then return nil end
    local okS, sub = pcall(C_Spell.GetSpellSubtext, spellID)
    if not okS or type(sub) ~= "string" or issecret(sub) then return nil end
    local n = sub:match("(%d+)")
    return n, sub
end

local function Rank(b)
    local s = skinned[b]
    if not s then return end
    local bar = b.evBar and M.db.bars[b.evBar]
    if not (bar and bar.rankText) then
        if s.rank then s.rank:Hide() end
        return
    end
    if not s.rank then
        -- On the edge frame, so it draws above the icon and cooldown swipe.
        s.rank = s.edge:CreateFontString(nil, "OVERLAY")
    end
    local fs = s.rank
    local n, full = RankOf(b.action)
    if not n then fs:Hide(); return end
    local point = RANK_JUSTIFY[bar.rankPoint] and bar.rankPoint or "TOPLEFT"
    fs:SetFont(EV.Media:Fetch("font"), bar.rankSize or 10, "OUTLINE")
    fs:ClearAllPoints()
    fs:SetPoint(point, b, point, bar.rankX or 0, bar.rankY or 0)
    fs:SetJustifyH(RANK_JUSTIFY[point])
    local c = type(bar.rankColour) == "table" and bar.rankColour or { 1, 0.82, 0 }
    fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1)
    if bar.rankFormat == "number" then
        fs:SetText(n)
    elseif bar.rankFormat == "full" then
        fs:SetText(full)
    else
        fs:SetText("R" .. n)
    end
    fs:Show()
end

local rankEvents = CreateFrame("Frame")
pcall(rankEvents.RegisterEvent, rankEvents, "SPELL_TEXT_UPDATE")
pcall(rankEvents.RegisterEvent, rankEvents, "UPDATE_MACROS")
rankEvents:SetScript("OnEvent", function()
    for b in pairs(skinned) do Rank(b) end
end)

--- Dress one Blizzard action button (once; later calls just re-apply).
function ns.SkinButton(b)
    if not b then return end
    local s = skinned[b]
    local icon = Icon(b)
    if not s then
        s = {}
        skinned[b] = s
        if icon then
            if b.IconMask and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, b.IconMask) end
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        end
        -- Our well behind the icon (shows on empty slots).
        s.well = T.Fill(b, "BACKGROUND", "surfaceSunk", 0.9, -8)
        s.well:SetAllPoints(b)
        -- Border on our own child frame, above the icon.
        local edge = CreateFrame("Frame", nil, b)
        edge:SetAllPoints(b)
        edge:SetFrameLevel(b:GetFrameLevel() + 2)
        edge:EnableMouse(false)
        T.TokenBorder(edge, "border")
        s.edge = edge
        -- Cooldowns fill the icon exactly.
        for _, k in ipairs({ "cooldown", "chargeCooldown", "lossOfControlCooldown" }) do
            local cd = b[k]
            if cd and cd.ClearAllPoints and icon then
                cd:ClearAllPoints()
                cd:SetAllPoints(icon)
            end
        end
        -- Blizzard re-sets the pushed / normal art in UpdateButtonArt.
        if type(b.UpdateButtonArt) == "function" then
            hooksecurefunc(b, "UpdateButtonArt", function(btn) States(btn) end)
        end
        -- Our reagent / ammo count follows Blizzard's every time it redraws.
        if type(b.UpdateCount) == "function" then
            hooksecurefunc(b, "UpdateCount", function(btn) FillCount(btn) end)
        end
        if type(b.UpdateHotkeys) == "function" then
            hooksecurefunc(b, "UpdateHotkeys", function(btn) Hotkey(btn) end)
        end
        if type(b.UpdateUsable) == "function" then
            hooksecurefunc(b, "UpdateUsable", function(btn) Tint(btn) end)
        end
        if type(b.Update) == "function" then
            hooksecurefunc(b, "Update", function(btn) Equipped(btn); Rank(btn) end)
        end
        function s.Paint()
            s.well:SetColorTexture(T.RGBA("surfaceSunk", 0.9))
            States(b)
            Equipped(b)
        end
        T.Watch(s)
    end
    States(b)
    Texts(b)
    FillCount(b)
    Equipped(b)
    Hotkey(b)
    Rank(b)
end

function ns.RestyleButtons()
    for b in pairs(skinned) do
        States(b)
        Texts(b)
        FillCount(b)
        Equipped(b)
        if b.UpdateHotkeys then
            -- Blizzard rewrites the text (full key names), our hook shortens
            -- it again if that is switched on.
            pcall(b.UpdateHotkeys, b, b.buttonType)
        end
        Hotkey(b)
        Rank(b)
        if b.UpdateUsable then pcall(b.UpdateUsable, b) end
    end
end
