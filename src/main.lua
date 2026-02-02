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
local SAFE_MODE = false 
local initTimer = 0
local guiInjected = false

local function isEnabled()
    return sfm ~= nil
end

local function checkModCompatibility()
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            if string.lower(tostring(modName)):find("tyre") or 
               string.lower(tostring(modName)):find("tire") then
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
    local isDedicatedServer = mission:getIsServer() and not mission:getIsClient()
    local disableGUI = isDedicatedServer or SAFE_MODE or not mission:getIsClient()
    
    if disableGUI then
        print("Soil Mod: Running in server/console-only mode - GUI features disabled")
    end
    
    if sfm == nil then
        print("Soil & Fertilizer Mod: Initializing...")
        sfm = SoilFertilityManager.new(mission, modDirectory, modName, disableGUI)
        getfenv(0)["g_SoilFertilityManager"] = sfm
        
        if disableGUI and sfm.settingsUI then
            sfm.settingsUI.injected = true 
        end
        
        print("Soil & Fertilizer Mod: Initialized in " .. (disableGUI and "server/console" or "full") .. " mode")
    end
end

local function unload()
    if sfm ~= nil then
        sfm:delete()
        sfm = nil
        getfenv(0)["g_SoilFertilityManager"] = nil
    end
end

local function delayedGUISetup()
    if SAFE_MODE or guiInjected then
        return
    end
    
    if g_gui and g_SoilFertilityManager and g_SoilFertilityManager.settingsUI then
        if g_currentMission and g_currentMission.isClient and 
           g_currentMission.controlledVehicle and 
           g_gui.screenControllers and g_gui.screenControllers[InGameMenu] then
            
            print("Soil Mod: Attempting safe GUI injection...")
            
            local success, errorMsg = pcall(function()
                if not g_SoilFertilityManager.settingsUI.injected then
                    g_SoilFertilityManager.settingsUI:inject()
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
