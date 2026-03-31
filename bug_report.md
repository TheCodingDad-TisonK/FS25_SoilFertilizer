# FS25_SoilFertilizer — Full Code Review
**Pass type:** Bugs · Edge Cases · Dead/Unhooked Code · Comments · Polish  
**Files reviewed:** all 15 Lua source files under `src/`

---

## CRITICAL BUGS

### 1. `SoilFertilitySystem.lua` — `PFActive` double-init race condition
```lua
-- checkPFCompatibility() starts with:
if self.PFActive ~= nil then return end
```
`PFActive` is set to `false` in `new()`, so this guard **always fires immediately** and the function becomes a no-op every time. `SoilFertilityManager.checkAndApplyCompatibility()` sets it correctly beforehand, but `SoilFertilitySystem:checkPFCompatibility()` is also called inside `initialize()` — creating an order-dependent code path that silently skips the dual-API check logic.

**Fix:** Change the guard to only skip if PFActive was explicitly set by the Manager:
```lua
-- In new(), use a sentinel instead of false:
self.PFActive = nil  -- nil = not yet determined

-- OR: add a separate flag
self.pfActiveSet = false
```
And in `Manager.new()`, set the flag AFTER creating soilSystem so the two stay in sync.

---

### 2. `SoilFertilityManager.lua` — `saveSoilData()` / `loadSoilData()` called too early
`loadSoilData()` is called at the end of `SoilFertilityManager.new()`. At that point, `g_currentMission.missionInfo.savegameDirectory` may be `nil` on the first frame of a new career. Both functions guard for this and bail out with a DIAG print, which means **the initial load is silently skipped** for new saves.

The actual load should happen in `onMissionLoaded()` or the deferred updater, after `missionDynamicInfo.isStarted` is true. The current code in `new()` is a dead call path for most real play sessions.

**Fix:** Move `loadSoilData()` from `new()` into `deferredSoilSystemInit()` right after `soilSystem:initialize()`.

---

### 3. `NetworkEvents.lua` — `SoilFullSyncEvent:run()` references `settings:getDifficultyName()` before `getDifficultyName` is available on the plain table
```lua
print(string.format("... Difficulty: %s", settings:getDifficultyName()))
```
`settings` here is the **raw table** `self.settings` that was populated field-by-field from the stream — it is **not** a `Settings` class instance. Calling `:getDifficultyName()` on it will throw `attempt to call a nil value`.

**Fix:**
```lua
-- Replace the getDifficultyName() call with an inline lookup:
local diffNames = {"Simple", "Realistic", "Hardcore"}
local diffName  = diffNames[settings.difficulty] or "Unknown"
print(string.format("... Difficulty: %s", diffName))
```

---

### 4. `SoilSettingsGUI.lua` — `consoleCommandShowSettings` uses `#fieldData` on a hash table
```lua
g_SoilFertilityManager.soilSystem and #g_SoilFertilityManager.soilSystem.fieldData or 0
```
`fieldData` is keyed by `fieldId` (integers that may not start at 1 or be contiguous). The `#` operator on a non-sequence table returns **undefined behavior** in Lua 5.1. This will almost always print `0` even when fields are tracked.

**Fix:** Use `SoilFertilitySystem:getFieldCount()` which already exists:
```lua
g_SoilFertilityManager.soilSystem and g_SoilFertilityManager.soilSystem:getFieldCount() or 0
```

---

### 5. `SoilHUD.lua` — `drawSprayerRatePanel()` references `SoilConstants.AUTO_RATE_TARGETS` (does not exist)
```lua
local targets = SoilConstants.AUTO_RATE_TARGETS
if profile.N and profile.N > 0 then targetText = targetText .. targets.N .. "N " end
```
`AUTO_RATE_TARGETS` is nested under `SoilConstants.SPRAYER_RATE.AUTO_RATE_TARGETS`, not at the top level. This will throw a nil-index error whenever Auto-Mode is active and the fill type has a profile.

**Fix:**
```lua
local targets = SoilConstants.SPRAYER_RATE.AUTO_RATE_TARGETS
```

