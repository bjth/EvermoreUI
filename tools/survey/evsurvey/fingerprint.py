"""Run EvermoreUI_Skins part fingerprints against the manifest, statically.

A part in Parts.lua matches an object at runtime by its shape: object type,
parent keys that hold a real table, and the atlas or texture on a named
region. The manifest records exactly that shape for every template Blizzard
declares, so the same match can be run here, offline, against all 2,900 of
them at once.

That turns coverage from a hand-maintained claim into a measurement, and it
catches the two failure modes a claim never will:

  * a part whose fingerprint matches NOTHING (too strict, or keyed on
    something this client does not expose)
  * a part that matches templates it was never meant to claim, or that
    shadows a later part because it is registered first

Limits, stated plainly: this reads Blizzard's XML, so it sees templates and
their inheritance, not frames built in Lua at runtime, and not what a
`test` function does beyond the texture checks modelled below. A template
reported as matched will be claimed in game; a template reported as
unmatched may still be claimed if Lua adds the missing key later.
"""
import re

# --- object type hierarchy, for IsObjectType -------------------------------
# Only what matters for the parts. Everything bottoms out at Frame.
PARENT = {
    "Button": "Frame", "CheckButton": "Button", "EventButton": "Button",
    "DropdownButton": "Button", "ItemButton": "Button", "EventFrame": "Frame",
    "EditBox": "Frame", "StatusBar": "Frame", "Slider": "Frame",
    "ScrollFrame": "Frame", "GameTooltip": "Frame", "ColorSelect": "Frame",
    "MessageFrame": "Frame", "ScrollingMessageFrame": "Frame",
    "SimpleHTML": "Frame", "Cooldown": "Frame", "Model": "Frame",
    "PlayerModel": "Model", "DressUpModel": "PlayerModel", "ModelScene": "Frame",
    "CinematicModel": "PlayerModel", "TabardModel": "PlayerModel",
    "MovieFrame": "Frame", "Minimap": "Frame", "ArchaeologyDigSiteFrame": "Frame",
    "ScenarioPOIFrame": "Frame", "QuestPOIFrame": "Frame", "UnitPositionFrame": "Frame",
    "OffScreenFrame": "Frame", "FogOfWarFrame": "Frame", "Checkout": "Frame",
    "POIFrame": "Frame", "WorldFrame": "Frame", "Browser": "Frame",
}
REGION_TAGS = {"Texture", "FontString", "MaskTexture", "Line", "MaskedTexture"}


def is_type(tag, want):
    seen = 0
    while tag and seen < 12:
        if tag == want:
            return True
        tag = PARENT.get(tag)
        seen += 1
    return False


# --- Lua pattern -> Python regex -------------------------------------------
def lua_pattern(p):
    """Translate the subset of Lua patterns the parts actually use."""
    out, i = [], 0
    while i < len(p):
        c = p[i]
        if c == "%" and i + 1 < len(p):
            nxt = p[i + 1]
            if nxt == "d":
                out.append(r"\d")
            elif nxt == "a":
                out.append("[A-Za-z]")
            elif nxt == "s":
                out.append(r"\s")
            elif nxt == "w":
                out.append(r"\w")
            else:
                out.append(re.escape(nxt))
            i += 2
            # Lua's lazy '-' quantifier
            if i < len(p) and p[i] == "-":
                out.append("*?")
                i += 1
            continue
        if c == "-":
            out.append("*?")
        elif c in ".^$*+?()[]{}|\\":
            out.append(re.escape(c) if c not in "^$" else c)
        else:
            out.append(c)
        i += 1
    return re.compile("".join(out))


# --- resolving a template's effective shape --------------------------------
class Shape:
    """What a template looks like once its inheritance is flattened."""

    __slots__ = ("name", "tag", "keys", "art", "slots", "kv", "chain", "truncated")

    def __init__(self, name):
        self.name = name
        self.tag = None
        self.keys = {}      # parentKey -> node, direct children only
        self.art = {}       # parentKey -> (atlas, file)
        self.slots = {}     # NormalTexture/... -> (atlas, file)
        self.kv = {}        # KeyValues set on the frame itself (layoutType, ...)
        self.chain = []
        self.truncated = False


