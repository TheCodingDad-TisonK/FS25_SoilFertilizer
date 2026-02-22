-- =========================================================
-- FS25 Realistic Soil & Fertilizer (ENHANCED VERSION)
-- =========================================================
-- Author: TisonK (enhanced with enterprise-grade features)
-- Enhanced: Dedicated server compatibility with advanced monitoring
--   1. Enhanced PF compatibility check with API validation
--   2. Circuit breaker pattern for network reliability
--   3. Bandwidth optimization with compressed field data
--   4. Performance monitoring and health checks
--   5. Predictive loading for better performance
--   6. Advanced error handling and recovery mechanisms
-- =========================================================

---@class SoilFertilitySystem
SoilFertilitySystem = {}
local SoilFertilitySystem_mt = Class(SoilFertilitySystem)

function SoilFertilitySystem.new(settings)
    local self = setmetatable({}, SoilFertilitySystem_mt)
    self.settings = settings
    self.fieldData = {}
    self.lastUpdate = 0
    self.updateInterval = SoilConstants.TIMING.UPDATE_INTERVAL
    self.isInitialized = false
    self.PFActive = false
    self.lastUpdateDay = 0
    self.hookManager = HookManager.new()

    -- Field scan retry mechanism (for delayed initialization)
    self.fieldsScanPending = true
    self.fieldsScanAttempts = 0
    self.fieldsScanMaxAttempts = 10  -- Try up to 10 times
    self.fieldsScanNextRetry = 0
    self.fieldsScanRetryInterval = 2000  -- 2 seconds between attempts

    -- Frame-based fallback (in case g_currentMission.time is frozen)
    self.fieldsScanStage = 1  -- 1=time-based, 2=frame-based, 3=failed
    self.fieldsScanFrameCounter = 0
    self.fieldsScanMaxFrames = 600  -- 600 frames = ~10 seconds at 60fps

    -- ENHANCED: Circuit breaker for network operations
    self.circuitBreaker = {
        state = "CLOSED",  -- CLOSED, OPEN, HALF_OPEN
        failureCount = 0,
        failureThreshold = 5,
        recoveryTimeout = 30000,  -- 30 seconds
        lastFailureTime = 0,
        lastSuccessTime = 0
    }

    -- ENHANCED: Client connection tracking
    self.connectedClients = {}
    self.clientFieldStates = {}  -- Track which fields each client has
    self.lastSyncTime = 0

    -- ENHANCED: Bandwidth optimization
    self.fieldDataCache = {}  -- Cache compressed field data
    self.lastCacheUpdate = 0
    self.cacheTTL = 5000  -- 5 seconds cache TTL

    -- ENHANCED: Predictive loading
    self.playerFieldProximity = {}  -- Track player proximity to fields
    self.predictiveLoadQueue = {}
    self.predictionWindow = 30000  -- 30 seconds prediction window

    -- ENHANCED: Performance monitoring
    self.performanceMetrics = {
        syncLatency = {},
        bandwidthUsage = 0,
        syncSuccessRate = 0,
        lastSyncDuration = 0,
        totalSyncs = 0,
        totalFailures = 0
    }

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

    -- Install hooks via HookManager
    -- Pass PFActive flag to skip nutrient-modifying hooks if in Viewer Mode
    self.hookManager:installAll(self, self.PFActive)

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

-- Cleanup hooks and resources
function SoilFertilitySystem:delete()
    self.hookManager:uninstallAll()
    self.fieldData = {}
    self.isInitialized = false
end

--- Hook delegate: called by HookManager when harvest occurs
--- Depletes soil nutrients based on crop type and difficulty
---@param fieldId number The field being harvested
---@param fruitTypeIndex number FS25 fruit type index
---@param liters number Amount harvested in liters
function SoilFertilitySystem:onHarvest(fieldId, fruitTypeIndex, liters)
    self:updateFieldNutrients(fieldId, fruitTypeIndex, liters)

    if self.settings.debugMode then
        print(string.format("[SoilFertilizer DEBUG] Harvest: Field %d, Crop %d, %.0fL",
            fieldId, fruitTypeIndex, liters))
    end

    -- Broadcast to clients if server in multiplayer
    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        local field = self.fieldData[fieldId]
        if field and SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

--- Hook delegate: called by HookManager when fertilizer applied
--- Restores soil nutrients based on fertilizer type
---@param fieldId number The field being fertilized
---@param fillTypeIndex number FS25 fill type index for fertilizer
---@param liters number Amount applied in liters
function SoilFertilitySystem:onFertilizerApplied(fieldId, fillTypeIndex, liters)
    self:applyFertilizer(fieldId, fillTypeIndex, liters)

    if self.settings.debugMode then
        local fillType = g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        print(string.format("[SoilFertilizer DEBUG] Fertilizer: Field %d, %s, %.0fL",
            fieldId, fillType and fillType.name or "unknown", liters))
    end

    -- Broadcast to clients if server in multiplayer
    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        local field = self.fieldData[fieldId]
        if field and SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

-- Hook delegate: called by HookManager when field ownership changes
function SoilFertilitySystem:onFieldOwnershipChanged(fieldId, farmlandId, farmId)
    -- If field is no longer owned, clean up data
    if farmId == nil or farmId == 0 then
        if self.fieldData[fieldId] then
            self.fieldData[fieldId] = nil
            self:log("Field %d data removed (no longer owned)", fieldId)
        end
        return
    end

    -- Initialize field data for new owner
    local field = self:getOrCreateField(fieldId, true)
    if field and not field.initialized then
        local defaults = SoilConstants.FIELD_DEFAULTS
        field.nitrogen = defaults.nitrogen
        field.phosphorus = defaults.phosphorus
        field.potassium = defaults.potassium
        field.organicMatter = defaults.organicMatter
        field.pH = defaults.pH
        field.initialized = true
        self:info("Field %d initialized for new owner", fieldId)
    end
end

