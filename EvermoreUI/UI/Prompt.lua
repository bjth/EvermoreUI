if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  UI/Prompt.lua
--  A small window asking for one number, in the house style.
--
--  U.AskNumber{
--      title = "Restock", text = "How many ...?", value = 20,
--      min = 0, max = 99999,
--      onSave = function(n) end,
--      extra = { text = "Stop", style = "danger", onClick = function() end },
--  }
--
--  Enter saves, Escape or Cancel closes. Only one prompt is open at a time;
--  asking again replaces it.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T, U = EV.Theme, EV.UI
local L = EV.L

local win

local function Build()
    if win then return win end
    local f = U.Window("EvermoreUIPrompt", { width = 340, height = 150, strata = "DIALOG" })
    local body = f.body

    f.text = T.Text(body, "body", "text")
    f.text:SetPoint("TOPLEFT", 14, -14)
    f.text:SetPoint("TOPRIGHT", -14, -14)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(true)

    f.field = U.Field(body, 110)
    f.field:SetNumeric(true)
    f.field:SetMaxLetters(5)
    f.field:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -10)

    local function Close() f:Hide() end
    local function Save()
        local n = tonumber(f.field:GetText())
        if n then
            if f.min then n = math.max(f.min, n) end
            if f.max then n = math.min(f.max, n) end
        end
        local cb = f.onSave
        Close()
        if cb and n then cb(n) end
    end

    f.save = U.Button(body, SAVE or L["Save"], 90, Save, "primary")
    f.save:SetPoint("BOTTOMRIGHT", -12, 12)
    f.cancel = U.Button(body, CANCEL or L["Cancel"], 90, Close)
    f.cancel:SetPoint("RIGHT", f.save, "LEFT", -8, 0)
    f.extra = U.Button(body, "", 120, function()
        local cb = f.onExtra
        Close()
        if cb then cb() end
    end)
    f.extra:SetPoint("BOTTOMLEFT", 12, 12)

    f.field:SetScript("OnEnterPressed", Save)
    f.field:SetScript("OnEscapePressed", Close)
    f:HookScript("OnHide", function(self) self.field:ClearFocus(); self.onSave, self.onExtra = nil, nil end)

    win = f
    return f
end

function U.AskNumber(opts)
    local f = Build()
    f:Hide()
    f:SetTitle(opts.title or "")
    f.text:SetText(opts.text or "")
    f.min, f.max = opts.min, opts.max
    f.onSave = opts.onSave
    local extra = opts.extra
    if extra then
        f.extra:SetText(extra.text or "")
        f.extra:SetStyle(extra.style)
        f.onExtra = extra.onClick
        f.extra:Show()
    else
        f.onExtra = nil
        f.extra:Hide()
    end
    f.field:SetText(opts.value and tostring(opts.value) or "")
    -- Height follows the message, so a long item name doesn't crowd the box.
    f:SetHeight(32 + 14 + math.ceil(f.text:GetStringHeight()) + 10 + U.HEIGHT + 12 + U.HEIGHT + 2 + 12 + 4)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:Show()
    f.field:SetFocus()
    f.field:HighlightText()
    return f
end
