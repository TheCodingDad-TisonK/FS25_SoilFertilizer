-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FIXED VERSION)
-- =========================================================
-- Author: TisonK (bugfixes applied)
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
    if self.isInitialized then 
        self:info("System already initialized, skipping")
        return 
    end
    
    self:info("Initializing Soil Fertility System...")
    
    self:checkPFCompatibility()
    
    -- Scan fields using real FieldManager
    if g_fieldManager then
        self:scanFields()
    else
        self:warning("FieldManager not available - will try delayed initialization")
    end
    
    -- Install ALL real hooks
    self:installAllHooks()
    
    self.isInitialized = true
    self:info("Soil Fertility System initialized successfully")
    self:info("Fertility System: %s, Nutrient Cycles: %s",
        tostring(self.settings.fertilitySystem),
        tostring(self.settings.nutrientCycles))
    
    -- Show notification
    if self.settings.enabled and self.settings.showNotifications then
        self:showNotification("Soil & Fertilizer Mod Active", "Real soil system with full event hooks")
    end
end

-- Install ALL real event hooks
function SoilFertilitySystem:installAllHooks()
    if self.hooksInstalled then 
        self:info("Hooks already installed, skipping re-installation")
        return 
    end
    
    self:info("Installing real event hooks...")
    
    -- Hook 1: Harvest events (FruitUtil)
    if FruitUtil and FruitUtil.fruitPickupEvent then
        FruitUtil.fruitPickupEvent = Utils.appendedFunction(
            FruitUtil.fruitPickupEvent,
            function(fruitTypeIndex, x, z, fieldId, liters)
                if g_SoilFertilityManager and 
                   g_SoilFertilityManager.soilSystem and
                   g_SoilFertilityManager.settings.enabled and
                   g_SoilFertilityManager.settings.nutrientCycles and
                   fieldId and fieldId > 0 then
                    
                    local success, errorMsg = pcall(function()
                        g_SoilFertilityManager.soilSystem:updateFieldNutrients(fieldId, fruitTypeIndex, liters)
                    end)
                    
                    if not success then
                        print("[Soil Mod ERROR] Harvest hook failed: " .. tostring(errorMsg))
                    elseif g_SoilFertilityManager.settings.debugMode then
                        print(string.format("[Soil Mod] Harvest: Field %d, Crop %d, %.0fL", 
                            fieldId, fruitTypeIndex, liters))
                    end
                end
            end
        )
        self:info("✓ Harvest hook installed")
    else
        self:warning("✗ Could not install harvest hook - FruitUtil not available")
    end
    
    -- Hook 2: Fertilizer application (Sprayer system)
    if Sprayer then
        local originalSpray = Sprayer.spray
        
        Sprayer.spray = function(self, fillTypeIndex, liters, fieldId, ...)
            local result = originalSpray(self, fillTypeIndex, liters, fieldId, ...)
            
            if g_SoilFertilityManager and 
               g_SoilFertilityManager.soilSystem and
               g_SoilFertilityManager.settings.enabled and
               fieldId and fieldId > 0 and
               liters and liters > 0 then
                
                local success, errorMsg = pcall(function()
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
                                print(string.format("[Soil Mod] Fertilizer: Field %d, %s, %.0fL", 
                                    fieldId, fillTypeName, liters))
                            end
                        end
                    end
                end)
                
                if not success then
                    print("[Soil Mod ERROR] Fertilizer hook failed: " .. tostring(errorMsg))
                end
            end
            
            return result
        end
        self:info("✓ Fertilizer hook installed")
    else
        self:warning("✗ Could not install fertilizer hook - Sprayer not available")
    end
    
    -- Hook 3: Field ownership changes
    if g_farmlandManager and g_farmlandManager.fieldOwnershipChanged then
        g_farmlandManager.fieldOwnershipChanged = Utils.appendedFunction(
            g_farmlandManager.fieldOwnershipChanged,
            function(fieldId, farmlandId, farmId)
                if g_SoilFertilityManager and 
                   g_SoilFertilityManager.soilSystem and
                   g_SoilFertilityManager.settings.enabled then
                    
                    local success, errorMsg = pcall(function()
                        local field = g_SoilFertilityManager.soilSystem:getOrCreateField(fieldId, true)
                        if field and not field.initialized then
                            field.nitrogen = 50
                            field.phosphorus = 40
                            field.potassium = 45
                            field.organicMatter = 3.5
                            field.pH = 6.5
                            field.initialized = true
                            
                            print(string.format("[Soil Mod] Field %d initialized for new owner", fieldId))
                        end
                    end)
                    
                    if not success then
                        print("[Soil Mod ERROR] Ownership hook failed: " .. tostring(errorMsg))
                    end
                end
            end
        )
        self:info("✓ Field ownership hook installed")
    else
        self:warning("✗ Could not install ownership hook - farmlandManager not available")
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
                    
                    local success, errorMsg = pcall(function()
                        -- Daily soil updates
                        local currentDay = self.currentDay or 0
                        if currentDay ~= g_SoilFertilityManager.soilSystem.lastUpdateDay then
                            g_SoilFertilityManager.soilSystem.lastUpdateDay = currentDay
                            g_SoilFertilityManager.soilSystem:updateDailySoil()
                        end
                        
                        -- Rain effects (check if enabled in settings)
                        if g_SoilFertilityManager.settings.rainEffects and 
                           self.weather and self.weather.rainScale and 
                           self.weather.rainScale > 0.1 then
                            g_SoilFertilityManager.soilSystem:applyRainEffects(dt, self.weather.rainScale)
                        end
                    end)
                    
                    if not success then
                        print("[Soil Mod ERROR] Weather hook failed: " .. tostring(errorMsg))
                    end
                end
                
                return result
            end
            self:info("✓ Weather hook installed")
        else
            self:warning("✗ Could not install weather hook - environment.update not found")
        end
    else
        self:warning("✗ Could not install weather hook - environment not available")
    end
    
    self.hooksInstalled = true
    self:info("All hooks installation complete")
