# Issue #27 Diagnostic Guide: HUD Not Showing Data

## Problem

"Fields being scanned but data not being showed in HUD" - The HUD overlay appears to be blank or missing soil nutrient information.

## Root Cause Analysis

The HUD has **multiple visibility checks** that can prevent display:

### Visibility Checks (in order):

1. ✅ **`self.initialized`** - HUD must be initialized
2. ✅ **`self.settings.enabled`** - Mod must be enabled
3. ⚠️ **`self.settings.showHUD`** - Show HUD setting (persistent)
4. ⚠️ **`self.visible`** - Runtime visibility toggle (J key)
5. ⚠️ **Position detection** - Must get player/vehicle position
6. ⚠️ **Field detection** - Must find field at position
7. ⚠️ **Field data** - Field must be initialized in system

## User Debugging Steps

### Step 1: Check HUD Visibility Settings

**Press J key** - This toggles HUD visibility on/off
- Look in console/log for: `"Soil HUD shown"` or `"Soil HUD hidden"`
- Try toggling J key 2-3 times

**Check Settings Menu:**
- Go to: Options → Settings → Soil & Fertilizer
- Find: "Show HUD" toggle
- Make sure it's **enabled** (checkmark)

### Step 2: Enable Debug Mode

**Open console** (~ key) and type:
```
SoilDebug
```

This enables detailed logging. Then watch the log file for:
- `[HUD] getCurrentFarmlandId:` messages
- `[HUD DEBUG]` messages showing position and field detection

### Step 3: Check Log File

**Location:** `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt`

**Look for these patterns:**

**GOOD - HUD Working:**
```
[SoilFertilizer] Soil HUD shown
[HUD] getCurrentFarmlandId: Position from g_localPlayer: x=123.4, z=567.8
[HUD DEBUG] Field detected via getFieldAtWorldPosition: 1
[HUD DEBUG] Field 1 data: N=50, P=40, K=45
```

**BAD - Position Detection Failed:**
```
[HUD] getCurrentFarmlandId: No position available from any source
```
**FIX:** This is a timing/game state issue. Try:
- Walking around the field
- Entering/exiting a vehicle
- Reloading the save

**BAD - No Field Detection:**
```
[HUD DEBUG] No field info for fieldId=nil (farmland 1)
```
**FIX:** You're on farmland but not in a cultivatable field. Move to a field that has been plowed/cultivated.

**BAD - Field Initializing:**
```
[HUD DEBUG] No field info for fieldId=1 (farmland 1)
```
**FIX:** Field exists but data not loaded. This happens when:
- New save (fields not initialized yet)
- Multiplayer client (waiting for server sync)
- Fields still scanning (wait 5-10 seconds)

### Step 4: Force Field Scan

**Open console** (~ key) and type:
```
SoilFieldInfo 1
```

Replace `1` with your field number. This forces the system to check if field data exists.

**Expected output:**
```
Field 1 - Soil Data:
  Nitrogen: 50 (Good)
  Phosphorus: 40 (Fair)
  ...
```

If this shows data but HUD doesn't, **the issue is HUD display logic**.
If this shows "Field not found", **the issue is field initialization**.

### Step 5: Check Multiplayer Sync

**If playing multiplayer as CLIENT:**

The HUD might be waiting for server sync. Check log for:
```
[SoilFertilizer] Client: Received full sync from server
[SoilFertilizer] Client: Synced X fields from server
```

If missing, the **multiplayer sync failed** (this was fixed in latest version - make sure you're using v1.0.4.2+).

### Step 6: Check for Mod Conflicts

**Common conflicting mods:**
- Other HUD overlays
- Visual enhancement mods
- Menu modification mods

**Test:** Disable all other mods and see if HUD appears.

## Quick Fix Summary

| Symptom | Fix |
|---------|-----|
| HUD completely invisible | Press **J** key to toggle, or check "Show HUD" in settings |
| HUD shows "No farmland detected" | Walk to a field you own |
| HUD shows "No field data (Not cultivatable)" | You're on farmland but not in a cultivated field - plow it first |
| HUD shows "Field X Initializing..." forever | Wait 10 seconds, or reload save. If persists, field scan failed. |
| HUD shows farmland but no field number | Position detection failed - enter/exit vehicle |
| Multiplayer: HUD blank on client | Server sync failed - reconnect or update mod to v1.0.4.2+ |

## Developer Notes

**Code locations:**
- Visibility checks: `src/ui/SoilHUD.lua:266-271`
- Position detection: `src/ui/SoilHUD.lua:666-724` (`getCurrentPosition()`)
- Field detection: `src/ui/SoilHUD.lua:462-519` (inside `drawPanel()`)
- Field data retrieval: `src/ui/SoilHUD.lua:530-556`

**Known issues:**
1. Position detection can fail in menu/pause state
2. Field detection requires cultivated fields (not just farmland)
3. Multiplayer clients need successful sync before HUD works

## Report Back

If none of these steps fix the issue, please provide:
1. Log file (`log.txt`)
2. Save game file (if possible)
3. List of other installed mods
4. Screenshot of HUD area
5. Multiplayer or singleplayer?
6. Map name

This will help identify edge cases not covered by this diagnostic.
