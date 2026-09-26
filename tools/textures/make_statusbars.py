"""Generate EvermoreUI statusbar textures as uncompressed 32-bit TGA.

Every texture is greyscale: the bar's vertex colour (class, reaction, power)
multiplies it, so white keeps the colour true and grey darkens it. Most are
horizontally uniform so the StatusBar's crop/stretch as it fills can't distort
them; Inset is the exception (it shades the left and right edges too). Output goes to EvermoreUI/Media/Statusbar.

    python tools/textures/make_statusbars.py
"""
import math, os, struct

W, H = 256, 32          # powers of two, required by the client
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "EvermoreUI", "Media", "Statusbar")

def lerp(a, b, t): return a + (b - a) * t
def smooth(t): return t * t * (3 - 2 * t)

# Each profile maps t (0 = top row, 1 = bottom row) to brightness 0..1.
def evermore(t, y):
    if y == 0: return 0.97                    # crisp top highlight
    if y == H - 1: return 0.52                # dark foot for definition
    return lerp(0.90, 0.66, smooth(t))

def soft(t, y):
    # Rounded: brightest a third of the way down, falling off to the edges.
    d = (t - 0.33) / (0.67 if t > 0.33 else 0.33)
    return lerp(0.92, 0.70, min(1, abs(d)) ** 1.6)

def matte(t, y):
    return lerp(0.84, 0.74, t)

def split(t, y):
    if t < 0.5: return lerp(0.95, 0.84, t / 0.5)
    return lerp(0.74, 0.66, (t - 0.5) / 0.5)

PROFILES = {"Evermore": evermore, "Soft": soft, "Matte": matte, "Split": split}

# 2D profiles: fn(x, y) -> brightness, for textures that vary along the bar.
def inset(x, y):
    # Recessed look: flat bright face, inner shadow on all four edges.
    # Vertical depth is a fraction of height so it survives squashing onto a
    # thin power bar; horizontal depth is ~6px at typical frame widths.
    def fall(d, depth, strength):
        if d >= depth: return 1.0
        k = 1 - d / depth
        return 1 - strength * k * k
    dy_top, dy_bot = y + 0.5, H - y - 0.5
    dx = min(x + 0.5, W - x - 0.5)
    v = 0.90
    v *= fall(dy_top, H * 0.30, 0.50)         # heavier from the top, like light from above
    v *= fall(dy_bot, H * 0.22, 0.38)
    v *= fall(dx, 7, 0.42)
    return v

PROFILES_2D = {"Inset": inset}

def write_tga2d(path, fn):
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x08)
    body = bytearray()
    for y in reversed(range(H)):
        for x in range(W):
            g = max(0, min(255, round(fn(x, y) * 255)))
            body += bytes((g, g, g, 255))
    with open(path, "wb") as f:
        f.write(hdr + body)

def write_tga(path, rows):
    # Header: no ID, no colour map, type 2 (uncompressed true colour),
    # 32 bpp, descriptor 0x08 = 8 alpha bits, bottom-left origin.
    hdr = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, W, H, 32, 0x08)
    body = bytearray()
    for v in reversed(rows):                  # bottom-left origin: last row first
        g = max(0, min(255, round(v * 255)))
        body += bytes((g, g, g, 255)) * W     # BGRA
    with open(path, "wb") as f:
        f.write(hdr + body)

os.makedirs(OUT, exist_ok=True)
for name, fn in PROFILES.items():
    rows = [fn(y / (H - 1), y) for y in range(H)]
    write_tga(os.path.join(OUT, name + ".tga"), rows)
    print(name, " ".join(f"{r:.2f}" for r in rows[::4]))
for name, fn in PROFILES_2D.items():
    write_tga2d(os.path.join(OUT, name + ".tga"), fn)
    print(name, " ".join(f"{fn(W // 2, y):.2f}" for y in range(0, H, 4)))
