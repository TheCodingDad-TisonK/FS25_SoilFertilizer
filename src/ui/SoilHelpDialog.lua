-- =========================================================
-- FS25 Soil & Fertilizer — PDA Help Dialog
-- =========================================================
-- Opened from the PDA screen X/help button.
-- Explains nutrients, soil chemistry, crop targets, status
-- levels, crop pressure, and general tips.
-- =========================================================
-- Author: TisonK
-- =========================================================

---@class SoilHelpDialog
SoilHelpDialog = {}
local SoilHelpDialog_mt = Class(SoilHelpDialog, ScreenElement)

local SF_HELP_MOD_NAME = g_currentModName
local SF_HELP_MOD_DIR  = g_currentModDirectory

SoilHelpDialog.INSTANCE = nil

-- Content table: {t="H"|"B"|"S", v="text"}
-- H = section header (bold, green, uppercase)
-- B = body line (white, normal)
-- S = spacer (blank gap)
SoilHelpDialog.CONTENT = {
    { t="H", v="NUTRIENTS" },
    { t="B", v="N  (Nitrogen)     \226\128\148 Depletes every harvest. Apply UAN, Urea, AMS, or Manure." },
    { t="B", v="P  (Phosphorus)   \226\128\148 Long-lasting. Apply MAP, DAP, Liquid MAP, or Liquid DAP." },
    { t="B", v="K  (Potassium)    \226\128\148 Apply Potash or Liquid Potash. Critical for root crops." },
    { t="B", v="OM (Organic Mat.) \226\128\148 Builds slowly. Incorporate Manure, Compost, or Biosolids." },
    { t="S", v=" " },
    { t="H", v="SOIL CHEMISTRY" },
    { t="B", v="pH 6.5 - 7.0 = Ideal. Apply Lime if below 6.5. Apply Gypsum if above 7.5." },
    { t="B", v="Lime raises pH. Gypsum lowers pH. Allow 1-2 seasons to normalize." },
    { t="S", v=" " },
    { t="H", v="CROP TARGETS" },
    { t="B", v="Each crop has different N/P/K requirements. The map tooltip shows" },
    { t="B", v="the gap between current levels and the crop's optimal target." },
    { t="B", v="Green = at or above target. Red = deficit. Hover a cell to inspect." },
    { t="S", v=" " },
    { t="H", v="STATUS LEVELS" },
    { t="B", v="Good  (green)  \226\128\148 Above optimal threshold. No action needed." },
    { t="B", v="Fair  (yellow) \226\128\148 Below optimal. Monitor or apply a preventive top-up." },
    { t="B", v="Poor  (red)    \226\128\148 Below minimum. Immediate treatment required." },
    { t="S", v=" " },
    { t="H", v="CROP PRESSURE" },
    { t="B", v="Weed    > 20% \226\128\148 Apply Herbicide or use mechanical weeder / hoe." },
    { t="B", v="Pest    > 20% \226\128\148 Apply Insecticide." },
    { t="B", v="Disease > 20% \226\128\148 Apply Fungicide." },
    { t="S", v=" " },
    { t="H", v="TIPS" },
    { t="B", v="* Open the Treatment Plan tab to see which fields need attention most." },
    { t="B", v="* Use the soil map overlay (press M then Soil Layers) to see per-cell data." },
    { t="B", v="* Season + rain affect nutrients. Avoid over-applying N in autumn." },
    { t="B", v="* Crop rotation avoids soil fatigue and can grant a legume N bonus." },
}

-- ── i18n helper ───────────────────────────────────────────

local function tr(key, fallback)
    local modEnv = g_modEnvironments and g_modEnvironments[SF_HELP_MOD_NAME]
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

function SoilHelpDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or SoilHelpDialog_mt)
    self._contentLineEls = {}
    return self
end

function SoilHelpDialog.register(modDirectory)
    if SoilHelpDialog.INSTANCE ~= nil then return end

    SF_HELP_MOD_DIR = modDirectory
    local xmlPath = modDirectory .. "xml/gui/SoilHelpDialog.xml"

    SoilHelpDialog.INSTANCE = SoilHelpDialog.new()
    SoilLogger.info("SoilHelpDialog: registering from %s", xmlPath)

    local ok, err = pcall(function()
        g_gui:loadGui(xmlPath, "SoilHelpDialog", SoilHelpDialog.INSTANCE)
    end)

    if not ok then
        SoilLogger.error("SoilHelpDialog: loadGui failed: %s", tostring(err))
        SoilHelpDialog.INSTANCE = nil
    else
        SoilLogger.info("SoilHelpDialog: registered successfully")
    end
end

function SoilHelpDialog.show()
    if SoilHelpDialog.INSTANCE == nil then
        SoilHelpDialog.register(SF_HELP_MOD_DIR)
    end
    if SoilHelpDialog.INSTANCE == nil then return end
    g_gui:showDialog("SoilHelpDialog")
end

-- ── Lifecycle ─────────────────────────────────────────────

function SoilHelpDialog:onGuiSetupFinished()
    SoilHelpDialog:superClass().onGuiSetupFinished(self)
    self._elContentBox = self:getDescendantById("sfHelp_contentBox")
end

function SoilHelpDialog:onOpen()
    SoilHelpDialog:superClass().onOpen(self)
    self:_buildContent()
end

function SoilHelpDialog:onClose()
    SoilHelpDialog:superClass().onClose(self)
    self:_clearContent()
end

-- ── Content Builder ───────────────────────────────────────

function SoilHelpDialog:_buildContent()
    if not self._elContentBox then return end

    local profileH = g_gui:getProfile("sfHelp_header")
    local profileB = g_gui:getProfile("sfHelp_body")
    local profileS = g_gui:getProfile("sfHelp_spacer")

    if not profileH or not profileB then
        SoilLogger.warning("SoilHelpDialog: required profiles not found")
        return
    end

    for _, row in ipairs(SoilHelpDialog.CONTENT) do
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

function SoilHelpDialog:_clearContent()
    for _, el in ipairs(self._contentLineEls) do
        if self._elContentBox then
            self._elContentBox:removeElement(el)
        end
    end
    self._contentLineEls = {}
end

-- ── Button ────────────────────────────────────────────────

function SoilHelpDialog:onClickClose()
    g_gui:closeDialogByName("SoilHelpDialog")
end
