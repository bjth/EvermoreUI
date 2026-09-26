if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Profiles: switch, create, copy, delete, reset.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L
local DB = EV.DB

local copyFrom, deleteName

local function ProfileList(excludeActive)
    local list = {}
    for _, name in ipairs(DB:ListProfiles()) do
        if not (excludeActive and name == DB:GetProfileName()) then
            list[#list + 1] = { value = name, text = name }
        end
    end
    return list
end

EV.Options:RegisterPage{
    key = "profiles", title = L["Profiles"], group = "General",
    description = L["Settings are saved per profile. Each character picks one."],
    build = function(p)
        p:Section(L["Active profile"])
        p:Row{ type = "dropdown", text = L["Profile for this character"], width = 220,
               values = function() return ProfileList(false) end,
               get = function() return DB:GetProfileName() end,
               set = function(v) DB:SetProfile(v); EV:Print(L["Switched to profile"], EV:Colour(v)) end }
        p:Row{ type = "input", text = L["Create a new profile"], width = 220, placeholder = L["Name, then Enter"],
               onCommit = function(name, box)
                   if name == "" then return end
                   DB:SetProfile(name)
                   box:SetText("")
                   EV:Print(L["Switched to profile"], EV:Colour(name))
                   EV.Options:RefreshCurrent()
               end }

        p:Section(L["Manage"])
        p:Dual(
            { type = "dropdown", text = L["Copy from"], width = 170,
              values = function() return ProfileList(true) end,
              get = function() return copyFrom end, set = function(v) copyFrom = v end },
            { type = "button", text = L["Into active profile"], label = L["Copy"], width = 110, confirm = true,
              disabled = function() return not copyFrom end,
              onClick = function()
                  if not copyFrom then return end
                  DB:CopyProfile(copyFrom)
                  EV:Print(L["Copied profile"], EV:Colour(copyFrom))
              end })
        p:Dual(
            { type = "dropdown", text = L["Delete"], width = 170,
              values = function() return ProfileList(true) end,
              get = function() return deleteName end, set = function(v) deleteName = v end },
            { type = "button", text = L["Remove it"], label = L["Delete"], width = 110, confirm = true,
              disabled = function() return not deleteName or deleteName == "Default" end,
              onClick = function()
                  if not deleteName then return end
                  if DB:DeleteProfile(deleteName) then EV:Print(L["Deleted profile"], deleteName) end
                  deleteName = nil
              end })
        p:Row{ type = "button", text = L["Reset the active profile to defaults"], label = L["Reset"], width = 110,
               confirm = true, onClick = function() DB:ResetProfile() end }

        p:Section(L["Share and back up"])
        p:Note(L["A profile string is your settings as one line of text: keep it somewhere safe, send it to someone else, or paste it back if your settings are lost."], 0.8)
        p:Dual(
            { type = "button", text = L["Copy this profile out"], label = L["Export"], width = 110,
              onClick = function()
                  local str, err = DB:ExportProfile()
                  if not str then EV:Print(L["Couldn't export:"], tostring(err)); return end
                  EV.UI.ShowCopyText(L["Export profile"] .. " - " .. DB:GetProfileName(), str,
                      L["Select all is done for you. Ctrl+C to copy."])
              end },
            { type = "button", text = L["Paste a profile in"], label = L["Import"], width = 110,
              onClick = function()
                  EV.UI.ShowPasteText(L["Import profile"],
                      L["Paste a profile string. It replaces the settings in your active profile."],
                      L["Import"], function(text)
                          local ok, info = DB:ImportProfile(text)
                          if not ok then return info end
                          EV:Print(L["Imported profile"], EV:Colour(tostring(info or "")))
                          EV.Options:RefreshCurrent()
                      end)
              end })
    end,
}
