#!/bin/bash
set -e

echo "📦 Установка Flutter..."

# Определяем директорию проекта
PROJECT_DIR="${VERCEL_SOURCE_DIR:-$(pwd)}"
echo "Project directory: $PROJECT_DIR"

# Устанавливаем Flutter
cd /tmp
if [ ! -d "flutter" ]; then
  echo "Клонируем Flutter..."
  FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.9}"
  git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1
fi

export PATH="$PATH:/tmp/flutter/bin"
export FLUTTER_ROOT="/tmp/flutter"

# Проверяем установку
echo "Проверяем Flutter..."
flutter --version || {
  echo "Ошибка: Flutter не установлен"
  exit 1
}

# Настраиваем Flutter
echo "Настройка Flutter..."
flutter config --no-analytics || true
flutter doctor || true

# Переходим в директорию проекта
cd "$PROJECT_DIR"
echo "Текущая директория: $(pwd)"

# Устанавливаем зависимости
echo "📥 Установка зависимостей..."
flutter pub get || {
  echo "Ошибка при установке зависимостей"
  exit 1
}

# Собираем веб-версию
echo "🔨 Сборка веб-версии..."
flutter build web --release --no-wasm-dry-run || {
  echo "Ошибка при сборке"
  exit 1
}

echo "✅ Сборка завершена!"
ls -la build/web/ || echo "Папка build/web не найдена"

