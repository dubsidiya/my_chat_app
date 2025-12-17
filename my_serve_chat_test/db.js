import pkg from 'pg';
const { Pool } = pkg;

import dotenv from 'dotenv';
dotenv.config();

// Проверка DATABASE_URL
if (!process.env.DATABASE_URL) {
  console.error('❌ ОШИБКА: DATABASE_URL не установлен!');
  console.error('Установите DATABASE_URL в переменных окружения на Render.com');
  // Не падаем сразу, чтобы можно было увидеть ошибку в логах
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('localhost') ? false : {
    rejectUnauthorized: false, // ОБЯЗАТЕЛЕН для Supabase/Neon/Render
  },
});

// Проверка подключения к БД
pool.on('error', (err) => {
  console.error('❌ Неожиданная ошибка подключения к БД:', err);
});

// Тестовое подключение при запуске (асинхронно, не блокируем запуск)
setTimeout(() => {
  pool.query('SELECT NOW()')
    .then(() => {
      console.log('✅ Подключение к базе данных успешно');
    })
    .catch((err) => {
      console.error('❌ Ошибка подключения к базе данных:', err.message);
      console.error('Проверьте DATABASE_URL в переменных окружения');
    });
}, 1000);

export default pool;
