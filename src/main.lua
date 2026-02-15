-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FIXED FOR MULTIPLAYER)
-- =========================================================
-- Realistic soil fertility and fertilizer management
-- =========================================================
-- Author: TisonK (Multiplayer fix applied)
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- =========================================================

local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- Source all required files (order matters: dependencies first)
-- 1. Utilities and config (no dependencies)
source(modDirectory .. "src/utils/Logger.lua")
source(modDirectory .. "src/utils/AsyncRetryHandler.lua")
source(modDirectory .. "src/config/Constants.lua")
source(modDirectory .. "src/config/SettingsSchema.lua")

-- 2. Core systems
source(modDirectory .. "src/hooks/HookManager.lua")
source(modDirectory .. "src/SoilFertilitySystem.lua")
source(modDirectory .. "src/SoilFertilityManager.lua")

-- 3. Settings
source(modDirectory .. "src/settings/SettingsManager.lua")
source(modDirectory .. "src/settings/Settings.lua")
source(modDirectory .. "src/settings/SoilSettingsGUI.lua")

-- 4. UI
source(modDirectory .. "src/utils/UIHelper.lua")
source(modDirectory .. "src/settings/SoilSettingsUI.lua")
source(modDirectory .. "src/ui/SoilHUD.lua")

-- 5. Network
source(modDirectory .. "src/network/NetworkEvents.lua")

-- Globals
local sfm = nil
local SAFE_MODE = false

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
                SoilLogger.info("Tyre-related mod detected - enabling compatibility mode")
                SAFE_MODE = true
                break
            end
        end
    end

    if g_currentMission and g_currentMission:getIsServer() and not g_currentMission:getIsClient() then
        SoilLogger.info("Dedicated server detected - enabling compatibility mode")
        SAFE_MODE = true
    end
end
checkModCompatibility()

-- Called after mission loaded
local function loadedMission(mission, node)
    if not isEnabled() or mission.cancelLoading then return end
    sfm:onMissionLoaded()

    -- Note: Multiplayer sync is handled in loadFromXMLFile hook
end

-- Load handler
local function load(mission)
    local isDedicatedServer = mission:getIsServer() and not mission:getIsClient()
    local disableGUI = isDedicatedServer or SAFE_MODE or not mission:getIsClient()

    if disableGUI then
        SoilLogger.info("Server/console-only mode - GUI disabled")
    end

    if sfm == nil then
        SoilLogger.info("Initializing...")

        -- Log multiplayer status
        if mission.missionDynamicInfo.isMultiplayer then
            if mission:getIsServer() then
                SoilLogger.info("Running as MULTIPLAYER SERVER")
            else
                SoilLogger.info("Running as MULTIPLAYER CLIENT")
            end
        else
            SoilLogger.info("Running in SINGLEPLAYER mode")
        end

        sfm = SoilFertilityManager.new(mission, modDirectory, modName, disableGUI)
        getfenv(0)["g_SoilFertilityManager"] = sfm

        SoilLogger.info("Initialized in %s mode", disableGUI and "server/console" or "full")
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


-- Hook save/load events
local function hookSaveLoadEvents()
    -- Hook mission save (SERVER ONLY)
    if Mission00.saveToXMLFile then
        Mission00.saveToXMLFile = Utils.prependedFunction(
            Mission00.saveToXMLFile,
            function(mission, xmlFile, key, usedModNames)
                -- Only server should save
                if g_server or not mission.missionDynamicInfo.isMultiplayer then
                    if g_SoilFertilityManager then
                        g_SoilFertilityManager:saveSoilData()
                    end
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

                    -- If multiplayer client, request sync
                    if g_client and not g_server and SoilNetworkEvents_RequestFullSync then
                        -- Small delay to let server finish loading
                        mission.loadingDelay = 2000
                    end
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
    if sfm then
        sfm:update(dt)
    end
end)

-- Hook draw for HUD (always-on overlay)
FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(mission)
    if sfm and sfm.soilHUD then
        sfm.soilHUD:draw()
    end
end)

-- Install save/load hooks
hookSaveLoadEvents()

-- Console commands
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
        print("SoilSetSeasonalEffects true|false - Toggle seasonal effects")
        print("SoilSetRainEffects true|false - Toggle rain effects")
        print("SoilSetPlowingBonus true|false - Toggle plowing bonus")
        print("SoilResetSettings - Reset to defaults")
        print("SoilFieldInfo <fieldId> - Show field soil info")
        print("SoilSaveData - Force save soil data")
        print("")
        print("NOTE: In multiplayer, only server admins can change settings")
        print("================================")
        return "Soil & Fertilizer Mod commands listed above"
    end
end

function soilStatus()
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local s = g_SoilFertilityManager.settings
        local isMultiplayer = g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer
        local isServer = g_server ~= nil
        local isClient = g_client ~= nil

        print(string.format(
            "=== Soil & Fertilizer Status ===\n" ..
            "Mode: %s\n" ..
            "Role: %s\n" ..
            "Enabled: %s\n" ..
            "Fertility System: %s\n" ..
            "Nutrient Cycles: %s\n" ..
            "Fertilizer Costs: %s\n" ..
            "Difficulty: %s\n" ..
            "Notifications: %s\n" ..
            "Seasonal Effects: %s\n" ..
            "Rain Effects: %s\n" ..
            "Plowing Bonus: %s\n" ..
            "================================",
            isMultiplayer and "Multiplayer" or "Singleplayer",
            isServer and "Server" or (isClient and "Client" or "Unknown"),
            tostring(s.enabled),
            tostring(s.fertilitySystem),
            tostring(s.nutrientCycles),
            tostring(s.fertilizerCosts),
            s:getDifficultyName(),
            tostring(s.showNotifications),
            tostring(s.seasonalEffects),
            tostring(s.rainEffects),
            tostring(s.plowingBonus)
        ))
    else
        print("Soil & Fertilizer Mod not initialized")
    end
end

-- Expose global console functions
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
