# FS25_SoilFertilizer — v2.0.0 Implementation Plan

**Started:** 2026-04-25  
**Branch:** `development` → PR to `main` when complete  
**Target version:** `2.0.0.0`  
**Status: ALL PHASES COMPLETE** ✅

---

## Status Summary

| Phase | Issue | Feature | Status | Commit |
|-------|-------|---------|--------|--------|
| P1-A | #217 | Extract shared `isPlayerAdmin()` utility | ✅ Done | (Phase 1 commit) |
| P1-B | #218 | Guard `updatePosition()` to `hudPosition` only | ✅ Done | (Phase 1 commit) |
| P1-C | #219 | Fix source load-order fragility in `main.lua` | ✅ Done | (Phase 1 commit) |
| P2-A | #224 | Replace `hudDragEnabled` with `SF_HUD_DRAG` input action | ✅ Done | dfd3f8d |
| P2-B | #223 | Per-cell coverage tracking | ✅ Done | dfd3f8d |
| P2-C | #220 | See-and-Spray Integration | ✅ Done | c210d38 |
| P2-D | #221 | Soil Compaction System | ✅ Done | c210d38 |
| BUMP | — | Version bump to 2.0.0.0 | ✅ Done | c210d38 |

---

## What Was Built

### Phase 1 — Architecture Cleanup (all issues closed, committed to development)

**P1-A:** Created `src/utils/SoilUtils.lua` with canonical `SoilUtils.isPlayerAdmin()`. All three call sites (SoilSettingsPanel, SoilSettingsUI, NetworkEvents) now delegate to it.

**P1-B:** `SoilSettingsPanel:requestChange()` now only calls `soilHUD:updatePosition()` when `id == "hudPosition"`, not for every localOnly setting change.

**P1-C:** `SoilFertilityManager.lua` moved to Phase 4 (after Settings) in `main.lua`. Guard assertions added at the top of `SoilFertilityManager.new()`.

### Phase 2 — Features

**P2-A: SF_HUD_DRAG Input Action**
- `modDesc.xml`: Added `<action name="SF_HUD_DRAG">` and default binding (RMB)
- `SoilFertilityManager.lua`: Registers `SF_HUD_DRAG` in both PLAYER and VEHICLE input contexts; `onHUDDragInput()` toggles `soilHUD.editMode`
- `SoilHUD.lua`: Removed old RMB mouse check, replaced with action callback
- `SettingsSchema.lua`: Removed `hudDragEnabled` definition
- `SoilSettingsPanel.lua`: Removed `hudDragEnabled` from Display & HUD section
- All 26 translations: Removed `sf_hud_drag_enabled_*` keys; added `input_SF_HUD_DRAG` key

**P2-B: Per-Cell Coverage Tracking**
- `SoilConstants.COVERAGE = { MIN_FULL_CREDIT = 0.70 }`
- `fieldData`: Added `coveredCells`, `coveredCellCount`, `totalFieldCells`, `coverageFraction`
- `SoilFertilitySystem.applyFertilizer()`: Tracks unique spray cells per day; computes `coverageFraction`
- Fully-treated notification gated on `coverageFraction >= 0.70`
- `SoilHUD`: Shows `Coverage: X% / 70% min` with green/amber color
- `NetworkEvents`: `coverageFraction` synced in batch and field update events

**P2-C: See-and-Spray Integration**
- New file: `src/integrations/SeeAndSprayIntegration.lua`
- Sourced in Phase 6 of `main.lua` (after NetworkEvents)
- Wraps `WeedSpotSpray.updateExtendedSprayerNozzleEffectState` at source time
- When the native weed check would deactivate a HERBICIDE nozzle, checks `fieldData.weedPressure` at the nozzle world position
- If `weedPressure >= 20`, re-activates the nozzle (bridges our tracking into See-and-Spray)
- Double-guarded: `WeedSpotSpray ~= nil` at source time + `g_precisionFarming ~= nil` at runtime

