-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.6.0)
-- =========================================================
-- Soil HUD Overlay - always-on display (like Precision Farming)
-- =========================================================
-- Author: TisonK
-- =========================================================
---@class SoilHUD

SoilHUD = {}
local SoilHUD_mt = Class(SoilHUD)

function SoilHUD.new(soilSystem, settings)
    local self = setmetatable({}, SoilHUD_mt)

    self.soilSystem = soilSystem
    self.settings = settings
    self.initialized = false
    self.backgroundOverlay = nil
    self.visible = true  -- Runtime visibility toggle (F8 key)

    -- Panel dimensions from constants
    self.panelWidth = SoilConstants.HUD.PANEL_WIDTH
    self.panelHeight = SoilConstants.HUD.PANEL_HEIGHT

    -- Position will be set based on hudPosition setting
    local defaultPos = SoilConstants.HUD.POSITIONS[1]
    self.panelX = defaultPos.x
    self.panelY = defaultPos.y
    self.lastHudPosition = nil  -- Track position changes

    return self
end

-- Calculate HUD position based on preset setting
function SoilHUD:updatePosition()
    local position = self.settings.hudPosition or 1

    -- Get position from constants (1=Top Right, 2=Top Left, 3=Bottom Right, 4=Bottom Left, 5=Center Right)
    local pos = SoilConstants.HUD.POSITIONS[position]
    if pos then
        self.panelX = pos.x
        self.panelY = pos.y
    end

    -- Update overlay position if it exists
    if self.backgroundOverlay and self.backgroundOverlay.setPosition then
        self.backgroundOverlay:setPosition(self.panelX, self.panelY)
    end
end

