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
local modDirectory = g_currentModDirectory
local modName = g_currentModName

source(modDirectory .. "src/settings/SettingsManager.lua")
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/SettingsGUI.lua") 
source(modDirectory .. "src/utils/UIHelper.lua")
source(modDirectory .. "src/settings/SettingsUI.lua")
source(modDirectory .. "src/SoilFertilitySystem.lua")
source(modDirectory .. "src/SoilFertilityManager.lua")

local sfm

local function isEnabled()
    return sfm ~= nil
end

local function loadedMission(mission, node)
    if not isEnabled() then
        return
    end
    
    if mission.cancelLoading then
        return
    end
    
    sfm:onMissionLoaded()
end

local function load(mission)
    if sfm == nil then
        print("Soil & Fertilizer Mod: Initializing...")
        sfm = SoilFertilityManager.new(mission, modDirectory, modName)
        getfenv(0)["g_SoilFertilityManager"] = sfm
        print("Soil & Fertilizer Mod: Initialized successfully")
    end
end

local function unload()
    if sfm ~= nil then
        sfm:delete()
        sfm = nil
        getfenv(0)["g_SoilFertilityManager"] = nil
    end
end

Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if sfm then
        sfm:update(dt)
    end
end)

function soilfertility()
    if g_SoilFertilityManager and g_SoilFertilityManager.settingsGUI then
        return g_SoilFertilityManager.settingsGUI:consoleCommandHelp()
    else
        print("=== Soil & Fertilizer Mod Commands ===")
        print("Type these commands in console (~):")
        print("SoilShowSettings - Show current settings")
        print("SoilEnable/Disable - Enable/disable mod")
        print("SoilSetDifficulty 1|2|3 - Set difficulty")
        print("SoilSetFertility true|false - Toggle fertility system")
        print("SoilSetNutrients true|false - Toggle nutrient cycles")
        print("SoilSetFertilizerCosts true|false - Toggle fertilizer costs")
        print("SoilSetNotifications true|false - Toggle notifications")
        print("SoilResetSettings - Reset to defaults")
        print("================================")
        return "Soil & Fertilizer Mod commands listed above"
    end
end

function soilStatus()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local settings = g_SoilFertilityManager.settings
        print(string.format(
            "Enabled: %s\nFertility System: %s\nNutrient Cycles: %s\nFertilizer Costs: %s\nDifficulty: %s\nNotifications: %s",
            tostring(settings.enabled),
            tostring(settings.fertilitySystem),
            tostring(settings.nutrientCycles),
            tostring(settings.fertilizerCosts),
            settings:getDifficultyName(),
            tostring(settings.showNotifications)
        ))
    else
        print("Soil & Fertilizer Mod not initialized")
    end
end

getfenv(0)["soilfertility"] = soilfertility
getfenv(0)["soilStatus"] = soilStatus
getfenv(0)["soilEnable"] = function() 
    if g_SoilFertilityManager and g_SoilFertilityManager.settingsGUI then
        return g_SoilFertilityManager.settingsGUI:consoleCommandSoilEnable()
    end
    return "Soil & Fertilizer Mod not initialized"
end

getfenv(0)["soilDisable"] = function() 
    if g_SoilFertilityManager and g_SoilFertilityManager.settingsGUI then
        return g_SoilFertilityManager.settingsGUI:consoleCommandSoilDisable()
    end
    return "Soil & Fertilizer Mod not initialized"
end

print("========================================")
print("  FS25 Soil & Fertilizer Mod LOADED     ")
print("  Realistic soil management system      ")
print("  Type 'soilfertility' for commands     ")
print("========================================")