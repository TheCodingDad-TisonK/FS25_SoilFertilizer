# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

**FS25_SoilFertilizer** is a Farming Simulator 25 mod that adds realistic soil nutrient management. It tracks Nitrogen, Phosphorus, Potassium, Organic Matter, and pH per field, with crop-specific depletion, fertilizer replenishment, weather effects, and seasonal cycles. Current version: **1.0.2.0**. Fully supports multiplayer with admin-only settings enforcement. 10-language localization inline in `modDesc.xml`.

---

## Quick Reference

| Resource | Location |
|----------|----------|
| **Mods Base Directory** | `C:\Users\tison\Desktop\FS25 MODS` |
| Active Mods (installed) | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods` |
| Game Log | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\log.txt` |
| **GIANTS Editor** | `C:\Program Files\GIANTS Software\GIANTS_Editor_10.0.11\editor.exe` |

### Mod Projects

All mods live under the **Mods Base Directory** above:

| Mod Folder | Description |
|------------|-------------|
| `FS25_SoilFertilizer` | Soil & fertilizer mechanics *(this repo)* |
| `FS25_NPCFavor` | NPC neighbors with AI, relationships, favor quests |
| `FS25_IncomeMod` | Income system mod |
| `FS25_TaxMod` | Tax system mod |
| `FS25_WorkerCosts` | Worker cost management |
| `FS25_FarmTablet` | In-game farm tablet UI |
| `FS25_AutonomousDroneHarvester` | Autonomous drone harvesting |
| `FS25_RandomWorldEvents` | Random world event system |
| `FS25_RealisticAnimalNames` | Realistic animal naming |

---

## Git Workflow

- **Work branch:** `development` — all commits and pushes go here.
- **Stable branch:** `main` — only updated via pull requests from `development`.
- Never commit or push directly to `main`. Always work on `development` and PR to `main`.

---

## Architecture

### Entry Point & Module Loading

`modDesc.xml` declares a single `<sourceFile filename="src/main.lua" />`. `main.lua` uses `source()` to load all 14 modules in strict dependency order across 5 phases:

1. **Utilities & Config** — `Logger.lua`, `Constants.lua`, `SettingsSchema.lua`
2. **Core Systems** — `HookManager.lua`, `SoilFertilitySystem.lua`, `SoilFertilityManager.lua`
3. **Settings** — `SettingsManager.lua`, `Settings.lua`, `SoilSettingsGUI.lua`
4. **UI** — `UIHelper.lua`, `SoilSettingsUI.lua`
5. **Network** — `NetworkEvents.lua`

**Adding a new module:** Add the `source()` call in `main.lua` at the correct phase. The loading order matters — utilities and config must load before everything else, settings before UI, etc.

### Central Coordinator: SoilFertilityManager

`SoilFertilityManager` owns all subsystems:

```
SoilFertilityManager (g_SoilFertilityManager)
  ├── settings          : Settings
  ├── settingsManager   : SettingsManager
  ├── soilSystem        : SoilFertilitySystem
  │     └── hookManager : HookManager
  ├── settingsUI        : SoilSettingsUI
  ├── settingsGUI       : SoilSettingsGUI
  └── (network events registered globally)
```

Global reference: `g_SoilFertilityManager` (set via `getfenv(0)`).

### Game Hook Pattern

`main.lua` hooks into FS25 lifecycle via `Utils.prependedFunction` / `Utils.appendedFunction`:

| Hook | Purpose |
|------|---------|
| `Mission00.load` | Create `SoilFertilityManager` instance |
| `Mission00.loadMission00Finished` | Post-load initialization, MP sync request |
| `FSBaseMission.update` | Per-frame update + delayed GUI injection |
| `FSBaseMission.delete` | Cleanup |
| `Mission00.saveToXMLFile` | Save soil data (server only) |
| `Mission00.loadFromXMLFile` | Load soil data |

### HookManager

`HookManager` handles installation and cleanup of 4 game hooks:

| Hook | Target | Purpose |
|------|--------|---------|
| Harvest | `FruitUtil` | Deplete nutrients on crop harvest |
| Sprayer | `Sprayer` | Restore nutrients on fertilizer application |
| Ownership | `FieldManager` | Clean up field data on ownership change |
| Weather | `environment.update` | Rain leaching, seasonal effects |

All hooks use `Utils.appendedFunction` for mod compatibility. `HookManager:uninstallAll()` is called on mod unload to prevent hook accumulation.

### Settings System

`SettingsSchema.lua` is the **single source of truth** for all settings. Each setting is defined once with `{id, type, default, uiId, pfProtected}`. This drives:
- `SettingsManager` — auto-generates XML load/save
- `Settings` — auto-generates defaults and validation
- `SoilSettingsUI` — auto-generates in-game UI elements

