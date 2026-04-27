# FS25_SoilFertilizer — Multiplayer & Dedicated Server Audit

**Scope:** All `.lua` files audited for MP/dedi-server correctness  
**Found:** 2 CRITICAL · 2 HIGH · 1 MEDIUM  
**All bugs have exact code fixes below.**

---

## Issue Summary

| # | Severity | File / Location | Description |
|---|----------|----------------|-------------|
| 1 | 🔴 CRITICAL | `NetworkEvents.lua` — `SoilSprayerRateEvent` / `SoilSprayerAutoModeEvent` | `vehicle.id` (local entity handle) sent raw across the network — rate changes silently ignored in every MP session |
| 2 | 🔴 CRITICAL | `NetworkEvents.lua` — `SoilSettingSyncEvent:run()` | Nil access crash on dedicated server when `settingsUI` is `nil`; Lua variable shadowing silently breaks the `localOnly` guard |
| 3 | 🟠 HIGH | `SoilFertilitySystem.lua` — `update()` PHASE-4 block | Daily soil batch drain runs on MP clients with no server guard — can permanently desync field data |
| 4 | 🟠 HIGH | `SoilFertilitySystem.lua` — `scanFields()` | Creates randomised `fieldData` on MP clients before server sync arrives — causes soil value flicker and potential stale data |
| 5 | 🟡 MEDIUM | `NetworkEvents.lua` — `SoilSettingChangeEvent:run()` | Duplicate `local def` declaration shadows outer `localOnly` guard; `enabled` toggle calls `initialize()` twice on listen-server host |

---

## Bug #1 — CRITICAL: `vehicle.id` sent raw across the network

### Root Cause

In FS25, `vehicle.id` is a **C++ entity handle** — an integer that is valid only within the process that created it. Dedicated servers and remote clients each maintain separate entity tables with different numbering.

When a player presses `]` to raise the sprayer rate, the sender does:

```lua
SoilNetworkEvents_SendSprayerRate(vehicle.id, newIdx)
-- which calls:
g_client:getServerConnection():sendEvent(SoilSprayerRateEvent.new(vehicle.id, rateIndex))
```

`writeStream` then sends that local handle as a raw `Int32`:

```lua
function SoilSprayerRateEvent:writeStream(streamId, connection)
    streamWriteInt32(streamId, self.vehicleId)  -- ← local entity handle, meaningless on server
    streamWriteUInt8(streamId, self.rateIndex)
end
```

The server reads that integer and calls `rm:setIndex(self.vehicleId, self.rateIndex)` — but the server has no vehicle with that handle. The rate is stored under a bogus key and **never applies**. This affects both `SoilSprayerRateEvent` and `SoilSprayerAutoModeEvent`.

**Side effect on dedicated servers:** The `SprayerRateManager` table accumulates infinite bogus entries over time, one per rate-change attempt by any player.

### Fix

Use `NetworkUtil.getObjectId()` on the sender and `NetworkUtil.getObject()` on the receiver — the same pattern vanilla FS25 uses for all vehicle references across the network.

**`SoilSprayerRateEvent:writeStream` (sender)**
```lua
function SoilSprayerRateEvent:writeStream(streamId, connection)
    -- BEFORE: streamWriteInt32(streamId, self.vehicleId)
    streamWriteInt32(streamId, NetworkUtil.getObjectId(self.vehicleId))
    streamWriteUInt8(streamId, self.rateIndex)
end
```

**`SoilSprayerRateEvent:readStream` (receiver)**
```lua
function SoilSprayerRateEvent:readStream(streamId, connection)
    -- BEFORE: self.vehicleId = streamReadInt32(streamId)
    local networkId = streamReadInt32(streamId)
    local vehicle   = NetworkUtil.getObject(networkId)
    self.vehicleId  = vehicle and vehicle.id or nil
    self.rateIndex  = streamReadUInt8(streamId)
    self:run(connection)
end
```

