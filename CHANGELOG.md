# Changelog

All notable changes to FS25_SoilFertilizer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.4.6.0] - 2026-04-06

### Fixed

- **Soil HUD showing wrong or stale crop name (issue #123)**: The HUD was displaying
  the crop from a previous harvest (e.g. "Oat" from 3-4 harvests ago) or showing
  "Fallow" even when a live crop was growing. Root cause: `SoilFertilitySystem:getFieldInfo()`
  called `fsField:getFieldState()`, which **does not exist in FS25**. `FieldState` is a
  standalone class that must be instantiated with `FieldState.new()` and populated via
  `fieldState:update(centerX, centerZ)`. The silent `pcall` failure meant live crop
  detection always fell through to the stale `field.lastCrop` value.

  Fix 1 (`SoilFertilitySystem.lua`): Replace the non-existent `getFieldState()` call with
  the correct `FieldState.new()` + `:update(fsField.posX, fsField.posZ)` pattern.

  Fix 2 (`HookManager.lua`): Add `installSowingHook()` on `SowingMachine.processSowingMachineArea`
  to clear `field.lastCrop = nil` whenever seeds are planted. This prevents the previous
  harvest's crop from showing during the gap between sowing and the next FieldState poll,
  and ensures "Fallow" is only shown on genuinely bare/cultivated ground.

---

## [1.4.5.0] - 2026-04-06

### Fixed

- **Herbicide / insecticide / fungicide instantly resetting pressure to 0% from any dose**
  (issue #121): The crop protection hook fired on every game frame (~60×/sec) while the
  sprayer was active. Each frame applied the full `HERBICIDE_PRESSURE_REDUCTION` (30 pts),
  `INSECTICIDE_PRESSURE_REDUCTION` (25 pts), or `FUNGICIDE_PRESSURE_REDUCTION` (20 pts),
  meaning a single pass across a field applied the reduction hundreds of times and drove
  weed / pest / disease pressure to zero regardless of how much product was actually used.

  Fixed with a **per-field, per-day throttle**: each of `onHerbicideApplied`,
  `onInsecticideApplied`, and `onFungicideApplied` now records the in-game day of the last
  application per field (`herbicideAppliedDay`, `insecticideAppliedDay`, `fungicideAppliedDay`
  tables on `SoilFertilitySystem`) and exits immediately if it has already fired today for
  that field. One application event per field per in-game day — consistent with the existing
  `fertNotifyShown` pattern used for NPK notifications.

- **Double-application of INSECTICIDE / FUNGICIDE crop protection** (related to #121): Both
  fill types are declared in `FERTILIZER_PROFILES` with `pestReduction` / `diseaseReduction`
  markers, causing `applyFertilizer` to route them to `onInsecticideApplied` /
  `onFungicideApplied` internally. The hook additionally called those same functions directly
  via the `pestEffectiveness` / `diseaseEffectiveness` path — a second application in the same
  frame. Fixed by only using the direct path for products that are **not** in
  `FERTILIZER_PROFILES` (e.g. vanilla `HERBICIDE` / `PESTICIDE` fill types with no profile
  entry). Profile-based products are handled exclusively through `applyFertilizer`.

---

## [1.4.4.0] - 2026-04-06

### Fixed

- **NPK not increasing after field scan with any fertilizer** (critical): The sprayer hook was
  gated on `spec.workAreaParameters.isActive`, which FS25 only sets `true` when the vanilla
  density map pixel actually changes. Fields already fully fertilised in the base-game system
  return `changedArea = 0`, so `isActive` stayed `false` and every fertiliser application was
  silently skipped — nutrients never changed. Fixed by replacing the `isActive` guard with a
  check on `sprayFillLevel > 0` and `usage > 0`: if the sprayer has product and consumed some
  this frame, the nutrient application is now always recorded regardless of vanilla terrain state.

- **`getDifficultyName()` crash on MP client sync** (Bug #3): On full-sync receive, the settings
  object is a plain Lua table populated field-by-field from the network stream — not a `Settings`
  class instance. Calling `:getDifficultyName()` on it threw `attempt to call a nil value`.
  Replaced with an inline `diffNames[]` table lookup. Also converted the surrounding `print()`
  to `SoilLogger.info()`.

- **`g_currentMission` nil crash in daily soil update** (Bug #8): Seasonal effects block accessed
  `g_currentMission.environment` without first guarding `g_currentMission` itself. Added the
  missing nil check — safe on dedicated server shutdown and level reload.

- **Stale full-sync retry handler after level reload** (Bug #10): The module-level
  `fullSyncRetryHandler` persisted across level reloads in its `success` or `failed` state.
  A reconnecting MP client would call `start()` on a completed handler, which guards on
  `state == "pending"` and is a no-op — the client never re-synced. Fixed by calling
  `reset()` before `start()` in `SoilNetworkEvents_RequestFullSync()`.

- **`math.randomseed()` polluting global PRNG during bulk field scan** (Bug #13): Calling
  `math.randomseed(fieldId * 67890)` on every lazy field creation resets the shared Lua random
  state. During the initial scan many fields are created in the same frame, each overwriting the
  previous seed before its random numbers are drawn. Replaced with a Lua 5.1-compatible
  deterministic LCG hash that produces stable, per-nutrient variation for each field without
  touching the global PRNG.

- **`listAllFields()` always printing `"?"` for FieldManager field IDs** (Bug #27): The function
  used `field.fieldId` which is always `nil` in FS25. Fixed to use `field.farmland.id`, consistent
  with the rest of the codebase. Converted all `print()` calls in the function to `SoilLogger`.

- **DIAG / debug `print()` calls spamming the log in production** (Bug #26): Several raw
  `print("[SoilFertilizer DIAG] ...")` calls in `SoilHUD`, `SoilReportDialog`,
  `SoilFertilityManager`, and `SoilFertilitySystem` fired unconditionally for every player in
  every session. Replaced with `SoilLogger.debug()` / `.warning()` / `.error()` so they are
  gated behind `debugMode` and go through the centralised logger.

---

## [1.4.3.0] - 2026-04-05

### Fixed

- Remaining 10000L changed to 1000L
- Improved (extended) pest duration and added to correct hook
- Cleaned modDesc (& becomes &amp;)


---

## [1.4.2.0] - 2026-04-04

### Fixed

- **Missing text entries and declaration in registerCustomSprayTypes**: Both new added types where missing their title entry. They are also added into `constants` and declared propperly.

---

## [1.4.1.0] - 2026-04-04

### Added

- **Purchasable big bags for Insecticide and Fungicide**: Both crop protection products are now available as 10,000 L big bags in the shop (same system as all other custom fertilizer types). Insecticide: $1,200/bag; Fungicide: $1,300/bag. Multi-buy available up to 8 bags at a time.

---

## [1.4.0.0] - 2026-04-04

### Added

- **Field Health System — Pest & Disease Pressure**: Two new per-field pressure scores (0–100) join the existing weed pressure system, each independently toggleable in settings.

  | Pressure | Max Yield Penalty | Controlled by | Resets via |
  |----------|-------------------|---------------|------------|
  | **Pest** | −20% | `INSECTICIDE` spray | Harvest event |
  | **Disease** | −25% | `FUNGICIDE` spray | Dry weather (3+ days) |

  Both grow daily with seasonal multipliers (pests peak in summer; disease peaks in spring and fall). Crop susceptibility varies by type — potatoes and canola are most vulnerable. Rain accelerates both. Active protection suppresses regrowth for 10–12 days after application.

- **Two new fill types**: `INSECTICIDE` (liquid, $1.20/L) and `FUNGICIDE` (liquid, $1.30/L), registered in `fillTypes.xml` and accepted by any liquid sprayer. Crop protection products are routed through the sprayer hook alongside fertilizers — they reduce pressure but do not add N/P/K.

- **Settings**: `Pest Pressure` and `Disease Pressure` toggles added to the mod settings page (default on). Both are server-authoritative in multiplayer and fully synced to joining clients.

- **HUD**: Pest and disease pressure rows appear below weed pressure when the respective settings are enabled, using the same colour tiers (green/amber/red).

- **Soil Report**: Pest and disease alerts added to the per-field report — flagged when pressure exceeds the medium threshold.

- **Save/load**: `pestPressure`, `diseasePressure`, `insecticideDaysLeft`, `fungicideDaysLeft`, and `dryDayCount` persisted per field in `soilData.xml`. Backward-compatible — old saves load cleanly with all new values defaulting to 0.

- **Multiplayer**: `SoilFullSyncEvent` and `SoilFieldUpdateEvent` extended with pest and disease fields. Stream symmetry preserved.

---

## [1.3.3.0] - 2026-04-04

### Fixed

- **Settings page showing raw key names instead of translated text**: All UI text lookups now correctly use the mod-scoped i18n instance. Root cause: `g_currentModName` is only valid at mod load time, not at UI construction time. The mod name is now captured in a local variable (`SF_MOD_NAME`) at file load time and used in all translation lookups across `SoilSettingsUI`, `SoilReportDialog`, and `UIHelper`. Affected 1.3.2.0 users on all languages.

---

## [1.3.2.0] - 2026-04-04

### Fixed

- **Sprayer visuals for custom fill types**: Custom fertilizers (UAN32, UAN28, Anhydrous, Starter, UREA, AMS, MAP, DAP, Potash) now correctly show spray/spread effects on all sprayer and spreader types, including PF-modded equipment. Root cause: vanilla runtime checks inside `Sprayer.onEndWorkAreaProcessing` compared against hardcoded `FillType`/`SprayType` constants, which never matched our custom indices. Fix wraps the function with a temporary global table swap (pattern identified from community testing) so all vanilla checks transparently pass for our fill types — originals are restored immediately after the call.

- **Save data not written on first career start**: `loadSoilData()` was called in the `SoilFertilityManager` constructor before `savegameDirectory` was set by the game engine. Moved to `deferredSoilSystemInit()` which runs after the mission info is fully populated.

- **Multiplayer clients never received full soil state on join**: `SoilNetworkEvents_RequestFullSync()` was implemented but never called. Now triggered in `loadedMission()` for MP clients, with the existing 3-attempt retry handler backing it.

- **Precision Farming compatibility mode removed**: The PF read-only mode was causing field data to silently disappear on servers with PF installed. Both mods now run fully independently. PF users retain their own soil maps; our mod tracks NPK/OM/pH separately.

- **fillTypeCategory name collision**: Categories named `FERTILIZER` and `LIQUIDFERTILIZER` conflicted with vanilla entries. Renamed to `SPREADER` and `SPRAYER`.

### Thanks

Special thanks to **seb** from the FS25 Modding Community Discord for testing and identifying the spray effects solution.

---

## [1.1.4.0] - 2026-03-15

### Added

- **Auto-Rate Control**: Sprayers and spreaders can now automatically adjust application rates based on field nutrient gaps (Alt+Z).
- **Gypsum Support**: Added Gypsum fertilizer type with pH stabilization and organic matter benefits.
- **Enhanced HUD**: Updated sprayer rate panel to show AUTO status and target nutrients.

## [1.0.7.1] - 2026-02-21

### Fixed

#### No field data on dedicated servers with Precision Farming (Issue #40)

- **FIXED**: `checkPFCompatibility` no longer blindly enables read-only mode when Precision Farming is detected
  - Now performs a second step probing the PF API (`g_precisionFarming.fieldData` / `soilMap:getFieldData`) before committing
  - On dedicated servers the PF global exists but its field data API is unpopulated at mod-init time — the mod previously entered a silent broken read-only state as a result
  - If the API is unreachable, logs a warning and falls back to independent mode so field data is written and synced normally
  - Log message: `[SoilFertilizer WARNING] Precision Farming detected but API not accessible (dedicated server / load-order issue) - falling back to independent mode`

- **FIXED**: Clients on dedicated servers never received initial field data
  - Field data was previously only broadcast to clients on harvest or fertilizer events
  - On a freshly loaded server with no activity, clients had empty field tables for the entire session
  - `scanFields` now calls new `broadcastAllFieldData()` immediately after a successful scan
  - `loadFromXMLFile` also calls `broadcastAllFieldData()` after load to re-sync clients following a save/load cycle

- **ADDED**: `broadcastAllFieldData()` — iterates all tracked fields and broadcasts each to every connected client via `SoilFieldUpdateEvent`

- **ADDED**: `onClientJoined(connection)` — sends full field state to a single newly-joined client; must be wired into the multiplayer connection-accepted handler (follow-up required)

- **FIXED**: Field ID resolution priority in `scanFields` corrected
  - Previous priority: `field.fieldId` → loop key → `field.id` → `field.index`
  - Corrected priority: `field.fieldId` → `field.id` → `field.index` → loop key (last resort)
  - The loop key is an internal table index that does not reliably match the in-game field ID on all maps, causing data to be stored and looked up under the wrong key

- **FIXED**: `hasFarmland` check in `scanFields` no longer gates field initialization
  - Unowned fields are valid and must be tracked so data is ready when ownership is later assigned via `onFieldOwnershipChanged`

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

---

## [2.0.0] - 2025-02-22

### 🚀 **MAJOR: Enterprise-Grade Reliability & Monitoring**

This release transforms the mod into an enterprise-grade system with comprehensive reliability features, advanced monitoring, and Google-style SRE patterns.

#### **Added**

##### **Core Enterprise Features**
- **Circuit Breaker Pattern** - Prevents cascading failures with automatic recovery
- **Advanced Health Monitoring** - Real-time system health checks with configurable thresholds
- **Performance Monitoring** - Comprehensive metrics collection and SLI/SLO tracking
- **Client Connection Tracking** - Enhanced multiplayer connection management
- **Bandwidth Optimization** - Field data compression and intelligent batching
- **Predictive Loading** - Proximity-based field data loading for better performance
- **Memory Management** - Automatic cleanup and leak detection
- **Error Recovery Mechanisms** - Automated failure recovery and graceful degradation

##### **Enhanced Network Features**
- **Compressed Field Data** - 50% bandwidth reduction for large maps
- **Intelligent Caching** - TTL-based field data caching with compression
- **Enhanced Multiplayer Sync** - Improved client join handling and data synchronization
- **Network Reliability Monitoring** - Circuit breaker integration for network operations
- **Bandwidth Limiting** - Configurable bandwidth usage limits
- **Retry Logic** - Exponential backoff with circuit breaker protection

##### **Monitoring & Observability**
- **Service Level Indicators (SLIs)** - Availability, latency, throughput, error rate tracking
- **Service Level Objectives (SLOs)** - 99% availability, 500ms P95 latency targets
- **Health Check System** - 5-category health monitoring (System, Field Data, Network, Memory, Performance)
- **Performance Metrics** - Latency tracking, bandwidth usage, success rate monitoring
- **Alert System** - Configurable alert thresholds with cooldown periods
- **Detailed Logging** - Enhanced structured logging with severity levels

##### **Enterprise Configuration**
- **SRE-Style Configuration** - Google-style reliability patterns and thresholds
- **Circuit Breaker Settings** - Configurable failure thresholds and recovery timeouts
- **Health Monitoring Settings** - Check intervals, alert thresholds, critical failure counts
- **Network Optimization Settings** - Compression, bandwidth limits, batch sizes
- **Memory Management Settings** - GC thresholds, cache cleanup, field count limits
- **Performance Monitoring Settings** - Metrics retention, alert cooldowns, SLA targets

##### **New Console Commands**
```bash
# Health monitoring
soilfertility health          # Show current health status
soilfertility health reset    # Reset health metrics
soilfertility health report   # Detailed health report

# Performance monitoring
soilfertility metrics         # Show performance metrics
soilfertility network         # Show network status

# Circuit breaker control
soilfertility circuit status  # Check circuit breaker status
soilfertility circuit reset   # Reset circuit breaker

# Field data management
soilfertility fields list     # List all tracked fields
soilfertility fields sync     # Force field data sync
```

##### **Enhanced Documentation**
- **Integration Guide** - Complete guide for integrating enterprise features
- **Implementation Summary** - Technical details of enterprise-grade patterns
- **Configuration Reference** - Comprehensive configuration options documentation

#### **Changed**

##### **Core System Architecture**
- **Enhanced SoilFertilitySystem** - Added enterprise-grade reliability features
- **Enhanced SoilFertilityManager** - Integrated health monitoring and performance tracking
- **Enhanced NetworkEvents** - Improved with circuit breaker and compression
- **Enhanced Constants** - Extended with enterprise configuration options

##### **Error Handling**
- **Graceful Degradation** - System continues operating with reduced functionality during failures
- **Exponential Backoff** - Improved retry logic for network operations
- **Circuit Breaker Integration** - All network operations now use circuit breaker pattern
- **Enhanced Error Recovery** - Automated recovery mechanisms with configurable strategies

##### **Performance Improvements**
- **Predictive Loading** - Load field data based on player proximity
- **Bandwidth Optimization** - Reduced network traffic for large maps
- **Memory Management** - Automatic cleanup and leak detection
- **Caching Strategy** - Intelligent field data caching with compression

#### **Fixed**

##### **Multiplayer Stability**
- **Network Failure Handling** - Circuit breaker prevents cascading failures
- **Client Connection Management** - Enhanced tracking and graceful disconnection
- **Field Data Synchronization** - Improved reliability with compression and retry logic
- **Dedicated Server Support** - Optimized for server performance and stability

##### **Large Map Performance**
- **Bandwidth Optimization** - Reduced network load for maps with 100+ fields
- **Memory Usage** - Automatic cleanup prevents memory leaks
- **Loading Performance** - Predictive loading reduces latency
- **Field Data Management** - Efficient handling of large field datasets

#### **Security**

##### **Enhanced Security Features**
- **Input Validation** - Enhanced validation for all network data
- **Error Sanitization** - Prevents information leakage in error messages
- **Circuit Breaker Security** - Prevents resource exhaustion attacks
- **Memory Protection** - Prevents memory leaks and excessive usage

#### **Dependencies**

##### **Enhanced Dependencies**
- **AsyncRetryHandler** - Enhanced with circuit breaker integration
- **Logger** - Extended with structured logging and performance tracking
- **HookManager** - Improved with enterprise-grade reliability patterns