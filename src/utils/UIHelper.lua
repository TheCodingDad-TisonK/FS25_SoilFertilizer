-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.4.1)
-- =========================================================
-- Realistic soil fertility and fertilizer management
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
---@class UIHelper
UIHelper = {}

-- Template cache to avoid repeated searches and ensure consistency
UIHelper.templateCache = {
    sectionHeader = nil,
    description = nil,
    binaryOption = nil,
    multiOption = nil,
    initialized = false
}

-- Reset template cache (called on mission load/unload)
function UIHelper.resetTemplateCache()
    UIHelper.templateCache = {
        sectionHeader = nil,
        description = nil,
        binaryOption = nil,
        multiOption = nil,
        initialized = false
    }
    SoilLogger.info("UI template cache reset")
end

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

-- Validate that an element has the expected structure for section headers
local function validateSectionTemplate(element)
    return element and
           element.name == "sectionHeader" and
           type(element.clone) == "function" and
           type(element.setText) == "function"
end

-- Validate that an element has the expected structure for descriptions
local function validateDescriptionTemplate(element)
    return element and
           type(element.clone) == "function" and
           type(element.setText) == "function"
end

-- Validate that an element has the expected structure for binary options
local function validateBinaryTemplate(element)
    if not element or not element.elements or #element.elements < 2 then
        return false
    end

    local opt = element.elements[1]
    local lbl = element.elements[2]

    -- Verify structure
    return opt and lbl and
           type(element.clone) == "function" and
           type(opt.setState) == "function" and
           type(lbl.setText) == "function"
end

-- Validate that an element has the expected structure for multi options
local function validateMultiTemplate(element)
    if not element or not element.elements or #element.elements < 2 then
        return false
    end

    local opt = element.elements[1]
    local lbl = element.elements[2]

    -- Verify structure
    return opt and lbl and
           type(element.clone) == "function" and
           type(opt.setTexts) == "function" and
           type(opt.setState) == "function" and
           type(lbl.setText) == "function"
end

-- Find and cache section header template
local function findSectionTemplate(layout)
    if UIHelper.templateCache.sectionHeader then
        return UIHelper.templateCache.sectionHeader
    end

    if not layout or not layout.elements then
        return nil
    end

    for _, el in ipairs(layout.elements) do
        if validateSectionTemplate(el) then
            SoilLogger.info("Found and cached section header template")
            UIHelper.templateCache.sectionHeader = el
            return el
        end
    end

    SoilLogger.warning("Section header template not found in layout")
    return nil
end

-- Find and cache description template
local function findDescriptionTemplate(layout)
    if UIHelper.templateCache.description then
        return UIHelper.templateCache.description
    end

    if not layout or not layout.elements then
        return nil
    end

    for _, el in ipairs(layout.elements) do
        if el and el.elements and #el.elements >= 2 then
            local secondChild = el.elements[2]
            if validateDescriptionTemplate(secondChild) then
                SoilLogger.info("Found and cached description template")
                UIHelper.templateCache.description = secondChild
                return secondChild
            end
        end
    end

    SoilLogger.warning("Description template not found in layout")
    return nil
end

