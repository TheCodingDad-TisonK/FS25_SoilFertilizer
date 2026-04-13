-- =========================================================
-- FS25 Soil & Fertilizer — PDA Screen
-- =========================================================
-- Registers a dedicated page in the InGameMenu (PDA) with
-- three tabs: Farm Overview, Soil Map, Treatment Plan.
-- Left sidebar is context-sensitive per tab:
--   Overview  → full field list (N/P/K/pH/OM/Status)
--   Soil Map  → simple jump list (click to center mini-map)
--   Treatment → summary stats + hint
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

SoilPDAScreen.CONTROLS = {
    "statsFieldsTracked", "statsFieldsOwned",
    "statsAvgN", "statsAvgP", "statsAvgK", "statsAvgPH", "statsAvgOM",
    "statsWeedFields", "statsPestFields", "statsDiseaseFields",
    "statsNeedsAttention",
    "mapLayerName", "mapLayerDesc", "mapLegendGroup",
    "mapLegendGoodBlock", "mapLegendGoodText",
    "mapLegendFairBlock", "mapLegendFairText",
    "mapLegendPoorBlock", "mapLegendPoorText",
    "mapLegendExcessBlock", "mapLegendExcessText",
    "soilMiniMap", "sidebarFieldList", "sidebarMapList", "treatmentList",
    "sidebarOverview", "sidebarMap", "sidebarTreatment",
    "overviewContent", "mapContent", "treatmentContent",
    "tabLabelOverview", "tabLabelMap", "tabLabelTreatment",
    "tabUnderlineOverview", "tabUnderlineMap", "tabUnderlineTreatment",
    "treatStatNeedsFert", "treatStatWeed", "treatStatPest",
    "treatStatDisease", "treatStatTotal", "treatHintText",
    "treatmentEmptyHint", "leftNoDataHint"
}

-- Tabs (3 tabs: Fields tab removed, sidebar is now context-sensitive)
local TAB_OVERVIEW  = 1
local TAB_MAP       = 2
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

    self.activeTab      = TAB_OVERVIEW
    self.fieldData      = {}    -- sorted list of {fieldId, info, urgency}
    self.treatmentData  = {}    -- subset: fields with urgency > 0, sorted desc
    self.selectedFieldIndex     = 0
    self.selectedTreatmentIndex = 0
    self.refreshTimer   = 0
    self.returnScreenName = ""
    self.menuButtonInfo   = {}
    self.sidebarMapList   = nil  -- simple jump list on Map tab

    self.lastPopupTime  = 0     -- Guard against multiple clicks/spam
    self.filterOwnedOnly = false -- Filter: All Fields vs Owned Only
    self.isMapLocked     = false -- Lock zoom/pan when field selected

    return self
end

-- ── initialize (called after registration) ───────────────

function SoilPDAScreen:initialize()
    SoilPDAScreen:superClass().initialize(self)

    self.menuButtonInfo = {
        {inputAction = "MENU_BACK"},
        {inputAction = "MENU_ACCEPT", text = tr("sf_pda_filter_all", "Filter"), callback = function() self:onClickFilter() end},
        {inputAction = InputAction.SF_CYCLE_MAP_LAYER, text = tr("input_SF_CYCLE_MAP_LAYER", "Cycle Map Layer"), callback = function() self:onCycleLayerInput() end},
        {inputAction = "MENU_EXTRA_1", text = tr("sf_pda_btn_help", "Dev Note"), callback = function() self:onClickHelp() end},
    }
    self:setMenuButtonInfo(self.menuButtonInfo)
end

