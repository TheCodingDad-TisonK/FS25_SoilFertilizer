-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.1.0)
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
    self.uiElements = {}
    self._resetButton = nil
    return self
end

function SettingsUI:inject()
    if self.injected or self.compatibilityMode then 
        if self.compatibilityMode then
            print("Soil Mod: Running in compatibility mode - GUI injection skipped")
        end
        return 
    end
    
    if not g_gui then
        Logging.warning("sf: g_gui not available")
        return false
    end
    
    if not g_gui.screenControllers then
        Logging.warning("sf: screenControllers not available")
        return false
    end
    
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if not inGameMenu then
        Logging.warning("sf: InGameMenu controller not found")
        return false
    end
    
    local page = inGameMenu.pageSettings
    if not page then
        Logging.warning("sf: Settings page not found")
        return false
    end

    if not page.generalSettingsLayout then
        Logging.warning("sf: generalSettingsLayout not ready")
        return false
    end
    
    local layout = page.generalSettingsLayout
    if not layout or not layout.elements then
        Logging.warning("sf: layout.elements is nil or invalid")
        return false
    end

    for _, element in ipairs(layout.elements) do
        if element and element.setText then
            local text = element:getText()
            if text and text:find("Soil & Fertilizer") then
                print("Soil Mod: Settings already injected")
                self.injected = true
                return true
            end
        end
    end
    
    self.uiElements = {}
    
    local spacerSuccess, spacer = pcall(function()
        local emptyDesc = UIHelper.createDescription(layout, " ")
        if emptyDesc then
            emptyDesc.textSize = emptyDesc.textSize * 0.3 
            emptyDesc:setText("")  
            return emptyDesc
        end
        return nil
    end)
    
    if spacerSuccess and spacer then
        table.insert(self.uiElements, spacer)
    end
    
    local section = UIHelper.createSection(layout, "sf_section")
    if not section then
        Logging.error("sf: Failed to create section header")
        for _, el in ipairs(layout.elements) do
            if el and el.name and el.name:find("section") then
                local success, cloned = pcall(function() return el:clone(layout) end)
                if success and cloned then
                    section = cloned
                    section.id = nil
                    if section.setText then
                        section:setText(g_i18n:getText("sf_section") or "Soil & Fertilizer")
                    end
                    layout:addElement(section)
                    table.insert(self.uiElements, section)
                    break
                end
            end
        end
    else
        table.insert(self.uiElements, section)
    end
    
    if not section then
        Logging.error("sf: Could not create section after all attempts")
        return false
    end
    
    local options = {
        {
            id = "sf_enabled",
            textId = "sf_enabled",
            value = self.settings.enabled,
            callback = function(val)
                self.settings.enabled = val
                self.settings:save()
                print("Soil Mod: " .. (val and "Enabled" or "Disabled"))
            end
        },
        {
            id = "sf_debug",
            textId = "sf_debug",
            value = self.settings.debugMode,
            callback = function(val)
                self.settings.debugMode = val
                self.settings:save()
                print("Soil Mod: Debug mode " .. (val and "enabled" or "disabled"))
            end
        },
        {
            id = "sf_fertility",
            textId = "sf_fertility",
            value = self.settings.fertilitySystem,
            callback = function(val)
                self.settings.fertilitySystem = val
                self.settings:save()
                print("Soil Mod: Fertility system " .. (val and "enabled" or "disabled"))
            end
        },
        {
            id = "sf_nutrients",
            textId = "sf_nutrients",
            value = self.settings.nutrientCycles,
            callback = function(val)
                self.settings.nutrientCycles = val
                self.settings:save()
                print("Soil Mod: Nutrient cycles " .. (val and "enabled" or "disabled"))
            end
        },
        {
            id = "sf_fertilizer_cost",
            textId = "sf_fertilizer_cost",
            value = self.settings.fertilizerCosts,
            callback = function(val)
                self.settings.fertilizerCosts = val
                self.settings:save()
                print("Soil Mod: Fertilizer costs " .. (val and "enabled" or "disabled"))
            end
        },
        {
            id = "sf_notifications",
            textId = "sf_notifications",
            value = self.settings.showNotifications,
            callback = function(val)
                self.settings.showNotifications = val
                self.settings:save()
                print("Soil Mod: Notifications " .. (val and "enabled" or "disabled"))
            end
        }
    }
    
    local optionsCreated = 0
    for _, optData in ipairs(options) do
        local success, element = pcall(function()
            return UIHelper.createBinaryOption(
                layout,
                optData.id,
                optData.textId,
                optData.value,
                optData.callback
            )
        end)
        
        if success and element then
            self.uiElements[optData.id] = element
            table.insert(self.uiElements, element)
            optionsCreated = optionsCreated + 1
        else
            Logging.warning("sf: Failed to create option: " .. optData.id)
        end
    end
    
    local diffSuccess, diffElement = pcall(function()
        local diffOptions = {
            g_i18n:getText("sf_diff_1") or "Simple",
            g_i18n:getText("sf_diff_2") or "Realistic",
            g_i18n:getText("sf_diff_3") or "Hardcore"
        }
        
        return UIHelper.createMultiOption(
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
    end)
    
    if diffSuccess and diffElement then
        self.uiElements.sf_diff = diffElement
        table.insert(self.uiElements, diffElement)
        optionsCreated = optionsCreated + 1
    end
    
    local endSpacerSuccess, endSpacer = pcall(function()
        local emptyDesc = UIHelper.createDescription(layout, " ")
        if emptyDesc then
            emptyDesc.textSize = emptyDesc.textSize * 0.5
            emptyDesc:setText("")
            return emptyDesc
        end
        return nil
    end)
    
    if endSpacerSuccess and endSpacer then
        table.insert(self.uiElements, endSpacer)
    end

    if layout.invalidateLayout then
        pcall(function() layout:invalidateLayout() end)
    end
    
    if layout.updateAbsolutePosition then
        pcall(function() layout:updateAbsolutePosition() end)
    end
    
    self.injected = true
    print(string.format("Soil Mod: Settings UI injected successfully (%d/%d options)", 
        optionsCreated, #options + 1))
    
    return true
end

function getTextSafe(key)
    if not g_i18n then
        return key
    end
    
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        return key
    end
    return text
end

function SettingsUI:cleanup()
    if self.uiElements then
        for _, element in ipairs(self.uiElements) do
            if element and element.delete then
                pcall(function() element:delete() end)
            end
        end
        self.uiElements = {}
    end
    self.injected = false
end

function SettingsUI:onSettingsFrameClosed()
    if self._resetButton then
        self._resetButton = nil
    end
end

function SettingsUI:refreshUI()
    if not self.injected then
        return
    end
    
    for id, element in pairs(self.uiElements) do
        if element then
            local value = self.settings[id:gsub("sf_", "")]
            if value ~= nil then
                if element.setIsChecked then
                    element:setIsChecked(value)
                elseif element.setState then
                    element:setState(value and 2 or 1)
                end
            elseif id == "sf_diff" and element.setState then
                element:setState(self.settings.difficulty)
            end
        end
    end
    
    print("Soil Mod: UI refreshed")
end

function SettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then
        return
    end
    
    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = getTextSafe("sf_reset") or "Reset Settings",
            callback = function()
                print("sf: Reset button clicked!")
                if g_SoilFertilityManager and g_SoilFertilityManager.settings then
                    g_SoilFertilityManager.settings:resetToDefaults()
                    if g_SoilFertilityManager.settingsUI then
                        g_SoilFertilityManager.settingsUI:refreshUI()
                    end
                    g_gui:showInfoDialog({
                        text = "Soil & Fertilizer settings have been reset to defaults"
                    })
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
        print("sf: Reset button added")
    end
end
