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

--- Install all game hooks for the soil system
--- Installs hooks for harvest, fertilizer, plowing, ownership, and weather
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

        local harvestOk = self:installHarvestHook()
        if harvestOk then successCount = successCount + 1 else failCount = failCount + 1 end

        local sprayerOk = self:installSprayerHook()
        if sprayerOk then successCount = successCount + 1 else failCount = failCount + 1 end

        local spreaderOk = self:installSpreaderHook()
        if spreaderOk then successCount = successCount + 1 else failCount = failCount + 1 end

        local ownershipOk = self:installOwnershipHook()
        if ownershipOk then successCount = successCount + 1 else failCount = failCount + 1 end

        local weatherOk = self:installWeatherHook()
        if weatherOk then successCount = successCount + 1 else failCount = failCount + 1 end

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

-- Hook 1: Harvest events (FruitUtil)
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

-- Hook 2: Fertilizer application (Sprayer) - converted from direct replacement to appended
---@return boolean success True if hook installed successfully
function HookManager:installSprayerHook()
    if not Sprayer or type(Sprayer.spray) ~= "function" then
        print("[SoilFertilizer WARNING] Could not install fertilizer hook - Sprayer.spray not available or replaced")
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

                SoilLogger.debug("Fertilizer hook triggered: Field %d, Fill type %s", fieldId, fillType.name or "unknown")

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
                print("[SoilFertilizer ERROR] Fertilizer hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(Sprayer, "spray", original, "Sprayer.spray")
    print("[SoilFertilizer] [OK] Fertilizer hook installed successfully")
    return true
end

-- Hook 3: Solid fertilizer spreaders (ManureSpreader / SpreadActivatable)
-- Sprayer.spray receives fieldId=0 for solid spreaders because their area-based discharge
-- system does not resolve a field before calling spray(). This hook intercepts
-- Sprayer.processSprayerArea, which IS called per-frame with a valid workArea, so we
-- can resolve the farmland from world coordinates — exactly like the plowing hook does.
-- We accumulate liters per field within each game update tick to avoid calling
-- onFertilizerApplied dozens of times per second for the same field.
---@return boolean success True if hook installed successfully
function HookManager:installSpreaderHook()
    if not Sprayer or type(Sprayer.processSprayerArea) ~= "function" then
        print("[SoilFertilizer WARNING] Could not install spreader hook - Sprayer.processSprayerArea not available")
        return false
    end

    -- Accumulator: [farmlandId] = { fillTypeIndex, liters }
    -- Flushed once per game update tick via a lightweight frame-coalescing pattern.
    local pendingApplication = {}
    local flushScheduled = false

    local function flushPending()
        flushScheduled = false
        for farmlandId, entry in pairs(pendingApplication) do
            local success, errorMsg = pcall(function()
                g_SoilFertilityManager.soilSystem:onFertilizerApplied(farmlandId, entry.fillTypeIndex, entry.liters)
            end)
            if not success then
                print("[SoilFertilizer ERROR] Spreader flush failed for field " .. tostring(farmlandId) .. ": " .. tostring(errorMsg))
            end
        end
        pendingApplication = {}
    end

    local original = Sprayer.processSprayerArea
    Sprayer.processSprayerArea = Utils.appendedFunction(
        original,
        function(sprayerSelf, workArea, dt)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled then
                return
            end

            -- Only intercept solid-material spreaders (spec_manureSpreader or spec_solidFertilizer).
            -- Liquid sprayers are already handled by installSprayerHook via Sprayer.spray.
            local isSolidSpreader = sprayerSelf.spec_manureSpreader ~= nil
                                 or sprayerSelf.spec_solidFertilizer ~= nil
                                 or (sprayerSelf.spec_sprayer ~= nil
                                     and sprayerSelf.spec_sprayer.sprayType == SprayType.SPREAD)
            if not isSolidSpreader then return end

            -- Validate workArea coords (same guard as plowing hook)
            if not workArea or type(workArea) ~= "table" or #workArea < 5 then return end

            local success, errorMsg = pcall(function()
                -- Resolve farmland from the centre of the work area
                local x = (workArea[1] + workArea[4]) / 2
                local z = (workArea[2] + workArea[5]) / 2

                if not g_farmlandManager then return end
                local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
                local farmlandId = farmland and farmland.id
                if not farmlandId or farmlandId <= 0 then return end

                -- Identify which fill type is currently being discharged
                local sprayerSpec = sprayerSelf.spec_sprayer
                if not sprayerSpec then return end

                local fillUnitIndex = sprayerSpec.fillUnitIndex or 1
                local fillTypeIndex = sprayerSelf:getFillUnitFillType(fillUnitIndex)
                if not fillTypeIndex or fillTypeIndex == FillType.UNKNOWN then return end

                local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                if not fillType then return end

                -- Only handle fill types we recognise as fertilizers
                if not SoilConstants.FERTILIZER_PROFILES[fillType.name] then return end

                -- Estimate liters applied this frame: discharge rate × dt
                -- sprayerSpec.sprayAmountScale carries the per-nozzle volume coefficient;
                -- multiply by dt (ms→s) for a per-frame litre estimate.
                local sprayAmount = (sprayerSpec.sprayAmountScale or 1.0) * (dt * 0.001)
                local rm = g_SoilFertilityManager.sprayerRateManager
                local rateMultiplier = (rm ~= nil) and rm:getMultiplier(sprayerSelf.id) or 1.0
                local effectiveLiters = sprayAmount * rateMultiplier

                -- Accumulate into pending batch (coalesce multiple workArea callbacks per tick)
                if pendingApplication[farmlandId] then
                    pendingApplication[farmlandId].liters = pendingApplication[farmlandId].liters + effectiveLiters
                else
                    pendingApplication[farmlandId] = { fillTypeIndex = fillTypeIndex, liters = effectiveLiters }
                end

                -- Schedule a single flush at the end of this update cycle
                if not flushScheduled then
                    flushScheduled = true
                    -- Utils.appendedFunction guarantees we run after original; schedule
                    -- flush for next idle step via a one-shot updater.
                    if g_currentMission and g_currentMission.addUpdateable then
                        g_currentMission:addUpdateable({
                            update = function(self2, _dt2)
                                flushPending()
                                return true  -- remove after one call
                            end
                        })
                    else
                        -- Fallback: flush immediately (slightly less coalesced but still correct)
                        flushPending()
                    end
                end

                SoilLogger.debug("Spreader work area: field %d, fillType %s, ~%.3fL this frame",
                    farmlandId, fillType.name, effectiveLiters)
            end)

            if not success then
                print("[SoilFertilizer ERROR] Spreader hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(Sprayer, "processSprayerArea", original, "Sprayer.processSprayerArea")
    print("[SoilFertilizer] [OK] Spreader hook installed successfully")
    return true
end

-- Hook 4: Field ownership changes (farmlandManager)
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

-- Hook 5: Weather/environment updates - converted from direct replacement to appended
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

-- Hook 6: Plowing operations (Cultivator)
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

            -- Check if this is actual plowing (not just cultivation)
            local workAreaSpec = cultivatorSelf.spec_workArea
            if not workAreaSpec then return end

            -- Validate workArea parameter
            if not workArea or type(workArea) ~= "table" or #workArea < 5 then
                return
            end

            local success, errorMsg = pcall(function()
                -- Get field ID from work area
                local x = (workArea[1] + workArea[4]) / 2
                local z = (workArea[2] + workArea[5]) / 2

                if g_farmlandManager then
                    -- getFarmlandAtWorldPosition returns a farmland object; .id is the field identifier.
                    -- getFarmlandIdAtWorldPosition and getFieldByFarmland do NOT exist in FS25.
                    local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
                    local farmlandId = farmland and farmland.id
                    if farmlandId and farmlandId > 0 then
                        -- Check if this is a plowing implement (various types trigger soil benefits)
                        -- spec_plow: Traditional plows, moldboard plows
                        -- spec_subsoiler: Deep loosening tools (improve OM mixing)
                        -- spec_cultivator with deep work: Some cultivators act as plows
                        local isPlowingTool = cultivatorSelf.spec_plow ~= nil or
                                              cultivatorSelf.spec_subsoiler ~= nil

                        -- Some cultivators work deep enough to act as plows
                        if not isPlowingTool and cultivatorSelf.spec_cultivator then
                            local cultivatorSpec = cultivatorSelf.spec_cultivator
                            -- Check if working depth is significant (deep plowing threshold)
                            if cultivatorSpec.workingDepth and cultivatorSpec.workingDepth > SoilConstants.PLOWING.MIN_DEPTH_FOR_PLOWING then
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