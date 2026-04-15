---@class SoilMapOverlay
SoilMapOverlay = {}
local SoilMapOverlay_mt = Class(SoilMapOverlay)

-- ── Constants ─────────────────────────────────────────────
SoilMapOverlay.LAYER_COUNT    = 9
SoilMapOverlay.ALPHA          = 0.72

-- Sampling constants from DMF
SoilMapOverlay.SAMPLE_UPDATE_INTERVAL_MS = 4500
SoilMapOverlay.SAMPLE_GRID_COUNT = 34
SoilMapOverlay.MAX_POINTS = 850

-- Status colors (match SoilHUD palette)
SoilMapOverlay.C_POOR = {0.88, 0.25, 0.25}
SoilMapOverlay.C_FAIR = {0.90, 0.82, 0.18}
SoilMapOverlay.C_GOOD = {0.25, 0.85, 0.25}

-- Per-layer accent color
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
    
    self.samplePoints = {}
    self.displayValues = nil
    self.nextSampleUpdateTime = 0
    self.isMapOpen = false
    
    -- Manual Button Rects for click detection
    self.buttonRects = {}
    
    return self
end

-- ── Initialize ────────────────────────────────────────────

function SoilMapOverlay:initialize()
    SoilLogger.info("SoilMapOverlay: initialized (DMF Heatmap Mode)")
end

-- ── Delete ────────────────────────────────────────────────

function SoilMapOverlay:delete()
    if self.pointPool then self.pointPool:clear() end
    self.samplePoints = {}
    SoilLogger.info("SoilMapOverlay: deleted")
end

-- ── PDA Integration ───────────────────────────────────────

function SoilMapOverlay:getDisplayValues()
    -- Return empty table to keep native code happy, but we draw manually
    return {}
end

function SoilMapOverlay:getAverageHealth()
    if not self.soilSystem or not self.soilSystem.fieldData then return 0.75 end
    
    local sum = 0
    local count = 0
    for farmlandId, _ in pairs(self.soilSystem.fieldData) do
        sum = sum + self.soilSystem:getFieldUrgency(farmlandId)
        count = count + 1
    end
    
    if count == 0 then return 1.0 end
    
    local avgUrgency = sum / count
    return math.clamp(1.0 - (avgUrgency / 100), 0, 1)
end

function SoilMapOverlay:getDefaultFilterState()
    return {}
end

function SoilMapOverlay:getSelectedFilterCount(filterStates)
    return 0
end

function SoilMapOverlay:requestRefresh()
    self.nextSampleUpdateTime = 0
end

-- ── Layer selection ───────────────────────────────────────

function SoilMapOverlay:setLayer(layerIdx)
    if self.settings.activeMapLayer == layerIdx then return end
    self.settings.activeMapLayer = layerIdx
    self:requestRefresh()
    SoilLogger.info("SoilMapOverlay: layer set to %d (%s)", layerIdx, g_i18n:getText(SoilMapOverlay.LAYER_KEYS[layerIdx] or "unknown"))
end

-- ── Sidebar Clicks ────────────────────────────────────────

function SoilMapOverlay:onSideBarClick(posX, posY)
    for _, rect in ipairs(self.buttonRects) do
        if posX >= rect.x1 and posX <= rect.x2 and posY >= rect.y1 and posY <= rect.y2 then
            self:setLayer(rect.index)
            return true
        end
    end
    return false
end

-- ── Point Sampling (DMF Pattern) ─────────────────────────

