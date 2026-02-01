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
---@class SettingsGUI

SettingsGUI = {}
local SettingsGUI_mt = Class(SettingsGUI)

function SettingsGUI.new()
    local self = setmetatable({}, SettingsGUI_mt)
    return self
end

function SettingsGUI:registerConsoleCommands()
    addConsoleCommand("SoilSetDifficulty", "Set difficulty (1=Simple, 2=Realistic, 3=Hardcore)", "consoleCommandSetDifficulty", self)
    
    addConsoleCommand("SoilEnable", "Enable Soil Mod", "consoleCommandSoilEnable", self)
    addConsoleCommand("SoilDisable", "Disable Soil Mod", "consoleCommandSoilDisable", self)
    addConsoleCommand("SoilSetFertility", "Enable/disable fertility system (true/false)", "consoleCommandSetFertility", self)
    addConsoleCommand("SoilSetNutrients", "Enable/disable nutrient cycles (true/false)", "consoleCommandSetNutrients", self)
    addConsoleCommand("SoilSetFertilizerCosts", "Enable/disable fertilizer costs (true/false)", "consoleCommandSetFertilizerCosts", self)
    addConsoleCommand("SoilSetNotifications", "Enable/disable notifications (true/false)", "consoleCommandSetNotifications", self)
    
    addConsoleCommand("SoilShowSettings", "Show current settings", "consoleCommandShowSettings", self)
    addConsoleCommand("SoilFieldInfo", "Show field soil information (fieldId)", "consoleCommandFieldInfo", self)
    
    addConsoleCommand("SoilResetSettings", "Reset all settings to defaults", "consoleCommandResetSettings", self)
    
    addConsoleCommand("soilfertility", "Show all soil commands", "consoleCommandHelp", self)
    
    Logging.info("Soil & Fertilizer Mod console commands registered")
end

function SettingsGUI:consoleCommandHelp()
    print("=== Soil & Fertilizer Mod Console Commands ===")
    print("soilfertility - Show this help")
    print("SoilEnable/Disable - Toggle mod")
    print("SoilSetDifficulty 1|2|3 - Set difficulty")
    print("SoilSetFertility true|false - Toggle fertility system")
    print("SoilSetNutrients true|false - Toggle nutrient cycles")
    print("SoilSetFertilizerCosts true|false - Toggle fertilizer costs")
    print("SoilSetNotifications true|false - Toggle notifications")
    print("SoilShowSettings - Show current settings")
    print("SoilFieldInfo <fieldId> - Show soil info for field")
    print("SoilResetSettings - Reset to defaults")
    print("==============================================")
    return "Type 'soilfertility' for more info"
end

function SettingsGUI:consoleCommandSetDifficulty(difficulty)
    local diff = tonumber(difficulty)
    if not diff or diff < 1 or diff > 3 then
        Logging.warning("Invalid difficulty. Use 1 (Simple), 2 (Realistic), or 3 (Hardcore)")
        return "Invalid difficulty"
    end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings:setDifficulty(diff)
        g_SoilFertilityManager.settings:save()
        return string.format("Difficulty set to: %s", g_SoilFertilityManager.settings:getDifficultyName())
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandSoilEnable()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.enabled = true
        g_SoilFertilityManager.settings:save()
        
        if g_SoilFertilityManager.soilSystem then
            g_SoilFertilityManager.soilSystem:initialize()
        end
        
        return "Soil & Fertilizer Mod enabled"
    end
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandSoilDisable()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.enabled = false
        g_SoilFertilityManager.settings:save()
        return "Soil & Fertilizer Mod disabled"
    end
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandSetFertility(enabled)
    if enabled == nil then
        return "Usage: SoilSetFertility true|false"
    end
    
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then
        return "Invalid value. Use 'true' or 'false'"
    end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.fertilitySystem = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Fertility system %s", g_SoilFertilityManager.settings.fertilitySystem and "enabled" or "disabled")
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandSetNutrients(enabled)
    if enabled == nil then
        return "Usage: SoilSetNutrients true|false"
    end
    
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then
        return "Invalid value. Use 'true' or 'false'"
    end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.nutrientCycles = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Nutrient cycles %s", g_SoilFertilityManager.settings.nutrientCycles and "enabled" or "disabled")
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandSetFertilizerCosts(enabled)
    if enabled == nil then
        return "Usage: SoilSetFertilizerCosts true|false"
    end
    
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then
        return "Invalid value. Use 'true' or 'false'"
    end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.fertilizerCosts = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Fertilizer costs %s", g_SoilFertilityManager.settings.fertilizerCosts and "enabled" or "disabled")
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandSetNotifications(enabled)
    if enabled == nil then
        return "Usage: SoilSetNotifications true|false"
    end
    
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then
        return "Invalid value. Use 'true' or 'false'"
    end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.showNotifications = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Notifications %s", g_SoilFertilityManager.settings.showNotifications and "enabled" or "disabled")
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandShowSettings()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local settings = g_SoilFertilityManager.settings
        local info = string.format(
            "=== Soil & Fertilizer Mod Settings ===\n" ..
            "Enabled: %s\n" ..
            "Debug Mode: %s\n" ..
            "Fertility System: %s\n" ..
            "Nutrient Cycles: %s\n" ..
            "Fertilizer Costs: %s\n" ..
            "Difficulty: %s\n" ..
            "Notifications: %s\n" ..
            "================================",
            tostring(settings.enabled),
            tostring(settings.debugMode),
            tostring(settings.fertilitySystem),
            tostring(settings.nutrientCycles),
            tostring(settings.fertilizerCosts),
            settings:getDifficultyName(),
            tostring(settings.showNotifications)
        )
        print(info)
        return info
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandFieldInfo(fieldId)
    local fieldIdNum = tonumber(fieldId)
    if not fieldIdNum then
        return "Usage: SoilFieldInfo <fieldId>"
    end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.soilSystem then
        local info = g_SoilFertilityManager.soilSystem:getFieldInfo(fieldIdNum)
        if info then
            local fieldInfo = string.format(
                "=== Field %d Soil Information ===\n" ..
                "Nitrogen: %d (%s)\n" ..
                "Phosphorus: %d (%s)\n" ..
                "Potassium: %d (%s)\n" ..
                "Organic Matter: %.1f%%\n" ..
                "pH: %.1f\n" ..
                "Needs Fertilization: %s\n" ..
                "================================",
                fieldIdNum,
                info.nitrogen.value, info.nitrogen.status,
                info.phosphorus.value, info.phosphorus.status,
                info.potassium.value, info.potassium.status,
                info.organicMatter,
                info.pH,
                info.needsFertilization and "Yes" or "No"
            )
            print(fieldInfo)
            return fieldInfo
        else
            return "Field not found or not initialized"
        end
    end
    
    return "Error: Soil Mod not initialized"
end

function SettingsGUI:consoleCommandResetSettings()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings:resetToDefaults()
        
        if g_SoilFertilityManager.soilSystem then
            g_SoilFertilityManager.soilSystem:initialize()
        end
        
        if g_SoilFertilityManager.settingsUI then
            g_SoilFertilityManager.settingsUI:refreshUI()
        end
        
        return "Soil Mod settings reset to default!"
    end
    
    return "Error: Soil Mod not initialized"
end