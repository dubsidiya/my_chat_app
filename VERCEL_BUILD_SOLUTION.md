# Решение проблемы сборки Flutter на Vercel

## Проблема
```
Build Failed
Command "bash build.sh" exited with 1
```

## Решение 1: Улучшенный скрипт сборки (текущий)

Я создал улучшенный скрипт `vercel-build.sh` с:
- ✅ Лучшей обработкой ошибок
- ✅ Проверкой установки Flutter
- ✅ Детальным логированием
- ✅ Проверкой результата сборки

## Решение 2: Сборка через GitHub Actions (РЕКОМЕНДУЕТСЯ)

Если скрипт все еще не работает, используйте GitHub Actions:

1. Создайте `.github/workflows/deploy.yml`:
```yaml
name: Build and Deploy

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          
      - run: flutter pub get
      - run: flutter build web --release
      
      - uses: amondnet/vercel-action@v25
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          vercel-args: '--prod'
```

2. Добавьте секреты в GitHub:
   - `VERCEL_TOKEN` - из Vercel Settings → Tokens
   - `VERCEL_ORG_ID` - из Vercel Settings → General
   - `VERCEL_PROJECT_ID` - из настроек проекта

## Решение 3: Локальная сборка + коммит build/web

Самый простой вариант:

```bash
# Соберите локально
flutter build web --release

# Закоммитьте build/web
git add build/web
git commit -m "Add pre-built web version"
git push
```

Затем в Vercel:
- **Build Command**: `echo "Using pre-built version"`
- **Output Directory**: `build/web`

## Решение 4: Использовать готовый Docker образ

Создайте `Dockerfile`:
```dockerfile
FROM cirrusci/flutter:stable AS build
WORKDIR /app
COPY . .
RUN flutter pub get
RUN flutter build web --release
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
```

Но это требует настройки Vercel для Docker.

## Рекомендация

**Используйте Решение 2 (GitHub Actions)** - это самый надежный способ:
- ✅ Flutter установлен автоматически
- ✅ Полный контроль над процессом сборки
- ✅ Автоматический деплой после сборки
- ✅ Работает стабильно

## Проверка текущего решения

После коммита `vercel-build.sh`:
1. Проверьте логи в Vercel Dashboard
2. Если видите "Flutter установлен" - скрипт работает
3. Если ошибка - используйте GitHub Actions

