-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.7.0)
-- =========================================================
-- Soil HUD Overlay - legend/reference display (toggle with J key)
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
    self.visible = true  -- Runtime visibility toggle (J key)

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
---@return nil
function SoilHUD:draw()
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end
    if not self.visible then return end
    if not g_currentMission then return end

    -- Don't draw over menus or dialogs
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        return
    end

    -- Don't draw over the fullscreen map
    if g_currentMission.hud and g_currentMission.hud.ingameMap then
        if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then
            return
        end
    end

    self:drawPanel()
end

--- Draw the static legend/reference panel.
--- Shows key bindings (J/K) and nutrient status thresholds color-coded by status.
--- Thresholds match SoilConstants.STATUS_THRESHOLDS (Good = N>=50/P>=45/K>=40, etc.)
function SoilHUD:drawPanel()
    local colorTheme   = self.settings.hudColorTheme or 1
    local fontSize     = self.settings.hudFontSize or 2
    local transparency = self.settings.hudTransparency or 3
    local compactMode  = self.settings.hudCompactMode or false

    -- Clamp to valid range
    if colorTheme < 1 or colorTheme > 4 then
        colorTheme = math.max(1, math.min(4, colorTheme))
    end

    -- Render background
    if self.backgroundOverlay then
        local alpha = SoilConstants.HUD.TRANSPARENCY_LEVELS[transparency]
        self.backgroundOverlay:setColor(0, 0, 0, alpha)
        self.backgroundOverlay:render()
    end

    local theme    = SoilConstants.HUD.COLOR_THEMES[colorTheme]
    local themeR   = theme.r
    local themeG   = theme.g
    local themeB   = theme.b
    local fontMult = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[fontSize]
    local lineH    = compactMode and SoilConstants.HUD.COMPACT_LINE_HEIGHT or SoilConstants.HUD.NORMAL_LINE_HEIGHT
    local needsShadow = transparency <= 2

    if needsShadow then setTextShadow(true) end

    local x = self.panelX + 0.005
    local y = self.panelY + self.panelHeight - 0.018

    -- Title
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1.0, 1.0, 1.0, 1.0)
    renderText(x, y, 0.014 * fontMult, "SOIL LEGEND")
    y = y - lineH * 1.4
    setTextBold(false)

    -- Key bindings
    setTextColor(themeR, themeG, themeB, 1.0)
    renderText(x, y, 0.011 * fontMult, "J = Toggle HUD")
    y = y - lineH
    renderText(x, y, 0.011 * fontMult, "K = Soil Report")
    y = y - lineH * 1.3

    -- Nutrient status legend — color matches the in-game status colors
    -- Good  = value >= fair threshold (50 / 45 / 40)
    -- Fair  = value >= poor threshold (30 / 25 / 20)
    -- Poor  = value below poor threshold
    setTextColor(0.3, 0.9, 0.3, 1.0)
    renderText(x, y, 0.011 * fontMult, "Good: N>50, P>45, K>40")
    y = y - lineH

    setTextColor(0.9, 0.9, 0.2, 1.0)
    renderText(x, y, 0.011 * fontMult, "Fair: N>30, P>25, K>20")
    y = y - lineH

    setTextColor(0.9, 0.3, 0.3, 1.0)
    renderText(x, y, 0.011 * fontMult, "Poor: needs fertilizer")
    y = y - lineH * 1.3

    -- pH reference
    setTextColor(themeR, themeG, themeB, 0.75)
    renderText(x, y, 0.010 * fontMult, "pH ideal: 6.5 - 7.0")

    -- Reset text state
    if needsShadow then setTextShadow(false) end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end
