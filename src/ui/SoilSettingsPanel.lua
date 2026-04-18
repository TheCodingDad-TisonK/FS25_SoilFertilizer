-- =========================================================
-- FS25 Soil & Fertilizer — Settings Panel
-- =========================================================
-- Fully custom-drawn settings panel. No XML — pure overlay.
-- Open/close: SHIFT+O
-- Landing page → category tile → settings list.
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilSettingsPanel
SoilSettingsPanel = {}
local SoilSettingsPanel_mt = Class(SoilSettingsPanel)

local SF_MOD_NAME = g_currentModName

-- ── i18n helper ───────────────────────────────────────────
local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[SF_MOD_NAME]
    local i18n   = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

-- ── Panel geometry (normalized, Y=0 at bottom) ────────────
local PW    = 0.60
local PH    = 0.74
local PX    = (1 - PW) / 2
local PY    = (1 - PH) / 2

local TB_H  = 0.052          -- title bar height
local IB_H  = 0.046          -- info/bottom bar height
local PAD   = 0.018          -- inner horizontal padding

local CX    = PX + PAD
local CW    = PW - PAD * 2
local CY_BOT = PY + IB_H + 0.010
local CY_TOP = PY + PH - TB_H - 0.008
local CH    = CY_TOP - CY_BOT

-- Landing: 3 category cards
local CARD_GAP  = 0.012
local CARD_W    = (CW - CARD_GAP * 2) / 3
local CARD_H    = 0.32
local CARD_Y    = CY_BOT + (CH - CARD_H) / 2

-- Category page rows
local ROW_H     = 0.036
local SEC_H     = 0.026
local TOGGLE_W  = 0.048   -- single pill width
local TOGGLE_H  = 0.026
local TOGGLE_GAP = 0.004  -- gap between ON / OFF pills
local MULTI_W   = 0.175   -- multi-select total width

-- Text sizes
local TS_TITLE  = 0.018
local TS_BODY   = 0.015
local TS_SMALL  = 0.013
local TS_TINY   = 0.011

-- ── Colors ────────────────────────────────────────────────
local C = {
    bg          = {0.05, 0.06, 0.09, 0.97},
    title_bg    = {0.07, 0.09, 0.13, 1.0},
    info_bg     = {0.04, 0.05, 0.08, 1.0},
    border      = {0.30, 0.72, 0.40, 0.45},
    shadow      = {0.00, 0.00, 0.00, 0.45},
    divider     = {0.20, 0.22, 0.28, 0.55},
    row_alt     = {1.00, 1.00, 1.00, 0.025},
    row_hover   = {0.28, 0.70, 0.38, 0.10},
    green       = {0.32, 0.88, 0.44, 1.0},
    green_dim   = {0.20, 0.55, 0.28, 1.0},
    white       = {1.00, 1.00, 1.00, 1.0},
    dim         = {0.55, 0.55, 0.60, 1.0},
    hint        = {0.38, 0.38, 0.46, 1.0},
    on_bg       = {0.22, 0.75, 0.33, 1.0},
    off_bg      = {0.15, 0.16, 0.20, 1.0},
    on_text     = {0.00, 0.00, 0.00, 1.0},
    off_text    = {0.45, 0.46, 0.52, 1.0},
    lock_bg     = {0.22, 0.14, 0.05, 0.70},
    lock_text   = {0.88, 0.60, 0.18, 1.0},
    card_hover  = {1.00, 1.00, 1.00, 0.04},
    sim_accent  = {0.30, 0.85, 0.42, 1.0},
    disp_accent = {0.35, 0.60, 0.95, 1.0},
    map_accent  = {0.90, 0.62, 0.18, 1.0},
    close_hover = {0.88, 0.25, 0.25, 0.80},
    back_hover  = {0.28, 0.70, 0.38, 0.20},
    info_admin  = {0.28, 0.80, 0.38, 1.0},
    info_no_adm = {0.88, 0.60, 0.18, 1.0},
    info_mode   = {0.55, 0.55, 0.62, 1.0},
}

