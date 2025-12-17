# 🔔 Руководство по веб-уведомлениям

## ⚠️ Важно понимать

**Веб-уведомления работают, НО с ограничениями:**
- ✅ Работают в современных браузерах (Chrome, Firefox, Edge, Safari 16+)
- ✅ Работают даже когда вкладка закрыта
- ⚠️ Требуют разрешения пользователя
- ⚠️ Работают только через HTTPS (или localhost)
- ⚠️ Требуют Service Worker
- ⚠️ Не работают в Safari на iOS (ограничение Apple)

---

## 🎯 Как работают веб-уведомления

### Архитектура

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Браузер   │────────►│ Push Service │────────►│   Сервер    │
│  (Flutter)  │         │  (Firebase/  │         │  (Node.js)  │
│             │         │   VAPID)     │         │             │
└─────────────┘         └──────────────┘         └─────────────┘
      │                                              │
      │                                              │
      └──────────────► Service Worker ◄─────────────┘
                      (обработка уведомлений)
```

### Процесс работы:

1. **Пользователь открывает сайт** → Запрашивается разрешение на уведомления
2. **Пользователь разрешает** → Браузер генерирует Push Subscription
3. **Subscription отправляется на сервер** → Сохраняется в БД
4. **Приходит новое сообщение** → Сервер отправляет push через Push Service
5. **Push Service доставляет уведомление** → Service Worker получает его
6. **Service Worker показывает уведомление** → Даже если вкладка закрыта

---

## 🔧 Варианты реализации

### Вариант 1: Firebase Cloud Messaging (FCM) - Рекомендуется ✅

**Плюсы:**
- ✅ Готовое решение от Google
- ✅ Работает на всех платформах (веб, Android, iOS)
- ✅ Бесплатно до 10,000 устройств
- ✅ Хорошая документация
- ✅ Надежная инфраструктура

**Минусы:**
- ⚠️ Зависимость от Google
- ⚠️ Нужна настройка Firebase проекта

**Сложность:** ⭐⭐⭐ (3/5)

---

### Вариант 2: Свой сервер с VAPID

**Плюсы:**
- ✅ Полный контроль
- ✅ Нет зависимости от внешних сервисов
- ✅ Бесплатно

**Минусы:**
- ⚠️ Нужно реализовывать самому
- ⚠️ Сложнее настройка
- ⚠️ Нужно поддерживать

**Сложность:** ⭐⭐⭐⭐ (4/5)

---

### Вариант 3: Альтернативы (если push не подходит)

#### 3.1. In-App уведомления (когда вкладка открыта)
- Показывать уведомления внутри приложения
- Использовать `flutter_local_notifications` (но это для мобильных)
- Для веба: кастомные виджеты уведомлений

#### 3.2. Email уведомления
- Отправлять email при новых сообщениях
- Проще реализовать
- Работает всегда

#### 3.3. Browser Badge API
- Показывать счетчик непрочитанных на иконке вкладки
- Работает без разрешений
- Ограниченная функциональность

---

## 🚀 Реализация через Firebase FCM (Рекомендуется)

### Шаг 1: Настройка Firebase

1. **Создать проект в Firebase Console**
   - https://console.firebase.google.com
   - Добавить веб-приложение
   - Получить `firebaseConfig`

2. **Включить Cloud Messaging**
   - В настройках проекта → Cloud Messaging
   - Сгенерировать ключ сервера

### Шаг 2: Установка зависимостей

```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^2.24.2
  firebase_messaging: ^14.7.9
  flutter_local_notifications: ^16.3.0  # Для мобильных
```

### Шаг 3: Инициализация Firebase

```dart
// lib/main.dart
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; // Сгенерируется автоматически

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}
```

### Шаг 4: Настройка Service Worker для веба

Создать файл `web/firebase-messaging-sw.js`:

```javascript
// web/firebase-messaging-sw.js
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js');

// Инициализация Firebase
firebase.initializeApp({
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_AUTH_DOMAIN",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_STORAGE_BUCKET",
  messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
  appId: "YOUR_APP_ID"
});

const messaging = firebase.messaging();

// Обработка фоновых сообщений
messaging.onBackgroundMessage((payload) => {
  console.log('Background message received:', payload);
  
  const notificationTitle = payload.notification?.title || 'Новое сообщение';
  const notificationOptions = {
    body: payload.notification?.body || 'У вас новое сообщение',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: payload.data?.chatId,
    data: payload.data,
  };

  return self.registration.showNotification(
    notificationTitle,
    notificationOptions
  );
});

// Обработка клика по уведомлению
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  
  const chatId = event.notification.data?.chatId;
  if (chatId) {
    event.waitUntil(
      clients.openWindow(`/#/chat/${chatId}`)
    );
  }
});
```

### Шаг 5: Код в Flutter

```dart
// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Запрос разрешения
  static Future<bool> requestPermission() async {
    if (kIsWeb) {
      // Для веба используем Web Notification API
      final permission = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      return permission.authorizationStatus == AuthorizationStatus.authorized;
    } else {
      // Для мобильных
      final settings = await _messaging.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized;
    }
  }

  // Получение токена для отправки на сервер
  static Future<String?> getToken() async {
    try {
      final token = await _messaging.getToken();
      print('FCM Token: $token');
      return token;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  // Инициализация
  static Future<void> initialize() async {
    // Обработка сообщений когда приложение открыто
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Message received: ${message.notification?.title}');
      // Показать уведомление в приложении
      _showInAppNotification(message);
    });

    // Обработка сообщений когда приложение в фоне
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Message opened app: ${message.data}');
      // Навигация к чату
      _handleNotificationTap(message);
    });

    // Проверка, было ли приложение открыто через уведомление
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  static void _showInAppNotification(RemoteMessage message) {
    // Показать кастомное уведомление в UI
    // Можно использовать SnackBar или кастомный виджет
  }

  static void _handleNotificationTap(RemoteMessage message) {
    final chatId = message.data['chatId'];
    if (chatId != null) {
      // Навигация к чату
      // Navigator.pushNamed(context, '/chat/$chatId');
    }
  }
}
```

### Шаг 6: Отправка уведомлений с сервера

```javascript
// my_serve_chat_test/controllers/messagesController.js
import admin from 'firebase-admin';

