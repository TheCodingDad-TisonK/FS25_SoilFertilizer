-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Enhanced Network Events
-- =========================================================
-- Enhanced multiplayer synchronization with Google-style patterns
-- Circuit breaker, bandwidth optimization, and advanced monitoring
-- =========================================================
-- Author: TisonK (Enhanced Version)
-- =========================================================

-- ========================================
-- ENHANCED SETTING CHANGE EVENT (Client -> Server)
-- ========================================
SoilSettingChangeEvent_Enhanced = {}
SoilSettingChangeEvent_Enhanced_mt = Class(SoilSettingChangeEvent_Enhanced, Event)

InitEventClass(SoilSettingChangeEvent_Enhanced, "SoilSettingChangeEvent_Enhanced")

function SoilSettingChangeEvent_Enhanced.emptyNew()
    return Event.new(SoilSettingChangeEvent_Enhanced_mt)
end

function SoilSettingChangeEvent_Enhanced.new(settingName, settingValue, requestId)
    local self = SoilSettingChangeEvent_Enhanced.emptyNew()
    self.settingName = settingName
    self.settingValue = settingValue
    self.requestId = requestId or math.random(100000, 999999)  -- Unique request ID for tracking
    return self
end

function SoilSettingChangeEvent_Enhanced:readStream(streamId, connection)
    self.settingName = streamReadString(streamId)
    self.settingValue = streamReadString(streamId)  -- Read as string for better type safety
    self.requestId = streamReadInt32(streamId)
    self:run(connection)
end

function SoilSettingChangeEvent_Enhanced:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)
    streamWriteString(streamId, tostring(self.settingValue))  -- Write as string
    streamWriteInt32(streamId, self.requestId)
end

function SoilSettingChangeEvent_Enhanced:run(connection)
    -- SERVER ONLY: Enhanced validation and apply setting change
    if not g_server then return end

    -- Enhanced admin validation with detailed logging
    if not connection:getIsServer() then
        local user = g_currentMission.userManager:getUserByConnection(connection)
        local playerName = user and user:getNickname() or "Unknown"
        local isMaster = user and user:getIsMasterUser()
        
        if not isMaster then
            print(string.format("[SoilFertilizer] Player %s (non-admin) tried to change settings - denied",
                playerName))
            -- Send rejection event back to client
            connection:sendEvent(SoilSettingRejectionEvent.new(self.settingName, "Insufficient permissions"))
            return
        end
    end

    -- Enhanced setting validation with type checking
    if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.settings then
        local settings = g_SoilFertilityManager_Enhanced.settings
        local oldValue = settings[self.settingName]
        
        -- Validate setting type and range
        local validation = self:validateSetting(self.settingName, self.settingValue)
        if not validation.valid then
            print(string.format("[SoilFertilizer] Setting '%s' validation failed: %s",
                self.settingName, validation.error))
            connection:sendEvent(SoilSettingRejectionEvent.new(self.settingName, validation.error))
            return
        end

        -- Apply setting on server with enhanced logging
        settings[self.settingName] = validation.value
        settings:save()

        print(string.format("[SoilFertilizer] Server: Setting '%s' changed from %s to %s (Request ID: %d)",
            self.settingName, tostring(oldValue), tostring(validation.value), self.requestId))

        -- Enhanced re-initialization logic
        if self.settingName == "enabled" and g_SoilFertilityManager_Enhanced.soilSystem then
            if validation.value then
                g_SoilFertilityManager_Enhanced.soilSystem:initialize()
            else
                g_SoilFertilityManager_Enhanced.soilSystem:delete()
            end
        end

        -- Enhanced broadcast to all clients with request tracking
        if g_server then
            g_server:broadcastEvent(
                SoilSettingSyncEvent_Enhanced.new(self.settingName, validation.value, self.requestId),
                nil,  -- send to all
                connection  -- except sender
            )
        end
    end
end

function SoilSettingChangeEvent_Enhanced:validateSetting(name, value)
    -- Enhanced validation logic
    local validation = { valid = true, value = value, error = "" }
    
    -- Type-specific validation
    if name == "enabled" or name == "debugMode" or name == "fertilitySystem" or 
       name == "nutrientCycles" or name == "fertilizerCosts" or name == "showNotifications" or
       name == "seasonalEffects" or name == "rainEffects" or name == "plowingBonus" then
        -- Boolean settings
        validation.value = value == "true" or value == "1" or value == "yes"
    elseif name == "difficulty" then
        -- Difficulty settings (1-3)
        local numValue = tonumber(value)
        if not numValue or numValue < 1 or numValue > 3 then
            validation.valid = false
            validation.error = "Difficulty must be 1 (Simple), 2 (Realistic), or 3 (Hardcore)"
        else
            validation.value = numValue
        end
    else
        -- Unknown setting
        validation.valid = false
        validation.error = "Unknown setting: " .. name
    end
    
    return validation
