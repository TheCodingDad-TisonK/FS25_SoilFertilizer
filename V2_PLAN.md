# FS25_SoilFertilizer — v2.0.0 Implementation Plan

**Started:** 2026-04-25  
**Branch:** `development` → PR to `main` when complete  
**Target version:** `2.0.0.0`

---

## Overview

v2.0.0 is split into two phases. Phase 1 is mandatory architectural cleanup that must be complete and verified before any Phase 2 feature work begins. Phase 2 delivers four major features, ordered by dependency.

---

## Phase 1 — Architecture Cleanup

All three items are low-risk, self-contained changes. Complete them in order; each is one commit.

---

### P1-A: Extract shared `isPlayerAdmin()` utility  *(Issue #217)*

**Problem:** Admin detection logic is copy-pasted in three places with slight implementation differences.

| Location | Function |
|----------|----------|
| `src/ui/SoilSettingsPanel.lua:348` | `SoilSettingsPanel:isAdmin()` |
| `src/settings/SoilSettingsUI.lua:46` | `SoilSettingsUI:isPlayerAdmin()` |
| `src/network/NetworkEvents.lua:895` | inline in `SoilNetworkEvents_IsPlayerAdmin()` |

**Implementation:**

1. Create `src/utils/SoilUtils.lua` — new utility module.
2. Add `SoilUtils.isPlayerAdmin()` with the canonical implementation (single-player → `true`, dedicated server → `true`, MP client → `currentUser:getIsMasterUser()`).
3. Source `SoilUtils.lua` in `main.lua` Phase 1 (after `Logger.lua`, before everything else).
4. Replace all three call sites with `SoilUtils.isPlayerAdmin()`.
5. Delete the three local implementations.

**Canonical implementation to use:**
```lua
function SoilUtils.isPlayerAdmin()
    if not g_currentMission then return false end
    if not (g_currentMission.missionDynamicInfo and
            g_currentMission.missionDynamicInfo.isMultiplayer) then
        return true
    end
    if g_dedicatedServer then return true end
    local user = g_currentMission.userManager and
                 g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    return user ~= nil and user:getIsMasterUser()
end
```

**Verify:** `SoilSettingsPanel:isAdmin()`, `SoilSettingsUI:isPlayerAdmin()`, and the NetworkEvents inline check all call through. No behavior change.

---

### P1-B: Restrict `updatePosition()` to `hudPosition` changes only  *(Issue #218)*

**Problem:** `SoilSettingsPanel:requestChange()` calls `soilHUD:updatePosition()` for every `localOnly` setting change — including `hudColorTheme`, `hudFontSize`, `hudTransparency` — which have no effect on HUD position. The HUD already redraws from live settings every frame.

**Location:** `src/ui/SoilSettingsPanel.lua` — the `localOnly` branch of `requestChange()`.

**Current code (line ~368):**
```lua
if g_SoilFertilityManager and g_SoilFertilityManager.soilHUD then
    g_SoilFertilityManager.soilHUD:updatePosition()
end
```

**Fix:** Guard behind an `id == "hudPosition"` check:
```lua
if id == "hudPosition" and g_SoilFertilityManager and g_SoilFertilityManager.soilHUD then
    g_SoilFertilityManager.soilHUD:updatePosition()
end
```

**Verify:** Changing `hudPosition` setting still repositions the HUD. Changing `hudColorTheme`, `hudFontSize`, or `hudTransparency` does not call `updatePosition()` but HUD still reflects the change on next frame.

---

### P1-C: Resolve source load-order fragility in `main.lua`  *(Issue #219)*

**Problem:** `SoilFertilityManager.lua` is sourced in Phase 2 but depends on `Settings` and `SettingsManager` which are loaded in Phase 3. This works today only because `new()` isn't called until mission load, but the ordering is misleading and fragile.

**Chosen fix:** Move `SoilFertilityManager.lua` to after Phase 3 (settings) in `main.lua`, and add guard assertions at the top of `SoilFertilityManager.new()`.

