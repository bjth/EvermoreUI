# EvermoreUI

A complete UI for **World of Warcraft: Forever**, built for Forever's client
rather than ported from retail. One core addon holds the settings, profiles
and shared look; each part of the UI is its own module you can switch off.

| Group | Modules |
|---|---|
| Combat | Unit Frames, Nameplates, Action Bars, Auras |
| Interface | Minimap, Objective Tracker, Data Bars, Micro Menu, Bag Bar |
| Chat & Tooltips | Chat, Tooltips |
| Extras | Window Skins, Quality of Life |

## Install

Get it from CurseForge or Wago (search "EvermoreUI"), or download the zip from
[Releases](https://github.com/bjth/EvermoreUI/releases) and unzip every
`EvermoreUI*` folder into `World of Warcraft\_classic_beta_\Interface\AddOns`.

## Using it

- `/evui` opens the options. `/evui edit` moves things around.
- Modules can be switched off under **General > Modules**. Blizzard's own
  frames come back after a reload.
- `/evui export` and `/evui import` share or back up a profile as a string.

## Found a bug? Got an idea?

Type **/evui bug** in game, copy what it shows, and paste it into a
[new issue](https://github.com/bjth/EvermoreUI/issues/new/choose). It carries
your version, modules, other addons and recent errors, so we can get straight
to the fix. Ideas and "this annoys me" are just as welcome.

---

# Development

## Setup

```powershell
cd C:\Development\Addons\EvermoreUI
.\tools\link.ps1                    # junctions into _classic_beta_
.\tools\link.ps1 -Flavour _retail_  # optional: live retail as a second test bed
```

In game: `/evui` options, `/evui caps` client report, `/evui unlock` movers,
`/evui profile [name]`, `/evui modules`.

## Writing a module

1. New folder `EvermoreUI_Thing` with a TOC carrying `## Dependencies: EvermoreUI`
   and no SavedVariables.
2. Line 1 of every file: `if EV_BLOCKED then return end`.
3. `local M = EvermoreUI:NewModule("Thing", defaults)`; implement `OnEnable`,
   `OnProfileChanged`, and a `Refresh` the options page can call.
4. Options page goes in `EvermoreUI_Options/Pages/Thing.lua`, listed in that TOC.
5. Add the folder to `.pkgmeta` and rerun `tools\link.ps1`.

## Rules

- Feature-detect, never gate on build or interface number (Forever is 16001 on
  the retail codebase).
- Never write fields onto Blizzard frames; keep state in weak-keyed side tables.
- No vendored libraries unless there's no sane alternative.
