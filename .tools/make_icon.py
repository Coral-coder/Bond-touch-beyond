#!/usr/bin/env python3
"""Generate the Bond Touch Beyond app icon: a silver polyamory infinity-heart
on a dark ombre sphere that fades to a black edge. 1024x1024, opaque."""
import math
from PIL import Image, ImageDraw, ImageFilter

SS = 4            # supersample factor
W = 1024 * SS
CX = W / 2

# ---------------------------------------------------------------- background
def make_background():
    """Black canvas with a dark charcoal sphere, lit top-left, fading to black
    at the rim (the 'clear edge black center ombre ball')."""
    bg = Image.new("RGB", (W, W), (0, 0, 0))
    px = bg.load()
    R = W * 0.47                       # sphere radius
    # specular highlight centre, offset up-left for a 3D ball read
    lx, ly = CX - R * 0.33, CX - R * 0.36
    for y in range(W):
        for x in range(W):
            dx, dy = x - CX, y - CX
            d = math.hypot(dx, dy)
            if d > R:
                continue               # stays pure black -> clear edge
            # radial falloff from rim (0) to centre (1)
            t = 1.0 - (d / R)
            core = 8 + 26 * (t ** 1.6)          # charcoal core, darker at rim
            # soft specular sheen toward top-left
            ld = math.hypot(x - lx, y - ly)
            spec = max(0.0, 1.0 - ld / (R * 1.15)) ** 2.2
            v = core + spec * 70
            # cool blue-grey tint
            r = int(min(255, v * 0.82))
            g = int(min(255, v * 0.90))
            b = int(min(255, v * 1.05))
            px[x, y] = (r, g, b)
    return bg

# ---------------------------------------------------------------- path maths
def heart_points(cx, cy, scale, n=1400):
    pts = []
    for i in range(n + 1):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((cx + x * scale, cy - y * scale))
    return pts

def infinity_points(cx, cy, a, n=1400):
    """Lemniscate of Gerono-ish horizontal figure-eight."""
    pts = []
    for i in range(n + 1):
        t = 2 * math.pi * i / n
        denom = 1 + math.sin(t) ** 2
        x = a * math.cos(t) / denom
        y = a * math.sin(t) * math.cos(t) / denom
        pts.append((cx + x, cy + y))
    return pts

def stroke(mask, pts, radius):
    d = ImageDraw.Draw(mask)
    d.line(pts, fill=255, width=int(radius * 2), joint="curve")
    for (x, y) in pts:
        d.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)

# ---------------------------------------------------------------- silver fill
def silver_gradient():
    g = Image.new("RGB", (W, W), (0, 0, 0))
    px = g.load()
    stops = [(0.00, (253, 253, 255)),
             (0.22, (214, 219, 228)),
             (0.42, (150, 157, 168)),
             (0.52, (92, 98, 108)),
             (0.60, (170, 176, 186)),
             (0.80, (225, 229, 236)),
             (1.00, (120, 126, 136))]
    def lerp(a, b, u):
        return tuple(int(a[k] + (b[k] - a[k]) * u) for k in range(3))
    col = []
    for y in range(W):
        f = y / (W - 1)
        for j in range(len(stops) - 1):
            if stops[j][0] <= f <= stops[j + 1][0]:
                u = (f - stops[j][0]) / (stops[j + 1][0] - stops[j][0])
                col.append(lerp(stops[j][1], stops[j + 1][1], u))
                break
        else:
            col.append(stops[-1][1])
    for y in range(W):
        c = col[y]
        for x in range(W):
            px[x, y] = c
    return g

# ---------------------------------------------------------------- compose
bg = make_background()

# symbol geometry (in supersampled space)
heart_cy = CX - W * 0.045
heart = heart_points(CX, heart_cy, W * 0.0225)
infin = infinity_points(CX, CX + W * 0.11, W * 0.30)
tube = W * 0.030

# dark backing (slightly larger) for separation from the ball
backing = Image.new("L", (W, W), 0)
stroke(backing, heart, tube * 1.32)
stroke(backing, infin, tube * 1.32)
backing = backing.filter(ImageFilter.GaussianBlur(W * 0.004))
dark = Image.new("RGB", (W, W), (6, 8, 12))
bg = Image.composite(dark, bg, backing)

# main silver body
body = Image.new("L", (W, W), 0)
stroke(body, heart, tube)
stroke(body, infin, tube)
silver = silver_gradient()
bg = Image.composite(silver, bg, body)

# top sheen highlight: thinner path, nudged up, near-white, partial alpha
sheen = Image.new("L", (W, W), 0)
heart_h = heart_points(CX, heart_cy - tube * 0.42, W * 0.0225)
infin_h = infinity_points(CX, CX + W * 0.11 - tube * 0.42, W * 0.30)
stroke(sheen, heart_h, tube * 0.34)
stroke(sheen, infin_h, tube * 0.34)
sheen = sheen.filter(ImageFilter.GaussianBlur(W * 0.0015))
sheen = sheen.point(lambda v: int(v * 0.55))
white = Image.new("RGB", (W, W), (255, 255, 255))
bg = Image.composite(white, bg, sheen)

# downsample
out = bg.resize((1024, 1024), Image.LANCZOS)
out.save("/home/user/Bond-touch-beyond/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
# preview copy
out.save("/tmp/claude-0/-home-user-Bond-touch-beyond/578d54dd-9962-5345-912c-4a75289251a9/scratchpad/icon-preview.png")
print("wrote icon-1024.png")
