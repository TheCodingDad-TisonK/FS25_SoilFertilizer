-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Entry Point
-- =========================================================
-- Loads all modules in dependency order, hooks FS25 mission
-- lifecycle events, and registers console commands.
-- =========================================================
-- Author: TisonK
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
source(modDirectory .. "src/SprayerRateManager.lua")
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
source(modDirectory .. "src/ui/SoilReportDialog.lua")
source(modDirectory .. "src/ui/SoilMapOverlay.lua")

-- 5. Network
source(modDirectory .. "src/network/NetworkEvents.lua")

-- Globals
local sfm = nil

-- Helper: check if mod is initialized
local function isEnabled()
    return sfm ~= nil
end

-- Called after mission loaded
local function loadedMission(mission, node)
    if not isEnabled() or mission.cancelLoading then return end
    sfm:onMissionLoaded()

    -- $modDir is not resolved in the fillTypes.xml loading context, so we patch
    -- the HUD icon filenames AND overlay handles directly via Lua.
    --
    -- WHY BOTH FIELDS:
    --   ft.hudOverlayFilename  – the path string stored on the fill type object.
    --   ft.hudOverlay          – the pre-loaded overlay handle that FS25's native
    --                            fill-level HUD (bottom-right) actually renders from.
    --
    -- FS25 creates ft.hudOverlay at mission load from the <image hud="..."/> entry
    -- in fillTypes.xml.  All our solid types share the same fallback path
    -- ($dataS/menu/hud/fillTypes/hud_fill_fertilizer.png), so every solid type
    -- displayed the same generic icon regardless of which product was loaded.
    -- Patching only hudOverlayFilename had no visible effect on the native HUD.
    --
    -- Fix: after updating the filename, also replace the overlay handle via
    -- createImageOverlay() (the same API used by SoilHUD.lua for its own overlays).
    -- The old handle is freed with delete() to avoid GPU resource leaks.
    if g_fillTypeManager then
        local hudDir = modDirectory .. "hud/fillTypes/"
        local icons = {
            UAN32       = "hud_fill_UAN32.dds",
            UAN28       = "hud_fill_UAN28.dds",
            ANHYDROUS   = "hud_fill_anhydrous.dds",
            STARTER     = "hud_fill_Starter.dds",
            UREA        = "hud_fill_UREA.dds",
            AMS         = "hud_fill_AMS.dds",
            MAP         = "hud_fill_map.dds",
            DAP         = "hud_fill_dap.dds",
            POTASH      = "hud_fill_potash.dds",
            INSECTICIDE = "hud_fill_insecticide.dds",
            FUNGICIDE   = "hud_fill_fungicide.dds",
        }
        local patched = 0
        local failed  = 0
        for name, file in pairs(icons) do
            local ft = g_fillTypeManager:getFillTypeByName(name)
            if ft then
                local path = hudDir .. file
                -- Update the filename string (read by some third-party mod integrations)
                ft.hudOverlayFilename = path
                -- Replace the overlay handle so the native FS25 fill-level HUD
                -- renders the correct icon instead of the generic fallback.
                if createImageOverlay ~= nil then
                    if ft.hudOverlay ~= nil then
                        delete(ft.hudOverlay)
                    end
                    ft.hudOverlay = createImageOverlay(path)
                    patched = patched + 1
                else
                    failed = failed + 1
                end
            end
        end
        if failed > 0 then
            SoilLogger.warning("HUD icon patch: createImageOverlay unavailable — %d icons not updated (filename only)", failed)
        else
            SoilLogger.info("Custom HUD icons patched for %d mod fill types (overlay + filename)", patched)
        end
    end

    -- Multiplayer client: request full state from server.
    -- SoilRequestFullSyncEvent asks the server for all settings + field data.
    -- The retry handler (AsyncRetryHandler) makes up to 3 attempts with delay
    -- in case the server-side soil system hasn't finished initializing yet.
    if g_client and not g_server and SoilNetworkEvents_RequestFullSync then
        SoilNetworkEvents_RequestFullSync()
    end
end

-- Load handler
local function load(mission)
    local isDedicatedServer = mission:getIsServer() and not mission:getIsClient()
    local disableGUI = isDedicatedServer or not mission:getIsClient()

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
        -- Cross-mod bridge: g_currentMission is a shared C++ object visible to all mods.
        -- getfenv(0) is per-mod scoped in FS25. Use mission property for reliable cross-mod detection.
        mission.soilFertilityManager = sfm

        SoilLogger.info("Initialized in %s mode", disableGUI and "server/console" or "full")
    end
