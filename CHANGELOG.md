# EvermoreUI

## 0.12.0

The unit frames catch up with the rest of the suite: everything Blizzard's
target and player frames used to carry, and the settings you'd expect from a
full frames addon.

### New
- **Cast bars** on the player, target, focus and pet frames. Under the
  frame, or anywhere you like in edit mode. Spell icon, name, time left,
  a spark on the leading edge, grey when the cast can't be interrupted and a
  red "Interrupted" when it's cut off. Your own bar shows your latency, and
  replaces Blizzard's (switch that off on the Player tab).
- **Buffs and debuffs on your target**: everyone's debuffs above the frame,
  so you can see who has Sunder or a curse up and whether it's sheeped, and
  its buffs below, for Purge, Tranquilizing Shot or checking a friend's
  buffs before you rebuff. "Only mine" narrows either to yours. Focus,
  player and pet can show them too.
- **Combo points** above the player frame for rogues, and druids in Cat
  Form, and across the edge of your target's nameplate so you can read them
  without looking away from the mob. Size, spot and colour on the
  Nameplates page.
- **Totems** under the player frame for shamans, with the time left. Right
  click one to destroy it.
- **Fade out of combat**: the player and pet frames can fade away until
  you're fighting, targeting, casting, hurt, short of power or hovering
  them.
- **Copy settings** from one frame onto another.
- **The designer**: drag the name, health and power text, icons, portrait,
  cast bar, buffs and debuffs, combo points and totems into place on a live
  copy of any unit frame, resize them by their corner, nudge with the arrow
  keys. Save, Discard and undo, as in edit mode. `/evui design`, or Open
  designer on the Unit Frames page.

### Changed
- **More ways to style a frame**: border from 0 to 8 pixels in any colour,
  background colour, your own health and power colours (or power in your
  class colour), a font per frame, name colour and width, where the name,
  health and power text sit with offsets, and the size and spot of the raid
  mark, leader and PvP icons and your combat and resting icons.
- **Target of target and pet** sit a little lower by default, clear of the
  new cast bars and your target's buffs. Frames you've already placed stay
  where you put them.

## 0.11.5

Small comforts while the bag addon is built.

### New
- **Bags**: all your bags in one window, split into sections: new items,
  gear sets, equipment, consumables, quest items, herbs, ore, leather and
  cloth for gatherers, trade goods and the rest, junk last. Search, sort,
  your gold and free space at a glance. Replaces Blizzard's bag windows.
- **Your own sections**: make sections with rules (item type, quality,
  name, tooltip text, soulbound, slot, item level, gear sets, can't be
  sold, item IDs), matching every rule or any. Drop an item on a section's
  title to keep it there. Reorder, fold and switch sections off; sort by
  quality, item level, name or ID; item level on gear. Interface > Bags.
- **Ready-made sets**: add a Gatherer, Dungeons and raids or Levelling set
  of sections in one click, and share your whole setup as a line of text.
- **Search terms**: `#herb` for a type, `ilvl>20`, `q>=rare`, `boe`, `bop`,
  `set`, `junk`, `new`, `quest`, `tip:use` for tooltip text, `in:gathering`
  for a section, `|` for or and `!` for not. Hover the search box for the
  list. Searching hides what doesn't match (or dims it, if you prefer).
- **Bank**: your bank in the same style when you visit one, with the same
  sections, search and sort, and your account bank alongside where the game
  allows. Right-click items in your bags to put them in whichever bank is
  showing, or use Deposit all. Buy bank tabs and move gold in and out of
  the account bank from the same window. The game's own bank window is a
  button away.
- **Empty a bag**: Alt + click a bag on the bag bar to move everything in
  it into free space in your other bags, topping up part stacks first and
  keeping arrows, shards and herbs in their own bags. Then swap it out.
- **Move Blizzard's windows**: drag the character sheet, spellbook,
  merchant, quest log and the rest by their title bar, and they open where
  you left them. Reset them all on the Quality of Life page.
