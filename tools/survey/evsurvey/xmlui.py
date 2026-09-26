"""Parse Blizzard UI XML into plain node dicts.

Node keys (short, the manifest is large):
  t   tag            n   name            k   parentKey      arr parentArray
  i   inherits list  m   mixin list      v   virtual        x   intrinsic
  l   draw layer     s   sublevel        a   atlas          f   file
  c   colour ([r,g,b,a] or a global name)                   fo  font object
  h   hidden         ch  children        role  button art slot (NormalTexture...)
"""
import re
import xml.etree.ElementTree as ET

REGION = {"Texture", "FontString", "MaskTexture", "Line", "MaskedTexture"}
# Button/StatusBar art given by element name rather than a parentKey.
SLOT_ART = {
    "NormalTexture", "PushedTexture", "HighlightTexture", "DisabledTexture",
    "CheckedTexture", "DisabledCheckedTexture", "ThumbTexture", "BarTexture",
    "ColorWheelTexture", "ColorWheelThumbTexture", "ColorValueTexture", "ColorValueThumbTexture",
}
SLOT_FONT = {"ButtonText"}
NOT_FRAMES = {
    "Script", "Include", "Font", "FontFamily", "Anchors", "Size", "Layers", "Frames",
    "Scripts", "KeyValues", "Animations", "AnimationGroup", "Attributes", "HitRectInsets",
    "TexCoords", "Color", "Shadow", "Backdrop", "ResizeBounds", "NormalFont", "HighlightFont",
    "DisabledFont", "PushedTextOffset", "FontHeight", "Offset", "Margins", "Member",
    "ScrollChild", "TextInsets", "Gradient", "Binding", "Bindings", "ModifiedClick",
} | REGION | SLOT_ART | SLOT_FONT


def local(tag):
    return tag.rsplit("}", 1)[-1]


def _split(v):
    return [x.strip() for x in v.split(",") if x.strip()] if v else []


def _truthy(v):
    return v is not None and v.lower() == "true"


def _color(el):
    for c in el:
        if local(c.tag) == "Color":
            if c.get("color"):
                return c.get("color")
            try:
                return [float(c.get("r", 0)), float(c.get("g", 0)), float(c.get("b", 0)), float(c.get("a", 1))]
            except ValueError:
                return None
    return None


def _region(el, layer, sub):
    t = local(el.tag)
    n = {"t": t}
    for src, dst in (("name", "n"), ("parentKey", "k"), ("parentArray", "arr"), ("atlas", "a"), ("file", "f")):
        if el.get(src):
            n[dst] = el.get(src)
    if el.get("inherits"):
        n["i"] = _split(el.get("inherits"))
    if _truthy(el.get("virtual")):
        n["v"] = True
    if _truthy(el.get("hidden")):
        n["h"] = True
    if layer:
        n["l"] = layer
    if sub:
        n["s"] = sub
    c = _color(el)
    if c is not None:
        n["c"] = c
    if t == "FontString" and el.get("inherits"):
        n["fo"] = _split(el.get("inherits"))[0]
    return n


def _frame(el):
    t = local(el.tag)
    n = {"t": t}
    for src, dst in (("name", "n"), ("parentKey", "k"), ("parentArray", "arr")):
        if el.get(src):
            n[dst] = el.get(src)
    if el.get("inherits"):
        n["i"] = _split(el.get("inherits"))
    if el.get("mixin"):
        n["m"] = _split(el.get("mixin"))
    if _truthy(el.get("virtual")):
        n["v"] = True
    if _truthy(el.get("intrinsic")):
        n["x"] = True
    if _truthy(el.get("hidden")):
        n["h"] = True
    if el.get("parent"):
        n["p"] = el.get("parent")
    ch = []
    for c in el:
        ct = local(c.tag)
        if ct == "Layers":
            for layer in c:
                if local(layer.tag) != "Layer":
                    continue
                lv = layer.get("level", "ARTWORK")
                sub = layer.get("textureSubLevel")
                for r in layer:
                    if local(r.tag) in REGION:
                        ch.append(_region(r, lv, sub))
        elif ct == "Frames":
            for f in c:
                if local(f.tag) not in NOT_FRAMES:
                    ch.append(_frame(f))
        elif ct == "ScrollChild":
            for f in c:
                sc = _frame(f)
                sc.setdefault("k", "ScrollChild")
                ch.append(sc)
        elif ct in SLOT_ART:
            r = _region(c, "ARTWORK", None)
            r["role"] = ct
            ch.append(r)
        elif ct in SLOT_FONT:
            r = _region(c, "OVERLAY", None)
            r["t"] = "FontString"
            r["role"] = ct
            ch.append(r)
        elif ct == "KeyValues":
            kv = {}
            for k in c:
                if local(k.tag) == "KeyValue" and k.get("key"):
                    kv[k.get("key")] = k.get("value")
            if kv:
                n["kv"] = kv
    if ch:
        n["ch"] = ch
    return n


def _font(el):
    n = {"t": "Font"}
    if el.get("inherits"):
        n["i"] = _split(el.get("inherits"))
    c = _color(el)
    if c is not None:
        n["c"] = c
    if el.get("height"):
        try:
            n["size"] = float(el.get("height"))
        except ValueError:
            pass
    for c in el:
        if local(c.tag) == "FontHeight":
            for av in c:
                if av.get("val"):
                    try:
                        n["size"] = float(av.get("val"))
                    except ValueError:
                        pass
    return n


AMP = re.compile(r"&(?!(amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)")


def parse(path):
    """Returns (includes, top-level nodes, fonts, error)."""
    with open(path, encoding="utf-8", errors="ignore") as fh:
        text = fh.read()
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        try:
            root = ET.fromstring(AMP.sub("&amp;", text))
        except ET.ParseError as e:
            return [], [], {}, str(e)
    includes, nodes, fonts = [], [], {}

    def top(parent):
        for el in parent:
            if local(el.tag) == "ScopedModifier":
                yield from top(el)
            else:
                yield el

    for el in top(root):
        t = local(el.tag)
        if t in ("Include", "Script"):
            if el.get("file"):
                includes.append((t, el.get("file").replace("\\", "/")))
        elif t == "Font":
            if el.get("name"):
                fonts[el.get("name")] = _font(el)
        elif t == "FontFamily":
            name = el.get("name")
            for m in el:
                if local(m.tag) == "Member":
                    for f in m:
                        if local(f.tag) == "Font" and name:
                            fonts.setdefault(name, _font(f))
                            break
        elif t in REGION:
            nodes.append(_region(el, None, None))
        elif t not in NOT_FRAMES:
            nodes.append(_frame(el))
    return includes, nodes, fonts, None
