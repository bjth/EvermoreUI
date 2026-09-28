if EV_BLOCKED then return end
-- Generated from CHANGELOG.md by tools/changelog/build.py. Edit the
-- changelog, not this file.
EvermoreUI.CHANGELOG = {
    {
        version = "0.13.5",
        intro = { "A pass over the windows you open most, to the standard the spellbook and character window set: no boxes inside boxes, controls on a tool bar or a footer, and cards and rows in our look." },
        sections = {
            { title = "New", items = {
                "**Tracked recipes in the objective tracker**: a Professions section of its own beside Quests, folding the same way, with a heading for each profession and each recipe as a row.",
            } },
            { title = "Changed", items = {
                "**Settings**, Blizzard's options window: a title band, the search on a tool bar, Close and Apply on a footer, rows in body text and thin sliders. The Graphics page's quality box and advanced rows are tidied.",
                "**Talents**: the spec tabs, search, options and unspent points on a tool bar under the title, the points in green while you have some to spend. Apply and reset sit on a footer, and the tree headings are flat.",
                "**World map and quest log**: the search, quest count and options on one line, the map's corner controls clear of its edges, and quest details that fit the window, with Back on the tool bar and the buttons on a footer. Rewards are cards, each icon edged in the item's quality.",
                "**Quest givers, gossip and guild charters** share one layout: the text straight under the title with no box round it and the buttons on a footer. Gossip options get a flat highlight, and the reward you pick shows in copper.",
                "**Inspect** is laid out like the character window, with the level and class in the title bar.",
                "**Character window**: Character, Equipment Manager and Pet are text tabs on a short band, the lists beside the model share one inset, and your level and class are in the title bar.",
                "**Class trainer**: the filter on a tool bar, your money, Train and Train all on a footer, and each spell a card with our icons. The one you've picked is copper, and anything you can't learn yet has a red edge.",
                "**Merchant**: items are cards with the icon in its own colours, and a red edge on what you can't use or can't buy. Empty slots are ours, the repair and sell junk buttons are in the icon style, and your money sits on the footer.",
                "**Loot**: one row per item with no boxes, the icon and name side by side, and a red bar on anything being rolled for.",
                "**Mail**: letters are rows you can click anywhere along, with the pager and Open All on a footer. Send Mail has a box round the message and its buttons on a footer. Letters and invoices lose the stationery, and attachments sit clear of the buttons.",
                "**Zone map** (Shift+M): no border, just our backdrop, which follows the map's opacity setting, with a flat tab. The opacity pop-up is in our style too.",
                "**Red is redder**, so warnings and things you can't do read apart from the copper.",
                "**No shadows round windows.** The edge does the job, without the points the shadow drew in each corner.",
                "Blizzard's older sliders use our slider.",
            } },
            { title = "Fixes", items = {
                "A border could lose a side, draw one a pixel too thick, or have a corner stand a pixel proud, depending on where its window sat on screen.",
                "A dropdown's label sat high on a taller button.",
                "Opening the Equipment Manager moved the character window's tabs and left a gap under them.",
            } },
        },
    },
    {
        version = "0.13.1",
        intro = { "A swing timer that keeps up with what actually happens to your swing." },
        sections = {
            { title = "New", items = {
                "**Parry haste and haste mid-swing** on the swing timer. Forever doesn't document either rule, so each one only moves the bar once your own swings have confirmed it twice in a row; until then, and after any swing that goes against it, the bar keeps Blizzard's timing. The Swing Timer page shows where each rule stands, and either can be switched off.",
                "**Global cooldown shading**: the part of the swing your global cooldown still covers, so you can see whether there's time for another ability before the swing lands. On by default.",
                "**Latency zone**: the end of each swing tinted by your latency, the stretch where anything you press arrives after the swing has gone. Off by default.",
                "**Auto attack off**: the main hand bar says so when you're in combat, within reach of something hostile, and not attacking it.",
                "**The swing timer stops when you do.** When your target dies or you stop attacking, the bar goes at once instead of running out the swing. Attack again before that swing would have landed and it comes back where the swing really is. Ranged bars follow Shoot, Auto Shot and Throw. Can be switched off on the Swing Timer page.",
            } },
            { title = "Fixes", items = {
                "Swapping weapons now restarts the swing at the new weapon's speed, as the game does, even in combat when the speed can't be read.",
                "The swing timer could stop dimming when your target was out of reach, after hiding Blizzard's own timer switched the range check off.",
            } },
        },
    },
    {
        version = "0.13.0",
        intro = { "Built around how Forever plays: a setup that gets you going in a minute, every character's bags, bank and gold from any of them, the built-in damage meter in our style, and cooldown icons that tell you more." },
        sections = {
            { title = "New", items = {
                "**Setup.** The first time you log in, a short walkthrough: whether this character shares its setup with your others, contrast, font and size, which modules to use, a starting layout for tanking, healing or damage, and the everyday conveniences. Nothing moves until you press Use this layout, and Undo puts it back. Your settings are all kept if you've used EvermoreUI before. /evui install runs it again. Tell us how it went on the Discord: setup is the part we most want feedback on.",
                "**Characters** (/evui alts). Every character's gold, rested XP, professions and when you last played them, side by side, with the total at the foot. Browse any character's bags, bank or mail, or the account bank, from any other. Find an item across all of them by name. Items you mail to your own characters count straight away. Mail about to run out gets a line in chat at login.",
                "**Item counts in tooltips**: how many each of your characters has, and where (bags, bank, mail, equipped), plus the account bank.",
                "**A gold readout** on the Data Bars, off by default: this character's gold or everyone's, with every character's on hover.",
                "**The damage meter**, Forever's built-in one, in our style: title bar, surface, flat bars and our font. Its own settings keep working. Window Skins page, or setup.",
                "**Cooldown icons**, all in the designer:",
                "**Icon look**: border thickness and colour (theme, gold, class), crop and how dark the cooldown sweep is.",
                "**Procs**: when the game lights a spell up, a pulsing or solid border of ours, Blizzard's glow sized to our square icons, or nothing.",
                "**Reactive abilities** glow while they're usable: Overpower, Revenge, Execute, Riposte, Counterattack, Mongoose Bite and Hammer of Wrath to start with, and any cooldown can be switched on.",
                "**Refresh window**: a tracked buff or debuff lights up for its last part (30% by default) or last few seconds, so you know when re-casting wastes nothing. Works in combat.",
            } },
            { title = "Changed", items = {
                "**One icon style for everything** (General > Icons): how much of each icon's baked-in edge is cropped, how thick its border is and what colour it rests in, set once and used by every icon EvermoreUI draws or skins: action bars, bags, auras on your frames and nameplates, buff reminders, quest items, loot rolls, the cooldown manager, and Blizzard's own windows (character, spellbook, merchant, loot, mail). An edge that means something keeps its colour: an item's quality, a debuff you can dispel, a reminder. The cooldown manager follows it unless you give it its own.",
                "**One look for every control.** Our buttons, boxes, tabs, lists and scroll bars, and Blizzard's own once skinned, now come from the same recipe, so a skinned window's buttons match ours in every state. Close buttons turn red on hover, the selected tab and window titles are gold, a greyed-out control shows it in its own colours rather than fading, and icon wells on the action bars, bags and quest items are all the same.",
                "**Windows open without a stutter.** Skinning a window as it opens does far less work than it did, and a large one, like professions or the auction house, is spread over a few frames instead of done all at once. Windows skinned in the background after you log in share the same small allowance each frame. Lists that rebuild themselves, after a sort or a filter, keep their look.",
                "**The spellbook, redone.** The school tabs, the search box and the filter button sit on a tool bar under the title, all the same height; each spell is a card, with passives a step quieter and spells not yet learned dimmed; the pager has a footer of its own with flat arrows. The pulsing glow and the sweep over every icon are gone: a spell on none of your bars has a small copper mark in its corner instead.",
                "**The character window, redone.** Stat groups are a gold heading between two rules instead of a box each. The stats, titles and sets buttons and your level sit on a band at the top of the pane. The model's backdrop stays inside the window. The tabs down the side are compact squares. The tabs beside each slot are slim, flat, with an arrow, and their list has a plain panel. New Set, Equip and Save are one set of buttons with room between them; titles and equipment sets are rows and cards in our look.",
                "**Reputation, Skills, Currency and Statistics**: flat group headers with an arrow, flat progress bars in a well, a copper highlight on the row you've picked, and the detail pane's rule in our colours.",
                "**Professions.** The skill bar sits on a tool bar under the title, flat copper in a well. The recipe list and the recipe sit side by side with one line between them, no boxes. The list has its search box and a proper filter button on one line, and plain rows with a copper highlight for the recipe you've picked (recipe colours still show how hard each one is). Create All, the count and Create are one group on a footer across the bottom, with the count centred. The profession tabs down the side match the character window's. Reagent and result icons use the icon style. The overview's cards are plain cards, their spells in the icon style and Unlearn a small red cross button, which now also sits beside the skill bar on a primary profession's own page.",
                "**Pop-ups** (confirming an unlearn, deleting an item, naming a set) are a plain window with our buttons, the one that confirms in copper, and a proper box round the text field.",
                "**Text on a control always reads.** Where a button's colour and its label would be too close, the label switches to light or dark to suit, and dark text drops the shadow that smeared it.",
                "**Page arrows** in every window that uses the spellbook's (mail, the merchant, collections) are flat buttons with a chevron.",
            } },
            { title = "Fixes", items = {
                "Parts of the options window and edit mode could stop following a contrast or colour change partway through a session, until a reload.",
            } },
        },
    },
    {
        version = "0.12.5",
        intro = { "Your own cooldowns: the bars now take what the game's Cooldown Manager doesn't track." },
        sections = {
            { title = "New", items = {
                "**Your own icons** in the cooldown bars: a trinket slot, any item with a cooldown (potions, Healthstones, engineering gear) or a spell the game doesn't list. They drag, reorder and hide like the rest. Items show how many you carry and grey out when you have none; a trinket shows while it has a Use. Drag one from your bags or spellbook onto a row in the designer's Cooldowns tab, or press the + at the end of a row.",
                "**Bars of your own**, as many as you like, each with a name. A buff bar shows just the buffs you name, in your order: your seals on one, the raid buffs you care about on another. Pick them from the buffs on you, drag a spell onto the row, or type a name; every rank counts, and it keeps working in combat. An icon bar holds whatever you put on it: your trinkets and potions, or any cooldown dragged across from the game's bars. Each has its own size, layout and visibility, and its own place in edit mode. New bar in the designer's Cooldowns tab.",
            } },
            { title = "Changed", items = {
                "**A new icon**: a copper E, in the addon list and on the project page.",
            } },
            { title = "Fixes", items = {
                "The Buffs & Debuffs page said this client couldn't show them and hid its settings. The buffs themselves were fine; the page is back.",
                "A lone \":\" under the chat when the input box was left showing without focus. The \"Say:\" part now only shows while you type.",
                "Channel names in the chat input no longer end in \"::\".",
                "The experience bar's session time starts again when you log in; it could run on from the day before. A /reload still carries it on.",
                "The sample party and raid frames in the designer showed the empty part of each health bar white.",
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
}
