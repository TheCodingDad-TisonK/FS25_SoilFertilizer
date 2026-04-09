-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Constants
-- =========================================================
-- All tunable values: timing, difficulty, nutrient limits,
-- crop extraction rates, fertilizer profiles, HUD config.
-- Single source of truth — modify here, not in system code.
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilConstants
SoilConstants = {}

-- ========================================
-- TIMING
-- ========================================
SoilConstants.TIMING = {
    UPDATE_INTERVAL = 30000,     -- ms between periodic checks
    FALLOW_THRESHOLD = 7,        -- days before fallow recovery kicks in
}

-- ========================================
-- DIFFICULTY MULTIPLIERS
-- ========================================
SoilConstants.DIFFICULTY = {
    EASY = 1,
    NORMAL = 2,
    HARD = 3,
    MULTIPLIERS = {
        [1] = 0.7,   -- Simple
        [2] = 1.0,   -- Realistic
        [3] = 1.5,   -- Hardcore
    }
}

-- ========================================
-- DEFAULT FIELD VALUES
-- ========================================
-- These defaults are calibrated to match the base game's initial field state:
--   pH 6.0  → "slightly acidic" in our system, consistent with base game "needs liming" at game start
--   N/P/K   → "fair" range (below optimal), consistent with base game "needs fertilizing" at game start
-- Players address both systems simultaneously: apply lime → base game lime state + our pH both rise;
-- apply fertilizer → base game fertilizer state + our N/P/K both rise.
-- Fields already saved in soilData.xml are not affected; only new/untracked fields use these values.
SoilConstants.FIELD_DEFAULTS = {
    nitrogen = 40,
    phosphorus = 30,
    potassium = 35,
    organicMatter = 3.5,
    pH = 6.0,
}

-- ========================================
-- PLOWING
-- ========================================
-- Thresholds for plowing operations
SoilConstants.PLOWING = {
    MIN_DEPTH_FOR_PLOWING = 0.15,  -- Minimum working depth (meters) to qualify as deep plowing
                                     -- Values > 0.15m improve organic matter mixing
}

-- ========================================
-- NUTRIENT LIMITS
-- ========================================
SoilConstants.NUTRIENT_LIMITS = {
    MIN = 0,
    MAX = 100,
    ORGANIC_MATTER_MAX = 10,
    PH_MIN = 5.0,
    PH_MAX = 7.5,
    PH_NEUTRAL_LOW = 6.5,
    PH_NEUTRAL_HIGH = 7.0,
}

-- ========================================
-- NUTRIENT RECOVERY RATES (per day, fallow fields)
-- ========================================
-- Adjusted for 0-100 scale (slower natural recovery rate)
SoilConstants.FALLOW_RECOVERY = {
    nitrogen = 0.07,      -- ~1 year to recover 25 points
    phosphorus = 0.03,    -- Phosphorus recovers slower
    potassium = 0.05,     -- Moderate recovery
    organicMatter = 0.01, -- Organic matter accumulates very slowly
}

-- ========================================
-- CHOPPED STRAW / CHAFF ORGANIC MATTER GAIN
-- ========================================
-- When a combine chops straw instead of dropping it, the material decomposes
-- into the soil and adds organic matter (realistic agricultural behaviour).
-- Rate is per 1000L of harvested crop, scaled by strawRatio (0.0-1.0).
-- Example: 5000L wheat, strawRatio=0.5 → 5 × 0.5 × 0.20 = 0.50 OM
-- (comparable to one plowing event on the 0-10 OM scale)
SoilConstants.CHOPPED_STRAW = {
    OM_RATE = 0.20,   -- OM gain per 1000L harvested at full strawRatio=1.0
}

-- ========================================
-- SEASONAL EFFECTS (per day)
-- ========================================
-- Adjusted for 0-100 scale (subtle seasonal changes)
SoilConstants.SEASONAL_EFFECTS = {
    SPRING_NITROGEN_BOOST = 0.03,  -- Small spring boost from biological activity
    FALL_NITROGEN_LOSS = 0.02,     -- Gradual fall depletion
    SPRING_SEASON = 1,
    FALL_SEASON = 3,
}

