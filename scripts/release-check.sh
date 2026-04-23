#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/my_serve_chat_test"

FAST_MODE="${1:-}"

echo "==> Flutter: pub get"
cd "$ROOT_DIR"
flutter pub get

echo "==> Flutter: analyze"
flutter analyze

echo "==> Flutter: tests"
flutter test

echo "==> Backend smoke checks"
cd "$SERVER_DIR"
npm run smoke:reports:permissions
npm run smoke:all

if [[ "$FAST_MODE" == "--fast" ]]; then
  echo "==> FAST mode enabled, skipping release builds"
  exit 0
fi

echo "==> Flutter: iOS release build (no codesign)"
cd "$ROOT_DIR"
flutter build ios --release --no-codesign

echo "==> Flutter: Android release build"
flutter build apk --release

echo "==> Release check completed"
