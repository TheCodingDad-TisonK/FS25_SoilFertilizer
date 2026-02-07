-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FarmlandManager version)
-- =========================================================
-- Author: TisonK (adapted for FarmlandManager)
-- Updated with complete real hooks for harvest, fertilizer, and soil events
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
    self.hooksInstalled = false
    self.lastUpdateDay = 0
    return self
end

-- Initialize system with ALL real hooks
function SoilFertilitySystem:initialize()
    if self.isInitialized then return end
    
    print("[Soil Mod] Initializing Soil Fertility System...")
    
    self:checkPFCompatibility()
    
    -- Scan fields using real FieldManager
    if g_fieldManager then
        self:scanFields()
    else
        print("[Soil Mod] WARNING: FieldManager not available - will try delayed initialization")
    end
    
    -- Install ALL real hooks
    self:installAllHooks()
    
    self.isInitialized = true
    self:log("Soil Fertility System initialized successfully with all real hooks")
    self:log("Fertility System: %s, Nutrient Cycles: %s",
        tostring(self.settings.fertilitySystem),
        tostring(self.settings.nutrientCycles))
    
    -- Show notification
    if self.settings.enabled and self.settings.showNotifications then
        self:showNotification("Soil & Fertilizer Mod Active", "Real soil system with full event hooks")
    end
end