function SoilHUD:initialize()
    if self.initialized then return true end

    -- Set position based on user preference
    self:updatePosition()

    -- Create background overlay with a 1x1 white pixel (we'll color it black)
    -- Using g_baseUIFilename which is a tiny white texture built into FS25
    self.backgroundOverlay = Overlay.new(g_baseUIFilename, self.panelX, self.panelY, self.panelWidth, self.panelHeight)
    self.backgroundOverlay:setUVs(g_colorBgUVs)  -- Use solid color UVs
    self.backgroundOverlay:setColor(0, 0, 0, 0.7)  -- Semi-transparent black

    self.initialized = true
    SoilLogger.info("Soil HUD overlay initialized at position %d (%0.3f, %0.3f)",
        self.settings.hudPosition or 1, self.panelX, self.panelY)

    return true
end

function SoilHUD:delete()
    if self.backgroundOverlay then
        self.backgroundOverlay:delete()
        self.backgroundOverlay = nil
    end

    self.initialized = false
    SoilLogger.info("Soil HUD overlay deleted")
end

-- Update HUD (called every frame)
function SoilHUD:update(dt)
    -- Check if position setting changed and update if needed
    local currentPosition = self.settings.hudPosition or 1
    if self.lastHudPosition ~= currentPosition then
        self:updatePosition()
        self.lastHudPosition = currentPosition
        SoilLogger.info("HUD position changed to preset %d", currentPosition)
    end
end

-- Toggle HUD visibility (called by J key)
function SoilHUD:toggleVisibility()
    self.visible = not self.visible
    local message = self.visible and "Soil HUD shown" or "Soil HUD hidden"
    SoilLogger.info(message)

    -- Show in-game notification so user sees the toggle
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(message, 2000)
    end
end

--- Draw HUD (called every frame from main update loop)
--- RENDER ORDER NOTES:
--- - FS25 Giants Engine does not provide explicit Z-order/layer APIs for Overlays
--- - Render order is determined by callback timing and call order within frame
--- - This HUD renders during standard draw() phase, AFTER game UI initialization
--- - Visibility checks ensure we don't render over critical game UI elements
--- - If experiencing conflicts with other mods, adjust HUD position via settings
--- - Common compatible mods tested: Courseplay, AutoDrive, GPS mod, Precision Farming
---@return nil
--- Draw HUD (called every frame from main update loop)
function SoilHUD:draw()
    -- Basic initialization and visibility checks first
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end  -- Check persistent HUD setting
    if not self.visible then return end  -- Check runtime visibility toggle (F8)

    -- Don't draw if mission objects aren't ready yet
    if not g_currentMission then return end

    -- FIX: Less aggressive player/vehicle check
    -- Instead of requiring both player and vehicle, just try to get position
    -- If we can't get position, we'll show a "waiting" message
    local hasPositionSource = false
    
    -- Check if we have any way to get position
    if g_localPlayer then
        hasPositionSource = true
    elseif g_currentMission.player then
        hasPositionSource = true
    elseif g_currentMission.controlledVehicle then
        hasPositionSource = true
    elseif g_currentMission.camera then
        hasPositionSource = true
    end
    
    -- If no position source at all, don't draw (prevents errors)
    if not hasPositionSource then
        return
    end

    -- Don't draw over critical UI elements
    if g_gui then
        -- Check for menus/dialogs
        if g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible() then
            return
        end
    end

    -- Only hide for fullscreen/large map - overlay map is fine
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.ingameMap then
        local mapState = g_currentMission.hud.ingameMap.state
        -- STATE_LARGE_MAP = fullscreen map that covers everything
        -- Other states (minimap, overlay) are small and don't conflict with corner HUD
        if mapState == IngameMap.STATE_LARGE_MAP then
            return
        end
    end

    -- FIX: Make context-aware hiding optional or less aggressive
    -- Only hide during critical moments
    if g_currentMission then
        -- Hide during tutorials only if they're actually covering the screen
        if g_currentMission.inGameMessage and g_currentMission.inGameMessage.visible then
            -- Check if it's a full-screen tutorial message
            local messageType = g_currentMission.inGameMessage.type
            if messageType == "FULLSCREEN" or messageType == "LARGE" then
                return
            end
        end

        -- Hide in construction mode only when actively placing
        if g_currentMission.controlledVehicle == nil and g_currentMission.player then
            if g_currentMission.player.isCarryingObject then
                -- Check if actually in placement mode
                local placementMode = false
                local player = g_currentMission.player

                if player.getIsPlacementMode ~= nil then
                    placementMode = player:getIsPlacementMode()
                end
                if placementMode then
                    return
                end
            end
        end

        -- Context help (small popup showing key bindings) doesn't conflict with corner HUD
        -- Removed aggressive hiding - context help is usually at bottom center, HUD is in corner
    end

    -- FIX: Make mod compatibility checks optional via setting
    -- You could add a setting for this
    local checkModCompatibility = false  -- Set to false to disable mod checks
    if checkModCompatibility then
        -- Defensive mod compatibility: Check for other common mod UIs
        if g_Courseplay and g_Courseplay.globalSettings and g_Courseplay.globalSettings.showMiniHud == false then
            return
        end
    end

    -- Detect position ONCE per frame — reused for farmland lookup and field detection
    local worldX, worldZ = self:getCurrentPosition()
    local farmlandId = self:getFarmlandIdAtPosition(worldX, worldZ)

    -- Draw panel (always draw, even if no farmland)
    -- This ensures the HUD is visible
    self:drawPanel(farmlandId, worldX, worldZ)
end

--- Draw the HUD panel
--- worldX/worldZ are pre-computed by draw() to avoid redundant position detection
---@param farmlandId number|nil Current farmland ID (nil if not on farmland)
---@param worldX number|nil World X coordinate (cached from draw())
---@param worldZ number|nil World Z coordinate (cached from draw())
function SoilHUD:drawPanel(farmlandId, worldX, worldZ)
    -- Get customization settings
    local colorTheme = self.settings.hudColorTheme or 1
    local fontSize = self.settings.hudFontSize or 2
    local transparency = self.settings.hudTransparency or 3

    -- Validate and clamp HUD settings to valid ranges
    if colorTheme < 1 or colorTheme > 4 then
        SoilLogger.warning("HUD color theme out of range (%d) - clamping to 1-4", colorTheme)
        colorTheme = math.max(1, math.min(4, colorTheme))
    end
    local compactMode = self.settings.hudCompactMode or false

    -- Apply transparency to background overlay
    if self.backgroundOverlay then
        local alpha = SoilConstants.HUD.TRANSPARENCY_LEVELS[transparency]
        self.backgroundOverlay:setColor(0, 0, 0, alpha)
        self.backgroundOverlay:render()
    end

    -- Get color theme
    local theme = SoilConstants.HUD.COLOR_THEMES[colorTheme]
    local themeR, themeG, themeB = theme.r, theme.g, theme.b

    -- Get font size multiplier
    local fontMult = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[fontSize]

    -- Get line height based on compact mode
    local lineHeight = compactMode and SoilConstants.HUD.COMPACT_LINE_HEIGHT or SoilConstants.HUD.NORMAL_LINE_HEIGHT

    -- Enable text shadow for low transparency (better readability)
    local needsShadow = transparency <= 2
    if needsShadow then
        setTextShadow(true)
    end

    -- FIX: Rename these variables to avoid conflict with world position variables
    local screenX = self.panelX + 0.005  -- Small padding
    local screenY = self.panelY + self.panelHeight - 0.018  -- Start from top

    -- Title (always white, bold)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1.0, 1.0, 1.0, 1.0)
    renderText(screenX, screenY, 0.014 * fontMult, "SOIL INFO")
    screenY = screenY - lineHeight * 1.3

    -- Data color (use theme)
    setTextBold(false)
    setTextColor(themeR, themeG, themeB, 1.0)

    -- DEBUG: Only log when debug mode enabled
    if self.settings.debugMode then
        SoilLogger.info("[HUD DEBUG] farmlandId=%s, soilSystem=%s", tostring(farmlandId), tostring(self.soilSystem ~= nil))
    end

    if not farmlandId or farmlandId == 0 then
        -- Not in a farmland
        renderText(screenX, screenY, 0.012 * fontMult, "No farmland detected")
        if self.settings.debugMode then
            SoilLogger.info("[HUD DEBUG] No farmland ID detected")
        end
    else
        -- Check if soil system has initialized any fields yet
        local fieldCount = self.soilSystem:getFieldCount()
        if fieldCount == 0 then
            -- Soil system still initializing fields - show progress
            renderText(screenX, screenY, 0.012 * fontMult, string.format("Farmland %d", farmlandId))
            screenY = screenY - lineHeight

            -- Show scanning progress if available
            if self.soilSystem.fieldsScanPending and self.soilSystem.fieldsScanAttempts then
                local attempts = self.soilSystem.fieldsScanAttempts
                local maxAttempts = self.soilSystem.fieldsScanMaxAttempts
                renderText(screenX, screenY, 0.011 * fontMult,
                    string.format("Scanning fields... (%d/%d)", attempts, maxAttempts))
            else
                renderText(screenX, screenY, 0.011 * fontMult, "System initializing...")
            end

            screenY = screenY - lineHeight
            renderText(screenX, screenY, 0.010 * fontMult, string.format("%d fields ready", fieldCount))
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextBold(false)
            setTextColor(1, 1, 1, 1)
            if needsShadow then
                setTextShadow(false)
            end
            return
        end
        
        -- Find which field contains the pre-cached position
        local fieldId = nil

        if worldX and worldZ then
            fieldId = self:findFieldAtPosition(worldX, worldZ)
        end

        -- Farmland-based fallback: if position-based detection failed (or no position),
        -- find any field belonging to this farmland. This covers FS25 builds where
        -- getFieldAtWorldPosition/getContainsPoint APIs are unavailable.
        if not fieldId and farmlandId and g_fieldManager and g_fieldManager.fields then
            for _, f in pairs(g_fieldManager.fields) do
                if f and f.farmland and f.farmland.id == farmlandId and f.fieldId then
                    fieldId = f.fieldId
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Field via farmland fallback: field %d on farmland %d", fieldId, farmlandId)
                    end
                    break
                end
            end
        end
        
        if self.settings.debugMode then
            SoilLogger.info("[HUD DEBUG] Farmland %d, derived fieldId=%s", farmlandId, tostring(fieldId))
        end

        -- Get soil data - preferring live PF data if available
        local fieldInfo = nil
        local pfData = nil
        local usingPFData = false

        if fieldId and fieldId > 0 then
            -- If Precision Farming is active, try to read live PF data first
            if self.soilSystem.PFActive then
                pfData = self.soilSystem:readPFFieldData(fieldId)
                if pfData then
                    usingPFData = true
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Using live Precision Farming data for field %d", fieldId)
                    end
                end
            end

            -- If no PF data, fall back to SoilFertilizer data
            if not pfData then
                -- Try to get field info
                fieldInfo = self.soilSystem:getFieldInfo(fieldId)

                -- If field info is nil, try to initialize the field
                if not fieldInfo and self.soilSystem.getOrCreateField then
                    local field = self.soilSystem:getOrCreateField(fieldId, true)
                    if field then
                        -- Try again after creation
                        fieldInfo = self.soilSystem:getFieldInfo(fieldId)
                    end
                end
            end
        end

        if self.settings.debugMode then
            if pfData then
                SoilLogger.info("[HUD DEBUG] Field %d PF data: N=%d, P=%d, K=%d",
                    fieldId or -1,
                    pfData.nitrogen or -1,
                    pfData.phosphorus or -1,
                    pfData.potassium or -1)
            elseif fieldInfo then
                SoilLogger.info("[HUD DEBUG] Field %d data: N=%d, P=%d, K=%d",
                    fieldId or -1,
                    fieldInfo.nitrogen and fieldInfo.nitrogen.value or -1,
                    fieldInfo.phosphorus and fieldInfo.phosphorus.value or -1,
                    fieldInfo.potassium and fieldInfo.potassium.value or -1)
            else
                SoilLogger.info("[HUD DEBUG] No field info for fieldId=%s (farmland %d)",
                    tostring(fieldId), farmlandId)
            end
        end

        -- Display farmland number (to match base game "Farmland 1" style)
        renderText(screenX, screenY, 0.012 * fontMult, string.format("Farmland %d", farmlandId))
        screenY = screenY - lineHeight

        if not pfData and not fieldInfo then
            -- Show why data isn't available
            if not fieldId then
                renderText(screenX, screenY, 0.012 * fontMult, "No field data")
                screenY = screenY - lineHeight
                renderText(screenX, screenY, 0.011 * fontMult, "(Not cultivatable)")
            else
                renderText(screenX, screenY, 0.012 * fontMult, string.format("Field %d", fieldId))
                screenY = screenY - lineHeight
                renderText(screenX, screenY, 0.011 * fontMult, "Initializing...")
            end
        else
            -- Show field ID with PF indicator if using PF data
            if fieldId then
                if usingPFData then
                    renderText(screenX, screenY, 0.011 * fontMult, string.format("(Field %d - PF)", fieldId))
                else
                    renderText(screenX, screenY, 0.011 * fontMult, string.format("(Field %d)", fieldId))
                end
                screenY = screenY - lineHeight
            end

            -- Status color palette (Good=green, Fair=yellow, Poor=red)
            local STATUS_COLORS = {
                Good = {0.3, 0.9, 0.3, 1.0},
                Fair = {0.9, 0.9, 0.2, 1.0},
                Poor = {0.9, 0.3, 0.3, 1.0},
            }

            -- Helper: infer status from raw value (used for PF data path)
            local function inferStatus(val, nutrient)
                local t = SoilConstants.STATUS_THRESHOLDS[nutrient]
                if not t then return "?" end
                if val < t.poor then return "Poor"
                elseif val < t.fair then return "Fair"
                else return "Good" end
            end

            -- Extract values and status strings from the appropriate data source
            local nVal, pVal, kVal, phVal, omVal, lastCrop
            local nStatus, pStatus, kStatus
            local needsFertilization, daysSinceHarvest

            if pfData then
                nVal = pfData.nitrogen or 0
                pVal = pfData.phosphorus or 0
                kVal = pfData.potassium or 0
                phVal = pfData.pH or 0
                omVal = pfData.organicMatter or 0
                lastCrop = nil
                -- Infer status from PF raw values so display stays consistent
                nStatus = inferStatus(nVal, "nitrogen")
                pStatus = inferStatus(pVal, "phosphorus")
                kStatus = inferStatus(kVal, "potassium")
                needsFertilization = false  -- PF handles its own warnings
                daysSinceHarvest = 0
            elseif fieldInfo then
                nVal = (fieldInfo.nitrogen and fieldInfo.nitrogen.value) or 0
                pVal = (fieldInfo.phosphorus and fieldInfo.phosphorus.value) or 0
                kVal = (fieldInfo.potassium and fieldInfo.potassium.value) or 0
                phVal = fieldInfo.pH or 0
                omVal = fieldInfo.organicMatter or 0
                lastCrop = fieldInfo.lastCrop
                nStatus = (fieldInfo.nitrogen and fieldInfo.nitrogen.status) or inferStatus(nVal, "nitrogen")
                pStatus = (fieldInfo.phosphorus and fieldInfo.phosphorus.status) or inferStatus(pVal, "phosphorus")
                kStatus = (fieldInfo.potassium and fieldInfo.potassium.status) or inferStatus(kVal, "potassium")
                needsFertilization = fieldInfo.needsFertilization or false
                daysSinceHarvest = fieldInfo.daysSinceHarvest or 0
            else
                nVal, pVal, kVal, phVal, omVal = 0, 0, 0, 0, 0
                lastCrop = nil
                nStatus, pStatus, kStatus = "?", "?", "?"
                needsFertilization = false
                daysSinceHarvest = 0
            end

            local pfIndicator = usingPFData and " (PF)" or ""

            -- Compact mode uses single-letter status: G/F/P
            local function fmtStatus(s)
                if compactMode then
                    return s == "Good" and "G" or s == "Fair" and "F" or s == "Poor" and "P" or s
                end
                return s
            end

            -- N line — color-coded by status
            local nColor = STATUS_COLORS[nStatus] or {themeR, themeG, themeB, 1.0}
            setTextColor(table.unpack(nColor))
            renderText(screenX, screenY, 0.012 * fontMult,
                string.format("N: %d (%s)%s", nVal, fmtStatus(nStatus), pfIndicator))
            screenY = screenY - lineHeight

            -- P line
            local pColor = STATUS_COLORS[pStatus] or {themeR, themeG, themeB, 1.0}
            setTextColor(table.unpack(pColor))
            renderText(screenX, screenY, 0.012 * fontMult,
                string.format("P: %d (%s)%s", pVal, fmtStatus(pStatus), pfIndicator))
            screenY = screenY - lineHeight

            -- K line
            local kColor = STATUS_COLORS[kStatus] or {themeR, themeG, themeB, 1.0}
            setTextColor(table.unpack(kColor))
            renderText(screenX, screenY, 0.012 * fontMult,
                string.format("K: %d (%s)%s", kVal, fmtStatus(kStatus), pfIndicator))
            screenY = screenY - lineHeight

            -- pH line (theme color — no status thresholds defined for pH display)
            setTextColor(themeR, themeG, themeB, 1.0)
            renderText(screenX, screenY, 0.012 * fontMult, string.format("pH: %.1f%s", phVal, pfIndicator))
            screenY = screenY - lineHeight

            -- Organic matter (compact mode: combine with last crop)
            setTextColor(themeR, themeG, themeB, 1.0)
            if compactMode and lastCrop and lastCrop ~= "None" and lastCrop ~= "" then
                renderText(screenX, screenY, 0.012 * fontMult,
                    string.format("OM: %.1f%%%s | %s", omVal, pfIndicator, lastCrop))
            else
                renderText(screenX, screenY, 0.012 * fontMult,
                    string.format("OM: %.1f%%%s", omVal, pfIndicator))

                if lastCrop and lastCrop ~= "None" and lastCrop ~= "" then
                    screenY = screenY - lineHeight
                    setTextColor(themeR, themeG, themeB, 0.85)
                    renderText(screenX, screenY, 0.011 * fontMult, lastCrop)
                end
            end

            -- Fertilization warning (actionable, orange)
            if needsFertilization then
                screenY = screenY - lineHeight
                setTextColor(0.95, 0.5, 0.1, 1.0)
                renderText(screenX, screenY, 0.011 * fontMult, "! Needs fertilizer")
            end

            -- Days since harvest (only shown when a harvest has occurred)
            if daysSinceHarvest and daysSinceHarvest > 0 then
                screenY = screenY - lineHeight
                setTextColor(themeR, themeG, themeB, 0.65)
                renderText(screenX, screenY, 0.010 * fontMult,
                    string.format("Last: %d days ago", daysSinceHarvest))
            end
        end
    end

    -- Disable text shadow if it was enabled
    if needsShadow then
        setTextShadow(false)
    end

    -- Reset text settings
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

