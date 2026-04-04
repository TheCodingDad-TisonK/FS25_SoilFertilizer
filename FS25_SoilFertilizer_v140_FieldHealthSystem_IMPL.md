# FS25_SoilFertilizer — v1.4.0 Field Health System
## Implementation Specification (claude.ai handoff document)

**Mod version to produce:** 1.4.0  
**Branch:** `development`  
**Repo:** TheCodingDad-TisonK/FS25_SoilFertilizer  
**Working directory:** `C:\Users\tison\Desktop\FS25 MODS\FS25_SoilFertilizer`

---

## What you are implementing

Three per-field pressure scores (0–100) tracking crop health threats:

| Pressure | Fill type to apply | Resets via | Max yield penalty |
|----------|--------------------|------------|-------------------|
| Weed (already coded) | `HERBICIDE` | Tillage/plow | −30% |
| **Pest** (new) | `INSECTICIDE` | Harvest event | −20% |
| **Disease** (new) | `FUNGICIDE` | Dry weather | −25% |

Weed pressure is **fully implemented** in constants and simulation code. **Do not touch weed pressure code.** You are adding pest and disease alongside it, following the exact same patterns.

---

## Files to modify (in this order)

1. `src/config/Constants.lua` — add constants
2. `src/config/SettingsSchema.lua` — add two new settings
3. `src/SoilFertilitySystem.lua` — add daily growth, apply on spray, reset on harvest, expose in getFieldInfo
4. `src/network/NetworkEvents.lua` — add two fields to SoilFullSyncEvent and SoilFieldUpdateEvent
5. `modDesc.xml` — add two fill types + two l10n settings keys
6. `translations/translation_en.xml` (and all 25 other language files) — add new setting keys

---

## 1. Constants.lua

**File:** `src/config/Constants.lua`  
**Insert after the `WEED_PRESSURE` block (after line ~562).**

