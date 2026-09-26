# Working on EvermoreUI

## Branches

| Branch | What it is |
|---|---|
| `main` | The next feature release. Always builds; may be ahead of what players have. |
| `release/X.Y` | Everything shipped as X.Y, and its patch releases (X.Y.1, X.Y.2...). Cut from the `vX.Y.0` tag. |
| `feature/<name>` | New work. Branch from `main`, or from `release/X.Y` if it is going out in a patch. |
| `fix/<name>` | A bug fix. Branch from the oldest `release/X.Y` it should reach. |

Merge with `--no-ff` (or a pull request) so each feature or fix stays one
visible unit in the history, then delete the branch.

**Fixes flow forwards, never backwards.** A fix lands on the release branch it
is for, and that release branch is then merged into `main`. `main` is never
merged into a release branch: that would ship half-finished features in a
patch.

## Releasing

Tags publish. Pushing a `v*` tag runs `.github/workflows/release.yml`, which
builds the zip and uploads it to CurseForge, Wago and GitHub Releases. Pushing
a branch never publishes anything.

1. On the branch you are releasing from, add the release to the top of
   `CHANGELOG.md` as `## X.Y.Z` (the notes format is in `tools/README.md`) and
   run `python tools/changelog/build.py`.
2. Commit, then tag with an annotated tag: `git tag -a vX.Y.Z -m "EvermoreUI X.Y.Z"`.
   `-betaN` or `-alphaN` on the end sends it to that channel instead.
3. Push the branch, then the tag: `git push origin <branch>` and
   `git push origin vX.Y.Z`.
4. A patch release: merge the release branch into `main` afterwards.
5. A new minor or major release (X.Y.0) from `main`: create its branch from the
   tag, `git branch release/X.Y vX.Y.0`, and push it.

The version in game comes from the tag (`@project-version@` in the TOCs), and
the What's New window shows the `CHANGELOG.md` section with the same number,
so the tag and the changelog heading must agree.

## Checks

`.github/workflows/check.yml` runs on every push and pull request: every Lua
file compiles under Lua 5.1, every file a TOC lists exists, and the generated
`EvermoreUI/Core/Changelog.lua` matches `CHANGELOG.md`. Run the same checks
locally with `python tools/check.py`.

## Commits

One change per commit, written as `Area: what changed`, for example
`Action bars: spell rank text per bar`. Comments in the code say what the code
does and why, not the history of how it got there.