end

-- Logging helpers
function SoilFertilitySystem:log(msg, ...)
    if self.settings and self.settings.debugMode then
        print(string.format("[Soil Mod DEBUG] " .. msg, ...))
    end
end

function SoilFertilitySystem:info(msg, ...)
    print(string.format("[Soil Mod] " .. msg, ...))
end

function SoilFertilitySystem:warning(msg, ...)
    print(string.format("[Soil Mod WARNING] " .. msg, ...))
end

-- Notification helper
function SoilFertilitySystem:showNotification(title, message)
    if not self.settings or not self.settings.showNotifications then return end
    
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(title .. ": " .. message, 6000)
    else
        self:info("%s - %s", title, message)
    end
end

-- Update function called every frame
function SoilFertilitySystem:update(dt)
    if not self.settings.enabled then return end
    
    self.lastUpdate = self.lastUpdate + dt
    
    if self.lastUpdate >= self.updateInterval then
        self.lastUpdate = 0
        -- Periodic checks could go here
    end
end

-- Check for Precision Farming compatibility
function SoilFertilitySystem:checkPFCompatibility()
    self.PFActive = false
    
    if g_precisionFarming then
        self.PFActive = true
        self:info("Precision Farming detected - enabling read-only mode")
        return
    end
    
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("precisionfarming") or lowerName:find("precision_farming") then
                self.PFActive = true
                self:info("Precision Farming mod detected - enabling read-only mode")
                return
            end
        end
    end
end

-- Scan all fields from FieldManager
function SoilFertilitySystem:scanFields()
    if not g_fieldManager or not g_fieldManager.fields then
        self:warning("FieldManager or fields not available")
        return
    end
    
    self:log("Scanning fields from FieldManager...")
    local count = 0
    
    for _, field in ipairs(g_fieldManager.fields) do
        if field and field.fieldId and field.fieldId > 0 then
            self:getOrCreateField(field.fieldId, true)
            count = count + 1
        end
    end
    
    self:info("Scanned and initialized %d fields", count)
end

