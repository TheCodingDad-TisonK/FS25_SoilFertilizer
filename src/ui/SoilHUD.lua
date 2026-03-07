-- =========================================================
-- FS25 Realistic Soil & Fertilizer
-- =========================================================
-- Soil HUD Overlay - live field soil monitor
-- Shows N/P/K/pH/OM for the field the player is standing on.
-- Toggle with J key. RMB on panel to drag/resize.
-- =========================================================
-- Author: TisonK
-- =========================================================
---@class SoilHUD

SoilHUD = {}
local SoilHUD_mt = Class(SoilHUD)

-- ── Scale / resize ──────────────────────────────────────
SoilHUD.MIN_SCALE          = 0.60
SoilHUD.MAX_SCALE          = 1.80
SoilHUD.RESIZE_HANDLE_SIZE = 0.008

-- ── Base panel dimensions at scale 1.0 ─────────────────
SoilHUD.BASE_W = 0.190
SoilHUD.BASE_H = 0.178

-- ── Layout constants at scale 1.0 ──────────────────────
SoilHUD.TITLE_H   = 0.024   -- title accent bar height
SoilHUD.ROW_H     = 0.022   -- nutrient row height
SoilHUD.LINE_H    = 0.018   -- text-only row height
SoilHUD.PAD       = 0.006   -- inner padding
SoilHUD.BAR_H     = 0.010   -- nutrient bar fill height
SoilHUD.BAR_W     = 0.095   -- nutrient bar width

-- ── Colors ──────────────────────────────────────────────
SoilHUD.C_BG         = {0.05, 0.05, 0.08, 0.82}
SoilHUD.C_TITLE_BG   = {0.08, 0.18, 0.38, 0.92}
SoilHUD.C_BORDER     = {0.30, 0.30, 0.42, 0.55}
SoilHUD.C_DIVIDER    = {0.30, 0.30, 0.45, 0.45}
SoilHUD.C_SHADOW     = {0.00, 0.00, 0.00, 0.30}
SoilHUD.C_BAR_BG     = {0.18, 0.18, 0.22, 0.90}
SoilHUD.C_GOOD       = {0.25, 0.85, 0.25, 1.00}
SoilHUD.C_FAIR       = {0.90, 0.82, 0.18, 1.00}
SoilHUD.C_POOR       = {0.88, 0.25, 0.25, 1.00}
SoilHUD.C_LABEL      = {0.65, 0.80, 0.65, 1.00}
SoilHUD.C_VALUE      = {1.00, 1.00, 1.00, 1.00}
SoilHUD.C_DIM        = {0.50, 0.50, 0.58, 0.85}
SoilHUD.C_HINT       = {0.45, 0.45, 0.58, 0.75}
SoilHUD.C_EDIT_HDL   = {0.20, 0.60, 1.00, 0.85}

-- ── Field detection throttle ────────────────────────────
SoilHUD.FIELD_DETECT_INTERVAL = 0.5   -- seconds between position queries

function SoilHUD.new(soilSystem, settings)
    local self = setmetatable({}, SoilHUD_mt)

    self.soilSystem  = soilSystem
    self.settings    = settings
    self.initialized = false
    self.visible     = true

    -- Position (from preset, overridden by drag)
    local defaultPos = SoilConstants.HUD.POSITIONS[1]
    self.panelX          = defaultPos.x
    self.panelY          = defaultPos.y
    self.lastHudPosition = nil

    -- Scale & edit state
    self.scale            = 1.0
    self.editMode         = false
    self.dragging         = false
    self.resizing         = false
    self.dragOffsetX      = 0
    self.dragOffsetY      = 0
    self.resizeStartX     = 0
    self.resizeStartY     = 0
    self.resizeStartScale = 1.0
    self.hoverCorner      = nil
    self.animTimer        = 0

    -- Camera freeze (NPCFavor pattern)
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil

    -- Field detection cache (throttled)
    self.cachedFieldId    = nil
    self.cachedFieldInfo  = nil
    self.fieldDetectTimer = 0

    -- Single overlay handle
    self.fillOverlay = nil

    return self
