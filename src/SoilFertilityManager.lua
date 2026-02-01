-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.0.5)
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
    
    -- Only initialize GUI if we're a client and not in safe mode
    if mission:getIsClient() and g_gui and not g_safeMode then
        self.settingsUI = SettingsUI.new(self.settings)
        
        -- Use a safer injection method
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
            InGameMenuSettingsFrame.onFrameOpen, 
            function(frame)
                if self.settingsUI and not self.settingsUI.injected then
                    local success = pcall(function() 
                        return self.settingsUI:inject() 
                    end)
                    
                    if not success then
                        print("Soil Mod: GUI injection failed - switching to console-only mode")
                        self.settingsUI.injected = true  -- Mark as injected to prevent retries
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
    end
    
    self.settingsGUI = SettingsGUI.new()
    self.settingsGUI:registerConsoleCommands()
    
    self.settings:load()
    
    return self
end

function SoilFertilityManager:onMissionLoaded()
    if self.settings.enabled then
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
            print("Soil Mod: Disabling to prevent game crashes")
            self.settings.enabled = false
            self.settings:save()
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
