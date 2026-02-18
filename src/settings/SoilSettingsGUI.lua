-- =========================================================
-- FS25 Realistic Soil & Fertilizer (Settings GUI)
-- =========================================================
-- Author: TisonK (modified)
-- =========================================================
---@class SoilSettingsGUI

SoilSettingsGUI = {}
local SoilSettingsGUI_mt = Class(SoilSettingsGUI)

function SoilSettingsGUI.new()
    local self = setmetatable({}, SoilSettingsGUI_mt)
    return self
end

function SoilSettingsGUI:registerConsoleCommands()
    addConsoleCommand("SoilSetDifficulty", "Set difficulty (1=Simple, 2=Realistic, 3=Hardcore)", "consoleCommandSetDifficulty", self)
    addConsoleCommand("SoilEnable", "Enable Soil Mod", "consoleCommandSoilEnable", self)
    addConsoleCommand("SoilDisable", "Disable Soil Mod", "consoleCommandSoilDisable", self)
    addConsoleCommand("SoilSetFertility", "Enable/disable fertility system (true/false)", "consoleCommandSetFertility", self)
    addConsoleCommand("SoilSetNutrients", "Enable/disable nutrient cycles (true/false)", "consoleCommandSetNutrients", self)
    addConsoleCommand("SoilSetFertilizerCosts", "Enable/disable fertilizer costs (true/false)", "consoleCommandSetFertilizerCosts", self)
    addConsoleCommand("SoilSetNotifications", "Enable/disable notifications (true/false)", "consoleCommandSetNotifications", self)
    -- NEW CONSOLE COMMANDS
    addConsoleCommand("SoilSetSeasonalEffects", "Enable/disable seasonal effects (true/false)", "consoleCommandSetSeasonalEffects", self)
    addConsoleCommand("SoilSetRainEffects", "Enable/disable rain effects (true/false)", "consoleCommandSetRainEffects", self)
    addConsoleCommand("SoilSetPlowingBonus", "Enable/disable plowing bonus (true/false)", "consoleCommandSetPlowingBonus", self)
    addConsoleCommand("SoilShowSettings", "Show current settings", "consoleCommandShowSettings", self)
    addConsoleCommand("SoilFieldInfo", "Show field soil information (fieldId)", "consoleCommandFieldInfo", self)
    addConsoleCommand("SoilListFields", "List all fields with soil data", "consoleCommandListFields", self)
    addConsoleCommand("SoilResetSettings", "Reset all settings to defaults", "consoleCommandResetSettings", self)
    addConsoleCommand("SoilSaveData", "Force save soil data", "consoleCommandSaveData", self)
    addConsoleCommand("SoilDebug", "Toggle debug mode", "consoleCommandDebug", self)
    addConsoleCommand("soilfertility", "Show all soil commands", "consoleCommandHelp", self)

    Logging.info("[SoilFertilizer] Console commands registered")
end

function SoilSettingsGUI:consoleCommandHelp()
    print("=== Soil & Fertilizer Mod Console Commands ===")
    print("soilfertility - Show this help")
    print("SoilEnable/Disable - Toggle mod")
    print("SoilSetDifficulty 1|2|3 - Set difficulty")
    print("SoilSetFertility true|false - Toggle fertility system")
    print("SoilSetNutrients true|false - Toggle nutrient cycles")
    print("SoilSetFertilizerCosts true|false - Toggle fertilizer costs")
    print("SoilSetNotifications true|false - Toggle notifications")
    -- NEW COMMANDS IN HELP
    print("SoilSetSeasonalEffects true|false - Toggle seasonal effects")
    print("SoilSetRainEffects true|false - Toggle rain effects")
    print("SoilSetPlowingBonus true|false - Toggle plowing bonus")
    print("SoilShowSettings - Show current settings")
    print("SoilFieldInfo <fieldId> - Show soil info for field")
    print("SoilListFields - List all fields with soil data")
    print("SoilResetSettings - Reset to defaults")
    print("SoilSaveData - Force save soil data")
    print("SoilDebug - Toggle debug mode")
    print("==============================================")
    return "Type 'soilfertility' for more info"
end

function SoilSettingsGUI:consoleCommandSetDifficulty(difficulty)
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

function SoilSettingsGUI:consoleCommandSoilEnable()
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

