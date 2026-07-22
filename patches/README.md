# Patches

The project does not patch packages in the pub cache.

`livekit_client` and the direct `flutter_webrtc` dependency are pinned to one
compatible pair in `pubspec.yaml`. Their package metadata selects the native
WebRTC SDK on Android and iOS, and CocoaPods records that selection in
`ios/Podfile.lock`.

If an upstream plugin fix is needed, consume a published compatible release
instead of modifying `$PUB_CACHE`. See `docs/IOS_APP_STORE_WEBRTC.md` for the
release workflow.
