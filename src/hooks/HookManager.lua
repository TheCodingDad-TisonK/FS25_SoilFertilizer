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
    if not FruitUtil or not FruitUtil.fruitPickupEvent then
        print("[SoilFertilizer WARNING] Could not install harvest hook - FruitUtil not available")
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

            local success, errorMsg = pcall(function()
                g_SoilFertilityManager.soilSystem:onHarvest(fieldId, fruitTypeIndex, liters)
            end)

            if not success then
                print("[SoilFertilizer ERROR] Harvest hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(FruitUtil, "fruitPickupEvent", original, "FruitUtil.fruitPickupEvent")
    print("[SoilFertilizer] ✓ Harvest hook installed successfully")
    return true
end

-- Hook 2: Fertilizer application (Sprayer) - converted from direct replacement to appended
---@return boolean success True if hook installed successfully
function HookManager:installSprayerHook()
    if not Sprayer or not Sprayer.spray then
        print("[SoilFertilizer WARNING] Could not install fertilizer hook - Sprayer not available")
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

                -- Check if this fill type is a recognized fertilizer
                if SoilConstants.FERTILIZER_PROFILES[fillType.name] then
                    g_SoilFertilityManager.soilSystem:onFertilizerApplied(fieldId, fillTypeIndex, liters)
                end
            end)

            if not success then
                print("[SoilFertilizer ERROR] Fertilizer hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(Sprayer, "spray", original, "Sprayer.spray")
    print("[SoilFertilizer] ✓ Fertilizer hook installed successfully")
    return true
end

-- Hook 3: Field ownership changes
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
    print("[SoilFertilizer] ✓ Field ownership hook installed successfully")
    return true
end

-- Hook 4: Weather/environment updates - converted from direct replacement to appended
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
    print("[SoilFertilizer] ✓ Weather hook installed successfully")
    return true
end

-- Hook 5: Plowing operations (Cultivator)
---@return boolean success True if hook installed successfully
function HookManager:installPlowingHook()
    if not Cultivator or not Cultivator.processCultivatorArea then
        print("[SoilFertilizer WARNING] Could not install plowing hook - Cultivator not available")
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

            local success, errorMsg = pcall(function()
                -- Get field ID from work area
                local x = (workArea[1] + workArea[4]) / 2
                local z = (workArea[2] + workArea[5]) / 2

                if g_farmlandManager then
                    local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
                    if farmlandId and farmlandId > 0 and g_fieldManager then
                        local field = g_fieldManager:getFieldByFarmland(farmlandId)
                        if field and field.fieldId then
                            -- Check if this is a plowing implement (various types trigger soil benefits)
                            -- spec_plow: Traditional plows, moldboard plows
                            -- spec_subsoiler: Deep loosening tools (improve OM mixing)
                            -- spec_cultivator with deep work: Some cultivators act as plows
                            local isPlowingTool = cultivatorSelf.spec_plow ~= nil or
                                                  cultivatorSelf.spec_subsoiler ~= nil

                            -- Some cultivators work deep enough to act as plows
                            if not isPlowingTool and cultivatorSelf.spec_cultivator then
                                local cultivatorSpec = cultivatorSelf.spec_cultivator
                                -- Check if working depth is significant (>15cm = plowing depth)
                                if cultivatorSpec.workingDepth and cultivatorSpec.workingDepth > 0.15 then
                                    isPlowingTool = true
                                end
                            end

                            if isPlowingTool then
                                g_SoilFertilityManager.soilSystem:onPlowing(field.fieldId)
                            end
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
    print("[SoilFertilizer] ✓ Plowing hook installed successfully")
    return true
end
