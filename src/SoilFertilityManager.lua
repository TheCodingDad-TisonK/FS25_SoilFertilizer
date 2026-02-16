-- =========================================================
-- FS25 Realistic Soil & Fertilizer (FarmlandManager version)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE: All rights reserved.
-- =========================================================
---@class SoilFertilityManager
SoilFertilityManager = {}
local SoilFertilityManager_mt = Class(SoilFertilityManager)

--- Create new SoilFertilityManager instance
---@param mission table The mission object
---@param modDirectory string Path to mod directory
---@param modName string Name of the mod
---@param disableGUI boolean Whether to disable GUI elements
---@return SoilFertilityManager
function SoilFertilityManager.new(mission, modDirectory, modName, disableGUI)
    local self = setmetatable({}, SoilFertilityManager_mt)

    self.mission = mission
    self.modDirectory = modDirectory
    self.modName = modName
    self.disableGUI = disableGUI or false
    self.guiRetryHandler = nil

    -- Settings
    if not SettingsManager then
        SoilLogger.error("CRITICAL: SettingsManager not loaded - mod cannot initialize")
        if g_gui then
            g_gui:showInfoDialog({
                text = "Soil & Fertilizer Mod failed to load.\n\nCritical module 'SettingsManager' is missing.\n\nPlease reinstall the mod or check for conflicts with other mods.",
                title = "Mod Load Error"
            })
        end
        return nil
    end
    self.settingsManager = SettingsManager.new()
    self.settings = Settings.new(self.settingsManager)

    -- Soil system
    if not SoilFertilitySystem then
        SoilLogger.error("CRITICAL: SoilFertilitySystem not loaded - mod cannot initialize")
        if g_gui then
            g_gui:showInfoDialog({
                text = "Soil & Fertilizer Mod failed to load.\n\nCritical module 'SoilFertilitySystem' is missing.\n\nPlease reinstall the mod or check for conflicts with other mods.",
                title = "Mod Load Error"
            })
        end
        return nil
    end
    self.soilSystem = SoilFertilitySystem.new(self.settings)

    -- GUI initialization (client only)
    local shouldInitGUI = not self.disableGUI and mission:getIsClient() and g_gui and not g_safeMode
    if shouldInitGUI then
        SoilLogger.info("Initializing GUI elements...")
        self.settingsUI = SoilSettingsUI.new(self.settings)

        -- Create retry handler for GUI injection
        self.guiRetryHandler = AsyncRetryHandler.new({
            name = "GUI_Injection",
            maxAttempts = 3,
            delays = {2000, 4000, 8000},  -- 2s, 4s, 8s - exponential backoff

            -- Attempt injection
            onAttempt = function()
                if not self.settingsUI or self.settingsUI.injected then return end

                local success, result = pcall(function()
                    return self.settingsUI:inject()
                end)

                if success and result then
                    -- Injection succeeded and validated
                    self.guiRetryHandler:markSuccess()
                end
            end,

            -- Check if already injected (manual success marker)
            condition = function()
                return self.settingsUI and self.settingsUI.injected
            end,

            -- Success callback
            onSuccess = function()
                SoilLogger.info("GUI injection completed successfully")
            end,

            -- Failure callback - show user dialog
            onFailure = function()
                SoilLogger.warning("GUI injection failed after all retry attempts")
                self:showGUIFailureDialog()
            end
        })

        -- Hook: Lazy injection when settings frame opens (primary path)
        InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
            InGameMenuSettingsFrame.onFrameOpen,
            function(frame)
                if self.settingsUI and not self.settingsUI.injected then
                    -- Try immediate injection
                    local success, result = pcall(function()
                        return self.settingsUI:inject()
                    end)

                    if success and result then
                        -- Success! Cancel any pending retries
                        if self.guiRetryHandler then
                            self.guiRetryHandler:markSuccess()
                        end
                    elseif not self.guiRetryHandler or not self.guiRetryHandler:isPending() then
                        -- Failed and no retry in progress - start retry sequence
                        SoilLogger.info("Initial GUI injection failed, starting retry sequence")
                        if self.guiRetryHandler then
                            self.guiRetryHandler:start()
                        end
                    end
                end

                -- Ensure reset button exists
                if self.settingsUI and self.settingsUI.injected then
                    self.settingsUI:ensureResetButton(frame)
                end
            end
        )

        -- Hook: Update buttons
        InGameMenuSettingsFrame.updateButtons = Utils.appendedFunction(
            InGameMenuSettingsFrame.updateButtons,
            function(frame)
                if self.settingsUI and self.settingsUI.injected then
                    self.settingsUI:ensureResetButton(frame)
                end
            end
        )

        -- Start background retry sequence (backup path)
        SoilLogger.info("Starting GUI injection retry handler")
        self.guiRetryHandler:start()
    else
        SoilLogger.info("GUI initialization skipped (Server/Console mode)")
        self.settingsUI = nil
    end

    -- Console commands
    self.settingsGUI = SoilSettingsGUI.new()
    self.settingsGUI:registerConsoleCommands()

    -- HUD (client only)
    if shouldInitGUI then
        if not SoilHUD then
            SoilLogger.error("CRITICAL: SoilHUD not loaded - HUD will be disabled")
            if g_gui then
                g_gui:showInfoDialog({
                    text = "Soil & Fertilizer Mod: HUD module failed to load.\n\nThe mod will run without the HUD display.\n\nCore features remain active.",
                    title = "HUD Load Warning"
                })
            end
            self.soilHUD = nil
        else
            self.soilHUD = SoilHUD.new(self.soilSystem, self.settings)
            SoilLogger.info("Soil HUD created")
        end
    else
        self.soilHUD = nil
    end

    -- Load settings
    self.settings:load()

    -- Load saved soil data
    self:loadSoilData()

    -- Compatibility with other mods
    self:checkAndApplyCompatibility()

    return self