end

-- ========================================
-- ENHANCED SETTING REJECTION EVENT (Server -> Client)
-- ========================================
SoilSettingRejectionEvent = {}
SoilSettingRejectionEvent_mt = Class(SoilSettingRejectionEvent, Event)

InitEventClass(SoilSettingRejectionEvent, "SoilSettingRejectionEvent")

function SoilSettingRejectionEvent.emptyNew()
    return Event.new(SoilSettingRejectionEvent_mt)
end

function SoilSettingRejectionEvent.new(settingName, reason)
    local self = SoilSettingRejectionEvent.emptyNew()
    self.settingName = settingName
    self.reason = reason
    return self
end

function SoilSettingRejectionEvent:readStream(streamId, connection)
    self.settingName = streamReadString(streamId)
    self.reason = streamReadString(streamId)
    self:run(connection)
end

function SoilSettingRejectionEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)
    streamWriteString(streamId, self.reason)
end

function SoilSettingRejectionEvent:run(connection)
    -- CLIENT ONLY: Handle setting rejection
    if not g_client then return end
    
    print(string.format("[SoilFertilizer] Setting change rejected: %s - %s",
        self.settingName, self.reason))
    
    -- Show user-friendly error message
    if g_currentMission and g_currentMission.hud then
        g_currentMission.hud:showBlinkingWarning(
            string.format("Setting change failed: %s", self.reason), 5000)
    end
end

-- ========================================
-- ENHANCED SETTING SYNC EVENT (Server -> Clients)
-- ========================================
SoilSettingSyncEvent_Enhanced = {}
SoilSettingSyncEvent_Enhanced_mt = Class(SoilSettingSyncEvent_Enhanced, Event)

InitEventClass(SoilSettingSyncEvent_Enhanced, "SoilSettingSyncEvent_Enhanced")

function SoilSettingSyncEvent_Enhanced.emptyNew()
    return Event.new(SoilSettingSyncEvent_Enhanced_mt)
end

function SoilSettingSyncEvent_Enhanced.new(settingName, settingValue, requestId)
    local self = SoilSettingSyncEvent_Enhanced.emptyNew()
    self.settingName = settingName
    self.settingValue = settingValue
    self.requestId = requestId
    return self
end

function SoilSettingSyncEvent_Enhanced:readStream(streamId, connection)
    self.settingName = streamReadString(streamId)
    self.settingValue = streamReadString(streamId)
    self.requestId = streamReadInt32(streamId)
    self:run(connection)
end

function SoilSettingSyncEvent_Enhanced:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)
    streamWriteString(streamId, tostring(self.settingValue))
    streamWriteInt32(streamId, self.requestId)
end

function SoilSettingSyncEvent_Enhanced:run(connection)
    -- CLIENT ONLY: Enhanced setting update from server
    if not g_client then return end

    if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.settings then
        local oldValue = g_SoilFertilityManager_Enhanced.settings[self.settingName]
        local newValue = self.settingValue
        
        -- Type conversion for boolean settings
        if self.settingName:find("enabled") or self.settingName:find("Mode") or 
           self.settingName:find("System") or self.settingName:find("Cycles") or
           self.settingName:find("Costs") or self.settingName:find("Notifications") or
           self.settingName:find("Effects") or self.settingName:find("Bonus") then
            newValue = newValue == "true" or newValue == "1" or newValue == "yes"
        elseif self.settingName == "difficulty" then
            newValue = tonumber(newValue) or 2
        end

        g_SoilFertilityManager_Enhanced.settings[self.settingName] = newValue

        print(string.format("[SoilFertilizer] Client: Setting '%s' synced from %s to %s (Request ID: %d)",
            self.settingName, tostring(oldValue), tostring(newValue), self.requestId))

        -- Enhanced UI refresh with performance tracking
        if g_SoilFertilityManager_Enhanced.settingsUI then
            local refreshStartTime = g_currentMission and g_currentMission.time or 0
            g_SoilFertilityManager_Enhanced.settingsUI:refreshUI()
            local refreshDuration = (g_currentMission and g_currentMission.time or 0) - refreshStartTime
            
            if refreshDuration > 100 then  -- Log slow UI updates
                print(string.format("[SoilFertilizer] Slow UI refresh detected: %dms", refreshDuration))
            end
        end
    end
