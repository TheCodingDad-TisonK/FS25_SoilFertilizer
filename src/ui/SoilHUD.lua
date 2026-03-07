-- =========================================================
-- FS25 Realistic Soil & Fertilizer
-- =========================================================
-- Soil HUD Overlay - legend/reference display
-- Toggle with J key. RMB to enter drag/resize edit mode.
-- Follows the NPCFavorHUD pattern for edit mode UX.
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
-- Width comes from the shared constant; height is defined here
-- because we add more content (dividers, hint) than the original.
SoilHUD.BASE_W = 0.165   -- slightly wider than the old 0.15 for readability
SoilHUD.BASE_H = 0.178   -- title + 2 keys + dividers + 3 status + pH + hint

-- ── Color constants ─────────────────────────────────────
SoilHUD.COLOR_BG          = {0.05, 0.05, 0.08, 0.78}
SoilHUD.COLOR_TITLE_BG    = {0.08, 0.18, 0.38, 0.88}
SoilHUD.COLOR_BORDER      = {0.30, 0.30, 0.42, 0.55}
SoilHUD.COLOR_DIVIDER     = {0.35, 0.35, 0.50, 0.50}
SoilHUD.COLOR_SHADOW      = {0.00, 0.00, 0.00, 0.32}
SoilHUD.COLOR_EDIT_HANDLE = {0.20, 0.60, 1.00, 0.85}

function SoilHUD.new(soilSystem, settings)
    local self = setmetatable({}, SoilHUD_mt)

    self.soilSystem  = soilSystem
    self.settings    = settings
    self.initialized = false
    self.visible     = true   -- J-key toggle

    -- Position (from preset, overridden by drag)
    local defaultPos = SoilConstants.HUD.POSITIONS[1]
    self.panelX          = defaultPos.x
    self.panelY          = defaultPos.y
    self.lastHudPosition = nil

    -- Scale & edit state (mirrors HUDOverlay / NPCFavorHUD)
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

    -- Single overlay handle (set in initialize)
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
        SoilLogger.warn("SoilHUD: createImageOverlay not available — rect rendering disabled")
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
    SoilLogger.info("SoilHUD deleted")
end

-- ── Position preset ──────────────────────────────────────
function SoilHUD:updatePosition()
    local position = self.settings.hudPosition or 1
    local pos = SoilConstants.HUD.POSITIONS[position]
    if pos then
        self.panelX = pos.x
        self.panelY = pos.y
    end
end

-- ── Edit mode: enter ─────────────────────────────────────
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
    SoilLogger.info("[SoilHUD] Edit mode ON — drag to move, corners to resize, RMB to finish")
end