---

### 6. `SoilHUD.lua` — `py()` helper used inside `drawSprayerRatePanel()` as a method with `:` but defined with `.`
```lua
-- Used as:
local padV = self:py(5) * s
-- Defined as:
function SoilHUD:py(pixels) return pixels / 1080 end
```
This is fine — defined with `:` so `self` is implicit. However `px()` is defined the same way but never called as `self:px()` anywhere. It is also never used at all. See **Dead Code** section below.

---

## HIGH PRIORITY BUGS / EDGE CASES

### 7. `HookManager.lua` — `installPlowingHook` appended function receives wrong args
`Utils.appendedFunction` appends a function that is called with the **same arguments as the original**. `Cultivator.processCultivatorArea` has the signature `(self, superFunc, workArea, dt)` in the base game. The appended closure therefore receives `(cultivatorSelf, superFunc, workArea, dt)` — but the code tries to use `workArea.start` directly. This is correct **only** if FS25 uses direct dispatch rather than superFunc dispatch. If the game wraps this call differently, `workArea` could be the `superFunc` and the nil-check `if not workArea or type(workArea) ~= "table"` would catch it. This should be verified against the LuaDoc. Add a fallback log so it's visible if the guard fires at runtime:
```lua
if not workArea or type(workArea) ~= "table" then
    SoilLogger.debug("Plowing hook: workArea invalid (type=%s) — skipping", type(workArea))
    return
end
```

---

### 8. `SoilFertilitySystem.lua` — `updateDailySoil` accesses `g_currentMission.environment` without a nil-guard
```lua
if self.settings.seasonalEffects and g_currentMission.environment then
    local season = g_currentMission.environment.currentSeason
```
`g_currentMission` itself is not checked here — the outer loop only checks `g_currentMission.environment`. If `g_currentMission` is nil (dedicated server shutdown, level reload), this will error.

**Fix:** Add a top-level guard:
```lua
if self.settings.seasonalEffects and g_currentMission and g_currentMission.environment then
```

---

### 9. `SoilFertilitySystem.lua` — `onClientJoined()` is never called
`onClientJoined(connection)` sends all field data to a joining client — a good feature — but there is **no hook anywhere** that calls it. `HookManager.installAll()` installs 5 hooks; none of them cover player join events. The function is dead. Either hook `FSBaseMission.onPlayerJoined` / the network connection accept event, or remove the method and document that `broadcastAllFieldData()` covers the initial sync.

---

### 10. `NetworkEvents.lua` — `SoilNetworkEvents_InitializeRetryHandler` uses a stale `fullSyncRetryHandler` reference
```lua
function SoilNetworkEvents_InitializeRetryHandler()
    if fullSyncRetryHandler then return end  -- early-exit if already created
    ...
end
```
On a level reload (MP client reconnects), the old handler object persists because it's a module-level `local`. If the client reconnects, `start()` is called on the old completed-state handler (`state == "success"`), which won't re-arm because `start()` guards `state == "pending"`. The client will never re-sync.

**Fix:** Reset the handler on each `SoilNetworkEvents_RequestFullSync` call:
```lua
function SoilNetworkEvents_RequestFullSync()
    if not g_client or g_server then return end
    SoilNetworkEvents_InitializeRetryHandler()
    fullSyncRetryHandler:reset()   -- re-arm before start
    fullSyncRetryHandler:start()
end
```

---

### 11. `SoilFertilityManager.lua` — `delete()` calls `saveSoilData()` before unregistering hooks
If any hook fires during `saveSoilData()` (e.g., a pending environment.update callback), it may access a partially-torn-down `soilSystem`. Recommended order:
1. Unregister input events
2. Restore hooks (so no new callbacks fire)
3. Save data
4. Delete soilHUD / soilSystem
5. Clear globals

---

### 12. `SoilFertilitySystem.lua` — `applyBurnEffect()` sets `field.burnActive = true` but nothing reads it
`burnActive` is written but never consumed — no HUD indicator, no recovery mechanic, no save/load persistence for it. Either wire it up or remove it to avoid misleading state.

---

