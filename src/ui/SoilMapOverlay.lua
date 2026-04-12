-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Soil Map Overlay
-- =========================================================
-- Renders per-farmland nutrient colors on the pause-menu
-- fullscreen map (ESC → Map).  A clickable sidebar panel
-- on the left edge of the map lets the player select which
-- soil layer to view.  Shift+M also cycles layers as a
-- keyboard shortcut.
--
-- Layers 0-9: Off, N, P, K, pH, OM, Urgency, Weed, Pest, Disease
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- =========================================================

---@class SoilMapOverlay
SoilMapOverlay = {}
local SoilMapOverlay_mt = Class(SoilMapOverlay)

-- ── Constants ─────────────────────────────────────────────
SoilMapOverlay.LAYER_COUNT    = 9
SoilMapOverlay.OVERLAY_W      = 512
SoilMapOverlay.OVERLAY_H      = 512
SoilMapOverlay.ALPHA          = 0.72
SoilMapOverlay.SIDEBAR_W_FRAC = 0.19   -- sidebar width as fraction of map width

-- Status colors (match SoilHUD palette)
SoilMapOverlay.C_POOR = {0.88, 0.25, 0.25}
SoilMapOverlay.C_FAIR = {0.90, 0.82, 0.18}
SoilMapOverlay.C_GOOD = {0.25, 0.85, 0.25}

-- Per-layer accent color shown as the left-edge bar in each sidebar button
SoilMapOverlay.LAYER_ACCENT = {
    [0] = {0.45, 0.45, 0.45},  -- Off:     grey
    [1] = {0.20, 0.55, 1.00},  -- N:       blue
    [2] = {1.00, 0.55, 0.10},  -- P:       orange
    [3] = {0.65, 0.25, 0.90},  -- K:       purple
    [4] = {0.10, 0.78, 0.75},  -- pH:      teal
    [5] = {0.60, 0.35, 0.10},  -- OM:      brown
    [6] = {0.95, 0.25, 0.25},  -- Urgency: red
    [7] = {0.20, 0.70, 0.20},  -- Weed:    dark green
    [8] = {0.85, 0.75, 0.10},  -- Pest:    amber
    [9] = {0.80, 0.10, 0.80},  -- Disease: magenta
}

-- i18n key per layer index (0 = Off)
SoilMapOverlay.LAYER_KEYS = {
    [0] = "sf_map_layer_off",
    [1] = "sf_map_layer_n",
    [2] = "sf_map_layer_p",
    [3] = "sf_map_layer_k",
    [4] = "sf_map_layer_ph",
    [5] = "sf_map_layer_om",
    [6] = "sf_map_layer_urgency",
    [7] = "sf_map_layer_weed",
    [8] = "sf_map_layer_pest",
    [9] = "sf_map_layer_disease",
}

-- Inverted layers: high value = bad (urgency / pressures)
SoilMapOverlay.INVERTED_LAYERS = {[6]=true,[7]=true,[8]=true,[9]=true}

-- ── Constructor ───────────────────────────────────────────

---@param soilSystem SoilFertilitySystem
---@param settings Settings
---@return SoilMapOverlay
function SoilMapOverlay.new(soilSystem, settings)
    local self = setmetatable({}, SoilMapOverlay_mt)
    self.soilSystem    = soilSystem
    self.settings      = settings
    self.overlayHandle = nil   -- density-map overlay handle
    self.fillOverlay   = nil   -- pixel fill overlay for sidebar rectangles
    self.isGenerating  = false
    self.isReady       = false
    self.pendingRegen  = false
    self._drawHook     = nil
    self._openHook     = nil
    self._closeHook    = nil
    self._mouseHook    = nil
    self.isMapOpen     = false
    -- Button rects updated each draw frame: {x, y, w, h, layer}
    self.buttonRects   = {}
    return self
end

-- ── Initialize ────────────────────────────────────────────

