"""Draws the Dacx launcher icon: a tiny 2 x 2 deck with two lit keys.
Run from mobile/: python assets/icon/make_icon.py, then dart run flutter_launcher_icons."""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
BG = (6, 6, 8)
VIOLET, VIOLET_DEEP, GREEN = (139, 92, 246), (76, 29, 149), (30, 215, 96)


def keys(size, area):
    """Four keys inside a square area (x0, y0, side), transparent background."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x0, y0, side = area
    gap = side * 0.08
    k = (side - gap) / 2
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    d = ImageDraw.Draw(img)
    for i, (cx, cy) in enumerate([(0, 0), (1, 0), (0, 1), (1, 1)]):
        x, y = x0 + cx * (k + gap), y0 + cy * (k + gap)
        box = [x, y, x + k, y + k]
        r = k * 0.2
        if i == 0:
            gd.rounded_rectangle(box, r, fill=VIOLET + (150,))
        if i == 3:
            gd.rounded_rectangle(box, r, fill=GREEN + (110,))
        d.rounded_rectangle(box, r, fill=(28, 28, 35, 255), outline=(52, 52, 62, 255), width=max(2, int(k * 0.02)))
        inset = k * 0.08
        lcd = [x + inset, y + inset, x + k - inset, y + k - inset]
        if i == 0:
            # violet LCD with a play triangle
            d.rounded_rectangle(lcd, r * 0.7, fill=VIOLET_DEEP + (255,))
            cx_, cy_, t = x + k / 2, y + k / 2, k * 0.2
            d.polygon([(cx_ - t * 0.7, cy_ - t), (cx_ - t * 0.7, cy_ + t), (cx_ + t, cy_)], fill=(245, 245, 250, 255))
        elif i == 3:
            d.rounded_rectangle(lcd, r * 0.7, fill=(10, 60, 30, 255))
            c = k * 0.2
            d.ellipse([x + k / 2 - c, y + k / 2 - c, x + k / 2 + c, y + k / 2 + c], fill=GREEN + (255,))
        else:
            d.rounded_rectangle(lcd, r * 0.7, fill=(8, 8, 10, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.03))
    return Image.alpha_composite(glow, img)


# Full icon (legacy launchers): rounded dark tile with the deck.
full = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(full).rounded_rectangle([0, 0, S - 1, S - 1], S * 0.22, fill=BG + (255,))
full = Image.alpha_composite(full, keys(S, (S * 0.2, S * 0.2, S * 0.6)))
full.save("assets/icon/icon.png")

# Adaptive icon: the launcher masks to ~66% of the canvas, so keep the deck small.
keys(S, (S * 0.25, S * 0.25, S * 0.5)).save("assets/icon/icon_foreground.png")
Image.new("RGBA", (S, S), BG + (255,)).save("assets/icon/icon_background.png")
print("icons written")
