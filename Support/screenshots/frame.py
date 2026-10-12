"""Frame raw simulator screenshots into App Store marketing images.

Usage: python frame.py RAW_DIR OUT_DIR
RAW_DIR holds <device>-<screen>-<theme>.png, e.g. iphone-home-day.png, ipad-details-night.png.
Writes OUT_DIR/<slot>/NN-<screen>-<theme>.png at the exact pixel size each App Store slot wants.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Every App Store Connect slot (portrait), folder named after the slot as ASC labels it.
SLOTS = {
    "iPhone 6.9in - 1320x2868": ("iphone", (1320, 2868)),
    "iPhone 6.5in - 1284x2778": ("iphone", (1284, 2778)),
    "iPhone 6.3in - 1206x2622": ("iphone", (1206, 2622)),
    "iPhone 6.1in - 1179x2556": ("iphone", (1179, 2556)),
    "iPad 13in - 2064x2752": ("ipad", (2064, 2752)),
}

# Upload order + captions.
SHOTS = [
    ("home-day", "That plane above you —\nwhere's it going?"),
    ("details-day", "Route, altitude & speed\nat a glance"),
    ("home-night", "Live flights near you,\nday or night"),
    ("details-night", "Fun facts for\ncurious minds"),
    ("home-evening", "Sky alerts when a\nplane flies over"),
]

# SkyPalette gradients (SkyTheme.swift) + caption colour.
THEMES = {
    "day": ((0xA7, 0xD4, 0xFF), (0xEA, 0xF6, 0xFF), (0x13, 0x26, 0x4F)),
    "evening": ((0x2E, 0x3A, 0x8C), (0x10, 0x1E, 0x4E), (0xF7, 0xFA, 0xFF)),
    "night": ((0x07, 0x16, 0x38), (0x07, 0x0D, 0x26), (0xF7, 0xFA, 0xFF)),
}

# Per device, as fractions of screen width: screen corner radius, bezel thickness.
DEVICE = {"iphone": (0.14, 0.035), "ipad": (0.035, 0.04)}

FONTS = [
    "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "C:/Windows/Fonts/arialbd.ttf",
]


def font(size):
    for path in FONTS:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default(size)


def gradient(size, top, bottom):
    w, h = size
    column = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / (h - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return column.resize(size)


def rounded_mask(size, radius, scale=4):
    """Anti-aliased rounded-rect mask (drawn large, then downsampled)."""
    big = Image.new("L", (size[0] * scale, size[1] * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, big.width - 1, big.height - 1), radius * scale, fill=255)
    return big.resize(size, Image.LANCZOS)


def device_mock(shot, kind):
    corner, bezel = DEVICE[kind]
    sw, sh = shot.size
    r, b = int(sw * corner), int(sw * bezel)
    body = Image.new("RGBA", (sw + 2 * b, sh + 2 * b), (0, 0, 0, 0))
    body.paste((22, 24, 32, 255), mask=rounded_mask(body.size, r + b))
    body.paste(shot.convert("RGB"), (b, b), rounded_mask(shot.size, r))
    if kind == "iphone":  # Dynamic Island (simulator screenshots leave the space empty)
        iw, ih = int(sw * 0.28), int(sw * 0.085)
        x, y = b + (sw - iw) // 2, b + int(sw * 0.025)
        ImageDraw.Draw(body).rounded_rectangle((x, y, x + iw, y + ih), ih // 2, fill=(0, 0, 0, 255))
    return body


def compose(shot, kind, size, theme, caption):
    top, bottom, ink = THEMES[theme]
    w, h = size
    canvas = gradient(size, top, bottom)

    text_font = font(int(w * (0.068 if kind == "iphone" else 0.052)))
    ImageDraw.Draw(canvas).multiline_text((w / 2, h * 0.055), caption, font=text_font, fill=ink,
                                          anchor="ma", align="center", spacing=int(text_font.size * 0.25))

    device = device_mock(shot, kind)
    scale = min(h * 0.80 / device.height, w * 0.86 / device.width)
    device = device.resize((round(device.width * scale), round(device.height * scale)), Image.LANCZOS)
    x, y = (w - device.width) // 2, h - device.height - int(h * 0.035)

    shadow = Image.new("L", size, 0)
    shadow.paste(device.getchannel("A"), (x, y + int(h * 0.01)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(w * 0.025)).point(lambda v: v * 0.35)
    canvas.paste((0, 0, 0), mask=shadow)
    canvas.paste(device, (x, y), device)
    return canvas


def main(raw_dir, out_dir):
    written = []
    for slot, (kind, size) in SLOTS.items():
        for i, (name, caption) in enumerate(SHOTS, 1):
            src = raw_dir / f"{kind}-{name}.png"
            if not src.exists():
                print(f"skip {slot}: missing {src.name}")
                continue
            dest = out_dir / slot / f"{i:02d}-{name}.png"
            dest.parent.mkdir(parents=True, exist_ok=True)
            compose(Image.open(src), kind, size, name.rsplit("-", 1)[1], caption).save(dest, optimize=True)
            written.append((dest, size))
    # App Store Connect rejects wrong sizes and alpha channels.
    for dest, size in written:
        with Image.open(dest) as img:
            assert img.size == size and img.mode == "RGB", (dest, img.size, img.mode)
    print(f"wrote {len(written)} screenshots to {out_dir}")
    return written


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