**P2-D: Soil Compaction System**
- `SoilConstants.COMPACTION`: 8t threshold, 2pt/pass, 0.5pt/day decay, 15pt subsoiler reduction, 20% max nutrient penalty
- `compactionEnabled` boolean setting: SettingsSchema + SoilSettingsPanel (Crop Stress section + Admin) + 26 translations
- `fieldData.compaction` (0–100): persisted in soilData.xml, synced in all network events
- `HookManager`: Cultivator hook checks `spec_cultivator.isSubsoiler` (calls `onSubsoilerPass`) or vehicle total mass ≥ 8t (calls `onCompaction`); Plow hook also checks mass
- `SoilFertilitySystem`: `onCompaction()` (once/day throttle), `onSubsoilerPass()`, daily decay in `updateDailySoil()`, nutrient extraction penalty in `updateFieldNutrients()` (up to 20% at max compaction)
- `SoilHUD`: Compaction % row with green/amber/red thresholds
- `SoilMapOverlay`: Layer 10 (Compaction, dark brown/orange), `LAYER_COUNT = 10`, `INVERTED_LAYERS[10]=true`
- `NetworkEvents`: `compaction` field in SoilFieldBatchSyncEvent and SoilFieldUpdateEvent (both paths)
- `SettingsSchema`: `activeMapLayer` max bumped from 9 → 10
- `SoilSettingsPanel`: MULTI_OPTS.activeMapLayer includes "Compaction"

---

## Files Modified

| File | Changes |
|------|---------|
| `src/utils/SoilUtils.lua` | NEW — P1-A |
| `src/integrations/SeeAndSprayIntegration.lua` | NEW — P2-C |
| `src/main.lua` | P1-A (source), P1-C (reorder), P2-C (new source) |
| `src/ui/SoilSettingsPanel.lua` | P1-A, P1-B, P2-A (remove toggle), P2-D (compaction) |
| `src/settings/SoilSettingsUI.lua` | P1-A |
| `src/network/NetworkEvents.lua` | P1-A, P2-B (coverage), P2-D (compaction) |
| `src/SoilFertilityManager.lua` | P1-C (assertions), P2-A (action events) |
| `src/SoilFertilitySystem.lua` | P2-B (coverage), P2-D (compaction field, decay, penalty, API) |
| `src/hooks/HookManager.lua` | P2-D (compaction triggers in plow/cultivator hooks) |
| `src/config/Constants.lua` | P2-B (COVERAGE), P2-D (COMPACTION) |
| `src/config/SettingsSchema.lua` | P2-A (remove hudDragEnabled), P2-D (compactionEnabled, max 10) |
| `src/ui/SoilHUD.lua` | P2-A (input action), P2-B (coverage display), P2-D (compaction display) |
| `src/ui/SoilLayerSystem.lua` | No changes needed (compaction uses field-average path only) |
| `src/ui/SoilMapOverlay.lua` | P2-D (layer 10, LAYER_COUNT=10, getLayerColor) |
| `modDesc.xml` | P2-A (action binding), P2-D (version 2.0.0.0) |
| `translations/translation_*.xml` (×26) | P2-A (SF_HUD_DRAG key), P2-D (compaction keys, map layer key) |

---

## Next Session Starting Point

**All v2.0.0 issues are closed and committed to `development`.** The next step is:

1. Open a PR from `development` → `main` for the v2.0.0 release
2. Review the PR, merge when ready
3. Create a GitHub release tagged `v2.0.0`

### Known Deferred Items (not blocking v2.0.0)

- **Coverage nutrient scaling (v2.1):** The V2_PLAN originally proposed scaling N/P/K application by `coverageFraction`. This was deferred because scaling per-frame creates a chicken-and-egg problem (first spray cells get near-zero credit). Currently, coverage tracking + HUD display + notification gate are implemented; the nutrient math scaling can be added in v2.1 after further design.
- **Compaction overlay GRLE layer:** Layer 10 uses the field-average color path (same as layers 6-9). A per-pixel GRLE density map for compaction could be added in a future update if per-zone variation is desired.
