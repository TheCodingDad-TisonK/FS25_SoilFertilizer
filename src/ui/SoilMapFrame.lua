-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Map Frame Page
-- =========================================================
-- Injects a soil layer selector as a native sub-page inside
-- InGameMenuMapFrame (the PDA map sidebar with the dot-nav).
--
-- HOW IT WORKS:
--   InGameMenuMapFrame stores its left-panel sub-pages in
--   self.mapOverlays (a list of {element, title} entries).
--   The arrows (◄ ►) cycle through these pages. We clone an
--   existing page container as our template, wipe its children,
--   populate it with MultiTextOption layer buttons, and append
--   it to the list. The overlay density map is already drawn by
--   SoilMapOverlay via IngameMapElement hooks — we just add the
--   sidebar controls.
--
-- WHAT THIS FILE DOES NOT DO:
--   - It does NOT replace SoilMapOverlay. That file still owns
--     the actual density-map drawing on the fullscreen map.
--   - It does NOT touch SoilSettingsUI or the game settings page.
--
-- THREAD SAFETY:
--   All hooks use Utils.appendedFunction (stacks, never replaces).
--   _injectPage() is guarded by _injected so it runs exactly once.
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilMapFrame
SoilMapFrame = {}
local SoilMapFrame_mt = Class(SoilMapFrame)

-- Capture mod name at source-time — only valid during loading
local SF_MOD_NAME = g_currentModName

-- ── i18n helper ───────────────────────────────────────────

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[SF_MOD_NAME]
    local i18n   = (modEnv and modEnv.i18n) or g_i18n
    if i18n then
        local text = i18n:getText(key)
        -- FS25 returns the key itself when not found, prefixed with $l10n_
        if text and text ~= "" and text ~= ("$l10n_" .. key) then
            return text
        end
    end
    return fallback or key
end

-- ── Layer definitions ─────────────────────────────────────
-- Must match SoilMapOverlay.LAYER_COUNT (9) and the layer indices

local LAYER_KEYS = {
    [0] = "sf_map_layer_off",
    [1] = "sf_map_layer_n",
    [2] = "sf_map_layer_p",
    [3] = "sf_map_layer_k",
    [4] = "sf_map_layer_ph",
    [5] = "sf_map_layer_om",
    [6] = "sf_map_layer_urgency",
    [7] = "sf_map_layer_weed",
    [8] = "sf_map_layer_pest",
    [9] = "sf_map_layer_disease",
}
local LAYER_COUNT = 9  -- layers 0..9

-- ── Constructor ───────────────────────────────────────────

---@param soilMapOverlay SoilMapOverlay
---@param settings       Settings
---@return SoilMapFrame
function SoilMapFrame.new(soilMapOverlay, settings)
    local self = setmetatable({}, SoilMapFrame_mt)

    self.soilMapOverlay = soilMapOverlay
    self.settings       = settings

    -- Will be set after injection
    self.layerSelector  = nil   -- MultiTextOptionElement
    self._injected      = false
    self._hooksInstalled = false

    return self
end

-- ── Public: call from SoilFertilityManager.new() ─────────

-- Installs the class-level hooks on InGameMenuMapFrame.
-- Safe to call at constructor time — hooks use appendedFunction
-- and reference g_SoilFertilityManager.soilMapFrame at call time.
function SoilMapFrame:installHooks()
    if self._hooksInstalled then return end
    if InGameMenuMapFrame == nil then
        SoilLogger.warning("[SoilMapFrame] InGameMenuMapFrame not found — hooks skipped")
        return
    end

    -- Inject our page when the map frame first opens
    InGameMenuMapFrame.onFrameOpen = Utils.appendedFunction(
        InGameMenuMapFrame.onFrameOpen,
        function(frame)
            local smf = g_SoilFertilityManager and g_SoilFertilityManager.soilMapFrame
            if smf then smf:_onFrameOpen(frame) end
        end
    )

    -- Keep selector in sync when the frame reopens
    InGameMenuMapFrame.onFrameClose = Utils.appendedFunction(
        InGameMenuMapFrame.onFrameClose,
        function(frame)
            local smf = g_SoilFertilityManager and g_SoilFertilityManager.soilMapFrame
            if smf then smf:_onFrameClose(frame) end
        end
    )

    self._hooksInstalled = true
    SoilLogger.info("[SoilMapFrame] InGameMenuMapFrame hooks installed")
end

-- ── Frame lifecycle ───────────────────────────────────────

