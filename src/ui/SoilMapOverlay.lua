-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Soil Map Overlay
-- =========================================================
-- Renders a colored overlay on the pause-menu fullscreen map
-- (ESC → Map) that colors each field by the selected soil
-- property. Uses the same density-map pipeline as the base
-- game's farmland ownership coloring.
--
-- Layer cycling: Shift+M (SF_CYCLE_MAP_LAYER action)
-- Layers 0-9: Off, N, P, K, pH, OM, Urgency, Weed, Pest, Disease
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilMapOverlay
SoilMapOverlay = {}
local SoilMapOverlay_mt = Class(SoilMapOverlay)

-- ── Constants ─────────────────────────────────────────────
SoilMapOverlay.LAYER_COUNT  = 9
SoilMapOverlay.OVERLAY_W    = 512
SoilMapOverlay.OVERLAY_H    = 512
SoilMapOverlay.ALPHA        = 0.70

-- Colors (match SoilHUD.C_POOR / C_FAIR / C_GOOD)
SoilMapOverlay.C_POOR  = {0.88, 0.25, 0.25}
SoilMapOverlay.C_FAIR  = {0.90, 0.82, 0.18}
SoilMapOverlay.C_GOOD  = {0.25, 0.85, 0.25}

-- Layer key names for legend display (index 0 = Off)
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

-- Layers 7-9 and 6 are "inverted" (high value = bad, so label accordingly)
SoilMapOverlay.INVERTED_LAYERS = {
    [6] = true,
    [7] = true,
    [8] = true,
    [9] = true,
}

-- ── Constructor ───────────────────────────────────────────

---@param soilSystem SoilFertilitySystem
---@param settings Settings
---@return SoilMapOverlay
function SoilMapOverlay.new(soilSystem, settings)
    local self = setmetatable({}, SoilMapOverlay_mt)
    self.soilSystem     = soilSystem
    self.settings       = settings
    self.overlayHandle  = nil   -- density-map overlay handle
    self.fillOverlay    = nil   -- plain image overlay for legend swatches
    self.isGenerating   = false
    self.isReady        = false
    self.pendingRegen   = false
    self._drawHook      = nil
    self._openHook      = nil
    return self
end

-- ── Initialize ────────────────────────────────────────────

function SoilMapOverlay:initialize()
    -- Create density-map visualization overlay (async, per-farmland coloring)
    if createDensityMapVisualizationOverlay then
        self.overlayHandle = createDensityMapVisualizationOverlay(
            "soilNutrientState",
            SoilMapOverlay.OVERLAY_W,
            SoilMapOverlay.OVERLAY_H
        )
        if self.overlayHandle and self.overlayHandle ~= 0 then
            SoilLogger.info("SoilMapOverlay: density overlay created (handle=%s)", tostring(self.overlayHandle))
        else
            SoilLogger.warning("SoilMapOverlay: createDensityMapVisualizationOverlay returned invalid handle")
            self.overlayHandle = nil
        end
    else
        SoilLogger.warning("SoilMapOverlay: createDensityMapVisualizationOverlay not available")
    end

    -- Pixel fill overlay used by legend swatch rectangles
    if createImageOverlay then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    -- Hook IngameMapElement:draw so we can render on top of the pause-menu map.
    -- Guard: ingameMap.isFullscreen == true ensures we skip the minimap context.
    if IngameMapElement then
        local overlay = self
        self._drawHook = function(mapElem)
            if overlay and g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay then
                overlay:onMapElementDraw(mapElem)
            end
        end
        IngameMapElement.draw = Utils.appendedFunction(IngameMapElement.draw, self._drawHook)

        -- Re-generate whenever the map is opened so data is fresh.
        self._openHook = function(mapElem)
            if overlay and g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay then
                overlay:requestGenerate()
            end
        end
        IngameMapElement.onOpen = Utils.appendedFunction(IngameMapElement.onOpen, self._openHook)

        SoilLogger.info("SoilMapOverlay: IngameMapElement draw/onOpen hooks installed")
    else
        SoilLogger.warning("SoilMapOverlay: IngameMapElement not available — hooks not installed")
    end
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
    -- Hooks guard against nil soilMapOverlay — nothing further to remove
    SoilLogger.info("SoilMapOverlay: deleted")
end

-- ── Layer cycling ─────────────────────────────────────────