end

function SoilFertilityManager:checkAndApplyCompatibility()
    -- Precision Farming
    local pfDetected = false
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("precisionfarming") then
                pfDetected = true
                break
            end
        end
    end

    if pfDetected then
        SoilLogger.info("Precision Farming detected - enabling read-only mode")
        self.soilSystem.PFActive = true
        -- Note: Notification is shown later in onMissionLoaded (consolidates PF + activation message)
    else
        self.soilSystem.PFActive = false
    end

    -- Used Tyres mod
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("tyre") or lowerName:find("tire") or lowerName:find("used") then
                if self.settingsUI then
                    self.settingsUI.compatibilityMode = true
                end
                SoilLogger.info("Used Tyres mod detected - UI compatibility mode enabled")
                break
            end
        end
    end
end

--- Called after mission is loaded
--- Initializes HUD and sets up deferred hook installation
function SoilFertilityManager:onMissionLoaded()
    if not self.settings.enabled then return end

    local success, errorMsg = pcall(function()
        -- Initialize HUD immediately (client-side only)
        if self.soilHUD then
            self.soilHUD:initialize()
            self:registerInputActions()
        end

        -- Defer soil system initialization (hook installation) until game is ready
        -- This fixes the timing issue where FruitUtil, Sprayer, g_farmlandManager aren't loaded yet
        self:deferredSoilSystemInit()
    end)

    if not success then
        SoilLogger.error("Error during mission load - %s", tostring(errorMsg))
        self.settings.enabled = false
        self.settings:save()
    end
end

--- Deferred initialization of soil system using updater pattern
--- Waits for game to be fully ready before installing hooks
function SoilFertilityManager:deferredSoilSystemInit()
    if not self.soilSystem then return end

    SoilLogger.info("Scheduling deferred soil system initialization...")

    local hookInstaller = {
        sfm = self,
        installed = false,
        attempts = 0,
        maxAttempts = 30,  -- 30 attempts at 1 update/frame = ~1 second max wait

        update = function(self, dt)
            if self.installed then
                return true  -- Remove updater - job done
            end

            self.attempts = self.attempts + 1

            -- Guard 1: Mission must be started
            if not g_currentMission or not g_currentMission.isMissionStarted then
                if self.attempts >= self.maxAttempts then
                    SoilLogger.warning("Deferred init timeout: Mission not started after %d attempts", self.attempts)
                    return true  -- Give up and remove updater
                end
                return false  -- Keep waiting
            end

            -- Guard 2: Field manager must be ready
            if not g_fieldManager or not g_fieldManager.fields then
                if self.attempts >= self.maxAttempts then
                    SoilLogger.warning("Deferred init timeout: FieldManager not ready after %d attempts", self.attempts)
                    return true  -- Give up and remove updater
                end
                return false  -- Keep waiting
            end

            -- All guards passed - initialize soil system now
            SoilLogger.info("Game ready after %d update cycles - initializing soil system...", self.attempts)

            local initSuccess, initError = pcall(function()
                self.sfm.soilSystem:initialize()

                -- Show consolidated notification (different message if PF is active)
                if self.sfm.settings.showNotifications and g_currentMission and g_currentMission.hud then
                    local message
                    if self.sfm.soilSystem.PFActive then
                        message = "Soil Mod: Viewer Mode (Precision Farming active) | Press J to toggle HUD"
                    else
                        message = "Soil & Fertilizer Mod Active | Press J to toggle HUD | Type 'soilfertility' for commands"
                    end
                    g_currentMission.hud:showBlinkingWarning(message, 8000)
                end
            end)

            if not initSuccess then
                SoilLogger.error("Deferred soil system init failed: %s", tostring(initError))
            end

            self.installed = true
            return true  -- Remove updater
        end
    }

    -- Register updater with mission
    if g_currentMission and g_currentMission.addUpdateable then
        g_currentMission:addUpdateable(hookInstaller)
        SoilLogger.info("Deferred init updater registered - waiting for game readiness...")
    else
        -- Fallback: try immediate initialization
        SoilLogger.warning("Mission.addUpdateable not available - attempting immediate init")
        self.soilSystem:initialize()
    end
