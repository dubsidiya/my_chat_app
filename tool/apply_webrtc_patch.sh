#!/usr/bin/env bash
# Apply flutter_webrtc Android + iOS fixes after `flutter pub get`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PATCH="$ROOT/patches/flutter_webrtc.patch"
if [[ ! -f "$PATCH" ]]; then
  echo "Missing $PATCH" >&2
  exit 1
fi
LOCK_VER="$(grep -A8 '  flutter_webrtc:$' "$ROOT/pubspec.lock" | grep 'version:' | head -1 | sed 's/.*version: "\(.*\)".*/\1/' || true)"
if [[ -z "$LOCK_VER" ]]; then
  echo "flutter_webrtc not in pubspec.lock; run flutter pub get first" >&2
  exit 1
fi
PKG_DIR="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/flutter_webrtc-${LOCK_VER}"
if [[ ! -d "$PKG_DIR" ]]; then
  echo "Missing $PKG_DIR; run flutter pub get first" >&2
  exit 1
fi
PCO="$PKG_DIR/android/src/main/java/com/cloudwebrtc/webrtc/PeerConnectionObserver.java"
MCH="$PKG_DIR/android/src/main/java/com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java"

android_patched() {
  grep -q 'if (peerConnection == null)' "$PCO" 2>/dev/null || return 1
  awk '/public boolean peerConnectionDispose\(final PeerConnectionObserver/,/^  \}/' "$MCH" 2>/dev/null \
    | grep -q 'peerConnection is null' || return 1
  awk '/public boolean peerConnectionDispose\(final PeerConnectionObserver/,/^  \}/' "$MCH" 2>/dev/null \
    | grep -q 'return false' && return 1
  return 0
}

ios_patched() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  # Upstream 1.4.x: nil sink guard in postEvent; optional eventChannel teardown patch.
  if grep -q 'postEvent: sink is nil' "$f" 2>/dev/null; then
    return 0
  fi
  grep -q 'FlutterEventSink copiedSink' "$f" && grep -q 'setStreamHandler:nil' "$f"
}

apply_ios_fix() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if ios_patched "$f"; then
    return 0
  fi
  python3 - "$f" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old_post = """void postEvent(FlutterEventSink _Nonnull sink, id _Nullable event) {
    dispatch_async(dispatch_get_main_queue(), ^{
      sink(event);
    });
}"""
new_post = """void postEvent(FlutterEventSink _Nonnull sink, id _Nullable event) {
  if (sink == nil) {
    return;
  }
  FlutterEventSink copiedSink = [sink copy];
  dispatch_async(dispatch_get_main_queue(), ^{
    if (copiedSink) {
      copiedSink(event);
    }
  });
}"""
old_close = """    if (peerConnection) {
      [peerConnection close];
      [self.peerConnections removeObjectForKey:peerConnectionId];"""
new_close = """    if (peerConnection) {
      peerConnection.eventSink = nil;
      if (peerConnection.eventChannel != nil) {
        [peerConnection.eventChannel setStreamHandler:nil];
      }
      [peerConnection close];
      [self.peerConnections removeObjectForKey:peerConnectionId];"""
if old_post not in text or old_close not in text:
    sys.stderr.write(f"iOS patch: unexpected content in {path}\n")
    sys.exit(1)
text = text.replace(old_post, new_post, 1).replace(old_close, new_close, 1)
open(path, "w", encoding="utf-8").write(text)
print(f"iOS patch applied: {path}")
PY
}

if ! android_patched; then
  patch -d "$PKG_DIR" -p1 --forward -r - < "$PATCH" 2>/dev/null || true
fi

for ios_file in \
  "$PKG_DIR/ios/Classes/FlutterWebRTCPlugin.m" \
  "$PKG_DIR/common/darwin/Classes/FlutterWebRTCPlugin.m" \
  "$PKG_DIR/macos/Classes/FlutterWebRTCPlugin.m"; do
  apply_ios_fix "$ios_file"
done

if android_patched && ios_patched "$PKG_DIR/ios/Classes/FlutterWebRTCPlugin.m"; then
  echo "Patch OK at $PKG_DIR"
elif android_patched; then
  echo "Android patch OK at $PKG_DIR (iOS uses upstream guards or manual patch)"
else
  echo "Patch incomplete; check $PKG_DIR" >&2
  exit 1
fi