end

-- ── Initialize ───────────────────────────────────────────
function SoilHUD:initialize()
    if self.initialized then return true end
    self:updatePosition()
    if createImageOverlay ~= nil then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    else
        SoilLogger.warn("SoilHUD: createImageOverlay not available")
    end
    self.initialized = true
    SoilLogger.info("SoilHUD initialized at (%.3f, %.3f)", self.panelX, self.panelY)
    return true
end

-- ── Delete ───────────────────────────────────────────────
function SoilHUD:delete()
    if self.editMode then self:exitEditMode() end
    if self.fillOverlay then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.initialized = false
end

-- ── Position preset ──────────────────────────────────────
function SoilHUD:updatePosition()
    local pos = SoilConstants.HUD.POSITIONS[self.settings.hudPosition or 1]
    if pos then
        self.panelX = pos.x
        self.panelY = pos.y
    end
end

-- ── Edit mode ────────────────────────────────────────────
function SoilHUD:enterEditMode()
    self.editMode = true
    self.dragging = false
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true)
    end
    if getCamera and getRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            local ok2, rx, ry, rz = pcall(getRotation, cam)
            if ok2 then
                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz
            end
        end
    end
    SoilLogger.info("[SoilHUD] Edit mode ON")
end

function SoilHUD:exitEditMode()
    self.editMode    = false
    self.dragging    = false
    self.resizing    = false
    self.hoverCorner = nil
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    SoilLogger.info("[SoilHUD] Edit mode OFF — pos=(%.3f,%.3f) scale=%.2f",
        self.panelX, self.panelY, self.scale)
end

-- ── Geometry helpers ─────────────────────────────────────
function SoilHUD:getHUDRect()
    local s = self.scale
    return self.panelX, self.panelY, SoilHUD.BASE_W * s, SoilHUD.BASE_H * s
end

function SoilHUD:isPointerOverHUD(posX, posY)
    local px, py, pw, ph = self:getHUDRect()
    return posX >= px and posX <= px + pw
       and posY >= py and posY <= py + ph
end

function SoilHUD:getResizeHandleRects()
    local px, py, pw, ph = self:getHUDRect()
    local hs = SoilHUD.RESIZE_HANDLE_SIZE
    return {
        bl = {x = px,        y = py,        w = hs, h = hs},
        br = {x = px+pw-hs,  y = py,        w = hs, h = hs},
        tl = {x = px,        y = py+ph-hs,  w = hs, h = hs},
        tr = {x = px+pw-hs,  y = py+ph-hs,  w = hs, h = hs},
    }
end

function SoilHUD:hitTestCorner(posX, posY)
    for key, r in pairs(self:getResizeHandleRects()) do
        if posX >= r.x and posX <= r.x + r.w
        and posY >= r.y and posY <= r.y + r.h then
            return key
        end
    end
    return nil
end

function SoilHUD:clampPosition()
    local s = self.scale
    local pw, ph = SoilHUD.BASE_W * s, SoilHUD.BASE_H * s
    self.panelX = math.max(0.01, math.min(1.0 - pw - 0.01, self.panelX))
    self.panelY = math.max(ph + 0.01, math.min(0.98, self.panelY))
end

