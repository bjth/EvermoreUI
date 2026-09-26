"""Build the manifest: everything the target client loads."""
import datetime
import hashlib
import os
import re

from . import tocs, xmlui

COLOR = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*CreateColor\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+))?\s*\)", re.M)
HEXCOLOR = re.compile(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*CreateColorFromHexString\(\s*"([0-9A-Fa-f]{8})"\s*\)', re.M)


def _lua_colours(path, out):
    with open(path, encoding="utf-8", errors="ignore") as fh:
        text = fh.read()
    for m in COLOR.finditer(text):
        out[m.group(1)] = [float(m.group(2)), float(m.group(3)), float(m.group(4)), float(m.group(5) or 1)]
    for m in HEXCOLOR.finditer(text):
        h = m.group(2)
        a, r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4, 6))
        out[m.group(1)] = [round(r, 3), round(g, 3), round(b, 3), round(a, 3)]


def build(export, target, log=print):
    root = os.path.join(export, "Interface", "AddOns")
    if not os.path.isdir(root):
        raise SystemExit("No Interface/AddOns under %s. Run ExportInterfaceFiles code in game first." % export)
    addons, templates, frames, fonts, colours = {}, {}, {}, {}, {}
    errors, digest = [], hashlib.sha1()

    def walk_xml(addon, path, seen, files):
        norm = os.path.normcase(os.path.normpath(path))
        if norm in seen:
            return
        seen.add(norm)
        if not os.path.exists(path):
            errors.append("missing %s" % os.path.relpath(path, root))
            return
        rel = os.path.relpath(path, root).replace("\\", "/")
        files.append(rel)
        with open(path, "rb") as fh:
            digest.update(fh.read())
        includes, nodes, fnts, err = xmlui.parse(path)
        if err:
            errors.append("%s: %s" % (rel, err))
        base = os.path.dirname(path)
        for kind, inc in includes:
            p = os.path.join(base, inc)
            if inc.lower().endswith(".xml"):
                walk_xml(addon, p, seen, files)
            elif inc.lower().endswith(".lua") and os.path.exists(p):
                files.append(os.path.relpath(p, root).replace("\\", "/"))
                _lua_colours(p, colours)
        fonts.update(fnts)
        for n in nodes:
            name = n.get("n")
            if not name:
                continue
            n["addon"] = addon
            n["file"] = rel
            if n.get("v") or n.get("x"):
                templates[name] = n
            else:
                frames[name] = n

    for addon in sorted(os.listdir(root)):
        d = os.path.join(root, addon)
        if not os.path.isdir(d):
            continue
        toc = tocs.find_toc(d)
        if not toc:
            continue
        headers, files, loads = tocs.read_toc(toc, target)
        if not loads:
            continue
        seen, loaded = set(), []
        for f in files:
            p = os.path.join(d, f)
            if f.lower().endswith(".xml"):
                walk_xml(addon, p, seen, loaded)
            elif f.lower().endswith(".lua") and os.path.exists(p):
                loaded.append(os.path.relpath(p, root).replace("\\", "/"))
                _lua_colours(p, colours)
        lod = any(v.strip() == "1" for v in headers.get("LoadOnDemand", []))
        deps = []
        for key in ("Dependencies", "RequiredDeps", "Dep"):
            for v in headers.get(key, []):
                if target.allowed(v):
                    deps += [x.strip() for x in re.sub(r"\[[^\]]*\]", "", v).split(",") if x.strip()]
        addons[addon] = {"lod": lod, "deps": deps, "files": loaded}

    # Named frames nested inside other frames are globals too.
    globals_ = {}

    def nested(node, owner, parent_name):
        for ch in node.get("ch", []):
            n = ch.get("n")
            if n and "$parent" in n and parent_name:
                n = n.replace("$parent", parent_name)
            if n and "$" not in n and ch.get("t") not in ("Texture", "FontString", "MaskTexture", "Line"):
                globals_.setdefault(n, owner)
            nested(ch, owner, n if n and "$" not in n else None)
    for name, node in frames.items():
        nested(node, name, name)
    log("  %d addons, %d frames, %d templates, %d fonts, %d colours" %
        (len(addons), len(frames), len(templates), len(fonts), len(colours)))
    return {
        "meta": {
            "gameType": target.game,
            "family": target.family,
            "generated": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
            "sourceHash": digest.hexdigest()[:16],
            "errors": errors,
        },
        "addons": addons,
        "templates": templates,
        "frames": frames,
        "globals": globals_,
        "fonts": fonts,
        "colours": colours,
    }