-- ── Category definitions ───────────────────────────────────
local CATEGORIES = {
    {
        id      = "simulation",
        label   = "Simulation",
        desc    = "Farm mechanics, difficulty\nand nutrient cycles",
        accent  = C.sim_accent,
        sections = {
            {
                header = "Core Systems",
                items  = { "fertilitySystem", "nutrientCycles", "fertilizerCosts",
                           "cropRotation", "autoRateControl" }
            },
            {
                header = "Difficulty",
                items  = { "difficulty" }
            },
            {
                header = "Environment",
                items  = { "seasonalEffects", "rainEffects", "plowingBonus" }
            },
            {
                header = "Crop Stress",
                items  = { "weedPressure", "pestPressure", "diseasePressure" }
            },
        }
    },
    {
        id      = "display",
        label   = "Display & HUD",
        desc    = "HUD appearance, color theme\nposition and font size",
        accent  = C.disp_accent,
        sections = {
            {
                header = "Visibility",
                items  = { "showHUD", "useImperialUnits" }
            },
            {
                header = "HUD Style",
                items  = { "hudColorTheme", "hudFontSize", "hudTransparency" }
            },
            {
                header = "Position",
                items  = { "hudPosition" }
            },
        }
    },
    {
        id      = "map",
        label   = "Map Overlay",
        desc    = "Active overlay layer\nshown in the PDA map",
        accent  = C.map_accent,
        sections = {
            {
                header = "Layer",
                items  = { "activeMapLayer" }
            },
        }
    },
}

-- ── Multi-option labels ────────────────────────────────────
local MULTI_OPTS = {
    difficulty        = {"Simple", "Realistic", "Hardcore"},
    hudPosition       = {"Top Right", "Top Left", "Bot Right", "Bot Left", "Ctr Right", "Custom"},
    hudColorTheme     = {"Green", "Blue", "Amber", "Mono"},
    hudFontSize       = {"Small", "Medium", "Large"},
    hudTransparency   = {"Clear", "Light", "Medium", "Dark", "Solid"},
    activeMapLayer    = {"Off", "Nitrogen", "Phosphorus", "Potassium", "pH",
                         "Org Matter", "Urgency", "Weed", "Pest", "Disease"},
}

-- Short descriptions for each setting
local SETTING_DESCS = {
    fertilitySystem  = "Full soil fertility modeling",
    nutrientCycles   = "Track N/P/K depletion and recovery",
    fertilizerCosts  = "Real in-game cost for fertilizers",
    cropRotation     = "Rotation benefits and penalties",
    autoRateControl  = "Smart sprayer application rates",
    difficulty       = "Nutrient drain intensity level",
    seasonalEffects  = "Season-driven soil changes",
    rainEffects      = "Rain causes nutrient leaching",
    plowingBonus     = "Plow bonus for soil recovery",
    weedPressure     = "Track and penalize weed spread",
    pestPressure     = "Track insect pest infestation",
    diseasePressure  = "Track fungal crop diseases",
    showHUD          = "Show the soil HUD overlay",
    useImperialUnits = "Use imperial units (US tons/acre)",
    hudColorTheme    = "Color palette for HUD elements",
    hudFontSize      = "HUD text size",
    hudTransparency  = "HUD background transparency",
    hudPosition      = "HUD preset anchor position",
    activeMapLayer   = "Nutrient layer shown in PDA map",
}

-- Page states
local PAGE_LANDING  = "landing"
local PAGE_CATEGORY = "category"

-- ── Constructor ───────────────────────────────────────────
function SoilSettingsPanel.new(settings)
    local self = setmetatable({}, SoilSettingsPanel_mt)
    self.settings     = settings
    self.fillOverlay  = nil
    self.isVisible    = false
    self.page         = PAGE_LANDING
    self.activeCatIdx = nil
    self.mouseX       = 0
    self.mouseY       = 0
    self.initialized  = false
    self._clickRects  = {}  -- populated each draw frame
    return self
end

function SoilSettingsPanel:initialize()
    if self.initialized then return end
    if createImageOverlay then
        self.fillOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end
    self.initialized = true
end

function SoilSettingsPanel:delete()
    if self.fillOverlay then
        delete(self.fillOverlay)
        self.fillOverlay = nil
    end
    self.initialized = false
end

-- ── Visibility ────────────────────────────────────────────
function SoilSettingsPanel:open()
    if not self.initialized then self:initialize() end
    self.isVisible = true
    self.page      = PAGE_LANDING
    self.activeCatIdx = nil
    -- Save camera rotation so update() can freeze it every frame (SoilHUD edit-mode pattern)
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if getCamera and getRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            local ok2, rx, ry, rz = pcall(getRotation, cam)
            if ok2 then
                self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = rx, ry, rz
            end
        end
    end
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
    SoilLogger.info("SoilSettingsPanel: opened")
