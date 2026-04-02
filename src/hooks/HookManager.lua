-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Hook Manager
-- =========================================================
-- Manages installation and cleanup of game engine hooks
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class HookManager
HookManager = {}
local HookManager_mt = Class(HookManager)

function HookManager.new()
    local self = setmetatable({}, HookManager_mt)
    self.hooks = {}
    self.installed = false
    return self
end

--- Helper to get field ID from world coordinates
---@param x number World X coordinate
---@param z number World Z coordinate
---@return number|nil fieldId
function HookManager:getFieldIdAtWorldPosition(x, z)
    if not g_fieldManager then return nil end
    
    -- Try direct field lookup first (most accurate)
    local field = g_fieldManager:getFieldAtWorldPosition(x, z)
    if field and field.farmland and field.farmland.id then
        return field.farmland.id
    end
    
    -- Fallback to farmland detection
    if g_farmlandManager then
        local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
        if farmland and farmland.id then
            -- Convert farmland ID to field ID (usually same in FS25)
            return farmland.id
        end
    end
    
    return nil
end

--- Helper to get field ID from work area coordinates
---@param sx number Start X
---@param sz number Start Z
---@param wx number Width X
---@param wz number Width Z
---@param hx number Height X
---@param hz number Height Z
---@return number|nil fieldId
function HookManager:getFieldIdFromArea(sx, sz, wx, wz, hx, hz)
    -- Calculate center point of the work area for field detection
    local centerX = (sx + wx + hx) / 3
    local centerZ = (sz + wz + hz) / 3
    return self:getFieldIdAtWorldPosition(centerX, centerZ)
end

--- Install all game hooks for the soil system
--- Installs hooks for harvest, fertilizer (all sprayer/spreader types), plowing, ownership, and weather
--- When Precision Farming is active, skips nutrient-modifying hooks for efficiency
--- Stores references for proper cleanup on uninstall
---@param soilSystem SoilFertilitySystem The soil system instance to connect hooks to
---@param pfActive boolean|nil If true, skips nutrient-modifying hooks (PF Viewer Mode)
function HookManager:installAll(soilSystem, pfActive)
    if self.installed then
        SoilLogger.warning("Hooks already installed, skipping re-installation")
        return
    end

    local successCount = 0
    local failCount = 0

    if pfActive then
        SoilLogger.info("Viewer Mode (Precision Farming active) - installing minimal hooks...")
        -- Only install ownership hook for field cleanup - skip all nutrient-modifying hooks
        local success = self:installOwnershipHook()
        if success then successCount = successCount + 1 else failCount = failCount + 1 end
        SoilLogger.info("Viewer Mode hooks: %d installed, %d failed", successCount, failCount)
    else
        SoilLogger.info("Installing event hooks...")

        -- Harvest hook (FruitUtil)
        local harvestOk = self:installHarvestHook()
        if harvestOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Fertilizer application hook (covers ALL sprayers + spreaders via Sprayer specialization)
        local sprayerAreaOk = self:installSprayerAreaHook()
        if sprayerAreaOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Field ownership changes
        local ownershipOk = self:installOwnershipHook()
        if ownershipOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Weather/environment effects
        local weatherOk = self:installWeatherHook()
        if weatherOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Plowing benefits
        local plowingOk = self:installPlowingHook()
        if plowingOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Patch vanilla fill units to accept custom fertilizer types
        local fillUnitOk = self:installFillUnitHook()
        if fillUnitOk then successCount = successCount + 1 else failCount = failCount + 1 end

        SoilLogger.info("Hook installation complete: %d/%d successful, %d failed",
            successCount, successCount + failCount, failCount)

        if failCount > 0 then
            SoilLogger.warning("Some hooks failed to install - mod functionality may be limited")
        end
    end

    self.installed = true
end

--- Uninstall all hooks and restore original functions
--- Called on mod unload to prevent hook accumulation
function HookManager:uninstallAll()
    if not self.installed then return end

    for i = #self.hooks, 1, -1 do
        local hook = self.hooks[i]
        if hook.cleanup then
            hook.cleanup()
            SoilLogger.debug("Cleaned up: %s", hook.name or "?")
        elseif hook.target and hook.key and hook.original then
            hook.target[hook.key] = hook.original
            SoilLogger.debug("Restored original: %s", hook.name or hook.key)
        end
    end

    self.hooks = {}
    self.installed = false
    SoilLogger.info("All hooks uninstalled")
