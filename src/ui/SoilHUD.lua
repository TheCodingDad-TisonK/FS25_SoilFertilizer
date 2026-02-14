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

-- Get current field ID based on player/vehicle position
function SoilHUD:getCurrentFieldId()
    if not g_currentMission then
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getCurrentFieldId: g_currentMission is nil")
        end
        return nil
    end
    if not g_fieldManager then
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getCurrentFieldId: g_fieldManager is nil")
        end
        return nil
    end

    local x, z
    local source = "unknown"

    -- Try player first
    local player = g_currentMission.player
    if player and player.rootNode then
        local px, _, pz = getWorldTranslation(player.rootNode)
        x, z = px, pz
        source = "player"
    else
        -- Try controlled vehicle
        local vehicle = g_currentMission.controlledVehicle
        if vehicle and vehicle.rootNode then
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            x, z = vx, vz
            source = "vehicle"
        else
            if self.settings.debugMode then
                SoilLogger.debug("[HUD] getCurrentFieldId: No player or vehicle position available")
            end
            return nil
        end
    end

    if self.settings.debugMode then
        SoilLogger.debug("[HUD] getCurrentFieldId: Position from %s: x=%.1f, z=%.1f", source, x, z)
    end

    -- Try direct field position lookup first (most accurate)
    if g_fieldManager.getFieldAtWorldPosition then
        local field = g_fieldManager:getFieldAtWorldPosition(x, z)
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getFieldAtWorldPosition returned: %s", field and "field object" or "nil")
            if field then
                SoilLogger.debug("[HUD] field.fieldId = %s", tostring(field.fieldId))
            end
        end
        if field and field.fieldId then
            if self.settings.debugMode then
                SoilLogger.debug("[HUD] getCurrentFieldId: Found field %d via getFieldAtWorldPosition", field.fieldId)
            end
            return field.fieldId
        end
    else
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] getFieldAtWorldPosition API not available")
        end
    end

    -- Fallback: Use farmland-based lookup (same pattern as HookManager)
    if g_farmlandManager then
        local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] farmlandId at position: %s", tostring(farmlandId))
        end

        if farmlandId and farmlandId > 0 then
            -- Use the proper API (same as HookManager uses)
            if g_fieldManager.getFieldByFarmland then
                local field = g_fieldManager:getFieldByFarmland(farmlandId)
                if self.settings.debugMode then
                    SoilLogger.debug("[HUD] getFieldByFarmland(%d) returned: %s", farmlandId, field and "field object" or "nil")
                    if field then
                        SoilLogger.debug("[HUD] field.fieldId = %s", tostring(field.fieldId))
                    end
                end
                if field and field.fieldId then
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] getCurrentFieldId: Found field %d via getFieldByFarmland", field.fieldId)
                    end
                    return field.fieldId
                end
            else
                if self.settings.debugMode then
                    SoilLogger.debug("[HUD] getFieldByFarmland API not available, using manual search")
                end
                -- Last resort: manual search through fields array
                if g_fieldManager.fields then
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Searching through %d fields manually", #g_fieldManager.fields)
                    end
                    for _, field in ipairs(g_fieldManager.fields) do
                        if field and field.farmland and field.farmland.id == farmlandId and field.fieldId then
                            if self.settings.debugMode then
                                SoilLogger.debug("[HUD] getCurrentFieldId: Found field %d via manual search", field.fieldId)
                            end
                            return field.fieldId
                        end
                    end
                    if self.settings.debugMode then
                        SoilLogger.debug("[HUD] Manual search: No field found with farmlandId %d", farmlandId)
                    end
                end
            end
        end
    else
        if self.settings.debugMode then
            SoilLogger.debug("[HUD] g_farmlandManager not available")
        end
    end

    if self.settings.debugMode then
        SoilLogger.debug("[HUD] getCurrentFieldId: No field detected at position")
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
function SoilHUD:draw()
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end  -- Check persistent HUD setting
    if not self.visible then return end  -- Check runtime visibility toggle (F8)

    -- Don't draw over menus/dialogs (critical - prevents rendering over pause menu, shop, etc)
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        return
    end

    -- Don't draw when large map is open
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.ingameMap then
        local mapState = g_currentMission.hud.ingameMap.state
        if mapState == IngameMap.STATE_LARGE_MAP then
            return
        end
    end

    -- Smart context-aware hiding
    if g_currentMission then
        -- Hide during tutorials
        if g_currentMission.inGameMessage and g_currentMission.inGameMessage.visible then
            return
        end

        -- Hide in construction mode (placeable placement/editing)
        if g_currentMission.controlledVehicle == nil and g_currentMission.player then
            if g_currentMission.player.isCarryingObject or g_currentMission.player.isObjectInRange then
                return
            end
        end

        -- Hide if camera is in special modes (cinema mode, photo mode, etc)
        if g_currentMission.camera and g_currentMission.camera.isActivated == false then
            return
        end

        -- Hide if help menu is open (prevents overlay conflicts)
        if g_currentMission.hud and g_currentMission.hud.contextActionDisplay then
            if g_currentMission.hud.contextActionDisplay.visible then
                -- Context help is showing, be respectful and hide
                return
            end
        end
    end

    -- Defensive mod compatibility: Check for other common mod UIs
    -- If Courseplay HUD is in full-screen mode, hide our HUD
    if g_Courseplay and g_Courseplay.globalSettings and g_Courseplay.globalSettings.showMiniHud == false then
        -- Courseplay is in full HUD mode, likely taking up screen space
        return
    end

    -- Get current field
    local fieldId = self:getCurrentFieldId()

    -- Draw panel (even if no field - show "No Field" message)
    self:drawPanel(fieldId)
