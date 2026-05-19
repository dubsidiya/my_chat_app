#!/bin/sh
# WebRTC.framework (flutter_webrtc) ships without dSYM; Xcode 16+ / App Store Connect
# require a matching dSYM in the archive. dsymutil creates one (UUID matches even if
# there are no debug symbols — warning "no debug symbols" is OK).
set -e

WEBRTC_BIN="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/WebRTC.framework/WebRTC"
if [ ! -f "${WEBRTC_BIN}" ]; then
  exit 0
fi

if [ -z "${DWARF_DSYM_FOLDER_PATH}" ]; then
  echo "warning: DWARF_DSYM_FOLDER_PATH is not set, skipping WebRTC dSYM"
  exit 0
fi

DSYM_OUT="${DWARF_DSYM_FOLDER_PATH}/WebRTC.framework.dSYM"
echo "note: Generating WebRTC.framework.dSYM for App Store Connect"
mkdir -p "${DWARF_DSYM_FOLDER_PATH}"
dsymutil "${WEBRTC_BIN}" -o "${DSYM_OUT}" || true