end

--- Register a hook for later cleanup.
---@param target table The object containing the function
---@param key string The function key on the target
---@param original function The original function reference before hooking
---@param name string A human-readable name for logging
function HookManager:register(target, key, original, name)
    table.insert(self.hooks, {
        target = target,
        key = key,
        original = original,
        name = name or key
    })
end

--- Register a cleanup-only hook (e.g. message center subscriptions).
---@param name string A human-readable name for logging
---@param cleanupFn function Called during uninstallAll() to undo the hook
function HookManager:registerCleanup(name, cleanupFn)
    table.insert(self.hooks, {
        name = name,
        cleanup = cleanupFn
    })
end

-- =========================================================
-- HOOK 1: Harvest events (Combine.addCutterArea)
-- =========================================================
-- FruitUtil.fruitPickupEvent does not exist in FS25.
-- Combine.addCutterArea fires on every combine harvest pass with:
--   area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad
-- 'self' inside the appended function is the combine vehicle instance.
---@return boolean success True if hook installed successfully
function HookManager:installHarvestHook()
    if not Combine or type(Combine.addCutterArea) ~= "function" then
        SoilLogger.warning("Could not install harvest hook - Combine.addCutterArea not available")
        return false
    end

    local original = Combine.addCutterArea
    Combine.addCutterArea = Utils.appendedFunction(
        original,
        function(combineSelf, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)
            if not combineSelf.isServer then return end
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled or
               not g_SoilFertilityManager.settings.nutrientCycles then
                return
            end

            if not inputFruitType or inputFruitType <= 0 then return end
            if not liters or liters <= 0 then return end

            local success, errorMsg = pcall(function()
                local x, _, z = getWorldTranslation(combineSelf.rootNode)
                if not x then return end

                local fieldId = nil
                if g_fieldManager and type(g_fieldManager.getFieldAtWorldPosition) == "function" then
                    local field = g_fieldManager:getFieldAtWorldPosition(x, z)
                    if field and field.farmland then
                        fieldId = field.farmland.id
                    end
                end
                if not fieldId and g_farmlandManager then
                    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
                    if farmland then fieldId = farmland.id end
                end
                if not fieldId or fieldId <= 0 then return end

                SoilLogger.debug("Harvest hook: Field %d, Crop %d, %.0fL, strawRatio=%.2f", fieldId, inputFruitType, liters, strawRatio or 0)
                g_SoilFertilityManager.soilSystem:onHarvest(fieldId, inputFruitType, liters, strawRatio)
            end)

            if not success then
                SoilLogger.error("Harvest hook failed: %s", tostring(errorMsg))
            end
        end
    )
    self:register(Combine, "addCutterArea", original, "Combine.addCutterArea")
    SoilLogger.info("[OK] Harvest hook installed (Combine.addCutterArea)")
    return true
end

