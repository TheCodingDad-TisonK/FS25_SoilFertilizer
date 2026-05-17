-- =========================================================
-- FS25 Soil & Fertilizer — Soil Map Overlay Help Dialog
-- =========================================================
-- Opened from the Help button in the overlay sidebar.
-- Explains how to read the soil map, layer meanings, the
-- tooltip, the color legend, and sidebar buttons.
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilOverlayHelpDialog
SoilOverlayHelpDialog = {}
local SoilOverlayHelpDialog_mt = Class(SoilOverlayHelpDialog, ScreenElement)

local SF_OVHELP_MOD_NAME = g_currentModName
local SF_OVHELP_MOD_DIR  = g_currentModDirectory

SoilOverlayHelpDialog.INSTANCE = nil

-- Content table: {t="H"|"B"|"S", v="text"}
-- H = section header (bold, green, uppercase)
-- B = body line (white, normal)
-- S = spacer (blank gap)
SoilOverlayHelpDialog.CONTENT = {
    { t="H", v="HOW TO READ THE SOIL MAP" },
    { t="B", v="The overlay colours each map cell based on the selected nutrient layer." },
    { t="B", v="  Red    = Poor  (below minimum, needs immediate attention)" },
    { t="B", v="  Yellow = Fair  (below optimal, monitor or top-up soon)" },
    { t="B", v="  Green  = Good  (at or above optimal, no action needed)" },
    { t="B", v="Unsampled cells appear dim \226\128\148 walk onto the field to sample them." },
    { t="S", v=" " },
    { t="H", v="MAP LAYERS" },
    { t="B", v="Layer 1 \226\128\148 Nitrogen (N)      : Most volatile. Depletes on every harvest." },
    { t="B", v="Layer 2 \226\128\148 Phosphorus (P)    : Slow-moving. Long-lasting from MAP / DAP." },
    { t="B", v="Layer 3 \226\128\148 Potassium (K)     : Apply Potash. Important for root crops." },
    { t="B", v="Layer 4 \226\128\148 pH                : 6.5 - 7.0 ideal. Green = optimal range." },
    { t="B", v="Layer 5 \226\128\148 Organic Matter    : Higher = better soil structure and retention." },
    { t="S", v=" " },
    { t="H", v="CELL TOOLTIP (hover a cell)" },
    { t="B", v="Shows the exact nutrient value (ppm), its Good / Fair / Poor status," },
    { t="B", v="and \226\128\148 when a crop is planted \226\128\148 the crop's target value and the gap" },
    { t="B", v="(how many ppm you are above or below the crop's optimal requirement)." },
    { t="S", v=" " },
    { t="H", v="COLOUR LEGEND (sidebar)" },
    { t="B", v="The gradient bar shows what colour = what status for the active layer." },
    { t="B", v="All layers use the same Red (poor) to Yellow (fair) to Green (good) scale." },
    { t="S", v=" " },
    { t="H", v="SIDEBAR BUTTONS" },
    { t="B", v="Farm Overview  \226\128\148 Opens the PDA soil report for all your fields." },
    { t="B", v="Treatment Plan \226\128\148 Opens a prioritised list of fields needing attention." },
    { t="B", v="Disable Overlay \226\128\148 Turns off the soil overlay (re-enable via sidebar)." },
    { t="B", v="Help           \226\128\148 You are reading it." },
    { t="S", v=" " },
    { t="H", v="TIPS" },
    { t="B", v="* Click a map cell while the overlay is active to inspect it." },
    { t="B", v="* The number on each field tile shows the field-average value." },
    { t="B", v="* Zoom into a field to see per-cell variability within the field." },
    { t="B", v="* Switch layers with the numbered buttons at the top of the sidebar." },
}

-- ── i18n helper ───────────────────────────────────────────

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[SF_OVHELP_MOD_NAME]
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

function SoilOverlayHelpDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SoilOverlayHelpDialog_mt)
    self._contentLineEls = {}
    return self
end

function SoilOverlayHelpDialog.register(modDirectory)
    if SoilOverlayHelpDialog.INSTANCE ~= nil then return end

    SF_OVHELP_MOD_DIR = modDirectory
    local xmlPath = modDirectory .. "xml/gui/SoilOverlayHelpDialog.xml"

    SoilOverlayHelpDialog.INSTANCE = SoilOverlayHelpDialog.new()
    SoilLogger.info("SoilOverlayHelpDialog: registering from %s", xmlPath)

    local ok, err = pcall(function()
        g_gui:loadGui(xmlPath, "SoilOverlayHelpDialog", SoilOverlayHelpDialog.INSTANCE)
    end)

    if not ok then
        SoilLogger.error("SoilOverlayHelpDialog: loadGui failed: %s", tostring(err))
        SoilOverlayHelpDialog.INSTANCE = nil
    else
        SoilLogger.info("SoilOverlayHelpDialog: registered successfully")
    end
end

function SoilOverlayHelpDialog.show()
    if SoilOverlayHelpDialog.INSTANCE == nil then
        SoilOverlayHelpDialog.register(SF_OVHELP_MOD_DIR)
    end
    if SoilOverlayHelpDialog.INSTANCE == nil then return end
    g_gui:showDialog("SoilOverlayHelpDialog")
end

-- ── Lifecycle ─────────────────────────────────────────────

function SoilOverlayHelpDialog:onGuiSetupFinished()
    SoilOverlayHelpDialog:superClass().onGuiSetupFinished(self)
    self._elContentBox = self:getDescendantById("sfOvHelp_contentBox")
end

function SoilOverlayHelpDialog:onOpen()
    SoilOverlayHelpDialog:superClass().onOpen(self)
    self:_buildContent()
end

function SoilOverlayHelpDialog:onClose()
    SoilOverlayHelpDialog:superClass().onClose(self)
    self:_clearContent()
end

-- ── Content Builder ───────────────────────────────────────

function SoilOverlayHelpDialog:_buildContent()
    if not self._elContentBox then return end

    local profileH = g_gui:getProfile("sfOvHelp_header")
    local profileB = g_gui:getProfile("sfOvHelp_body")
    local profileS = g_gui:getProfile("sfOvHelp_spacer")

    if not profileH or not profileB then
        SoilLogger.warning("SoilOverlayHelpDialog: required profiles not found")
        return
    end

    for _, row in ipairs(SoilOverlayHelpDialog.CONTENT) do
        local profile = (row.t == "H") and profileH
                     or (row.t == "S") and profileS
                     or profileB

        if profile then
            local el = TextElement.new()
            el:loadProfile(profile, true)
            el:setText(row.v)
            self._elContentBox:addElement(el)
            el:onGuiSetupFinished()
            table.insert(self._contentLineEls, el)
        end
    end

    self._elContentBox:invalidateLayout()
end

function SoilOverlayHelpDialog:_clearContent()
    for _, el in ipairs(self._contentLineEls) do
        if self._elContentBox then
            self._elContentBox:removeElement(el)
        end
    end
    self._contentLineEls = {}
end

-- ── Button ────────────────────────────────────────────────

function SoilOverlayHelpDialog:onClickClose()
    g_gui:closeDialogByName("SoilOverlayHelpDialog")
end
