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
SoilHUD.BASE_H = 0.228   -- Default fallback height

-- ── Layout constants at scale 1.0 ──────────────────────
SoilHUD.TITLE_H   = 0.024   -- title accent bar height
SoilHUD.ROW_H     = 0.022   -- nutrient row height
SoilHUD.LINE_H    = 0.018   -- text-only row height
SoilHUD.PAD       = 0.006   -- inner padding
SoilHUD.BAR_H     = 0.010   -- nutrient bar fill height
SoilHUD.BAR_W     = 0.095   -- nutrient bar width

-- ── Colors ──────────────────────────────────────────────
SoilHUD.C_BG         = {0.05, 0.05, 0.05, 0.82}   -- dark, matches native Field Info
SoilHUD.C_TITLE_BG   = {0.10, 0.10, 0.10, 0.90}   -- subtle dark header, no colored accent
SoilHUD.C_BORDER     = {0.20, 0.20, 0.20, 0.40}   -- neutral dark border
SoilHUD.C_DIVIDER    = {0.25, 0.25, 0.25, 0.45}   -- neutral divider
SoilHUD.C_SHADOW     = {0.00, 0.00, 0.00, 0.30}
SoilHUD.C_BAR_BG     = {0.18, 0.18, 0.18, 0.90}   -- neutral bar track
SoilHUD.C_GOOD       = {0.25, 0.85, 0.25, 1.00}   -- green  — data color, keep
SoilHUD.C_FAIR       = {0.90, 0.82, 0.18, 1.00}   -- yellow — data color, keep
SoilHUD.C_POOR       = {0.88, 0.25, 0.25, 1.00}   -- red    — data color, keep
SoilHUD.C_LABEL      = {0.72, 0.72, 0.72, 1.00}   -- neutral gray, no green tint
SoilHUD.C_VALUE      = {1.00, 1.00, 1.00, 1.00}
SoilHUD.C_DIM        = {0.52, 0.52, 0.52, 0.85}   -- neutral dim
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
    self:loadLayout()   -- override preset with saved position/scale if available
    if createImageOverlay ~= nil then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    else
        SoilLogger.warning("SoilHUD: createImageOverlay not available")
    end
    self.initialized = true
    SoilLogger.info("SoilHUD initialized at (%.3f, %.3f) scale=%.2f", self.panelX, self.panelY, self.scale)
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
    -- hudPosition 6 = Custom: use whatever loadLayout() restored, don't overwrite
    if (self.settings.hudPosition or 1) == 6 then return end
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
    self.movedInEditMode = false
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
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
    self:saveLayout()
    -- If the player actually moved/resized, switch setting to Custom (6)
    if self.movedInEditMode then
        self.movedInEditMode = false
        self.settings.hudPosition = 6
        self.settings:save()
        if g_SoilFertilityManager and g_SoilFertilityManager.settingsUI then
            g_SoilFertilityManager.settingsUI:refreshUI()
        end
    end
    SoilLogger.info("[SoilHUD] Edit mode OFF — pos=(%.3f,%.3f) scale=%.2f",
        self.panelX, self.panelY, self.scale)
end

-- ── HUD layout persistence ────────────────────────────────
function SoilHUD:getLayoutPath()
    if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        return g_currentMission.missionInfo.savegameDirectory .. "/FS25_SoilFertilizer_hud.xml"
    end
end

function SoilHUD:saveLayout()
    local path = self:getLayoutPath()
    if not path then return end
    local xml = XMLFile.create("sf_hud", path, "hudLayout")
    if xml then
        xml:setFloat("hudLayout.panelX",  self.panelX)
        xml:setFloat("hudLayout.panelY",  self.panelY)
        xml:setFloat("hudLayout.scale",   self.scale)
        xml:setBool("hudLayout.visible",  self.visible)
        xml:save()
        xml:delete()
    end
end

function SoilHUD:loadLayout()
    local path = self:getLayoutPath()
    if not path or not fileExists(path) then return end
    local xml = XMLFile.load("sf_hud", path)
    if xml then
        self.panelX  = xml:getFloat("hudLayout.panelX",  self.panelX)
        self.panelY  = xml:getFloat("hudLayout.panelY",  self.panelY)
        self.scale   = xml:getFloat("hudLayout.scale",   self.scale)
        self.visible = xml:getBool("hudLayout.visible",  self.visible)
        xml:delete()
        SoilLogger.info("[SoilHUD] Layout loaded: pos=(%.3f,%.3f) scale=%.2f", self.panelX, self.panelY, self.scale)
    end
end

