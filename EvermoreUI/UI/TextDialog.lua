if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  TextDialog.lua
--  One window, two jobs: show text to copy out (a profile string) and take
--  text pasted in. The box scrolls with the shared scroll bar, Escape
--  closes, and copy mode selects everything so Ctrl+C is the only keypress.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local T, U = EV.Theme, EV.UI
local L = EV.L

local dialog

local function Build()
    if dialog then return dialog end
    local f = U.Window("EvermoreUITextDialog", { width = 560, height = 320, strata = "DIALOG" })
    f.hint = T.Text(f.titleBar, "small", "textMuted")
    f.hint:SetPoint("RIGHT", f.closeButton or f.titleBar, f.closeButton and "LEFT" or "RIGHT", -10, 0)

    local body = f.body or f
    local well = CreateFrame("Frame", nil, body)
    well:SetPoint("TOPLEFT", 12, -12)
    well:SetPoint("BOTTOMRIGHT", -12, 46)
    well.bg = T.Fill(well, "BACKGROUND", "surfaceSunk", 0.9)
    well.bg:SetAllPoints()
    T.TokenBorder(well, "border")

    local scroll = CreateFrame("ScrollFrame", nil, well)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -16, 6)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(EV.Media:Fetch("font"), 12, "")
    box:SetTextColor(T.RGBA("text"))
    box:SetWidth(510)
    box:SetTextInsets(2, 2, 2, 2)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(box)

    local bar = U.ScrollBar(well, {
        range = function() return scroll:GetVerticalScrollRange() end,
        offset = function() return scroll:GetVerticalScroll() end,
        visible = function() return scroll:GetHeight() end,
        set = function(v) scroll:SetVerticalScroll(v) end,
        step = 40,
    })
    bar:SetPoint("TOPRIGHT", -4, -4)
    bar:SetPoint("BOTTOMRIGHT", -4, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 40)))
        bar:Update()
    end)
    scroll:SetScript("OnScrollRangeChanged", function() bar:Update() end)
    scroll:SetScript("OnVerticalScroll", function() bar:Update() end)

    f.action = U.Button(body, L["Apply"], 120, function()
        if f.onAction then f.onAction(box:GetText()) end
    end, "accent")
    f.action:SetPoint("BOTTOMRIGHT", -12, 12)
    f.note = T.Text(body, "small", "textMuted")
    f.note:SetPoint("BOTTOMLEFT", 14, 18)
    f.note:SetPoint("RIGHT", f.action, "LEFT", -10, 0)
    f.note:SetJustifyH("LEFT")

    f.box, f.scroll, f.bar = box, scroll, bar
    dialog = f
    return f
end

--- Show text for the user to copy (read-only in practice: typing in it
--- changes nothing but the box).
function U.ShowCopyText(title, text, note)
    local f = Build()
    f.title:SetText(title or "")
    f.hint:SetText(L["Ctrl+C to copy, Esc to close"])
    f.note:SetText(note or "")
    f.onAction = nil
    f.action:Hide()
    f.box:SetText(text or "")
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
    return f
end

--- Ask for text: the button calls onAction(text). Returning a string keeps
--- the window open and shows it as the note (an error), anything else closes.
function U.ShowPasteText(title, note, actionLabel, onAction)
    local f = Build()
    f.title:SetText(title or "")
    f.hint:SetText(L["Ctrl+V to paste, Esc to close"])
    f.note:SetText(note or "")
    f.action:SetText(actionLabel or L["Apply"])
    f.action:Show()
    f.box:SetText("")
    f.onAction = function(text)
        local problem = onAction and onAction(text)
        if type(problem) == "string" then
            f.note:SetText("|cffe46a55" .. problem .. "|r")
        else
            f:Hide()
        end
    end
    f:Show()
    f.box:SetFocus()
    return f
end