function SoilMapOverlay:cycleLayer()
    local current = self.settings.activeMapLayer or 0
    -- Cycles 0 → 1 → 2 → ... → 9 → 0 (Off is reachable)
    local next = (current + 1) % (SoilMapOverlay.LAYER_COUNT + 1)
    self.settings.activeMapLayer = next
    self.settings:save()
    self.isReady = false
    self:requestGenerate()
    SoilLogger.debug("SoilMapOverlay: cycled to layer %d", next)
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

    -- Reset to transparent
    resetDensityMapVisualizationOverlay(self.overlayHandle)

    -- Get farmland density map
    if not g_farmlandManager then return end
    local map = g_farmlandManager:getLocalMap()
    if not map then
        SoilLogger.warning("SoilMapOverlay: g_farmlandManager:getLocalMap() returned nil")
        return
    end

    local numChannels = getBitVectorMapNumChannels and getBitVectorMapNumChannels(map) or 8

    -- Iterate all fields and set their farmland color
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
                                farmlandId, r, g, b
                            )
                        end
                    end
                end
            end
        end
    end

    if generateDensityMapVisualizationOverlay then
        generateDensityMapVisualizationOverlay(self.overlayHandle)
        self.isGenerating  = true
        self.pendingRegen  = false
        SoilLogger.debug("SoilMapOverlay: generation started for layer %d", layerIdx)
    end
end

-- ── Draw (called each frame by hook) ─────────────────────

function SoilMapOverlay:onMapElementDraw(mapElem)
    -- Only render on fullscreen pause-menu map
    if not mapElem or not mapElem.ingameMap then return end
    if not mapElem.ingameMap.isFullscreen then return end

    local layerIdx = self.settings.activeMapLayer or 0

    -- Check async generation readiness
    if self.isGenerating and self.overlayHandle and self.overlayHandle ~= 0 then
        if getIsDensityMapVisualizationOverlayReady then
            if getIsDensityMapVisualizationOverlayReady(self.overlayHandle) then
                self.isReady       = true
                self.isGenerating  = false
                SoilLogger.debug("SoilMapOverlay: overlay ready")
                if self.pendingRegen then
                    self:requestGenerate()
                end
            end
        end
    end

    -- Always draw the legend (even for Off layer, to show instructions)
    -- Get map position/size from the IngameMap element
    local ingameMap = mapElem.ingameMap
    local mapX, mapY = ingameMap:getPosition()
    local mapW = ingameMap:getWidth()
    local mapH = ingameMap:getHeight()

    -- Render density overlay when ready and layer is active
    if layerIdx > 0 and self.isReady and self.overlayHandle and self.overlayHandle ~= 0 then
        if setOverlayColor then
            setOverlayColor(self.overlayHandle, 1, 1, 1, SoilMapOverlay.ALPHA)
        end
        if renderOverlay then
            renderOverlay(self.overlayHandle, mapX, mapY, mapW, mapH)
        end
    end

    -- Draw legend panel
    self:drawLegend(mapX, mapY, mapW, mapH, layerIdx)
end

-- ── Legend ────────────────────────────────────────────────

function SoilMapOverlay:drawLegend(mapX, mapY, mapW, mapH, layerIdx)
    if not self.fillOverlay or self.fillOverlay == 0 then return end
    if not renderOverlay or not renderText then return end

    local cfg = SoilConstants.MAP_OVERLAY
    local margin  = cfg.LEGEND_MARGIN  * mapW
    local panelW  = cfg.LEGEND_W_FRAC  * mapW
    local panelH  = cfg.LEGEND_H_FRAC  * mapH

    -- Bottom-left of map + margin
    local panelX = mapX + margin
    local panelY = mapY + margin

    -- Background panel (dark semi-transparent)
    setOverlayColor(self.fillOverlay, 0.05, 0.05, 0.05, 0.78)
    renderOverlay(self.fillOverlay, panelX, panelY, panelW, panelH)

    -- Layer name (centered in panel)
    local layerKey = SoilMapOverlay.LAYER_KEYS[layerIdx] or "sf_map_layer_off"
    local layerName = g_i18n and g_i18n:getText(layerKey) or layerKey

    local titleFontSize = 0.009
    local titleX = panelX + panelW * 0.5
    local titleY = panelY + panelH - titleFontSize * 1.5
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(0.95, 0.95, 0.95, 1.0)
    renderText(titleX, titleY, titleFontSize, layerName)
    setTextBold(false)

    if layerIdx == 0 then
        -- Off layer: show key hint centered
        local hintFontSize = 0.007
        local hintText = g_i18n and g_i18n:getText("sf_map_overlay_cycle") or "Shift+M: Cycle Layer"
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextColor(0.70, 0.70, 0.70, 1.0)
        renderText(titleX, panelY + panelH * 0.35, hintFontSize, hintText)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(1, 1, 1, 1)
        return
    end

    -- Three swatches: Low / Med / High
    -- For inverted layers (urgency/pressure): Low=green, Med=yellow, High=red
    -- For normal layers (nutrients):          Low=red, Med=yellow, High=green
    local isInverted = SoilMapOverlay.INVERTED_LAYERS[layerIdx]
    local swatchColors, swatchLabels
    if isInverted then
        swatchColors = {SoilMapOverlay.C_GOOD, SoilMapOverlay.C_FAIR, SoilMapOverlay.C_POOR}
        swatchLabels = {
            g_i18n and g_i18n:getText("sf_map_overlay_low")  or "Low",
            g_i18n and g_i18n:getText("sf_map_overlay_med")  or "Med",
            g_i18n and g_i18n:getText("sf_map_overlay_high") or "High",
        }
    else
        swatchColors = {SoilMapOverlay.C_POOR, SoilMapOverlay.C_FAIR, SoilMapOverlay.C_GOOD}
        swatchLabels = {
            g_i18n and g_i18n:getText("sf_map_overlay_low")  or "Low",
            g_i18n and g_i18n:getText("sf_map_overlay_med")  or "Med",
            g_i18n and g_i18n:getText("sf_map_overlay_high") or "High",
        }
    end

    -- Swatch geometry
    local swatchFontSize = 0.0065
    local swatchH        = panelH * 0.22
    local swatchW        = swatchH * 1.2
    local swatchY        = panelY + panelH * 0.38
    local totalSwatchW   = 3 * swatchW
    local labelW         = panelW / 3
    local gapPerSlot     = labelW

    for i = 1, 3 do
        local slotX = panelX + (i - 1) * gapPerSlot
        local col   = swatchColors[i]
        local lbl   = swatchLabels[i]

        -- Swatch rectangle (centered in slot)
        local sx = slotX + (gapPerSlot - swatchW) * 0.5
        setOverlayColor(self.fillOverlay, col[1], col[2], col[3], 0.95)
        renderOverlay(self.fillOverlay, sx, swatchY, swatchW, swatchH)

        -- Label below swatch
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextColor(0.90, 0.90, 0.90, 1.0)
        renderText(slotX + gapPerSlot * 0.5, panelY + panelH * 0.12, swatchFontSize, lbl)
    end

    -- Key hint at very bottom
    local hintFontSize = 0.006
    local hintText = g_i18n and g_i18n:getText("sf_map_overlay_cycle") or "Shift+M: Cycle Layer"
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(0.60, 0.60, 0.60, 1.0)
    renderText(titleX, panelY + hintFontSize * 0.8, hintFontSize, hintText)

    -- Reset text state
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Layer color logic ─────────────────────────────────────