function SoilPDAScreen:onCycleLayerInput()
    if g_SoilFertilityManager then
        g_SoilFertilityManager:onCycleMapLayerInput()
        if self.activeTab == TAB_MAP then
            self:_refreshMapTab()
        end
    end
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

    -- Overview stats
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

    -- Right panel: content panels (3 tabs)
    self.overviewContent  = self:getDescendantById("overviewContent")
    self.mapContent       = self:getDescendantById("mapContent")
    self.treatmentContent = self:getDescendantById("treatmentContent")

    -- Map tab elements
    self.mapLayerName        = self:getDescendantById("mapLayerName")
    self.mapLayerDesc        = self:getDescendantById("mapLayerDesc")
    self.mapLegendGroup      = self:getDescendantById("mapLegendGroup")
    self.mapLegendGoodBlock  = self:getDescendantById("mapLegendGoodBlock")
    self.mapLegendFairBlock  = self:getDescendantById("mapLegendFairBlock")
    self.mapLegendPoorBlock  = self:getDescendantById("mapLegendPoorBlock")
    self.mapLegendExcessBlock= self:getDescendantById("mapLegendExcessBlock")
    self.mapLegendGoodText   = self:getDescendantById("mapLegendGoodText")
    self.mapLegendFairText   = self:getDescendantById("mapLegendFairText")
    self.mapLegendPoorText   = self:getDescendantById("mapLegendPoorText")
    self.mapLegendExcessText = self:getDescendantById("mapLegendExcessText")
    self.soilMiniMap         = self:getDescendantById("soilMiniMap")

    -- Left sidebar panels
    self.sidebarOverview   = self:getDescendantById("sidebarOverview")
    self.sidebarMap        = self:getDescendantById("sidebarMap")
    self.sidebarTreatment  = self:getDescendantById("sidebarTreatment")

    -- Sidebar A: full field list (Overview tab)
    self.sidebarFieldList = self:getDescendantById("sidebarFieldList")

    -- Sidebar B: simple jump list (Map tab)
    self.sidebarMapList   = self:getDescendantById("sidebarMapList")

    -- Sidebar C: treatment summary stats
    self.treatStatNeedsFert = self:getDescendantById("treatStatNeedsFert")
    self.treatStatWeed      = self:getDescendantById("treatStatWeed")
    self.treatStatPest      = self:getDescendantById("treatStatPest")
    self.treatStatDisease   = self:getDescendantById("treatStatDisease")
    self.treatStatTotal     = self:getDescendantById("treatStatTotal")
    self.treatHintText      = self:getDescendantById("treatHintText")

    -- Treatment tab
    self.treatmentList      = self:getDescendantById("treatmentList")
    self.treatmentEmptyHint = self:getDescendantById("treatmentEmptyHint")

    -- Tab labels + underlines (3 tabs)
    self.tabLabelOverview      = self:getDescendantById("tabLabelOverview")
    self.tabLabelMap           = self:getDescendantById("tabLabelMap")
    self.tabLabelTreatment     = self:getDescendantById("tabLabelTreatment")
    self.tabUnderlineOverview  = self:getDescendantById("tabUnderlineOverview")
    self.tabUnderlineMap       = self:getDescendantById("tabUnderlineMap")
    self.tabUnderlineTreatment = self:getDescendantById("tabUnderlineTreatment")

    -- Wire SmoothList data sources
    if self.sidebarFieldList then
        self.sidebarFieldList.dataSource = self
        self.sidebarFieldList.delegate   = self
    end
    if self.sidebarMapList then
        self.sidebarMapList.dataSource = self
        self.sidebarMapList.delegate   = self
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
end

function SoilPDAScreen:onOpen()
    SoilPDAScreen:superClass().onOpen(self)

    -- Initialize interactive map state
    self.mapZoom = 3.5
    local px, pz = 0, 0
    if g_localPlayer and g_localPlayer.rootNode then
        local ok, x, y, z = pcall(getWorldTranslation, g_localPlayer.rootNode)
        if ok and x then px, pz = x, z end
    end
    self.mapCenterX = px
    self.mapCenterZ = pz
    self.isMapDragging = false
    self.lastMouseX = 0
    self.lastMouseY = 0

    self:_rebuildAllData()
    self:_refreshSummaryStats()
    self:_refreshTreatmentSidebar()
    self:_updateFilterButtonText()
    self:_reloadLists()
    -- setActiveTab handles _refreshMapTab + _showMiniMap — do NOT call them separately here
    self:setActiveTab(self.activeTab)
