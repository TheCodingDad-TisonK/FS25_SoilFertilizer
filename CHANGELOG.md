# Changelog

All notable changes to FS25_SoilFertilizer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.7.0] - 2026-02-18

### Changed

#### SoilHUD — Converted to Legend/Reference Panel
- **CHANGED**: `SoilHUD` is now a static **legend/reference panel** instead of a live per-field data display
  - The full-detail field view is now properly served by the Soil Report dialog (K key)
  - The HUD no longer needs player position, farmland detection, or field polling each frame
  - Eliminates all timing-sensitive field-detection code that could crash or return stale data

#### New HUD Content
- **Keys section**: `J = Toggle HUD` and `K = Soil Report` always visible for discoverability
- **Color-coded nutrient legend**: Good / Fair / Poor thresholds (N>50/P>45/K>40, N>30/P>25/K>20) matching `STATUS_THRESHOLDS` in Constants exactly
- **pH reference**: `pH ideal: 6.5 - 7.0` as a quick agronomic reminder

#### Code Cleanup (`src/ui/SoilHUD.lua`)
- **REMOVED**: `getCurrentPosition()` — position detection no longer needed
- **REMOVED**: `getFarmlandIdAtPosition()` — farmland lookup no longer needed
- **REMOVED**: `findFieldAtPosition()` with 3-tier field detection fallback — no longer needed
- **SIMPLIFIED**: `draw()` reduced to basic visibility guards only (no player/vehicle checks)
- **SIMPLIFIED**: `drawPanel()` is now a pure static renderer — no field data, no PF integration, no farmland fallback logic
- File reduced from 719 lines to 202 lines

### Fixed
- **FIXED**: `self:getActionName("SF_SOIL_REPORT")` call in `drawPanel()` that would have caused a runtime error (method did not exist on SoilHUD)

---

## [1.0.6.5] - 2026-02-17