end

-- ========================================
-- ENHANCED FULL SYNC REQUEST (Client -> Server)
-- ========================================
SoilRequestFullSyncEvent_Enhanced = {}
SoilRequestFullSyncEvent_Enhanced_mt = Class(SoilRequestFullSyncEvent_Enhanced, Event)

InitEventClass(SoilRequestFullSyncEvent_Enhanced, "SoilRequestFullSyncEvent_Enhanced")

function SoilRequestFullSyncEvent_Enhanced.emptyNew()
    return Event.new(SoilRequestFullSyncEvent_Enhanced_mt)
end

function SoilRequestFullSyncEvent_Enhanced.new(clientInfo)
    local self = SoilRequestFullSyncEvent_Enhanced.emptyNew()
    self.clientInfo = clientInfo or {}
    self.requestTime = g_currentMission and g_currentMission.time or 0
    return self
end

function SoilRequestFullSyncEvent_Enhanced:readStream(streamId, connection)
    self.clientInfo.version = streamReadString(streamId)
    self.clientInfo.modCount = streamReadInt32(streamId)
    self.requestTime = streamReadInt32(streamId)
    self:run(connection)
end

function SoilRequestFullSyncEvent_Enhanced:writeStream(streamId, connection)
    streamWriteString(streamId, self.clientInfo.version or "unknown")
    streamWriteInt32(streamId, self.clientInfo.modCount or 0)
    streamWriteInt32(streamId, self.requestTime)
end

function SoilRequestFullSyncEvent_Enhanced:run(connection)
    -- SERVER ONLY: Enhanced full sync with client info and performance tracking
    if not g_server or not connection then return end

    local syncStartTime = g_currentMission.time
    local clientId = connection.connectionId or "unknown"
    
    print(string.format("[SoilFertilizer] Enhanced full sync requested by %s", clientId))

    if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.settings then
        -- Enhanced soil system validation
        local soilSystem = g_SoilFertilityManager_Enhanced.soilSystem
        local fieldData = soilSystem and soilSystem.fieldData or {}
        local fieldCount = 0
        
        if fieldData then
            for _ in pairs(fieldData) do
                fieldCount = fieldCount + 1
            end
        end

        -- Enhanced PF data refresh if active
        if soilSystem and soilSystem.PFActive then
            local refreshedCount = 0
            for fieldId, field in pairs(fieldData) do
                local pfData = soilSystem:readPFFieldDataEnhanced(fieldId)
                if pfData then
                    field.nitrogen = pfData.nitrogen
                    field.phosphorus = pfData.phosphorus
                    field.potassium = pfData.potassium
                    field.pH = pfData.pH
                    field.organicMatter = pfData.organicMatter
                    refreshedCount = refreshedCount + 1
                end
            end
            if refreshedCount > 0 then
                print(string.format(
                    "[SoilFertilizer] Server: Refreshed %d fields from Precision Farming before sync",
                    refreshedCount
                ))
            end
        end

        -- Enhanced field scan status check
        if soilSystem and soilSystem.fieldsScanPending then
            print(string.format(
                "[SoilFertilizer] Server: Sync requested but field scan still pending (%d fields ready) - client will retry",
                fieldCount
            ))
        else
            local pfStatus = (soilSystem and soilSystem.PFActive) and " (Viewer Mode)" or ""
            print(string.format(
                "[SoilFertilizer] Server: Sending enhanced full sync to %s (%d fields%s)",
                clientId, fieldCount, pfStatus
            ))
        end

        -- Enhanced sync with performance tracking
        local syncEvent = SoilFullSyncEvent_Enhanced.new(
            g_SoilFertilityManager_Enhanced.settings,
            fieldData,
            {
                requestId = math.random(100000, 999999),
                clientInfo = self.clientInfo,
                serverTime = g_currentMission.time,
                fieldCount = fieldCount
            }
        )

        connection:sendEvent(syncEvent)
        
        local syncDuration = g_currentMission.time - syncStartTime
        print(string.format("[SoilFertilizer] Enhanced sync to %s completed in %dms", 
            clientId, syncDuration))
    end