```lua
-- ========================================
-- PEST PRESSURE
-- ========================================
-- Per-field 0-100 insect/pest infestation score.
-- Grows daily, peaks in summer, rain accelerates it.
-- Insecticide spray reduces pressure and suppresses regrowth.
-- Harvest disperses the pest population (resets to 30% of current).
SoilConstants.PEST_PRESSURE = {
    -- Daily base growth rate (points/day) by current pressure tier
    GROWTH_RATE_LOW    = 0.8,   -- 0-20:  slow colonisation phase
    GROWTH_RATE_MID    = 1.5,   -- 20-50: active infestation
    GROWTH_RATE_HIGH   = 1.0,   -- 50-75: density self-limiting
    GROWTH_RATE_PEAK   = 0.3,   -- 75-100: near carrying capacity

    -- Seasonal growth multipliers (season index: 1=Spring 2=Summer 3=Fall 4=Winter)
    SEASONAL_SPRING = 1.1,
    SEASONAL_SUMMER = 1.8,   -- peak insect activity
    SEASONAL_FALL   = 0.6,
    SEASONAL_WINTER = 0.05,  -- near dormancy

    -- Rain bonus added to base daily rate when raining
    RAIN_BONUS = 0.3,

    -- Crop susceptibility multipliers (lowercased fruitDesc.name → multiplier)
    -- Any crop NOT listed here defaults to 1.0
    CROP_SUSCEPTIBILITY = {
        potato    = 1.4,
        sugarbeet = 1.4,
        canola    = 1.4,
        soybean   = 1.3,
        maize     = 1.2,
        sunflower = 1.2,
        wheat     = 0.8,
        barley    = 0.7,
        oats      = 0.7,
        rye       = 0.7,
        sorghum   = 0.7,
    },

    -- Insecticide fill type names → effectiveness multiplier (0.0-1.0)
    INSECTICIDE_TYPES = {
        INSECTICIDE = 1.0,
    },
    -- Pressure points removed on a single insecticide application
    INSECTICIDE_PRESSURE_REDUCTION = 25,
    -- Days insecticide suppresses pest growth after application
    INSECTICIDE_DURATION_DAYS = 10,

    -- On harvest: pest pressure resets to this fraction of current value
    -- (insects disperse when the host crop is removed)
    HARVEST_RESET_FRACTION = 0.30,

    -- Harvest yield penalty at each pressure tier
    YIELD_PENALTY_LOW    = 0.00,  -- 0-20:  none
    YIELD_PENALTY_MID    = 0.05,  -- 20-50: -5%
    YIELD_PENALTY_HIGH   = 0.12,  -- 50-75: -12%
    YIELD_PENALTY_PEAK   = 0.20,  -- 75-100: -20%

    -- HUD tier thresholds (mirrors WEED_PRESSURE)
    LOW    = 20,
    MEDIUM = 50,
    HIGH   = 75,
}

-- ========================================
-- DISEASE PRESSURE
-- ========================================
-- Per-field 0-100 fungal/crop disease score.
-- Rain is the primary driver. Peaks in spring and fall.
-- Fungicide spray reduces pressure and suppresses regrowth.
-- Extended dry weather causes natural decay.
SoilConstants.DISEASE_PRESSURE = {
    -- Daily base growth rate (points/day) by current pressure tier
    GROWTH_RATE_LOW    = 0.6,   -- 0-20:  initial infection
    GROWTH_RATE_MID    = 1.2,   -- 20-50: active spread
    GROWTH_RATE_HIGH   = 0.8,   -- 50-75: density self-limiting
    GROWTH_RATE_PEAK   = 0.2,   -- 75-100: near maximum

    -- Seasonal growth multipliers (season: 1=Spring 2=Summer 3=Fall 4=Winter)
    SEASONAL_SPRING = 1.5,   -- fungal window: cool+moist
    SEASONAL_SUMMER = 0.9,
    SEASONAL_FALL   = 1.3,   -- second fungal window
    SEASONAL_WINTER = 0.1,

    -- Rain is the primary driver: extra points/day added during active rain
    RAIN_BONUS = 1.0,

    -- Dry weather decay: pressure points lost per day when it has NOT rained
    -- for DRY_DAYS_THRESHOLD consecutive days.
    -- NOTE: tracking consecutive dry days requires a new field: `field.dryDayCount`
    -- (integer, default 0). Increment each day without rain, reset to 0 on rain.
    DRY_DAYS_THRESHOLD = 3,    -- after this many dry days, decay begins
    DRY_DECAY_RATE     = 0.5,  -- pts/day removed during dry period

    -- Crop susceptibility multipliers (lowercased fruitDesc.name → multiplier)
    CROP_SUSCEPTIBILITY = {
        wheat     = 1.3,   -- fusarium / septoria risk
        canola    = 1.3,   -- sclerotinia risk
        potato    = 1.4,   -- blight risk
        soybean   = 1.2,
        maize     = 1.1,
        barley    = 0.8,
        rye       = 0.7,
        sorghum   = 0.7,
    },

    -- Fungicide fill type names → effectiveness multiplier
    FUNGICIDE_TYPES = {
        FUNGICIDE = 1.0,
    },
    -- Pressure points removed on a single fungicide application
    FUNGICIDE_PRESSURE_REDUCTION = 20,
    -- Days fungicide suppresses disease growth after application
    FUNGICIDE_DURATION_DAYS = 12,

    -- Harvest yield penalty at each pressure tier
    YIELD_PENALTY_LOW    = 0.00,  -- 0-20:  none
    YIELD_PENALTY_MID    = 0.05,  -- 20-50: -5%
    YIELD_PENALTY_HIGH   = 0.15,  -- 50-75: -15%
    YIELD_PENALTY_PEAK   = 0.25,  -- 75-100: -25%

    -- HUD tier thresholds
    LOW    = 20,
    MEDIUM = 50,
    HIGH   = 75,
}
```

**Also add to `FERTILIZER_PROFILES` table** (after the LIQUIDLIME entry at ~line 199):

```lua
    -- Crop protection products
    INSECTICIDE = { pestReduction = 1.0 },   -- effectiveness 1.0 (key signals this is insecticide)
    FUNGICIDE   = { diseaseReduction = 1.0 }, -- effectiveness 1.0
```

**Also add to `FERTILIZER_TYPES` list:**

```lua
    -- Crop protection
    "INSECTICIDE", "FUNGICIDE",
```

---

## 2. SettingsSchema.lua

**File:** `src/config/SettingsSchema.lua`  
**Insert after the `weedPressure` entry** (currently around line 114–118):

