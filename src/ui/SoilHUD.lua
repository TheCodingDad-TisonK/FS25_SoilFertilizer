-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.4.1)
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

-- Get current farmland ID based on player/vehicle position
-- NOTE: Changed from getCurrentFieldId to getCurrentFarmlandId to match base game behavior
-- Base game shows "Farmland 1", "Farmland 2" etc, not field IDs
function SoilHUD:getCurrentFarmlandId()
    if not g_currentMission then
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getCurrentFarmlandId: g_currentMission is nil")
        end
        return nil
    end
    if not g_farmlandManager then
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getCurrentFarmlandId: g_farmlandManager is nil")
        end
        return nil
    end

    local x, z
    local source = "unknown"

    -- Debug: Log what's available
    if self.settings.debugMode then
        local player = g_currentMission.player
        local vehicle = g_currentMission.controlledVehicle
        SoilLogger.debug("[HUD] Player object: %s, rootNode: %s",
            tostring(player ~= nil),
            player and tostring(player.rootNode ~= nil) or "N/A")
        SoilLogger.debug("[HUD] Vehicle object: %s, rootNode: %s",
            tostring(vehicle ~= nil),
            vehicle and tostring(vehicle.rootNode ~= nil) or "N/A")
    end

    -- Tier 0: Try g_localPlayer first (most reliable - from FS25 API)
    if g_localPlayer then
        local success, px, py, pz = pcall(function()
            -- Try getPosition() method first
            if g_localPlayer.getPosition then
                return g_localPlayer:getPosition()
            -- Fallback to rootNode
            elseif g_localPlayer.rootNode and g_localPlayer.rootNode ~= 0 then
                return getWorldTranslation(g_localPlayer.rootNode)
            end
            return nil, nil, nil
        end)

        if success and px then
            x, z = px, pz
            source = "g_localPlayer"
        -- Check if player is in vehicle
        elseif g_localPlayer.getIsInVehicle and g_localPlayer:getIsInVehicle() then
            local vehicle = g_localPlayer:getCurrentVehicle()
            if vehicle and vehicle.rootNode and vehicle.rootNode ~= 0 then
                success, px, py, pz = pcall(getWorldTranslation, vehicle.rootNode)
                if success and px then
                    x, z = px, pz
                    source = "g_localPlayer.vehicle"
                end
            end
        end

        if self.settings.debugMode and x then
            SoilLogger.debug("[HUD] Using g_localPlayer for position")
        end
    end

    -- Tier 1: Try g_currentMission.player (standard method)
    if not x then
        local player = g_currentMission.player
        if player and player.rootNode then
            local success, px, _, pz = pcall(getWorldTranslation, player.rootNode)
            if success and px then
                x, z = px, pz
                source = "player"
            end
        -- Fallback: Try player position from baseInformation (FS25 multiplayer)
        elseif player and player.baseInformation and player.baseInformation.lastPositionX then
            x = player.baseInformation.lastPositionX
            z = player.baseInformation.lastPositionZ
            source = "player.baseInformation"
            if self.settings.debugMode then
                SoilLogger.debug("[HUD] Using player.baseInformation for position")
            end
        end
    end

    -- Tier 2: Try controlled vehicle
    if not x then
        local vehicle = g_currentMission.controlledVehicle
        if vehicle and vehicle.rootNode then
            local success, vx, _, vz = pcall(getWorldTranslation, vehicle.rootNode)
            if success and vx then
                x, z = vx, vz
                source = "vehicle"
            end
        end
    end

    -- Tier 3: Try camera position (last resort)
    if not x and g_currentMission.camera then
        local success, cx, cy, cz = pcall(function()
            if g_currentMission.camera.cameraNode then
                return getWorldTranslation(g_currentMission.camera.cameraNode)
            end
        end)
        if success and cx and cz then
            x, z = cx, cz
            source = "camera"
            if self.settings.debugMode then
                SoilLogger.debug("[HUD] Using camera position as last resort")
            end
        end
    end

    -- No position available
    if not x then
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getCurrentFarmlandId: No position available from any source")
        end
        return nil
    end

    if self.settings.debugMode then
        SoilLogger.debug("[HUD] getCurrentFarmlandId: Position from %s: x=%.1f, z=%.1f", source, x, z)
    end

    -- Use farmland API to get farmland ID at world position
    -- This is the correct FS25 API - returns the farmland ID directly
    local farmlandId = nil
    
    -- Safely call the API (it might not be available in all game states)
    if g_farmlandManager.getFarmlandIdAtWorldPosition then
        farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
    elseif g_farmlandManager.getFarmlandAtWorldPosition then
        -- Fallback for older API naming (if it exists)
        local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
        if farmland and farmland.id then
            farmlandId = farmland.id
        end
    end
    
    if self.settings.debugMode then
        SoilLogger.debug("[HUD] getFarmlandIdAtWorldPosition returned: %s", tostring(farmlandId))
    end

    -- Validate farmland ID (must be > 0, as 0 or nil means no farmland)
    if farmlandId and farmlandId > 0 then
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getCurrentFarmlandId: Found farmland %d at position", farmlandId)
        end
        return farmlandId
    end

    if self.settings.debugMode then
        SoilLogger.debug("[HUD] getCurrentFarmlandId: No farmland detected at position")
    end
    return nil
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

