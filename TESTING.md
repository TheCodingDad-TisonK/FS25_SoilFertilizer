# FS25_SoilFertilizer - Testing Guide

**Version**: 1.0.4.1
**Last Updated**: 2026-02-14

---

## Overview

This document provides manual testing procedures for verifying mod functionality. Since FS25 mods run inside the game engine, traditional unit tests aren't practical. Use this guide for manual testing and regression verification.

---

## Pre-Testing Setup

1. **Clean Install**
   - Remove any previous version from `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods`
   - Copy fresh `FS25_SoilFertilizer.zip` to mods folder
   - Launch FS25 and load a savegame

2. **Verify Installation**
   - Check log file (`log.txt`) for `[SoilFertilizer]` entries
   - Should see: "All hooks installation complete"
   - Should see: "Soil HUD overlay initialized"
   - No errors or warnings on load

3. **Access Console**
   - Press `~` (tilde) to open developer console
   - Type `soilfertility` to verify commands are registered

---

## Feature Test Scenarios

### 1. Core Soil System

**Test: Field Initialization**
- Load savegame with owned fields
- Console: `SoilFieldInfo <fieldId>`
- Verify: Shows N/P/K values, pH, organic matter
- Expected: Values should be sensible (N:40-60, P:30-50, K:35-55, pH:6.0-7.0, OM:3-4%)

**Test: Crop Harvest Depletion**
1. Plant and grow a crop to harvest stage
2. Note field nutrients before harvest: `SoilFieldInfo <fieldId>`
3. Harvest the field completely
4. Check nutrients after: `SoilFieldInfo <fieldId>`
5. Verify: N/P/K decreased (amount varies by crop and difficulty)

**Test: Fertilizer Application**
1. Note field nutrients: `SoilFieldInfo <fieldId>`
2. Apply liquid fertilizer with sprayer
3. Check nutrients after: `SoilFieldInfo <fieldId>`
4. Verify: N increased significantly
5. Repeat with solid fertilizer, manure, slurry
6. Verify: Each fertilizer type affects different nutrients

**Test: Plowing Bonus**
1. Enable plowing bonus: `SoilSetPlowingBonus true`
2. Note organic matter and pH: `SoilFieldInfo <fieldId>`
3. Plow the field with a plow (not cultivator)
4. Check values after: `SoilFieldInfo <fieldId>`
5. Verify: Organic matter increased ~5%, pH moved toward 7.0

---

### 2. HUD Display

**Test: HUD Visibility**
1. Stand in a field or enter vehicle in field
2. Verify: HUD appears in configured position
3. Shows: Field ID, N, P, K, pH, OM, last crop
4. Press F8
5. Verify: HUD toggles off/on

**Test: HUD Position Presets**
1. Open Settings → General → Soil & Fertilizer
2. Change "HUD Position" dropdown
3. Verify: HUD moves immediately (no restart needed)
4. Test all 5 positions: Top Right, Top Left, Bottom Right, Bottom Left, Center Right

**Test: HUD Context Awareness**
1. Open game menu (ESC)
2. Verify: HUD hidden
3. Open map (Tab)
4. Verify: HUD hidden when map is large view
5. Enter construction mode (place building)
6. Verify: HUD hidden while placing objects

**Test: Show HUD Setting**
1. Settings → Soil & Fertilizer → Show HUD → Off
2. Verify: HUD disappears
3. Press F8
4. Verify: HUD does NOT appear (setting overrides F8)
5. Turn Show HUD back On
6. Verify: HUD reappears

---

### 3. Multiplayer

**Test: Server-Client Sync**
1. Host multiplayer server
2. Join as client from another PC
3. As client, check field info: `SoilFieldInfo <fieldId>`
4. Verify: Shows same values as server
5. As server, harvest a field
6. As client, check field info again
7. Verify: Client sees updated values automatically

**Test: Admin-Only Settings**
1. Join multiplayer as non-admin client
2. Try to change settings in menu
3. Verify: Controls disabled with "Admin only" tooltip
4. Try console command: `SoilSetDifficulty 3`
5. Verify: Rejected (not admin)
6. Promote to admin, try again
7. Verify: Setting changes now work

**Test: Full Sync on Join**
1. Host server, play for a while (harvest fields, apply fertilizer)
2. Join as new client
3. Verify: Client receives all field data within 5 seconds
4. Check log: Should see "Client: Full sync completed successfully"

---

### 4. Save/Load Persistence

**Test: Data Saves Between Sessions**
1. Note field nutrients: `SoilFieldInfo <fieldId>`
2. Save and exit game
3. Reload savegame
4. Check field nutrients: `SoilFieldInfo <fieldId>`
5. Verify: Values identical to before save
6. Check savegame folder for `soilData.xml`
7. Verify: File exists and contains field data

**Test: Settings Persistence**
1. Change difficulty to Hardcore
2. Disable rain effects
3. Change HUD position to Bottom Left
4. Save and exit
5. Reload savegame
6. Verify: All settings preserved

---

### 5. Mod Compatibility

**Test: Precision Farming Compatibility**
1. Install Precision Farming mod
2. Load savegame with both mods
3. Check log: Should see "Precision Farming detected - entering read-only mode"
4. Verify: Soil settings disabled (PF takes over)
5. Verify: No conflicts, both mods work

**Test: Multiple Mods**
1. Load with other popular mods (Courseplay, AutoDrive, etc.)
2. Verify: No errors in log
3. Verify: HUD doesn't overlap with other mod UIs
4. Adjust HUD position if needed

