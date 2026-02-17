-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FIXED FOR MULTIPLAYER)
-- =========================================================
-- Settings UI - auto-generated from SettingsSchema
-- =========================================================
-- Author: TisonK (Multiplayer fix applied)
-- =========================================================
---@class SoilSettingsUI

SoilSettingsUI = {}
local SoilSettingsUI_mt = Class(SoilSettingsUI)

function SoilSettingsUI.new(settings)
    local self = setmetatable({}, SoilSettingsUI_mt)
    self.settings = settings
    self.injected = false
    self.uiElements = {}
    self._resetButton = nil
    self.compatibilityMode = false
    return self
end

-- Check if current player is admin
function SoilSettingsUI:isPlayerAdmin()
    if not g_currentMission then return false end

    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true
    end

    if g_dedicatedServer then
        return true
    end

    local currentUser = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    if currentUser then
        return currentUser:getIsMasterUser()
    end

    return false
end

-- Show admin-only warning
function SoilSettingsUI:showAdminOnlyWarning()
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(
            "Only server admins can change Soil & Fertilizer settings",
            5000
        )
    end

    if g_gui and g_gui.showInfoDialog then
        g_gui:showInfoDialog({
            text = "Only the server admin can change Soil & Fertilizer Mod settings.\n\nIf you are the server owner, make sure you are logged in as admin.",
            callback = nil
        })
    end
end

-- Request setting change via network (or apply directly if server/singleplayer)
function SoilSettingsUI:requestSettingChange(settingName, value)
    if not self:isPlayerAdmin() then
        self:showAdminOnlyWarning()
        self:refreshUI()
        return
    end

    if SoilNetworkEvents_RequestSettingChange then
        SoilNetworkEvents_RequestSettingChange(settingName, value)
    else
        self.settings[settingName] = value
        self.settings:save()
        print(string.format("[SoilFertilizer] Setting '%s' changed to %s", settingName, tostring(value)))
    end
end

-- PF-protected toggle helper
function SoilSettingsUI:togglePFProtected(settingKey, val)
    local pfActive = g_SoilFertilityManager and g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem.PFActive

    if pfActive then
        if g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(
                "Viewer Mode: Precision Farming is managing soil data - this setting is locked",
                5000
            )
        end
        self:refreshUI()
        return
    end

    self:requestSettingChange(settingKey, val)
end