```lua
    {
        id = "pestPressure",
        type = "boolean",
        default = true,
        uiId = "sf_pest_pressure",
    },
    {
        id = "diseasePressure",
        type = "boolean",
        default = true,
        uiId = "sf_disease_pressure",
    },
```

---

## 3. SoilFertilitySystem.lua

### 3a. getOrCreateField — add new fields to the fieldData table

**Find the `self.fieldData[fieldId] = {` block in `getOrCreateField` (~line 590). Add two fields at the end of the table, alongside `weedPressure` and `herbicideDaysLeft`:**

```lua
        weedPressure = 0,
        herbicideDaysLeft = 0,
        pestPressure = 0,        -- ADD
        insecticideDaysLeft = 0, -- ADD
        diseasePressure = 0,     -- ADD
        fungicideDaysLeft = 0,   -- ADD
        dryDayCount = 0,         -- ADD (tracks consecutive days without rain for disease decay)
```

### 3b. onHarvest — apply pest/disease yield penalties and reset pest on harvest

**Find `onHarvest` (~line 128). The weed penalty block already exists. Add pest and disease penalties immediately after the weed block and before `self:updateFieldNutrients(...)`:**

```lua
    -- Pest pressure yield penalty
    if self.settings.pestPressure and SoilConstants.PEST_PRESSURE then
        local field = self.fieldData[fieldId]
        if field then
            local pp = SoilConstants.PEST_PRESSURE
            local pressure = field.pestPressure or 0
            local penalty
            if pressure < pp.LOW then
                penalty = pp.YIELD_PENALTY_LOW
            elseif pressure < pp.MEDIUM then
                penalty = pp.YIELD_PENALTY_MID
            elseif pressure < pp.HIGH then
                penalty = pp.YIELD_PENALTY_HIGH
            else
                penalty = pp.YIELD_PENALTY_PEAK
            end
            if penalty > 0 then
                liters = liters * (1.0 - penalty)
                self:log("Pest penalty field %d: pressure=%.0f, penalty=%.0f%%",
                    fieldId, pressure, penalty * 100)
            end
            -- Harvest disperses pest population
            field.pestPressure = pressure * pp.HARVEST_RESET_FRACTION
            field.insecticideDaysLeft = 0
        end
    end

    -- Disease pressure yield penalty
    if self.settings.diseasePressure and SoilConstants.DISEASE_PRESSURE then
        local field = self.fieldData[fieldId]
        if field then
            local dp = SoilConstants.DISEASE_PRESSURE
            local pressure = field.diseasePressure or 0
            local penalty
            if pressure < dp.LOW then
                penalty = dp.YIELD_PENALTY_LOW
            elseif pressure < dp.MEDIUM then
                penalty = dp.YIELD_PENALTY_MID
            elseif pressure < dp.HIGH then
                penalty = dp.YIELD_PENALTY_HIGH
            else
                penalty = dp.YIELD_PENALTY_PEAK
            end
            if penalty > 0 then
                liters = liters * (1.0 - penalty)
                self:log("Disease penalty field %d: pressure=%.0f, penalty=%.0f%%",
                    fieldId, pressure, penalty * 100)
            end
        end
    end
```

### 3c. onFertilizerApplied — route INSECTICIDE and FUNGICIDE fill types

**Find `applyFertilizer` (~line 783). At the top of the function, after the fill type lookup, add a check BEFORE the `entry = SoilConstants.FERTILIZER_PROFILES[fillType.name]` lookup:**

Actually the cleaner place is inside `applyFertilizer`, after line `if not entry then ... return end`. Replace that `return` block:

```lua
    local entry = SoilConstants.FERTILIZER_PROFILES[fillType.name]
    if not entry then
        -- Check if this is a crop protection product even without a full fertilizer profile
        self:log("Fertilizer type %s not recognized", fillType.name)
        return
    end

    -- Route crop protection products (they don't add N/P/K, they reduce pressure)
    if entry.pestReduction then
        local effectiveness = SoilConstants.PEST_PRESSURE.INSECTICIDE_TYPES[fillType.name] or 0
        if effectiveness > 0 then
            self:onInsecticideApplied(fieldId, effectiveness)
        end
        return
    end
    if entry.diseaseReduction then
        local effectiveness = SoilConstants.DISEASE_PRESSURE.FUNGICIDE_TYPES[fillType.name] or 0
        if effectiveness > 0 then
            self:onFungicideApplied(fieldId, effectiveness)
        end
        return
    end
```