-- Install ALL real event hooks
function SoilFertilitySystem:installAllHooks()
    if self.hooksInstalled then return end
    
    print("[Soil Mod] Installing real event hooks...")
    
    -- Hook 1: Harvest events (FruitUtil)
    if FruitUtil then
        if FruitUtil.fruitPickupEvent then
            FruitUtil.fruitPickupEvent = Utils.appendedFunction(
                FruitUtil.fruitPickupEvent,
                function(fruitTypeIndex, x, z, fieldId, liters)
                    if g_SoilFertilityManager and 
                       g_SoilFertilityManager.soilSystem and
                       g_SoilFertilityManager.settings.enabled and
                       g_SoilFertilityManager.settings.nutrientCycles and
                       fieldId and fieldId > 0 then
                        
                        g_SoilFertilityManager.soilSystem:updateFieldNutrients(fieldId, fruitTypeIndex, liters)
                        
                        if g_SoilFertilityManager.settings.debugMode then
                            print(string.format("[Soil Mod] Harvest detected: Field %d, Crop Index %d, %.0fL", 
                                fieldId, fruitTypeIndex, liters))
                        end
                    end
                end
            )
            print("[Soil Mod] ✓ Harvest hook installed")
        end
    end
    
    -- Hook 2: Fertilizer application (Sprayer system)
    if Sprayer then
        -- Store original spray function
        local originalSpray = Sprayer.spray
        
        Sprayer.spray = function(self, fillTypeIndex, liters, fieldId, ...)
            -- Call original function first
            local result = originalSpray(self, fillTypeIndex, liters, fieldId, ...)
            
            -- Then process soil effects if applicable
            if g_SoilFertilityManager and 
               g_SoilFertilityManager.soilSystem and
               g_SoilFertilityManager.settings.enabled and
               fieldId and fieldId > 0 and
               liters and liters > 0 then
                
                local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                if fillType then
                    local fillTypeName = fillType.name
                    local isFertilizer = (
                        fillTypeName == "LIQUIDFERTILIZER" or
                        fillTypeName == "FERTILIZER" or
                        fillTypeName == "MANURE" or
                        fillTypeName == "SLURRY" or
                        fillTypeName == "DIGESTATE" or
                        fillTypeName == "LIME"
                    )
                    
                    if isFertilizer then
                        g_SoilFertilityManager.soilSystem:applyFertilizer(fieldId, fillTypeIndex, liters)
                        
                        if g_SoilFertilityManager.settings.debugMode then
                            print(string.format("[Soil Mod] Fertilizer applied: Field %d, %s, %.0fL", 
                                fieldId, fillTypeName, liters))
                        end
                    end
                end
            end
            
            return result
        end
        print("[Soil Mod] ✓ Fertilizer hook installed")
    end
    
    -- Hook 3: Field ownership changes
    if g_farmlandManager then
        g_farmlandManager.fieldOwnershipChanged = Utils.appendedFunction(
            g_farmlandManager.fieldOwnershipChanged,
            function(fieldId, farmlandId, farmId)
                if g_SoilFertilityManager and 
                   g_SoilFertilityManager.soilSystem and
                   g_SoilFertilityManager.settings.enabled then
                    
                    -- Initialize field data for new owner
                    local field = g_SoilFertilityManager.soilSystem:getOrCreateField(fieldId, true)
                    if field and not field.initialized then
                        -- Set default values for newly owned field
                        field.nitrogen = 50
                        field.phosphorus = 40
                        field.potassium = 45
                        field.organicMatter = 3.5
                        field.pH = 6.5
                        field.initialized = true
                        
                        print(string.format("[Soil Mod] Field %d initialized for new owner", fieldId))
                    end
                end
            end
        )
        print("[Soil Mod] ✓ Field ownership hook installed")
    end
    
    -- Hook 4: Weather effects on soil
    if g_currentMission and g_currentMission.environment then
        local originalUpdate = g_currentMission.environment.update
        if originalUpdate then
            g_currentMission.environment.update = function(self, dt, ...)
                local result = originalUpdate(self, dt, ...)
                
                if g_SoilFertilityManager and 
                   g_SoilFertilityManager.soilSystem and
                   g_SoilFertilityManager.settings.enabled and
                   g_SoilFertilityManager.settings.nutrientCycles then
                    
                    -- Daily soil updates
                    local currentDay = self.currentDay
                    if currentDay ~= g_SoilFertilityManager.soilSystem.lastUpdateDay then
                        g_SoilFertilityManager.soilSystem.lastUpdateDay = currentDay
                        g_SoilFertilityManager.soilSystem:updateDailySoil()
                    end
                    
                    -- Rain effects
                    if self.rainScale and self.rainScale > 0.1 then
                        -- Rain can leach nutrients
                        g_SoilFertilityManager.soilSystem:applyRainEffects(dt, self.rainScale)
                    end
                end
                
                return result
            end
            print("[Soil Mod] ✓ Weather hook installed")
        end
    end
    
    self.hooksInstalled = true
    print("[Soil Mod] All real hooks successfully installed")
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
                "Precision Farming detected - Mod running in read-only mode",
                5000
            )
        end
        
        return true
    end
    self.PFActive = false
    return false
end

-- Scan fields using real FieldManager - FIXED VERSION
function SoilFertilitySystem:scanFields()
    if not g_fieldManager or not g_fieldManager.fields then
        self:log("WARNING: FieldManager unavailable")
        return
    end
    
    local fieldCount = 0
    for _, field in ipairs(g_fieldManager.fields) do
        local fieldId = field.fieldId
        if fieldId ~= nil and self.fieldData[fieldId] == nil then
            self.fieldData[fieldId] = {
                nitrogen = 50 + math.random(-10, 10),  -- Random initial values
                phosphorus = 40 + math.random(-10, 10),
                potassium = 45 + math.random(-10, 10),
                organicMatter = 3.5 + math.random() * 2,
                pH = 6.5 + math.random() - 0.5,
                lastCrop = nil,
                lastHarvest = g_currentMission and g_currentMission.environment.currentDay or 0,
                fertilizerApplied = 0,
                lastPlowed = 0,
                initialized = true
            }
            fieldCount = fieldCount + 1
        end
    end
    
    self:log("Scanned %d fields for soil data", fieldCount)
end

