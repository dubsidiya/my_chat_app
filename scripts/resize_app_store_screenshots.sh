#!/bin/bash
# Resize App Store screenshots to 1242×2688 px (portrait) for App Store Connect.
#
# Usage (from project root):
#   bash scripts/resize_app_store_screenshots.sh
#   bash scripts/resize_app_store_screenshots.sh [output_dir]
#   SRC_DIR=/path/to/screenshots bash scripts/resize_app_store_screenshots.sh
#
# Place your 4 PNG screenshots in one of:
#   - app_store_screenshots_src/  (in project)
#   - or set SRC_DIR to Cursor assets: SRC_DIR="$HOME/.cursor/projects/Users-vladkharin-my-chat-app/assets"
#
# Output: app_store_screenshots/ (or your dir) with 1242×2688 px images.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$PROJECT_ROOT/app_store_screenshots}"
SRC_DIR="${SRC_DIR:-$PROJECT_ROOT/app_store_screenshots_src}"
mkdir -p "$OUT_DIR"

W=1242
H=2688

# Order: 1=login, 2=profile, 3=chats empty, 4=create chat. Name sources 01.png, 02.png, ... for order.
NAMES=( "1_login" "2_profile" "3_chats_empty" "4_create_chat" )
shopt -s nullglob
FILES=("$SRC_DIR"/*.png)
FILES=($(printf '%s\n' "${FILES[@]}" | sort))
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No PNG files in $SRC_DIR"
  echo "Copy your 4 screenshots to $SRC_DIR/ or set SRC_DIR=..."
  exit 1
fi

# If exactly 4 files, use in order; else resize all found
for i in "${!FILES[@]}"; do
  src="${FILES[$i]}"
  name="${NAMES[$i]:-$i}"
  out="$OUT_DIR/${name}_1242x2688.png"
  sips -z $H $W "$src" --out "$out"
  echo "OK: $out"
done

echo "Done. Screenshots in $OUT_DIR/ (1242×2688 px)."