**Also check HERBICIDE routing** — the existing code already routes HERBICIDE via `onHerbicideApplied`. Verify this is done in `HookManager.lua` (see section 3e below) and not inside `applyFertilizer`.

**Looking at the existing code:** HERBICIDE routing is handled separately in HookManager via the sprayer hook. For consistency, INSECTICIDE and FUNGICIDE should follow the SAME pattern. See section 3e.

### 3d. Add new delegate methods (after `onHerbicideApplied`, ~line 326)

```lua
--- Called when insecticide is applied to a field.
---@param fieldId number
---@param effectiveness number 0.0-1.0 insecticide effectiveness multiplier
function SoilFertilitySystem:onInsecticideApplied(fieldId, effectiveness)
    if not self.settings.pestPressure then return end
    if not SoilConstants.PEST_PRESSURE then return end

    local field = self:getOrCreateField(fieldId, false)
    if not field then return end

    local pp = SoilConstants.PEST_PRESSURE
    local reduction = pp.INSECTICIDE_PRESSURE_REDUCTION * (effectiveness or 1.0)
    local before = field.pestPressure or 0
    field.pestPressure = math.max(0, before - reduction)
    field.insecticideDaysLeft = pp.INSECTICIDE_DURATION_DAYS

    self:log("[Insecticide] Field %d: pest pressure %.0f -> %.0f, protected for %d days",
        fieldId, before, field.pestPressure, field.insecticideDaysLeft)

    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end

--- Called when fungicide is applied to a field.
---@param fieldId number
---@param effectiveness number 0.0-1.0 fungicide effectiveness multiplier
function SoilFertilitySystem:onFungicideApplied(fieldId, effectiveness)
    if not self.settings.diseasePressure then return end
    if not SoilConstants.DISEASE_PRESSURE then return end

    local field = self:getOrCreateField(fieldId, false)
    if not field then return end

    local dp = SoilConstants.DISEASE_PRESSURE
    local reduction = dp.FUNGICIDE_PRESSURE_REDUCTION * (effectiveness or 1.0)
    local before = field.diseasePressure or 0
    field.diseasePressure = math.max(0, before - reduction)
    field.fungicideDaysLeft = dp.FUNGICIDE_DURATION_DAYS

    self:log("[Fungicide] Field %d: disease pressure %.0f -> %.0f, protected for %d days",
        fieldId, before, field.diseasePressure, field.fungicideDaysLeft)

    if g_server and g_currentMission and g_currentMission.missionDynamicInfo.isMultiplayer then
        if SoilFieldUpdateEvent then
            g_server:broadcastEvent(SoilFieldUpdateEvent.new(fieldId, field))
        end
    end
end
```

### 3e. HookManager.lua — add INSECTICIDE and FUNGICIDE detection to sprayer hook

**File:** `src/hooks/HookManager.lua`

The existing sprayer hook already calls `soilSystem:onHerbicideApplied(fieldId, effectiveness)` when it detects a HERBICIDE fill type. Find that block and extend it to also detect INSECTICIDE and FUNGICIDE.

Look for the block that checks `SoilConstants.WEED_PRESSURE.HERBICIDE_TYPES[fillType.name]`. Immediately after the herbicide dispatch, add:

```lua
                -- Insecticide detection
                if SoilConstants.PEST_PRESSURE then
                    local insectEff = SoilConstants.PEST_PRESSURE.INSECTICIDE_TYPES[fillType.name]
                    if insectEff then
                        soilSystem:onInsecticideApplied(fieldId, insectEff)
                        return  -- don't also try to fertilize
                    end
                end

                -- Fungicide detection
                if SoilConstants.DISEASE_PRESSURE then
                    local fungEff = SoilConstants.DISEASE_PRESSURE.FUNGICIDE_TYPES[fillType.name]
                    if fungEff then
                        soilSystem:onFungicideApplied(fieldId, fungEff)
                        return  -- don't also try to fertilize
                    end
                end
```

**IMPORTANT:** Read the full sprayer hook in HookManager.lua before adding this. Find the exact location where herbicide is dispatched. The insecticide/fungicide checks must be inserted at the same level, within the same fill-type detection guard.

### 3f. updateDailySoil — add pest and disease daily growth

