-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Smart Sensor Panel
-- =========================================================
-- Compact in-vehicle overlay displayed when the player is
-- controlling a sprayer. Shows the three Smart Sensor states
-- (Pest / Disease / Nutrient) and current field readings for
-- the product loaded.  Sensor toggles use three vehicle-
-- category input actions (SF_SENSOR_PEST, SF_SENSOR_DISEASE,
-- SF_SENSOR_NUTRIENT) bound by default to Alt+1/2/3.
--
-- Visual style matches SoilHUD and the rate panel:
--   • Same dark background with color-theme tinting
--   • Same transparency level from settings
--   • Orange pulse border in HUD edit mode
--
-- The panel is hidden when:
--   • Player is not in a sprayer with VWW sections
--   • Smart Sensor is globally disabled (admin toggle)
--   • PF compat mode is active (PF owns section control)
--   • The SF mod is disabled
--   • A GUI dialog / large map is visible (except in edit mode)
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilSmartSensorPanel
SoilSmartSensorPanel = {}
local SoilSmartSensorPanel_mt = Class(SoilSmartSensorPanel)

-- Panel geometry at scale 1.0 (normalized screen space, Y=0 bottom)
SoilSmartSensorPanel.ROW_H   = 0.024   -- height per sensor row
SoilSmartSensorPanel.PAD     = 0.006   -- inner padding
SoilSmartSensorPanel.TITLE_H = 0.022   -- title bar height
SoilSmartSensorPanel.GAP     = 0.007   -- gap between this panel and the rate panel above

-- Colors (shared with SoilHUD palette — data indicators only)
SoilSmartSensorPanel.C_BORDER   = {0.20, 0.20, 0.20, 0.40}
SoilSmartSensorPanel.C_SHADOW   = {0.00, 0.00, 0.00, 0.30}
SoilSmartSensorPanel.C_ON       = {0.25, 0.85, 0.25, 1.00}
SoilSmartSensorPanel.C_OFF      = {0.52, 0.52, 0.52, 0.85}
SoilSmartSensorPanel.C_WARN     = {0.90, 0.82, 0.18, 1.00}
SoilSmartSensorPanel.C_LABEL    = {0.72, 0.72, 0.72, 1.00}
SoilSmartSensorPanel.C_VALUE    = {1.00, 1.00, 1.00, 1.00}
SoilSmartSensorPanel.C_DIM      = {0.52, 0.52, 0.52, 0.85}
SoilSmartSensorPanel.C_TITLE_BG = {0.10, 0.10, 0.10, 0.90}
SoilSmartSensorPanel.C_DIVIDER  = {0.25, 0.25, 0.25, 0.45}

function SoilSmartSensorPanel.new(soilSystem, settings)
    local self = setmetatable({}, SoilSmartSensorPanel_mt)
    self.soilSystem   = soilSystem
    self.settings     = settings
    self.fillOverlay  = nil
    self.initialized  = false
    return self
end

function SoilSmartSensorPanel:initialize()
    if self.initialized then return end
    if createImageOverlay then
        local ov = createImageOverlay("dataS/menu/base/graph_pixel.dds")
        if ov and ov ~= 0 then
            self.fillOverlay = ov
            self.initialized = true
            SoilLogger.info("[SoilSmartSensorPanel] Initialized")
        else
            SoilLogger.warning("[SoilSmartSensorPanel] createImageOverlay returned invalid handle — panel will not render")
        end
    else
        SoilLogger.warning("[SoilSmartSensorPanel] createImageOverlay not available — panel will not render")
    end
end

function SoilSmartSensorPanel:delete()
    if self.fillOverlay and self.fillOverlay ~= 0 then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.initialized = false
end

-- ── Internal helpers ─────────────────────────────────────

function SoilSmartSensorPanel:drawRect(x, y, w, h, c, a)
    if not self.fillOverlay or self.fillOverlay == 0 then return end
    setOverlayColor(self.fillOverlay, c[1], c[2], c[3], a or c[4] or 1.0)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