end

-- Register input actions for HUD toggle
function SoilFertilityManager:registerInputActions()
    if not self.soilHUD then
        SoilLogger.info("HUD not available - input actions skipped")
        return
    end

    -- Use proper RVB pattern (Register-Validate-Bind) for FS25 input system
    g_inputBinding:beginActionEventsModification("PLAYER")

    local success, eventId = g_inputBinding:registerActionEvent(
        InputAction.SF_TOGGLE_HUD,
        self,
        self.onToggleHUDInput,
        false,  -- triggerUp
        true,   -- triggerDown
        false,  -- triggerAlways
        true,   -- startActive
        nil,    -- callbackState
        true    -- textVisibility
    )

    g_inputBinding:endActionEventsModification()

    if success and eventId then
        self.toggleHUDEventId = eventId
        SoilLogger.info("J HUD toggle registered")
    else
        SoilLogger.warning("Failed to register J HUD toggle")
    end
end

-- Input callback for HUD toggle (J)
function SoilFertilityManager:onToggleHUDInput()
    if self.soilHUD then
        self.soilHUD:toggleVisibility()
    end
end

--- Save soil data to XML file
--- Only runs on server in multiplayer, always in singleplayer
--- Saves to {savegame}/soilData.xml
function SoilFertilityManager:saveSoilData()
    if not self.soilSystem or not g_currentMission or not g_currentMission.missionInfo then
        return
    end

    local savegamePath = g_currentMission.missionInfo.savegameDirectory
    if not savegamePath then return end

    local xmlPath = savegamePath .. "/soilData.xml"
    local xmlFile = createXMLFile("soilData", xmlPath, "soilData")

    if xmlFile then
        self.soilSystem:saveToXMLFile(xmlFile, "soilData")
        saveXMLFile(xmlFile)
        delete(xmlFile)
        SoilLogger.info("Soil data saved to %s", xmlPath)
    end
end

--- Load soil data from XML file
--- Reads from {savegame}/soilData.xml if exists
--- Falls back to defaults if file not found
function SoilFertilityManager:loadSoilData()
    if not self.soilSystem or not g_currentMission or not g_currentMission.missionInfo then
        return
    end

    local savegamePath = g_currentMission.missionInfo.savegameDirectory
    if not savegamePath then return end

    local xmlPath = savegamePath .. "/soilData.xml"
    if fileExists(xmlPath) then
        local xmlFile = loadXMLFile("soilData", xmlPath)
        if xmlFile then
            self.soilSystem:loadFromXMLFile(xmlFile, "soilData")
            delete(xmlFile)
            SoilLogger.info("Soil data loaded from %s", xmlPath)
        end
    else
        SoilLogger.info("No saved soil data found, using defaults")
    end
end

--- Update loop called every frame
---@param dt number Delta time in milliseconds
function SoilFertilityManager:update(dt)
    -- Always update soil system (server side)
    if self.soilSystem then
        self.soilSystem:update(dt)
    end

    -- Update GUI retry handler if active
    if self.guiRetryHandler then
        self.guiRetryHandler:update(dt)
    end

    -- FIX: Only update HUD if it exists (client side only)
    if self.soilHUD then
        -- Add pcall to prevent crashes if HUD has issues
        local success, err = pcall(function()
            self.soilHUD:update(dt)
        end)
        if not success and self.settings and self.settings.debugMode then
            print("[SoilFertilizer DEBUG] HUD update error: " .. tostring(err))
        end
    end
