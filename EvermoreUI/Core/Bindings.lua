--------------------------------------------------------------------------------
--  Bindings.lua
--  Names for the entries in Bindings.xml (Key Bindings > AddOns). The
--  bindings live in the core addon so they're known at startup, whichever
--  of our addons provides the buttons they click. No EV_BLOCKED gate: the
--  names should show even if the suite blocks itself.
--------------------------------------------------------------------------------
BINDING_HEADER_EVERMOREUI = "|cffd4924eEvermore|rUI"
BINDING_HEADER_EVERMOREUIQUESTITEMS = "Quest Items"
for i = 1, 12 do
    _G["BINDING_NAME_CLICK EvermoreUIQuestItem" .. i .. ":LeftButton"] = "Quest Item " .. i
end