-- ── Edit mode: exit ──────────────────────────────────────
function SoilHUD:exitEditMode()
    self.editMode    = false
    self.dragging    = false
    self.resizing    = false
    self.hoverCorner = nil
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    SoilLogger.info("[SoilHUD] Edit mode OFF — position (%.3f, %.3f) scale=%.2f",
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
    local s  = self.scale
    local pw = SoilHUD.BASE_W * s
    local ph = SoilHUD.BASE_H * s
    self.panelX = math.max(0.01, math.min(1.0 - pw - 0.01, self.panelX))
    self.panelY = math.max(ph + 0.01, math.min(0.98, self.panelY))
end

-- ── Mouse event (called from main.lua addModEventListener) ──
-- FS25 button numbers: 1=LMB, 3=RMB, 2=MMB.
-- With setShowMouseCursor(true) active, FS25 fires mouseEvent
-- on every mouse MOVEMENT as well as clicks, enabling continuous drag.
--
-- RMB only enters edit mode when cursor is over THIS panel
-- to prevent cross-contamination with other mods' RMB handlers.
function SoilHUD:onMouseEvent(posX, posY, isDown, isUp, button)
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end
    if not self.visible then return end

    -- RMB: enter if over our HUD, exit from anywhere while editing
    if isDown and button == 3 then
        if self.editMode then
            self:exitEditMode()
        elseif self:isPointerOverHUD(posX, posY) then
            self:enterEditMode()
        end
        return
    end

    if not self.editMode then return end

    -- LMB down: corner resize or body drag
    if isDown and button == 1 then
        local corner = self:hitTestCorner(posX, posY)
        if corner then
            self.resizing         = true
            self.dragging         = false
            self.resizeStartX     = posX
            self.resizeStartY     = posY
            self.resizeStartScale = self.scale
            return
        end
        if self:isPointerOverHUD(posX, posY) then
            self.dragging    = true
            self.resizing    = false
            self.dragOffsetX = posX - self.panelX
            self.dragOffsetY = posY - self.panelY
        end
        return
    end

    -- LMB up: end drag/resize and clamp
    if isUp and button == 1 then
        if self.dragging or self.resizing then
            self.dragging = false
            self.resizing = false
            self:clampPosition()
        end
        return
    end

    -- Mouse movement: continuous drag or resize
    if self.dragging then
        local s = self.scale
        local pw = SoilHUD.BASE_W * s
        self.panelX = math.max(0.0, math.min(1.0 - pw, posX - self.dragOffsetX))
        self.panelY = math.max(0.05, math.min(0.95, posY - self.dragOffsetY))
    end

    if self.resizing then
        local px, py, pw, ph = self:getHUDRect()
        local cx       = px + pw * 0.5
        local cy       = py + ph * 0.5
        local startDist = math.sqrt((self.resizeStartX - cx)^2 + (self.resizeStartY - cy)^2)
        local currDist  = math.sqrt((posX - cx)^2 + (posY - cy)^2)
        local delta     = (currDist - startDist) * 2.5
        self.scale = math.max(SoilHUD.MIN_SCALE,
            math.min(SoilHUD.MAX_SCALE, self.resizeStartScale + delta))
        self:clampPosition()
    end

    -- Hover corner detection while not dragging/resizing
    if not self.dragging and not self.resizing then
        self.hoverCorner = self:hitTestCorner(posX, posY)
    end
end

-- ── Update (called every frame) ──────────────────────────
function SoilHUD:update(dt)
    self.animTimer = self.animTimer + dt

    -- Apply preset only when not in free-drag mode
    local currentPosition = self.settings.hudPosition or 1
    if not self.editMode and not self.dragging and self.lastHudPosition ~= currentPosition then
        self:updatePosition()
        self.lastHudPosition = currentPosition
    end

    if self.editMode then
        -- Re-assert cursor unlock every frame (NPCFavor pattern)
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true)
        end
        -- Freeze camera
        if self.savedCamRotX ~= nil and getCamera and setRotation then
            local ok, cam = pcall(getCamera)
            if ok and cam and cam ~= 0 then
                pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
            end
        end
        -- Auto-exit when a GUI/dialog opens
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            self:exitEditMode()
        end
        -- Hover detection (fallback when movement events aren't firing)
        if not self.dragging and not self.resizing then
            if g_inputBinding and g_inputBinding.mousePosXLast then
                self.hoverCorner = self:hitTestCorner(
                    g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast)
            end
        end
    else
        self.hoverCorner = nil
    end
end

-- ── Toggle visibility (J key) ────────────────────────────
function SoilHUD:toggleVisibility()
    self.visible = not self.visible
    local message = self.visible and "Soil HUD shown" or "Soil HUD hidden"
    SoilLogger.info(message)
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(message, 2000)
    end
end

-- ── Draw helper: filled rect ─────────────────────────────
function SoilHUD:drawRect(x, y, w, h, r, g, b, a)
    if not self.fillOverlay then return end
    setOverlayColor(self.fillOverlay, r, g, b, a)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

-- ── Draw (called every frame from main.lua) ──────────────
function SoilHUD:draw()
    if not self.initialized then return end
    if not self.settings.enabled then return end
    if not self.settings.showHUD then return end
    if not self.visible then return end
    if not g_currentMission then return end

    -- Suppress over menus unless editing
    if not self.editMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            return
        end
        if g_currentMission.hud and g_currentMission.hud.ingameMap then
            if g_currentMission.hud.ingameMap.state == IngameMap.STATE_LARGE_MAP then
                return
            end
        end
    end

    self:drawPanel()
    self:drawSprayerRatePanel()
end

-- ── Draw main legend panel ───────────────────────────────
function SoilHUD:drawPanel()
    local s           = self.scale
    local transparency = self.settings.hudTransparency or 3
    local alpha       = SoilConstants.HUD.TRANSPARENCY_LEVELS[transparency]
    local compactMode = self.settings.hudCompactMode or false
    local fontSize    = self.settings.hudFontSize or 2
    local colorTheme  = math.max(1, math.min(4, self.settings.hudColorTheme or 1))

    local pw = SoilHUD.BASE_W * s
    local ph = SoilHUD.BASE_H * s
    local px = self.panelX
    local py = self.panelY

    -- Drop shadow
    local sd = 0.003 * s
    self:drawRect(px + sd, py - sd, pw, ph, 0, 0, 0, 0.30)

    -- Background
    self:drawRect(px, py, pw, ph, SoilHUD.COLOR_BG[1], SoilHUD.COLOR_BG[2], SoilHUD.COLOR_BG[3], alpha)

    -- Title bar accent
    local titleH = 0.024 * s
    self:drawRect(px, py + ph - titleH, pw, titleH,
        SoilHUD.COLOR_TITLE_BG[1], SoilHUD.COLOR_TITLE_BG[2], SoilHUD.COLOR_TITLE_BG[3], SoilHUD.COLOR_TITLE_BG[4])

    -- Subtle permanent border
    local bw = 0.001
    self:drawRect(px,          py,          pw, bw, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])
    self:drawRect(px,          py + ph - bw, pw, bw, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])
    self:drawRect(px,          py,          bw, ph, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])
    self:drawRect(px + pw - bw, py,          bw, ph, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])

    -- Edit mode: pulsing orange border + corner handles
    if self.editMode then
        local pulse = 0.55 + 0.45 * math.sin(self.animTimer * 0.004)
        local ebw   = 0.002
        self:drawRect(px,           py,            pw, ebw, 1.0, 0.55, 0.10, pulse)
        self:drawRect(px,           py + ph - ebw,  pw, ebw, 1.0, 0.55, 0.10, pulse)
        self:drawRect(px,           py,            ebw, ph, 1.0, 0.55, 0.10, pulse)
        self:drawRect(px + pw - ebw, py,            ebw, ph, 1.0, 0.55, 0.10, pulse)

        local hs = SoilHUD.RESIZE_HANDLE_SIZE
        for key, r in pairs(self:getResizeHandleRects()) do
            local isHover = (self.hoverCorner == key)
            self:drawRect(r.x, r.y, r.w, r.h,
                SoilHUD.COLOR_EDIT_HANDLE[1],
                SoilHUD.COLOR_EDIT_HANDLE[2],
                SoilHUD.COLOR_EDIT_HANDLE[3],
                isHover and 1.0 or 0.65)
        end
    end

    -- ── Text content ─────────────────────────────────────
    local theme    = SoilConstants.HUD.COLOR_THEMES[colorTheme]
    local fontMult = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[fontSize]
    local lineH    = (compactMode and SoilConstants.HUD.COMPACT_LINE_HEIGHT or SoilConstants.HUD.NORMAL_LINE_HEIGHT) * s
    local needsShadow = transparency <= 2

    if needsShadow then setTextShadow(true) end
    setTextAlignment(RenderText.ALIGN_LEFT)

    local tx = px + 0.007 * s
    local ty = py + ph - 0.018 * s  -- start just inside the title bar

    -- Title
    setTextBold(true)
    setTextColor(1.0, 1.0, 1.0, 1.0)
    renderText(tx, ty, 0.012 * fontMult * s, "SOIL LEGEND")
    setTextBold(false)
    ty = ty - lineH * 1.6

    -- Key bindings
    setTextColor(theme.r, theme.g, theme.b, 1.0)
    renderText(tx, ty, 0.010 * fontMult * s, "J  =  Toggle HUD")
    ty = ty - lineH
    renderText(tx, ty, 0.010 * fontMult * s, "K  =  Soil Report")
    ty = ty - lineH * 1.1

    -- Divider
    self:drawRect(px + 0.006 * s, ty, pw - 0.012 * s, 0.0005,
        SoilHUD.COLOR_DIVIDER[1], SoilHUD.COLOR_DIVIDER[2], SoilHUD.COLOR_DIVIDER[3], SoilHUD.COLOR_DIVIDER[4])
    ty = ty - lineH * 0.8

    -- Nutrient status legend
    setTextColor(0.28, 0.88, 0.28, 1.0)
    renderText(tx, ty, 0.010 * fontMult * s, "Good  N>50  P>45  K>40")
    ty = ty - lineH

    setTextColor(0.90, 0.88, 0.20, 1.0)
    renderText(tx, ty, 0.010 * fontMult * s, "Fair  N>30  P>25  K>20")
    ty = ty - lineH

    setTextColor(0.90, 0.28, 0.28, 1.0)
    renderText(tx, ty, 0.010 * fontMult * s, "Poor  needs fertilizer")
    ty = ty - lineH * 1.1

    -- Divider
    self:drawRect(px + 0.006 * s, ty, pw - 0.012 * s, 0.0005,
        SoilHUD.COLOR_DIVIDER[1], SoilHUD.COLOR_DIVIDER[2], SoilHUD.COLOR_DIVIDER[3], SoilHUD.COLOR_DIVIDER[4])
    ty = ty - lineH * 0.8

    -- pH reference
    setTextColor(theme.r, theme.g, theme.b, 0.85)
    renderText(tx, ty, 0.010 * fontMult * s, "pH ideal:  6.5 – 7.0")
    ty = ty - lineH * 1.2

    -- Edit / normal hint
    if self.editMode then
        setTextColor(1.0, 0.65, 0.15, 0.95)
        renderText(tx, ty, 0.009 * fontMult * s, "Drag: move")
        ty = ty - lineH * 0.95
        renderText(tx, ty, 0.009 * fontMult * s, "Corner: resize   RMB: done")
    else
        setTextColor(0.45, 0.45, 0.58, 0.80)
        renderText(tx, ty, 0.009 * fontMult * s, "RMB: move / resize")
    end

    -- Restore text state
    if needsShadow then setTextShadow(false) end
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- ── Sprayer rate panel ───────────────────────────────────
function SoilHUD:drawSprayerRatePanel()
    local sprayer = self:getCurrentSprayer()
    if sprayer == nil then return end

    local rm = g_SoilFertilityManager and g_SoilFertilityManager.sprayerRateManager
    if rm == nil then return end

    local s        = self.scale
    local steps    = SoilConstants.SPRAYER_RATE.STEPS
    local currentIdx = rm:getIndex(sprayer.id)
    local fontMult = SoilConstants.HUD.FONT_SIZE_MULTIPLIERS[self.settings.hudFontSize or 2]

    local pw      = SoilHUD.BASE_W * s
    local rateH   = self:py(24) * s
    local labelH  = self:py(14) * s
    local gap     = self:py(6)  * s
    local panelH  = rateH + labelH + self:py(8) * s

    local panelX  = self.panelX
    local panelY  = self.panelY - gap - panelH

    -- Shadow
    local sd = 0.002 * s
    self:drawRect(panelX + sd, panelY - sd, pw, panelH, 0, 0, 0, 0.28)

    -- Background
    self:drawRect(panelX, panelY, pw, panelH, 0.05, 0.05, 0.08, 0.80)

    -- Border
    local bw = 0.001
    self:drawRect(panelX,           panelY,              pw, bw, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])
    self:drawRect(panelX,           panelY + panelH - bw,  pw, bw, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])
    self:drawRect(panelX,           panelY,              bw, panelH, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])
    self:drawRect(panelX + pw - bw,  panelY,              bw, panelH, SoilHUD.COLOR_BORDER[1], SoilHUD.COLOR_BORDER[2], SoilHUD.COLOR_BORDER[3], SoilHUD.COLOR_BORDER[4])

    -- Label row
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextColor(1, 1, 1, 0.90)
    renderText(panelX + pw * 0.5, panelY + rateH + self:py(4) * s,
        0.009 * fontMult * s, "APP. RATE  ( [ / ] )")
    setTextBold(false)

    -- Step colors: blue → cyan → green → yellow → orange → red
    local COLORS = {
        {0.35, 0.55, 0.95},
        {0.25, 0.75, 0.90},
        {0.20, 0.82, 0.35},
        {0.92, 0.82, 0.12},
        {0.95, 0.50, 0.10},
        {0.95, 0.18, 0.18},
    }
    local LABELS = {"50%", "75%", "100%", "125%", "150%", "200%"}

    local pad  = self:px(3) * s
    local btnW = (pw - pad * (#steps + 1)) / #steps
    local btnY = panelY + self:py(2) * s

    for i = 1, #steps do
        local btnX  = panelX + pad + (i - 1) * (btnW + pad)
        local col   = COLORS[i]
        local isCur = (i == currentIdx)
        local alpha = isCur and 0.95 or 0.22

        -- Button background
        self:drawRect(btnX, btnY, btnW, rateH, col[1], col[2], col[3], alpha)

        -- Active indicator: thin top bar
        if isCur then
            self:drawRect(btnX, btnY + rateH - 0.002, btnW, 0.002, col[1], col[2], col[3], 1.0)
        end

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextColor(1, 1, 1, isCur and 1.0 or 0.50)
        if isCur then setTextBold(true) end
        renderText(btnX + btnW * 0.5, btnY + self:py(7) * s, 0.009 * fontMult * s, LABELS[i])
        if isCur then setTextBold(false) end
    end

    -- Burn warning
    local curRate = steps[currentIdx]
    local warnY   = panelY - self:py(14) * s
    setTextAlignment(RenderText.ALIGN_CENTER)
    if curRate >= SoilConstants.SPRAYER_RATE.BURN_GUARANTEED_THRESHOLD then
        setTextColor(1.0, 0.15, 0.15, 1.0)
        renderText(panelX + pw * 0.5, warnY, 0.010 * fontMult * s, "BURN RISK: GUARANTEED")
    elseif curRate > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
        setTextColor(0.95, 0.65, 0.10, 1.0)
        renderText(panelX + pw * 0.5, warnY, 0.010 * fontMult * s, "BURN RISK: POSSIBLE")
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
    if vehicle and vehicle.spec_sprayer then
        return vehicle
    end
    return nil
end

-- ── Pixel helpers (resolution-independent) ───────────────
function SoilHUD:px(pixels) return pixels / 1920 end
function SoilHUD:py(pixels) return pixels / 1080 end
