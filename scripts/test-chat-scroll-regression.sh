#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Chat scroll regression: analyze changed chat files"
flutter analyze \
  lib/features/chat/chat_scroll_policy.dart \
  lib/screens/chat_screen_scroll.dart \
  lib/screens/chat_screen_messages_sync.dart \
  lib/widgets/chat_message_tile.dart

echo "==> Chat scroll regression: unit + widget tests"
flutter test \
  test/chat/chat_scroll_policy_test.dart \
  test/chat/chat_scroll_regression_matrix_test.dart \
  test/chat/chat_open_scroll_widget_test.dart \
  test/chat/chat_message_tile_media_layout_test.dart

echo "==> Chat scroll regression: ALL PASSED"
