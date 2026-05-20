# Patches

After `flutter pub get`, apply the WebRTC Android fix:

```bash
bash tool/apply_webrtc_patch.sh
```

- **Android:** crash when `createPeerConnection` fails and `getUserMedia` runs afterward (zombie observer).
- **iOS:** `EXC_BAD_ACCESS` in `postEvent` when PeerConnection events arrive after the Dart event channel was cancelled (voice calls freeze/crash).
