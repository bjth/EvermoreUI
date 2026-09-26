"""TOC resolution: which files a client of a given game type loads.

TOC lines can carry [AllowLoadGameType a, b] / [ExcludeLoadGameType a] and
use [Family] / [Game] path tokens. [Family] is the family folder (Mainline)
and [Game] the game type's own folder (Camelot)."""
import os
import re

ALLOW = re.compile(r"\[AllowLoadGameType ([^\]]+)\]")
EXCLUDE = re.compile(r"\[ExcludeLoadGameType ([^\]]+)\]")
LOCALE = re.compile(r"\[AllowLoadTextLocale:?([^\]]+)\]")
HEADER = re.compile(r"^##\s*([\w-]+)\s*:\s*(.*)$")


def _set(s):
    return {x.strip().lower() for x in s.split(",") if x.strip()}


class Target:
    """The client we resolve for: its game type and family."""

    def __init__(self, game_type, family):
        self.game = game_type.lower()
        self.family = family.lower()
        self.types = {self.game, self.family}
        self.game_dir = self.game.capitalize()
        self.family_dir = self.family.capitalize()

    def allowed(self, text):
        a = ALLOW.search(text)
        if a and not (_set(a.group(1)) & self.types):
            return False
        e = EXCLUDE.search(text)
        if e and self.game in _set(e.group(1)):
            return False
        return True

    def path(self, p):
        return p.replace("[Family]", self.family_dir).replace("[Game]", self.game_dir).replace("\\", "/")


def find_toc(addon_dir):
    name = os.path.basename(addon_dir)
    tocs = sorted(f for f in os.listdir(addon_dir) if f.lower().endswith(".toc"))
    if not tocs:
        return None
    # Prefer the addon's own name, then any.
    for t in tocs:
        if t[:-4].lower() == name.lower():
            return os.path.join(addon_dir, t)
    return os.path.join(addon_dir, tocs[0])


def read_toc(path, target):
    """Returns (headers, files, loads). loads False if the TOC itself is
    excluded for this target."""
    headers, files = {}, []
    loads = True
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            m = HEADER.match(line)
            if m:
                key, val = m.group(1), m.group(2)
                headers.setdefault(key, []).append(val)
                if key == "AllowLoadGameType" and not (_set(val) & target.types):
                    loads = False
                if key == "ExcludeLoadGameType" and target.game in _set(val):
                    loads = False
                continue
            if line.startswith("#"):
                continue
            if not target.allowed(line):
                continue
            loc = LOCALE.search(line)
            if loc and not (_set(loc.group(1).replace(":", "")) & {"enus", "engb"}):
                continue
            line = LOCALE.sub("", line).strip()
            f = re.split(r"\s+\[", line)[0].strip()
            files.append(target.path(f))
    return headers, files, loads


def game_types_in(root):
    """Every game type named in any TOC filter, with a count."""
    seen = {}
    for addon in os.listdir(root):
        d = os.path.join(root, addon)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if not f.lower().endswith(".toc"):
                continue
            with open(os.path.join(d, f), encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    for rx in (ALLOW, EXCLUDE):
                        for m in rx.finditer(line):
                            for t in _set(m.group(1)):
                                seen[t] = seen.get(t, 0) + 1
                    m = HEADER.match(line.strip())
                    if m and m.group(1) in ("AllowLoadGameType", "ExcludeLoadGameType"):
                        for t in _set(m.group(2)):
                            seen[t] = seen.get(t, 0) + 1
    return seen


def game_folders(root):
    """Folder names used for per-game files inside addons (Camelot, Cata...)."""
    names = {}
    for addon in os.listdir(root):
        d = os.path.join(root, addon)
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if os.path.isdir(os.path.join(d, f)) and f[:1].isupper():
                names[f] = names.get(f, 0) + 1
    return names
