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
    -- Hooks are installed at file-load time in SoilSettingsUI.lua (runs once).
    -- We just create the instance here; the hooks reference g_SoilFertilityManager.settingsUI.
    local shouldInitGUI = not self.disableGUI and mission:getIsClient() and g_gui and not g_safeMode
    if shouldInitGUI then
        SoilLogger.info("Initializing GUI elements...")
        self.settingsUI = SoilSettingsUI.new(self.settings)
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

        -- Soil Report dialog (K key)
        if SoilReportDialog and g_gui then
            self.soilReportDialog = SoilReportDialog.getInstance(modDirectory)
            SoilLogger.info("Soil Report dialog created")
        end

        -- Hook PlayerInputComponent.registerActionEvents for reliable J-key binding.
        -- This fires at exactly the right time (when the player's input subsystem is ready),
        -- eliminating the race condition from calling g_inputBinding during onMissionLoaded.
        -- Pattern proven in FS25_NPCFavor main.lua:430-523.
        if self.soilHUD and PlayerInputComponent and PlayerInputComponent.registerActionEvents then
            local originalRegisterActionEvents = PlayerInputComponent.registerActionEvents
            self._inputHookOriginal = originalRegisterActionEvents  -- saved for cleanup in delete()
            PlayerInputComponent.registerActionEvents = function(inputComponent, ...)
                originalRegisterActionEvents(inputComponent, ...)

                -- Only register for the local (owning) player, not for every networked player
                if not (inputComponent.player and inputComponent.player.isOwner) then return end
                -- Guard against double-registration across level reloads
                if g_SoilFertilityManager and g_SoilFertilityManager.toggleHUDEventId then return end
                if not g_SoilFertilityManager or not g_SoilFertilityManager.soilHUD then return end

                g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

                local success, eventId = g_inputBinding:registerActionEvent(
                    InputAction.SF_TOGGLE_HUD,
                    g_SoilFertilityManager,
                    g_SoilFertilityManager.onToggleHUDInput,
                    false,  -- triggerUp
                    true,   -- triggerDown
                    false,  -- triggerAlways
                    true    -- startActive
                )
                if success and eventId then
                    g_SoilFertilityManager.toggleHUDEventId = eventId
                    SoilLogger.info("HUD toggle (J) registered via PlayerInputComponent hook")
                else
                    SoilLogger.warning("HUD toggle (J) registration failed in PlayerInputComponent hook")
                end

                -- Register K key for Soil Report dialog
                if g_SoilFertilityManager.soilReportDialog and not g_SoilFertilityManager.soilReportEventId then
                    local reportSuccess, reportEventId = g_inputBinding:registerActionEvent(
                        InputAction.SF_SOIL_REPORT,
                        g_SoilFertilityManager,
                        g_SoilFertilityManager.onSoilReportInput,
                        false, true, false, true
                    )
                    if reportSuccess and reportEventId then
                        g_SoilFertilityManager.soilReportEventId = reportEventId
                        SoilLogger.info("Soil Report (K) registered via PlayerInputComponent hook")
                    end
                end

                g_inputBinding:endActionEventsModification()
            end
            SoilLogger.info("PlayerInputComponent hook installed for J/K keys")
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

    -- Informational detection for known mod categories
    if g_modIsLoaded then
        for modName, _ in pairs(g_modIsLoaded) do
            local lowerName = string.lower(tostring(modName))
            if lowerName:find("realisticharvesting") or lowerName:find("realistic_harvesting") then
                SoilLogger.info("RealisticHarvesting detected — harvest hooks appended safely; soil updates fire if FruitUtil still present")
            elseif lowerName:find("croprotation") or lowerName:find("crop_rotation") then
                SoilLogger.info("CropRotation detected — no conflict; separate crop tracking data")
            elseif lowerName:find("bettercontracts") then
                SoilLogger.info("BetterContracts detected — profile-based UI creation ensures no settings page corruption")
            elseif lowerName:find("mudsystem") or lowerName:find("mud_system") or lowerName:find("mudphysic") then
                SoilLogger.info("MudSystem/terrain mod detected — no conflict with soil nutrients")
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
        -- Input binding (J key) is registered via PlayerInputComponent hook in new(), not here
        if self.soilHUD then
            self.soilHUD:initialize()
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
        maxAttempts = 3000,  -- ~50s at 60fps — covers very heavy modded servers

        update = function(self, dt)
            if self.installed then
                return true  -- Remove updater - job done
            end

            self.attempts = self.attempts + 1

            -- Guard 1: Mission must exist and be in a started state.
            -- FS25 does not reliably expose isMissionStarted; instead check missionDynamicInfo.isStarted
            -- which is set once the loading screen completes, with a fallback to checking that hud
            -- exists (initialized late in the load sequence) for older or modded builds.
            local missionReady = g_currentMission ~= nil and (
                (g_currentMission.missionDynamicInfo ~= nil and g_currentMission.missionDynamicInfo.isStarted) or
                (g_currentMission.hud ~= nil)
            )
            if not missionReady then
                if self.attempts >= self.maxAttempts then
                    SoilLogger.warning("Deferred init timeout: Mission not ready after %d attempts", self.attempts)
                    return true  -- Give up and remove updater
                end
                return false  -- Keep waiting
            end

            -- Guard 2: Field manager must be ready AND populated with at least one field.
            -- On 100+ mod servers, g_fieldManager.fields exists as an empty table for several
            -- seconds before the game finishes populating it — we must wait for next() to return
            -- a valid entry, not just check for non-nil.
            if not g_fieldManager or not g_fieldManager.fields or next(g_fieldManager.fields) == nil then
                if self.attempts >= self.maxAttempts then
                    SoilLogger.warning("Deferred init timeout: FieldManager not populated after %d attempts", self.attempts)
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
                        message = "Soil Mod: Viewer Mode (Precision Farming active) | J = HUD | K = Soil Report"
                    else
                        message = "Soil & Fertilizer Mod Active | J = HUD | K = Soil Report | Type 'soilfertility' for commands"
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

-- NOTE: registerInputActions() removed.
-- J key is now registered inside the PlayerInputComponent.registerActionEvents hook
-- installed in SoilFertilityManager.new(). This fires at the exact moment the player's
-- input subsystem is ready, eliminating the race condition on dedicated-server clients.

-- Input callback for HUD toggle (J)
function SoilFertilityManager:onToggleHUDInput()
    if self.soilHUD then
        self.soilHUD:toggleVisibility()
    end
end

-- Input callback for Soil Report dialog (K)
function SoilFertilityManager:onSoilReportInput()
    if self.soilReportDialog then
        self.soilReportDialog:show()
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

    -- Restore PlayerInputComponent hook if we installed one
    if self._inputHookOriginal and PlayerInputComponent then
        PlayerInputComponent.registerActionEvents = self._inputHookOriginal
        self._inputHookOriginal = nil
        SoilLogger.info("PlayerInputComponent hook restored")
    end

    -- Clean up HUD and input actions
    if self.toggleHUDEventId then
        g_inputBinding:removeActionEvent(self.toggleHUDEventId)
        self.toggleHUDEventId = nil
    end

    if self.soilReportEventId then
        g_inputBinding:removeActionEvent(self.soilReportEventId)
        self.soilReportEventId = nil
    end

    if self.soilReportDialog then
        g_gui:closeDialogByName("SoilReportDialog")
        self.soilReportDialog = nil
        SoilReportDialog.instance = nil
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