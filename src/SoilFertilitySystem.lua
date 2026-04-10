-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Core Simulation
-- =========================================================
-- Per-field N/P/K/pH/OM tracking: depletion on harvest,
-- restoration on fertilizer, rain leaching, seasonal effects,
-- fallow recovery, Precision Farming compatibility.
-- =========================================================
-- Author: TisonK
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
    self.lastUpdateDay = 0
    self.hookManager = HookManager.new()

    -- Per-day flag table for fertilizer application notifications (fieldId → game day last shown)
    -- Prevents notification spam since the sprayer hook fires every frame while active.
    -- Stores the game day, not a timestamp, so the notification fires at most once per field per in-game day.
    self.fertNotifyShown = {}

    -- Per-day throttle tables for crop protection pressure reductions (fieldId → game day last applied).
    -- The sprayer hook fires every frame while the sprayer is active. Without throttling, a single
    -- pass across a field applies the full pressure reduction 60+ times per second, instantly
    -- resetting weed/pest/disease pressure to 0 from even 1L of product applied.
    -- Fix: allow at most ONE reduction event per field per in-game day, matching real-world
    -- application logic (you spray a field once per day at most, not 3600 times per minute).
    self.herbicideAppliedDay  = {}   -- fieldId → game day herbicide last reduced pressure
    self.insecticideAppliedDay = {}  -- fieldId → game day insecticide last reduced pressure
    self.fungicideAppliedDay  = {}   -- fieldId → game day fungicide last reduced pressure

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

    return self
end

-- Initialize system with ALL real hooks
function SoilFertilitySystem:initialize()
    if self.isInitialized then
        self:info("System already initialized, skipping")
        return
    end

    self:info("Initializing Soil Fertility System...")

    -- Scan fields using real FieldManager
    if g_fieldManager then
        self:scanFields()
    else
        self:warning("FieldManager not available - will try delayed initialization")
    end

    -- Install hooks via HookManager
    self.hookManager:installAll(self)

    self.isInitialized = true
    self:info("Soil Fertility System initialized successfully")
    self:info("Fertility System: %s, Nutrient Cycles: %s",
        tostring(self.settings.fertilitySystem),
        tostring(self.settings.nutrientCycles))

    -- Log multifruit compatibility status
    self:logCropProfileStatus()

    -- Show notification
    if self.settings.enabled and self.settings.showNotifications then
        self:showNotification("Soil & Fertilizer Mod Active", "Real soil system with full event hooks")
    end
end

-- Log which registered fruit types have explicit extraction profiles
-- and which will use the fallback (multifruit/custom map crops).
function SoilFertilitySystem:logCropProfileStatus()
    if not g_fruitTypeManager then return end
    local fruitTypes = g_fruitTypeManager:getFruitTypes()
    if not fruitTypes then return end

    local explicit = {}
    local fallback = {}

    for _, fruitDesc in pairs(fruitTypes) do
        local name = fruitDesc and fruitDesc.name
        if name then
            local lowerName = string.lower(name)
            if SoilConstants.CROP_EXTRACTION[lowerName] then
                table.insert(explicit, name)
            else
                table.insert(fallback, name)
            end
        end
    end

    table.sort(explicit)
    table.sort(fallback)

    local def = SoilConstants.CROP_EXTRACTION_DEFAULT
    self:info("Crop profiles: %d explicit, %d using fallback (N=%.2f P=%.2f K=%.2f)",
        #explicit, #fallback, def.N, def.P, def.K)
    if #explicit > 0 then
        self:info("  Explicit: %s", table.concat(explicit, ", "))
    end
    if #fallback > 0 then
        self:info("  Fallback (multifruit/unknown): %s", table.concat(fallback, ", "))
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
---@param strawRatio number 0.0-1.0 fraction of straw that was chopped (0 = dropped/collected, 1 = fully chopped)
function SoilFertilitySystem:onHarvest(fieldId, fruitTypeIndex, liters, strawRatio, area)
    -- Apply weed pressure yield penalty before nutrient update
    if self.settings.weedPressure and SoilConstants.WEED_PRESSURE then
        local field = self.fieldData[fieldId]
        if field then
            local wp = SoilConstants.WEED_PRESSURE
            local pressure = field.weedPressure or 0
            local penalty
            if pressure < wp.LOW then
                penalty = wp.YIELD_PENALTY_LOW
            elseif pressure < wp.MEDIUM then
                penalty = wp.YIELD_PENALTY_MID
            elseif pressure < wp.HIGH then
                penalty = wp.YIELD_PENALTY_HIGH
            else
                penalty = wp.YIELD_PENALTY_PEAK
            end
            if penalty > 0 then
                liters = liters * (1.0 - penalty)
                self:log("Weed penalty field %d: pressure=%.0f, penalty=%.0f%%",
                    fieldId, pressure, penalty * 100)
            end
        end
    end

    -- Pest pressure yield penalty
    if self.settings.pestPressure and SoilConstants.PEST_PRESSURE then
        local field = self.fieldData[fieldId]
        if field then
            local pp = SoilConstants.PEST_PRESSURE
            local pressure = field.pestPressure or 0
            local penalty
            if pressure < pp.LOW then
                penalty = pp.YIELD_PENALTY_LOW
            elseif pressure < pp.MEDIUM then
                penalty = pp.YIELD_PENALTY_MID
            elseif pressure < pp.HIGH then
                penalty = pp.YIELD_PENALTY_HIGH
            else
                penalty = pp.YIELD_PENALTY_PEAK
            end
            if penalty > 0 then
                liters = liters * (1.0 - penalty)
                self:log("Pest penalty field %d: pressure=%.0f, penalty=%.0f%%",
                    fieldId, pressure, penalty * 100)
            end
            -- Harvest disperses pest population
            field.pestPressure = pressure * pp.HARVEST_RESET_FRACTION
            field.insecticideDaysLeft = 0
        end
    end

    -- Disease pressure yield penalty
    if self.settings.diseasePressure and SoilConstants.DISEASE_PRESSURE then
        local field = self.fieldData[fieldId]
        if field then
            local dp = SoilConstants.DISEASE_PRESSURE
            local pressure = field.diseasePressure or 0
            local penalty
            if pressure < dp.LOW then
                penalty = dp.YIELD_PENALTY_LOW
            elseif pressure < dp.MEDIUM then
                penalty = dp.YIELD_PENALTY_MID
            elseif pressure < dp.HIGH then
                penalty = dp.YIELD_PENALTY_HIGH
            else
                penalty = dp.YIELD_PENALTY_PEAK
            end
            if penalty > 0 then
                liters = liters * (1.0 - penalty)
                self:log("Disease penalty field %d: pressure=%.0f, penalty=%.0f%%",
                    fieldId, pressure, penalty * 100)
            end
        end
    end

    self:updateFieldNutrients(fieldId, fruitTypeIndex, liters, strawRatio, area)

    SoilLogger.debug("Harvest: Field %d, Crop %d, %.0fL, area=%.1f", fieldId, fruitTypeIndex, liters, area or 0)

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

    local fillType = g_fillTypeManager and g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)

    SoilLogger.debug("Fertilizer: Field %d, %s, %.0fL", fieldId, fillType and fillType.name or "unknown", liters)

    -- Show application confirmation notification (singleplayer only; MP clients see HUD refresh via SoilFieldUpdateEvent)
    -- Shown at most once per field per in-game day to avoid spam (hook fires every frame while spraying)
    if self.settings.showNotifications and
       g_currentMission and not g_currentMission.missionDynamicInfo.isMultiplayer then
        local today = (g_currentMission.environment and g_currentMission.environment.currentDay) or 0
        if self.fertNotifyShown[fieldId] ~= today then
            self.fertNotifyShown[fieldId] = today
            local typeName = fillType and fillType.title or (fillType and fillType.name) or "Fertilizer"
            self:showNotification(
                "Fertilizer Recorded",
                string.format("%s on Field %d — nutrients absorb next game day", typeName, fieldId)
            )
        end
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

