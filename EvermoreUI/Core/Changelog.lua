if EV_BLOCKED then return end
-- Generated from CHANGELOG.md by tools/changelog/build.py. Edit the
-- changelog, not this file.
EvermoreUI.CHANGELOG = {
    {
        version = "0.11.0",
        intro = { "Party and raid frames, just in time for dungeons." },
        sections = {
            { title = "New", items = {
                "**Party and raid frames**: in the same style as your unit frames, sorted and kept up to date by the game's own group headers, so they follow roster changes in combat. Role, leader and ready check icons, a fade when someone is out of range, an aggro glow, incoming heals, and the debuffs you can remove. Healers can add their own buffs and heals over time too. Combat > Party & Raid.",
                "**Order and layout**: party frames can run in any direction and sort by group, role or name; raid frames sit in groups side by side or stacked, by group, role or class. Use the raid frames for your party too if you like.",
                "**Preview**: stand-in frames to place and size them before you have a group.",
                "**Click casting** works on party and raid frames.",
                "**Cooldowns**: your cooldowns and the buffs they leave, in EvermoreUI bars. Built on the game's own Cooldown Manager, so it keeps working in combat: square icons, your fonts, size, spacing, rows and direction per bar, and show always, faded, or only in combat. Keybinds and spell ranks on the icons, found from your action bars and macros. Move them with /evui edit. Combat > Cooldowns.",
                "**Linked timers**: a countdown over a cooldown's icon for a set time after you cast it. Priests start with Power Word: Shield counting down Weakened Soul's 15 seconds; add your own on the Cooldowns page.",
            } },
            { title = "Changed", items = {
                "**Aura trackers are gone**, replaced by Cooldowns. Choose the buffs you want to watch in the game's Cooldown Manager settings (there's a button on the Cooldowns page) and they appear in the Tracked buffs bar. Your movable buffs and debuffs, and Reminders, are unchanged; their page is now called Buffs & Debuffs.",
            } },
        },
    },
    {
        version = "0.10.1",
        intro = { "The little things that make a classic evening smoother: bags that stay stocked, a nudge when a buff drops, and tidier group windows." },
        sections = {
            { title = "New", items = {
                "**Restock**: keep reagents, ammo, food and water topped up. Alt + click an item at a vendor to add it to this character's list, set how many you want to carry, and we buy the difference every time. Extras > Quality of Life.",
                "**Reminders**: icons for the class buffs you're missing, a poison or imbue that has worn off, and food in dungeons. Click one to cast the buff, apply the poison or eat. Hidden in combat. The list is yours to edit: reorder it, switch things off, or add your own flasks, elixirs and anything you're wearing right now. Combat > Reminders.",
                "**Loot rolls**: need, greed and pass rows in the EvermoreUI style, movable with `/evui edit`. Interface > Group has a test roll for placing them.",
                "**Ready check**: a prompt that matches the rest of the UI, with a sound and a taskbar flash, and a line in chat afterwards saying who wasn't ready.",
                "**Loot luck**: every need, greed and pass is counted, by quality, for each of your characters, and `/evui luck` ranks them by how often they win. Find out which of your alts the dice love.",
            } },
            { title = "Fixes", items = {
                "The action bar editor's spell list now shows spells you haven't learnt yet, greyed out with the level they arrive at.",
                "Repairs no longer claim guild funds paid when you aren't in a guild.",
                "The spell count on the micro menu works again. Forever no longer lists unlearnt spells in the spellbook, so the count now comes from what your class trainer lists; visit one once and every character of that class benefits. Hover the spellbook button to see what's ready, with prices, and what arrives at your next level.",
                "Train All sits neatly between the money and Train buttons.",
                "Alt + clicking an item to restock now asks how many to carry, with a full stack filled in. Alt + click it again to change the amount or stop.",
                "The restock list on the Quality of Life page shows each item with its icon and how many you have, and each can be paused without losing its amount.",
                "Nameplate cast targets and class-coloured player health no longer error.",
                "Swing timer rows no longer throw \"Font not set\" errors.",
                "Hovering durability on the data bar no longer errors.",
                "The Well Fed reminder only shows when you have food that gives it, and clicking it eats that food. Any reminder can do the same with \"Only when I carry something for it\".",
                "Unit frames no longer error on class colours in dungeons.",
            } },
        },
    },
    {
        version = "0.10.0",
        intro = { "A big one for classic players: training reminders, a swing timer, energy ticks, and action bars you can set up without ever leaving the options." },
        sections = {
            { title = "New", items = {
                "**Training**: a badge on the spellbook button when you have spells to learn, a line in chat when you level, and a Train All button at your trainer.",
                "**Swing timer**: main hand, off hand and ranged bars, built on Forever's own swing events. Combat > Swing Timer.",
                "**Energy ticks and the five-second rule**: a strip on your power bar timing the next tick, and a preview of what it will add.",
                "**Click casting**: Shift + click (and friends) on your unit frames casts on that unit, in combat too. Combat > Click Casting.",
                "**Colours**: your own palette for class, hostility, power, threat, cast bars and the interface itself, and a string to share it. General > Colours.",
                "**Durability**: a warning in chat when your gear runs low, and a readout on Data Bars with the repair cost.",
                "**Sell prices** in item tooltips, with the price of one item on a stack.",
                "**Reagent and ammo counts** on your action buttons.",
                "**Pet happiness** on the pet frame.",
                "**Small fixes**, all off until you want them: easy delete, maximum camera distance and fewer red error messages. Extras > Quality of Life.",
                "**What's new**: this window. It shows once after each update, and `/evui new` brings it back.",
            } },
            { title = "Action bars", items = {
                "**Bar editor**: pick a bar in the options and edit it right there. Drag spells on from the spellbook, swap buttons, clear them and bind keys.",
                "**Keybind mode**: hover a button and press a key. `/evui kb`.",
                "**Paging**: Alt, Ctrl and Shift pages, a fixed page per bar, or your own conditions.",
                "**Modifier actions**: give a button a second job, like Alt + click to cast it on yourself.",
                "**Right click self cast**, and the game's self cast, focus cast, button lock and spell queue settings all in one place.",
                "**Spell rank** text on each bar, placed and coloured how you like.",
                "Growth direction, scale, opacity, fade groups, text per bar, short keybind names, red icons out of range and an edge on equipped items.",
            } },
            { title = "Improvements", items = {
                "Chat keeps each window's last lines through a reload.",
                "Fast loot is properly instant now.",
                "Spellbook: tidier school tabs, and an option to hide the parchment.",
                "The flight map is skinned.",
                "The nameplate pixel check has moved out of your login chat and into `/evui bug`.",
            } },
        },
    },
    {
        version = "0.9.0",
        intro = { "First public release. Everything below has been played on Forever's beta throughout development; expect rough edges and please report them with `/evui bug`." },
        sections = {
            { title = "", items = {
                "**Unit Frames**: clean, resizable player, target, target of target, focus and pet frames.",
                "**Nameplates**: our own plates on Blizzard's: health, cast, your dots with timers, threat colouring and target highlighting. Targeting stays Blizzard's.",
                "**Action Bars**: Blizzard's buttons in EvermoreUI bars, with our layout, look, fading and movers. Paging, keybinds and casting are still Blizzard's.",
                "**Auras**: movable buffs and debuffs, plus trackers for seals, aspects, shouts and the like.",
                "**Minimap**: square, with zone, clock, coordinates and buttons around it.",
                "**Objective Tracker**: your quests in our own panel, with levelling extras.",
                "**Data Bars**: experience with quest and rested segments, XP/hour, time to level and session stats.",
                "**Micro Menu and Bag Bar**: flat glyph micro menu, bag bar with free slots.",
                "**Chat**: a clean chat panel with sidebar, idle fade, timestamps, short channel names, clickable links and copy.",
                "**Tooltips**: tooltips and right-click menus in the EvermoreUI style, with class colours, item level, quality borders and a movable or cursor anchor.",
                "**Window Skins**: Blizzard's own windows in the EvermoreUI palette, their layout untouched.",
                "**Quality of Life**: auto repair, sell greys, fast loot, quest accept and hand-in. Hold Shift to skip.",
                "Profiles, profile strings (`/evui export`, `/evui import`), pixel-perfect scaling and a full Edit Mode (`/evui edit`).",
                "`/evui bug` builds a report to paste into GitHub issues.",
            } },
        },
    },
}