// Инициализация Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert({
    projectId: process.env.FIREBASE_PROJECT_ID,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
  }),
});

// При отправке сообщения
export const sendMessage = async (req, res) => {
  // ... существующий код отправки сообщения ...

  // Получаем FCM токены всех участников чата (кроме отправителя)
  const members = await pool.query(
    'SELECT user_id, fcm_token FROM chat_users WHERE chat_id = $1 AND user_id != $2',
    [chatId, userId]
  );

  // Отправляем уведомления
  const tokens = members.rows
    .map(row => row.fcm_token)
    .filter(token => token != null);

  if (tokens.length > 0) {
    const message = {
      notification: {
        title: chatName,
        body: content,
      },
      data: {
        chatId: chatId.toString(),
        userId: userId.toString(),
        type: 'new_message',
      },
      tokens: tokens,
    };

    try {
      const response = await admin.messaging().sendMulticast(message);
      console.log(`Sent ${response.successCount} notifications`);
    } catch (error) {
      console.error('Error sending notifications:', error);
    }
  }

  // ... остальной код ...
};
```

---

## 🔄 Альтернатива: Простые веб-уведомления (без Firebase)

Если не хотите использовать Firebase, можно использовать Web Notification API напрямую:

```dart
// lib/services/web_notification_service.dart
import 'dart:html' as html;

class WebNotificationService {
  // Запрос разрешения
  static Future<bool> requestPermission() async {
    if (html.window.Notification == null) {
      print('Notifications not supported');
      return false;
    }

    final permission = await html.window.Notification.requestPermission();
    return permission == 'granted';
  }

  // Показать уведомление
  static void showNotification({
    required String title,
    required String body,
    String? icon,
    String? tag,
    Map<String, dynamic>? data,
    Function()? onClick,
  }) {
    if (html.window.Notification == null) return;

    final notification = html.window.Notification(
      title,
      NotificationOptions(
        body: body,
        icon: icon ?? '/icons/Icon-192.png',
        tag: tag,
        data: data,
      ),
    );

    if (onClick != null) {
      notification.onClick.listen((_) => onClick());
    }
  }
}
```

**Но это работает только когда вкладка открыта!** Для фоновых уведомлений нужен Push Service (Firebase или VAPID).

---

## 📊 Сравнение вариантов

| Критерий | Firebase FCM | VAPID | Web Notifications API |
|---------|---------------|-------|---------------------|
| Работает в фоне | ✅ | ✅ | ❌ |
| Работает когда вкладка закрыта | ✅ | ✅ | ❌ |
| Сложность настройки | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Зависимость от внешних сервисов | ✅ | ❌ | ❌ |
| Кроссплатформенность | ✅ | ⚠️ | ❌ |
| Бесплатно | ✅ (до лимита) | ✅ | ✅ |

---

## ⚠️ Ограничения веб-уведомлений

1. **Safari на iOS**
   - Не поддерживает Web Push API
   - Работает только через нативные приложения

2. **Требуется разрешение пользователя**
   - Многие пользователи блокируют уведомления
   - Нужно объяснять зачем они нужны

3. **HTTPS обязателен**
   - Не работает на HTTP (кроме localhost)
   - Vercel уже использует HTTPS ✅

4. **Service Worker обязателен**
   - У вас уже есть flutter_service_worker.js ✅
   - Нужно добавить обработку push-событий

---

## 🎯 Рекомендация

**Для вашего проекта рекомендую:**

1. **Начать с простых in-app уведомлений** (когда вкладка открыта)
   - Показывать уведомления внутри приложения
   - Использовать WebSocket для real-time
   - Проще реализовать

2. **Потом добавить Firebase FCM** (для фоновых уведомлений)
   - Когда нужно уведомлять когда вкладка закрыта
   - Более сложная настройка, но надежнее

3. **Альтернатива: Browser Badge API**
   - Показывать счетчик непрочитанных на иконке
   - Работает без разрешений
   - Простая реализация

---

## 💡 Что выбрать?

**Если нужно уведомлять когда вкладка закрыта:**
→ Используйте **Firebase FCM**

**Если достаточно уведомлений когда вкладка открыта:**
→ Используйте **Web Notifications API** или **in-app уведомления**

**Если нужен только счетчик:**
→ Используйте **Badge API**

---

## 🚀 Быстрый старт (In-App уведомления)

Самый простой вариант - показывать уведомления внутри приложения когда вкладка открыта:

```dart
// Показывать уведомление в UI когда приходит сообщение через WebSocket
// Уже есть WebSocket подключение - можно использовать его!
```

Это работает всегда, не требует разрешений, и легко реализуется!

---

*Какой вариант вам больше подходит?*

