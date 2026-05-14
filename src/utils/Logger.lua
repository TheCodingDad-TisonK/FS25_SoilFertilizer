-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Logger
-- =========================================================
-- Centralized logging with consistent [SoilFertilizer] prefix
-- and debug-mode gating
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilLogger
SoilLogger = {}

local PREFIX = "[SoilFertilizer]"

SoilLogger.debugBuffer    = {}
SoilLogger.DEBUG_BUF_MAX  = 500

--- Log a debug message (only shown when debugMode is enabled)
function SoilLogger.debug(msg, ...)
    if g_SoilFertilityManager and g_SoilFertilityManager.settings and g_SoilFertilityManager.settings.debugMode then
        local success, formatted = pcall(string.format, PREFIX .. " DEBUG: " .. msg, ...)
        local line = success and formatted or (PREFIX .. " DEBUG: " .. tostring(msg))
        print(line)
        local buf = SoilLogger.debugBuffer
        buf[#buf + 1] = {
            t   = g_currentMission and math.floor(g_currentMission.time or 0) or 0,
            msg = line,
        }
        if #buf > SoilLogger.DEBUG_BUF_MAX then
            table.remove(buf, 1)
        end
    end
end

--- Flush buffered debug messages to Debug/debug.xml in the mod profile folder.
--- Called when debug mode is turned off or the game session ends.
function SoilLogger.flushDebugLog()
    local buf = SoilLogger.debugBuffer
    if #buf == 0 then return end
    local base = SettingsManager and SettingsManager.getModProfileDir and SettingsManager.getModProfileDir()
    if not base then return end
    local xml = XMLFile.create("sf_debugLog", base .. "/Debug/debug.xml", "debugLog")
    if not xml then return end
    xml:setInt("debugLog#count", #buf)
    for i, entry in ipairs(buf) do
        local key = string.format("debugLog.entry(%d)", i - 1)
        xml:setInt(key .. "#t", entry.t)
        xml:setString(key .. "#msg", entry.msg)
    end
    xml:save()
    xml:delete()
    SoilLogger.debugBuffer = {}
end

--- Log an info message (always shown)
function SoilLogger.info(msg, ...)
    local success, formatted = pcall(string.format, PREFIX .. " " .. msg, ...)
    if success then
        print(formatted)
    else
        print(PREFIX .. " " .. tostring(msg))
    end
end

--- Log a warning message (always shown)
function SoilLogger.warning(msg, ...)
    local success, formatted = pcall(string.format, PREFIX .. " WARNING: " .. msg, ...)
    if success then
        print(formatted)
    else
        print(PREFIX .. " WARNING: " .. tostring(msg))
    end
end

--- Log an error message (always shown)
function SoilLogger.error(msg, ...)
    local success, formatted = pcall(string.format, PREFIX .. " ERROR: " .. msg, ...)
    if success then
        print(formatted)
    else
        print(PREFIX .. " ERROR: " .. tostring(msg))
    end
end
