"""Draws the app icon / splash artwork (3 faders over a keyboard) with Pillow.

    python3 tools/make_icons.py

Writes assets/icon/{icon,icon_fg,splash,splash_android12}.png; then run
`dart run flutter_launcher_icons && dart run flutter_native_splash:create`.
"""
from PIL import Image, ImageDraw, ImageFilter

BG_TOP, BG_BOTTOM = (22, 22, 25), (8, 8, 10)
TILE, KEY, KEY_DARK = (230, 227, 224), (239, 238, 236), (19, 19, 20)
ORANGE, RED = (255, 138, 31), (255, 59, 48)
SS = 2  # supersampling


def rr(d, box, r, fill, outline=None, width=0):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def motif(d, ox, oy, side):
    """Draw the artwork inside the square (ox, oy, side)."""
    u = side / 100.0

    def P(x, y):
        return ox + x * u, oy + y * u

    # --- three faders on off-white tiles (top 60 %)
    tile_w, gap, top, tile_h = 28, 6, 4, 56
    x0 = (100 - (3 * tile_w + 2 * gap)) / 2
    levels = [0.62, 0.30, 0.48]
    for i, lv in enumerate(levels):
        tx = x0 + i * (tile_w + gap)
        rr(d, (*P(tx, top), *P(tx + tile_w, top + tile_h)), 4.5 * u, TILE)
        gx = tx + tile_w / 2
        gy0, gy1 = top + 7, top + tile_h - 7
        rr(d, (*P(gx - 1.6, gy0), *P(gx + 1.6, gy1)), 1.6 * u, KEY_DARK)
        cy = gy1 - (gy1 - gy0) * lv
        rr(d, (*P(gx - 1.6, cy), *P(gx + 1.6, gy1)), 1.6 * u, ORANGE)
        rr(d, (*P(gx - 8.5, cy - 4.2), *P(gx + 8.5, cy + 4.2)), 2.8 * u, (40, 40, 44),
           outline=(110, 110, 116), width=max(1, int(0.8 * u)))
        d.line((*P(gx - 5.5, cy), *P(gx + 5.5, cy)), fill=RED, width=max(2, int(1.3 * u)))

    # --- keyboard strip (bottom 34 %)
    ky0, ky1 = 68, 98
    n, kx0, kx1 = 6, 4, 96
    kw = (kx1 - kx0) / n
    pressed = 3
    for i in range(n):
        x = kx0 + i * kw
        fill = ORANGE if i == pressed else KEY
        rr(d, (*P(x + 0.8, ky0), *P(x + kw - 0.8, ky1)), 3 * u, fill)
        # square the top corners
        d.rectangle((*P(x + 0.8, ky0), *P(x + kw - 0.8, ky0 + 4)), fill=fill)
    for i in (0, 1, 3, 4):  # black keys between whites (skip the gap after #2)
        x = kx0 + (i + 1) * kw
        rr(d, (*P(x - 3.6, ky0), *P(x + 3.6, ky0 + 18)), 2 * u,
           ORANGE if False else KEY_DARK)


def background(size):
    img = Image.new("RGB", (size, size))
    px = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        px.line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    return img


def render(size, scale, with_bg):
    big = size * SS
    img = background(big).convert("RGBA") if with_bg else Image.new("RGBA", (big, big), (0, 0, 0, 0))
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    side = big * scale
    motif(d, (big - side) / 2, (big - side) / 2, side)
    # soft glow under the pressed key
    glow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    u = side / 100.0
    ox = oy = (big - side) / 2
    kw = (96 - 4) / 6
    gx = ox + (4 + 3.5 * kw) * u
    gd.ellipse((gx - 14 * u, oy + 78 * u, gx + 14 * u, oy + 104 * u), fill=(255, 138, 31, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(5 * u))
    img = Image.alpha_composite(img, glow)
    img = Image.alpha_composite(img, layer)
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    # Full-bleed square (iOS / macOS / legacy Android): artwork fills the icon.
    render(1024, 0.84, True).convert("RGB").save("assets/icon/icon.png")
    # Adaptive foreground: transparent, artwork inside the 66 % safe zone.
    render(1024, 0.60, False).save("assets/icon/icon_fg.png")
    # Android 12 splash: the system crops the icon to a circle (2/3 of the canvas),
    # so the whole artwork has to fit inside that circle.
    render(1024, 0.47, False).save("assets/icon/splash_android12.png")
    # Splash: transparent artwork.
    render(768, 1.0, False).save("assets/icon/splash.png")
    print("icons written")
