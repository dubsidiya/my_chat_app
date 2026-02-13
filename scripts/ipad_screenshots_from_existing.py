#!/usr/bin/env python3
"""Создать скриншоты для iPad Pro 13" из уже имеющихся в app_store_screenshots."""
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Установите Pillow: pip install Pillow")
    raise

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "app_store_screenshots"
IPAD_SIZES = [(2064, 2752), (2752, 2064)]  # portrait, landscape


def resize_cover(img, target_w, target_h):
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
    if not OUTPUT_DIR.exists():
        print(f"Папка не найдена: {OUTPUT_DIR}")
        return
    # Берём первый попавшийся скриншот (например 1242x2688) как источник
    sources = list(OUTPUT_DIR.glob("*_1242x2688.png")) or list(OUTPUT_DIR.glob("*.png"))
    if not sources:
        print("В app_store_screenshots нет PNG. Сначала запустите scripts/resize_screenshots.py")
        return
    for path in sources[:3]:  # максимум 3 разных источника
        img = Image.open(path).convert("RGB")
        base = path.stem.replace("_1242x2688", "").replace("_1284x2778", "")
        for w, h in IPAD_SIZES:
            out = resize_cover(img, w, h)
            out_name = f"{base}_iPad13_{w}x{h}.png"
            out_path = OUTPUT_DIR / out_name
            out.save(out_path, "PNG", optimize=True)
            print(f"Сохранено: {out_path}")
    print("Готово. Загрузи файлы *_iPad13_2064x2752.png в App Store Connect для iPad Pro 13\".")


if __name__ == "__main__":
    main()
