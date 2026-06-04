# iOS App Store и WebRTC (отказ «non-public / deprecated APIs»)

## Суть

Сообщение App Store Connect означает: **автоматический сканер** нашёл в `.ipa` символы, похожие на приватные или устаревшие API Apple. В приложении с **голосовыми звонками** это почти всегда бинарник **`WebRTC.framework`** из `flutter_webrtc` / `WebRTC-SDK`.

Типичные селекторы (ложные «private» или deprecated на iOS 26):

- `initWithURLStrings:`, `addStream:`, `sendData:` — публичные методы **WebRTC**, не Apple.
- `mainScreen`, `sharedApplication` — из кода Google WebRTC (камера/аудио); `mainScreen` помечен deprecated в iOS 26.

Это **не баг вашего Dart-кода**.

## Что сделано в репозитории

1. **WebRTC-SDK** для iOS обновлён до **144.7559.04** (через `tool/patch_ios_webrtc_sdk.sh` + `pod update WebRTC-SDK`).
2. В `ios/Podfile` добавлен spec-репозиторий `webrtc-sdk/Specs` и `ONLY_ACTIVE_ARCH` для WebRTC.
3. Скрипт **`tool/ios_app_store_release.sh`** — подготовка Pods и сборка release.

Перед каждой **новой** отправкой в App Store на Mac:

```bash
flutter pub get
bash tool/patch_ios_webrtc_sdk.sh
cd ios && pod update WebRTC-SDK && cd ..
flutter build ipa   # или Archive в Xcode
```

## Если отказ повторится

### 1. Ответ в Resolution Center (шаблон)

> The flagged selectors are not Apple private APIs. They come from the open-source WebRTC.framework (WebRTC-SDK 144.7559.x) used for voice calls, bundled via the flutter_webrtc plugin. Names such as `addStream:`, `initWithURLStrings:`, and `sendData:` are documented WebRTC APIs. References to `UIScreen`/`UIApplication` originate from Google's libwebrtc iOS capture stack, not undocumented Apple SPI. We use the latest WebRTC-SDK from https://github.com/webrtc-sdk/Specs. Please allow the build or specify the exact symbol list so we can address a targeted upstream update.

(Можно перевести на русский для переписки с поддержкой.)

### 2. Проверить, что в Connect залит **новый** билд

- Увеличить `version` / build number в `pubspec.yaml`.
- После `flutter clean` пересобрать IPA.
- В Organizer убедиться, что в приложении есть `Frameworks/WebRTC.framework` с актуальной датой сборки.

### 3. Локальная диагностика (на Mac)

```bash
APP=build/ios/iphoneos/Runner.app
strings "$APP/Frameworks/WebRTC.framework/WebRTC" | grep -E 'mainScreen|initWithURLStrings|addStream:'
```

### 4. Крайний вариант — сборка без звонков на iOS

Если Apple не пропускает даже с апелляцией, временно убрать `flutter_webrtc` из `pubspec.yaml` и отключить UI звонков (звонки только Android/Web). Это отдельный объём работ; пишите, если нужно автоматизировать скриптом.

## Ссылки

- [react-native-webrtc #881](https://github.com/react-native-webrtc/react-native-webrtc/issues/881) — ложные срабатывания ITMS-90338.
- [LiveKit client-sdk-swift #998](https://github.com/livekit/client-sdk-swift/issues/998) — `mainScreen` / iOS 26.
- [webrtc-sdk/Specs](https://github.com/webrtc-sdk/Specs/releases)
