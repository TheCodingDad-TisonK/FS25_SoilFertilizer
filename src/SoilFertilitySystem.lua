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
    self.PFActive = false
    return self
end

-- Initialize system
function SoilFertilitySystem:initialize()
    if self.isInitialized then return end

    self:checkPFCompatibility()

    if g_farmlandManager then
        self:scanFields()
        self.isInitialized = true
        self:log("Soil Fertility System initialized successfully")
        self:log("Fertility System: %s, Nutrient Cycles: %s",
            tostring(self.settings.fertilitySystem),
            tostring(self.settings.nutrientCycles))

        if self.settings.enabled and self.settings.showNotifications then
            self:showNotification("Soil & Fertilizer Mod Active", "Type 'soilfertility' for commands")
        end
    else
        self.isInitialized = true
        self:log("WARNING: FarmlandManager not available - running in limited mode")
    end
end

-- Logging helper
function SoilFertilitySystem:log(msg, ...)
    if self.settings.debugMode then
        print(string.format("[Soil Mod] " .. msg, ...))
    end
end

-- Notification helper
function SoilFertilitySystem:showNotification(title, message)
    if not g_currentMission or not self.settings.showNotifications then return end
    if g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(message, 4000)
    end
    self:log("%s: %s", title, message)
end

-- Check PF compatibility (read-only mode)
function SoilFertilitySystem:checkPFCompatibility()
    if g_precisionFarming or _G["g_precisionFarming"] then
        self.PFActive = true
        self:log("PF detected - running in read-only mode")

        if g_currentMission and g_currentMission.hud and self.settings.showNotifications then
            g_currentMission.hud:showBlinkingWarning(
                "Precision Farming detected - Mod running in read-only mode (settings wont be changed)",
                5000
            )
        end

        return true
    end
    self.PFActive = false
    return false
end


-- Scan all fields
function SoilFertilitySystem:scanFields()
    if not g_farmlandManager or not g_farmlandManager.farmlands then
        self:log("WARNING: FarmlandManager unavailable or empty")
        return
    end

    local fieldCount = 0
    for id, field in pairs(g_farmlandManager.farmlands) do
        if field and not self.fieldData[id] then
            self.fieldData[id] = {
                fieldId = id,
                nitrogen = 80,
                phosphorus = 75,
                potassium = 70,
                organicMatter = 3.5,
                pH = 6.5,
                lastCrop = nil,
                lastHarvest = 0,
                fertilizerApplied = 0
            }
            fieldCount = fieldCount + 1
        end
    end
    self:log("Scanned %d farmlands for soil data", fieldCount)
end

-- Lazy getter
function SoilFertilitySystem:getOrCreateField(fieldId)
    if not self.fieldData[fieldId] then
        self:scanFields()
        if not self.fieldData[fieldId] then
            self:log("WARNING: Field %d not found", fieldId)
            return nil
        end
    end
    return self.fieldData[fieldId]
end

-- Update loop
function SoilFertilitySystem:update(dt)
    if not self.settings.enabled or not self.isInitialized then return end
    self.lastUpdate = self.lastUpdate + dt

    if self.lastUpdate >= self.updateInterval then
        self.lastUpdate = 0

        if self.settings.nutrientCycles and not self.PFActive then
            for fieldId, field in pairs(self.fieldData) do
                local farmland = g_farmlandManager.farmlands[fieldId]
                if field and farmland and g_currentMission and g_currentMission.environment then
                    if g_currentMission.environment.currentDay - field.lastHarvest > 30 then
                        -- Natural nutrient recovery for fallow fields
                        field.nitrogen = math.min(100, field.nitrogen + 0.5)
                        field.phosphorus = math.min(100, field.phosphorus + 0.3)
                        field.potassium = math.min(100, field.potassium + 0.4)
                    end
                end
            end
        end
    end
end

