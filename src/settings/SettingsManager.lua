-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Settings Manager
-- =========================================================
-- Saves/loads mod settings from the server savegame XML.
-- Auto-generated from SettingsSchema — add settings there.
-- =========================================================
-- Author: TisonK
-- =========================================================
---@class SettingsManager
SettingsManager = {}
local SettingsManager_mt = Class(SettingsManager)

SettingsManager.MOD_NAME = g_currentModName or "FS25_SoilFertilizer"
SettingsManager.XMLTAG = "SoilFertilityManager"

-- Default config is now derived from schema
SettingsManager.defaultConfig = SettingsSchema.getAllDefaults()

function SettingsManager.new()
    return setmetatable({}, SettingsManager_mt)
end

-- Settings are saved to the server savegame directory so all players share the same config.
function SettingsManager:getSavegameXmlFilePath()
    if g_currentMission and g_currentMission.missionInfo and g_currentMission.missionInfo.savegameDirectory then
        local path = string.format("%s/%s.xml",
            g_currentMission.missionInfo.savegameDirectory,
            SettingsManager.MOD_NAME)
        return path
    end

    SoilLogger.warning("Savegame directory not available yet")
    return nil
end

function SettingsManager:loadSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()

    if not xmlPath then
        SoilLogger.info("Cannot load settings - savegame path not available, using defaults")
        self:applyDefaults(settingsObject)
        return
    end

    if fileExists(xmlPath) then
        local xml = XMLFile.load("sf_Config", xmlPath)
        if xml then
            -- Auto-load all settings from schema
            for _, def in ipairs(SettingsSchema.definitions) do
                local xmlKey = self.XMLTAG .. "." .. def.id
                if def.type == "boolean" then
                    settingsObject[def.id] = xml:getBool(xmlKey, def.default)
                elseif def.type == "number" then
                    settingsObject[def.id] = xml:getInt(xmlKey, def.default)
                end
            end

            xml:delete()
            SoilLogger.info("Settings loaded from server savegame: %s", xmlPath)
            return
        end
    end

    SoilLogger.info("No saved settings found, using defaults")
    self:applyDefaults(settingsObject)
end

function SettingsManager:applyDefaults(settingsObject)
    for _, def in ipairs(SettingsSchema.definitions) do
        settingsObject[def.id] = def.default
    end
end

function SettingsManager:saveSettings(settingsObject)
    local xmlPath = self:getSavegameXmlFilePath()

    if not xmlPath then
        SoilLogger.error("Cannot save settings - savegame path not available")
        return
    end

    -- Only server should save (or singleplayer)
    if g_client ~= nil and g_server == nil then
        SoilLogger.debug("Client skipping save (settings saved on server)")
        return
    end

    local xml = XMLFile.create("sf_Config", xmlPath, self.XMLTAG)
    if xml then
        -- Auto-save all settings from schema
        for _, def in ipairs(SettingsSchema.definitions) do
            local xmlKey = self.XMLTAG .. "." .. def.id
            if def.type == "boolean" then
                xml:setBool(xmlKey, settingsObject[def.id])
            elseif def.type == "number" then
                xml:setInt(xmlKey, settingsObject[def.id])
            end
        end

        xml:save()
        xml:delete()

        SoilLogger.info("Settings saved to server savegame: %s", xmlPath)
    else
        SoilLogger.error("Failed to create settings XML file")
    end
end
