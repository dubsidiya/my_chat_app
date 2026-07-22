#!/usr/bin/env bash
# Resolve package-owned iOS dependencies and build a release IPA for App Store.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== flutter pub get =="
flutter pub get

echo "== CocoaPods (WebRTC-SDK selected by LiveKit/flutter_webrtc) =="
cd ios
pod install --repo-update
cd "$ROOT"

echo "== scan WebRTC symbols (informational) =="
flutter build ios --release --no-codesign
APP="$ROOT/build/ios/iphoneos/Runner.app"
WR="$APP/Frameworks/WebRTC.framework/WebRTC"
if [[ -f "$WR" ]]; then
  echo "WebRTC.framework present. UIKit-related strings:"
  strings "$WR" | grep -E 'mainScreen|sharedApplication|initWithURLStrings' | sort -u || true
  echo ""
  echo "If App Store still rejects: see docs/IOS_APP_STORE_WEBRTC.md (appeal template)."
else
  echo "No WebRTC.framework in build (voice calls not linked)."
fi

echo ""
echo "Next: archive for App Store (codesign required):"
echo "  flutter build ipa"
echo "  or open ios/Runner.xcworkspace -> Product -> Archive"