-- ── Mouse event ──────────────────────────────────────────
function SoilHUD:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end
    if not self.visible then return end

    if isDown and button == 3 then
        if self.editMode then
            self:exitEditMode()
        elseif self:isPointerOverHUD(posX, posY) then
            self:enterEditMode()
        end
        return
    end

    if not self.editMode then return end

    if isDown and button == 1 then
        local corner = self:hitTestCorner(posX, posY)
        if corner then
            self.resizing = true ; self.dragging = false
            self.resizeStartX = posX ; self.resizeStartY = posY
            self.resizeStartScale = self.scale
            return
        end
        if self:isPointerOverHUD(posX, posY) then
            self.dragging = true ; self.resizing = false
            self.dragOffsetX = posX - self.panelX
            self.dragOffsetY = posY - self.panelY
        end
        return
    end

    if isUp and button == 1 then
        if self.dragging or self.resizing then
            self.dragging = false ; self.resizing = false
            self:clampPosition()
        end
        return
    end

    if self.dragging then
        local pw = SoilHUD.BASE_W * self.scale
        self.panelX = math.max(0.0, math.min(1.0 - pw, posX - self.dragOffsetX))
        self.panelY = math.max(0.05, math.min(0.95, posY - self.dragOffsetY))
    end

    if self.resizing then
        local px, py, pw, ph = self:getHUDRect()
        local cx, cy = px + pw * 0.5, py + ph * 0.5
        local startDist = math.sqrt((self.resizeStartX-cx)^2 + (self.resizeStartY-cy)^2)
        local currDist  = math.sqrt((posX-cx)^2 + (posY-cy)^2)
        local delta = (currDist - startDist) * 2.5
        self.scale = math.max(SoilHUD.MIN_SCALE,
            math.min(SoilHUD.MAX_SCALE, self.resizeStartScale + delta))
        self:clampPosition()
    end

    if not self.dragging and not self.resizing then
        self.hoverCorner = self:hitTestCorner(posX, posY)
    end
end

-- ── Update ───────────────────────────────────────────────
function SoilHUD:update(dt)
    self.animTimer = self.animTimer + dt

    local currentPosition = self.settings.hudPosition or 1
    if not self.editMode and not self.dragging and self.lastHudPosition ~= currentPosition then
        self:updatePosition()
        self.lastHudPosition = currentPosition
    end

    if self.editMode then
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true)
        end
        if self.savedCamRotX ~= nil and getCamera and setRotation then
            local ok, cam = pcall(getCamera)
            if ok and cam and cam ~= 0 then
                pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
            end
        end
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            self:exitEditMode()
        end
        if not self.dragging and not self.resizing then
            if g_inputBinding and g_inputBinding.mousePosXLast then
                self.hoverCorner = self:hitTestCorner(
                    g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast)
            end
        end
    else
        self.hoverCorner = nil
    end

    -- Throttled field detection (every 0.5s)
    self.fieldDetectTimer = self.fieldDetectTimer + dt * 0.001
    if self.fieldDetectTimer >= SoilHUD.FIELD_DETECT_INTERVAL then
        self.fieldDetectTimer = 0
        self:refreshFieldData()
    end
end

-- ── Field detection ──────────────────────────────────────
function SoilHUD:refreshFieldData()
    local soilSys = g_SoilFertilityManager and g_SoilFertilityManager.soilSystem
    if not soilSys then
        self.cachedFieldId   = nil
        self.cachedFieldInfo = nil
        return
    end

    local fieldId = self:detectCurrentFieldId()
    self.cachedFieldId = fieldId
    if fieldId then
        self.cachedFieldInfo = soilSys:getFieldInfo(fieldId)
    else
        self.cachedFieldInfo = nil
    end
end

function SoilHUD:detectCurrentFieldId()
    local x, z

    -- Priority 1: g_localPlayer
    if g_localPlayer then
        if type(g_localPlayer.getIsInVehicle) == "function" and g_localPlayer:getIsInVehicle() then
            local v = g_localPlayer:getCurrentVehicle()
            if v and v.rootNode then
                local ok, vx, vy, vz = pcall(getWorldTranslation, v.rootNode)
                if ok then x, z = vx, vz end
            end
        end
        if not x and g_localPlayer.rootNode then
            local ok, px, py, pz = pcall(getWorldTranslation, g_localPlayer.rootNode)
            if ok then x, z = px, pz end
        end
    end

    -- Priority 2: controlled vehicle
    if not x and g_currentMission and g_currentMission.controlledVehicle then
        local v = g_currentMission.controlledVehicle
        if v and v.rootNode then
            local ok, vx, vy, vz = pcall(getWorldTranslation, v.rootNode)
            if ok then x, z = vx, vz end
        end
    end

    if not x then return nil end

    if g_fieldManager and g_fieldManager.getFieldAtWorldPosition then
        local ok, field = pcall(function()
            return g_fieldManager:getFieldAtWorldPosition(x, z)
        end)
        if ok and field and field.fieldId then return field.fieldId end
    end

    return nil
