#!/usr/bin/env python3
"""Generate the Velvet 3 logo assets.

The mark is a notification stack: a front banner card carrying Velvet's signature
accent line, with a second card peeking out behind it, on a velvet-purple squircle.
Everything is drawn from these numbers, so the branding is reproducible — re-run this
script rather than hand-editing a PNG.

    python3 tools/make-logo.py

Writes assets/ (master + README banner) and preferences/Resources/ (the sizes the
preference bundle and Sileo actually load).
"""

import os
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
RESOURCES = os.path.join(ROOT, "preferences", "Resources")

# Supersample factor: shapes are drawn hard-edged at S and downsampled to the target,
# which is where the antialiasing comes from.
S = 3072

VIOLET_LIGHT = (139, 92, 246)     # #8B5CF6 — top of the squircle gradient
VIOLET_DEEP = (59, 7, 100)        # #3B0764 — bottom
MAGENTA_GLOW = (232, 121, 249)    # #E879F9 — bottom-right velvet sheen
ACCENT_WARM = (251, 113, 133)     # #FB7185 — accent line, top
ACCENT_COOL = (249, 115, 22)      # #F97316 — accent line, bottom
ICON_TOP = (192, 132, 252)        # the little app-icon tile inside the card
ICON_BOTTOM = (147, 51, 234)
TEXT_STRONG = (91, 33, 182)       # title line on the card
TEXT_SOFT = (167, 139, 250)       # message line
WORDMARK = (139, 92, 246)

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/urw-base35/NimbusSans-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise SystemExit("no usable bold sans font found")


def linear_gradient(size, top, bottom):
    """Vertical ramp as a float HxWx3 array in 0..255."""
    t = np.linspace(0.0, 1.0, size, dtype=np.float32)[:, None, None]
    c0 = np.array(top, dtype=np.float32)
    c1 = np.array(bottom, dtype=np.float32)
    return (c0 + (c1 - c0) * t) * np.ones((1, size, 1), dtype=np.float32)


def radial_falloff(size, cx, cy, radius):
    """Smooth 1→0 falloff from (cx, cy), both given as fractions of `size`."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.hypot(xs / size - cx, ys / size - cy) / radius
    return np.clip(1.0 - d, 0.0, 1.0) ** 2


def superellipse_mask(size, n=4.4):
    """Apple-style squircle — rounder shoulders than a plain rounded rectangle."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    u = np.abs((xs + 0.5) / size * 2.0 - 1.0)
    v = np.abs((ys + 0.5) / size * 2.0 - 1.0)
    return (u ** n + v ** n) <= 1.0


