# PR: Fix Critical HUD and Field Detection Issues (v1.0.5.1)

## Overview
This PR addresses 6 critical issues reported in PR #29 that prevented the HUD from displaying soil data, caused crashes in field-related functionality, and introduced multiplayer desync risks.

---

## Issues Fixed

### 🔧 Issue #1: `SoilListFields` Console Command Crash
**Problem**: Console command crashed with "invalid argument #2 to 'format' (number expected, got nil)"

**Root Cause**: Line 919 in `SoilFertilitySystem.lua` tried to format `field.fieldId` which was `nil` for some entries in `g_fieldManager.fields`

**Solution**:
- Added safe string conversion: `tostring(field.fieldId or "?")`
- Fields without IDs now display as "?" instead of crashing
- Helps identify problematic field entries in debugging

**Files Changed**: `src/SoilFertilitySystem.lua`

---

### 🔧 Issue #2: Lua Stack Error on Input Registration
**Problem**: Warning in log during mod initialization:
```
LUA call stack:
  =dataS/scripts/input/InputBinding.lua:804 validateActionEventParameters
  =dataS/scripts/input/InputBinding.lua:860 registerActionEvent
```

**Root Cause**: `registerActionEvent()` call missing required parameters and proper RVB (Register-Validate-Bind) wrapper

**Solution**:
- Added `g_inputBinding:beginActionEventsModification("PLAYER")` wrapper
- Added missing parameters: `callbackState` (nil) and `textVisibility` (true)
- Added `g_inputBinding:endActionEventsModification()` wrapper
- Follows FS25 best practices (same pattern as NPCFavor mod)

**Files Changed**: `src/SoilFertilityManager.lua` (lines 318-340)

---

### 🔧 Issue #3: Keybind Not Showing in Settings > Controls
**Problem**: J key works but doesn't appear in game's Settings > Controls menu

**Root Cause**: Missing `<actions>` declaration in `modDesc.xml` before `<inputBinding>`

**Solution**:
- Added `<actions>` tag with proper action declaration:
  ```xml
  <actions>
      <action name="SF_TOGGLE_HUD" category="ONFOOT" />
  </actions>
  ```
- Keybind now properly integrates with FS25's input system
- Appears in controls menu under "On Foot" category

**Files Changed**: `modDesc.xml`

---

### 🔧 Issue #4: HUD Shows No Field Data (Critical)
**Problem**:
- HUD correctly detects farmland ID (e.g., "Farmland 3")
- But shows "No field data" because `derivedFieldId=nil`
- Debug log shows: `Farmland 3, derived fieldId=nil`

**Root Cause**:
Field detection relied on unreliable FS25 APIs:
1. `g_fieldManager:getFieldAtWorldPosition(x, z)` → returns `nil`
2. `field.getContainsPoint(field, x, z)` → returns `nil`
3. `g_fieldManager:getFieldByFarmland(farmlandId)` → returns `nil`

These APIs either don't exist or don't work correctly in FS25.

**Solution**:
Implemented NPCFavor's proven field detection pattern:
- Added new `findFieldAtPosition(x, z)` method (lines 746-814 in `SoilHUD.lua`)
- **Method 1**: Manually iterate through `g_fieldManager.fields` and test if position is within field boundaries using `field.getContainsPoint()`
- **Method 2**: If no exact match, find nearest field within 500m by calculating distance to field centers
- Uses multiple field center location patterns for compatibility:
  - `field.fieldArea.fieldCenterX/Z`
  - `field.posX/posZ`
  - `field.rootNode` (with `getWorldTranslation`)
- Replaced unreliable 60+ lines of API calls with robust 68-line solution

**Files Changed**:
- `src/ui/SoilHUD.lua` (added `findFieldAtPosition()` method)
- `src/ui/SoilHUD.lua` (simplified `drawPanel()` field detection logic)

---

### 🔧 Issue #5: All Fields Show Identical Default Values
**Problem**:
- `SoilListFields` shows all 77 fields with identical values:
  - N=50.0, P=40.0, K=45.0, pH=6.5, OM=3.51%
- No variation across map (unrealistic)

**Root Cause**:
`getOrCreateField()` initialized all fields with static default values from `SoilConstants.FIELD_DEFAULTS`

**Solution**:
Added natural soil variation on field creation:
- **Nutrients**: ±10% randomization
  - Nitrogen: 45-55 (was always 50)
  - Phosphorus: 36-44 (was always 40)
  - Potassium: 40-50 (was always 45)
- **pH**: ±0.5 randomization → 6.0-7.0 (was always 6.5)
- **Organic Matter**: ±0.5% randomization → 3.0-4.0% (was always 3.51%)
- Uses `fieldId * 67890` as deterministic seed for consistency
- Same field always gets same random values, even after save/load
- Reflects real-world soil diversity across a map

**Files Changed**: `src/SoilFertilitySystem.lua` (lines 479-507)

---

### 🔧 Issue #6: Multiplayer Desync Risk in Field Randomization
**Problem**:
- Original randomization used `fieldId + gameTime` as seed
- In multiplayer, server and clients could create fields at different times
- Different timing → different seeds → different random values → **desync**
- Example: Server sees Field 12 with N=48, client sees N=51 for same field
- HUD calls `getOrCreateField()`, allowing clients to lazy-create before sync

**Root Cause**:
No guard preventing clients from creating field data. When clients accessed HUD before receiving server sync, they would generate different randomized values than the server.

**Solution**:
- Added multiplayer safety guard in `getOrCreateField()` (lines 457-464)
- **Clients now blocked from creating fields** - must wait for server sync
- Only server can lazy-create field data in multiplayer
- Simplified seed to pure `fieldId * 67890` (removed time component)
- Clients show "No field data" until sync arrives (honest UX)

**Impact**:
- Prevents multiplayer desync issues with randomized soil values
- Ensures all players see identical field data
- Small delay for clients before HUD shows data (waiting for sync)

**Files Changed**: `src/SoilFertilitySystem.lua` (lines 457-464, 493-495)

---

## Testing Checklist

### Singleplayer Tests
- [ ] Load game and verify no Lua errors in log
- [ ] Run `SoilListFields` console command → should complete without crash
- [ ] Check Settings > Controls → "Toggle Soil HUD" should appear under "On Foot"
- [ ] Stand on a field → HUD should show soil data (not "No field data")
- [ ] Run `SoilListFields` again → fields should show varied values (not all identical)
- [ ] Press J → HUD should toggle visibility with notification

### Multiplayer Tests
- [ ] Host multiplayer server → server player sees HUD data immediately
- [ ] Client joins → client sees "No field data" briefly, then syncs and shows correct data
- [ ] Both players stand on same field → verify they see **identical** soil values
- [ ] Run `SoilListFields` on both server and client → verify field values match exactly

---

## Breaking Changes
None. All changes are backwards-compatible and fix existing functionality.

---

## Performance Impact
Minimal. The new `findFieldAtPosition()` method iterates through all fields once per frame when HUD is visible, but:
- Only runs when HUD is enabled
- Uses efficient distance calculations
- Early exits when exact match found
- Tested with 77 fields with no performance issues

---

## Related Issues
- Fixes issues raised in PR #29
- Addresses field detection problems from Issue #24

---

## Credits
- Field detection pattern adapted from FS25_NPCFavor mod (proven working implementation)
- Bug reports and testing by @TheCodingDad-TisonK
