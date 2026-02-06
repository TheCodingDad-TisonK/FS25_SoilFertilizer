-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.1.2)
-- =========================================================
-- Realistic soil fertility and fertilizer management
-- =========================================================
-- Author: TisonK (modified)
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- =========================================================

local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- Source all required files
source(modDirectory .. "src/SoilFertilitySystem.lua")
source(modDirectory .. "src/SoilFertilityManager.lua")
source(modDirectory .. "src/settings/SettingsManager.lua")
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/SoilSettingsGUI.lua")
source(modDirectory .. "src/utils/UIHelper.lua")
source(modDirectory .. "src/settings/SoilSettingsUI.lua")

-- Globals
local sfm = nil
local SAFE_MODE = false
local initTimer = 0
local guiInjected = false

-- Helper: check if mod is initialized
local function isEnabled()
    return sfm ~= nil
end

-- Compatibility check
local function checkModCompatibility()
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lower = string.lower(tostring(modName))
            if lower:find("tyre") or lower:find("tire") then
                print("Soil Mod: Tyre-related mod detected - enabling compatibility mode")
                SAFE_MODE = true
                break
            end
        end
    end

    if g_currentMission and g_currentMission:getIsServer() and not g_currentMission:getIsClient() then
        print("Soil Mod: Dedicated server detected - enabling compatibility mode")
        SAFE_MODE = true
    end
end
checkModCompatibility()

-- Called after mission loaded
local function loadedMission(mission, node)
    if not isEnabled() or mission.cancelLoading then return end
    sfm:onMissionLoaded()
end

-- Load handler
local function load(mission)
    local isDedicatedServer = mission:getIsServer() and not mission:getIsClient()
    local disableGUI = isDedicatedServer or SAFE_MODE or not mission:getIsClient()

    if disableGUI then
        print("Soil Mod: Server/console-only mode - GUI disabled")
    end

    if sfm == nil then
        print("Soil & Fertilizer Mod: Initializing...")
        sfm = SoilFertilityManager.new(mission, modDirectory, modName, disableGUI)
        getfenv(0)["g_SoilFertilityManager"] = sfm

        -- Ensure GUI flagged as injected in server mode
        if disableGUI and sfm.soilSettingsUI then
            sfm.soilSettingsUI.injected = true
        end

        print("Soil & Fertilizer Mod: Initialized in " .. (disableGUI and "server/console" or "full") .. " mode")
    end
end

-- Unload handler
local function unload()
    if sfm ~= nil then
        sfm:delete()
        sfm = nil
        getfenv(0)["g_SoilFertilityManager"] = nil
    end
end

-- Delayed GUI injection for safe client
local function delayedGUISetup()
    if SAFE_MODE or guiInjected then return end
    if g_gui and g_SoilFertilityManager and g_SoilFertilityManager.soilSettingsUI then
        if g_currentMission and g_currentMission.isClient and 
           g_currentMission.controlledVehicle and 
           g_gui.screenControllers and g_gui.screenControllers[InGameMenu] then

            print("Soil Mod: Attempting safe GUI injection...")
            local success, errorMsg = pcall(function()
                if not g_SoilFertilityManager.soilSettingsUI.injected then
                    g_SoilFertilityManager.soilSettingsUI:inject()
                    print("Soil Mod: GUI injected successfully")
                end
            end)

            if not success then
                print("Soil Mod: GUI injection failed: " .. tostring(errorMsg))
                SAFE_MODE = true
            end

            guiInjected = true
        end
    end
end

-- Hook save/load events
local function hookSaveLoadEvents()
    -- Hook mission save
    if Mission00.saveToXMLFile then
        Mission00.saveToXMLFile = Utils.prependedFunction(
            Mission00.saveToXMLFile,
            function(mission, xmlFile, key, usedModNames)
                if g_SoilFertilityManager then
                    g_SoilFertilityManager:saveSoilData()
                end
            end
        )
    end
    
    -- Hook mission load
    if Mission00.loadFromXMLFile then
        Mission00.loadFromXMLFile = Utils.appendedFunction(
            Mission00.loadFromXMLFile,
            function(mission, xmlFile, key)
                if g_SoilFertilityManager then
                    g_SoilFertilityManager:loadSoilData()
                end
            end
        )
    end
end

-- Hook into FS25 mission events
Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if not guiInjected and initTimer < 10000 then
        initTimer = initTimer + dt
        if initTimer >= 3000 then
            delayedGUISetup()
        end
    end

    if sfm then
        sfm:update(dt)
    end
end)

-- Install save/load hooks
hookSaveLoadEvents()

-- Console commands
function soilfertility()
    if g_SoilFertilityManager and g_SoilFertilityManager.soilSettingsGUI then
        return g_SoilFertilityManager.soilSettingsGUI:consoleCommandHelp()
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
        print("SoilFieldInfo <fieldId> - Show field soil info")
        print("SoilSaveData - Force save soil data")
        print("================================")
        return "Soil & Fertilizer Mod commands listed above"
    end
end

function soilStatus()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local s = g_SoilFertilityManager.settings
        print(string.format(
            "Enabled: %s\nFertility System: %s\nNutrient Cycles: %s\nFertilizer Costs: %s\nDifficulty: %s\nNotifications: %s",
            tostring(s.enabled), tostring(s.fertilitySystem), tostring(s.nutrientCycles),
            tostring(s.fertilizerCosts), s:getDifficultyName(), tostring(s.showNotifications)
        ))
    else
        print("Soil & Fertilizer Mod not initialized")
    end
end

-- Additional console command for saving data
addConsoleCommand("SoilSaveData", "Force save soil data", "consoleCommandSaveData", 
    function()
        if g_SoilFertilityManager then
            g_SoilFertilityManager:saveSoilData()
            return "Soil data saved"
        end
        return "Soil Mod not initialized"
    end
)

-- Expose global console functions
getfenv(0)["soilfertility"] = soilfertility
getfenv(0)["soilStatus"] = soilStatus
getfenv(0)["soilEnable"] = function() 
    if g_SoilFertilityManager and g_SoilFertilityManager.soilSettingsGUI then
        return g_SoilFertilityManager.soilSettingsGUI:consoleCommandSoilEnable()
    end
    return "Soil & Fertilizer Mod not initialized"
end
getfenv(0)["soilDisable"] = function() 
    if g_SoilFertilityManager and g_SoilFertilityManager.soilSettingsGUI then
        return g_SoilFertilityManager.soilSettingsGUI:consoleCommandSoilDisable()
    end
    return "Soil & Fertilizer Mod not initialized"
end

print("========================================")
print("  FS25 Soil & Fertilizer Mod LOADED     ")
print("  Realistic soil management system      ")
print("  Type 'soilfertility' for commands     ")
print("  With full real event hooks installed  ")
print("========================================")