end

-- Draw the HUD panel
function SoilHUD:drawPanel(fieldId)
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

    local x = self.panelX + 0.005  -- Small padding
    local y = self.panelY + self.panelHeight - 0.018  -- Start from top

    -- Title (always white, bold)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1.0, 1.0, 1.0, 1.0)
    renderText(x, y, 0.014 * fontMult, "SOIL INFO")
    y = y - lineHeight * 1.3

    -- Data color (use theme)
    setTextBold(false)
    setTextColor(themeR, themeG, themeB, 1.0)

    -- DEBUG: Only log when debug mode enabled
    if self.settings.debugMode then
        SoilLogger.info("[HUD DEBUG] fieldId=%s, soilSystem=%s", tostring(fieldId), tostring(self.soilSystem ~= nil))
    end

    if not fieldId or fieldId == 0 then
        -- Not in a field
        renderText(x, y, 0.012 * fontMult, "No field detected")
        if self.settings.debugMode then
            SoilLogger.info("[HUD DEBUG] No field ID detected")
        end
    else
        -- Get field data
        local fieldInfo = self.soilSystem:getFieldInfo(fieldId)

        if self.settings.debugMode then
            SoilLogger.info("[HUD DEBUG] Field %d, fieldInfo=%s", fieldId, tostring(fieldInfo ~= nil))

            if fieldInfo then
                SoilLogger.info("[HUD DEBUG] Field data: N=%d, P=%d, K=%d",
                    fieldInfo.nitrogen and fieldInfo.nitrogen.value or -1,
                    fieldInfo.phosphorus and fieldInfo.phosphorus.value or -1,
                    fieldInfo.potassium and fieldInfo.potassium.value or -1)
            end
        end

        if not fieldInfo then
            renderText(x, y, 0.012 * fontMult, string.format("Field %d", fieldId))
            y = y - lineHeight
            renderText(x, y, 0.012 * fontMult, "No data available")
        else
            -- Show field data
            renderText(x, y, 0.012 * fontMult, string.format("Field %d", fieldId))
            y = y - lineHeight

            renderText(x, y, 0.012 * fontMult, string.format("N: %d", fieldInfo.nitrogen.value))
            y = y - lineHeight

            renderText(x, y, 0.012 * fontMult, string.format("P: %d", fieldInfo.phosphorus.value))
            y = y - lineHeight

            renderText(x, y, 0.012 * fontMult, string.format("K: %d", fieldInfo.potassium.value))
            y = y - lineHeight

            renderText(x, y, 0.012 * fontMult, string.format("pH: %.1f", fieldInfo.pH))
            y = y - lineHeight

            -- Organic matter line (compact mode: combine with last crop)
            if compactMode and fieldInfo.lastCrop and fieldInfo.lastCrop ~= "None" then
                renderText(x, y, 0.012 * fontMult, string.format("OM: %.1f%% | %s", fieldInfo.organicMatter, fieldInfo.lastCrop))
            else
                renderText(x, y, 0.012 * fontMult, string.format("OM: %.1f%%", fieldInfo.organicMatter))

                -- Show last crop on separate line (non-compact mode)
                if fieldInfo.lastCrop and fieldInfo.lastCrop ~= "None" then
                    y = y - lineHeight
                    renderText(x, y, 0.011 * fontMult, string.format("%s", fieldInfo.lastCrop))
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