end

function SoilSettingsPanel:close()
    self.isVisible = false
    self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = nil, nil, nil
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end
    SoilLogger.info("SoilSettingsPanel: closed")
end

-- Called every frame by SoilFertilityManager:update(). Keeps cursor shown and camera frozen.
function SoilSettingsPanel:update()
    if not self.isVisible then return end
    -- Keep cursor shown every frame (game may try to hide it)
    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true, true)
    end
    -- Force camera back to saved rotation every frame (prevents mouse-look while panel is open)
    if self.savedCamRotX ~= nil and getCamera and setRotation then
        local ok, cam = pcall(getCamera)
        if ok and cam and cam ~= 0 then
            pcall(setRotation, cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
        end
    end
    -- Auto-close if a GUI (dialog/menu) opens on top
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        self:close()
    end
end

function SoilSettingsPanel:toggle()
    if self.isVisible then self:close() else self:open() end
end

function SoilSettingsPanel:isOpen()
    return self.isVisible
end

-- ── Admin / settings helpers ──────────────────────────────
function SoilSettingsPanel:isAdmin()
    if not g_currentMission then return false end
    if not (g_currentMission.missionDynamicInfo and
            g_currentMission.missionDynamicInfo.isMultiplayer) then
        return true
    end
    if g_dedicatedServer then return true end
    local user = g_currentMission.userManager and
                 g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    return user and user:getIsMasterUser() or false
end

function SoilSettingsPanel:requestChange(id, value)
    local def = SettingsSchema.byId[id]
    if not def then return end
    if def.localOnly then
        self.settings[id] = value
        self.settings:save()
        -- sync HUD if needed
        if g_SoilFertilityManager and g_SoilFertilityManager.soilHUD then
            g_SoilFertilityManager.soilHUD:updatePosition()
        end
        return
    end
    if not self:isAdmin() then
        if g_currentMission and g_currentMission.hud and
           g_currentMission.hud.showBlinkingWarning then
            g_currentMission.hud:showBlinkingWarning(
                "Only server admins can change this setting", 4000)
        end
        return
    end
    if SoilNetworkEvents_RequestSettingChange then
        SoilNetworkEvents_RequestSettingChange(id, value)
    else
        self.settings[id] = value
        self.settings:save()
    end
end

function SoilSettingsPanel:getValue(id)
    return self.settings[id]
end

-- ── Drawing helper ────────────────────────────────────────
function SoilSettingsPanel:drawRect(x, y, w, h, col, alpha)
    if not self.fillOverlay then return end
    local a = alpha or col[4] or 1.0
    setOverlayColor(self.fillOverlay, col[1], col[2], col[3], a)
    renderOverlay(self.fillOverlay, x, y, w, h)
end

function SoilSettingsPanel:drawText(x, y, size, text, col, align, bold)
    setTextColor(col[1], col[2], col[3], col[4] or 1.0)
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x, y, size, text)
end

function SoilSettingsPanel:registerClick(id, x, y, w, h, data)
    table.insert(self._clickRects, { id = id, x = x, y = y, w = w, h = h, data = data })
end

function SoilSettingsPanel:hitTest(rx, ry, rw, rh, mx, my)
    return mx >= rx and mx <= rx + rw and my >= ry and my <= ry + rh
end

-- ── Main draw entry ───────────────────────────────────────
function SoilSettingsPanel:draw()
    if not self.isVisible then return end
    if not self.initialized then return end
    if not g_currentMission then return end

    self._clickRects = {}

    -- Dark screen fade
    self:drawRect(0, 0, 1, 1, C.shadow, 0.40)

    -- Panel shadow
    self:drawRect(PX + 0.004, PY - 0.004, PW, PH, C.shadow, 0.55)

    -- Panel background
    self:drawRect(PX, PY, PW, PH, C.bg)

    -- Border
    local bw = 0.0015
    self:drawRect(PX,          PY,          PW, bw, C.border)
    self:drawRect(PX,          PY + PH - bw, PW, bw, C.border)
    self:drawRect(PX,          PY,          bw, PH, C.border)
    self:drawRect(PX + PW - bw, PY,         bw, PH, C.border)

    -- Title bar
    self:drawTitleBar()

    -- Info bar (bottom)
    self:drawInfoBar()

    -- Page content
    if self.page == PAGE_LANDING then
        self:drawLandingPage()
    elseif self.page == PAGE_CATEGORY then
        self:drawCategoryPage()
    end
