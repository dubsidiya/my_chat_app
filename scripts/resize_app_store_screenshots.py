#!/usr/bin/env python3
"""
Resize App Store screenshots to 1242×2688 px (portrait).
Scale to fit, then pad with dark background to exact size (no stretching).
Requires: pip install Pillow
"""
import os
import sys

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip install Pillow")
    sys.exit(1)

W, H = 1242, 2688
# Dark purple (#1a0e24) for padding to match app theme
BG_RGB = (0x1a, 0x0e, 0x24)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_ROOT, "app_store_screenshots")
SRC_DIR = os.environ.get("SRC_DIR") or os.path.join(PROJECT_ROOT, "app_store_screenshots_src")
# Optional: explicit file list (if SRC_DIR has other PNGs, we use first 4 in order)
NAMES = ["1_login", "2_profile", "3_chats_empty", "4_create_chat"]

os.makedirs(OUT_DIR, exist_ok=True)
if not os.path.isdir(SRC_DIR):
    print(f"Create folder and put 4 PNG screenshots: {SRC_DIR}")
    sys.exit(1)
files = sorted([f for f in os.listdir(SRC_DIR) if f.lower().endswith(".png")])
if not files:
    print(f"No PNG in {SRC_DIR}")
    sys.exit(1)
# Use first 4 PNGs in alphabetical order
for i, filename in enumerate(files[:4]):
    name = NAMES[i] if i < len(NAMES) else str(i)
    src = os.path.join(SRC_DIR, filename)
    out = os.path.join(OUT_DIR, f"{name}_1242x2688.png")
    img = Image.open(src).convert("RGB")
    iw, ih = img.size
    scale = min(W / iw, H / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    img = img.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (W, H), BG_RGB)
    x = (W - nw) // 2
    y = (H - nh) // 2
    canvas.paste(img, (x, y))
    canvas.save(out, "PNG", optimize=True)
    print(f"OK: {out}")

print(f"Done. Screenshots in {OUT_DIR}/ ({W}×{H} px).")