end

-- ── Toggle visibility (J key) ────────────────────────────
function SoilHUD:toggleVisibility()
    self.visible = not self.visible
    local msg = self.visible and "Soil HUD shown" or "Soil HUD hidden"
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(msg, 2000)
    end
end

-- ── Color helpers ────────────────────────────────────────
function SoilHUD:statusColor(status)
    if status == "Good" then return SoilHUD.C_GOOD
    elseif status == "Fair" then return SoilHUD.C_FAIR
    else return SoilHUD.C_POOR end
end

function SoilHUD:pHColor(pH)
    if pH >= 6.5 and pH <= 7.0 then return SoilHUD.C_GOOD
    elseif pH >= 5.5 and pH <= 7.5 then return SoilHUD.C_FAIR
    else return SoilHUD.C_POOR end
end

function SoilHUD:omColor(om)
    if om >= 4.0 then return SoilHUD.C_GOOD
    elseif om >= 2.5 then return SoilHUD.C_FAIR
    else return SoilHUD.C_POOR end
end

function SoilHUD:overallStatus(info)
    local rank = {Good = 1, Fair = 2, Poor = 3}
    local worst = 1
    for _, key in ipairs({"nitrogen", "phosphorus", "potassium"}) do
        local r = rank[info[key].status] or 3
        if r > worst then worst = r end
    end
    if worst == 1 then return "Good", SoilHUD.C_GOOD
    elseif worst == 2 then return "Fair", SoilHUD.C_FAIR
    else return "Poor", SoilHUD.C_POOR end
end

-- ── Draw helper ──────────────────────────────────────────
function SoilHUD:drawRect(x, y, w, h, c, a)
    if not self.fillOverlay then return end
    local alpha = a or c[4] or 1.0
    setOverlayColor(self.fillOverlay, c[1], c[2], c[3], alpha)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

-- ── Draw ─────────────────────────────────────────────────
function SoilHUD:draw()
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end
    if not self.visible then return end
    if not g_currentMission then return end

    if not self.editMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then return end
        if g_currentMission.hud and g_currentMission.hud.ingameMap then
            if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then return end
        end
    end

    self:drawPanel()
    self:drawSprayerRatePanel()
end

