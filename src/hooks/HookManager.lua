-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Hook Manager (FIXED)
-- =========================================================
-- Manages installation and cleanup of game engine hooks
-- NOW INCLUDES: Spreader hook for solid fertilizer application
-- =========================================================
-- Author: TisonK (spreader fix by Claude & Samantha)
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
--- Installs hooks for harvest, fertilizer (sprayer), spreader, plowing, ownership, and weather
--- When Precision Farming is active, skips nutrient-modifying hooks for efficiency
--- Stores references for proper cleanup on uninstall
---@param soilSystem SoilFertilitySystem The soil system instance to connect hooks to
---@param pfActive boolean|nil If true, skips nutrient-modifying hooks (PF Viewer Mode)
function HookManager:installAll(soilSystem, pfActive)
    if self.installed then
        print("[SoilFertilizer] Hooks already installed, skipping re-installation")
        return
    end

    local successCount = 0
    local failCount = 0

    if pfActive then
        print("[SoilFertilizer] Viewer Mode (Precision Farming active) - installing minimal hooks...")
        -- Only install ownership hook for field cleanup - skip all nutrient-modifying hooks
        local success = self:installOwnershipHook()
        if success then successCount = successCount + 1 else failCount = failCount + 1 end
        print(string.format("[SoilFertilizer] Viewer Mode hooks: %d installed, %d failed", successCount, failCount))
    else
        print("[SoilFertilizer] Installing event hooks...")

        -- Harvest hook (FruitUtil)
        local harvestOk = self:installHarvestHook()
        if harvestOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Liquid fertilizer hook (Sprayer)
        local sprayerOk = self:installSprayerHook()
        if sprayerOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- SOLID FERTILIZER HOOK (Spreader) - NEW!
        local spreaderOk = self:installSpreaderHook()
        if spreaderOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Field ownership changes
        local ownershipOk = self:installOwnershipHook()
        if ownershipOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Weather/environment effects
        local weatherOk = self:installWeatherHook()
        if weatherOk then successCount = successCount + 1 else failCount = failCount + 1 end

        -- Plowing benefits
        local plowingOk = self:installPlowingHook()
        if plowingOk then successCount = successCount + 1 else failCount = failCount + 1 end

        print(string.format("[SoilFertilizer] Hook installation complete: %d/%d successful, %d failed",
            successCount, successCount + failCount, failCount))

        if failCount > 0 then
            print("[SoilFertilizer WARNING] Some hooks failed to install - mod functionality may be limited")
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
        if hook.target and hook.key and hook.original then
            hook.target[hook.key] = hook.original
            print(string.format("[SoilFertilizer] Restored original: %s", hook.name or hook.key))
        end
    end

    self.hooks = {}
    self.installed = false
    print("[SoilFertilizer] All hooks uninstalled")
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