end

-- ── Title bar ─────────────────────────────────────────────
function SoilSettingsPanel:drawTitleBar()
    local ty = PY + PH - TB_H
    self:drawRect(PX, ty, PW, TB_H, C.title_bg)

    -- Left accent line
    local accColor = (self.activeCatIdx and CATEGORIES[self.activeCatIdx].accent) or C.green
    self:drawRect(PX, ty, 0.004, TB_H, accColor)

    -- Title text
    local title = "SOIL & FERTILIZER SETTINGS"
    if self.activeCatIdx then
        title = title .. "  /  " .. string.upper(CATEGORIES[self.activeCatIdx].label)
    end
    self:drawText(PX + 0.018, ty + TB_H * 0.32, TS_TITLE, title, C.white, RenderText.ALIGN_LEFT, true)

    -- Version tag
    self:drawText(PX + PW - 0.020, ty + TB_H * 0.32, TS_TINY, "v1.9.2", C.hint, RenderText.ALIGN_RIGHT, false)

    -- [X] close button — right side
    local cbW = 0.038
    local cbH = TB_H * 0.60
    local cbX = PX + PW - cbW - 0.010
    local cbY = ty + (TB_H - cbH) / 2
    local closeHover = self:hitTest(cbX, cbY, cbW, cbH, self.mouseX, self.mouseY)
    self:drawRect(cbX, cbY, cbW, cbH, closeHover and C.close_hover or C.off_bg)
    self:drawText(cbX + cbW * 0.5, cbY + cbH * 0.18, TS_SMALL, "X", C.white, RenderText.ALIGN_CENTER, true)
    self:registerClick("close", cbX, cbY, cbW, cbH)
end

-- ── Info bar ──────────────────────────────────────────────
function SoilSettingsPanel:drawInfoBar()
    local iy = PY
    self:drawRect(PX, iy, PW, IB_H, C.info_bg)

    -- Thin top border
    self:drawRect(PX, iy + IB_H - 0.001, PW, 0.001, C.divider)

    local isAdmin = self:isAdmin()
    local isMP    = g_currentMission and g_currentMission.missionDynamicInfo and
                    g_currentMission.missionDynamicInfo.isMultiplayer

    local adminText  = isAdmin and "Admin: YES" or "Admin: NO"
    local adminColor = isAdmin and C.info_admin or C.info_no_adm
    local modeText   = isMP and "Multiplayer" or "Single Player"

    local textY = iy + IB_H * 0.25
    self:drawText(PX + PAD, textY, TS_SMALL, adminText, adminColor, RenderText.ALIGN_LEFT, true)
    self:drawText(PX + PAD + 0.10, textY, TS_SMALL, "·  " .. modeText, C.info_mode, RenderText.ALIGN_LEFT, false)

    if self.page == PAGE_CATEGORY then
        -- Back button
        local bbW = 0.085
        local bbH = IB_H * 0.62
        local bbX = PX + PW - bbW * 2 - 0.030
        local bbY = iy + (IB_H - bbH) / 2
        local backHover = self:hitTest(bbX, bbY, bbW, bbH, self.mouseX, self.mouseY)
        self:drawRect(bbX, bbY, bbW, bbH, backHover and C.back_hover or C.off_bg)
        self:drawRect(bbX, bbY, 0.002, bbH, C.green_dim)
        self:drawText(bbX + bbW * 0.5, bbY + bbH * 0.18, TS_SMALL, "< Back", C.white, RenderText.ALIGN_CENTER, false)
        self:registerClick("back", bbX, bbY, bbW, bbH)

        -- Reset button
        local rbW = 0.095
        local rbX = bbX + bbW + 0.010
        local rbY = bbY
        local resetHover = self:hitTest(rbX, rbY, rbW, bbH, self.mouseX, self.mouseY)
        self:drawRect(rbX, rbY, rbW, bbH, resetHover and {0.50, 0.20, 0.10, 0.70} or C.off_bg)
        self:drawText(rbX + rbW * 0.5, rbY + bbH * 0.18, TS_SMALL, "Reset Cat.", C.dim, RenderText.ALIGN_CENTER, false)
        self:registerClick("reset_cat", rbX, rbY, rbW, bbH)
    else
        -- Close hint on landing
        self:drawText(PX + PW - PAD, textY, TS_SMALL, "SHIFT+O to close", C.hint, RenderText.ALIGN_RIGHT, false)
    end