-- Helper function to get current position (extracted from getCurrentFarmlandId logic)
function SoilHUD:getCurrentPosition()
    local x, z

    -- Try g_localPlayer first
    if g_localPlayer then
        local success, px, py, pz = pcall(function()
            if g_localPlayer.getPosition then
                return g_localPlayer:getPosition()
            elseif g_localPlayer.rootNode and g_localPlayer.rootNode ~= 0 then
                return getWorldTranslation(g_localPlayer.rootNode)
            end
            return nil, nil, nil
        end)

        if success and px then
            x, z = px, pz
            return x, z
        elseif g_localPlayer.getIsInVehicle and g_localPlayer:getIsInVehicle() then
            local vehicle = g_localPlayer:getCurrentVehicle()
            if vehicle and vehicle.rootNode and vehicle.rootNode ~= 0 then
                success, px, py, pz = pcall(getWorldTranslation, vehicle.rootNode)
                if success and px then
                    x, z = px, pz
                    return x, z
                end
            end
        end
    end

    -- Try player
    if not x then
        local player = g_currentMission.player
        if player and player.rootNode then
            local success, px, _, pz = pcall(getWorldTranslation, player.rootNode)
            if success and px then
                x, z = px, pz
                return x, z
            end
        elseif player and player.baseInformation and player.baseInformation.lastPositionX then
            x = player.baseInformation.lastPositionX
            z = player.baseInformation.lastPositionZ
            return x, z
        end
    end

    -- Try vehicle
    if not x then
        local vehicle = g_currentMission.controlledVehicle
        if vehicle and vehicle.rootNode then
            local success, vx, _, vz = pcall(getWorldTranslation, vehicle.rootNode)
            if success and vx then
                x, z = vx, vz
                return x, z
            end
        end
    end

    return nil, nil