-- =========================================================
-- HOOK 1: Harvest events (FruitUtil)
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installHarvestHook()
    if not FruitUtil or type(FruitUtil.fruitPickupEvent) ~= "function" then
        print("[SoilFertilizer WARNING] Could not install harvest hook - FruitUtil.fruitPickupEvent not available or replaced")
        return false
    end

    local original = FruitUtil.fruitPickupEvent
    FruitUtil.fruitPickupEvent = Utils.appendedFunction(
        original,
        function(fruitTypeIndex, x, z, fieldId, liters)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled or
               not g_SoilFertilityManager.settings.nutrientCycles or
               not fieldId or fieldId <= 0 then
                return
            end

            SoilLogger.debug("Harvest hook triggered: Field %d, Crop %d, %.0fL", fieldId, fruitTypeIndex, liters)

            local success, errorMsg = pcall(function()
                g_SoilFertilityManager.soilSystem:onHarvest(fieldId, fruitTypeIndex, liters)
            end)

            if not success then
                print("[SoilFertilizer ERROR] Harvest hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(FruitUtil, "fruitPickupEvent", original, "FruitUtil.fruitPickupEvent")
    print("[SoilFertilizer] [OK] Harvest hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 2: Liquid fertilizer application (Sprayer)
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installSprayerHook()
    if not Sprayer or type(Sprayer.spray) ~= "function" then
        print("[SoilFertilizer WARNING] Could not install sprayer hook - Sprayer.spray not available or replaced")
        return false
    end

    local original = Sprayer.spray
    Sprayer.spray = Utils.appendedFunction(
        original,
        function(sprayerSelf, fillTypeIndex, liters, fieldId, ...)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled or
               not fieldId or fieldId <= 0 or
               not liters or liters <= 0 then
                return
            end

            local success, errorMsg = pcall(function()
                local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                if not fillType then return end

                SoilLogger.debug("Sprayer hook triggered: Field %d, Fill type %s, %.0fL", 
                    fieldId, fillType.name or "unknown", liters)

                -- Check if this fill type is a recognized fertilizer
                if SoilConstants.FERTILIZER_PROFILES[fillType.name] then
                    -- Scale liters by the per-vehicle application rate
                    local rm = g_SoilFertilityManager.sprayerRateManager
                    local rateMultiplier = (rm ~= nil) and rm:getMultiplier(sprayerSelf.id) or 1.0
                    local effectiveLiters = liters * rateMultiplier

                    g_SoilFertilityManager.soilSystem:onFertilizerApplied(fieldId, fillTypeIndex, effectiveLiters)

                    -- Over-application burn check (only for nutrient fertilizers, not lime)
                    local entry = SoilConstants.FERTILIZER_PROFILES[fillType.name]
                    local isNutrientFertilizer = entry and (entry.N or entry.P or entry.K)
                    if isNutrientFertilizer and rateMultiplier > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
                        g_SoilFertilityManager.soilSystem:applyBurnEffect(fieldId, rateMultiplier)
                    end
                end
            end)

            if not success then
                print("[SoilFertilizer ERROR] Sprayer hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(Sprayer, "spray", original, "Sprayer.spray")
    print("[SoilFertilizer] [OK] Sprayer hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 3: SOLID FERTILIZER APPLICATION (Spreader) - NEW!
-- =========================================================
--- Handles manure spreaders, dry fertilizer spreaders, and other solid applicators
---@return boolean success True if hook installed successfully
function HookManager:installSpreaderHook()
    if not Spreader or type(Spreader.processSpreadArea) ~= "function" then
        print("[SoilFertilizer WARNING] Could not install spreader hook - Spreader.processSpreadArea not available")
        return false
    end

    local original = Spreader.processSpreadArea
    Spreader.processSpreadArea = Utils.appendedFunction(
        original,
        function(spreaderSelf, workArea, dt, fillTypeIndex, liters, ...)
            -- Early exits for disabled mod or missing dependencies
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled then
                return
            end

            -- Validate inputs
            if not workArea or type(workArea) ~= "table" then return end
            if not fillTypeIndex or fillTypeIndex <= 0 then return end
            if not liters or liters <= 0 then return end

            -- Get field ID from work area coordinates
            local sx, _, sz = getWorldTranslation(workArea.start)
            local wx, _, wz = getWorldTranslation(workArea.width)
            local hx, _, hz = getWorldTranslation(workArea.height)
            
            local fieldId = self:getFieldIdFromArea(sx, sz, wx, wz, hx, hz)
            if not fieldId or fieldId <= 0 then return end

            local success, errorMsg = pcall(function()
                local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                if not fillType then return end

                SoilLogger.debug("Spreader hook triggered: Field %d, Fill type %s, %.0fL", 
                    fieldId, fillType.name or "unknown", liters)

                -- Check if this fill type is a recognized fertilizer
                -- Supports: MANURE, PELLETIZED_MANURE, FERTILIZER, LIME, etc.
                if SoilConstants.FERTILIZER_PROFILES[fillType.name] then
                    -- Apply rate multiplier if spreader supports variable rates
                    -- (Some spreaders have the same rate control system as sprayers)
                    local rateMultiplier = 1.0
                    if g_SoilFertilityManager.sprayerRateManager then
                        rateMultiplier = g_SoilFertilityManager.sprayerRateManager:getMultiplier(spreaderSelf.id)
                    end
                    
                    local effectiveLiters = liters * rateMultiplier
                    g_SoilFertilityManager.soilSystem:onFertilizerApplied(fieldId, fillTypeIndex, effectiveLiters)

                    -- Burn check for over-application (if applicable to solid fertilizers)
                    local entry = SoilConstants.FERTILIZER_PROFILES[fillType.name]
                    local isNutrientFertilizer = entry and (entry.N or entry.P or entry.K)
                    if isNutrientFertilizer and rateMultiplier > SoilConstants.SPRAYER_RATE.BURN_RISK_THRESHOLD then
                        g_SoilFertilityManager.soilSystem:applyBurnEffect(fieldId, rateMultiplier)
                    end
                else
                    SoilLogger.debug("Spreader applied non-fertilizer fill type: %s", fillType.name or "unknown")
                end
            end)

            if not success then
                print("[SoilFertilizer ERROR] Spreader hook failed: " .. tostring(errorMsg))
            end
        end
    )
    
    self:register(Spreader, "processSpreadArea", original, "Spreader.processSpreadArea")
    print("[SoilFertilizer] [OK] Spreader hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 4: Field ownership changes
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installOwnershipHook()
    if not g_farmlandManager or not g_farmlandManager.fieldOwnershipChanged then
        print("[SoilFertilizer WARNING] Could not install ownership hook - farmlandManager not available")
        return false
    end

    local original = g_farmlandManager.fieldOwnershipChanged
    g_farmlandManager.fieldOwnershipChanged = Utils.appendedFunction(
        original,
        function(fieldId, farmlandId, farmId)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled then
                return
            end

            local success, errorMsg = pcall(function()
                g_SoilFertilityManager.soilSystem:onFieldOwnershipChanged(fieldId, farmlandId, farmId)
            end)

            if not success then
                print("[SoilFertilizer ERROR] Ownership hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(g_farmlandManager, "fieldOwnershipChanged", original, "farmlandManager.fieldOwnershipChanged")
    print("[SoilFertilizer] [OK] Field ownership hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 5: Weather/environment updates
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installWeatherHook()
    if not g_currentMission or not g_currentMission.environment then
        print("[SoilFertilizer WARNING] Could not install weather hook - environment not available")
        return false
    end

    local env = g_currentMission.environment
    if not env.update then
        print("[SoilFertilizer WARNING] Could not install weather hook - environment.update not found")
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
                print("[SoilFertilizer ERROR] Weather hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(env, "update", original, "environment.update")
    print("[SoilFertilizer] [OK] Weather hook installed successfully")
    return true
end

-- =========================================================
-- HOOK 6: Plowing operations (Cultivator)
-- =========================================================
---@return boolean success True if hook installed successfully
function HookManager:installPlowingHook()
    if not Cultivator or type(Cultivator.processCultivatorArea) ~= "function" then
        print("[SoilFertilizer WARNING] Could not install plowing hook - Cultivator.processCultivatorArea not available or replaced")
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

            -- Validate workArea parameter
            if not workArea or type(workArea) ~= "table" or #workArea < 5 then
                return
            end

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
                print("[SoilFertilizer ERROR] Plowing hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(Cultivator, "processCultivatorArea", original, "Cultivator.processCultivatorArea")
    print("[SoilFertilizer] [OK] Plowing hook installed successfully")
    return true
end

-- =========================================================
-- DEBUG: Console command to test spreader detection
-- =========================================================
--- Call this from console to verify spreaders are being hooked
function HookManager:debugListSpreaders()
    print("[SoilFertilizer] === Spreader Debug Info ===")
    if g_currentMission and g_currentMission.vehicles then
        local spreaderCount = 0
        for _, vehicle in pairs(g_currentMission.vehicles) do
            if vehicle.spec_spreader then
                spreaderCount = spreaderCount + 1
                local fillTypeInfo = "unknown"
                if vehicle.spec_spreader.fillUnitIndex then
                    local fillType = vehicle:getFillUnitFillType(vehicle.spec_spreader.fillUnitIndex)
                    if fillType then
                        local fillTypeObj = g_fillTypeManager:getFillTypeByIndex(fillType)
                        fillTypeInfo = fillTypeObj and fillTypeObj.name or tostring(fillType)
                    end
                end
                print(string.format("  Spreader %d: %s", spreaderCount, vehicle.configFileName))
                print(string.format("    - Fill Type: %s", fillTypeInfo))
                print(string.format("    - Vehicle ID: %s", tostring(vehicle.id)))
            end
        end
        print(string.format("Total spreaders found: %d", spreaderCount))
    else
        print("  No vehicles or mission not available")
    end
    print("=== End Spreader Debug ===")
end