end

-- ── Landing page ──────────────────────────────────────────
function SoilSettingsPanel:drawLandingPage()
    -- Header above cards
    local headerY = CY_BOT + CH - 0.042
    self:drawText(PX + PW * 0.5, headerY, TS_SMALL,
        "Select a category to configure settings", C.hint, RenderText.ALIGN_CENTER, false)

    for i, cat in ipairs(CATEGORIES) do
        local cardX = CX + (i - 1) * (CARD_W + CARD_GAP)
        self:drawCategoryCard(cardX, CARD_Y, CARD_W, CARD_H, cat, i)
    end
end

function SoilSettingsPanel:drawCategoryCard(x, y, w, h, cat, idx)
    local hovered = self:hitTest(x, y, w, h, self.mouseX, self.mouseY)

    -- Card background
    self:drawRect(x, y, w, h, C.bg)
    if hovered then
        self:drawRect(x, y, w, h, C.card_hover)
    end

    -- Card border
    local bw = 0.0012
    self:drawRect(x,         y,         w, bw, cat.accent, 0.30)
    self:drawRect(x,         y + h - bw, w, bw, cat.accent, 0.30)
    self:drawRect(x,         y,         bw, h,  cat.accent, 0.30)
    self:drawRect(x + w - bw, y,         bw, h,  cat.accent, 0.30)

    -- Top color accent bar
    self:drawRect(x, y + h - 0.018, w, 0.018, cat.accent, hovered and 0.85 or 0.65)

    -- Category title
    local titleY = y + h - 0.018 - 0.044
    self:drawText(x + w * 0.5, titleY, TS_BODY,
        string.upper(cat.label), C.white, RenderText.ALIGN_CENTER, true)

    -- Divider under title
    self:drawRect(x + 0.010, titleY - 0.006, w - 0.020, 0.001, C.divider)

    -- Count settings
    local count = 0
    for _, sec in ipairs(cat.sections) do count = count + #sec.items end

    -- Description (2 lines)
    local descY = titleY - 0.038
    local lines = {}
    for line in (cat.desc .. "\n"):gmatch("([^\n]*)\n") do
        table.insert(lines, line)
    end
    for j, line in ipairs(lines) do
        self:drawText(x + w * 0.5, descY - (j - 1) * 0.022, TS_SMALL,
            line, C.dim, RenderText.ALIGN_CENTER, false)
    end

    -- Settings count badge
    local badgeY = y + 0.040
    self:drawText(x + w * 0.5, badgeY, TS_SMALL,
        count .. " settings", cat.accent, RenderText.ALIGN_CENTER, false)

    -- "Configure →" button at bottom
    local btnW = w - 0.024
    local btnH = 0.028
    local btnX = x + 0.012
    local btnY = y + 0.008
    self:drawRect(btnX, btnY, btnW, btnH,
        hovered and cat.accent or C.off_bg,
        hovered and 0.20 or 1.0)
    self:drawText(btnX + btnW * 0.5, btnY + btnH * 0.18, TS_SMALL,
        hovered and "Open  →" or "Configure  →",
        hovered and cat.accent or C.hint,
        RenderText.ALIGN_CENTER, false)

    self:registerClick("cat_" .. idx, x, y, w, h)
end

-- ── Category page ─────────────────────────────────────────
function SoilSettingsPanel:drawCategoryPage()
    if not self.activeCatIdx then return end
    local cat = CATEGORIES[self.activeCatIdx]
    if not cat then return end

    local curY = CY_TOP
    local isAdmin = self:isAdmin()
    local rowIdx  = 0

    for _, sec in ipairs(cat.sections) do
        -- Section header
        curY = curY - SEC_H
        if curY < CY_BOT then break end

        self:drawRect(CX, curY, CW, SEC_H, C.title_bg, 0.60)
        self:drawRect(CX, curY, 0.003, SEC_H, cat.accent)
        self:drawText(CX + 0.012, curY + SEC_H * 0.25, TS_SMALL,
            string.upper(sec.header), cat.accent, RenderText.ALIGN_LEFT, true)

        for _, settingId in ipairs(sec.items) do
            curY = curY - ROW_H
            if curY < CY_BOT then break end

            rowIdx = rowIdx + 1
            self:drawSettingRow(CX, curY, CW, settingId, rowIdx, isAdmin)
        end

        -- Small gap between sections
        curY = curY - 0.005
    end

    -- Thin top divider under title bar
    self:drawRect(CX, CY_TOP, CW, 0.001, C.divider)
