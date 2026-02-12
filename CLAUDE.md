# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FS25_SoilFertilizer is a Farming Simulator 25 mod (Lua) that adds realistic soil nutrient management. It tracks Nitrogen, Phosphorus, Potassium, Organic Matter, and pH per field, with crop-specific depletion, fertilizer replenishment, weather effects, and seasonal cycles. Fully supports multiplayer with admin-only settings enforcement.

## Git Workflow

- **Work branch:** `development` — all commits and pushes go here.
- **Stable branch:** `main` — only updated via pull requests from `development`.
- Never commit or push directly to `main`. Always work on `development` and PR to `main`.

## Commit Rules

- Do NOT include `Co-Authored-By` lines or any AI/Claude Code advertisement in commit messages.
- Keep commit messages concise and focused on what changed.

## Development & Deployment

There is no build system. The mod is loaded directly by FS25 from the mod folder:
- **Install location:** `Documents/My Games/FarmingSimulator25/mods/FS25_SoilFertilizer/`
- **Entry point:** `modDesc.xml` references `src/main.lua`
- **Distribution:** Packaged as `FS25_SoilFertilizer.zip`
- **Testing:** Launch FS25, load a savegame with the mod enabled. Use console commands (e.g., `soilfertility`, `SoilFieldInfo <id>`, `SoilShowSettings`) for debugging.

## Architecture

```
main.lua                         -- FS25 lifecycle hooks (load/unload/update), delayed GUI injection
  └─ SoilFertilityManager.lua    -- Orchestrator: init order is Settings → System → GUI → Network
       ├─ Settings.lua           -- 9 boolean toggles + 1 difficulty enum (Simple/Realistic/Hardcore)
       │   └─ SettingsManager.lua -- XML persistence to savegame directory
       ├─ SoilFertilitySystem.lua -- Core simulation engine, game hook installation
       ├─ SoilSettingsUI.lua     -- In-game settings menu integration
       │   └─ UIHelper.lua       -- UI element factories (toggles, dropdowns, sections)
       ├─ SoilSettingsGUI.lua    -- Console command handlers (15+ commands)
       └─ NetworkEvents.lua      -- 4 event types for multiplayer sync
```

### Key Patterns

- **Hook injection:** Uses `Utils.appendedFunction`/`Utils.prependedFunction` to hook into FS25's `FruitUtil`, `Sprayer`, `FieldManager`, and environment update systems.
- **Delayed GUI setup:** GUI injection is deferred 3+ seconds after mission load to ensure game UI systems are ready.
- **Server/client detection:** Disables GUI on dedicated servers; uses direct settings updates in singleplayer vs. network events in multiplayer.
- **Precision Farming compatibility:** Auto-detects PF mod and enters read-only mode (displays data but doesn't modify soil).
- **Config flags:** `config.txt` has `DISABLE_GUI`, `DISABLE_MOD`, `PF_COMPATIBILITY`, `DEBUG` flags.

### Core Simulation (SoilFertilitySystem)

- `fieldData[fieldId]` stores per-field nutrients, pH, lastCrop, lastHarvest, fertilizerApplied
- Crop extraction rates for 16+ crop types; difficulty multipliers (0.7x/1x/1.5x)
- Fertilizer types (liquid, solid, manure, slurry, digestate, lime) with different nutrient profiles
- Environmental: rain causes nutrient leaching, seasons affect nitrogen, fallow fields slowly recover
- Update loop throttled to 30-second intervals; daily updates on game-day change
- Data persisted to `soilData.xml` in savegame directory

### Multiplayer Network Flow

Client settings change → `SoilSettingChangeEvent` to server → server validates admin status → applies & saves → broadcasts `SoilSettingSyncEvent` to all clients. Full sync available via `SoilRequestFullSyncEvent`/`SoilFullSyncEvent`.

## Localization

`modDesc.xml` contains translations for 10 languages (en, de, fr, pl, es, it, cz, br, uk, ru). When adding new user-facing strings, add entries for all languages in the `<l10n>` section.