**`main.lua` target order:**
```
Phase 1: Logger, AsyncRetryHandler, Constants, SettingsSchema, SoilUtils (new)
Phase 2: HookManager, SoilLayerSystem, SprayerRateManager, SoilFertilitySystem
Phase 3: SettingsManager, Settings, SoilSettingsGUI
Phase 4: UIHelper, SoilSettingsUI, SoilHUD, SoilReportDialog, SoilMapOverlay,
         SoilMapHooks, SoilPDAScreen, SoilFieldDetailDialog, SoilTreatmentDialog,
         SoilSettingsPanel, SoilFertilityManager  ← moved here
Phase 5: NetworkEvents
```

**Guard assertions to add at top of `SoilFertilityManager.new()`:**
```lua
assert(Settings,        "[SoilFertilizer] Settings not loaded — check source order in main.lua")
assert(SettingsManager, "[SoilFertilizer] SettingsManager not loaded — check source order in main.lua")
```

**Verify:** Mod loads without errors. Assertions don't fire.

---

## Phase 2 — Features

Complete in the order listed. Each feature is independent, but #223 builds on foundation that must be solid before #221.

---

### P2-A: Replace `hudDragEnabled` with rebindable `SF_HUD_DRAG` input action  *(Issue #224)*

**Goal:** Players remap HUD drag to any key in Controls settings rather than using a binary toggle.

**Implementation steps:**

1. **`modDesc.xml`** — add input action declaration and default binding (RMB = mouse button 3):
   ```xml
   <action name="SF_HUD_DRAG" axisType="HALF_POSITIVE_AXIS" />
   ```
   ```xml
   <actionBinding action="SF_HUD_DRAG">
       <binding device="KB_MOUSE_DEFAULT" input="MOUSE_BUTTON_RIGHT" />
   </actionBinding>
   ```
   > Before implementing, verify `axisType` values and binding syntax in the LUADOC under `InputBinding` / `ActionEvent`.

2. **`src/ui/SoilHUD.lua`** — register/unregister the input action event:
   - In `SoilHUD:init()` or `SoilHUD:registerActionEvents()`, register `SF_HUD_DRAG` via `g_inputBinding:registerActionEvent`.
   - In `onMouseEvent()`, replace the `button == 3 and self.settings.hudDragEnabled` check with the action event callback.
   - In the `update()` drag-hover check, replace the `hudDragEnabled` guard with an action state check.
   - Store the registered action event ID for cleanup in `SoilHUD:delete()`.
   > Check LUADOC: `InputBinding:registerActionEvent`, `ActionEvent`, callback signature, and `removeActionEvent`.

3. **`src/config/SettingsSchema.lua`** — remove the `hudDragEnabled` setting definition entirely.

4. **`src/ui/SoilSettingsPanel.lua`** — remove the `hudDragEnabled` row from the Display & HUD category render list and any references to it.

5. **`modDesc.xml`** `<l10n>` — remove all 26 `hudDragEnabled_*` translation keys.

6. **Verify:** Controls settings screen shows `SF_HUD_DRAG` action. Remapping works. `hudDragEnabled` toggle no longer appears in Shift+O panel.

---

### P2-B: Per-cell coverage tracking — require full-field pass for fertilizer credit  *(Issue #223)*

**Goal:** Fertilizer credit is proportional to area covered, not total liters delivered. Player must cover most of the field.

**Foundation already in place:**
- `fieldData[fieldId].zoneData` — sparse `{cellKey → {N,P,K,pH,OM}}` per-cell store exists
- `self._lastSprayX / _lastSprayZ` — sprayer position tracked
- `SoilLayerSystem` — per-pixel density map already updated on spray
- `nutrientBuffer` — accumulates liters before committing to field aggregate

**Current flow (v1):** liters → `nutrientBuffer` → when buffer ≥ threshold → apply full N/P/K delta to field aggregate.

