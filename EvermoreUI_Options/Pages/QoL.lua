if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Quality of Life: the small automations, each one off until you say so.
--------------------------------------------------------------------------------
local EV = EvermoreUI
local L = EV.L

local M = EV:GetModule("QoL", true)
if not M then return end

EV.Options:RegisterPage{
    key = "qol", title = L["Quality of Life"], group = "Extras", module = "QoL",
    description = L["Repair and sell greys at a vendor, loot without clicking, take and hand in quests. Hold Shift as the window opens to skip it just that once."],
    build = function(p)
        local function Get(k) return function() return M.db[k] end end
        local function Set(k) return function(v) M.db[k] = v end end
        local function T(k, text, tip, extra)
            local cfg = { type = "toggle", text = text, tooltip = tip,
                          get = Get(k), set = Set(k) }
            if extra then for a, b in pairs(extra) do cfg[a] = b end end
            return cfg
        end

        p:Section(L["Vendor"])
        p:Dual(T("autoRepair", L["Repair on opening a vendor"]),
               T("repairFromGuild", L["Use guild funds first"],
                 L["Falls back to your own gold when the guild will not or cannot cover it."],
                 { disabled = function() return not M.db.autoRepair end }))
        p:Dual(T("autoSellJunk", L["Sell greys"],
                 L["Uses the client's own Sell All Junk, so it sells exactly what that button sells."]),
               T("announceVendor", L["Say what it did"],
                 L["One line in chat with the repair cost and what the greys fetched."]))

        local ns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_QoL"]
        local R = ns and ns.Restock
        if R then
            p:Section(L["Restock"])
            p:Dual(T("restock", L["Top up at vendors"],
                     L["Buys reagents, ammo, food and water back up to the counts below whenever a vendor sells them. Hold Shift as the window opens to skip."]), nil)
            p:Note(L["This character's list. Alt + click an item in a vendor's window to add it and choose how many (again to change or stop), or add it here."], 0.7)
            local list = R.List()
            local ids = {}
            for id in pairs(list) do ids[#ids + 1] = id end
            table.sort(ids, function(a, b) return R.Name(a) < R.Name(b) end)
            if #ids == 0 then p:Note(L["Nothing on the list yet."], 0.6) end
            local W = EV.UI
            for _, id in ipairs(ids) do
                local f = CreateFrame("Frame", nil, UIParent)
                f:SetSize(p.width - 40, 34)
                local paused = R.Paused(id)
                local icon = f:CreateTexture(nil, "ARTWORK")
                icon:SetSize(26, 26)
                icon:SetPoint("LEFT", 0, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                icon:SetTexture(R.Icon(id))
                icon:SetDesaturated(paused)

                local remove = W.Button(f, L["Remove"], 80, function()
                    R.Remove(id); if R.MarkAll then R.MarkAll() end; EV.Options:Rebuild()
                end)
                remove:SetPoint("RIGHT", 0, 0)
                local top = math.max(200, R.DefaultTarget(id) * 5)
                local amount = W.Stepper(f, 1, top, 1,
                    function() return list[id] or 1 end,
                    function(v) list[id] = v end, nil, 120)
                amount:SetPoint("RIGHT", remove, "LEFT", -10, 0)
                local on = W.Toggle(f, function() return not R.Paused(id) end,
                    function(v) R.SetPaused(id, not v); EV.Options:Rebuild() end)
                on:SetPoint("RIGHT", amount, "LEFT", -14, 0)
                on:SetTooltip(L["Restock this item"], L["Switch off to pause it without losing the amount."])

                local name = EV.Theme.Text(f, "body", paused and "textMuted" or "text")
                name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
                name:SetPoint("RIGHT", on, "LEFT", -10, 0)
                name:SetWordWrap(false)
                name:SetText(R.Name(id))
                local sub = EV.Theme.Text(f, "caption", "textMuted")
                sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, -1)
                sub:SetPoint("RIGHT", on, "LEFT", -10, 0)
                sub:SetWordWrap(false)
                sub:SetText(paused and L["Paused"] or (L["You have %d"]):format(R.Count(id)))
                if not M.db.restock then
                    on:SetDisabled(true); amount:SetAlpha(0.5); icon:SetDesaturated(true)
                end
                p:Row{ type = "custom", height = 42, build = function() return f end }
            end
            p:Row{ type = "input", text = L["Add an item"], width = 240,
                   placeholder = L["Item link, name or ID"],
                   tooltip = L["Type its name (it must be in your bags or seen recently) or its ID. Easiest of all: Alt + click it at the vendor."],
                   onCommit = function(text)
                       local id = tonumber(text) or tonumber((text or ""):match("item:(%d+)"))
                       if not id and text ~= "" and C_Item and C_Item.GetItemInfoInstant then
                           id = C_Item.GetItemInfoInstant(text)
                       end
                       if not id then
                           EV:Print(L["Couldn't find that item."])
                           return
                       end
                       list[id] = list[id] or R.DefaultTarget(id)
                       EV.Options:Rebuild()
                   end }
        end

        p:Section(L["Loot"])
        p:Dual(T("fastLoot", L["Loot everything automatically"],
                 L["Takes the loot as soon as the server has it, so the loot window usually never appears."]), nil)

        p:Section(L["Quests"])
        p:Dual(T("autoAccept", L["Accept quests"]),
               T("autoTurnIn", L["Hand in quests"],
                 L["Only when there is nothing to choose. A quest offering a choice of rewards opens as normal."]))
        p:Dual(T("skipRepeatable", L["Skip repeatables"],
                 L["Leaves dailies, weeklies and anything else flagged repeatable to you."],
                 { disabled = function() return not (M.db.autoAccept or M.db.autoTurnIn) end }),
               T("skipTrivial", L["Skip trivial quests"],
                 L["Quests below your level, shown in grey."],
                 { disabled = function() return not (M.db.autoAccept or M.db.autoTurnIn) end }))

        p:Section(L["Gossip"])
        p:Dual(T("autoGossip", L["Take a lone gossip option"],
                 L["When an NPC offers exactly one thing to say and has no quests, take it rather than clicking it. The game already does this for options its own server marks as safe, so this covers the rest."]),
               T("gossipForced", L["...even when the NPC wants its menu read"],
                 L["Some NPCs ask for their menu to be shown on purpose. This overrides that. It is where most of the remaining clicks are, and also the only place this can skip something you wanted to read."],
                 { disabled = function() return not M.db.autoGossip end }))

        p:Note(L["Holding Shift as a vendor, loot or quest window opens skips everything here for that one interaction."])

        local ns = EV._ModuleNS and EV._ModuleNS["EvermoreUI_QoL"]
        local function Apply() if ns and ns.ApplyTweaks then ns.ApplyTweaks() end end
        local function Badge() EV:SendMessage("EV_TRAINING_CHANGED", ns and ns.Training and ns.Training.count or 0) end

        p:Section(L["Training"])
        p:Dual(T("trainingNotify", L["Say what to train when you level"],
                 L["One line in chat after a level up listing the new spells your trainer has, with the cost where a trainer visit has shown it."]),
               T("trainingBadge", L["Count on the spellbook button"],
                 L["The micro menu's spellbook button shows how many spells are ready to train."],
                 { set = function(v) M.db.trainingBadge = v; Badge() end }))
        p:Dual(T("trainAllButton", L["Train All button at trainers"],
                 L["Adds a button to the class trainer that learns everything it lists as available that you can afford. Professions are left to you."]), nil)

        p:Section(L["Durability"])
        p:Dual(T("durabilityWarn", L["Warn when gear gets low"],
                 L["One line in chat when your worst item drops below the threshold, and again if anything breaks, with what the repair will cost."]),
               { type = "slider", text = L["Warn below"], min = 5, max = 75, step = 5,
                 fmt = function(v) return v .. "%" end,
                 disabled = function() return not M.db.durabilityWarn end,
                 get = Get("durabilityAt"), set = Set("durabilityAt") })

        p:Section(L["Small fixes"])
        p:Dual(T("easyDelete", L["Type DELETE for me"],
                 L["When destroying an item asks you to type DELETE, it is filled in for you. You still have to click Yes."]),
               T("maxCamera", L["Furthest camera distance"],
                 L["Sets the camera's maximum distance to the furthest the game allows. Switching this off puts your old setting back."],
                 { set = function(v) M.db.maxCamera = v; Apply() end }))
        p:Dual(T("quietErrors", L["Quieter error messages"],
                 L["Stops the red lines that repeat while you press a key too early: not ready yet, not enough energy or mana, out of range, no target. Other errors still show."],
                 { set = function(v) M.db.quietErrors = v; Apply() end }), nil)
    end,
}
