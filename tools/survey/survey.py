#!/usr/bin/env python3
"""EvermoreUI survey.

Reads Blizzard's exported interface code (in game: /console
ExportInterfaceFiles code) and, for the configured game type:

  1. builds a manifest of everything the client loads
     (tools/survey/manifests/<gameType>.json, previous kept as .prev.json)
  2. diffs it against the last run
  3. MEASURES template coverage: it loads EvermoreUI_Skins/Parts.lua itself
     (coverage.lua, through lupa or a lua5.1) and runs its fingerprints
     against every template in the manifest, reporting which part claims
     each one, which parts match nothing, and which templates nothing
     claims. That last list is the to-do list. Without a Lua it falls back
     to the Python copy of the fingerprints in evsurvey/fingerprint.py.
  4. writes tools/survey/report.md

  python tools/survey/survey.py [--export PATH] [--game camelot] [--family mainline]
  python tools/survey/survey.py --detect          (list game types in the export)
  python tools/survey/survey.py --check           (no writes)
  python tools/survey/survey.py --shapes FILE     (also write the shapes
                                                   coverage.lua reads, to run
                                                   it by hand)

Settings default from tools/survey/config.json. Standard library only;
lupa (pip install lupa) or a lua5.1 on the PATH is optional and makes the
coverage measurement use the real Parts.lua.

This tool does NOT generate any Lua. It used to write
EvermoreUI_Skins/Data/Generated.lua and a simulator's mocks; both that
generated-rules generation and the simulator were removed on 21 Sep 2026.
Parts are written by hand; the survey only tells you what is worth writing.
"""
import argparse
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from evsurvey import fingerprint, luarun, manifest, tocs  # noqa: E402

# Templates that carry no art of their own: pure layout, behaviour or data
# mixins. They inherit heavily and would otherwise dominate the uncovered
# list forever. Nothing here wants a part.
NO_ART = {
    "ResizeLayoutFrame", "HorizontalLayoutFrame", "VerticalLayoutFrame",
    "CallbackRegistrantTemplate", "UIWidgetBaseTemplate", "UserScaledFrameTemplate",
    "EditModeSystemTemplate", "ScriptAnimatedModelSceneTemplate",
    "WowScrollBoxList", "ScrollFrameTemplate", "CooldownFrameTemplate",
    "TooltipTextureTemplate", "InputIconTextureFrameTemplate",
    # The nineslice is the mechanism a panel is drawn WITH, not a frame to
    # skin: its owner is claimed instead, and FadeSlice takes its art down.
    "NineSlicePanelTemplate", "NineSliceLayoutFrame",
}

PART_RE = re.compile(r'^\s*name\s*=\s*"([^"]+)"', re.M)
# Mirrors the assert in Core.lua's S.Register. A part MUST say what it
# recognises; `type` alone is not a fingerprint. This is checked here as well
# as at runtime because the runtime check fires at LOAD, and a part that
# fails it aborts Parts.lua's main chunk: every part after it never
# registers, so the whole skin library goes quiet. That happened on 21 Sep
# with `slider` and the game gave no clue that 17 other parts had gone with
# it. Offline is the cheaper place to find out.
FINGERPRINTS = ("keys", "art", "file", "artOrFile", "layout", "test")
ROLE_RE = re.compile(r'^\s*\["([^"]+)"\]\s*=\s*"', re.M)


def read_parts(addons):
    """Part names registered in Parts.lua, in file order."""
    path = os.path.join(addons, "EvermoreUI_Skins", "Parts.lua")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", errors="ignore") as fh:
        return PART_RE.findall(fh.read())


def lint_parts(addons):
    """Every R{...} block in Parts.lua must carry a real fingerprint."""
    path = os.path.join(addons, "EvermoreUI_Skins", "Parts.lua")
    if not os.path.exists(path):
        # Never report "all clear" for a file we could not read: a silent
        # pass is worse than no check, because it is trusted.
        return ["<Parts.lua not found at %s>" % path]
    with open(path, encoding="utf-8", errors="ignore") as fh:
        src = fh.read()
    bad = []
    for block in src.split("\nR{")[1:]:
        depth, end = 1, 0
        for i, ch in enumerate(block):
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        body = block[:end]
        m = PART_RE.search(body)
        name = m.group(1) if m else "<unnamed>"
        if not any(re.search(r"^\s*%s\s*=" % f, body, re.M) for f in FINGERPRINTS):
            bad.append(name)
    return bad


def read_font_roles(addons):
    """Font-object patterns Fonts.lua restyles (GameFontNormal*, ...)."""
    path = os.path.join(addons, "EvermoreUI_Skins", "Fonts.lua")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", errors="ignore") as fh:
        return ROLE_RE.findall(fh.read())


