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

    -- Sprayer rate manager (always active — not GUI-dependent)
    self.sprayerRateManager = SprayerRateManager.new()

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

        -- Hook PlayerInputComponent.registerActionEvents to register J/K in the PLAYER context.
        -- PLAYER context is reused (not recreated) when the player returns on foot, so these
        -- events persist across vehicle entry/exit cycles.
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

                -- Register J and K in PLAYER context (on-foot use).
                -- PlayerStateDriving calls setContext("PLAYER") WITHOUT createNew=true,
                -- so the PLAYER context is reused and our events survive vehicle transitions.
                g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

                local hudOk, hudId = g_inputBinding:registerActionEvent(
                    InputAction.SF_TOGGLE_HUD, g_SoilFertilityManager,
                    g_SoilFertilityManager.onToggleHUDInput,
                    false, true, false, true
                )
                if hudOk and hudId then
                    g_SoilFertilityManager.toggleHUDEventId = hudId
                    SoilLogger.info("HUD toggle (J) registered in PLAYER context")
                else
                    SoilLogger.warning("HUD toggle (J) PLAYER registration failed")
                end

                if g_SoilFertilityManager.soilReportDialog then
                    local repOk, repId = g_inputBinding:registerActionEvent(
                        InputAction.SF_SOIL_REPORT, g_SoilFertilityManager,
                        g_SoilFertilityManager.onSoilReportInput,
                        false, true, false, true
                    )
                    if repOk and repId then
                        g_SoilFertilityManager.soilReportEventId = repId
                        SoilLogger.info("Soil Report (K) registered in PLAYER context")
                    end
                end

                g_inputBinding:endActionEventsModification()
                SoilLogger.info("PLAYER context input registration complete")
            end
            SoilLogger.info("PlayerInputComponent hook installed for J/K (PLAYER context)")
        end

        -- Hook InputBinding.endActionEventsModification to register our keys in VEHICLE context.
        --
        -- WHY this approach instead of hooking Vehicle.registerActionEvents directly:
        -- SpecializationUtil.copyTypeFunctionsInto() copies functions to each vehicle INSTANCE
        -- table at spawn time. After that, vehicle:registerActionEvents() resolves from the
        -- instance table, never looking up Vehicle.registerActionEvents on the class. Any
        -- override of Vehicle.registerActionEvents after vehicles exist is silently ignored.
        --
        -- Instead, we hook InputBinding.endActionEventsModification (a class method on the
        -- InputBinding class). Every call to endActionEventsModification routes through it,
        -- including every VEHICLE context close. We detect VEHICLE context and inject our events.
        -- registerActionEvent's built-in dedup handles multiple calls per session gracefully.
        if self.soilHUD and InputBinding and InputBinding.endActionEventsModification then
            local _soilVehicleHookActive = false
            local originalEndMod = InputBinding.endActionEventsModification
            self._vehicleInputHookOriginal = originalEndMod
            InputBinding.endActionEventsModification = function(binding, ignoreCheck)
                -- Capture context name BEFORE the original resets it to NO_REGISTRATION_CONTEXT
                local contextName = ""
                if binding.registrationContext and
                   binding.registrationContext ~= InputBinding.NO_REGISTRATION_CONTEXT then
                    contextName = binding.registrationContext.name or ""
                end

                originalEndMod(binding, ignoreCheck)

                -- Only act on VEHICLE context closures, and avoid re-entrancy
                if contextName ~= Vehicle.INPUT_CONTEXT_NAME then return end
                if _soilVehicleHookActive then return end
                if not g_SoilFertilityManager or not g_SoilFertilityManager.soilHUD then return end

                _soilVehicleHookActive = true
                binding:beginActionEventsModification(Vehicle.INPUT_CONTEXT_NAME)

                -- HUD toggle (J) in vehicle
                local vHudOk, vHudId = binding:registerActionEvent(
                    InputAction.SF_TOGGLE_HUD, g_SoilFertilityManager,
                    g_SoilFertilityManager.onToggleHUDInput,
                    false, true, false, true
                )
                if vHudOk and vHudId then
                    g_SoilFertilityManager.vehicleHUDEventId = vHudId
                    SoilLogger.info("HUD toggle (J) registered in VEHICLE context")
                end

                -- Soil Report (K) in vehicle
                if g_SoilFertilityManager.soilReportDialog then
                    local vRepOk, vRepId = binding:registerActionEvent(
                        InputAction.SF_SOIL_REPORT, g_SoilFertilityManager,
                        g_SoilFertilityManager.onSoilReportInput,
                        false, true, false, true
                    )
                    if vRepOk and vRepId then
                        g_SoilFertilityManager.vehicleReportEventId = vRepId
                        SoilLogger.info("Soil Report (K) registered in VEHICLE context")
                    end
                end

                -- Rate UP (])
                local upOk, upId = binding:registerActionEvent(
                    InputAction.SF_RATE_UP, g_SoilFertilityManager,
                    g_SoilFertilityManager.onSprayerRateUpInput,
                    false, true, false, true
                )
                if upOk and upId then
                    g_SoilFertilityManager.rateUpEventId = upId
                    SoilLogger.info("Rate UP (]) registered in VEHICLE context")
                end

                -- Rate DOWN ([)
                local downOk, downId = binding:registerActionEvent(
                    InputAction.SF_RATE_DOWN, g_SoilFertilityManager,
                    g_SoilFertilityManager.onSprayerRateDownInput,
                    false, true, false, true
                )
                if downOk and downId then
                    g_SoilFertilityManager.rateDownEventId = downId
                    SoilLogger.info("Rate DOWN ([) registered in VEHICLE context")
                end

                -- Auto toggle (Shift+L)
                local autoOk, autoId = binding:registerActionEvent(
                    InputAction.SF_TOGGLE_AUTO, g_SoilFertilityManager,
                    g_SoilFertilityManager.onToggleAutoInput,
                    false, true, false, true
                )
                if autoOk and autoId then
                    g_SoilFertilityManager.toggleAutoEventId = autoId
                    SoilLogger.info("Auto toggle (Shift+L) registered in VEHICLE context")
                end

                binding:endActionEventsModification()
                _soilVehicleHookActive = false
            end
            SoilLogger.info("InputBinding.endActionEventsModification hooked for VEHICLE context keys")
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
            self.soilHUD:loadLayout()
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

            -- Guard 3: FarmlandManager must be available for ownership hook installation.
            -- Without this, the ownership hook fails on heavily modded servers where
            -- farmlandManager loads after fieldManager.
            if not g_farmlandManager then
                if self.attempts >= self.maxAttempts then
                    SoilLogger.warning("Deferred init timeout: FarmlandManager not available after %d attempts", self.attempts)
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

-- Input callbacks for sprayer rate up/down ([ / ] keys in VEHICLE context)
-- Note: `self` here is the sprayer vehicle (the action event target), not SoilFertilityManager.
-- Player-context rate callbacks (registered in PlayerInputComponent hook).
-- `self` here is g_SoilFertilityManager.  Current vehicle is fetched via g_localPlayer.
local function getPlayerVehicle()
    if not g_localPlayer then return nil end
    if type(g_localPlayer.getIsInVehicle) ~= "function" then return nil end
    if not g_localPlayer:getIsInVehicle() then return nil end
    return g_localPlayer:getCurrentVehicle()
end

-- Returns the fertilizer applicator relevant for rate adjustment.
-- Checks the directly driven vehicle first; if that is not an applicator (e.g. a
-- tractor towing a spreader), scans the attacher-joint implement tree.
-- Mirrors the same logic in SoilHUD:getCurrentSprayer so both the HUD panel
-- and the key callbacks always agree on which vehicle the rate belongs to.
local function getApplicatorVehicle()
    local v = getPlayerVehicle()
    if not v then return nil end

    -- Direct (self-propelled): liquid sprayer, air seeder, etc.
    if SoilFertilityManager.isFertilizerApplicator(v) then
        return v
    end

    -- Pulled implement: walk the attacher-joint tree
    local function scanImpls(root)
        local ok, spec = pcall(function() return root.spec_attacherJoints end)
        if not ok or not spec then return nil end
        local ok2, impls = pcall(function() return spec.attachedImplements end)
        if not ok2 or not impls then return nil end
        for _, impl in pairs(impls) do
            local obj = impl.object
            if obj then
                if SoilFertilityManager.isFertilizerApplicator(obj) then
                    return obj
                end
                local found = scanImpls(obj)
                if found then return found end
            end
        end
        return nil
    end
    return scanImpls(v)
end

function SoilFertilityManager:onSprayerRateUpInput()
    local vehicle = getApplicatorVehicle()
    if not vehicle then return end
    local rm = self.sprayerRateManager
    if rm then
        local newIdx = rm:cycleUp(vehicle.id)
        SoilNetworkEvents_SendSprayerRate(vehicle.id, newIdx)
    end
end

function SoilFertilityManager:onSprayerRateDownInput()
    local vehicle = getApplicatorVehicle()
    if not vehicle then return end
    local rm = self.sprayerRateManager
    if rm then
        local newIdx = rm:cycleDown(vehicle.id)
        SoilNetworkEvents_SendSprayerRate(vehicle.id, newIdx)
    end
end

function SoilFertilityManager:onToggleAutoInput()
    local vehicle = getApplicatorVehicle()
    if not vehicle then return end
    if not self.settings.autoRateControl then return end
    local rm = self.sprayerRateManager
    if rm then
        local newState = rm:toggleAutoMode(vehicle.id)
        SoilNetworkEvents_SendSprayerAutoMode(vehicle.id, newState)
    end
end

--- Helper function to determine if a vehicle is a fertilizer applicator (sprayer, spreader, planter)
--- This includes vehicles with spec_sprayer or vehicles with fill units whose SUPPORTED fill types
--- include any type belonging to the mod's SPREADER or SPRAYER categories.
---
--- FIX (Issue #1 / Issue #2):
---   Previously this checked fillUnit.fillTypeIndex (the *currently loaded* fill type) and
---   workArea:getIsActive() (only true while physically working a field). Both are always wrong
---   at vehicle-enter time:
---     - fillTypeIndex is 0/FT_UNKNOWN when the spreader is empty → category check fails → no rate UI
---     - getIsActive() is always false at enter time → entire spreader branch was dead code
---   The fix iterates fillUnit.supportedFillTypes (the static set of types the fill unit can hold,
---   registered at mission load time) and removes the isWorkAreaActive gate entirely.
---   This correctly identifies spreaders as fertilizer applicators regardless of their current
---   fill level, which also resolves the fill-acceptance detection used downstream.
---@param vehicle table The vehicle object to check
---@return boolean True if the vehicle is a fertilizer applicator, false otherwise.
function SoilFertilityManager.isFertilizerApplicator(vehicle)
    if not vehicle then
        return false
    end

    -- Fast path: check for dedicated applicator specializations.
    -- All of these are set at vehicle load time and are always reliable even when empty.
    --   spec_sprayer              → liquid sprayers (Patriot 50, anhydrous applicators, etc.)
    --   spec_manureSpreader       → solid/liquid manure spreaders, lime spreaders
    --   spec_slurryTanker         → slurry / liquid manure tankers
    --   spec_limeSpreader         → dedicated lime spreader spec (some mods)
    --   spec_fertilizingCultivator  → cultivators that also apply fertilizer/herbicide
    --   spec_fertilizingSowingMachine → seeders that apply starter fertilizer in-furrow
    --   spec_manureBarrel         → backpack/small barrel sprayers
    if vehicle.spec_sprayer
    or vehicle.spec_manureSpreader
    or vehicle.spec_slurryTanker
    or vehicle.spec_limeSpreader
    or vehicle.spec_fertilizingCultivator
    or vehicle.spec_fertilizingSowingMachine
    or vehicle.spec_manureBarrel then
        return true
    end

    -- Slow path: applicators whose specialization we don't directly recognize.
    -- Checks whether any supported fill type is one our system tracks in FERTILIZER_PROFILES.
    --
    -- IMPORTANT guard: also require spec_workArea.
    -- All implements that ACTIVELY apply material to the ground have spec_workArea
    -- (sprayers, spreaders, cultivators, seeders). Transport wagons, grain trailers,
    -- overload belts, and auger wagons do NOT have spec_workArea even when they
    -- support fill types like LIME or POTASH (e.g., via category mods like
    -- FS25_0_THDefaultTypes adding LIME to the BULK fill type category).
    -- This guard eliminates false positives from transport equipment.
    if vehicle.spec_workArea and vehicle.spec_fillUnit and g_fillTypeManager then
        local fillUnits = vehicle.spec_fillUnit.fillUnits
        if fillUnits then
            for _, fillUnit in ipairs(fillUnits) do
                if fillUnit.supportedFillTypes then
                    for fillTypeIndex, supported in pairs(fillUnit.supportedFillTypes) do
                        if supported then
                            local ft = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                            if ft and ft.name and SoilConstants.FERTILIZER_PROFILES[ft.name] then
                                return true
                            end
                        end
                    end
                end
            end
        end
    end

    return false
end

--- Save soil data to XML file
--- Only runs on server in multiplayer, always in singleplayer
--- Saves to {savegame}/soilData.xml
function SoilFertilityManager:saveSoilData()
    print("[SoilFertilizer DIAG] saveSoilData() CALLED")
    if not self.soilSystem then
        print("[SoilFertilizer DIAG] saveSoilData() ABORT: soilSystem is nil")
        return
    end
    if not g_currentMission or not g_currentMission.missionInfo then
        print("[SoilFertilizer DIAG] saveSoilData() ABORT: missionInfo is nil")
        return
    end

    local savegamePath = g_currentMission.missionInfo.savegameDirectory
    print("[SoilFertilizer DIAG] saveSoilData() savegamePath = " .. tostring(savegamePath))
    if not savegamePath then
        print("[SoilFertilizer DIAG] saveSoilData() ABORT: savegamePath is nil")
        return
    end

    -- Count fields with data
    local fieldCount = 0
    if self.soilSystem.fieldData then
        for _ in pairs(self.soilSystem.fieldData) do fieldCount = fieldCount + 1 end
    end
    print(string.format("[SoilFertilizer DIAG] saveSoilData() fields in memory: %d", fieldCount))

    local xmlPath = savegamePath .. "/soilData.xml"
    print("[SoilFertilizer DIAG] saveSoilData() writing to: " .. xmlPath)
    local xmlFile = createXMLFile("soilData", xmlPath, "soilData")

    if xmlFile then
        self.soilSystem:saveToXMLFile(xmlFile, "soilData")
        saveXMLFile(xmlFile)
        delete(xmlFile)
        print("[SoilFertilizer DIAG] saveSoilData() SUCCESS — file written")
        SoilLogger.info("Soil data saved to %s (%d fields)", xmlPath, fieldCount)
    else
        print("[SoilFertilizer DIAG] saveSoilData() FAILED — createXMLFile returned nil for: " .. xmlPath)
        SoilLogger.error("Failed to create XML file for save: %s", xmlPath)
    end
end

--- Load soil data from XML file
--- Reads from {savegame}/soilData.xml if exists
--- Falls back to defaults if file not found
function SoilFertilityManager:loadSoilData()
    print("[SoilFertilizer DIAG] loadSoilData() CALLED")
    if not self.soilSystem then
        print("[SoilFertilizer DIAG] loadSoilData() ABORT: soilSystem is nil")
        return
    end
    if not g_currentMission or not g_currentMission.missionInfo then
        print("[SoilFertilizer DIAG] loadSoilData() ABORT: missionInfo is nil")
        return
    end

    local savegamePath = g_currentMission.missionInfo.savegameDirectory
    print("[SoilFertilizer DIAG] loadSoilData() savegamePath = " .. tostring(savegamePath))
    if not savegamePath then
        print("[SoilFertilizer DIAG] loadSoilData() ABORT: savegamePath is nil")
        return
    end

    local xmlPath = savegamePath .. "/soilData.xml"
    print("[SoilFertilizer DIAG] loadSoilData() looking for: " .. xmlPath)
    if fileExists(xmlPath) then
        print("[SoilFertilizer DIAG] loadSoilData() FILE FOUND — loading...")
        local xmlFile = loadXMLFile("soilData", xmlPath)
        if xmlFile then
            self.soilSystem:loadFromXMLFile(xmlFile, "soilData")
            delete(xmlFile)
            -- Count fields loaded
            local fieldCount = 0
            if self.soilSystem.fieldData then
                for _ in pairs(self.soilSystem.fieldData) do fieldCount = fieldCount + 1 end
            end
            print(string.format("[SoilFertilizer DIAG] loadSoilData() SUCCESS — %d fields loaded", fieldCount))
            SoilLogger.info("Soil data loaded from %s (%d fields)", xmlPath, fieldCount)
        else
            print("[SoilFertilizer DIAG] loadSoilData() FAILED — loadXMLFile returned nil")
        end
    else
        print("[SoilFertilizer DIAG] loadSoilData() FILE NOT FOUND — using defaults")
        SoilLogger.info("No saved soil data found at %s, using defaults", xmlPath)
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

    -- Restore InputBinding.endActionEventsModification hook if we installed one
    if self._vehicleInputHookOriginal and InputBinding then
        InputBinding.endActionEventsModification = self._vehicleInputHookOriginal
        self._vehicleInputHookOriginal = nil
        SoilLogger.info("InputBinding.endActionEventsModification hook restored")
    end

    -- Clean up sprayer rate state
    if self.sprayerRateManager then
        self.sprayerRateManager:delete()
        self.sprayerRateManager = nil
    end

    -- Clean up all registered input action events (PLAYER context)
    if self.toggleHUDEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.toggleHUDEventId)
        self.toggleHUDEventId = nil
    end

    if self.soilReportEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.soilReportEventId)
        self.soilReportEventId = nil
    end

    -- Clean up VEHICLE context events
    if self.vehicleHUDEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.vehicleHUDEventId)
        self.vehicleHUDEventId = nil
    end

    if self.vehicleReportEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.vehicleReportEventId)
        self.vehicleReportEventId = nil
    end

    if self.rateUpEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.rateUpEventId)
        self.rateUpEventId = nil
    end

    if self.rateDownEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.rateDownEventId)
        self.rateDownEventId = nil
    end

    if self.toggleAutoEventId and g_inputBinding then
        g_inputBinding:removeActionEvent(self.toggleAutoEventId)
        self.toggleAutoEventId = nil
    end

    if self.soilReportDialog then
        if g_gui then g_gui:closeDialogByName("SoilReportDialog") end
        self.soilReportDialog = nil
        SoilReportDialog.instance = nil
    end

    if self.soilHUD then
        self.soilHUD:saveLayout()
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