function SoilMapOverlay:initialize()
    -- Density-map overlay for per-farmland field coloring
    if createDensityMapVisualizationOverlay then
        self.overlayHandle = createDensityMapVisualizationOverlay(
            "soilNutrientState", SoilMapOverlay.OVERLAY_W, SoilMapOverlay.OVERLAY_H)
        if not self.overlayHandle or self.overlayHandle == 0 then
            SoilLogger.warning("SoilMapOverlay: density overlay handle invalid")
            self.overlayHandle = nil
        else
            SoilLogger.info("SoilMapOverlay: density overlay created (handle=%s)", tostring(self.overlayHandle))
        end
    else
        SoilLogger.warning("SoilMapOverlay: createDensityMapVisualizationOverlay not available")
    end

    -- Pixel fill overlay used for drawing sidebar rectangles
    if createImageOverlay then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    if not IngameMapElement then
        SoilLogger.warning("SoilMapOverlay: IngameMapElement not available — hooks skipped")
        return
    end

    local overlay = self

    -- Helper: returns true only for the fullscreen PDA map element, not the
    -- farm-overview preview (IngameMapPreviewElement). The preview element does
    -- not have ingameMap.isFullscreen and calling setCustomLayout on its nil
    -- internal state crashes the game (IngameMapPreviewElement.lua:48/64).
    local function isFullscreenMap(mapElem)
        return mapElem
            and mapElem.ingameMap ~= nil
            and mapElem.ingameMap.isFullscreen == true
    end

    -- Draw hook: renders the sidebar + density overlay on the fullscreen map each frame
    self._drawHook = function(mapElem)
        if isFullscreenMap(mapElem)
           and overlay and g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay then
            overlay:onMapElementDraw(mapElem)
        end
    end
    IngameMapElement.draw = Utils.appendedFunction(IngameMapElement.draw, self._drawHook)

    -- Open hook: mark map open + trigger overlay generation when player opens map
    self._openHook = function(mapElem)
        if isFullscreenMap(mapElem)
           and overlay and g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay then
            overlay.isMapOpen = true
            overlay:requestGenerate()
        end
    end
    IngameMapElement.onOpen = Utils.appendedFunction(IngameMapElement.onOpen, self._openHook)

    -- Close hook: clear map-open flag
    self._closeHook = function(mapElem)
        if isFullscreenMap(mapElem)
           and overlay and g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay then
            overlay.isMapOpen = false
        end
    end
    IngameMapElement.onClose = Utils.appendedFunction(IngameMapElement.onClose, self._closeHook)

    -- Mouse hook: handle sidebar button clicks on the fullscreen map.
    -- Appended so IngameMapElement's own handler (zoom/pan) runs first; we only
    -- consume clicks that land within our sidebar button rects.
    self._mouseHook = function(mapElem, posX, posY, isDown, isUp, button, eventUsed)
        if not eventUsed and isFullscreenMap(mapElem)
           and overlay and g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay then
            if overlay:onMapMouseEvent(posX, posY, isDown, isUp, button) then
                return true   -- consumed — prevents further propagation
            end
        end
        return eventUsed
    end
    IngameMapElement.mouseEvent = Utils.appendedFunction(IngameMapElement.mouseEvent, self._mouseHook)

    SoilLogger.info("SoilMapOverlay: hooks installed (draw / onOpen / onClose / mouseEvent)")
end

-- ── Delete ────────────────────────────────────────────────

function SoilMapOverlay:delete()
    if self.overlayHandle and self.overlayHandle ~= 0 and delete then
        delete(self.overlayHandle)
        self.overlayHandle = nil
    end
    if self.fillOverlay and self.fillOverlay ~= 0 and delete then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    -- Hooks guard against nil soilMapOverlay — no explicit removal needed
    SoilLogger.info("SoilMapOverlay: deleted")
end

-- ── Layer selection ───────────────────────────────────────

-- Cycle to the next layer (keyboard shortcut via Shift+M)
function SoilMapOverlay:cycleLayer()
    local current = self.settings.activeMapLayer or 0
    local next = (current + 1) % (SoilMapOverlay.LAYER_COUNT + 1)
    self:setLayer(next)
end

-- Set a specific layer by index (0 = Off)
function SoilMapOverlay:setLayer(layerIdx)
    self.settings.activeMapLayer = layerIdx
    self.settings:save()
    self.isReady = false
    self:requestGenerate()
    SoilLogger.debug("SoilMapOverlay: layer set to %d", layerIdx)
end

-- ── Async generation ──────────────────────────────────────

