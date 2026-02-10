-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.1.6)
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

local function getTextSafe(key)
    if not g_i18n then
        return key
    end
    
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        Logging.warning("sf: Missing translation for key: " .. tostring(key))
        return key
    end
    return text
end

function UIHelper.createSection(layout, textId)
    if not layout or not layout.elements then
        Logging.error("sf: Invalid layout passed to createSection")
        return nil
    end
    
    local section = nil
    for _, el in ipairs(layout.elements) do
        if el and el.name == "sectionHeader" then
            local success, cloned = pcall(function() return el:clone(layout) end)
            if success and cloned then
                section = cloned
                section.id = nil
                if section.setText then
                    section:setText(getTextSafe(textId))
                end
                local addSuccess = pcall(function() layout:addElement(section) end)
                if not addSuccess then
                    Logging.error("sf: Failed to add section to layout")
                    return nil
                end
            end
            break
        end
    end
    return section
end

function UIHelper.createDescription(layout, textId)
    if not layout or not layout.elements then
        Logging.error("sf: Invalid layout passed to createDescription")
        return nil
    end

    local template = nil

    for _, el in ipairs(layout.elements) do
        if el and el.elements and #el.elements >= 2 then
            local secondChild = el.elements[2]
            if secondChild and secondChild.setText then
                template = secondChild
                break
            end
        end
    end
    
    if not template then
        Logging.warning("sf: Description template not found!")
        return nil
    end
    
    local success, desc = pcall(function() return template:clone(layout) end)
    if not success or not desc then
        Logging.error("sf: Failed to clone description template")
        return nil
    end
    
    desc.id = nil
    
    if desc.setText then
        desc:setText(getTextSafe(textId))
    end
    
    if desc.textSize then
        desc.textSize = desc.textSize * 0.85
    end
    
    if desc.textColor then
        desc.textColor = {0.7, 0.7, 0.7, 1}
    end
    
    local addSuccess = pcall(function() layout:addElement(desc) end)
    if not addSuccess then
        Logging.error("sf: Failed to add description to layout")
        return nil
    end
    
    return desc
end

function UIHelper.createBinaryOption(layout, id, textId, state, callback)
    if not layout or not layout.elements then
        Logging.error("sf: Invalid layout passed to createBinaryOption")
        return nil
    end
    
    local template = nil
    
    for _, el in ipairs(layout.elements) do
        if el and el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild and firstChild.id and (
                string.find(firstChild.id, "^check") or 
                string.find(firstChild.id, "Check")
            ) then
                template = el
                break
            end
        end
    end
    
    if not template then 
        Logging.warning("sf: BinaryOption template not found!")
        return nil 
    end
    
    local success, row = pcall(function() return template:clone(layout) end)
    if not success or not row then
        Logging.error("sf: Failed to clone binary option template")
        return nil
    end
    
    row.id = nil
    
    if not row.elements or #row.elements < 2 then
        Logging.error("sf: Cloned row has invalid elements")
        return nil
    end
    
    local opt = row.elements[1]
    local lbl = row.elements[2]
    
    if opt then opt.id = nil end
    if opt then opt.target = nil end
    if lbl then lbl.id = nil end
    
    if opt and opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end
    
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
    
    local addSuccess = pcall(function() layout:addElement(row) end)
    if not addSuccess then
        Logging.error("sf: Failed to add binary option to layout")
        return nil
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
    
    return opt
end

function UIHelper.createMultiOption(layout, id, textId, options, state, callback)
    if not layout or not layout.elements then
        Logging.error("sf: Invalid layout passed to createMultiOption")
        return nil
    end
    
    local template = nil
    
    for _, el in ipairs(layout.elements) do
        if el and el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild and firstChild.id and string.find(firstChild.id, "^multi") then
                template = el
                break
            end
        end
    end
    
    if not template then 
        Logging.warning("sf: MultiOption template not found!")
        return nil 
    end
    
    local success, row = pcall(function() return template:clone(layout) end)
    if not success or not row then
        Logging.error("sf: Failed to clone multi option template")
        return nil
    end
    
    row.id = nil
    
    if not row.elements or #row.elements < 2 then
        Logging.error("sf: Cloned row has invalid elements")
        return nil
    end
    
    local opt = row.elements[1]
    local lbl = row.elements[2]

    if opt then opt.id = nil end
    if opt then opt.target = nil end
    if lbl then lbl.id = nil end
    
    if opt and opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end
    
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
    
    local addSuccess = pcall(function() layout:addElement(row) end)
    if not addSuccess then
        Logging.error("sf: Failed to add multi option to layout")
        return nil
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
    
    return opt
end