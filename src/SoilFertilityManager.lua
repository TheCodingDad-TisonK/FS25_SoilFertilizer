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
---@class SoilFertilityManager
SoilFertilityManager = {}
local SoilFertilityManager_mt = Class(SoilFertilityManager)

function SoilFertilityManager.new(mission, modDirectory, modName)
    local self = setmetatable({}, SoilFertilityManager_mt)
    
    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    
    self.settingsManager = SettingsManager.new()
    self.settings = Settings.new(self.settingsManager)
    
    self.soilSystem = SoilFertilitySystem.new(self.settings)
    
    if mission:getIsClient() and g_gui then
        self.settingsUI = SettingsUI.new(self.settings)
        
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
            self.settingsUI:inject()
        end)
        
        InGameMenuSettingsFrame.updateButtons = Utils.appendedFunction(InGameMenuSettingsFrame.updateButtons, function(frame)
            if self.settingsUI then
                self.settingsUI:ensureResetButton(frame)
            end
        end)
    end
    
    self.settingsGUI = SettingsGUI.new()
    self.settingsGUI:registerConsoleCommands()
    
    self.settings:load()
    
    return self
end

function SoilFertilityManager:onMissionLoaded()
    if self.soilSystem then
        self.soilSystem:initialize()
    end
    
    if self.settings.enabled and self.settings.showNotifications then
        if g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(
                "Soil & Fertilizer Mod Active - Type 'soilfertility' for commands",
                4000
            )
        end
    end
end

function SoilFertilityManager:update(dt)
    if self.soilSystem then
        self.soilSystem:update(dt)
    end
end

function SoilFertilityManager:delete()
    if self.settings then
        self.settings:save()
    end
    
    print("Soil & Fertilizer Mod: Shutting down")
end