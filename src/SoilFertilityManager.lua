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
---@class SoilFertilityManager
SoilFertilityManager = {}
local SoilFertilityManager_mt = Class(SoilFertilityManager)

function SoilFertilityManager.new(mission, modDirectory, modName, disableGUI)
    local self = setmetatable({}, SoilFertilityManager_mt)
    
    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    self.disableGUI = disableGUI or false
    
    self.settingsManager = SettingsManager.new()
    self.settings = Settings.new(self.settingsManager)
    
    self.soilSystem = SoilFertilitySystem.new(self.settings)
    
    -- Check if we should initialize GUI
    local shouldInitializeGUI = not self.disableGUI and 
                               mission:getIsClient() and 
                               g_gui and 
                               not g_safeMode
    
    -- Only create GUI elements if not disabled and client
    if shouldInitializeGUI then
        print("Soil Mod: Initializing GUI elements...")
        self.settingsUI = SettingsUI.new(self.settings)
        
        -- Hook into settings frame with safe error handling
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
            InGameMenuSettingsFrame.onFrameOpen, 
            function(frame)
                if self.settingsUI and not self.settingsUI.injected then
                    local success = pcall(function() 
                        return self.settingsUI:inject() 
                    end)
                    
                    if not success then
                        print("Soil Mod: GUI injection failed - switching to console-only mode")
                        self.settingsUI.injected = true 
                        self.disableGUI = true
                    end
                end
                
                -- Always try to add reset button
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
    
    -- Console commands always available
    self.settingsGUI = SettingsGUI.new()
    self.settingsGUI:registerConsoleCommands()
    
    -- Load settings
    self.settings:load()
    
    -- Auto-disable certain features if Precision Farming detected
    self:checkAndApplyCompatibility()
    
    return self
end

-- Add this new method to the class
function SoilFertilityManager:checkAndApplyCompatibility()
    -- Check for Precision Farming
    if g_precisionFarming or _G["g_precisionFarming"] then
        print("Soil Mod: Precision Farming detected - adjusting settings for compatibility")
        
        if self.settings.fertilitySystem then
            self.settings.fertilitySystem = false
            print("Soil Mod: Auto-disabled fertility system for PF compatibility")
        end
        
        if self.settings.nutrientCycles then
            self.settings.nutrientCycles = false
            print("Soil Mod: Auto-disabled nutrient cycles for PF compatibility")
        end
        
        if self.settings.fertilizerCosts then
            self.settings.fertilizerCosts = false
            print("Soil Mod: Auto-disabled fertilizer costs for PF compatibility")
        end
        
        self.settings:save()
    end
    
    -- Check for Used Tyres mod
    local hasUsedTyres = false
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("tyre") or lowerName:find("tire") or 
               lowerName:find("used") then
                hasUsedTyres = true
                break
            end
        end
    end
    
    if hasUsedTyres then
        print("Soil Mod: Used Tyres mod detected - enabling UI compatibility mode")
        if self.settingsUI then
            self.settingsUI.compatibilityMode = true
        end
    end
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
