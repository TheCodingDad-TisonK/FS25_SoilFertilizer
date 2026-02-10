-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FIXED FOR MULTIPLAYER)
-- =========================================================
-- Settings UI with multiplayer support
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
    
    -- Single player = always admin
    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true
    end
    
    -- Dedicated server console = always admin
    if g_dedicatedServer then
        return true
    end
    
    -- Multiplayer: check if master user
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
    -- Check admin permission first
    if not self:isPlayerAdmin() then
        self:showAdminOnlyWarning()
        -- Revert UI to current value
        self:refreshUI()
        return
    end
    
    -- Use network event system if available
    if SoilNetworkEvents_RequestSettingChange then
        SoilNetworkEvents_RequestSettingChange(settingName, value)
    else
        -- Fallback: direct change (singleplayer or old code path)
        self.settings[settingName] = value
        self.settings:save()
        
        print(string.format("[Soil Mod] Setting '%s' changed to %s", settingName, tostring(value)))
    end
end

-- PF-protected toggle helper
function SoilSettingsUI:togglePFProtected(settingKey, val)
    local pfActive = g_SoilFertilityManager and g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem.PFActive
    
    if pfActive then
        -- Show blinking warning on HUD
        if g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(
                "Precision Farming active - cannot change this setting",
                4000
            )
        end
        -- Revert UI
        self:refreshUI()
        return
    end
    
    -- Normal toggle via network
    self:requestSettingChange(settingKey, val)
end