function SoilMapOverlay:requestGenerate()
    local layerIdx = self.settings.activeMapLayer or 0
    if layerIdx <= 0 then return end
    if not self.overlayHandle or self.overlayHandle == 0 then return end
    if not resetDensityMapVisualizationOverlay then return end

    if self.isGenerating then
        self.pendingRegen = true
        return
    end

    resetDensityMapVisualizationOverlay(self.overlayHandle)

    if not g_farmlandManager then return end
    local map = g_farmlandManager:getLocalMap()
    if not map then
        SoilLogger.warning("SoilMapOverlay: g_farmlandManager:getLocalMap() returned nil")
        return
    end

    local numChannels = (getBitVectorMapNumChannels and getBitVectorMapNumChannels(map)) or 8

    if g_fieldManager and g_fieldManager.fields then
        for _, field in pairs(g_fieldManager.fields) do
            if field and field.farmland then
                local farmlandId = field.farmland.id
                if farmlandId and farmlandId > 0 then
                    local info = self.soilSystem:getFieldInfo(farmlandId)
                    if info then
                        local r, g, b = self:getLayerColor(layerIdx, info, farmlandId)
                        if setDensityMapVisualizationOverlayStateColor then
                            setDensityMapVisualizationOverlayStateColor(
                                self.overlayHandle, map,
                                0, 0, 0, numChannels,
                                farmlandId, r, g, b)
                        end
                    end
                end
            end
        end
    end

    if generateDensityMapVisualizationOverlay then
        generateDensityMapVisualizationOverlay(self.overlayHandle)
        self.isGenerating = true
        self.pendingRegen = false
        SoilLogger.debug("SoilMapOverlay: generation started for layer %d", layerIdx)
    end
end

-- ── Draw (called each frame by hook) ─────────────────────

function SoilMapOverlay:onMapElementDraw(mapElem)
    if not mapElem or not mapElem.ingameMap then return end
    if not mapElem.ingameMap.isFullscreen then return end

    local layerIdx = self.settings.activeMapLayer or 0

    -- Poll async generation readiness
    if self.isGenerating and self.overlayHandle and self.overlayHandle ~= 0 then
        if getIsDensityMapVisualizationOverlayReady and
           getIsDensityMapVisualizationOverlayReady(self.overlayHandle) then
            self.isReady      = true
            self.isGenerating = false
            SoilLogger.debug("SoilMapOverlay: overlay ready")
            if self.pendingRegen then self:requestGenerate() end
        end
    end

    local ingameMap        = mapElem.ingameMap
    local mapX, mapY       = ingameMap:getPosition()
    local mapW             = ingameMap:getWidth()
    local mapH             = ingameMap:getHeight()
    local sidebarW         = mapW * SoilMapOverlay.SIDEBAR_W_FRAC

    -- Render the density overlay in the non-sidebar area so it doesn't bleed under the panel
    if layerIdx > 0 and self.isReady and self.overlayHandle and self.overlayHandle ~= 0 then
        if setOverlayColor then setOverlayColor(self.overlayHandle, 1, 1, 1, SoilMapOverlay.ALPHA) end
        if renderOverlay then
            renderOverlay(self.overlayHandle, mapX + sidebarW, mapY, mapW - sidebarW, mapH)
        end
    end

    -- Draw the clickable sidebar
    self:drawSidebar(mapX, mapY, mapW, mapH, layerIdx)
end

-- ── Sidebar ───────────────────────────────────────────────

