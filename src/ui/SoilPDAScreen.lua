-- =========================================================
-- FS25 Soil & Fertilizer — PDA Screen
-- =========================================================
-- Registers a dedicated page in the InGameMenu (PDA) with
-- three tabs: Soil Map overview, Fields table, Treatment plan.
--
-- Pattern: identical to FS25_MarketDynamics MDMMarketScreen.
--   - Extends TabbedMenuFrameElement
--   - Static register() / _performRegistration() hooks
--   - SmoothList datasource/delegate for Fields + Treatment
--
-- Lifecycle (hooks installed at bottom of this file):
--   Mission00.loadMission00Finished  → register PDA page
--   FSBaseMission.update             → deferred retry + refresh
--   FSBaseMission.delete             → cleanup
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilPDAScreen
SoilPDAScreen = {}
SoilPDAScreen._mt = Class(SoilPDAScreen, TabbedMenuFrameElement)

SoilPDAScreen.CLASS_NAME     = "SoilPDAScreen"
SoilPDAScreen.MENU_PAGE_NAME = "menuSoilFertilizer"
SoilPDAScreen.XML_FILENAME   = "xml/gui/SoilPDAScreen.xml"
SoilPDAScreen.MENU_ICON_PATH = "images/menuIcon.dds"

-- Capture mod directory at source-time (valid during loading only)
local SF_PDA_MOD_DIR = g_currentModDirectory
local SF_PDA_MOD_NAME = g_currentModName

-- Tabs
local TAB_MAP       = 1
local TAB_FIELDS    = 2
local TAB_TREATMENT = 3

-- How often to rebuild all data while PDA is open (ms)
local REFRESH_INTERVAL = 2000

-- Colors (soil green, amber, red)
local COLOR_GOOD  = {0.25, 0.85, 0.25, 1.0}
local COLOR_FAIR  = {0.90, 0.82, 0.18, 1.0}
local COLOR_POOR  = {0.88, 0.25, 0.25, 1.0}
local COLOR_DIM   = {0.65, 0.65, 0.65, 1.0}
local COLOR_GREEN = {0.35, 0.85, 0.40, 1.0}

-- Pressure threshold above which a field is flagged (0-100 scale)
local PRESSURE_THRESHOLD = 20

-- Module-level pending registration state
local _pendingRegistration = false
local _pendingModDir = nil