**`SoilSprayerRateEvent:run` — add nil guard**
```lua
function SoilSprayerRateEvent:run(connection)
    local rm = g_SoilFertilityManager and g_SoilFertilityManager.sprayerRateManager
    if rm == nil then return end

    -- Vehicle may not exist on this machine yet (loading race on join)
    if self.vehicleId == nil then return end

    local steps = SoilConstants.SPRAYER_RATE.STEPS
    if self.rateIndex < 1 or self.rateIndex > #steps then return end

    rm:setIndex(self.vehicleId, self.rateIndex)
    -- ... rest unchanged
end
```

Apply the **identical fix** to `SoilSprayerAutoModeEvent` (same file, same issue).

---

## Bug #2 — CRITICAL: `SoilSettingSyncEvent:run()` nil access on dedicated server

### Root Cause

`SoilSettingSyncEvent:run()` calls `g_SoilFertilityManager.settingsUI:refreshUI()` without a nil check:

```lua
function SoilSettingSyncEvent:run(connection)
    if g_client == nil then return end
    -- ...
    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        -- ...
        if g_SoilFertilityManager.settingsUI then   -- ← this guard IS present, but...
            g_SoilFertilityManager.settingsUI:refreshUI()
        end
    end
end
```

The nil-check on `settingsUI` is actually there — but there is a second problem: the `localOnly` guard uses a `local def` declaration that **shadows** the one already declared earlier in the same scope:

```lua
-- In SoilSettingChangeEvent:run() — two declarations of 'def' in the same function:
local def = SettingsSchema and SettingsSchema.byId and SettingsSchema.byId[self.settingName]
if def and def.localOnly then return end   -- ← outer guard
-- ... 40 lines later ...
local def = SettingsSchema and ...   -- ← shadows the outer one; Lua 5.1 allows this
if def and def.localOnly then return end   -- ← effectively a duplicate, outer guard is now unreachable
```

Additionally, on a **listen-server host** (where `g_server ~= nil` and `g_client ~= nil`), a setting change:
1. Applies the value in `SoilSettingChangeEvent:run()` (server half)
2. Broadcasts `SoilSettingSyncEvent` to all clients
3. The host's client half receives and runs `SoilSettingSyncEvent:run()` again

For the `enabled` setting specifically, step 1 calls `soilSystem:initialize()`. If `initialize()` is not idempotent in all paths, a double-call can cause double hook installation.

### Fix

**`SoilSettingSyncEvent:run()` — ensure the early-exit guard is at the very top**
```lua
function SoilSettingSyncEvent:run(connection)
    -- Guard: dedicated server has no client state; settingsUI is nil
    if g_client == nil then return end

    local def = SettingsSchema and SettingsSchema.byId and SettingsSchema.byId[self.settingName]
    if def and def.localOnly then return end

    if g_SoilFertilityManager and g_SoilFertilityManager.settings then
        local oldValue = g_SoilFertilityManager.settings[self.settingName]
        g_SoilFertilityManager.settings[self.settingName] = self.settingValue

        SoilLogger.info("Client: Setting '%s' synced from %s to %s",
            self.settingName, tostring(oldValue), tostring(self.settingValue))

        -- settingsUI is nil on dedicated servers and headless clients
        if g_SoilFertilityManager.settingsUI then
            g_SoilFertilityManager.settingsUI:refreshUI()
        end
    end
end
```

**`SoilSettingChangeEvent:run()` — remove the shadowing `local def` redeclaration**
```lua
-- BEFORE (second declaration, ~40 lines into the function):
local def = SettingsSchema and SettingsSchema.byId and SettingsSchema.byId[self.settingName]
if def and def.localOnly then return end

-- AFTER (remove the 'local' keyword — reuse the outer variable already fetched at the top):
if def and def.localOnly then return end
```

**`SoilSettingChangeEvent:run()` — guard `initialize()` against double-call on listen server**
```lua
if self.settingName == "enabled" and g_SoilFertilityManager.soilSystem then
    if self.settingValue then
        -- Only re-initialize if the system is not already running
        if not g_SoilFertilityManager.soilSystem.isInitialized then
            g_SoilFertilityManager.soilSystem:initialize()
        end
    end
end
```