### Summary
Polish pass by XelaNull (PR #33). Localization improvements, dialog stacking fixes, pagination cleanup, and mod compatibility corrections.

### Fixed
- Mod compatibility: settings tab integration, J-key binding race condition, slow-server field initialization (Issue #21)
- Settings corruption on dedicated servers with 100+ mods loaded

### Changed
- Localization string improvements across all 10 supported languages
- Dialog stacking and close-order correctness for `SoilReportDialog`
- Pagination layout and display for the Soil Report

---

## [1.0.6.0] - 2026-02-16

### Changed
- Version bump to 1.0.6.0 consolidating v1.0.5.x hotfixes as stable baseline

### Fixed
- Settings corruption when 100+ mods are loaded on dedicated servers

---

## [1.0.5.2] - 2026-02-16

### Fixed
- Settings UI corruption on dedicated server clients

---

## [1.0.5.1] - 2026-02-16

### Fixed
- 6 critical HUD and multiplayer issues identified post-1.0.5.0 release

### Changed
- Improved HUD field detection accuracy
- Added status-enriched (color-coded Good/Fair/Poor) soil display in HUD

---

## [1.0.5.0] - 2026-02-16

### Summary
**Major robustness and quality improvements** based on comprehensive code audit comparing against proven NPCFavor and UsedPlus mod patterns. All changes are **backwards compatible** - existing savegames will work without modification.

**13 issues fixed**: 1 HIGH severity (crash prevention), 6 MEDIUM severity (robustness), 6 LOW severity (code quality)

### Added

#### Console Commands
- **NEW**: `SoilListFields` - List all tracked fields with soil data and compare against FieldManager
  - Useful for debugging field initialization issues
  - Displays N/P/K/pH/OM values for all fields

#### Constants
- **NEW**: `SoilConstants.PLOWING` section with `MIN_DEPTH_FOR_PLOWING` constant
  - Replaced magic number (0.15) with documented constant
  - Improves maintainability for plowing depth threshold

### Changed

#### Critical Crash Prevention (HIGH Severity)
- **FIXED**: Replaced all `assert()` calls with graceful error handling + user dialogs
  - Prevents game crashes if modules fail to load
  - Shows informative dialogs to players: "Soil & Fertilizer Mod failed to load..."
  - Mod degrades gracefully instead of crashing entire game
  - Affected: `SoilFertilityManager.lua` (3 locations)

#### Robustness Improvements (MEDIUM Severity)
- **FIXED**: Added nil validation to plowing hook `workArea` parameter
  - Prevents crash from nil workArea in cultivator operations
  - Validates array structure before access
  - Affected: `HookManager.lua` line 267

- **FIXED**: Wrapped all Logger `string.format()` calls in `pcall()` with fallback
  - Prevents crashes from mismatched format arguments
  - Falls back to `tostring()` if format fails
  - Adopted NPCFavor proven pattern
  - Affected: `Logger.lua` (all 4 functions: debug, info, warning, error)

- **FIXED**: Added defensive nil checks to HUD `fieldInfo` access
  - Prevents crash from nil fieldInfo in edge cases
  - Shows "Initializing..." message gracefully
  - Affected: `SoilHUD.lua` lines 622-625

- **FIXED**: Network corruption detection and sanitization for multiplayer field data
  - Validates all incoming network data (N/P/K/OM/pH, lastHarvest, fertilizerApplied)
  - Detects NaN, negative values, out-of-range values
  - Logs warnings: "Corrupt MP data: Field X nitrogen out of range... clamping"
  - Shows user notification: "Soil Mod: Data sync issue detected. Please report if this persists."
  - Sanitizes corrupt data to safe defaults before applying
  - Affected: `NetworkEvents.lua` SoilFullSyncEvent:readStream()

- **FIXED**: 3-tier field scan retry with frame-based fallback and graceful failure
  - **Tier 1**: Time-based retry (10 attempts, 2 sec intervals) - existing system
  - **Tier 2**: Frame-based fallback (600 frames = ~10 sec) - NEW
    - Triggers if `g_currentMission.time` is frozen
    - Shows notification: "Field initialization delayed. Trying alternative method..."
    - Shows success notification: "Field initialization successful!" if recovery works
  - **Tier 3**: Graceful failure - NEW
    - Dialog: "Could not initialize fields... The mod has been disabled for this session only. Please restart the game to try again."
    - Disables mod for current session (non-persistent)
    - Mod re-enables automatically on next launch
  - Affected: `SoilFertilitySystem.lua` initialization + update loop

- **FIXED**: Settings validation now rejects unknown settings (fail-secure pattern)
  - `SettingsSchema.validate()` returns `nil` for unknown settings instead of passing through
  - Logs rejection: "Validation rejected unknown setting: XYZ"
  - Prevents future code from accidentally accepting invalid settings
  - Affected: `SettingsSchema.lua`, validation flow

#### Code Quality (LOW Severity)
- **FIXED**: HUD color theme bounds validation
  - Clamps `hudColorTheme` to range 1-4
  - Logs warnings for out-of-bounds values
  - Falls back to theme 1 if invalid
  - Affected: `SoilHUD.lua` line 391

- **IMPROVED**: Hook-level debug logging consistency
  - Added debug logging to fertilizer hook (matches harvest hook pattern)
  - Both hooks now log: "Hook triggered: Field X, ..."
  - Helps diagnose hook execution issues
  - Affected: `HookManager.lua` harvest + fertilizer hooks

- **IMPROVED**: Network value clamping on read (NPCFavor pattern)
  - Added `math.max`/`min` clamping to all network reads
  - Clamps to `SoilConstants.NUTRIENT_LIMITS` ranges
  - Applied to both `SoilFullSyncEvent` AND `SoilFieldUpdateEvent`
  - Double layer of protection: clamp on read (network) + validate on apply (settings)
  - Affected: `NetworkEvents.lua` (2 event classes)

### Developer Notes
- **Testing Time**: ~4 hours comprehensive, ~1 hour critical path (see `TESTING_CHECKLIST_v1.0.5.md`)
- **Code Changes**: 9 files modified, ~300 lines added/modified
- **Patterns Adopted**: NPCFavor pcall wrapping, network clamping, field retry with exponential backoff
- **Breaking Changes**: None - fully backwards compatible

---

## [1.0.4.1] - 2026-02-15

### Fixed
- Hook installation timing issue causing 3 of 5 hooks to fail
- Improved deferred initialization using mission updateables
- Field scan retry mechanism for delayed FieldManager availability

---

## [1.0.4.0] - 2026-02-14

### Fixed
- Multiplayer sync improvements
- HUD visibility feedback enhancement
- Precision Farming integration improvements
- Critical gameplay balance and UX issues

---

## [1.0.3.0] - 2026-02-13

### Fixed
- HUD overlay rendering issues

---

## [1.0.2.0] - 2026-02-12

### Added
- Initial multiplayer support
- Admin-only settings enforcement
- Field ownership change handling

### Changed
- Improved settings persistence
- Enhanced compatibility system

---

## [1.0.1.0] - 2026-02-11

### Added
- Console commands for all settings
- Field info console command
- Debug mode toggle

### Fixed
- Settings validation edge cases
- HUD positioning issues

---

## [1.0.0.0] - 2026-02-10

### Added
- Initial release
- Core soil nutrient tracking (N/P/K/OM/pH)
- Crop-specific depletion on harvest
- Fertilizer type profiles (liquid, solid, manure, slurry, digestate, lime)
- Weather effects (rain leaching)
- Seasonal effects (spring nitrogen boost, fall nitrogen loss)
- Plowing bonus for organic matter
- Difficulty levels (Simple/Realistic/Hardcore)
- In-game HUD with customization (position, color, font, transparency)
- Settings GUI integration
- 10-language localization (en, de, fr, pl, es, it, cz, br, uk, ru)
- Precision Farming compatibility (read-only mode)
- Save/load persistence
- Console commands

---

## Version Numbering

Format: `MAJOR.MINOR.PATCH.HOTFIX`

- **MAJOR**: Breaking changes, major feature additions
- **MINOR**: New features, significant changes (backwards compatible)
- **PATCH**: Bug fixes, minor improvements
- **HOTFIX**: Critical fixes between patches

---

*For detailed testing procedures, see `TESTING_CHECKLIST_v1.0.5.md`*
