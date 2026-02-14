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

    -- Panel dimensions (matching FIELD INFO style)
    self.panelWidth = 0.15
    self.panelHeight = 0.15

    -- Position will be set based on hudPosition setting
    self.panelX = 0.850
    self.panelY = 0.55
    self.lastHudPosition = nil  -- Track position changes

    return self
end

-- Calculate HUD position based on preset setting
function SoilHUD:updatePosition()
    local position = self.settings.hudPosition or 1

    -- Position presets: 1=Top Right, 2=Top Left, 3=Bottom Right, 4=Bottom Left, 5=Center Right
    if position == 1 then
        -- Top Right (default)
        self.panelX = 0.850
        self.panelY = 0.70
    elseif position == 2 then
        -- Top Left
        self.panelX = 0.010
        self.panelY = 0.70
    elseif position == 3 then
        -- Bottom Right
        self.panelX = 0.850
        self.panelY = 0.20
    elseif position == 4 then
        -- Bottom Left
        self.panelX = 0.010
        self.panelY = 0.20
    elseif position == 5 then
        -- Center Right
        self.panelX = 0.850
        self.panelY = 0.45
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
    if not g_currentMission then return nil end
    if not g_fieldManager then return nil end

    local x, z

    -- Try player first
    local player = g_currentMission.player
    if player and player.rootNode then
        local px, _, pz = getWorldTranslation(player.rootNode)
        x, z = px, pz
    else
        -- Try controlled vehicle
        local vehicle = g_currentMission.controlledVehicle
        if vehicle and vehicle.rootNode then
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            x, z = vx, vz
        else
            return nil
        end
    end

    -- Try direct field position lookup first (most accurate)
    if g_fieldManager.getFieldAtWorldPosition then
        local field = g_fieldManager:getFieldAtWorldPosition(x, z)
        if field and field.fieldId then
            return field.fieldId
        end
    end

    -- Fallback: Use farmland-based search (less precise but more compatible)
    if g_farmlandManager then
        local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
        if farmlandId and farmlandId > 0 then
            local fields = g_fieldManager:getFields()
            if fields and type(fields) == "table" then
                for _, field in pairs(fields) do
                    if field and field.farmland and field.farmland.id == farmlandId and field.fieldId then
                        return field.fieldId
                    end
                end
            end
        end
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

-- Draw HUD (called every frame)
function SoilHUD:draw()
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end  -- Check persistent HUD setting
    if not self.visible then return end  -- Check runtime visibility toggle (F8)

    -- Don't draw over menus/dialogs
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

    -- Get current field
    local fieldId = self:getCurrentFieldId()

    -- Draw panel (even if no field - show "No Field" message)
    self:drawPanel(fieldId)
end

-- Draw the HUD panel
function SoilHUD:drawPanel(fieldId)
    -- Draw background overlay
    if self.backgroundOverlay then
        self.backgroundOverlay:render()
    end

    local x = self.panelX + 0.005  -- Small padding
    local y = self.panelY + self.panelHeight - 0.018  -- Start from top
    local lineHeight = 0.016

    -- Title
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1.0, 1.0, 1.0, 1.0)
    renderText(x, y, 0.014, "SOIL INFO")
    y = y - lineHeight * 1.3

    -- Data color
    setTextColor(0.8, 0.8, 0.8, 1.0)

    -- DEBUG: Only log when debug mode enabled
    if self.settings.debugMode then
        SoilLogger.info("[HUD DEBUG] fieldId=%s, soilSystem=%s", tostring(fieldId), tostring(self.soilSystem ~= nil))
    end

    if not fieldId or fieldId == 0 then
        -- Not in a field
        renderText(x, y, 0.012, "No field detected")
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
            renderText(x, y, 0.012, string.format("Field %d", fieldId))
            y = y - lineHeight
            renderText(x, y, 0.012, "No data available")
        else
            -- Show field data
            renderText(x, y, 0.012, string.format("Field %d", fieldId))
            y = y - lineHeight

            renderText(x, y, 0.012, string.format("N: %d", fieldInfo.nitrogen.value))
            y = y - lineHeight

            renderText(x, y, 0.012, string.format("P: %d", fieldInfo.phosphorus.value))
            y = y - lineHeight

            renderText(x, y, 0.012, string.format("K: %d", fieldInfo.potassium.value))
            y = y - lineHeight

            renderText(x, y, 0.012, string.format("pH: %.1f", fieldInfo.pH))
            y = y - lineHeight

            renderText(x, y, 0.012, string.format("OM: %.1f%%", fieldInfo.organicMatter))

            if fieldInfo.lastCrop and fieldInfo.lastCrop ~= "None" then
                y = y - lineHeight
                renderText(x, y, 0.011, string.format("%s", fieldInfo.lastCrop))
            end
        end
    end

    -- Reset text settings
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end
