#!/usr/bin/env python3
"""Prepare source image as 1024x1024 app icon with solid background (iOS requirement)."""
from pathlib import Path

from PIL import Image

SRC = Path("/Users/vladkharin/.cursor/projects/Users-vladkharin-my-chat-app/assets/_____________________-b22acada-0936-4293-a2c2-d3c14e00423a.png")
OUT = Path(__file__).resolve().parent.parent / "assets" / "app_icon.png"
SIZE = 1024
# Сплошной фон для иконки (светло-серый, без прозрачности для iOS)
BG_RGB = (0xE8, 0xE8, 0xE8)


def main():
    img = Image.open(SRC)
    if img.mode in ("RGBA", "P"):
        img = img.convert("RGBA")
    else:
        img = img.convert("RGB")

    iw, ih = img.size
    scale = min(SIZE / iw, SIZE / ih)
    new_w = round(iw * scale)
    new_h = round(ih * scale)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

    out_img = Image.new("RGB", (SIZE, SIZE), BG_RGB)
    paste_x = (SIZE - new_w) // 2
    paste_y = (SIZE - new_h) // 2

    if img.mode == "RGBA":
        out_img.paste(img, (paste_x, paste_y), img)
    else:
        out_img.paste(img, (paste_x, paste_y))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    out_img.save(OUT, "PNG", optimize=True)
    print(f"Сохранено: {OUT}")


if __name__ == "__main__":
    main()