def font_covered(name, roles):
    for p in roles:
        if p.endswith("*"):
            if name.startswith(p[:-1]):
                return True
        elif name == p:
            return True
    return False


def inherit_counts(m):
    """How many places inherit each template, frames and templates alike."""
    c = collections.Counter()

    def walk(node):
        for parent in (node.get("i") or []):
            c[parent] += 1
        for ch in node.get("ch") or []:
            walk(ch)

    for section in ("frames", "templates"):
        for node in m[section].values():
            walk(node)
    return c


def diff_manifests(old, new):
    """What changed between two manifests. Names only: no rule analysis."""
    if old["meta"].get("sourceHash") == new["meta"].get("sourceHash"):
        return ["Source unchanged since %s." % old["meta"].get("generated")]
    lines = ["Compared with the export surveyed %s." % old["meta"].get("generated")]
    if old["meta"].get("gameType") != new["meta"].get("gameType"):
        lines.append("Game type changed: %s -> %s"
                     % (old["meta"].get("gameType"), new["meta"].get("gameType")))
    for kind in ("addons", "frames", "templates", "fonts"):
        added = sorted(set(new.get(kind, {})) - set(old.get(kind, {})))
        removed = sorted(set(old.get(kind, {})) - set(new.get(kind, {})))
        if added or removed:
            lines.append("%s: +%d -%d" % (kind, len(added), len(removed)))
            lines += ["  + %s" % n for n in added[:40]]
            lines += ["  - %s" % n for n in removed[:40]]
            if len(added) > 40 or len(removed) > 40:
                lines.append("  ...")
    return lines


# The header over each part quotes what it covers, from the survey that was
# current when it was written: "UIPanelButtonTemplate, 284 inherits", or for
# a layoutType part, 'layoutType "Dialog", 5 templates'. Quoted numbers go
# stale on a client patch, so the survey checks them.
HEADER_RE = re.compile(r"^--\s*\d+[a-z]?\.\s+.+?\s{2,}(.+)$")
HEADER_TEMPLATE_RE = re.compile(r"^([A-Za-z_]\w*), (\d+) inherits")
HEADER_LAYOUT_RE = re.compile(r'^layoutType "(\w+)", (\d+) templates')


def read_headers(addons):
    """[(part, kind, name, number)] quoted in the headers over each part."""
    path = os.path.join(addons, "EvermoreUI_Skins", "Parts.lua")
    if not os.path.exists(path):
        return []
    out, pending = [], []
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            h = HEADER_RE.match(line.rstrip())
            if h:
                rest = h.group(1).strip()
                t = HEADER_TEMPLATE_RE.match(rest)
                lay = HEADER_LAYOUT_RE.match(rest)
                if t:
                    pending.append(("template", t.group(1), int(t.group(2))))
                elif lay:
                    pending.append(("layout", lay.group(1), int(lay.group(2))))
                continue
            n = PART_RE.match(line)
            if n and pending:
                out += [(n.group(1),) + q for q in pending]
                pending = []
    return out


def check_headers(addons, claimed, counts):
    """What the headers quote against what was measured. Mismatches only."""
    per_part = collections.Counter(claimed.values())
    bad = []
    for part, kind, name, n in read_headers(addons):
        if kind == "template":
            if counts.get(name, 0) != n:
                bad.append("%s: header says %s has %d inherits, the manifest has %d"
                           % (part, name, n, counts.get(name, 0)))
            if claimed.get(name) != part:
                bad.append("%s: header names %s, which is claimed by %s"
                           % (part, name, claimed.get(name) or "nothing"))
        elif per_part.get(part, 0) != n:
            bad.append('%s: header says %d templates with layoutType "%s", it claims %d'
                       % (part, n, name, per_part.get(part, 0)))
    return bad


