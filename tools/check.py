#!/usr/bin/env python3
"""The checks CI runs, runnable locally: python tools/check.py

  * every file a .toc lists exists (TOCs are the load order; a missing file
    is a silent hole in game)
  * every .lua compiles under Lua 5.1, if luac5.1 or luac is on the PATH
  * EvermoreUI/Core/Changelog.lua is what CHANGELOG.md generates
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SKIP = {".git", "_backup", "_deploy", ".release", "tools", "branding"}
failures = []


def addon_dirs():
    for name in sorted(os.listdir(ROOT)):
        if name.startswith("EvermoreUI") and os.path.isdir(os.path.join(ROOT, name)):
            yield os.path.join(ROOT, name)


def check_tocs():
    for d in addon_dirs():
        for f in os.listdir(d):
            if not f.endswith(".toc"):
                continue
            with open(os.path.join(d, f), encoding="utf-8") as fh:
                for n, raw in enumerate(fh, 1):
                    line = raw.strip()
                    if not line or line.startswith("#"):
                        continue
                    path = line.split()[0].replace("\\", "/")
                    if not path.endswith((".lua", ".xml")):
                        continue
                    if not os.path.isfile(os.path.join(d, path)):
                        failures.append("%s/%s:%d lists %s, which does not exist" % (os.path.basename(d), f, n, path))


def check_lua():
    luac = shutil.which("luac5.1") or shutil.which("luac")
    if not luac:
        print("luac not found, skipping the compile check")
        return
    for d in addon_dirs():
        for base, dirs, files in os.walk(d):
            dirs[:] = [x for x in dirs if x not in SKIP]
            for f in files:
                if f.endswith(".lua"):
                    p = os.path.join(base, f)
                    r = subprocess.run([luac, "-p", p], capture_output=True, text=True)
                    if r.returncode != 0:
                        failures.append(r.stderr.strip() or ("does not compile: " + p))


def check_changelog():
    sys.path.insert(0, os.path.join(ROOT, "tools", "changelog"))
    import build  # noqa: E402
    with open(build.SRC, encoding="utf-8") as fh:
        want = build.render(build.parse(fh.read()))
    try:
        with open(build.OUT, encoding="utf-8") as fh:
            have = fh.read()
    except FileNotFoundError:
        have = ""
    if want != have:
        failures.append("EvermoreUI/Core/Changelog.lua is out of date: run python tools/changelog/build.py")


check_tocs()
check_lua()
check_changelog()
for f in failures:
    print("FAIL", f)
print("%d problem%s" % (len(failures), "" if len(failures) == 1 else "s"))
sys.exit(1 if failures else 0)