function SoilMapOverlay:updateSamplePoints(force)
    local now = (g_currentMission and g_currentMission.time) or g_time or 0
    if not force and now < self.nextSampleUpdateTime then
        return
    end

    self.nextSampleUpdateTime = now + SoilMapOverlay.SAMPLE_UPDATE_INTERVAL_MS
    
    -- Return existing points to the pool to prevent GC stutters
    for _, pt in ipairs(self.samplePoints) do
        self.pointPool:returnToPool(pt)
    end
    table.clear(self.samplePoints)

    local layerIdx = self.settings.activeMapLayer or 0
    if layerIdx <= 0 then 
        SoilLogger.debug("SoilMapOverlay: No active layer selected")
        return 
    end

    if g_currentMission == nil or g_farmlandManager == nil then
        SoilLogger.info("SoilMapOverlay: Sampling aborted - mission or farmlandManager nil")
        return
    end

    -- FS25 terrains are centered at 0,0. 2k map = -1024 to 1024.
    local worldSize = g_currentMission.terrainSize or 2048
    local half = worldSize * 0.5
    local gridCount = SoilMapOverlay.SAMPLE_GRID_COUNT
    local gridStep = worldSize / math.max(gridCount - 1, 1)

    for gx = 0, gridCount - 1 do
        local worldX = -half + gx * gridStep
        for gz = 0, gridCount - 1 do
            local worldZ = -half + gz * gridStep
            
            -- Filter: Only points on actual farmland
            local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(worldX, worldZ)
            if farmlandId and farmlandId > 0 then
                local info = self.soilSystem:getFieldInfo(farmlandId)
                if info then
                    local r, g, b = self:getLayerColor(layerIdx, info, farmlandId)
                    local pt = self.pointPool:getOrCreateNext()
                    pt.x = worldX
                    pt.z = worldZ
                    pt.r = r
                    pt.g = g
                    pt.b = b
                    table.insert(self.samplePoints, pt)
                end
            end
        end
    end

    -- Cap points if needed
    if #self.samplePoints > SoilMapOverlay.MAX_POINTS then
        for i = #self.samplePoints, SoilMapOverlay.MAX_POINTS + 1, -1 do
            local pt = table.remove(self.samplePoints, i)
            self.pointPool:returnToPool(pt)
        end
    end
    
    if #self.samplePoints > 0 then
        SoilLogger.info("SoilMapOverlay: Sampled %d points for layer %d", #self.samplePoints, layerIdx)
    else
        SoilLogger.info("SoilMapOverlay: No farmland points found in terrain (Sampled %d grid points, range %d to %d)", gridCount * gridCount, -half, half)
    end
end

-- ── Draw (called by hook) ────────────────────────────────

function SoilMapOverlay:onDraw(frame, mapElement, ingameMap, pageIndex)
    self:updateSamplePoints(false)

    if #self.samplePoints == 0 then return end

    -- Use the layout-based bounds (DFF pattern) — ingameMap:getPosition() does not exist.
    local mapX, mapY, mapWidth, mapHeight = self:getMapRenderBounds(frame, ingameMap)
    if mapX == nil or mapWidth == nil or mapHeight == nil then return end

    local layerIdx = self.settings.activeMapLayer or 0
    if layerIdx <= 0 then return end

    local mapMaxX = mapX + mapWidth
    local mapMaxY = mapY + mapHeight

    for _, point in ipairs(self.samplePoints) do
        local screenX, screenY = self:worldToScreenPosition(ingameMap, point.x, point.z)
        if screenX ~= nil and screenY ~= nil
           and screenX >= mapX and screenX <= mapMaxX
           and screenY >= mapY and screenY <= mapMaxY then
            local sizePx = 16
            local sizeX, sizeY = getNormalizedScreenValues(sizePx, sizePx)
            drawFilledRect(screenX - sizeX * 0.5, screenY - sizeY * 0.5, sizeX, sizeY,
                           point.r, point.g, point.b, 0.95)
        end
    end
end

function SoilMapOverlay:worldToScreenPosition(ingameMap, worldX, worldZ)
    if ingameMap == nil or ingameMap.layout == nil then return nil, nil end
    if ingameMap.layout.getMapObjectPosition == nil then return nil, nil end

    local worldSizeX = ingameMap.worldSizeX or g_currentMission.terrainSize or 2048
    local worldSizeZ = ingameMap.worldSizeZ or g_currentMission.terrainSize or 2048

    if worldSizeX == 0 or worldSizeZ == 0 then return nil, nil end

    -- DFF pattern: use worldCenterOffsetX/Z directly (0 for centered maps)
    local objectX = (worldX + (ingameMap.worldCenterOffsetX or 0)) / worldSizeX
    local objectZ = (worldZ + (ingameMap.worldCenterOffsetZ or 0)) / worldSizeZ

    objectX = objectX * (ingameMap.mapExtensionScaleFactor or 1) + (ingameMap.mapExtensionOffsetX or 0)
    objectZ = objectZ * (ingameMap.mapExtensionScaleFactor or 1) + (ingameMap.mapExtensionOffsetZ or 0)

    return ingameMap.layout:getMapObjectPosition(objectX, objectZ, 0, 0)
end

-- ── Sidebar Rendering ─────────────────────────────────────

function SoilMapOverlay:getSidebarBounds(frame)
    local minW, _ = getNormalizedScreenValues(230, 0)
    local marginX, marginY = getNormalizedScreenValues(8, 8)
    local safeX, safeY = getNormalizedScreenValues(6, 6)
    
    local panelX = safeX + marginX
    local panelWidth = minW

    if frame.filterList then
        panelX = frame.filterList.absPosition[1]
        panelWidth = frame.filterList.absSize[1]
    end

    -- Top Y starts below the selector - added extra margin to avoid dots clipping
    local topY = 0.82 
    if frame.mapOverviewSelector then
        local _, extraMargin = getNormalizedScreenValues(0, 45) -- Push buttons down
        topY = frame.mapOverviewSelector.absPosition[2] - extraMargin
    end

    return panelX, topY, panelWidth
end

function SoilMapOverlay:onDrawHud(frame)
    self.buttonRects = {}
    
    local panelX, topY, panelWidth = self:getSidebarBounds(frame)
    local _, buttonH = getNormalizedScreenValues(0, 38)
    local _, marginY = getNormalizedScreenValues(0, 4)
    local _, textSize = getNormalizedScreenValues(0, 15)
    local padX, _ = getNormalizedScreenValues(10, 0)
    local accentW, _ = getNormalizedScreenValues(4, 0)

    local activeIdx = self.settings.activeMapLayer or 0

    -- 1. Draw 9 Nutrient Buttons (from top down)
    local currentY = topY - buttonH
    for i = 1, SoilMapOverlay.LAYER_COUNT do
        local isActive = (i == activeIdx)
        
        local bgR, bgG, bgB = 0.05, 0.05, 0.05
        if isActive then bgR, bgG, bgB = 0.12, 0.12, 0.12 end
        drawFilledRect(panelX, currentY, panelWidth, buttonH, bgR, bgG, bgB, 0.85)
        
        local color = SoilMapOverlay.LAYER_ACCENT[i]
        drawFilledRect(panelX, currentY, accentW, buttonH, color[1], color[2], color[3], 1.0)
        
        if isActive then
            self:drawThinBorder(panelX, currentY, panelWidth, buttonH, 0.8, 0.8, 0.8, 0.5)
        end

        local key = SoilMapOverlay.LAYER_KEYS[i]
        local name = (g_i18n and g_i18n:getText(key)) or key
        
        setTextBold(isActive)
        setTextColor(isActive and 1 or 0.8, isActive and 1 or 0.8, isActive and 1 or 0.8, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        renderText(panelX + padX + accentW, currentY + buttonH * 0.3, textSize, name)
        
        table.insert(self.buttonRects, {
            x1 = panelX, y1 = currentY, 
            x2 = panelX + panelWidth, y2 = currentY + buttonH,
            index = i
        })

        currentY = currentY - buttonH - marginY
    end

    -- 2. Draw Health Summary (Anchored to BOTTOM area per DMF pattern)
    local _, summaryH = getNormalizedScreenValues(0, 74)
    local _, panelMargin = getNormalizedScreenValues(0, 8)
    local _, safeY = getNormalizedScreenValues(0, 6)
    local _, upOffset = getNormalizedScreenValues(0, 15) -- Extra push up
    
    local summaryY = safeY + panelMargin + upOffset
    -- Check if native buttons exist and are visible
    if frame.buttonDeselectAllText ~= nil and frame.buttonDeselectAllText:getIsVisible() then
        summaryY = frame.buttonDeselectAllText.absPosition[2] + frame.buttonDeselectAllText.absSize[2] + panelMargin + upOffset
    elseif frame.buttonHelpText ~= nil and frame.buttonHelpText:getIsVisible() then
        summaryY = frame.buttonHelpText.absPosition[2] + frame.buttonHelpText.absSize[2] + panelMargin + upOffset
    end
    
    self:drawSummaryAt(frame, panelX, summaryY, panelWidth, summaryH)
end

function SoilMapOverlay:drawSummaryAt(frame, panelX, panelY, panelWidth, panelHeight)
    local padX, padY = getNormalizedScreenValues(11, 9)
    local _, titleSize = getNormalizedScreenValues(0, 16)
    local _, statusSize = getNormalizedScreenValues(0, 13)
    local _, barHeight = getNormalizedScreenValues(0, 11)
    local _, rowGap = getNormalizedScreenValues(0, 8)
    local indicatorWidth, indicatorHeightPad = getNormalizedScreenValues(2, 2)

    local health = self:getAverageHealth()
    local healthPercent = math.floor(health * 100 + 0.5)
    
    local barX = panelX + padX
    local barY = panelY + padY + statusSize + rowGap
    local barWidth = panelWidth - padX * 2
    local headerY = barY + barHeight + rowGap
    local statusY = panelY + padY

    drawFilledRect(panelX, panelY, panelWidth, panelHeight, 0.03, 0.03, 0.03, 0.86)
    self:drawThinBorder(panelX, panelY, panelWidth, panelHeight, 0.62, 0.62, 0.62, 0.78)

    drawFilledRect(barX, barY, barWidth, barHeight, 0.12, 0.12, 0.12, 0.94)
    self:drawHealthGradientBar(barX, barY, barWidth, barHeight)
    self:drawThinBorder(barX, barY, barWidth, barHeight, 0.82, 0.82, 0.82, 0.76)

    local markerX = barX + barWidth * health
    drawFilledRect(markerX - indicatorWidth * 0.5, barY - indicatorHeightPad, indicatorWidth, barHeight + indicatorHeightPad * 2, 1, 1, 1, 0.94)

    setTextBold(true)
    setTextColor(0.93, 0.93, 0.93, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(barX, headerY, titleSize, g_i18n:getText("sf_map_health_overall") or "Average Soil Health")

    setTextAlignment(RenderText.ALIGN_RIGHT)
    renderText(barX + barWidth, headerY, titleSize, string.format("%d%%", healthPercent))

    local statusText = "Growth Conditions: Optimal"
    if health < 0.4 then statusText = "Growth Conditions: Poor"
    elseif health < 0.7 then statusText = "Growth Conditions: Fair" end

    setTextBold(false)
    setTextColor(0.80, 0.80, 0.80, 0.95)
    setTextAlignment(RenderText.ALIGN_LEFT)
    renderText(barX, statusY, statusSize, statusText)
    
    setTextColor(1, 1, 1, 1)
end

function SoilMapOverlay:drawThinBorder(x, y, width, height, r, g, b, a)
    local borderX, borderY = getNormalizedScreenValues(1, 1)
    drawFilledRect(x - borderX, y - borderY, width + borderX * 2, borderY, r, g, b, a)
    drawFilledRect(x - borderX, y + height, width + borderX * 2, borderY, r, g, b, a)
    drawFilledRect(x - borderX, y, borderX, height, r, g, b, a)
    drawFilledRect(x + width, y, borderX, height, r, g, b, a)
end

function SoilMapOverlay:drawHealthGradientBar(x, y, width, height)
    local steps = 34
    local stepWidth = width / steps
    for i = 0, steps - 1 do
        local t = (i + 0.5) / steps
        local r, g, b
        if t <= 0.5 then
            local alpha = t / 0.5
            r = 0.88 + (0.90 - 0.88) * alpha
            g = 0.25 + (0.82 - 0.25) * alpha
            b = 0.25 + (0.18 - 0.25) * alpha
        else
            local alpha = (t - 0.5) / 0.5
            r = 0.90 + (0.25 - 0.90) * alpha
            g = 0.82 + (0.85 - 0.82) * alpha
            b = 0.18 + (0.25 - 0.18) * alpha
        end
        drawFilledRect(x + i * stepWidth, y, stepWidth + 0.00001, height, r, g, b, 0.94)
    end
end

function SoilMapOverlay:getMapRenderBounds(frame, ingameMap)
    local layout = nil
    if frame ~= nil and frame.ingameMapBase ~= nil and frame.ingameMapBase.fullScreenLayout ~= nil then
        layout = frame.ingameMapBase.fullScreenLayout
    elseif ingameMap ~= nil and ingameMap.fullScreenLayout ~= nil then
        layout = ingameMap.fullScreenLayout
    end

    if layout == nil or layout.getMapSize == nil or layout.getMapPosition == nil then
        return nil, nil, nil, nil
    end

    return layout:getMapPosition(), layout:getMapSize()
end

-- ── Layer color logic ─────────────────────────────────────

function SoilMapOverlay:getLayerColor(layerIdx, info, farmlandId)
    local POOR = SoilMapOverlay.C_POOR
    local FAIR = SoilMapOverlay.C_FAIR
    local GOOD = SoilMapOverlay.C_GOOD
    local T    = SoilConstants.STATUS_THRESHOLDS

    if layerIdx == 1 then
        local v = info.nitrogen and info.nitrogen.value or 0
        if v < T.nitrogen.poor     then return POOR[1], POOR[2], POOR[3]
        elseif v < T.nitrogen.fair then return FAIR[1], FAIR[2], FAIR[3]
        else                            return GOOD[1], GOOD[2], GOOD[3] end
    elseif layerIdx == 2 then
        local v = info.phosphorus and info.phosphorus.value or 0
        if v < T.phosphorus.poor     then return POOR[1], POOR[2], POOR[3]
        elseif v < T.phosphorus.fair then return FAIR[1], FAIR[2], FAIR[3]
        else                              return GOOD[1], GOOD[2], GOOD[3] end
    elseif layerIdx == 3 then
        local v = info.potassium and info.potassium.value or 0
        if v < T.potassium.poor     then return POOR[1], POOR[2], POOR[3]
        elseif v < T.potassium.fair then return FAIR[1], FAIR[2], FAIR[3]
        else                             return GOOD[1], GOOD[2], GOOD[3] end
    elseif layerIdx == 4 then
        local pH = info.pH or 7.0
        if pH >= 6.5 and pH <= 7.0 then     return GOOD[1], GOOD[2], GOOD[3]
        elseif pH >= 5.5 and pH <= 7.5 then return FAIR[1], FAIR[2], FAIR[3]
        else                                return POOR[1], POOR[2], POOR[3] end
    elseif layerIdx == 5 then
        local om = info.organicMatter or 0
        if om >= 4.0     then return GOOD[1], GOOD[2], GOOD[3]
        elseif om >= 2.5 then return FAIR[1], FAIR[2], FAIR[3]
        else                  return POOR[1], POOR[2], POOR[3] end
    elseif layerIdx == 6 then
        local u = self.soilSystem:getFieldUrgency(farmlandId)
        if u > 66     then return POOR[1], POOR[2], POOR[3]
        elseif u > 33 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end
    elseif layerIdx == 7 then
        local v = info.weedPressure or 0
        if v > 50     then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end
    elseif layerIdx == 8 then
        local v = info.pestPressure or 0
        if v > 50     then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end
    elseif layerIdx == 9 then
        local v = info.diseasePressure or 0
        if v > 50     then return POOR[1], POOR[2], POOR[3]
        elseif v > 20 then return FAIR[1], FAIR[2], FAIR[3]
        else               return GOOD[1], GOOD[2], GOOD[3] end
    end

    return GOOD[1], GOOD[2], GOOD[3]
end

SoilLogger.info("SoilMapOverlay loaded")