-- ── Main panel ───────────────────────────────────────────
function SoilHUD:drawPanel()
    local s   = self.scale
    local px  = self.panelX
    local py  = self.panelY
    local pw  = SoilHUD.BASE_W * s
    local ph  = SoilHUD.BASE_H * s

    local alpha = SoilConstants.HUD.TRANSPARENCY_LEVELS[self.settings.hudTransparency or 3]
    local fontMult = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[self.settings.hudFontSize or 2]

    -- Shadow
    self:drawRect(px + 0.003*s, py - 0.003*s, pw, ph, SoilHUD.C_SHADOW)

    -- Background
    self:drawRect(px, py, pw, ph, SoilHUD.C_BG, alpha)

    -- Title bar
    local titleH = SoilHUD.TITLE_H * s
    self:drawRect(px, py + ph - titleH, pw, titleH, SoilHUD.C_TITLE_BG)

    -- Permanent border
    local bw = 0.001
    self:drawRect(px,           py,            pw, bw, SoilHUD.C_BORDER)
    self:drawRect(px,           py + ph - bw,   pw, bw, SoilHUD.C_BORDER)
    self:drawRect(px,           py,            bw, ph, SoilHUD.C_BORDER)
    self:drawRect(px + pw - bw,  py,            bw, ph, SoilHUD.C_BORDER)

    -- Edit mode chrome
    if self.editMode then
        local pulse = 0.55 + 0.45 * math.sin(self.animTimer * 0.004)
        local ebw   = 0.002
        self:drawRect(px,            py,             pw, ebw, {1.0, 0.55, 0.10, pulse})
        self:drawRect(px,            py + ph - ebw,   pw, ebw, {1.0, 0.55, 0.10, pulse})
        self:drawRect(px,            py,             ebw, ph, {1.0, 0.55, 0.10, pulse})
        self:drawRect(px + pw - ebw,  py,             ebw, ph, {1.0, 0.55, 0.10, pulse})
        for key, r in pairs(self:getResizeHandleRects()) do
            local isHover = (self.hoverCorner == key)
            self:drawRect(r.x, r.y, r.w, r.h, SoilHUD.C_EDIT_HDL, isHover and 1.0 or 0.65)
        end
    end

    -- ── Content ───────────────────────────────────────────
    local transparency = self.settings.hudTransparency or 3
    if transparency <= 2 then setTextShadow(true) end
    setTextAlignment(RenderText.ALIGN_LEFT)

    local pad  = SoilHUD.PAD * s
    local tx   = px + pad
    local ty   = py + ph - titleH * 0.5  -- vertical center of title bar

    local info = self.cachedFieldInfo

    -- Title + overall status badge
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(tx, ty - 0.006*s, 0.012 * fontMult * s, "SOIL MONITOR")

    if info then
        local statusLabel, statusCol = self:overallStatus(info)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(statusCol[1], statusCol[2], statusCol[3], 1.0)
        renderText(px + pw - pad, ty - 0.006*s, 0.011 * fontMult * s, statusLabel)
    end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)

    -- Current Y cursor (below title bar)
    local cy = py + ph - titleH - pad

    -- Field / crop row
    local fieldText, cropText
    if info then
        fieldText = string.format("Field %d", self.cachedFieldId)
        local crop = info.lastCrop
        if crop and crop ~= "" then
            cropText = crop:sub(1,1):upper() .. crop:sub(2)
        else
            cropText = "Fallow"
        end
    else
        fieldText = "Walk onto a field"
        cropText  = nil
    end

    cy = cy - SoilHUD.LINE_H * s
    setTextColor(SoilHUD.C_LABEL[1], SoilHUD.C_LABEL[2], SoilHUD.C_LABEL[3], SoilHUD.C_LABEL[4])
    renderText(tx, cy, 0.010 * fontMult * s, fieldText)
    if cropText then
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(SoilHUD.C_DIM[1], SoilHUD.C_DIM[2], SoilHUD.C_DIM[3], SoilHUD.C_DIM[4])
        renderText(px + pw - pad, cy, 0.010 * fontMult * s, cropText)
        setTextAlignment(RenderText.ALIGN_LEFT)
    end

    -- Divider
    cy = cy - pad * 0.8
    self:drawRect(px + pad, cy, pw - pad*2, 0.0005, SoilHUD.C_DIVIDER)
    cy = cy - pad * 0.8

    if info then
        -- N / P / K rows
        cy = self:drawNutrientRow("N", info.nitrogen,   px, cy, pw, s, fontMult)
        cy = self:drawNutrientRow("P", info.phosphorus,  px, cy, pw, s, fontMult)
        cy = self:drawNutrientRow("K", info.potassium,   px, cy, pw, s, fontMult)

        -- Divider
        cy = cy - pad * 0.5
        self:drawRect(px + pad, cy, pw - pad*2, 0.0005, SoilHUD.C_DIVIDER)
        cy = cy - pad * 0.8

        -- pH + OM row
        local pHCol = self:pHColor(info.pH)
        local omCol = self:omColor(info.organicMatter)

        setTextColor(SoilHUD.C_LABEL[1], SoilHUD.C_LABEL[2], SoilHUD.C_LABEL[3], SoilHUD.C_LABEL[4])
        renderText(tx, cy, 0.010 * fontMult * s, "pH")
        setTextColor(pHCol[1], pHCol[2], pHCol[3], 1.0)
        renderText(tx + 0.020*s, cy, 0.010 * fontMult * s, string.format("%.1f", info.pH))

        local omX = tx + pw * 0.50
        setTextColor(SoilHUD.C_LABEL[1], SoilHUD.C_LABEL[2], SoilHUD.C_LABEL[3], SoilHUD.C_LABEL[4])
        renderText(omX, cy, 0.010 * fontMult * s, "OM")
        setTextColor(omCol[1], omCol[2], omCol[3], 1.0)
        renderText(omX + 0.020*s, cy, 0.010 * fontMult * s, string.format("%.1f%%", info.organicMatter))
        cy = cy - SoilHUD.LINE_H * s

        -- Divider
        cy = cy - pad * 0.5
        self:drawRect(px + pad, cy, pw - pad*2, 0.0005, SoilHUD.C_DIVIDER)
        cy = cy - pad * 0.8
    else
        cy = cy - SoilHUD.LINE_H * s * 4  -- skip nutrient rows space
    end

    -- Hint row
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(SoilHUD.C_HINT[1], SoilHUD.C_HINT[2], SoilHUD.C_HINT[3], SoilHUD.C_HINT[4])
    if self.editMode then
        renderText(px + pw * 0.5, cy, 0.009 * fontMult * s, "Drag: move   Corner: resize   RMB: done")
    else
        renderText(px + pw * 0.5, cy, 0.009 * fontMult * s, "J: toggle   K: report   RMB: move")
    end

    -- Reset text state
    if transparency <= 2 then setTextShadow(false) end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Nutrient bar row ─────────────────────────────────────