def _merge(shape, node, templates, seen, depth):
    if depth > 10:
        shape.truncated = True
        return
    # Inherited shape comes first; own declarations win.
    for parent in (node.get("i") or []):
        if parent in templates and parent not in seen:
            seen.add(parent)
            shape.chain.append(parent)
            _merge(shape, templates[parent], templates, seen, depth + 1)
    shape.kv.update(node.get("kv") or {})
    if shape.tag is None or node.get("t") not in (None, "Frame"):
        shape.tag = node.get("t") or shape.tag
    for ch in (node.get("ch") or []):
        k = ch.get("k")
        role = ch.get("role")
        atlas, file = ch.get("a"), ch.get("f")
        # A child frame that inherits a template can carry the art we test.
        if not atlas and not file:
            for parent in (ch.get("i") or []):
                pn = templates.get(parent)
                if pn:
                    atlas = atlas or pn.get("a")
                    file = file or pn.get("f")
        if k:
            shape.keys[k] = ch
            if atlas or file:
                shape.art[k] = (atlas, file)
        else:
            # Older templates attach nothing and name the region "$parentLeft",
            # reachable only as the global FrameNameLeft. S.Sub in Core.lua
            # looks both up, so the measurement has to as well or it reports
            # coverage we actually have as a gap.
            n = ch.get("n") or ""
            if n.startswith("$parent") and len(n) > 7:
                suffix = n[7:]
                shape.keys.setdefault(suffix, ch)
                if (atlas or file) and suffix not in shape.art:
                    shape.art[suffix] = (atlas, file)
        if role:
            shape.slots[role] = (atlas, file)
        # Regions declared inside a child frame belong to that child, not here.


def resolve(name, templates, frames=None):
    node = templates.get(name) or (frames or {}).get(name)
    if not node:
        return None
    s = Shape(name)
    _merge(s, node, templates, {name}, 0)
    if s.tag is None:
        s.tag = node.get("t")
    return s


def resolve_all(manifest):
    t = manifest["templates"]
    return {n: resolve(n, t) for n in t}


# --- the parts, as they are registered in Parts.lua ------------------------
# Mirrors EvermoreUI_Skins/Parts.lua, IN REGISTRATION ORDER. Keep in step by
# hand; the report flags any name here that Parts.lua no longer registers and
# any part Parts.lua registers that is missing here.
def _art(pattern):
    rx = lua_pattern(pattern)

    def check(pair):
        if not pair:
            return False
        atlas, file = pair
        # ArtIs tries GetAtlas() then GetTexture(). In this client
        # GetTexture() on XML file art returns "FileData ID N", never the
        # path, so a file texture can only match if the pattern would match
        # that string, which it never does. Model that honestly.
        return bool(atlas and rx.search(atlas.lower()))

    check.pattern = pattern
    check.file_only_would_match = lambda pair: bool(
        pair and pair[1] and rx.search(pair[1].lower().replace("\\", "/")))
    return check


FURNITURE = ["TitleContainer", "TitleText", "PortraitContainer", "portrait",
             "CloseButton", "Inset", "TitleBg"]

WINDOW_LAYOUTS = ["PortraitFrameTemplate", "PortraitFrameTemplateMinimizable",
                  "ButtonFrameTemplateNoPortrait", "HeldBagLayout",
                  "SimplePanelTemplate", "SelectionFrameTemplate"]

def _file(path):
    want = path.lower().replace("\\", "/")

    def check(pair):
        if not pair:
            return False
        atlas, file = pair
        if atlas:        # atlas-backed regions are excluded, as ArtIsFile does
            return False
        return bool(file and file.lower().replace("\\", "/") == want)

    check.pattern = path
    check.file_only_would_match = lambda pair: False
    return check


PARTS = [
    dict(name="tooltip", layout=["TooltipDefaultLayout", "TooltipMixedLayout",
                                 "TooltipGluesLayout", "ChatBubble"], stop=True),
    dict(name="slider", tag="Slider", keys=["Thumb"]),
    dict(name="closeButton", tag="Button",
         slot_art={"NormalTexture": _art("redbutton%-exit")}),
    dict(name="maxMin", tag="Button",
         slot_any={"NormalTexture": [_art("redbutton%-expand"), _art("condense"),
                                     _art("uitools%-icon%-%a-size"),
                                     _art("%-maximize"), _art("%-minimize")]}),
    dict(name="panelTab", tag="Button",
         keys=["Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive"]),
    dict(name="stretchButton", tag="Button",
         keys=["TopLeft", "TopMiddle", "TopRight", "MiddleLeft", "MiddleMiddle",
               "MiddleRight", "BottomLeft", "BottomMiddle", "BottomRight"]),
    dict(name="panelButton", tag="Button", keys=["Left", "Middle", "Right", "Text"]),
    dict(name="radioButton", tag="CheckButton",
         slot_art={"NormalTexture": _file("Interface\\Buttons\\UI-RadioButton")}),
    dict(name="checkButton", tag="CheckButton",
         slot_any={"NormalTexture": [_art("checkbox%-minimal"),
                                     _art("checkbox%-?%d*$"),
                                     _art("common%-checkbox"),
                                     _file("Interface\\Buttons\\UI-CheckBox-Up")]}),
    dict(name="dropdown", keys=["Arrow", "Background", "Text"]),
    dict(name="searchBox", tag="EditBox", keys=["searchIcon", "clearButton"]),
    dict(name="inputBox", tag="EditBox", keys_any=["Left", "LeftTex", "MiddleTex"]),
    dict(name="scrollBar", keys=["Track"], keys_any_extra=["Back", "Forward"],
         nested_any=[("Track", "Thumb")]),
    dict(name="navBar", keys=["overlay", "overflow", "home"]),
    # navCrumb fingerprints on "my parent is a nav bar". That is a runtime
    # relationship: the XML does not say who a pooled button's parent will
    # be, and the home and overflow buttons are handed to NavBar_Initialize
    # rather than built from a template. So it cannot be matched statically.
    # Flagged rather than faked, so the report does not call it dead.
    dict(name="navCrumb", tag="Button", unmodelled=True,
         reason="matches on parent identity, which only exists at runtime",
         runtime_claims=["NavButtonTemplate"]),
    dict(name="scrollBarLegacy", tag="Slider", without=["Thumb"],
         keys_any=["ThumbTexture", "thumbTexture", "ScrollUpButton"]),
    dict(name="inset", layout=["InsetFrameTemplate"]),
    dict(name="dialogBorder", layout=["Dialog"]),
    dict(name="window", layout=WINDOW_LAYOUTS),
    dict(name="panel", keys=["NineSlice"], furniture=True),
    dict(name="ninesliceBox", keys=["NineSlice"]),
]


