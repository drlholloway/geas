#!/usr/bin/env python3
"""Draw the Geas icon and write the platform masters.

The picture: a check mark bound inside a cord ring, for a geas, an
obligation you are bound to keep. Cream ink on the app's deep teal, with
one amber knot where the cord is tied.

Outputs (in apps/geas/assets/icon/):
  icon_1024.png        full-bleed square, rounded corners baked in
  icon_android_bg.png  adaptive-icon background layer: the teal
  icon_android_fg.png  adaptive-icon foreground layer: ring and check, in
                       the safe zone
  icon_macos.png       transparent canvas, Apple-style rounded square at
                       824/1024
  icon_512.png         smaller copy of the full-bleed master (AppImage)
Run with: python3 packaging/icon/make_icon.py
"""
import math
import os

from PIL import Image, ImageDraw

SS = 4  # supersampling factor
OUT = os.path.join(
    os.path.dirname(__file__), "..", "..", "apps", "geas", "assets", "icon"
)

TEAL_TOP = (36, 92, 87, 255)
TEAL_BOTTOM = (24, 64, 61, 255)
INK = (242, 232, 213, 255)    # cream
KNOT = (224, 160, 48, 255)    # amber, the medium-priority color


def background(size):
    """A top-to-bottom teal gradient."""
    img = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        color = tuple(
            round(a + (b - a) * t) for a, b in zip(TEAL_TOP, TEAL_BOTTOM)
        )
        draw.line([(0, y), (size, y)], fill=color)
    return img


def foreground(size, scale=1.0):
    """The ring, the check and the knot, centered, on transparency.

    Drawn in a 1000-unit square; [scale] shrinks it about the center.
    """
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def p(x, y):
        cx = 500 + (x - 500) * scale
        cy = 500 + (y - 500) * scale
        return (cx * big / 1000, cy * big / 1000)

    def w(units):
        return max(1, round(units * scale * big / 1000))

    # The cord ring, open at the upper right where the check breaks out.
    r = 300
    box = [p(500 - r, 500 - r), p(500 + r, 500 + r)]
    draw.arc(box, start=-20, end=300, fill=INK, width=w(56))

    # The check: short stroke down, long stroke up and out of the ring.
    pts = [p(330, 520), p(450, 640), p(760, 270)]
    draw.line(pts, fill=INK, width=w(84), joint="curve")
    for x, y in (pts[0], pts[-1]):
        rr = w(84) / 2
        draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=INK)

    # The knot where the ring ends, tying the check in.
    angle = math.radians(300)
    kx, ky = 500 + r * math.cos(angle), 500 + r * math.sin(angle)
    kx, ky = p(kx, ky)
    kr = w(52)
    draw.ellipse([kx - kr, ky - kr, kx + kr, ky + kr], fill=KNOT)

    return img.resize((size, size), Image.LANCZOS)


def rounded(img, radius_frac):
    """[img] with rounded corners."""
    size = img.size[0]
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * SS - 1, size * SS - 1],
        radius=round(size * SS * radius_frac),
        fill=255,
    )
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    size = 1024

    full = background(size)
    full.alpha_composite(foreground(size))
    master = rounded(full, 0.18)
    master.save(os.path.join(OUT, "icon_1024.png"))
    master.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon_512.png"))

    background(size).save(os.path.join(OUT, "icon_android_bg.png"))
    # Adaptive icons crop to the middle 66%; keep the art inside it.
    foreground(size, scale=0.62).save(os.path.join(OUT, "icon_android_fg.png"))

    inner = 824
    tile = background(inner)
    tile.alpha_composite(foreground(inner))
    tile = rounded(tile, 0.225)
    mac = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - inner) // 2
    mac.paste(tile, (offset, offset), tile)
    mac.save(os.path.join(OUT, "icon_macos.png"))


if __name__ == "__main__":
    main()