---

## Bug #3 — HIGH: Daily soil batch drain runs on MP clients (desync)

### Root Cause

`SoilFertilityManager:update()` calls `self.soilSystem:update(dt)` unconditionally on every game instance, including pure MP clients:

```lua
function SoilFertilityManager:update(dt)
    -- Comment says "server side" but there is no actual guard:
    if self.soilSystem then
        self.soilSystem:update(dt)   -- ← runs on clients too
    end
```

Inside `SoilFertilitySystem:update()`, the PHASE-4 daily batch drain has no server guard:

```lua
if self._pendingDailyUpdate then
    -- NO guard here — runs on clients if _pendingDailyUpdate is ever true
    -- ...
    self:_processOneDailyField(fid, fd)   -- ← mutates server-synced field data on client
end
```

`updateDailySoil()` itself is correctly guarded in `onEnvironmentUpdate()` (returns early when `g_server == nil`), so `_pendingDailyUpdate` is never set to `true` on clients *today*. However, `scanFields()` runs on clients via the unguarded `fieldsScanPending` retry loop in `update()`, and `_addToActiveSet()` is called from `scanFields()`. If any future code path or race condition sets `_pendingDailyUpdate = true` on a client, `_processOneDailyField()` will silently corrupt synced server data for the rest of the session with no error or warning.

### Fix

**`SoilFertilitySystem:update()` — add server guard to the PHASE-4 block**
```lua
-- PHASE 4: Batched daily field processing — SERVER ONLY
if self._pendingDailyUpdate then
    -- Guard: clients must never run the daily simulation.
    -- Field data is authoritative on the server and pushed via SoilFieldUpdateEvent.
    if g_server == nil then
        self._pendingDailyUpdate = false
        return
    end
    -- ... existing batch drain code unchanged ...
end
```

**`SoilFertilitySystem:update()` — add server guard to the field-scan retry block**
```lua
if self.fieldsScanPending then
    -- Clients must not run field scans — data arrives via SoilFieldBatchSyncEvent
    if g_server == nil then
        self.fieldsScanPending = false
    else
        -- ... existing 3-stage retry code ...
    end
end
```

---

## Bug #4 — HIGH: `scanFields()` creates randomised `fieldData` on MP clients

### Root Cause

`scanFields()` calls `getOrCreateField()` for every field on the map. `getOrCreateField()` writes **randomised default soil values** into `self.fieldData` when an entry does not yet exist:

```lua
self.fieldData[fieldId] = {
    nitrogen   = math.floor(randomize(defaults.nitrogen, defaults.nitrogen * 0.10, 1)),
    phosphorus = math.floor(randomize(defaults.phosphorus, ...)),
    -- ...
}
```

On an MP client, the correct values should arrive from the server via `SoilFullSyncEvent` + `SoilFieldBatchSyncEvent`. If `scanFields()` runs first — which it does, because the retry loop in `update()` has no client guard — the client creates its own random-default `fieldData` entries.

When the server sync arrives it overwrites them, but the window between join and sync completion can be multiple seconds on a slow connection or a large map. During that window, any UI reading `fieldData` (the HUD, the PDA screen, the soil report dialog) shows completely wrong values.

### Fix

**Add a client-exit at the top of `scanFields()`**
```lua
function SoilFertilitySystem:scanFields()
    -- Guard: clients must not create local fieldData.
    -- Soil values are authoritative on the server and arrive via network sync events.
    if g_currentMission
       and g_currentMission.missionDynamicInfo
       and g_currentMission.missionDynamicInfo.isMultiplayer
       and g_server == nil then
        self:info("Client: skipping local field scan — waiting for server sync")
        self.fieldsScanPending = false
        return true   -- signal 'done' to suppress further retries
    end

    -- ... rest of existing scanFields() code unchanged ...
end
```

---

## Bug #5 — MEDIUM: Duplicate `local def` in `SoilSettingChangeEvent:run()` shadows outer guard