-- ── Geometry helpers ─────────────────────────────────────
function SoilHUD:calculateHeight()
    local h = SoilHUD.TITLE_H + SoilHUD.PAD

    local info = self.cachedFieldInfo
    local ys = SoilConstants and SoilConstants.YIELD_SENSITIVITY
    
    if info then
        h = h + SoilHUD.LINE_H
        h = h + SoilHUD.PAD * 1.6
        
        h = h + SoilHUD.ROW_H * 3
        h = h + SoilHUD.PAD * 1.3
        
        h = h + SoilHUD.LINE_H
        h = h + SoilHUD.PAD * 1.3
        
        local cropLower = info.lastCrop and string.lower(info.lastCrop) or nil
        if not cropLower or cropLower == "" or not (ys and ys.NON_CROP_NAMES and ys.NON_CROP_NAMES[cropLower]) then
            h = h + SoilHUD.LINE_H
            h = h + SoilHUD.PAD * 1.3
        end
        
        local mgr = g_SoilFertilityManager
        if mgr and mgr.settings then
            if mgr.settings.weedPressure and (info.weedPressure or 0) > 0 then h = h + SoilHUD.LINE_H end
            if mgr.settings.pestPressure and (info.pestPressure or 0) > 0 then h = h + SoilHUD.LINE_H end
            if mgr.settings.diseasePressure and (info.diseasePressure or 0) > 0 then h = h + SoilHUD.LINE_H end
        end
        
        h = h + SoilHUD.PAD * 1.3
    else
        h = h + SoilHUD.LINE_H
        h = h + SoilHUD.LINE_H * 4
    end

    h = h + SoilHUD.LINE_H
    h = h + SoilHUD.PAD

    self.currentHeight = h
end

function SoilHUD:getHUDRect()
    local s = self.scale
    local h = self.currentHeight or SoilHUD.BASE_H
    return self.panelX, self.panelY, SoilHUD.BASE_W * s, h * s
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
    local h = self.currentHeight or SoilHUD.BASE_H
    local pw, ph = SoilHUD.BASE_W * s, h * s
    self.panelX = math.max(0.01, math.min(1.0 - pw - 0.01, self.panelX))
    self.panelY = math.max(0.01, math.min(0.98 - ph, self.panelY))
end

-- ── Mouse event ──────────────────────────────────────────
-- Returns true when the event is consumed so the caller can propagate eventUsed correctly.
function SoilHUD:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self.initialized then return false end
    if not self.settings.enabled then return false end
    if not self.settings.showHUD then return false end
    if not self.visible then return false end

    -- RMB: toggle edit mode (only consume when cursor is over panel or already in edit mode)
    if isDown and button == Input.MOUSE_BUTTON_RIGHT then
        if self.editMode then
            self:exitEditMode()
            return true
        elseif self:isPointerOverHUD(posX, posY) then
            self:enterEditMode()
            return true
        end
        return false
    end

    if not self.editMode then return false end

    -- LMB down: start drag or resize
    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        local corner = self:hitTestCorner(posX, posY)
        if corner then
            self.resizing = true ; self.dragging = false
            self.resizeStartX = posX ; self.resizeStartY = posY
            self.resizeStartScale = self.scale
            self.movedInEditMode = true
            return true
        end
        if self:isPointerOverHUD(posX, posY) then
            self.dragging = true ; self.resizing = false
            self.dragOffsetX = posX - self.panelX
            self.dragOffsetY = posY - self.panelY
            self.movedInEditMode = true
            return true
        end
        return false
    end

    -- LMB up: release drag/resize
    if isUp and button == Input.MOUSE_BUTTON_LEFT then
        if self.dragging or self.resizing then
            self.dragging = false ; self.resizing = false
            self:clampPosition()
            return true
        end
        return false
    end

    -- Mouse move: update drag/resize/hover
    if self.dragging then
        local pw = SoilHUD.BASE_W * self.scale
        self.panelX = math.max(0.0, math.min(1.0 - pw, posX - self.dragOffsetX))
        self.panelY = math.max(0.05, math.min(0.95, posY - self.dragOffsetY))
        return true
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
        return true
    end

    self.hoverCorner = self:hitTestCorner(posX, posY)
    return false
end

