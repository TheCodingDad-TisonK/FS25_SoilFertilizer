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
---@class Settings

Settings = {}
local Settings_mt = Class(Settings)

Settings.DIFFICULTY_EASY = 1
Settings.DIFFICULTY_NORMAL = 2
Settings.DIFFICULTY_HARD = 3

function Settings.new(manager)
    local self = setmetatable({}, Settings_mt)
    self.manager = manager
    
    self:resetToDefaults(false)
    
    Logging.info("Soil & Fertilizer Mod: Settings initialized")
    
    return self
end

---@param difficulty number 
function Settings:setDifficulty(difficulty)
    if difficulty >= Settings.DIFFICULTY_EASY and difficulty <= Settings.DIFFICULTY_HARD then
        self.difficulty = difficulty
        
        local difficultyName = "Normal"
        if difficulty == Settings.DIFFICULTY_EASY then
            difficultyName = "Simple"
        elseif difficulty == Settings.DIFFICULTY_HARD then
            difficultyName = "Hardcore"
        end
        
        Logging.info("Soil Mod: Difficulty changed to: %s", difficultyName)
    end
end

---@return string 
function Settings:getDifficultyName()
    if self.difficulty == Settings.DIFFICULTY_EASY then
        return "Simple"
    elseif self.difficulty == Settings.DIFFICULTY_HARD then
        return "Hardcore"
    else
        return "Realistic"
    end
end

function Settings:load()
    if type(self.difficulty) ~= "number" then
        Logging.warning("Soil Mod: difficulty is not a number! Type: %s, Value: %s", 
            type(self.difficulty), tostring(self.difficulty))
        self.difficulty = Settings.DIFFICULTY_NORMAL 
    end
    
    self.manager:loadSettings(self)
    
    self:validateSettings()
    
    Logging.info("Soil Mod: Settings Loaded. Enabled: %s, Difficulty: %s", 
        tostring(self.enabled), self:getDifficultyName())
end

function Settings:validateSettings()
    if self.difficulty < Settings.DIFFICULTY_EASY or self.difficulty > Settings.DIFFICULTY_HARD then
        Logging.warning("Soil Mod: Invalid difficulty value %d, resetting to Normal", self.difficulty)
        self.difficulty = Settings.DIFFICULTY_NORMAL
    end
    
    self.enabled = not not self.enabled 
    self.debugMode = not not self.debugMode
    self.fertilitySystem = not not self.fertilitySystem
    self.nutrientCycles = not not self.nutrientCycles
    self.fertilizerCosts = not not self.fertilizerCosts
    self.showNotifications = not not self.showNotifications
    -- NEW SETTINGS
    self.seasonalEffects = not not self.seasonalEffects
    self.rainEffects = not not self.rainEffects
    self.plowingBonus = not not self.plowingBonus
end

function Settings:save()
    if type(self.difficulty) ~= "number" then
        Logging.warning("Soil Mod: difficulty is not a number! Type: %s, Value: %s", 
            type(self.difficulty), tostring(self.difficulty))
        self.difficulty = Settings.DIFFICULTY_NORMAL
    end
    
    self.manager:saveSettings(self)
    Logging.info("Soil Mod: Settings Saved. Difficulty: %s", self:getDifficultyName())
end

---@param saveImmediately boolean
function Settings:resetToDefaults(saveImmediately)
    saveImmediately = saveImmediately ~= false
    
    self.difficulty = Settings.DIFFICULTY_NORMAL
    self.enabled = true
    self.debugMode = false
    self.fertilitySystem = true
    self.nutrientCycles = true
    self.fertilizerCosts = true
    self.showNotifications = true
    -- NEW SETTINGS DEFAULT VALUES
    self.seasonalEffects = true
    self.rainEffects = true
    self.plowingBonus = true
    
    if saveImmediately then
        self:save()
        print("Soil Mod: Settings reset to defaults")
    end
end