### 13. `SoilFertilitySystem.lua` — `math.randomseed(fieldId * 67890)` called on every lazy-create
`math.randomseed` resets the global Lua random state. If multiple fields are created in the same frame (initial scan), later calls overwrite the seed from earlier calls before the random numbers are drawn. Fields created in bulk will all use the seed of whichever `getOrCreateField` ran last before the `math.random()` calls execute.

**Fix:** Set the seed then immediately call `math.random()` within the same stack frame (which the current code does), but note this still affects any other code using `math.random()` elsewhere in the same frame. Consider using a local deterministic hash instead:
```lua
-- Deterministic variation without touching global random state:
local function hash(n)
    n = ((n >> 16) ~ n) * 0x45d9f3b
    n = ((n >> 16) ~ n) * 0x45d9f3b
    return ((n >> 16) ~ n) / 2147483647.0  -- 0.0–1.0
end
local function randField(fieldId, slot)
    return hash(fieldId * 67890 + slot)
end
-- Use randField(fieldId, 1) for N, randField(fieldId, 2) for P, etc.
```

---

## EDGE CASES

### 14. `SoilFertilitySystem.lua` — `getFieldInfo()` creates a field for any query, even HUD polling
`getOrCreateField(fieldId, true)` is called in `getFieldInfo()`. The HUD calls this every 0.5 s for whatever field the player is standing on. In multiplayer, clients cannot create fields (guarded), so they get `nil` back and the HUD shows nothing — that part is correct. But in singleplayer, walking through untracked regions continuously creates new field entries with default values. This is probably the intended "lazy init" behavior, but it means the `fieldData` table grows silently to include fields the player has never farmed. Consider only creating on explicit ownership events in singleplayer too, or document this as intentional.

---

### 15. `SoilHUD.lua` — Yield forecast uses `info.lastCrop` (a post-harvest snapshot)
The yield forecast logic branches on `info.lastCrop`. For a field with an active growing crop (not yet harvested), `lastCrop` is the **previous** season's crop. The HUD shows a yield forecast for the wrong crop until harvest fires. The comment in `getFieldInfo()` addresses this for the display name but the yield tier lookup in `drawPanel()` does not: it uses `info.lastCrop` without checking whether the live `fieldState.fruitTypeIndex` was substituted. Ensure the yield forecast tier also uses the live crop name returned in `info.lastCrop` (which `getFieldInfo()` does correctly resolve — just confirm the HUD reads the resolved value).

---

### 16. `SoilFertilityManager.lua` — `_soilVehicleHookActive` re-entrancy guard is a closure-local, not instance field
```lua
local _soilVehicleHookActive = false
```
This is a `local` inside `new()`. Correct for preventing re-entrancy within one call chain, but if `new()` is ever called more than once (e.g., after a mod reload on a server), a second manager instance would create a **second closure** with its own `_soilVehicleHookActive`. The first instance's hook would already be replaced, so in practice this is safe — but it's fragile. Move it to `self._soilVehicleHookActive` for clarity and to make the lifecycle explicit.

---

### 17. `Settings.lua` — `resetToDefaults(false)` called in `new()` but `saveImmediately` logic is inverted
```lua
function Settings:resetToDefaults(saveImmediately)
    saveImmediately = saveImmediately ~= false  -- treats nil as true
    ...
    if saveImmediately then self:save() end
end
```
Called from `new()` as `resetToDefaults(false)` — correctly suppresses the save. But the comment/parameter name implies `false` means "do not save", yet the expression `saveImmediately ~= false` converts `nil` to `true`. If someone calls `resetToDefaults()` (no arg), it saves immediately — that is the intended default behavior, but the code is easy to misread. Add a clarifying comment.

---

### 18. `SoilHUD.lua` — `clampPosition()` lower bound uses `ph + 0.01` which can push panel off the bottom
```lua
self.panelY = math.max(ph + 0.01, math.min(0.98, self.panelY))
```
This means the panel Y must always be **above** its own height from the bottom of the screen. The clamp is correct for keeping the panel fully visible, but if `scale` is large (1.80x), `ph` ≈ 0.36, so the minimum panelY becomes 0.37 — the panel can never be placed in the lower third of the screen at max scale. Document this as an intentional constraint or adjust the clamp to allow full-screen freedom:
```lua
-- Allow panel to go near bottom; just keep title bar visible:
self.panelY = math.max(0.03, math.min(0.98 - ph, self.panelY))
```