-- ── Update ───────────────────────────────────────────────
function SoilHUD:update(dt)
    self.animTimer = self.animTimer + dt
    self:calculateHeight()

    local currentPosition = self.settings.hudPosition or 1
    if not self.editMode and not self.dragging and self.lastHudPosition ~= currentPosition then
        self:updatePosition()
        self.lastHudPosition = currentPosition
    end

    -- Detection for initial RMB click when cursor might be hidden
    if not self.editMode and self.initialized and self.settings.enabled and self.settings.showHUD and self.visible then
        if g_inputBinding and g_inputBinding:getIsInputButtonDown(InputButton.RIGHT) then
            -- Note: posX/posY might not be perfectly accurate if hidden, but we check last known
            if g_inputBinding.mousePosXLast and g_inputBinding.mousePosYLast then
                if self:isPointerOverHUD(g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast) then
                    self:enterEditMode()
                end
            end
        end
    end

    if self.editMode then
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true, true)
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
    local prevId  = self.cachedFieldId
    self.cachedFieldId = fieldId

    if fieldId then
        self.cachedFieldInfo = soilSys:getFieldInfo(fieldId)

        if fieldId ~= prevId and self.cachedFieldInfo then
            local info = self.cachedFieldInfo
            local ppm  = SoilConstants.PPM_DISPLAY or { N=1, P=1, K=1 }
            SoilLogger.debug("HUD field → %s | N=%d (raw) → %dppm | P=%d → %dppm | K=%d → %dppm | pH=%.1f | OM=%.1f",
                tostring(fieldId),
                math.floor(info.nitrogen.value + 0.5),
                math.floor(info.nitrogen.value   * ppm.N + 0.5),
                math.floor(info.phosphorus.value + 0.5),
                math.floor(info.phosphorus.value * ppm.P + 0.5),
                math.floor(info.potassium.value  + 0.5),
                math.floor(info.potassium.value  * ppm.K + 0.5),
                info.pH,
                info.organicMatter
            )
            SoilLogger.debug("HUD status → N:%s P:%s K:%s",
                tostring(info.nitrogen.status),
                tostring(info.phosphorus.status),
                tostring(info.potassium.status)
            )
        end
    else
        self.cachedFieldInfo = nil
        if prevId and prevId ~= fieldId then
            SoilLogger.debug("HUD field → off-field (was %s)", tostring(prevId))
        end
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

    -- Tier 1: direct field lookup via position
    -- NOTE: do NOT guard with g_fieldManager.getFieldAtWorldPosition — in FS25's OOP
    -- system methods live on the metatable, not the instance, so that check returns nil
    -- even when the method is callable. Always use pcall directly.
    -- NOTE: field.fieldId / field.id / field.index all return nil in FS25.
    -- The correct identifier is field.farmland.id (confirmed in SoilFertilitySystem).
    if g_fieldManager then
        local ok, field = pcall(function()
            return g_fieldManager:getFieldAtWorldPosition(x, z)
        end)
        if ok and field and field.farmland and field.farmland.id then
            return field.farmland.id
        end
    end

    -- Tier 2: farmland object lookup
    -- NOTE: getFarmlandIdAtWorldPosition does not exist in FS25.
    -- getFarmlandAtWorldPosition returns a farmland object; read .id from it.
    if g_farmlandManager then
        local ok, farmland = pcall(function()
            return g_farmlandManager:getFarmlandAtWorldPosition(x, z)
        end)
        if ok and farmland and farmland.id and farmland.id > 0 then
            return farmland.id
        end
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
    -- N / P / K
    for _, key in ipairs({"nitrogen", "phosphorus", "potassium"}) do
        local r = rank[info[key].status] or 3
        if r > worst then worst = r end
    end
    -- pH
    if info.pH then
        local r = rank[self:pHColor(info.pH) == SoilHUD.C_POOR and "Poor"
                    or self:pHColor(info.pH) == SoilHUD.C_FAIR and "Fair"
                    or "Good"] or 1
        if r > worst then worst = r end
    end
    -- OM
    if info.organicMatter then
        local r = rank[self:omColor(info.organicMatter) == SoilHUD.C_POOR and "Poor"
                    or self:omColor(info.organicMatter) == SoilHUD.C_FAIR and "Fair"
                    or "Good"] or 1
        if r > worst then worst = r end
    end
    -- Weed / pest / disease pressures (0-100, 3-level: <25 Good, <60 Fair, else Poor)
    for _, key in ipairs({"weedPressure", "pestPressure", "diseasePressure"}) do
        local val = info[key]
        if val and val >= 0 then
            local r = (val >= 60) and 3 or (val >= 25) and 2 or 1
            if r > worst then worst = r end
        end
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
    local ph  = (self.currentHeight or SoilHUD.BASE_H) * s

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
    renderText(tx, ty - 0.006*s, 0.012 * fontMult * s, g_i18n:getText("sf_hud_title"))

    if info then
        local statusLabel, statusCol = self:overallStatus(info)
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextColor(statusCol[1], statusCol[2], statusCol[3], 1.0)
        renderText(px + pw - pad, ty - 0.006*s, 0.011 * fontMult * s, g_i18n:getText("sf_report_rec_" .. statusLabel:lower()))
    end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)

    -- Current Y cursor (below title bar)
    local cy = py + ph - titleH - pad

    -- Field / crop row
    local fieldText, cropText
    if info then
        fieldText = string.format(g_i18n:getText("sf_hud_field"), self.cachedFieldId)
        local crop = info.lastCrop
        if crop and crop ~= "" then
            cropText = crop:sub(1,1):upper() .. crop:sub(2)
        else
            cropText = g_i18n:getText("sf_hud_fallow")
        end
    else
        fieldText = g_i18n:getText("sf_hud_noField")
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

    -- Divider above N/P/K block; "(ppm)" unit label right-aligned on the same line
    -- so the user sees the unit context once, not repeated on every row.
    cy = cy - pad * 0.8
    self:drawRect(px + pad, cy, pw - pad*2, 0.0005, SoilHUD.C_DIVIDER)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(SoilHUD.C_DIM[1], SoilHUD.C_DIM[2], SoilHUD.C_DIM[3], 0.60)
    renderText(px + pw - pad, cy + 0.001*s, 0.007 * fontMult * s, "(ppm)")
    setTextAlignment(RenderText.ALIGN_LEFT)
    cy = cy - pad * 0.8

    if info then
        -- Detect current sprayer activity for "Projected" ghost bars
        local sprayer = self:getCurrentSprayer()
        local fillType = self:getSprayerFillType(sprayer)
        local profile = fillType and SoilConstants.FERTILIZER_PROFILES[fillType.name]

        -- N / P / K rows
        cy = self:drawNutrientRow("N", info.nitrogen,   px, cy, pw, s, fontMult, info, profile, fillType)
        cy = self:drawNutrientRow("P", info.phosphorus,  px, cy, pw, s, fontMult, info, profile, fillType)
        cy = self:drawNutrientRow("K", info.potassium,   px, cy, pw, s, fontMult, info, profile, fillType)

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

        -- Divider below pH/OM row
        cy = cy - SoilHUD.LINE_H * s
        cy = cy - pad * 0.5
        self:drawRect(px + pad, cy, pw - pad*2, 0.0005, SoilHUD.C_DIVIDER)
        cy = cy - pad * 0.8

        -- Yield forecast row (Issue #81 interim HUD warning)
        -- Always shown unless the crop is a NON_CROP (like grass).
        local ys = SoilConstants.YIELD_SENSITIVITY
        local cropLower = info.lastCrop and string.lower(info.lastCrop) or nil
        
        if not cropLower or cropLower == "" or not ys.NON_CROP_NAMES[cropLower] then
            local tier     = ys.CROP_TIERS[cropLower] or ys.DEFAULT_TIER
            local tierData = ys.TIERS[tier]
            local thresh   = ys.OPTIMAL_THRESHOLD

            local nDef = math.max(0, thresh - info.nitrogen.value)   / thresh
            local pDef = math.max(0, thresh - info.phosphorus.value) / thresh
            local kDef = math.max(0, thresh - info.potassium.value)  / thresh
            local avgDef = (nDef + pDef + kDef) / 3

            local penalty    = math.min(ys.MAX_PENALTY, avgDef * tierData.scale)
            local penaltyPct = math.floor(penalty * 100 + 0.5)

            local yieldColor, yieldText
            local yieldPrefix = (not cropLower or cropLower == "") and g_i18n:getText("sf_hud_estYield") or g_i18n:getText("sf_hud_yield")
            if penaltyPct <= 0 then
                yieldColor = SoilHUD.C_GOOD
                yieldText  = string.format("%s: %s", yieldPrefix, g_i18n:getText("sf_hud_optimal"))
            elseif penaltyPct < 15 then
                yieldColor = SoilHUD.C_FAIR
                yieldText  = string.format("%s ~-%d%%", yieldPrefix, penaltyPct)
            else
                yieldColor = SoilHUD.C_POOR
                yieldText  = string.format("%s ~-%d%%", yieldPrefix, penaltyPct)
            end

            setTextColor(yieldColor[1], yieldColor[2], yieldColor[3], 1.0)
            renderText(tx, cy, 0.010 * fontMult * s, yieldText)
            setTextAlignment(RenderText.ALIGN_RIGHT)
            setTextColor(SoilHUD.C_DIM[1], SoilHUD.C_DIM[2], SoilHUD.C_DIM[3], SoilHUD.C_DIM[4])
            renderText(px + pw - pad, cy, 0.009 * fontMult * s, tierData.label)
            setTextAlignment(RenderText.ALIGN_LEFT)

            -- Divider before weed row
            cy = cy - SoilHUD.LINE_H * s
            cy = cy - pad * 0.5
            self:drawRect(px + pad, cy, pw - pad*2, 0.0005, SoilHUD.C_DIVIDER)
            cy = cy - pad * 0.8
        end

        -- Weed / pest / disease pressure rows
        local mgr = g_SoilFertilityManager
        if mgr then
            if mgr.settings.weedPressure then
                cy = self:drawPressureRow("sf_hud_weeds", info.weedPressure or 0,
                    info.herbicideActive, px, cy, pw, s, fontMult)
            end
            if mgr.settings.pestPressure then
                cy = self:drawPressureRow("sf_hud_pests", info.pestPressure or 0,
                    info.insecticideActive, px, cy, pw, s, fontMult)
            end
            if mgr.settings.diseasePressure then
                cy = self:drawPressureRow("sf_hud_disease", info.diseasePressure or 0,
                    info.fungicideActive, px, cy, pw, s, fontMult)
            end
        end

        -- Divider before hint
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
        renderText(px + pw * 0.5, cy, 0.009 * fontMult * s, g_i18n:getText("sf_hud_hint_edit"))
    else
        renderText(px + pw * 0.5, cy, 0.009 * fontMult * s, g_i18n:getText("sf_hud_hint_normal"))
    end

    -- Reset text state
    if transparency <= 2 then setTextShadow(false) end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Nutrient bar row ─────────────────────────────────────
-- Returns the new cy after drawing the row.
-- label must be "N", "P", or "K" — used to look up ppm conversion + thresholds.
function SoilHUD:drawNutrientRow(label, nutrient, px, cy, pw, s, fontMult, info, profile, fillType)
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

    -- Projected "Ghost Bar" (V1.7 Realism Update)
    -- Shows the expected nutrient gain for the remainder of the current application pass.
    local projectedDelta = 0
    if profile and profile[label] and info and info.nutrientBuffer then
        local fillTypeIndex = fillType and fillType.index
        if fillTypeIndex then
            local currentBuffer = info.nutrientBuffer[fillTypeIndex] or 0
            local br = SoilConstants.SPRAYER_RATE.BASE_RATES
            local baseRate = (fillType and br[fillType.name]) or br.DEFAULT
            
            if baseRate then
                local targetVolume = (info.fieldArea or 1.0) * baseRate.value
                
                -- Ghost bar shows the gain remaining to reach the 90% threshold
                local threshold = targetVolume * (SoilConstants.SPRAYER_RATE.FERTILIZER_COVERAGE_THRESHOLD or 0.90)
                local remaining = math.max(0, threshold - currentBuffer)
                
                if remaining > 0 then
                    projectedDelta = profile[label] * (remaining / 1000) / (info.fieldArea or 1.0)
                    local ghostFill = math.min(1.0 - fill, projectedDelta / 100)
                    if ghostFill > 0 then
                        self:drawRect(barX + barW * fill, barY, barW * ghostFill, barH, col, 0.35)
                    end
                end
            end
        end
    end

    -- Threshold tick marks
    local thresholdKey = label == "N" and "nitrogen"
                      or label == "P" and "phosphorus"
                      or label == "K" and "potassium"
                      or nil
    if thresholdKey then
        local th = SoilConstants.STATUS_THRESHOLDS[thresholdKey]
        if th then
            local tickW  = 0.0005 * s
            local tickH  = barH + 0.002 * s
            local tickY  = barY - 0.001 * s
            local poorX  = barX + barW * (th.poor / 100) - tickW * 0.5
            local fairX  = barX + barW * (th.fair / 100) - tickW * 0.5
            self:drawRect(poorX, tickY, tickW, tickH, {0.70, 0.70, 0.70, 0.50})
            self:drawRect(fairX, tickY, tickW, tickH, {0.70, 0.70, 0.70, 0.50})
        end
    end

    -- Value displayed in ppm
    local ppmMult = SoilConstants.PPM_DISPLAY and SoilConstants.PPM_DISPLAY[label] or 1.0
    local ppmVal  = math.floor(nutrient.value * ppmMult + 0.5)
    local valX    = barX + barW + 0.006*s
    setTextColor(col[1], col[2], col[3], 1.0)
    
    local valStr = string.format("%d", ppmVal)
    if projectedDelta > 0 then
        local projPpm = math.floor(projectedDelta * ppmMult + 0.5)
        if projPpm > 0 then
            valStr = valStr .. string.format(" (+%d)", projPpm)
        end
    end
    renderText(valX, cy + (rowH - 0.010*s) * 0.5, 0.010 * fontMult * s, valStr)

    -- Status label
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(col[1], col[2], col[3], 0.80)
    renderText(px + pw - pad, cy + (rowH - 0.009*s) * 0.5, 0.009 * fontMult * s, nutrient.status)
    setTextAlignment(RenderText.ALIGN_LEFT)

    return cy
end

-- ── Pressure bar row ─────────────────────────────────────
-- Draws a single weed/pest/disease pressure row.
-- pressure is 0-100.  isProtected shows "(protected)" suffix when true.
-- Returns updated cy after the row.
function SoilHUD:drawPressureRow(labelKey, pressure, isProtected, px, cy, pw, s, fontMult)
    local pad  = SoilHUD.PAD * s
    local barH = SoilHUD.BAR_H * s
    local barW = SoilHUD.BAR_W * s
    local tx   = px + pad

    -- 3-level color (matches getPressureColor in SoilReportDialog — aligned with Constants thresholds)
    local wp = SoilConstants.WEED_PRESSURE  -- LOW=20, MEDIUM=50 (shared by weed/pest/disease)
    local col
    if pressure < wp.LOW    then col = SoilHUD.C_GOOD
    elseif pressure < wp.MEDIUM then col = SoilHUD.C_FAIR
    else                         col = SoilHUD.C_POOR end

    -- Label
    setTextColor(SoilHUD.C_LABEL[1], SoilHUD.C_LABEL[2], SoilHUD.C_LABEL[3], SoilHUD.C_LABEL[4])
    renderText(tx, cy, 0.010 * fontMult * s, g_i18n:getText(labelKey))

    -- Bar
    local barX = tx + 0.038*s
    local barY = cy + (SoilHUD.LINE_H * s - barH) * 0.5
    self:drawRect(barX, barY, barW, barH, SoilHUD.C_BAR_BG)
    local fill = math.max(0, math.min(1, pressure / 100))
    if fill > 0 then
        self:drawRect(barX, barY, barW * fill, barH, col)
    end

    -- Value + protection tag
    local label = string.format("%.0f%%", pressure)
    if isProtected then label = label .. " " .. g_i18n:getText("sf_hud_protected") end
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(col[1], col[2], col[3], 1.0)
    renderText(px + pw - pad, cy, 0.010 * fontMult * s, label)
    setTextAlignment(RenderText.ALIGN_LEFT)

    return cy - SoilHUD.LINE_H * s
end

-- ── Sprayer fill-type helpers ─────────────────────────────
--- Returns the FillType object currently loaded in the sprayer, or nil.
function SoilHUD:getSprayerFillType(sprayer)
    if not sprayer then return nil end
    local fillTypeIndex

    -- Try workAreaParameters first (populated while actively spraying)
    local spec = sprayer.spec_sprayer
    if spec and spec.workAreaParameters then
        local ft = spec.workAreaParameters.sprayFillType
        if ft and ft > 0 then fillTypeIndex = ft end
    end

    -- Fall back to fill unit query (works when parked)
    if not fillTypeIndex then
        local ok, ft = pcall(function() return sprayer:getFillUnitFillType(1) end)
        if ok and ft and ft > 0 then fillTypeIndex = ft end
    end

    if not fillTypeIndex then return nil end
    return g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
end

--- Returns the BASE_RATES entry for a fill type, falling back to DEFAULT.
function SoilHUD:getRateConfig(fillType)
    local br = SoilConstants.SPRAYER_RATE.BASE_RATES
    if fillType and br[fillType.name] then
        return br[fillType.name]
    end
    return br.DEFAULT
end

--- Returns a formatted rate string with units for the given multiplier.
--- Shows gal/ac (liquid) or lb/ac (dry) when useImperialUnits is true,
--- otherwise L/ha or kg/ha.
function SoilHUD:formatRate(multiplier, rateConfig)
    local value    = rateConfig.value * multiplier
    local imperial = (self.settings.useImperialUnits ~= false)
    local conv     = SoilConstants.SPRAYER_RATE

    -- For very low base rates (Insecticide/Fungicide), show 1 decimal place
    local fmt = (rateConfig.value < 10.0) and "%.1f" or "%.0f"

    if rateConfig.unit == "liquid" then
        if imperial then
            local impVal = value * conv.L_PER_HA_TO_GAL_PER_AC
            return string.format(fmt .. " gal/ac", impVal)
        else
            return string.format(fmt .. " L/ha", value)
        end
    else
        if imperial then
            local impVal = value * conv.KG_PER_HA_TO_LB_PER_AC
            return string.format(fmt .. " lb/ac", impVal)
        else
            return string.format(fmt .. " kg/ha", value)
        end
    end
end

--- Returns just the numeric part of the rate (no unit suffix), for adjacent step labels.
function SoilHUD:formatRateNumber(multiplier, rateConfig)
    local value    = rateConfig.value * multiplier
    local imperial = (self.settings.useImperialUnits ~= false)
    local conv     = SoilConstants.SPRAYER_RATE

    -- For very low base rates, show 1 decimal place
    local fmt = (rateConfig.value < 10.0) and "%.1f" or "%.0f"

    if rateConfig.unit == "liquid" then
        if imperial then
            return string.format(fmt, value * conv.L_PER_HA_TO_GAL_PER_AC)
        else
            return string.format(fmt, value)
        end
    else
        if imperial then
            return string.format(fmt, value * conv.KG_PER_HA_TO_LB_PER_AC)
        else
            return string.format(fmt, value)
        end
    end
end

-- ── Sprayer rate panel ───────────────────────────────────
-- Center-scroll design: ← prev prev  CURRENT RATE  next next →
-- Thin progress bar beneath; burn warning below panel.
function SoilHUD:drawSprayerRatePanel()
    local sprayer = self:getCurrentSprayer()
    if sprayer == nil then return end

    local rm = g_SoilFertilityManager and g_SoilFertilityManager.sprayerRateManager
    if rm == nil then return end

    local s          = self.scale
    local steps      = SoilConstants.SPRAYER_RATE.STEPS
    local currentIdx = rm:getIndex(sprayer.id)
    local fontMult   = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[self.settings.hudFontSize or 2]
    local fillType   = self:getSprayerFillType(sprayer)
    local rateConfig = self:getRateConfig(fillType)
    local curMult    = steps[currentIdx]

    -- Panel geometry
    local pw      = SoilHUD.BASE_W * s
    local padV    = self:py(5)  * s
    local barH    = self:py(4)  * s
    local scrollH = self:py(22) * s
    local headerH = self:py(16) * s
    local panelH  = padV + barH + padV + scrollH + padV + headerH
    local gap     = self:py(6) * s
    local panelX  = self.panelX
    local panelY  = self.panelY - gap - panelH
    local cx      = panelX + pw * 0.5

    -- Shadow + background + border
    self:drawRect(panelX + 0.002*s, panelY - 0.002*s, pw, panelH, SoilHUD.C_SHADOW)
    self:drawRect(panelX, panelY, pw, panelH, SoilHUD.C_BG, 0.82)
    local bw = 0.001
    self:drawRect(panelX,           panelY,               pw, bw, SoilHUD.C_BORDER)
    self:drawRect(panelX,           panelY + panelH - bw,  pw, bw, SoilHUD.C_BORDER)
    self:drawRect(panelX,           panelY,               bw, panelH, SoilHUD.C_BORDER)
    self:drawRect(panelX + pw - bw,  panelY,               bw, panelH, SoilHUD.C_BORDER)

    -- Header: "APP. RATE  AUTO: OFF  [Alt+Z]" or "APP. RATE  AUTO: ON"
    -- isAuto = auto rate mode active on this vehicle AND the setting is enabled
    local isAuto = rm:getAutoMode(sprayer.id) and self.settings.autoRateControl
    local autoKey = "Shift+L"   -- fallback display string (matches modDesc.xml binding)
    if g_inputDisplayManager ~= nil then
        local ok, helpElement = pcall(function()
            -- Four-argument form per FS25 API: (action1, action2, text, ignoreComboButtons)
            return g_inputDisplayManager:getControllerSymbolOverlays(InputAction.SF_TOGGLE_AUTO, "", "", false)
        end)
        if ok and helpElement ~= nil and helpElement.keys ~= nil and #helpElement.keys > 0 then
            -- keys is an array of display strings, one per key in the combo (e.g. {"Shift","L"})
            -- Join them with "+" to produce "Shift+L"
            local parts = {}
            for _, k in ipairs(helpElement.keys) do
                table.insert(parts, tostring(k))
            end
            autoKey = table.concat(parts, "+")
        end
    end
    -- Separate the mode status from the toggle hint so AUTO is never ambiguous
    local headerText
    if isAuto then
        headerText = "APP. RATE  ( AUTO: ON )"
    else
        headerText = string.format("APP. RATE  AUTO: OFF [%s]", autoKey)
    end

    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(1, 1, 1, 0.90)
    if isAuto then
        setTextColor(0.4, 1.0, 0.4, 1.0)
    end
    renderText(cx, panelY + panelH - headerH * 0.5 - self:py(3)*s,
        0.009 * fontMult * s, headerText)
    setTextBold(false)

    -- Rate scroll row base Y
    local scrollY = panelY + padV + barH + padV

    -- Current rate color (burn-aware or auto-aware)
    local curCol
    if isAuto then
        curCol = {0.4, 1.0, 0.4, 1.0}
    elseif curMult >= SoilConstants.SPRAYER_RATE.BURN_GUARANTEED_THRESHOLD then
        curCol = {1.0, 0.20, 0.20, 1.0}
    elseif curMult > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
        curCol = {0.95, 0.65, 0.10, 1.0}
    else
        curCol = {1.0, 1.0, 1.0, 1.0}
    end

    -- Current rate (large, centered, bold)
    local curRateStr = self:formatRate(curMult, rateConfig)
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(curCol[1], curCol[2], curCol[3], 1.0)
    renderText(cx, scrollY + self:py(7)*s, 0.013 * fontMult * s, curRateStr)
    setTextBold(false)

    -- In Auto-Mode, show what we are targeting below the rate
    if isAuto and fillType then
        local profile = SoilConstants.FERTILIZER_PROFILES[fillType.name]
        if profile then
            local targetText = "Target: "
            local targets = SoilConstants.SPRAYER_RATE.AUTO_RATE_TARGETS
            if not targets then return end
            if profile.N and profile.N > 0 then targetText = targetText .. targets.N .. "N " end
            if profile.P and profile.P > 0 then targetText = targetText .. targets.P .. "P " end
            if profile.K and profile.K > 0 then targetText = targetText .. targets.K .. "K " end
            if profile.pH and profile.pH > 0 then targetText = targetText .. targets.pH .. "pH " end
            setTextColor(0.7, 0.9, 0.7, 0.8)
            renderText(cx, scrollY - self:py(6)*s, 0.008 * fontMult * s, targetText)
        end
    end

    -- Adjacent steps: offsets -2, -1, +1, +2
    -- Positioned symmetrically around center, dimming by distance
    local adjPositions = { [-2] = -0.38, [-1] = -0.21, [1] = 0.21, [2] = 0.38 }
    local adjSizes     = { [-2] = 0.008, [-1] = 0.009, [1] = 0.009, [2] = 0.008 }
    local adjAlphas    = { [-2] = 0.28,  [-1] = 0.50,  [1] = 0.50,  [2] = 0.28  }

    setTextAlignment(RenderText.ALIGN_CENTER)
    for _, offset in ipairs({-2, -1, 1, 2}) do
        local adjIdx = currentIdx + offset
        if adjIdx >= 1 and adjIdx <= #steps then
            local adjStr = self:formatRateNumber(steps[adjIdx], rateConfig)
            setTextColor(1.0, 1.0, 1.0, adjAlphas[offset])
            renderText(cx + pw * adjPositions[offset], scrollY + self:py(7)*s,
                adjSizes[offset] * fontMult * s, adjStr)
        end
    end

    -- Progress bar
    local progress = (currentIdx - 1) / (#steps - 1)
    local barPad   = pw * 0.06
    local barW     = pw - barPad * 2
    local barY     = panelY + padV
    self:drawRect(panelX + barPad, barY, barW, barH, SoilHUD.C_BAR_BG)
    if progress > 0 then
        self:drawRect(panelX + barPad, barY, barW * progress, barH, curCol)
    end

    -- Burn warning below panel
    local warnY = panelY - self:py(14) * s
    setTextAlignment(RenderText.ALIGN_CENTER)
    if curMult >= SoilConstants.SPRAYER_RATE.BURN_GUARANTEED_THRESHOLD then
        setTextColor(1.0, 0.15, 0.15, 1.0)
        renderText(cx, warnY, 0.010 * fontMult * s, "BURN RISK: GUARANTEED")
    elseif curMult > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
        setTextColor(0.95, 0.65, 0.10, 1.0)
        renderText(cx, warnY, 0.010 * fontMult * s, "BURN RISK: POSSIBLE")
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Sprayer / spreader detection ────────────────────────────────────
-- Recursively walks the attacher-joint implement tree of `vehicle` looking
-- for the first attached object that passes isFertilizerApplicator.
-- Used so that tractor+spreader combos show the rate panel even though the
-- player is seated in the tractor, not the spreader.
-- Safe: wrapped in pcall; returns nil on any API error.
local function findApplicatorImplement(vehicle)
    if not vehicle then return nil end
    local ok, spec = pcall(function() return vehicle.spec_attacherJoints end)
    if not ok or not spec then return nil end
    local ok2, implements = pcall(function() return spec.attachedImplements end)
    if not ok2 or not implements then return nil end
    for _, impl in pairs(implements) do
        local obj = impl.object
        if obj then
            if SoilFertilityManager.isFertilizerApplicator(obj) then
                return obj
            end
            -- Recurse: implements can themselves have implements (e.g. wagon train)
            local found = findApplicatorImplement(obj)
            if found then return found end
        end
    end
    return nil
end

-- Returns the fertilizer applicator the player should adjust rate for:
--   1. The directly driven vehicle (self-propelled sprayer / spreader)
--   2. First attached implement that passes isFertilizerApplicator (tractor+spreader)
-- Returns the current vehicle if it is any fertilizer applicator (liquid sprayer,
-- dry spreader, or planter with fertilizer capability).  Uses isFertilizerApplicator
-- so the rate panel appears for all equipment types, not just spec_sprayer vehicles.
function SoilHUD:getCurrentSprayer()
    local player = g_localPlayer
    if player == nil then return nil end
    if type(player.getIsInVehicle) ~= "function" then return nil end
    if not player:getIsInVehicle() then
        -- State change: was in sprayer, now not
        if self._lastSprayerDetected ~= false then
            self._lastSprayerDetected = false
            SoilLogger.debug("getCurrentSprayer: player NOT in vehicle — rate panel hidden")
        end
        return nil
    end
    local vehicle = player:getCurrentVehicle()
    if not vehicle then return nil end

    local result = nil
    if SoilFertilityManager and SoilFertilityManager.isFertilizerApplicator then
        if SoilFertilityManager.isFertilizerApplicator(vehicle) then
            -- Self-propelled: the driven vehicle is the applicator
            result = vehicle
        else
            -- Pulled implement: scan the attacher joint tree
            result = findApplicatorImplement(vehicle)
        end
    elseif vehicle.spec_sprayer then
        -- Fallback: SoilFertilityManager not yet available, accept any sprayer
        result = vehicle
    end

    -- Log only on state change to avoid log spam
    local prevId = self._lastSprayerVehicleId
    local newId  = result and result.id or nil
    if prevId ~= newId then
        self._lastSprayerVehicleId = newId
        self._lastSprayerDetected  = (result ~= nil)
        if result then
            local isImpl = (result ~= vehicle) and "IMPLEMENT" or "DIRECT"
            SoilLogger.debug("getCurrentSprayer: APPLICATOR %s id=%s cfg=%s",
                isImpl, tostring(result.id), tostring(result.configFileName))
        else
            SoilLogger.debug("getCurrentSprayer: no applicator on vehicle cfg=%s — rate panel hidden",
                tostring(vehicle.configFileName))
        end
    end
    return result
end

-- ── Pixel helpers ────────────────────────────────────────
function SoilHUD:px(pixels) return pixels / 1920 end
function SoilHUD:py(pixels) return pixels / 1080 end