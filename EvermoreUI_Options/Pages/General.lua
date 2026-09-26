if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  General: window scale, movers, client report.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local floor = math.floor

local SCALES = {
    { value = 0.75, text = "75%" }, { value = 0.85, text = "85%" }, { value = 0.9, text = "90%" },
    { value = 1.0,  text = "100%" }, { value = 1.1, text = "110%" }, { value = 1.25, text = "125%" },
    { value = 1.5,  text = "150%" },
}

local function YesNo(v)
    if v == nil then return "|cffaaaaaa?|r" end
    return v and ("|cff" .. EV.Theme.Hex("accent") .. "yes|r") or ("|cff" .. EV.Theme.Hex("danger") .. "no|r")
end

EV.Options:RegisterPage{
    key = "general", title = L["General"], group = "General",
    description = L["Window, layout and client information."],
    build = function(p)
        p:Section(L["Interface"])
        p:Dual(
            { type = "dropdown", text = L["Options window scale"], width = 120, values = SCALES,
              get = function() return EV.DB:GetCore().panelScale or 1 end,
              set = function(v) EV.Options:SetScale(v) end },
            { type = "button", text = L["Edit mode"], label = L["Open"], width = 120,
              tooltip = L["Move, anchor, align and resize every EvermoreUI frame. Also /evui edit."],
              onClick = function() EV.Movers:Unlock() end })

        p:Section(L["Look"])
        p:Dual(
            { type = "dropdown", text = L["Contrast"], width = 160,
              values = { { value = "standard", text = L["Standard"] }, { value = "high", text = L["High contrast"] } },
              tooltip = L["High contrast brightens borders and text and deepens panels, for every EvermoreUI window and skinned Blizzard window. Both settings meet WCAG AA contrast."],
              get = function() return EV.Theme.mode end,
              set = function(v) EV.Theme.SetContrast(v) end },
            { type = "button", text = L["Widget gallery"], label = L["Open"], width = 120,
              tooltip = L["Every EvermoreUI control in one window. Also /evui widgets."],
              onClick = function() SlashCmdList.EVERMOREUI("widgets") end })

        p:Section(L["Font"])
        p:Dual(
            { type = "dropdown", text = L["Font"], width = 170,
              values = function() return EV.Media:FontValues(false) end,
              tooltip = L["The font for every EvermoreUI addon. Chat, tooltips and skinned windows follow it unless you pick a font on their own pages. Blizzard's text changes straight away; ours finishes changing after a reload."],
              get = function() return EV.Media:GlobalFontName() end,
              set = function(v)
                  EV.Fonts:SetGlobal(v)
                  EV.Options:MarkReloadNeeded()
              end },
            { type = "toggle", text = L["Use it in Blizzard's interface"],
              tooltip = L["Swaps Blizzard's plain text font for ours everywhere it's used: unit frames, nameplates, quest text, menus and windows. Decorative fonts are left alone. Only for languages our fonts cover."],
              disabled = function() return not EV.Fonts:Supported() end,
              get = function() return EV.DB:GetCore().blizzardFonts ~= false end,
              set = function(v) EV.Fonts:SetBlizzard(v) end })

        p:Dual(
            { type = "toggle", text = L["Options button in the Escape menu"],
              tooltip = L["Adds an EvermoreUI button to the game menu, under Shop, that opens these options."],
              get = function() return EV.DB:GetCore().gameMenuButton ~= false end,
              set = function(v) EV.DB:GetCore().gameMenuButton = v end },
            { type = "toggle", text = L["Edit Mode button in the Escape menu"],
              tooltip = L["Adds an EvermoreUI Edit Mode button to the game menu that unlocks every EvermoreUI frame for moving. Also /evui edit."],
              get = function() return EV.DB:GetCore().gameMenuEditButton == true end,
              set = function(v) EV.DB:GetCore().gameMenuEditButton = v end })

        p:Section(L["UI scale"])
        local Px = EV.Pixel
        p:Dual(
            { type = "toggle", text = L["Pixel-perfect scale"],
              tooltip = L["Sets the UI scale so one UI unit is exactly one screen pixel, so borders and edges line up. Turning this off hands scaling back to Blizzard after a reload."],
              get = function() return Px.ScaleSettings().managed end,
              set = function(v)
                  Px.ScaleSettings().managed = v
                  if v then Px:ApplyScale() else EV.Options:MarkReloadNeeded() end
              end },
            { type = "slider", text = L["UI size"], min = 100, max = 200, step = 5,
              fmt = function(v) return v .. "%" end,
              tooltip = L["Makes everything bigger while keeping it pixel-perfect: sizes and borders still snap to whole screen pixels."],
              disabled = function() return not Px.ScaleSettings().managed end,
              get = function() return floor((Px.ScaleSettings().size or 1) * 100 + 0.5) end,
              set = function(v) Px.ScaleSettings().size = v / 100; Px:ApplyScale() end })
        p:Note(("%s %dpx  -  %s %.4f"):format(L["Screen height"], Px:PhysicalHeight(),
            L["pixel-perfect scale"], Px:Perfect()), 0.6)

        p:Section(L["Client"])
        local c = EV.Caps
        p:Note(("%s %s (%s)   %s %s   %s %s"):format(
            L["Client"], tostring(c.version), tostring(c.build), L["Interface"], tostring(c.interface),
            L["Retail codebase"], YesNo(c.isMainline)), 0.7)
        p:Note(("C_Secrets %s    Edit Mode %s    Cooldown Viewer %s    GetSpecialization %s    %s %s"):format(
            YesNo(c.secrets), YesNo(c.editMode), YesNo(c.cooldownViewer), YesNo(c.specAPI),
            L["Secure snippets"], YesNo(c.secureSnippets)), 0.7)
        p:Row{ type = "button", text = L["Full capability report"], label = L["Print to chat"], width = 140,
               onClick = function() EV:PrintCaps() end }

        p:Section(L["Updates"])
        p:Dual(
            { type = "toggle", text = L["Show what's new after an update"],
              tooltip = L["The first time you log in after EvermoreUI updates, a window lists what changed."],
              get = function() return EV.DB:GetGlobal().whatsNew ~= false end,
              set = function(v) EV.DB:GetGlobal().whatsNew = v end },
            { type = "button", text = L["What's new"], label = L["Open"], width = 120,
              tooltip = "/evui new",
              onClick = function() EV.Options:Toggle(); EV.WhatsNew.Show() end })

        p:Section(L["Feedback"])
        p:Note(L["Found a bug or want something changed? The report collects your version, modules, other addons and any recent EvermoreUI errors, ready to paste into an issue."], 0.7)
        p:Row{ type = "button", text = L["Bug report"], label = L["Copy report"], width = 140,
               tooltip = "/evui bug",
               onClick = function() EV.Report:Show() end }
        p:Note(EV.Report:IssuesURL(), 0.6)
    end,
}