-- Returns the current sprayer vehicle, or nil if not in one.
function SoilSmartSensorPanel:getActiveSprayer()
    local player = g_localPlayer
    if not player then return nil end
    if type(player.getIsInVehicle) ~= "function" then return nil end
    if not player:getIsInVehicle() then return nil end
    local vehicle = player:getCurrentVehicle()
    if not vehicle then return nil end
    if vehicle.spec_sprayer then return vehicle end
    local impl = vehicle.spec_attacherJoints and vehicle.spec_attacherJoints.attachedImplements
    if impl then
        for _, att in ipairs(impl) do
            if att.object and att.object.spec_sprayer then
                return att.object
            end
        end
    end
    return nil
end

-- Returns the field ID and soil data for the vehicle's current position.
function SoilSmartSensorPanel:getFieldData(vehicle)
    if not vehicle or not vehicle.rootNode then return nil, nil end
    local ok, x, _, z = pcall(getWorldTranslation, vehicle.rootNode)
    if not ok or not x then return nil, nil end
    local sfm = g_SoilFertilityManager
    if not sfm or not sfm.soilSystem then return nil, nil end
    local field = nil
    if g_fieldManager then
        local fok, f = pcall(function() return g_fieldManager:getFieldAtWorldPosition(x, z) end)
        if fok and f then field = f end
    end
    local fieldId = field and field.fieldId
    if not fieldId or fieldId <= 0 then return nil, nil end
    local fd = sfm.soilSystem.fieldData[fieldId]
    return fieldId, fd
end

