-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.1.1)
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
        return
    end
    -- Normal toggle
    self.settings[settingKey] = val
    self.settings:save()
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

    -- Detect PF mode
    local pfActive = g_SoilFertilityManager and g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem.PFActive

    -- Options
    local options = {
        {id="sf_enabled", value=self.settings.enabled, callback=function(val) self.settings.enabled=val; self.settings:save() end},
        {id="sf_debug", value=self.settings.debugMode, callback=function(val) self.settings.debugMode=val; self.settings:save() end},
        {id="sf_fertility", value=self.settings.fertilitySystem, callback=function(val) self:togglePFProtected("fertilitySystem", val) end, disabled=pfActive},
        {id="sf_nutrients", value=self.settings.nutrientCycles, callback=function(val) self:togglePFProtected("nutrientCycles", val) end, disabled=pfActive},
        {id="sf_fertilizer_cost", value=self.settings.fertilizerCosts, callback=function(val) self:togglePFProtected("fertilizerCosts", val) end, disabled=pfActive},
        {id="sf_notifications", value=self.settings.showNotifications, callback=function(val) self.settings.showNotifications=val; self.settings:save() end}
    }

    for _, opt in ipairs(options) do
        local success, element = pcall(UIHelper.createBinaryOption, layout, opt.id, opt.id, opt.value, opt.callback)
        if success and element then
            if opt.disabled and element.setIsEnabled then
                element:setIsEnabled(false)
                element:setTooltip("Disabled while Precision Farming is active")
            end
            self.uiElements[opt.id] = element
            table.insert(self.uiElements, element)
        end
    end

    -- Difficulty
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
            return
        end
        self.settings.difficulty = val
        self.settings:save()
    end)
    if success and diffElement then
        self.uiElements.sf_diff = diffElement
        table.insert(self.uiElements, diffElement)
    end

    self.injected = true
    print("Soil Mod: Settings UI injected successfully (PFActive="..tostring(pfActive)..")")
    return true
end

function SoilSettingsUI:refreshUI()
    if not self.injected then return end
    for id, element in pairs(self.uiElements) do
        local val = self.settings[id:gsub("sf_", "")]
        if val ~= nil then
            if element.setIsChecked then
                element:setIsChecked(val)
            elseif element.setState then
                element:setState(val and 2 or 1)
            end
        elseif id=="sf_diff" and element.setState then
            element:setState(self.settings.difficulty)
        end
    end
    print("Soil Mod: UI refreshed")
end

function SoilSettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then return end
    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = "Reset Settings",
            callback = function()
                if g_SoilFertilityManager and g_SoilFertilityManager.settings then
                    g_SoilFertilityManager.settings:resetToDefaults()
                    if g_SoilFertilityManager.soilSettingsUI then
                        g_SoilFertilityManager.soilSettingsUI:refreshUI()
                    end
                    g_gui:showInfoDialog({text="Soil & Fertilizer settings have been reset to defaults"})
                end
            end,
            showWhenPaused = true
        }
    end
    local exists = false
    for _, btn in ipairs(settingsFrame.menuButtonInfo) do
        if btn==self._resetButton then exists=true; break end
    end
    if not exists then
        table.insert(settingsFrame.menuButtonInfo, self._resetButton)
        if settingsFrame.setMenuButtonInfoDirty then
            settingsFrame:setMenuButtonInfoDirty()
        end
    end
end
