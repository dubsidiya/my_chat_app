#!/usr/bin/env bash
# Fail if StablePluginRegistrant is missing plugins listed in GeneratedPluginRegistrant.m
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$ROOT/ios/Runner/GeneratedPluginRegistrant.m"
STABLE="$ROOT/ios/Runner/StablePluginRegistrant.swift"

if [[ ! -f "$GEN" || ! -f "$STABLE" ]]; then
  echo "check_ios_plugin_registrant: run flutter pub get first" >&2
  exit 1
fi

missing=0
while read -r key; do
  if ! grep -q "pluginKey: \"$key\"" "$STABLE"; then
    echo "Missing in StablePluginRegistrant: $key (see GeneratedPluginRegistrant.m)" >&2
    missing=1
  fi
done < <(grep 'registrarForPlugin:@"' "$GEN" | sed -E 's/.*registrarForPlugin:@"([^"]+)".*/\1/')

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
echo "StablePluginRegistrant covers all GeneratedPluginRegistrant plugins"