end

--- Lightweight farmland lookup using pre-computed world position
---@param x number|nil World X coordinate
---@param z number|nil World Z coordinate
---@return number|nil farmlandId
function SoilHUD:getFarmlandIdAtPosition(x, z)
    if not x or not z then return nil end
    if not g_farmlandManager then return nil end

    local farmlandId = nil

    if g_farmlandManager.getFarmlandIdAtWorldPosition then
        farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
    elseif g_farmlandManager.getFarmlandAtWorldPosition then
        local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
        if farmland and farmland.id then
            farmlandId = farmland.id
        end
    end

    if farmlandId and farmlandId > 0 then
        return farmlandId
    end
    return nil
end

--- Find which field contains a world position
--- Tier 0: g_fieldManager:getFieldAtWorldPosition() — most accurate FS25 API
--- Tier 1: manual iteration using field.getContainsPoint()
--- Tier 2: nearest field distance fallback
---@param x number World X coordinate
---@param z number World Z coordinate
---@return number|nil fieldId The field ID, or nil if not in any field
function SoilHUD:findFieldAtPosition(x, z)
    if not x or not z then return nil end
    if not g_fieldManager then return nil end

    -- TIER 0: g_fieldManager:getFieldAtWorldPosition() — most accurate (FS25 API)
    if g_fieldManager.getFieldAtWorldPosition then
        local ok, field = pcall(g_fieldManager.getFieldAtWorldPosition, g_fieldManager, x, z)
        if ok and field and field.fieldId and field.fieldId > 0 then
            if self.settings.debugMode then
                SoilLogger.debug("[HUD] Field %d found via getFieldAtWorldPosition (Tier 0)", field.fieldId)
            end
            return field.fieldId
        end
    end

    if not g_fieldManager.fields then return nil end

    -- TIER 1: Try to find field that contains the position
    -- Check if field has boundary data and test if point is inside
    for _, field in pairs(g_fieldManager.fields) do
        if field and field.fieldId and field.fieldId > 0 then
            -- Try getContainsPoint if available (FS25 API)
            if field.getContainsPoint then
                local success, contains = pcall(field.getContainsPoint, field, x, z)
                if success and contains then
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Field %d contains position (%.1f, %.1f)", field.fieldId, x, z)
                    end
                    return field.fieldId
                end
            end
        end
    end

    -- TIER 2: Find nearest field (fallback for edge cases)
    -- This ensures we always return a field ID even if position detection is imperfect
    local nearestFieldId = nil
    local nearestDist = math.huge

    for _, field in pairs(g_fieldManager.fields) do
        if field and field.fieldId and field.fieldId > 0 then
            -- Try multiple field center location patterns (from NPCFavor)
            local cx, cz = nil, nil

            if field.fieldArea and field.fieldArea.fieldCenterX then
                cx = field.fieldArea.fieldCenterX
                cz = field.fieldArea.fieldCenterZ
            elseif field.posX and field.posZ then
                cx = field.posX
                cz = field.posZ
            elseif field.rootNode then
                local ok, fx, _, fz = pcall(getWorldTranslation, field.rootNode)
                if ok and fx then
                    cx = fx
                    cz = fz
                end
            end

            if cx and cz then
                local dx = cx - x
                local dz = cz - z
                local dist = math.sqrt(dx * dx + dz * dz)

                -- Only consider fields within reasonable distance (500m)
                -- This prevents showing data for far-away fields
                if dist < nearestDist and dist < 500 then
                    nearestDist = dist
                    nearestFieldId = field.fieldId
                end
            end
        end
    end

    if nearestFieldId and self.settings.debugMode then
        SoilLogger.debug("[HUD] Nearest field %d at distance %.1fm", nearestFieldId, nearestDist)
    end

    return nearestFieldId
end