-- =========================================================
-- HOOK 2: All fertilizer application (Sprayer + Spreader)
-- =========================================================
--- Hooks Sprayer.onEndWorkAreaProcessing, which covers ALL fertilizer vehicles:
--- liquid sprayers, manure spreaders, dry fertilizer spreaders, slurry tankers, etc.
--- All of these use the Sprayer specialization in FS25 — there is no separate Spreader class.
--- onEndWorkAreaProcessing is called via dynamic event dispatch (SpecializationUtil.registerEventListener),
--- so replacing Sprayer.onEndWorkAreaProcessing works at any time, including post-load.
---@return boolean success True if hook installed successfully
function HookManager:installSprayerAreaHook()
    if not Sprayer or type(Sprayer.onEndWorkAreaProcessing) ~= "function" then
        SoilLogger.warning("Could not install sprayer area hook - Sprayer.onEndWorkAreaProcessing not available")
        return false
    end

    local original = Sprayer.onEndWorkAreaProcessing
    Sprayer.onEndWorkAreaProcessing = Utils.appendedFunction(
        original,
        function(self, dt, hasProcessed)
            -- Server only
            if not self.isServer then return end

            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled then
                return
            end

            local spec = self.spec_sprayer
            if not spec or not spec.workAreaParameters then return end

            -- Only fire when the sprayer was actually active this frame
            if not spec.workAreaParameters.isActive then return end

            local fillTypeIndex = spec.workAreaParameters.sprayFillType
            local liters = spec.workAreaParameters.usage

            if (not fillTypeIndex or fillTypeIndex <= 0) then return end
            if not liters or liters <= 0 then return end

            local success, errorMsg = pcall(function()
                local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                if not fillType then return end

                if not SoilConstants.FERTILIZER_PROFILES[fillType.name] then return end

                -- Resolve field from vehicle root position
                local x, _, z = getWorldTranslation(self.rootNode)
                if not x then return end

                local fieldId = nil
                if g_fieldManager and type(g_fieldManager.getFieldAtWorldPosition) == "function" then
                    local field = g_fieldManager:getFieldAtWorldPosition(x, z)
                    if field and field.farmland then
                        fieldId = field.farmland.id
                    end
                end
                if not fieldId and g_farmlandManager then
                    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
                    if farmland then fieldId = farmland.id end
                end
                if not fieldId or fieldId <= 0 then return end

                -- Apply rate multiplier
                local rm = g_SoilFertilityManager.sprayerRateManager
                local rateMultiplier = (rm ~= nil) and rm:getMultiplier(self.id) or 1.0
                local effectiveLiters = liters * rateMultiplier

                SoilLogger.debug("Sprayer/Spreader hook: Field %d, %s, %.1fL (x%.2f rate)",
                    fieldId, fillType.name, effectiveLiters, rateMultiplier)

                g_SoilFertilityManager.soilSystem:onFertilizerApplied(fieldId, fillTypeIndex, effectiveLiters)

                -- Over-application burn check (nutrient fertilizers only, not lime)
                local entry = SoilConstants.FERTILIZER_PROFILES[fillType.name]
                local isNutrientFertilizer = entry and (entry.N or entry.P or entry.K)
                if isNutrientFertilizer and rateMultiplier > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
                    g_SoilFertilityManager.soilSystem:applyBurnEffect(fieldId, rateMultiplier)
                end
            end)

            if not success then
                SoilLogger.error("Sprayer area hook failed: %s", tostring(errorMsg))
            end
        end
    )
    self:register(Sprayer, "onEndWorkAreaProcessing", original, "Sprayer.onEndWorkAreaProcessing")
    SoilLogger.info("[OK] Sprayer/Spreader hook installed (Sprayer.onEndWorkAreaProcessing)")
    return true
end

-- =========================================================
-- HOOK 3: Field ownership changes (MessageType.FARMLAND_OWNER_CHANGED)
-- =========================================================
-- g_farmlandManager.fieldOwnershipChanged does not exist in FS25.
-- The correct pattern is g_messageCenter:subscribe(MessageType.FARMLAND_OWNER_CHANGED, cb, target).
-- Callback receives: farmlandId, farmId, loadFromSavegame
-- loadFromSavegame=true fires for every field on game load; we skip those to avoid
-- resetting existing soil data on a fresh load.
---@return boolean success True if hook installed successfully
function HookManager:installOwnershipHook()
    if not g_messageCenter or not MessageType or not MessageType.FARMLAND_OWNER_CHANGED then
        SoilLogger.warning("Could not install ownership hook - g_messageCenter or MessageType.FARMLAND_OWNER_CHANGED not available")
        return false
    end

    local function onOwnerChanged(farmlandId, farmId, loadFromSavegame)
        if loadFromSavegame then return end  -- skip initial population on load
        if not g_SoilFertilityManager or
           not g_SoilFertilityManager.soilSystem or
           not g_SoilFertilityManager.settings.enabled then
            return
        end

        local success, errorMsg = pcall(function()
            -- farmlandId is used as the fieldId key (same value; FS25 uses farmland IDs throughout)
            g_SoilFertilityManager.soilSystem:onFieldOwnershipChanged(farmlandId, farmlandId, farmId)
        end)

        if not success then
            SoilLogger.error("Ownership hook failed: %s", tostring(errorMsg))
        end
    end

    g_messageCenter:subscribe(MessageType.FARMLAND_OWNER_CHANGED, onOwnerChanged, self)

    -- Register cleanup so uninstallAll() unsubscribes correctly
    self:registerCleanup("MessageType.FARMLAND_OWNER_CHANGED", function()
        g_messageCenter:unsubscribeAll(self)
    end)

    SoilLogger.info("[OK] Field ownership hook installed (MessageType.FARMLAND_OWNER_CHANGED)")
    return true