end

function SoilSettingsPanel:drawSettingRow(x, y, w, settingId, rowIdx, isAdmin)
    local def = SettingsSchema.byId[settingId]
    if not def then return end

    -- Alternating row background
    if rowIdx % 2 == 0 then
        self:drawRect(x, y, w, ROW_H, C.row_alt)
    end

    -- Hover highlight (only on the left/label portion)
    if self:hitTest(x, y, w, ROW_H, self.mouseX, self.mouseY) then
        self:drawRect(x, y, w, ROW_H, C.row_hover)
    end

    local locked = not def.localOnly and not isAdmin
    local labelColor = locked and C.lock_text or C.white
    local descColor  = locked and {C.lock_text[1]*0.7, C.lock_text[2]*0.7, C.lock_text[3]*0.7, 1} or C.dim

    -- Lock indicator
    if locked then
        self:drawRect(x, y, 0.003, ROW_H, {0.88, 0.60, 0.18, 0.45})
    end

    -- Setting label
    local labelX = x + (locked and 0.010 or 0.008)
    local labelY = y + ROW_H * 0.52
    local labelText = tr(def.uiId .. "_short", settingId)
    self:drawText(labelX, labelY, TS_BODY, labelText, labelColor, RenderText.ALIGN_LEFT, not locked)

    -- Description
    local desc = SETTING_DESCS[settingId] or ""
    self:drawText(labelX, y + ROW_H * 0.15, TS_TINY, desc, descColor, RenderText.ALIGN_LEFT, false)

    -- Control (toggle or multi-select) on the right
    local ctrlX = x + w - 0.012
    local ctrlY = y + (ROW_H - TOGGLE_H) / 2

    if def.type == "boolean" then
        self:drawToggleControl(ctrlX, ctrlY, settingId, locked)
    elseif def.type == "number" then
        self:drawMultiControl(ctrlX, ctrlY, settingId, locked)
    end

    -- Row bottom divider
    self:drawRect(x, y, w, 0.0005, C.divider, 0.35)
end

-- ── Toggle control [ON] [OFF] ─────────────────────────────
function SoilSettingsPanel:drawToggleControl(rightX, y, settingId, locked)
    local val = self:getValue(settingId)
    local isOn = val == true

    -- Pill: [OFF] on left, [ON] on right
    local offX = rightX - TOGGLE_W * 2 - TOGGLE_GAP
    local onX  = rightX - TOGGLE_W

    -- OFF pill
    local offHover = not locked and self:hitTest(offX, y, TOGGLE_W, TOGGLE_H, self.mouseX, self.mouseY)
    local offBg    = (not isOn) and C.dim or C.off_bg
    self:drawRect(offX, y, TOGGLE_W, TOGGLE_H, offBg, (not isOn) and 0.90 or 0.60)
    self:drawText(offX + TOGGLE_W * 0.5, y + TOGGLE_H * 0.20, TS_TINY,
        "OFF", (not isOn) and C.white or C.off_text, RenderText.ALIGN_CENTER, not isOn)

    -- ON pill
    local onHover  = not locked and self:hitTest(onX, y, TOGGLE_W, TOGGLE_H, self.mouseX, self.mouseY)
    local onBg     = isOn and C.on_bg or C.off_bg
    self:drawRect(onX, y, TOGGLE_W, TOGGLE_H, onBg, isOn and 1.0 or 0.60)
    self:drawText(onX + TOGGLE_W * 0.5, y + TOGGLE_H * 0.20, TS_TINY,
        "ON", isOn and C.on_text or C.off_text, RenderText.ALIGN_CENTER, isOn)

    if not locked then
        self:registerClick("toggle_off_" .. settingId, offX, y, TOGGLE_W, TOGGLE_H,
            { id = settingId, value = false })
        self:registerClick("toggle_on_" .. settingId, onX, y, TOGGLE_W, TOGGLE_H,
            { id = settingId, value = true })
    end
end

