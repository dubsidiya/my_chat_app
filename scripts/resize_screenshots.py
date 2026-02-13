#!/usr/bin/env python3
"""Resize screenshots to App Store required dimensions (cover + center crop)."""
import os
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Установите Pillow: pip install Pillow")
    raise

# App Store screenshot sizes: (width, height)
SIZES = [
    (1242, 2688),   # iPhone 6.5" portrait
    (2688, 1242),   # iPhone 6.5" landscape
    (1284, 2778),   # iPhone 6.7" portrait
    (2778, 1284),   # iPhone 6.7" landscape
    (2064, 2752),   # iPad Pro 13" portrait
    (2752, 2064),   # iPad Pro 13" landscape
]

# Исходные фото (Cursor assets)
ASSETS = Path("/Users/vladkharin/.cursor/projects/Users-vladkharin-my-chat-app/assets")
# Результат в папке проекта
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "app_store_screenshots"
SOURCES = [
    "photo_2026-02-12_21.18.25-db656ac4-1521-4940-90cc-59a7f2d90368.png",
    "photo_2026-02-12_21.18.28-d06dd70f-99fa-484b-b12f-8b45dbdbfbab.png",
    "photo_2026-02-12_21.18.30-9eb4e9eb-1d0a-40d9-ad07-b668adee56a5.png",
]


def resize_cover(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    """Scale image to cover target size, then center crop."""
    tw, th = target_w, target_h
    iw, ih = img.size
    scale = max(tw / iw, th / ih)
    new_w = round(iw * scale)
    new_h = round(ih * scale)
    img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    left = (new_w - tw) // 2
    top = (new_h - th) // 2
    return img.crop((left, top, left + tw, top + th))


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for name in SOURCES:
        path = ASSETS / name
        if not path.exists():
            print(f"Пропуск (не найден): {path}")
            continue
        img = Image.open(path).convert("RGB")
        base = Path(name).stem
        for w, h in SIZES:
            out = resize_cover(img, w, h)
            out_name = f"{base}_{w}x{h}.png"
            out_path = OUTPUT_DIR / out_name
            out.save(out_path, "PNG", optimize=True)
            print(f"Сохранено: {out_path}")


if __name__ == "__main__":
    main()
