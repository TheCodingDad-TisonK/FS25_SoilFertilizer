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
        pfProtected = false,
    },
    {
        id = "debugMode",
        type = "boolean",
        default = false,
        uiId = "sf_debug",
        pfProtected = false,
    },
    {
        id = "fertilitySystem",
        type = "boolean",
        default = true,
        uiId = "sf_fertility",
        pfProtected = true,
    },
    {
        id = "nutrientCycles",
        type = "boolean",
        default = true,
        uiId = "sf_nutrients",
        pfProtected = true,
    },
    {
        id = "fertilizerCosts",
        type = "boolean",
        default = true,
        uiId = "sf_fertilizer_cost",
        pfProtected = true,
    },
    {
        id = "showNotifications",
        type = "boolean",
        default = true,
        uiId = "sf_notifications",
        pfProtected = false,
    },
    {
        id = "showHUD",
        type = "boolean",
        default = true,
        uiId = "sf_show_hud",
        pfProtected = false,
    },
    {
        id = "hudPosition",
        type = "number",
        default = 1,  -- 1=Top Right, 2=Top Left, 3=Bottom Right, 4=Bottom Left, 5=Center Right
        min = 1,
        max = 5,
        uiId = "sf_hud_position",
        pfProtected = false,
    },
    {
        id = "hudColorTheme",
        type = "number",
        default = 1,  -- 1=Green, 2=Blue, 3=Amber, 4=Mono
        min = 1,
        max = 4,
        uiId = "sf_hud_color_theme",
        pfProtected = false,
    },
    {
        id = "hudFontSize",
        type = "number",
        default = 2,  -- 1=Small, 2=Medium, 3=Large
        min = 1,
        max = 3,
        uiId = "sf_hud_font_size",
        pfProtected = false,
    },
    {
        id = "hudTransparency",
        type = "number",
        default = 3,  -- 1=Clear (25%), 2=Light (50%), 3=Medium (70%), 4=Dark (85%), 5=Solid (100%)
        min = 1,
        max = 5,
        uiId = "sf_hud_transparency",
        pfProtected = false,
    },
    {
        id = "hudCompactMode",
        type = "boolean",
        default = false,
        uiId = "sf_hud_compact_mode",
        pfProtected = false,
    },
    {
        id = "seasonalEffects",
        type = "boolean",
        default = true,
        uiId = "sf_seasonal_effects",
        pfProtected = true,
    },
    {
        id = "rainEffects",
        type = "boolean",
        default = true,
        uiId = "sf_rain_effects",
        pfProtected = true,
    },
    {
        id = "plowingBonus",
        type = "boolean",
        default = true,
        uiId = "sf_plowing_bonus",
        pfProtected = true,
    },
    {
        id = "difficulty",
        type = "number",
        default = 2,
        min = 1,
        max = 3,
        uiId = "sf_diff",
        pfProtected = true,
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
function SettingsSchema.validate(id, value)
    local def = SettingsSchema.byId[id]
    if not def then return value end

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

print("[SoilFertilizer] Settings schema loaded")
