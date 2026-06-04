#!/usr/bin/env bash
# Pin flutter_webrtc iOS pod to latest WebRTC-SDK (App Store / iOS 26 scanner).
# Run after: flutter pub get
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCK_VER="$(grep -A8 '  flutter_webrtc:$' pubspec.lock | grep 'version:' | head -1 | sed 's/.*version: "\(.*\)".*/\1/' || true)"
if [[ -z "$LOCK_VER" ]]; then
  echo "flutter_webrtc not in pubspec.lock; run flutter pub get" >&2
  exit 1
fi

PKG_DIR="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/flutter_webrtc-${LOCK_VER}"
PODSPEC="$PKG_DIR/ios/flutter_webrtc.podspec"
if [[ ! -f "$PODSPEC" ]]; then
  echo "Missing $PODSPEC" >&2
  exit 1
fi

# Latest from https://github.com/webrtc-sdk/Specs/releases (override via WEBRTC_SDK_VERSION).
TARGET_VER="${WEBRTC_SDK_VERSION:-144.7559.04}"

python3 - "$PODSPEC" "$TARGET_VER" <<'PY'
import re, sys
path, ver = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
m = re.search(r"s\.dependency 'WebRTC-SDK', '([^']+)'", text)
if not m:
    sys.stderr.write(f"WebRTC-SDK dependency not found in {path}\n")
    sys.exit(1)
if m.group(1) == ver:
    print(f"iOS WebRTC-SDK already {ver} in {path}")
else:
    new = re.sub(
        r"s\.dependency 'WebRTC-SDK', '[^']+'",
        f"s.dependency 'WebRTC-SDK', '{ver}'",
        text,
        count=1,
    )
    open(path, "w", encoding="utf-8").write(new)
    print(f"iOS WebRTC-SDK {m.group(1)} -> {ver} in {path}")
PY

bash "$ROOT/tool/apply_webrtc_patch.sh"
