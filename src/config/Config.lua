-- =========================================================
-- Configuration settings for Soil & Fertilizer Mod
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
SoilFertilityConfig = {
    DISABLE_GUI = false,
    DISABLE_MOD = false,
    PF_COMPATIBILITY = true,
    DEBUG = false
}

function SoilFertilityConfig:loadFromFile()
    local configPath = g_currentModDirectory .. "config.txt"
    if fileExists(configPath) then
        local file = io.open(configPath, "r")
        if file then
            for line in file:lines() do
                local key, value = line:match("([^=]+)=(.+)")
                if key and value then
                    key = key:trim()
                    value = value:trim()
                    
                    if self[key] ~= nil then
                        if value:lower() == "true" then
                            self[key] = true
                        elseif value:lower() == "false" then
                            self[key] = false
                        elseif tonumber(value) then
                            self[key] = tonumber(value)
                        end
                    end
                end
            end
            file:close()
        end
    end
end

SoilFertilityConfig:loadFromFile()