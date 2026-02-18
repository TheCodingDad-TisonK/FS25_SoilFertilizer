-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.6.0)
-- =========================================================
-- Settings domain object - uses SettingsSchema for defaults/validation
-- =========================================================
-- Author: TisonK
-- =========================================================
---@class Settings

Settings = {}
local Settings_mt = Class(Settings)

Settings.DIFFICULTY_EASY = SoilConstants.DIFFICULTY.EASY
Settings.DIFFICULTY_NORMAL = SoilConstants.DIFFICULTY.NORMAL
Settings.DIFFICULTY_HARD = SoilConstants.DIFFICULTY.HARD

function Settings.new(manager)
    local self = setmetatable({}, Settings_mt)
    self.manager = manager

    self:resetToDefaults(false)

    SoilLogger.info("[SoilFertilizer] Settings initialized")

    return self
end

---@param difficulty number
function Settings:setDifficulty(difficulty)
    if difficulty >= Settings.DIFFICULTY_EASY and difficulty <= Settings.DIFFICULTY_HARD then
        self.difficulty = difficulty

        local difficultyName = "Normal"
        if difficulty == Settings.DIFFICULTY_EASY then
            difficultyName = "Simple"
        elseif difficulty == Settings.DIFFICULTY_HARD then
            difficultyName = "Hardcore"
        end

        SoilLogger.info("[SoilFertilizer] Difficulty changed to: %s", difficultyName)
    end
end

---@return string
function Settings:getDifficultyName()
    if self.difficulty == Settings.DIFFICULTY_EASY then
        return "Simple"
    elseif self.difficulty == Settings.DIFFICULTY_HARD then
        return "Hardcore"
    else
        return "Realistic"
    end
end

function Settings:load()
    if type(self.difficulty) ~= "number" then
        SoilLogger.warning("[SoilFertilizer]difficulty is not a number! Type: %s, Value: %s",
            type(self.difficulty), tostring(self.difficulty))
        self.difficulty = Settings.DIFFICULTY_NORMAL
    end

    self.manager:loadSettings(self)

    self:validateSettings()

    SoilLogger.info("[SoilFertilizer]Settings Loaded. Enabled: %s, Difficulty: %s",
        tostring(self.enabled), self:getDifficultyName())
end

function Settings:validateSettings()
    -- Validate all settings against schema
    for _, def in ipairs(SettingsSchema.definitions) do
        self[def.id] = SettingsSchema.validate(def.id, self[def.id])
    end
end

function Settings:save()
    if type(self.difficulty) ~= "number" then
        SoilLogger.warning("[SoilFertilizer]difficulty is not a number! Type: %s, Value: %s",
            type(self.difficulty), tostring(self.difficulty))
        self.difficulty = Settings.DIFFICULTY_NORMAL
    end

    self.manager:saveSettings(self)
    SoilLogger.info("[SoilFertilizer]Settings Saved. Difficulty: %s", self:getDifficultyName())
end

---@param saveImmediately boolean
function Settings:resetToDefaults(saveImmediately)
    saveImmediately = saveImmediately ~= false

    -- Reset all settings from schema defaults
    for _, def in ipairs(SettingsSchema.definitions) do
        self[def.id] = def.default
    end

    if saveImmediately then
        self:save()
        print("[SoilFertilizer] Settings reset to defaults")
    end
end