function SoilSettingsUI:inject()
    if self.injected then return true end
    if not g_gui or not g_gui.screenControllers then
        SoilLogger.warning("[SoilFertilizer] GUI unavailable")
        return false
    end

    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if not inGameMenu or not inGameMenu.pageSettings or not inGameMenu.pageSettings.generalSettingsLayout then
        SoilLogger.warning("[SoilFertilizer] Settings page not ready")
        return false
    end

    local layout = inGameMenu.pageSettings.generalSettingsLayout

    -- Non-admin MP clients cannot change settings and must not inject UI elements.
    -- Template cloning on dedicated server clients can corrupt other settings pages
    -- (Graphics, Server Settings, Better Contracts, etc.) by reparenting shared elements.
    local isMP = g_currentMission.missionDynamicInfo.isMultiplayer
    if isMP and not self:isPlayerAdmin() then
        self.injected = true
        SoilLogger.info("Non-admin MP client: UI injection skipped (admin-only settings)")
        return true
    end

    -- Clear any existing elements to prevent duplicates on retry
    if #self.uiElements > 0 then
        SoilLogger.info("Clearing %d existing UI elements before retry", #self.uiElements)
        self.uiElements = {}
        -- Also reset template cache on retry to handle mod load order changes
        UIHelper.resetTemplateCache()
    end

    -- Section header
    local section = UIHelper.createSection(layout, "sf_section")
    table.insert(self.uiElements, section)

    local isAdmin = self:isPlayerAdmin()
    local pfActive = g_SoilFertilityManager and g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem.PFActive

    -- Add Viewer Mode banner if Precision Farming is active
    if pfActive then
        local pfInfoText = UIHelper.createDescription(layout, "sf_pf_viewer_mode_info")
        if pfInfoText and pfInfoText.setText then
            pfInfoText:setText("VIEWER MODE: Precision Farming is managing soil data - settings locked")
            if pfInfoText.textColor then
                pfInfoText.textColor = {0.4, 0.8, 1.0, 1.0}  -- Blue color to match info theme
            end
        end
        table.insert(self.uiElements, pfInfoText)
    end

    -- Auto-generate boolean toggle options from schema
    for _, def in ipairs(SettingsSchema.getBooleanSettings()) do
        local callback
        if def.pfProtected then
            callback = function(val)
                self:togglePFProtected(def.id, val)
            end
        else
            callback = function(val)
                self:requestSettingChange(def.id, val)
            end
        end

        local disabled = def.pfProtected and pfActive or false

        local success, element = pcall(UIHelper.createBinaryOption, layout, def.uiId, def.uiId, self.settings[def.id], callback)
        if success and element then
            local shouldDisable = (not isAdmin) or disabled

            if shouldDisable and element.setIsEnabled then
                element:setIsEnabled(false)

                local tooltip = "Admin only"
                if disabled then
                    tooltip = "Viewer Mode - Precision Farming manages this"
                end

                if element.setToolTipText then
                    element:setToolTipText(tooltip)
                end
            end

            self.uiElements[def.uiId] = element
            table.insert(self.uiElements, element)
        end
    end

    -- Difficulty dropdown (the only non-boolean setting)
    local diffDef = SettingsSchema.byId["difficulty"]
    if diffDef then
        local diffOptions = {
            g_i18n:getText("sf_diff_1") or "Simple",
            g_i18n:getText("sf_diff_2") or "Realistic",
            g_i18n:getText("sf_diff_3") or "Hardcore"
        }

        local success, diffElement = pcall(UIHelper.createMultiOption, layout, diffDef.uiId, "sf_difficulty", diffOptions, self.settings.difficulty, function(val)
            if pfActive then
                if g_currentMission and g_currentMission.hud then
                    g_currentMission.hud:showBlinkingWarning(
                        "Viewer Mode: Precision Farming is managing soil data - difficulty locked",
                        5000
                    )
                end
                self:refreshUI()
                return
            end

            self:requestSettingChange("difficulty", val)
        end)

        if success and diffElement then
            if (not isAdmin or pfActive) and diffElement.setIsEnabled then
                diffElement:setIsEnabled(false)
                local tooltip = pfActive and "Viewer Mode - Precision Farming manages this" or "Admin only"
                if diffElement.setToolTipText then
                    diffElement:setToolTipText(tooltip)
                end
            end

            self.uiElements[diffDef.uiId] = diffElement
            table.insert(self.uiElements, diffElement)
        end
    end

    -- HUD Position dropdown
    local hudPosDef = SettingsSchema.byId["hudPosition"]
    if hudPosDef then
        local hudPosOptions = {
            g_i18n:getText("sf_hud_pos_1") or "Top Right",
            g_i18n:getText("sf_hud_pos_2") or "Top Left",
            g_i18n:getText("sf_hud_pos_3") or "Bottom Right",
            g_i18n:getText("sf_hud_pos_4") or "Bottom Left",
            g_i18n:getText("sf_hud_pos_5") or "Center Right"
        }

        local success, hudPosElement = pcall(UIHelper.createMultiOption, layout, hudPosDef.uiId, "sf_hud_position", hudPosOptions, self.settings.hudPosition or 1, function(val)
            self:requestSettingChange("hudPosition", val)
        end)

        if success and hudPosElement then
            if not isAdmin and hudPosElement.setIsEnabled then
                hudPosElement:setIsEnabled(false)
                if hudPosElement.setToolTipText then
                    hudPosElement:setToolTipText("Admin only")
                end
            end

            self.uiElements[hudPosDef.uiId] = hudPosElement
            table.insert(self.uiElements, hudPosElement)
        end
    end

    -- Validate injection before marking as complete
    if not self:validateInjection() then
        SoilLogger.warning("GUI injection failed validation")
        return false
    end

    self.injected = true

    local statusMsg = string.format(
        "Settings UI injected (Admin: %s, PF: %s, Multiplayer: %s)",
        tostring(isAdmin),
        tostring(pfActive),
        tostring(g_currentMission.missionDynamicInfo.isMultiplayer)
    )
    SoilLogger.info(statusMsg)

    return true
end

function SoilSettingsUI:refreshUI()
    if not self.injected then return end

    for id, element in pairs(self.uiElements) do
        if type(id) == "string" then
            local def = nil
            -- Find schema definition by uiId
            for _, d in ipairs(SettingsSchema.definitions) do
                if d.uiId == id then
                    def = d
                    break
                end
            end

            if def then
                local val = self.settings[def.id]
                if def.type == "boolean" then
                    if element.setIsChecked then
                        element:setIsChecked(val)
                    elseif element.setState then
                        element:setState(val and 2 or 1)
                    end
                elseif def.type == "number" and element.setState then
                    element:setState(val)
                end
            end
        end
    end

    print("[SoilFertilizer] UI refreshed with current settings")
end

-- Validate that UI elements were successfully injected
function SoilSettingsUI:validateInjection()
    -- Check that we have UI elements
    if not self.uiElements or #self.uiElements == 0 then
        SoilLogger.warning("Validation failed: No UI elements created")
        return false
    end

    -- Check that g_gui is available
    if not g_gui or not g_gui.screenControllers then
        SoilLogger.warning("Validation failed: g_gui not available")
        return false
    end

    -- Check that InGameMenu exists
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if not inGameMenu or not inGameMenu.pageSettings then
        SoilLogger.warning("Validation failed: InGameMenu not available")
        return false
    end

    -- Check that settings layout exists
    local layout = inGameMenu.pageSettings.generalSettingsLayout
    if not layout or not layout.elements then
        SoilLogger.warning("Validation failed: Settings layout not available")
        return false
    end

    -- Simplified validation: Trust UIHelper's built-in pcall validation
    -- UIHelper functions only return non-nil elements that were successfully created and added
    -- Strict layout array verification is fragile when multiple mods inject UI elements
    local hasValidElements = false
    for _, elem in ipairs(self.uiElements) do
        if elem and type(elem) == "table" then
            hasValidElements = true
            break
        end
    end

    if not hasValidElements then
        SoilLogger.warning("Validation failed: No valid UI elements created")
        return false
    end

    local modeText = ""
    if g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        modeText = g_server and " (MP server)" or " (MP client)"
    else
        modeText = " (SP)"
    end

    SoilLogger.info("GUI validation passed%s: %d elements created", modeText, #self.uiElements)
    return true
end

function SoilSettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then return end

    if not self:isPlayerAdmin() then return end

    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = "Reset Soil Settings",
            callback = function()
                if not self:isPlayerAdmin() then
                    self:showAdminOnlyWarning()
                    return
                end

                if g_SoilFertilityManager and g_SoilFertilityManager.settings then
                    if g_client then
                        if g_dedicatedServer then
                            g_SoilFertilityManager.settings:resetToDefaults()
                        else
                            g_gui:showYesNoDialog({
                                text = "Reset all Soil & Fertilizer settings to defaults?",
                                callback = function(yes)
                                    if yes then
                                        if g_SoilFertilityManager.settingsGUI then
                                            g_SoilFertilityManager.settingsGUI:consoleCommandResetSettings()
                                        end
                                    end
                                end
                            })
                        end
                    else
                        g_SoilFertilityManager.settings:resetToDefaults()
                        if self then
                            self:refreshUI()
                        end
                        g_gui:showInfoDialog({text="Soil & Fertilizer settings reset to defaults"})
                    end
                end
            end,
            showWhenPaused = true
        }
    end

    local exists = false
    for _, btn in ipairs(settingsFrame.menuButtonInfo) do
        if btn == self._resetButton then
            exists = true
            break
        end
    end

    if not exists then
        table.insert(settingsFrame.menuButtonInfo, self._resetButton)
        if settingsFrame.setMenuButtonInfoDirty then
            settingsFrame:setMenuButtonInfoDirty()
        end
    end
end
