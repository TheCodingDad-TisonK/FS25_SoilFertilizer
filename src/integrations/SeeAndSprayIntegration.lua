-- =========================================================
-- FS25 Realistic Soil & Fertilizer - See-and-Spray Integration
-- =========================================================
-- Augments the Precision Farming See-and-Spray system so that
-- our weed pressure data can activate spot-spray nozzles even
-- when the native weed density map shows no weeds at a position.
--
-- GUARD STRATEGY:
--   Source-time:  check WeedSpotSpray ~= nil (DLC must be loaded before us)
--   Runtime:      check g_precisionFarming ~= nil (DLC fully initialized)
--
-- HOW IT WORKS:
--   WeedSpotSpray.updateExtendedSprayerNozzleEffectState decides per-nozzle
--   whether to spray (isActive) based on the native weed density map.
--   We wrap it: if the original says "no spray" but our fieldData shows high
--   weed pressure at that position, we re-enable the nozzle.
--   Only activates for HERBICIDE fill type (native See-and-Spray gate).
-- =========================================================
-- Author: TisonK
-- =========================================================

local SEE_AND_SPRAY_WEED_THRESHOLD = 20  -- our weedPressure (0-100) above which we activate

if WeedSpotSpray ~= nil and WeedSpotSpray.updateExtendedSprayerNozzleEffectState ~= nil then
    local origFn = WeedSpotSpray.updateExtendedSprayerNozzleEffectState

    WeedSpotSpray.updateExtendedSprayerNozzleEffectState = function(self, superFunc, effectData, dt, isTurnedOn, lastSpeed)
        local isActive, amountScale = origFn(self, superFunc, effectData, dt, isTurnedOn, lastSpeed)

        -- Only augment when: nozzle would be off, DLC runtime is active, and our system is ready
        if not isActive and g_precisionFarming ~= nil and g_SoilFertilityManager ~= nil then
            local spec = self[WeedSpotSpray.SPEC_TABLE_NAME]
            -- Only augment for See-and-Spray enabled vehicles using HERBICIDE
            if spec and spec.isEnabled then
                local specSprayer = self.spec_sprayer
                local sprayFillType = specSprayer and specSprayer.workAreaParameters and
                                      specSprayer.workAreaParameters.sprayFillType
                if sprayFillType == FillType.HERBICIDE then
                    -- Sample world position 1m ahead of the nozzle node
                    local ok, wx, _, wz = pcall(function()
                        return localToWorld(effectData.effectNode, 0, 0, 1)
                    end)
                    if ok and wx then
                        local soilSystem = g_SoilFertilityManager.soilSystem
                        if soilSystem then
                            local field = g_fieldManager and g_fieldManager:getFieldAtWorldPosition(wx, wz)
                            if field and field.farmland and field.farmland.id then
                                local fieldData = soilSystem.fieldData and soilSystem.fieldData[field.farmland.id]
                                if fieldData and (fieldData.weedPressure or 0) >= SEE_AND_SPRAY_WEED_THRESHOLD then
                                    isActive = true
                                end
                            end
                        end
                    end
                end
            end
        end

        return isActive, amountScale
    end

    SoilLogger.info("[SeeAndSpray] WeedSpotSpray hook installed — weed pressure bridge active")
else
    SoilLogger.info("[SeeAndSpray] WeedSpotSpray not found — Precision Farming DLC not loaded, integration skipped")
end
