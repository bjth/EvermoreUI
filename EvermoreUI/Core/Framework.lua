if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Framework.lua
--  Minimal module system. Replaces AceAddon/AceEvent with the bits we use.
--
--  local M = EvermoreUI:NewModule("DataBars", defaults)
--    M:OnInitialize()      ADDON_LOADED of the owning addon, M.db is ready
--    M:OnEnable()          PLAYER_LOGIN (or straight away if loaded later)
--    M:OnProfileChanged()  after a profile switch/reset, M.db already rebound
--
--  Each module gets its own event frame, created in NewModule. NewModule runs
--  in the child's main chunk, so the frame is attributed to the child addon
--  and the CPU profiler bills its event work there, not to the parent.
--------------------------------------------------------------------------------
local EV = EvermoreUI

local modules      = {}   -- name -> module
local moduleOrder  = {}   -- creation order
local initQueue    = {}
local enableQueue  = {}
local messages     = {}   -- msg -> { [module] = handler }

EV.dbReady  = false
EV.loggedIn = false

--------------------------------------------------------------------------------
--  Module mixin
--------------------------------------------------------------------------------
local Module = {}
Module.__index = Module

-- Call mod:method() and route errors to the error handler (BugSack) without
-- stopping the caller. Closure form works on any Lua 5.1 xpcall.
local function SafeCall(fn, mod)
    return xpcall(function() return fn(mod) end, geterrorhandler())
end

local function Dispatch(mod, handler, ...)
    if type(handler) == "string" then handler = mod[handler] end
    if handler then handler(mod, ...) end
end

--- Register a game event. handler: function(self, event, ...) or a method
--- name; defaults to a method named after the event.
--- Returns false (instead of erroring) if the client doesn't know the event,
--- since Forever's event list isn't retail's.
function Module:RegisterEvent(event, handler)
    if not pcall(self._frame.RegisterEvent, self._frame, event) then return false end
    self._events[event] = handler or event
    return true
end

--- Register a unit event: M:RegisterUnitEvent("UNIT_HEALTH", handler, "player", "target")
function Module:RegisterUnitEvent(event, handler, unit1, unit2)
    if not pcall(self._frame.RegisterUnitEvent, self._frame, event, unit1, unit2) then return false end
    self._events[event] = handler or event
    return true
end

function Module:UnregisterEvent(event)
    self._events[event] = nil
    self._frame:UnregisterEvent(event)
end

function Module:UnregisterAllEvents()
    wipe(self._events)
    self._frame:UnregisterAllEvents()
end

--- Internal suite messages (profile changes, unlock mode, etc.)
function Module:RegisterMessage(msg, handler)
    messages[msg] = messages[msg] or {}
    messages[msg][self] = handler or msg
end

function Module:UnregisterMessage(msg)
    if messages[msg] then messages[msg][self] = nil end
end

function Module:IsEnabled()
    return self._enabled == true
end

--- True unless the user has switched this module off in options.
function Module:IsWanted()
    local core = EV.DB and EV.DB:GetCore()
    return not (core and core.disabled[self.name])
end

--------------------------------------------------------------------------------
--  Registry
--------------------------------------------------------------------------------
function EV:NewModule(name, defaults)
    if modules[name] then
        error("EvermoreUI:NewModule: module '" .. name .. "' already exists.", 2)
    end
    local mod = setmetatable({
        name      = name,
        defaults  = defaults or {},
        _events   = {},
        _enabled  = false,
    }, Module)

    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...)
        local h = mod._events[event]
        if h then Dispatch(mod, h, event, ...) end
    end)
    mod._frame = f

    modules[name] = mod
    moduleOrder[#moduleOrder + 1] = mod
    initQueue[#initQueue + 1] = mod
    return mod
end

function EV:GetModule(name, silent)
    local mod = modules[name]
    if not mod and not silent then
        error("EvermoreUI:GetModule: module '" .. tostring(name) .. "' not found.", 2)
    end
    return mod
end

--- Iterate modules in creation order: for i, mod in EV:IterateModules() do
function EV:IterateModules()
    return ipairs(moduleOrder)
end

function EV:SendMessage(msg, ...)
    local subs = messages[msg]
    if not subs then return end
    for mod, handler in pairs(subs) do
        Dispatch(mod, handler, msg, ...)
    end
end

--------------------------------------------------------------------------------
--  Lifecycle
--------------------------------------------------------------------------------
local function EnableModule(mod)
    if mod._enabled or not mod:IsWanted() then return end
    mod._enabled = true
    if mod.OnEnable then
        SafeCall(mod.OnEnable, mod)
    end
end

local function FlushInit()
    if not EV.dbReady then return end
    while #initQueue > 0 do
        local mod = table.remove(initQueue, 1)
        mod.db = EV.DB:BindModule(mod.name, mod.defaults)
        if mod.OnInitialize then
            SafeCall(mod.OnInitialize, mod)
        end
        if EV.loggedIn then
            EnableModule(mod)          -- LoadOnDemand module after login
        else
            enableQueue[#enableQueue + 1] = mod
        end
    end
end

local function FlushEnable()
    while #enableQueue > 0 do
        EnableModule(table.remove(enableQueue, 1))
    end
end

-- Called by DB after a profile switch or reset.
function EV:_RebindModules()
    for _, mod in ipairs(moduleOrder) do
        if mod.db then
            mod.db = EV.DB:BindModule(mod.name, mod.defaults)
            if mod._enabled and mod.OnProfileChanged then
                SafeCall(mod.OnProfileChanged, mod)
            end
        end
    end
    if EV.Movers then EV.Movers:ApplyAll() end
    EV:SendMessage("EV_PROFILE_CHANGED")
end

local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == EV.name then
            EV.DB:Init()
            EV.dbReady = true
        end
        FlushInit()
    elseif event == "PLAYER_LOGIN" then
        EV.loggedIn = true
        FlushInit()
        FlushEnable()
        EV:SendMessage("EV_READY")
    elseif event == "PLAYER_LOGOUT" then
        EV:SendMessage("EV_LOGOUT")
        EV.DB:Shutdown()
    end
end)
