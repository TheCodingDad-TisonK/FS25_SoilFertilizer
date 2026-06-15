-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Shared Utilities
-- =========================================================
-- Author: TisonK
-- =========================================================

SoilUtils = {}

--- Returns true if the local player has admin rights.
--- Single-player: always true. Dedicated server console: always true.
--- Multiplayer client: checks master-user flag.
function SoilUtils.isPlayerAdmin()
    if not g_currentMission then return false end
    if not (g_currentMission.missionDynamicInfo and
            g_currentMission.missionDynamicInfo.isMultiplayer) then
        return true
    end
    if g_dedicatedServer then return true end
    local user = g_currentMission.userManager and
                 g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    return user ~= nil and user:getIsMasterUser()
end

--- Returns the localized display name for a crop given its internal fruit-type name
--- (e.g. "WHEAT", "GREENRYE"). Soil data stores the raw uppercase identifier; rendering
--- it directly (capitalised, underscores → spaces) showed English names to every locale —
--- the Bodenmonitor mistranslation in #635. Each fruit type owns a fill type whose .title
--- is already localized by the engine, so resolve through that. Falls back to a prettified
--- raw name when no fruit/fill type matches (custom or unknown crops still read cleanly).
--- Returns nil for empty/nil input so callers can show their own "Fallow" label.
function SoilUtils.getCropDisplayName(name)
    if not name or name == "" then return nil end
    if g_fruitTypeManager then
        local fruitType = g_fruitTypeManager:getFruitTypeByName(name)
        if fruitType and fruitType.fillType and fruitType.fillType.title
           and fruitType.fillType.title ~= "" then
            return fruitType.fillType.title
        end
    end
    return (name:sub(1, 1):upper() .. name:sub(2):lower()):gsub("_", " ")
end