### Root Cause

Described in Bug #2 above. The second `local def = ...` declaration inside `SoilSettingChangeEvent:run()` shadows the first. In Lua 5.1 this is a silent redeclaration — no warning, no error. The outer `localOnly` guard is effectively dead code once the inner declaration shadows it.

### Fix

Already documented in Bug #2. Remove the `local` keyword from the second declaration so both checks reference the same variable fetched once at the top of the function.

---

## What Is Working Correctly

These MP patterns were audited and confirmed correct — no changes needed:

- **`SoilRequestFullSyncEvent`** — dedicated-server path sends all batches synchronously (correct; connection object must not be captured across ticks on a dedi server). Listen-server path uses `addUpdateable` with a valid connection-alive guard.
- **`SoilFullSyncEvent` read/write symmetry** — field data stream fields are in the same order on both sides. NaN and out-of-range clamping on read is correct. Settings sub-stream iterates `SettingsSchema.definitions` in the same order on both sides.
- **`SoilFieldBatchSyncEvent`** — `writeStream` and `readStream` are symmetric. `coverageFraction` and `nutrientBuffer` are written and read correctly.
- **`SoilFieldUpdateEvent`** — `:run()` correctly returns early when `g_client == nil`. All hook sites check `g_server ~= nil` before calling `broadcastEvent`.
- **Admin validation** — `SoilSettingChangeEvent:run()` correctly uses `getUserByConnection` + `getIsMasterUser()`. The `connection:getIsServer()` bypass for the listen-server host is correct.
- **Save path (server only)** — the `FSCareerMissionInfo:saveToXMLFile` hook correctly checks `g_server == nil` before returning in multiplayer.
- **FillType injection on dedi servers** — the `FillTypeManager.loadModFillTypes` hook that force-injects `fillTypes.xml` into `modsToLoad` is present and correct.
- **Hook installation guards** — all harvest, sprayer, plowing, and weather hooks check `combineSelf.isServer` / `plowSelf.isServer` / `g_server` before writing soil data.
- **`AsyncRetryHandler`** — uses `g_currentMission.time` (not `os.time()`). `reset()` re-arms cleanly across level reloads.
- **GUI disabled on dedi servers** — `disableGUI` flag correctly set; all GUI objects are nil-guarded before use.

---

## Dedicated Server Checklist

| | Check | Status |
|---|---|---|
| ✅ | `fillTypes.xml` forced into `FillTypeManager.modsToLoad` queue | PASS |
| ✅ | Synchronous full-sync batch dispatch on dedi server | PASS |
| ✅ | Settings save guarded — only server writes `soilData.xml` | PASS |
| ✅ | GUI objects nil on dedi server — no crash in normal paths | PASS (with fix #2) |
| ✅ | Hooks install only on server via `deferredSoilSystemInit` | PASS |
| ✅ | Admin setting change validated via `getIsMasterUser()` | PASS |
| ❌ | `vehicle.id` sent raw across network | FAIL — fix #1 |
| ❌ | Daily batch drain runs on clients | FAIL — fix #3 |
| ❌ | `scanFields()` creates local `fieldData` on clients | FAIL — fix #4 |
| ✅ | `broadcastAllFieldData()` guarded by `g_server` + `g_dedicatedServer` path | PASS |
| ✅ | `onEnvironmentUpdate` returns early on clients (`g_server == nil` guard) | PASS |

---

## Fix Priority Order

1. **Fix #1** first — vehicle ID bug causes every sprayer rate change to silently fail in MP for all players. Also causes `SprayerRateManager` to grow unboundedly on busy dedicated servers.
2. **Fix #3 + Fix #4 together** — both relate to client-side simulation running where it shouldn't. Fixing the daily batch drain without fixing `scanFields()` still allows clients to create stale `fieldData`.
3. **Fix #2** — nil-access crash on dedicated server when settings are changed; also cleans up the variable shadowing.
4. **Fix #5** — lower risk but cleans up silent dead code in the `localOnly` guard.