**Adding a new setting:** Add one entry to `SettingsSchema.definitions` + translations in `modDesc.xml`.

### Multiplayer Network Flow

| Event | Direction | Purpose |
|-------|-----------|---------|
| `SoilSettingChangeEvent` | Client → Server | Setting change request (admin validated) |
| `SoilSettingSyncEvent` | Server → Clients | Broadcast setting changes |
| `SoilRequestFullSyncEvent` | Client → Server | Request full state on join |
| `SoilFullSyncEvent` | Server → Client | Full settings + field data snapshot |
| `SoilFieldUpdateEvent` | Server → Clients | Per-field soil data sync on harvest/fertilize |

Full sync has retry logic: 3 attempts at 5-second intervals.

### Save/Load

- **Soil data:** `{savegameDirectory}/soilData.xml` — per-field N/P/K/OM/pH, lastCrop, lastHarvest, fertilizerApplied
- **Settings:** `{savegameDirectory}/FS25_SoilFertilizer.xml` — all settings from schema
- Save path discovered via `g_currentMission.missionInfo.savegameDirectory`

### Core Simulation (SoilFertilitySystem)

- `fieldData[fieldId]` stores per-field nutrients, pH, lastCrop, lastHarvest, fertilizerApplied
- Crop extraction rates for 16+ crop types; difficulty multipliers (0.7x/1x/1.5x)
- Fertilizer types (liquid, solid, manure, slurry, digestate, lime) with different nutrient profiles
- Environmental: rain causes nutrient leaching, seasons affect nitrogen, fallow fields slowly recover
- Update loop throttled to 30-second intervals; daily updates on game-day change
- Precision Farming compatibility: auto-detects PF mod and enters read-only mode

### Constants

All tunable values live in `src/config/Constants.lua` (`SoilConstants` global). Categories: `TIMING`, `DIFFICULTY`, `FIELD_DEFAULTS`, `NUTRIENT_LIMITS`, `FALLOW_RECOVERY`, `SEASONAL_EFFECTS`, `PH_NORMALIZATION`, `RAIN`, `CROP_EXTRACTION`, `FERTILIZER_PROFILES`, `STATUS_THRESHOLDS`, `NETWORK`.

---

## What DOESN'T Work (FS25 Lua 5.1 Constraints)

| Pattern | Problem | Solution |
|---------|---------|----------|
| `goto` / labels | FS25 = Lua 5.1 (no goto) | Use `if/else` or early `return` |
| `continue` | Not in Lua 5.1 | Use guard clauses |
| `os.time()` / `os.date()` | Not available in FS25 sandbox | Use `g_currentMission.time` / `.environment.currentDay` |
| `Slider` widgets | Unreliable events | Use quick buttons or `MultiTextOption` |
| `DialogElement` base | Deprecated | Use `MessageDialog` pattern |
| Dialog XML naming callbacks `onClose`/`onOpen` | System lifecycle conflict | Use different callback names |

---

## Console Commands

Type `soilfertility` in the developer console (`~` key) for the full list. Key commands:

| Command | Description |
|---------|-------------|
| `soilfertility` | Show all commands |
| `SoilShowSettings` | Show current settings |
| `SoilEnable` / `SoilDisable` | Toggle mod |
| `SoilSetDifficulty 1\|2\|3` | Set difficulty (Simple/Realistic/Hardcore) |
| `SoilSetFertility true\|false` | Toggle fertility system |
| `SoilSetNutrients true\|false` | Toggle nutrient cycles |
| `SoilSetFertilizerCosts true\|false` | Toggle fertilizer costs |
| `SoilSetNotifications true\|false` | Toggle notifications |
| `SoilSetSeasonalEffects true\|false` | Toggle seasonal effects |
| `SoilSetRainEffects true\|false` | Toggle rain effects |
| `SoilSetPlowingBonus true\|false` | Toggle plowing bonus |
| `SoilFieldInfo <fieldId>` | Show field soil info |
| `SoilResetSettings` | Reset to defaults |
| `SoilSaveData` | Force save soil data |
| `SoilDebug` | Toggle debug mode |

---

## Localization

All i18n strings are inline in `modDesc.xml` under `<l10n>` (not separate translation files). 10 languages: en, de, fr, pl, es, it, cz, br, uk, ru. Access via `g_i18n:getText("key_name")`.

---

## File Size Rule: 1500 Lines

If a file exceeds 1500 lines, refactor it into smaller modules with clear single responsibilities. Update `main.lua` source order accordingly.

---

## No Branding / No Advertising

- **Never** add "Generated with Claude Code", "Co-Authored-By: Claude", or any claude.ai links to commit messages, PR descriptions, code comments, or any other output.
- **Never** advertise or reference Anthropic, Claude, or claude.ai in any project artifacts.
- This mod is by its human author(s) — keep it that way.
