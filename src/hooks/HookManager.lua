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
function HookManager:installAll(soilSystem)
    if self.installed then
        SoilLogger.warning("Hooks already installed, skipping re-installation")
        return
    end

    local successCount = 0
    local failCount = 0

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

    -- Sowing / planting: clear stale lastCrop so HUD shows live crop (fix #123)
    local sowingOk = self:installSowingHook()
    if sowingOk then successCount = successCount + 1 else failCount = failCount + 1 end

    -- Patch vanilla fill units to accept custom fertilizer types
    local fillUnitOk = self:installFillUnitHook()
    if fillUnitOk then successCount = successCount + 1 else failCount = failCount + 1 end

    SoilLogger.info("Hook installation complete: %d/%d successful, %d failed",
        successCount, successCount + failCount, failCount)

    if failCount > 0 then
        SoilLogger.warning("Some hooks failed to install - mod functionality may be limited")
    end

    -- Register custom fill types in SprayTypeManager so they get correct tank
    -- drain rates and visual spray effects. Must run after hooks (g_sprayTypeManager
    -- is populated from map XML before loadMission00Finished fires).
    self:registerCustomSprayTypes()

    -- Remap custom fill types to vanilla visual equivalents for all effect classes
    -- (FertilizerMotionPathEffect, ShaderPlaneEffect, etc.). Two-layer approach:
    -- primary hook on g_effectManager:setEffectTypeInfo intercepts before storage;
    -- backup hook on g_motionPathEffectManager:getSharedMotionPathEffect catches any
    -- indices that bypass setEffectTypeInfo. Must run in both full and viewer-mode paths.
    self:installEffectTypeHook()

    -- Inject custom fill type names into each vehicle's sprayType.fillTypes arrays so
    -- that Sprayer:getIsSprayTypeActive returns true for our custom types, triggering
    -- the correct sprayType.effects visual. Also hooks Sprayer.onLoad so newly bought
    -- or spawned vehicles receive the same injection.
    self:installSprayTypeEffectsHook()

    -- Force-refresh sprayer/spreader effects on all vehicles already in memory.
    -- Must run AFTER installSprayTypeEffectsHook so the fill type arrays are patched
    -- before updateSprayerEffects re-evaluates getActiveSprayType.
    self:refreshAllSprayerEffects()

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

-- =========================================================
-- SPRAY TYPE REGISTRATION: custom fill types
-- =========================================================
-- FS25 determines tank drain rate and visual spray effects (terrain overlay,
-- nozzle particles) from g_sprayTypeManager entries. Base-game types
-- (FERTILIZER, LIQUIDFERTILIZER, MANURE, LIME, etc.) are registered by the
-- map XML. Our custom types are NOT in any map XML, so FS25 falls back to
-- litersPerSecond=1 — ~300-400x higher than vanilla. This empties tanks
-- instantly and suppresses all spray visuals (FSDensityMapUtil.updateSprayArea
-- is a no-op with a nil spray type).
--
-- Fix: inherit litersPerSecond and sprayGroundType from the closest vanilla
-- equivalent, then call g_sprayTypeManager:addSprayType() for each custom type.
---@return nil
function HookManager:registerCustomSprayTypes()
    if not g_sprayTypeManager then
        SoilLogger.warning("registerCustomSprayTypes: g_sprayTypeManager not available - skipping")
        return
    end
    if not g_fillTypeManager then
        SoilLogger.warning("registerCustomSprayTypes: g_fillTypeManager not available - skipping")
        return
    end

    -- Borrow litersPerSecond and sprayGroundType from the vanilla base types.
    local liqType = g_sprayTypeManager:getSprayTypeByName("LIQUIDFERTILIZER")
    local dryType = g_sprayTypeManager:getSprayTypeByName("FERTILIZER")

    if not liqType and not dryType then
        SoilLogger.warning("registerCustomSprayTypes: vanilla spray types not found - skipping")
        return
    end

    local liquidLPS         = liqType and liqType.litersPerSecond or 0
    local liquidGroundType  = liqType and liqType.sprayGroundType or 1
    local solidLPS          = dryType and dryType.litersPerSecond or 0
    local solidGroundType   = dryType and dryType.sprayGroundType or 1

    -- Liquid nitrogen / starter types → inherit from LIQUIDFERTILIZER
    local liquidNames = { "UAN32", "UAN28", "ANHYDROUS", "STARTER", "LIQUIDLIME", "INSECTICIDE", "FUNGICIDE" }
    -- Granular/solid types → inherit from FERTILIZER
    local solidNames  = { "UREA", "AMS", "MAP", "DAP", "POTASH",
                          "COMPOST", "BIOSOLIDS", "CHICKEN_MANURE", "PELLETIZED_MANURE", "GYPSUM" }

    local registered = 0
    local skipped    = 0

    for _, name in ipairs(liquidNames) do
        if g_fillTypeManager:getFillTypeByName(name) then
            -- addSprayType is idempotent: if already registered it updates the entry
            g_sprayTypeManager:addSprayType(name, liquidLPS, "FERTILIZER", liquidGroundType, false)
            registered = registered + 1
        else
            skipped = skipped + 1
        end
    end

    for _, name in ipairs(solidNames) do
        if g_fillTypeManager:getFillTypeByName(name) then
            g_sprayTypeManager:addSprayType(name, solidLPS, "FERTILIZER", solidGroundType, false)
            registered = registered + 1
        else
            skipped = skipped + 1
        end
    end

    SoilLogger.info(
        "[OK] Custom spray types registered: %d types (liquid LPS=%.5f, solid LPS=%.5f, %d skipped/unavailable)",
        registered, liquidLPS, solidLPS, skipped
    )
end

-- =========================================================
-- EFFECT TYPE REMAP: custom fill types → vanilla visuals
-- =========================================================
-- FS25 effect classes (FertilizerMotionPathEffect, ShaderPlaneEffect, etc.)
-- only have visual configurations for vanilla fill types that were present
-- when the vehicle or map XML was authored. Custom fill types (UREA, UAN32,
-- ANHYDROUS, etc.) have no such configuration, so the game logs "Could not
-- find motion path effect for settings" and shows no visual at all.
--
-- Root cause for sprayers: g_effectManager:setEffectTypeInfo stores the
-- custom fill type index on each effect object. Downstream lookups
-- (getSharedMotionPathEffect, shader parameter tables, etc.) find no entry
-- for the custom type and fail silently — effects never start.
--
-- Fix (two-layer):
--   PRIMARY: Wrap g_effectManager:setEffectTypeInfo to substitute custom
--   fill type indices with their vanilla visual equivalents before the index
--   is stored on any effect object. Every downstream system then sees only
--   vanilla types and works normally. Purely cosmetic — nutrient tracking
--   uses the real fill type index from the sprayer hook, not the effect.
--
--   BACKUP: Wrap g_motionPathEffectManager:getSharedMotionPathEffect so
--   that if a custom index somehow reaches it (e.g. set through a code path
--   that bypasses setEffectTypeInfo), we remap and retry before returning nil.
---@return boolean success
function HookManager:installEffectTypeHook()
    if not g_fillTypeManager then
        SoilLogger.warning("Effect type hook: g_fillTypeManager not available - skipping")
        return false
    end

    local fm = g_fillTypeManager
    local fertIdx = fm:getFillTypeIndexByName("FERTILIZER")
    local liqIdx  = fm:getFillTypeIndexByName("LIQUIDFERTILIZER")

    -- Build remap: customFillTypeIndex → vanillaFillTypeIndex
    local remap = {}
    if fertIdx then
        for _, name in ipairs({ "UREA", "AMS", "MAP", "DAP", "POTASH",
                                 "COMPOST", "BIOSOLIDS", "CHICKEN_MANURE", "PELLETIZED_MANURE", "GYPSUM" }) do
            local idx = fm:getFillTypeIndexByName(name)
            if idx then remap[idx] = fertIdx end
        end
    end
    if liqIdx then
        for _, name in ipairs({ "UAN32", "UAN28", "ANHYDROUS", "STARTER", "LIQUIDLIME" }) do
            local idx = fm:getFillTypeIndexByName(name)
            if idx then remap[idx] = liqIdx end
        end
    end

    if not next(remap) then
        SoilLogger.warning("Effect type hook: no custom fill types found — skipping")
        return false
    end

    local count = 0
    for _ in pairs(remap) do count = count + 1 end

    -- PRIMARY: hook g_effectManager:setEffectTypeInfo
    -- This fires before the fill type index is stored on the effect object,
    -- so all downstream lookups (FertilizerMotionPathEffect shared effect,
    -- ShaderPlaneEffect shader tables, etc.) only ever see vanilla types.
    if g_effectManager and type(g_effectManager.setEffectTypeInfo) == "function" then
        local origSetTypeInfo = g_effectManager.setEffectTypeInfo
        g_effectManager.setEffectTypeInfo = function(mgr, effects, fillType, ...)
            local mapped = (fillType ~= nil and remap[fillType]) or fillType
            return origSetTypeInfo(mgr, effects, mapped, ...)
        end
        self:registerCleanup("g_effectManager.setEffectTypeInfo", function()
            g_effectManager.setEffectTypeInfo = origSetTypeInfo
        end)
        SoilLogger.info("[OK] Effect type hook installed on g_effectManager.setEffectTypeInfo - %d custom fill types remapped", count)
    else
        SoilLogger.warning("Effect type hook: g_effectManager.setEffectTypeInfo not available - sprayer visuals may not show")
    end

    -- BACKUP: hook g_motionPathEffectManager:getSharedMotionPathEffect
    -- Handles any custom fill type index that bypasses setEffectTypeInfo and
    -- reaches the motion path lookup directly (e.g. via direct field writes).
    if g_motionPathEffectManager and
       type(g_motionPathEffectManager.getSharedMotionPathEffect) == "function" then
        local FILL_TYPE_FIELDS = { "fillTypeIndex", "fillType", "sprayTypeIndex", "currentFillType" }
        local origGetShared = g_motionPathEffectManager.getSharedMotionPathEffect
        g_motionPathEffectManager.getSharedMotionPathEffect = function(mgr, effectObj)
            local result = origGetShared(mgr, effectObj)
            if result ~= nil then return result end

            local fieldName, customIdx
            for _, fname in ipairs(FILL_TYPE_FIELDS) do
                local val = effectObj[fname]
                if val ~= nil and remap[val] then
                    fieldName = fname
                    customIdx = val
                    break
                end
            end
            if fieldName == nil then return nil end

            local vanillaIdx = remap[customIdx]
            effectObj[fieldName] = vanillaIdx
            result = origGetShared(mgr, effectObj)
            effectObj[fieldName] = customIdx
            return result
        end
        self:registerCleanup("g_motionPathEffectManager.getSharedMotionPathEffect", function()
            g_motionPathEffectManager.getSharedMotionPathEffect = origGetShared
        end)
        SoilLogger.info("[OK] Effect type hook backup installed on g_motionPathEffectManager - %d custom fill types remapped", count)
    end

    -- RUNTIME CONSTANT REMAP: wrap Sprayer.onEndWorkAreaProcessing
    -- Pattern from THPFConfigurator: temporarily swap FillType and SprayType globals
    -- so that FillType.LIQUIDFERTILIZER == our custom fill type index for the duration
    -- of the call. Every vanilla runtime check inside (getIsSprayTypeActive,
    -- if fillType == FillType.LIQUIDFERTILIZER, etc.) transparently passes for our types.
    -- Restore originals immediately after. No persistent global state change.
    --
    -- Build inverseRemap: customFillTypeIndex → vanilla constant name (e.g. "LIQUIDFERTILIZER")
    local inverseRemap = {}
    for customIdx, vanillaIdx in pairs(remap) do
        local vanillaFT = fm:getFillTypeByIndex(vanillaIdx)
        if vanillaFT and vanillaFT.name then
            inverseRemap[customIdx] = vanillaFT.name
        end
    end

    local globalEnv = getfenv(0)

    if Sprayer and type(Sprayer.onEndWorkAreaProcessing) == "function" then
        local origOnEnd = Sprayer.onEndWorkAreaProcessing
        Sprayer.onEndWorkAreaProcessing = function(self, ...)
            local spec    = self.spec_sprayer
            local wap     = spec and spec.workAreaParameters
            local sprayFT = wap and wap.sprayFillType
            local vName   = sprayFT and inverseRemap[sprayFT]

            if not vName then
                return origOnEnd(self, ...)
            end

            -- Swap FillType global: FillType.LIQUIDFERTILIZER → our custom index
            local origFT = globalEnv.FillType
            local newFT  = {}
            for k, v in pairs(origFT) do newFT[k] = v end
            newFT[vName] = sprayFT
            globalEnv.FillType = newFT

            -- Swap SprayType global: SprayType.LIQUIDFERTILIZER → our custom spray type index
            local origST    = globalEnv.SprayType
            local customSTD = g_sprayTypeManager and g_sprayTypeManager:getSprayTypeByFillTypeIndex(sprayFT)
            if customSTD then
                local newST = {}
                for k, v in pairs(origST) do newST[k] = v end
                newST[vName] = customSTD.index
                globalEnv.SprayType = newST
            end

            origOnEnd(self, ...)

            globalEnv.FillType = origFT
            if customSTD then globalEnv.SprayType = origST end
        end
        self:registerCleanup("Sprayer.onEndWorkAreaProcessing (constant remap)", function()
            Sprayer.onEndWorkAreaProcessing = origOnEnd
        end)
        SoilLogger.info("[OK] Sprayer.onEndWorkAreaProcessing wrapped with runtime constant remap")
    end

    return true
end

-- =========================================================
-- SPRAY TYPE EFFECTS INJECTION: custom fill types → sprayType.fillTypes
-- =========================================================
-- Sprayer:getIsSprayTypeActive(sprayType) checks whether the vehicle's current
-- fill type matches any name in sprayType.fillTypes (the list from the vehicle XML,
-- e.g. {"FERTILIZER"} or {"LIQUIDFERTILIZER"}). Only when it matches does FS25 call
-- g_effectManager:setEffectTypeInfo(sprayType.effects, fillType) and startEffects —
-- giving the spreading/spraying visual for that sprayType slot.
--
-- Because no vanilla or mod vehicle XML lists our custom fill type names (UREA, UAN32,
-- etc.), getIsSprayTypeActive always returns false for them → getActiveSprayType()
-- returns nil → sprayType.effects never starts → NO visual, even though the base
-- spec.effects fallback is usually empty on modern FS25 vehicles.
--
-- Fix (two-part):
--   1. Retroactively patch every loaded vehicle: for each sprayType entry whose
--      fillTypes list contains "FERTILIZER", also add our solid custom names;
--      likewise for "LIQUIDFERTILIZER" and our liquid names.
--   2. Hook Sprayer.onLoad (fires when any vehicle is loaded) to apply the same
--      injection to newly bought/spawned vehicles going forward.
---@return boolean success
function HookManager:installSprayTypeEffectsHook()
    -- Solid custom types visually match FERTILIZER spreading
    local solidNames  = { "UREA", "AMS", "MAP", "DAP", "POTASH",
                          "COMPOST", "BIOSOLIDS", "CHICKEN_MANURE", "PELLETIZED_MANURE", "GYPSUM" }
    -- Liquid custom types visually match LIQUIDFERTILIZER spraying
    local liquidNames = { "UAN32", "UAN28", "ANHYDROUS", "STARTER", "LIQUIDLIME" }

    -- Shared helper: walk a vehicle's sprayType entries and inject our names
    local function patchVehicleSprayTypes(vehicle)
        local spec = vehicle.spec_sprayer
        if not spec or not spec.sprayTypes then return end

        for _, st in ipairs(spec.sprayTypes) do
            if st.fillTypes then
                local hasFert    = false
                local hasLiqFert = false

                -- Check what vanilla base types this sprayType slot already covers
                for _, name in ipairs(st.fillTypes) do
                    local upper = string.upper(name)
                    if upper == "FERTILIZER"        then hasFert    = true end
                    if upper == "LIQUIDFERTILIZER"  then hasLiqFert = true end
                end

                -- Build a lookup of names already present to avoid duplicates
                local existing = {}
                for _, name in ipairs(st.fillTypes) do
                    existing[string.upper(name)] = true
                end

                if hasFert then
                    for _, name in ipairs(solidNames) do
                        if not existing[name] then
                            table.insert(st.fillTypes, name)
                            existing[name] = true
                        end
                    end
                end

                if hasLiqFert then
                    for _, name in ipairs(liquidNames) do
                        if not existing[name] then
                            table.insert(st.fillTypes, name)
                            existing[name] = true
                        end
                    end
                end
            end
        end
    end

    -- Part 1: retroactively patch all vehicles already in memory
    local vehicleSystem = g_currentMission and g_currentMission.vehicleSystem
    local patched = 0
    if vehicleSystem and vehicleSystem.vehicles then
        for _, vehicle in pairs(vehicleSystem.vehicles) do
            patchVehicleSprayTypes(vehicle)
            patched = patched + 1
        end
    end

    -- Part 2: hook Sprayer.onLoad so future vehicles get the same treatment.
    -- onLoad fires after the vehicle XML is fully parsed but before the vehicle
    -- enters the world, so sprayType.fillTypes is already populated at this point.
    if not Sprayer or type(Sprayer.onLoad) ~= "function" then
        SoilLogger.warning("SprayTypeEffects hook: Sprayer.onLoad not available - new vehicles won't be patched")
    else
        local original = Sprayer.onLoad
        Sprayer.onLoad = Utils.appendedFunction(original, function(sprayerSelf, savegame)
            patchVehicleSprayTypes(sprayerSelf)
        end)
        self:register(Sprayer, "onLoad", original, "Sprayer.onLoad (sprayType effects)")
    end

    SoilLogger.info("[OK] SprayType effects hook installed - %d vehicles patched retroactively", patched)
    return true
end

-- =========================================================
-- POST-INSTALL: Force-refresh sprayer effects on loaded vehicles
-- =========================================================
-- After our deferred hooks install, vehicles that were loaded before
-- registerCustomSprayTypes ran will have workAreaParameters.sprayType = nil
-- (because getSprayTypeIndexByFillTypeIndex returned nil at vehicle-load time
-- before our custom types were registered). Their effects also have a stale
-- lastEffectsState that prevents re-evaluation.
--
-- Fix: iterate all loaded vehicles, reset lastEffectsState to nil so the
-- next updateSprayerEffects call sees a state change, then call it with
-- force=true to immediately re-resolve the sprayType and restart effects.
-- This is purely cosmetic and safe to call at any time post-load.
---@return nil
function HookManager:refreshAllSprayerEffects()
    local vehicleSystem = g_currentMission and g_currentMission.vehicleSystem
    if not vehicleSystem or not vehicleSystem.vehicles then
        SoilLogger.debug("refreshAllSprayerEffects: vehicleSystem not available, skipping")
        return
    end

    local refreshed = 0
    for _, vehicle in pairs(vehicleSystem.vehicles) do
        local spec = vehicle.spec_sprayer
        if spec then
            -- Re-resolve sprayType from the current fillType now that our custom
            -- types are registered in SprayTypeManager.
            local wap = spec.workAreaParameters
            if wap and wap.sprayFillType and wap.sprayFillType > 0 then
                wap.sprayType = g_sprayTypeManager:getSprayTypeIndexByFillTypeIndex(wap.sprayFillType)
            end

            -- Reset lastEffectsState so updateSprayerEffects sees a change and
            -- re-calls setEffectTypeInfo with the now-remapped fill type.
            spec.lastEffectsState = nil

            -- Call updateSprayerEffects(force=true) if the method exists on this vehicle.
            if type(vehicle.updateSprayerEffects) == "function" then
                local ok, err = pcall(vehicle.updateSprayerEffects, vehicle, true)
                if not ok then
                    SoilLogger.debug("refreshAllSprayerEffects: updateSprayerEffects failed on vehicle %s: %s",
                        tostring(vehicle.configFileName or "?"), tostring(err))
                end
            end

            refreshed = refreshed + 1
        end
    end

    if refreshed > 0 then
        SoilLogger.info("[OK] Refreshed sprayer effects on %d loaded vehicle(s)", refreshed)
    end
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

                SoilLogger.debug("Harvest hook: Field %d, Crop %d, %.0fL, area=%.1fm2, strawRatio=%.2f", 
                    fieldId, inputFruitType, liters, area, strawRatio or 0)
                g_SoilFertilityManager.soilSystem:onHarvest(fieldId, inputFruitType, liters, strawRatio, area)
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

            -- Guard: sprayer must have a valid fill type and consumed product this frame.
            -- NOTE: We deliberately do NOT gate on spec.workAreaParameters.isActive here.
            -- isActive is only set true inside processSprayerArea when FSDensityMapUtil.updateSprayArea
            -- returns changedArea > 0 — i.e., when it actually paints terrain pixels.
            -- On fields that are already fully fertilized in the vanilla FS25 density map,
            -- updateSprayArea returns changedArea=0, isActive stays false, and our hook would
            -- silently skip every application even though the sprayer IS running and product IS
            -- being consumed. This was the root cause of "NPK never increases after field scan".
            -- Using sprayFillLevel > 0 and usage > 0 is the correct gate: if the sprayer has
            -- product and consumed some this frame, we should record the nutrient application.
            local fillTypeIndex = spec.workAreaParameters.sprayFillType
            local liters        = spec.workAreaParameters.usage
            local sprayFillLevel = spec.workAreaParameters.sprayFillLevel

            if not fillTypeIndex or fillTypeIndex <= 0 then return end
            if not liters or liters <= 0 then return end
            if not sprayFillLevel or sprayFillLevel <= 0 then return end

            local success, errorMsg = pcall(function()
                local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
                if not fillType then return end

                -- Check herbicide first (mutually exclusive with fertilizer profiles)
                local herbTypes = SoilConstants.WEED_PRESSURE and SoilConstants.WEED_PRESSURE.HERBICIDE_TYPES
                local herbEffectiveness = herbTypes and herbTypes[fillType.name]
                
                -- Check insecticide
                local pestTypes = SoilConstants.PEST_PRESSURE and SoilConstants.PEST_PRESSURE.INSECTICIDE_TYPES
                local pestEffectiveness = pestTypes and pestTypes[fillType.name]
                
                -- Check fungicide
                local diseaseTypes = SoilConstants.DISEASE_PRESSURE and SoilConstants.DISEASE_PRESSURE.FUNGICIDE_TYPES
                local diseaseEffectiveness = diseaseTypes and diseaseTypes[fillType.name]
                
                local isFertilizer = SoilConstants.FERTILIZER_PROFILES[fillType.name] ~= nil

                -- Crop protection products (INSECTICIDE, FUNGICIDE, HERBICIDE) that are also
                -- listed in FERTILIZER_PROFILES carry pestReduction/diseaseReduction markers
                -- and are routed through applyFertilizer → on*Applied internally.
                -- We must NOT also call on*Applied directly from here, or they would be
                -- double-applied. Only use the direct path for products NOT in FERTILIZER_PROFILES
                -- (e.g. vanilla HERBICIDE / PESTICIDE fill types that have no profile entry).
                local herbOnlyDirect = herbEffectiveness and not isFertilizer
                local pestOnlyDirect = pestEffectiveness and not isFertilizer
                local diseaseOnlyDirect = diseaseEffectiveness and not isFertilizer

                if not isFertilizer and not herbOnlyDirect and not pestOnlyDirect and not diseaseOnlyDirect then return end

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

                if isFertilizer then
                    g_SoilFertilityManager.soilSystem:onFertilizerApplied(fieldId, fillTypeIndex, effectiveLiters)
                end

                -- Herbicide application reduces weed pressure (direct path: non-profile products only)
                if herbOnlyDirect and g_SoilFertilityManager.soilSystem.onHerbicideApplied then
                    g_SoilFertilityManager.soilSystem:onHerbicideApplied(fieldId, herbEffectiveness)
                end

                -- Insecticide application reduces pest pressure (direct path: non-profile products only)
                if pestOnlyDirect and g_SoilFertilityManager.soilSystem.onInsecticideApplied then
                    g_SoilFertilityManager.soilSystem:onInsecticideApplied(fieldId, pestEffectiveness)
                end

                -- Fungicide application reduces disease pressure (direct path: non-profile products only)
                if diseaseOnlyDirect and g_SoilFertilityManager.soilSystem.onFungicideApplied then
                    g_SoilFertilityManager.soilSystem:onFungicideApplied(fieldId, diseaseEffectiveness)
                end

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
-- HOOK 6: Sowing / planting (SowingMachine)
-- =========================================================
-- Clears field.lastCrop when seeds go in the ground so the HUD immediately
-- falls through to live FieldState detection instead of showing the stale
-- crop name from the previous harvest (fix for issue #123).
---@return boolean success True if hook installed successfully
function HookManager:installSowingHook()
    if not SowingMachine or type(SowingMachine.processSowingMachineArea) ~= "function" then
        SoilLogger.warning("Could not install sowing hook - SowingMachine.processSowingMachineArea not available")
        return false
    end

    local original = SowingMachine.processSowingMachineArea
    SowingMachine.processSowingMachineArea = Utils.appendedFunction(
        original,
        function(sowingSelf, workArea, dt)
            if not sowingSelf.isServer then return end
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.soilSystem or
               not g_SoilFertilityManager.settings.enabled then
                return
            end

            local ok, err = pcall(function()
                local x, _, z = getWorldTranslation(sowingSelf.rootNode)
                if not x then return end

                local fieldId = nil
                if g_fieldManager then
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

                g_SoilFertilityManager.soilSystem:onSowing(fieldId)
            end)

            if not ok then
                SoilLogger.error("Sowing hook failed: %s", tostring(err))
            end
        end
    )
    self:register(SowingMachine, "processSowingMachineArea", original, "SowingMachine.processSowingMachineArea")
    SoilLogger.info("[OK] Sowing hook installed (SowingMachine.processSowingMachineArea)")
    return true
end

-- =========================================================
-- HOOK 7: Patch vehicle fill units to accept custom types
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

    local solidNames  = {"UREA", "AMS", "MAP", "DAP", "POTASH",
                          "COMPOST", "BIOSOLIDS", "CHICKEN_MANURE", "PELLETIZED_MANURE", "GYPSUM"}
    local liquidNames = {"UAN32", "UAN28", "ANHYDROUS", "STARTER", "LIQUIDLIME", "INSECTICIDE", "FUNGICIDE"}

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