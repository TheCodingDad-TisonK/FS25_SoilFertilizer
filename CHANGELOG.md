# Changelog

All notable changes to FS25_SoilFertilizer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.6.0.0] - 2026-04-10

### Added

- **Crop rotation tracking** (issue #132): Each field now tracks the last 3 harvested crops
  (`lastCrop`, `lastCrop2`, `lastCrop3`). On harvest the history shifts automatically so the
  full 3-season sequence is always available. History is saved to `soilData.xml` and synced
  to all clients in multiplayer.

- **Rotation bonus**: When a legume (soybean, peas, or beans) follows a non-legume in the
  previous season, the field receives +0.5 N per day for the first 3 days of spring, modelling
  nitrogen fixation carry-over. The counter is saved and survives mid-spring save/reload.

- **Mono-crop fatigue multiplier**: When the same crop is harvested two seasons running, all
  nutrient extraction rates are multiplied by 1.15× — an extra 15% depletion for that harvest
  to represent diminishing returns from repeated cropping. Does not stack beyond 2 seasons.

- **Crop rotation status in the Soil Report**: The per-field recommendation panel now shows one
  of three rotation status strings alongside the nutrient advice: *Rotation Bonus* (legume bonus
  active), *Fatigue: Same Crop* (mono-crop penalty in effect), or *Rotation: OK* (healthy
  alternation, no effect either way).

- **Crop Rotation toggle**: New server-authoritative setting in the mod settings panel. When
  disabled, no bonus or fatigue fires but the crop history is still recorded so turning it back
  on takes effect immediately.

- **Six new purchasable fertilizer fill types** (issue #133): GYPSUM, COMPOST, BIOSOLIDS,
  CHICKEN_MANURE, PELLETIZED_MANURE, and LIQUIDLIME are now formally registered in
  `fillTypes.xml`. They appear in the price table, are added to the SPREADER and SPRAYER fill
  type categories, and are routed through the nutrient hook with their pre-existing profiles.
  Note: big bag shop objects for the new organic types are planned for a future patch.

- **Liquid equivalents for all custom fertilizer types** (#137): Added LIQUID_UREA, LIQUID_AMS,
  LIQUID_MAP, LIQUID_DAP, and LIQUID_POTASH to support sprayer application, with big bags and
  BUY-mode support.

### Fixed

- **Pressure values displayed as 4-digit percentages in Soil Report**: Weed, pest, and disease
  pressure are stored internally as 0–100. The report dialog was multiplying them by 100 again,
  producing values like "6500%" and always rendering red status regardless of actual severity.
  Fixed in table rows and in the detail view. *(Silent bug — only visible when any pressure > 0.)*

- **Overall status badge ignores pH, OM, and bio-pressures**: The "Good / Fair / Poor" status
  shown in the Soil Report table and the HUD title bar only considered N/P/K. A field with poor
  pH, low organic matter, or high weed/pest/disease pressure could still show "Good". Now all
  five soil parameters plus all three pressure scores are included in the worst-case ranking.

- **Farm Health % uses uneven scoring weights**: Farm Health was calculated using 100 / 55 / 10
  for Good / Fair / Poor. The non-linear gap between Fair (55) and Poor (10) made the percentage
  drop unnaturally sharp. Changed to 100 / 50 / 0 — a clean linear scale.

### Improved

- **Soil Report detail view fully localized**: Several status labels in the field detail panel
  were hardcoded English strings. All replaced with `tr()` calls backed by new i18n keys.

- **Weed/pest/disease HUD rows extracted to `drawPressureRow()` helper**: Removed ~60 lines
  of duplication; color scale simplified to 3 levels to match N/P/K bars.

---

## [1.5.1.0] - 2026-04-09

### Fixed

- **HUD text missing in 24 languages (issue #130)**: The HUD overlay was showing raw
  translation key names (`sf_hud_title`, `sf_hud_fallow`, `sf_hud_yield`, etc.) for
  every language except English and Ukrainian. Root cause: 13 `sf_hud_*` keys were
  added when the live HUD was implemented but never propagated to the 24 non-EN
  language files. English text added as fallback in all 24 files — proper per-language
  translations can follow in community PRs.
  Credit: sava4903-coder for identifying this in issue #130.

- **Mouse event double-firing in vehicles (issue #130)**: The `soilMouseHandler`
  registered via `addModEventListener` was not checking the `eventUsed` flag before
  processing mouse input and was not returning it afterward. In vehicles where the
  camera or another listener had already consumed an RMB event, the HUD would still
  try to enter edit mode from a stale or mis-positioned cursor.
  Fix: `soilMouseHandler` now guards on `not eventUsed` and returns the flag.
  `SoilHUD:onMouseEvent` now accepts and returns `eventUsed`, and uses
  `Input.MOUSE_BUTTON_RIGHT` / `Input.MOUSE_BUTTON_LEFT` constants (LUADOC-verified).

---

## [1.5.0.0] - 2026-04-09

### Added

- **Yield Forecast (issue #81)**: Live yield penalty estimate now displayed in the HUD while
  standing in a field. Shows the projected harvest loss (e.g. `Yield ~-18%`) based on current
  N/P/K deficits, crop sensitivity tier, and the `YIELD_SENSITIVITY` constants. Suppressed for
  non-cropland states (fallow, grass).

- **Urgency-Based Soil Report Sorting**: The Soil Report (K key) now sorts fields by urgency
  score — a combined deficit across N/P/K/pH/weed/pest/disease (0–100). Most critical fields
  appear at the top. The yield penalty estimate is also shown in the recommendation column.

- **Critical Field Alerts**: Once per in-game year, the mod fires a notification when any
  owned field's urgency score exceeds the configured threshold. Alerts appear during spring to
  give players time to act before the growing season.

- **`SoilFieldForecast <fieldId>` console command**: Prints a detailed yield forecast for the
  specified field — projected penalty %, urgency score, crop sensitivity tier, and a text
  recommendation for which nutrients need attention most.

- **Plowing hook diagnostic logging**: The workArea nil-guard in the plowing hook now emits a
  `debug`-level log entry when it fires, making it visible under `SoilDebug` if a cultivator
  dispatches an unexpected workArea format. Aids verification under non-standard FS25 dispatch modes.

### Fixed
- **Mod Compatibility (issue #128)**: Removed the aggressive safe-mode check entirely. The
  trigger was mis-firing on harmless visual mods (tire tracks, decal placeables), causing users
  to lose all soil simulation without any real conflict present. Soil simulation now always runs.

## [1.4.9.0] - 2026-04-08

### Fixed
- **Settings UI Crash**: Fixed a game crash occurring when players attempted to reset mod settings, replacing an invalid GUI API call (`showYesNoDialog`) with the correct FS25 `YesNoDialog.show` API.
- **Field Detection Accuracy**: Improved the field ID detection from work areas by replacing the geometric center averaging with accurate parallelogram midpoint calculations.

## [1.4.8.0] - 2026-04-07

### Fixed

- **Soil Report "Syncing" timeout in multiplayer (issue #120)**: Joining clients on
  multiplayer servers would often hang on the "Syncing field ownership data..."
  screen, eventually timing out after 15s. This occurred because the ownership
  synchronization check was too restrictive, especially on maps where no land is
  owned by default (survival starts).

  Fix: Enhanced `isOwnershipSynced` in `SoilReportDialog.lua` with a multi-stage
  verification process. The sync check now correctly identifies server-sent initial
  state by verifying if *any* land on the map is owned by *any* farm. Added a
  fallback that considers sync complete once the mission is fully started or the
  game HUD is visible. Increased the sync retry window to 30s (15 attempts) for
  better reliability on heavily modded dedicated servers.

---

## [1.4.7.0] - 2026-04-07

### Fixed

- **"BUY" refill mode not working with custom fill types (issue #125)**: When the player
  (or a worker/CP) set the sprayer refill mode to "BUY", vanilla fill types
  (FERTILIZER, LIQUIDFERTILIZER) correctly charged money per liter consumed without
  depleting the physical tank. Custom types (UAN32, UAN28, ANHYDROUS, STARTER, UREA,
  AMS, MAP, DAP, POTASH, INSECTICIDE, FUNGICIDE, and organic types) still depleted the
  fill unit normally, causing workers to stop when the tank ran dry and potentially
  switch to a vanilla fertilizer type instead.

  Root cause: FS25's internal "BUY" purchase intercept only fires for fill types
  recognized by its own economy system. Custom mod fill types have `pricePerLiter`
  defined in `fillTypes.xml` but are not included in the game's purchasable-fill-type
  whitelist, so `FillUnit.addFillUnitFillLevel` never intercepts their consumption.

  Fix: Added `installPurchaseRefillHook()` in `HookManager.lua` (Hook 8). This hook
  wraps `FillUnit.addFillUnitFillLevel` and intercepts negative-delta (consumption)
  calls for custom fill types when the vehicle's fill unit is in BUY mode. When
  intercepted, it charges the owning farm `pricePerLiter × litersConsumed` via
  `g_currentMission:addMoney()` and returns `0` (no physical depletion). BUY mode is
  detected via `fillUnit.fillModeIndex == 1` (primary) and `fillUnit.reloadState > 0`
  (secondary), matching how FS25 internally signals the purchase-refill state.

  Prices used for money charge match the `economy pricePerLiter` values in
  `fillTypes.xml` and the `SoilConstants.PURCHASABLE_SINGLE_NUTRIENT` table for
  single-nutrient types (ANHYDROUS, MAP, POTASH).

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
