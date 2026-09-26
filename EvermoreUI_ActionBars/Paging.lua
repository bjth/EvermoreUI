if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Paging.lua
--  Which page of actions a bar shows: a fixed page, a page while Alt, Ctrl
--  or Shift is held, or your own macro conditions.
--
--  Forever has no secure snippets, so the usual recipe (a state handler
--  that pushes the page to each button) is out. It turns out not to be
--  needed. A Blizzard action button works out its action in CalculateAction
--  (SecureTemplates.lua):
--
--      page = SecureButton_GetModifiedAttribute(self, "actionpage", button)
--
--  which reads the BUTTON's own "actionpage" first and only then its bar's.
--  And the game's attribute driver (RegisterAttributeDriver,
--  SecureStateDriver.lua) re-evaluates macro conditions and sets an
--  attribute from secure code, in combat, with no snippet. Changing the
--  attribute fires the button's OnAttributeChanged, which calls UpdateAction,
--  so icons, cooldowns and keybind presses all follow the new page.
--
--  The driver's value "nil" clears the attribute, and a cleared attribute
--  means Blizzard's own paging: the main bar's stance, form and stealth
--  pages (the engine remaps slots 1-12) and bars 2-8's fixed pages. So an
--  unmatched condition always falls back to exactly what Blizzard would do,
--  and the main bar hands over to the game while you are in a vehicle or
--  controlling something.
--------------------------------------------------------------------------------
local _, ns = ...
local M = ns.module
if not M then return end

local MAX_PAGE = 10
local floor = math.floor

local function Page(v)
    v = tonumber(v)
    if v and v >= 1 and v <= MAX_PAGE then return floor(v) end
end

--- The driver string for a bar, or nil when Blizzard's paging is untouched.
function ns.PageCondition(def, cfg)
    if def.small then return nil end
    local parts = {}
    local custom = type(cfg.pageCustom) == "string" and strtrim(cfg.pageCustom) or ""
    custom = custom:gsub(";%s*$", "")
    if custom ~= "" then
        parts[#parts + 1] = custom
    else
        for _, m in ipairs({ { "alt", cfg.pageAlt }, { "ctrl", cfg.pageCtrl }, { "shift", cfg.pageShift } }) do
            local p = Page(m[2])
            if p then parts[#parts + 1] = ("[mod:%s] %d"):format(m[1], p) end
        end
    end
    local fixed = Page(cfg.page)
    if #parts == 0 and not fixed then return nil end
    local out = {}
    if def.main then
        -- Vehicles, possession and override bars belong to the game.
        out[1] = "[vehicleui][possessbar][overridebar] nil"
    end
    for _, p in ipairs(parts) do out[#out + 1] = p end
    out[#out + 1] = fixed and tostring(fixed) or "nil"
    return table.concat(out, "; ")
end

--- Put the bar's paging on its buttons (out of combat; Layout calls this).
function ns.ApplyPaging(def)
    local cfg = ns.Bar(def.key)
    local cond = ns.PageCondition(def, cfg)
    for _, b in ipairs(ns.Buttons(def)) do
        if cond then
            if b.evPaging ~= cond then
                RegisterAttributeDriver(b, "actionpage", cond)
                b.evPaging = cond
            end
        elseif b.evPaging then
            UnregisterAttributeDriver(b, "actionpage")
            b:SetAttribute("actionpage", nil)
            b.evPaging = nil
        end
    end
end
