# Patches

After `flutter pub get`, apply the WebRTC Android fix:

```bash
bash tool/apply_webrtc_patch.sh
```

Fixes a crash when `createPeerConnection` fails and `getUserMedia` runs afterward (null native `PeerConnection` zombie observer).