-- Find and cache binary option template with improved matching
local function findBinaryTemplate(layout)
    if UIHelper.templateCache.binaryOption then
        return UIHelper.templateCache.binaryOption
    end

    if not layout or not layout.elements then
        return nil
    end

    -- Search for valid checkbox templates
    -- Try multiple strategies to handle different mod configurations
    local candidates = {}

    for _, el in ipairs(layout.elements) do
        if el and el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]

            -- Strategy 1: Look for elements with "check" in ID (original approach)
            if firstChild and firstChild.id then
                local id = tostring(firstChild.id)
                if string.find(id, "check") or string.find(id, "Check") then
                    table.insert(candidates, el)
                end
            end
        end
    end

    -- Validate candidates in order and use the first valid one
    for _, candidate in ipairs(candidates) do
        if validateBinaryTemplate(candidate) then
            SoilLogger.info("Found and cached binary option template (checked %d candidates)", #candidates)
            UIHelper.templateCache.binaryOption = candidate
            return candidate
        end
    end

    SoilLogger.warning("Binary option template not found (checked %d candidates)", #candidates)
    return nil
end

-- Find and cache multi option template with improved matching
local function findMultiTemplate(layout)
    if UIHelper.templateCache.multiOption then
        return UIHelper.templateCache.multiOption
    end

    if not layout or not layout.elements then
        return nil
    end

    -- Search for valid multi-option templates
    local candidates = {}

    for _, el in ipairs(layout.elements) do
        if el and el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]

            -- Look for elements with "multi" in ID
            if firstChild and firstChild.id then
                local id = tostring(firstChild.id)
                if string.find(id, "multi") then
                    table.insert(candidates, el)
                end
            end
        end
    end

    -- Validate candidates in order and use the first valid one
    for _, candidate in ipairs(candidates) do
        if validateMultiTemplate(candidate) then
            SoilLogger.info("Found and cached multi option template (checked %d candidates)", #candidates)
            UIHelper.templateCache.multiOption = candidate
            return candidate
        end
    end

    SoilLogger.warning("Multi option template not found (checked %d candidates)", #candidates)
    return nil
end

function UIHelper.createSection(layout, textId)
    if not layout or not layout.elements then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createSection")
        return nil
    end

    local template = findSectionTemplate(layout)
    if not template then
        SoilLogger.error("[SoilFertilizer] No valid section template found")
        return nil
    end

    local success, section = pcall(function() return template:clone(layout) end)
    if not success or not section then
        SoilLogger.error("[SoilFertilizer] Failed to clone section template: %s", tostring(success))
        return nil
    end

    section.id = nil

    if section.setText then
        section:setText(getTextSafe(textId))
    end

    -- Defensive styling: ensure visibility
    if section.setVisible then
        section:setVisible(true)
    end
    section.visible = true

    -- Ensure text color is not white-on-white
    if section.textColor then
        section.textColor = {0.95, 0.95, 0.95, 1.0}
    end

    SoilLogger.info("Created section header: %s (visible=%s)", textId, tostring(section.visible))
    return section
end

function UIHelper.createDescription(layout, textId)
    if not layout or not layout.elements then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createDescription")
        return nil
    end

    local template = findDescriptionTemplate(layout)
    if not template then
        SoilLogger.error("[SoilFertilizer] No valid description template found")
        return nil
    end

    local success, desc = pcall(function() return template:clone(layout) end)
    if not success or not desc then
        SoilLogger.error("[SoilFertilizer] Failed to clone description template: %s", tostring(success))
        return nil
    end

    desc.id = nil

    if desc.setText then
        desc:setText(getTextSafe(textId))
    end

    if desc.textSize then
        desc.textSize = desc.textSize * 0.85
    end

    -- Defensive styling: explicit colors and visibility
    if desc.textColor then
        desc.textColor = {0.7, 0.7, 0.7, 1.0}
    end

    if desc.setVisible then
        desc:setVisible(true)
    end
    desc.visible = true

    -- Ensure alpha is not 0
    if desc.alpha ~= nil then
        desc.alpha = 1.0
    end

    SoilLogger.info("Created description: %s (visible=%s)", textId, tostring(desc.visible))
    return desc
end

function UIHelper.createBinaryOption(layout, id, textId, state, callback)
    if not layout or not layout.elements then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createBinaryOption")
        return nil
    end

    local template = findBinaryTemplate(layout)
    if not template then
        SoilLogger.error("[SoilFertilizer] No valid binary option template found")
        return nil
    end

    local success, row = pcall(function() return template:clone(layout) end)
    if not success or not row then
        SoilLogger.error("[SoilFertilizer] Failed to clone binary option template: %s", tostring(success))
        return nil
    end

    -- Validate cloned structure
    if not row.elements or #row.elements < 2 then
        SoilLogger.error("[SoilFertilizer] Cloned binary option has invalid structure")
        return nil
    end

    row.id = nil

    local opt = row.elements[1]
    local lbl = row.elements[2]

    -- Additional validation of cloned elements
    if not opt or not lbl or not opt.setState or not lbl.setText then
        SoilLogger.error("[SoilFertilizer] Cloned binary option elements missing required methods")
        return nil
    end

    if opt then opt.id = nil end
    if opt then opt.target = nil end
    if lbl then lbl.id = nil end

    if opt and opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end

    -- Defensive styling: ensure visibility and proper colors
    if row.setVisible then
        row:setVisible(true)
    end
    row.visible = true

    if opt then
        if opt.setVisible then opt:setVisible(true) end
        opt.visible = true
        if opt.alpha ~= nil then opt.alpha = 1.0 end
    end

    if lbl then
        if lbl.setVisible then lbl:setVisible(true) end
        lbl.visible = true
        if lbl.textColor then
            lbl.textColor = {0.9, 0.9, 0.9, 1.0} -- Light gray, clearly visible
        end
        if lbl.alpha ~= nil then lbl.alpha = 1.0 end
    end

    if opt then
        opt.onClickCallback = function(newState, element)
            local isChecked = (newState == 2)
            if callback then
                callback(isChecked)
            end
        end
    end

    if lbl and lbl.setText then
        lbl:setText(getTextSafe(textId .. "_short"))
    end

    if opt and opt.setState then
        opt:setState(1)
    end

    if state and opt then
        if opt.setIsChecked then
            opt:setIsChecked(true)
        elseif opt.setState then
            opt:setState(2)
        end
    end

    local tooltipText = getTextSafe(textId .. "_long")

    if opt and opt.setToolTipText then
        opt:setToolTipText(tooltipText)
    end
    if lbl and lbl.setToolTipText then
        lbl:setToolTipText(tooltipText)
    end

    if opt then opt.toolTipText = tooltipText end
    if lbl then lbl.toolTipText = tooltipText end

    if row.setToolTipText then
        row:setToolTipText(tooltipText)
    end
    row.toolTipText = tooltipText

    if opt and opt.elements and opt.elements[1] and opt.elements[1].setText then
        opt.elements[1]:setText(tooltipText)
    end

    SoilLogger.info("Created binary option: %s (state=%s, visible=%s, lblColor=%s)",
        textId, tostring(state), tostring(row.visible),
        lbl.textColor and string.format("%.1f,%.1f,%.1f", lbl.textColor[1], lbl.textColor[2], lbl.textColor[3]) or "nil")

    return opt
end

function UIHelper.createMultiOption(layout, id, textId, options, state, callback)
    if not layout or not layout.elements then
        SoilLogger.error("[SoilFertilizer] Invalid layout passed to createMultiOption")
        return nil
    end

    local template = findMultiTemplate(layout)
    if not template then
        SoilLogger.error("[SoilFertilizer] No valid multi option template found")
        return nil
    end

    local success, row = pcall(function() return template:clone(layout) end)
    if not success or not row then
        SoilLogger.error("[SoilFertilizer] Failed to clone multi option template: %s", tostring(success))
        return nil
    end

    -- Validate cloned structure
    if not row.elements or #row.elements < 2 then
        SoilLogger.error("[SoilFertilizer] Cloned multi option has invalid structure")
        return nil
    end

    row.id = nil

    local opt = row.elements[1]
    local lbl = row.elements[2]

    -- Additional validation of cloned elements
    if not opt or not lbl or not opt.setTexts or not opt.setState or not lbl.setText then
        SoilLogger.error("[SoilFertilizer] Cloned multi option elements missing required methods")
        return nil
    end

    if opt then opt.id = nil end
    if opt then opt.target = nil end
    if lbl then lbl.id = nil end

    if opt and opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end

    -- Defensive styling: ensure visibility and proper colors
    if row.setVisible then
        row:setVisible(true)
    end
    row.visible = true

    if opt then
        if opt.setVisible then opt:setVisible(true) end
        opt.visible = true
        if opt.alpha ~= nil then opt.alpha = 1.0 end
    end

    if lbl then
        if lbl.setVisible then lbl:setVisible(true) end
        lbl.visible = true
        if lbl.textColor then
            lbl.textColor = {0.9, 0.9, 0.9, 1.0} -- Light gray, clearly visible
        end
        if lbl.alpha ~= nil then lbl.alpha = 1.0 end
    end

    if opt and opt.setTexts then
        opt:setTexts(options)
    end

    if opt and opt.setState then
        opt:setState(state)
    end

    if opt then
        opt.onClickCallback = function(newState, element)
            if callback then
                callback(newState)
            end
        end
    end

    if lbl and lbl.setText then
        lbl:setText(getTextSafe(textId .. "_short"))
    end

    local tooltipText = getTextSafe(textId .. "_long")

    if opt and opt.setToolTipText then
        opt:setToolTipText(tooltipText)
    end
    if lbl and lbl.setToolTipText then
        lbl:setToolTipText(tooltipText)
    end

    if opt then opt.toolTipText = tooltipText end
    if lbl then lbl.toolTipText = tooltipText end

    if row.setToolTipText then
        row:setToolTipText(tooltipText)
    end
    row.toolTipText = tooltipText

    if opt and opt.elements and opt.elements[1] and opt.elements[1].setText then
        opt.elements[1]:setText(tooltipText)
    end

    SoilLogger.info("Created multi option: %s (state=%s, visible=%s, lblColor=%s)",
        textId, tostring(state), tostring(row.visible),
        lbl.textColor and string.format("%.1f,%.1f,%.1f", lbl.textColor[1], lbl.textColor[2], lbl.textColor[3]) or "nil")

    return opt
end