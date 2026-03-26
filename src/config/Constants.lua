-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Enhanced Constants
-- =========================================================
-- Configuration values and constants for the mod
-- Enhanced with enterprise-grade monitoring and reliability features
-- =========================================================
-- Author: TisonK (Enhanced Version)
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
--
-- Base game fill types are recognized out of the box.
-- Extended types (UAN32, ANHYDROUS, MAP, etc.) activate automatically
-- when equipment mods register those fill type names via g_fillTypeManager.
SoilConstants.FERTILIZER_PROFILES = {
    -- Base game
    LIQUIDFERTILIZER  = { N=0.50, P=0.21, K=0.33 },           -- Balanced liquid NPK
    FERTILIZER        = { N=0.67, P=0.33, K=0.25 },           -- Solid granular, high N/P
    MANURE            = { N=0.25, P=0.17, K=0.29, OM=0.05 },  -- Organic, slow-release
    LIQUIDMANURE      = { N=0.33, P=0.17, K=0.42, OM=0.03 },  -- Liquid organic, high K (FS25 fill type name)
    DIGESTATE         = { N=0.42, P=0.18, K=0.46, OM=0.04 },  -- Biogas byproduct
    LIME              = { pH=0.4 },                             -- pH adjustment

    -- Nitrogen sources (common in NA-style equipment mods)
    UAN32             = { N=0.87, P=0.00, K=0.00 },  -- 32-0-0 liquid
    UAN28             = { N=0.76, P=0.00, K=0.00 },  -- 28-0-0 liquid
    ANHYDROUS         = { N=1.00, P=0.00, K=0.00 },  -- 82-0-0, highest N concentration
    AMS               = { N=0.46, P=0.00, K=0.00 },  -- 21-0-0-24S ammonium sulfate
    UREA              = { N=0.95, P=0.00, K=0.00 },  -- 46-0-0 dry granular

    -- Starter fertilizer
    STARTER           = { N=0.27, P=0.68, K=0.18 },  -- High-P starter (approx 10-34-0)

    -- Gypsum (Calcium Sulfate)
    GYPSUM            = { pH=0.1, OM=0.01 },         -- Stabilizes pH, improves structure (OM)

    -- Phosphorus & potassium sources
    MAP               = { N=0.30, P=1.41, K=0.00 },  -- 11-52-0 monoammonium phosphate
    DAP               = { N=0.49, P=1.26, K=0.00 },  -- 18-46-0 diammonium phosphate
    POTASH            = { N=0.00, P=0.00, K=1.63 },  -- 0-0-60 muriate of potash

    -- Organic / slow-release
    COMPOST           = { N=0.08, P=0.05, K=0.06, OM=0.12 },
    BIOSOLIDS         = { N=0.28, P=0.22, K=0.08, OM=0.07 },
    CHICKEN_MANURE    = { N=0.35, P=0.29, K=0.18, OM=0.08 },
    PELLETIZED_MANURE = { N=0.65, P=0.45, K=0.55, OM=0.08 },

    -- Lime variants
    LIQUIDLIME        = { pH=0.3 },  -- Slightly weaker per volume than dry lime
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

-- Threshold for "needs fertilization" warning
SoilConstants.FERTILIZATION_THRESHOLDS = {
    nitrogen = 30,
    phosphorus = 25,
    potassium = 20,
    pH = 5.5,
}

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

-- ========================================
-- ENHANCED ENTERPRISE CONFIGURATION
-- ========================================
-- Additional constants for enterprise-grade features
-- Circuit breaker, monitoring, and reliability patterns
-- ========================================

-- Circuit breaker configuration
SoilConstants.CIRCUIT_BREAKER = {
    FAILURE_THRESHOLD = 5,           -- Number of failures before opening
    RECOVERY_TIMEOUT = 30000,        -- Time in ms before attempting half-open
    HALF_OPEN_MAX_CALLS = 3,         -- Max calls in half-open state
    FAILURE_RATE_THRESHOLD = 0.5,    -- Failure rate to trigger opening
}

-- Health monitoring configuration
SoilConstants.HEALTH_MONITORING = {
    CHECK_INTERVAL = 10000,          -- Run health checks every 10 seconds
    CRITICAL_FAILURE_THRESHOLD = 3,  -- Failures before critical status
    WARNING_FAILURE_THRESHOLD = 2,   -- Failures before warning status
    MEMORY_LEAK_THRESHOLD = 1000,    -- Max field count before memory warning
    CACHE_SIZE_THRESHOLD = 500,      -- Max cache entries before warning
    CORRUPTION_THRESHOLD = 0.05,     -- 5% corruption rate before failure
    LATENCY_THRESHOLD = 1000,        -- Max average latency in ms
    SUCCESS_RATE_THRESHOLD = 0.8,    -- Minimum sync success rate (80%)
}

-- Network optimization configuration
SoilConstants.NETWORK_OPTIMIZATION = {
    COMPRESSION_ENABLED = true,      -- Enable field data compression
    CACHE_TTL = 5000,               -- Cache field data for 5 seconds
    BANDWIDTH_LIMIT = 102400,       -- Max bandwidth usage per second (100KB)
    BATCH_SIZE = 10,                -- Number of fields to send in batch
    RETRY_DELAY = 2000,             -- Delay between retry attempts
    MAX_RETRIES = 3,                -- Maximum retry attempts
}

-- Performance monitoring configuration
SoilConstants.PERFORMANCE_MONITORING = {
    METRICS_RETENTION = 100,         -- Keep last 100 metric samples
    LATENCY_WINDOW = 60000,          -- 1 minute latency window
    BANDWIDTH_WINDOW = 60000,        -- 1 minute bandwidth window
    ALERT_COOLDOWN = 300000,         -- 5 minutes between duplicate alerts
}

-- Client connection tracking
SoilConstants.CLIENT_TRACKING = {
    CONNECTION_TIMEOUT = 600000,     -- 10 minutes connection timeout
    HEARTBEAT_INTERVAL = 30000,      -- 30 seconds heartbeat
    MAX_CONNECTIONS = 100,           -- Maximum tracked connections
    SYNC_TIMEOUT = 15000,            -- 15 seconds sync timeout
}

-- Predictive loading configuration
SoilConstants.PREDICTIVE_LOADING = {
    PREDICTION_WINDOW = 30000,       -- 30 seconds prediction window
    PROXIMITY_THRESHOLD = 500,       -- 500m proximity threshold
    PREFETCH_RADIUS = 1000,          -- 1km prefetch radius
    LOAD_PRIORITY = 10,              -- Priority for predictive loads
}

-- Error handling configuration
SoilConstants.ERROR_HANDLING = {
    MAX_ERROR_LOGS = 100,            -- Maximum error logs to keep
    ERROR_COOLDOWN = 5000,           -- 5 seconds between duplicate error logs
    CRITICAL_ERROR_THRESHOLD = 10,   -- Critical errors before shutdown
    RECOVERY_ATTEMPTS = 3,           -- Recovery attempts before giving up
}

-- Memory management configuration
SoilConstants.MEMORY_MANAGEMENT = {
    GC_THRESHOLD = 1000000,          -- Force GC at 1MB memory usage
    CACHE_CLEANUP_INTERVAL = 60000,  -- 1 minute cache cleanup
    FIELD_DATA_MAX_AGE = 3600000,    -- 1 hour max field data age
    MAX_FIELD_COUNT = 1000,          -- Maximum fields to track
}

-- Logging configuration
SoilConstants.LOGGING = {
    LOG_LEVEL = "INFO",              -- DEBUG, INFO, WARNING, ERROR, CRITICAL
    LOG_RETENTION = 1000,            -- Maximum log entries to keep
    LOG_FLUSH_INTERVAL = 60000,      -- 1 minute log flush interval
    LOG_FILE_SIZE = 10485760,        -- 10MB max log file size
    LOG_COMPRESSION = true,          -- Compress old log files
}

-- ========================================
-- ENHANCED NETWORK CONSTANTS
-- ========================================
-- Extended network configuration for enterprise features
-- ========================================

-- Enhanced network value types
SoilConstants.NETWORK.VALUE_TYPE = {
    BOOLEAN = 0,
    NUMBER = 1,
    STRING = 2,
    COMPRESSED = 3,                  -- Compressed field data
    METRICS = 4,                     -- Performance metrics
    HEALTH = 5,                      -- Health check data
    PREDICTIVE = 6,                  -- Predictive loading data
}

-- Enhanced network operations
SoilConstants.NETWORK.OPERATIONS = {
    FULL_SYNC = "FULL_SYNC",
    FIELD_UPDATE = "FIELD_UPDATE",
    HEALTH_CHECK = "HEALTH_CHECK",
    METRICS_REPORT = "METRICS_REPORT",
    PREDICTIVE_LOAD = "PREDICTIVE_LOAD",
    CIRCUIT_BREAKER = "CIRCUIT_BREAKER",
}

-- Network bandwidth optimization
SoilConstants.NETWORK.BANDWIDTH = {
    COMPRESSION_RATIO = 0.5,         -- 50% compression ratio expected
    BATCH_THRESHOLD = 1000,          -- Batch when more than 1000 bytes
    PRIORITY_HIGH = 1,               -- High priority (health checks)
    PRIORITY_MEDIUM = 2,             -- Medium priority (field updates)
    PRIORITY_LOW = 3,                -- Low priority (metrics, logs)
}

-- ========================================
-- ENHANCED MONITORING CONSTANTS
-- ========================================
-- Constants for Google-style SRE patterns
-- ========================================

-- Service Level Indicators (SLIs)
SoilConstants.SLI = {
    AVAILABILITY = "availability",   -- Percentage of successful requests
    LATENCY = "latency",             -- Response time percentiles
    THROUGHPUT = "throughput",       -- Requests per second
    ERROR_RATE = "error_rate",       -- Percentage of failed requests
}

-- Service Level Objectives (SLOs)
SoilConstants.SLO = {
    AVAILABILITY_TARGET = 0.99,      -- 99% availability
    LATENCY_P95_TARGET = 500,        -- 95th percentile under 500ms
    ERROR_RATE_TARGET = 0.01,        -- Error rate under 1%
    THROUGHPUT_MIN = 10,             -- Minimum 10 requests per second
}

-- Service Level Agreements (SLAs)
SoilConstants.SLA = {
    RESPONSE_TIME = 1000,            -- Maximum response time (1 second)
    RECOVERY_TIME = 300000,          -- Maximum recovery time (5 minutes)
    MAINTENANCE_WINDOW = 3600000,    -- 1 hour maintenance window
}

-- Alert thresholds
SoilConstants.ALERTS = {
    AVAILABILITY_WARNING = 0.95,     -- Warn at 95% availability
    AVAILABILITY_CRITICAL = 0.90,    -- Critical at 90% availability
    LATENCY_WARNING = 1000,          -- Warn at 1 second latency
    LATENCY_CRITICAL = 2000,         -- Critical at 2 seconds latency
    ERROR_RATE_WARNING = 0.05,       -- Warn at 5% error rate
    ERROR_RATE_CRITICAL = 0.10,      -- Critical at 10% error rate
}

-- ========================================
-- ENHANCED PREDICTIVE ANALYTICS
-- ========================================
-- Constants for predictive failure detection
-- ========================================

-- Predictive thresholds
SoilConstants.PREDICTIVE = {
    FAILURE_PROBABILITY_THRESHOLD = 0.8,  -- 80% probability triggers alert
    TREND_WINDOW = 300000,               -- 5 minutes trend analysis
    ANOMALY_THRESHOLD = 2.0,             -- 2 standard deviations
    PREDICTION_CONFIDENCE = 0.7,         -- 70% confidence required
}

-- Machine learning parameters (simplified)
SoilConstants.ML = {
    LEARNING_RATE = 0.01,                -- Learning rate for anomaly detection
    MEMORY_FACTOR = 0.9,                 -- How much past data to remember
    SMOOTHING_FACTOR = 0.1,              -- Exponential smoothing factor
    OUTLIER_SENSITIVITY = 1.5,           -- Sensitivity to outliers
}

-- ========================================
-- ENHANCED RECOVERY MECHANISMS
-- ========================================
-- Constants for automated recovery
-- ========================================

-- Recovery strategies
SoilConstants.RECOVERY = {
    STRATEGY_IMMEDIATE = "IMMEDIATE",    -- Immediate retry
    STRATEGY_EXPONENTIAL = "EXPONENTIAL", -- Exponential backoff
    STRATEGY_CIRCUIT_BREAKER = "CIRCUIT_BREAKER", -- Circuit breaker pattern
    STRATEGY_GRACEFUL_DEGRADATION = "GRACEFUL_DEGRADATION", -- Reduce functionality
}

-- Recovery timing
SoilConstants.RECOVERY_TIMING = {
    IMMEDIATE_RETRY_DELAY = 1000,        -- 1 second immediate retry
    EXPONENTIAL_BASE = 2,                -- Base for exponential backoff
    MAX_RETRY_DELAY = 300000,            -- 5 minutes max retry delay
    DEGRADATION_TIMEOUT = 600000,        -- 10 minutes degradation timeout
}

-- Recovery thresholds
SoilConstants.RECOVERY_THRESHOLDS = {
    MAX_RECOVERY_ATTEMPTS = 5,           -- Maximum recovery attempts
    RECOVERY_SUCCESS_RATE = 0.8,         -- 80% success rate required
    DEGRADATION_TRIGGER = 0.5,           -- 50% failure rate triggers degradation
    FULL_RECOVERY_THRESHOLD = 0.1,       -- 10% failure rate allows full recovery
}

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
