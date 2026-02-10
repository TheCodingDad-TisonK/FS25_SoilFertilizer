-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Network Events
-- =========================================================
-- Handles multiplayer synchronization of settings and state
-- =========================================================
-- Author: TisonK
-- =========================================================

-- ========================================
-- SETTING CHANGE EVENT (Client → Server)
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
    
    if valueType == 0 then -- boolean
        self.settingValue = streamReadBool(streamId)
    elseif valueType == 1 then -- number (int)
        self.settingValue = streamReadInt32(streamId)
    elseif valueType == 2 then -- string
        self.settingValue = streamReadString(streamId)
    end
    
    self:run(connection)
end

function SoilSettingChangeEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)
    
    if type(self.settingValue) == "boolean" then
        streamWriteUInt8(streamId, 0)
        streamWriteBool(streamId, self.settingValue)
    elseif type(self.settingValue) == "number" then
        streamWriteUInt8(streamId, 1)
        streamWriteInt32(streamId, self.settingValue)
    else
        streamWriteUInt8(streamId, 2)
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
            print(string.format("[Soil Mod] Player %s (non-admin) tried to change settings - denied", 
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
        
        print(string.format("[Soil Mod] Server: Setting '%s' changed from %s to %s", 
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
-- SETTING SYNC EVENT (Server → Clients)
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
    
    if valueType == 0 then
        self.settingValue = streamReadBool(streamId)
    elseif valueType == 1 then
        self.settingValue = streamReadInt32(streamId)
    else
        self.settingValue = streamReadString(streamId)
    end
    
    self:run(connection)
end

function SoilSettingSyncEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.settingName)
    
    if type(self.settingValue) == "boolean" then
        streamWriteUInt8(streamId, 0)
        streamWriteBool(streamId, self.settingValue)
    elseif type(self.settingValue) == "number" then
        streamWriteUInt8(streamId, 1)
        streamWriteInt32(streamId, self.settingValue)
    else
        streamWriteUInt8(streamId, 2)
        streamWriteString(streamId, tostring(self.settingValue))
    end
end

function SoilSettingSyncEvent:run(connection)
    -- CLIENT ONLY: Receive setting update from server
    if not g_client then return end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local oldValue = g_SoilFertilityManager.settings[self.settingName]
        g_SoilFertilityManager.settings[self.settingName] = self.settingValue
        
        print(string.format("[Soil Mod] Client: Setting '%s' synced from %s to %s", 
            self.settingName, tostring(oldValue), tostring(self.settingValue)))
        
        -- Refresh UI if open
        if g_SoilFertilityManager.settingsUI then
            g_SoilFertilityManager.settingsUI:refreshUI()
        end
    end
end

-- ========================================
-- FULL SYNC REQUEST (Client → Server)
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
    -- SERVER ONLY: Send full settings to requesting client
    if not g_server or not connection then return end
    
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        print("[Soil Mod] Server: Sending full settings sync to client")
        connection:sendEvent(SoilFullSyncEvent.new(g_SoilFertilityManager.settings))
    end
end

-- ========================================
-- FULL SYNC RESPONSE (Server → Client)
-- ========================================
SoilFullSyncEvent = {}
SoilFullSyncEvent_mt = Class(SoilFullSyncEvent, Event)

InitEventClass(SoilFullSyncEvent, "SoilFullSyncEvent")

function SoilFullSyncEvent.emptyNew()
    return Event.new(SoilFullSyncEvent_mt)
end

function SoilFullSyncEvent.new(settings)
    local self = SoilFullSyncEvent.emptyNew()
    self.settings = settings
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
end

function SoilFullSyncEvent:run(connection)
    -- CLIENT ONLY: Receive full settings from server
    if not g_client or not g_SoilFertilityManager then return end
    
    print("[Soil Mod] Client: Received full settings sync from server")
    
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
    
    -- Refresh UI if open
    if g_SoilFertilityManager.settingsUI then
        g_SoilFertilityManager.settingsUI:refreshUI()
    end
    
    print(string.format("[Soil Mod] Client: Settings synced - Enabled: %s, Difficulty: %s", 
        tostring(settings.enabled), settings:getDifficultyName()))
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
        print(string.format("[Soil Mod] Client: Requesting setting change '%s' = %s", 
            settingName, tostring(value)))
    else
        -- Server/Singleplayer: apply directly
        if g_SoilFertilityManager and g_SoilFertilityManager.settings then
            g_SoilFertilityManager.settings[settingName] = value
            g_SoilFertilityManager.settings:save()
            
            print(string.format("[Soil Mod] Server: Setting '%s' changed to %s", 
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

-- Request full sync from server
function SoilNetworkEvents_RequestFullSync()
    if g_client and not g_server then
        g_client:getServerConnection():sendEvent(SoilRequestFullSyncEvent.new())
        print("[Soil Mod] Client: Requesting full settings sync")
    end
end

print("[Soil Mod] Network events system loaded")