function SoilMapFrame:_onFrameOpen(frame)
    -- Inject exactly once
    if not self._injected then
        self:_injectPage(frame)
        self:_injectMenuButton(frame)
    end

    -- Always sync the selector to the current layer
    self:_syncSelector()

    -- Tell the overlay the map is open and (re)generate if needed
    if self.soilMapOverlay then
        self.soilMapOverlay.isMapOpen = true
        local layer = self.settings and self.settings.activeMapLayer or 0
        if layer > 0 and not self.soilMapOverlay.isReady then
            self.soilMapOverlay:requestGenerate()
        end
    end
end

function SoilMapFrame:_injectMenuButton(frame)
    if not frame or not frame.menuButtonInfo then return end

    if not self._pdaButton then
        self._pdaButton = {
            inputAction = InputAction.MENU_EXTRA_1,
            text = tr("sf_pda_open_btn", "Open Soil PDA"),
            callback = function()
                if SoilPDAScreen then
                    SoilPDAScreen.toggle()
                end
            end,
            showWhenPaused = true
        }
    end

    if not self._devNoteButton then
        self._devNoteButton = {
            inputAction = InputAction.MENU_EXTRA_2,
            text = tr("sf_pda_btn_help", "Dev Note"),
            callback = function()
                if SoilHelpDialog then
                    SoilHelpDialog.show()
                end
            end,
            showWhenPaused = true
        }
    end

    local pdaExists = false
    local devNoteExists = false
    for _, btn in ipairs(frame.menuButtonInfo) do
        if btn == self._pdaButton then pdaExists = true end
        if btn == self._devNoteButton then devNoteExists = true end
    end

    local dirty = false
    if not pdaExists then
        table.insert(frame.menuButtonInfo, self._pdaButton)
        dirty = true
    end
    if not devNoteExists then
        table.insert(frame.menuButtonInfo, self._devNoteButton)
        dirty = true
    end

    if dirty and frame.setMenuButtonInfoDirty then
        frame:setMenuButtonInfoDirty()
    end
end

function SoilMapFrame:_onFrameClose(frame)
    if self.soilMapOverlay then
        self.soilMapOverlay.isMapOpen = false
    end
end

-- ── Page injection ────────────────────────────────────────