-- Returns the new cy after drawing the row.
function SoilHUD:drawNutrientRow(label, nutrient, px, cy, pw, s, fontMult)
    local pad    = SoilHUD.PAD * s
    local rowH   = SoilHUD.ROW_H * s
    local barH   = SoilHUD.BAR_H * s
    local barW   = SoilHUD.BAR_W * s
    local tx     = px + pad
    local col    = self:statusColor(nutrient.status)

    cy = cy - rowH

    -- Label (N / P / K)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(SoilHUD.C_LABEL[1], SoilHUD.C_LABEL[2], SoilHUD.C_LABEL[3], SoilHUD.C_LABEL[4])
    renderText(tx, cy + (rowH - 0.010*s) * 0.5, 0.010 * fontMult * s, label)

    -- Bar background + fill
    local barX = tx + 0.015*s
    local barY = cy + (rowH - barH) * 0.5
    self:drawRect(barX, barY, barW, barH, SoilHUD.C_BAR_BG)
    local fill = math.max(0, math.min(1, nutrient.value / 100))
    if fill > 0 then
        self:drawRect(barX, barY, barW * fill, barH, col)
    end

    -- Value
    local valX = barX + barW + 0.006*s
    setTextColor(col[1], col[2], col[3], 1.0)
    renderText(valX, cy + (rowH - 0.010*s) * 0.5, 0.010 * fontMult * s,
        string.format("%d", nutrient.value))

    -- Status label (right-aligned)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(col[1], col[2], col[3], 0.80)
    renderText(px + pw - pad, cy + (rowH - 0.009*s) * 0.5, 0.009 * fontMult * s, nutrient.status)
    setTextAlignment(RenderText.ALIGN_LEFT)

    return cy
end

