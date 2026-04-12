-- =========================================================
-- FS25 Realistic Soil & Fertilizer
-- =========================================================
-- Settings UI - profile-based element creation
-- Pattern from: FS25_UsedPlus/src/gui/UsedPlusSettingsMenuExtension.lua
-- =========================================================
-- Hooks InGameMenuSettingsFrame at file-load time (runs once).
-- Elements are created via FS25 profiles, not clone().
-- This eliminates the white settings page bug on dedicated
-- server clients (GitHub #21).
-- =========================================================
---@class SoilSettingsUI

SoilSettingsUI = {}
local SoilSettingsUI_mt = Class(SoilSettingsUI)

-- Capture mod name at load time — g_currentModName is only valid during loading.
local SF_MOD_NAME = g_currentModName

-- Resolve a translation key using the mod-scoped i18n instance.
-- g_i18n is the base-game global and does not know about mod keys.
local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[SF_MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

function SoilSettingsUI.new(settings)
    local self = setmetatable({}, SoilSettingsUI_mt)
    self.settings = settings
    self._resetButton = nil
    return self
end

-- Check if current player is admin
function SoilSettingsUI:isPlayerAdmin()
    if not g_currentMission then return false end

    if not (g_currentMission and g_currentMission.missionDynamicInfo and g_currentMission.missionDynamicInfo.isMultiplayer) then
        return true
    end

    if g_dedicatedServer then
        return true
    end

    local currentUser = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
    if currentUser then
        return currentUser:getIsMasterUser()
    end

    return false
end

-- Show admin-only warning
function SoilSettingsUI:showAdminOnlyWarning()
    if g_currentMission and g_currentMission.hud and g_currentMission.hud.showBlinkingWarning then
        g_currentMission.hud:showBlinkingWarning(
            "Only server admins can change Soil & Fertilizer settings",
            5000
        )
    end

    if g_gui and g_gui.showInfoDialog then
        g_gui:showInfoDialog({
            text = "Only the server admin can change Soil & Fertilizer Mod settings.\n\nIf you are the server owner, make sure you are logged in as admin.",
            callback = nil
        })
    end
end

-- Request setting change via network (or apply directly if server/singleplayer)
function SoilSettingsUI:requestSettingChange(settingName, value)
    -- Local-only settings (HUD display prefs) bypass admin check and network sync entirely
    local def = SettingsSchema.byId[settingName]
    if def and def.localOnly then
        self.settings[settingName] = value
        self.settings:save()
        return
    end

    if not self:isPlayerAdmin() then
        self:showAdminOnlyWarning()
        self:refreshUI()
        return
    end

    if SoilNetworkEvents_RequestSettingChange then
        SoilNetworkEvents_RequestSettingChange(settingName, value)
    else
        self.settings[settingName] = value
        self.settings:save()
        print(string.format("[SoilFertilizer] Setting '%s' changed to %s", settingName, tostring(value)))
    end
end

-- Refresh UI elements to match current settings values
function SoilSettingsUI:refreshUI()
    -- Find the current settings frame
    if not g_gui or not g_gui.screenControllers then return end
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if not inGameMenu or not inGameMenu.pageSettings then return end
    local frame = inGameMenu.pageSettings
    if not frame.soilFertilizer_initDone then return end

    for _, def in ipairs(SettingsSchema.definitions) do
        local element = frame["soilFertilizer_" .. def.uiId]
        if element then
            local val = self.settings[def.id]
            if def.type == "boolean" then
                if element.setIsChecked then
                    element:setIsChecked(val == true, false, false)
                end
            elseif def.type == "number" and element.setState then
                element:setState(val or def.default)
            end
        end
    end
end

--- Re-enable/disable all settings elements based on current admin status.
--- Called on every frame open so that players who gain admin after first open are handled.
function SoilSettingsUI:updateAdminState(frame)
    if not frame.soilFertilizer_initDone then return end
    local isAdmin = self:isPlayerAdmin()

    for _, def in ipairs(SettingsSchema.definitions) do
        local element = frame["soilFertilizer_" .. def.uiId]
        if element and element.setIsEnabled then
            if def.localOnly then
                -- Per-player HUD settings: always enabled regardless of admin status
                element:setIsEnabled(true)
                if element.setToolTipText then element:setToolTipText("") end
            else
                element:setIsEnabled(isAdmin)
                if element.setToolTipText then
                    element:setToolTipText(isAdmin and "" or "Admin only")
                end
            end
        end
    end
end

--- Called when InGameMenuSettingsFrame opens.
--- Creates all settings elements using profile-based factory functions.
function SoilSettingsUI:onFrameOpen(frame)
    if frame.soilFertilizer_initDone then
        -- Frame already built — just refresh admin state and values (fixes stale disabled state)
        self:updateAdminState(frame)
        self:updateGameSettings(frame)
        return
    end

    local layout = frame.gameSettingsLayout
    if not layout then
        SoilLogger.warning("gameSettingsLayout not found on frame")
        return
    end

    local isAdmin = self:isPlayerAdmin()

    -- Section header
    local ok, err = pcall(UIHelper.createSectionHeader, layout, tr("sf_section") or "Soil & Fertilizer")
    if not ok then
        SoilLogger.warning("Failed to create section header: %s", tostring(err))
    end

    -- Auto-generate boolean toggle options from schema
    for _, def in ipairs(SettingsSchema.getBooleanSettings()) do
        local callbackName = "on_" .. def.id .. "_Changed"
        local title = tr(def.uiId .. "_short") or def.id
        local tooltip = tr(def.uiId .. "_long") or ""

        local ok3, element = pcall(UIHelper.createBinaryOption, layout, SoilSettingsUI, callbackName, title, tooltip)
        if ok3 and element then
            -- localOnly settings (HUD prefs) are always accessible; only gate server-wide settings
            local shouldDisable = not def.localOnly and not isAdmin

            if shouldDisable and element.setIsEnabled then
                element:setIsEnabled(false)
                if element.setToolTipText then
                    element:setToolTipText("Admin only")
                end
            end

            frame["soilFertilizer_" .. def.uiId] = element
        else
            SoilLogger.warning("Failed to create toggle for %s: %s", def.id, tostring(element))
        end
    end

    -- Difficulty dropdown
    local diffDef = SettingsSchema.byId["difficulty"]
    if diffDef then
        local diffOptions = {
            tr("sf_diff_1") or "Simple",
            tr("sf_diff_2") or "Realistic",
            tr("sf_diff_3") or "Hardcore"
        }

        local ok4, diffElement = pcall(UIHelper.createMultiOption, layout, SoilSettingsUI, "onDifficultyChanged", diffOptions,
            tr("sf_difficulty_short") or "Difficulty",
            tr("sf_difficulty_long") or "Soil management difficulty level")
        if ok4 and diffElement then
            if not isAdmin and diffElement.setIsEnabled then
                diffElement:setIsEnabled(false)
                if diffElement.setToolTipText then
                    diffElement:setToolTipText("Admin only")
                end
            end
            frame["soilFertilizer_" .. diffDef.uiId] = diffElement
        end
    end

    -- HUD Position dropdown
    local hudPosDef = SettingsSchema.byId["hudPosition"]
    if hudPosDef then
        local hudPosOptions = {
            tr("sf_hud_pos_1") or "Top Right",
            tr("sf_hud_pos_2") or "Top Left",
            tr("sf_hud_pos_3") or "Bottom Right",
            tr("sf_hud_pos_4") or "Bottom Left",
            tr("sf_hud_pos_5") or "Center Right",
            tr("sf_hud_pos_6") or "Custom"
        }

        local ok5, hudPosElement = pcall(UIHelper.createMultiOption, layout, SoilSettingsUI, "onHudPositionChanged", hudPosOptions,
            tr("sf_hud_position_short") or "HUD Position",
            tr("sf_hud_position_long") or "Position of the soil HUD overlay")
        if ok5 and hudPosElement then
            -- hudPosition is localOnly — all players can adjust their own HUD position
            frame["soilFertilizer_" .. hudPosDef.uiId] = hudPosElement
        end
    end

    -- HUD Color Theme dropdown
    local hudColorDef = SettingsSchema.byId["hudColorTheme"]
    if hudColorDef then
        local hudColorOptions = {
            tr("sf_hud_color_1") or "Green",
            tr("sf_hud_color_2") or "Blue",
            tr("sf_hud_color_3") or "Amber",
            tr("sf_hud_color_4") or "Mono"
        }

        local ok6, hudColorElement = pcall(UIHelper.createMultiOption, layout, SoilSettingsUI, "onHudColorThemeChanged", hudColorOptions,
            tr("sf_hud_color_theme_short") or "HUD Color Theme",
            tr("sf_hud_color_theme_long") or "Color theme for the soil HUD")
        if ok6 and hudColorElement then
            frame["soilFertilizer_" .. hudColorDef.uiId] = hudColorElement
        end
    end

    -- HUD Font Size dropdown
    local hudFontDef = SettingsSchema.byId["hudFontSize"]
    if hudFontDef then
        local hudFontOptions = {
            tr("sf_hud_font_1") or "Small",
            tr("sf_hud_font_2") or "Medium",
            tr("sf_hud_font_3") or "Large"
        }

        local ok7, hudFontElement = pcall(UIHelper.createMultiOption, layout, SoilSettingsUI, "onHudFontSizeChanged", hudFontOptions,
            tr("sf_hud_font_size_short") or "HUD Font Size",
            tr("sf_hud_font_size_long") or "Font size for the soil HUD")
        if ok7 and hudFontElement then
            frame["soilFertilizer_" .. hudFontDef.uiId] = hudFontElement
        end
    end

    -- HUD Transparency dropdown
    local hudTransDef = SettingsSchema.byId["hudTransparency"]
    if hudTransDef then
        local hudTransOptions = {
            tr("sf_hud_trans_1") or "Clear (25%)",
            tr("sf_hud_trans_2") or "Light (50%)",
            tr("sf_hud_trans_3") or "Medium (70%)",
            tr("sf_hud_trans_4") or "Dark (85%)",
            tr("sf_hud_trans_5") or "Solid (100%)"
        }

        local ok8, hudTransElement = pcall(UIHelper.createMultiOption, layout, SoilSettingsUI, "onHudTransparencyChanged", hudTransOptions,
            tr("sf_hud_transparency_short") or "HUD Transparency",
            tr("sf_hud_transparency_long") or "Background transparency of the soil HUD")
        if ok8 and hudTransElement then
            frame["soilFertilizer_" .. hudTransDef.uiId] = hudTransElement
        end
    end

    -- Finalize layout
    layout:invalidateLayout()
    if frame.updateAlternatingElements then
        frame:updateAlternatingElements(layout)
    end
    if frame.updateGeneralSettings then
        frame:updateGeneralSettings(layout)
    end

    frame.soilFertilizer_initDone = true

    -- Sync UI state from current settings
    self:updateGameSettings(frame)

    SoilLogger.info("Settings UI injected via profile-based creation (Admin: %s)", tostring(isAdmin))
end

--- Sync UI elements with current settings values. Called on frame refresh.
function SoilSettingsUI:updateGameSettings(frame)
    if not frame.soilFertilizer_initDone then return end

    for _, def in ipairs(SettingsSchema.definitions) do
        local element = frame["soilFertilizer_" .. def.uiId]
        if element then
            local val = self.settings[def.id]
            if def.type == "boolean" then
                if element.setIsChecked then
                    element:setIsChecked(val == true, false, false)
                end
            elseif def.type == "number" and element.setState then
                element:setState(val or def.default)
            end
        end
    end
end

function SoilSettingsUI:ensureResetButton(settingsFrame)
    if not settingsFrame or not settingsFrame.menuButtonInfo then return end

    if not self:isPlayerAdmin() then return end

    if not self._resetButton then
        self._resetButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = "Reset Soil Settings",
            callback = function()
                if not self:isPlayerAdmin() then
                    self:showAdminOnlyWarning()
                    return
                end

                if g_SoilFertilityManager and g_SoilFertilityManager.settings then
                    if g_client ~= nil then
                        if g_dedicatedServer then
                            g_SoilFertilityManager.settings:resetToDefaults()
                        else
                            YesNoDialog.show(
                                function(yes)
                                    if yes then
                                        if g_SoilFertilityManager.settingsGUI then
                                            g_SoilFertilityManager.settingsGUI:consoleCommandResetSettings()
                                        end
                                    end
                                end,
                                nil,
                                "Reset all Soil & Fertilizer settings to defaults?",
                                "Confirm Reset"
                            )
                        end
                    else
                        g_SoilFertilityManager.settings:resetToDefaults()
                        self:refreshUI()
                        g_gui:showInfoDialog({text="Soil & Fertilizer settings reset to defaults"})
                    end
                end
            end,
            showWhenPaused = true
        }
    end

    local exists = false
    for _, btn in ipairs(settingsFrame.menuButtonInfo) do
        if btn == self._resetButton then
            exists = true
            break
        end
    end

    if not exists then
        table.insert(settingsFrame.menuButtonInfo, self._resetButton)
        if settingsFrame.setMenuButtonInfoDirty then
            settingsFrame:setMenuButtonInfoDirty()
        end
    end
end

-- Dynamic callback generation from schema (boolean toggles)
for _, def in ipairs(SettingsSchema.getBooleanSettings()) do
    SoilSettingsUI["on_" .. def.id .. "_Changed"] = function(self, state)
        if not g_SoilFertilityManager or not g_SoilFertilityManager.settingsUI then return end
        local settingsUI = g_SoilFertilityManager.settingsUI
        local isChecked = (state == BinaryOptionElement.STATE_RIGHT)
        settingsUI:requestSettingChange(def.id, isChecked)
    end
end

-- Difficulty dropdown callback
function SoilSettingsUI:onDifficultyChanged(state)
    if not g_SoilFertilityManager or not g_SoilFertilityManager.settingsUI then return end
    g_SoilFertilityManager.settingsUI:requestSettingChange("difficulty", state)
end

-- HUD Position dropdown callback
function SoilSettingsUI:onHudPositionChanged(state)
    if not g_SoilFertilityManager or not g_SoilFertilityManager.settingsUI then return end
    g_SoilFertilityManager.settingsUI:requestSettingChange("hudPosition", state)
end

-- HUD Color Theme dropdown callback
function SoilSettingsUI:onHudColorThemeChanged(state)
    if not g_SoilFertilityManager or not g_SoilFertilityManager.settingsUI then return end
    g_SoilFertilityManager.settingsUI:requestSettingChange("hudColorTheme", state)
end

-- HUD Font Size dropdown callback
function SoilSettingsUI:onHudFontSizeChanged(state)
    if not g_SoilFertilityManager or not g_SoilFertilityManager.settingsUI then return end
    g_SoilFertilityManager.settingsUI:requestSettingChange("hudFontSize", state)
end

-- HUD Transparency dropdown callback
function SoilSettingsUI:onHudTransparencyChanged(state)
    if not g_SoilFertilityManager or not g_SoilFertilityManager.settingsUI then return end
    g_SoilFertilityManager.settingsUI:requestSettingChange("hudTransparency", state)
end

-- Install hooks at file-load time (runs once, never accumulates on level reload)
local function init()
    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(
        InGameMenuSettingsFrame.onFrameOpen,
        function(frame)
            if g_SoilFertilityManager and g_SoilFertilityManager.settingsUI then
                g_SoilFertilityManager.settingsUI:onFrameOpen(frame)
                -- Ensure reset button
                if frame.soilFertilizer_initDone then
                    g_SoilFertilityManager.settingsUI:ensureResetButton(frame)
                end
            end
        end
    )

    InGameMenuSettingsFrame.updateGameSettings = Utils.appendedFunction(
        InGameMenuSettingsFrame.updateGameSettings,
        function(frame)
            if g_SoilFertilityManager and g_SoilFertilityManager.settingsUI then
                g_SoilFertilityManager.settingsUI:updateGameSettings(frame)
            end
        end
    )

    InGameMenuSettingsFrame.updateButtons = Utils.appendedFunction(
        InGameMenuSettingsFrame.updateButtons,
        function(frame)
            if g_SoilFertilityManager and g_SoilFertilityManager.settingsUI then
                if frame.soilFertilizer_initDone then
                    g_SoilFertilityManager.settingsUI:ensureResetButton(frame)
                end
            end
        end
    )

    SoilLogger.info("Settings UI hooks installed (file-load time)")
end

init()