-- ========================================
-- pH NORMALIZATION (per day)
-- ========================================
SoilConstants.PH_NORMALIZATION = {
    RATE = 0.01,
}

-- ========================================
-- RAIN EFFECTS
-- ========================================
-- Adjusted for 0-100 nutrient scale
SoilConstants.RAIN = {
    LEACH_BASE_FACTOR = 0.00000008,  -- base leach per dt per rainScale (÷12 for scale adjustment)
    NITROGEN_MULTIPLIER = 5,         -- nitrogen leaches most (mobile nutrient)
    POTASSIUM_MULTIPLIER = 2,        -- potassium moderate leaching
    PHOSPHORUS_MULTIPLIER = 0.5,     -- phosphorus binds to soil (least mobile)
    PH_ACIDIFICATION = 0.1,          -- rain acidification multiplier
    MIN_RAIN_THRESHOLD = 0.1,        -- minimum rainScale to trigger effects
}

-- ========================================
-- CROP EXTRACTION RATES (per 1,000 liters harvested)
-- ========================================
-- Calibrated for 0-100 nutrient scale (normalized by field area)
-- Typical 1-hectare field yields ~8,000L, resulting in 15-25% nutrient depletion
-- Example: 8,000L wheat depletes 16N, 6.4P, 12K (from defaults 50N, 40P, 45K)
SoilConstants.CROP_EXTRACTION = {
    wheat      = { N=2.00, P=0.80, K=1.50 },  -- Moderate N demand, standard grain
    barley     = { N=1.80, P=0.80, K=1.40 },  -- Similar to wheat, slightly less
    maize      = { N=2.30, P=1.00, K=2.00 },  -- High N/P demand, large biomass
    canola     = { N=2.70, P=1.20, K=2.20 },  -- High N demand, oilseed
    soybean    = { N=3.20, P=1.30, K=1.70 },  -- Highest N (compensates for fixation)
    sunflower  = { N=2.50, P=1.10, K=2.30 },  -- Moderate-high demand
    potato     = { N=3.80, P=1.70, K=5.40 },  -- Very high K demand (tuber crop)
    sugarbeet  = { N=3.30, P=1.50, K=5.80 },  -- Extreme K demand (root crop)
    oats       = { N=1.80, P=0.90, K=1.60 },  -- Light feeder
    rye        = { N=2.00, P=0.80, K=1.80 },  -- Moderate demand
    triticale  = { N=2.10, P=1.00, K=1.90 },  -- Hybrid characteristics
    sorghum    = { N=2.30, P=0.90, K=1.80 },  -- Efficient nutrient user
    peas       = { N=2.90, P=1.10, K=2.00 },  -- Legume, moderate demand
    beans      = { N=3.00, P=1.20, K=2.10 },  -- Legume, similar to peas
}

-- Default extraction for unknown crops (average cereal)
SoilConstants.CROP_EXTRACTION_DEFAULT = { N=2.10, P=0.90, K=1.70 }

