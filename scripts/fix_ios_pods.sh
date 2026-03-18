#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="/Users/vladkharin/my_chat_app"
IOS_DIR="$PROJECT_ROOT/ios"

echo "==> Flutter clean"
cd "$PROJECT_ROOT"
flutter clean

echo "==> Remove stale iOS pod artifacts"
rm -rf "$IOS_DIR/Pods" "$IOS_DIR/.symlinks"
rm -f "$IOS_DIR/Podfile.lock"

echo "==> Resolve Flutter packages"
flutter pub get

echo "==> Install CocoaPods"
cd "$IOS_DIR"
pod install

echo "==> Done"
echo "Open workspace: $IOS_DIR/Runner.xcworkspace"
