-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Settings Schema
-- =========================================================
-- Single source of truth for all settings definitions
-- Adding a new setting: add one entry here + translations in modDesc.xml
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SettingsSchema
SettingsSchema = {}

-- Schema entries: each defines a setting completely
-- Order matters for UI display and network sync
SettingsSchema.definitions = {
    {
        id = "enabled",
        type = "boolean",
        default = true,
        uiId = "sf_enabled",
    },
    {
        id = "debugMode",
        type = "boolean",
        default = false,
        uiId = "sf_debug",
    },
    {
        id = "fertilitySystem",
        type = "boolean",
        default = true,
        uiId = "sf_fertility",
    },
    {
        id = "nutrientCycles",
        type = "boolean",
        default = true,
        uiId = "sf_nutrients",
    },
    {
        id = "fertilizerCosts",
        type = "boolean",
        default = true,
        uiId = "sf_fertilizer_cost",
    },
    {
        id = "showNotifications",
        type = "boolean",
        default = true,
        uiId = "sf_notifications",
    },
    {
        id = "showHUD",
        type = "boolean",
        default = true,
        uiId = "sf_show_hud",
        localOnly = true,  -- per-player HUD visibility, not synced to server
    },
    {
        id = "hudPosition",
        type = "number",
        default = 1,  -- 1=Top Right, 2=Top Left, 3=Bottom Right, 4=Bottom Left, 5=Center Right, 6=Custom
        min = 1,
        max = 6,
        uiId = "sf_hud_position",
        localOnly = true,  -- per-player display preference, not synced to server
    },
    {
        id = "hudColorTheme",
        type = "number",
        default = 1,  -- 1=Green, 2=Blue, 3=Amber, 4=Mono
        min = 1,
        max = 4,
        uiId = "sf_hud_color_theme",
        localOnly = true,  -- per-player display preference, not synced to server
    },
    {
        id = "hudFontSize",
        type = "number",
        default = 2,  -- 1=Small, 2=Medium, 3=Large
        min = 1,
        max = 3,
        uiId = "sf_hud_font_size",
        localOnly = true,  -- per-player display preference, not synced to server
    },
    {
        id = "hudTransparency",
        type = "number",
        default = 3,  -- 1=Clear (25%), 2=Light (50%), 3=Medium (70%), 4=Dark (85%), 5=Solid (100%)
        min = 1,
        max = 5,
        uiId = "sf_hud_transparency",
        localOnly = true,  -- per-player display preference, not synced to server
    },
    {
        id = "hudDragEnabled",
        type = "boolean",
        default = true,
        uiId = "sf_hud_drag_enabled",
        localOnly = true,  -- per-player preference, not synced to server
    },
    {
        id = "seasonalEffects",
        type = "boolean",
        default = true,
        uiId = "sf_seasonal_effects",
    },
    {
        id = "rainEffects",
        type = "boolean",
        default = true,
        uiId = "sf_rain_effects",
    },
    {
        id = "plowingBonus",
        type = "boolean",
        default = true,
        uiId = "sf_plowing_bonus",
    },
    {
        id = "weedPressure",
        type = "boolean",
        default = true,
        uiId = "sf_weed_pressure",
    },
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
    {
        id = "difficulty",
        type = "number",
        default = 2,
        min = 1,
        max = 3,
        uiId = "sf_diff",
    },
    {
        id = "useImperialUnits",
        type = "boolean",
        default = true,
        uiId = "sf_use_imperial",
        localOnly = true,  -- per-player display preference, not synced to server
    },
    {
        id = "autoRateControl",
        type = "boolean",
        default = true,
        uiId = "sf_auto_rate",
    },
    {
        id = "cropRotation",
        type = "boolean",
        default = true,
        uiId = "sf_crop_rotation",
    },
    {
        id = "activeMapLayer",
        type = "number",
        default = 0,  -- 0=Off, 1=N, 2=P, 3=K, 4=pH, 5=OM, 6=Urgency, 7=Weed, 8=Pest, 9=Disease
        min = 0,
        max = 9,
        uiId = "sf_active_map_layer",
        localOnly = true,  -- per-player map view, not synced to server
    },
    {
        id = "overlayDensity",
        type = "number",
        default = 2,  -- 1=Low (8k pts), 2=Medium (20k pts), 3=High (40k pts)
        min = 1,
        max = 3,
        uiId = "sf_overlay_density",
        localOnly = true,  -- per-player render preference, not synced to server
    },
}

-- Build lookup table by id for fast access
SettingsSchema.byId = {}
for _, def in ipairs(SettingsSchema.definitions) do
    SettingsSchema.byId[def.id] = def
end

--- Get all boolean settings (for UI toggles)
function SettingsSchema.getBooleanSettings()
    local result = {}
    for _, def in ipairs(SettingsSchema.definitions) do
        if def.type == "boolean" then
            table.insert(result, def)
        end
    end
    return result
end

--- Get the default value for a setting
function SettingsSchema.getDefault(id)
    local def = SettingsSchema.byId[id]
    return def and def.default or nil
end

--- Get a table of all defaults
function SettingsSchema.getAllDefaults()
    local defaults = {}
    for _, def in ipairs(SettingsSchema.definitions) do
        defaults[def.id] = def.default
    end
    return defaults
end

--- Validate a setting value against its schema
--- Returns validated value, or nil if setting is unknown
function SettingsSchema.validate(id, value)
    local def = SettingsSchema.byId[id]
    if not def then
        -- Reject unknown settings (fail-secure pattern)
        SoilLogger.warning("Validation rejected unknown setting: %s", tostring(id))
        return nil
    end

    if def.type == "boolean" then
        return not not value
    elseif def.type == "number" then
        value = tonumber(value) or def.default
        if def.min and value < def.min then value = def.default end
        if def.max and value > def.max then value = def.default end
        return value
    end
    return value
end

SoilLogger.info("Settings schema loaded")
