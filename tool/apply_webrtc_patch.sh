#!/usr/bin/env bash
# Apply flutter_webrtc Android fixes after `flutter pub get`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PATCH="$ROOT/patches/flutter_webrtc.patch"
if [[ ! -f "$PATCH" ]]; then
  echo "Missing $PATCH" >&2
  exit 1
fi
PKG_DIR="$(find "${PUB_CACHE:-$HOME/.pub-cache}/hosted" -maxdepth 2 -type d -name 'flutter_webrtc-*' 2>/dev/null | head -1)"
if [[ -z "$PKG_DIR" ]]; then
  echo "flutter_webrtc not in pub-cache; run flutter pub get first" >&2
  exit 1
fi
PCO="$PKG_DIR/android/src/main/java/com/cloudwebrtc/webrtc/PeerConnectionObserver.java"
MCH="$PKG_DIR/android/src/main/java/com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java"
is_patched() {
  grep -q 'if (peerConnection == null)' "$PCO" 2>/dev/null \
    && awk '/public boolean peerConnectionDispose\(final PeerConnectionObserver/,/^  \}/' "$MCH" 2>/dev/null \
      | grep -q 'peerConnection is null' \
    && ! awk '/public boolean peerConnectionDispose\(final PeerConnectionObserver/,/^  \}/' "$MCH" 2>/dev/null \
      | grep -q 'return false'
}
if is_patched; then
  echo "Patch already applied at $PKG_DIR"
  exit 0
fi
if patch -d "$PKG_DIR" -p1 --forward -r - < "$PATCH"; then
  echo "Patched flutter_webrtc at $PKG_DIR"
elif is_patched; then
  echo "Patch already applied at $PKG_DIR"
else
  echo "Patch failed; check $PKG_DIR" >&2
  exit 1
fi