---@param layerIdx number 1-9
---@param info table  Return value of SoilFertilitySystem:getFieldInfo()
---@param farmlandId number (used for urgency layer)
---@return number r, number g, number b
function SoilMapOverlay:getLayerColor(layerIdx, info, farmlandId)
    local POOR = SoilMapOverlay.C_POOR
    local FAIR = SoilMapOverlay.C_FAIR
    local GOOD = SoilMapOverlay.C_GOOD
    local T    = SoilConstants.STATUS_THRESHOLDS

    -- Layer 1: Nitrogen
    if layerIdx == 1 then
        local v = info.nitrogen and info.nitrogen.value or 0
        if v < T.nitrogen.poor then return POOR[1], POOR[2], POOR[3]
        elseif v < T.nitrogen.fair then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 2: Phosphorus
    elseif layerIdx == 2 then
        local v = info.phosphorus and info.phosphorus.value or 0
        if v < T.phosphorus.poor then return POOR[1], POOR[2], POOR[3]
        elseif v < T.phosphorus.fair then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 3: Potassium
    elseif layerIdx == 3 then
        local v = info.potassium and info.potassium.value or 0
        if v < T.potassium.poor then return POOR[1], POOR[2], POOR[3]
        elseif v < T.potassium.fair then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 4: pH (6.5-7.0 = good, 5.5-7.5 = fair, outside = poor)
    elseif layerIdx == 4 then
        local pH = info.pH or 7.0
        if pH >= 6.5 and pH <= 7.0 then return GOOD[1], GOOD[2], GOOD[3]
        elseif pH >= 5.5 and pH <= 7.5 then return FAIR[1], FAIR[2], FAIR[3]
        else return POOR[1], POOR[2], POOR[3] end

    -- Layer 5: Organic Matter (>=4.0 = good, >=2.5 = fair, else poor)
    elseif layerIdx == 5 then
        local om = info.organicMatter or 0
        if om >= 4.0 then return GOOD[1], GOOD[2], GOOD[3]
        elseif om >= 2.5 then return FAIR[1], FAIR[2], FAIR[3]
        else return POOR[1], POOR[2], POOR[3] end

    -- Layer 6: Field Urgency (inverted: red = high urgency = needs attention)
    elseif layerIdx == 6 then
        local urgency = self.soilSystem:getFieldUrgency(farmlandId)
        if urgency > 66 then return POOR[1], POOR[2], POOR[3]
        elseif urgency > 33 then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 7: Weed Pressure (inverted: red = high pressure)
    elseif layerIdx == 7 then
        local v = info.weedPressure or 0
        if v > 50 then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 8: Pest Pressure (inverted)
    elseif layerIdx == 8 then
        local v = info.pestPressure or 0
        if v > 50 then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end

    -- Layer 9: Disease Pressure (inverted)
    elseif layerIdx == 9 then
        local v = info.diseasePressure or 0
        if v > 50 then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else return GOOD[1], GOOD[2], GOOD[3] end
    end

    -- Fallback (should never reach here)
    return GOOD[1], GOOD[2], GOOD[3]
end

SoilLogger.info("SoilMapOverlay loaded")