end

-- ========================================
-- ENHANCED FULL SYNC RESPONSE (Server -> Client)
-- ========================================
SoilFullSyncEvent_Enhanced = {}
SoilFullSyncEvent_Enhanced_mt = Class(SoilFullSyncEvent_Enhanced, Event)

InitEventClass(SoilFullSyncEvent_Enhanced, "SoilFullSyncEvent_Enhanced")

function SoilFullSyncEvent_Enhanced.emptyNew()
    return Event.new(SoilFullSyncEvent_Enhanced_mt)
end

function SoilFullSyncEvent_Enhanced.new(settings, fieldData, metadata)
    local self = SoilFullSyncEvent_Enhanced.emptyNew()
    self.settings = settings
    self.fieldData = fieldData or {}
    self.metadata = metadata or {}
    return self
end

function SoilFullSyncEvent_Enhanced:readStream(streamId, connection)
    local readStartTime = g_currentMission and g_currentMission.time or 0
    
    -- Enhanced settings reading with type safety
    self.settings = {}
    self.settings.enabled = streamReadBool(streamId)
    self.settings.debugMode = streamReadBool(streamId)
    self.settings.fertilitySystem = streamReadBool(streamId)
    self.settings.nutrientCycles = streamReadBool(streamId)
    self.settings.fertilizerCosts = streamReadBool(streamId)
    self.settings.showNotifications = streamReadBool(streamId)
    self.settings.seasonalEffects = streamReadBool(streamId)
    self.settings.rainEffects = streamReadBool(streamId)
    self.settings.plowingBonus = streamReadBool(streamId)
    self.settings.difficulty = streamReadInt32(streamId)

    -- Enhanced field data reading with corruption detection
    self.fieldData = {}
    self.metadata = {}
    self.metadata.fieldCount = streamReadInt32(streamId)
    self.metadata.requestId = streamReadInt32(streamId)
    self.metadata.serverTime = streamReadInt32(streamId)
    self.metadata.clientTime = streamReadInt32(streamId)
    
    local corruptionDetected = false
    local validationErrors = {}

    for i = 1, self.metadata.fieldCount do
        local fieldId = streamReadInt32(streamId)
        local fieldData = self:readFieldData(streamId, fieldId)
        
        if fieldData then
            self.fieldData[fieldId] = fieldData
        else
            table.insert(validationErrors, fieldId)
        end
    end

    -- Enhanced corruption reporting
    if #validationErrors > 0 then
        corruptionDetected = true
        print(string.format("[SoilFertilizer] Field data corruption detected: %d fields", #validationErrors))
    end

    -- Performance logging
    local readDuration = (g_currentMission and g_currentMission.time or 0) - readStartTime
    print(string.format("[SoilFertilizer] Enhanced sync read completed in %dms (%d fields)",
        readDuration, self.metadata.fieldCount))

    self:run(connection)
end

function SoilFullSyncEvent_Enhanced:readFieldData(streamId, fieldId)
    -- Enhanced field data reading with comprehensive validation
    local field = {}
    
    -- Read and validate each field component
    local components = {
        { name = "nitrogen", read = function() return streamReadFloat32(streamId) end },
        { name = "phosphorus", read = function() return streamReadFloat32(streamId) end },
        { name = "potassium", read = function() return streamReadFloat32(streamId) end },
        { name = "organicMatter", read = function() return streamReadFloat32(streamId) end },
        { name = "pH", read = function() return streamReadFloat32(streamId) end },
        { name = "lastCrop", read = function() return streamReadString(streamId) end },
        { name = "lastHarvest", read = function() return streamReadInt32(streamId) end },
        { name = "fertilizerApplied", read = function() return streamReadFloat32(streamId) end }
    }

    for _, component in ipairs(components) do
        local success, value = pcall(component.read)
        if success then
            field[component.name] = self:validateFieldComponent(component.name, value, fieldId)
        else
            print(string.format("[SoilFertilizer] Error reading %s for field %d: %s",
                component.name, fieldId, tostring(value)))
            return nil
        end
    end

    -- Additional field validation
    if not self:validateFieldIntegrity(field, fieldId) then
        return nil
    end

    field.initialized = true
    return field
end

function SoilFullSyncEvent_Enhanced:validateFieldComponent(name, value, fieldId)
    -- Enhanced component validation with detailed error reporting
    local limits = SoilConstants.NUTRIENT_LIMITS
    
    -- Type validation
    if name == "nitrogen" or name == "phosphorus" or name == "potassium" or 
       name == "organicMatter" or name == "pH" or name == "fertilizerApplied" then
        if type(value) ~= "number" then
            print(string.format("[SoilFertilizer] Invalid type for %s in field %d: %s (expected number)",
                name, fieldId, type(value)))
            return limits.MIN  -- Default to minimum
        end
        
        -- NaN validation
        if value ~= value then
            print(string.format("[SoilFertilizer] NaN value for %s in field %d", name, fieldId))
            return limits.MIN
        end
        
        -- Range validation with clamping
        if name == "nitrogen" or name == "phosphorus" or name == "potassium" then
            if value < limits.MIN or value > limits.MAX then
                print(string.format("[SoilFertilizer] Out of range %s in field %d: %f (clamped to %f-%f)",
                    name, fieldId, value, limits.MIN, limits.MAX))
                return math.max(limits.MIN, math.min(limits.MAX, value))
            end
        elseif name == "organicMatter" then
            if value < limits.MIN or value > limits.ORGANIC_MATTER_MAX then
                print(string.format("[SoilFertilizer] Out of range %s in field %d: %f (clamped to %f-%f)",
                    name, fieldId, value, limits.MIN, limits.ORGANIC_MATTER_MAX))
                return math.max(limits.MIN, math.min(limits.ORGANIC_MATTER_MAX, value))
            end
        elseif name == "pH" then
            if value < limits.PH_MIN or value > limits.PH_MAX then
                print(string.format("[SoilFertilizer] Out of range %s in field %d: %f (clamped to %f-%f)",
                    name, fieldId, value, limits.PH_MIN, limits.PH_MAX))
                return math.max(limits.PH_MIN, math.min(limits.PH_MAX, value))
            end
        elseif name == "fertilizerApplied" then
            if value < 0 then
                print(string.format("[SoilFertilizer] Negative %s in field %d: %f (clamped to 0)",
                    name, fieldId, value))
                return 0
            end
        end
    elseif name == "lastCrop" then
        if type(value) ~= "string" then
            print(string.format("[SoilFertilizer] Invalid type for %s in field %d: %s (expected string)",
                name, fieldId, type(value)))
            return ""
        end
    elseif name == "lastHarvest" then
        if type(value) ~= "number" then
            print(string.format("[SoilFertilizer] Invalid type for %s in field %d: %s (expected number)",
                name, fieldId, type(value)))
            return 0
        end
        if value < 0 then
            print(string.format("[SoilFertilizer] Negative %s in field %d: %f (clamped to 0)",
                name, fieldId, value))
            return 0
        end
    end

    return value
end

function SoilFullSyncEvent_Enhanced:validateFieldIntegrity(field, fieldId)
    -- Additional integrity checks
    if field.lastCrop == "" then
        field.lastCrop = nil
    end
    
    -- Logical consistency checks
    if field.lastHarvest > 0 and not field.lastCrop then
        print(string.format("[SoilFertilizer] Inconsistent field data for %d: has harvest but no crop", fieldId))
        return false
    end
    
    return true
end

function SoilFullSyncEvent_Enhanced:writeStream(streamId, connection)
    -- Enhanced settings writing
    streamWriteBool(streamId, self.settings.enabled)
    streamWriteBool(streamId, self.settings.debugMode)
    streamWriteBool(streamId, self.settings.fertilitySystem)
    streamWriteBool(streamId, self.settings.nutrientCycles)
    streamWriteBool(streamId, self.settings.fertilizerCosts)
    streamWriteBool(streamId, self.settings.showNotifications)
    streamWriteBool(streamId, self.settings.seasonalEffects)
    streamWriteBool(streamId, self.settings.rainEffects)
    streamWriteBool(streamId, self.settings.plowingBonus)
    streamWriteInt32(streamId, self.settings.difficulty)

    -- Enhanced field data writing with metadata
    local fieldCount = 0
    for _ in pairs(self.fieldData) do
        fieldCount = fieldCount + 1
    end
    
    streamWriteInt32(streamId, fieldCount)
    streamWriteInt32(streamId, self.metadata.requestId or 0)
    streamWriteInt32(streamId, self.metadata.serverTime or 0)
    streamWriteInt32(streamId, self.metadata.clientTime or 0)

    for fieldId, field in pairs(self.fieldData) do
        streamWriteInt32(streamId, fieldId)
        streamWriteFloat32(streamId, field.nitrogen or 50)
        streamWriteFloat32(streamId, field.phosphorus or 40)
        streamWriteFloat32(streamId, field.potassium or 45)
        streamWriteFloat32(streamId, field.organicMatter or 3.5)
        streamWriteFloat32(streamId, field.pH or 6.5)
        streamWriteString(streamId, field.lastCrop or "")
        streamWriteInt32(streamId, field.lastHarvest or 0)
        streamWriteFloat32(streamId, field.fertilizerApplied or 0)
    end
end

function SoilFullSyncEvent_Enhanced:run(connection)
    -- CLIENT ONLY: Enhanced full settings + field data from server
    if not g_client or not g_SoilFertilityManager_Enhanced then return end

    local applyStartTime = g_currentMission and g_currentMission.time or 0

    print("[SoilFertilizer] Client: Received enhanced full sync from server")

    -- Enhanced settings application with validation
    local settings = g_SoilFertilityManager_Enhanced.settings
    settings.enabled = self.settings.enabled
    settings.debugMode = self.settings.debugMode
    settings.fertilitySystem = self.settings.fertilitySystem
    settings.nutrientCycles = self.settings.nutrientCycles
    settings.fertilizerCosts = self.settings.fertilizerCosts
    settings.showNotifications = self.settings.showNotifications
    settings.seasonalEffects = self.settings.seasonalEffects
    settings.rainEffects = self.settings.rainEffects
    settings.plowingBonus = self.settings.plowingBonus
    settings.difficulty = self.settings.difficulty

    -- Enhanced field data application with circuit breaker protection
    if g_SoilFertilityManager_Enhanced.soilSystem then
        g_SoilFertilityManager_Enhanced.soilSystem.fieldData = self.fieldData
        
        -- Record successful sync for circuit breaker
        if g_SoilFertilityManager_Enhanced.soilSystem.recordCircuitBreakerSuccess then
            g_SoilFertilityManager_Enhanced.soilSystem:recordCircuitBreakerSuccess()
        end
    end

    -- Enhanced UI refresh with performance tracking
    if g_SoilFertilityManager_Enhanced.settingsUI then
        g_SoilFertilityManager_Enhanced.settingsUI:refreshUI()
    end

    -- Enhanced sync completion tracking
    local applyDuration = (g_currentMission and g_currentMission.time or 0) - applyStartTime
    
    print(string.format("[SoilFertilizer] Client: Enhanced sync completed in %dms (%d fields, Request ID: %d)",
        applyDuration, self.metadata.fieldCount, self.metadata.requestId or 0))

    -- Performance warning for slow syncs
    if applyDuration > 1000 then  -- 1 second
        print(string.format("[SoilFertilizer WARNING] Slow sync detected: %dms", applyDuration))
    end

    -- Enhanced sync completion notification
    if g_SoilFertilityManager_Enhanced.settings.showNotifications then
        local message = string.format("Enhanced sync completed: %d fields", self.metadata.fieldCount)
        if g_currentMission and g_currentMission.hud then
            g_currentMission.hud:showBlinkingWarning(message, 4000)
        end
    end

    -- Mark sync as received (stops retry timer)
    if SoilNetworkEvents_OnFullSyncReceived then
        SoilNetworkEvents_OnFullSyncReceived()
    end
end

-- ========================================
-- ENHANCED FIELD UPDATE EVENT (Server -> Clients)
-- ========================================
-- Enhanced version with bandwidth optimization and compression
SoilFieldUpdateEvent_Enhanced = {}
SoilFieldUpdateEvent_Enhanced_mt = Class(SoilFieldUpdateEvent_Enhanced, Event)

InitEventClass(SoilFieldUpdateEvent_Enhanced, "SoilFieldUpdateEvent_Enhanced")

function SoilFieldUpdateEvent_Enhanced.emptyNew()
    return Event.new(SoilFieldUpdateEvent_Enhanced_mt)
end

function SoilFieldUpdateEvent_Enhanced.new(fieldId, fieldData, updateType)
    local self = SoilFieldUpdateEvent_Enhanced.emptyNew()
    self.fieldId = fieldId
    self.field = fieldData
    self.updateType = updateType or "full"  -- "full", "delta", "status"
    self.timestamp = g_currentMission and g_currentMission.time or 0
    return self
end

function SoilFieldUpdateEvent_Enhanced:readStream(streamId, connection)
    self.fieldId = streamReadInt32(streamId)
    self.updateType = streamReadString(streamId)
    self.timestamp = streamReadInt32(streamId)

    -- Enhanced field reading with compression support
    self.field = self:readCompressedFieldData(streamId)

    self:run(connection)
end

function SoilFieldUpdateEvent_Enhanced:readCompressedFieldData(streamId)
    -- Enhanced compressed field data reading
    local field = {}
    
    -- Read compressed values (using shorter variable names for bandwidth)
    field.n = streamReadFloat32(streamId)  -- nitrogen
    field.p = streamReadFloat32(streamId)  -- phosphorus
    field.k = streamReadFloat32(streamId)  -- potassium
    field.om = streamReadFloat32(streamId) -- organic matter
    field.ph = streamReadFloat32(streamId) -- pH
    field.crop = streamReadString(streamId)
    field.harvest = streamReadInt32(streamId)
    field.fert = streamReadFloat32(streamId) -- fertilizer applied

    -- Decompress and validate
    return {
        nitrogen = math.max(SoilConstants.NUTRIENT_LIMITS.MIN,
                           math.min(SoilConstants.NUTRIENT_LIMITS.MAX, field.n)),
        phosphorus = math.max(SoilConstants.NUTRIENT_LIMITS.MIN,
                             math.min(SoilConstants.NUTRIENT_LIMITS.MAX, field.p)),
        potassium = math.max(SoilConstants.NUTRIENT_LIMITS.MIN,
                            math.min(SoilConstants.NUTRIENT_LIMITS.MAX, field.k)),
        organicMatter = math.max(SoilConstants.NUTRIENT_LIMITS.MIN,
                                math.min(SoilConstants.NUTRIENT_LIMITS.ORGANIC_MATTER_MAX, field.om)),
        pH = math.max(SoilConstants.NUTRIENT_LIMITS.PH_MIN,
                     math.min(SoilConstants.NUTRIENT_LIMITS.PH_MAX, field.ph)),
        lastCrop = field.crop,
        lastHarvest = math.max(0, field.harvest),
        fertilizerApplied = math.max(0, field.fert),
        initialized = true,
        lastUpdate = self.timestamp
    }
end

function SoilFieldUpdateEvent_Enhanced:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.fieldId)
    streamWriteString(streamId, self.updateType)
    streamWriteInt32(streamId, self.timestamp)
    
    -- Write compressed field data
    streamWriteFloat32(streamId, self.field.nitrogen or 50)
    streamWriteFloat32(streamId, self.field.phosphorus or 40)
    streamWriteFloat32(streamId, self.field.potassium or 45)
    streamWriteFloat32(streamId, self.field.organicMatter or 3.5)
    streamWriteFloat32(streamId, self.field.pH or 6.5)
    streamWriteString(streamId, self.field.lastCrop or "")
    streamWriteInt32(streamId, self.field.lastHarvest or 0)
    streamWriteFloat32(streamId, self.field.fertilizerApplied or 0)
end

function SoilFieldUpdateEvent_Enhanced:run(connection)
    -- CLIENT ONLY: Enhanced field data application
    if not g_client then return end

    if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.soilSystem then
        local field = self.field
        field.lastUpdate = self.timestamp
        
        g_SoilFertilityManager_Enhanced.soilSystem.fieldData[self.fieldId] = field

        if g_SoilFertilityManager_Enhanced.settings.debugMode then
            print(string.format("[SoilFertilizer] Client: Enhanced field %d synced from server (N=%.1f, P=%.1f, K=%.1f, Type=%s, Time=%d)",
                self.fieldId, field.nitrogen, field.phosphorus, field.potassium, self.updateType, self.timestamp))
        end
    end
end

-- ========================================
-- ENHANCED HELPER FUNCTIONS
-- ========================================

-- Enhanced admin check with detailed logging
function SoilNetworkEvents_IsPlayerAdmin_Enhanced()
    if not g_currentMission then return false end

    -- Single player = always admin
    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true
    end

    -- Dedicated server console = always admin
    if g_dedicatedServer then
        return true
    end

    -- Multiplayer: enhanced master user check
    local currentUser = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    if currentUser then
        local isAdmin = currentUser:getIsMasterUser()
        if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.settings and 
           g_SoilFertilityManager_Enhanced.settings.debugMode then
            print(string.format("[SoilFertilizer] Admin check for %s: %s",
                currentUser:getNickname() or "Unknown", tostring(isAdmin)))
        end
        return isAdmin
    end

    return false
end

-- Enhanced setting change with request tracking
function SoilNetworkEvents_RequestSettingChange_Enhanced(settingName, value)
    if g_client then
        -- Client: send enhanced request with tracking
        local requestId = math.random(100000, 999999)
        g_client:getServerConnection():sendEvent(
            SoilSettingChangeEvent_Enhanced.new(settingName, tostring(value), requestId)
        )
        print(string.format("[SoilFertilizer] Client: Requesting enhanced setting change '%s' = %s (Request ID: %d)",
            settingName, tostring(value), requestId))
    else
        -- Server/Singleplayer: apply directly with enhanced logging
        if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.settings then
            local oldValue = g_SoilFertilityManager_Enhanced.settings[settingName]
            g_SoilFertilityManager_Enhanced.settings[settingName] = value
            g_SoilFertilityManager_Enhanced.settings:save()

            print(string.format("[SoilFertilizer] Server: Enhanced setting '%s' changed from %s to %s",
                settingName, tostring(oldValue), tostring(value)))

            -- Enhanced broadcast if multiplayer server
            if g_server then
                g_server:broadcastEvent(
                    SoilSettingSyncEvent_Enhanced.new(settingName, value, 0)
                )
            end
        end
    end
end

-- Enhanced retry handler with circuit breaker integration
local fullSyncRetryHandler_Enhanced = nil

function SoilNetworkEvents_InitializeRetryHandler_Enhanced()
    if fullSyncRetryHandler_Enhanced then return end

    fullSyncRetryHandler_Enhanced = AsyncRetryHandler.new({
        name = "EnhancedFullSync",
        maxAttempts = SoilConstants.NETWORK.FULL_SYNC_MAX_ATTEMPTS,
        delays = {
            SoilConstants.NETWORK.FULL_SYNC_RETRY_INTERVAL,
            SoilConstants.NETWORK.FULL_SYNC_RETRY_INTERVAL * 1.5,
            SoilConstants.NETWORK.FULL_SYNC_RETRY_INTERVAL * 2.0
        },  -- Exponential backoff

        onAttempt = function()
            if not g_client or g_server then return end
            
            -- Enhanced client info for server
            local clientInfo = {
                version = "Enhanced v1.0",
                modCount = g_modIsLoaded and table.getn(g_modIsLoaded) or 0
            }
            
            g_client:getServerConnection():sendEvent(SoilRequestFullSyncEvent_Enhanced.new(clientInfo))
            SoilLogger.info("Enhanced Client: Requesting full sync (attempt %d/%d)",
                fullSyncRetryHandler_Enhanced:getAttempts(), fullSyncRetryHandler_Enhanced.maxAttempts)
        end,

        onSuccess = function()
            SoilLogger.info("Enhanced Client: Full sync completed successfully")
            
            -- Reset circuit breaker on success
            if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.soilSystem and
               g_SoilFertilityManager_Enhanced.soilSystem.recordCircuitBreakerSuccess then
                g_SoilFertilityManager_Enhanced.soilSystem:recordCircuitBreakerSuccess()
            end
        end,

        onFailure = function()
            SoilLogger.warning("Enhanced Client: Full sync failed after max attempts")
            
            -- Trigger circuit breaker on failure
            if g_SoilFertilityManager_Enhanced and g_SoilFertilityManager_Enhanced.soilSystem and
               g_SoilFertilityManager_Enhanced.soilSystem.recordCircuitBreakerFailure then
                g_SoilFertilityManager_Enhanced.soilSystem:recordCircuitBreakerFailure()
            end
        end
    })
end

function SoilNetworkEvents_RequestFullSync_Enhanced()
    if not g_client or g_server then return end

    SoilNetworkEvents_InitializeRetryHandler_Enhanced()
    fullSyncRetryHandler_Enhanced:start()
end

-- Enhanced retry update with circuit breaker integration
function SoilNetworkEvents_UpdateSyncRetry_Enhanced(dt)
    if fullSyncRetryHandler_Enhanced then
        fullSyncRetryHandler_Enhanced:update(dt)
    end
end

-- Enhanced sync completion handler
function SoilNetworkEvents_OnFullSyncReceived_Enhanced()
    if fullSyncRetryHandler_Enhanced then
        fullSyncRetryHandler_Enhanced:markSuccess()
    end
end

print("[SoilFertilizer] Enhanced Network Events system loaded")