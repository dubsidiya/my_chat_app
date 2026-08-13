#!/bin/bash
set -e

echo "🚀 Начало сборки Flutter приложения на Vercel"
echo "Текущая директория: $(pwd)"
echo "VERCEL_SOURCE_DIR: ${VERCEL_SOURCE_DIR:-не установлена}"

# Переходим в директорию проекта
PROJECT_DIR="${VERCEL_SOURCE_DIR:-$(pwd)}"
cd "$PROJECT_DIR"
echo "Рабочая директория: $(pwd)"

# Устанавливаем Flutter
echo "📦 Установка Flutter SDK..."
FLUTTER_DIR="/tmp/flutter"

# Удаляем старую установку если есть
rm -rf "$FLUTTER_DIR" 2>/dev/null || true

# Pin SDK: `stable` follows the latest release. Flutter 3.47 (2026-08-12)
# fails this app's web compile (dart:html / dart:io vs Wasm dry-run).
# 3.44.9 is the last 3.44 patch — the line Vercel used through July 2026.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.9}"
echo "Flutter SDK: $FLUTTER_VERSION"

git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1 "$FLUTTER_DIR" || {
  echo "❌ Ошибка при клонировании Flutter"
  exit 1
}

# Добавляем Flutter в PATH
export PATH="$PATH:$FLUTTER_DIR/bin"
export FLUTTER_ROOT="$FLUTTER_DIR"

# Проверяем установку
echo "Проверка Flutter..."
if ! command -v flutter &> /dev/null; then
  echo "❌ Flutter не найден в PATH"
  echo "PATH: $PATH"
  exit 1
fi

flutter --version || {
  echo "❌ Ошибка при проверке версии Flutter"
  exit 1
}

# Настраиваем Flutter
echo "Настройка Flutter..."
flutter config --no-analytics || echo "⚠️ Предупреждение: не удалось отключить аналитику"
flutter doctor || echo "⚠️ Предупреждение: flutter doctor показал проблемы"

# Устанавливаем зависимости
echo "📥 Установка зависимостей..."
cd "$PROJECT_DIR"
flutter pub get || {
  echo "❌ Ошибка при установке зависимостей"
  exit 1
}

# Собираем веб-версию (API_BASE_URL из Vercel Environment Variables подставляется в приложение)
echo "🔨 Сборка веб-версии..."
DART_DEFINES=""
if [ -n "$API_BASE_URL" ]; then
  DART_DEFINES="--dart-define=API_BASE_URL=$API_BASE_URL"
  echo "Используется API_BASE_URL: $API_BASE_URL"
fi
# --no-wasm-dry-run: keep dart2js (JS) builds green; this app still imports
# dart:html / dart:io, which dart2wasm rejects.
flutter build web --release --no-wasm-dry-run $DART_DEFINES || {
  echo "❌ Ошибка при сборке"
  exit 1
}

# Проверяем результат
if [ ! -d "build/web" ]; then
  echo "❌ Папка build/web не найдена после сборки"
  exit 1
fi

echo "✅ Сборка завершена успешно!"
echo "📁 Содержимое build/web:"
ls -la build/web/ | head -10

