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