**New flow (v2):**
1. On each spray event, write nutrients to the cell for the sprayer's current position (already partially done via `zoneData` updates in `applyFertilizer()`).
2. Track `fieldData[fieldId].coveredCells` — a set of cell keys that have received fertilizer this application pass.
3. Track `fieldData[fieldId].totalFieldCells` — calculated once when field is first processed (count cells inside field polygon at the configured cell size).
4. Compute `coverageFraction = #coveredCells / totalFieldCells`.
5. When `coveredCells` is cleared (daily reset or manual pass complete), apply `coverageFraction` as a multiplier to the nutrient delta committed to the field aggregate.
6. Add `coverageFraction` to HUD display and PDA field info (show as "Coverage: 73%").
7. Add `coverageThreshold` constant to `Constants.lua` (default: 0.70 — 70% of field must be covered for full credit).
8. If `coverageFraction < coverageThreshold`, scale nutrient application proportionally (not binary).

**Constants to add in `Constants.lua`:**
```lua
COVERAGE = {
    CELL_SIZE_M       = 10,   -- metres per coverage cell
    MIN_FULL_CREDIT   = 0.70, -- fraction of field required for 100% nutrient credit
}
```

**Files to change:** `src/SoilFertilitySystem.lua`, `src/config/Constants.lua`, `src/ui/SoilHUD.lua` (display), `src/ui/SoilPDAScreen.lua` (field detail).

**Save/load:** `coveredCells` is transient (reset daily) — does not need persistence. `coverageFraction` of last completed pass can be stored per-field in `soilData.xml` for display purposes.

**Multiplayer:** Coverage cells are local to the machine running the sprayer. For MP, the server applies the coverage fraction when the spray event arrives via network (consistent with current model — sprayer events are server-authoritative).

---

### P2-C: See-and-Spray Integration  *(Issue #220)*

**Goal:** Our custom herbicide fill types are recognized by the base game's See-and-Spray AI, and our weed pressure data feeds the AI's targeting decisions.

**Pre-check:** This entire feature must be guarded behind a `hasMod("FS25_PrecisionFarming")` or equivalent DLC check. If See-and-Spray is not installed, the integration must be a complete no-op.

> **LUADOC CHECK REQUIRED** before any implementation:
> - `SprayTypeManager` — how fill types are registered, what `isHerbicide` field controls
> - `WeedSystem` or `WeedMap` — how weed density is stored, what See-and-Spray AI reads
> - Whether `g_precisionFarming` is the correct global for the DLC guard
> - `Sprayer.spec_sprayer` spray type registration hooks

**Implementation steps:**

1. **Fill type registration** — On `Mission00.loadMission00Finished`, iterate all fill types that have a `herbicideReduction` entry in our fertilizer profiles. For each, set `isHerbicide = true` via `SprayTypeManager` (verify exact API). This teaches See-and-Spray to recognize them as herbicide.

2. **Weed density bridge** — Two options (choose after LUADOC research):
   - *Option A (preferred):* Hook the See-and-Spray AI decision function and inject our `fieldData[fieldId].weedPressure` as an additional signal.
   - *Option B (fallback):* On daily update, write our `weedPressure` values into the native weed density layer at field centroid positions, so See-and-Spray reads them naturally.

3. **Graceful fallback** — Wrap all integration code in:
   ```lua
   if g_modIsLoaded and g_modIsLoaded["FS25_PrecisionFarming"] then
       -- integration code
   end
   ```
   > Verify the correct DLC presence check in LUADOC.

4. **New file:** `src/integrations/SeeAndSprayIntegration.lua` — keeps integration code separate from core systems. Source in Phase 5 of `main.lua` (after NetworkEvents), so it can reference all globals safely.

**Verify:** With See-and-Spray DLC: fields with high weed pressure are targeted. Without DLC: no errors, no behavior change.

---

### P2-D: Soil Compaction System  *(Issue #221)*

**Goal:** Heavy vehicles compact soil over time, reducing nutrient absorption. Subsoiler / deep tillage reduces compaction. New HUD + overlay layer.