function SoilSettingsUI:inject()
    if self.injected then return end
    if not g_gui or not g_gui.screenControllers then
        Logging.warning("sf: GUI unavailable")
        return false
    end

    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if not inGameMenu or not inGameMenu.pageSettings or not inGameMenu.pageSettings.generalSettingsLayout then
        Logging.warning("sf: Settings page not ready")
        return false
    end

    local layout = inGameMenu.pageSettings.generalSettingsLayout

    -- Section header
    local section = UIHelper.createSection(layout, "sf_section")
    table.insert(self.uiElements, section)

    -- Check admin status and PF status
    local isAdmin = self:isPlayerAdmin()
    local pfActive = g_SoilFertilityManager and g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem.PFActive

    -- Add info text if not admin
    if not isAdmin and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        local infoText = UIHelper.createDescription(layout, "sf_admin_only_info")
        if infoText and infoText.setText then
            infoText:setText("(Admin only - contact server owner to change these settings)")
            if infoText.textColor then
                infoText.textColor = {1.0, 0.6, 0.0, 1.0} -- Orange warning color
            end
        end
        table.insert(self.uiElements, infoText)
    end

    -- Options with callbacks that use network events
    local options = {
        {
            id="sf_enabled", 
            value=self.settings.enabled, 
            callback=function(val) 
                self:requestSettingChange("enabled", val)
            end
        },
        {
            id="sf_debug", 
            value=self.settings.debugMode, 
            callback=function(val) 
                self:requestSettingChange("debugMode", val)
            end
        },
        {
            id="sf_fertility", 
            value=self.settings.fertilitySystem, 
            callback=function(val) 
                self:togglePFProtected("fertilitySystem", val)
            end, 
            disabled=pfActive
        },
        {
            id="sf_nutrients", 
            value=self.settings.nutrientCycles, 
            callback=function(val) 
                self:togglePFProtected("nutrientCycles", val)
            end, 
            disabled=pfActive
        },
        {
            id="sf_fertilizer_cost", 
            value=self.settings.fertilizerCosts, 
            callback=function(val) 
                self:togglePFProtected("fertilizerCosts", val)
            end, 
            disabled=pfActive
        },
        {
            id="sf_notifications", 
            value=self.settings.showNotifications, 
            callback=function(val) 
                self:requestSettingChange("showNotifications", val)
            end
        },
        {
            id="sf_seasonal_effects", 
            value=self.settings.seasonalEffects, 
            callback=function(val) 
                self:togglePFProtected("seasonalEffects", val)
            end, 
            disabled=pfActive
        },
        {
            id="sf_rain_effects", 
            value=self.settings.rainEffects, 
            callback=function(val) 
                self:togglePFProtected("rainEffects", val)
            end, 
            disabled=pfActive
        },
        {
            id="sf_plowing_bonus", 
            value=self.settings.plowingBonus, 
            callback=function(val) 
                self:togglePFProtected("plowingBonus", val)
            end, 
            disabled=pfActive
        }
    }

    for _, opt in ipairs(options) do
        local success, element = pcall(UIHelper.createBinaryOption, layout, opt.id, opt.id, opt.value, opt.callback)
        if success and element then
            -- Disable if not admin OR if PF is active for this setting
            local shouldDisable = (not isAdmin) or opt.disabled
            
            if shouldDisable and element.setIsEnabled then
                element:setIsEnabled(false)
                
                -- Set appropriate tooltip
                local tooltip = "Admin only"
                if opt.disabled then
                    tooltip = "Disabled while Precision Farming is active"
                end
                
                if element.setToolTipText then
                    element:setToolTipText(tooltip)
                end
            end
            
            self.uiElements[opt.id] = element
            table.insert(self.uiElements, element)
        end
    end

    -- Difficulty dropdown
    local diffOptions = {
        g_i18n:getText("sf_diff_1") or "Simple",
        g_i18n:getText("sf_diff_2") or "Realistic",
        g_i18n:getText("sf_diff_3") or "Hardcore"
    }
    
    local success, diffElement = pcall(UIHelper.createMultiOption, layout, "sf_diff", "sf_difficulty", diffOptions, self.settings.difficulty, function(val)
        if pfActive then
            if g_currentMission and g_currentMission.hud then
                g_currentMission.hud:showBlinkingWarning(
                    "Precision Farming active - cannot change difficulty",
                    4000
                )
            end
            self:refreshUI()
            return
        end
        
        self:requestSettingChange("difficulty", val)
    end)
    
    if success and diffElement then
        -- Disable if not admin or PF active
        if (not isAdmin or pfActive) and diffElement.setIsEnabled then
            diffElement:setIsEnabled(false)
            local tooltip = pfActive and "Disabled while Precision Farming is active" or "Admin only"
            if diffElement.setToolTipText then
                diffElement:setToolTipText(tooltip)
            end
        end
        
        self.uiElements.sf_diff = diffElement
        table.insert(self.uiElements, diffElement)
    end

    self.injected = true
    
    local statusMsg = string.format(
        "Settings UI injected (Admin: %s, PF: %s, Multiplayer: %s)", 
        tostring(isAdmin),
        tostring(pfActive),
        tostring(g_currentMission.missionDynamicInfo.isMultiplayer)
    )
    print("[Soil Mod] " .. statusMsg)
    
    return true
end

function SoilSettingsUI:refreshUI()
    if not self.injected then return end
    
    for id, element in pairs(self.uiElements) do
        if type(id) == "string" then
            local settingKey = id:gsub("sf_", "")
            local val = self.settings[settingKey]
            
            if val ~= nil then
                if element.setIsChecked then
                    element:setIsChecked(val)
                elseif element.setState then
                    element:setState(val and 2 or 1)
                end
            elseif id == "sf_diff" and element.setState then
                element:setState(self.settings.difficulty)
            end
        end
    end
    
    print("[Soil Mod] UI refreshed with current settings")
end

function SoilSettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then return end
    
    -- Only show reset button to admins
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
                    -- Reset on server (will broadcast to clients)
                    if g_client then
                        -- Request reset via console command
                        -- (We could create a network event for this too)
                        if g_dedicatedServer then
                            g_SoilFertilityManager.settings:resetToDefaults()
                        else
                            -- Show confirmation dialog
                            g_gui:showYesNoDialog({
                                text = "Reset all Soil & Fertilizer settings to defaults?",
                                callback = function(yes)
                                    if yes then
                                        -- Use console command to trigger reset
                                        if g_SoilFertilityManager.settingsGUI then
                                            g_SoilFertilityManager.settingsGUI:consoleCommandResetSettings()
                                        end
                                    end
                                end
                            })
                        end
                    else
                        -- Singleplayer
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