end

-- Unload handler
local function unload()
    if sfm ~= nil then
        sfm:delete()
        sfm = nil
        getfenv(0)["g_SoilFertilityManager"] = nil
        if g_currentMission then g_currentMission.soilFertilityManager = nil end
    end
end


-- Hook save/load events
local function hookSaveLoadEvents()
    -- Hook mission save via FSCareerMissionInfo:saveToXMLFile().
    --
    -- FS25 1.17+ save flow:
    --   FSBaseMission:saveSavegame()
    --     → g_savegameController:saveSavegame()
    --       → saveWriteSavegameStart() (C++)
    --         → SavegameController:onSaveStartComplete(errorCode, savegameDirectory)
    --           → missionInfo:setSavegameDirectory(savegameDirectory)   ← sets tempsavegame path
    --           → missionInfo:saveToXMLFile()                           ← THIS is what we hook
    --
    -- The old Mission00.saveToXMLFile hook was a ghost — that method does not exist on
    -- Mission00 and was never called by FS25 1.17, so soilData.xml was never written.
    --
    -- At the time our appended function fires, missionInfo.savegameDirectory already
    -- points to the tempsavegame staging directory.  FS25 copies ALL files from
    -- tempsavegame to the real savegame directory after save tasks complete, so
    -- soilData.xml written here will land in the correct savegame folder on disk.
    if FSCareerMissionInfo and FSCareerMissionInfo.saveToXMLFile then
        FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
            FSCareerMissionInfo.saveToXMLFile,
            function(missionInfo)
                -- In multiplayer only the server holds authoritative soil data
                if g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
                    if not g_server then return end
                end
                if g_SoilFertilityManager then
                    g_SoilFertilityManager:saveSoilData()
                    if g_SoilFertilityManager.soilHUD then
                        g_SoilFertilityManager.soilHUD:saveLayout()
                    end
                else
                    SoilLogger.warning("g_SoilFertilityManager is NIL — soil data NOT saved!")
                end
            end
        )
        SoilLogger.info("Save hook installed on FSCareerMissionInfo:saveToXMLFile")
    else
        SoilLogger.warning("FSCareerMissionInfo.saveToXMLFile not found — soil data will NOT be saved")
    end

    -- Load is handled in SoilFertilityManager:deferredSoilSystemInit() after soilSystem:initialize().
    -- This guarantees missionInfo.savegameDirectory is set (it is nil at constructor time
    -- for new careers) before we attempt to read soilData.xml.
end

-- Hook into FS25 mission events
Mission00.load = Utils.prependedFunction(Mission00.load, load)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, loadedMission)
-- Prepend so our cleanup runs before FS25 tears down g_inputBinding/HUD (fixes black screen with AGS)
FSBaseMission.delete = Utils.prependedFunction(FSBaseMission.delete, unload)

FSBaseMission.update = Utils.appendedFunction(FSBaseMission.update, function(mission, dt)
    if sfm then
        sfm:update(dt)
    end
end)

-- Hook draw for HUD — guard isRunning so we stop drawing once teardown begins
FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function(mission)
    if sfm and sfm.soilHUD and mission.isRunning then
        sfm.soilHUD:draw()
    end
end)

-- Install save/load hooks
hookSaveLoadEvents()

-- Route mouse events to SoilHUD (for drag/resize edit mode)
-- RMB only enters edit mode when cursor is over the panel (no cross-contamination).
-- eventUsed is checked before processing and returned after, per FS25 standard pattern
-- (prevents double-handling when vehicle camera or another listener already consumed the event).
local soilMouseHandler = {}
function soilMouseHandler:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not eventUsed and sfm and sfm.soilHUD then
        eventUsed = sfm.soilHUD:onMouseEvent(posX, posY, isDown, isUp, button, eventUsed) or eventUsed
    end
    return eventUsed
end
addModEventListener(soilMouseHandler)

-- Console commands
function soilfertility()
    if g_SoilFertilityManager and g_SoilFertilityManager.settingsGUI then
        return g_SoilFertilityManager.settingsGUI:consoleCommandHelp()
    else
        print("=== Soil & Fertilizer Mod Commands ===")
        print("Type these commands in console (~):")
        print("SoilShowSettings - Show current settings")
        print("soilStatus - Show current mod status")
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
