#!/usr/bin/env python3
"""Turn CHANGELOG.md into EvermoreUI/Core/Changelog.lua for the in-game
What's New window.

CHANGELOG.md is the one place release notes are written. The release
workflow runs this before packaging, so the shipped addon always carries the
notes of the build it is. Run it by hand after editing the changelog to see
the result in game:  python tools/changelog/build.py

Shape it understands:
    ## 1.2.3            a release (newest first)
    plain text          the release's intro (wrapped lines are joined)
    ### Title           a section
    - item              a bullet; indented lines continue it
Inline **bold** and `code` are kept as written; the game renders them.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "CHANGELOG.md")
OUT = os.path.join(ROOT, "EvermoreUI", "Core", "Changelog.lua")
KEEP = 6  # releases carried in game


def parse(text):
    releases = []
    rel = sec = item = None
    intro = []

    def close_item():
        nonlocal item
        if item is not None:
            sec["items"].append(" ".join(item))
            item = None

    def close_intro():
        if rel is not None and intro:
            rel["intro"].append(" ".join(intro))
            intro.clear()

    for raw in text.splitlines():
        line = raw.rstrip()
        m = re.match(r"^##\s+v?(\d+\.\d+(?:\.\d+)?)\s*$", line)
        if m:
            close_item()
            close_intro()
            rel = {"version": m.group(1), "intro": [], "sections": []}
            releases.append(rel)
            sec = None
            continue
        if rel is None:
            continue
        m = re.match(r"^###\s+(.+)$", line)
        if m:
            close_item()
            close_intro()
            sec = {"title": m.group(1).strip(), "items": []}
            rel["sections"].append(sec)
            continue
        m = re.match(r"^\s*[-*]\s+(.+)$", line)
        if m:
            close_item()
            close_intro()
            if sec is None:
                sec = {"title": "", "items": []}
                rel["sections"].append(sec)
            item = [m.group(1).strip()]
            continue
        if not line.strip():
            close_item()
            close_intro()
            continue
        if item is not None and raw[:1] in (" ", "\t"):
            item.append(line.strip())
        elif sec is None:
            intro.append(line.strip())
        else:
            close_item()
    close_item()
    close_intro()
    return releases


def lua(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(releases):
    out = [
        "if EV_BLOCKED then return end",
        "-- Generated from CHANGELOG.md by tools/changelog/build.py. Edit the",
        "-- changelog, not this file.",
        "EvermoreUI.CHANGELOG = {",
    ]
    for r in releases[:KEEP]:
        out.append("    {")
        out.append("        version = %s," % lua(r["version"]))
        out.append("        intro = { %s }," % ", ".join(lua(p) for p in r["intro"]))
        out.append("        sections = {")
        for s in r["sections"]:
            out.append("            { title = %s, items = {" % lua(s["title"]))
            for i in s["items"]:
                out.append("                %s," % lua(i))
            out.append("            } },")
        out.append("        },")
        out.append("    },")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    with open(SRC, encoding="utf-8") as f:
        releases = parse(f.read())
    if not releases:
        sys.exit("no releases found in CHANGELOG.md")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(render(releases))
    print("%d releases -> %s" % (min(len(releases), KEEP), os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    main()
