<div align="center">

# 🌾 FS25 Soil & Fertilizer
### *Realistic Nutrient Management*

[![Downloads](https://img.shields.io/github/downloads/TheCodingDad-TisonK/FS25_SoilFertilizer/total?style=for-the-badge&logo=github&color=4caf50&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/releases)
[![Release](https://img.shields.io/github/v/release/TheCodingDad-TisonK/FS25_SoilFertilizer?style=for-the-badge&logo=tag&color=76c442&logoColor=white)](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/releases/latest)
[![License](https://img.shields.io/badge/license-CC%20BY--NC--ND%204.0-lightgrey?style=for-the-badge&logo=creativecommons&logoColor=white)](https://creativecommons.org/licenses/by-nc-nd/4.0/)
<a href="https://paypal.me/TheCodingDad">
  <img src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" alt="Donate via PayPal" height="50">
</a>

<br>

> *"Applied liquid fertilizer three seasons straight because the yield looked fine. Then I checked the pH — it was sitting at 5.4. The nutrients I'd been pouring in couldn't even be absorbed. One application of lime later and the next harvest told the whole story."*

<br>

**In base FS25, every field is born equal and stays that way forever. This mod remembers.**

Each field builds its own history. Nitrogen drops after a heavy wheat crop. Rain washes potassium out of sandy ground. Fallow fields slowly breathe back to life. The numbers you see in the HUD aren't arbitrary — they're the consequence of every harvest, every storm, and every bag of fertilizer you did or didn't apply.

`Singleplayer` • `Multiplayer (server-authoritative)` • `Persistent saves` • `26 languages`

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

### 🔄 Crop Rotation

The mod tracks the last **3 harvested crops** per field and actively rewards good rotation practice — and penalises lazy mono-cropping.

| Situation | Effect |
|---|---|
| **Legume → Non-legume** (soybean, peas, or beans last season) | +0.5 N/day for the first 3 days of spring — nitrogen fixation carry-over |
| **Same crop two seasons running** | ×1.15 extraction multiplier on that harvest — 15% extra depletion across N, P, and K |
| **Healthy alternation** | No modifier in either direction |

The Soil Report now shows your rotation status per field alongside the nutrient recommendations: *Rotation Bonus*, *Fatigue: Same Crop*, or *Rotation: OK*. History is saved with your savegame and synced in multiplayer. Can be toggled off in settings.

### 🐛 Field Health System

Three pressure scores (0–100) track threats to each field independently. Left unchecked they reduce your yield at harvest. Treat them with the right product and the pressure drops within a few days.

| Pressure | Source | Treatment | Resets naturally | Max penalty |
|----------|--------|-----------|-----------------|-------------|
| 🌿 **Weed** | Grows daily — peaks without tillage | `HERBICIDE` spray | Any tillage / plowing | −30% |
| 🐞 **Pest** | Insects — peaks in summer | `INSECTICIDE` spray | Harvest disperses population | −20% |
| 🍄 **Disease** | Fungal — driven by rain | `FUNGICIDE` spray | 3+ dry days cause natural decay | −25% |

All three are visible in the HUD and the full Soil Report. Each can be toggled off in settings.

### 💊 Fertilizer Types

25+ products tracked, each with a different nutrient job.

**Base game (always available):**

| Fertilizer | N | P | K | Organic Matter | Notes |
|---|---|---|---|---|---|
| **Liquid Fertilizer** | ●●●○○ | ●●○○○ | ●●●○○ | — | Fast-acting, balanced NPK |
| **Solid Fertilizer** | ●●●●○ | ●●●○○ | ●●●○○ | — | Higher N/P, granular |
| **Manure** | ●●○○○ | ●●○○○ | ●●●○○ | ✓ | Slow-release, builds OM over time |
| **Slurry** | ●●●○○ | ●●○○○ | ●●●●○ | ✓ | Liquid organic, strong K |
| **Digestate** | ●●●○○ | ●●○○○ | ●●●●○ | ✓ | Biogas byproduct, well-rounded |
| **Lime** | — | — | — | — | Only raises pH — but nothing else works properly without it |

**Custom dry/liquid (purchasable big bags in shop):**

| Product | Type | Primary benefit |
|---|---|---|
| UAN-32 / UAN-28 | Liquid nitrogen | Highest N/L of liquid sources |
| Anhydrous Ammonia | Liquid nitrogen | Maximum N concentration |
| Urea / AMS | Dry nitrogen | Standard granular N sources |
| MAP / DAP | Dry P+N | Phosphorus-focused blends |
| Potash | Dry K | Pure potassium supplement |
| Starter 10-34-0 | Liquid P | In-furrow high-P starter |

**Liquid equivalents for sprayer compatibility (purchasable big bags in shop):**

All five dry granular products above have a liquid equivalent that works in standard sprayers instead of spreaders.

| Product | Type | Primary benefit |
|---|---|---|
| Liquid Urea | Liquid N | Dissolved urea for sprayer application |
| Liquid AMS | Liquid N | Liquid ammonium sulphate |
| Liquid MAP | Liquid P+N | High-P liquid blend |
| Liquid DAP | Liquid P+N | Liquid DAP equivalent |
| Liquid Potash | Liquid K | Dissolved potassium for sprayers |

**Organic / soil amendments (registered, obtained from compatible mods or production lines):**

| Product | Application | N | P | K | OM | Notes |
|---|---|---|---|---|---|---|
| **Compost** | Spreader | Low | Low | Low | ●●●●● | Best OM builder per litre |
| **Biosolids** | Spreader | ●●○○○ | ●●○○○ | Low | ✓ | Municipal organic amendment |
| **Chicken Manure** | Spreader | ●●●○○ | ●●●○○ | ●●○○○ | ✓ | Concentrated poultry litter |
| **Pelletized Manure** | Spreader | ●●●●○ | ●●●●○ | ●●●●○ | ✓ | Dense balanced organic NPK |
| **Gypsum** | Spreader | — | — | — | Low | pH correction, minor OM gain |
| **Liquid Lime** | Sprayer | — | — | — | — | Raises pH via sprayer equipment |

> [!NOTE]
> Organic matter builds slowly — it takes many seasons to accumulate meaningfully. Soil with high OM buffers pH swings and slows nutrient loss from rain.

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

Press **`K`** to open a full farm overview sorted by urgency — the fields that need the most attention appear at the top. Each row shows N/P/K, pH, OM, weed and pest pressure, and an overall status badge. Click **►** on any row to open a field detail view with a complete breakdown, yield forecast, and specific treatment recommendations.

### 📱 Soil PDA Page

Press **`Shift+P`** to open the dedicated Soil & Fertilizer page inside the FS25 in-game menu (PDA). Accessible any time — on foot, in a vehicle, or while paused.

**Left sidebar** — live farm-wide snapshot updated each time the page opens:
- Fields tracked and fields owned
- Average N, P, K, pH, and Organic Matter across all your fields
- Weed, Pest, and Disease pressure field counts
- Fields currently below fertilizer threshold

**Two tabs:**

| Tab | What you see |
|---|---|
| **Farm Overview** | Full list of every tracked field — N%, P%, K%, pH, OM, and an overall status badge. Click any row to open a per-field detail popup |
| **Treatment Plan** | Fields sorted by urgency (worst first) with the primary deficiency or pressure identified. Minor-urgency fields grouped at the bottom |

The interactive **Soil Map overlay** lives in the native PDA Map (ESC → Map). Use the sidebar to select and cycle overlay layers (Nitrogen, Phosphorus, Potassium, pH, OM, Weed, Pest, Disease) without leaving the game map.

**Field Detail popup** (click any row in Farm Overview or Treatment Plan):
- All five nutrient values with colour-coded Good / Fair / Poor status
- Weed, Pest, and Disease pressure — asterisk (`*`) shown when a protection product is active
- Last harvested crop and crop rotation status (Legume Bonus / Fatigue / OK)

---

## ⚙️ Settings

Settings are split across two places.

### ESC → Settings → Game Settings → Soil & Fertilizer

Three core settings live here so you can reach them quickly:

| Setting | Options | What it does |
|---|---|---|
| **Enable mod** | On / Off | Stops all simulation when off |
| **Notifications** | On / Off | Pop-up alerts when fields get critically low |
| **Debug mode** | On / Off | Verbose logging to the game log |

### SHIFT+O — Full Settings Panel

Press **`Shift+O`** anywhere in-game (on foot or in a vehicle) to open the full settings panel. Settings are organised into three categories:

**🌱 Simulation** — controls the core simulation behaviour

| Setting | Options | What it does |
|---|---|---|
| **Fertility system** | On / Off | Toggles the entire nutrient and pH simulation |
| **Nutrient cycles** | On / Off | Enables crop depletion and natural recovery |
| **Fertilizer costs** | On / Off | Adds running costs to fertilizer application |
| **Seasonal effects** | On / Off | Spring nitrogen boost and fall nitrogen loss |
| **Rain effects** | On / Off | Leaching and pH acidification from rain |
| **Plowing bonus** | On / Off | Whether plowing improves OM and pH |
| **Weed pressure** | On / Off | Track weed competition per field |
| **Pest pressure** | On / Off | Track insect pest populations per field |
| **Disease pressure** | On / Off | Track crop disease per field |
| **Crop rotation** | On / Off | Enable legume bonus and mono-crop fatigue multiplier |
| **Imperial units** | On / Off | Sprayer rates in gal/ac and lb/ac instead of L/ha and kg/ha |
| **Difficulty** | Simple / Realistic / Hardcore | Scales depletion rate — 0.7× / 1× / 1.5× |

**🖥️ Display / HUD** — controls what you see on screen

| Setting | Options | What it does |
|---|---|---|
| **HUD enabled** | On / Off | Show or hide the soil overlay |
| **HUD position** | 6 options | Top-right, top-left, bottom-right, bottom-left, centre-right, or custom |
| **HUD colour theme** | 4 themes | Green / Blue / Amber / Mono |
| **HUD transparency** | Clear → Solid | 5 opacity levels |
| **HUD font size** | Small / Medium / Large | Scales all HUD text |
| **Auto rate control** | On / Off | Sprayer rate auto-adjusts toward the target rate for the current product |

**🗺️ Map** — controls the PDA map overlay

| Setting | Options | What it does |
|---|---|---|
| **Active map layer** | N / P / K / pH / OM / Weed / Pest / Disease | Nutrient layer shown on the PDA map |

> [!NOTE]
> In multiplayer, settings are **server-authoritative** — the host's settings are pushed to all clients on join. Non-admin clients can see but not change server settings. HUD display preferences are always local and can be changed by any player.

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
| `SoilFieldForecast` | `<fieldId>` | Yield forecast and treatment recommendations for one field |
| `SoilListFields` | — | List all tracked fields with current soil values |
| `SoilShowSettings` | — | Print current settings to log |
| `SoilResetSettings` | — | Reset everything to defaults |
| `SoilSaveData` | — | Force-save soil state now |
| `SoilDebug` | — | Toggle verbose debug logging |

---

## 🔌 Mod Integrations

All integrations are detected automatically at runtime and fail gracefully if the mod isn't installed.

| Mod | Behaviour |
|---|---|
| **Precision Farming DLC** | Compatible — both mods run independently. No conflicts. |
| **FS25_SeasonalCropStress** | Soil pH and organic matter influence evapotranspiration rates per field. |
| **FS25_NPCFavor** | NPC neighbour favour quests can reference your fields' soil state. |
| **FS25_MoistureSystem** | Compatible — both mods use independent hooks. No conflicts. |

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
7. Press Shift+O → open the full settings panel to tune the simulation
8. Let a field go fallow for a season → it slowly recovers on its own
9. At harvest → healthy soil means the full yield you worked for
```

> [!TIP]
> Fields start slightly acidic and with moderate nutrients — matching the base game's starting state. Lime first, then fertilize. Nutrients in acidic soil have reduced availability no matter how much product you apply.

---

## ⚠️ Known Limitations

| Issue | Details |
|---|---|
| 🌱 **Base game lime indicator** | The base game's "needs liming" flag is a separate system from our pH tracking. Both update when you apply lime through the sprayer, but the indicators can show different states until the field is treated. Workaround: disable the base game's liming requirement in **Settings → Farming → Liming** to rely solely on our HUD. |
| 🌐 **Multiplayer** | Soil simulation runs on the server only. Clients receive synced state on join and after each harvest or fertiliser event. |
| 🔬 **Precision Farming** | Compatible — both mods track nutrients independently. No conflicts. |

---

## 🤝 Contributing

Found a bug? [Open an issue](https://github.com/TheCodingDad-TisonK/FS25_SoilFertilizer/issues/new/choose) — the template will walk you through what to include.

Want to contribute code? PRs are welcome on the `development` branch. See `CLAUDE.md` in the repo root for architecture notes and naming conventions.

---

## 📝 License

This mod is licensed under **[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/)**.

You may share it in its original form with attribution. You may not sell it, modify and redistribute it, or reupload it under a different name or authorship. Contributions via pull request are explicitly permitted and encouraged.

**Author:** TisonK &nbsp;·&nbsp; **Version:** 1.9.2.0

© 2026 TisonK — See [LICENSE](LICENSE) for full terms.

---

<div align="center">

*Farming Simulator 25 is published by GIANTS Software. This is an independent fan creation, not affiliated with or endorsed by GIANTS Software.*

*Your soil remembers everything.* 🌱

</div>
