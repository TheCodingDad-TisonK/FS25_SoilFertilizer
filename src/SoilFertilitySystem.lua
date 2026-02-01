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
---@class SoilFertilitySystem
SoilFertilitySystem = {}
local SoilFertilitySystem_mt = Class(SoilFertilitySystem)

function SoilFertilitySystem.new(settings)
    local self = setmetatable({}, SoilFertilitySystem_mt)
    self.settings = settings
    self.fieldData = {}
    self.lastUpdate = 0
    self.updateInterval = 30000 -- 30 seconds
    self.isInitialized = false
    
    return self
end

function SoilFertilitySystem:initialize()
    if self.isInitialized then
        return
    end
    
    -- Check for PF compatibility
    if self:checkPFCompatibility() then
        self.isInitialized = true
        self:log("Initialized in PF compatibility mode")
        return
    end
    
    -- Normal initialization
    if g_currentMission and g_currentMission.fieldGroundSystem then
        self:scanFields()
        
        -- FIX: Ensure fieldData is initialized even if scanFields fails
        if not self.fieldData or type(self.fieldData) ~= "table" then
            self.fieldData = {}
            self:log("Field data initialized as empty table")
        end
        
        self.isInitialized = true
        self:log("Soil Fertility System initialized successfully")
        self:log("Fertility System: %s, Nutrient Cycles: %s", 
            tostring(self.settings.fertilitySystem),
            tostring(self.settings.nutrientCycles))
        
        if self.settings.enabled and self.settings.showNotifications then
            self:showNotification("Soil & Fertilizer Mod Active", "Type 'soilfertility' for commands")
        end
    else
        self:log("WARNING: Could not initialize - fieldGroundSystem not available")
        self.fieldData = {}  -- FIX: Initialize empty to prevent nil errors
    end
end

function SoilFertilitySystem:log(msg, ...)
    if self.settings.debugMode then
        print(string.format("[Soil Mod] " .. msg, ...))
    end
end

function SoilFertilitySystem:showNotification(title, message)
    if not g_currentMission or not self.settings.showNotifications then
        return
    end
    
    if g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(message, 4000)
    end
    
    self:log("%s: %s", title, message)
end

-- Add this function to SoilFertilitySystem class
function SoilFertilitySystem:checkPFCompatibility()
    -- Check if Precision Farming is active
    if g_precisionFarming or _G["g_precisionFarming"] then
        self:log("WARNING: Precision Farming detected - running in compatibility mode")
        
        -- Auto-disable conflicting features
        if self.settings.fertilitySystem then
            self.settings.fertilitySystem = false
            self:log("Auto-disabled fertility system for PF compatibility")
        end
        
        if self.settings.nutrientCycles then
            self.settings.nutrientCycles = false
            self:log("Auto-disabled nutrient cycles for PF compatibility")
        end
        
        if self.settings.fertilizerCosts then
            self.settings.fertilizerCosts = false
            self:log("Auto-disabled fertilizer costs for PF compatibility")
        end
        
        self.settings:save()
        
        if self.settings.showNotifications then
            self:showNotification("PF Compatibility", 
                "Some features disabled for Precision Farming compatibility")
        end
        
        return true
    end
    
    return false
end

-- Modify the initialize function:
function SoilFertilitySystem:initialize()
    if self.isInitialized then
        return
    end
    
    -- Check for PF compatibility
    if self:checkPFCompatibility() then
        self.isInitialized = true
        self:log("Initialized in PF compatibility mode")
        return
    end
    
    -- Normal initialization
    if g_currentMission and g_currentMission.fieldGroundSystem then
        self:scanFields()
        self.isInitialized = true
        self:log("Soil Fertility System initialized successfully")
        self:log("Fertility System: %s, Nutrient Cycles: %s", 
            tostring(self.settings.fertilitySystem),
            tostring(self.settings.nutrientCycles))
        
        if self.settings.enabled and self.settings.showNotifications then
            self:showNotification("Soil & Fertilizer Mod Active", "Type 'soilfertility' for commands")
        end
    end
end

function SoilFertilitySystem:scanFields()
    if not g_currentMission or not g_currentMission.fieldGroundSystem then
        self.fieldData = {}
        self:log("WARNING: Could not scan fields - returning empty table")
        return
    end
    
    self.fieldData = {}
    local fieldCount = 0
    
    for _, field in pairs(g_currentMission.fieldGroundSystem.fields) do
        if field and field.fieldId then
            self.fieldData[field.fieldId] = {
                fieldId = field.fieldId,
                nitrogen = 80, -- Start with good nitrogen levels (0-100)
                phosphorus = 75,
                potassium = 70,
                organicMatter = 3.5, -- Percentage
                pH = 6.5, -- Neutral pH
                lastCrop = nil,
                lastHarvest = 0,
                fertilizerApplied = 0
            }
            fieldCount = fieldCount + 1
        end
    end
    
    self:log("Scanned %d fields for soil data", fieldCount)
end

function SoilFertilitySystem:updateFieldNutrients(fieldId, cropType, yieldMultiplier)
    if not self.fieldData[fieldId] or not self.settings.nutrientCycles then
        return
    end
    
    local field = self.fieldData[fieldId]
    
    -- Different crops extract different nutrients
    local nutrientExtraction = {
        nitrogen = 15, -- Base nutrient extraction
        phosphorus = 8,
        potassium = 12
    }
    
    -- Adjust based on yield
    nutrientExtraction.nitrogen = nutrientExtraction.nitrogen * yieldMultiplier
    nutrientExtraction.phosphorus = nutrientExtraction.phosphorus * yieldMultiplier
    nutrientExtraction.potassium = nutrientExtraction.potassium * yieldMultiplier
    
    -- Deplete nutrients
    field.nitrogen = math.max(0, field.nitrogen - nutrientExtraction.nitrogen)
    field.phosphorus = math.max(0, field.phosphorus - nutrientExtraction.phosphorus)
    field.potassium = math.max(0, field.potassium - nutrientExtraction.potassium)
    
    field.lastCrop = cropType
    field.lastHarvest = g_currentMission.environment.currentDay
    
    self:log("Field %d nutrients updated: N=%d, P=%d, K=%d", 
        fieldId, field.nitrogen, field.phosphorus, field.potassium)
    
    if self.settings.showNotifications and (field.nitrogen < 30 or field.phosphorus < 25 or field.potassium < 20) then
        self:showNotification("Low Soil Nutrients", 
            string.format("Field %d needs fertilization", fieldId))
    end