---

### 19. `HookManager.lua` — Sprayer hook resolves field from `vehicle.rootNode` (the cab), not the boom
For self-propelled sprayers the cab and boom are co-located, so this is fine. For tractor+trailed-sprayer combos, `self.rootNode` is the tractor's position, which is behind the boom by several meters. On narrow headlands or field boundaries this can resolve to `nil` (off-field) or the wrong adjacent farmland. A more accurate approach would resolve from the sprayer's work area center (as the harvest hook does with the combine position) or average the boom nozzle nodes. This is a precision issue rather than a crash bug, but worth noting for accuracy.

---

## DEAD / UNHOOKED CODE

### 20. `SoilHUD.lua` — `px()` method is never called
```lua
function SoilHUD:px(pixels) return pixels / 1920 end
```
`py()` is used extensively in `drawSprayerRatePanel()`. `px()` is never called anywhere. Either use it for X-axis sizing (currently hardcoded as `0.006*s`, `0.015*s`, etc.) or remove it.

---

### 21. `SoilFertilitySystem.lua` — `onClientJoined()` has no caller (covered in Bug #9)

---

### 22. `SoilFertilitySystem.lua` — `PLOWING.MIN_DEPTH_FOR_PLOWING` constant defined but only partially used
`SoilConstants.PLOWING.MIN_DEPTH_FOR_PLOWING` is checked in `HookManager:installPlowingHook()` against `cultivatorSpec.workingDepth`. However `cultivatorSpec.workingDepth` is a non-standard field that does not exist on the vanilla Cultivator spec in FS25 — it reads `nil`, so the deep-cultivator branch (`isPlowingTool = true`) can never fire. The constant and the check are effectively dead for all vanilla cultivators. Remove the `workingDepth` branch or document that it requires a specific equipment mod that adds this field.

---

### 23. `SoilFertilitySystem.lua` — `field.burnActive` field is written but never read (covered in Bug #12)

---

### 24. `SoilFertilityManager.lua` — `SAFE_MODE` (tyre mod compatibility) disables GUI for all clients unnecessarily
```lua
if lower:find("tyre") or lower:find("tire") then
    SAFE_MODE = true
```
`SAFE_MODE = true` causes `disableGUI = true` in `load()`. This disables the HUD and settings UI for **every** player in a session where any tyre-related mod is loaded. Tyre mods don't interact with soil GUI at all. The original intent may have been to handle a specific crash, but this is overly broad. Either remove this compat check entirely, or narrow it to only skip a specific known-bad code path.

---

