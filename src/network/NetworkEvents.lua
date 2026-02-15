-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Network Events
-- =========================================================
-- Handles multiplayer synchronization of settings and state
-- =========================================================
-- Author: TisonK
-- =========================================================

-- ========================================
-- SETTING CHANGE EVENT (Client -> Server)
-- ========================================
SoilSettingChangeEvent = {}
SoilSettingChangeEvent_mt = Class(SoilSettingChangeEvent, Event)

InitEventClass(SoilSettingChangeEvent, "SoilSettingChangeEvent")

function SoilSettingChangeEvent.emptyNew()
    return Event.new(SoilSettingChangeEvent_mt)
end

function SoilSettingChangeEvent.new(settingName, settingValue)
    local self = SoilSettingChangeEvent.emptyNew()
    self.settingName = settingName
    self.settingValue = settingValue
    return self
end

function SoilSettingChangeEvent:readStream(streamId, connection)
    self.settingName = streamReadString(streamId)
    local valueType = streamReadUInt8(streamId)

    if valueType == SoilConstants.NETWORK.VALUE_TYPE.BOOLEAN then
        self.settingValue = streamReadBool(streamId)
    elseif valueType == SoilConstants.NETWORK.VALUE_TYPE.NUMBER then
        self.settingValue = streamReadInt32(streamId)
    elseif valueType == SoilConstants.NETWORK.VALUE_TYPE.STRING then
        self.settingValue = streamReadString(streamId)
    end

    self:run(connection)
end

function SoilSettingChangeEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)

    if type(self.settingValue) == "boolean" then
        streamWriteUInt8(streamId, SoilConstants.NETWORK.VALUE_TYPE.BOOLEAN)
        streamWriteBool(streamId, self.settingValue)
    elseif type(self.settingValue) == "number" then
        streamWriteUInt8(streamId, SoilConstants.NETWORK.VALUE_TYPE.NUMBER)
        streamWriteInt32(streamId, self.settingValue)
    else
        streamWriteUInt8(streamId, SoilConstants.NETWORK.VALUE_TYPE.STRING)
        streamWriteString(streamId, tostring(self.settingValue))
    end
end

function SoilSettingChangeEvent:run(connection)
    -- SERVER ONLY: Validate and apply setting change
    if not g_server then return end

    -- Validate player is admin (master user)
    if not connection:getIsServer() then
        local user = g_currentMission.userManager:getUserByConnection(connection)
        if not user or not user:getIsMasterUser() then
            print(string.format("[SoilFertilizer] Player %s (non-admin) tried to change settings - denied",
                user and user:getNickname() or "Unknown"))
            return
        end
    end

    -- Apply setting on server
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local settings = g_SoilFertilityManager.settings
        local oldValue = settings[self.settingName]

        -- Update the setting
        settings[self.settingName] = self.settingValue
        settings:save()

        print(string.format("[SoilFertilizer] Server: Setting '%s' changed from %s to %s",
            self.settingName, tostring(oldValue), tostring(self.settingValue)))

        -- Re-initialize system if enabled state changed
        if self.settingName == "enabled" and g_SoilFertilityManager.soilSystem then
            if self.settingValue then
                g_SoilFertilityManager.soilSystem:initialize()
            end
        end

        -- Broadcast to all clients
        if g_server then
            g_server:broadcastEvent(
                SoilSettingSyncEvent.new(self.settingName, self.settingValue),
                nil,  -- send to all
                connection  -- except sender
            )
        end
    end
end

-- ========================================
-- SETTING SYNC EVENT (Server -> Clients)
-- ========================================
SoilSettingSyncEvent = {}
SoilSettingSyncEvent_mt = Class(SoilSettingSyncEvent, Event)

InitEventClass(SoilSettingSyncEvent, "SoilSettingSyncEvent")

function SoilSettingSyncEvent.emptyNew()
    return Event.new(SoilSettingSyncEvent_mt)
end

function SoilSettingSyncEvent.new(settingName, settingValue)
    local self = SoilSettingSyncEvent.emptyNew()
    self.settingName = settingName
    self.settingValue = settingValue
    return self
end

