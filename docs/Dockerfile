# Dockerfile для сборки Flutter веб-приложения
FROM cirrusci/flutter:stable AS build

WORKDIR /app

# Копируем файлы проекта
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Собираем веб-приложение
RUN flutter build web --release

# Используем nginx для раздачи статических файлов
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

