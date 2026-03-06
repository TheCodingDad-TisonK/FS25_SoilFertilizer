<div align="center">

# 🌾 FS25 Soil & Fertilizer
### *Realistic Nutrient Management*

[![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SoilFertilizer/total?style=for-the-badge&logo=github&color=4caf50&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/releases)
[![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SoilFertilizer?style=for-the-badge&logo=tag&color=76c442&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/releases/latest)
[![License](https://img.shields.io/badge/license-CC%20BY--NC--ND%204.0-lightgrey?style=for-the-badge&logo=creativecommons&logoColor=white)](https://creativecommons.org/licenses/by-nc-nd/4.0/)

<br>

> *"Applied liquid fertilizer three seasons straight because the yield looked fine. Then I checked the pH — it was sitting at 5.4. The nutrients I'd been pouring in couldn't even be absorbed. One application of lime later and the next harvest told the whole story."*

<br>

**In base FS25, every field is born equal and stays that way forever. This mod remembers.**

Each field builds its own history. Nitrogen drops after a heavy wheat crop. Rain washes potassium out of sandy ground. Fallow fields slowly breathe back to life. The numbers you see in the HUD aren't arbitrary — they're the consequence of every harvest, every storm, and every bag of fertilizer you did or didn't apply.

`Singleplayer` • `Multiplayer (server-authoritative)` • `Persistent saves` • `10 languages`

</div>

> [!TIP]
> Want to be part of our community? Share tips, report issues, and chat with other farmers on the **[FS25 Modding Community Discord](https://discord.gg/Th2pnq36)**!

---

## ✨ Features

### 🧪 Per-Field Soil Chemistry

Five values tracked independently for every field on the map:

| | Nutrient | Role | Depleted By |
|---|---|---|---|
| 🟢 | **Nitrogen (N)** | Growth and leaf mass | Harvest, rain leaching, fall season |
| 🔵 | **Phosphorus (P)** | Root development and energy | Harvest |
| 🟡 | **Potassium (K)** | Water regulation and yield quality | Harvest, rain leaching |
| 🟤 | **Organic Matter (OM)** | Soil structure and nutrient buffering | Builds slowly via manure and plowing |
| ⚗️ | **pH** | Unlocks nutrient availability | Rain acidification — raised by lime and plowing |

All five values persist in your save. A field that's been growing canola for three seasons without lime will feel different from one you've been managing carefully.

### 🌾 Crop-Specific Extraction

Different crops take different amounts from your soil. Push the same field too hard and it shows.

| Crop | N drain | P drain | K drain | Notes |
|---|---|---|---|---|
| 🥔 Potato | ●●●●● | ●●●● | ●●●●● | Extreme K demand — must rotate |
| 🟣 Sugar Beet | ●●●●○ | ●●●○○ | ●●●●● | Heaviest K of any crop |
| 🌻 Sunflower | ●●●●○ | ●●●○○ | ●●●●○ | Moderate-high all round |
| 🌼 Canola | ●●●●○ | ●●●○○ | ●●●●○ | High N demand, oilseed crop |
| 🫘 Soybean | ●●●●● | ●●●○○ | ●●●○○ | Highest N — partial fixation assumed |
| 🌽 Maize | ●●●●○ | ●●●○○ | ●●●●○ | Large biomass, needs N and K |
| 🌾 Wheat | ●●●○○ | ●●○○○ | ●●●○○ | Moderate — manageable with rotation |
| 🌾 Barley / Oats / Rye | ●●●○○ | ●●○○○ | ●●●○○ | Light feeders, good rotation crops |
| 🫛 Peas / Beans | ●●●●○ | ●●●○○ | ●●●●○ | Legumes — still need balanced soil |

### 💊 Fertilizer Types

Six products, each with a different job:

| Fertilizer | N | P | K | Organic Matter | Notes |
|---|---|---|---|---|---|
| **Liquid Fertilizer** | ●●●○○ | ●●○○○ | ●●●○○ | — | Fast-acting, balanced NPK |
| **Solid Fertilizer** | ●●●●○ | ●●●○○ | ●●●○○ | — | Higher N/P, granular |
| **Manure** | ●●○○○ | ●●○○○ | ●●●○○ | ✓ builds | Slow-release, builds OM over time |
| **Slurry** | ●●●○○ | ●●○○○ | ●●●●○ | ✓ builds | Liquid organic, strong K |
| **Digestate** | ●●●○○ | ●●○○○ | ●●●●○ | ✓ builds | Biogas byproduct, well-rounded |
| **Lime** | — | — | — | — | Only raises pH — but nothing else works properly without it |

> [!NOTE]
> Organic matter builds slowly with manure, slurry, and digestate — it takes many seasons to accumulate meaningfully. Soil with high OM buffers pH swings and slows nutrient loss from rain.

### 🌦️ Environmental Effects

The mod isn't just about what you put in — it's about what the world takes out.

| Effect | What happens |
|---|---|
| 🌧️ **Rain leaching** | Nitrogen and potassium wash out during heavy rain. Phosphorus binds tightly and barely moves. |
| 🍂 **Fall nitrogen loss** | Biological activity slows in autumn, pulling N levels down naturally. |
| 🌱 **Spring nitrogen boost** | Microbial activity picks back up in spring, recovering a small amount of N. |
| 🌧️ **pH acidification** | Rain is slightly acidic. Ignore liming long enough and your soil will show it. |
| 🌾 **Fallow recovery** | Fields left unplanted for 7+ days slowly recover nutrients on their own. |
| 🚜 **Plowing bonus** | Aerates soil, nudging pH toward neutral and boosting organic matter mixing. |

### 📊 Soil HUD

A compact overlay shows the current field's soil status while you're working. Colour-coded indicators make problems visible at a glance:

🟢 **Green** — healthy, no action needed &nbsp;|&nbsp; 🟡 **Amber** — getting low, plan ahead &nbsp;|&nbsp; 🔴 **Red** — depleted, yield is being affected

Fully customisable: 5 positions, 4 colour themes, 5 transparency levels, 3 font sizes, and a compact mode that shrinks to one line per nutrient.

### 📋 Full Farm Soil Report

Press **`K`** to open a field-by-field breakdown of every nutrient, pH, organic matter level, and last crop across your whole farm. Fields flagged red need attention now.

---

## ⚙️ Settings

Open via **ESC → Settings → Game Settings → Soil & Fertilizer**.

| Setting | Options | What it does |
|---|---|---|
| **Enable mod** | On / Off | Stops all simulation when off |
| **Fertility system** | On / Off | Toggles the entire nutrient and pH simulation |
| **Nutrient cycles** | On / Off | Enables crop depletion and natural recovery |
| **Fertilizer costs** | On / Off | Adds running costs to fertilizer application |
| **Notifications** | On / Off | Pop-up alerts when fields get critically low |
| **Seasonal effects** | On / Off | Spring boost and fall nitrogen loss |
| **Rain effects** | On / Off | Leaching and pH acidification from rain |
| **Plowing bonus** | On / Off | Whether plowing improves OM and pH |
| **Difficulty** | Simple / Realistic / Hardcore | Scales depletion rate — 0.7× / 1× / 1.5× |
| **HUD enabled** | On / Off | Show or hide the soil overlay |
| **HUD position** | 5 presets | Top-right, top-left, bottom-right, bottom-left, centre-right |
| **HUD colour theme** | 4 themes | Green / Blue / Amber / Mono |
| **HUD transparency** | Clear → Solid | 5 levels from 25% to 100% opacity |
| **HUD font size** | Small / Medium / Large | Scales all HUD text |
| **Compact mode** | On / Off | One line per nutrient instead of full bars |

> [!NOTE]
> In multiplayer, settings are **server-authoritative** — the host's settings are pushed to all clients on join. Clients cannot override locked settings.

---

## 🖥️ Console Commands

Open the developer console with **`~`** and type `soilfertility` for the full list.

| Command | Arguments | Description |
|---|---|---|
| `SoilEnable` / `SoilDisable` | — | Toggle the mod on or off |
| `SoilSetDifficulty` | `1` `2` `3` | Simple / Realistic / Hardcore |
| `SoilSetFertility` | `true` / `false` | Toggle fertility simulation |
| `SoilSetNutrients` | `true` / `false` | Toggle nutrient cycles |
| `SoilSetFertilizerCosts` | `true` / `false` | Toggle fertilizer costs |
| `SoilSetNotifications` | `true` / `false` | Toggle alert popups |
| `SoilSetSeasonalEffects` | `true` / `false` | Toggle seasonal N changes |
| `SoilSetRainEffects` | `true` / `false` | Toggle rain leaching and acidification |
| `SoilSetPlowingBonus` | `true` / `false` | Toggle plowing OM/pH bonus |
| `SoilFieldInfo` | `<fieldId>` | Detailed soil readout for one field |
| `SoilShowSettings` | — | Print current settings to log |
| `SoilResetSettings` | — | Reset everything to defaults |
| `SoilSaveData` | — | Force-save soil state now |
| `SoilDebug` | — | Toggle verbose debug logging |

---

## 🔌 Mod Integrations

All integrations are detected automatically at runtime and fail gracefully if the mod isn't installed.

| Mod | Behaviour |
|---|---|
| **Precision Farming DLC** | Auto-detected. Enters read-only mode — your PF soil data is displayed in the HUD without modification. No double-tracking, no conflicts. |
| **FS25_SeasonalCropStress** | Soil pH and organic matter influence evapotranspiration rates per field. |
| **FS25_NPCFavor** | NPC neighbour favour quests can reference your fields' soil state. |

---

## 🛠️ Installation

**1. Download** `FS25_SoilFertilizer.zip` from the [latest release](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/releases/latest).

**2. Copy** the ZIP (do not extract) to your mods folder:

| Platform | Path |
|---|---|
| 🪟 Windows | `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\` |
| 🍎 macOS | `~/Library/Application Support/FarmingSimulator2025/mods/` |

**3. Enable** *Realistic Soil & Fertilizer* in the in-game mod manager.

**4. Load** any career save — soil data initialises automatically on first load.

---

## 🎮 Quick Start

```
1. Load your farm — the soil HUD appears in the top-right corner
2. Drive to any field — nutrient values update as you move
3. Amber or red values → that field needs fertilizer or lime
4. Apply lime first — it unlocks the full value of everything else
5. Apply fertilizer → watch N/P/K climb in real time
6. Press K → open the full farm soil report sorted by urgency
7. Let a field go fallow for a season → it slowly recovers on its own
8. At harvest → healthy soil means the full yield you worked for
```

> [!TIP]
> Fields start slightly acidic and with moderate nutrients — matching the base game's starting state. Lime first, then fertilize. Nutrients in acidic soil have reduced availability no matter how much product you apply.

---

## ⚠️ Known Limitations

| Issue | Details |
|---|---|
| 🌱 **Base game lime indicator** | The base game's "needs liming" flag is a separate system from our pH tracking. Both update when you apply lime through the sprayer, but the indicators can show different states until the field is treated. Workaround: disable the base game's liming requirement in **Settings → Farming → Liming** to rely solely on our HUD. |
| 🌐 **Multiplayer** | Soil simulation runs on the server only. Clients receive synced state on join and after each harvest or fertiliser event. |
| 🔬 **Precision Farming** | When PF is detected, the mod enters read-only mode. All nutrient modification hooks are skipped to avoid conflict — PF data is displayed, not overwritten. |

---

## 🤝 Contributing

Found a bug? [Open an issue](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/issues/new/choose) — the template will walk you through what to include.

Want to contribute code? PRs are welcome on the `development` branch. See `CLAUDE.md` in the repo root for architecture notes and naming conventions.

---

## 📝 License

This mod is licensed under **[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)**.

You may share it in its original form with attribution. You may not sell it, modify and redistribute it, or reupload it under a different name or authorship. Contributions via pull request are explicitly permitted and encouraged.

**Author:** TisonK &nbsp;·&nbsp; **Version:** 1.0.8.1

© 2026 TisonK — See [LICENSE](LICENSE) for full terms.

---

<div align="center">

*Farming Simulator 25 is published by GIANTS Software. This is an independent fan creation, not affiliated with or endorsed by GIANTS Software.*

*Your soil remembers everything.* 🌱

</div>