-- ========================================
-- FERTILIZER PROFILES (per 1,000 liters applied)
-- ========================================
-- Calibrated for 0-100 nutrient scale (normalized by field area)
-- Example: 1,000L liquid fertilizer restores ~5.0N, ~2.1P, ~3.3K on 1 hectare
--
-- Base game fill types are recognized out of the box.
SoilConstants.FERTILIZER_PROFILES = {
    -- Base game
    LIQUIDFERTILIZER  = { N=5.00, P=2.10, K=3.30 },           -- Balanced liquid NPK
    FERTILIZER        = { N=6.70, P=3.30, K=2.50 },           -- Solid granular, high N/P
    MANURE            = { N=2.50, P=1.70, K=2.90, OM=0.50 },  -- Organic, slow-release
    LIQUIDMANURE      = { N=3.30, P=1.70, K=4.20, OM=0.30 },  -- Liquid organic, high K
    DIGESTATE         = { N=4.20, P=1.80, K=4.60, OM=0.40 },  -- Biogas byproduct
    LIME              = { pH=4.0 },                             -- pH adjustment

    -- Nitrogen sources
    UAN32             = { N=8.70, P=0.00, K=0.00 },  -- 32-0-0 liquid
    UAN28             = { N=7.60, P=0.00, K=0.00 },  -- 28-0-0 liquid
    ANHYDROUS         = { N=10.0, P=0.00, K=0.00 },  -- 82-0-0
    AMS               = { N=4.60, P=0.00, K=0.00 },  -- 21-0-0
    UREA              = { N=9.50, P=0.00, K=0.00 },  -- 46-0-0

    -- Starter fertilizer
    STARTER           = { N=2.70, P=6.80, K=1.80 },  -- High-P starter

    -- Gypsum
    GYPSUM            = { pH=1.0, OM=0.10 },

    -- Phosphorus & potassium sources
    MAP               = { N=3.00, P=14.1, K=0.00 },  -- 11-52-0
    DAP               = { N=4.90, P=12.6, K=0.00 },  -- 18-46-0
    POTASH            = { N=0.00, P=0.00, K=16.3 },  -- 0-0-60

    -- Organic / slow-release
    COMPOST           = { N=0.80, P=0.50, K=0.60, OM=1.20 },
    BIOSOLIDS         = { N=2.80, P=2.20, K=0.80, OM=0.70 },
    CHICKEN_MANURE    = { N=3.50, P=2.90, K=1.80, OM=0.80 },
    PELLETIZED_MANURE = { N=6.50, P=4.50, K=5.50, OM=0.80 },

    -- Lime variants
    LIQUIDLIME        = { pH=3.0 },

    -- Crop protection products
    INSECTICIDE = { pestReduction = 1.0 },
    FUNGICIDE   = { diseaseReduction = 1.0 },
}

-- List of recognized fertilizer fill type names (for reference/iteration)
SoilConstants.FERTILIZER_TYPES = {
    -- Base game
    "LIQUIDFERTILIZER", "FERTILIZER", "MANURE", "LIQUIDMANURE", "DIGESTATE", "LIME",
    -- Nitrogen sources
    "UAN32", "UAN28", "ANHYDROUS", "AMS", "UREA",
    -- Starter
    "STARTER",
    -- Gypsum
    "GYPSUM",
    -- P&K sources
    "MAP", "DAP", "POTASH",
    -- Organic
    "COMPOST", "BIOSOLIDS", "CHICKEN_MANURE", "PELLETIZED_MANURE",
    -- Lime variants
    "LIQUIDLIME",
    -- Crop protection
    "INSECTICIDE", "FUNGICIDE",
}