def rounded_mask(size, box, radius):
    """Antialiasing comes from the later downsample, so a hard mask is fine here."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(
        [box[0] * size, box[1] * size, box[2] * size, box[3] * size],
        radius=radius * size,
        fill=255,
    )
    return np.asarray(m, dtype=np.float32) / 255.0


def over(base, color, alpha):
    """Composite a colour (constant or HxWx3) onto base with an HxW alpha."""
    a = alpha[:, :, None]
    return base * (1.0 - a) + np.asarray(color, dtype=np.float32) * a


def build_mark(size=S):
    rgb = linear_gradient(size, VIOLET_LIGHT, VIOLET_DEEP)

    # Velvet has a sheen: a warm bloom low-right, a cool highlight up-left.
    rgb = over(rgb, MAGENTA_GLOW, radial_falloff(size, 0.86, 0.94, 0.72) * 0.34)
    rgb = over(rgb, (255, 255, 255), radial_falloff(size, 0.26, 0.10, 0.70) * 0.13)

    # The notification behind the notification — the reason this is a *stack*.
    rgb = over(rgb, (255, 255, 255),
               rounded_mask(size, (0.268, 0.262, 0.732, 0.460), 0.052) * 0.32)

    # Front banner card.
    card = rounded_mask(size, (0.150, 0.408, 0.850, 0.763), 0.080)
    rgb = over(rgb, (255, 255, 255), card * 0.97)

    # Velvet's signature: the coloured accent line down the leading edge.
    accent = rounded_mask(size, (0.196, 0.480, 0.238, 0.691), 0.021)
    rgb = over(rgb, linear_gradient(size, ACCENT_WARM, ACCENT_COOL), accent)

    # App icon tile.
    icon = rounded_mask(size, (0.283, 0.5155, 0.423, 0.6555), 0.038)
    rgb = over(rgb, linear_gradient(size, ICON_TOP, ICON_BOTTOM), icon)

    # Title and message lines.
    rgb = over(rgb, TEXT_STRONG,
               rounded_mask(size, (0.462, 0.5275, 0.790, 0.5735), 0.023) * 0.90)
    rgb = over(rgb, TEXT_SOFT,
               rounded_mask(size, (0.462, 0.6015, 0.700, 0.6435), 0.021) * 0.85)

    alpha = superellipse_mask(size).astype(np.float32) * 255.0
    out = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def tracked_text(draw, xy, text, fnt, fill, tracking):
    """PIL has no letter-spacing; a logo wordmark needs one."""
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking
    return x - tracking


def text_width(draw, text, fnt, tracking):
    return sum(draw.textlength(c, font=fnt) for c in text) + tracking * (len(text) - 1)


def build_header(height=420):
    """Settings-pane header: mark + wordmark, transparent so it reads on both themes.

    The pane scales this to 80pt tall by aspect fit, so the canvas is sized to its own
    contents — any slack would just shrink the logo.
    """
    mark_size = int(height * 0.84)
    gap = height * 0.16
    label = "VELVET 3"
    fnt = font(int(height * 0.36))
    tracking = height * 0.030

    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    label_w = text_width(probe, label, fnt, tracking)
    img = Image.new("RGBA", (int(mark_size + gap + label_w), height), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    img.alpha_composite(build_mark().resize((mark_size, mark_size), Image.LANCZOS),
                        (0, (height - mark_size) // 2))
    bbox = fnt.getbbox(label)
    tracked_text(d, (mark_size + gap, (height - (bbox[3] + bbox[1])) / 2),
                 label, fnt, WORDMARK, tracking)
    return img


def build_banner(mark, width=1280, height=440):
    """README hero."""
    rgb = linear_gradient(height, (26, 12, 41), (12, 6, 20))[:, :1, :]
    rgb = np.repeat(rgb, width, axis=1)
    glow = radial_falloff(max(width, height), 0.20, 0.55, 0.55)[:height, :width]
    rgb = over(rgb, (124, 58, 237), glow * 0.30)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    d = ImageDraw.Draw(img)

    m = mark.resize((236, 236), Image.LANCZOS)
    img.alpha_composite(m, (96, 102))

    title = font(112)
    sub = font(38)
    tracked_text(d, (388, 128), "VELVET 3", title, (237, 233, 254), 6)
    d.text((392, 262), "Notification banners, your way.", font=sub, fill=(167, 139, 250))
    d.text((392, 316), "iOS 15 – 18  ·  rootless  ·  arm64e",
           font=font(30), fill=(124, 106, 158))
    return img


def save(img, path, size=None):
    out = img.resize((size, size), Image.LANCZOS) if size else img
    out.save(path, "PNG", optimize=True)
    print("wrote", os.path.relpath(path, ROOT), out.size)


def main():
    os.makedirs(ASSETS, exist_ok=True)
    mark = build_mark()

    save(mark, os.path.join(ASSETS, "velvet3-icon.png"), 1024)
    save(build_banner(mark), os.path.join(ASSETS, "velvet3-banner.png"))

    # Settings row icon (@1x/@2x/@3x) — PreferenceLoader picks the right one.
    save(mark, os.path.join(RESOURCES, "icon.png"), 30)
    save(mark, os.path.join(RESOURCES, "icon@2x.png"), 60)
    save(mark, os.path.join(RESOURCES, "icon@3x.png"), 90)

    # Sileo / Zebra package listing.
    save(mark, os.path.join(RESOURCES, "PackageIcon.png"), 256)

    save(build_header(), os.path.join(RESOURCES, "velvet-header-icon.png"))


if __name__ == "__main__":
    main()