-- ── Sprayer rate panel ───────────────────────────────────
function SoilHUD:drawSprayerRatePanel()
    local sprayer = self:getCurrentSprayer()
    if sprayer == nil then return end

    local rm = g_SoilFertilityManager and g_SoilFertilityManager.sprayerRateManager
    if rm == nil then return end

    local s          = self.scale
    local steps      = SoilConstants.SPRAYER_RATE.STEPS
    local currentIdx = rm:getIndex(sprayer.id)
    local fontMult   = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[self.settings.hudFontSize or 2]

    local pw     = SoilHUD.BASE_W * s
    local rateH  = self:py(24) * s
    local labelH = self:py(14) * s
    local gap    = self:py(6)  * s
    local panelH = rateH + labelH + self:py(8) * s

    local panelX = self.panelX
    local panelY = self.panelY - gap - panelH

    -- Shadow
    self:drawRect(panelX + 0.002*s, panelY - 0.002*s, pw, panelH, SoilHUD.C_SHADOW)

    -- Background + border
    self:drawRect(panelX, panelY, pw, panelH, SoilHUD.C_BG, 0.82)
    local bw = 0.001
    self:drawRect(panelX,           panelY,              pw, bw, SoilHUD.C_BORDER)
    self:drawRect(panelX,           panelY + panelH - bw,  pw, bw, SoilHUD.C_BORDER)
    self:drawRect(panelX,           panelY,              bw, panelH, SoilHUD.C_BORDER)
    self:drawRect(panelX + pw - bw,  panelY,              bw, panelH, SoilHUD.C_BORDER)

    -- Label
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(1, 1, 1, 0.90)
    renderText(panelX + pw * 0.5, panelY + rateH + self:py(4)*s,
        0.009 * fontMult * s, "APP. RATE  ( [ / ] )")
    setTextBold(false)

    local COLORS = {
        {0.35, 0.55, 0.95}, {0.25, 0.75, 0.90}, {0.20, 0.82, 0.35},
        {0.92, 0.82, 0.12}, {0.95, 0.50, 0.10}, {0.95, 0.18, 0.18},
    }
    local LABELS = {"50%", "75%", "100%", "125%", "150%", "200%"}

    local pad  = self:px(3) * s
    local btnW = (pw - pad * (#steps + 1)) / #steps
    local btnY = panelY + self:py(2) * s

    for i = 1, #steps do
        local btnX  = panelX + pad + (i-1) * (btnW + pad)
        local col   = COLORS[i]
        local isCur = (i == currentIdx)

        self:drawRect(btnX, btnY, btnW, rateH, col, isCur and 0.95 or 0.22)
        if isCur then
            self:drawRect(btnX, btnY + rateH - 0.002, btnW, 0.002, col, 1.0)
        end

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextColor(1, 1, 1, isCur and 1.0 or 0.50)
        if isCur then setTextBold(true) end
        renderText(btnX + btnW*0.5, btnY + self:py(7)*s, 0.009*fontMult*s, LABELS[i])
        if isCur then setTextBold(false) end
    end

    -- Burn warning
    local curRate = steps[currentIdx]
    local warnY   = panelY - self:py(14) * s
    setTextAlignment(RenderText.ALIGN_CENTER)
    if curRate >= SoilConstants.SPRAYER_RATE.BURN_GUARANTEED_THRESHOLD then
        setTextColor(1.0, 0.15, 0.15, 1.0)
        renderText(panelX + pw*0.5, warnY, 0.010*fontMult*s, "BURN RISK: GUARANTEED")
    elseif curRate > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
        setTextColor(0.95, 0.65, 0.10, 1.0)
        renderText(panelX + pw*0.5, warnY, 0.010*fontMult*s, "BURN RISK: POSSIBLE")
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Sprayer detection ────────────────────────────────────
function SoilHUD:getCurrentSprayer()
    local player = g_localPlayer
    if player == nil then return nil end
    if type(player.getIsInVehicle) ~= "function" then return nil end
    if not player:getIsInVehicle() then return nil end
    local vehicle = player:getCurrentVehicle()
    if vehicle and vehicle.spec_sprayer then return vehicle end
    return nil
end

-- ── Pixel helpers ────────────────────────────────────────
function SoilHUD:px(pixels) return pixels / 1920 end
function SoilHUD:py(pixels) return pixels / 1080 end
