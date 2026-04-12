-- =========================================================
-- FS25 Realistic Soil & Fertilizer - Help Dialog
-- =========================================================
-- A larger help dialog with two text sections for developer 
-- updates and community information.
-- =========================================================
-- Author: TisonK
-- =========================================================

SoilHelpDialog = {}
local SoilHelpDialog_mt = Class(SoilHelpDialog, MessageDialog)

function SoilHelpDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or SoilHelpDialog_mt)
    self.name = "SoilHelpDialog"
    return self
end

function SoilHelpDialog:onGuiSetupFinished()
    SoilHelpDialog:superClass().onGuiSetupFinished(self)
    -- Element caching if needed (currently using $l10n in XML)
end

function SoilHelpDialog:onOpen()
    SoilHelpDialog:superClass().onOpen(self)
end

function SoilHelpDialog:onClose()
    SoilHelpDialog:superClass().onClose(self)
end

function SoilHelpDialog:onCloseClick()
    self:close()
end

function SoilHelpDialog:close()
    g_gui:closeDialog(self)
end

-- ── Singleton static methods ────────────────────────────

SoilHelpDialog.INSTANCE = nil

function SoilHelpDialog.show()
    if SoilHelpDialog.INSTANCE == nil then
        SoilHelpDialog.INSTANCE = SoilHelpDialog.new()
        -- Load XML dynamically
        g_gui:loadGui(
            g_currentModDirectory .. "gui/SoilHelpDialog.xml", 
            "SoilHelpDialog", 
            SoilHelpDialog.INSTANCE
        )
    end

    g_gui:showDialog("SoilHelpDialog")
end