**Data model:**
- `fieldData[fieldId].compaction` — float 0–100 (0 = no compaction, 100 = fully compacted)
- Persisted in `soilData.xml` per field — backward compatible (missing key defaults to 0)

**Settings:**
- `compactionEnabled` — boolean, server-authoritative, default `true`
- Add to `SettingsSchema.lua` in the Simulation category
- Add toggle to Shift+O Simulation tile and all 26 language keys

**Constants to add in `Constants.lua`:**
```lua
COMPACTION = {
    HEAVY_VEHICLE_THRESHOLD_KG = 8000,  -- axle weight to trigger compaction
    COMPACTION_PER_PASS        = 2.0,   -- points added per heavy-vehicle pass
    NATURAL_DECAY_PER_DAY      = 0.5,   -- points removed per game day (natural recovery)
    SUBSOILER_REDUCTION        = 15.0,  -- points removed per subsoiler pass
    MAX_COMPACTION             = 100.0,
    NUTRIENT_PENALTY_MAX       = 0.20,  -- max 20% reduction to N/P/K absorption at max compaction
}
```

**Hooks to add in `HookManager.lua`:**

1. **Vehicle weight hook** — Hook `Vehicle.onUpdateTick` (or work area processing):
   > **LUADOC CHECK REQUIRED:** Verify `Vehicle.spec_motorized` for mass/weight access, `getFieldAtWorldPosition` timing, and whether `onUpdateTick` is the right hook point.
   - Check if vehicle is on a field.
   - Check axle weight against threshold (use `spec_motorized.mass` or equivalent).
   - Add `COMPACTION_PER_PASS` to `fieldData[fieldId].compaction`, capped at 100.
   - Throttle: only trigger once per field per vehicle pass (track with a cooldown per vehicleId+fieldId pair).

2. **Subsoiler hook** — Extend existing `Cultivator.processCultivatorArea` hook (already present at `HookManager.lua:1243`):
   - Check if the cultivator has `spec_subsoiler` or a `deepTillage` flag.
   - If yes, reduce `fieldData[fieldId].compaction` by `SUBSOILER_REDUCTION`, floored at 0.
   > LUADOC check: confirm `spec_subsoiler` exists or find the correct deep-tillage spec name.

**Yield integration:**
- In `SoilFertilitySystem:applyHarvestDepletion()`, compute `compactionPenalty = (field.compaction / 100) * NUTRIENT_PENALTY_MAX`.
- Multiply effective N/P/K depletion by `(1 + compactionPenalty)` — more compaction → nutrients depleted faster (less uptake efficiency).

**HUD display:**
- Add compaction percentage line to SoilHUD field info block when `compactionEnabled` and `compaction > 0`.
- Use color coding: green ≤ 20%, amber ≤ 60%, red > 60%.

**Overlay layer:**
- Add Layer 10 to `SoilMapOverlay` — "Compaction" — color gradient white→brown→black.
- Add layer entry to `SoilLayerSystem`.
- Update layer cycle in the map sidebar button.

**Network sync:**
- Add `compaction` field to `SoilFieldBatchSyncEvent` and `SoilFieldUpdateEvent` (already used for nutrient sync — just add the field).

**Multiplayer:**
- Compaction changes are server-authoritative (same pattern as nutrient changes).
- Server broadcasts `SoilFieldUpdateEvent` after each compaction change.

**Files to change:** `src/SoilFertilitySystem.lua`, `src/hooks/HookManager.lua`, `src/config/Constants.lua`, `src/config/SettingsSchema.lua`, `src/ui/SoilHUD.lua`, `src/ui/SoilLayerSystem.lua`, `src/ui/SoilMapOverlay.lua`, `src/network/NetworkEvents.lua`, `src/ui/SoilSettingsPanel.lua`, `modDesc.xml` (l10n + new setting label).

---

## UX Polish Notes (Samantha review)