-- ========================================
-- BIG BAG CAPACITY
-- ========================================
-- Capacity (in litres) for all BigBag objects.
-- Real IBC / FIBC bags hold 500–1000 kg of dry product or 1000L of liquid.
-- The game's sprayers consume product quickly, so we use a larger value
-- (10,000 L) to give a realistic field-spanning amount per bag.
-- Change this value here and update the matching capacity/startFillLevel
-- attributes in every objects/bigBag/*/bigBag_*.xml and multiPurchase*.xml.
SoilConstants.BIGBAG = {
    CAPACITY = 1000,  -- litres per bag
}

-- ========================================
-- SINGLE-NUTRIENT PURCHASABLE FILL TYPES
-- ========================================
-- These fill types are declared in modDesc.xml <fillTypes> and are available
-- for purchase at in-game shops when compatible equipment mods are installed.
-- The entries here mirror the pricePerLiter values in modDesc.xml so that any
-- Lua code performing cost estimates or HUD display can read a single source.
--
-- Nutrient targeting:
--   ANHYDROUS  →  N only  (82-0-0)
--   MAP        →  P-heavy (11-52-0)
--   POTASH     →  K only  (0-0-60)
SoilConstants.PURCHASABLE_SINGLE_NUTRIENT = {
    ANHYDROUS = {
        pricePerLiter = 1.85,   -- ~50 % premium over base LIQUIDFERTILIZER
        fillUnit      = "liquid",
        primaryNutrient = "N",
        description   = "Anhydrous Ammonia 82-0-0",
    },
    MAP = {
        pricePerLiter = 1.95,   -- ~60 % premium; P is the scarcest macro
        fillUnit      = "dry",
        primaryNutrient = "P",
        description   = "Monoammonium Phosphate 11-52-0",
    },
    POTASH = {
        pricePerLiter = 1.80,   -- ~50 % premium over base granular FERTILIZER
        fillUnit      = "dry",
        primaryNutrient = "K",
        description   = "Muriate of Potash 0-0-60",
    },
}

-- ========================================
-- NUTRIENT STATUS THRESHOLDS
-- ========================================
SoilConstants.STATUS_THRESHOLDS = {
    nitrogen   = { poor = 30, fair = 50 },
    phosphorus = { poor = 25, fair = 45 },
    potassium  = { poor = 20, fair = 40 },
}

-- ========================================
-- PPM DISPLAY SCALE
-- ========================================
-- Converts the internal 0-100 nutrient scale to soil-test PPM values for
-- HUD and Report display.  Calibrated so that the fair→good status boundary
-- aligns with standard agronomic lab benchmarks (Mehlich-3 / ammonium-acetate):
--   N: Good >150 ppm  (plant-available nitrogen)
--   P: Good >27 ppm   (Bray/Mehlich-3 phosphorus; lab "Good" ~25-30 ppm)
--   K: Good >160 ppm  (Mehlich-3 potassium; lab "Good" ~150 ppm)
-- The bar in the HUD still runs 0-100 % (internal), where 100 % represents
-- the luxury-level ceiling (300 ppm N, 60 ppm P, 400 ppm K).
-- Nothing in the simulation changes — these multipliers are display-only.
SoilConstants.PPM_DISPLAY = {
    N = 3.0,   -- internal 50 (fair→good boundary) = 150 ppm
    P = 0.6,   -- internal 45 (fair→good boundary) = 27 ppm
    K = 4.0,   -- internal 40 (fair→good boundary) = 160 ppm
}

-- Threshold for "needs fertilization" warning
SoilConstants.FERTILIZATION_THRESHOLDS = {
    nitrogen = 30,
    phosphorus = 25,
    potassium = 20,
    pH = 5.5,
}

-- Urgency score threshold for critical field alerts
SoilConstants.CRITICAL_ALERT_THRESHOLD = 50

-- ========================================
-- YIELD SENSITIVITY (Issue #81 interim HUD warning)
-- ========================================
-- Nutrient levels >= OPTIMAL_THRESHOLD (0-100 scale) → no yield penalty.
-- Below that, penalty scales with how far each nutrient has dropped and
-- how demanding the crop is.  Max penalty is capped at MAX_PENALTY.
--
-- Formula (per nutrient): deficit_fraction = max(0, threshold - value) / threshold
-- Combined deficit = average of N, P, K deficit fractions
-- Raw penalty      = combined_deficit * tier.scale
-- Final penalty %  = min(MAX_PENALTY, raw_penalty) * 100
SoilConstants.YIELD_SENSITIVITY = {
    -- Nutrients must be at or above this value (0–100) for full yield
    OPTIMAL_THRESHOLD = 70,

    -- Hard cap on how much yield can be lost to nutrient stress
    MAX_PENALTY = 0.50,

    -- Tier definitions: scale how harshly the deficit translates to a penalty
    TIERS = {
        tolerant  = { scale = 0.50, label = "Tolerant"  },  -- barley, oat, sunflower
        moderate  = { scale = 1.00, label = "Moderate"  },  -- wheat, canola, maize, etc.
        demanding = { scale = 2.00, label = "Demanding" },  -- potato, sugarbeet, soybean
    },

    -- Crop name (lowercased fruitDesc.name) → sensitivity tier
    CROP_TIERS = {
        -- Tolerant: manage well even in poor soil
        barley     = "tolerant",
        oat        = "tolerant",
        oats       = "tolerant",   -- alternate name
        sunflower  = "tolerant",
        rye        = "tolerant",
        sorghum    = "tolerant",
        -- Moderate: standard response to nutrient levels
        wheat      = "moderate",
        canola     = "moderate",
        maize      = "moderate",
        triticale  = "moderate",
        peas       = "moderate",
        beans      = "moderate",
        -- Demanding: yield falls sharply with nutrient stress
        potato     = "demanding",
        sugarbeet  = "demanding",
        soybean    = "demanding",
    },

    DEFAULT_TIER = "moderate",

    -- Crops that are not row-crop harvests; skip yield forecast for these
    NON_CROP_NAMES = {
        grass = true, drygrass = true, poplar = true, oilseedradish = true,
    },
}

-- ========================================
-- REPORT COLOR THRESHOLDS
-- ========================================
-- pH/OM ranges for color-coded report display
SoilConstants.REPORT_COLORS = {
    PH_GOOD_LOW  = 6.0,
    PH_GOOD_HIGH = 7.0,
    PH_FAIR_LOW  = 5.5,
    PH_FAIR_HIGH = 7.5,
    OM_GOOD      = 4.0,
    OM_FAIR      = 2.5,
}

-- ========================================
-- HUD DISPLAY
-- ========================================
SoilConstants.HUD = {
    PANEL_WIDTH = 0.15,
    PANEL_HEIGHT = 0.15,

    -- Position presets (matched to hudPosition setting values 1-5)
    POSITIONS = {
        [1] = { x = 0.850, y = 0.70 },  -- Top Right
        [2] = { x = 0.010, y = 0.70 },  -- Top Left
        [3] = { x = 0.850, y = 0.20 },  -- Bottom Right
        [4] = { x = 0.010, y = 0.20 },  -- Bottom Left
        [5] = { x = 0.850, y = 0.45 },  -- Center Right
    },

    -- Color themes (matched to hudColorTheme setting values 1-4)
    COLOR_THEMES = {
        [1] = { r = 0.4, g = 1.0, b = 0.4 },  -- Green (default farming theme)
        [2] = { r = 0.4, g = 0.8, b = 1.0 },  -- Blue (cool tech theme)
        [3] = { r = 1.0, g = 0.7, b = 0.2 },  -- Amber (high contrast)
        [4] = { r = 0.9, g = 0.9, b = 0.9 },  -- Mono (minimalist grayscale)
    },

    -- Transparency levels (matched to hudTransparency setting values 1-5)
    TRANSPARENCY_LEVELS = {
        [1] = 0.25,  -- Clear (25%)
        [2] = 0.50,  -- Light (50%)
        [3] = 0.70,  -- Medium (70%) - default
        [4] = 0.85,  -- Dark (85%)
        [5] = 1.00,  -- Solid (100%)
    },

    -- Font size multipliers (matched to hudFontSize setting values 1-3)
    FONT_SIZE_MULTIPLIERS = {
        [1] = 0.85,  -- Small
        [2] = 1.00,  -- Medium (default)
        [3] = 1.20,  -- Large
    },

    NORMAL_LINE_HEIGHT = 0.016,

    -- RENDER ORDER NOTES:
    -- FS25 Giants Engine does not provide explicit render layer/Z-order APIs
    -- Overlay render order is determined by:
    --   1. Callback timing (we use FSBaseMission.update)
    --   2. Call order within frame
    --   3. Mod load order
    -- Our HUD renders AFTER game UI init, BEFORE debug overlays
    -- If experiencing conflicts with other mods, users should:
    --   - Adjust HUD position via settings (5 presets available)
    --   - Check mod load order in mods menu
    -- Visibility checks ensure we don't render over critical UI (menus, dialogs, etc)
}

-- ========================================
-- NETWORK SYNC
-- ========================================
SoilConstants.NETWORK = {
    FULL_SYNC_MAX_ATTEMPTS = 3,
    FULL_SYNC_RETRY_INTERVAL = 5000, -- ms

    -- Network value type encoding
    VALUE_TYPE = {
        BOOLEAN = 0,
        NUMBER = 1,
        STRING = 2,
    }
}

SoilLogger.info("Constants loaded")

-- ========================================
-- SPRAYER APPLICATION RATE
-- ========================================
-- 20 stepped rate multipliers (0.10x – 2.00x in 0.10 increments).
-- DEFAULT_INDEX = 10 → 1.0x (no change from base behaviour).
-- The HUD displays real units (gal/ac or L/ha) by multiplying each step
-- against the BASE_RATE for the currently loaded fertilizer fill type.
-- Burn effects apply when nutrient-rich fertilizer is over-applied:
--   > BURN_RISK_THRESHOLD      : probabilistic pH/N burn (prob scales with excess)
--   >= BURN_GUARANTEED_THRESHOLD: guaranteed burn every application
SoilConstants.SPRAYER_RATE = {
    STEPS = {
        0.10, 0.20, 0.30, 0.40, 0.50,
        0.60, 0.70, 0.80, 0.90, 1.00,
        1.10, 1.20, 1.30, 1.40, 1.50,
        1.60, 1.70, 1.80, 1.90, 2.00,
    },
    DEFAULT_INDEX             = 10,    -- 1.0x
    BURN_RISK_THRESHOLD       = 1.25,  -- above this: chance of burn
    BURN_GUARANTEED_THRESHOLD = 1.50,  -- at or above this: burn every time
    BURN_PH_DROP_RISK         = 0.15,  -- pH units lost on probabilistic burn
    BURN_PH_DROP_CERTAIN      = 0.30,  -- pH units lost on guaranteed burn
    BURN_N_DRAIN_RISK         = 5.0,   -- N points lost on probabilistic burn
    BURN_N_DRAIN_CERTAIN      = 12.0,  -- N points lost on guaranteed burn

    -- Reference application rates at 1.0x (step 10) per fill type.
    -- unit = "liquid" → value in L/ha;  unit = "dry" → value in kg/ha.
    -- actual_display_rate = STEPS[idx] * BASE_RATES[name].value
    BASE_RATES = {
        -- Base game
        LIQUIDFERTILIZER  = { value =    93.5, unit = "liquid" },  -- 10 gal/ac
        FERTILIZER        = { value =   225.0, unit = "dry"    },  -- ~200 lb/ac
        MANURE            = { value = 14000.0, unit = "liquid" },  -- ~1500 gal/ac
        LIQUIDMANURE      = { value = 14000.0, unit = "liquid" },  -- FS25 fill type name for slurry
        DIGESTATE         = { value = 14000.0, unit = "liquid" },
        LIME              = { value =  2500.0, unit = "dry"    },  -- ~2230 lb/ac
        LIQUIDLIME        = { value =  2800.0, unit = "liquid" },
        -- Nitrogen sources
        UAN32             = { value =    60.8, unit = "liquid" },  -- ~6.5 gal/ac
        UAN28             = { value =    60.8, unit = "liquid" },
        ANHYDROUS         = { value =    28.0, unit = "liquid" },  -- ~3 gal/ac
        AMS               = { value =   168.0, unit = "dry"    },  -- ~150 lb/ac
        UREA              = { value =   168.0, unit = "dry"    },
        -- Starter / P&K sources
        STARTER           = { value =    46.8, unit = "liquid" },  -- ~5 gal/ac
        MAP               = { value =   225.0, unit = "dry"    },
        DAP               = { value =   225.0, unit = "dry"    },
        POTASH            = { value =   225.0, unit = "dry"    },
        -- Organic / slow-release
        PELLETIZED_MANURE = { value =   450.0, unit = "dry"    },  -- ~400 lb/ac
        COMPOST           = { value =  5000.0, unit = "dry"    },
        BIOSOLIDS         = { value =  4500.0, unit = "dry"    },
        CHICKEN_MANURE    = { value =  2000.0, unit = "dry"    },
        GYPSUM            = { value =  1500.0, unit = "dry"    },
        -- Crop protection
        INSECTICIDE = { value = 1.5, unit = "liquid" },  -- ~0.16 gal/ac
        FUNGICIDE   = { value = 1.5, unit = "liquid" },  -- ~0.16 gal/ac
        -- Fallback for unrecognized fill types
        DEFAULT           = { value =    93.5, unit = "liquid" },
    },

    -- Target nutrient levels for Auto-Rate Control
    -- Used when SF_TOGGLE_AUTO is active on a sprayer
    AUTO_RATE_TARGETS = {
        N  = 80,
        P  = 70,
        K  = 75,
        pH = 7.0,
        OM = 5.0
    },

    -- Unit conversions for display
    L_PER_HA_TO_GAL_PER_AC = 0.10694,  -- multiply L/ha by this for gal/ac
    KG_PER_HA_TO_LB_PER_AC = 0.89218,  -- multiply kg/ha by this for lb/ac
}

-- ========================================
-- WEED PRESSURE (Issue #98)
-- ========================================
-- Field-level 0-100 score representing weed density.
-- Grows daily with seasonal/rain multipliers.
-- Herbicide spray reduces pressure and temporarily suppresses growth.
-- Tillage (any cultivator/plow) resets pressure to 0.
-- Harvest applies a yield penalty proportional to pressure tier.
SoilConstants.WEED_PRESSURE = {
    -- Daily base growth rate (points/day) by current pressure tier
    -- Growth slows as pressure approaches capacity
    GROWTH_RATE_LOW    = 1.2,   -- 0-20:  slow germination phase
    GROWTH_RATE_MID    = 2.0,   -- 20-50: active competition phase
    GROWTH_RATE_HIGH   = 1.2,   -- 50-75: density self-limiting
    GROWTH_RATE_PEAK   = 0.4,   -- 75-100: near carrying capacity

    -- Seasonal growth multipliers (season index matches FS25 environment.currentSeason)
    -- Season 1=Spring, 2=Summer, 3=Fall, 4=Winter (matches SoilConstants.SEASONAL_EFFECTS)
    SEASONAL_SPRING = 1.4,  -- peak germination
    SEASONAL_SUMMER = 1.6,  -- maximum growth
    SEASONAL_FALL   = 0.7,  -- slowing down
    SEASONAL_WINTER = 0.05, -- near dormancy

    -- Rain bonus added to base daily rate when it is raining
    RAIN_BONUS = 0.5,

    -- Herbicide fill type names → effectiveness multiplier (0.0-1.0)
    -- Any fill type not listed here is NOT treated as herbicide
    HERBICIDE_TYPES = {
        HERBICIDE = 1.0,
        PESTICIDE = 0.8,
    },
    -- Pressure points removed on a single herbicide application
    HERBICIDE_PRESSURE_REDUCTION = 30,
    -- Number of in-game days herbicide suppresses weed growth after application
    HERBICIDE_DURATION_DAYS = 14,

    -- Tillage resets pressure to 0 (handled in onPlowing)

    -- Harvest yield penalty at each pressure tier
    YIELD_PENALTY_LOW    = 0.00,  -- 0-20:  none
    YIELD_PENALTY_MID    = 0.05,  -- 20-50: -5%
    YIELD_PENALTY_HIGH   = 0.15,  -- 50-75: -15%
    YIELD_PENALTY_PEAK   = 0.30,  -- 75-100: -30%

    -- HUD tier thresholds
    LOW    = 20,
    MEDIUM = 50,
    HIGH   = 75,
}

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
    INSECTICIDE_DURATION_DAYS = 30,

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
    FUNGICIDE_DURATION_DAYS = 35,

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