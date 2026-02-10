-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FIXED FOR MULTIPLAYER)
-- =========================================================
-- Realistic soil fertility and fertilizer management
-- =========================================================
-- Author: TisonK (Multiplayer fix applied)
-- =========================================================
---@class SettingsManager
SettingsManager = {}
local SettingsManager_mt = Class(SettingsManager)

SettingsManager.MOD_NAME = g_currentModName or "FS25_SoilFertilizer"
SettingsManager.XMLTAG = "SoilFertilityManager"

SettingsManager.defaultConfig = {
    difficulty = 2,
    
    enabled = true,
    debugMode = false,
    fertilitySystem = true,
    nutrientCycles = true,
    fertilizerCosts = true,
    showNotifications = true,
    seasonalEffects = true,
    rainEffects = true,
    plowingBonus = true
}

function SettingsManager.new()
    return setmetatable({}, SettingsManager_mt)
end

-- FIXED: Now saves to SERVER SAVEGAME instead of client PC
function SettingsManager:getSavegameXmlFilePath()
    -- MULTIPLAYER FIX: Always use savegame directory (server-side storage)
    if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        local path = string.format("%s/%s.xml", 
            g_currentMission.missionInfo.savegameDirectory, 
            SettingsManager.MOD_NAME)
        return path
    end
    
    -- Fallback for early initialization (should not happen in normal gameplay)
    print("[Soil Mod WARNING] Savegame directory not available yet")
    return nil
end

function SettingsManager:loadSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    
    if not xmlPath then
        print("[Soil Mod] Cannot load settings - savegame path not available, using defaults")
        self:applyDefaults(settingsObject)
        return
    end
    
    if fileExists(xmlPath) then
        local xml = XMLFile.load("sf_Config", xmlPath)
        if xml then
            settingsObject.difficulty = xml:getInt(self.XMLTAG..".difficulty", self.defaultConfig.difficulty)
            
            settingsObject.enabled = xml:getBool(self.XMLTAG..".enabled", self.defaultConfig.enabled)
            settingsObject.debugMode = xml:getBool(self.XMLTAG..".debugMode", self.defaultConfig.debugMode)
            settingsObject.fertilitySystem = xml:getBool(self.XMLTAG..".fertilitySystem", self.defaultConfig.fertilitySystem)
            settingsObject.nutrientCycles = xml:getBool(self.XMLTAG..".nutrientCycles", self.defaultConfig.nutrientCycles)
            settingsObject.fertilizerCosts = xml:getBool(self.XMLTAG..".fertilizerCosts", self.defaultConfig.fertilizerCosts)
            settingsObject.showNotifications = xml:getBool(self.XMLTAG..".showNotifications", self.defaultConfig.showNotifications)
            settingsObject.seasonalEffects = xml:getBool(self.XMLTAG..".seasonalEffects", self.defaultConfig.seasonalEffects)
            settingsObject.rainEffects = xml:getBool(self.XMLTAG..".rainEffects", self.defaultConfig.rainEffects)
            settingsObject.plowingBonus = xml:getBool(self.XMLTAG..".plowingBonus", self.defaultConfig.plowingBonus)
            
            xml:delete()
            
            print(string.format("[Soil Mod] Settings loaded from server savegame: %s", xmlPath))
            return
        end
    end
    
    -- No saved settings found - use defaults
    print("[Soil Mod] No saved settings found, using defaults")
    self:applyDefaults(settingsObject)
end

function SettingsManager:applyDefaults(settingsObject)
    settingsObject.difficulty = self.defaultConfig.difficulty
    settingsObject.enabled = self.defaultConfig.enabled
    settingsObject.debugMode = self.defaultConfig.debugMode
    settingsObject.fertilitySystem = self.defaultConfig.fertilitySystem
    settingsObject.nutrientCycles = self.defaultConfig.nutrientCycles
    settingsObject.fertilizerCosts = self.defaultConfig.fertilizerCosts
    settingsObject.showNotifications = self.defaultConfig.showNotifications
    settingsObject.seasonalEffects = self.defaultConfig.seasonalEffects
    settingsObject.rainEffects = self.defaultConfig.rainEffects
    settingsObject.plowingBonus = self.defaultConfig.plowingBonus
end

function SettingsManager:saveSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    
    if not xmlPath then
        print("[Soil Mod ERROR] Cannot save settings - savegame path not available")
        return
    end
    
    -- Only server should save (or singleplayer)
    if g_client and not g_server then
        print("[Soil Mod] Client skipping save (settings saved on server)")
        return
    end
    
    local xml = XMLFile.create("sf_Config", xmlPath, self.XMLTAG)
    if xml then
        xml:setInt(self.XMLTAG..".difficulty", settingsObject.difficulty)
        
        xml:setBool(self.XMLTAG..".enabled", settingsObject.enabled)
        xml:setBool(self.XMLTAG..".debugMode", settingsObject.debugMode)
        xml:setBool(self.XMLTAG..".fertilitySystem", settingsObject.fertilitySystem)
        xml:setBool(self.XMLTAG..".nutrientCycles", settingsObject.nutrientCycles)
        xml:setBool(self.XMLTAG..".fertilizerCosts", settingsObject.fertilizerCosts)
        xml:setBool(self.XMLTAG..".showNotifications", settingsObject.showNotifications)
        xml:setBool(self.XMLTAG..".seasonalEffects", settingsObject.seasonalEffects)
        xml:setBool(self.XMLTAG..".rainEffects", settingsObject.rainEffects)
        xml:setBool(self.XMLTAG..".plowingBonus", settingsObject.plowingBonus)
        
        xml:save()
        xml:delete()
        
        print(string.format("[Soil Mod] Settings saved to server savegame: %s", xmlPath))
    else
        print("[Soil Mod ERROR] Failed to create settings XML file")
    end
end

-- MIGRATION: Try to migrate old client-side settings to server
function SettingsManager:migrateOldClientSettings()
    -- This would be path to old client-side settings (if they exist)
    -- We don't actually want to use getUserProfileAppPath() anymore
    -- but we can check if old settings exist and inform the user
    
    return false -- No migration performed
end