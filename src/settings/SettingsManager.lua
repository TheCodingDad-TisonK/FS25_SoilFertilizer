-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.1.2)
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
---@class SettingsManager
SettingsManager = {}
local SettingsManager_mt = Class(SettingsManager)

SettingsManager.MOD_NAME = g_currentModName
SettingsManager.XMLTAG = "SoilFertilityManager"

SettingsManager.defaultConfig = {
    difficulty = 2,
    
    enabled = true,
    debugMode = false,
    fertilitySystem = true,
    nutrientCycles = true,
    fertilizerCosts = true,
    showNotifications = true,
    -- NEW SETTINGS DEFAULT CONFIG
    seasonalEffects = true,
    rainEffects = true,
    plowingBonus = true
}

function SettingsManager.new()
    return setmetatable({}, SettingsManager_mt)
end

function SettingsManager:getSavegameXmlFilePath()
    if g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        return ("%s/%s.xml"):format(g_currentMission.missionInfo.savegameDirectory, SettingsManager.MOD_NAME)
    end
    return nil
end

function SettingsManager:loadSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    if xmlPath and fileExists(xmlPath) then
        local xml = XMLFile.load("sf_Config", xmlPath)
        if xml then
            settingsObject.difficulty = xml:getInt(self.XMLTAG..".difficulty", self.defaultConfig.difficulty)
            
            settingsObject.enabled = xml:getBool(self.XMLTAG..".enabled", self.defaultConfig.enabled)
            settingsObject.debugMode = xml:getBool(self.XMLTAG..".debugMode", self.defaultConfig.debugMode)
            settingsObject.fertilitySystem = xml:getBool(self.XMLTAG..".fertilitySystem", self.defaultConfig.fertilitySystem)
            settingsObject.nutrientCycles = xml:getBool(self.XMLTAG..".nutrientCycles", self.defaultConfig.nutrientCycles)
            settingsObject.fertilizerCosts = xml:getBool(self.XMLTAG..".fertilizerCosts", self.defaultConfig.fertilizerCosts)
            settingsObject.showNotifications = xml:getBool(self.XMLTAG..".showNotifications", self.defaultConfig.showNotifications)
            -- NEW SETTINGS LOAD
            settingsObject.seasonalEffects = xml:getBool(self.XMLTAG..".seasonalEffects", self.defaultConfig.seasonalEffects)
            settingsObject.rainEffects = xml:getBool(self.XMLTAG..".rainEffects", self.defaultConfig.rainEffects)
            settingsObject.plowingBonus = xml:getBool(self.XMLTAG..".plowingBonus", self.defaultConfig.plowingBonus)
            
            xml:delete()
            return
        end
    end
    settingsObject.difficulty = self.defaultConfig.difficulty
    settingsObject.enabled = self.defaultConfig.enabled
    settingsObject.debugMode = self.defaultConfig.debugMode
    settingsObject.fertilitySystem = self.defaultConfig.fertilitySystem
    settingsObject.nutrientCycles = self.defaultConfig.nutrientCycles
    settingsObject.fertilizerCosts = self.defaultConfig.fertilizerCosts
    settingsObject.showNotifications = self.defaultConfig.showNotifications
    -- NEW SETTINGS DEFAULT LOAD
    settingsObject.seasonalEffects = self.defaultConfig.seasonalEffects
    settingsObject.rainEffects = self.defaultConfig.rainEffects
    settingsObject.plowingBonus = self.defaultConfig.plowingBonus
end

function SettingsManager:saveSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()
    if not xmlPath then return end
    
    local xml = XMLFile.create("sf_Config", xmlPath, self.XMLTAG)
    if xml then
        xml:setInt(self.XMLTAG..".difficulty", settingsObject.difficulty)
        
        xml:setBool(self.XMLTAG..".enabled", settingsObject.enabled)
        xml:setBool(self.XMLTAG..".debugMode", settingsObject.debugMode)
        xml:setBool(self.XMLTAG..".fertilitySystem", settingsObject.fertilitySystem)
        xml:setBool(self.XMLTAG..".nutrientCycles", settingsObject.nutrientCycles)
        xml:setBool(self.XMLTAG..".fertilizerCosts", settingsObject.fertilizerCosts)
        xml:setBool(self.XMLTAG..".showNotifications", settingsObject.showNotifications)
        -- NEW SETTINGS SAVE
        xml:setBool(self.XMLTAG..".seasonalEffects", settingsObject.seasonalEffects)
        xml:setBool(self.XMLTAG..".rainEffects", settingsObject.rainEffects)
        xml:setBool(self.XMLTAG..".plowingBonus", settingsObject.plowingBonus)
        
        xml:save()
        xml:delete()
    end
end