def coverage(m, addons, top=60):
    """Measured, not claimed: run the part fingerprints over every template."""
    counts = inherit_counts(m)
    parts = read_parts(addons)
    roles = read_font_roles(addons)
    shapes, claimed, hits, dead, shadowed = fingerprint.classify(m, counts)
    mirror = dict(claimed)

    # The real thing, if there is a Lua to run it with. A runner that fails is
    # reported, never swallowed: a silent fallback would be trusted.
    measured, lua_error = None, None
    try:
        measured = luarun.run(m, counts, addons)
    except Exception as exc:  # noqa: BLE001
        lua_error = str(exc)

    if measured:
        source = "Parts.lua itself, run by coverage.lua (%s)" % luarun.describe(luarun.runner())
        claimed, hits = measured["claimed"], measured["hits"]
        # Runtime-only claims are rows with a part and no fingerprint hit.
        runtime = {t: p for t, p in claimed.items() if t not in hits}
        claimed = {t: p for t, p in claimed.items() if t in hits}
        unmodelled = [(n, why, sorted(t for t, p in runtime.items() if p == n))
                      for n, why in measured["runtime"].items()]
        inside = collections.Counter(p for _t, _k, p, _c in measured["inside"])
        dead = [n for n in measured["parts"]
                if n not in measured["runtime"] and n not in set(claimed.values())
                and not inside.get(n) and not measured["objects"].get(n)]
        shadowed = {t: h for t, h in hits.items() if len(h) > 1}
        mirror_drift = sorted(t for t in set(claimed) | set(mirror)
                              if claimed.get(t) != mirror.get(t))
    else:
        source = "the Python copy in evsurvey/fingerprint.py: %s" % (
            ("coverage.lua failed: " + lua_error) if lua_error
            else luarun.describe(None))
        # Templates a part claims at runtime but the matcher cannot see.
        # Counted as covered, and named in the report so the claim stays
        # visible.
        unmodelled = fingerprint.unmodelled()
        runtime = {}
        for name, _reason, tmpls in unmodelled:
            for t in tmpls:
                runtime[t] = name
        mirror_drift = []

    rows, gaps = [], []
    for name, n in counts.most_common(top):
        if name in claimed:
            rows.append((name, n, "part " + claimed[name]))
        elif name in runtime:
            rows.append((name, n, "part %s (runtime)" % runtime[name]))
        elif font_covered(name, roles):
            rows.append((name, n, "font role"))
        elif name in NO_ART:
            rows.append((name, n, "no art"))
        elif name.startswith("Glue"):
            rows.append((name, n, "login screen"))
        else:
            rows.append((name, n, ""))
            gaps.append((name, n))

    unfingerprinted = lint_parts(addons)
    modelled = [p["name"] for p in fingerprint.PARTS]
    drift_missing = [n for n in parts if n not in modelled]
    drift_extra = [n for n in modelled if n not in parts]
    headers = check_headers(addons, dict(claimed, **runtime), counts)
    return dict(rows=rows, gaps=gaps, dead=dead, shadowed=shadowed, claimed=claimed,
                unmodelled=unmodelled, runtime=runtime, measured=measured,
                source=source, lua_error=lua_error, mirror_drift=mirror_drift,
                mirror=mirror,
                headers=headers,
                counts=counts, parts=parts, shapes=shapes,
                unfingerprinted=unfingerprinted,
                drift_missing=drift_missing, drift_extra=drift_extra)


def write_manifest(path, m):
    """One entry per line: compact, and git diffs stay readable."""
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("{\n")
        sections = list(m.items())
        for si, (sec, val) in enumerate(sections):
            fh.write(json.dumps(sec) + ": ")
            if isinstance(val, dict) and sec != "meta":
                fh.write("{\n")
                items = sorted(val.items())
                for i, (k, v) in enumerate(items):
                    fh.write(" " + json.dumps(k) + ": "
                             + json.dumps(v, separators=(",", ":"), sort_keys=True))
                    fh.write(",\n" if i < len(items) - 1 else "\n")
                fh.write("}")
            else:
                fh.write(json.dumps(val, indent=1, sort_keys=True))
            fh.write(",\n" if si < len(sections) - 1 else "\n")
        fh.write("}\n")