-- Lazy getter with real field validation - FIXED VERSION
function SoilFertilitySystem:getOrCreateField(fieldId, forceCreate)
    if fieldId == nil or fieldId <= 0 then 
        self:log("Invalid field ID: %s", tostring(fieldId))
        return nil 
    end
    
    -- PF ACTIVE → READ FROM PF
    if self.PFActive then
        local pfData = self:readPFFieldData(fieldId)
        if pfData then
            self:log("Using PF data for field %d", fieldId)
            return {
                nitrogen = pfData.nitrogen,
                phosphorus = pfData.phosphorus,
                potassium = pfData.potassium,
                organicMatter = pfData.organicMatter,
                pH = pfData.pH,
                lastCrop = "PF",
                lastHarvest = g_currentMission.environment.currentDay,
                fertilizerApplied = 0,
                initialized = true
            }
        end
        self:log("No PF data for field %d", fieldId)
    end
    
    -- NON-PF MODE → CHECK OUR DATA
    if self.fieldData[fieldId] then
        self:log("Returning existing data for field %d", fieldId)
        return self.fieldData[fieldId]
    end
    
    -- Check if field exists in real FieldManager
    local fieldExists = false
    local fieldName = "Unknown"
    
    if g_fieldManager and g_fieldManager.fields then
        for _, field in ipairs(g_fieldManager.fields) do
            if field.fieldId == fieldId then
                fieldExists = true
                if field.name then
                    fieldName = field.name
                end
                break
            end
        end
    end
    
    -- Also check farmlands
    if not fieldExists and g_farmlandManager and g_farmlandManager.farmlands then
        for _, farmland in ipairs(g_farmlandManager.farmlands) do
            if farmland.fieldId == fieldId then
                fieldExists = true
                break
            end
        end
    end
    
    if fieldExists or forceCreate then
        self:log("Creating new soil data for field %d (%s)", fieldId, fieldName)
        self.fieldData[fieldId] = {
            nitrogen = 50,
            phosphorus = 40,
            potassium = 45,
            organicMatter = 3.5,
            pH = 6.5,
            lastCrop = nil,
            lastHarvest = g_currentMission and g_currentMission.environment.currentDay or 0,
            fertilizerApplied = 0,
            lastPlowed = 0,
            initialized = true,
            fieldName = fieldName
        }
        return self.fieldData[fieldId]
    else
        self:log("Field %d does not exist in FieldManager or FarmlandManager", fieldId)
        return nil
    end
end

-- Daily soil updates
function SoilFertilitySystem:updateDailySoil()
    if not self.settings.nutrientCycles or self.PFActive then return end
    
    local currentDay = g_currentMission.environment.currentDay
    local season = g_currentMission.environment.season
    
    for fieldId, field in pairs(self.fieldData) do
        if field then
            -- Natural nutrient changes based on season (if seasonal effects enabled)
            local seasonFactor = 1.0
            if self.settings.seasonalEffects then
                if season == 1 then seasonFactor = 1.2 end -- Spring: faster nutrient release
                if season == 3 then seasonFactor = 0.8 end -- Fall: slower changes
            end
            
            -- Temperature effects
            local temp = g_currentMission.environment.currentTemperature or 15
            local tempFactor = 0.5 + (temp / 30)  -- 0.5 at 0°C, 1.0 at 15°C, 1.5 at 30°C
            
            -- Daily nutrient changes
            field.nitrogen = math.max(0, math.min(100, field.nitrogen + 
                (0.05 * seasonFactor * tempFactor) -  -- Natural release
                (0.02 * (field.organicMatter / 5))   -- Plant uptake
            ))
            
            field.phosphorus = math.max(0, math.min(100, field.phosphorus + 
                (0.03 * seasonFactor) -  -- Slow release
                (0.01 * (field.organicMatter / 5))
            ))
            
            field.potassium = math.max(0, math.min(100, field.potassium + 
                (0.04 * seasonFactor * tempFactor) -
                (0.015 * (field.organicMatter / 5))
            ))
            
            -- Organic matter decomposition
            if temp > 5 then  -- Only decompose above 5°C
                field.organicMatter = math.max(0.5, field.organicMatter - 
                    (0.001 * tempFactor * seasonFactor)
                )
            end
            
            -- pH slowly neutralizes
            if field.pH < 6.0 then
                field.pH = field.pH + 0.001
            elseif field.pH > 7.5 then
                field.pH = field.pH - 0.001
            end
            
            -- Plowing bonus (if enabled)
            if self.settings.plowingBonus and field.lastPlowed then
                local daysSincePlowed = currentDay - field.lastPlowed
                if daysSincePlowed <= 7 then  -- Plowing benefits last 7 days
                    local plowBonus = 1.0 - (daysSincePlowed / 7)  -- Fades over time
                    field.nitrogen = math.min(100, field.nitrogen + (0.1 * plowBonus))
                    field.organicMatter = math.min(10, field.organicMatter + (0.01 * plowBonus))
                end
            end
        end
    end
    
    self:log("Daily soil update complete (Day %d, Season %d)", currentDay, season)