-- Returns sensor key display string from input binding, or fallback.
local function getActionKey(actionName, fallback)
    if g_inputDisplayManager then
        local ok, el = pcall(function()
            return g_inputDisplayManager:getControllerSymbolOverlays(InputAction[actionName], "", "", false)
        end)
        if ok and el and el.keys and #el.keys > 0 then
            local parts = {}
            for _, k in ipairs(el.keys) do parts[#parts + 1] = tostring(k) end
            return table.concat(parts, "+")
        end
    end
    return fallback
end

-- ── Main draw ────────────────────────────────────────────

function SoilSmartSensorPanel:draw()
    if not self.initialized then return end
    if not self.settings or not self.settings.enabled then return end
    if not g_currentMission then return end

    local sfm = g_SoilFertilityManager
    if not sfm or not sfm.sensorManager then return end
    if sfm.settings and sfm.settings.smartSensorEnabled == false then return end

    local hud = sfm.soilHUD
    local inEditMode = hud and hud.editMode

    -- Only bypass GUI visibility check in edit mode (mirrors SoilHUD behaviour)
    if not inEditMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then return end
        if g_currentMission.hud and g_currentMission.hud.ingameMap then
            if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then return end
        end
    end

    -- Only show when in a sprayer with VWW sections
    local sprayer = self:getActiveSprayer()
    if not sprayer then return end
    local vww = sprayer.spec_variableWorkWidth
    if not vww or not vww.sections or #vww.sections == 0 then return end

    self:drawPanel(sprayer, sfm)
end

function SoilSmartSensorPanel:drawPanel(sprayer, sfm)
    local sensorMgr  = sfm.sensorManager
    local pfActive   = sfm.settings and sfm.settings.pfCompatibilityMode

    local hud = sfm.soilHUD
    if not hud then return end

    local s  = hud.scale or 1.0
    local pw = SoilHUD and (SoilHUD.BASE_W * s) or (0.190 * s)

    -- Rate panel geometry (mirrors SoilHUD:drawSprayerRatePanel)
    local padV    = (5  / 1080) * s
    local barH    = (4  / 1080) * s
    local scrollH = (22 / 1080) * s
    local headerH = (16 / 1080) * s
    local ratePanelH = padV + barH + padV + scrollH + padV + headerH
    local gap     = (6  / 1080) * s

    local panelX       = hud.panelX
    local mainPanelY   = hud.panelY
    local ratePanelY   = mainPanelY - gap - ratePanelH

    -- Sensor panel sits below the rate panel
    local numRows       = pfActive and 1 or 3
    local rowH          = SoilSmartSensorPanel.ROW_H   * s
    local pad           = SoilSmartSensorPanel.PAD     * s
    local titleH        = SoilSmartSensorPanel.TITLE_H * s
    local sensorPanelH  = titleH + pad + numRows * rowH + pad
    local sensorPanelY  = ratePanelY - SoilSmartSensorPanel.GAP * s - sensorPanelH

    -- Match rate panel background: color-theme tint + transparency from settings
    local rTheme = SoilConstants.HUD and SoilConstants.HUD.COLOR_THEMES
        and SoilConstants.HUD.COLOR_THEMES[self.settings.hudColorTheme or 1]
        or { r = 0.4, g = 1.0, b = 0.4 }
    local bgR = 0.05 + rTheme.r * 0.04
    local bgG = 0.05 + rTheme.g * 0.04
    local bgB = 0.05 + rTheme.b * 0.04
    local alpha = SoilConstants.HUD and SoilConstants.HUD.TRANSPARENCY_LEVELS
        and SoilConstants.HUD.TRANSPARENCY_LEVELS[self.settings.hudTransparency or 3] or 0.70

    -- Shadow
    self:drawRect(panelX + 0.002*s, sensorPanelY - 0.002*s, pw, sensorPanelH, SoilSmartSensorPanel.C_SHADOW)
    -- Background (color-themed, same as rate panel)
    self:drawRect(panelX, sensorPanelY, pw, sensorPanelH, {bgR, bgG, bgB, 1}, alpha)
    -- Title bar (slightly lighter)
    self:drawRect(panelX, sensorPanelY + sensorPanelH - titleH, pw, titleH, SoilSmartSensorPanel.C_TITLE_BG)
    -- Border
    local bw = 0.001
    self:drawRect(panelX,          sensorPanelY,                pw, bw, SoilSmartSensorPanel.C_BORDER)
    self:drawRect(panelX,          sensorPanelY + sensorPanelH - bw, pw, bw, SoilSmartSensorPanel.C_BORDER)
    self:drawRect(panelX,          sensorPanelY,                bw, sensorPanelH, SoilSmartSensorPanel.C_BORDER)
    self:drawRect(panelX + pw - bw, sensorPanelY,               bw, sensorPanelH, SoilSmartSensorPanel.C_BORDER)

    -- Edit mode: orange pulse border (mirrors SoilHUD and rate panel behaviour)
    if hud.editMode then
        local pulse = 0.55 + 0.45 * math.sin((hud.animTimer or 0) * 0.004)
        local ebw = 0.0015
        self:drawRect(panelX,               sensorPanelY,                        pw, ebw, {1.0, 0.55, 0.10, pulse})
        self:drawRect(panelX,               sensorPanelY + sensorPanelH - ebw,   pw, ebw, {1.0, 0.55, 0.10, pulse})
        self:drawRect(panelX,               sensorPanelY,                        ebw, sensorPanelH, {1.0, 0.55, 0.10, pulse})
        self:drawRect(panelX + pw - ebw,    sensorPanelY,                        ebw, sensorPanelH, {1.0, 0.55, 0.10, pulse})
    end

    -- Title text
    local cx = panelX + pw * 0.5
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(1, 1, 1, 0.90)
    local titleFs = 0.009 * s
    renderText(cx, sensorPanelY + sensorPanelH - titleH * 0.5 - titleFs * 0.3, titleFs,
        g_i18n:getText("sf_sensor_panel_title"))
    setTextBold(false)

    -- PF compat mode: show a single disabled notice
    if pfActive then
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextColor(SoilSmartSensorPanel.C_WARN[1], SoilSmartSensorPanel.C_WARN[2],
            SoilSmartSensorPanel.C_WARN[3], 1.0)
        local fs = 0.008 * s
        renderText(cx, sensorPanelY + pad + rowH * 0.5 - fs * 0.45, fs,
            g_i18n:getText("sf_sensor_pf_mode"))
        setTextColor(1, 1, 1, 1)
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextBold(false)
        return
    end

    -- Field data for status readout
    local _, fd = self:getFieldData(sprayer)
    local vehicleId = sprayer.id

    -- Bound keys (lazy lookup)
    local keyPest    = getActionKey("SF_SENSOR_PEST",    "Alt+1")
    local keyDisease = getActionKey("SF_SENSOR_DISEASE", "Alt+2")
    local keyNut     = getActionKey("SF_SENSOR_NUTRIENT","Alt+3")

    local pestOn    = sensorMgr:isPestEnabled(vehicleId)
    local diseaseOn = sensorMgr:isDiseaseEnabled(vehicleId)
    local nutrientOn = sensorMgr:isNutrientEnabled(vehicleId)

    -- Build value strings
    local pestVal, diseaseVal, nutVal = "", "", ""
    if fd then
        local pest = fd.pestPressure    or 0
        local dis  = fd.diseasePressure or 0
        local k    = fd.potassium  or 0
        local p    = fd.phosphorus or 0
        pestVal    = string.format("%.0f (%.0f%%)", pest, pest * 100)
        diseaseVal = string.format("%.0f (%.0f%%)", dis,  dis  * 100)
        nutVal     = string.format("K=%d  P=%d",    math.floor(k), math.floor(p))
    end

    local rows = {
        { label = g_i18n:getText("sf_sensor_pest"),     on = pestOn,    key = keyPest,    val = pestVal    },
        { label = g_i18n:getText("sf_sensor_disease"),  on = diseaseOn, key = keyDisease, val = diseaseVal },
        { label = g_i18n:getText("sf_sensor_nutrient"), on = nutrientOn,key = keyNut,     val = nutVal     },
    }

    local fs     = 0.0075 * s
    local fsDim  = 0.0065 * s
    local tx     = panelX + pad
    local valX   = panelX + pw - pad
    local rowY   = sensorPanelY + pad

    setTextAlignment(RenderText.ALIGN_LEFT)

    for i = #rows, 1, -1 do
        local row  = rows[i]
        local midY = rowY + (i - 1) * rowH + rowH * 0.5

        -- Divider between rows
        if i < #rows then
            self:drawRect(tx, rowY + (i - 1) * rowH + rowH - 0.0003, pw - pad*2, 0.0003, SoilSmartSensorPanel.C_DIVIDER)
        end

        -- Status dot
        local dotC = row.on and SoilSmartSensorPanel.C_ON or SoilSmartSensorPanel.C_OFF
        self:drawRect(tx, midY - 0.004*s, 0.007*s, 0.007*s, dotC)

        -- Label
        local labelC = row.on and SoilSmartSensorPanel.C_VALUE or SoilSmartSensorPanel.C_DIM
        setTextColor(labelC[1], labelC[2], labelC[3], labelC[4] or 1.0)
        renderText(tx + 0.010*s, midY - fs * 0.45, fs, row.label)

        -- Key hint (right-aligned, dim)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(SoilSmartSensorPanel.C_DIM[1], SoilSmartSensorPanel.C_DIM[2],
            SoilSmartSensorPanel.C_DIM[3], 0.70)
        renderText(valX, midY - fsDim * 0.45, fsDim, "[" .. row.key .. "]")
        setTextAlignment(RenderText.ALIGN_LEFT)

        -- Value readout when sensor is on
        if row.on and row.val ~= "" then
            setTextColor(SoilSmartSensorPanel.C_LABEL[1], SoilSmartSensorPanel.C_LABEL[2],
                SoilSmartSensorPanel.C_LABEL[3], 1.0)
            renderText(tx + 0.010*s, midY - fsDim * 0.45 - fsDim * 1.1, fsDim, row.val)
        end
    end

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
end