-- Get or create field data
function SoilFertilitySystem:getOrCreateField(fieldId, createIfMissing)
    if not fieldId or fieldId <= 0 then return nil end
    
    -- Return existing field
    if self.fieldData[fieldId] then
        return self.fieldData[fieldId]
    end
    
    -- Don't create if not requested
    if not createIfMissing then
        return nil
    end
    
    -- Check if PF is active and try to read from it
    if self.PFActive then
        local pfData = self:readPFFieldData(fieldId)
        if pfData then
            self.fieldData[fieldId] = {
                nitrogen = pfData.nitrogen or 50,
                phosphorus = pfData.phosphorus or 40,
                potassium = pfData.potassium or 45,
                organicMatter = pfData.organicMatter or 3.5,
                pH = pfData.pH or 6.5,
                lastCrop = nil,
                lastHarvest = 0,
                fertilizerApplied = 0,
                initialized = true,
                fromPF = true
            }
            self:log("Created field %d from PF data", fieldId)
            return self.fieldData[fieldId]
        end
    end
    
    -- Create new field with default values
    self.fieldData[fieldId] = {
        nitrogen = 50,
        phosphorus = 40,
        potassium = 45,
        organicMatter = 3.5,
        pH = 6.5,
        lastCrop = nil,
        lastHarvest = 0,
        fertilizerApplied = 0,
        initialized = true,
        fromPF = false
    }
    
    self:log("Created new field data for field %d", fieldId)
    return self.fieldData[fieldId]
end

-- Daily soil update
function SoilFertilitySystem:updateDailySoil()
    if not self.settings.enabled or not self.settings.nutrientCycles then return end
    if self.PFActive then return end -- Don't modify if PF is active
    
    local currentDay = (g_currentMission and g_currentMission.environment and g_currentMission.environment.currentDay) or 0
    
    for fieldId, field in pairs(self.fieldData) do
        -- Natural nutrient recovery for fallow fields
        local daysSinceFallow = currentDay - (field.lastHarvest or 0)
        if daysSinceFallow > 7 then
            -- Slow natural recovery
            field.nitrogen = math.min(100, field.nitrogen + 0.2)
            field.phosphorus = math.min(100, field.phosphorus + 0.1)
            field.potassium = math.min(100, field.potassium + 0.15)
            
            -- Organic matter slowly increases in fallow
            field.organicMatter = math.min(10, field.organicMatter + 0.01)
        end
        
        -- Seasonal effects (if enabled)
        if self.settings.seasonalEffects and g_currentMission.environment then
            local season = g_currentMission.environment.currentSeason
            if season == 1 then -- Spring - boost
                field.nitrogen = math.min(100, field.nitrogen + 0.1)
            elseif season == 3 then -- Fall - slowdown
                field.nitrogen = math.max(0, field.nitrogen - 0.05)
            end
        end
        
        -- pH normalization toward neutral (very slow)
        if field.pH < 6.5 then
            field.pH = math.min(6.5, field.pH + 0.01)
        elseif field.pH > 7.0 then
            field.pH = math.max(7.0, field.pH - 0.01)
        end
    end
    
    self:log("Daily soil update completed for %d fields", self:getFieldCount())
end

-- Apply rain effects
function SoilFertilitySystem:applyRainEffects(dt, rainScale)
    if not self.settings.enabled or not self.settings.rainEffects then return end
    if self.PFActive then return end
    
    -- Rain leaches nutrients (very slow effect)
    local leachFactor = rainScale * dt * 0.000001
    
    for fieldId, field in pairs(self.fieldData) do
        -- Nitrogen is most easily leached
        field.nitrogen = math.max(0, field.nitrogen - (leachFactor * 5))
        -- Potassium is moderately leached
        field.potassium = math.max(0, field.potassium - (leachFactor * 2))
        -- Phosphorus is least leached (binds to soil)
        field.phosphorus = math.max(0, field.phosphorus - (leachFactor * 0.5))
        
        -- Rain slightly acidifies soil
        field.pH = math.max(5.0, field.pH - (leachFactor * 0.1))
    end
end