-- InGameMenuMapFrame.mapOverlays is a list of tables, each with:
--   entry.element  — the GuiElement shown in the left sidebar
--   entry.title    — string shown in the ◄ TITLE ► header
-- (Some builds use .frame instead of .element — we handle both)
--
-- We find an existing entry, clone its element as a blank container,
-- build our MultiTextOption selector into it, then append to the list.
function SoilMapFrame:_injectPage(frame)
    -- Find the overlay list
    local overlayList = frame.mapOverlays
    if overlayList == nil or type(overlayList) ~= "table" then
        SoilLogger.warning("[SoilMapFrame] frame.mapOverlays not found — cannot inject page")
        SoilLogger.warning("[SoilMapFrame] Soil layer selector will not appear in the map sidebar")
        self._injected = true  -- don't retry; overlay still draws via IngameMapElement hook
        return
    end

    if #overlayList == 0 then
        SoilLogger.warning("[SoilMapFrame] mapOverlays is empty — cannot clone template")
        self._injected = true
        return
    end

    -- Grab a template from the first existing entry
    local templateEntry   = overlayList[1]
    local templateElement = templateEntry.element or templateEntry.frame
    if templateElement == nil then
        SoilLogger.warning("[SoilMapFrame] Template overlay entry has no element/frame field")
        self._injected = true
        return
    end

    local parent = templateElement.parent
    if parent == nil then
        SoilLogger.warning("[SoilMapFrame] Template element has no parent — cannot clone")
        self._injected = true
        return
    end

    -- Clone the template container
    local container = templateElement:clone(parent)
    if container == nil then
        SoilLogger.warning("[SoilMapFrame] clone() returned nil")
        self._injected = true
        return
    end

    -- Give all cloned children fresh focusIds so FocusManager doesn't get confused
    self:_refreshFocusIds(container)

    -- Remove all children from the clone (we want a clean slate)
    -- Iterate backwards so removals don't corrupt the index
    for i = #container.elements, 1, -1 do
        local child = container.elements[i]
        if child then
            container:removeElement(child)
            if child.delete then child:delete() end
        end
    end

    -- Build our content into the blank container
    local scrollLayout = self:_buildContent(container)

    -- Hide until the player navigates to our page
    container:setVisible(false)

    -- Build the page entry and append it
    local pageTitle = tr("sf_map_page_title", "Soil Layers")
    local pageEntry = {
        element = container,
        frame   = container,   -- some builds use .frame
        title   = pageTitle,
    }
    table.insert(overlayList, pageEntry)

    -- If the frame tracks numOverlays separately, keep it consistent
    if frame.numOverlays ~= nil then
        frame.numOverlays = #overlayList
    end

    -- Refresh the nav dots / page count indicator if the frame exposes that method
    if frame.updateOverlayPage then
        pcall(frame.updateOverlayPage, frame)
    end

    self._injected = true
    SoilLogger.info("[SoilMapFrame] Soil layer page injected into mapOverlays (%d total pages)", #overlayList)
end

-- ── Content builder ───────────────────────────────────────

-- Populates the blank container with:
--   1. A section header ("Soil Map Layer")
--   2. A MultiTextOption dropdown to pick the active layer
-- Returns the layout element (container itself acts as scroll panel).
function SoilMapFrame:_buildContent(container)
    -- Section header using the same UIHelper the settings page uses
    if UIHelper and UIHelper.createSectionHeader then
        local ok, err = pcall(UIHelper.createSectionHeader,
            container, tr("sf_map_sidebar_header", "Soil Map Layer"))
        if not ok then
            SoilLogger.warning("[SoilMapFrame] createSectionHeader failed: %s", tostring(err))
        end
    end

    -- Build the layer option texts (0=Off, 1..9=layers)
    local layerTexts = {}
    for i = 0, LAYER_COUNT do
        layerTexts[i + 1] = tr(LAYER_KEYS[i], "Layer " .. i)
    end

    -- Create a MultiTextOption (dropdown) for the layer selector.
    -- UIHelper.createMultiOption adds it to `container` and returns the element.
    if UIHelper and UIHelper.createMultiOption then
        local ok, element = pcall(UIHelper.createMultiOption,
            container,
            SoilMapFrame,               -- callbackTarget: method is looked up on this table
            "onLayerSelectorChanged",   -- callbackName: SoilMapFrame.onLayerSelectorChanged
            layerTexts,
            tr("sf_map_sidebar_label", "Active Layer"),
            tr("sf_map_sidebar_tooltip", "Select which soil nutrient to display on the map")
        )
        if ok and element then
            self.layerSelector = element
            SoilLogger.info("[SoilMapFrame] Layer MultiTextOption created")
        else
            SoilLogger.warning("[SoilMapFrame] createMultiOption failed: %s", tostring(element))
        end
    else
        SoilLogger.warning("[SoilMapFrame] UIHelper.createMultiOption not available")
    end

    if container.invalidateLayout then
        container:invalidateLayout()
    end

    return container
end

-- ── Callback: MultiTextOption changed ────────────────────

-- Called when the player changes the dropdown.
-- MultiTextOption state is 1-based; our layers are 0-based.
-- Static method so UIHelper can look it up by name on SoilMapFrame.
function SoilMapFrame.onLayerSelectorChanged(target, state)
    local smf = g_SoilFertilityManager and g_SoilFertilityManager.soilMapFrame
    if smf == nil then return end
    if smf.soilMapOverlay == nil then return end

    -- state is 1-based from MultiTextOption; convert to 0-based layer index
    local layerIdx = (state or 1) - 1
    smf.soilMapOverlay:setLayer(layerIdx)
    SoilLogger.debug("[SoilMapFrame] Layer changed to %d via sidebar selector", layerIdx)
end

-- ── Sync selector state ───────────────────────────────────

-- Called on every frame-open to keep the dropdown in sync with
-- the current activeMapLayer (which may have been changed by
-- Shift+M keyboard shortcut or the overlay's own raw sidebar).
function SoilMapFrame:_syncSelector()
    if self.layerSelector == nil then return end
    if not self.layerSelector.setState then return end

    local activeLayer = (self.settings and self.settings.activeMapLayer) or 0
    -- MultiTextOption is 1-based; clamp to valid range
    local state = math.max(1, math.min(LAYER_COUNT + 1, activeLayer + 1))
    self.layerSelector:setState(state)
end

-- ── FocusId refresh ───────────────────────────────────────

-- Cloned elements share duplicate focusIds from their template,
-- causing FocusManager to break keyboard/controller navigation.
-- Assign fresh IDs recursively.
function SoilMapFrame:_refreshFocusIds(element)
    if element == nil then return end
    if FocusManager and FocusManager.serveAutoFocusId then
        element.focusId = FocusManager:serveAutoFocusId()
    end
    if element.elements then
        for _, child in ipairs(element.elements) do
            self:_refreshFocusIds(child)
        end
    end
end

-- ── Delete / cleanup ──────────────────────────────────────

function SoilMapFrame:delete()
    -- appendedFunction hooks on InGameMenuMapFrame are class-level and
    -- not individually removable — guard via g_SoilFertilityManager check
    -- inside the closure means they no-op safely after delete().
    self.layerSelector  = nil
    self.soilMapOverlay = nil
    self.settings       = nil
    SoilLogger.info("[SoilMapFrame] deleted")
end