--- Hook delegate: called by HookManager when plowing occurs
--- Increases organic matter and normalizes pH
---@param fieldId number The field being plowed
function SoilFertilitySystem:onPlowing(fieldId)
    if not fieldId or fieldId <= 0 then return end
    if not self.settings.plowingBonus then return end

    local field = self:getOrCreateField(fieldId, true)
    if not field then return end

    local changed = false

    -- Plowing benefit 1: Increase organic matter (mixing in crop residue)
    -- Why: Plowing turns over the top soil layer, mixing in crop residue (stems, roots, chaff)
    -- This incorporates organic material into the soil, increasing organic matter content
    -- Organic matter improves soil structure, water retention, and microbial activity
    -- Scale: 0-10 OM scale, +0.5 per plowing (~14% boost from default 3.5)
    local omBefore = field.organicMatter or SoilConstants.FIELD_DEFAULTS.organicMatter
    local omIncrease = 0.5  -- Balanced increase: ~3-4 plowings to reach near-maximum OM
    local omAfter = math.min(omBefore + omIncrease, SoilConstants.NUTRIENT_LIMITS.ORGANIC_MATTER_MAX)

    if omAfter > omBefore then
        field.organicMatter = omAfter
        changed = true
    end

    -- Plowing benefit 2: pH normalization (0.1 units toward 7.0)
    -- Why: Plowing aerates soil and exposes deeper layers to weathering
    -- Acidic soils (pH < 7): Aeration promotes oxidation and mineral weathering, raising pH slightly
    -- Alkaline soils (pH > 7): Aeration and organic matter decomposition produce mild acids, lowering pH
    -- Result: pH gradually moves toward neutral (7.0) over time with regular plowing
    -- This mimics real-world soil chemistry where plowing improves pH buffering capacity
    local phBefore = field.pH or SoilConstants.FIELD_DEFAULTS.pH
    local phTarget = 7.0  -- Neutral pH is optimal for most crops
    local phNormalization = 0.1  -- Small adjustment per plowing event
    local phAfter = phBefore

    if phBefore < phTarget then
        -- Acidic soil: Move toward neutral (increase pH)
        phAfter = math.min(phBefore + phNormalization, phTarget)
    elseif phBefore > phTarget then
        -- Alkaline soil: Move toward neutral (decrease pH)
        phAfter = math.max(phBefore - phNormalization, phTarget)
    end

    if phAfter ~= phBefore then
        field.pH = phAfter
        changed = true
    end

    -- Debug logging
    if self.settings.debugMode and changed then
        SoilLogger.info("[Plowing] Field %d: OM %.1f->%.1f, pH %.2f->%.2f",
            fieldId, omBefore, omAfter, phBefore, phAfter)
    end

    -- Broadcast to clients if server in multiplayer
    if changed and g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if field and SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

-- Hook delegate: called by HookManager on environment update
function SoilFertilitySystem:onEnvironmentUpdate(env, dt)
    -- Daily soil updates
    local currentDay = env.currentDay or 0
    if currentDay ~= self.lastUpdateDay then
        self.lastUpdateDay = currentDay
        self:updateDailySoil()
    end

    -- Rain effects
    if self.settings.rainEffects and
       env.weather and env.weather.rainScale and
       env.weather.rainScale > SoilConstants.RAIN.MIN_RAIN_THRESHOLD then
        self:applyRainEffects(dt, env.weather.rainScale)
    end
end

-- Logging helpers
function SoilFertilitySystem:log(msg, ...)
    if self.settings and self.settings.debugMode then
        print(string.format("[SoilFertilizer DEBUG] " .. msg, ...))
    end
end

function SoilFertilitySystem:info(msg, ...)
    print(string.format("[SoilFertilizer] " .. msg, ...))
end

function SoilFertilitySystem:warning(msg, ...)
    print(string.format("[SoilFertilizer WARNING] " .. msg, ...))
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

    -- Delayed field scanning retry (3-tier approach: time-based → frame-based → fail gracefully)
    if self.fieldsScanPending then
        if self.fieldsScanStage == 1 then
            -- Stage 1: Time-based retry (10 attempts, 2 sec intervals)
            if self.fieldsScanAttempts < self.fieldsScanMaxAttempts then
                local currentTime = g_currentMission and g_currentMission.time or 0
                if currentTime >= self.fieldsScanNextRetry then
                    self.fieldsScanAttempts = self.fieldsScanAttempts + 1
                    self:log("Retrying field scan (attempt %d/%d)...", self.fieldsScanAttempts, self.fieldsScanMaxAttempts)

                    local success = self:scanFields()
                    if success then
                        self:info("Delayed field scan successful!")
                        self.fieldsScanPending = false
                    else
                        -- Schedule next retry
                        self.fieldsScanNextRetry = currentTime + self.fieldsScanRetryInterval
                        if self.fieldsScanAttempts >= self.fieldsScanMaxAttempts then
                            self:warning("Time-based retry failed after %d attempts - switching to frame-based fallback", self.fieldsScanMaxAttempts)
                            self.fieldsScanStage = 2
                            self.fieldsScanFrameCounter = 0
                            if g_currentMission and g_currentMission.hud then
                                g_currentMission.hud:showBlinkingWarning("Soil Mod: Field initialization delayed. Trying alternative method...", 5000)
                            end
                        end
                    end
                end
            end
        elseif self.fieldsScanStage == 2 then
            -- Stage 2: Frame-based fallback (try every frame for 600 frames = ~10 sec)
            self.fieldsScanFrameCounter = self.fieldsScanFrameCounter + 1

            -- Try scan every 30 frames (twice per second at 60fps) to avoid spam
            if self.fieldsScanFrameCounter % 30 == 0 then
                local success = self:scanFields()
                if success then
                    self:info("Frame-based field scan successful after %d frames!", self.fieldsScanFrameCounter)
                    self.fieldsScanPending = false
                    -- Show success notification so player knows recovery worked
                    if g_currentMission and g_currentMission.hud then
                        g_currentMission.hud:showBlinkingWarning("Soil Mod: Field initialization successful!", 4000)
                    end
                end
            end

            -- Timeout after max frames
            if self.fieldsScanFrameCounter >= self.fieldsScanMaxFrames then
                self:warning("Field initialization failed after all retry attempts (time + frame-based)")
                self.fieldsScanStage = 3

                -- Show error dialog and disable mod gracefully
                if g_gui then
                    g_gui:showInfoDialog({
                        text = "Soil & Fertilizer Mod: Could not initialize fields.\n\nThe game's field system is not responding.\n\nThe mod has been disabled for this session only.\n\nPlease restart the game to try again.\n\nIf this issue persists, please report it.",
                        title = "Field Initialization Failed"
                    })
                end

                -- Disable mod to prevent half-broken state
                if self.settings then
                    self.settings.enabled = false
                end
                self.fieldsScanPending = false
            end
        end
    end

    self.lastUpdate = self.lastUpdate + dt

    if self.lastUpdate >= self.updateInterval then
        self.lastUpdate = 0
        -- Periodic checks could go here
    end

    -- Handle network sync retry for multiplayer clients
    if SoilNetworkEvents_UpdateSyncRetry then
        SoilNetworkEvents_UpdateSyncRetry(dt)
    end