def main():
    cfg_path = os.path.join(HERE, "config.json")
    cfg = json.load(open(cfg_path)) if os.path.exists(cfg_path) else {}
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--export", default=cfg.get("export"))
    ap.add_argument("--game", default=cfg.get("gameType", "camelot"))
    ap.add_argument("--family", default=cfg.get("family", "mainline"))
    ap.add_argument("--addons", default=os.path.normpath(
        os.path.join(HERE, cfg.get("addonRoot", "../.."))))
    ap.add_argument("--top", type=int, default=60,
                    help="how many of the most-inherited templates to report")
    ap.add_argument("--detect", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--shapes", metavar="FILE",
                    help="also write the template shapes coverage.lua reads")
    args = ap.parse_args()

    if not args.export or not os.path.isdir(args.export):
        for alt in cfg.get("exportAlternatives", []):
            alt = os.path.expanduser(alt)
            if os.path.isdir(alt):
                args.export = alt
                break
    if not args.export or not os.path.isdir(args.export):
        raise SystemExit("Export folder not found: %s (set it in config.json or pass --export)"
                         % args.export)
    iface = os.path.join(args.export, "Interface", "AddOns")

    types = tocs.game_types_in(iface)
    if args.detect:
        print("Game types named in TOC filters:")
        for t, n in sorted(types.items(), key=lambda x: -x[1]):
            print("  %-22s %d" % (t, n))
        print("Per-game folders:", ", ".join("%s (%d)" % kv
                                             for kv in sorted(tocs.game_folders(iface).items())))
        return 0
    if args.game.lower() not in types:
        print("WARNING: game type %r is not named in any TOC. Blizzard may have renamed or dropped it."
              % args.game)
        print("         Run with --detect and set gameType in config.json.")

    target = tocs.Target(args.game, args.family)
    print("Surveying %s (%s/%s)" % (args.export, target.game, target.family))
    m = manifest.build(args.export, target)

    mdir = os.path.join(HERE, "manifests")
    mpath = os.path.join(mdir, target.game + ".json")
    old = json.load(open(mpath, encoding="utf-8")) if os.path.exists(mpath) else None
    changes = diff_manifests(old, m) if old else ["First survey for %s." % target.game]

    cov = coverage(m, args.addons, args.top)
    rows, gaps, parts = cov["rows"], cov["gaps"], cov["parts"]
    claimed, counts = cov["claimed"], cov["counts"]

    by_part = collections.Counter(claimed.values())
    report = ["# Survey report", "",
              "Export: `%s`  " % args.export,
              "Game type: %s (family %s), source %s, %s"
              % (target.game, target.family, m["meta"]["sourceHash"], m["meta"]["generated"]),
              "", "## Changes since last survey", ""] + ["    " + l for l in changes]

    measured = cov["measured"]
    report += ["", "## What each part claims", "",
               "Measured by running each fingerprint in `Parts.lua` against all %d"
               % len(m["templates"]),
               "templates in this client, with %s." % cov["source"],
               "A part matching nothing is a bug in its fingerprint, not a gap in",
               "Blizzard's UI.", ""]
    names = measured["parts"] if measured else [p["name"] for p in fingerprint.PARTS]
    dead = set(cov["dead"])
    if measured:
        inside = collections.Counter(p for _t, _k, p, _c in measured["inside"])
        inside_sites = collections.Counter()
        for _t, _k, p, c in measured["inside"]:
            inside_sites[p] += c
        report += ["`templates` is the template's own root. `inside` is frames a template",
                   "declares within itself (the coin boxes in a money frame), which the",
                   "walk dresses too. `objects` counts every frame in Blizzard's named",
                   "windows, the instances a player actually sees.", "",
                   "| part | templates | inherit sites | inside | inside sites | objects |",
                   "| --- | ---: | ---: | ---: | ---: | ---: |"]
        tot = [0, 0, 0, 0, 0]
        for n in names:
            sites = sum(counts.get(t, 0) for t, c in claimed.items() if c == n)
            row = [by_part.get(n, 0), sites, inside.get(n, 0), inside_sites.get(n, 0),
                   measured["objects"].get(n, 0)]
            tot = [a + b for a, b in zip(tot, row)]
            flag = " **MATCHES NOTHING**" if n in dead else ""
            report.append("| `%s`%s | %d | %d | %d | %d | %d |" % ((n, flag) + tuple(row)))
        report.append("| **total** | %d | %d | %d | %d | %d of %d |"
                      % tuple(tot + [measured["objects_total"]]))
    else:
        report += ["| part | templates | inherit sites |", "| --- | ---: | ---: |"]
        for n in names:
            sites = sum(counts.get(t, 0) for t, c in claimed.items() if c == n)
            flag = " **MATCHES NOTHING**" if n in dead else ""
            report.append("| `%s`%s | %d | %d |" % (n, flag, by_part.get(n, 0), sites))
        report.append("| **total** | %d | %d |"
                      % (len(claimed), sum(counts.get(t, 0) for t in claimed)))

    if cov["unfingerprinted"]:
        report += ["", "### PARTS WITH NO FINGERPRINT (these break the addon at load)", "",
                   "`S.Register` asserts on these, and the assert aborts Parts.lua's main",
                   "chunk, so every part registered after one of these never registers at all.", ""]
        report += ["- `%s`" % n for n in cov["unfingerprinted"]]
    if cov["unmodelled"]:
        report += ["", "### Parts the matcher cannot evaluate", "",
                   "Not dead, not measured. Verify these in game with `/evui skin this`.", ""]
        report += ["- `%s`: %s%s" % (n, r, (" (claims " + ", ".join(t) + ")") if t else "")
                   for n, r, t in cov["unmodelled"]]
    if cov["dead"]:
        report += ["", "### Parts that match nothing", ""] + ["- `%s`" % d for d in cov["dead"]]
    if measured and measured["errors"]:
        report += ["", "### Fingerprints that threw", ""] + ["- " + e for e in measured["errors"][:40]]
    if cov["headers"]:
        report += ["", "### Parts.lua headers out of date", "",
                   "The counts quoted over each part no longer match this client.", ""]
        report += ["- " + h for h in cov["headers"]]
    if cov["mirror_drift"]:
        report += ["", "### fingerprint.py disagrees with Parts.lua", "",
                   "The Python copy is only the fallback for a machine with no Lua, but",
                   "it should give the same answer. It does not on:", ""]
        report += ["- `%s`: Parts.lua %s, fingerprint.py %s"
                   % (t, cov["claimed"].get(t) or "nothing",
                      cov["mirror"].get(t) or "nothing")
                   for t in cov["mirror_drift"][:40]]
    if cov["drift_missing"] or cov["drift_extra"]:
        report += ["", "### fingerprint.py is out of step with Parts.lua", ""]
        report += ["- registered in Parts.lua, not modelled here: %s" % ", ".join(cov["drift_missing"])] if cov["drift_missing"] else []
        report += ["- modelled here, not registered in Parts.lua: %s" % ", ".join(cov["drift_extra"])] if cov["drift_extra"] else []

    report += ["", "## Most-inherited templates", "",
               "The %d most-inherited templates in this client. A blank third column"
               % args.top,
               "is a template nothing claims: the candidates for the next part.", "",
               "| template | inherits | covered by |", "| --- | ---: | --- |"]
    report += ["| `%s` | %d | %s |" % (n, c, w or "**nothing**") for n, c, w in rows]

    if gaps:
        report += ["", "### Uncovered, most used first", ""]
        report += ["- `%s` (%d)" % (n, c) for n, c in gaps[:25]]
    if cov["shadowed"]:
        sh = sorted(((counts.get(t, 0), t, h) for t, h in cov["shadowed"].items()), reverse=True)
        report += ["", "### Templates more than one part matches", "",
                   "The first registered wins, as `S.Dress` does. Check the order is right.", ""]
        report += ["- `%s` (%d): %s" % (t, c, " > ".join(h)) for c, t, h in sh[:20]]
    if m["meta"]["errors"]:
        report += ["", "## Source problems", ""] + ["- " + e for e in m["meta"]["errors"]]

    print("\n".join(changes[:30]))
    print()
    print("Measured with %s." % cov["source"])
    print("%d parts claim %d templates across %d inherit sites."
          % (len(names), len(claimed), sum(counts.get(t, 0) for t in claimed)))
    if measured:
        print("  and %d of the %d frame objects in Blizzard's named windows."
              % (sum(measured["objects"].values()), measured["objects_total"]))
        for e in measured["errors"][:10]:
            print("  THREW      %s" % e)
    for n in cov["unfingerprinted"]:
        print("  NO FINGERPRINT  %s -- this ABORTS Parts.lua at load" % n)
    for d in cov["dead"]:
        print("  DEAD PART  %s matches nothing in this client" % d)
    for n, r, _t in cov["unmodelled"]:
        print("  UNMODELLED %s -- %s; verify in game" % (n, r))
    for h in cov["headers"]:
        print("  HEADER     %s" % h)
    if cov["mirror_drift"]:
        print("  MIRROR     fingerprint.py disagrees with Parts.lua on %d templates (see report)"
              % len(cov["mirror_drift"]))
    for n in cov["drift_missing"]:
        print("  DRIFT      Parts.lua registers %r, fingerprint.py does not model it" % n)
    for n in cov["drift_extra"]:
        print("  DRIFT      fingerprint.py models %r, Parts.lua no longer registers it" % n)
    print("  %d of the top %d templates unclaimed:" % (len(gaps), args.top))
    for n, c in gaps[:15]:
        print("    %-44s %d" % (n, c))

    if args.shapes:
        luarun.write_shapes(args.shapes, m, counts)
        print("Wrote shapes to %s: lua5.1 tools/survey/coverage.lua %s [summary|all]"
              % (args.shapes, args.shapes))

    if args.check:
        return 0

    os.makedirs(mdir, exist_ok=True)
    if old and old["meta"].get("sourceHash") != m["meta"]["sourceHash"]:
        os.replace(mpath, os.path.join(mdir, target.game + ".prev.json"))
    write_manifest(mpath, m)
    with open(os.path.join(HERE, "report.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(report) + "\n")
    print("\nWrote manifest and tools/survey/report.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