-- ── Multi-select control [◄ Option ►] ────────────────────
function SoilSettingsPanel:drawMultiControl(rightX, y, settingId, locked)
    local opts    = MULTI_OPTS[settingId]
    if not opts then return end
    local val     = self:getValue(settingId) or 1
    local current = opts[val] or opts[1] or "?"

    local arrowW = 0.022
    local labelW = MULTI_W - arrowW * 2
    local totalX = rightX - MULTI_W
    local leftX  = totalX
    local midX   = totalX + arrowW
    local rightBX = totalX + arrowW + labelW

    -- Left arrow [◄]
    local lHover = not locked and self:hitTest(leftX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(leftX, y, arrowW, TOGGLE_H, lHover and C.back_hover or C.off_bg)
    self:drawText(leftX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        "<", lHover and C.green or C.dim, RenderText.ALIGN_CENTER, true)

    -- Middle label
    self:drawRect(midX, y, labelW, TOGGLE_H, {0.10, 0.11, 0.15, 0.90})
    self:drawText(midX + labelW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        current, C.white, RenderText.ALIGN_CENTER, false)

    -- Right arrow [►]
    local rHover = not locked and self:hitTest(rightBX, y, arrowW, TOGGLE_H, self.mouseX, self.mouseY)
    self:drawRect(rightBX, y, arrowW, TOGGLE_H, rHover and C.back_hover or C.off_bg)
    self:drawText(rightBX + arrowW * 0.5, y + TOGGLE_H * 0.18, TS_TINY,
        ">", rHover and C.green or C.dim, RenderText.ALIGN_CENTER, true)

    if not locked then
        self:registerClick("multi_prev_" .. settingId, leftX, y, arrowW, TOGGLE_H,
            { id = settingId, dir = -1, opts = opts })
        self:registerClick("multi_next_" .. settingId, rightBX, y, arrowW, TOGGLE_H,
            { id = settingId, dir = 1, opts = opts })
    end
end

-- ── Mouse event ───────────────────────────────────────────
function SoilSettingsPanel:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self.isVisible then return false end

    -- Always update hover state
    self.mouseX = posX
    self.mouseY = posY

    if not isDown then return true end  -- consume all events when open
    if button ~= Input.MOUSE_BUTTON_LEFT then return true end

    -- Check registered click rects
    for _, r in ipairs(self._clickRects) do
        if self:hitTest(r.x, r.y, r.w, r.h, posX, posY) then
            self:handleClick(r.id, r.data)
            return true
        end
    end

    -- Click outside panel = close
    if not self:hitTest(PX, PY, PW, PH, posX, posY) then
        self:close()
        return true
    end

    return true
end

function SoilSettingsPanel:handleClick(id, data)
    if id == "close" then
        self:close()

    elseif id == "back" then
        self.page = PAGE_LANDING
        self.activeCatIdx = nil

    elseif id == "reset_cat" then
        self:resetCurrentCategory()

    elseif id:sub(1, 4) == "cat_" then
        local idx = tonumber(id:sub(5))
        if idx and CATEGORIES[idx] then
            self.activeCatIdx = idx
            self.page = PAGE_CATEGORY
        end

    elseif id:sub(1, 11) == "toggle_off_" then
        if data then self:requestChange(data.id, false) end

    elseif id:sub(1, 10) == "toggle_on_" then
        if data then self:requestChange(data.id, true) end

    elseif id:sub(1, 10) == "multi_prev" then
        if data then
            local cur = self:getValue(data.id) or 1
            local nxt = cur - 1
            if nxt < 1 then nxt = #data.opts end
            self:requestChange(data.id, nxt)
        end

    elseif id:sub(1, 10) == "multi_next" then
        if data then
            local cur = self:getValue(data.id) or 1
            local nxt = cur + 1
            if nxt > #data.opts then nxt = 1 end
            self:requestChange(data.id, nxt)
        end
    end
end

function SoilSettingsPanel:resetCurrentCategory()
    if not self.activeCatIdx then return end
    local cat = CATEGORIES[self.activeCatIdx]
    if not cat then return end

    for _, sec in ipairs(cat.sections) do
        for _, settingId in ipairs(sec.items) do
            local def = SettingsSchema.byId[settingId]
            if def and def.default ~= nil then
                self:requestChange(settingId, def.default)
            end
        end
    end
    SoilLogger.info("SoilSettingsPanel: reset category '%s' to defaults", cat.id)
end
