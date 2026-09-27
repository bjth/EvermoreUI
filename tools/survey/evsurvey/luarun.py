"""Run tools/survey/coverage.lua: the real Parts.lua over every template.

Needs a Lua 5.1. It uses whichever it finds first:

  * lupa (pip install lupa), in process. The easy one on Windows.
  * lua5.1, lua51 or luajit on the PATH. CI installs lua5.1.

Without either, the survey falls back to the hand-kept Python copy of the
fingerprints in fingerprint.py and says so.
"""
import os
import shutil
import subprocess
import tempfile

from . import shapes

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(HERE, "coverage.lua")


def runner():
    """(kind, handle) for the first Lua 5.1 available, or None."""
    try:
        import lupa.lua51 as lua51  # noqa: F401
        return ("lupa", lua51)
    except ImportError:
        pass
    for exe in ("lua5.1", "lua51", "luajit"):
        path = shutil.which(exe)
        if path:
            return ("exe", path)
    return None


def describe(r):
    if not r:
        return "no Lua 5.1 (pip install lupa, or put lua5.1 on the PATH)"
    return "lupa" if r[0] == "lupa" else os.path.basename(r[1])


def _lines(r, shapes_path, addons):
    if r[0] == "lupa":
        lua = r[1].LuaRuntime()
        with open(SCRIPT, encoding="utf-8") as fh:
            main = lua.execute(fh.read())
        out = []
        main(shapes_path, addons, "tsv", out.append)
        return out
    p = subprocess.run([r[1], SCRIPT, shapes_path, "tsv", addons],
                       capture_output=True, text=True)
    if p.returncode not in (0, 1) or (p.returncode and not p.stdout):
        raise RuntimeError((p.stdout + p.stderr).strip() or "coverage.lua failed")
    return p.stdout.splitlines()


def write_shapes(path, manifest, counts):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(shapes.to_lua(manifest, counts))


def run(manifest, counts, addons, r=None):
    """Measure. Returns None when no Lua is available.

    parts     part names in registration order
    runtime   {part: why} for parts only a live frame can match
    claimed   {template: part}, first match, as S.Dress
    hits      {template: [part, ...]} every part that matches
    inside    [(template, key, part, count)] frames a template declares
    objects   {part: n} objects claimed in Blizzard's named frames
    objects_total  every frame object in those named frames
    errors    fingerprints that threw
    """
    r = r or runner()
    if not r:
        return None
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "shapes.lua")
        write_shapes(path, manifest, counts)
        lines = _lines(r, path, os.path.abspath(addons))
    res = dict(parts=[], runtime={}, claimed={}, hits={}, inside=[], objects={},
               objects_total=0, errors=[])
    for line in lines:
        f = line.split("\t")
        kind = f[0]
        if kind == "part":
            res["parts"].append(f[1])
            if len(f) > 3 and f[2] == "runtime":
                res["runtime"][f[1]] = f[3]
        elif kind == "row":
            if f[3]:
                res["claimed"][f[1]] = f[3]
            if f[4]:
                res["hits"][f[1]] = f[4].split(">")
        elif kind == "inside":
            res["inside"].append((f[1], f[2], f[3], int(f[4])))
        elif kind == "objects":
            res["objects"][f[1]] = int(f[2])
        elif kind == "frameobjects":
            res["objects_total"] = int(f[1])
        elif kind == "error":
            res["errors"].append("\t".join(f[1:]))
    if not res["parts"]:
        raise RuntimeError("coverage.lua printed no parts:\n" + "\n".join(lines[:20]))
    return res
