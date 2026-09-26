if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  ReadyCheck.lua
--  The ready check prompt in the EvermoreUI style, with a sound and a flash
--  of the game's taskbar icon so you notice it from another window, and a
--  line in chat afterwards saying who wasn't ready and who didn't answer.
--
--  Built on the events and calls Blizzard's own prompt uses:
--      READY_CHECK(initiatorName, timeLeft)     a check starts
--      ConfirmReadyCheck(true | false)          your answer
--      READY_CHECK_CONFIRM(unit, isReady)       someone answers
--      READY_CHECK_FINISHED(preempted)          it's over
--      GetReadyCheckStatus(unit)                "ready", "notready", "waiting"
--  The person who started the check gets no prompt, as with Blizzard's, but
--  still gets the summary. Blizzard's prompt is hidden while ours is on.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local T = EV.Theme

local M = EV:NewModule("ReadyCheck", {
    sound   = true,
    flash   = true,
    summary = true,
})
M.title = "Ready Check"
M.description = "The ready check prompt in the EvermoreUI style, with a sound, a taskbar flash and a summary of who wasn't ready."
ns.readyCheck = M

local frame
local deadline, total = 0, 1

local function Build()
    if frame then return frame end
    local W = EV.UI
    frame = CreateFrame("Frame", "EvermoreUIReadyCheck", UIParent)
    frame:SetSize(320, 112)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame.bg = T.Fill(frame, "BACKGROUND", "surface0", 0.97)
    frame.bg:SetAllPoints()
    T.TokenBorder(frame, "border")
    if T.Shadow then T.Shadow(frame, 12) end

    frame.title = T.Text(frame, "title", "title", true)
    frame.title:SetPoint("TOP", 0, -12)
    frame.title:SetText(READY_CHECK or L["Ready check"])
    frame.text = T.Text(frame, "body", "text")
    frame.text:SetPoint("TOP", frame.title, "BOTTOM", 0, -8)
    frame.text:SetWidth(290)
    frame.text:SetWordWrap(true)
    frame.text:SetJustifyH("CENTER")

    frame.yes = W.Button(frame, READY or L["Ready"], 120, function() M:Answer(true) end, "accent")
    frame.yes:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -4, 14)
    frame.no = W.Button(frame, NOT_READY or L["Not ready"], 120, function() M:Answer(false) end)
    frame.no:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 4, 14)

    frame.timer = CreateFrame("StatusBar", nil, frame)
    frame.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.timer:SetStatusBarColor(T.RGBA("accent", 0.9))
    frame.timer:SetPoint("BOTTOMLEFT", 1, 1)
    frame.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.timer:SetHeight(3)
    frame.timer:SetMinMaxValues(0, 1)
    frame:SetScript("OnUpdate", function(self)
        local left = deadline - GetTime()
        if left <= 0 then self:Hide(); return end
        self.timer:SetValue(left / total)
    end)

    EV.Movers:Register(frame, "ReadyCheck", L["Ready Check"], { "TOP", "TOP", 0, -180 }, {
        group = L["Interface"], page = "group",
        isDisabled = function() return not M:IsEnabled() end,
    })
    EV.Movers:Apply("ReadyCheck")
    return frame
end

function M:Answer(ready)
    if frame and frame.test then frame:Hide(); return end
    pcall(ConfirmReadyCheck, ready and true or false)
    if frame then frame:Hide() end
end

local function Show(initiator, seconds, test)
    Build()
    frame.test = test
    total = math.max(seconds or 30, 1)
    deadline = GetTime() + total
    frame.text:SetText((L["%s wants to know if you're ready."]):format(initiator or "?"))
    frame:Show()
    if M.db.sound and SOUNDKIT and SOUNDKIT.READY_CHECK then PlaySound(SOUNDKIT.READY_CHECK, "Master") end
    if M.db.flash and FlashClientIcon then FlashClientIcon() end
end

function M:Test() Show(UnitName("player"), 30, true) end

--------------------------------------------------------------------------------
--  The summary
--------------------------------------------------------------------------------
local function Members()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

-- name -> "ready" | "notready" | "waiting", from the start of the check and
-- each answer as it comes in. Kept ourselves because the game's own status
-- may already be cleared by the time the check finishes.
local answers = {}

local function Begin(initiator)
    wipe(answers)
    for _, u in ipairs(Members()) do
        local name = UnitName(u)
        if name then answers[name] = "waiting" end
    end
    if initiator then answers[Ambiguate(initiator, "none")] = "ready" end
end

local function Answered(unit, ready)
    local name = unit and UnitName(unit)
    if name then answers[name] = ready and "ready" or "notready" end
end

local function Summary()
    if not M.db.summary or not IsInGroup() then return end
    local notReady, waiting = {}, {}
    for _, u in ipairs(Members()) do
        local name = UnitName(u)
        local status = name and answers[name]
        local ok, live = pcall(GetReadyCheckStatus, u)
        if ok and (live == "ready" or live == "notready") then status = live end
        if name then
            if status == "notready" then notReady[#notReady + 1] = name
            elseif status == "waiting" then waiting[#waiting + 1] = name end
        end
    end
    if #notReady == 0 and #waiting == 0 then
        EV:Print(L["Ready check: everyone's ready."])
        return
    end
    local parts = {}
    if #notReady > 0 then parts[#parts + 1] = L["not ready: "] .. table.concat(notReady, ", ") end
    if #waiting > 0 then parts[#parts + 1] = L["no answer: "] .. table.concat(waiting, ", ") end
    EV:Print(L["Ready check"] .. ", " .. table.concat(parts, "; ") .. ".")
end

--------------------------------------------------------------------------------
--  Blizzard's prompt steps aside
--------------------------------------------------------------------------------
local function Silence(f)
    if f and not f.evSilenced then
        f.evSilenced = true
        f:HookScript("OnShow", function(self) if M:IsEnabled() then self:Hide() end end)
    end
end

function M:OnEnable()
    Build()
    Silence(ReadyCheckFrame)
    Silence(ReadyCheckListenerFrame)
    self:RegisterEvent("READY_CHECK", function(_, _, initiator, seconds)
        Begin(initiator)
        local me = UnitName("player")
        if initiator and me and Ambiguate(initiator, "none") == me then return end
        Show(Ambiguate(initiator or "?", "short"), seconds)
    end)
    self:RegisterEvent("READY_CHECK_CONFIRM", function(_, _, unit, ready) Answered(unit, ready) end)
    -- Once the last answer is in, or time runs out.
    self:RegisterEvent("READY_CHECK_FINISHED", function()
        if frame and not frame.test then frame:Hide() end
        Summary()
    end)
end
