# Ошибки в GeneratedPluginRegistrant.java (Cannot resolve symbol)

Если в Android Studio или в Cursor/VS Code подсвечиваются ошибки в файле  
`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`  
(androidx, Log, FlutterEngine, embedding и т.д.) — это **не ошибки компиляции**, а проблема classpath в IDE.

## Причина

IDE не подхватывает классы из Android SDK и Flutter embedding. Обычно так бывает, когда:
- открыта только папка **android**, а не корень проекта;
- не выполнялась синхронизация Gradle после открытия проекта.

## Что сделать

### 1. Открывать корень проекта

- **Android Studio:** File → Open → выберите папку **`my_chat_app`** (корень репозитория), не `android`.
- **Cursor / VS Code:** в проводнике должна быть открыта папка **`my_chat_app`**.

### 2. Синхронизация Gradle

- **Android Studio:** File → Sync Project with Gradle Files (или иконка слона с синей стрелкой).
- **Терминал (из корня проекта):**
  ```bash
  cd android && ./gradlew tasks --no-daemon
  ```
  Дождитесь окончания — после этого IDE часто подхватывает зависимости.

### 3. Проверка сборки

Из корня проекта:

```bash
flutter pub get
flutter build apk
```

или только Android:

```bash
cd android && ./gradlew assembleDebug
```

Если сборка проходит успешно, приложение собирается корректно; красные подсветки в `GeneratedPluginRegistrant.java` — только косметическая проблема IDE.

### 4. Android SDK

Убедитесь, что в `android/local.properties` указан путь к SDK, например:

```properties
sdk.dir=/Users/YOUR_USER/Library/Android/sdk
flutter.sdk=/path/to/flutter
```

В Android Studio: File → Project Structure → SDK Location — путь к Android SDK должен быть задан.

---

**Итог:** открывайте корень `my_chat_app`, делайте Sync Project with Gradle Files (или `./gradlew tasks`), при необходимости выполните `flutter build apk`. После этого символы в `GeneratedPluginRegistrant.java` должны разрешаться.