end

-- Rain effects on soil
function SoilFertilitySystem:applyRainEffects(dt, rainIntensity)
    if not self.settings.nutrientCycles or self.PFActive or not self.settings.rainEffects then return end
    
    local rainFactor = rainIntensity * dt / 1000
    
    for fieldId, field in pairs(self.fieldData) do
        if field then
            -- Rain leaches nitrogen
            field.nitrogen = math.max(0, field.nitrogen - (0.5 * rainFactor))
            
            -- Rain improves potassium availability
            field.potassium = math.min(100, field.potassium + (0.1 * rainFactor))
            
            -- Heavy rain can lower pH slightly
            if rainIntensity > 0.5 then
                field.pH = math.max(4.0, field.pH - (0.005 * rainFactor))
            end
        end
    end
end

-- Update loop - FIXED to ensure fields are initialized
function SoilFertilitySystem:update(dt)
    if not self.settings.enabled or not self.isInitialized then return end
    
    self.lastUpdate = self.lastUpdate + dt
    
    -- Periodic updates every 30 seconds
    if self.lastUpdate >= self.updateInterval then
        self.lastUpdate = 0
        
        -- Scan for new fields on first few updates
        if not self.initialScanComplete then
            self:scanFields()
            self.initialScanComplete = true
        end
        
        -- Check for new fields
        if g_fieldManager and g_fieldManager.fields then
            for _, field in ipairs(g_fieldManager.fields) do
                local fieldId = field.fieldId
                if fieldId and not self.fieldData[fieldId] then
                    -- Initialize any missing fields
                    self:getOrCreateField(fieldId, true)
                end
            end
        end
        
        -- Natural nutrient recovery for fallow fields
        if self.settings.nutrientCycles and not self.PFActive then
            for fieldId, field in pairs(self.fieldData) do
                if field and g_currentMission and g_currentMission.environment then
                    if g_currentMission.environment.currentDay - field.lastHarvest > 30 then
                        -- Natural nutrient recovery for fallow fields
                        field.nitrogen = math.min(100, field.nitrogen + 0.5)
                        field.phosphorus = math.min(100, field.phosphorus + 0.3)
                        field.potassium = math.min(100, field.potassium + 0.4)
                    end
                end
            end
        end
        
        -- Check for low nutrient warnings
        if self.settings.showNotifications then
            self:checkLowNutrientWarnings()
        end
    end
end