def matches(part, shape, templates):
    if part.get("layout"):
        if shape.kv.get("layoutType") not in part["layout"]:
            return False
    if part.get("furniture") and not any(k in shape.keys for k in FURNITURE):
        return False
    if part.get("tag") and not is_type(shape.tag, part["tag"]):
        return False
    for k in part.get("without", []):
        if k in shape.keys:
            return False
    for k in part.get("keys", []):
        if k not in shape.keys:
            return False
    if "keys_any" in part and not any(k in shape.keys for k in part["keys_any"]):
        return False
    if "keys_any_extra" in part:
        ok = any(k in shape.keys for k in part["keys_any_extra"])
        for owner, child in part.get("nested_any", []):
            node = shape.keys.get(owner)
            if node and any(c.get("k") == child for c in (node.get("ch") or [])):
                ok = True
        if not ok:
            return False
    for k, check in part.get("key_art", {}).items():
        if not check(shape.art.get(k)):
            return False
    for slot, check in part.get("slot_art", {}).items():
        if not check(shape.slots.get(slot)):
            return False
    for slot, checks in part.get("slot_any", {}).items():
        if not any(c(shape.slots.get(slot)) for c in checks):
            return False
    return True


def classify(manifest, counts):
    """For every template: which part claims it, and which would have."""
    templates = manifest["templates"]
    shapes = resolve_all(manifest)
    claimed, all_hits = {}, {}
    live = [p for p in PARTS if not p.get("unmodelled")]
    for name, shape in shapes.items():
        if not shape or shape.tag in REGION_TAGS:
            continue
        hits = [p["name"] for p in live if matches(p, shape, templates)]
        if hits:
            claimed[name] = hits[0]      # first match wins, as S.Dress does
            all_hits[name] = hits
    # An unmodelled part is not a dead part: it simply cannot be measured
    # from the XML. Keep the two apart or the report starts lying.
    dead = [p["name"] for p in PARTS
            if not p.get("unmodelled") and p["name"] not in set(claimed.values())]
    shadowed = {n: h for n, h in all_hits.items() if len(h) > 1}
    return shapes, claimed, all_hits, dead, shadowed


def unmodelled():
    """Parts the static matcher cannot evaluate, with why, and what they claim."""
    return [(p["name"], p.get("reason", ""), p.get("runtime_claims") or [])
            for p in PARTS if p.get("unmodelled")]


def near_misses(part_name, manifest, shapes, counts, limit=15):
    """Templates that fail ONE condition of a part. Where a fingerprint leaks."""
    part = next((p for p in PARTS if p["name"] == part_name), None)
    if not part:
        return []
    templates = manifest["templates"]
    out = []
    for name, shape in shapes.items():
        if not shape or shape.tag in REGION_TAGS or matches(part, shape, templates):
            continue
        fails = []
        if part.get("tag") and not is_type(shape.tag, part["tag"]):
            fails.append("type is %s, wants %s" % (shape.tag, part["tag"]))
        missing = [k for k in part.get("keys", []) if k not in shape.keys]
        if missing:
            fails.append("no key " + "/".join(missing))
        for k, check in part.get("key_art", {}).items():
            pair = shape.art.get(k)
            if k in shape.keys and not check(pair):
                if pair and pair[1] and check.file_only_would_match(pair):
                    fails.append("%s art is a FILE (%s), pattern %r can only match an atlas"
                                 % (k, pair[1], check.pattern))
                else:
                    fails.append("%s art %r does not match %r"
                                 % (k, pair, check.pattern))
        for slot, check in part.get("slot_art", {}).items():
            pair = shape.slots.get(slot)
            if pair and not check(pair):
                if pair[1] and check.file_only_would_match(pair):
                    fails.append("%s is a FILE (%s), pattern %r can only match an atlas"
                                 % (slot, pair[1], check.pattern))
                else:
                    fails.append("%s %r does not match %r" % (slot, pair, check.pattern))
        if len(fails) == 1:
            out.append((counts.get(name, 0), name, fails[0]))
    out.sort(reverse=True)
    return out[:limit]