### 25. `NetworkEvents.lua` — `SoilRequestFullSyncEvent` is defined and registered but `SoilNetworkEvents_RequestFullSync()` is only called from within the file — no external trigger
There is no code in `SoilFertilityManager.lua` or `main.lua` that calls `SoilNetworkEvents_RequestFullSync()` on client connect. The full-sync pathway is defined but never initiated. Clients joining a server will only receive field data via `broadcastAllFieldData()` (called after the server's initial field scan) and individual `SoilFieldUpdateEvent` broadcasts on harvest/fertilizer events. If a client joins mid-session (after the initial scan), they receive no existing field data.

**Fix:** Call `SoilNetworkEvents_RequestFullSync()` from the deferred init path (client side):
```lua
-- In deferredSoilSystemInit or onMissionLoaded, after game-ready check:
if g_client and not g_server then
    SoilNetworkEvents_RequestFullSync()
end
```

---

## COMMENT / DOCUMENTATION ISSUES

### 26. `SoilFertilityManager.lua` — Inline diagnostic `print()` calls left in production code
Throughout `saveSoilData()` and `loadSoilData()`, raw `print("[SoilFertilizer DIAG] ...")` calls exist. These will spam the log for every save event in every user's session. These should use `SoilLogger.debug()` so they are gated by `debugMode`, or be removed entirely now that the save hook is confirmed working.

There are also diagnostic `print()` calls in `SoilHUD:refreshFieldData()`, `SoilHUD:getCurrentSprayer()`, and `SoilReportDialog:updateFieldRows()` (`[SoilFertilizer DIAG]` prefix). Same treatment — gate them behind `SoilLogger.debug()`.

---

### 27. `SoilFertilitySystem.lua` — `listAllFields()` uses `field.fieldId` which is always nil in FS25
```lua
local fieldIdStr = tostring(field.fieldId or "?")
```
As noted extensively elsewhere in the code, `field.fieldId` does not exist in FS25. This debug function always prints `"?"` for the FieldManager fields listing. Fix to use the loop variable or `field.farmland.id`.

---

### 28. `SoilFertilityManager.lua` — Comment says `registerInputActions()` was removed, but there are still several TODO-style inline notes scattered that reference old patterns
Clean up stale inline notes:
- `-- NOTE: registerInputActions() removed.` could be deleted entirely (it's been removed, no need to document the removal).
- The vehicle hook comment block is excellent but very long (40+ lines). Consider extracting to `DEVELOPMENT.md`.

---

### 29. `SoilFertilitySystem.lua` — `update()` comment says "periodic checks could go here" — stale placeholder
```lua
if self.lastUpdate >= self.updateInterval then
    self.lastUpdate = 0
    -- Periodic checks could go here
end
```
This 30-second periodic timer fires but does nothing. Either use it (e.g., for auto-rate-control adjustments) or remove the timer entirely to save CPU.

---

### 30. `Constants.lua` — `PURCHASABLE_SINGLE_NUTRIENT` block is well-documented but unused
This table is defined with `pricePerLiter`, `fillUnit`, and `description` fields, but nothing in the codebase reads from it. It appears to be a forward-looking stub for an unimplemented "cost estimation" feature. Add a `-- TODO` comment or remove it to reduce confusion.

---

## POLISH / STYLE

### 31. `SoilFertilitySystem.lua` — `info()` and `warning()` helpers bypass `SoilLogger`
```lua
function SoilFertilitySystem:info(msg, ...) print(string.format("[SoilFertilizer] " .. msg, ...)) end
function SoilFertilitySystem:warning(msg, ...) print(string.format("[SoilFertilizer WARNING] " .. msg, ...)) end
```
These duplicate `SoilLogger.info()` / `SoilLogger.warning()`. All call sites inside `SoilFertilitySystem` use `self:info()` / `self:warning()` instead of `SoilLogger.*`, so they bypass the centralized logger. This means `debugMode` gating doesn't apply to `self:log()` either (it's already debug-gated). Replace all three with direct `SoilLogger` calls to unify logging.

---

### 32. `SoilHUD.lua` — `drawPanel()` uses magic numbers for spacing instead of `py()` / `px()`
The main panel uses `0.006*s`, `0.003*s`, `0.020*s`, etc. directly, while `drawSprayerRatePanel()` uses `self:py(5)*s`. Standardize on one approach throughout to make responsive scaling consistent.

---

### 33. `SoilSettingsGUI.lua` — Console commands reference `soilfertility` (lowercase) but `main.lua` also registers `soilfertility` as a global function, creating a duplicate `addConsoleCommand` registration
In `SoilSettingsGUI:registerConsoleCommands()`:
```lua
addConsoleCommand("soilfertility", "Show all soil commands", "consoleCommandHelp", self)
```
And in `main.lua`:
```lua
getfenv(0)["soilfertility"] = soilfertility
```
These two registrations target different function objects. The console command routes to `SoilSettingsGUI:consoleCommandHelp()`, while the global `soilfertility()` function in `main.lua` has its own fallback print. Pick one path and remove the other.

---

### 34. `SoilReportDialog.lua` — `getFertilizationRecommendation()` uses `g_i18n:getText()` with fallback default strings inline
```lua
g_i18n:getText("sf_report_rec_n_poor", "N (Poor)")
```
This is fine for robustness, but the fallback strings are English-only raw text mixed into logic code. The same pattern is used everywhere. Consider collecting all fallback strings into a single table at the top of the file for easier localization review.

---

### 35. `main.lua` — `loadedMission()` HUD icon patch loop does not warn on missing fill types
```lua
local ft = g_fillTypeManager:getFillTypeByName(name)
if ft then ft.hudOverlayFilename = hudDir .. file end
```
If a fill type is missing (e.g., user hasn't installed a compatible equipment mod), it silently skips. Add a `SoilLogger.debug()` when `ft` is nil so modpack debugging is easier:
```lua
if ft then
    ft.hudOverlayFilename = hudDir .. file
else
    SoilLogger.debug("HUD icon patch: fill type '%s' not registered (equipment mod not loaded)", name)
end
```

---

### 36. `AsyncRetryHandler.lua` — `checkCondition()` is called on every `update()` but the `condition` callback is always the no-op default `function() return false end`
The full-sync retry handler provides `onAttempt` but no `condition`. This means `checkCondition()` runs every frame (polling `false`), and success is only triggered by the explicit `markSuccess()` call from `SoilNetworkEvents_OnFullSyncReceived()`. This is correct behavior, but the `condition` polling adds unnecessary overhead. The method could short-circuit when condition is the default no-op, or the pattern should be documented.

---

## SUMMARY TABLE

| # | File | Severity | Category |
|---|------|----------|----------|
| 1 | SoilFertilitySystem.lua | CRITICAL | Bug — PFActive guard always skips |
| 2 | SoilFertilityManager.lua | CRITICAL | Bug — loadSoilData() called before path exists |
| 3 | NetworkEvents.lua | CRITICAL | Bug — getDifficultyName() called on raw table |
| 4 | SoilSettingsGUI.lua | HIGH | Bug — # on hash table |
| 5 | SoilHUD.lua | HIGH | Bug — wrong constant path for AUTO_RATE_TARGETS |
| 7 | HookManager.lua | HIGH | Edge case — plowing hook arg order needs verification |
| 8 | SoilFertilitySystem.lua | HIGH | Edge case — g_currentMission nil in daily update |
| 9 | SoilFertilitySystem.lua | HIGH | Dead code — onClientJoined() never called |
| 10 | NetworkEvents.lua | HIGH | Bug — stale retry handler on level reload |
| 11 | SoilFertilityManager.lua | MEDIUM | Edge case — delete() order unsafe |
| 12 | SoilFertilitySystem.lua | MEDIUM | Dead code — burnActive never read |
| 13 | SoilFertilitySystem.lua | MEDIUM | Edge case — randomseed affects global state |
| 14 | SoilFertilitySystem.lua | LOW | Edge case — HUD creates fields in singleplayer |
| 15 | SoilHUD.lua | LOW | Edge case — yield uses lastCrop (confirm live crop resolve) |
| 19 | HookManager.lua | LOW | Edge case — field resolved from cab, not boom |
| 20 | SoilHUD.lua | LOW | Dead code — px() unused |
| 22 | HookManager.lua | LOW | Dead code — workingDepth never non-nil |
| 24 | main.lua | MEDIUM | Dead code — SAFE_MODE too broad |
| 25 | NetworkEvents.lua | HIGH | Dead code — full sync never triggered on client join |
| 26 | Multiple | MEDIUM | Polish — DIAG print() not gated by debugMode |
| 27 | SoilFertilitySystem.lua | LOW | Comment — field.fieldId always nil in listAllFields |
| 29 | SoilFertilitySystem.lua | LOW | Polish — unused 30-second timer |
| 30 | Constants.lua | LOW | Dead code — PURCHASABLE_SINGLE_NUTRIENT unused |
| 31 | SoilFertilitySystem.lua | MEDIUM | Polish — info()/warning() bypass SoilLogger |
| 33 | SoilSettingsGUI + main.lua | LOW | Polish — duplicate console command registration |
| 35 | main.lua | LOW | Polish — missing debug log on unknown fill type |