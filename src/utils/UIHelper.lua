-- =========================================================
-- FS25 Realistic Soil & Fertilizer
-- =========================================================
-- UIHelper - Profile-based UI element creation
-- Pattern from: FS25_UsedPlus/src/gui/UsedPlusSettingsMenuExtension.lua
-- =========================================================
-- Replaces clone-based approach that corrupted other mods'
-- settings pages on dedicated server clients (GitHub #21).
-- =========================================================
---@class UIHelper
UIHelper = {}

local function getTextSafe(key)
    if not g_i18n then
        return key
    end

    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        SoilLogger.warning("[SoilFertilizer] Missing translation for key: " .. tostring(key))
        return key
    end
    return text
end

--- Create a section header element using FS25 profile
---@param layout table The gameSettingsLayout to add to
---@param text string The section header text
---@return table|nil The created text element
function UIHelper.createSectionHeader(layout, text)
    if not layout then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createSectionHeader")
        return nil
    end

    local textElement = TextElement.new()
    local profile = g_gui:getProfile("fs25_settingsSectionHeader")
    textElement.name = "sectionHeader"
    textElement:loadProfile(profile, true)
    textElement:setText(text)
    layout:addElement(textElement)
    textElement:onGuiSetupFinished()

    return textElement
end

--- Create a binary (Yes/No) toggle option using FS25 profiles
---@param layout table The gameSettingsLayout to add to
---@param callbackTarget table The object that owns the callback method
---@param callbackName string The method name on callbackTarget to call on click
---@param title string Display text for the setting label
---@param tooltip string Tooltip text shown on hover
---@return table|nil The created BinaryOptionElement
function UIHelper.createBinaryOption(layout, callbackTarget, callbackName, title, tooltip)
    if not layout then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createBinaryOption")
        return nil
    end

    local bitMap = BitmapElement.new()
    local bitMapProfile = g_gui:getProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)

    local binaryOption = BinaryOptionElement.new()
    binaryOption.useYesNoTexts = true
    local binaryOptionProfile = g_gui:getProfile("fs25_settingsBinaryOption")
    binaryOption:loadProfile(binaryOptionProfile, true)
    binaryOption.target = callbackTarget
    binaryOption:setCallback("onClickCallback", callbackName)

    local titleElement = TextElement.new()
    local titleProfile = g_gui:getProfile("fs25_settingsMultiTextOptionTitle")
    titleElement:loadProfile(titleProfile, true)
    titleElement:setText(title)

    local tooltipElement = TextElement.new()
    local tooltipProfile = g_gui:getProfile("fs25_multiTextOptionTooltip")
    tooltipElement.name = "ignore"
    tooltipElement:loadProfile(tooltipProfile, true)
    tooltipElement:setText(tooltip)

    binaryOption:addElement(tooltipElement)
    bitMap:addElement(binaryOption)
    bitMap:addElement(titleElement)

    binaryOption:onGuiSetupFinished()
    titleElement:onGuiSetupFinished()
    tooltipElement:onGuiSetupFinished()

    layout:addElement(bitMap)
    bitMap:onGuiSetupFinished()

    return binaryOption
end

--- Create a multi-text option (dropdown) using FS25 profiles
---@param layout table The gameSettingsLayout to add to
---@param callbackTarget table The object that owns the callback method
---@param callbackName string The method name on callbackTarget to call on click
---@param texts table Array of display strings for the dropdown options
---@param title string Display text for the setting label
---@param tooltip string Tooltip text shown on hover
---@return table|nil The created MultiTextOptionElement
function UIHelper.createMultiOption(layout, callbackTarget, callbackName, texts, title, tooltip)
    if not layout then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createMultiOption")
        return nil
    end

    local bitMap = BitmapElement.new()
    local bitMapProfile = g_gui:getProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)

    local multiTextOption = MultiTextOptionElement.new()
    local multiTextOptionProfile = g_gui:getProfile("fs25_settingsMultiTextOption")
    multiTextOption:loadProfile(multiTextOptionProfile, true)
    multiTextOption.target = callbackTarget
    multiTextOption:setCallback("onClickCallback", callbackName)
    multiTextOption:setTexts(texts)

    local titleElement = TextElement.new()
    local titleProfile = g_gui:getProfile("fs25_settingsMultiTextOptionTitle")
    titleElement:loadProfile(titleProfile, true)
    titleElement:setText(title)

    local tooltipElement = TextElement.new()
    local tooltipProfile = g_gui:getProfile("fs25_multiTextOptionTooltip")
    tooltipElement.name = "ignore"
    tooltipElement:loadProfile(tooltipProfile, true)
    tooltipElement:setText(tooltip)

    multiTextOption:addElement(tooltipElement)
    bitMap:addElement(multiTextOption)
    bitMap:addElement(titleElement)

    multiTextOption:onGuiSetupFinished()
    titleElement:onGuiSetupFinished()
    tooltipElement:onGuiSetupFinished()

    layout:addElement(bitMap)
    bitMap:onGuiSetupFinished()

    return multiTextOption
end