--- Hook delegate: called by HookManager when sowing/planting occurs on a field.
--- Clears the stale lastCrop so the HUD falls through to live FieldState detection
--- instead of showing the crop from the previous harvest (fix for issue #123).
---@param fieldId number The field being sown
function SoilFertilitySystem:onSowing(fieldId)
    if not fieldId or fieldId <= 0 then return end
    local field = self:getOrCreateField(fieldId, true)
    if not field then return end
    -- Clearing lastCrop here is safe: getFieldInfo() will immediately pick up the
    -- live fruitTypeIndex from FieldState:update() once the crop is in the ground.
    -- If FieldState somehow returns UNKNOWN in the first tick, we get "Fallow"
    -- momentarily (correct — seeds just went in, nothing is growing yet).
    field.lastCrop = nil
    SoilLogger.debug("Sowing on field %d: cleared lastCrop for fresh HUD detection", fieldId)
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

    -- Plowing benefit 3: Reset weed pressure to 0 (tillage buries weed seeds/roots)
    if self.settings.weedPressure and (field.weedPressure or 0) > 0 then
        self:log("[Plowing] Field %d: weed pressure %.0f -> 0 (tillage reset)", fieldId, field.weedPressure)
        field.weedPressure = 0
        field.herbicideDaysLeft = 0
        changed = true
    end

    -- Debug logging
    if self.settings.debugMode and changed then
        self:info("[Plowing] Field %d: OM %.1f->%.1f, pH %.2f->%.2f",
            fieldId, omBefore, omAfter, phBefore, phAfter)
    end

    -- Broadcast to clients if server in multiplayer
    if changed and g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if field and SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

--- Called when herbicide is applied to a field.
--- Reduces weed pressure and activates suppression window.
---@param fieldId number
---@param effectiveness number 0.0-1.0 herbicide effectiveness multiplier
function SoilFertilitySystem:onHerbicideApplied(fieldId, effectiveness)
    if not self.settings.weedPressure then return end
    if not SoilConstants.WEED_PRESSURE then return end

    local field = self:getOrCreateField(fieldId, false)
    if not field then return end

    -- Throttle: apply pressure reduction at most once per field per in-game day.
    -- The sprayer hook fires every frame (~60x/sec). Without this guard, a single
    -- pass applies the full reduction hundreds of times, instantly zeroing pressure.
    local today = (g_currentMission and g_currentMission.environment and
                   g_currentMission.environment.currentDay) or 0
    if self.herbicideAppliedDay[fieldId] == today then return end
    self.herbicideAppliedDay[fieldId] = today

    local wp = SoilConstants.WEED_PRESSURE
    local reduction = wp.HERBICIDE_PRESSURE_REDUCTION * (effectiveness or 1.0)
    local before = field.weedPressure or 0
    field.weedPressure = math.max(0, before - reduction)
    field.herbicideDaysLeft = wp.HERBICIDE_DURATION_DAYS

    self:log("[Herbicide] Field %d: weed pressure %.0f -> %.0f, protected for %d days",
        fieldId, before, field.weedPressure, field.herbicideDaysLeft)

    -- Broadcast in multiplayer
    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

--- Called when insecticide is applied to a field.
---@param fieldId number
---@param effectiveness number 0.0-1.0 insecticide effectiveness multiplier
function SoilFertilitySystem:onInsecticideApplied(fieldId, effectiveness)
    if not self.settings.pestPressure then return end
    if not SoilConstants.PEST_PRESSURE then return end

    local field = self:getOrCreateField(fieldId, false)
    if not field then return end

    -- Throttle: once per field per in-game day (see onHerbicideApplied for rationale)
    local today = (g_currentMission and g_currentMission.environment and
                   g_currentMission.environment.currentDay) or 0
    if self.insecticideAppliedDay[fieldId] == today then return end
    self.insecticideAppliedDay[fieldId] = today

    local pp = SoilConstants.PEST_PRESSURE
    local reduction = pp.INSECTICIDE_PRESSURE_REDUCTION * (effectiveness or 1.0)
    local before = field.pestPressure or 0
    field.pestPressure = math.max(0, before - reduction)
    field.insecticideDaysLeft = pp.INSECTICIDE_DURATION_DAYS

    self:log("[Insecticide] Field %d: pest pressure %.0f -> %.0f, protected for %d days",
        fieldId, before, field.pestPressure, field.insecticideDaysLeft)

    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

--- Called when fungicide is applied to a field.
---@param fieldId number
---@param effectiveness number 0.0-1.0 fungicide effectiveness multiplier
function SoilFertilitySystem:onFungicideApplied(fieldId, effectiveness)
    if not self.settings.diseasePressure then return end
    if not SoilConstants.DISEASE_PRESSURE then return end

    local field = self:getOrCreateField(fieldId, false)
    if not field then return end

    -- Throttle: once per field per in-game day (see onHerbicideApplied for rationale)
    local today = (g_currentMission and g_currentMission.environment and
                   g_currentMission.environment.currentDay) or 0
    if self.fungicideAppliedDay[fieldId] == today then return end
    self.fungicideAppliedDay[fieldId] = today

    local dp = SoilConstants.DISEASE_PRESSURE
    local reduction = dp.FUNGICIDE_PRESSURE_REDUCTION * (effectiveness or 1.0)
    local before = field.diseasePressure or 0
    field.diseasePressure = math.max(0, before - reduction)
    field.fungicideDaysLeft = dp.FUNGICIDE_DURATION_DAYS

    self:log("[Fungicide] Field %d: disease pressure %.0f -> %.0f, protected for %d days",
        fieldId, before, field.diseasePressure, field.fungicideDaysLeft)

    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if SoilFieldUpdateEvent then
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
    SoilLogger.debug(msg, ...)
end

function SoilFertilitySystem:info(msg, ...)
    SoilLogger.info(msg, ...)
end

function SoilFertilitySystem:warning(msg, ...)
    SoilLogger.warning(msg, ...)
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
    -- field.fieldId / field.id / field.index do NOT exist in FS25 — all return nil.
    -- The correct field identifier is field.farmland.id (confirmed in-game).
    -- g_currentMission.fieldManager does not exist; use the global g_fieldManager.fields table directly.
    if not g_fieldManager or not g_fieldManager.fields then
        self:warning("g_fieldManager.fields not available — scan deferred")
        return false
    end
    local fields = g_fieldManager.fields
    for _, field in ipairs(fields) do
        if field and type(field) == "table" then
            local actualFieldId = field.farmland and field.farmland.id

            if actualFieldId and actualFieldId > 0 then
                -- FS25: field.fieldArea is the cultivated area in hectares.
                -- Fallback to farmland area if fieldArea is missing (though it shouldn't be).
                local area = field.fieldArea or (field.farmland and field.farmland.area) or 1.0
                
                SoilLogger.debug("Found field %d (%.2f ha)", actualFieldId, area)

                self:getOrCreateField(actualFieldId, true, area)
                fieldCount = fieldCount + 1
            end
        end
    end

    self:info("Scanned %d farmlands and initialized %d fields", farmlandCount, fieldCount)

    if fieldCount > 0 then
        self.fieldsScanPending = false

        -- Broadcast all field data to connected clients immediately after scan.
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

-- Get or create field data
function SoilFertilitySystem:getOrCreateField(fieldId, createIfMissing, area)
    if not fieldId or fieldId <= 0 then return nil end

    -- Return existing field
    if self.fieldData[fieldId] then
        -- Update area if provided (handles initial scan or later updates)
        if area and area > 0 then
            self.fieldData[fieldId].fieldArea = area
        end
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

    -- Allow lazy creation (HUD-safe, server-only in multiplayer)
    -- Add natural soil variation: ±10% for nutrients, ±0.5 for pH, ±0.5% for OM
    -- This reflects real-world soil diversity across a map.
    --
    -- Use a deterministic hash instead of math.randomseed() to avoid polluting
    -- the global Lua random state (math.randomseed resets the shared PRNG, which
    -- disrupts any other code using math.random() in the same frame — e.g. during
    -- the initial bulk field scan where many fields are created simultaneously).
    local function hash(n)
        -- Lua 5.1-compatible deterministic hash (LCG-style, no bitwise ops).
        -- Produces a float in [0.0, 1.0) that is stable for the same (fieldId, slot) pair
        -- across save/load cycles. Avoids touching math.randomseed (global state).
        n = (n * 1664525 + 1013904223) % 4294967296
        n = (n * 1664525 + 1013904223) % 4294967296
        return n / 4294967296
    end
    local function randField(slot)
        -- Each nutrient gets its own deterministic slot so values are independent
        local r = hash(fieldId * 67890 + slot)
        return r * 2.0 - 1.0  -- range [-1.0, 1.0]
    end

    local function randomize(baseValue, variation, slot)
        return baseValue + randField(slot) * variation
    end

    local defaults = SoilConstants.FIELD_DEFAULTS

    self.fieldData[fieldId] = {
        fieldArea = area or 1.0, -- default 1ha if unknown
        nitrogen   = math.floor(randomize(defaults.nitrogen,   defaults.nitrogen   * 0.10, 1)),
        phosphorus = math.floor(randomize(defaults.phosphorus, defaults.phosphorus * 0.10, 2)),
        potassium  = math.floor(randomize(defaults.potassium,  defaults.potassium  * 0.10, 3)),
        organicMatter = math.max(1.0, math.min(10.0, randomize(defaults.organicMatter, 0.5, 4))),
        pH            = math.max(5.0, math.min(8.5,  randomize(defaults.pH,            0.5, 5))),
        lastCrop = nil,
        lastCrop2 = nil,
        lastCrop3 = nil,
        rotationBonusDaysLeft = 0,
        lastHarvest = 0,
        fertilizerApplied = 0,
        initialized = true,
        weedPressure = 0,
        herbicideDaysLeft = 0,
        pestPressure = 0,
        insecticideDaysLeft = 0,
        diseasePressure = 0,
        fungicideDaysLeft = 0,
        dryDayCount = 0,
    }

    self:log("Lazy-created field %d with area %.2f ha and natural soil variation", fieldId, self.fieldData[fieldId].fieldArea)
    return self.fieldData[fieldId]
end

-- Daily soil update
function SoilFertilitySystem:updateDailySoil()
    if not self.settings.enabled or not self.settings.nutrientCycles then return end

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
        if self.settings.seasonalEffects and g_currentMission and g_currentMission.environment then
            local season = g_currentMission.environment.currentSeason
            if season == seasonal.SPRING_SEASON then
                field.nitrogen = math.min(limits.MAX, field.nitrogen + seasonal.SPRING_NITROGEN_BOOST)
            elseif season == seasonal.FALL_SEASON then
                field.nitrogen = math.max(limits.MIN, field.nitrogen - seasonal.FALL_NITROGEN_LOSS)
            end
        end

        -- Crop rotation spring bonus
        if self.settings.cropRotation and g_currentMission and g_currentMission.environment then
            local season = g_currentMission.environment.currentSeason
            -- On first day of spring: initialise bonus counter for qualifying fields
            if season == seasonal.SPRING_SEASON and self.lastSeason ~= seasonal.SPRING_SEASON then
                if field.lastCrop and field.lastCrop2 then
                    local cr = SoilConstants.CROP_ROTATION
                    local c1 = string.lower(field.lastCrop)
                    local c2 = string.lower(field.lastCrop2)
                    if cr.LEGUMES[c1] and not cr.LEGUMES[c2]
                       and (field.rotationBonusDaysLeft or 0) == 0 then
                        field.rotationBonusDaysLeft = cr.LEGUME_BONUS_DAYS
                    end
                end
            end
            -- Apply bonus while counter > 0 in spring
            if season == seasonal.SPRING_SEASON and (field.rotationBonusDaysLeft or 0) > 0 then
                local cr = SoilConstants.CROP_ROTATION
                field.nitrogen = math.min(limits.MAX, field.nitrogen + cr.LEGUME_BONUS_N_PER_DAY)
                field.rotationBonusDaysLeft = field.rotationBonusDaysLeft - 1
            end
        end

        -- pH normalization toward neutral (very slow)
        if field.pH < limits.PH_NEUTRAL_LOW then
            field.pH = math.min(limits.PH_NEUTRAL_LOW, field.pH + phNorm.RATE)
        elseif field.pH > limits.PH_NEUTRAL_HIGH then
            field.pH = math.max(limits.PH_NEUTRAL_HIGH, field.pH - phNorm.RATE)
        end

        -- Weed pressure daily growth
        if self.settings.weedPressure and SoilConstants.WEED_PRESSURE then
            local wp = SoilConstants.WEED_PRESSURE
            local pressure = field.weedPressure or 0
            local herbDays = field.herbicideDaysLeft or 0

            -- Decrement herbicide protection
            if herbDays > 0 then
                field.herbicideDaysLeft = herbDays - 1
            end

            -- Only grow when not under herbicide protection
            if (field.herbicideDaysLeft or 0) <= 0 then
                -- Base rate by current pressure tier
                local baseRate
                if pressure < wp.LOW then
                    baseRate = wp.GROWTH_RATE_LOW
                elseif pressure < wp.MEDIUM then
                    baseRate = wp.GROWTH_RATE_MID
                elseif pressure < wp.HIGH then
                    baseRate = wp.GROWTH_RATE_HIGH
                else
                    baseRate = wp.GROWTH_RATE_PEAK
                end

                -- Seasonal multiplier
                local seasonMult = 1.0
                if g_currentMission and g_currentMission.environment then
                    local season = g_currentMission.environment.currentSeason
                    if season == 1 then seasonMult = wp.SEASONAL_SPRING
                    elseif season == 2 then seasonMult = wp.SEASONAL_SUMMER
                    elseif season == 3 then seasonMult = wp.SEASONAL_FALL
                    elseif season == 4 then seasonMult = wp.SEASONAL_WINTER
                    end
                end

                field.weedPressure = math.min(100, pressure + baseRate * seasonMult)
            end
        end

        -- Pest pressure daily growth
        if self.settings.pestPressure and SoilConstants.PEST_PRESSURE then
            local pp = SoilConstants.PEST_PRESSURE

            -- Decrement insecticide protection
            if (field.insecticideDaysLeft or 0) > 0 then
                field.insecticideDaysLeft = field.insecticideDaysLeft - 1
            end

            -- Only grow when not under insecticide protection
            if (field.insecticideDaysLeft or 0) <= 0 then
                local pressure = field.pestPressure or 0

                -- Base rate by tier
                local baseRate
                if pressure < pp.LOW then
                    baseRate = pp.GROWTH_RATE_LOW
                elseif pressure < pp.MEDIUM then
                    baseRate = pp.GROWTH_RATE_MID
                elseif pressure < pp.HIGH then
                    baseRate = pp.GROWTH_RATE_HIGH
                else
                    baseRate = pp.GROWTH_RATE_PEAK
                end

                -- Seasonal multiplier
                local seasonMult = 1.0
                if g_currentMission and g_currentMission.environment then
                    local season = g_currentMission.environment.currentSeason
                    if season == 1 then seasonMult = pp.SEASONAL_SPRING
                    elseif season == 2 then seasonMult = pp.SEASONAL_SUMMER
                    elseif season == 3 then seasonMult = pp.SEASONAL_FALL
                    elseif season == 4 then seasonMult = pp.SEASONAL_WINTER
                    end
                end

                -- Crop susceptibility multiplier
                local cropMult = 1.0
                if field.lastCrop then
                    cropMult = pp.CROP_SUSCEPTIBILITY[string.lower(field.lastCrop)] or 1.0
                end

                -- Rain bonus (check current rain state)
                local rainBonus = 0
                if g_currentMission and g_currentMission.environment and
                   g_currentMission.environment.weather and
                   (g_currentMission.environment.weather.rainScale or 0) > SoilConstants.RAIN.MIN_RAIN_THRESHOLD then
                    rainBonus = pp.RAIN_BONUS
                end

                field.pestPressure = math.min(100, pressure + (baseRate * seasonMult * cropMult) + rainBonus)
            end
        end

        -- Disease pressure daily growth
        if self.settings.diseasePressure and SoilConstants.DISEASE_PRESSURE then
            local dp = SoilConstants.DISEASE_PRESSURE
            local isRaining = g_currentMission and g_currentMission.environment and
                              g_currentMission.environment.weather and
                              (g_currentMission.environment.weather.rainScale or 0) > SoilConstants.RAIN.MIN_RAIN_THRESHOLD

            -- Track consecutive dry days for natural decay
            if isRaining then
                field.dryDayCount = 0
            else
                field.dryDayCount = (field.dryDayCount or 0) + 1
            end

            -- Decrement fungicide protection
            if (field.fungicideDaysLeft or 0) > 0 then
                field.fungicideDaysLeft = field.fungicideDaysLeft - 1
            end

            local pressure = field.diseasePressure or 0

            -- Natural dry-weather decay (overrides growth)
            if (field.dryDayCount or 0) >= dp.DRY_DAYS_THRESHOLD then
                field.diseasePressure = math.max(0, pressure - dp.DRY_DECAY_RATE)
            elseif (field.fungicideDaysLeft or 0) <= 0 then
                -- Only grow when not protected

                local baseRate
                if pressure < dp.LOW then
                    baseRate = dp.GROWTH_RATE_LOW
                elseif pressure < dp.MEDIUM then
                    baseRate = dp.GROWTH_RATE_MID
                elseif pressure < dp.HIGH then
                    baseRate = dp.GROWTH_RATE_HIGH
                else
                    baseRate = dp.GROWTH_RATE_PEAK
                end

                local seasonMult = 1.0
                if g_currentMission and g_currentMission.environment then
                    local season = g_currentMission.environment.currentSeason
                    if season == 1 then seasonMult = dp.SEASONAL_SPRING
                    elseif season == 2 then seasonMult = dp.SEASONAL_SUMMER
                    elseif season == 3 then seasonMult = dp.SEASONAL_FALL
                    elseif season == 4 then seasonMult = dp.SEASONAL_WINTER
                    end
                end

                local cropMult = 1.0
                if field.lastCrop then
                    cropMult = dp.CROP_SUSCEPTIBILITY[string.lower(field.lastCrop)] or 1.0
                end

                local rainBonus = isRaining and dp.RAIN_BONUS or 0

                field.diseasePressure = math.min(100, pressure + (baseRate * seasonMult * cropMult) + rainBonus)
            end
        end

        -- Burn warning countdown — decrements each day until cleared
        if (field.burnDaysLeft or 0) > 0 then
            field.burnDaysLeft = field.burnDaysLeft - 1
        end

        -- Critical Field Alerts (before planting season, e.g., early spring)
        if self.settings.showNotifications and g_currentMission and g_currentMission.environment then
            local season = g_currentMission.environment.currentSeason
            local threshold = SoilConstants.CRITICAL_ALERT_THRESHOLD or 50
            if season == (SoilConstants.SEASONAL_EFFECTS and SoilConstants.SEASONAL_EFFECTS.SPRING_SEASON or 1) then
                local currentYear = g_currentMission.environment.currentYear or math.floor(currentDay / 12)
                if field.lastAlertYear ~= currentYear then
                    local urgency = self:getFieldUrgency(fieldId)
                    if urgency > threshold then
                        self:showNotification("Critical Field Alert", string.format("Field %d needs attention! Urgency Score: %d", fieldId, math.floor(urgency)))
                        field.lastAlertYear = currentYear
                    end
                end
            end
        end
    end

    -- Track season for spring-transition detection (crop rotation bonus)
    if g_currentMission and g_currentMission.environment then
        self.lastSeason = g_currentMission.environment.currentSeason
    end

    self:log("Daily soil update completed for %d fields", self:getFieldCount())
end

-- Apply rain effects
function SoilFertilitySystem:applyRainEffects(dt, rainScale)
    if not self.settings.enabled or not self.settings.rainEffects then return end

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
---@param strawRatio number 0.0-1.0 fraction of straw chopped back into the field (adds organic matter)
function SoilFertilitySystem:updateFieldNutrients(fieldId, fruitTypeIndex, harvestedLiters, strawRatio)
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

    -- Shift crop history before recording new crop (lastCrop → lastCrop2 → lastCrop3)
    field.lastCrop3 = field.lastCrop2
    field.lastCrop2 = field.lastCrop

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

    -- Step 3a: Crop rotation fatigue — same crop two seasons running depletes more
    if self.settings.cropRotation and field.lastCrop2 and field.lastCrop2 == fruitDesc.name then
        factor = factor * SoilConstants.CROP_ROTATION.FATIGUE_MULTIPLIER
        self:log("Rotation fatigue on field %d (%s harvested twice) — factor ×%.2f",
            fieldId, fruitDesc.name, SoilConstants.CROP_ROTATION.FATIGUE_MULTIPLIER)
    end

    -- Step 3b: Deplete nutrients from field
    -- Formula: new_value = max(0, current_value - (extraction_rate × factor))
    -- Scale: 0-100 nutrient points
    -- Example: N=50, wheat extraction=0.20, factor=80
    --          → 50 - (0.20 × 80) = 50 - 16 = 34 nitrogen remaining (~32% depletion)
    -- Only N/P/K deplete from harvest; pH and organic matter change through other means
    local limits = SoilConstants.NUTRIENT_LIMITS
    field.nitrogen   = math.max(limits.MIN, field.nitrogen   - rates.N * factor)
    field.phosphorus = math.max(limits.MIN, field.phosphorus - rates.P * factor)
    field.potassium  = math.max(limits.MIN, field.potassium  - rates.K * factor)

    -- Step 4: Chopped straw/chaff adds organic matter
    -- When strawRatio > 0 the combine is chopping material back into the field.
    -- The chopped biomass decomposes and increases soil organic matter.
    -- Formula: OM gain = (harvestedLiters / 1000) × strawRatio × OM_RATE
    local sr = strawRatio or 0
    if sr > 0 then
        local omGain = (harvestedLiters / 1000) * sr * SoilConstants.CHOPPED_STRAW.OM_RATE
        field.organicMatter = math.min(limits.ORGANIC_MATTER_MAX, (field.organicMatter or 0) + omGain)
    end

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

    -- Route crop protection products (they don't add N/P/K, they reduce pressure)
    if entry.pestReduction then
        local effectiveness = SoilConstants.PEST_PRESSURE.INSECTICIDE_TYPES[fillType.name] or 0
        if effectiveness > 0 then
            self:onInsecticideApplied(fieldId, effectiveness)
        end
        return
    end
    if entry.diseaseReduction then
        local effectiveness = SoilConstants.DISEASE_PRESSURE.FUNGICIDE_TYPES[fillType.name] or 0
        if effectiveness > 0 then
            self:onFungicideApplied(fieldId, effectiveness)
        end
        return
    end

    local limits = SoilConstants.NUTRIENT_LIMITS

    -- AREA NORMALIZATION: Calculate hectares for this field
    local areaInHa = field.fieldArea or 1.0
    if areaInHa <= 0 then areaInHa = 1.0 end

    -- FERTILIZER RESTORATION CALCULATION:
    -- factor = (liters per frame / 1000) / total field hectares
    -- This distributes the applied liters across the entire field's concentration.
    -- Example: 225L applied to 1ha → factor = 0.225 / 1.0 = 0.225
    -- Example: 225L applied to 10ha → factor = 0.225 / 10.0 = 0.0225
    -- (As the sprayer covers more ground, these small per-frame increases
    -- sum up to the correct total concentration change for the whole field.)
    local factor = (liters / 1000) / areaInHa

    if entry.N then field.nitrogen   = math.min(limits.MAX, field.nitrogen   + entry.N * factor) end
    if entry.P then field.phosphorus = math.min(limits.MAX, field.phosphorus + entry.P * factor) end
    if entry.K then field.potassium  = math.min(limits.MAX, field.potassium  + entry.K * factor) end
    if entry.pH then field.pH        = math.min(limits.PH_MAX, field.pH + entry.pH * factor) end
    if entry.OM then field.organicMatter = math.min(limits.ORGANIC_MATTER_MAX, field.organicMatter + entry.OM * factor) end

    field.fertilizerApplied = (field.fertilizerApplied or 0) + liters

    -- We only log high-precision values for fertilizer to track these small per-frame changes
    if self.settings.debugMode then
        self:log("Fertilizer applied field %d (%s): %.4f L -> +N %.6f (area %.2f ha)", 
            fieldId, fillType.name, liters, (entry.N or 0) * factor, areaInHa)
    end
end

--- Apply over-application burn penalty to a field.
--- Called by HookManager after fertilizer is applied at rate > BURN_RISK_THRESHOLD.
--- At risk threshold: probabilistic burn (probability scales linearly with excess).
--- At guaranteed threshold: burn every application.
--- Burn reduces pH and nitrogen to simulate salt/chemical soil damage.
---@param fieldId number
---@param rateMultiplier number The actual rate multiplier used (e.g. 1.5)
function SoilFertilitySystem:applyBurnEffect(fieldId, rateMultiplier)
    local field = self.fieldData[fieldId]
    if not field then return end

    local burnCfg = SoilConstants.SPRAYER_RATE
    local limits  = SoilConstants.NUTRIENT_LIMITS
    local phDrop  = 0
    local nDrain  = 0

    if rateMultiplier >= burnCfg.BURN_GUARANTEED_THRESHOLD then
        phDrop = burnCfg.BURN_PH_DROP_CERTAIN
        nDrain = burnCfg.BURN_N_DRAIN_CERTAIN
        field.burnDaysLeft = 3   -- show burn warning in HUD for 3 in-game days
    else
        -- Probability scales linearly between risk threshold and guaranteed threshold
        local excess = (rateMultiplier - burnCfg.BURN_RISK_THRESHOLD) /
                       (burnCfg.BURN_GUARANTEED_THRESHOLD - burnCfg.BURN_RISK_THRESHOLD)
        if math.random() < excess then
            phDrop = burnCfg.BURN_PH_DROP_RISK
            nDrain = burnCfg.BURN_N_DRAIN_RISK
            field.burnDaysLeft = 3
        end
    end

    if phDrop > 0 then
        field.pH       = math.max(limits.PH_MIN, field.pH - phDrop)
        field.nitrogen = math.max(limits.MIN, field.nitrogen - nDrain)

        self:log("Burn effect field %d: pH -%.2f, N -%.1f (rate=%.0f%%)",
            fieldId, phDrop, nDrain, rateMultiplier * 100)

        if self.settings.showNotifications then
            self:showNotification(
                "Fertilizer Burn",
                string.format("Field %d: over-application damage (pH %.1f)", fieldId, field.pH)
            )
        end

        -- Broadcast updated field data in multiplayer
        if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
            if SoilFieldUpdateEvent then
                g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
            end
        end
    end
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

    -- Resolve current crop name: prefer the live growing fruit (what's actually in
    -- the ground right now) over lastCrop, which is only set on harvest and will be
    -- stale as soon as the next crop is sown.
    -- #99 fix: field.id / field.fieldId are nil in FS25; our fieldId is farmland.id.
    -- g_fieldManager:getFieldById() searches by field.id which is always nil, so it
    -- returns the wrong field or nil depending on list position.
    -- Correct approach: iterate g_fieldManager.fields and match farmland.id.
    local cropName = nil
    if g_fieldManager and g_fieldManager.fields then
        local fsField = nil
        for _, f in ipairs(g_fieldManager.fields) do
            if f and f.farmland and f.farmland.id == fieldId then
                fsField = f
                break
            end
        end
        if fsField then
            -- Fix #123: Field:getFieldState() does NOT exist in FS25.
            -- FieldState is a standalone class; it must be instantiated and then
            -- populated by calling :update(worldX, worldZ) with a point inside the field.
            -- fsField.posX / posZ are the polygon centroid, set by Field:load() via
            -- MathUtil.getPolygonLabel(). They are always valid after field initialization.
            local centerX = fsField.posX
            local centerZ = fsField.posZ
            if centerX and centerZ then
                local ok, fieldState = pcall(function()
                    local fs = FieldState.new()
                    fs:update(centerX, centerZ)
                    return fs
                end)
                if ok and fieldState and fieldState.fruitTypeIndex ~= FruitType.UNKNOWN then
                    local fruitDesc = g_fruitTypeManager and
                        g_fruitTypeManager:getFruitTypeByIndex(fieldState.fruitTypeIndex)
                    if fruitDesc and fruitDesc.name then
                        cropName = fruitDesc.name
                    end
                end
            end
        end
    end
    -- Fall back to lastCrop when the field is fallow (no live fruit detected)
    if not cropName or cropName == "" then
        cropName = field.lastCrop
    end

    -- Compute crop rotation status for external consumers (e.g. FarmTablet)
    local rotationStatus = nil
    if SoilConstants.CROP_ROTATION and field.lastCrop and field.lastCrop2 then
        local cr      = SoilConstants.CROP_ROTATION
        local crop1   = string.lower(field.lastCrop)
        local crop2   = string.lower(field.lastCrop2)
        if cr.LEGUMES[crop1] and not cr.LEGUMES[crop2] then
            rotationStatus = "Bonus"
        elseif field.lastCrop == field.lastCrop2 then
            rotationStatus = "Fatigue"
        else
            rotationStatus = "OK"
        end
    end

    return {
        fieldId = fieldId,
        nitrogen = { value = math.floor(field.nitrogen), status = nutrientStatus(field.nitrogen, "nitrogen") },
        phosphorus = { value = math.floor(field.phosphorus), status = nutrientStatus(field.phosphorus, "phosphorus") },
        potassium = { value = math.floor(field.potassium), status = nutrientStatus(field.potassium, "potassium") },
        organicMatter = field.organicMatter,
        pH = field.pH,
        lastCrop = cropName,
        lastCrop2 = field.lastCrop2,
        rotationStatus = rotationStatus,
        daysSinceHarvest = field.lastHarvest > 0 and (currentDay - field.lastHarvest) or 0,
        fertilizerApplied = field.fertilizerApplied or 0,
        weedPressure = field.weedPressure or 0,
        herbicideActive = (field.herbicideDaysLeft or 0) > 0,
        pestPressure = field.pestPressure or 0,
        insecticideActive = (field.insecticideDaysLeft or 0) > 0,
        diseasePressure = field.diseasePressure or 0,
        fungicideActive = (field.fungicideDaysLeft or 0) > 0,
        burnDaysLeft = field.burnDaysLeft or 0,
        needsFertilization = (
            field.nitrogen < fertThresholds.nitrogen or
            field.phosphorus < fertThresholds.phosphorus or
            field.potassium < fertThresholds.potassium or
            field.pH < fertThresholds.pH
        )
    }
end

--- Calculate the urgency score (0-100) for a field
---@param fieldId number
---@return number
function SoilFertilitySystem:getFieldUrgency(fieldId)
    local info = self:getFieldInfo(fieldId)
    if not info then return 0 end

    local urgency = 0
    local thresh = SoilConstants.YIELD_SENSITIVITY and SoilConstants.YIELD_SENSITIVITY.OPTIMAL_THRESHOLD or 70
    
    local nDef = math.max(0, thresh - info.nitrogen.value) / thresh
    local pDef = math.max(0, thresh - info.phosphorus.value) / thresh
    local kDef = math.max(0, thresh - info.potassium.value) / thresh

    local phOpt = SoilConstants.PH_NORMALIZATION and SoilConstants.PH_NORMALIZATION.OPTIMAL or 6.5
    local phMin = SoilConstants.NUTRIENT_LIMITS and SoilConstants.NUTRIENT_LIMITS.PH_MIN or 5.0
    local phDef = math.max(0, phOpt - info.pH) / (phOpt - phMin)

    local weedDef = (info.weedPressure or 0) / 100
    local pestDef = (info.pestPressure or 0) / 100
    local diseaseDef = (info.diseasePressure or 0) / 100

    urgency = math.min(100, ((nDef + pDef + kDef + phDef + weedDef + pestDef + diseaseDef) / 7) * 100)
    return urgency
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
        SoilLogger.error("saveToXMLFile called with invalid self")
        return
    end

    if not self.fieldData or type(self.fieldData) ~= "table" then
        SoilLogger.warning("Cannot save - fieldData invalid (type: %s)", type(self.fieldData))
        return
    end

    local defaults = SoilConstants.FIELD_DEFAULTS
    local index = 0

    for fieldId, field in pairs(self.fieldData) do
        if type(field) == "table" then
            local fieldKey = string.format("%s.field(%d)", key, index)

            setXMLInt(xmlFile, fieldKey .. "#id", fieldId)
            setXMLFloat(xmlFile, fieldKey .. "#fieldArea", field.fieldArea or 1.0)
            setXMLFloat(xmlFile, fieldKey .. "#nitrogen", field.nitrogen or defaults.nitrogen)
            setXMLFloat(xmlFile, fieldKey .. "#phosphorus", field.phosphorus or defaults.phosphorus)
            setXMLFloat(xmlFile, fieldKey .. "#potassium", field.potassium or defaults.potassium)
            setXMLFloat(xmlFile, fieldKey .. "#organicMatter", field.organicMatter or defaults.organicMatter)
            setXMLFloat(xmlFile, fieldKey .. "#pH", field.pH or defaults.pH)
            setXMLString(xmlFile, fieldKey .. "#lastCrop", field.lastCrop or "")
            setXMLString(xmlFile, fieldKey .. "#lastCrop2", field.lastCrop2 or "")
            setXMLString(xmlFile, fieldKey .. "#lastCrop3", field.lastCrop3 or "")
            setXMLInt(xmlFile, fieldKey .. "#rotationBonusDaysLeft", field.rotationBonusDaysLeft or 0)
            setXMLInt(xmlFile, fieldKey .. "#lastHarvest", field.lastHarvest or 0)
            setXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied", field.fertilizerApplied or 0)
            setXMLFloat(xmlFile, fieldKey .. "#weedPressure", field.weedPressure or 0)
            setXMLInt(xmlFile, fieldKey .. "#herbicideDaysLeft", field.herbicideDaysLeft or 0)
            setXMLFloat(xmlFile, fieldKey .. "#pestPressure", field.pestPressure or 0)
            setXMLInt(xmlFile, fieldKey .. "#insecticideDaysLeft", field.insecticideDaysLeft or 0)
            setXMLFloat(xmlFile, fieldKey .. "#diseasePressure", field.diseasePressure or 0)
            setXMLInt(xmlFile, fieldKey .. "#fungicideDaysLeft", field.fungicideDaysLeft or 0)
            setXMLInt(xmlFile, fieldKey .. "#dryDayCount", field.dryDayCount or 0)
            setXMLInt(xmlFile, fieldKey .. "#burnDaysLeft", field.burnDaysLeft or 0)

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
            fieldArea = getXMLFloat(xmlFile, fieldKey .. "#fieldArea") or 1.0,
            nitrogen = getXMLFloat(xmlFile, fieldKey .. "#nitrogen") or defaults.nitrogen,
            phosphorus = getXMLFloat(xmlFile, fieldKey .. "#phosphorus") or defaults.phosphorus,
            potassium = getXMLFloat(xmlFile, fieldKey .. "#potassium") or defaults.potassium,
            organicMatter = getXMLFloat(xmlFile, fieldKey .. "#organicMatter") or defaults.organicMatter,
            pH = getXMLFloat(xmlFile, fieldKey .. "#pH") or defaults.pH,
            lastCrop = getXMLString(xmlFile, fieldKey .. "#lastCrop"),
            lastCrop2 = getXMLString(xmlFile, fieldKey .. "#lastCrop2"),
            lastCrop3 = getXMLString(xmlFile, fieldKey .. "#lastCrop3"),
            rotationBonusDaysLeft = getXMLInt(xmlFile, fieldKey .. "#rotationBonusDaysLeft") or 0,
            lastHarvest = getXMLInt(xmlFile, fieldKey .. "#lastHarvest") or 0,
            fertilizerApplied = getXMLFloat(xmlFile, fieldKey .. "#fertilizerApplied") or 0,
            weedPressure = getXMLFloat(xmlFile, fieldKey .. "#weedPressure") or 0,
            herbicideDaysLeft = getXMLInt(xmlFile, fieldKey .. "#herbicideDaysLeft") or 0,
            pestPressure = getXMLFloat(xmlFile, fieldKey .. "#pestPressure") or 0,
            insecticideDaysLeft = getXMLInt(xmlFile, fieldKey .. "#insecticideDaysLeft") or 0,
            diseasePressure = getXMLFloat(xmlFile, fieldKey .. "#diseasePressure") or 0,
            fungicideDaysLeft = getXMLInt(xmlFile, fieldKey .. "#fungicideDaysLeft") or 0,
            dryDayCount = getXMLInt(xmlFile, fieldKey .. "#dryDayCount") or 0,
            burnDaysLeft = getXMLInt(xmlFile, fieldKey .. "#burnDaysLeft") or 0,
            initialized = true
        }

        -- Clear empty strings
        if self.fieldData[fieldId].lastCrop == "" then
            self.fieldData[fieldId].lastCrop = nil
        end
        if self.fieldData[fieldId].lastCrop2 == "" then
            self.fieldData[fieldId].lastCrop2 = nil
        end
        if self.fieldData[fieldId].lastCrop3 == "" then
            self.fieldData[fieldId].lastCrop3 = nil
        end

        index = index + 1
    end

    self:info("Loaded data for %d fields", index)

    -- Re-broadcast after load so clients that were connected during a
    -- save/load cycle get up-to-date values immediately.
    self:broadcastAllFieldData()
end

-- Debug: List all fields
function SoilFertilitySystem:listAllFields()
    SoilLogger.info("=== Listing all fields ===")

    SoilLogger.info("Our tracked fields:")
    for fieldId, field in pairs(self.fieldData) do
        SoilLogger.info("  Field %d: N=%.1f, P=%.1f, K=%.1f, pH=%.1f, OM=%.2f%%",
            fieldId, field.nitrogen, field.phosphorus, field.potassium, field.pH, field.organicMatter)
    end

    if g_fieldManager and g_fieldManager.fields then
        SoilLogger.info("Fields in FieldManager:")
        for _, field in ipairs(g_fieldManager.fields) do
            -- NOTE: field.fieldId / field.id / field.index are all nil in FS25.
            -- The correct identifier is field.farmland.id (farmland-based ID system).
            local fieldIdStr = tostring(field.farmland and field.farmland.id or "?")
            local nameStr    = tostring(field.name or "Unknown")
            SoilLogger.info("  Field %s: Name=%s", fieldIdStr, nameStr)
        end
    end

    SoilLogger.info("=== End field list ===")
end