**Find `updateDailySoil` (~line 609). The weed pressure daily growth block starts around line 646. After the closing `end` of the weed pressure block, add:**

```lua
        -- Pest pressure daily growth
        if self.settings.pestPressure and SoilConstants.PEST_PRESSURE then
            local pp = SoilConstants.PEST_PRESSURE

            -- Decrement insecticide protection
            if (field.insecticideDaysLeft or 0) > 0 then
                field.insecticideDaysLeft = field.insecticideDaysLeft - 1
            end

            -- Only grow when not under insecticide protection
            if (field.insecticideDaysLeft or 0) <= 0 then
                local pressure = field.pestPressure or 0

                -- Base rate by tier
                local baseRate
                if pressure < pp.LOW then
                    baseRate = pp.GROWTH_RATE_LOW
                elseif pressure < pp.MEDIUM then
                    baseRate = pp.GROWTH_RATE_MID
                elseif pressure < pp.HIGH then
                    baseRate = pp.GROWTH_RATE_HIGH
                else
                    baseRate = pp.GROWTH_RATE_PEAK
                end

                -- Seasonal multiplier
                local seasonMult = 1.0
                if g_currentMission and g_currentMission.environment then
                    local season = g_currentMission.environment.currentSeason
                    if season == 1 then seasonMult = pp.SEASONAL_SPRING
                    elseif season == 2 then seasonMult = pp.SEASONAL_SUMMER
                    elseif season == 3 then seasonMult = pp.SEASONAL_FALL
                    elseif season == 4 then seasonMult = pp.SEASONAL_WINTER
                    end
                end

                -- Crop susceptibility multiplier
                local cropMult = 1.0
                if field.lastCrop then
                    cropMult = pp.CROP_SUSCEPTIBILITY[string.lower(field.lastCrop)] or 1.0
                end

                -- Rain bonus (check current rain state)
                local rainBonus = 0
                if g_currentMission and g_currentMission.environment and
                   g_currentMission.environment.weather and
                   (g_currentMission.environment.weather.rainScale or 0) > SoilConstants.RAIN.MIN_RAIN_THRESHOLD then
                    rainBonus = pp.RAIN_BONUS
                end

                field.pestPressure = math.min(100, pressure + (baseRate * seasonMult * cropMult) + rainBonus)
            end
        end

        -- Disease pressure daily growth
        if self.settings.diseasePressure and SoilConstants.DISEASE_PRESSURE then
            local dp = SoilConstants.DISEASE_PRESSURE
            local isRaining = g_currentMission and g_currentMission.environment and
                              g_currentMission.environment.weather and
                              (g_currentMission.environment.weather.rainScale or 0) > SoilConstants.RAIN.MIN_RAIN_THRESHOLD

            -- Track consecutive dry days for natural decay
            if isRaining then
                field.dryDayCount = 0
            else
                field.dryDayCount = (field.dryDayCount or 0) + 1
            end

            -- Decrement fungicide protection
            if (field.fungicideDaysLeft or 0) > 0 then
                field.fungicideDaysLeft = field.fungicideDaysLeft - 1
            end

            local pressure = field.diseasePressure or 0

            -- Natural dry-weather decay (overrides growth)
            if (field.dryDayCount or 0) >= dp.DRY_DAYS_THRESHOLD then
                field.diseasePressure = math.max(0, pressure - dp.DRY_DECAY_RATE)
            elseif (field.fungicideDaysLeft or 0) <= 0 then
                -- Only grow when not protected

                local baseRate
                if pressure < dp.LOW then
                    baseRate = dp.GROWTH_RATE_LOW
                elseif pressure < dp.MEDIUM then
                    baseRate = dp.GROWTH_RATE_MID
                elseif pressure < dp.HIGH then
                    baseRate = dp.GROWTH_RATE_HIGH
                else
                    baseRate = dp.GROWTH_RATE_PEAK
                end

                local seasonMult = 1.0
                if g_currentMission and g_currentMission.environment then
                    local season = g_currentMission.environment.currentSeason
                    if season == 1 then seasonMult = dp.SEASONAL_SPRING
                    elseif season == 2 then seasonMult = dp.SEASONAL_SUMMER
                    elseif season == 3 then seasonMult = dp.SEASONAL_FALL
                    elseif season == 4 then seasonMult = dp.SEASONAL_WINTER
                    end
                end

                local cropMult = 1.0
                if field.lastCrop then
                    cropMult = dp.CROP_SUSCEPTIBILITY[string.lower(field.lastCrop)] or 1.0
                end

                local rainBonus = isRaining and dp.RAIN_BONUS or 0

                field.diseasePressure = math.min(100, pressure + (baseRate * seasonMult * cropMult) + rainBonus)
            end
        end
```