-- Update field nutrients after harvest
function SoilFertilitySystem:updateFieldNutrients(fieldId, fruitTypeIndex, harvestedLiters)
    if self.PFActive then return end
    if not self.settings.enabled or not self.settings.nutrientCycles then return end
    
    local field = self:getOrCreateField(fieldId, true)
    if not field then 
        self:warning("Cannot update nutrients - field %d not found", fieldId)
        return 
    end
    
    local fruitDesc = g_fruitTypeManager and g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if not fruitDesc then 
        self:warning("Cannot update nutrients - fruit type %d not found", fruitTypeIndex)
        return 
    end
    
    -- Base nutrient removal per 1,000 liters
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
    
    local name = string.lower(fruitDesc.name or "unknown")
    local rates = cropExtraction[name] or { N=2.5, P=1.1, K=2.0 }
    local factor = harvestedLiters / 1000
    
    -- Apply difficulty multiplier
    if self.settings.difficulty == 3 then -- Hardcore
        factor = factor * 1.5
    elseif self.settings.difficulty == 1 then -- Simple
        factor = factor * 0.7
    end
    
    field.nitrogen   = math.max(0, field.nitrogen   - rates.N * factor)
    field.phosphorus = math.max(0, field.phosphorus - rates.P * factor)
    field.potassium  = math.max(0, field.potassium  - rates.K * factor)
    
    field.lastCrop = fruitDesc.name
    field.lastHarvest = (g_currentMission and g_currentMission.environment and g_currentMission.environment.currentDay) or 0
    
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
    if not self.settings.enabled then return end
    
    local field = self:getOrCreateField(fieldId, true)
    if not field then 
        self:warning("Cannot apply fertilizer - field %d not found", fieldId)
        return 
    end
    
    local fillType = g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    if not fillType then 
        self:warning("Cannot apply fertilizer - fill type %d not found", fillTypeIndex)
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
    if not entry then 
        self:log("Fertilizer type %s not recognized", fillType.name)
        return 
    end
    
    local factor = liters / 1000
    
    if entry.N then field.nitrogen   = math.min(100, field.nitrogen   + entry.N * factor) end
    if entry.P then field.phosphorus = math.min(100, field.phosphorus + entry.P * factor) end
    if entry.K then field.potassium  = math.min(100, field.potassium  + entry.K * factor) end
    if entry.pH then field.pH        = math.min(7.5, field.pH + entry.pH * factor) end
    if entry.OM then field.organicMatter = math.min(10, field.organicMatter + entry.OM * factor) end
    
    field.fertilizerApplied = (field.fertilizerApplied or 0) + liters
    
    self:log(
        "Fertilizer applied field %d (%s): %.0f L",
        fieldId, fillType.name, liters
    )
end

-- Read PF data
function SoilFertilitySystem:readPFFieldData(fieldId)
    if not self.PFActive or not g_precisionFarming then return nil end
    
    -- Try to get from fieldData
    if g_precisionFarming.fieldData and g_precisionFarming.fieldData[fieldId] then
        local pf = g_precisionFarming.fieldData[fieldId]
        return {
            nitrogen = pf.nitrogen,
            phosphorus = pf.phosphorus,
            potassium = pf.potassium,
            pH = pf.pH,
            organicMatter = pf.organicMatter
        }
    end
    
    -- Try to get from soilMap
    if g_precisionFarming.soilMap and g_precisionFarming.soilMap.getFieldData then
        local data = g_precisionFarming.soilMap:getFieldData(fieldId)
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

-- Get field info for display
function SoilFertilitySystem:getFieldInfo(fieldId)
    if not fieldId or fieldId <= 0 then return nil end
    
    local field = self:getOrCreateField(fieldId, true)
    if not field then 
        self:warning("Field %d not found in getFieldInfo", fieldId)
        return nil 
    end
    
    local function nutrientStatus(value, poor, fair)
        if value < poor then return "Poor"
        elseif value < fair then return "Fair"
        else return "Good" end
    end
    
    local currentDay = (g_currentMission and g_currentMission.environment and g_currentMission.environment.currentDay) or 0
    
    return {
        fieldId = fieldId,
        nitrogen = { value = math.floor(field.nitrogen), status = nutrientStatus(field.nitrogen, 30, 50) },
        phosphorus = { value = math.floor(field.phosphorus), status = nutrientStatus(field.phosphorus, 25, 45) },
        potassium = { value = math.floor(field.potassium), status = nutrientStatus(field.potassium, 20, 40) },
        organicMatter = field.organicMatter,
        pH = field.pH,
        lastCrop = field.lastCrop,
        daysSinceHarvest = field.lastHarvest > 0 and (currentDay - field.lastHarvest) or 0,
        fertilizerApplied = field.fertilizerApplied or 0,
        needsFertilization = not self.PFActive and (
            field.nitrogen < 30 or
            field.phosphorus < 25 or
            field.potassium < 20 or
            field.pH < 5.5
        )
    }
