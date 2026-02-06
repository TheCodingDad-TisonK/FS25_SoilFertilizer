-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FarmlandManager version)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE: All rights reserved.
-- =========================================================
---@class SoilFertilityManager
SoilFertilityManager = {}
local SoilFertilityManager_mt = Class(SoilFertilityManager)

function SoilFertilityManager.new(mission, modDirectory, modName, disableGUI)
    local self = setmetatable({}, SoilFertilityManager_mt)

    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    self.disableGUI = disableGUI or false

    -- Settings
    assert(SettingsManager, "SettingsManager not loaded")
    self.settingsManager = SettingsManager.new()
    self.settings = Settings.new(self.settingsManager)

    -- Soil system
    assert(SoilFertilitySystem, "SoilFertilitySystem not loaded")
    self.soilSystem = SoilFertilitySystem.new(self.settings)

    -- GUI initialization (client only)
    local shouldInitGUI = not self.disableGUI and mission:getIsClient() and g_gui and not g_safeMode
    if shouldInitGUI then
        print("Soil Mod: Initializing GUI elements...")
        self.settingsUI = SoilSettingsUI.new(self.settings)

        -- Inject GUI safely
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
            InGameMenuSettingsFrame.onFrameOpen,
            function(frame)
                if self.settingsUI and not self.settingsUI.injected then
                    local success = pcall(function()
                        self.settingsUI:inject()
                    end)
                    if not success then
                        print("Soil Mod: GUI injection failed - switching to console-only mode")
                        self.settingsUI.injected = true
                        self.disableGUI = true
                    end
                end
                if self.settingsUI then
                    self.settingsUI:ensureResetButton(frame)
                end
            end
        )

        InGameMenuSettingsFrame.updateButtons = Utils.appendedFunction(
            InGameMenuSettingsFrame.updateButtons,
            function(frame)
                if self.settingsUI then
                    self.settingsUI:ensureResetButton(frame)
                end
            end
        )
    else
        print("Soil Mod: GUI initialization skipped (Server/Console mode)")
        self.settingsUI = nil
    end

    -- Console commands
    self.settingsGUI = SoilSettingsGUI.new()
    self.settingsGUI:registerConsoleCommands()

    -- Load settings
    self.settings:load()
    
    -- Load saved soil data
    self:loadSoilData()

    -- Compatibility with other mods
    self:checkAndApplyCompatibility()

    return self
end

function SoilFertilityManager:checkAndApplyCompatibility()
    -- Precision Farming
    local pfDetected = false
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("precisionfarming") then
                pfDetected = true
                break
            end
        end
    end

    if pfDetected then
        print("Soil Mod: Precision Farming detected - enabling read-only mode")
        self.soilSystem.PFActive = true
        if self.settings.showNotifications then
            if g_currentMission and g_currentMission.hud then
                g_currentMission.hud:showBlinkingWarning(
                    "PF Detected - Soil & Fertilizer Mod running in read-only mode",
                    4000
                )
            else
                self.soilSystem:log("PF Detected - Soil & Fertilizer Mod running in read-only mode")
            end
        end
    else
        self.soilSystem.PFActive = false
    end

    -- Used Tyres mod
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("tyre") or lowerName:find("tire") or lowerName:find("used") then
                if self.settingsUI then
                    self.settingsUI.compatibilityMode = true
                end
                print("Soil Mod: Used Tyres mod detected - UI compatibility mode enabled")
                break
            end
        end
    end
end

function SoilFertilityManager:onMissionLoaded()
    if not self.settings.enabled then return end

    local success, errorMsg = pcall(function()
        if self.soilSystem then
            self.soilSystem:initialize()
        end
        if self.settings.showNotifications and g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(
                "Soil & Fertilizer Mod Active - Type 'soilfertility' for commands",
                4000
            )
        end
    end)

    if not success then
        print("Soil Mod: Error during mission load - " .. tostring(errorMsg))
        self.settings.enabled = false
        self.settings:save()
    end
end

-- Save soil data
function SoilFertilityManager:saveSoilData()
    if not self.soilSystem or not g_currentMission or not g_currentMission.missionInfo then
        return
    end
    
    local savegamePath = g_currentMission.missionInfo.savegameDirectory
    if not savegamePath then return end
    
    local xmlPath = savegamePath .. "/soilData.xml"
    local xmlFile = createXMLFile("soilData", xmlPath, "soilData")
    
    if xmlFile then
        self.soilSystem:saveToXMLFile(xmlFile, "soilData")
        saveXMLFile(xmlFile)
        delete(xmlFile)
        print("Soil Mod: Soil data saved to " .. xmlPath)
    end
end

-- Load soil data
function SoilFertilityManager:loadSoilData()
    if not self.soilSystem or not g_currentMission or not g_currentMission.missionInfo then
        return
    end
    
    local savegamePath = g_currentMission.missionInfo.savegameDirectory
    if not savegamePath then return end
    
    local xmlPath = savegamePath .. "/soilData.xml"
    if fileExists(xmlPath) then
        local xmlFile = loadXMLFile("soilData", xmlPath)
        if xmlFile then
            self.soilSystem:loadFromXMLFile(xmlFile, "soilData")
            delete(xmlFile)
            print("Soil Mod: Soil data loaded from " .. xmlPath)
        end
    else
        print("Soil Mod: No saved soil data found, using defaults")
    end
end

function SoilFertilityManager:update(dt)
    if self.soilSystem then
        self.soilSystem:update(dt)
    end
end

function SoilFertilityManager:delete()
    -- Save soil data before shutdown
    self:saveSoilData()
    
    if self.soilSystem then
        self.soilSystem.fieldData = nil
    end
    if self.settings then
        self.settings:save()
    end
    print("Soil & Fertilizer Mod: Shutting down")
end