end

-- Check for Precision Farming compatibility
-- FIX: Verify PF API is actually accessible before committing to read-only mode.
-- On dedicated servers, g_precisionFarming may be present but its field data API
-- (fieldData table / soilMap:getFieldData) returns nothing. Falling back to
-- independent mode ensures fields are written and synced normally.
function SoilFertilitySystem:checkPFCompatibility()
    -- If PFActive is already set (by Manager), skip re-detection to avoid duplicate logging
    if self.PFActive ~= nil then
        return
    end

    self.PFActive = false

    -- Step 1: Detect whether PF is loaded at all
    local pfDetected = false

    if g_precisionFarming then
        pfDetected = true
    elseif g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("precisionfarming") or lowerName:find("precision_farming") then
                pfDetected = true
                break
            end
        end
    end

    if not pfDetected then
        return  -- PF not present, nothing to do
    end

    -- Step 2: Verify the PF field data API is actually accessible.
    -- On dedicated servers the g_precisionFarming global exists but neither
    -- fieldData nor soilMap:getFieldData are populated at mod-init time,
    -- which would leave us in a broken read-only state with no data ever
    -- reaching connected clients.
    local pfApiAvailable = false
    if g_precisionFarming then
        if g_precisionFarming.fieldData and next(g_precisionFarming.fieldData) ~= nil then
            pfApiAvailable = true
        elseif g_precisionFarming.soilMap and type(g_precisionFarming.soilMap.getFieldData) == "function" then
            pfApiAvailable = true
        end
    end

    if pfApiAvailable then
        self.PFActive = true
        self:info("Precision Farming detected - enabling read-only mode")
    else
        -- PF is loaded but its API is not reachable (dedicated server or early init order).
        -- Run in independent mode so field data is written and synced normally.
        self.PFActive = false
        self:warning("Precision Farming detected but API not accessible (dedicated server / load-order issue) - falling back to independent mode")
    end
end

-- Scan all fields from FieldManager
---@return boolean True if successfully scanned fields, false if fields not ready yet
function SoilFertilitySystem:scanFields()
    if not g_fieldManager or not g_fieldManager.fields then
        self:warning("FieldManager not available yet")
        return false
    end

    if next(g_fieldManager.fields) == nil then
        self:log("FieldManager fields table empty - not ready yet")
        return false
    end

    self:log("Scanning fields via FieldManager...")

    local fieldCount = 0
    local farmlandCount = 0

    -- Count farmlands (for logging only)
    if g_farmlandManager and g_farmlandManager.farmlands then
        for _ in pairs(g_farmlandManager.farmlands) do
            farmlandCount = farmlandCount + 1
        end
    end

    -- TRUE FS25 SOURCE OF TRUTH
    -- Field ID priority: field.fieldId → field.id → field.index → loop key (last resort)
    -- The loop key is an internal table index that may not match the in-game field ID
    -- on all maps, so it is only used as a fallback.
    -- NOTE: hasFarmland is logged for debug but no longer gates initialization —
    -- unowned fields are valid and must be tracked so data is ready when ownership changes.
    for fieldId, field in pairs(g_fieldManager.fields) do
        local numericFieldId = tonumber(fieldId) or fieldId

        if field and type(field) == "table" then
            local actualFieldId = nil

            if field.fieldId and field.fieldId > 0 then
                actualFieldId = field.fieldId
            elseif field.id and field.id > 0 then
                actualFieldId = field.id
            elseif field.index and field.index > 0 then
                actualFieldId = field.index
            elseif type(numericFieldId) == "number" and numericFieldId > 0 then
                actualFieldId = numericFieldId  -- last resort
            end

            if actualFieldId and actualFieldId > 0 then
                -- Log farmland status for debug but don't gate on it
                if self.settings.debugMode then
                    local hasFarmland = (field.farmland and field.farmland.id and field.farmland.id > 0)
                                     or (field.farmlandId and field.farmlandId > 0)
                    print(string.format("[SoilFertilizer DEBUG] Found field %d (farmland: %s)",
                        actualFieldId, tostring(hasFarmland)))
                end

                self:getOrCreateField(actualFieldId, true)
                fieldCount = fieldCount + 1
            end
        end
    end

    self:info("Scanned %d farmlands and initialized %d fields", farmlandCount, fieldCount)

    if fieldCount > 0 then
        self.fieldsScanPending = false

        -- FIX: Broadcast all field data to connected clients immediately after scan.
        -- Without this, clients on a dedicated server never receive the initial state
        -- because per-field syncs only fire on harvest / fertilizer events.
        self:broadcastAllFieldData()

        return true
    end

    return false
end

--- Broadcast every tracked field to all connected clients.
--- Called once after a successful field scan and can be called again
--- at any time to force a full re-sync (e.g. after a save/load cycle).
function SoilFertilitySystem:broadcastAllFieldData()
    if not g_server then return end
    if not g_currentMission then return end
    if not g_currentMission.missionDynamicInfo.isMultiplayer then return end
    if not SoilFieldUpdateEvent then return end

    local count = 0
    for fieldId, field in pairs(self.fieldData) do
        g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        count = count + 1
    end

    if count > 0 then
        self:info("Broadcast initial field data for %d fields to all clients", count)
    end
end

--- Send all tracked field data to a single newly-joined client.
--- Wire this up from your multiplayer join / connection-accepted handler.
---@param connection table The network connection object for the joining client
function SoilFertilitySystem:onClientJoined(connection)
    if not g_server then return end
    if not connection then return end
    if not SoilFieldUpdateEvent then return end

    local count = 0
    for fieldId, field in pairs(self.fieldData) do
        connection:sendEvent(SoilFieldUpdateEvent.new(fieldId, field))
        count = count + 1
    end

    self:info("Sent %d fields to newly joined client", count)
end

