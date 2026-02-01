-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.0.0)
-- =========================================================
-- Realistic soil fertility and fertilizer management
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
---@class SettingsUI
SettingsUI = {}
local SettingsUI_mt = Class(SettingsUI)

function SettingsUI.new(settings)
    local self = setmetatable({}, SettingsUI_mt)
    self.settings = settings
    self.injected = false
    return self
end

function SettingsUI:inject()
    if self.injected then 
        return 
    end
    
    local page = g_gui.screenControllers[InGameMenu].pageSettings
    if not page then
        Logging.error("sf: Settings page not found - cannot inject settings!")
        return 
    end
    
    local layout = page.generalSettingsLayout
    if not layout then
        Logging.error("sf: Settings layout not found!")
        return 
    end
    
    local section = UIHelper.createSection(layout, "sf_section")
    if not section then
        Logging.error("sf: Failed to create settings section!")
        return
    end
    
    local enabledOpt = UIHelper.createBinaryOption(
        layout,
        "sf_enabled",
        "sf_enabled",
        self.settings.enabled,
        function(val)
            self.settings.enabled = val
            self.settings:save()
            print("Soil Mod: " .. (val and "Enabled" or "Disabled"))
        end
    )
    
    local debugOpt = UIHelper.createBinaryOption(
        layout,
        "sf_debug",
        "sf_debug",
        self.settings.debugMode,
        function(val)
            self.settings.debugMode = val
            self.settings:save()
            print("Soil Mod: Debug mode " .. (val and "enabled" or "disabled"))
        end
    )
    
    local fertilityOpt = UIHelper.createBinaryOption(
        layout,
        "sf_fertility",
        "sf_fertility",
        self.settings.fertilitySystem,
        function(val)
            self.settings.fertilitySystem = val
            self.settings:save()
            print("Soil Mod: Fertility system " .. (val and "enabled" or "disabled"))
        end
    )
    
    local nutrientsOpt = UIHelper.createBinaryOption(
        layout,
        "sf_nutrients",
        "sf_nutrients",
        self.settings.nutrientCycles,
        function(val)
            self.settings.nutrientCycles = val
            self.settings:save()
            print("Soil Mod: Nutrient cycles " .. (val and "enabled" or "disabled"))
        end
    )
    
    local fertilizerCostsOpt = UIHelper.createBinaryOption(
        layout,
        "sf_fertilizer_cost",
        "sf_fertilizer_cost",
        self.settings.fertilizerCosts,
        function(val)
            self.settings.fertilizerCosts = val
            self.settings:save()
            print("Soil Mod: Fertilizer costs " .. (val and "enabled" or "disabled"))
        end
    )
    
    local diffOptions = {
        getTextSafe("sf_diff_1"),
        getTextSafe("sf_diff_2"),
        getTextSafe("sf_diff_3")
    }
    
    local diffOpt = UIHelper.createMultiOption(
        layout,
        "sf_diff",
        "sf_difficulty",
        diffOptions,
        self.settings.difficulty,
        function(val)
            self.settings.difficulty = val
            self.settings:save()
            print("Soil Mod: Difficulty set to " .. self.settings:getDifficultyName())
        end
    )
    
    local notificationsOpt = UIHelper.createBinaryOption(
        layout,
        "sf_notifications",
        "sf_notifications",
        self.settings.showNotifications,
        function(val)
            self.settings.showNotifications = val
            self.settings:save()
            print("Soil Mod: Notifications " .. (val and "enabled" or "disabled"))
        end
    )
    
    self.enabledOption = enabledOpt
    self.debugOption = debugOpt
    self.fertilityOption = fertilityOpt
    self.nutrientsOption = nutrientsOpt
    self.fertilizerCostsOption = fertilizerCostsOpt
    self.difficultyOption = diffOpt
    self.notificationsOption = notificationsOpt
    
    self.injected = true
    layout:invalidateLayout()
    
    print("Soil Mod: Settings UI injected successfully")
end

function getTextSafe(key)
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        return key
    end
    return text
end

function SettingsUI:refreshUI()
    if not self.injected then
        return
    end
    
    if self.enabledOption and self.enabledOption.setIsChecked then
        self.enabledOption:setIsChecked(self.settings.enabled)
    elseif self.enabledOption and self.enabledOption.setState then
        self.enabledOption:setState(self.settings.enabled and 2 or 1)
    end
    
    if self.debugOption and self.debugOption.setIsChecked then
        self.debugOption:setIsChecked(self.settings.debugMode)
    elseif self.debugOption and self.debugOption.setState then
        self.debugOption:setState(self.settings.debugMode and 2 or 1)
    end
    
    if self.fertilityOption and self.fertilityOption.setIsChecked then
        self.fertilityOption:setIsChecked(self.settings.fertilitySystem)
    elseif self.fertilityOption and self.fertilityOption.setState then
        self.fertilityOption:setState(self.settings.fertilitySystem and 2 or 1)
    end
    
    if self.nutrientsOption and self.nutrientsOption.setIsChecked then
        self.nutrientsOption:setIsChecked(self.settings.nutrientCycles)
    elseif self.nutrientsOption and self.nutrientsOption.setState then
        self.nutrientsOption:setState(self.settings.nutrientCycles and 2 or 1)
    end
    
    if self.fertilizerCostsOption and self.fertilizerCostsOption.setIsChecked then
        self.fertilizerCostsOption:setIsChecked(self.settings.fertilizerCosts)
    elseif self.fertilizerCostsOption and self.fertilizerCostsOption.setState then
        self.fertilizerCostsOption:setState(self.settings.fertilizerCosts and 2 or 1)
    end
    
    if self.difficultyOption and self.difficultyOption.setState then
        self.difficultyOption:setState(self.settings.difficulty)
    end
    
    if self.notificationsOption and self.notificationsOption.setIsChecked then
        self.notificationsOption:setIsChecked(self.settings.showNotifications)
    elseif self.notificationsOption and self.notificationsOption.setState then
        self.notificationsOption:setState(self.settings.showNotifications and 2 or 1)
    end
    
    print("Soil Mod: UI refreshed")
end

function SettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then
        print("sf: ensureResetButton - settingsFrame invalid")
        return
    end
    
    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = g_i18n:getText("sf_reset") or "Reset Settings",
            callback = function()
                print("sf: Reset button clicked!")
                if g_SoilFertilityManager and g_SoilFertilityManager.settings then
                    g_SoilFertilityManager.settings:resetToDefaults()
                    if g_SoilFertilityManager.settingsUI then
                        g_SoilFertilityManager.settingsUI:refreshUI()
                    end
                end
            end,
            showWhenPaused = true
        }
    end
    
    for _, btn in ipairs(settingsFrame.menuButtonInfo) do
        if btn == self._resetButton then
            print("sf: Reset button already in menuButtonInfo")
            return
        end
    end
    
    table.insert(settingsFrame.menuButtonInfo, self._resetButton)
    settingsFrame:setMenuButtonInfoDirty()
    print("sf: Reset button added to footer! (X key)")
end