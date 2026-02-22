# FS25_SoilFertilizer - Developer Guide

**Version**: 1.0.7.1
**Last Updated**: 2026-02-21

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Architecture Overview](#architecture-overview)
3. [Adding New Crops](#adding-new-crops)
4. [Adding New Fertilizers](#adding-new-fertilizers)
5. [Adding New Settings](#adding-new-settings)
6. [Network Synchronization](#network-synchronization)
7. [Hook System](#hook-system)
8. [HUD System](#hud-system)
9. [Testing Your Changes](#testing-your-changes)
10. [Common Gotchas](#common-gotchas)
11. [Build & Release](#build--release)

---

## Getting Started

### Development Setup

1. **Clone Repository**
   ```bash
   git clone https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer.git
   cd FS25_SoilFertilizer
   ```

2. **Install to FS25**
   - Copy entire folder to `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\`
   - Or create symbolic link for live development

3. **Enable Developer Console**
   - Edit `game.xml` in FS25 root
   - Set `<development>` to `<controls>true</controls>`
   - Press `~` in-game to open console

4. **Enable Logging**
   - Use `SoilDebug` console command
   - Check `log.txt` in FS25 documents folder

### File Structure

```
FS25_SoilFertilizer/
├── modDesc.xml              # Mod manifest & translations
├── icon.dds                 # Mod icon
├── CLAUDE.md                # Project architecture guide
├── DEVELOPMENT.md           # This file
├── TESTING.md               # Testing procedures
├── src/
│   ├── main.lua             # Entry point & lifecycle hooks
│   ├── SoilFertilityManager.lua    # Central coordinator
│   ├── SoilFertilitySystem.lua     # Core soil simulation logic
│   ├── config/
│   │   ├── Constants.lua           # All tunable values
│   │   └── SettingsSchema.lua      # Settings definitions
│   ├── settings/
│   │   ├── Settings.lua            # Settings domain object
│   │   ├── SettingsManager.lua     # XML save/load
│   │   ├── SoilSettingsUI.lua      # In-game UI generation
│   │   └── SoilSettingsGUI.lua     # Console commands
│   ├── hooks/
│   │   └── HookManager.lua         # Game engine hooks
│   ├── network/
│   │   └── NetworkEvents.lua       # Multiplayer sync
│   ├── ui/
│   │   ├── SoilHUD.lua             # Always-on legend/reference HUD overlay
│   │   └── SoilReportDialog.lua    # Full-farm soil report dialog (K key)
│   └── utils/
│       ├── Logger.lua              # Centralized logging
│       ├── AsyncRetryHandler.lua   # Retry pattern utility
│       └── UIHelper.lua            # UI element creation
```

---

## Architecture Overview

### Module Loading Order

`main.lua` loads modules in strict dependency order (see `CLAUDE.md` for details):

1. **Utilities & Config**: Logger, Constants, SettingsSchema
2. **Core Systems**: HookManager, SoilFertilitySystem, SoilFertilityManager
3. **Settings**: SettingsManager, Settings, SoilSettingsGUI
4. **UI**: UIHelper, SoilSettingsUI, SoilHUD
5. **Network**: NetworkEvents

**Important**: Respect this order when adding new modules.

### Central Coordinator Pattern

`SoilFertilityManager` (exposed as `g_SoilFertilityManager`) owns all subsystems:

```lua
g_SoilFertilityManager
  ├── settings          : Settings instance
  ├── settingsManager   : SettingsManager instance
  ├── soilSystem        : SoilFertilitySystem instance
  ├── soilHUD           : SoilHUD instance
  └── Network events registered globally
```

### Data Flow

**Harvest Event**:
1. `FruitUtil.fruitPickupEvent` fires (FS25)
2. `HookManager` intercepts via hook
3. Calls `SoilFertilitySystem:onHarvest(fieldId, fruitType, liters)`
4. System calculates nutrient depletion
5. Updates `fieldData[fieldId]` internal state
6. If multiplayer server: broadcasts `SoilFieldUpdateEvent` to clients

---

## Adding New Crops

Crops have different nutrient extraction rates. To add a new crop:

### Step 1: Add Extraction Rates to Constants

Edit `src/config/Constants.lua`:

```lua
SoilConstants.CROP_EXTRACTION = {
    -- Existing crops...

    -- Add your new crop here
    ["yourcrop"] = {    -- Must match FS25 fruit type name (lowercase)
        N = 15,         -- Nitrogen extraction per 1000L harvested
        P = 8,          -- Phosphorus extraction
        K = 10,         -- Potassium extraction
    },
}
```

**Calibration Guidelines**:
- **High N crops**: Wheat, Barley, Corn (leafy growth) - N: 15-20
- **High P crops**: Corn, Soybeans (energy/seeds) - P: 8-12
- **High K crops**: Potatoes, Sugar Beets (roots/tubers) - K: 12-18
- **Nitrogen-fixing**: Soybeans, Peas (legumes) - N: 5-8 (they fix their own)

### Step 2: Test

1. Plant your crop in FS25
2. Note field nutrients before harvest: `SoilFieldInfo <fieldId>`
3. Harvest the crop
4. Check nutrients after: `SoilFieldInfo <fieldId>`
5. Verify depletion matches your rates × difficulty multiplier

**No code changes needed** - the system automatically picks up crops from Constants!

---

## Adding New Fertilizers

Fertilizers restore nutrients with different ratios.

### Step 1: Add Fertilizer Profile to Constants

Edit `src/config/Constants.lua`:

```lua
SoilConstants.FERTILIZER_PROFILES = {
    -- Existing fertilizers...

    -- Add your new fertilizer here
    ["YOURFERTILIZER"] = {  -- Must match FS25 fill type name (UPPERCASE)
        N = 25,             -- Nitrogen added per 1000L applied
        P = 15,             -- Phosphorus added
        K = 10,             -- Potassium added
        pH = 0,             -- pH change (positive increases, negative decreases)
        OM = 0,             -- Organic matter change
    },
}
```

**Common Fertilizer Types**:
- **Liquid Fertilizer**: High N (25-30), Moderate P/K (10-15)
- **Solid Fertilizer**: Balanced N/P/K (15-20 each)
- **Manure**: Moderate N/P/K (10-15), adds OM (0.5-1.0)
- **Slurry**: Moderate N/P/K (12-18), adds OM (0.3-0.5)
- **Digestate**: High N (20-25), moderate P/K, adds OM (0.4)
- **Lime**: No N/P/K, raises pH (+0.2 to +0.5)

### Step 2: Test

1. Note field nutrients: `SoilFieldInfo <fieldId>`
2. Apply your fertilizer in FS25
3. Check nutrients after: `SoilFieldInfo <fieldId>`
4. Verify nutrients increased by your rates

---

## Adding New Settings

The mod uses a **schema-driven settings system**. One definition in `SettingsSchema.lua` auto-generates:
- XML save/load
- Default values
- In-game UI
- Console commands
- Network sync

### Step 1: Add to SettingsSchema

Edit `src/config/SettingsSchema.lua`:

```lua
SettingsSchema.definitions = {
    -- Existing settings...

    -- Add your new setting here
    {
        id = "yourSetting",              -- Internal ID (camelCase)
        type = "boolean",                -- "boolean" or "number"
        default = true,                  -- Default value
        min = 1,                         -- (Optional) Min value for numbers
        max = 10,                        -- (Optional) Max value for numbers
        uiId = "sf_your_setting",        -- UI/translation key (snake_case)
        pfProtected = false,             -- true = disabled when Precision Farming active
    },
}
```

### Step 2: Add Translations to modDesc.xml

Edit `modDesc.xml` in the `<l10n>` section:

```xml
<!-- Short label for UI toggle -->
<text name="sf_your_setting_short">
    <en>Your Setting</en>
    <de>Deine Einstellung</de>
    <!-- ... other languages -->
</text>

<!-- Long description/tooltip -->
<text name="sf_your_setting_long">
    <en>Enable/disable your new feature</en>
    <de>Aktiviere/deaktiviere deine neue Funktion</de>
    <!-- ... other languages -->
</text>
```

**Languages**: en, de, fr, pl, es, it, cz, br, uk, ru, hu (11 total)

### Step 3: Use in Code

The setting is now automatically available:

```lua
-- Access anywhere via g_SoilFertilityManager.settings
if g_SoilFertilityManager.settings.yourSetting then
    -- Your feature code here
end
```

**That's it!** The UI, save/load, network sync, and console commands are all auto-generated.

---

## Network Synchronization

### Multiplayer Architecture

- **Server-authoritative**: Server owns soil data and settings
- **Client sync**: Clients receive updates via network events
- **Admin-only**: Only admin users can change settings

### Network Events

| Event | Direction | Purpose |
|-------|-----------|---------|
| `SoilSettingChangeEvent` | Client → Server | Request setting change (admin validated) |
| `SoilSettingSyncEvent` | Server → Clients | Broadcast setting change |
| `SoilRequestFullSyncEvent` | Client → Server | Request full state on join |
| `SoilFullSyncEvent` | Server → Client | Send all settings + field data |
| `SoilFieldUpdateEvent` | Server → Clients | Update specific field after harvest/fertilize |

### Full Sync Flow

1. Client joins server
2. Client sends `SoilRequestFullSyncEvent`
3. Server responds with `SoilFullSyncEvent` containing:
   - All settings
   - All field data
4. Client applies received data
5. If sync fails, client retries (3 attempts, 5-second intervals)

### Initial Field Data Broadcast (Dedicated Servers)

On dedicated servers, clients may join before any harvest or fertilizer events have
fired, meaning per-field `SoilFieldUpdateEvent` broadcasts never reach them. To handle
this, `SoilFertilitySystem` performs a full broadcast immediately after the field scan
completes and again after `loadFromXMLFile`:

```lua
-- Called automatically by scanFields() and loadFromXMLFile()
function SoilFertilitySystem:broadcastAllFieldData()
    if not g_server then return end
    for fieldId, field in pairs(self.fieldData) do
        g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
    end
end
```

For late-joining clients, call `SoilFertilitySystem:onClientJoined(connection)` from
your multiplayer connection-accepted handler. This sends the full field state to the
single new connection rather than broadcasting to everyone:

```lua
-- Wire this up wherever the server accepts a new player connection
g_SoilFertilityManager.soilSystem:onClientJoined(connection)
```

> **Note**: `onClientJoined` is implemented but not yet wired to a connection event.
> This is tracked as a follow-up task. The `broadcastAllFieldData` call after scan
> covers the common case of all players being present at server load.

### Precision Farming on Dedicated Servers

`checkPFCompatibility` detects PF by presence of `g_precisionFarming` or a matching
mod name, then **probes the API** before enabling read-only mode. If neither
`g_precisionFarming.fieldData` nor `soilMap:getFieldData` are accessible — which is
the case on dedicated servers where the PF global exists but is not yet populated —
the mod falls back to independent mode automatically:

```
[SoilFertilizer WARNING] Precision Farming detected but API not accessible
(dedicated server / load-order issue) - falling back to independent mode
```

This prevents the mod from entering a silent broken read-only state where no field
data is ever written or synced to clients.

### Adding New Network-Synced Data

If you need to sync new data types:

1. **Add to SoilFullSyncEvent** (`NetworkEvents.lua`):
   ```lua
   -- In writeStream:
   streamWriteString(streamId, tostring(self.yourNewData))

   -- In readStream:
   self.yourNewData = streamReadString(streamId)
   ```

2. **Broadcast changes**:
   ```lua
   if g_server and g_currentMission.missionDynamicInfo.isMultiplayer then
       g_server:broadcastEvent(YourUpdateEvent.new(data))
   end
   ```

---

## Hook System

### How Hooks Work

The mod intercepts FS25 game events using `Utils.appendedFunction`:

```lua
-- Original FS25 function
FruitUtil.fruitPickupEvent = function(...)
    -- FS25's original code runs first
end

-- Our hook wraps it
FruitUtil.fruitPickupEvent = Utils.appendedFunction(
    FruitUtil.fruitPickupEvent,  -- Original function
    function(...)                 -- Our code runs AFTER original
        -- Our soil depletion logic
    end
)
```

### Existing Hooks

| Hook | Target | Triggers On | Handler |
|------|--------|-------------|---------|
| Harvest | `FruitUtil.fruitPickupEvent` | Crop harvested | `SoilFertilitySystem:onHarvest()` |
| Fertilizer | `Sprayer.spray` | Fertilizer applied | `SoilFertilitySystem:onFertilizerApplied()` |
| Plowing | `Cultivator.processCultivatorArea` | Field plowed | `SoilFertilitySystem:onPlowing()` |
| Ownership | `g_farmlandManager.fieldOwnershipChanged` | Field bought/sold | `SoilFertilitySystem:onFieldOwnershipChanged()` |
| Weather | `g_currentMission.environment.update` | Every frame | `SoilFertilitySystem:onEnvironmentUpdate()` |

### Adding a New Hook

1. **Add hook installation** in `HookManager.lua`:

```lua
function HookManager:installYourHook()
    if not YourGameClass or not YourGameClass.yourMethod then
        print("[SoilFertilizer WARNING] Could not install your hook")
        return
    end

    local original = YourGameClass.yourMethod
    YourGameClass.yourMethod = Utils.appendedFunction(
        original,
        function(self, param1, param2, ...)
            if not g_SoilFertilityManager or
               not g_SoilFertilityManager.settings.enabled then
                return
            end

            local success, errorMsg = pcall(function()
                g_SoilFertilityManager.soilSystem:onYourEvent(param1, param2)
            end)

            if not success then
                print("[SoilFertilizer ERROR] Your hook failed: " .. tostring(errorMsg))
            end
        end
    )

    self:register(YourGameClass, "yourMethod", original, "YourGameClass.yourMethod")
    print("[SoilFertilizer] Your hook installed")
end
```

2. **Call from installAll()**:
```lua
function HookManager:installAll(soilSystem)
    -- ... existing hooks
    self:installYourHook()
end
```

3. **Add handler** in `SoilFertilitySystem.lua`:
```lua
function SoilFertilitySystem:onYourEvent(param1, param2)
    -- Your logic here
end
```

**Important**: Always use `pcall()` to prevent crashes from propagating to FS25!

---

## HUD System

### Architecture

The HUD is a **static legend/reference panel** always rendered in a corner of the screen.
Per-field soil data is shown in the **Soil Report dialog** (`SoilReportDialog`, opened with K).

| File | Role |
|------|------|
| `src/ui/SoilHUD.lua` | Renders the static legend overlay |
| `src/ui/SoilReportDialog.lua` | Full paginated soil report (K key) |

### What the HUD Shows

```
SOIL LEGEND
J = Toggle HUD
K = Soil Report
Good: N>50, P>45, K>40   ← green
Fair: N>30, P>25, K>20   ← yellow
Poor: needs fertilizer    ← red
pH ideal: 6.5 - 7.0
```

- **Position**: User-configurable (5 presets in `SoilConstants.HUD.POSITIONS`)
- **Appearance**: Color theme, font size, and transparency all respect user settings
- **Visibility**: `settings.showHUD` (persistent) and `self.visible` (J key runtime toggle)

### HUD Visibility Logic

The HUD hides automatically when:
1. Mod disabled (`settings.enabled = false`)
2. Show HUD setting off (`settings.showHUD = false`)
3. J key toggled off (`self.visible = false`)
4. Menu or dialog open (`g_gui:getIsGuiVisible()` / `getIsDialogVisible()`)
5. Fullscreen map open (`IngameMap.STATE_LARGE_MAP`)

### Modifying the Legend Content

Edit `SoilHUD:drawPanel()` in `src/ui/SoilHUD.lua`. The method is a simple top-to-bottom text renderer:

```lua
-- Pattern: render text, then step Y down by lineH
setTextColor(r, g, b, 1.0)
renderText(x, y, 0.011 * fontMult, "Your line here")
y = y - lineH
```

Threshold values come from `SoilConstants.STATUS_THRESHOLDS` — if you change the thresholds there, update the legend text to match.

### Render Order Note

FS25 does not expose Z-order APIs for Overlays. Render order is determined by callback registration order. The HUD renders via `FSBaseMission.draw`, which runs after core UI initialization. If a mod conflict causes overlap, players can move the HUD via the position preset setting.

---

## Testing Your Changes

See `TESTING.md` for comprehensive manual testing procedures.

### Quick Testing Checklist

- [ ] Load mod in clean savegame - no errors in log
- [ ] Harvest crops - nutrients deplete correctly
- [ ] Apply fertilizer - nutrients restore correctly
- [ ] Toggle settings - changes take effect
- [ ] Save/load - data persists
- [ ] Multiplayer - server/client sync works
- [ ] With Precision Farming - read-only mode activates (listen-server)
- [ ] With Precision Farming on dedicated server - falls back to independent mode, clients receive data

### Dedicated Server Testing

When testing dedicated server scenarios with Precision Farming:

1. Start a dedicated server with Precision Farming enabled
2. Connect as a client
3. Check `log.txt` — you should see:
   ```
   [SoilFertilizer WARNING] Precision Farming detected but API not accessible
   (dedicated server / load-order issue) - falling back to independent mode
   ```
   followed by:
   ```
   [SoilFertilizer] Broadcast initial field data for N fields to all clients
   ```
4. Open the Soil Report (K key) — all fields should show soil data immediately without needing to harvest or fertilize first

### Debug Logging

```lua
-- Add to your code for debugging
if self.settings.debugMode then
    SoilLogger.info("Your debug message: %s", tostring(value))
end
```

Enable in-game: `SoilDebug`

---

## Common Gotchas

### 1. Lua 5.1 Limitations

FS25 uses Lua 5.1 (not 5.2+):

- ❌ No `goto` or `continue`
- ❌ No `os.time()` or `os.date()` - Use `g_currentMission.time`
- ❌ No bitwise operators - Use `bitAND`, `bitOR`, etc.
- ✅ Use guard clauses instead of `continue`:
  ```lua
  -- Bad (doesn't work)
  for i, v in ipairs(list) do
      if v == skip then continue end
  end

  -- Good
  for i, v in ipairs(list) do
      if v ~= skip then
          -- your code
      end
  end
  ```

### 2. Global Namespace Pollution

Use module prefixes for global functions:

```lua
-- Bad
function RequestSync()  -- Pollutes global namespace
end

-- Good
function SoilNetworkEvents_RequestSync()  -- Namespaced
end
```

### 3. Hook Accumulation

Always uninstall hooks on mod unload:

```lua
-- HookManager tracks all hooks
self:register(TargetClass, "method", originalFunction, "name")

-- Cleanup in HookManager:uninstallAll()
for _, hook in ipairs(self.hooks) do
    hook.target[hook.key] = hook.original  -- Restore original
end
```

### 4. Multiplayer Desyncs

- **Always** run soil changes on server only
- **Always** broadcast updates to clients
- **Never** modify soil data on clients directly

```lua
-- Good pattern
if g_server then
    -- Modify data
    field.nitrogen = newValue

    -- Broadcast to clients
    if g_currentMission.missionDynamicInfo.isMultiplayer then
        g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
    end
end
```

### 5. Dedicated Server + Precision Farming

On dedicated servers, `g_precisionFarming` may exist in the global scope before its
field data API is populated. Do **not** assume PF API availability from the presence
of the global alone — always probe `g_precisionFarming.fieldData` or
`soilMap:getFieldData` before treating it as accessible. The existing
`checkPFCompatibility` handles this correctly; follow the same pattern in any new
PF-aware code you add.

### 6. Settings Schema Order Matters

`SettingsSchema.definitions` order affects:
- UI display order
- Network sync order
- XML save/load order

**Don't reorder** existing settings after release - it breaks saves!

### 7. Translation Keys

- UI IDs must have `_short` and `_long` variants:
  - `sf_your_setting_short` - Label in UI
  - `sf_your_setting_long` - Tooltip text

- Multi-option settings need option labels:
  - `sf_your_option_1`, `sf_your_option_2`, etc.

### 8. Field ID vs Farmland ID

- **Field ID**: Specific field polygon (unique)
- **Farmland ID**: Purchasable land parcel (may contain multiple fields)

Use `g_fieldManager:getFieldAtWorldPosition(x, z)` for precise field lookup.

### 9. Field ID Resolution in scanFields

When iterating `g_fieldManager.fields`, the loop key is an internal table index that
does not reliably match the in-game field ID on all maps. Always resolve the actual
field ID using this priority order:

```lua
local actualFieldId = nil
if field.fieldId and field.fieldId > 0 then
    actualFieldId = field.fieldId
elseif field.id and field.id > 0 then
    actualFieldId = field.id
elseif field.index and field.index > 0 then
    actualFieldId = field.index
elseif type(numericFieldId) == "number" and numericFieldId > 0 then
    actualFieldId = numericFieldId  -- last resort: loop key
end
```

Using the loop key as anything other than a last resort causes data to be stored
under the wrong ID, breaking all subsequent lookups.

---

## Build & Release

### Preparing a Release

1. **Update version in modDesc.xml**:
   ```xml
   <version>1.0.7.1</version>
   ```

2. **Update version in source file headers**:
   - Update headers in `SoilHUD.lua`, `UIHelper.lua`, `Settings.lua`, etc.
   - Update `CLAUDE.md` Project Overview section
   - Update `DEVELOPMENT.md` header (this file)

3. **Test thoroughly**:
   - Run full regression test checklist (see `TESTING.md`)
   - Test in multiplayer (listen server)
   - Test on dedicated server
   - Test with Precision Farming on both listen server and dedicated server

4. **Update CHANGELOG**:
   - Document all changes since last version
   - Group by: Added, Changed, Fixed, Removed

5. **Create ZIP**:
   ```bash
   # From mod root directory
   zip -r FS25_SoilFertilizer.zip . -x "*.git*" -x "*.md"
   ```

6. **Commit & Tag**:
   ```bash
   git add .
   git commit -m "Release v1.0.7.1"
   git tag v1.0.7.1
   git push origin development
   git push origin v1.0.7.1
   ```

7. **Create Pull Request** from `development` to `main`

### ModHub Submission Guidelines

- **Icon**: 256×256 DDS file
- **ZIP name**: Must match modDesc `<modName>`
- **No external dependencies**: All code must be self-contained
- **Translations**: All 11 languages required
- **Testing**: Must work in both SP and MP
- **File size**: Keep under 50MB

---

## Additional Resources

- **FS25 Scripting Documentation**: https://gdn.giants-software.com/
- **CLAUDE.md**: Project architecture and conventions
- **TESTING.md**: Manual testing procedures
- **CODEBASE_AUDIT.md**: Known issues and tech debt

---

**Questions?** Open an issue on GitHub!

**Happy Modding!** 🚜🌾

---

## Enterprise-Grade Development Patterns

### Circuit Breaker Implementation

```lua
-- Example circuit breaker pattern
function myNetworkOperation()
    if self:circuitBreakerOpen() then
        self:log("Circuit breaker open - skipping operation")
        return false
    end

    local success, result = pcall(function()
        -- Network operation here
        return self:performNetworkCall()
    end)

    if success then
        self:recordCircuitBreakerSuccess()
        return result
    else
        self:recordCircuitBreakerFailure()
        return false
    end
end
```

### Health Monitoring

```lua
-- Example health check implementation
function checkSystemHealth()
    local checks = {
        "checkSystemIntegrity",
        "checkFieldDataIntegrity", 
        "checkNetworkReliability",
        "checkMemoryUsage",
        "checkPerformanceMetrics"
    }

    local results = {}
    for _, checkName in ipairs(checks) do
        local success, result = pcall(self[checkName])
        results[checkName] = {
            success = success,
            result = result,
            timestamp = g_currentMission.time
        }
    end

    return results
end
```

### Performance Monitoring

```lua
-- Example performance tracking
function trackPerformance(operationName, func)
    local startTime = g_currentMission.time
    
    local success, result = pcall(func)
    
    local duration = g_currentMission.time - startTime
    
    -- Record metrics
    self:recordMetric(operationName, {
        duration = duration,
        success = success,
        timestamp = g_currentMission.time
    })
    
    return success, result
end
```

### Error Recovery

```lua
-- Example graceful degradation
function handleFailure(operation, fallback)
    local maxAttempts = 3
    local attempt = 0
    
    while attempt < maxAttempts do
        local success, result = pcall(operation)
        if success then
            return result
        end
        
        attempt = attempt + 1
        self:log("Operation failed, attempt %d/%d", attempt, maxAttempts)
        
        -- Exponential backoff
        if attempt < maxAttempts then
            self:waitForRetry(math.pow(2, attempt))
        end
    end
    
    -- Fallback mechanism
    self:log("Max attempts reached, using fallback")
    return fallback()
end
```

### Enterprise Testing Guidelines

#### 1. **Reliability Testing**
- Test circuit breaker behavior under failure conditions
- Verify health monitoring accuracy
- Test graceful degradation scenarios
- Validate recovery mechanisms

#### 2. **Performance Testing**
- Test with large maps (100+ fields)
- Measure memory usage over time
- Test network bandwidth optimization
- Validate predictive loading performance

#### 3. **Multiplayer Testing**
- Test client connection tracking
- Verify field data synchronization
- Test network failure scenarios
- Validate circuit breaker in multiplayer

#### 4. **Stress Testing**
- Test memory leak detection
- Validate garbage collection
- Test system under high load
- Verify error handling under stress

### Enhanced Debug Features

#### 1. **Health Monitoring Debug**
```bash
# Check system health
soilfertility debug health

# View detailed health report
soilfertility debug health detailed

# Reset health metrics
soilfertility debug health reset
```

#### 2. **Performance Debug**
```bash
# Show performance metrics
soilfertility debug metrics

# Monitor memory usage
soilfertility debug memory

# Track network performance
soilfertility debug network
```

#### 3. **Circuit Breaker Debug**
```bash
# Check circuit breaker status
soilfertility debug circuit

# Force circuit breaker state
soilfertility debug circuit force open
soilfertility debug circuit force closed

# Reset circuit breaker
soilfertility debug circuit reset
```

#### 4. **Field Data Debug**
```bash
# List all tracked fields
soilfertility debug fields list

# Check field data integrity
soilfertility debug fields integrity

# Force field data sync
soilfertility debug fields sync
```

### Enterprise Configuration

#### Development Environment Setup

```lua
-- Development configuration
SoilConstants.DEVELOPMENT = {
    DEBUG_MODE = true,
    HEALTH_CHECK_INTERVAL = 5000,      -- Faster checks in dev
    CIRCUIT_BREAKER_DEBUG = true,      -- Verbose circuit breaker logging
    PERFORMANCE_MONITORING = true,     -- Detailed performance tracking
    MEMORY_TRACKING = true,            -- Memory leak detection
    NETWORK_DEBUG = true,              -- Detailed network logging
}
```

#### Monitoring in Development

```lua
-- Development monitoring helpers
function devMonitorSystem()
    if not SoilConstants.DEVELOPMENT.DEBUG_MODE then return end
    
    -- Log health status
    local health = g_SoilFertilityManager:getHealthReport()
    print(string.format("Health: %s, Uptime: %dms, Fields: %d",
        health.status, health.uptime, health.fieldCount))
    
    -- Log performance metrics
    local metrics = g_SoilFertilityManager.soilSystem:getPerformanceReport()
    print(string.format("Latency: %.1fms, Success: %.1f%%, Bandwidth: %.1fKB",
        metrics.avgSyncLatency, metrics.syncSuccessRate * 100, metrics.bandwidthUsage / 1024))
end
```

### Security Considerations

#### Enterprise Security Patterns

1. **Input Validation**
   - All network data must be validated
   - Use bounds checking for all numeric inputs
   - Sanitize all user inputs

2. **Error Handling**
   - Never expose internal system details in error messages
   - Use structured error codes
   - Implement error rate limiting

3. **Resource Management**
   - Prevent resource exhaustion attacks
   - Implement proper cleanup mechanisms
   - Monitor resource usage patterns

4. **Network Security**
   - Validate all network messages
   - Implement message signing where appropriate
   - Use circuit breaker to prevent DoS

### Performance Optimization

#### Enterprise Performance Guidelines

1. **Memory Management**
   - Implement automatic garbage collection
   - Monitor memory usage patterns
   - Prevent memory leaks with cleanup mechanisms

2. **Network Optimization**
   - Use compression for large data transfers
   - Implement intelligent caching
   - Optimize bandwidth usage

3. **CPU Optimization**
   - Use efficient algorithms for field processing
   - Implement lazy loading where possible
   - Optimize update loops

4. **I/O Optimization**
   - Batch file operations
   - Use asynchronous operations where possible
   - Implement intelligent caching for file data

### Troubleshooting

#### Common Enterprise Issues

1. **Circuit Breaker Stays Open**
   - Check network connectivity
   - Verify server availability
   - Review failure thresholds

2. **High Memory Usage**
   - Check for memory leaks
   - Verify garbage collection
   - Review field data retention

3. **Poor Performance**
   - Check bandwidth limits
   - Verify compression settings
   - Review predictive loading configuration

4. **Health Check Failures**
   - Verify system integrity
   - Check field data corruption
   - Review network reliability

#### Debug Commands Reference

```bash
# Health monitoring
soilfertility debug health          # System health status
soilfertility debug health detailed # Detailed health report
soilfertility debug health reset    # Reset health metrics

# Performance monitoring  
soilfertility debug metrics         # Performance metrics
soilfertility debug memory          # Memory usage
soilfertility debug network         # Network performance

# Circuit breaker
soilfertility debug circuit         # Circuit breaker status
soilfertility debug circuit force   # Force circuit state
soilfertility debug circuit reset   # Reset circuit breaker

# Field data
soilfertility debug fields list     # List tracked fields
soilfertility debug fields integrity # Check data integrity
soilfertility debug fields sync     # Force data sync

# System status
soilfertility debug status          # Overall system status
soilfertility debug connections     # Client connections
soilfertility debug errors          # Error logs
```