- **The whole world map**: the parts of each zone you haven't explored yet
  are revealed too, as if you had. Tint them darker on the Quality of Life
  page if you want to tell them apart; switch it off on the Modules page.

## 0.11.0

Party and raid frames, just in time for dungeons.

### New
- **Party and raid frames**: in the same style as your unit frames, sorted
  and kept up to date by the game's own group headers, so they follow roster
  changes in combat. Role, leader and ready check icons, a fade when someone
  is out of range, an aggro glow, incoming heals, and the debuffs you can
  remove. Healers can add their own buffs and heals over time too.
  Combat > Party & Raid.
- **Order and layout**: party frames can run in any direction and sort by
  group, role or name; raid frames sit in groups side by side or stacked, by
  group, role or class. Use the raid frames for your party too if you like.
- **Preview**: stand-in frames to place and size them before you have a group.
- **Click casting** works on party and raid frames.
- **Cooldowns**: your cooldowns and the buffs they leave, in EvermoreUI
  bars. Built on the game's own Cooldown Manager, so it keeps working in
  combat: square icons, your fonts, size, spacing, rows and direction per
  bar, and show always, faded, or only in combat. Keybinds and spell ranks
  on the icons, found from your action bars and macros. Move them with
  /evui edit. Combat > Cooldowns.
- **Linked timers**: a countdown over a cooldown's icon for a set time after
  you cast it. Priests start with Power Word: Shield counting down Weakened
  Soul's 15 seconds; add your own on the Cooldowns page.

### Changed
- **Aura trackers are gone**, replaced by Cooldowns. Choose the buffs you
  want to watch in the game's Cooldown Manager settings (there's a button on
  the Cooldowns page) and they appear in the Tracked buffs bar. Your movable
  buffs and debuffs, and Reminders, are unchanged; their page is now called
  Buffs & Debuffs.

## 0.10.1

The little things that make a classic evening smoother: bags that stay
stocked, a nudge when a buff drops, and tidier group windows.

### New
- **Restock**: keep reagents, ammo, food and water topped up. Alt + click an
  item at a vendor to add it to this character's list, set how many you want
  to carry, and we buy the difference every time. Extras > Quality of Life.
- **Reminders**: icons for the class buffs you're missing, a poison or imbue
  that has worn off, and food in dungeons. Click one to cast the buff, apply
  the poison or eat. Hidden in combat. The list is yours to edit: reorder it,
  switch things off, or add your own flasks, elixirs and anything you're
  wearing right now. Combat > Reminders.
- **Loot rolls**: need, greed and pass rows in the EvermoreUI style, movable
  with `/evui edit`. Interface > Group has a test roll for placing them.
- **Ready check**: a prompt that matches the rest of the UI, with a sound and
  a taskbar flash, and a line in chat afterwards saying who wasn't ready.
- **Loot luck**: every need, greed and pass is counted, by quality, for each
  of your characters, and `/evui luck` ranks them by how often they win. Find
  out which of your alts the dice love.

### Fixes
- The action bar editor's spell list now shows spells you haven't learnt
  yet, greyed out with the level they arrive at.
- Repairs no longer claim guild funds paid when you aren't in a guild.
- The spell count on the micro menu works again. Forever no longer lists
  unlearnt spells in the spellbook, so the count now comes from what your
  class trainer lists; visit one once and every character of that class
  benefits. Hover the spellbook button to see what's ready, with prices,
  and what arrives at your next level.
- Train All sits neatly between the money and Train buttons.
- Alt + clicking an item to restock now asks how many to carry, with a
  full stack filled in. Alt + click it again to change the amount or stop.
- The restock list on the Quality of Life page shows each item with its
  icon and how many you have, and each can be paused without losing its
  amount.
- Nameplate cast targets and class-coloured player health no longer error.
- Swing timer rows no longer throw "Font not set" errors.
- Hovering durability on the data bar no longer errors.
- The Well Fed reminder only shows when you have food that gives it, and
  clicking it eats that food. Any reminder can do the same with "Only when
  I carry something for it".