end

-- Get field count
function SoilFertilitySystem:getFieldCount()
    local count = 0
    for _ in pairs(self.fieldData) do
        count = count + 1
    end
    return count
end

-- Save to XML file
function SoilFertilitySystem:saveToXMLFile(xmlFile, key)
    if not xmlFile then return end
    
    local index = 0
    for fieldId, field in pairs(self.fieldData) do
        local fieldKey = string.format("%s.field(%d)", key, index)
        setXMLInt(xmlFile, fieldKey .. "#id", fieldId)
        setXMLFloat(xmlFile, fieldKey .. "#nitrogen", field.nitrogen or 50)
        setXMLFloat(xmlFile, fieldKey .. "#phosphorus", field.phosphorus or 40)
        setXMLFloat(xmlFile, fieldKey .. "#potassium", field.potassium or 45)
        setXMLFloat(xmlFile, fieldKey .. "#organicMatter", field.organicMatter or 3.5)
        setXMLFloat(xmlFile, fieldKey .. "#pH", field.pH or 6.5)
        setXMLString(xmlFile, fieldKey .. "#lastCrop", field.lastCrop or "")
        setXMLInt(xmlFile, fieldKey .. "#lastHarvest", field.lastHarvest or 0)
        setXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied", field.fertilizerApplied or 0)
        index = index + 1
    end
    
    self:info("Saved data for %d fields", index)
end

-- Load from XML file
function SoilFertilitySystem:loadFromXMLFile(xmlFile, key)
    if not xmlFile then return end
    
    self.fieldData = {}
    local index = 0
    
    while true do
        local fieldKey = string.format("%s.field(%d)", key, index)
        local fieldId = getXMLInt(xmlFile, fieldKey .. "#id")
        
        if not fieldId then break end
        
        self.fieldData[fieldId] = {
            nitrogen = getXMLFloat(xmlFile, fieldKey .. "#nitrogen") or 50,
            phosphorus = getXMLFloat(xmlFile, fieldKey .. "#phosphorus") or 40,
            potassium = getXMLFloat(xmlFile, fieldKey .. "#potassium") or 45,
            organicMatter = getXMLFloat(xmlFile, fieldKey .. "#organicMatter") or 3.5,
            pH = getXMLFloat(xmlFile, fieldKey .. "#pH") or 6.5,
            lastCrop = getXMLString(xmlFile, fieldKey .. "#lastCrop"),
            lastHarvest = getXMLInt(xmlFile, fieldKey .. "#lastHarvest") or 0,
            fertilizerApplied = getXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied") or 0,
            initialized = true
        }
        
        -- Clear empty strings
        if self.fieldData[fieldId].lastCrop == "" then
            self.fieldData[fieldId].lastCrop = nil
        end
        
        index = index + 1
    end
    
    self:info("Loaded data for %d fields", index)
end

-- Debug: List all fields
function SoilFertilitySystem:listAllFields()
    print("[Soil Mod] === Listing all fields ===")
    
    print("Our tracked fields:")
    for fieldId, field in pairs(self.fieldData) do
        print(string.format("  Field %d: N=%.1f, P=%.1f, K=%.1f, pH=%.1f, OM=%.2f%%", 
            fieldId, field.nitrogen, field.phosphorus, field.potassium, field.pH, field.organicMatter))
    end
    
    if g_fieldManager and g_fieldManager.fields then
        print("\nFields in FieldManager:")
        for _, field in ipairs(g_fieldManager.fields) do
            print(string.format("  Field %d: Name=%s", field.fieldId, tostring(field.name or "Unknown")))
        end
    end
    
    print("=== End field list ===")
end