function SoilSettingSyncEvent:readStream(streamId, connection)
    self.settingName = streamReadString(streamId)
    local valueType = streamReadUInt8(streamId)

    if valueType == SoilConstants.NETWORK.VALUE_TYPE.BOOLEAN then
        self.settingValue = streamReadBool(streamId)
    elseif valueType == SoilConstants.NETWORK.VALUE_TYPE.NUMBER then
        self.settingValue = streamReadInt32(streamId)
    else
        self.settingValue = streamReadString(streamId)
    end

    self:run(connection)
end

function SoilSettingSyncEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)

    if type(self.settingValue) == "boolean" then
        streamWriteUInt8(streamId, SoilConstants.NETWORK.VALUE_TYPE.BOOLEAN)
        streamWriteBool(streamId, self.settingValue)
    elseif type(self.settingValue) == "number" then
        streamWriteUInt8(streamId, SoilConstants.NETWORK.VALUE_TYPE.NUMBER)
        streamWriteInt32(streamId, self.settingValue)
    else
        streamWriteUInt8(streamId, SoilConstants.NETWORK.VALUE_TYPE.STRING)
        streamWriteString(streamId, tostring(self.settingValue))
    end
end

function SoilSettingSyncEvent:run(connection)
    -- CLIENT ONLY: Receive setting update from server
    if not g_client then return end

    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local oldValue = g_SoilFertilityManager.settings[self.settingName]
        g_SoilFertilityManager.settings[self.settingName] = self.settingValue

        print(string.format("[SoilFertilizer] Client: Setting '%s' synced from %s to %s",
            self.settingName, tostring(oldValue), tostring(self.settingValue)))

        -- Refresh UI if open
        if g_SoilFertilityManager.settingsUI then
            g_SoilFertilityManager.settingsUI:refreshUI()
        end
    end
end

-- ========================================
-- FULL SYNC REQUEST (Client -> Server)
-- ========================================
SoilRequestFullSyncEvent = {}
SoilRequestFullSyncEvent_mt = Class(SoilRequestFullSyncEvent, Event)

InitEventClass(SoilRequestFullSyncEvent, "SoilRequestFullSyncEvent")

function SoilRequestFullSyncEvent.emptyNew()
    return Event.new(SoilRequestFullSyncEvent_mt)
end

function SoilRequestFullSyncEvent.new()
    return SoilRequestFullSyncEvent.emptyNew()
end

function SoilRequestFullSyncEvent:readStream(streamId, connection)
    self:run(connection)
end

function SoilRequestFullSyncEvent:writeStream(streamId, connection)
    -- No data needed
end

function SoilRequestFullSyncEvent:run(connection)
    -- SERVER ONLY: Send full settings + field data to requesting client
    if not g_server or not connection then return end

    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        -- Validate that soil system has initialized field data
        local soilSystem = g_SoilFertilityManager.soilSystem
        local fieldData = soilSystem and soilSystem.fieldData or {}

        -- Count actual fields (not just empty table)
        local fieldCount = 0
        if fieldData then
            for _ in pairs(fieldData) do
                fieldCount = fieldCount + 1
            end
        end

        -- If soil system is still initializing (no fields yet), log warning
        -- Client will retry automatically via retry handler
        if soilSystem and soilSystem.fieldsScanPending then
            print(string.format(
                "[SoilFertilizer] Server: Sync requested but field scan still pending (%d fields ready) - client will retry",
                fieldCount
            ))
        else
            print(string.format(
                "[SoilFertilizer] Server: Sending full sync to client (%d fields)",
                fieldCount
            ))
        end

        -- Send sync event (even if empty - client needs settings)
        -- Empty field data is valid for new saves or dedicated servers
        connection:sendEvent(SoilFullSyncEvent.new(
            g_SoilFertilityManager.settings,
            fieldData
        ))
    end
end

-- ========================================
-- FULL SYNC RESPONSE (Server -> Client)
-- ========================================
SoilFullSyncEvent = {}
SoilFullSyncEvent_mt = Class(SoilFullSyncEvent, Event)

InitEventClass(SoilFullSyncEvent, "SoilFullSyncEvent")

function SoilFullSyncEvent.emptyNew()
    return Event.new(SoilFullSyncEvent_mt)
end

function SoilFullSyncEvent.new(settings, fieldData)
    local self = SoilFullSyncEvent.emptyNew()
    self.settings = settings
    self.fieldData = fieldData or {}
    return self