### 3g. saveToXMLFile — save new fields

**Find `saveToXMLFile` (~line 979). After the existing `weedPressure` and `herbicideDaysLeft` lines, add:**

```lua
            setXMLFloat(xmlFile, fieldKey .. "#pestPressure", field.pestPressure or 0)
            setXMLInt(xmlFile, fieldKey .. "#insecticideDaysLeft", field.insecticideDaysLeft or 0)
            setXMLFloat(xmlFile, fieldKey .. "#diseasePressure", field.diseasePressure or 0)
            setXMLInt(xmlFile, fieldKey .. "#fungicideDaysLeft", field.fungicideDaysLeft or 0)
            setXMLInt(xmlFile, fieldKey .. "#dryDayCount", field.dryDayCount or 0)
```

### 3h. loadFromXMLFile — load new fields

**Find `loadFromXMLFile` (~line 1029). In the `self.fieldData[fieldId] = { ... }` table, after `herbicideDaysLeft`, add:**

```lua
            pestPressure = getXMLFloat(xmlFile, fieldKey .. "#pestPressure") or 0,
            insecticideDaysLeft = getXMLInt(xmlFile, fieldKey .. "#insecticideDaysLeft") or 0,
            diseasePressure = getXMLFloat(xmlFile, fieldKey .. "#diseasePressure") or 0,
            fungicideDaysLeft = getXMLInt(xmlFile, fieldKey .. "#fungicideDaysLeft") or 0,
            dryDayCount = getXMLInt(xmlFile, fieldKey .. "#dryDayCount") or 0,
```

### 3i. getFieldInfo — expose new values

**Find `getFieldInfo` (~line 893). In the returned table, after `weedPressure` and `herbicideActive`, add:**

```lua
        pestPressure = field.pestPressure or 0,
        insecticideActive = (field.insecticideDaysLeft or 0) > 0,
        diseasePressure = field.diseasePressure or 0,
        fungicideActive = (field.fungicideDaysLeft or 0) > 0,
```

---

## 4. NetworkEvents.lua

### 4a. SoilFullSyncEvent — settings stream

**In `writeStream` (around line 352), after `streamWriteBool(streamId, self.settings.weedPressure == true)`:**

```lua
    streamWriteBool(streamId, self.settings.pestPressure == true)
    streamWriteBool(streamId, self.settings.diseasePressure == true)
```

**In `readStream` (around line 262), after `self.settings.weedPressure = streamReadBool(streamId)`:**

```lua
    self.settings.pestPressure = streamReadBool(streamId)
    self.settings.diseasePressure = streamReadBool(streamId)
```

**In `run` (around line 404), after `settings.weedPressure = self.settings.weedPressure`:**

```lua
    settings.pestPressure = self.settings.pestPressure
    settings.diseasePressure = self.settings.diseasePressure
```

### 4b. SoilFullSyncEvent — field data stream

**In `writeStream` (around line 374–384), after `streamWriteFloat32(streamId, field.fertilizerApplied or 0)`:**

```lua
        streamWriteFloat32(streamId, field.pestPressure or 0)
        streamWriteFloat32(streamId, field.diseasePressure or 0)
```

**In `readStream` (around line 279–341), after reading `fertilizerApplied`, read the two new values and add them to the fieldData table:**

```lua
        local pestPressure = streamReadFloat32(streamId)
        local diseasePressure = streamReadFloat32(streamId)
```

Then in the `self.fieldData[fieldId] = { ... }` assignment (around line 324), after `herbicideDaysLeft = 0`:

```lua
                pestPressure = math.max(0, math.min(100, pestPressure)),
                insecticideDaysLeft = 0,
                diseasePressure = math.max(0, math.min(100, diseasePressure)),
                fungicideDaysLeft = 0,
                dryDayCount = 0,
```

### 4c. SoilFieldUpdateEvent — field data stream

