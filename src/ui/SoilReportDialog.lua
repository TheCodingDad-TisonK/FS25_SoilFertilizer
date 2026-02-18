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

--- Collect field data from the soil system
function SoilReportDialog:collectFieldData()
    self.fieldInfos = {}
    self.sortedFieldIds = {}

    local soilSystem = g_SoilFertilityManager.soilSystem
    if not soilSystem or not soilSystem.fieldData then return end

    -- Collect sorted field IDs
    for fieldId, _ in pairs(soilSystem.fieldData) do
        table.insert(self.sortedFieldIds, fieldId)
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
                        if info.needsFertilization then
                            row.fert:setText(g_i18n:getText("sf_report_yes", "YES"))
                            row.fert:setTextColor(1, 0.4, 0.4, 1)
                        else
                            row.fert:setText(g_i18n:getText("sf_report_ok", "OK"))
                            row.fert:setTextColor(0.3, 1, 0.3, 1)
                        end
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