-- Draws the left-side layer selector panel and stores button rects for click detection.
-- Layout (bottom-up Y, as FS25 uses OpenGL convention where Y=0 is screen bottom):
--   Layer 0 (Off)    → top row    (rowY = mapY + mapH - rowH)
--   Layer 1 (N)      → second row (rowY = mapY + mapH - 2*rowH)
--   ...
--   Layer 9 (Disease)→ bottom row (rowY = mapY)
function SoilMapOverlay:drawSidebar(mapX, mapY, mapW, mapH, layerIdx)
    if not self.fillOverlay or self.fillOverlay == 0 then return end
    if not renderOverlay or not renderText then return end

    local numRows   = SoilMapOverlay.LAYER_COUNT + 1   -- 10 entries: 0..9
    local sideW     = mapW * SoilMapOverlay.SIDEBAR_W_FRAC
    local rowH      = mapH / numRows
    local accentW   = sideW * 0.06
    local fontSize  = math.min(rowH * 0.30, 0.013)
    local textPadL  = accentW + sideW * 0.06

    -- Clear stale button rects (rebuilt fresh each frame)
    self.buttonRects = {}

    -- Full panel background
    setOverlayColor(self.fillOverlay, 0.04, 0.04, 0.06, 0.90)
    renderOverlay(self.fillOverlay, mapX, mapY, sideW, mapH)

    -- Panel title at the very top (above layer rows)
    local titleFontSize = math.min(rowH * 0.27, 0.009)
    local titleText = (g_i18n and g_i18n:getText("sf_map_panel_title")) or "Soil Nutrients"
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(0.65, 0.65, 0.75, 1.0)
    -- Place title above row 0's top edge
    local titleY = mapY + mapH + titleFontSize * 0.1
    -- If there's space above the rows, use it; otherwise overlap top of first row
    renderText(mapX + sideW * 0.5, mapY + mapH - titleFontSize * 1.6, titleFontSize, titleText)
    setTextBold(false)

    -- Separator below title
    setOverlayColor(self.fillOverlay, 0.28, 0.28, 0.38, 0.80)
    renderOverlay(self.fillOverlay, mapX, mapY + mapH - fontSize * 2.2, sideW, 0.001)

    for i = 0, SoilMapOverlay.LAYER_COUNT do
        -- Row Y: layer 0 at top, layer 9 at bottom
        -- We place title above all rows, so rows start a little lower
        local rowY = mapY + mapH - (i + 1) * rowH

        local isActive = (i == layerIdx)

        -- Active row highlight
        if isActive then
            setOverlayColor(self.fillOverlay, 0.10, 0.10, 0.20, 1.0)
            renderOverlay(self.fillOverlay, mapX, rowY, sideW, rowH)
        end

        -- Left-edge accent bar
        local ac = SoilMapOverlay.LAYER_ACCENT[i] or {0.5, 0.5, 0.5}
        setOverlayColor(self.fillOverlay, ac[1], ac[2], ac[3], isActive and 1.0 or 0.55)
        renderOverlay(self.fillOverlay, mapX, rowY, accentW, rowH)

        -- Row separator line
        setOverlayColor(self.fillOverlay, 0.18, 0.18, 0.25, 0.55)
        renderOverlay(self.fillOverlay, mapX, rowY, sideW, 0.0008)

        -- Layer name
        local key  = SoilMapOverlay.LAYER_KEYS[i] or ("sf_map_layer_" .. i)
        local name = (g_i18n and g_i18n:getText(key)) or key
        local textY = rowY + rowH * 0.32

        setTextAlignment(RenderText.ALIGN_LEFT)
        if isActive then
            setTextColor(1.0, 1.0, 1.0, 1.0)
            setTextBold(true)
        else
            setTextColor(0.72, 0.72, 0.76, 1.0)
            setTextBold(false)
        end
        renderText(mapX + textPadL, textY, fontSize, name)

        -- For the active (non-Off) layer: draw three status swatches (Poor/Fair/Good)
        -- on the right side of the row so the player knows what the colors mean
        if isActive and i > 0 then
            local swatchSz   = rowH * 0.22
            local swatchGap  = swatchSz * 0.20
            local totalW     = 3 * swatchSz + 2 * swatchGap
            local sx         = mapX + sideW - totalW - sideW * 0.04
            local sy         = rowY + (rowH - swatchSz) * 0.5

            local isInv  = SoilMapOverlay.INVERTED_LAYERS[i]
            local colors = isInv
                and {SoilMapOverlay.C_GOOD, SoilMapOverlay.C_FAIR, SoilMapOverlay.C_POOR}
                or  {SoilMapOverlay.C_POOR, SoilMapOverlay.C_FAIR, SoilMapOverlay.C_GOOD}

            for s = 1, 3 do
                local col = colors[s]
                setOverlayColor(self.fillOverlay, col[1], col[2], col[3], 0.92)
                renderOverlay(self.fillOverlay, sx + (s - 1) * (swatchSz + swatchGap), sy, swatchSz, swatchSz)
            end
        end

        -- Store button rect for click detection
        table.insert(self.buttonRects, {x = mapX, y = rowY, w = sideW, h = rowH, layer = i})
    end

    -- Reset render state
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Mouse click handler ───────────────────────────────────