end

function SoilPDAScreen:onClose()
    SoilPDAScreen:superClass().onClose(self)
    self:_hideMiniMap()
end

-- Show the mini-map: call setIngameMap then make it visible.
-- IngameMapPreviewElement.draw() crashes if called while visible=true
-- but before setIngameMap has run (internal C++ map object is nil).
-- We keep visible=false in the XML and only flip to true here.
function SoilPDAScreen:_showMiniMap()
    if not self.soilMiniMap then return end

    -- Wire the internal IngameMap C++ object -- must happen before setVisible(true)
    local ingameMap = g_currentMission and g_currentMission.hud and g_currentMission.hud:getIngameMap()
    if not ingameMap then
        SoilLogger.warning("SoilPDAScreen:_showMiniMap: getIngameMap() returned nil, minimap unavailable")
        return
    end
    self.soilMiniMap:setIngameMap(ingameMap)
    self.soilMiniMap:setCenterToWorldPosition(self.mapCenterX or 0, self.mapCenterZ or 0)
    self.soilMiniMap:setMapZoom(self.mapZoom or 3.5)
    self.soilMiniMap:setMapAlpha(1)
    
    -- Suppress hotspots (vehicles, sell points, etc) from drawing on our clean mini-map
    -- but keep Field Numbers and the Player Marker!
    if not self.soilMiniMap._drawHooked then
        local oldDraw = self.soilMiniMap.draw
        self.soilMiniMap.draw = function(mapSelf, clipX1, clipY1, clipX2, clipY2)
            local im = mapSelf.ingameMap
            if im and type(im.filter) == "table" then
                -- Backup the global map filter and disable everything
                local origFilter = {}
                for k, v in pairs(im.filter) do
                    origFilter[k] = v
                    im.filter[k] = false
                end
                
                -- Re-enable only the Field numbers and Player marker
                if MapHotspot then
                    if MapHotspot.CATEGORY_FIELD   ~= nil then im.filter[MapHotspot.CATEGORY_FIELD]   = true end
                    if MapHotspot.CATEGORY_PLAYER  ~= nil then im.filter[MapHotspot.CATEGORY_PLAYER]  = true end
                    if MapHotspot.CATEGORY_DEFAULT ~= nil then im.filter[MapHotspot.CATEGORY_DEFAULT] = true end
                end
                
                local ok, err = pcall(oldDraw, mapSelf, clipX1, clipY1, clipX2, clipY2)
                
                -- Restore the exact original filter state immediately
                for k, v in pairs(origFilter) do
                    im.filter[k] = v
                end
                
                if not ok then error(err) end
                
                -- After drawing map and hotspots, render our density overlay if a layer is active
                local overlay = g_SoilFertilityManager and g_SoilFertilityManager.soilMapOverlay
                if overlay and overlay.overlayHandle and overlay.overlayHandle ~= 0 then
                    -- Poll async generation readiness if it's currently generating
                    if overlay.isGenerating then
                        if getIsDensityMapVisualizationOverlayReady and getIsDensityMapVisualizationOverlayReady(overlay.overlayHandle) then
                            overlay.isReady = true
                            overlay.isGenerating = false
                            if overlay.pendingRegen then overlay:requestGenerate() end
                        end
                    end

                    if overlay.isReady then
                        local layerIdx = overlay.settings.activeMapLayer or 0
                        if layerIdx > 0 then
                            -- Use the absolute screen position/size of our GUI element (normalized 0-1)
                            local mapX, mapY = mapSelf.absPosition[1], mapSelf.absPosition[2]
                            local mapW, mapH = mapSelf.size[1], mapSelf.size[2]
                            
                            -- Aspect Ratio Fix: The GUI element box is 960x340 (wide), but the map is square.
                            -- Giants letterboxes the map to fit the SHORTEST side.
                            local renderW, renderH = mapW, mapH
                            local renderX, renderY = mapX, mapY
                            
                            if mapW > mapH then
                                -- Box is wider than it is tall: map is a square of height, centered horizontally
                                renderW = mapH
                                renderX = mapX + (mapW - mapH) * 0.5
                            elseif mapH > mapW then
                                -- Box is taller than it is wide: map is a square of width, centered vertically
                                renderH = mapW
                                renderY = mapY + (mapH - mapW) * 0.5
                            end

                            if self._lastRenderedLayer ~= layerIdx then
                                SoilLogger.debug("SoilPDAScreen: Rendering layer %d inside mini-map (%.3f, %.3f, %.3f, %.3f)", layerIdx, renderX, renderY, renderW, renderH)
                                self._lastRenderedLayer = layerIdx
                            end

                            -- Alignment Fix: Sync UVs with the actual background map's zoom/pan
                            local uvs = nil
                            if im.mapOverlay and im.mapOverlay.uvs then
                                uvs = im.mapOverlay.uvs
                            end

                            -- Fallback to manual UV calculation ONLY if internal UVs are missing
                            if not uvs then
                                local worldSize = (g_currentMission and g_currentMission.terrainSize) or 2048
                                local zoom = self.mapZoom or 3.5
                                local cx, cz = self.mapCenterX or 0, self.mapCenterZ or 0
                                local uCenter = (cx + worldSize * 0.5) / worldSize
                                local vCenter = (worldSize * 0.5 - cz) / worldSize
                                local halfUV = 0.5 / zoom
                                uvs = {uCenter - halfUV, vCenter - halfUV,  -- BL
                                       uCenter - halfUV, vCenter + halfUV,  -- TL
                                       uCenter + halfUV, vCenter - halfUV,  -- BR
                                       uCenter + halfUV, vCenter + halfUV}  -- TR
                            end

                            if uvs and setOverlayUVs then
                                setOverlayUVs(overlay.overlayHandle, unpack(uvs))
                            end

                            if setOverlayColor then setOverlayColor(overlay.overlayHandle, 1, 1, 1, SoilMapOverlay.ALPHA) end
                            if renderOverlay then
                                renderOverlay(overlay.overlayHandle, renderX, renderY, renderW, renderH)
                            end
                        end
                    end
                end
            else
                oldDraw(mapSelf, clipX1, clipY1, clipX2, clipY2)
            end
        end
        self.soilMiniMap._drawHooked = true
    end

    -- We called onClose() in _hideMiniMap, so we must call onOpen() here to restore layout state
    if type(self.soilMiniMap.onOpen) == "function" then
        self.soilMiniMap:onOpen()
    end
    
    self.soilMiniMap:setVisible(true)
