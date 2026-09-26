if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  MapReveal.lua
--  Show the whole world map: the parts of each zone you haven't explored are
--  drawn as if you had. Optionally tinted darker so you can tell them apart.
--
--  The game only hands out the overlays you've explored
--  (C_MapExplorationInfo.GetExploredMapTextures). Every overlay a map has is
--  in MapData.lua, built from the game's own map tables. Blizzard's
--  exploration pin draws the explored ones; after each of its refreshes we
--  draw the rest on a frame of our own laid over the pin, with the same
--  tiling maths, so nothing of Blizzard's pin or its texture pools is touched.
--
--  A guard against data that doesn't fit this client: if you've explored
--  part of a map and none of those overlays are in our data for it, we
--  draw nothing on that map rather than the wrong art.
--------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
if not (EvermoreUI and EvermoreUI.NewModule) then return end
local EV = EvermoreUI
local L = EV.L
local ceil, max = math.ceil, math.max

local M = EV:NewModule("MapReveal", {
    tint = false,   -- draw unexplored areas darker
    shade = 0.6,    -- their brightness when tinted
})
M.title = "Whole Map"
M.description = "Reveals the whole world map, including the parts you haven't explored yet."
ns.mapReveal = M

local overlays = setmetatable({}, { __mode = "k" })   -- pin -> our frame

local function Layer(pin)
    local f = overlays[pin]
    if f then return f end
    f = CreateFrame("Frame", nil, pin)
    f:SetAllPoints(pin)
    f:EnableMouse(false)
    f.textures = {}
    overlays[pin] = f
    return f
end

local function Clear(f)
    for _, t in ipairs(f.textures) do t:Hide() end
    f.used = 0
end

local function Texture(f, layer, sub)
    f.used = f.used + 1
    local t = f.textures[f.used]
    if not t then
        t = f:CreateTexture(nil, layer, nil, sub)
        f.textures[f.used] = t
    else
        t:SetDrawLayer(layer, sub)
    end
    t:ClearAllPoints()
    return t
end

local function Draw(pin)
    local f = Layer(pin)
    Clear(f)
    if not M:IsEnabled() then return end
    local canvas = pin.GetMap and pin:GetMap()
    local mapID = canvas and canvas:GetMapID()
    local list = mapID and ns.MapOverlays and ns.MapOverlays[mapID]
    if not list then return end

    -- What's explored already, by first tile.
    local explored = C_MapExplorationInfo.GetExploredMapTextures(mapID) or {}
    local have, known = {}, {}
    for _, e in ipairs(list) do known[e[5]] = true end
    local matched, total = 0, 0
    for _, e in ipairs(explored) do
        local first = e.fileDataIDs and e.fileDataIDs[1]
        if first then
            have[first] = true
            total = total + 1
            if known[first] then matched = matched + 1 end
        end
    end
    if total > 0 and matched == 0 then return end   -- our data isn't this client's

    local layers = C_Map.GetMapArtLayers(mapID)
    local index = canvas.GetCanvasContainer and canvas:GetCanvasContainer():GetCurrentLayerIndex() or 1
    local info = layers and (layers[index] or layers[1])
    if not info then return end
    local TW, TH = info.tileWidth, info.tileHeight
    local layer, sub = "ARTWORK", 0
    if pin.dataProvider and pin.dataProvider.GetDrawLayer then layer, sub = pin.dataProvider:GetDrawLayer() end
    local shade = M.db.tint and (M.db.shade or 1) or 1

    for _, e in ipairs(list) do
        if not have[e[5]] then
            local w, h, ox, oy = e[1], e[2], e[3], e[4]
            local wide, tall = ceil(w / TW), ceil(h / TH)
            for j = 1, tall do
                local ph, fh
                if j < tall then
                    ph, fh = TH, TH
                else
                    ph = h % TH
                    if ph == 0 then ph = TH end
                    fh = 16
                    while fh < ph do fh = fh * 2 end
                end
                for k = 1, wide do
                    local file = e[4 + (j - 1) * wide + k]
                    if file then
                        local pw, fw
                        if k < wide then
                            pw, fw = TW, TW
                        else
                            pw = w % TW
                            if pw == 0 then pw = TW end
                            fw = 16
                            while fw < pw do fw = fw * 2 end
                        end
                        local t = Texture(f, layer, sub)
                        t:SetSize(pw, ph)
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:SetPoint("TOPLEFT", f, "TOPLEFT", ox + TW * (k - 1), -(oy + TH * (j - 1)))
                        t:SetTexture(file, nil, nil, "TRILINEAR")
                        t:SetVertexColor(shade, shade, shade)
                        t:Show()
                    end
                end
            end
        end
    end
end

local hooked = setmetatable({}, { __mode = "k" })

local function HookPins()
    local map = WorldMapFrame
    if not (map and map.EnumeratePinsByTemplate) then return end
    for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        if not hooked[pin] and pin.RefreshOverlays then
            hooked[pin] = true
            hooksecurefunc(pin, "RefreshOverlays", function(self) ns.Safe("map reveal", Draw, self) end)
            ns.Safe("map reveal", Draw, pin)
        end
    end
end

function M:Refresh()
    for pin in pairs(overlays) do ns.Safe("map reveal", Draw, pin) end
end

local watching = false
local function Watch()
    if watching or not WorldMapFrame then return end
    watching = true
    WorldMapFrame:HookScript("OnShow", HookPins)
    HookPins()
end

function M:OnEnable()
    Watch()
    self:RegisterEvent("ADDON_LOADED", function(_, _, name)
        if name == "Blizzard_WorldMap" then Watch() end
    end)
end
