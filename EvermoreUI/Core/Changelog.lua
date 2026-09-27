if EV_BLOCKED then return end
-- Generated from CHANGELOG.md by tools/changelog/build.py. Edit the
-- changelog, not this file.
EvermoreUI.CHANGELOG = {
    {
        version = "0.12.5",
        intro = { "Your own cooldowns: the bars now take what the game's Cooldown Manager doesn't track." },
        sections = {
            { title = "New", items = {
                "**Your own icons** in the cooldown bars: a trinket slot, any item with a cooldown (potions, Healthstones, engineering gear) or a spell the game doesn't list. They drag, reorder and hide like the rest. Items show how many you carry and grey out when you have none; a trinket shows while it has a Use. Drag one from your bags or spellbook onto a row in the designer's Cooldowns tab, or press the + at the end of a row.",
                "**Bars of your own**, as many as you like, each with a name. A buff bar shows just the buffs you name, in your order: your seals on one, the raid buffs you care about on another. Pick them from the buffs on you, drag a spell onto the row, or type a name; every rank counts, and it keeps working in combat. An icon bar holds whatever you put on it: your trinkets and potions, or any cooldown dragged across from the game's bars. Each has its own size, layout and visibility, and its own place in edit mode. New bar in the designer's Cooldowns tab.",
            } },
            { title = "Fixes", items = {
                "The Buffs & Debuffs page said this client couldn't show them and hid its settings. The buffs themselves were fine; the page is back.",
                "A lone \":\" under the chat when the input box was left showing without focus. The \"Say:\" part now only shows while you type.",
            } },
        },
    },
    {
        version = "0.12.0",
        intro = { "The unit frames catch up with the rest of the suite: everything Blizzard's target and player frames used to carry, and the settings you'd expect from a full frames addon." },
        sections = {
            { title = "New", items = {
                "**Cast bars** on the player, target, focus and pet frames. Under the frame, or anywhere you like in edit mode. Spell icon, name, time left, a spark on the leading edge, grey when the cast can't be interrupted and a red \"Interrupted\" when it's cut off. Your own bar shows your latency, and replaces Blizzard's (switch that off on the Player tab).",
                "**Buffs and debuffs on your target**: everyone's debuffs above the frame, so you can see who has Sunder or a curse up and whether it's sheeped, and its buffs below, for Purge, Tranquilizing Shot or checking a friend's buffs before you rebuff. \"Only mine\" narrows either to yours. Focus, player and pet can show them too.",
                "**Combo points** above the player frame for rogues, and druids in Cat Form, and across the edge of your target's nameplate so you can read them without looking away from the mob. Size, spot and colour on the Nameplates page.",
                "**Totems** under the player frame for shamans, with the time left. Right click one to destroy it.",
                "**Fade out of combat**: the player and pet frames can fade away until you're fighting, targeting, casting, hurt, short of power or hovering them.",
                "**Copy settings** from one frame onto another.",
                "**The designer**: drag the name, health and power text, icons, portrait, cast bar, buffs and debuffs, combo points and totems into place on a live copy of any unit frame, resize them by their corner, nudge with the arrow keys. Save, Discard and undo, as in edit mode. `/evui design`, or Open designer on the Unit Frames page.",
                "**Arrange your cooldowns**: the designer's Cooldowns tab shows each bar as a row of icons. Drag to reorder, move a cooldown between the Essential and Utility bars, or drop it in the tray to hide it from our bars. Saved per class and spec; which spells are tracked stays in the game's own Cooldown Manager settings, a button away.",
                "**Design your nameplates**: the designer's Nameplates tab has a plate with a sample cast, auras, raid mark and quest count. Drag the raid mark, the quest count and each row of auras anywhere around the bar, move the mana strip and cast bar up or down, flip combo points between edges, and resize by the corner. Nothing moves until you move it.",
                "**Design your party and raid frames**: the designer's Party & Raid tab shows a sample party, or three raid groups, laid out as yours will be. Drag the name, health text, role, leader, ready check and raid mark anywhere on the first frame, and the debuff and buff rows around it, and every frame follows. Resize by the corner. Texture, border, font and colours are there too.",
                "**Everything in the designer**: every Unit Frames, Nameplates, Cooldowns and Party & Raid setting now lives in the designer, with the part it belongs to. The frame or plate as a whole (size, colours, fading, the aggro glow, threat, target highlighting, how plates move) is under Frame or Plate behaviour in its list; click a cooldown bar for its size and text, or a cooldown for its linked timer. Their options pages open the designer, and so does Frame settings in edit mode.",
            } },
            { title = "Changed", items = {
                "**More ways to style a frame**: border from 0 to 8 pixels in any colour, background colour, your own health and power colours (or power in your class colour), a font per frame, name colour and width, where the name, health and power text sit with offsets, and the size and spot of the raid mark, leader and PvP icons and your combat and resting icons.",
                "**Target of target and pet** sit a little lower by default, clear of the new cast bars and your target's buffs. Frames you've already placed stay where you put them.",
            } },
        },
    },
    {
        version = "0.11.5",
        intro = { "Small comforts while the bag addon is built." },
        sections = {
            { title = "New", items = {
                "**Bags**: all your bags in one window, split into sections: new items, gear sets, equipment, consumables, quest items, herbs, ore, leather and cloth for gatherers, trade goods and the rest, junk last. Search, sort, your gold and free space at a glance. Replaces Blizzard's bag windows.",
                "**Your own sections**: make sections with rules (item type, quality, name, tooltip text, soulbound, slot, item level, gear sets, can't be sold, item IDs), matching every rule or any. Drop an item on a section's title to keep it there. Reorder, fold and switch sections off; sort by quality, item level, name or ID; item level on gear. Interface > Bags.",
                "**Ready-made sets**: add a Gatherer, Dungeons and raids or Levelling set of sections in one click, and share your whole setup as a line of text.",
                "**Search terms**: `#herb` for a type, `ilvl>20`, `q>=rare`, `boe`, `bop`, `set`, `junk`, `new`, `quest`, `tip:use` for tooltip text, `in:gathering` for a section, `|` for or and `!` for not. Hover the search box for the list. Searching hides what doesn't match (or dims it, if you prefer).",
                "**Bank**: your bank in the same style when you visit one, with the same sections, search and sort, and your account bank alongside where the game allows. Right-click items in your bags to put them in whichever bank is showing, or use Deposit all. Buy bank tabs and move gold in and out of the account bank from the same window. The game's own bank window is a button away.",
                "**Empty a bag**: Alt + click a bag on the bag bar to move everything in it into free space in your other bags, topping up part stacks first and keeping arrows, shards and herbs in their own bags. Then swap it out.",
                "**Move Blizzard's windows**: drag the character sheet, spellbook, merchant, quest log and the rest by their title bar, and they open where you left them. Reset them all on the Quality of Life page.",
                "**The whole world map**: the parts of each zone you haven't explored yet are revealed too, as if you had. Switch it on or off on the Quality of Life page, and tint them darker there if you want to tell them apart.",
                "**Weather density**: choose how much rain, snow and dust the game draws, from low to very high, on the Quality of Life page or from the cloud next to the sun and moon on the minimap. Switching it off puts your old setting back.",
            } },
            { title = "Changed", items = {
                "**Up/Down in the chat box** remembers what you've sent through a reload or relog: your last 50 lines per window, for this character. Forget kept history on the Chat page clears them too.",
            } },
            { title = "Fixes", items = {
                "The minimap clock's tooltip shows realm and local time in your theme's text colour, not red.",
            } },
        },
    },
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
}