end

function SoilFullSyncEvent:readStream(streamId, connection)
    self.settings = {}

    -- Read all settings
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

    -- Read field data
    self.fieldData = {}
    local fieldCount = streamReadInt32(streamId)
    for i = 1, fieldCount do
        local fieldId = streamReadInt32(streamId)
        self.fieldData[fieldId] = {
            nitrogen = streamReadFloat32(streamId),
            phosphorus = streamReadFloat32(streamId),
            potassium = streamReadFloat32(streamId),
            organicMatter = streamReadFloat32(streamId),
            pH = streamReadFloat32(streamId),
            lastCrop = streamReadString(streamId),
            lastHarvest = streamReadInt32(streamId),
            fertilizerApplied = streamReadFloat32(streamId),
            initialized = true
        }
        -- Clear empty strings
        if self.fieldData[fieldId].lastCrop == "" then
            self.fieldData[fieldId].lastCrop = nil
        end
    end

    self:run(connection)
end

function SoilFullSyncEvent:writeStream(streamId, connection)
    -- Write all settings
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

    -- Write field data
    local fieldCount = 0
    for _ in pairs(self.fieldData) do
        fieldCount = fieldCount + 1
    end
    streamWriteInt32(streamId, fieldCount)

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

function SoilFullSyncEvent:run(connection)
    -- CLIENT ONLY: Receive full settings + field data from server
    if not g_client or not g_SoilFertilityManager then return end

    print("[SoilFertilizer] Client: Received full sync from server")

    -- Apply all settings
    local settings = g_SoilFertilityManager.settings
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

    -- Apply field data (server-authoritative)
    if g_SoilFertilityManager.soilSystem then
        g_SoilFertilityManager.soilSystem.fieldData = self.fieldData
        print(string.format("[SoilFertilizer] Client: Synced %d fields from server", self:getFieldCount()))
    end

    -- Refresh UI if open
    if g_SoilFertilityManager.settingsUI then
        g_SoilFertilityManager.settingsUI:refreshUI()
    end

    -- Mark sync as received (stops retry timer)
    SoilNetworkEvents_OnFullSyncReceived()

    print(string.format("[SoilFertilizer] Client: Settings synced - Enabled: %s, Difficulty: %s",
        tostring(settings.enabled), settings:getDifficultyName()))
end

function SoilFullSyncEvent:getFieldCount()
    local count = 0
    for _ in pairs(self.fieldData) do
        count = count + 1
    end
    return count
end

-- ========================================
-- FIELD UPDATE EVENT (Server -> Clients)
-- ========================================
-- Sent when soil data changes (harvest, fertilizer) for a single field
SoilFieldUpdateEvent = {}
SoilFieldUpdateEvent_mt = Class(SoilFieldUpdateEvent, Event)

InitEventClass(SoilFieldUpdateEvent, "SoilFieldUpdateEvent")

function SoilFieldUpdateEvent.emptyNew()
    return Event.new(SoilFieldUpdateEvent_mt)
end

function SoilFieldUpdateEvent.new(fieldId, fieldData)
    local self = SoilFieldUpdateEvent.emptyNew()
    self.fieldId = fieldId
    self.field = fieldData
    return self
end

function SoilFieldUpdateEvent:readStream(streamId, connection)
    self.fieldId = streamReadInt32(streamId)
    self.field = {
        nitrogen = streamReadFloat32(streamId),
        phosphorus = streamReadFloat32(streamId),
        potassium = streamReadFloat32(streamId),
        organicMatter = streamReadFloat32(streamId),
        pH = streamReadFloat32(streamId),
        lastCrop = streamReadString(streamId),
        lastHarvest = streamReadInt32(streamId),
        fertilizerApplied = streamReadFloat32(streamId),
        initialized = true
    }
    -- Clear empty strings
    if self.field.lastCrop == "" then
        self.field.lastCrop = nil
    end

    self:run(connection)
end

function SoilFieldUpdateEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.fieldId)
    streamWriteFloat32(streamId, self.field.nitrogen or 50)
    streamWriteFloat32(streamId, self.field.phosphorus or 40)
    streamWriteFloat32(streamId, self.field.potassium or 45)
    streamWriteFloat32(streamId, self.field.organicMatter or 3.5)
    streamWriteFloat32(streamId, self.field.pH or 6.5)
    streamWriteString(streamId, self.field.lastCrop or "")
    streamWriteInt32(streamId, self.field.lastHarvest or 0)
    streamWriteFloat32(streamId, self.field.fertilizerApplied or 0)