end

-- =========================================================
-- HOOK 4: Weather/environment updates
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installWeatherHook()
    if not g_currentMission or not g_currentMission.environment then
        SoilLogger.warning("Could not install weather hook - environment not available")
        return false
    end

    local env = g_currentMission.environment
    if not env.update then
        SoilLogger.warning("Could not install weather hook - environment.update not found")
        return false
    end

    local original = env.update
    env.update = Utils.appendedFunction(
        original,
        function(envSelf, dt, ...)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled or
               not g_SoilFertilityManager.settings.nutrientCycles then
                return
            end

            local success, errorMsg = pcall(function()
                g_SoilFertilityManager.soilSystem:onEnvironmentUpdate(envSelf, dt)
            end)

            if not success then
                SoilLogger.error("Weather hook failed: %s", tostring(errorMsg))
            end
        end
    )
    self:register(env, "update", original, "environment.update")
    SoilLogger.info("[OK] Weather hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 5: Plowing operations (Cultivator)
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installPlowingHook()
    if not Cultivator or type(Cultivator.processCultivatorArea) ~= "function" then
        SoilLogger.warning("Could not install plowing hook - Cultivator.processCultivatorArea not available or replaced")
        return false
    end

    local original = Cultivator.processCultivatorArea
    Cultivator.processCultivatorArea = Utils.appendedFunction(
        original,
        function(cultivatorSelf, superFunc, workArea, dt)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled or
               not g_SoilFertilityManager.settings.plowingBonus then
                return
            end

            -- Validate workArea parameter.
            -- workArea is a named-key table ({start=node, width=node, height=node}),
            -- not a sequence — #workArea always returns 0 and cannot be used as a guard.
            if not workArea or type(workArea) ~= "table" then return end
            if not workArea.start or not workArea.width or not workArea.height then return end

            -- Get field ID from work area
            local sx, _, sz = getWorldTranslation(workArea.start)
            local wx, _, wz = getWorldTranslation(workArea.width)
            local hx, _, hz = getWorldTranslation(workArea.height)
            
            local centerX = (sx + wx + hx) / 3
            local centerZ = (sz + wz + hz) / 3

            local success, errorMsg = pcall(function()
                if g_farmlandManager then
                    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(centerX, centerZ)
                    local farmlandId = farmland and farmland.id
                    if farmlandId and farmlandId > 0 then
                        -- Check if this is a plowing implement
                        local isPlowingTool = cultivatorSelf.spec_plow ~= nil or
                                              cultivatorSelf.spec_subsoiler ~= nil

                        -- Some cultivators work deep enough to act as plows
                        if not isPlowingTool and cultivatorSelf.spec_cultivator then
                            local cultivatorSpec = cultivatorSelf.spec_cultivator
                            if cultivatorSpec.workingDepth and 
                               cultivatorSpec.workingDepth > SoilConstants.PLOWING.MIN_DEPTH_FOR_PLOWING then
                                isPlowingTool = true
                            end
                        end

                        if isPlowingTool then
                            g_SoilFertilityManager.soilSystem:onPlowing(farmlandId)
                        end
                    end
                end
            end)

            if not success then
                SoilLogger.error("Plowing hook failed: %s", tostring(errorMsg))
            end
        end
    )
    self:register(Cultivator, "processCultivatorArea", original, "Cultivator.processCultivatorArea")
    SoilLogger.info("[OK] Plowing hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 6: Patch vehicle fill units to accept custom types
-- =========================================================
-- Vanilla spreaders/sprayers have fillUnit#fillTypes="FERTILIZER" or "LIQUIDFERTILIZER".
-- FS25 resolves these by NAME at parse time, yielding only the single vanilla type index.
-- Our fillTypes.xml extends those categories, but category extension only helps vehicles
-- that use fillTypeCategories="..." (category lookup), not fillTypes="..." (name lookup).
-- Therefore vanilla equipment never gets DAP/UREA/etc added to their supportedFillTypes.
--
-- Fix: hook FillUnit.onPostLoad to inject our custom fill type indices into any fill unit
-- that already accepts the corresponding vanilla base type (FERTILIZER or LIQUIDFERTILIZER).
-- This runs on every vehicle after its fill unit data is fully parsed, covering all
-- vanilla spreaders, sprayers, and any mod equipment using the standard category names.
--
-- Additionally, after the hook is installed, all vehicles already in memory are patched
-- retroactively. This covers the save/load scenario where FillUnit.onPostLoad fires during
-- Mission00.load — well before our deferred hook installation — leaving saved sprayers
-- unable to accept custom fill types until a new one is bought from the shop.
---@return boolean success
function HookManager:installFillUnitHook()
    if not FillUnit or type(FillUnit.onPostLoad) ~= "function" then
        SoilLogger.warning("Could not install FillUnit hook - FillUnit.onPostLoad not available")
        return false
    end

    -- Resolve fill type indices once at install time (used by hook closure + retroactive patch)
    local fm = g_fillTypeManager
    if not fm then
        SoilLogger.warning("FillUnit hook: g_fillTypeManager not available")
        return false
    end

    local fertIndex    = fm:getFillTypeIndexByName("FERTILIZER")
    local liqFertIndex = fm:getFillTypeIndexByName("LIQUIDFERTILIZER")
    if not fertIndex and not liqFertIndex then
        SoilLogger.warning("FillUnit hook: base fertilizer fill types not registered")
        return false
    end

    local solidNames  = {"UREA", "AMS", "MAP", "DAP", "POTASH"}
    local liquidNames = {"UAN32", "UAN28", "ANHYDROUS", "STARTER"}

    local solidIndices  = {}
    local liquidIndices = {}
    for _, name in ipairs(solidNames) do
        local idx = fm:getFillTypeIndexByName(name)
        if idx then table.insert(solidIndices, idx) end
    end
    for _, name in ipairs(liquidNames) do
        local idx = fm:getFillTypeIndexByName(name)
        if idx then table.insert(liquidIndices, idx) end
    end

    -- Shared helper: inject custom fill type indices into one vehicle's fill units
    local function patchVehicleFillUnits(vehicleSelf)
        local spec = vehicleSelf.spec_fillUnit
        if not spec or not spec.fillUnits then return end
        for _, fillUnit in pairs(spec.fillUnits) do
            if fillUnit.supportedFillTypes then
                local addSolid  = fertIndex    and fillUnit.supportedFillTypes[fertIndex]
                local addLiquid = liqFertIndex and fillUnit.supportedFillTypes[liqFertIndex]
                if addSolid then
                    for _, idx in ipairs(solidIndices) do
                        fillUnit.supportedFillTypes[idx] = true
                    end
                end
                if addLiquid then
                    for _, idx in ipairs(liquidIndices) do
                        fillUnit.supportedFillTypes[idx] = true
                    end
                end
            end
        end
    end

    local original = FillUnit.onPostLoad
    FillUnit.onPostLoad = Utils.appendedFunction(
        original,
        function(vehicleSelf, savegame)
            patchVehicleFillUnits(vehicleSelf)
        end
    )
    self:register(FillUnit, "onPostLoad", original, "FillUnit.onPostLoad")
    SoilLogger.info("[OK] FillUnit hook installed - custom types injected into compatible vehicles")

    -- Retroactively patch all vehicles already in memory.
    -- On save/load, FillUnit.onPostLoad fires during Mission00.load (before our deferred
    -- hook installation runs), so saved sprayers miss the injection entirely. Patching them
    -- here ensures they accept custom fill types without needing a shop purchase.
    -- NOTE: In FS25, vehicles are stored in g_currentMission.vehicleSystem.vehicles,
    --       not g_currentMission.vehicles (which does not exist).
    local vehicleSystem = g_currentMission and g_currentMission.vehicleSystem
    if vehicleSystem and vehicleSystem.vehicles then
        local patched = 0
        for _, vehicle in pairs(vehicleSystem.vehicles) do
            patchVehicleFillUnits(vehicle)
            patched = patched + 1
        end
        if patched > 0 then
            SoilLogger.info("Retroactively patched %d existing vehicles with custom fill types", patched)
        end
    end

    return true
end
