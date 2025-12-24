#!/bin/bash
set -e

echo "📦 Установка Flutter..."

# Устанавливаем Flutter через официальный скрипт
cd /tmp
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:/tmp/flutter/bin"

# Настраиваем Flutter
flutter config --no-analytics
flutter precache --web

# Переходим в директорию проекта
cd "$VERCEL_SOURCE_DIR" || cd "$(pwd)"

echo "📥 Установка зависимостей..."
flutter pub get

echo "🔨 Сборка веб-версии..."
flutter build web --release

echo "✅ Сборка завершена!"