---

### 6. Settings & Console Commands

**Test: Difficulty Levels**
- `SoilSetDifficulty 1` (Simple) → Verify: Less nutrient depletion
- `SoilSetDifficulty 2` (Realistic) → Verify: Normal depletion
- `SoilSetDifficulty 3` (Hardcore) → Verify: Faster depletion

**Test: Feature Toggles**
- `SoilSetNutrients false` → Verify: No depletion on harvest
- `SoilSetSeasonalEffects false` → Verify: No seasonal changes
- `SoilSetRainEffects false` → Verify: Rain doesn't affect nutrients
- Re-enable all, verify normal behavior returns

**Test: Debug Mode**
- `SoilDebug` → Verify: Detailed logging in console/log file
- Harvest field → Verify: Debug messages appear
- `SoilDebug` again → Verify: Debug logging stops

**Test: Reset Settings**
- Change multiple settings
- `SoilResetSettings`
- Verify: All settings return to defaults

---

## Regression Test Checklist

Use this checklist before releasing a new version:

### Critical Functionality
- [ ] Mod loads without errors
- [ ] Fields initialize with valid data
- [ ] Harvest depletes nutrients
- [ ] Fertilizer restores nutrients
- [ ] Plowing applies bonus
- [ ] Save/load preserves data
- [ ] Multiplayer sync works
- [ ] Admin controls enforced in MP

### UI/HUD
- [ ] HUD appears in fields
- [ ] F8 toggles HUD on/off
- [ ] HUD position presets work
- [ ] HUD hides in menus/map
- [ ] HUD hides in construction mode
- [ ] Show HUD setting works

### Settings
- [ ] All settings save/load correctly
- [ ] Difficulty changes affect depletion rate
- [ ] Feature toggles work (nutrients, seasonal, rain)
- [ ] Debug mode enables/disables logging
- [ ] Reset settings works

### Console Commands
- [ ] `soilfertility` shows command list
- [ ] `SoilFieldInfo <id>` shows field data
- [ ] All toggle commands work
- [ ] Admin-only commands enforced in MP

### Compatibility
- [ ] Works with Precision Farming (read-only mode)
- [ ] No conflicts with popular mods
- [ ] HUD doesn't overlap other UIs

---

## Known Edge Cases

### Field Detection Edge Cases
- **Multiple fields on one farmland**: HUD uses precise position detection
- **Player on farmland boundary**: May flicker between fields
- **Vehicle partially in/out of field**: Shows field where vehicle center is

### Multiplayer Edge Cases
- **Client joins during harvest**: Sync happens after harvest completes
- **Server crashes**: Data saved on last auto-save, may lose recent changes
- **Network lag**: Sync retries up to 3 times with 5-second intervals

### Save/Load Edge Cases
- **Save during harvest**: Harvested nutrients reflected in save
- **Corrupted save file**: Mod falls back to defaults, logs warning
- **Missing soilData.xml**: Normal, uses defaults for new savegames

---

## Performance Verification

### Frame Rate Impact
- **Expected**: <1% CPU usage in normal gameplay
- **HUD rendering**: ~0.1ms per frame
- **Update loop**: Runs every 30 seconds, negligible impact

### Memory Usage
- **Expected**: ~5-10 MB for typical 20-field map
- **Per field**: ~1-2 KB of data
- **Network traffic**: Minimal, only syncs on changes

### Log File Size
- **Normal mode**: <100 lines of [SoilFertilizer] logs per session
- **Debug mode**: Can be verbose, disable for normal play

---

## Common Issues & Solutions

### HUD Not Appearing
1. Check: Mod enabled? `SoilEnable`
2. Check: Show HUD enabled in settings?
3. Check: Standing in a valid field?
4. Check: F8 toggle state (press to toggle on)
5. Check: Not in construction/tutorial mode?

### Nutrients Not Changing
1. Check: Nutrient cycles enabled? `SoilSetNutrients true`
2. Check: Mod enabled? `SoilEnable`
3. Check: Precision Farming installed? (PF overrides this mod)
4. Check: Difficulty set to Simple? (slower depletion)

### Multiplayer Sync Issues
1. Check log: "Full sync completed"?
2. Wait 15 seconds (3 retries × 5 seconds)
3. If still failing, client should rejoin
4. Check: Firewall blocking FS25?

### Settings Not Saving
1. Check: savegameDirectory writable?
2. Check: Disk space available?
3. Check log for XML save errors
4. Try: `SoilSaveData` to force save

---

## Reporting Bugs

When reporting bugs, include:

1. **FS25 Version**: (e.g., 1.2.0.0)
2. **Mod Version**: (check modDesc.xml)
3. **Log File**: Full `log.txt` from `Documents\My Games\FarmingSimulator2025\`
4. **Steps to Reproduce**: Exact steps that cause the issue
5. **Expected vs Actual**: What should happen vs what does happen
6. **Other Mods**: List all active mods
7. **Savegame**: If possible, provide savegame that reproduces issue

---

## Testing Best Practices

1. **Test in clean environment**: New savegame, minimal other mods
2. **Test multiplayer**: Both as host and client
3. **Test with Precision Farming**: Ensure read-only mode works
4. **Check logs**: No errors or warnings
5. **Test edge cases**: Boundary conditions, rapid actions, network lag
6. **Performance test**: No frame drops, smooth HUD rendering

---

**Happy Testing!** 🎮🌾
