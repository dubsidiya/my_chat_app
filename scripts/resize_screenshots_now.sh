#!/bin/bash
# Один запуск: копирует 4 скриншота из Cursor assets и ресайзит в 1242×2688.
# Запусти в Терминале из корня проекта: bash scripts/resize_screenshots_now.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$HOME/.cursor/projects/Users-vladkharin-my-chat-app/assets"
OUT="$ROOT/app_store_screenshots"
TMP="$ROOT/app_store_screenshots_src"

FILES=(
  "06B1EA1C-587B-43A1-A599-9BEC582E6875-fadee9b8-42e3-44d5-add7-2ce43873e626.png"
  "292AD49F-72BF-45CF-87D6-40B99C5C83D6-a7dd904d-cbcd-4613-806c-997fd6d5a3a5.png"
  "EFA2CE78-557D-45C6-BC75-947957753C98-139862f7-46f5-46ce-8c56-bea7abee7a07.png"
  "3DB00DD9-D2DE-4EB6-9169-AFF9AA168DA0-94ec3c9a-14e6-4424-b3a2-6215d50f4d11.png"
)
NAMES=( "1_login" "2_profile" "3_chats_empty" "4_create_chat" )

mkdir -p "$TMP" "$OUT"

for i in "${!FILES[@]}"; do
  src="$SRC/${FILES[$i]}"
  if [[ ! -f "$src" ]]; then
    echo "Нет файла: $src"
    exit 1
  fi
  cp "$src" "$TMP/"
done

for i in "${!FILES[@]}"; do
  src="$TMP/${FILES[$i]}"
  out="$OUT/${NAMES[$i]}_1242x2688.png"
  sips -z 2688 1242 "$src" --out "$out"
  echo "OK: $out"
done

echo "Готово. Скриншоты 1242×2688 в: $OUT"