end

-- Tear down the mini-map: call onClose then hide it.
-- This mirrors AFMGuiVehicleFrame:onFrameClose which calls itemDetailsMap:onClose().
function SoilPDAScreen:_hideMiniMap()
    if not self.soilMiniMap then return end
    -- Prevent Giants Engine crash: IngameMapPreviewElement:onClose() assumes self.ingameMap is not nil.
    if self.soilMiniMap.ingameMap ~= nil then
        self.soilMiniMap:onClose()
    end
    self.soilMiniMap:setVisible(false)
end

function SoilPDAScreen:update(dt)
    SoilPDAScreen:superClass().update(self, dt)
    self.refreshTimer = self.refreshTimer + dt
    if self.refreshTimer >= REFRESH_INTERVAL then
        self.refreshTimer = 0
        self:_rebuildAllData()
        self:_refreshSummaryStats()
        self:_refreshTreatmentSidebar()
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
            if newTab < TAB_OVERVIEW then newTab = TAB_TREATMENT end
            self:setActiveTab(newTab)
            return true
        end
        if action == InputAction.MENU_PAGE_NEXT then
            local newTab = self.activeTab + 1
            if newTab > TAB_TREATMENT then newTab = TAB_OVERVIEW end
            self:setActiveTab(newTab)
            return true
        end
    end
    return SoilPDAScreen:superClass().inputEvent(self, action, value, eventUsed)
end

-- ── Tab switching ─────────────────────────────────────────

