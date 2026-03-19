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
            if not g_currentMission:getIsServer() then return end
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
        print("[SoilFertilizer WARNING] Could not install sprayer area hook - Sprayer.onEndWorkAreaProcessing not available")
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

            if not fillTypeIndex or fillTypeIndex <= 0 then return end
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
                local rateMultiplier = 1.0

                if rm ~= nil then
                    if rm:getAutoMode(self.id) and g_SoilFertilityManager.settings.autoRateControl then
                        -- AUTO-RATE LOGIC: Calculate required multiplier to reach target
                        local soilSystem = g_SoilFertilityManager.soilSystem
                        local field = soilSystem:getFieldData(fieldId)
                        local profile = SoilConstants.FERTILIZER_PROFILES[fillType.name]

                        if field and profile then
                            -- Find the nutrient that needs the most "help" from this fertilizer
                            local maxRequiredMultiplier = 0.1 -- minimum
                            local targets = SoilConstants.AUTO_RATE_TARGETS
                            local baseRates = SoilConstants.SPRAYER_RATE.BASE_RATES
                            local baseRate = (baseRates[fillType.name] or baseRates.DEFAULT).value

                            -- Check N, P, K
                            for _, nutrient in ipairs({"N", "P", "K"}) do
                                local profVal = profile[nutrient]
                                if profVal and profVal > 0 then
                                    local key = (nutrient == "N" and "nitrogen") or (nutrient == "P" and "phosphorus") or "potassium"
                                    local current = field[key] or 0
                                    local target = targets[nutrient] or 80
                                    local gap = math.max(0, target - current)

                                    -- nutrient_per_ha_at_1x = (base_rate / 1000) * profVal
                                    local nutrientPerHaAt1x = (baseRate / 1000) * profVal
                                    if nutrientPerHaAt1x > 0 then
                                        local reqM = gap / nutrientPerHaAt1x
                                        maxRequiredMultiplier = math.max(maxRequiredMultiplier, reqM)
                                    end
                                end
                            end

                            -- Check pH (Lime/Gypsum)
                            if profile.pH and profile.pH > 0 then
                                local current = field.pH or 6.5
                                local target = targets.pH or 7.0
                                local gap = math.max(0, target - current)
                                local pHPerHaAt1x = (baseRate / 1000) * profile.pH
                                if pHPerHaAt1x > 0 then
                                    local reqM = gap / pHPerHaAt1x
                                    maxRequiredMultiplier = math.max(maxRequiredMultiplier, reqM)
                                end
                            end

                            -- Check OM (Manure/Gypsum/Slurry)
                            if profile.OM and profile.OM > 0 then
                                local current = field.organicMatter or 2.0
                                local target = targets.OM or 5.0
                                local gap = math.max(0, target - current)
                                local OMPerHaAt1x = (baseRate / 1000) * profile.OM
                                if OMPerHaAt1x > 0 then
                                    local reqM = gap / OMPerHaAt1x
                                    maxRequiredMultiplier = math.max(maxRequiredMultiplier, reqM)
                                end
                            end

                            -- Clamp to allowed steps
                            local steps = SoilConstants.SPRAYER_RATE.STEPS
                            rateMultiplier = math.max(steps[1], math.min(steps[#steps], maxRequiredMultiplier))
                        else
                            rateMultiplier = rm:getMultiplier(self.id)
                        end
                    else
                        -- MANUAL MODE
                        rateMultiplier = rm:getMultiplier(self.id)
                    end
                end

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
                print("[SoilFertilizer ERROR] Sprayer area hook failed: " .. tostring(errorMsg))
            end
        end
    )
    self:register(Sprayer, "onEndWorkAreaProcessing", original, "Sprayer.onEndWorkAreaProcessing")
    print("[SoilFertilizer] [OK] Sprayer/Spreader hook installed (Sprayer.onEndWorkAreaProcessing)")
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
            if not g_currentMission:getIsServer() then return end
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
            if not g_currentMission:getIsServer() then return end
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
            if not g_currentMission:getIsServer() then return end
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