-- Called from the IngameMapElement.mouseEvent hook (fullscreen map only).
-- Returns true if a sidebar button was clicked (event consumed).
function SoilMapOverlay:onMapMouseEvent(posX, posY, isDown, isUp, button)
    if not isDown then return false end
    if button ~= Input.MOUSE_BUTTON_LEFT then return false end
    if not self.buttonRects or #self.buttonRects == 0 then return false end

    for _, rect in ipairs(self.buttonRects) do
        if posX >= rect.x and posX <= rect.x + rect.w
           and posY >= rect.y and posY <= rect.y + rect.h then
            self:setLayer(rect.layer)
            return true
        end
    end
    return false
end

-- ── Layer color logic ─────────────────────────────────────

---@param layerIdx number  1–9 (caller guarantees > 0)
---@param info     table   return of SoilFertilitySystem:getFieldInfo()
---@param farmlandId number
---@return number r, number g, number b
function SoilMapOverlay:getLayerColor(layerIdx, info, farmlandId)
    local POOR = SoilMapOverlay.C_POOR
    local FAIR = SoilMapOverlay.C_FAIR
    local GOOD = SoilMapOverlay.C_GOOD
    local T    = SoilConstants.STATUS_THRESHOLDS

    -- Layer 1: Nitrogen
    if layerIdx == 1 then
        local v = info.nitrogen and info.nitrogen.value or 0
        if v < T.nitrogen.poor     then return POOR[1], POOR[2], POOR[3]
        elseif v < T.nitrogen.fair then return FAIR[1], FAIR[2], FAIR[3]
        else                            return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 2: Phosphorus
    elseif layerIdx == 2 then
        local v = info.phosphorus and info.phosphorus.value or 0
        if v < T.phosphorus.poor     then return POOR[1], POOR[2], POOR[3]
        elseif v < T.phosphorus.fair then return FAIR[1], FAIR[2], FAIR[3]
        else                              return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 3: Potassium
    elseif layerIdx == 3 then
        local v = info.potassium and info.potassium.value or 0
        if v < T.potassium.poor     then return POOR[1], POOR[2], POOR[3]
        elseif v < T.potassium.fair then return FAIR[1], FAIR[2], FAIR[3]
        else                             return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 4: pH (6.5–7.0 = good, 5.5–7.5 = fair, outside = poor)
    elseif layerIdx == 4 then
        local pH = info.pH or 7.0
        if pH >= 6.5 and pH <= 7.0 then     return GOOD[1], GOOD[2], GOOD[3]
        elseif pH >= 5.5 and pH <= 7.5 then return FAIR[1], FAIR[2], FAIR[3]
        else                                return POOR[1], POOR[2], POOR[3] end

    -- Layer 5: Organic Matter (≥4.0 = good, ≥2.5 = fair, else poor)
    elseif layerIdx == 5 then
        local om = info.organicMatter or 0
        if om >= 4.0     then return GOOD[1], GOOD[2], GOOD[3]
        elseif om >= 2.5 then return FAIR[1], FAIR[2], FAIR[3]
        else                  return POOR[1], POOR[2], POOR[3] end

    -- Layer 6: Urgency (inverted)
    elseif layerIdx == 6 then
        local u = self.soilSystem:getFieldUrgency(farmlandId)
        if u > 66     then return POOR[1], POOR[2], POOR[3]
        elseif u > 33 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 7: Weed Pressure (inverted)
    elseif layerIdx == 7 then
        local v = info.weedPressure or 0
        if v > 50     then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 8: Pest Pressure (inverted)
    elseif layerIdx == 8 then
        local v = info.pestPressure or 0
        if v > 50     then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 9: Disease Pressure (inverted)
    elseif layerIdx == 9 then
        local v = info.diseasePressure or 0
        if v > 50     then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end
    end

    return GOOD[1], GOOD[2], GOOD[3]   -- fallback
end

SoilLogger.info("SoilMapOverlay loaded")
