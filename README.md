# Realistic Soil & Fertilizer Mod for Farming Simulator 25
![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SoilFertilizer/total?style=for-the-badge)
![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SoilFertilizer?style=for-the-badge)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red?style=for-the-badge)

## Overview
The **Realistic Soil & Fertilizer Mod** adds depth and realism to soil management and fertilization in Farming Simulator 25. This mod introduces dynamic soil fertility, nutrient cycles, and realistic fertilizer economics, making farming more challenging and rewarding.

## Features

### 🌱 **Dynamic Soil Fertility System**
- Tracks nitrogen, phosphorus, and potassium levels for each field
- Soil nutrients deplete naturally as crops grow
- Different crops extract different amounts of nutrients
- Visual feedback on soil health status

### 🔄 **Realistic Nutrient Cycles**
- Nutrients are consumed by crops during growth
- Natural replenishment occurs when fields are fallow
- Organic matter content affects long-term fertility
- pH levels impact nutrient availability

### 💰 **Realistic Fertilizer Economics**
- Different fertilizer types have varying costs and effectiveness:
  - Liquid Fertilizer: Balanced nutrients, moderate cost
  - Solid Fertilizer: Higher phosphorus, standard cost
  - Manure: Improves organic matter, lower cost
- Costs scale with difficulty level
- Strategic fertilizer planning becomes essential

### ⚙️ **Customizable Settings**
- **Difficulty Levels:**
  - Simple: Reduced nutrient depletion, lower costs
  - Realistic: Balanced gameplay, standard settings
  - Hardcore: Rapid nutrient depletion, higher costs
- **System Toggles:**
  - Enable/disable fertility system
  - Toggle nutrient cycles
  - Control fertilizer costs
  - Manage notifications

### 🎮 **User-Friendly Interface**
- Integrated into game settings menu
- Console commands for advanced control
- Real-time notifications for low nutrients
- Field-specific soil information

### 🌐 **Multiplayer Support**
- Fully compatible with multiplayer games
- Settings sync properly between players
- No conflicts with other mods

## Installation

### Automatic Installation (Recommended)
1. Download the mod archive from KingMods or ModHub
2. Extract the `FS25_SoilFertilizer` folder to your mods directory:
   - **Windows:** `Documents/My Games/FarmingSimulator25/mods/`
   - **Mac:** `~/Documents/My Games/FarmingSimulator25/mods/`
   - **Linux:** `~/.local/share/FarmingSimulator25/mods/`

### Manual Installation
1. Create a folder named `FS25_SoilFertilizer` in your mods directory
2. Copy all files from the mod archive into this folder
3. Ensure the folder structure matches:
   ```
   FS25_SoilFertilizer/
   ├── modDesc.xml
   ├── icon.dds
   └── src/
       ├── main.lua
       ├── ...
   ```

## Configuration

### In-Game Settings
1. Open the game menu
2. Navigate to **Settings → General**
3. Find the **"Soil & Fertilizer"** section
4. Adjust settings to your preference

### Console Commands
Open the console with `~` key and use these commands:

| Command | Description |
|---------|-------------|
| `soilfertility` | Show all available commands |
| `SoilEnable/Disable` | Toggle the mod on/off |
| `SoilSetDifficulty 1/2/3` | Set difficulty (1=Simple, 2=Realistic, 3=Hardcore) |
| `SoilSetFertility true/false` | Toggle fertility system |
| `SoilSetNutrients true/false` | Toggle nutrient cycles |
| `SoilSetFertilizerCosts true/false` | Toggle fertilizer costs |
| `SoilSetNotifications true/false` | Toggle notifications |
| `SoilFieldInfo <fieldId>` | Show soil info for specific field |
| `SoilShowSettings` | Display current settings |
| `SoilResetSettings` | Reset to default settings |

## Gameplay Tips

### Managing Soil Health
1. **Monitor Nutrients:** Check field nutrient levels regularly
2. **Rotate Crops:** Different crops have different nutrient needs
3. **Use Manure:** Improves organic matter for long-term fertility
4. **Leave Fields Fallow:** Allows natural nutrient recovery
5. **Test Soil:** Use console commands to check specific fields

### Fertilizer Strategy
1. **Liquid Fertilizer:** Best for balanced nutrient boost
2. **Solid Fertilizer:** Use when phosphorus is particularly low
3. **Manure:** Excellent for improving organic matter content
4. **Timing:** Apply fertilizer before planting for best results
5. **Budget:** Plan fertilizer purchases as part of farm expenses

## Technical Details

### System Requirements
- **Game Version:** Farming Simulator 25 (v1.0 or higher)
- **Platform:** PC, Mac, Linux
- **Multiplayer:** Fully supported
- **Mod Conflicts:** None known

### Performance Impact
- Minimal performance impact
- Memory usage: ~10-20MB
- CPU usage: Negligible
- No impact on save game size

### Compatibility
- ✅ Compatible with all base game features
- ✅ Works with most other mods
- ✅ Save game compatible
- ✅ Multiplayer compatible
- ✅ Works on all maps

## Troubleshooting

### Common Issues
1. **Mod not appearing in game:**
   - Ensure mod is in correct folder
   - Check game.log for loading errors
   - Verify mod is enabled in mod manager

2. **Settings not saving:**
   - Ensure you have write permissions
   - Check for conflicting mods
   - Try resetting settings to default

3. **Console commands not working:**
   - Ensure mod is enabled
   - Check spelling of commands
   - Verify mod initialized properly

### Error Reporting
If you encounter issues:
1. Check the `game.log` file for error messages
2. Note what you were doing when the issue occurred
3. Report on KingMods with:
   - Game version
   - Other mods installed
   - Error messages from game.log

## Development

### Source Code
The mod is written in Lua and follows Farming Simulator 25's modding guidelines. Source code is included for transparency and educational purposes.

### Contributing
While this is a personal project, suggestions and feedback are welcome.

### Credits
- **Author:** TisonK

## Version History

### v1.0.3.1 (2026-02-14)
**Bug Fixes:**
- Fixed mod compatibility issues with multiple mods installed (Issues #20, #21)
- Improved UI template search with validation and caching
- Added defensive element cloning to prevent crashes when other mods modify the layout
- Fixed white screen/broken display menu when used with CropRotation, RealisticHarvesting, and other UI mods
- Better error messages for debugging template search failures

**Technical Improvements:**
- Template validation before caching
- Template caching for consistency across multi-mod environments
- Post-clone validation to catch structural issues
- Cache reset on retry to handle mod load order changes

### v1.0.3.0 (2026-02-14)
- Improved GUI injection reliability
- Fixed multiplayer settings synchronization
- Fixed packaging structure

### v1.0.2.0
- Initial stable release
- Full multiplayer support
- 10-language localization
- Precision Farming compatibility

## Support
For support, questions, or feedback:
- Comment on the KingMods page
- Create a issue on this Github Repo
- Review troubleshooting guide above


**Enjoy more realistic farming with the Soil & Fertilizer Mod!**
