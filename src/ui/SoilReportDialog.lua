-- =========================================================
-- FS25 Realistic Soil & Fertilizer (Soil Report Dialog)
-- =========================================================
-- Full-farm soil report: paginated table of all tracked fields
-- with color-coded N/P/K/pH/OM values.
-- Press K to open (SF_SOIL_REPORT action).
-- =========================================================
-- Author: TisonK
-- =========================================================

SoilReportDialog = {}
local SoilReportDialog_mt = Class(SoilReportDialog, ScreenElement)

SoilReportDialog.MAX_ROWS = 10
SoilReportDialog.instance = nil
SoilReportDialog.xmlPath = nil

-- Status colors
SoilReportDialog.COLOR_GOOD  = {0.3, 1.0, 0.3, 1}
SoilReportDialog.COLOR_FAIR  = {1.0, 0.9, 0.3, 1}
SoilReportDialog.COLOR_POOR  = {1.0, 0.4, 0.4, 1}
SoilReportDialog.COLOR_WHITE = {1.0, 1.0, 1.0, 1}

function SoilReportDialog.getInstance(modDirectory)
    if SoilReportDialog.instance == nil then
        if SoilReportDialog.xmlPath == nil then
            SoilReportDialog.xmlPath = modDirectory .. "gui/SoilReportDialog.xml"
        end

        SoilReportDialog.instance = SoilReportDialog.new()
        g_gui:loadGui(SoilReportDialog.xmlPath, "SoilReportDialog", SoilReportDialog.instance)
    end

    return SoilReportDialog.instance
end

function SoilReportDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SoilReportDialog_mt)

    self.fieldInfos = {}
    self.sortedFieldIds = {}
    self.currentPage = 1
    self.totalPages = 1
    self.fieldRows = {}
    self.isBackAllowed = true

    return self
end

function SoilReportDialog:onCreate()
    -- Cache row elements
    for i = 0, SoilReportDialog.MAX_ROWS - 1 do
        local rowId = "fieldRow" .. i
        self.fieldRows[i] = {
            row   = self[rowId],
            bg    = self[rowId .. "Bg"],
            id    = self[rowId .. "Id"],
            n     = self[rowId .. "N"],
            p     = self[rowId .. "P"],
            k     = self[rowId .. "K"],
            ph    = self[rowId .. "pH"],
            om    = self[rowId .. "OM"],
            crop  = self[rowId .. "Crop"],
            fert  = self[rowId .. "Fert"],
        }
    end
end

--- Show dialog with current soil data
function SoilReportDialog:show()
    if g_gui.currentGui ~= nil then return end

    if not g_SoilFertilityManager or not g_SoilFertilityManager.soilSystem then
        SoilLogger.warning("[SoilReport] Soil system not available")
        return
    end

    self.currentPage = 1
    self:collectFieldData()
    self:updateDisplay()
    g_gui:showDialog("SoilReportDialog")
end

--- Get the local player's farm ID.
---@return number
local function getLocalFarmId()
    if g_currentMission and g_currentMission.player then
        local id = g_currentMission.player.farmId
        if id and id > 0 then return id end
    end

    if g_currentMission and g_currentMission.userManager and g_currentMission.playerUserId then
        local user = g_currentMission.userManager:getUserByUserId(g_currentMission.playerUserId)
        if user and user.farmId and user.farmId > 0 then return user.farmId end
    end

    return 1  -- singleplayer is always farm 1
end

--- Returns true if the farmland is owned by the given farm.
--- Uses g_farmlandManager.farmlandMapping[farmlandId] — the authoritative
--- FS25 ownership table (confirmed in FarmlandManager.lua source).
---@param farmlandId number
---@param localFarmId number
---@return boolean
local function isFarmlandOwnedByFarm(farmlandId, localFarmId)
    if not g_farmlandManager or not g_farmlandManager.farmlandMapping then
        return false
    end
    return g_farmlandManager.farmlandMapping[farmlandId] == localFarmId
end