These are observations from UX review — not blocking, but worth addressing during implementation:

| Area | Observation | Action |
|------|-------------|--------|
| Coverage HUD display | "Coverage: 73%" is useful but players need to know WHAT the threshold is | Show "Coverage: 73% / 70% min" or use color coding (green = at/above threshold) |
| Compaction indicator | Compaction value 0–100 is abstract — consider showing as label ("Low / Medium / High / Severe") next to the number | Add `SoilUtils.compactionLabel(v)` helper returning localized string |
| See-and-Spray DLC | Players without the DLC must never see any UI or setting related to this feature | Ensure all UI elements are fully gated — no orphaned settings in Shift+O |
| `SF_HUD_DRAG` action | The new action appears in Controls settings — needs a human-readable label in all 26 languages | Add `SF_HUD_DRAG` l10n key to `modDesc.xml` before v2 ship |
| Compaction overlay | Layer 10 needs a sidebar label — update the cycle button to show "Compaction" in all 26 languages | Add l10n key `map_layer_compaction` |

---

## Implementation Order (Commit Sequence)

```
1. [P1-A] SoilUtils.lua + isPlayerAdmin() extraction
2. [P1-B] Guard updatePosition() behind hudPosition check
3. [P1-C] Move SoilFertilityManager to Phase 4, add load assertions
4. [P2-A] SF_HUD_DRAG input action + remove hudDragEnabled
5. [P2-B] Per-cell coverage tracking
6. [P2-C] See-and-Spray integration
7. [P2-D] Soil Compaction System
8. [BUMP] Bump version to 2.0.0.0, update modDesc + roadmap issue
```

Each commit is one issue. PRs for each phase (Phase 1 as single PR, Phase 2 as individual PRs or one combined PR).

---

## LUADOC Checks Required Before Coding

These must be verified before writing the corresponding code — **do not guess**:

| Feature | Check needed |
|---------|-------------|
| P2-A | `InputBinding:registerActionEvent` signature, `axisType` for button actions, `removeActionEvent` |
| P2-C | `SprayTypeManager` fill type registration, `isHerbicide` field, weed density layer API, DLC presence check |
| P2-D | `Vehicle` mass/weight API (`spec_motorized`), `onUpdateTick` hook viability, `spec_subsoiler` existence |

---

## Files Modified Summary

| File | Issues |
|------|--------|
| `src/utils/SoilUtils.lua` | New — P1-A |
| `src/main.lua` | P1-A (source), P1-C (reorder), P2-C (new source) |
| `src/ui/SoilSettingsPanel.lua` | P1-A (isAdmin), P1-B (requestChange), P2-A (remove toggle), P2-D (new setting) |
| `src/settings/SoilSettingsUI.lua` | P1-A (isPlayerAdmin) |
| `src/network/NetworkEvents.lua` | P1-A (inline check), P2-D (compaction in sync events) |
| `src/SoilFertilityManager.lua` | P1-C (guard assertions) |
| `src/SoilFertilitySystem.lua` | P2-B (coverage), P2-D (compaction penalty) |
| `src/hooks/HookManager.lua` | P2-D (vehicle weight + subsoiler hooks) |
| `src/config/Constants.lua` | P2-B (COVERAGE), P2-D (COMPACTION) |
| `src/config/SettingsSchema.lua` | P2-A (remove hudDragEnabled), P2-D (compactionEnabled) |
| `src/ui/SoilHUD.lua` | P2-A (input action), P2-B (coverage display), P2-D (compaction display) |
| `src/ui/SoilLayerSystem.lua` | P2-D (layer 10) |
| `src/ui/SoilMapOverlay.lua` | P2-D (compaction layer) |
| `src/ui/SoilPDAScreen.lua` | P2-B (coverage in field detail) |
| `src/integrations/SeeAndSprayIntegration.lua` | New — P2-C |
| `modDesc.xml` | P2-A (action binding, remove l10n keys), P2-D (new l10n keys) |