end

--- Draw loop called every frame for rendering
function SoilFertilityManager:draw()
    -- FIX: Only draw HUD if it exists (client side only)
    if self.soilHUD then
        local success, err = pcall(function()
            self.soilHUD:draw()
        end)
        if not success and self.settings and self.settings.debugMode then
            print("[SoilFertilizer DEBUG] HUD draw error: " .. tostring(err))
        end
    end
end

--- Cleanup on mod unload
--- Saves soil data and uninstalls hooks
function SoilFertilityManager:delete()
    -- Save soil data before shutdown
    self:saveSoilData()

    -- Clean up retry handler
    if self.guiRetryHandler then
        self.guiRetryHandler:reset()
        self.guiRetryHandler = nil
    end

    -- Clean up HUD and input actions
    if self.toggleHUDEventId then
        g_inputBinding:removeActionEvent(self.toggleHUDEventId)
        self.toggleHUDEventId = nil
    end

    if self.soilHUD then
        self.soilHUD:delete()
        self.soilHUD = nil
    end

    if self.soilSystem then
        self.soilSystem:delete()
    end
    if self.settings then
        self.settings:save()
    end
    SoilLogger.info("Shutting down")
end

-- Show GUI failure dialog with retry option
function SoilFertilityManager:showGUIFailureDialog()
    if not g_gui then return end

    -- Don't show dialog if we're already shutting down
    if not g_currentMission or g_currentMission.cancelLoading then return end

    local dialogText = "Soil & Fertilizer Mod: Settings UI unavailable.\n\n" ..
                      "The mod is active and working, but the settings menu couldn't be loaded.\n" ..
                      "This can happen when other mods interfere with menu initialization.\n\n" ..
                      "The mod is still tracking soil nutrients and all features are active.\n\n" ..
                      "Would you like to:\n" ..
                      "• Try loading the UI again, or\n" ..
                      "• Use console commands instead?\n\n" ..
                      "(Console: Press ~ and type 'soilfertility' for commands)"

    g_gui:showYesNoDialog({
        text = dialogText,
        title = "Settings UI Failed to Load",
        yesText = "Try Again",
        noText = "Use Console",
        callback = function(retry)
            if retry then
                -- User wants to retry
                SoilLogger.info("User requested manual GUI injection retry")

                if self.settingsUI and not self.settingsUI.injected then
                    -- Reset and try again
                    local success, result = pcall(function()
                        return self.settingsUI:inject()
                    end)

                    if success and result then
                        g_gui:showInfoDialog({
                            text = "Settings UI loaded successfully!\n\nYou can now access Soil & Fertilizer settings in the game menu.",
                            title = "Success"
                        })
                        SoilLogger.info("Manual GUI injection succeeded")
                    else
                        g_gui:showInfoDialog({
                            text = "Settings UI still unavailable.\n\nPlease use console commands instead:\n\n" ..
                                  "Press ~ to open console\n" ..
                                  "Type 'soilfertility' for command list\n" ..
                                  "Type 'SoilShowSettings' to view current settings\n\n" ..
                                  "The mod is working normally, only the UI menu is affected.",
                            title = "Console Mode"
                        })
                        SoilLogger.warning("Manual GUI injection failed again")
                    end
                else
                    g_gui:showInfoDialog({
                        text = "Settings UI is now available!\n\nCheck your game menu.",
                        title = "Already Loaded"
                    })
                end
            else
                -- User chose console mode
                SoilLogger.info("User chose console-only mode")
                g_gui:showInfoDialog({
                    text = "Console Commands for Soil & Fertilizer Mod:\n\n" ..
                          "Press ~ to open console, then type:\n\n" ..
                          "• soilfertility - Show all commands\n" ..
                          "• SoilShowSettings - View current settings\n" ..
                          "• SoilEnable/SoilDisable - Toggle mod\n" ..
                          "• SoilSetDifficulty 1|2|3 - Change difficulty\n" ..
                          "• SoilFieldInfo <id> - Show field details\n\n" ..
                          "The mod is working normally!",
                    title = "Console Commands"
                })
            end
        end
    })
end