- Unit frames no longer error on class colours in dungeons.

## 0.10.0

A big one for classic players: training reminders, a swing timer, energy
ticks, and action bars you can set up without ever leaving the options.

### New
- **Training**: a badge on the spellbook button when you have spells to learn,
  a line in chat when you level, and a Train All button at your trainer.
- **Swing timer**: main hand, off hand and ranged bars, built on Forever's own
  swing events. Combat > Swing Timer.
- **Energy ticks and the five-second rule**: a strip on your power bar timing
  the next tick, and a preview of what it will add.
- **Click casting**: Shift + click (and friends) on your unit frames casts on
  that unit, in combat too. Combat > Click Casting.
- **Colours**: your own palette for class, hostility, power, threat, cast bars
  and the interface itself, and a string to share it. General > Colours.
- **Durability**: a warning in chat when your gear runs low, and a readout on
  Data Bars with the repair cost.
- **Sell prices** in item tooltips, with the price of one item on a stack.
- **Reagent and ammo counts** on your action buttons.
- **Pet happiness** on the pet frame.
- **Small fixes**, all off until you want them: easy delete, maximum camera
  distance and fewer red error messages. Extras > Quality of Life.
- **What's new**: this window. It shows once after each update, and
  `/evui new` brings it back.

### Action bars
- **Bar editor**: pick a bar in the options and edit it right there. Drag
  spells on from the spellbook, swap buttons, clear them and bind keys.
- **Keybind mode**: hover a button and press a key. `/evui kb`.
- **Paging**: Alt, Ctrl and Shift pages, a fixed page per bar, or your own
  conditions.
- **Modifier actions**: give a button a second job, like Alt + click to cast
  it on yourself.
- **Right click self cast**, and the game's self cast, focus cast, button lock
  and spell queue settings all in one place.
- **Spell rank** text on each bar, placed and coloured how you like.
- Growth direction, scale, opacity, fade groups, text per bar, short keybind
  names, red icons out of range and an edge on equipped items.

### Improvements
- Chat keeps each window's last lines through a reload.
- Fast loot is properly instant now.
- Spellbook: tidier school tabs, and an option to hide the parchment.
- The flight map is skinned.
- The nameplate pixel check has moved out of your login chat and into
  `/evui bug`.

## 0.9.0

First public release. Everything below has been played on Forever's beta
throughout development; expect rough edges and please report them with
`/evui bug`.

- **Unit Frames**: clean, resizable player, target, target of target, focus
  and pet frames.
- **Nameplates**: our own plates on Blizzard's: health, cast, your dots with
  timers, threat colouring and target highlighting. Targeting stays Blizzard's.
- **Action Bars**: Blizzard's buttons in EvermoreUI bars, with our layout,
  look, fading and movers. Paging, keybinds and casting are still Blizzard's.
- **Auras**: movable buffs and debuffs, plus trackers for seals, aspects,
  shouts and the like.
- **Minimap**: square, with zone, clock, coordinates and buttons around it.
- **Objective Tracker**: your quests in our own panel, with levelling extras.
- **Data Bars**: experience with quest and rested segments, XP/hour, time to
  level and session stats.
- **Micro Menu and Bag Bar**: flat glyph micro menu, bag bar with free slots.
- **Chat**: a clean chat panel with sidebar, idle fade, timestamps, short
  channel names, clickable links and copy.
- **Tooltips**: tooltips and right-click menus in the EvermoreUI style, with
  class colours, item level, quality borders and a movable or cursor anchor.
- **Window Skins**: Blizzard's own windows in the EvermoreUI palette, their
  layout untouched.
- **Quality of Life**: auto repair, sell greys, fast loot, quest accept and
  hand-in. Hold Shift to skip.
- Profiles, profile strings (`/evui export`, `/evui import`), pixel-perfect
  scaling and a full Edit Mode (`/evui edit`).
- `/evui bug` builds a report to paste into GitHub issues.