**In `writeStream` (around line 493–503), after `streamWriteFloat32(streamId, self.field.fertilizerApplied or 0)`:**

```lua
    streamWriteFloat32(streamId, self.field.pestPressure or 0)
    streamWriteFloat32(streamId, self.field.diseasePressure or 0)
```

**In `readStream` (around line 454–483), after reading `fertilizerApplied`, add:**

```lua
    local pestPressure = streamReadFloat32(streamId)
    local diseasePressure = streamReadFloat32(streamId)
```

Then in `self.field = { ... }` (around line 468), add:

```lua
        pestPressure = math.max(0, math.min(100, pestPressure)),
        insecticideDaysLeft = 0,
        diseasePressure = math.max(0, math.min(100, diseasePressure)),
        fungicideDaysLeft = 0,
        dryDayCount = 0,
```

**CRITICAL:** writeStream and readStream must always be **perfectly symmetric** — every `streamWrite*` call in writeStream must have a matching `streamRead*` in readStream, in the same order. Breaking symmetry causes corrupt data silently.

---

## 5. modDesc.xml — new fill types

**Find the `<fillTypes>` section. Add after the last existing fill type entry:**

```xml
<fillType name="INSECTICIDE" title="$l10n_fillType_insecticide" saveId="insecticide" modsDesc="mod_name_soil_fertilizer">
    <physics massPerLiter="0.001" />
    <vehicleDrainTypes>
        <drainType name="sprayer" />
    </vehicleDrainTypes>
    <economy pricePerLiter="1.20" />
    <image hud="$modDir/hud/fillTypes/hud_fill_insecticide.dds" hudUVs="0 0 1 1" />
</fillType>
<fillType name="FUNGICIDE" title="$l10n_fillType_fungicide" saveId="fungicide" modsDesc="mod_name_soil_fertilizer">
    <physics massPerLiter="0.001" />
    <vehicleDrainTypes>
        <drainType name="sprayer" />
    </vehicleDrainTypes>
    <economy pricePerLiter="1.30" />
    <image hud="$modDir/hud/fillTypes/hud_fill_fungicide.dds" hudUVs="0 0 1 1" />
</fillType>
```

**Note on HUD icons:** `hud_fill_insecticide.dds` and `hud_fill_fungicide.dds` do not exist yet. Either:
- Create placeholder icons (copy an existing .dds from the hud/fillTypes/ folder and rename)
- OR change the `hud=` attribute to point to an existing icon temporarily

**Find the `<l10n>` settings keys section. Add the two new setting keys to `translations/translation_en.xml` (and all 25 other language files — see Section 6).**

---

## 6. Translation files — all 26 languages

**File pattern:** `translations/translation_*.xml`

The translations are in separate files per language. Each file has entries like:
```xml
<l10n>
    <elements>
        <e k="sf_pest_pressure" v="Pest Pressure" />
        <e k="sf_pest_pressure_desc" v="Track and simulate insect pest populations per field. Apply insecticide to reduce pressure." />
        <e k="sf_disease_pressure" v="Disease Pressure" />
        <e k="sf_disease_pressure_desc" v="Track and simulate crop disease per field. Apply fungicide to reduce pressure." />
        <e k="fillType_insecticide" v="Insecticide" />
        <e k="fillType_fungicide" v="Fungicide" />
    </elements>
</l10n>
```

Add these six entries to **every language file** (`translation_en.xml`, `translation_de.xml`, `translation_fr.xml`, etc. — all 26). For languages other than English, use the English text as-is (proper translations can be added by the community later). The important thing is the key exists so the UI doesn't show raw key names.

The 26 language file codes are: `en de fr nl it pl es ea pt br ru uk cz hu ro tr fi no sv da kr jp ct fc id vi`

---

## 7. SoilSettingsUI.lua — add UI toggles

**File:** `src/settings/SoilSettingsUI.lua`

The settings UI auto-generates toggles from `SettingsSchema.definitions`. Because you've added the two new entries to SettingsSchema, they will appear in the UI automatically **if** the `uiId` values (`sf_pest_pressure`, `sf_disease_pressure`) are registered in the UI element creation loop.

Read the existing UI file to find how `weedPressure` is handled — it uses `sf_weed_pressure` as its `uiId`. The new settings follow the same pattern.

