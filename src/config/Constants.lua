-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Constants
-- =========================================================
-- Single source of truth for all tunable values
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
SoilConstants.FIELD_DEFAULTS = {
    nitrogen = 50,
    phosphorus = 40,
    potassium = 45,
    organicMatter = 3.5,
    pH = 6.5,
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
-- Calibrated for 0-100 nutrient scale
-- Typical 10-hectare field yields ~80,000L, resulting in 15-25% nutrient depletion
-- Example: 80,000L wheat depletes 16N, 6.4P, 12K (from defaults 50N, 40P, 45K)
SoilConstants.CROP_EXTRACTION = {
    wheat      = { N=0.20, P=0.08, K=0.15 },  -- Moderate N demand, standard grain
    barley     = { N=0.18, P=0.08, K=0.14 },  -- Similar to wheat, slightly less
    maize      = { N=0.23, P=0.10, K=0.20 },  -- High N/P demand, large biomass
    canola     = { N=0.27, P=0.12, K=0.22 },  -- High N demand, oilseed
    soybean    = { N=0.32, P=0.13, K=0.17 },  -- Highest N (compensates for fixation)
    sunflower  = { N=0.25, P=0.11, K=0.23 },  -- Moderate-high demand
    potato     = { N=0.38, P=0.17, K=0.54 },  -- Very high K demand (tuber crop)
    sugarbeet  = { N=0.33, P=0.15, K=0.58 },  -- Extreme K demand (root crop)
    oats       = { N=0.18, P=0.09, K=0.16 },  -- Light feeder
    rye        = { N=0.20, P=0.08, K=0.18 },  -- Moderate demand
    triticale  = { N=0.21, P=0.10, K=0.19 },  -- Hybrid characteristics
    sorghum    = { N=0.23, P=0.09, K=0.18 },  -- Efficient nutrient user
    peas       = { N=0.29, P=0.11, K=0.20 },  -- Legume, moderate demand
    beans      = { N=0.30, P=0.12, K=0.21 },  -- Legume, similar to peas
}

-- Default extraction for unknown crops (average cereal)
SoilConstants.CROP_EXTRACTION_DEFAULT = { N=0.21, P=0.09, K=0.17 }

-- ========================================
-- FERTILIZER PROFILES (per 1,000 liters applied)
-- ========================================
-- Calibrated for 0-100 nutrient scale
-- Example: 2,000L liquid fertilizer restores ~13N, ~5.6P, ~10.7K
SoilConstants.FERTILIZER_PROFILES = {
    LIQUIDFERTILIZER = { N=0.50, P=0.21, K=0.33 },  -- Balanced liquid NPK
    FERTILIZER       = { N=0.67, P=0.33, K=0.25 },  -- Solid granular, high N/P
    MANURE           = { N=0.25, P=0.17, K=0.29, OM=0.05 },  -- Organic, slow-release
    SLURRY           = { N=0.33, P=0.17, K=0.42, OM=0.03 },  -- Liquid organic, high K
    DIGESTATE        = { N=0.42, P=0.18, K=0.46, OM=0.04 },  -- Biogas byproduct
    LIME             = { pH=0.4 },  -- pH adjustment (not on nutrient scale)
}

-- List of recognized fertilizer fill type names
SoilConstants.FERTILIZER_TYPES = {
    "LIQUIDFERTILIZER",
    "FERTILIZER",
    "MANURE",
    "SLURRY",
    "DIGESTATE",
    "LIME",
}

-- ========================================
-- NUTRIENT STATUS THRESHOLDS
-- ========================================
SoilConstants.STATUS_THRESHOLDS = {
    nitrogen   = { poor = 30, fair = 50 },
    phosphorus = { poor = 25, fair = 45 },
    potassium  = { poor = 20, fair = 40 },
}

-- Threshold for "needs fertilization" warning
SoilConstants.FERTILIZATION_THRESHOLDS = {
    nitrogen = 30,
    phosphorus = 25,
    potassium = 20,
    pH = 5.5,
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

    -- Compact mode dimensions
    COMPACT_LINE_HEIGHT = 0.013,  -- vs normal 0.016
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
    --   - Enable compact mode to reduce screen space
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

print("[SoilFertilizer] Constants loaded")