end

function SoilFertilitySystem:applyFertilizer(fieldId, fertilizerType, amount)
    if not self.fieldData[fieldId] then
        return
    end
    
    local field = self.fieldData[fieldId]
    local effectiveness = 1.0
    
    -- Different fertilizer types have different effects
    if fertilizerType == "LIQUID_FERTILIZER" then
        field.nitrogen = math.min(100, field.nitrogen + (30 * effectiveness))
        field.phosphorus = math.min(100, field.phosphorus + (15 * effectiveness))
        field.potassium = math.min(100, field.potassium + (20 * effectiveness))
    elseif fertilizerType == "SOLID_FERTILIZER" then
        field.nitrogen = math.min(100, field.nitrogen + (25 * effectiveness))
        field.phosphorus = math.min(100, field.phosphorus + (20 * effectiveness))
        field.potassium = math.min(100, field.potassium + (15 * effectiveness))
    elseif fertilizerType == "MANURE" then
        field.nitrogen = math.min(100, field.nitrogen + (15 * effectiveness))
        field.phosphorus = math.min(100, field.phosphorus + (25 * effectiveness))
        field.potassium = math.min(100, field.potassium + (10 * effectiveness))
        field.organicMatter = math.min(8.0, field.organicMatter + 0.5)
    end
    
    field.fertilizerApplied = field.fertilizerApplied + amount
    
    self:log("Fertilizer applied to field %d: %s, N=%d, P=%d, K=%d", 
        fieldId, fertilizerType, field.nitrogen, field.phosphorus, field.potassium)
    
    if self.settings.showNotifications then
        self:showNotification("Fertilizer Applied", 
            string.format("Field %d nutrient levels improved", fieldId))
    end
end

function SoilFertilitySystem:calculateFertilizerCost(fertilizerType, amount)
    if not self.settings.fertilizerCosts then
        return 0
    end
    
    local costPerLiter = 0
    
    if fertilizerType == "LIQUID_FERTILIZER" then
        costPerLiter = 2.5
    elseif fertilizerType == "SOLID_FERTILIZER" then
        costPerLiter = 1.8
    elseif fertilizerType == "MANURE" then
        costPerLiter = 0.8
    end
    
    -- Adjust cost based on difficulty
    if self.settings.difficulty == Settings.DIFFICULTY_HARD then
        costPerLiter = costPerLiter * 1.5
    elseif self.settings.difficulty == Settings.DIFFICULTY_EASY then
        costPerLiter = costPerLiter * 0.7
    end
    
    return amount * costPerLiter
end

function SoilFertilitySystem:getFieldInfo(fieldId)
    if not self.fieldData[fieldId] then
        return nil
    end
    
    local field = self.fieldData[fieldId]
    
    local nitrogenStatus = "Good"
    if field.nitrogen < 30 then nitrogenStatus = "Poor" 
    elseif field.nitrogen < 50 then nitrogenStatus = "Fair" end
    
    local phosphorusStatus = "Good"
    if field.phosphorus < 25 then phosphorusStatus = "Poor" 
    elseif field.phosphorus < 45 then phosphorusStatus = "Fair" end
    
    local potassiumStatus = "Good"
    if field.potassium < 20 then potassiumStatus = "Poor" 
    elseif field.potassium < 40 then potassiumStatus = "Fair" end
    
    return {
        nitrogen = {value = field.nitrogen, status = nitrogenStatus},
        phosphorus = {value = field.phosphorus, status = phosphorusStatus},
        potassium = {value = field.potassium, status = potassiumStatus},
        organicMatter = field.organicMatter,
        pH = field.pH,
        needsFertilization = field.nitrogen < 30 or field.phosphorus < 25 or field.potassium < 20
    }
end

function SoilFertilitySystem:update(dt)
    if not self.settings.enabled or not self.isInitialized then
        return
    end
    
    self.lastUpdate = self.lastUpdate + dt
    
    if self.lastUpdate >= self.updateInterval then
        self.lastUpdate = 0
        
        -- Natural nutrient replenishment over time
        -- FIX: Check if fieldData exists and is a table before iterating
        if self.settings.nutrientCycles and self.fieldData and type(self.fieldData) == "table" then
            for fieldId, field in pairs(self.fieldData) do
                if field and g_currentMission and g_currentMission.environment then
                    if g_currentMission.environment.currentDay - field.lastHarvest > 30 then
                        -- Natural recovery when fields are fallow
                        field.nitrogen = math.min(100, field.nitrogen + 0.5)
                        field.phosphorus = math.min(100, field.phosphorus + 0.3)
                        field.potassium = math.min(100, field.potassium + 0.4)
                    end
                end
            end
        end
    end
end

function SoilFertilitySystem:saveState()
    return {
        fieldData = self.fieldData,
        lastUpdate = self.lastUpdate
    }
end

function SoilFertilitySystem:loadState(state)
    if state then
        self.fieldData = state.fieldData or {}
        self.lastUpdate = state.lastUpdate or 0
    end
end