--- Collect field data limited to fields owned by the local player's farm.
--- Uses field.fieldState.ownerFarmId via FieldManager.farmlandIdFieldMapping.
function SoilReportDialog:collectFieldData()
    self.fieldInfos = {}
    self.sortedFieldIds = {}

    local soilSystem = g_SoilFertilityManager.soilSystem
    if not soilSystem or not soilSystem.fieldData then return end

    local localFarmId = getLocalFarmId()

    local filtered = {}
    for fieldId, _ in pairs(soilSystem.fieldData) do
        if isFarmlandOwnedByFarm(fieldId, localFarmId) then
            table.insert(filtered, fieldId)
        end
    end

    -- Fallback: if fieldState isn't populated yet or player owns no fields,
    -- show all tracked fields so the dialog is never uselessly blank.
    if #filtered == 0 then
        SoilLogger.warning("[SoilReport] No owned fields found for farmId %s - showing all tracked fields", tostring(localFarmId))
        for fieldId, _ in pairs(soilSystem.fieldData) do
            table.insert(self.sortedFieldIds, fieldId)
        end
    else
        self.sortedFieldIds = filtered
    end

    table.sort(self.sortedFieldIds)

    -- Build info for each field
    for _, fieldId in ipairs(self.sortedFieldIds) do
        local info = soilSystem:getFieldInfo(fieldId)
        if info then
            self.fieldInfos[fieldId] = info
        else
            SoilLogger.warning("[SoilReport] getFieldInfo returned nil for field %s", tostring(fieldId))
        end
    end

    -- Calculate pages
    self.totalPages = math.ceil(#self.sortedFieldIds / SoilReportDialog.MAX_ROWS)
    if self.totalPages < 1 then
        self.totalPages = 1
    end
end

--- Update all display elements
function SoilReportDialog:updateDisplay()
    -- Summary section
    local totalFields = #self.sortedFieldIds
    local needFertCount = 0
    for _, info in pairs(self.fieldInfos) do
        if info.needsFertilization then
            needFertCount = needFertCount + 1
        end
    end

    if self.fieldCountText then
        self.fieldCountText:setText(tostring(totalFields))
    end
    if self.needFertText then
        self.needFertText:setText(tostring(needFertCount))
        if needFertCount > 0 then
            self.needFertText:setTextColor(1, 0.4, 0.4, 1)
        else
            self.needFertText:setTextColor(0.3, 1, 0.3, 1)
        end
    end
    if self.difficultyText and g_SoilFertilityManager.settings then
        self.difficultyText:setText(g_SoilFertilityManager.settings:getDifficultyName())
    end

    -- Show/hide no-data message
    local hasData = totalFields > 0
    if self.noDataText then
        self.noDataText:setVisible(not hasData)
    end

    self:updateFieldRows()
    self:updatePagination()
end

--- Get status color for a nutrient value
---@param status string "Good", "Fair", or "Poor"
---@return table RGBA color
local function getStatusColor(status)
    if status == "Good" then
        return SoilReportDialog.COLOR_GOOD
    elseif status == "Fair" then
        return SoilReportDialog.COLOR_FAIR
    elseif status == "Poor" then
        return SoilReportDialog.COLOR_POOR
    end
    return SoilReportDialog.COLOR_WHITE
end

--- Get pH status color
---@param ph number
---@return table RGBA color
local function getPHColor(ph)
    local rc = SoilConstants.REPORT_COLORS
    if ph >= rc.PH_GOOD_LOW and ph <= rc.PH_GOOD_HIGH then
        return SoilReportDialog.COLOR_GOOD
    elseif ph >= rc.PH_FAIR_LOW and ph <= rc.PH_FAIR_HIGH then
        return SoilReportDialog.COLOR_FAIR
    end
    return SoilReportDialog.COLOR_POOR
end

--- Get organic matter color
---@param om number
---@return table RGBA color
local function getOMColor(om)
    local rc = SoilConstants.REPORT_COLORS
    if om >= rc.OM_GOOD then
        return SoilReportDialog.COLOR_GOOD
    elseif om >= rc.OM_FAIR then
        return SoilReportDialog.COLOR_FAIR
    end
    return SoilReportDialog.COLOR_POOR
end

--- Get fertilization recommendation and color based on field info
---@param info table Field information from SoilFertilitySystem:getFieldInfo
---@return string Recommendation text
---@return table RGBA color for the recommendation text
function SoilReportDialog:getFertilizationRecommendation(info)
    local recommendations = {}
    local overallStatus = "Good" -- Start optimistic, downgrade as needed

    -- Check individual nutrient statuses
    if info.nitrogen.status == "Poor" then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_n_poor", "N (Poor)"))
        overallStatus = "Poor"
    elseif info.nitrogen.status == "Fair" then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_n_fair", "N (Fair)"))
        if overallStatus == "Good" then overallStatus = "Fair" end
    end

    if info.phosphorus.status == "Poor" then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_p_poor", "P (Poor)"))
        overallStatus = "Poor"
    elseif info.phosphorus.status == "Fair" then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_p_fair", "P (Fair)"))
        if overallStatus == "Good" then overallStatus = "Fair" end
    end

    if info.potassium.status == "Poor" then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_k_poor", "K (Poor)"))
        overallStatus = "Poor"
    elseif info.potassium.status == "Fair" then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_k_fair", "K (Fair)"))
        if overallStatus == "Good" then overallStatus = "Fair" end
    end

    -- Check pH status
    local phColor = getPHColor(info.pH)
    if phColor == SoilReportDialog.COLOR_POOR then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_ph_adjust", "Adjust pH (Poor)"))
        overallStatus = "Poor"
    elseif phColor == SoilReportDialog.COLOR_FAIR then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_ph_monitor", "Monitor pH (Fair)"))
        if overallStatus == "Good" then overallStatus = "Fair" end
    end

    -- Check Organic Matter status
    local omColor = getOMColor(info.organicMatter)
    if omColor == SoilReportDialog.COLOR_POOR then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_om_increase", "Increase OM (Poor)"))
        overallStatus = "Poor"
    elseif omColor == SoilReportDialog.COLOR_FAIR then
        table.insert(recommendations, g_i18n:getText("sf_report_rec_om_maintain", "Maintain OM (Fair)"))
        if overallStatus == "Good" then overallStatus = "Fair" end
    end

    local recommendationString
    local recommendationColor

    if #recommendations > 0 then
        recommendationString = g_i18n:getText("sf_report_rec_needs", "Needs: ") .. table.concat(recommendations, ", ")
        if overallStatus == "Poor" then
            recommendationColor = SoilReportDialog.COLOR_POOR
        else
            recommendationColor = SoilReportDialog.COLOR_FAIR
        end
    else
        recommendationString = g_i18n:getText("sf_report_rec_optimal", "Soil Health: Optimal")
        recommendationColor = SoilReportDialog.COLOR_GOOD
    end

    return recommendationString, recommendationColor
end

--- Set text and color on a text element
---@param element table GUI text element
---@param text string
---@param color table RGBA
local function setColoredText(element, text, color)
    if element then
        element:setText(text)
        element:setTextColor(color[1], color[2], color[3], color[4])
    end
end

--- Update field rows for current page
function SoilReportDialog:updateFieldRows()
    local startIndex = (self.currentPage - 1) * SoilReportDialog.MAX_ROWS + 1

    for i = 0, SoilReportDialog.MAX_ROWS - 1 do
        local dataIndex = startIndex + i
        local row = self.fieldRows[i]

        if row and row.row then
            if dataIndex <= #self.sortedFieldIds then
                local fieldId = self.sortedFieldIds[dataIndex]
                local info = self.fieldInfos[fieldId]

                row.row:setVisible(true)

                if info then
                    -- Field ID
                    if row.id then
                        row.id:setText(tostring(fieldId))
                    end

                    -- Nitrogen (color-coded)
                    local nColor = getStatusColor(info.nitrogen.status)
                    setColoredText(row.n, tostring(info.nitrogen.value), nColor)

                    -- Phosphorus (color-coded)
                    local pColor = getStatusColor(info.phosphorus.status)
                    setColoredText(row.p, tostring(info.phosphorus.value), pColor)

                    -- Potassium (color-coded)
                    local kColor = getStatusColor(info.potassium.status)
                    setColoredText(row.k, tostring(info.potassium.value), kColor)

                    -- pH (color-coded)
                    local phColor = getPHColor(info.pH)
                    setColoredText(row.ph, string.format("%.1f", info.pH), phColor)

                    -- Organic Matter (color-coded)
                    local omColor = getOMColor(info.organicMatter)
                    setColoredText(row.om, string.format("%.1f", info.organicMatter), omColor)

                    -- Last Crop
                    if row.crop then
                        local noneText = g_i18n:getText("sf_report_none", "None")
                        local cropName = info.lastCrop or noneText
                        -- Capitalize first letter
                        if cropName ~= noneText then
                            cropName = cropName:sub(1,1):upper() .. cropName:sub(2)
                        end
                        row.crop:setText(cropName)
                        row.crop:setTextColor(0.7, 0.7, 0.7, 1)
                    end

                    -- Needs Fertilization
                    if row.fert then
                        local recommendationText, recommendationColor = self:getFertilizationRecommendation(info)
                        setColoredText(row.fert, recommendationText, recommendationColor)
                    end

                    -- Row background tint for fields needing attention
                    if row.bg then
                        if info.needsFertilization then
                            row.bg:setImageColor(nil, 0.18, 0.1, 0.1, 1)
                        else
                            if i % 2 == 0 then
                                row.bg:setImageColor(nil, 0.1, 0.1, 0.1, 1)
                            else
                                row.bg:setImageColor(nil, 0.12, 0.12, 0.14, 1)
                            end
                        end
                    end
                end
            else
                row.row:setVisible(false)
            end
        end
    end
end

--- Update pagination controls
function SoilReportDialog:updatePagination()
    local totalFields = #self.sortedFieldIds

    if totalFields > 0 then
        local startIndex = (self.currentPage - 1) * SoilReportDialog.MAX_ROWS + 1
        local endIndex = math.min(startIndex + SoilReportDialog.MAX_ROWS - 1, totalFields)

        if self.pageInfoText then
            local pageFmt = g_i18n:getText("sf_report_page_info", "Fields %d-%d of %d  |  Page %d of %d")
            self.pageInfoText:setText(string.format(pageFmt,
                startIndex, endIndex, totalFields, self.currentPage, self.totalPages))
            self.pageInfoText:setVisible(true)
        end
    else
        if self.pageInfoText then
            self.pageInfoText:setVisible(false)
        end
    end

    if self.prevButton then
        self.prevButton:setDisabled(self.currentPage <= 1 or totalFields == 0)
    end
    if self.nextButton then
        self.nextButton:setDisabled(self.currentPage >= self.totalPages or totalFields == 0)
    end
end

function SoilReportDialog:onPrevPage()
    if self.currentPage > 1 then
        self.currentPage = self.currentPage - 1
        self:updateFieldRows()
        self:updatePagination()
    end
end

function SoilReportDialog:onNextPage()
    if self.currentPage < self.totalPages then
        self.currentPage = self.currentPage + 1
        self:updateFieldRows()
        self:updatePagination()
    end
end

function SoilReportDialog:onCloseDialog()
    g_gui:closeDialogByName("SoilReportDialog")
end

function SoilReportDialog:onClickBack()
    g_gui:closeDialogByName("SoilReportDialog")
end

function SoilReportDialog:inputEvent(action, value, eventUsed)
    eventUsed = SoilReportDialog:superClass().inputEvent(self, action, value, eventUsed)

    if not eventUsed and action == InputAction.MENU_BACK and value > 0 then
        g_gui:closeDialogByName("SoilReportDialog")
        eventUsed = true
    end

    return eventUsed
end

function SoilReportDialog:onClose()
    SoilReportDialog:superClass().onClose(self)
    self.fieldInfos = {}
    self.sortedFieldIds = {}
    self.currentPage = 1
    self.totalPages = 1
end
