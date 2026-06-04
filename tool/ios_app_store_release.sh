#!/usr/bin/env bash
# Prepare iOS deps (WebRTC-SDK pin) and build release IPA for App Store.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== flutter pub get =="
flutter pub get

echo "== patch WebRTC (SDK version + Android/iOS crash fixes) =="
bash "$ROOT/tool/patch_ios_webrtc_sdk.sh"

echo "== CocoaPods (WebRTC-SDK from webrtc-sdk/Specs) =="
cd ios
pod install --repo-update
pod update WebRTC-SDK
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
