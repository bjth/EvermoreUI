if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Theme.lua (options)
--  Colours, fonts and drawing helpers live in core (EvermoreUI/Core/Theme.lua)
--  so every module shares them. This file only adds the options window's
--  layout metrics.
--------------------------------------------------------------------------------
local T = EvermoreUI.Theme

T.W, T.H          = 1040, 720
T.SIDEBAR_W       = 230
T.HEADER_H        = 96
T.TABS_H          = 34
T.FOOTER_H        = 58
T.PAD             = 32       -- content side padding
T.ROW_H           = 46
T.SECTION_H       = 38
T.NAV_H           = 34
