# EvermoreUI tools

None of this ships: the packager ignores `tools/`. The survey needs Python
3.8+, standard library only.

There is no simulator. It was removed on 21 Sep 2026: it was slow, it drifted
out of step with the addon (it had been asserting against `S.skinned`, an API
that stopped existing in the skins rewrite, so it errored part way through and
silently stopped running the tests after it), and a `/reload` in game tells you
the truth in about the same wall time. Test in game.

## The survey

`python tools/survey/survey.py`

It reads Blizzard's exported interface code and answers one question: **what
is worth skinning next.**

1. In game: `/console ExportInterfaceFiles code`. That writes Blizzard's source
   to `<WoW>\_classic_beta_\BlizzardInterfaceCode`. Put the path in
   `tools/survey/config.json`.
2. Run the survey. It writes:
   - `tools/survey/manifests/camelot.json`, everything the client loads
     (addons, frames, templates, font objects, colour globals). The previous
     one is kept as `.prev.json`.
   - `tools/survey/report.md`, which is the part you actually read.
3. `--check` analyses without writing. `--detect` lists the game types named in
   the export, for when Blizzard renames or drops `camelot`. `--top N` changes
   how many templates the coverage table covers (default 60).

The survey writes no Lua. It used to generate `EvermoreUI_Skins/Data/Generated.lua`
and a set of simulator mocks; both the generated-rules generation of the skins
addon and the simulator are gone. Parts are written by hand.

### Reading the coverage report

Coverage is **measured, not claimed**. `evsurvey/fingerprint.py` resolves every
template's inheritance into its effective shape (object type, parent keys,
the art on each named region, its `layoutType`) and then runs the actual
fingerprints from `Parts.lua` against all 2,937 of them. The report says which
part claims each template, in registration order, exactly as `S.Dress` would.

That catches the two things a hand-maintained list never will:

- **a part that matches nothing.** On 21 Sep this found `inset` and
  `dialogBorder` claiming zero templates between them, 93 and 80 inherit sites
  respectively, because both fingerprinted an atlas pattern against a file
  texture. They had been dead since they were written.
- **a part that claims what it should not.** The same run found `window`,
  fingerprinted on `keys = { "NineSlice" }` alone, claiming 106 templates
  across 398 sites: every tooltip, every inset, sliders, the chat config
  boxes, the auction house panels.

The template table's third column reads:

| column | meaning |
| --- | --- |
| `part <name>` | that part's fingerprint claims it |
| `font role` | `Fonts.lua` restyles it as a shared font object |
| `no art` | a pure layout or behaviour mixin, nothing to skin |
| `login screen` | `Glue*`, where addons never load |
| **nothing** | a candidate for the next part |

`fingerprint.py` mirrors `Parts.lua` by hand, so it can drift. The report
compares the two lists and says so when it has. Keep them in step.

The report also **lints `Parts.lua` the way `S.Register` does**: every part
must carry a real fingerprint, and `type` alone is not one. This is checked
offline as well as at runtime because the runtime assert fires at LOAD and
aborts Parts.lua's main chunk, so every part registered after the offender
never registers at all and the skin library goes quiet with no clue why. That
happened on 21 Sep: `slider` was registered with `type = "Slider"` and nothing
else, and took the other 17 parts down with it.

`type` alone is never enough, and `Slider` is the example worth remembering:
11 of this client's 18 `Slider` templates are scroll bars, because classic
implements scroll bars as Sliders. A real slider attaches its thumb as
`Thumb`, a scroll bar as `ThumbTexture`, and never both.

The model is honest about its limits: it reads Blizzard's XML, so it sees
templates and inheritance, not frames built in Lua at runtime. A template it
reports as matched will be claimed in game; one it reports as unmatched may
still be claimed if Lua adds the missing key later.

## Growing coverage, in order of preference

1. **An atlas pattern in `S.ORNATE`** (`Parts.lua`). Applies to every window
   at once.
2. **A file path in `S.ORNATE_FILES`.** Same reach, for chrome drawn from a
   file rather than an atlas. Curate it: a path there mutes every texture
   drawn from that sheet, so never add a bar fill, an icon sheet or an item
   slot.
3. **A new part.** For a Blizzard template nothing claims yet. Give it a real
   fingerprint: `layout` (Blizzard's own `layoutType`) is the best one
   available, then `keys`, then art. Add it to `fingerprint.py` in the same
   commit.
4. **A window pack** (`WindowPacks.lua`), last. Only for a window's own art,
   or a fix that needs a decision about layout. A pattern in the lists above
   is worth ten packs.

## Packs

A pack is written against one named window by someone who opened it and
looked, and that is what buys it the right to move things. Parts get a
`Painter`, which has no `SetPoint`, `SetSize` or `SetParent`; packs get a
`Kit`, which has those plus `Move`, `Nudge`, `Size`, `Row` and `Restore`, all
combat-guarded and idempotent. The rule is not "never move anything", it is
**nothing that matches by guess may move anything**.

## When a window still looks wrong in game

- `/evui skin` lists the registered parts, the ornate atlas and file counts,
  the registered window packs, and anything that has thrown.
- `/evui skin this` with the mouse over the window: what the parts claimed, and
  every texture still on screen that no part and no ornate pattern accounted
  for, with its atlas name. That loose list is how coverage grows.
- `/evui reskin` re-sweeps, for a window built while we were not looking.
- `/evui skinoff` / `/evui skinon`.

Then work down the preference list above. **On file textures:** in this client
`GetTexture()` on art declared in XML returns `"FileData ID 123456"` rather
than the path, which is why an earlier pass concluded file art could never be
matched. It can: `S.ArtIsFile` puts the same path on a scratch texture of our
own and compares what the client hands back for both sides, so the string
never has to be parsed. That is what `S.ORNATE_FILES` and the `file` and
`artOrFile` fingerprints are built on.

## Theme and widgets

- Colours are tokens in `EvermoreUI/Core/Theme.lua`, standard and high
  contrast. `/evui theme audit` checks the contrast contract in game.
- Controls live in `EvermoreUI/UI/`. `/evui widgets` shows every one in every
  state.

## Other tools

- `tools/link.ps1` junctions the `EvermoreUI*` folders into WoW.
  `-Flavour _retail_` for live, `-Unlink` to remove.
- `tools/textures/make_statusbars.py` regenerates the status bar textures.

## Release notes

`python tools/changelog/build.py`

`CHANGELOG.md` is the one place release notes are written: the packager puts
it on CurseForge and Wago, and this script turns it into
`EvermoreUI/Core/Changelog.lua` for the in-game What's New window (shown once
after each update, and on `/evui new`). The release workflow runs it before
packaging, so a tag always ships its own notes. Run it by hand after editing
the changelog to check the window in game.

Write each release as `## 1.2.3`, an intro paragraph, then `### Section`
headings with `- ` bullets. `**bold**` and `` `code` `` are shown in colour.
The in-game version is matched on the number, so `v1.2.3-beta1` shows the
`1.2.3` notes.