end

function SoilFieldUpdateEvent:run(connection)
    -- CLIENT ONLY: Apply server-authoritative field data
    if not g_client then return end

    if g_SoilFertilityManager and g_SoilFertilityManager.soilSystem then
        g_SoilFertilityManager.soilSystem.fieldData[self.fieldId] = self.field

        if g_SoilFertilityManager.settings.debugMode then
            print(string.format("[SoilFertilizer] Client: Field %d synced from server (N=%.1f, P=%.1f, K=%.1f)",
                self.fieldId, self.field.nitrogen, self.field.phosphorus, self.field.potassium))
        end
    end
end

-- ========================================
-- HELPER FUNCTIONS
-- ========================================

-- Check if current player is admin
function SoilNetworkEvents_IsPlayerAdmin()
    if not g_currentMission then return false end

    -- Single player = always admin
    if not g_currentMission.missionDynamicInfo.isMultiplayer then
        return true
    end

    -- Dedicated server console = always admin
    if g_dedicatedServer then
        return true
    end

    -- Multiplayer: check if master user
    local currentUser = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    if currentUser then
        return currentUser:getIsMasterUser()
    end

    return false
end

-- Send setting change request
function SoilNetworkEvents_RequestSettingChange(settingName, value)
    if g_client then
        -- Client: send request to server
        g_client:getServerConnection():sendEvent(
            SoilSettingChangeEvent.new(settingName, value)
        )
        print(string.format("[SoilFertilizer] Client: Requesting setting change '%s' = %s",
            settingName, tostring(value)))
    else
        -- Server/Singleplayer: apply directly
        if g_SoilFertilityManager and g_SoilFertilityManager.settings then
            g_SoilFertilityManager.settings[settingName] = value
            g_SoilFertilityManager.settings:save()

            print(string.format("[SoilFertilizer] Server: Setting '%s' changed to %s",
                settingName, tostring(value)))

            -- Broadcast if multiplayer server
            if g_server then
                g_server:broadcastEvent(
                    SoilSettingSyncEvent.new(settingName, value)
                )
            end
        end
    end
end

-- Request full sync from server with retry logic using AsyncRetryHandler
local fullSyncRetryHandler = nil

function SoilNetworkEvents_InitializeRetryHandler()
    if fullSyncRetryHandler then return end

    fullSyncRetryHandler = AsyncRetryHandler.new({
        name = "FullSync",
        maxAttempts = SoilConstants.NETWORK.FULL_SYNC_MAX_ATTEMPTS,
        delays = {
            SoilConstants.NETWORK.FULL_SYNC_RETRY_INTERVAL,
            SoilConstants.NETWORK.FULL_SYNC_RETRY_INTERVAL,
            SoilConstants.NETWORK.FULL_SYNC_RETRY_INTERVAL
        },

        onAttempt = function()
            if not g_client or g_server then return end
            g_client:getServerConnection():sendEvent(SoilRequestFullSyncEvent.new())
            SoilLogger.info("Client: Requesting full sync (attempt %d/%d)",
                fullSyncRetryHandler:getAttempts(), fullSyncRetryHandler.maxAttempts)
        end,

        onSuccess = function()
            SoilLogger.info("Client: Full sync completed successfully")
        end,

        onFailure = function()
            SoilLogger.warning("Client: Full sync failed after max attempts")
        end
    })
end

function SoilNetworkEvents_RequestFullSync()
    if not g_client or g_server then return end

    SoilNetworkEvents_InitializeRetryHandler()
    fullSyncRetryHandler:start()
end

-- Called from update loop to handle retry
function SoilNetworkEvents_UpdateSyncRetry(dt)
    if fullSyncRetryHandler then
        fullSyncRetryHandler:update(dt)
    end
end

-- Mark sync as received (called from SoilFullSyncEvent:run)
function SoilNetworkEvents_OnFullSyncReceived()
    if fullSyncRetryHandler then
        fullSyncRetryHandler:markSuccess()
    end
end

print("[SoilFertilizer] Network events system loaded")