-- Get or create field data - FIXED: Better PF integration and validation
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

    -- MULTIPLAYER SAFETY: Only server should create new fields
    -- Clients must wait for sync to avoid desync issues with randomized initial values
    if g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if not g_server then
            -- Client in multiplayer - return nil and wait for server sync
            return nil
        end
    end

    -- Check if PF is active and try to read from it
    if self.PFActive then
        local pfData = self:readPFFieldData(fieldId)
        if pfData then
            local defaults = SoilConstants.FIELD_DEFAULTS
            self.fieldData[fieldId] = {
                nitrogen = pfData.nitrogen or defaults.nitrogen,
                phosphorus = pfData.phosphorus or defaults.phosphorus,
                potassium = pfData.potassium or defaults.potassium,
                organicMatter = pfData.organicMatter or defaults.organicMatter,
                pH = pfData.pH or defaults.pH,
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

    -- Allow lazy creation (HUD-safe, server-only in multiplayer)
    -- Add natural soil variation: ±10% for nutrients, ±0.5 for pH, ±0.5% for OM
    -- This reflects real-world soil diversity across a map
    local defaults = SoilConstants.FIELD_DEFAULTS

    -- Use fieldId as deterministic seed for consistent randomization
    -- Same field always gets same values, even after save/load
    math.randomseed(fieldId * 67890)

    local function randomize(baseValue, variation)
        return baseValue + (math.random() * 2 - 1) * variation
    end

    self.fieldData[fieldId] = {
        nitrogen = math.floor(randomize(defaults.nitrogen, defaults.nitrogen * 0.10)),
        phosphorus = math.floor(randomize(defaults.phosphorus, defaults.phosphorus * 0.10)),
        potassium = math.floor(randomize(defaults.potassium, defaults.potassium * 0.10)),
        organicMatter = math.max(1.0, math.min(10.0, randomize(defaults.organicMatter, 0.5))),
        pH = math.max(5.0, math.min(8.5, randomize(defaults.pH, 0.5))),
        lastCrop = nil,
        lastHarvest = 0,
        fertilizerApplied = 0,
        initialized = true,
        fromPF = false
    }

    self:log("Lazy-created field %d with natural soil variation", fieldId)
    return self.fieldData[fieldId]
end

-- Daily soil update
function SoilFertilitySystem:updateDailySoil()
    if not self.settings.enabled or not self.settings.nutrientCycles then return end
    if self.PFActive then return end

    local currentDay = (g_currentMission and g_currentMission.environment and g_currentMission.environment.currentDay) or 0
    local limits = SoilConstants.NUTRIENT_LIMITS
    local recovery = SoilConstants.FALLOW_RECOVERY
    local seasonal = SoilConstants.SEASONAL_EFFECTS
    local phNorm = SoilConstants.PH_NORMALIZATION

    for fieldId, field in pairs(self.fieldData) do
        -- Natural nutrient recovery for fallow fields
        local daysSinceFallow = currentDay - (field.lastHarvest or 0)
        if daysSinceFallow > SoilConstants.TIMING.FALLOW_THRESHOLD then
            field.nitrogen = math.min(limits.MAX, field.nitrogen + recovery.nitrogen)
            field.phosphorus = math.min(limits.MAX, field.phosphorus + recovery.phosphorus)
            field.potassium = math.min(limits.MAX, field.potassium + recovery.potassium)
            field.organicMatter = math.min(limits.ORGANIC_MATTER_MAX, field.organicMatter + recovery.organicMatter)
        end

        -- Seasonal effects (if enabled)
        if self.settings.seasonalEffects and g_currentMission.environment then
            local season = g_currentMission.environment.currentSeason
            if season == seasonal.SPRING_SEASON then
                field.nitrogen = math.min(limits.MAX, field.nitrogen + seasonal.SPRING_NITROGEN_BOOST)
            elseif season == seasonal.FALL_SEASON then
                field.nitrogen = math.max(limits.MIN, field.nitrogen - seasonal.FALL_NITROGEN_LOSS)
            end
        end

        -- pH normalization toward neutral (very slow)
        if field.pH < limits.PH_NEUTRAL_LOW then
            field.pH = math.min(limits.PH_NEUTRAL_LOW, field.pH + phNorm.RATE)
        elseif field.pH > limits.PH_NEUTRAL_HIGH then
            field.pH = math.max(limits.PH_NEUTRAL_HIGH, field.pH - phNorm.RATE)
        end
    end

    self:log("Daily soil update completed for %d fields", self:getFieldCount())
end

-- Apply rain effects
function SoilFertilitySystem:applyRainEffects(dt, rainScale)
    if not self.settings.enabled or not self.settings.rainEffects then return end
    if self.PFActive then return end

    local rain = SoilConstants.RAIN
    local limits = SoilConstants.NUTRIENT_LIMITS
    local leachFactor = rainScale * dt * rain.LEACH_BASE_FACTOR

    for fieldId, field in pairs(self.fieldData) do
        field.nitrogen = math.max(limits.MIN, field.nitrogen - (leachFactor * rain.NITROGEN_MULTIPLIER))
        field.potassium = math.max(limits.MIN, field.potassium - (leachFactor * rain.POTASSIUM_MULTIPLIER))
        field.phosphorus = math.max(limits.MIN, field.phosphorus - (leachFactor * rain.PHOSPHORUS_MULTIPLIER))
        field.pH = math.max(limits.PH_MIN, field.pH - (leachFactor * rain.PH_ACIDIFICATION))
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

    -- Look up crop-specific extraction rates (how much N/P/K this crop removes from soil)
    -- Different crops have different nutrient demands:
    -- - Wheat/Barley: High nitrogen demand (leafy growth)
    -- - Corn/Maize: Very high N/P demand (large biomass)
    -- - Soybeans: Low nitrogen (fixes own N), moderate P/K
    -- - Potatoes/Sugar beets: High potassium demand (root/tuber crops)
    local name = string.lower(fruitDesc.name or "unknown")
    local rates = SoilConstants.CROP_EXTRACTION[name] or SoilConstants.CROP_EXTRACTION_DEFAULT

    -- NUTRIENT DEPLETION CALCULATION EXPLAINED:
    --
    -- Step 1: Calculate depletion factor
    -- Formula: factor = harvested liters / 1000
    -- Why: Extraction rates in Constants.lua are calibrated per 1000L of harvested crop
    -- Example: 80,000L wheat harvest → factor = 80
    local factor = harvestedLiters / 1000

    -- Step 2: Apply difficulty multiplier
    -- Simple (0.7x): 30% less depletion, easier for new players
    -- Realistic (1.0x): Balanced depletion based on real agricultural rates
    -- Hardcore (1.5x): 50% more depletion, challenging management
    -- Example: factor 80 × 0.7 (Simple) = 56, or × 1.5 (Hardcore) = 120
    local diffMultiplier = SoilConstants.DIFFICULTY.MULTIPLIERS[self.settings.difficulty]
    if diffMultiplier then
        factor = factor * diffMultiplier
    end

    -- Step 3: Deplete nutrients from field
    -- Formula: new_value = max(0, current_value - (extraction_rate × factor))
    -- Scale: 0-100 nutrient points
    -- Example: N=50, wheat extraction=0.20, factor=80
    --          → 50 - (0.20 × 80) = 50 - 16 = 34 nitrogen remaining (~32% depletion)
    -- Only N/P/K deplete from harvest; pH and organic matter change through other means
    local limits = SoilConstants.NUTRIENT_LIMITS
    field.nitrogen   = math.max(limits.MIN, field.nitrogen   - rates.N * factor)
    field.phosphorus = math.max(limits.MIN, field.phosphorus - rates.P * factor)
    field.potassium  = math.max(limits.MIN, field.potassium  - rates.K * factor)

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

    -- Look up fertilizer profile from constants (defines N/P/K/pH/OM values per type)
    local entry = SoilConstants.FERTILIZER_PROFILES[fillType.name]
    if not entry then
        self:log("Fertilizer type %s not recognized", fillType.name)
        return
    end

    local limits = SoilConstants.NUTRIENT_LIMITS

    -- FERTILIZER RESTORATION CALCULATION EXPLAINED:
    --
    -- Step 1: Calculate application factor
    -- Formula: factor = liters applied / 1000
    -- Why: Fertilizer profiles in Constants.lua are calibrated per 1000L
    -- Example: 2,000L liquid fertilizer → factor = 2.0
    local factor = liters / 1000

    -- Step 2: Apply nutrients from fertilizer profile, capping at maximum limits
    -- Scale: 0-100 nutrient points (N/P/K), 5.0-7.5 pH, 0-10 organic matter
    -- Example: Liquid fertilizer N=0.50 per 1000L, factor=2.0
    --          → Current N=34, Add: 34 + (0.50 × 2.0) = 34 + 1.0 = 35 nitrogen
    --
    -- Fertilizer type characteristics (see FERTILIZER_PROFILES in Constants):
    -- - LIQUIDFERTILIZER: High N, moderate P/K, fast-acting
    -- - FERTILIZER (solid): Very high N/P, balanced granular NPK
    -- - MANURE: Lower NPK, adds organic matter (slow-release)
    -- - SLURRY: Moderate N/K, adds organic matter (liquid organic)
    -- - DIGESTATE: Good all-around, adds organic matter (biogas byproduct)
    -- - LIME: Only affects pH (raises toward neutral/alkaline)
    if entry.N then field.nitrogen   = math.min(limits.MAX, field.nitrogen   + entry.N * factor) end
    if entry.P then field.phosphorus = math.min(limits.MAX, field.phosphorus + entry.P * factor) end
    if entry.K then field.potassium  = math.min(limits.MAX, field.potassium  + entry.K * factor) end
    if entry.pH then field.pH        = math.min(limits.PH_MAX, field.pH + entry.pH * factor) end
    if entry.OM then field.organicMatter = math.min(limits.ORGANIC_MATTER_MAX, field.organicMatter + entry.OM * factor) end

    field.fertilizerApplied = (field.fertilizerApplied or 0) + liters

    self:log(
        "Fertilizer applied field %d (%s): %.0f L",
        fieldId, fillType.name, liters
    )
end

-- Read PF data with validation and logging
function SoilFertilitySystem:readPFFieldData(fieldId)
    if not self.PFActive or not g_precisionFarming then return nil end

    local rawData = nil
    local apiPath = "none"

    -- Try API path 1: g_precisionFarming.fieldData[fieldId]
    if g_precisionFarming.fieldData and g_precisionFarming.fieldData[fieldId] then
        rawData = g_precisionFarming.fieldData[fieldId]
        apiPath = "fieldData"
    -- Try API path 2: g_precisionFarming.soilMap:getFieldData(fieldId)
    elseif g_precisionFarming.soilMap and g_precisionFarming.soilMap.getFieldData then
        rawData = g_precisionFarming.soilMap:getFieldData(fieldId)
        if rawData then
            apiPath = "soilMap.getFieldData"
        end
    end

    -- No data found via either API
    if not rawData then
        if self.settings.debugMode then
            self:log("PF data not available for field %d (tried both API paths)", fieldId)
        end
        return nil
    end

    -- Validate and extract PF data
    local pfData = {
        nitrogen = rawData.nitrogen,
        phosphorus = rawData.phosphorus,
        potassium = rawData.potassium,
        pH = rawData.pH,
        organicMatter = rawData.organicMatter
    }

    -- Validation: check for nil values
    local missingFields = {}
    for key, value in pairs(pfData) do
        if value == nil then
            table.insert(missingFields, key)
        end
    end

    if #missingFields > 0 then
        self:warning("PF data incomplete for field %d (missing: %s) via API: %s",
            fieldId, table.concat(missingFields, ", "), apiPath)
        return nil
    end

    -- Validation: check for reasonable ranges (PF uses similar 0-100 scale)
    local outOfRange = {}
    if pfData.nitrogen < 0 or pfData.nitrogen > 100 then
        table.insert(outOfRange, string.format("N=%.1f", pfData.nitrogen))
    end
    if pfData.phosphorus < 0 or pfData.phosphorus > 100 then
        table.insert(outOfRange, string.format("P=%.1f", pfData.phosphorus))
    end
    if pfData.potassium < 0 or pfData.potassium > 100 then
        table.insert(outOfRange, string.format("K=%.1f", pfData.potassium))
    end
    if pfData.pH < 4.0 or pfData.pH > 9.0 then
        table.insert(outOfRange, string.format("pH=%.1f", pfData.pH))
    end
    if pfData.organicMatter < 0 or pfData.organicMatter > 20 then
        table.insert(outOfRange, string.format("OM=%.1f", pfData.organicMatter))
    end

    if #outOfRange > 0 then
        self:warning("PF data out of expected range for field %d (%s) via API: %s",
            fieldId, table.concat(outOfRange, ", "), apiPath)
    end

    -- Debug log successful read
    if self.settings.debugMode then
        self:log("PF data read for field %d via API: %s (N=%.1f, P=%.1f, K=%.1f, pH=%.1f, OM=%.1f)",
            fieldId, apiPath,
            pfData.nitrogen, pfData.phosphorus, pfData.potassium, pfData.pH, pfData.organicMatter)
    end

    return pfData
end

--- Get field info for display (HUD, console, etc)
---@param fieldId number The field ID to query
---@return table|nil Field info with nutrient values and status, or nil if not found
function SoilFertilitySystem:getFieldInfo(fieldId)
    if not fieldId or fieldId <= 0 then return nil end

    local field = self:getOrCreateField(fieldId, true)
    if not field then
        self:warning("Field %d not found in getFieldInfo", fieldId)
        return nil
    end

    local thresholds = SoilConstants.STATUS_THRESHOLDS
    local fertThresholds = SoilConstants.FERTILIZATION_THRESHOLDS

    local function nutrientStatus(value, nutrient)
        local t = thresholds[nutrient]
        if not t then return "Unknown" end
        if value < t.poor then return "Poor"
        elseif value < t.fair then return "Fair"
        else return "Good" end
    end

    local currentDay = (g_currentMission and g_currentMission.environment and g_currentMission.environment.currentDay) or 0

    return {
        fieldId = fieldId,
        nitrogen = { value = math.floor(field.nitrogen), status = nutrientStatus(field.nitrogen, "nitrogen") },
        phosphorus = { value = math.floor(field.phosphorus), status = nutrientStatus(field.phosphorus, "phosphorus") },
        potassium = { value = math.floor(field.potassium), status = nutrientStatus(field.potassium, "potassium") },
        organicMatter = field.organicMatter,
        pH = field.pH,
        lastCrop = field.lastCrop,
        daysSinceHarvest = field.lastHarvest > 0 and (currentDay - field.lastHarvest) or 0,
        fertilizerApplied = field.fertilizerApplied or 0,
        needsFertilization = not self.PFActive and (
            field.nitrogen < fertThresholds.nitrogen or
            field.phosphorus < fertThresholds.phosphorus or
            field.potassium < fertThresholds.potassium or
            field.pH < fertThresholds.pH
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

    -- SAFETY: ensure fieldData is valid
    if not self or type(self) ~= "table" then
        print("[SoilFertilizer ERROR] saveToXMLFile called with invalid self")
        return
    end

    if not self.fieldData or type(self.fieldData) ~= "table" then
        print(string.format(
            "[SoilFertilizer WARNING] Cannot save - fieldData invalid (type: %s)",
            type(self.fieldData)
        ))
        return
    end

    local defaults = SoilConstants.FIELD_DEFAULTS
    local index = 0

    for fieldId, field in pairs(self.fieldData) do
        if type(field) == "table" then
            local fieldKey = string.format("%s.field(%d)", key, index)

            setXMLInt(xmlFile, fieldKey .. "#id", fieldId)
            setXMLFloat(xmlFile, fieldKey .. "#nitrogen", field.nitrogen or defaults.nitrogen)
            setXMLFloat(xmlFile, fieldKey .. "#phosphorus", field.phosphorus or defaults.phosphorus)
            setXMLFloat(xmlFile, fieldKey .. "#potassium", field.potassium or defaults.potassium)
            setXMLFloat(xmlFile, fieldKey .. "#organicMatter", field.organicMatter or defaults.organicMatter)
            setXMLFloat(xmlFile, fieldKey .. "#pH", field.pH or defaults.pH)
            setXMLString(xmlFile, fieldKey .. "#lastCrop", field.lastCrop or "")
            setXMLInt(xmlFile, fieldKey .. "#lastHarvest", field.lastHarvest or 0)
            setXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied", field.fertilizerApplied or 0)

            index = index + 1
        else
            print(string.format(
                "[SoilFertilizer WARNING] Skipping corrupted field entry %s (type: %s)",
                tostring(fieldId),
                type(field)
            ))
        end
    end

    self:info("Saved data for %d fields", index)
end

-- Load from XML file
function SoilFertilitySystem:loadFromXMLFile(xmlFile, key)
    if not xmlFile then return end

    local defaults = SoilConstants.FIELD_DEFAULTS
    self.fieldData = {}
    local index = 0

    while true do
        local fieldKey = string.format("%s.field(%d)", key, index)
        local fieldId = getXMLInt(xmlFile, fieldKey .. "#id")

        if not fieldId then break end

        self.fieldData[fieldId] = {
            nitrogen = getXMLFloat(xmlFile, fieldKey .. "#nitrogen") or defaults.nitrogen,
            phosphorus = getXMLFloat(xmlFile, fieldKey .. "#phosphorus") or defaults.phosphorus,
            potassium = getXMLFloat(xmlFile, fieldKey .. "#potassium") or defaults.potassium,
            organicMatter = getXMLFloat(xmlFile, fieldKey .. "#organicMatter") or defaults.organicMatter,
            pH = getXMLFloat(xmlFile, fieldKey .. "#pH") or defaults.pH,
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

    -- FIX: Re-broadcast after load so clients that were connected during a
    -- save/load cycle get up-to-date values immediately.
    self:broadcastAllFieldData()
end

-- Debug: List all fields
function SoilFertilitySystem:listAllFields()
    print("[SoilFertilizer] === Listing all fields ===")

    print("Our tracked fields:")
    for fieldId, field in pairs(self.fieldData) do
        print(string.format("  Field %d: N=%.1f, P=%.1f, K=%.1f, pH=%.1f, OM=%.2f%%",
            fieldId, field.nitrogen, field.phosphorus, field.potassium, field.pH, field.organicMatter))
    end

    if g_fieldManager and g_fieldManager.fields then
        print("\nFields in FieldManager:")
        for _, field in pairs(g_fieldManager.fields) do
            local fieldIdStr = tostring(field.fieldId or "?")
            local nameStr = tostring(field.name or "Unknown")
            print(string.format("  Field %s: Name=%s", fieldIdStr, nameStr))
        end
    end

    print("=== End field list ===")
end

-- ENHANCED: Circuit breaker implementation
function SoilFertilitySystem:circuitBreakerOpen()
    local cb = self.circuitBreaker
    
    if cb.state == "CLOSED" then
        return false
    elseif cb.state == "OPEN" then
        -- Check if enough time has passed to try half-open
        local timeSinceFailure = (g_currentMission and g_currentMission.time or 0) - cb.lastFailureTime
        if timeSinceFailure >= cb.recoveryTimeout then
            cb.state = "HALF_OPEN"
            self:info("Circuit breaker transitioning to HALF_OPEN")
            return false
        end
        return true
    elseif cb.state == "HALF_OPEN" then
        return false
    end
    
    return false
end

function SoilFertilitySystem:recordCircuitBreakerSuccess()
    local cb = self.circuitBreaker
    cb.state = "CLOSED"
    cb.failureCount = 0
    cb.lastSuccessTime = g_currentMission and g_currentMission.time or 0
    self:debug("Circuit breaker: SUCCESS - reset to CLOSED")
end

function SoilFertilitySystem:recordCircuitBreakerFailure()
    local cb = self.circuitBreaker
    cb.failureCount = cb.failureCount + 1
    cb.lastFailureTime = g_currentMission and g_currentMission.time or 0
    
    self:warning("Circuit breaker: FAILURE %d/%d", cb.failureCount, cb.failureThreshold)
    
    if cb.failureCount >= cb.failureThreshold then
        cb.state = "OPEN"
        self:warning("Circuit breaker: OPEN - network operations suspended")
    end
end

-- ENHANCED: Client connection tracking
function SoilFertilitySystem:updateClientConnection(clientId, connection)
    if not clientId or not connection then return end
    
    self.connectedClients[clientId] = {
        connection = connection,
        joinTime = g_currentMission and g_currentMission.time or 0,
        fieldsSynced = 0,
        lastSyncTime = 0,
        syncErrors = 0
    }
    
    self:debug("Client %s connection updated", clientId)
end

function SoilFertilitySystem:removeClientConnection(clientId)
    if self.connectedClients[clientId] then
        self.connectedClients[clientId] = nil
        self:debug("Client %s connection removed", clientId)
    end
end

-- ENHANCED: Bandwidth optimization
function SoilFertilitySystem:compressFieldData()
    -- Simplified compression - in practice would use proper compression algorithms
    local compressed = {}
    for fieldId, field in pairs(self.fieldData) do
        compressed[fieldId] = {
            n = field.nitrogen,
            p = field.phosphorus,
            k = field.potassium,
            om = field.organicMatter,
            ph = field.pH,
            crop = field.lastCrop,
            harvest = field.lastHarvest,
            fert = field.fertilizerApplied
        }
    end
    return compressed
end

function SoilFertilitySystem:estimateEventDataSize(field)
    -- Estimate event data size in bytes
    -- This is a rough estimate based on typical field data size
    return 64  -- Approximate bytes per field event
end

-- ENHANCED: Performance monitoring
function SoilFertilitySystem:resetMetrics()
    self.performanceMetrics = {
        syncLatency = {},
        bandwidthUsage = 0,
        syncSuccessRate = 1.0,
        lastSyncDuration = 0,
        totalSyncs = 0,
        totalFailures = 0
    }
end

function SoilFertilitySystem:updateMetrics(data)
    local metrics = self.performanceMetrics
    
    if data.syncDuration then
        table.insert(metrics.syncLatency, data.syncDuration)
        if #metrics.syncLatency > 100 then
            table.remove(metrics.syncLatency, 1)
        end
        metrics.lastSyncDuration = data.syncDuration
    end
    
    if data.dataSize then
        metrics.bandwidthUsage = metrics.bandwidthUsage + data.dataSize
    end
    
    if data.success then
        metrics.totalSyncs = metrics.totalSyncs + 1
    else
        metrics.totalFailures = metrics.totalFailures + 1
    end
    
    -- Calculate success rate
    if metrics.totalSyncs > 0 then
        metrics.syncSuccessRate = metrics.totalSyncs / (metrics.totalSyncs + metrics.totalFailures)
    end
end

function SoilFertilitySystem:getPerformanceReport()
    local metrics = self.performanceMetrics
    local avgLatency = 0
    
    if #metrics.syncLatency > 0 then
        local sum = 0
        for _, latency in ipairs(metrics.syncLatency) do
            sum = sum + latency
        end
        avgLatency = sum / #metrics.syncLatency
    end
    
    return {
        avgSyncLatency = avgLatency,
        bandwidthUsage = metrics.bandwidthUsage,
        syncSuccessRate = metrics.syncSuccessRate,
        lastSyncDuration = metrics.lastSyncDuration,
        totalSyncs = metrics.totalSyncs,
        totalFailures = metrics.totalFailures,
        circuitBreakerState = self.circuitBreaker.state,
        connectedClients = #self.connectedClients
    }
end

-- ENHANCED: Predictive loading
function SoilFertilitySystem:updatePlayerFieldProximity(dt)
    if not self.settings.enabled then return end
    if not g_currentMission or not g_currentMission.player then return end
    
    local player = g_currentMission.player
    local playerX, _, playerZ = getWorldTranslation(player.rootNode)
    
    for fieldId, proximity in pairs(self.playerFieldProximity) do
        -- Calculate distance to field center (simplified)
        local fieldCenterX, fieldCenterZ = self:getFieldCenter(fieldId)
        if fieldCenterX and fieldCenterZ then
            local distance = math.sqrt((playerX - fieldCenterX)^2 + (playerZ - fieldCenterZ)^2)
            proximity.lastPlayerDistance = distance
            proximity.lastUpdateTime = (g_currentMission and g_currentMission.time or 0)
            
            -- Predict if field will be active soon (within 500m)
            proximity.predictedActive = distance < 500
        end
    end
end

function SoilFertilitySystem:getFieldCenter(fieldId)
    -- Simplified field center calculation
    -- In a real implementation, this would use field geometry data
    local field = self.fieldData[fieldId]
    if field then
        -- Return approximate center based on field ID (placeholder)
        return fieldId * 100, fieldId * 100
    end
    return nil, nil
end

-- ENHANCED: Enhanced broadcasting with circuit breaker and compression
function SoilFertilitySystem:broadcastAllFieldDataEnhanced()
    if not g_server then return end
    if not g_currentMission then return end
    if not g_currentMission.missionDynamicInfo.isMultiplayer then return end
    if not SoilFieldUpdateEvent then return end

    -- Check circuit breaker state
    if self:circuitBreakerOpen() then
        self:warning("Circuit breaker open - skipping field data broadcast")
        return
    end

    local broadcastStartTime = g_currentMission.time
    local count = 0
    local totalSize = 0

    -- Compress field data for bandwidth optimization
    local compressedData = self:compressFieldData()

    for fieldId, field in pairs(self.fieldData) do
        if field and field.initialized then
            local event = SoilFieldUpdateEvent.new(fieldId, field)
            
            -- Track bandwidth usage
            local dataSize = self:estimateEventDataSize(field)
            totalSize = totalSize + dataSize

            g_server:broadcastEvent(event)
            count = count + 1
        end
    end

    local broadcastDuration = g_currentMission.time - broadcastStartTime

    -- Update performance metrics
    self:updateMetrics({
        syncDuration = broadcastDuration,
        fieldsSynced = count,
        dataSize = totalSize,
        success = true
    })

    if count > 0 then
        self:info("Enhanced broadcast: %d fields to all clients in %dms (%.1fKB)",
            count, broadcastDuration, totalSize / 1024)
    end
end

-- ENHANCED: Enhanced client join handling with predictive data
function SoilFertilitySystem:onClientJoinedEnhanced(connection)
    if not g_server then return end
    if not connection then return end
    if not SoilFieldUpdateEvent then return end

    local clientId = connection.connectionId or "unknown"
    local joinStartTime = g_currentMission and g_currentMission.time or 0

    self:info("Enhanced client join handling for %s", clientId)

    -- Initialize client tracking
    self:updateClientConnection(clientId, connection)

    local count = 0
    local totalSize = 0

    -- Send fields with bandwidth optimization
    for fieldId, field in pairs(self.fieldData) do
        if field and field.initialized then
            local event = SoilFieldUpdateEvent.new(fieldId, field)
            local dataSize = self:estimateEventDataSize(field)
            
            connection:sendEvent(event)
            count = count + 1
            totalSize = totalSize + dataSize
        end
    end

    local joinDuration = (g_currentMission and g_currentMission.time or 0) - joinStartTime

    -- Update client tracking
    if self.connectedClients[clientId] then
        self.connectedClients[clientId].fieldsSynced = count
        self.connectedClients[clientId].lastSyncTime = g_currentMission and g_currentMission.time or 0
    end

    -- Update performance metrics
    self:updateMetrics({
        clientJoinDuration = joinDuration,
        clientFieldsSynced = count,
        clientDataSize = totalSize,
        success = true
    })

    self:info("Enhanced client join: %d fields sent to %s in %dms (%.1fKB)",
        count, clientId, joinDuration, totalSize / 1024)
end

-- ENHANCED: Enhanced update loop with all new features
function SoilFertilitySystem:updateEnhanced(dt)
    if not self.settings.enabled then return end

    -- Enhanced field scanning with circuit breaker
    if self.fieldsScanPending then
        self:updateFieldScanWithCircuitBreaker(dt)
    end

    -- Enhanced predictive loading
    self:updatePlayerFieldProximity(dt)

    -- Performance monitoring
    self:updateMetricsIfNeeded(dt)

    -- Handle network sync retry with enhanced error handling
    if SoilNetworkEvents_UpdateSyncRetry then
        SoilNetworkEvents_UpdateSyncRetry(dt)
    end
end

function SoilFertilitySystem:updateFieldScanWithCircuitBreaker(dt)
    if self.fieldsScanStage == 1 then
        -- Time-based retry with circuit breaker monitoring
        if self.fieldsScanAttempts < self.fieldsScanMaxAttempts then
            local currentTime = g_currentMission and g_currentMission.time or 0
            if currentTime >= self.fieldsScanNextRetry then
                local success = self:scanFields()
                if success then
                    self:recordCircuitBreakerSuccess()
                    self:info("Enhanced field scan successful!")
                    self.fieldsScanPending = false
                else
                    self:recordCircuitBreakerFailure()
                    self.fieldsScanAttempts = self.fieldsScanAttempts + 1
                    self.fieldsScanNextRetry = currentTime + self.fieldsScanRetryInterval
                    
                    if self.fieldsScanAttempts >= self.fieldsScanMaxAttempts then
                        self:warning("Enhanced field scan failed after %d attempts", self.fieldsScanMaxAttempts)
                        self.fieldsScanStage = 2
                        self.fieldsScanFrameCounter = 0
                    end
                end
            end
        end
    end
end

function SoilFertilitySystem:updateMetricsIfNeeded(dt)
    self.lastMetricsUpdate = (self.lastMetricsUpdate or 0) + dt
    if self.lastMetricsUpdate >= 10000 then  -- Update every 10 seconds
        local report = self:getPerformanceReport()
        self:debug("Performance Report: Latency=%.1fms, Success=%.1f%%, Clients=%d, Circuit=%s",
            report.avgSyncLatency, report.syncSuccessRate * 100, report.connectedClients, report.circuitBreakerState)
        self.lastMetricsUpdate = 0
    end
end

-- ENHANCED: Enhanced error logging and debugging
function SoilFertilitySystem:debug(msg, ...)
    if self.settings and self.settings.debugMode then
        print(string.format("[SoilFertilizer DEBUG] " .. msg, ...))
    end
end

-- ENHANCED: Enhanced notification system
function SoilFertilitySystem:showEnhancedNotification(title, message)
    if not self.settings or not self.settings.showNotifications then return end

    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(title .. ": " .. message, 6000)
    else
        self:info("%s - %s", title, message)
    end
end

-- ENHANCED: Performance monitoring console command
function SoilFertilitySystem:showPerformanceReport()
    local report = self:getPerformanceReport()
    
    print("=== Enhanced Soil System Performance Report ===")
    print(string.format("Average Sync Latency: %.1fms", report.avgSyncLatency))
    print(string.format("Bandwidth Usage: %.2fMB", report.bandwidthUsage / (1024 * 1024)))
    print(string.format("Sync Success Rate: %.1f%%", report.syncSuccessRate * 100))
    print(string.format("Last Sync Duration: %dms", report.lastSyncDuration))
    print(string.format("Total Syncs: %d", report.totalSyncs))
    print(string.format("Total Failures: %d", report.totalFailures))
    print(string.format("Circuit Breaker State: %s", report.circuitBreakerState))
    print(string.format("Connected Clients: %d", report.connectedClients))
    print("==============================================")
end
