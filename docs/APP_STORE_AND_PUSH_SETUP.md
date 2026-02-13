# Публикация в App Store и Push-уведомления

Пошаговая настройка: размещение приложения в App Store и получение push-уведомлений о новых сообщениях.

---

## Часть 1: App Store Connect и первая загрузка

### 1.1 Создать приложение в App Store Connect

1. Войди в [App Store Connect](https://appstoreconnect.apple.com) под своим Apple Developer аккаунтом.
2. **Мои приложения** → **+** → **Новое приложение**.
3. Заполни:
   - **Платформы:** iOS.
   - **Название:** например, «My Chat App».
   - **Основной язык:** Русский (или нужный).
   - **Bundle ID:** выбери из списка (должен совпадать с тем, что в Xcode). Сейчас в проекте указан `com.estellia.reol` — если хочешь свой, сначала поменяй его в Xcode (Runner → Signing & Capabilities) и создай соответствующий App ID в [developer.apple.com/account](https://developer.apple.com/account) → Identifiers.
   - **SKU:** уникальный код (например, `mychatapp001`).
   - **Доступ к пользователям:** полный (или по необходимости).
4. Создай приложение.

### 1.2 App ID и Push Notifications в Apple Developer

1. [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Найди свой App ID (или создай новый с тем же Bundle ID, что и в приложении).
3. Открой App ID → включи галочку **Push Notifications** → **Save**.
4. Для отправки push с сервера понадобится **APNs ключ** или сертификат:
   - **Keys** → **+** → имя, например «APNs My Chat App», включи **Apple Push Notifications service (APNs)** → **Continue** → **Register**.
   - Скачай `.p8` файл **один раз** (повторно скачать нельзя). Запомни **Key ID** и **Team ID** / **Bundle ID** — они понадобятся для Firebase или для прямой отправки через APNs.

### 1.3 Сборка и загрузка в App Store Connect

1. В Xcode открой `ios/Runner.xcworkspace`.
2. Выбери **Runner** → **Signing & Capabilities**: укажи свою **Team**, проверь **Bundle Identifier**.
3. Подключи реальное устройство или выбери **Any iOS Device (arm64)** для архива.
4. **Product** → **Archive**. После сборки откроется Organizer.
5. **Distribute App** → **App Store Connect** → **Upload** → выбери опции (например, загрузка символов) → **Upload**.
6. В App Store Connect через несколько минут появится сборка в разделе **Тестирование** или в карточке приложения → **Сборка**. Выбери её для версии (например, 1.0.0).

### 1.4 Метаданные для первой версии

В карточке приложения в App Store Connect заполни по пунктам. Ниже — готовый текст, который можно вставить или отредактировать.

**Название приложения (до 30 символов):**  
Reol  

**Подзаголовок (до 30 символов):**  
Чаты, сообщения, отчёты  

**Описание (до 4000 символов):**
```
Reol — удобный мессенджер для общения и совместной работы. Создавайте чаты, обменивайтесь текстом, голосовыми сообщениями и фото. Есть отчёты и учёт — удобно для преподавателей и команд.

• Чаты один на один и групповые
• Текстовые и голосовые сообщения
• Отправка фото и файлов
• Отчёты и учёт занятий (для преподавателей)
• Push-уведомления о новых сообщениях
• Тёмная тема
```

**Ключевые слова (до 100 символов, через запятую без пробелов):**  
чат,мессенджер,сообщения,голосовые,фото,отчёты,обучение,группа  

**Категория (основная):**  
Социальные сети — **обязательно выбери в интерфейсе** (если проверка пишет «Необходимо указать основную категорию», зайди в карточку приложения → раздел с метаданными версии или «Информация о приложении» → поле **Основная категория** → выбери, например, **Социальные сети**).  
**Категория (доп., по желанию):**  
Образование или Бизнес  

**Снимки экрана:**  
Обязательно загрузи минимум 3 скриншота для iPhone 6.7" (например, экран чатов, экран переписки, экран отчётов). **Если приложение доступно на iPad** — нужны отдельно скриншоты для iPad Pro 13": размер **2064×2752** (портрет) или **2752×2064** (ландшафт). Готовые файлы для iPad можно сгенерировать: `python3 scripts/ipad_screenshots_from_existing.py` — появятся в папке `app_store_screenshots` (файлы `*_iPad13_2064x2752.png`). Загрузи хотя бы один такой скриншот в блок «iPad Pro с 13‑дюймовым дисплеем» в App Store Connect.

**Контакт для связи с Apple:**  
vlad.kh4rin@yandex.ru

**URL службы поддержки (обязательно ссылка, не email):**  
См. ниже раздел «Страница поддержки через GitHub Pages».

**URL политики конфиденциальности:**  
Обязательное поле. В проекте есть готовая страница **`docs/privacy.html`** — её нужно выложить в интернет и вставить сюда ссылку. Проще всего: тот же репозиторий GitHub Pages, что и для поддержки (см. раздел ниже). Добавь в него файл **privacy.html** (скопируй содержимое из `docs/privacy.html`), включи GitHub Pages в настройках репозитория. URL будет вида: `https://ТВОЙ_ЛОГИН.github.io/reol-support/privacy.html` — его и укажи в App Store Connect в разделе «Конфиденциальность приложения» / «URL политики конфиденциальности».

**Ценовая категория:**  
Бесплатно (или выбери платную, если приложение платное).

После выбора сборки и прохождения проверки отправь приложение на **модерацию**.

**Если появляется «Не удается добавить для проверки»** — проверь три пункта:
| Требование | Что сделать |
|------------|-------------|
| **Снимок для iPad Pro 13"** | В блоке скриншотов выбери «iPad Pro с 13‑дюймовым дисплеем» и загрузи минимум один файл **2064×2752** или **2752×2064** px. Готовые: `app_store_screenshots/*_iPad13_2064x2752.png` (созданы скриптом `scripts/ipad_screenshots_from_existing.py`). |
| **URL политики конфиденциальности** | Выложи `docs/privacy.html` на GitHub Pages (или другой хостинг), вставь полученный URL в раздел «Конфиденциальность приложения» в App Store Connect. |
| **Основная категория** | В карточке приложения в метаданных версии укажи **Основная категория** → например, **Социальные сети**. |

**ITMS-91061 (Missing privacy manifest):** если Apple пишет, что в приложении используется SDK без privacy manifest (например, `connectivity_plus`), нужно убрать такой SDK. В этом проекте проверка сети сделана через обычный HTTP-запрос к API (`MessagesService._isOnline()`), пакет `connectivity_plus` удалён. После правок выполни `flutter clean && flutter pub get`, затем собери новый билд и загрузи его в App Store Connect.

### 1.5 Иконка приложения

Иконка, которую видит пользователь на домашнем экране и в App Store, задаётся в проекте и попадает в сборку автоматически.

**Как поменять иконку:**

1. Подготовь одно изображение **1024×1024 px**, формат PNG. Для iOS в иконке не должно быть прозрачности (сплошной фон).
2. Сохрани файл как **`assets/app_icon.png`** в корне проекта (папку `assets` создай, если её нет).
3. В терминале выполни:
   ```bash
   flutter pub get
   dart run flutter_launcher_icons
   ```
4. Будут обновлены все размеры иконок для iOS (`ios/Runner/Assets.xcassets/AppIcon.appiconset/`) и Android (`android/app/src/main/res/mipmap-*`). Собери приложение заново и загрузи новую сборку в App Store Connect — в ней уже будет новая иконка.

Настройка генерации иконок прописана в `pubspec.yaml` (раздел `flutter_launcher_icons`). При необходимости можно указать другой путь к картинке или отдельные иконки для Android и iOS.

---

### Страница поддержки через GitHub Pages

Чтобы в App Store Connect указать **URL службы поддержки**, нужна обычная веб-страница с контактом. Проще всего сделать её через GitHub Pages (бесплатно, без своего сервера).

#### Шаг 1: Репозиторий для страницы

1. Зайди на [github.com](https://github.com) и войди в аккаунт.
2. Нажми **+** → **New repository**.
3. Имя репозитория, например: **reol-support** (или любое, например **app-support**).
4. Поставь **Public**, галочку **Add a README file** можно снять.
5. Нажми **Create repository**.

#### Шаг 2: Файл страницы

1. В созданном репозитории нажми **Add file** → **Create new file**.
2. В поле имени файла введи: **index.html**.
3. Вставь такой код (уже с твоим email):

```html
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Поддержка — Reol</title>
  <style>
    body { font-family: -apple-system, sans-serif; max-width: 600px; margin: 40px auto; padding: 0 20px; line-height: 1.6; }
    h1 { font-size: 1.5rem; }
    a { color: #007AFF; }
  </style>
</head>
<body>
  <h1>Поддержка приложения Reol</h1>
  <p>По вопросам работы приложения пишите на email:</p>
  <p><a href="mailto:vlad.kh4rin@yandex.ru">vlad.kh4rin@yandex.ru</a></p>
</body>
</html>
```

4. Внизу страницы нажми **Commit new file** (можно оставить сообщение по умолчанию).

#### Шаг 3: Включить GitHub Pages

1. В репозитории открой **Settings** (вкладка сверху).
2. Слева выбери **Pages** (в блоке "Code and automation").
3. В разделе **Build and deployment**:
   - **Source** — **Deploy from a branch**.
   - **Branch** — выбери **main** (или **master**), папка **/ (root)**.
4. Нажми **Save**. Через 1–2 минуты появится надпись вида: *Your site is live at https://ТВОЙ_ЛОГИН.github.io/reol-support/*.

#### Шаг 4: URL в App Store Connect

Скопируй адрес сайта (например, `https://ТВОЙ_ЛОГИН.github.io/reol-support/`) и вставь в поле **«URL-адрес службы поддержки»** в карточке приложения в App Store Connect. Ошибка «URL недействителен» пропадёт, т.к. это настоящая ссылка.

**Если репозиторий уже есть (например, my_chat_app):** в этом проекте в папке **docs** уже лежит готовая страница **support.html**. В репозитории на GitHub: **Settings** → **Pages** → Source: ветка **main**, папка **/docs** → Save. Через пару минут страница будет доступна по адресу:  
`https://ТВОЙ_ЛОГИН.github.io/my_chat_app/support.html`  
Этот URL и укажи в App Store Connect как URL службы поддержки.

---

## Часть 2: Push-уведомления (Firebase FCM + iOS)

На iOS push идут через APNs. Удобный вариант — **Firebase Cloud Messaging (FCM)**: он сам работает с APNs, плюс даёт единый способ отправки с бэкенда для iOS и при желании для веба/Android.

### 2.1 Firebase Console

1. [console.firebase.google.com](https://console.firebase.google.com) → создай проект (или выбери существующий).
2. **Добавить приложение** → **iOS** → укажи **Bundle ID** (такой же, как в Xcode и App Store Connect).
3. Скачай **GoogleService-Info.plist** и положи в `ios/Runner/` в проекте (в Xcode он должен быть в группе Runner).
4. В проекте Firebase: **Project settings** → **Cloud Messaging**:
   - Вкладка **Apple app configuration**: загрузи **APNs Authentication Key** (тот самый `.p8`), укажи **Key ID**, **Team ID**, **Bundle ID**. Так FCM сможет слать push на iOS.

### 2.2 Flutter (уже добавлено в проект)

- В `pubspec.yaml` подключены: `firebase_core`, `firebase_messaging`, `flutter_local_notifications`.
- Сервис `lib/services/push_notification_service.dart`:
  - запрашивает разрешение на уведомления;
  - получает FCM-токен и отправляет его на бэкенд (`POST /auth/fcm-token`);
  - обрабатывает входящие сообщения и переход в чат при нажатии на уведомление.
- В `main.dart` вызывается `PushNotificationService.init()` после инициализации хранилища.
- После входа токен отправляется на сервер (при открытии главного экрана с залогиненным пользователем).

### 2.3 Бэкенд (Node.js)

- В таблицу `users` добавлено поле `fcm_token` (миграция `add_fcm_token.sql`).
- Эндпоинт **POST /auth/fcm-token** (с JWT): в теле `{ "fcmToken": "..." }` — сохраняет токен для текущего пользователя.
- При создании нового сообщения в чате сервер получает участников чата (кроме отправителя), для каждого берёт `fcm_token` из БД и отправляет push через Firebase Admin SDK (файл `utils/pushNotifications.js`).

Переменные окружения на сервере (для отправки push):

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY` (приватный ключ сервисного аккаунта JSON, символ `\n` можно оставить как `\\n` в .env)

Сервисный аккаунт: Firebase Console → Project settings → **Service accounts** → **Generate new private key**. Эти данные кладутся в `.env` на сервере (Render и т.д.).

### 2.4 iOS: возможности проекта

- В `ios/Runner/Runner.entitlements` включён **Push Notifications** (`aps-environment`). Для сборки в **App Store** замени в файле `development` на `production`.
- В Xcode для таргета Runner в **Signing & Capabilities** должна быть включена возможность **Push Notifications** (если не подтянулась автоматически, добавь вручную).

---

## Краткий чеклист

| Шаг | Где | Действие |
|-----|-----|----------|
| 1 | App Store Connect | Создать приложение, указать Bundle ID |
| 2 | developer.apple.com | Включить Push в App ID, создать APNs ключ (.p8) |
| 3 | Firebase | Создать проект, добавить iOS app, загрузить APNs ключ, скачать GoogleService-Info.plist |
| 4 | Xcode | Подключить GoogleService-Info.plist, проверить Signing и entitlements |
| 5 | Flutter | Запустить приложение, войти — токен уйдёт на бэкенд |
| 6 | Сервер | Задать FIREBASE_* в .env, применить миграцию `add_fcm_token.sql`, перезапустить |
| 7 | App Store Connect | Загрузить сборку (Archive → Upload), заполнить метаданные, отправить на модерацию |

После этого приложение будет публиковаться в App Store, а новые сообщения в чатах — приходить push-уведомлениями на устройство.