-- ── i18n helper ───────────────────────────────────────────

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[SF_PDA_MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local ok, text = pcall(function() return i18n:getText(key) end)
        if ok and text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

-- ── Constructor ───────────────────────────────────────────

function SoilPDAScreen.new()
    local self = SoilPDAScreen:superClass().new(nil, SoilPDAScreen._mt)

    self.name      = "SoilPDAScreen"
    self.className = "SoilPDAScreen"

    self.activeTab      = TAB_MAP
    self.fieldData      = {}    -- sorted list of {fieldId, info, urgency}
    self.treatmentData  = {}    -- subset: fields with urgency > 0, sorted desc
    self.selectedFieldIndex     = 0
    self.selectedTreatmentIndex = 0
    self.refreshTimer   = 0
    self.returnScreenName = ""
    self.menuButtonInfo   = {}
    
    self.lastPopupTime  = 0     -- Guard against multiple clicks/spam

    return self
end

-- ── initialize (called after registration) ───────────────

function SoilPDAScreen:initialize()
    SoilPDAScreen:superClass().initialize(self)
    -- Standard back button only — no custom footer buttons needed
    self:setMenuButtonInfo({
        {inputAction = "MENU_BACK"},
    })
end

-- ── Static registration ───────────────────────────────────

---@param modDir string
function SoilPDAScreen.register(modDir)
    if SoilPDAScreen._performRegistration(modDir) then
        return
    end
    _pendingRegistration = true
    _pendingModDir = modDir
    SoilLogger.info("SoilPDAScreen: deferred registration until InGameMenu ready")
end

---@return boolean true if successfully registered
function SoilPDAScreen._performRegistration(modDir)
    if g_gui == nil or g_inGameMenu == nil then return false end

    if g_inGameMenu[SoilPDAScreen.MENU_PAGE_NAME] ~= nil then
        SoilLogger.info("SoilPDAScreen: already registered, skipping")
        return true
    end

    local screen = SoilPDAScreen.new()
    local xmlPath = modDir .. SoilPDAScreen.XML_FILENAME

    SoilLogger.info("SoilPDAScreen: loading GUI from: " .. xmlPath)
    local ok, err = pcall(function()
        g_gui:loadGui(xmlPath, SoilPDAScreen.CLASS_NAME, screen, true)
    end)
    if not ok then
        SoilLogger.error("SoilPDAScreen: loadGui failed: " .. tostring(err))
        return false
    end

    -- Inject into InGameMenu pagingElement
    local inGameMenu = g_gui.screenControllers[InGameMenu] or g_inGameMenu

    if inGameMenu == nil or inGameMenu.pagingElement == nil then
        SoilLogger.error("SoilPDAScreen: inGameMenu or pagingElement nil after loadGui")
        return false
    end

    -- Clear any stale controlID to avoid conflicts
    if g_inGameMenu ~= nil and g_inGameMenu.controlIDs ~= nil then
        g_inGameMenu.controlIDs[SoilPDAScreen.MENU_PAGE_NAME] = nil
    end

    inGameMenu[SoilPDAScreen.MENU_PAGE_NAME] = screen

    -- Add to paging element (guard against duplicates)
    local alreadyAdded = false
    if inGameMenu.pagingElement.elements then
        for _, el in ipairs(inGameMenu.pagingElement.elements) do
            if el == screen then
                alreadyAdded = true
                break
            end
        end
    end
    if not alreadyAdded then
        inGameMenu.pagingElement:addElement(screen)
    end

    -- Expose controls as fields on the menu object
    if type(inGameMenu.exposeControlsAsFields) == "function" then
        pcall(inGameMenu.exposeControlsAsFields, inGameMenu, SoilPDAScreen.MENU_PAGE_NAME)
    end

    if type(inGameMenu.pagingElement.updateAbsolutePosition) == "function" then
        pcall(inGameMenu.pagingElement.updateAbsolutePosition, inGameMenu.pagingElement)
    end
    if type(inGameMenu.pagingElement.updatePageMapping) == "function" then
        pcall(inGameMenu.pagingElement.updatePageMapping, inGameMenu.pagingElement)
    end

    -- Register page with InGameMenu navigation
    if type(inGameMenu.registerPage) == "function" then
        pcall(inGameMenu.registerPage, inGameMenu, screen, nil, function() return true end)
    end

    -- Add tab icon to the InGameMenu tab bar
    local iconFile = Utils.getFilename(SoilPDAScreen.MENU_ICON_PATH, modDir)
    if iconFile and type(inGameMenu.addPageTab) == "function" then
        local okTab, errTab = pcall(inGameMenu.addPageTab, inGameMenu, screen, iconFile, GuiUtils.getUVs({0, 0, 1024, 1024}))
        if not okTab then
            SoilLogger.warning("SoilPDAScreen: addPageTab failed: " .. tostring(errTab))
        end
    end

    if type(inGameMenu.rebuildTabList) == "function" then
        pcall(inGameMenu.rebuildTabList, inGameMenu)
    end

    -- Call initialize to set up menu button info
    if type(screen.initialize) == "function" then
        pcall(screen.initialize, screen)
    end

    SoilLogger.info("SoilPDAScreen: registered successfully")
    return true
end

function SoilPDAScreen._attemptDeferredRegister(dt)
    if not _pendingRegistration then return end
    if SoilPDAScreen._performRegistration(_pendingModDir or SF_PDA_MOD_DIR) then
        _pendingRegistration = false
        _pendingModDir = nil
    end
end

-- ── Static show / toggle ─────────────────────────────────

function SoilPDAScreen.show()
    local inGameMenu = g_gui.screenControllers[InGameMenu] or g_inGameMenu
    if inGameMenu == nil then return end
    local page = inGameMenu[SoilPDAScreen.MENU_PAGE_NAME]
    if page == nil then return end
    g_gui:showGui("InGameMenu")
    inGameMenu:goToPage(page)
end

function SoilPDAScreen.toggle()
    if g_gui.currentGuiName == "InGameMenu" then
        local inGameMenu = g_gui.screenControllers[InGameMenu] or g_inGameMenu
        if inGameMenu and inGameMenu.currentPage == inGameMenu[SoilPDAScreen.MENU_PAGE_NAME] then
            g_gui:changeScreen(nil)
            return
        end
    end
    SoilPDAScreen.show()
end

-- ── Lifecycle ─────────────────────────────────────────────

function SoilPDAScreen:onGuiSetupFinished()
    SoilPDAScreen:superClass().onGuiSetupFinished(self)

    -- Left column stat elements
    self.statsFieldsTracked  = self:getDescendantById("statsFieldsTracked")
    self.statsFieldsOwned    = self:getDescendantById("statsFieldsOwned")
    self.statsAvgN           = self:getDescendantById("statsAvgN")
    self.statsAvgP           = self:getDescendantById("statsAvgP")
    self.statsAvgK           = self:getDescendantById("statsAvgK")
    self.statsAvgPH          = self:getDescendantById("statsAvgPH")
    self.statsAvgOM          = self:getDescendantById("statsAvgOM")
    self.statsWeedFields     = self:getDescendantById("statsWeedFields")
    self.statsPestFields     = self:getDescendantById("statsPestFields")
    self.statsDiseaseFields  = self:getDescendantById("statsDiseaseFields")
    self.statsNeedsAttention = self:getDescendantById("statsNeedsAttention")
    self.leftNoDataHint      = self:getDescendantById("leftNoDataHint")

    -- Right panel: content panels
    self.mapContent       = self:getDescendantById("mapContent")
    self.fieldsContent    = self:getDescendantById("fieldsContent")
    self.treatmentContent = self:getDescendantById("treatmentContent")

    -- Map tab elements
    self.mapLayerName     = self:getDescendantById("mapLayerName")
    self.mapLayerDesc     = self:getDescendantById("mapLayerDesc")
    self.mapLegendGroup   = self:getDescendantById("mapLegendGroup")
    self.mapLegendGoodBlock  = self:getDescendantById("mapLegendGoodBlock")
    self.mapLegendFairBlock  = self:getDescendantById("mapLegendFairBlock")
    self.mapLegendPoorBlock  = self:getDescendantById("mapLegendPoorBlock")
    self.mapLegendExcessBlock = self:getDescendantById("mapLegendExcessBlock")
    self.mapLegendGoodText   = self:getDescendantById("mapLegendGoodText")
    self.mapLegendFairText   = self:getDescendantById("mapLegendFairText")
    self.mapLegendPoorText   = self:getDescendantById("mapLegendPoorText")
    self.mapLegendExcessText = self:getDescendantById("mapLegendExcessText")
    self.mapInstructions  = self:getDescendantById("mapInstructions")
    self.btnOpenMap       = self:getDescendantById("btnOpenMap")

    -- Fields tab
    self.fieldList        = self:getDescendantById("fieldList")
    self.fieldsEmptyHint  = self:getDescendantById("fieldsEmptyHint")

    -- Treatment tab
    self.treatmentList    = self:getDescendantById("treatmentList")
    self.treatmentEmptyHint = self:getDescendantById("treatmentEmptyHint")

    -- Tab labels + underlines
    self.tabLabelMap        = self:getDescendantById("tabLabelMap")
    self.tabLabelFields     = self:getDescendantById("tabLabelFields")
    self.tabLabelTreatment  = self:getDescendantById("tabLabelTreatment")
    self.tabUnderlineMap       = self:getDescendantById("tabUnderlineMap")
    self.tabUnderlineFields    = self:getDescendantById("tabUnderlineFields")
    self.tabUnderlineTreatment = self:getDescendantById("tabUnderlineTreatment")

    -- Wire SmoothList data sources
    if self.fieldList then
        self.fieldList.dataSource = self
        self.fieldList.delegate   = self
    end
    if self.treatmentList then
        self.treatmentList.dataSource = self
        self.treatmentList.delegate   = self
    end

    -- Localize static text elements
    local function setText(el, key, fallback)
        if el == nil then return end
        local ok, err = pcall(el.setText, el, tr(key, fallback))
        if not ok then
            SoilLogger.warning("SoilPDAScreen:setText failed for " .. tostring(key) .. ": " .. tostring(err))
        end
    end
    setText(self.mapInstructions, "sf_pda_map_instructions",
        "Open the fullscreen map (ESC → Map) to see the live soil overlay. Press Shift+M to cycle through soil layers.")
end

function SoilPDAScreen:onOpen()
    SoilPDAScreen:superClass().onOpen(self)
    self:_rebuildAllData()
    self:_refreshSummaryStats()
    self:_refreshMapTab()
    self:_reloadLists()
    self:setActiveTab(self.activeTab)
end

function SoilPDAScreen:onClose()
    SoilPDAScreen:superClass().onClose(self)
end

function SoilPDAScreen:update(dt)
    SoilPDAScreen:superClass().update(self, dt)
    self.refreshTimer = self.refreshTimer + dt
    if self.refreshTimer >= REFRESH_INTERVAL then
        self.refreshTimer = 0
        self:_rebuildAllData()
        self:_refreshSummaryStats()
        if self.activeTab == TAB_MAP then
            self:_refreshMapTab()
        end
        self:_reloadLists()
    end
end

function SoilPDAScreen:delete()
    SoilPDAScreen:superClass().delete(self)
end

-- ── Input ─────────────────────────────────────────────────

function SoilPDAScreen:onClickBack()
    self:changeScreen(nil)
end

function SoilPDAScreen:inputEvent(action, value, eventUsed)
    if not eventUsed and value > 0 then
        if action == InputAction.MENU_PAGE_PREV then
            local newTab = self.activeTab - 1
            if newTab < TAB_MAP then newTab = TAB_TREATMENT end
            self:setActiveTab(newTab)
            return true
        end
        if action == InputAction.MENU_PAGE_NEXT then
            local newTab = self.activeTab + 1
            if newTab > TAB_TREATMENT then newTab = TAB_MAP end
            self:setActiveTab(newTab)
            return true
        end
    end
    return SoilPDAScreen:superClass().inputEvent(self, action, value, eventUsed)
end

-- ── Tab switching ─────────────────────────────────────────

function SoilPDAScreen:onClickTabMap()
    self:setActiveTab(TAB_MAP)
end

function SoilPDAScreen:onClickTabFields()
    self:setActiveTab(TAB_FIELDS)
end

function SoilPDAScreen:onClickTabTreatment()
    self:setActiveTab(TAB_TREATMENT)
end

-- Manual mouse-click fallback for tab labels (mirrors MDM pattern)
function SoilPDAScreen:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self:getIsVisible() or eventUsed then
        return SoilPDAScreen:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
    end

    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        local tabs = {
            { el = self.tabLabelMap,       cb = SoilPDAScreen.onClickTabMap       },
            { el = self.tabLabelFields,    cb = SoilPDAScreen.onClickTabFields    },
            { el = self.tabLabelTreatment, cb = SoilPDAScreen.onClickTabTreatment },
        }
        for _, t in ipairs(tabs) do
            if t.el and t.el:getIsVisible() then
                local ap = t.el.absPosition
                local as = t.el.absSize
                if ap and as and as[1] and as[2] and
                   posX >= ap[1] and posX <= ap[1] + as[1] and
                   posY >= ap[2] and posY <= ap[2] + as[2] then
                    t.cb(self)
                    return true
                end
            end
        end
    end
    return SoilPDAScreen:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

---@param tab number TAB_MAP | TAB_FIELDS | TAB_TREATMENT
function SoilPDAScreen:setActiveTab(tab)
    self.activeTab = tab

    -- Show/hide content panels
    if self.mapContent       then self.mapContent:setVisible(tab == TAB_MAP) end
    if self.fieldsContent    then self.fieldsContent:setVisible(tab == TAB_FIELDS) end
    if self.treatmentContent then self.treatmentContent:setVisible(tab == TAB_TREATMENT) end

    -- Trigger layout update on newly visible panels
    if tab == TAB_FIELDS and self.fieldsContent then
        if type(self.fieldsContent.updateAbsolutePosition) == "function" then
            self.fieldsContent:updateAbsolutePosition()
        end
        if self.fieldList then self.fieldList:reloadData() end
    elseif tab == TAB_TREATMENT and self.treatmentContent then
        if type(self.treatmentContent.updateAbsolutePosition) == "function" then
            self.treatmentContent:updateAbsolutePosition()
        end
        if self.treatmentList then self.treatmentList:reloadData() end
    elseif tab == TAB_MAP then
        self:_refreshMapTab()
    end

    -- Color active tab label green, inactive labels dim
    local function setTabColor(el, isActive)
        if not el then return end
        if isActive then
            el:setTextColor(0.35, 0.85, 0.40, 1.0)
        else
            el:setTextColor(1.0, 1.0, 1.0, 0.40)
        end
    end
    setTabColor(self.tabLabelMap,       tab == TAB_MAP)
    setTabColor(self.tabLabelFields,    tab == TAB_FIELDS)
    setTabColor(self.tabLabelTreatment, tab == TAB_TREATMENT)

    -- Underline active tab only
    if self.tabUnderlineMap       then self.tabUnderlineMap:setVisible(tab == TAB_MAP) end
    if self.tabUnderlineFields    then self.tabUnderlineFields:setVisible(tab == TAB_FIELDS) end
    if self.tabUnderlineTreatment then self.tabUnderlineTreatment:setVisible(tab == TAB_TREATMENT) end
end

-- ── Map Tab button ────────────────────────────────────────

function SoilPDAScreen:onClickOpenMap()
    -- Navigate to the InGameMenu Map page (where our SoilMapOverlay already renders)
    local inGameMenu = g_gui.screenControllers[InGameMenu] or g_inGameMenu
    if inGameMenu == nil then return end
    local mapPage = inGameMenu.pageMapOverview or inGameMenu["pageMapOverview"]
    if mapPage then
        inGameMenu:goToPage(mapPage)
    else
        -- Fallback: switch to the InGameMenu map frame by name
        if type(inGameMenu.showPage) == "function" then
            inGameMenu:showPage("pageMapOverview")
        end
    end
end

-- ── SmoothList Data Source ────────────────────────────────

function SoilPDAScreen:getNumberOfItemsInSection(list, section)
    if list == self.fieldList then
        return #self.fieldData
    elseif list == self.treatmentList then
        return #self.treatmentData
    end
    return 0
end

function SoilPDAScreen:populateCellForItemInSection(list, section, index, cell)
    -- Store index on cell for onClick handlers
    cell.rowDataIndex = index
    
    if list == self.fieldList then
        self:_populateFieldCell(index, cell)
    elseif list == self.treatmentList then
        self:_populateTreatmentCell(index, cell)
    end
end

-- ── SmoothList Delegate ───────────────────────────────────

function SoilPDAScreen:onListSelectionChanged(list, section, index)
    if list == self.fieldList and index > 0 then
        self.selectedFieldIndex = index
    elseif list == self.treatmentList and index > 0 then
        self.selectedTreatmentIndex = index
    end
end

-- ── Row Click Handlers ────────────────────────────────────

--- Called by ListItem.onClick in PDA Fields tab (XML)
function SoilPDAScreen:onClickFieldRow(element)
    -- Use stored index from population
    local index = element and element.rowDataIndex
    SoilLogger.info("SoilPDAScreen: onClickFieldRow index: %s", tostring(index))
    if index and index > 0 then
        self:_openFieldDetail(index)
    end
end

--- Called by ListItem.onClick in PDA Treatment tab (XML)
function SoilPDAScreen:onClickTreatmentRow(element)
    local index = element and element.rowDataIndex
    SoilLogger.info("SoilPDAScreen: onClickTreatmentRow index: %s", tostring(index))
    if index and index > 0 then
        self:_openTreatmentDetail(index)
    end
end

-- ── Detail Dialog ─────────────────────────────────────────

function SoilPDAScreen:_openFieldDetail(index)
    local entry = self.fieldData[index]
    SoilLogger.info("SoilPDAScreen: _openFieldDetail index=%s, fieldId=%s", tostring(index), tostring(entry and entry.fieldId))
    if not entry then return end
    if SoilFieldDetailDialog then
        SoilFieldDetailDialog.show(entry.fieldId)
    end
end

function SoilPDAScreen:_openTreatmentDetail(index)
    local entry = self.treatmentData[index]
    SoilLogger.info("SoilPDAScreen: _openTreatmentDetail index=%s, fieldId=%s", tostring(index), tostring(entry and entry.fieldId))
    if not entry then return end
    if SoilFieldDetailDialog then
        SoilFieldDetailDialog.show(entry.fieldId)
    end
end

-- ── Data Building ─────────────────────────────────────────

function SoilPDAScreen:_rebuildAllData()
    self:_buildFieldData()
    self:_buildTreatmentData()
end

function SoilPDAScreen:_buildFieldData()
    self.fieldData = {}

    local sfm = g_SoilFertilityManager
    if sfm == nil or sfm.soilSystem == nil then return end

    for fieldId, _ in pairs(sfm.soilSystem.fieldData) do
        local ok, info = pcall(function()
            return sfm.soilSystem:getFieldInfo(fieldId)
        end)
        if ok and info then
            local urgency = 0
            local urgOk, urgVal = pcall(function()
                return sfm.soilSystem:getFieldUrgency(fieldId)
            end)
            if urgOk then urgency = urgVal end

            table.insert(self.fieldData, {
                fieldId = fieldId,
                info    = info,
                urgency = urgency,
            })
        end
    end

    -- Sort by field ID ascending
    table.sort(self.fieldData, function(a, b) return a.fieldId < b.fieldId end)
end

function SoilPDAScreen:_buildTreatmentData()
    self.treatmentData = {}

    for _, entry in ipairs(self.fieldData) do
        -- Include fields that have any nutrient deficit OR pressure problem
        local info = entry.info
        local hasIssue = info.needsFertilization
            or (info.weedPressure    or 0) >= PRESSURE_THRESHOLD
            or (info.pestPressure    or 0) >= PRESSURE_THRESHOLD
            or (info.diseasePressure or 0) >= PRESSURE_THRESHOLD
        if hasIssue or entry.urgency > 0 then
            table.insert(self.treatmentData, entry)
        end
    end

    -- Sort by urgency descending (most urgent first)
    table.sort(self.treatmentData, function(a, b) return a.urgency > b.urgency end)
end

-- ── Summary Stats Refresh ─────────────────────────────────

function SoilPDAScreen:_refreshSummaryStats()
    local sfm = g_SoilFertilityManager
    local hasData = sfm ~= nil and sfm.soilSystem ~= nil
                    and next(sfm.soilSystem.fieldData) ~= nil

    if self.leftNoDataHint then
        self.leftNoDataHint:setVisible(not hasData)
    end

    if not hasData then
        local function setDash(el) if el then el:setText("--") end end
        setDash(self.statsFieldsTracked)
        setDash(self.statsFieldsOwned)
        setDash(self.statsAvgN)
        setDash(self.statsAvgP)
        setDash(self.statsAvgK)
        setDash(self.statsAvgPH)
        setDash(self.statsAvgOM)
        setDash(self.statsWeedFields)
        setDash(self.statsPestFields)
        setDash(self.statsDiseaseFields)
        setDash(self.statsNeedsAttention)
        return
    end

    local totalFields = #self.fieldData
    if self.statsFieldsTracked then
        self.statsFieldsTracked:setText(tostring(totalFields))
    end

    -- Count owned fields (local player's farm)
    local ownedCount = 0
    local farmId = g_localPlayer and g_localPlayer.farmId
    if farmId and farmId > 0 and g_farmlandManager then
        local farmlands = g_farmlandManager:getFarmlands()
        if farmlands then
            for _, farmland in pairs(farmlands) do
                local owner = g_farmlandManager:getFarmlandOwner(farmland.id)
                if owner == farmId then
                    ownedCount = ownedCount + 1
                end
            end
        end
    end
    if self.statsFieldsOwned then
        self.statsFieldsOwned:setText(tostring(ownedCount))
    end

    -- Compute averages
    local sumN, sumP, sumK, sumPH, sumOM = 0, 0, 0, 0, 0
    local weedCount, pestCount, diseaseCount, attentionCount = 0, 0, 0, 0
    local n = totalFields

    for _, entry in ipairs(self.fieldData) do
        local info = entry.info
        sumN  = sumN  + info.nitrogen.value
        sumP  = sumP  + info.phosphorus.value
        sumK  = sumK  + info.potassium.value
        sumPH = sumPH + (info.pH or 7.0)
        sumOM = sumOM + (info.organicMatter or 3.5)
        if (info.weedPressure    or 0) >= PRESSURE_THRESHOLD then weedCount    = weedCount    + 1 end
        if (info.pestPressure    or 0) >= PRESSURE_THRESHOLD then pestCount    = pestCount    + 1 end
        if (info.diseasePressure or 0) >= PRESSURE_THRESHOLD then diseaseCount = diseaseCount + 1 end
        if info.needsFertilization then attentionCount = attentionCount + 1 end
    end

    local avgN   = n > 0 and math.floor(sumN  / n) or 0
    local avgP   = n > 0 and math.floor(sumP  / n) or 0
    local avgK   = n > 0 and math.floor(sumK  / n) or 0
    local avgPH  = n > 0 and string.format("%.1f", sumPH / n) or "--"
    local avgOM  = n > 0 and string.format("%.1f", sumOM / n) or "--"

    -- Set text and color for nutrient averages
    local function setNutrientStat(el, value, threshPoor, threshFair)
        if not el then return end
        el:setText(tostring(value) .. "%")
        if value >= threshFair then
            el:setTextColor(unpack(COLOR_GOOD))
        elseif value >= threshPoor then
            el:setTextColor(unpack(COLOR_FAIR))
        else
            el:setTextColor(unpack(COLOR_POOR))
        end
    end

    local thresh = SoilConstants.STATUS_THRESHOLDS
    setNutrientStat(self.statsAvgN, avgN,
        thresh and thresh.nitrogen   and thresh.nitrogen.poor   or 30,
        thresh and thresh.nitrogen   and thresh.nitrogen.fair   or 50)
    setNutrientStat(self.statsAvgP, avgP,
        thresh and thresh.phosphorus and thresh.phosphorus.poor or 25,
        thresh and thresh.phosphorus and thresh.phosphorus.fair or 45)
    setNutrientStat(self.statsAvgK, avgK,
        thresh and thresh.potassium  and thresh.potassium.poor  or 20,
        thresh and thresh.potassium  and thresh.potassium.fair  or 40)

    if self.statsAvgPH  then self.statsAvgPH:setText(avgPH) end
    if self.statsAvgOM  then self.statsAvgOM:setText(avgOM) end

    -- Pressure and attention counts (red if > 0)
    local function setCountStat(el, count)
        if not el then return end
        el:setText(tostring(count))
        if count > 0 then
            el:setTextColor(unpack(COLOR_POOR))
        else
            el:setTextColor(unpack(COLOR_GOOD))
        end
    end

    setCountStat(self.statsWeedFields,     weedCount)
    setCountStat(self.statsPestFields,     pestCount)
    setCountStat(self.statsDiseaseFields,  diseaseCount)
    setCountStat(self.statsNeedsAttention, attentionCount)
end

-- ── Map Tab Refresh ───────────────────────────────────────

-- Descriptions per layer index
local MAP_LAYER_DESCS = {
    [0] = "sf_pda_map_layer_off_desc",
    [1] = "sf_pda_map_layer_n_desc",
    [2] = "sf_pda_map_layer_p_desc",
    [3] = "sf_pda_map_layer_k_desc",
    [4] = "sf_pda_map_layer_ph_desc",
    [5] = "sf_pda_map_layer_om_desc",
    [6] = "sf_pda_map_layer_urgency_desc",
    [7] = "sf_pda_map_layer_weed_desc",
    [8] = "sf_pda_map_layer_pest_desc",
    [9] = "sf_pda_map_layer_disease_desc",
}

-- Fallback descriptions (English hardcoded, used when l10n key missing)
local MAP_LAYER_DESC_FALLBACKS = {
    [0] = "Soil map overlay is currently off. Press Shift+M to activate a layer.",
    [1] = "Nitrogen (N): Primary growth driver. Shows per-field N availability.",
    [2] = "Phosphorus (P): Root development and flowering. Shows per-field P availability.",
    [3] = "Potassium (K): Disease resistance and water regulation. Shows per-field K availability.",
    [4] = "pH Level: Soil acidity/alkalinity. Optimal range 6.5–7.0. Apply lime to raise pH.",
    [5] = "Organic Matter: Improves soil structure and nutrient retention. Plow to increase OM.",
    [6] = "Field Urgency: Combined score of all deficits. High = immediate treatment needed.",
    [7] = "Weed Pressure: Active weed infestation level. Apply herbicide to reduce.",
    [8] = "Pest Pressure: Insect pest population. Apply insecticide to reduce.",
    [9] = "Disease Pressure: Fungal/bacterial disease level. Apply fungicide to reduce.",
}

-- Color themes per layer (Good, Fair, Poor, Excess descriptors)
-- Inverted layers (Urgency, Weed, Pest, Disease): high = bad
local INVERTED_LAYERS = {[6]=true, [7]=true, [8]=true, [9]=true}

function SoilPDAScreen:_refreshMapTab()
    local sfm = g_SoilFertilityManager
    local layerIdx = 0
    if sfm and sfm.soilMapOverlay and sfm.settings then
        layerIdx = sfm.settings.activeMapLayer or 0
    end

    -- Active layer name
    local layerKeys = SoilMapOverlay and SoilMapOverlay.LAYER_KEYS or {}
    local layerKey = layerKeys[layerIdx] or "sf_map_layer_off"
    local layerName = tr(layerKey, "Layer " .. layerIdx)
    if self.mapLayerName then
        self.mapLayerName:setText(layerName)
        if layerIdx > 0 then
            self.mapLayerName:setTextColor(unpack(COLOR_GREEN))
        else
            self.mapLayerName:setTextColor(0.60, 0.60, 0.60, 1.0)
        end
    end

    -- Layer description
    local descKey = MAP_LAYER_DESCS[layerIdx]
    local descFallback = MAP_LAYER_DESC_FALLBACKS[layerIdx] or ""
    local descText = descKey and tr(descKey, descFallback) or descFallback
    if self.mapLayerDesc then
        self.mapLayerDesc:setText(descText)
    end

    -- Legend (only when a layer is active)
    local showLegend = layerIdx > 0
    if self.mapLegendGroup then
        self.mapLegendGroup:setVisible(showLegend)
    end

    if showLegend then
        local isInverted = INVERTED_LAYERS[layerIdx]

        -- For inverted layers: Good = low, Poor = high
        -- For normal layers: Good = high, Poor = low
        local goodColor, fairColor, poorColor
        if isInverted then
            goodColor = COLOR_GOOD   -- low value = good (green)
            fairColor = COLOR_FAIR   -- mid = fair (amber)
            poorColor = COLOR_POOR   -- high = bad (red)
        else
            goodColor = COLOR_GOOD   -- high value = good (green)
            fairColor = COLOR_FAIR
            poorColor = COLOR_POOR
        end

        -- Set legend block background-ish using text color on solid block character
        local function setBlock(el, color)
            if not el then return end
            el:setTextColor(color[1], color[2], color[3], color[4])
        end

        setBlock(self.mapLegendGoodBlock,  goodColor)
        setBlock(self.mapLegendFairBlock,  fairColor)
        setBlock(self.mapLegendPoorBlock,  poorColor)

        -- Legend labels
        local function setLegendLabel(el, key, fallback)
            if el then el:setText(tr(key, fallback)) end
        end

        if isInverted then
            setLegendLabel(self.mapLegendGoodText,  "sf_pda_map_legend_low",    "Low (Good)")
            setLegendLabel(self.mapLegendFairText,  "sf_pda_map_legend_medium", "Medium")
            setLegendLabel(self.mapLegendPoorText,  "sf_pda_map_legend_high",   "High (Bad)")
        else
            setLegendLabel(self.mapLegendGoodText,  "sf_pda_map_legend_good",   "Good (High)")
            setLegendLabel(self.mapLegendFairText,  "sf_pda_map_legend_fair",   "Fair (Medium)")
            setLegendLabel(self.mapLegendPoorText,  "sf_pda_map_legend_poor",   "Poor (Low)")
        end

        -- Excess block (for pH: too alkaline is also bad)
        if layerIdx == 4 then  -- pH layer
            if self.mapLegendExcessBlock  then
                self.mapLegendExcessBlock:setTextColor(unpack(COLOR_POOR))
            end
            if self.mapLegendExcessText then
                self.mapLegendExcessText:setText(tr("sf_pda_map_legend_excess", "High pH (Alkaline)"))
                self.mapLegendExcessText:setVisible(true)
            end
            if self.mapLegendExcessBlock then
                self.mapLegendExcessBlock:setVisible(true)
            end
        else
            if self.mapLegendExcessText   then self.mapLegendExcessText:setVisible(false) end
            if self.mapLegendExcessBlock  then self.mapLegendExcessBlock:setVisible(false) end
        end
    end
end

-- ── List reload ───────────────────────────────────────────

function SoilPDAScreen:_reloadLists()
    if self.fieldList    then self.fieldList:reloadData() end
    if self.treatmentList then self.treatmentList:reloadData() end

    -- Toggle empty hints
    if self.fieldsEmptyHint then
        self.fieldsEmptyHint:setVisible(#self.fieldData == 0)
    end
    if self.treatmentEmptyHint then
        self.treatmentEmptyHint:setVisible(#self.treatmentData == 0)
    end
end

-- ── Cell population: Fields list ─────────────────────────

function SoilPDAScreen:_populateFieldCell(index, cell)
    local entry = self.fieldData[index]
    if not entry then return end

    local info = entry.info

    local idEl     = cell:getDescendantByName("fieldRowId")
    local nEl      = cell:getDescendantByName("fieldRowN")
    local pEl      = cell:getDescendantByName("fieldRowP")
    local kEl      = cell:getDescendantByName("fieldRowK")
    local phEl     = cell:getDescendantByName("fieldRowPH")
    local omEl     = cell:getDescendantByName("fieldRowOM")
    local statusEl = cell:getDescendantByName("fieldRowStatus")

    if idEl then idEl:setText(tostring(entry.fieldId)) end

    local function setNutrient(el, value, statusStr)
        if not el then return end
        el:setText(tostring(value))
        if statusStr == "good" then
            el:setTextColor(unpack(COLOR_GOOD))
        elseif statusStr == "fair" then
            el:setTextColor(unpack(COLOR_FAIR))
        else
            el:setTextColor(unpack(COLOR_POOR))
        end
    end

    setNutrient(nEl, info.nitrogen.value,    info.nitrogen.status)
    setNutrient(pEl, info.phosphorus.value,  info.phosphorus.status)
    setNutrient(kEl, info.potassium.value,   info.potassium.status)

    -- pH
    if phEl then
        local phVal = string.format("%.1f", info.pH or 7.0)
        phEl:setText(phVal)
        local ph = info.pH or 7.0
        if ph >= 6.5 and ph <= 7.0 then
            phEl:setTextColor(unpack(COLOR_GOOD))
        elseif ph >= 6.0 and ph < 7.5 then
            phEl:setTextColor(unpack(COLOR_FAIR))
        else
            phEl:setTextColor(unpack(COLOR_POOR))
        end
    end

    -- OM
    if omEl then
        local omVal = string.format("%.1f", info.organicMatter or 3.5)
        omEl:setText(omVal)
        local om = info.organicMatter or 3.5
        if om >= 4.0 then
            omEl:setTextColor(unpack(COLOR_GOOD))
        elseif om >= 2.5 then
            omEl:setTextColor(unpack(COLOR_FAIR))
        else
            omEl:setTextColor(unpack(COLOR_POOR))
        end
    end

    -- Overall status
    if statusEl then
        if entry.urgency >= 60 then
            statusEl:setText(tr("sf_pda_status_poor", "Poor"))
            statusEl:setTextColor(unpack(COLOR_POOR))
        elseif entry.urgency >= 25 then
            statusEl:setText(tr("sf_pda_status_fair", "Fair"))
            statusEl:setTextColor(unpack(COLOR_FAIR))
        else
            statusEl:setText(tr("sf_pda_status_good", "Good"))
            statusEl:setTextColor(unpack(COLOR_GOOD))
        end
    end
end

-- ── Cell population: Treatment list ──────────────────────

-- Returns a comma-separated string of what the field needs
local function buildNeedsString(info)
    local needs = {}
    local thresh = SoilConstants.STATUS_THRESHOLDS

    local nThreshPoor  = thresh and thresh.nitrogen   and thresh.nitrogen.poor   or 30
    local pThreshPoor  = thresh and thresh.phosphorus and thresh.phosphorus.poor or 25
    local kThreshPoor  = thresh and thresh.potassium  and thresh.potassium.poor  or 20

    if info.nitrogen.value   < nThreshPoor then
        table.insert(needs, tr("sf_pda_need_n", "Nitrogen"))
    end
    if info.phosphorus.value < pThreshPoor then
        table.insert(needs, tr("sf_pda_need_p", "Phosphorus"))
    end
    if info.potassium.value  < kThreshPoor then
        table.insert(needs, tr("sf_pda_need_k", "Potassium"))
    end
    if (info.pH or 7.0) < 6.0 then
        table.insert(needs, tr("sf_pda_need_ph", "Lime (pH)"))
    end
    if (info.weedPressure    or 0) >= PRESSURE_THRESHOLD then
        table.insert(needs, tr("sf_pda_need_weed", "Herbicide"))
    end
    if (info.pestPressure    or 0) >= PRESSURE_THRESHOLD then
        table.insert(needs, tr("sf_pda_need_pest", "Insecticide"))
    end
    if (info.diseasePressure or 0) >= PRESSURE_THRESHOLD then
        table.insert(needs, tr("sf_pda_need_disease", "Fungicide"))
    end

    if #needs == 0 then
        return tr("sf_pda_treatment_minor", "Minor deficit")
    elseif #needs > 3 then
        return tr("sf_pda_need_multiple", "Multiple treatments")
    else
        return table.concat(needs, ", ")
    end
end

function SoilPDAScreen:_populateTreatmentCell(index, cell)
    local entry = self.treatmentData[index]
    if not entry then return end

    local idEl      = cell:getDescendantByName("treatRowId")
    local urgencyEl = cell:getDescendantByName("treatRowUrgency")
    local needsEl   = cell:getDescendantByName("treatRowNeeds")

    if idEl then idEl:setText(tostring(entry.fieldId)) end

    if urgencyEl then
        local urgency = math.floor(entry.urgency)
        urgencyEl:setText(urgency .. "%")
        if urgency >= 60 then
            urgencyEl:setTextColor(unpack(COLOR_POOR))
        elseif urgency >= 25 then
            urgencyEl:setTextColor(unpack(COLOR_FAIR))
        else
            urgencyEl:setTextColor(unpack(COLOR_DIM))
        end
    end

    if needsEl then
        needsEl:setText(buildNeedsString(entry.info))
    end
end

-- ── Module-level lifecycle hooks (installed at source-time) ──

local function _onMissionLoaded(mission)
    SoilPDAScreen.register(SF_PDA_MOD_DIR)
end

local function _onUpdate(mission, dt)
    SoilPDAScreen._attemptDeferredRegister(dt)
end

local function _onDelete(mission)
    -- Nothing to clean up — g_inGameMenu owns the page reference
end

-- Register a keyboard shortcut (SF_SOIL_PDA → Shift+P) for quick PDA toggle
local function _registerToggleAction(mission)
    if not InputAction or not InputAction.SF_SOIL_PDA then return end
    local ok, eventId = pcall(function()
        return g_inputBinding:registerActionEvent(
            InputAction.SF_SOIL_PDA, nil, SoilPDAScreen.toggle,
            false, true, false, true
        )
    end)
    if ok and eventId then
        pcall(g_inputBinding.setActionEventTextVisibility, g_inputBinding, eventId, false)
        SoilLogger.info("SoilPDAScreen: SF_SOIL_PDA toggle registered")
    end
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, _onMissionLoaded)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, _registerToggleAction)
FSBaseMission.update            = Utils.appendedFunction(FSBaseMission.update,            _onUpdate)
FSBaseMission.delete            = Utils.appendedFunction(FSBaseMission.delete,            _onDelete)