function SoilPDAScreen:onClickTabOverview()
    self:setActiveTab(TAB_OVERVIEW)
end

function SoilPDAScreen:onClickTabMap()
    self:setActiveTab(TAB_MAP)
end

function SoilPDAScreen:onClickTabTreatment()
    self:setActiveTab(TAB_TREATMENT)
end

-- Manual mouse-click fallback for tab labels (mirrors MDM pattern)
function SoilPDAScreen:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self:getIsVisible() or eventUsed then
        return SoilPDAScreen:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
    end

    local overMap = false
    if self.soilMiniMap and self.soilMiniMap:getIsVisible() then
        local mp = self.soilMiniMap.absPosition
        local ms = self.soilMiniMap.absSize
        if posX >= mp[1] and posX <= mp[1] + ms[1] and posY >= mp[2] and posY <= mp[2] + ms[2] then
            overMap = true
        end
    end

    -- Scroll Wheel Zoom
    if overMap and not self.isMapLocked then
        local zoomDelta = 0
        if button == Input.MOUSE_BUTTON_WHEEL_UP then zoomDelta = 0.5
        elseif button == Input.MOUSE_BUTTON_WHEEL_DOWN then zoomDelta = -0.5 end

        if zoomDelta ~= 0 then
            local currentZoom = self.mapZoom or 3.5
            self.mapZoom = math.clamp(currentZoom + zoomDelta, 1.0, 15.0)
            SoilLogger.debug("SoilPDAScreen: zoom changed to %f", self.mapZoom)

            -- Recalculate allowed center bounds for the new zoom level immediately
            local worldSize = (g_currentMission and g_currentMission.terrainSize) or 2048
            local halfWorld = worldSize * 0.5
            local halfView = halfWorld / self.mapZoom
            local maxCenter = math.max(0, halfWorld - halfView)

            self.mapCenterX = math.clamp(self.mapCenterX or 0, -maxCenter, maxCenter)
            self.mapCenterZ = math.clamp(self.mapCenterZ or 0, -maxCenter, maxCenter)

            if self.soilMiniMap then
                pcall(function()
                    self.soilMiniMap:setMapZoom(self.mapZoom)
                    self.soilMiniMap:setCenterToWorldPosition(self.mapCenterX, self.mapCenterZ)
                end)
            end
            return true
        end
    end

    -- Left Click Drag (Pan)
    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        if overMap then
            if self.isMapLocked then
                self.isMapLocked = false
                SoilLogger.info("SoilPDAScreen: Map unlocked via click")
                return true
            else
                self.isMapDragging = true
                self.lastMouseX = posX
                self.lastMouseY = posY
            end
        end
        local tabs = {
            { el = self.tabLabelOverview,  cb = SoilPDAScreen.onClickTabOverview  },
            { el = self.tabLabelMap,       cb = SoilPDAScreen.onClickTabMap       },
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

    -- Panning Logic (Movement Delta)
    if self.isMapDragging then
        if isUp and button == Input.MOUSE_BUTTON_LEFT then
            self.isMapDragging = false
        else
            -- REVERT INVERSION: posX - lastMouseX (moves with mouse)
            local dx = posX - self.lastMouseX
            local dy = posY - self.lastMouseY

            if dx ~= 0 or dy ~= 0 then
                local worldSize = (g_currentMission and g_currentMission.terrainSize) or 2048
                local mapSize = (self.soilMiniMap and self.soilMiniMap.absSize and self.soilMiniMap.absSize[1]) or 0
                local zoom = self.mapZoom or 1.0
                
                if mapSize > 0 and zoom > 0 then
                    -- World delta = (Pixel delta / Map Screen Size) * (Full World Size / Zoom)
                    local worldDX = (dx / mapSize) * (worldSize / zoom)
                    local worldDZ = (dy / mapSize) * (worldSize / zoom)
                    
                    -- CRITICAL FIX: Zoom-Aware Clamping
                    local halfWorld = worldSize * 0.5
                    local halfView = halfWorld / zoom
                    local maxCenter = math.max(0, halfWorld - halfView)
                    
                    self.mapCenterX = math.clamp((self.mapCenterX or 0) + worldDX, -maxCenter, maxCenter)
                    self.mapCenterZ = math.clamp((self.mapCenterZ or 0) + worldDZ, -maxCenter, maxCenter)
                    
                    if self.soilMiniMap then
                        pcall(function()
                            self.soilMiniMap:setCenterToWorldPosition(self.mapCenterX, self.mapCenterZ)
                        end)
                    end
                end
                
                self.lastMouseX = posX
                self.lastMouseY = posY
                return true
            end
        end
    end

    return SoilPDAScreen:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

---@param tab number TAB_OVERVIEW | TAB_MAP | TAB_TREATMENT
function SoilPDAScreen:setActiveTab(tab)
    self.activeTab = tab

    -- Show/hide content panels (Right side)
    if self.overviewContent  then self.overviewContent:setVisible(tab == TAB_OVERVIEW) end
    if self.mapContent       then self.mapContent:setVisible(tab == TAB_MAP) end
    if self.treatmentContent then self.treatmentContent:setVisible(tab == TAB_TREATMENT) end

    -- Show/hide sidebars (Left side)
    if self.sidebarOverview  then self.sidebarOverview:setVisible(tab == TAB_OVERVIEW) end
    if self.sidebarMap       then self.sidebarMap:setVisible(tab == TAB_MAP) end
    if self.sidebarTreatment then self.sidebarTreatment:setVisible(tab == TAB_TREATMENT) end

    -- Mini-map must be explicitly managed: show only on map tab.
    if tab == TAB_MAP then
        self:_showMiniMap()
    else
        self:_hideMiniMap()
    end

    -- Trigger layout update on newly visible panels
    if tab == TAB_MAP then
        self:_refreshMapTab()
    elseif tab == TAB_TREATMENT then
        self:_refreshTreatmentSidebar()
    end
    
    self:_reloadLists()

    -- Color active tab label green, inactive labels dim
    local function setTabColor(el, isActive)
        if not el then return end
        if isActive then
            el:setTextColor(0.35, 0.85, 0.40, 1.0)
        else
            el:setTextColor(1.0, 1.0, 1.0, 0.40)
        end
    end
    setTabColor(self.tabLabelOverview,  tab == TAB_OVERVIEW)
    setTabColor(self.tabLabelMap,       tab == TAB_MAP)
    setTabColor(self.tabLabelTreatment, tab == TAB_TREATMENT)

    -- Underline active tab only
    if self.tabUnderlineOverview  then self.tabUnderlineOverview:setVisible(tab == TAB_OVERVIEW) end
    if self.tabUnderlineMap       then self.tabUnderlineMap:setVisible(tab == TAB_MAP) end
    if self.tabUnderlineTreatment then self.tabUnderlineTreatment:setVisible(tab == TAB_TREATMENT) end
end

-- ── Map Tab button ────────────────────────────────────────

function SoilPDAScreen:onClickHelp()
    if InfoDialog then
        local msg = g_i18n:getText("sf_pda_help_text") .. "\n\n" .. 
                    "--------------------------------------------------\n\n" ..
                    g_i18n:getText("sf_pda_help_github")
        InfoDialog.show(msg, nil, g_i18n:getText("sf_pda_screen_title"))
    end
end

-- ── Filter Toggle ─────────────────────────────────────────

function SoilPDAScreen:onClickFilter()
    self.filterOwnedOnly = not self.filterOwnedOnly
    self:_rebuildAllData()
    self:_updateFilterButtonText()
    self:_reloadLists()
end

function SoilPDAScreen:_updateFilterButtonText()
    local textKey = self.filterOwnedOnly and "sf_pda_filter_owned" or "sf_pda_filter_all"
    local text = tr(textKey, self.filterOwnedOnly and "Filter: Owned Only" or "Filter: All Fields")

    -- Keep the footer bar button in sync with the current filter state
    if self.menuButtonInfo and self.menuButtonInfo[2] then
        self.menuButtonInfo[2].text = text
        self:setMenuButtonInfo(self.menuButtonInfo)
    end
end

-- ── SmoothList Data Source ────────────────────────────────

function SoilPDAScreen:getNumberOfItemsInSection(list, section)
    if list == self.sidebarFieldList or list == self.sidebarMapList then
        return #self.fieldData
    elseif list == self.treatmentList then
        return #self.treatmentData
    end
    return 0
end

function SoilPDAScreen:populateCellForItemInSection(list, section, index, cell)
    -- Store index on cell for onClick handlers
    cell.rowDataIndex = index

    if list == self.sidebarFieldList then
        self:_populateFieldCell(index, cell)
    elseif list == self.sidebarMapList then
        self:_populateMapJumpCell(index, cell)
    elseif list == self.treatmentList then
        self:_populateTreatmentCell(index, cell)
    end
end

-- ── SmoothList Delegate ───────────────────────────────────

function SoilPDAScreen:onListSelectionChanged(list, section, index)
    SoilLogger.info("SoilPDAScreen: onListSelectionChanged index: %s", tostring(index))
    if index > 0 then
        if list == self.sidebarFieldList or list == self.sidebarMapList then
            self.selectedFieldIndex = index
            local entry = self.fieldData[index]
            if entry and entry.fieldId then
                self:_centerMapOnField(entry.fieldId)
            end
        elseif list == self.treatmentList then
            self.selectedTreatmentIndex = index
        end
    end
end

-- ── Row Click Handlers ────────────────────────────────────

--- Called by ListItem.onClick in Map Sidebar (XML)
function SoilPDAScreen:onClickMapJumpRow(element)
    local index = element and element.rowDataIndex
    SoilLogger.info("SoilPDAScreen: onClickMapJumpRow element.index=%s, element.rowDataIndex=%s", tostring(element and element.index), tostring(index))
    if index and index > 0 then
        local entry = self.fieldData[index]
        if entry and entry.fieldId then
            self:_centerMapOnField(entry.fieldId)
            -- If we were on Overview and clicked a jump row, move to Map tab
            if self.activeTab ~= TAB_MAP then
                self:setActiveTab(TAB_MAP)
            end
        end
    end
end

--- Called by ListItem.onClick in PDA Overview (XML)
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
    if SoilTreatmentDialog then
        SoilTreatmentDialog.show(entry.fieldId)
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

    local farmId = g_localPlayer and g_localPlayer.farmId

    for fieldId, _ in pairs(sfm.soilSystem.fieldData) do
        local isAllowed = true
        
        -- Check filter.
        -- fieldId in soilSystem is the FARMLAND ID (set from field.farmland.id in the
        -- sprayer hook), so we query getFarmlandOwner directly — no field lookup needed.
        if self.filterOwnedOnly and farmId and farmId > 0 and g_farmlandManager then
            local owner = g_farmlandManager:getFarmlandOwner(fieldId)
            if owner ~= farmId then
                isAllowed = false
            end
        end

        if isAllowed then
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

    -- Note: Summary stats always reflect ALL fields or all OWNED fields depending on overall Mod philosophy?
    -- Usually summary reflects everything. But let's count properly.
    
    local allFields = {}
    for fieldId, _ in pairs(sfm.soilSystem.fieldData) do
        local ok, info = pcall(function() return sfm.soilSystem:getFieldInfo(fieldId) end)
        if ok and info then
            table.insert(allFields, {fieldId = fieldId, info = info})
        end
    end

    local totalFields = #allFields
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

    for _, entry in ipairs(allFields) do
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

function SoilPDAScreen:_centerMapOnField(fieldId)
    SoilLogger.info("SoilPDAScreen: _centerMapOnField(fieldId=%s)", tostring(fieldId))
    
    local fields = g_fieldManager and g_fieldManager.fields
    if fields then
        local foundField = nil
        for _, field in ipairs(fields) do
            if field and field.farmland and field.farmland.id == fieldId then
                foundField = field
                break
            end
        end

        if foundField then
            local x, z = foundField.posX, foundField.posZ
            SoilLogger.info("SoilPDAScreen: Focusing map on field %s at %.1f, %.1f", tostring(fieldId), x, z)
            
            self.mapCenterX = x
            self.mapCenterZ = z
            self.mapZoom = 5.0
            self.isMapLocked = true

            -- Ensure a layer is active (default to Urgency layer if off)
            local sfm = g_SoilFertilityManager
            if sfm and sfm.settings then
                local currentLayer = sfm.settings.activeMapLayer or 0
                if currentLayer == 0 then
                    sfm.settings.activeMapLayer = 6 -- Urgency
                    if self.activeTab == TAB_MAP then
                        self:_refreshMapTab()
                    end
                end
            end

            if self.soilMiniMap then
                pcall(function()
                    self.soilMiniMap:setMapZoom(self.mapZoom)
                    self.soilMiniMap:setCenterToWorldPosition(self.mapCenterX, self.mapCenterZ)
                end)
            end
        else
            SoilLogger.warning("SoilPDAScreen: Could not find field with farmland ID %s in g_fieldManager", tostring(fieldId))
        end
    else
        SoilLogger.warning("SoilPDAScreen: g_fieldManager.fields not available")
    end
end
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

function SoilPDAScreen:_refreshTreatmentSidebar()
    local sfm = g_SoilFertilityManager
    if not sfm or not sfm.soilSystem then return end

    local needsFert, weedCount, pestCount, diseaseCount = 0, 0, 0, 0
    for _, entry in ipairs(self.fieldData) do
        local info = entry.info
        if info.needsFertilization then needsFert = needsFert + 1 end
        if (info.weedPressure    or 0) >= PRESSURE_THRESHOLD then weedCount    = weedCount    + 1 end
        if (info.pestPressure    or 0) >= PRESSURE_THRESHOLD then pestCount    = pestCount    + 1 end
        if (info.diseasePressure or 0) >= PRESSURE_THRESHOLD then diseaseCount = diseaseCount + 1 end
    end

    local function setText(el, val)
        if el then el:setText(tostring(val)) end
    end

    setText(self.treatStatNeedsFert, needsFert)
    setText(self.treatStatWeed,      weedCount)
    setText(self.treatStatPest,      pestCount)
    setText(self.treatStatDisease,   diseaseCount)
    setText(self.treatStatTotal,     #self.treatmentData)

    if self.treatHintText then
        self.treatHintText:setText(tr("sf_pda_treatment_hint", "Fields listed on the right need treatment. Click a row to see recommended inputs and estimated quantities."))
    end
end

-- ── List reload ───────────────────────────────────────────

function SoilPDAScreen:_reloadLists()
    if self.sidebarFieldList then self.sidebarFieldList:reloadData() end
    if self.sidebarMapList   then self.sidebarMapList:reloadData() end
    if self.treatmentList    then self.treatmentList:reloadData() end

    -- Empty hints
    if self.fieldsEmptyHint then
        self.fieldsEmptyHint:setVisible(#self.fieldData == 0)
    end
    if self.treatmentEmptyHint then
        self.treatmentEmptyHint:setVisible(#self.treatmentData == 0)
    end
end

-- ── Cell population: Map Jump list ───────────────────────

function SoilPDAScreen:_populateMapJumpCell(index, cell)
    local entry = self.fieldData[index]
    if not entry then return end

    local idEl     = cell:getDescendantByName("jumpRowId")
    local statusEl = cell:getDescendantByName("jumpRowStatus")

    if idEl then idEl:setText(tostring(entry.fieldId)) end

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
-- (Removed: Shift P toggle is now a UI button)
local function _registerToggleAction(mission)
    -- No-op
end

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, _onMissionLoaded)
FSBaseMission.update            = Utils.appendedFunction(FSBaseMission.update,            _onUpdate)
FSBaseMission.delete            = Utils.appendedFunction(FSBaseMission.delete,            _onDelete)