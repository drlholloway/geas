#!/usr/bin/env python3
"""Draw the Geas icon and write the platform masters.

The picture: an amber wax seal pressed with a cream check, for a geas, an
obligation sealed and bound to be kept. On the app's deep teal.

Outputs (in apps/geas/assets/icon/):
  icon_1024.png        full-bleed square, rounded corners baked in
  icon_android_bg.png  adaptive-icon background layer: the teal
  icon_android_fg.png  adaptive-icon foreground layer: seal and check, in
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
INK = (242, 232, 213, 255)      # cream
WAX = (224, 160, 48, 255)       # amber, the medium-priority color
PRESSED = (170, 112, 24, 255)   # the wax where the stamp pressed it


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
    """The seal and its check, centered, on transparency.

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

    # The wax, with a rippled edge where it spread under the stamp.
    edge = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        r = 340 + 16 * math.sin(14 * t) + 6 * math.sin(5 * t + 1)
        edge.append(p(500 + r * math.cos(t), 500 + r * math.sin(t)))
    draw.polygon(edge, fill=WAX)

    # The stamp's rim, pressed in.
    draw.ellipse([p(225, 225), p(775, 775)], outline=PRESSED, width=w(18))

    # The check, raised from the wax: a shadow below and to the right.
    def check(pts, fill):
        draw.line(pts, fill=fill, width=w(74), joint="curve")
        for x, y in (pts[0], pts[-1]):
            rr = w(74) / 2
            draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=fill)

    check([p(351, 518), p(466, 633), p(671, 383)], PRESSED)
    check([p(345, 510), p(460, 625), p(665, 375)], INK)

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
