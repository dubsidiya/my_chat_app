#!/usr/bin/env bash
# Resolve iOS dependencies and build a signed App Store IPA.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/ios/Runner/GoogleService-Info.plist" ]]; then
  echo "error: ios/Runner/GoogleService-Info.plist is missing (gitignored, required for the App Store IPA)."
  echo "Download it from Firebase for bundle com.estellia.reol and place it at that path."
  exit 1
fi

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
echo "== App Store IPA (codesign required) =="
mkdir -p "$ROOT/build/debug-info/ios"
flutter build ipa --release \
  --obfuscate \
  --split-debug-info="$ROOT/build/debug-info/ios" \
  --export-options-plist="$ROOT/ios/ExportOptions.plist"

echo ""
echo "IPA: $ROOT/build/ios/ipa/"
echo "Keep build/debug-info/ios to deobfuscate crash logs."
echo "Upload via Transporter or Xcode Organizer. Checklist: docs/APP_STORE_RELEASE.md"
