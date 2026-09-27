#!/usr/bin/env python3
"""Chrome colours outside the Looks: python tools/lint_tokens.py

Modules may not compose a control or a panel from raw tokens. A button is
U.Button, a bordered box is U.Surface or U.Panel, a control box goes through
U.PaintBox and a Look (EvermoreUI/Core/Looks.lua). This lists every string
literal naming a surface or border token in the EvermoreUI_* addons, except
EvermoreUI_Skins, which paints through the Looks by construction.

Content colours are allowed: bar fills, class and data colours, a track under
a value. Mark such a line with the comment `-- content colour` and it is
skipped.

Exits non-zero when anything is listed, so it can run in CI.
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# A chrome token handed to something that paints: a fill, a border, a colour.
# Settings that merely share a name ("border" as an option key) don't match.
PATTERN = re.compile(
    r'(Fill|Solid|TokenBorder|SetBorderToken|RGBA|Mix|Glyph|SetColorTexture|SetVertexColor)'
    r'\(.*"(surface[0-9A-Za-z]*|border|borderStrong)"'
    r'|(token|Token)\s*=\s*[^\n]*"(surface[0-9A-Za-z]*|border|borderStrong)"')
MARK = "-- content colour"


def hits():
    out = []
    for name in sorted(os.listdir(ROOT)):
        if not name.startswith("EvermoreUI_") or name == "EvermoreUI_Skins":
            continue
        base = os.path.join(ROOT, name)
        for dirpath, _, files in os.walk(base):
            for f in sorted(files):
                if not f.endswith(".lua"):
                    continue
                path = os.path.join(dirpath, f)
                with open(path, encoding="utf-8", errors="replace") as fh:
                    for n, line in enumerate(fh, 1):
                        code = line.split("--", 1)[0] if MARK not in line else ""
                        if MARK in line:
                            continue
                        if PATTERN.search(code):
                            out.append("%s:%d: %s" % (os.path.relpath(path, ROOT), n, line.strip()))
    return out


if __name__ == "__main__":
    found = hits()
    for h in found:
        print(h)
    sys.exit(1 if found else 0)