-- Check for fields with low nutrients
function SoilFertilitySystem:checkLowNutrientWarnings()
    local lowNutrientFields = {}
    
    for fieldId, field in pairs(self.fieldData) do
        if field and field.initialized then
            local needsAttention = false
            local message = ""
            
            if field.nitrogen < 20 then
                needsAttention = true
                message = message .. string.format("N:%d ", math.floor(field.nitrogen))
            end
            if field.phosphorus < 15 then
                needsAttention = true
                message = message .. string.format("P:%d ", math.floor(field.phosphorus))
            end
            if field.potassium < 15 then
                needsAttention = true
                message = message .. string.format("K:%d ", math.floor(field.potassium))
            end
            if field.pH < 5.0 or field.pH > 8.0 then
                needsAttention = true
                message = message .. string.format("pH:%.1f ", field.pH)
            end
            
            if needsAttention then
                table.insert(lowNutrientFields, {
                    fieldId = fieldId,
                    message = message
                })
            end
        end
    end
    
    -- Show warning if any fields need attention
    if #lowNutrientFields > 0 and g_currentMission and g_currentMission.hud then
        local warning = string.format("%d fields need attention: ", #lowNutrientFields)
        for i, field in ipairs(lowNutrientFields) do
            if i <= 3 then  -- Limit to 3 fields in notification
                warning = warning .. string.format("F%d(%s) ", field.fieldId, field.message)
            end
        end
        if #lowNutrientFields > 3 then
            warning = warning .. "..."
        end
        
        g_currentMission.hud:showBlinkingWarning(warning, 5000)
    end
end

-- Save/load XML
function SoilFertilitySystem:saveToXMLFile(xmlFile, baseKey)
    local key = baseKey .. ".soilFertility"
    local i = 0
    for fieldId, data in pairs(self.fieldData) do
        local fieldKey = string.format("%s.field(%d)", key, i)
        setXMLInt(xmlFile, fieldKey .. "#id", fieldId)
        setXMLFloat(xmlFile, fieldKey .. "#nitrogen", data.nitrogen)
        setXMLFloat(xmlFile, fieldKey .. "#phosphorus", data.phosphorus)
        setXMLFloat(xmlFile, fieldKey .. "#potassium", data.potassium)
        setXMLFloat(xmlFile, fieldKey .. "#organicMatter", data.organicMatter)
        setXMLFloat(xmlFile, fieldKey .. "#pH", data.pH)
        setXMLInt(xmlFile, fieldKey .. "#lastHarvest", data.lastHarvest)
        setXMLInt(xmlFile, fieldKey .. "#lastPlowed", data.lastPlowed or 0)
        setXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied", data.fertilizerApplied)
        setXMLBool(xmlFile, fieldKey .. "#initialized", data.initialized or false)
        i = i + 1
    end
end

function SoilFertilitySystem:loadFromXMLFile(xmlFile, baseKey)
    local key = baseKey .. ".soilFertility"
    self.fieldData = {}
    
    local i = 0
    while true do
        local fieldKey = string.format("%s.field(%d)", key, i)
        if not hasXMLProperty(xmlFile, fieldKey) then break end
        
        local fieldId = getXMLInt(xmlFile, fieldKey .. "#id")
        if fieldId ~= nil then
            self.fieldData[fieldId] = {
                nitrogen = getXMLFloat(xmlFile, fieldKey .. "#nitrogen") or 50,
                phosphorus = getXMLFloat(xmlFile, fieldKey .. "#phosphorus") or 40,
                potassium = getXMLFloat(xmlFile, fieldKey .. "#potassium") or 45,
                organicMatter = getXMLFloat(xmlFile, fieldKey .. "#organicMatter") or 3.5,
                pH = getXMLFloat(xmlFile, fieldKey .. "#pH") or 6.5,
                lastHarvest = getXMLInt(xmlFile, fieldKey .. "#lastHarvest") or 0,
                lastPlowed = getXMLInt(xmlFile, fieldKey .. "#lastPlowed") or 0,
                fertilizerApplied = getXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied") or 0,
                initialized = getXMLBool(xmlFile, fieldKey .. "#initialized") or true,
                lastCrop = nil
            }
        end
        
        i = i + 1
    end
end

-- Update nutrients after harvest
function SoilFertilitySystem:updateFieldNutrients(fieldId, fruitTypeIndex, harvestedLiters)
    if self.PFActive or not self.settings.nutrientCycles then return end
    
    local field = self:getOrCreateField(fieldId, true)
    if field == nil then 
        self:log("Cannot update nutrients - field %d not found", fieldId)
        return 
    end
    
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if fruitDesc == nil then 
        self:log("Cannot update nutrients - fruit type %d not found", fruitTypeIndex)
        return 
    end
    
    -- Base nutrient removal per 1,000 liters (approx agronomic values)
    local cropExtraction = {
        wheat  = { N=2.3, P=1.0, K=1.8 },
        barley = { N=2.1, P=0.9, K=1.7 },
        maize  = { N=2.8, P=1.2, K=2.4 },
        canola = { N=3.2, P=1.4, K=2.6 },
        soybean= { N=3.8, P=1.6, K=2.0 },
        sunflower= { N=3.0, P=1.3, K=2.8 },
        potato = { N=4.5, P=2.0, K=6.5 },
        sugarbeet= { N=4.0, P=1.8, K=7.0 },
        oats = { N=2.2, P=1.1, K=1.9 },
        rye = { N=2.4, P=1.0, K=2.1 },
        triticale = { N=2.5, P=1.2, K=2.3 },
        sorghum = { N=2.7, P=1.1, K=2.2 },
        peas = { N=3.5, P=1.3, K=2.4 },
        beans = { N=3.6, P=1.4, K=2.5 }
    }
    
    local name = fruitDesc.name:lower()
    local rates = cropExtraction[name] or { N=2.5, P=1.1, K=2.0 }
    local factor = harvestedLiters / 1000
    
    field.nitrogen   = math.max(0, field.nitrogen   - rates.N * factor)
    field.phosphorus = math.max(0, field.phosphorus - rates.P * factor)
    field.potassium  = math.max(0, field.potassium  - rates.K * factor)
    
    field.lastCrop = fruitDesc.name
    field.lastHarvest = g_currentMission.environment.currentDay
    
    self:log(
        "Harvest depletion field %d (%s): -N %.1f -P %.1f -K %.1f",
        fieldId, fruitDesc.name,
        rates.N * factor,
        rates.P * factor,
        rates.K * factor
    )
end

-- Apply fertilizer
function SoilFertilitySystem:applyFertilizer(fieldId, fillTypeIndex, liters)
    if self.PFActive then return end
    
    local field = self:getOrCreateField(fieldId, true)
    if field == nil then 
        self:log("Cannot apply fertilizer - field %d not found", fieldId)
        return 
    end
    
    local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    if fillType == nil then 
        self:log("Cannot apply fertilizer - fill type %d not found", fillTypeIndex)
        return 
    end
    
    local nutrientTable = {
        LIQUIDFERTILIZER = { N=6.0, P=2.5, K=4.0 },
        FERTILIZER       = { N=8.0, P=4.0, K=3.0 },
        MANURE           = { N=3.0, P=2.0, K=3.5, OM=0.05 },
        SLURRY           = { N=4.0, P=2.0, K=5.0, OM=0.03 },
        DIGESTATE        = { N=5.0, P=2.2, K=5.5, OM=0.04 },
        LIME             = { pH=0.4 }
    }
    
    local entry = nutrientTable[fillType.name]
    if entry == nil then 
        self:log("Fertilizer type %s not recognized", fillType.name)
        return 
    end
    
    local factor = liters / 1000
    
    if entry.N then field.nitrogen   = math.min(100, field.nitrogen   + entry.N * factor) end
    if entry.P then field.phosphorus = math.min(100, field.phosphorus + entry.P * factor) end
    if entry.K then field.potassium  = math.min(100, field.potassium  + entry.K * factor) end
    if entry.pH then field.pH        = math.min(7.5, field.pH + entry.pH * factor) end
    if entry.OM then field.organicMatter = math.min(10, field.organicMatter + entry.OM * factor) end
    
    field.fertilizerApplied = field.fertilizerApplied + liters
    
    self:log(
        "Fertilizer applied field %d (%s): %.0f L",
        fieldId, fillType.name, liters
    )
end

-- Read PF data
function SoilFertilitySystem:readPFFieldData(fieldId)
    if not self.PFActive or not g_precisionFarming then return nil end
    
    local fieldData = g_precisionFarming.fieldData
    if fieldData and fieldData[fieldId] then
        local pf = fieldData[fieldId]
        return {
            nitrogen = pf.nitrogen,
            phosphorus = pf.phosphorus,
            potassium = pf.potassium,
            pH = pf.pH,
            organicMatter = pf.organicMatter
        }
    end
    
    local soilMap = g_precisionFarming.soilMap
    if soilMap and soilMap.getFieldData then
        local data = soilMap:getFieldData(fieldId)
        if data then
            return {
                nitrogen = data.nitrogen,
                phosphorus = data.phosphorus,
                potassium = data.potassium,
                pH = data.pH,
                organicMatter = data.organicMatter
            }
        end
    end
    
    return nil
end

-- Get field info - FIXED VERSION
function SoilFertilitySystem:getFieldInfo(fieldId)
    if not fieldId then return nil end
    
    -- Try to get or create the field
    local field = self:getOrCreateField(fieldId, true)
    if not field then 
        self:log("Field %d not found in getFieldInfo", fieldId)
        return nil 
    end
    
    local function nutrientStatus(value, poor, fair)
        if value < poor then return "Poor"
        elseif value < fair then return "Fair"
        else return "Good" end
    end
    
    local currentDay = g_currentMission and g_currentMission.environment and g_currentMission.environment.currentDay or 0
    
    return {
        fieldId = fieldId,
        nitrogen = { value = math.floor(field.nitrogen), status = nutrientStatus(field.nitrogen, 30, 50) },
        phosphorus = { value = math.floor(field.phosphorus), status = nutrientStatus(field.phosphorus, 25, 45) },
        potassium = { value = math.floor(field.potassium), status = nutrientStatus(field.potassium, 20, 40) },
        organicMatter = field.organicMatter,
        pH = field.pH,
        lastCrop = field.lastCrop,
        daysSinceHarvest = field.lastHarvest > 0 and (currentDay - field.lastHarvest) or 0,
        fertilizerApplied = field.fertilizerApplied,
        needsFertilization = not self.PFActive and (
            field.nitrogen < 30 or
            field.phosphorus < 25 or
            field.potassium < 20 or
            field.pH < 5.5
        )
    }
end

-- Save/load state
function SoilFertilitySystem:saveState()
    return { fieldData = self.fieldData, lastUpdate = self.lastUpdate, lastUpdateDay = self.lastUpdateDay }
end

function SoilFertilitySystem:loadState(state)
    if not state then return end
    if state.fieldData then self.fieldData = state.fieldData end
    if state.lastUpdate then self.lastUpdate = state.lastUpdate end
    if state.lastUpdateDay then self.lastUpdateDay = state.lastUpdateDay end
end

-- NEW: Debug function to list all fields
function SoilFertilitySystem:listAllFields()
    print("[Soil Mod] === Listing all fields ===")
    
    -- List from our data
    print("Our tracked fields:")
    for fieldId, field in pairs(self.fieldData) do
        print(string.format("  Field %d: N=%.1f, P=%.1f, K=%.1f, pH=%.1f, OM=%.2f%%", 
            fieldId, field.nitrogen, field.phosphorus, field.potassium, field.pH, field.organicMatter))
    end
    
    -- List from FieldManager if available
    if g_fieldManager and g_fieldManager.fields then
        print("\nFields in FieldManager:")
        for _, field in ipairs(g_fieldManager.fields) do
            print(string.format("  Field %d: Name=%s", field.fieldId, tostring(field.name or "Unknown")))
        end
    end
    
    print("=== End field list ===")
end