-- Update nutrients after harvest
function SoilFertilitySystem:updateFieldNutrients(fieldId, cropType, yieldMultiplier)
    if self.PFActive then
        self:log("PF active - skipping nutrient update for field %d", fieldId)
        return
    end

    local field = self:getOrCreateField(fieldId)
    if not field or not self.settings.nutrientCycles then return end

    local extraction = { nitrogen = 15, phosphorus = 8, potassium = 12 }
    extraction.nitrogen = extraction.nitrogen * yieldMultiplier
    extraction.phosphorus = extraction.phosphorus * yieldMultiplier
    extraction.potassium = extraction.potassium * yieldMultiplier

    field.nitrogen = math.max(0, field.nitrogen - extraction.nitrogen)
    field.phosphorus = math.max(0, field.phosphorus - extraction.phosphorus)
    field.potassium = math.max(0, field.potassium - extraction.potassium)

    field.lastCrop = cropType
    field.lastHarvest = g_currentMission.environment.currentDay

    self:log("Field %d nutrients updated: N=%d, P=%d, K=%d",
        fieldId, field.nitrogen, field.phosphorus, field.potassium)

    if self.settings.showNotifications and (field.nitrogen < 30 or field.phosphorus < 25 or field.potassium < 20) then
        self:showNotification("Low Soil Nutrients", string.format("Field %d needs fertilization", fieldId))
    end
end

-- Apply fertilizer
function SoilFertilitySystem:applyFertilizer(fieldId, fertilizerType, amount)
    if self.PFActive then
        self:log("PF active - skipping fertilizer application for field %d", fieldId)
        return
    end

    local field = self:getOrCreateField(fieldId)
    if not field then return end

    local effectiveness = 1.0
    if fertilizerType == "LIQUID_FERTILIZER" then
        field.nitrogen = math.min(100, field.nitrogen + 30 * effectiveness)
        field.phosphorus = math.min(100, field.phosphorus + 15 * effectiveness)
        field.potassium = math.min(100, field.potassium + 20 * effectiveness)
    elseif fertilizerType == "SOLID_FERTILIZER" then
        field.nitrogen = math.min(100, field.nitrogen + 25 * effectiveness)
        field.phosphorus = math.min(100, field.phosphorus + 20 * effectiveness)
        field.potassium = math.min(100, field.potassium + 15 * effectiveness)
    elseif fertilizerType == "MANURE" then
        field.nitrogen = math.min(100, field.nitrogen + 15 * effectiveness)
        field.phosphorus = math.min(100, field.phosphorus + 25 * effectiveness)
        field.potassium = math.min(100, field.potassium + 10 * effectiveness)
        field.organicMatter = math.min(8.0, field.organicMatter + 0.5)
    end

    field.fertilizerApplied = field.fertilizerApplied + amount

    self:log("Fertilizer applied to field %d: %s, N=%d, P=%d, K=%d",
        fieldId, fertilizerType, field.nitrogen, field.phosphorus, field.potassium)

    if self.settings.showNotifications then
        self:showNotification("Fertilizer Applied", string.format("Field %d nutrient levels improved", fieldId))
    end
end

-- Calculate fertilizer cost
function SoilFertilitySystem:calculateFertilizerCost(fertilizerType, amount)
    if not self.settings.fertilizerCosts then return 0 end
    local costPerLiter = 0
    if fertilizerType == "LIQUID_FERTILIZER" then costPerLiter = 2.5
    elseif fertilizerType == "SOLID_FERTILIZER" then costPerLiter = 1.8
    elseif fertilizerType == "MANURE" then costPerLiter = 0.8 end

    if self.settings.difficulty == Settings.DIFFICULTY_HARD then
        costPerLiter = costPerLiter * 1.5
    elseif self.settings.difficulty == Settings.DIFFICULTY_EASY then
        costPerLiter = costPerLiter * 0.7
    end

    return amount * costPerLiter
end

-- Get field info
function SoilFertilitySystem:getFieldInfo(fieldId)
    local field = self:getOrCreateField(fieldId)
    if not field then return nil end

    local function nutrientStatus(value, poor, fair)
        if value < poor then return "Poor"
        elseif value < fair then return "Fair"
        else return "Good" end
    end

    return {
        nitrogen = { value = field.nitrogen, status = nutrientStatus(field.nitrogen, 30, 50) },
        phosphorus = { value = field.phosphorus, status = nutrientStatus(field.phosphorus, 25, 45) },
        potassium = { value = field.potassium, status = nutrientStatus(field.potassium, 20, 40) },
        organicMatter = field.organicMatter,
        pH = field.pH,
        needsFertilization = field.nitrogen < 30 or field.phosphorus < 25 or field.potassium < 20
    }
end

-- Save/load state
function SoilFertilitySystem:saveState()
    return { fieldData = self.fieldData, lastUpdate = self.lastUpdate }
end

function SoilFertilitySystem:loadState(state)
    if not state then return end
    if state.fieldData then self.fieldData = state.fieldData end
    if state.lastUpdate then self.lastUpdate = state.lastUpdate end
end


