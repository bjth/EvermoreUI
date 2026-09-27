"""Every template as the object it would build, written out for Lua.

fingerprint.py runs a Python copy of each part's fingerprint. That copy is
kept in step by hand, so it can drift from Parts.lua without anyone noticing
(it had: `moneyBox` was registered for a week before the copy knew about it).
This module takes the copy out of the measurement. It flattens each template
into the tree of objects the client would build from it, inheritance and all,
and writes that tree as a Lua table. tools/survey/coverage.lua then loads the
real Core.lua and Parts.lua and runs the real `S.Matches` over it.

Only data crosses over. No rule about what matches lives in this file.
"""

# Object type -> the type it derives from, for IsObjectType. Everything
# bottoms out at Frame. Region types are listed so a region answers
# IsObjectType("Texture") the way the client does.
PARENT = {
    "Button": "Frame", "CheckButton": "Button", "EventButton": "Button",
    "DropdownButton": "Button", "ItemButton": "Button", "AuraButton": "Button",
    "ContainedAlertFrame": "Button", "DropDownToggleButton": "Button",
    "EventFrame": "Frame", "EditBox": "Frame", "EventEditBox": "EditBox",
    "StatusBar": "Frame", "Slider": "Frame", "ScrollFrame": "Frame",
    "EventScrollFrame": "ScrollFrame", "GameTooltip": "Frame",
    "ColorSelect": "Frame", "MessageFrame": "Frame",
    "ScrollingMessageFrame": "Frame", "SimpleHTML": "Frame", "Cooldown": "Frame",
    "Model": "Frame", "PlayerModel": "Model", "DressUpModel": "PlayerModel",
    "CinematicModel": "PlayerModel", "TabardModel": "PlayerModel",
    "ModelScene": "Frame", "MovieFrame": "Frame", "Minimap": "Frame",
    "AuraContainer": "Frame", "ArchaeologyDigSiteFrame": "Frame",
    "ScenarioPOIFrame": "Frame", "QuestPOIFrame": "Frame",
    "UnitPositionFrame": "Frame", "OffScreenFrame": "Frame",
    "FogOfWarFrame": "Frame", "Checkout": "Frame", "POIFrame": "Frame",
    "WorldFrame": "Frame", "Browser": "Frame",
    "MaskTexture": "Texture", "Line": "Texture",
}

# XML element names that build a region rather than a frame, and which kind.
# The button art slots (<NormalTexture>, <ButtonText>...) are elements of
# their own in the XML but build an ordinary Texture or FontString.
TEXTURE_TAGS = {"Texture", "MaskTexture", "Line", "HighlightTexture",
                "NormalTexture", "PushedTexture", "DisabledTexture",
                "CheckedTexture", "DisabledCheckedTexture", "ThumbTexture",
                "BarTexture"}
FONT_TAGS = {"FontString", "ButtonText", "NormalFont", "HighlightFont",
             "DisabledFont"}
REGION_TAGS = TEXTURE_TAGS | FONT_TAGS

MAX_DEPTH = 6


def _is_frame(tag):
    """True for a frame type. Animations, actors and regions are not."""
    seen = 0
    while tag and seen < 12:
        if tag == "Frame":
            return True
        tag = PARENT.get(tag)
        seen += 1
    return False


def flatten(node, templates, depth=0, seen=None):
    """The object a node builds: its type, art, KeyValues and children.

    Inherited declarations come first and the node's own come after, which is
    the order the client applies them in, so a later parentKey wins.
    """
    seen = set(seen or ())
    out = {"t": None, "a": None, "f": None, "kv": {}, "ch": []}
    if depth > MAX_DEPTH:
        out["cut"] = True
        return out
    for parent in node.get("i") or []:
        pn = templates.get(parent)
        if pn is None or parent in seen:
            continue
        base = flatten(pn, templates, depth + 1, seen | {parent})
        if base["t"] and (out["t"] is None or out["t"] == "Frame"):
            out["t"] = base["t"]
        out["a"] = base["a"] or out["a"]
        out["f"] = base["f"] or out["f"]
        out["kv"].update(base["kv"])
        for c in base["ch"]:
            c["own"] = False      # declared by the parent template, measured there
        out["ch"].extend(base["ch"])
        if base.get("cut"):
            out["cut"] = True
    own = node.get("t")
    if own and (out["t"] is None or own != "Frame"):
        out["t"] = own
    # An atlas and a file on the same element: the atlas is what draws.
    if node.get("a"):
        out["a"], out["f"] = node["a"], None
    elif node.get("f"):
        out["f"], out["a"] = node["f"], None
    out["kv"].update(node.get("kv") or {})
    for ch in node.get("ch") or []:
        c = flatten(ch, templates, depth + 1, seen)
        for key, dst in (("k", "k"), ("n", "n"), ("role", "role"), ("arr", "arr")):
            if ch.get(key):
                c[dst] = ch[key]
        c["own"] = True
        out["ch"].append(c)
    return out


# --- Lua serialisation -----------------------------------------------------
def _lstr(s):
    s = str(s)
    return '"' + (s.replace("\\", "\\\\").replace('"', '\\"')
                   .replace("\n", "\\n").replace("\r", "\\r")) + '"'


def _lobj(o, out):
    out.append("{")
    for key in ("t", "a", "f", "k", "n", "role", "arr"):
        if o.get(key):
            out.append("%s=%s," % (key, _lstr(o[key])))
    if o.get("own"):
        out.append("own=true,")
    if o.get("kv"):
        out.append("kv={")
        for k in sorted(o["kv"]):
            out.append("[%s]=%s," % (_lstr(k), _lstr(o["kv"][k])))
        out.append("},")
    if o.get("ch"):
        out.append("ch={")
        for c in o["ch"]:
            _lobj(c, out)
            out.append(",")
        out.append("},")
    out.append("}")


def to_lua(manifest, counts):
    """The whole manifest's templates as one Lua chunk returning a table."""
    templates = manifest["templates"]
    out = ["-- Generated by tools/survey/evsurvey/shapes.py. Not committed.\n",
           "return {\nparent={"]
    for k in sorted(PARENT):
        out.append("[%s]=%s," % (_lstr(k), _lstr(PARENT[k])))
    out.append("},\ntexture={")
    out.extend("[%s]=true," % _lstr(t) for t in sorted(TEXTURE_TAGS))
    out.append("},\nfont={")
    out.extend("[%s]=true," % _lstr(t) for t in sorted(FONT_TAGS))
    out.append("},\ntemplates={\n")
    for name in sorted(templates):
        shape = flatten(templates[name], templates, 0, {name})
        if not _is_frame(shape["t"]):
            continue
        out.append("{name=%s,count=%d,obj=" % (_lstr(name), counts.get(name, 0)))
        _lobj(shape, out)
        out.append("},\n")
    # Named frames are real instances: what the player actually sees.
    out.append("},\nframes={\n")
    for name in sorted(manifest.get("frames") or {}):
        shape = flatten(manifest["frames"][name], templates, 0, set())
        if not _is_frame(shape["t"]):
            continue
        out.append("{name=%s,count=1,obj=" % _lstr(name))
        _lobj(shape, out)
        out.append("},\n")
    out.append("}}\n")
    return "".join(out)