function SoilSettingsGUI:consoleCommandSoilDisable()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.enabled = false
        g_SoilFertilityManager.settings:save()
        return "Soil & Fertilizer Mod disabled"
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSetFertility(enabled)
    if enabled == nil then return "Usage: SoilSetFertility true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.fertilitySystem = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Fertility system %s", g_SoilFertilityManager.settings.fertilitySystem and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSetNutrients(enabled)
    if enabled == nil then return "Usage: SoilSetNutrients true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.nutrientCycles = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Nutrient cycles %s", g_SoilFertilityManager.settings.nutrientCycles and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSetFertilizerCosts(enabled)
    if enabled == nil then return "Usage: SoilSetFertilizerCosts true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.fertilizerCosts = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Fertilizer costs %s", g_SoilFertilityManager.settings.fertilizerCosts and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSetNotifications(enabled)
    if enabled == nil then return "Usage: SoilSetNotifications true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.showNotifications = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Notifications %s", g_SoilFertilityManager.settings.showNotifications and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

-- NEW CONSOLE COMMAND FUNCTIONS
function SoilSettingsGUI:consoleCommandSetSeasonalEffects(enabled)
    if enabled == nil then return "Usage: SoilSetSeasonalEffects true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.seasonalEffects = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Seasonal effects %s", g_SoilFertilityManager.settings.seasonalEffects and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSetRainEffects(enabled)
    if enabled == nil then return "Usage: SoilSetRainEffects true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.rainEffects = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Rain effects %s", g_SoilFertilityManager.settings.rainEffects and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSetPlowingBonus(enabled)
    if enabled == nil then return "Usage: SoilSetPlowingBonus true|false" end
    local enable = enabled:lower()
    if enable ~= "true" and enable ~= "false" then return "Invalid value. Use 'true' or 'false'" end
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.plowingBonus = (enable == "true")
        g_SoilFertilityManager.settings:save()
        return string.format("Plowing bonus %s", g_SoilFertilityManager.settings.plowingBonus and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandDebug()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        g_SoilFertilityManager.settings.debugMode = not g_SoilFertilityManager.settings.debugMode
        g_SoilFertilityManager.settings:save()
        return string.format("Debug mode %s", g_SoilFertilityManager.settings.debugMode and "enabled" or "disabled")
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandSaveData()
    if g_SoilFertilityManager then
        g_SoilFertilityManager:saveSoilData()
        return "Soil data saved"
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandShowSettings()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local s = g_SoilFertilityManager.settings
        local info = string.format(
            "=== Soil & Fertilizer Mod Settings ===\n" ..
            "Enabled: %s\nDebug Mode: %s\nFertility System: %s\nNutrient Cycles: %s\nFertilizer Costs: %s\nDifficulty: %s\nNotifications: %s\n" ..
            -- NEW SETTINGS IN SHOW SETTINGS
            "Seasonal Effects: %s\nRain Effects: %s\nPlowing Bonus: %s\n" ..
            "PF Active: %s\nFields Tracked: %d\n" ..
            "================================",
            tostring(s.enabled), tostring(s.debugMode), tostring(s.fertilitySystem),
            tostring(s.nutrientCycles), tostring(s.fertilizerCosts),
            s:getDifficultyName(), tostring(s.showNotifications),
            -- NEW SETTINGS VALUES
            tostring(s.seasonalEffects), tostring(s.rainEffects), tostring(s.plowingBonus),
            tostring(g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem.PFActive or false),
            g_SoilFertilityManager.soilSystem and #g_SoilFertilityManager.soilSystem.fieldData or 0
        )
        print(info)
        return info
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandFieldInfo(fieldId)
    local fid = tonumber(fieldId)
    if not fid then return "Usage: SoilFieldInfo <fieldId>" end
    if g_SoilFertilityManager and g_SoilFertilityManager.soilSystem then
        local info = g_SoilFertilityManager.soilSystem:getFieldInfo(fid)
        if info then
            local fInfo = string.format(
                "=== Field %d Soil Information ===\n" ..
                "Nitrogen: %d (%s)\nPhosphorus: %d (%s)\nPotassium: %d (%s)\n" ..
                "Organic Matter: %.1f%%\npH: %.1f\n" ..
                "Last Crop: %s\nDays Since Harvest: %d\nFertilizer Applied: %.0fL\n" ..
                "Needs Fertilization: %s\n" ..
                "================================",
                fid,
                info.nitrogen.value, info.nitrogen.status,
                info.phosphorus.value, info.phosphorus.status,
                info.potassium.value, info.potassium.status,
                info.organicMatter,
                info.pH,
                info.lastCrop or "None",
                info.daysSinceHarvest,
                info.fertilizerApplied,
                info.needsFertilization and "Yes" or "No"
            )
            print(fInfo)
            return fInfo
        else
            return "Field not found or not initialized"
        end
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandListFields()
    if g_SoilFertilityManager and g_SoilFertilityManager.soilSystem then
        g_SoilFertilityManager.soilSystem:listAllFields()
        return "Field list displayed in console"
    end
    return "Error: Soil Mod not initialized"
end

function SoilSettingsGUI:consoleCommandResetSettings()
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