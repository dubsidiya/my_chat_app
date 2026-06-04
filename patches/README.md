# Patches

After `flutter pub get`:

```bash
bash tool/patch_ios_webrtc_sdk.sh   # iOS: WebRTC-SDK 144.7559.04 + Android/iOS crash fixes
# or only Android/iOS plugin fixes:
bash tool/apply_webrtc_patch.sh
```

- **iOS App Store:** см. `docs/IOS_APP_STORE_WEBRTC.md` и `tool/ios_app_store_release.sh`.
- **Android:** crash when `createPeerConnection` fails and `getUserMedia` runs afterward (zombie observer).
- **iOS plugin:** на flutter_webrtc 1.4.x в upstream уже есть guard в `postEvent`; старый iOS-патч нужен только для 0.12.x.