If the UI uses a whitelist of which settings to render (some mods do), add `sf_pest_pressure` and `sf_disease_pressure` to that list.

---

## 8. Soil Report Dialog (optional but recommended)

**File:** `src/ui/SoilReportDialog.lua`

Find where `weedPressure` is rendered per field in the report table. Add two new rows for `pestPressure` and `diseasePressure` using the same formatting pattern.

The `getFieldInfo()` return table now includes `pestPressure` and `diseasePressure` — use those values.

---

## Invariants to preserve (DO NOT BREAK)

1. **Network stream symmetry:** Every writeStream field must have a matching readStream field in exactly the same order. Pest and disease go AFTER fertilizerApplied in both SoilFullSyncEvent and SoilFieldUpdateEvent.

2. **Save backward compatibility:** Old saves missing `pestPressure`, `diseasePressure` etc. will return `nil` from `getXMLFloat/Int`. The `or 0` default handles this. Do not remove that default.

3. **Multiplayer creation guard:** `getOrCreateField` only creates fields on the server. This guard is at the top of that function. Do NOT bypass it.

4. **Weed pressure is untouched:** Do not modify any existing weed pressure code paths. Only add the new pest/disease blocks alongside them.

5. **Lua 5.1 constraints:** No `goto`, no `continue`, no `os.time()`, no `os.date()`. Use `if/else` or early `return`.

6. **`g_currentModName` capture:** Any new file with local helper functions that call `g_modEnvironments` must capture the mod name at file scope:
   ```lua
   local SF_MOD_NAME = g_currentModName
   ```

---

## After implementation — build and test checklist

```bash
# From mod directory:
bash build.sh --deploy
```

Then launch the game and verify in `log.txt`:
- `[SoilFertilizer] Constants loaded` — no errors
- `[SoilFertilizer] Soil Fertility System initialized successfully`
- No `nil` indexing errors on startup

In-game:
- [ ] Settings page shows "Pest Pressure" and "Disease Pressure" toggles with translated text
- [ ] Toggling them off/on works and persists after reload
- [ ] Spraying INSECTICIDE on a field calls `onInsecticideApplied` (check `SoilDebug` log)
- [ ] Spraying FUNGICIDE on a field calls `onFungicideApplied`
- [ ] After a few in-game days, pest/disease values increase (check `SoilFieldInfo <id>`)
- [ ] Soil Report (K key) shows pest and disease rows
- [ ] In multiplayer: joining client receives correct pest/disease values

---

## Git workflow

```bash
git checkout development   # always work here
git add -A
git commit -m "feat: add pest and disease pressure to Field Health System (v1.4.0)"
# Then run /fs25-release 1.4.0.0 when ready to release
```

---

## Reference: current fieldData structure (before your changes)

```lua
fieldData[fieldId] = {
    nitrogen       = number,   -- 0-100
    phosphorus     = number,   -- 0-100
    potassium      = number,   -- 0-100
    organicMatter  = number,   -- 0-10
    pH             = number,   -- 5.0-7.5
    lastCrop       = string|nil,
    lastHarvest    = number,   -- game day
    fertilizerApplied = number,
    weedPressure   = number,   -- 0-100 (already implemented)
    herbicideDaysLeft = number, -- already implemented
    initialized    = boolean,
}
```

After your changes, add:
```lua
    pestPressure      = number,  -- 0-100
    insecticideDaysLeft = number,
    diseasePressure   = number,  -- 0-100
    fungicideDaysLeft = number,
    dryDayCount       = number,  -- consecutive dry days (for disease decay)
```

---

## Reference: HookManager sprayer hook pattern

The sprayer hook fires every work area process. It:
1. Gets fill type from the sprayer
2. Checks `SoilConstants.WEED_PRESSURE.HERBICIDE_TYPES[fillType.name]` for herbicide
3. If herbicide: calls `soilSystem:onHerbicideApplied(fieldId, effectiveness)` and returns
4. Otherwise: calls `soilSystem:onFertilizerApplied(fieldId, fillTypeIndex, liters)`

Your INSECTICIDE/FUNGICIDE checks go between step 2 and step 4. Read HookManager.lua in full before editing to find the exact insertion point.

---

*This document covers everything needed. Do not add speculative features. Do not add error handling beyond what the existing patterns use. Do not refactor surrounding code.*
