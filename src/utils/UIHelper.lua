-- =========================================================
-- FS25 Realistic Soil & Fertilizer (version 1.0.0.0)
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
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        Logging.warning("sf: Missing translation for key: " .. tostring(key))
        return key
    end
    return text
end

function UIHelper.createSection(layout, textId)
    local section = nil
    for _, el in ipairs(layout.elements) do
        if el.name == "sectionHeader" then
            section = el:clone(layout)
            section.id = nil
            section:setText(getTextSafe(textId))
            layout:addElement(section)
            break
        end
    end
    return section
end

function UIHelper.createDescription(layout, textId)
    local template = nil

    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local secondChild = el.elements[2]
            if secondChild.setText then
                template = secondChild
                break
            end
        end
    end
    
    if not template then
        Logging.warning("sf: Description template not found!")
        return nil
    end
    
    local desc = template:clone(layout)
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
    
    layout:addElement(desc)
    return desc
end

function UIHelper.createBinaryOption(layout, id, textId, state, callback)
    local template = nil
    
    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild.id and (
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
    
    local row = template:clone(layout)
    row.id = nil
    
    local opt = row.elements[1]
    local lbl = row.elements[2]
    
    opt.id = nil
    opt.target = nil
    if lbl then lbl.id = nil end
    
    if opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end
    
    opt.onClickCallback = function(newState, element)
        local isChecked = (newState == 2)
        callback(isChecked)
    end
    
    if lbl and lbl.setText then
        lbl:setText(getTextSafe(textId .. "_short"))
    end
    
    layout:addElement(row)
    
    if opt.setState then
        opt:setState(1)
    end
    
    if state then
        if opt.setIsChecked then
            opt:setIsChecked(true)
        elseif opt.setState then
            opt:setState(2)
        end
    end
    
    local tooltipText = getTextSafe(textId .. "_long")
    
    if opt.setToolTipText then
        opt:setToolTipText(tooltipText)
    end
    if lbl and lbl.setToolTipText then
        lbl:setToolTipText(tooltipText)
    end
    
    opt.toolTipText = tooltipText
    if lbl then
        lbl.toolTipText = tooltipText
    end
    
    if row.setToolTipText then
        row:setToolTipText(tooltipText)
    end
    row.toolTipText = tooltipText
    
    if opt.elements and opt.elements[1] and opt.elements[1].setText then
        opt.elements[1]:setText(tooltipText)
    end
    
    return opt
end

function UIHelper.createMultiOption(layout, id, textId, options, state, callback)
    local template = nil
    
    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild.id and string.find(firstChild.id, "^multi") then
                template = el
                break
            end
        end
    end
    
    if not template then 
        Logging.warning("sf: MultiOption template not found!")
        return nil 
    end
    
    local row = template:clone(layout)
    row.id = nil
    
    local opt = row.elements[1]
    local lbl = row.elements[2]

    opt.id = nil
    opt.target = nil
    if lbl then lbl.id = nil end
    
    if opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end
    
    if opt.setTexts then
        opt:setTexts(options)
    end
    
    if opt.setState then
        opt:setState(state)
    end
    
    opt.onClickCallback = function(newState, element)
        callback(newState)
    end
    
    if lbl and lbl.setText then
        lbl:setText(getTextSafe(textId .. "_short"))
    end
    
    layout:addElement(row)
    
    local tooltipText = getTextSafe(textId .. "_long")
    
    if opt.setToolTipText then
        opt:setToolTipText(tooltipText)
    end
    if lbl and lbl.setToolTipText then
        lbl:setToolTipText(tooltipText)
    end
    
    opt.toolTipText = tooltipText
    if lbl then
        lbl.toolTipText = tooltipText
    end

    if row.setToolTipText then
        row:setToolTipText(tooltipText)
    end
    row.toolTipText = tooltipText
    
    if opt.elements and opt.elements[1] and opt.elements[1].setText then
        opt.elements[1]:setText(tooltipText)
    end
    
    print(string.format("sf: Set tooltip for %s: %s", textId, tooltipText))
    
    return opt
end