-- Toggle HUD visibility (called by F8 key)
function SoilHUD:toggleVisibility()
    self.visible = not self.visible
    SoilLogger.info("Soil HUD %s", self.visible and "shown" or "hidden")
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

    -- Get current farmland - this will also try to get position
    local farmlandId = self:getCurrentFarmlandId()

    -- Draw panel (always draw, even if no farmland)
    -- This ensures the HUD is visible
    self:drawPanel(farmlandId)
end

-- Draw the HUD panel
-- NOTE: Updated to use farmlandId instead of fieldId
-- Draw the HUD panel
-- FIXED: Now properly finds field based on position, not just farmland
-- Draw the HUD panel
function SoilHUD:drawPanel(farmlandId)
    -- Get customization settings
    local colorTheme = self.settings.hudColorTheme or 1
    local fontSize = self.settings.hudFontSize or 2
    local transparency = self.settings.hudTransparency or 3
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
        
        -- FIX: Get the current position first - use different variable names
        local worldX, worldZ = self:getCurrentPosition()
        
        -- Then find which field contains this position
        local fieldId = nil
        local field = nil
        
        if worldX and worldZ then
            -- Method 1: Use FieldManager's getFieldAtWorldPosition if available (most accurate)
            if g_fieldManager and g_fieldManager.getFieldAtWorldPosition then
                field = g_fieldManager:getFieldAtWorldPosition(worldX, worldZ)
                if field and field.fieldId then
                    fieldId = field.fieldId
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Field detected via getFieldAtWorldPosition: %d", fieldId)
                    end
                end
            end

            -- Method 2: Fallback - iterate through fields and check if position is in field polygon
            if not fieldId and g_fieldManager and g_fieldManager.fields then
                for _, f in pairs(g_fieldManager.fields) do
                    if f and f.fieldId and f.getContainsPoint then
                        local success, contains = pcall(f.getContainsPoint, f, worldX, worldZ)
                        if success and contains then
                            fieldId = f.fieldId
                            field = f
                            if self.settings.debugMode then
                                SoilLogger.debug("[HUD] Field detected via getContainsPoint: %d", fieldId)
                            end
                            break
                        end
                    end
                end
            end

            -- If position is available but no field contains it, player is not in a field
            -- Don't fall back to "first field in farmland" as that would show wrong data
        else
            -- Can't get position - use farmland-to-field mapping as best guess
            -- Note: This may show wrong field if multiple fields exist on this farmland
            if g_fieldManager and g_fieldManager.getFieldByFarmland then
                field = g_fieldManager:getFieldByFarmland(farmlandId)
                if field and field.fieldId then
                    fieldId = field.fieldId
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Field via farmland mapping (no position): %d", fieldId)
                    end
                end
            end

            -- If still no field, find first field in this farmland
            if not fieldId and g_fieldManager and g_fieldManager.fields then
                for _, f in pairs(g_fieldManager.fields) do
                    if f and f.farmland and f.farmland.id == farmlandId and f.fieldId then
                        fieldId = f.fieldId
                        field = f
                        if self.settings.debugMode then
                            SoilLogger.debug("[HUD] Field via first-in-farmland fallback: %d", fieldId)
                        end
                        break
                    end
                end
            end
        end
        
        if self.settings.debugMode then
            SoilLogger.info("[HUD DEBUG] Farmland %d, derived fieldId=%s", farmlandId, tostring(fieldId))
        end

        -- Get soil data from our system
        local fieldInfo = nil
        if fieldId and fieldId > 0 then
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

        if self.settings.debugMode then
            if fieldInfo then
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

        if not fieldInfo then
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
            -- Show field ID if available (for debugging/info)
            if fieldId then
                renderText(screenX, screenY, 0.011 * fontMult, string.format("(Field %d)", fieldId))
                screenY = screenY - lineHeight
            end
            
            -- Show soil data with safe value extraction
            local nVal = (fieldInfo.nitrogen and fieldInfo.nitrogen.value) or 0
            local pVal = (fieldInfo.phosphorus and fieldInfo.phosphorus.value) or 0
            local kVal = (fieldInfo.potassium and fieldInfo.potassium.value) or 0
            local phVal = fieldInfo.pH or 0
            local omVal = fieldInfo.organicMatter or 0
            
            renderText(screenX, screenY, 0.012 * fontMult, string.format("N: %d", nVal))
            screenY = screenY - lineHeight

            renderText(screenX, screenY, 0.012 * fontMult, string.format("P: %d", pVal))
            screenY = screenY - lineHeight

            renderText(screenX, screenY, 0.012 * fontMult, string.format("K: %d", kVal))
            screenY = screenY - lineHeight

            renderText(screenX, screenY, 0.012 * fontMult, string.format("pH: %.1f", phVal))
            screenY = screenY - lineHeight

            -- Organic matter line (compact mode: combine with last crop)
            if compactMode and fieldInfo.lastCrop and fieldInfo.lastCrop ~= "None" and fieldInfo.lastCrop ~= "" then
                renderText(screenX, screenY, 0.012 * fontMult, string.format("OM: %.1f%% | %s", omVal, fieldInfo.lastCrop))
            else
                renderText(screenX, screenY, 0.012 * fontMult, string.format("OM: %.1f%%", omVal))

                -- Show last crop on separate line (non-compact mode)
                if fieldInfo.lastCrop and fieldInfo.lastCrop ~= "None" and fieldInfo.lastCrop ~= "" then
                    screenY = screenY - lineHeight
                    renderText(screenX, screenY, 0.011 * fontMult, string.format("%s", fieldInfo.lastCrop))
                end
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